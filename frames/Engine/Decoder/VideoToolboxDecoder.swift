//
//  VideoToolboxDecoder.swift
//  frames
//
//  Zero-copy hardware-accelerated video decompression engine powered by
//  Apple Silicon VideoToolbox ASIC media engines and Unified Memory.
//

import Foundation
import CoreMedia
import VideoToolbox
import CoreVideo

nonisolated public final class VideoToolboxDecoder: @unchecked Sendable {
    
    // MARK: - Types
    
    nonisolated public struct DecodedVideoFrame: @unchecked Sendable {
        public let pixelBuffer: CVPixelBuffer
        public let pts: Double
        public let duration: Double
        
        public init(pixelBuffer: CVPixelBuffer, pts: Double, duration: Double) {
            self.pixelBuffer = pixelBuffer
            self.pts = pts
            self.duration = duration
        }
    }
    
    public typealias FrameHandler = @Sendable (DecodedVideoFrame) -> Void
    
    // MARK: - Properties
    
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    public let track: DemuxedTrack
    public let is10Bit: Bool
    public let isAnnexBStream: Bool
    public private(set) var isHardwareAccelerated: Bool = false
    public private(set) var decoderImplementationName: String = "VideoToolbox"
    
    private let frameLock = NSLock()
    private var sessionGeneration: Int = 0
    private var onFrameDecoded: FrameHandler?
    private var bufferedFrames: [DecodedVideoFrame] = []
    private let maxBufferedFrames = 8
    
    // MARK: - Lifecycle
    
    public init?(track: DemuxedTrack, onFrame: FrameHandler? = nil) {
        guard track.isVideo else { return nil }
        self.track = track
        self.onFrameDecoded = onFrame
        
        // Determine bit depth from track metadata (10-bit HDR vs 8-bit SDR)
        self.is10Bit = track.bitsPerChannel > 8
        
        if let priv = track.codecPrivate,
           (NALParser.parseAVCDecoderConfigurationRecord(priv) != nil ||
            NALParser.parseHEVCDecoderConfigurationRecord(priv) != nil) {
            self.isAnnexBStream = false
        } else {
            self.isAnnexBStream = true
        }
        
        // Build format description from track codec and private data if available upfront
        if let desc = Self.createFormatDescription(for: track) {
            self.formatDescription = desc
            _ = setupDecompressionSession(with: desc)
        }
    }
    
    deinit {
        invalidate()
    }
    
    public func setFrameHandler(_ handler: @escaping FrameHandler) {
        frameLock.lock()
        self.onFrameDecoded = handler
        frameLock.unlock()
    }
    
    public func invalidate() {
        frameLock.lock()
        sessionGeneration &+= 1
        let s = session
        session = nil
        isHardwareAccelerated = false
        decoderImplementationName = "None"
        bufferedFrames.removeAll()
        frameLock.unlock()
        
        if let s = s {
            VTDecompressionSessionWaitForAsynchronousFrames(s)
            VTDecompressionSessionInvalidate(s)
        }
    }
    
    public func flush() {
        frameLock.lock()
        defer { frameLock.unlock() }
        sessionGeneration &+= 1
        bufferedFrames.removeAll()
    }
    
    public func waitForFrames() {
        frameLock.lock()
        let s = session
        frameLock.unlock()
        if let s = s {
            VTDecompressionSessionWaitForAsynchronousFrames(s)
        }
    }
    
    // MARK: - Format Description Creation
    
    private static func createFormatDescription(for track: DemuxedTrack) -> CMVideoFormatDescription? {
        let width = Int32(track.pixelWidth > 0 ? track.pixelWidth : 1920)
        let height = Int32(track.pixelHeight > 0 ? track.pixelHeight : 1080)
        
        if track.isH264 {
            if let priv = track.codecPrivate,
               let parsed = NALParser.parseAVCDecoderConfigurationRecord(priv) {
                return NALParser.createH264FormatDescription(sps: parsed.sps, pps: parsed.pps)
            } else if let priv = track.codecPrivate {
                let nals = NALParser.extractAnnexBNALUnits(from: priv)
                let sps = nals.filter { ($0.first ?? 0) & 0x1F == 7 }
                let pps = nals.filter { ($0.first ?? 0) & 0x1F == 8 }
                return NALParser.createH264FormatDescription(sps: sps, pps: pps)
            }
            return nil
        } else if track.isHEVC {
            if let priv = track.codecPrivate,
               let parsed = NALParser.parseHEVCDecoderConfigurationRecord(priv) {
                return NALParser.createHEVCFormatDescription(vps: parsed.vps, sps: parsed.sps, pps: parsed.pps)
            } else if let priv = track.codecPrivate {
                let nals = NALParser.extractAnnexBNALUnits(from: priv)
                let vps = nals.filter { (($0.first ?? 0) >> 1) & 0x3F == 32 }
                let sps = nals.filter { (($0.first ?? 0) >> 1) & 0x3F == 33 }
                let pps = nals.filter { (($0.first ?? 0) >> 1) & 0x3F == 34 }
                return NALParser.createHEVCFormatDescription(vps: vps, sps: sps, pps: pps)
            }
            return nil
        } else if track.isVP9 {
            var desc: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: kCMVideoCodecType_VP9,
                width: width,
                height: height,
                extensions: nil,
                formatDescriptionOut: &desc
            )
            return status == noErr ? desc : nil
        } else if track.isAV1 {
            var desc: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: kCMVideoCodecType_AV1,
                width: width,
                height: height,
                extensions: nil,
                formatDescriptionOut: &desc
            )
            return status == noErr ? desc : nil
        } else if track.isProRes {
            var desc: CMVideoFormatDescription?
            let codecType: CMVideoCodecType
            if track.codecID.contains("4444") {
                codecType = kCMVideoCodecType_AppleProRes4444
            } else if track.codecID.contains("HQ") {
                codecType = kCMVideoCodecType_AppleProRes422HQ
            } else if track.codecID.contains("LT") {
                codecType = kCMVideoCodecType_AppleProRes422LT
            } else if track.codecID.contains("PROXY") {
                codecType = kCMVideoCodecType_AppleProRes422Proxy
            } else {
                codecType = kCMVideoCodecType_AppleProRes422
            }
            let status = CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: codecType,
                width: width,
                height: height,
                extensions: nil,
                formatDescriptionOut: &desc
            )
            return status == noErr ? desc : nil
        }
        
        return nil
    }
    
    // MARK: - Session Setup
    
    private func setupDecompressionSession(with formatDesc: CMVideoFormatDescription) -> Bool {
        let pixelFormat: OSType = is10Bit ?
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange :
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            
        let destinationPixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferOpenGLCompatibilityKey: false
        ]
        
        var decoderSpecification: [CFString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ]
        let hwPref = UserDefaults.standard.object(forKey: SettingsManager.hardwareAccelerationKey) as? Bool ?? true
        if hwPref {
            decoderSpecification[kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder] = true
        }

        var status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: decoderSpecification as CFDictionary,
            imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary,
            decompressionSessionOut: &session
        )
        
        // Fallback to enable-only if require returns an error
        if status != noErr {
            let fallbackSpec: [CFString: Any] = [
                kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
            ]
            status = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: formatDesc,
                decoderSpecification: fallbackSpec as CFDictionary,
                imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary,
                decompressionSessionOut: &session
            )
        }

        guard status == noErr, let session = session else {
            self.isHardwareAccelerated = false
            self.decoderImplementationName = "VideoToolbox (Failed)"
            return false
        }
        
        // Enable low latency real-time playback
        VTSessionSetProperty(
            session,
            key: kVTDecompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )
        // Maximize Apple Silicon ASIC power and thermal efficiency
        VTSessionSetProperty(
            session,
            key: kVTDecompressionPropertyKey_MaximizePowerEfficiency,
            value: kCFBooleanTrue
        )
        
        // Runtime verification of hardware acceleration
        var isHW: CFTypeRef?
        let propStatus = VTSessionCopyProperty(
            session,
            key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
            allocator: kCFAllocatorDefault,
            valueOut: &isHW
        )
        if propStatus == noErr, let isHW = isHW {
            if CFGetTypeID(isHW) == CFBooleanGetTypeID() {
                self.isHardwareAccelerated = CFBooleanGetValue((isHW as! CFBoolean))
            } else if let b = isHW as? Bool {
                self.isHardwareAccelerated = b
            } else {
                self.isHardwareAccelerated = false
            }
        } else {
            self.isHardwareAccelerated = false
        }
        self.decoderImplementationName = self.isHardwareAccelerated ? "Apple Silicon ASIC (VideoToolbox)" : "VideoToolbox (Software)"
        
        return true
    }
    
    // MARK: - Zero-Copy Block Buffer Creation
    
    /// Creates an optimized, zero-copy `CMBlockBuffer` backed directly by packet memory.
    /// Avoids redundant heap allocations and payload memory copying during high-bitrate playback.
    public static func createBlockBuffer(from data: Data) -> CMBlockBuffer? {
        guard !data.isEmpty else { return nil }
        
        let cfData = data as CFData
        guard let bytePtr = CFDataGetBytePtr(cfData) else { return nil }
        let unmanaged = Unmanaged.passRetained(cfData)
        
        var customBlockSource = CMBlockBufferCustomBlockSource(
            version: UInt32(kCMBlockBufferCustomBlockSourceVersion),
            AllocateBlock: nil,
            FreeBlock: { refCon, _, _ in
                if let refCon = refCon {
                    Unmanaged<CFData>.fromOpaque(refCon).release()
                }
            },
            refCon: unmanaged.toOpaque()
        )
        
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: UnsafeMutableRawPointer(mutating: bytePtr),
            blockLength: data.count,
            blockAllocator: nil,
            customBlockSource: &customBlockSource,
            offsetToData: 0,
            dataLength: data.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr, let bb = blockBuffer else {
            unmanaged.release()
            return nil
        }
        
        return bb
    }
    
    /// Dynamically resolved video dimensions from the active format description.
    public var videoDimensions: (width: Int, height: Int)? {
        frameLock.lock()
        defer { frameLock.unlock() }
        guard let desc = formatDescription else { return nil }
        let dims = CMVideoFormatDescriptionGetDimensions(desc)
        return (Int(dims.width), Int(dims.height))
    }
    
    // MARK: - Frame Decompression
    
    /// Feeds an elementary demuxed video packet into the VideoToolbox hardware decoder.
    public func decode(packet: DemuxedPacket, doNotOutput: Bool = false) -> Bool {
        return autoreleasepool {
            // Dynamic Parameter Set Bootstrap if formatDescription was not in container headers
            frameLock.lock()
            let needsBootstrap = (formatDescription == nil || session == nil)
            frameLock.unlock()
            
            if needsBootstrap {
                if track.isH264 {
                    let nals = NALParser.extractAnnexBNALUnits(from: packet.data)
                    let sps = nals.filter { ($0.first ?? 0) & 0x1F == 7 }
                    let pps = nals.filter { ($0.first ?? 0) & 0x1F == 8 }
                    if !sps.isEmpty && !pps.isEmpty, let desc = NALParser.createH264FormatDescription(sps: sps, pps: pps) {
                        frameLock.lock()
                        self.formatDescription = desc
                        _ = setupDecompressionSession(with: desc)
                        frameLock.unlock()
                    }
                } else if track.isHEVC {
                    let nals = NALParser.extractAnnexBNALUnits(from: packet.data)
                    let vps = nals.filter { (($0.first ?? 0) >> 1) & 0x3F == 32 }
                    let sps = nals.filter { (($0.first ?? 0) >> 1) & 0x3F == 33 }
                    let pps = nals.filter { (($0.first ?? 0) >> 1) & 0x3F == 34 }
                    if !sps.isEmpty && !pps.isEmpty, let desc = NALParser.createHEVCFormatDescription(vps: vps, sps: sps, pps: pps) {
                        frameLock.lock()
                        self.formatDescription = desc
                        _ = setupDecompressionSession(with: desc)
                        frameLock.unlock()
                    }
                }
            }
            
            frameLock.lock()
            let currentSession = self.session
            let currentFormatDesc = self.formatDescription
            frameLock.unlock()
            
            guard let session = currentSession, let formatDesc = currentFormatDesc else { return false }
            
            // Video Translation Layer: Convert Annex-B to AVCC/HVCC length-prefixed format for VideoToolbox
            let payload: Data
            if (track.isH264 || track.isHEVC) && NALParser.isAnnexB(packet.data) {
                payload = NALParser.convertAnnexBToAVCC(packet.data)
            } else {
                payload = packet.data
            }
            
            // Wrap packet raw payload in an optimized zero-copy CMBlockBuffer backed directly by CFData
            guard let bb = VideoToolboxDecoder.createBlockBuffer(from: payload) else { return false }
            
            // Construct CMSampleTimingInfo
            let ptsTime = CMTime(seconds: packet.pts, preferredTimescale: 1_000_000)
            let dtsTime = CMTime.invalid
            let durationTime: CMTime
            if let dur = packet.duration, dur > 0 {
                durationTime = CMTime(seconds: dur, preferredTimescale: 1_000_000)
            } else {
                durationTime = CMTime.invalid
            }
                
            var timing = CMSampleTimingInfo(
                duration: durationTime,
                presentationTimeStamp: ptsTime,
                decodeTimeStamp: dtsTime
            )
            
            // Create CMSampleBuffer
            var sampleBuffer: CMSampleBuffer?
            var sampleSize = payload.count
            
            let sampleStatus = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: bb,
                formatDescription: formatDesc,
                sampleCount: 1,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: &sampleSize,
                sampleBufferOut: &sampleBuffer
            )
            
            guard sampleStatus == noErr, let sb = sampleBuffer else { return false }
            
            // Configure keyframe and dependency attachments for VideoToolbox DPB reference management
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) {
                let count = CFArrayGetCount(attachments)
                if count > 0 {
                    let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                    if packet.isKeyframe {
                        CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
                        CFDictionaryRemoveValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
                        CFDictionaryRemoveValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DependsOnOthers).toOpaque())
                    } else {
                        CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
                        CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DependsOnOthers).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
                    }
                }
            }
            
            // Configure decode flags: enable asynchronous decompression.
            // B-frame temporal reordering is handled gracefully by FrameQueue PTS monotonic insertion.
            var decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
            if doNotOutput {
                decodeFlags.insert(._DoNotOutputFrame)
            }
            
            // Submit to Apple Silicon VideoToolbox ASIC with modern Swift completion handler
            frameLock.lock()
            let currentGen = self.sessionGeneration
            guard let activeSession = self.session else {
                frameLock.unlock()
                return false
            }

            let decodeStatus = VTDecompressionSessionDecodeFrame(
                activeSession,
                sampleBuffer: sb,
                flags: decodeFlags,
                infoFlagsOut: nil
            ) { [weak self] status, infoFlags, imageBuffer, _, presentationTimeStamp, presentationDuration in
                guard let self = self else { return }
                self.frameLock.lock()
                guard self.sessionGeneration == currentGen else {
                    self.frameLock.unlock()
                    return
                }
                self.frameLock.unlock()

                self.handleDecodedFrame(
                    status: status,
                    infoFlags: infoFlags,
                    imageBuffer: imageBuffer,
                    presentationTimeStamp: presentationTimeStamp,
                    presentationDuration: presentationDuration
                )
            }
            frameLock.unlock()

            return decodeStatus == noErr
        }
    }
    
    // MARK: - Frame Delivery Callback
    
    private func handleDecodedFrame(
        status: OSStatus,
        infoFlags: VTDecodeInfoFlags,
        imageBuffer: CVImageBuffer?,
        presentationTimeStamp: CMTime,
        presentationDuration: CMTime
    ) {
        autoreleasepool {
            guard status == noErr, let pixelBuffer = imageBuffer else { return }
            
            let pts = CMTimeGetSeconds(presentationTimeStamp)
            let duration = presentationDuration.isValid ? CMTimeGetSeconds(presentationDuration) : 0.0
            CVBufferSetAttachment(pixelBuffer, "FramesPTS" as CFString, NSNumber(value: pts), .shouldPropagate)
            CVBufferSetAttachment(pixelBuffer, "FramesDuration" as CFString, NSNumber(value: duration), .shouldPropagate)
            let frame = DecodedVideoFrame(pixelBuffer: pixelBuffer, pts: pts, duration: duration)
            
            frameLock.lock()
            if let handler = onFrameDecoded {
                frameLock.unlock()
                handler(frame)
            } else {
                bufferedFrames.append(frame)
                if bufferedFrames.count > maxBufferedFrames {
                    bufferedFrames.removeFirst()
                }
                frameLock.unlock()
            }
        }
    }
}
