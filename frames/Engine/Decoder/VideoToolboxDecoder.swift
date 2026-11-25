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
    private let nalLengthSize: Int?
    public var isAnnexBStream: Bool { nalLengthSize == nil }
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
        
        // Codec configuration specifies the packet framing. A length-prefixed
        // sample can begin 00 00 01 xx, which looks exactly like a start code.
        if track.isH264, let data = track.codecPrivate {
            nalLengthSize = NALParser.parseAVCDecoderConfigurationRecord(data)?.nalLengthSize
        } else if track.isHEVC, let data = track.codecPrivate {
            nalLengthSize = NALParser.parseHEVCDecoderConfigurationRecord(data)?.nalLengthSize
        } else {
            nalLengthSize = nil
        }
        let config = track.codecPrivate
        let hevc10Bit = track.isHEVC && (config?.count ?? 0) >= 23 && config?.first == 1
            && ((config![config!.startIndex + 17] & 7) > 0)
        self.is10Bit = track.bitsPerChannel > 8 || track.isHDR || hevc10Bit || track.isProRes

        if let desc = Self.createFormatDescription(for: track) {
            self.formatDescription = desc
            guard setupDecompressionSession(with: desc) else { return nil }
        } else if !track.isH264 && !track.isHEVC {
            return nil
        }
    }

    var hasSession: Bool { frameLock.withLock { session != nil } }

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
    
    static func createFormatDescription(for track: DemuxedTrack) -> CMVideoFormatDescription? {
        if track.isH264, let data = track.codecPrivate {
            if let config = NALParser.parseAVCDecoderConfigurationRecord(data) {
                return NALParser.createH264FormatDescription(sps: config.sps, pps: config.pps, nalLengthSize: config.nalLengthSize)
            }
            return parameterSetDescription(track: track, units: NALParser.extractAnnexBNALUnits(from: data), lengthSize: 4)
        }
        if track.isHEVC, let data = track.codecPrivate {
            if let config = NALParser.parseHEVCDecoderConfigurationRecord(data) {
                return NALParser.createHEVCFormatDescription(vps: config.vps, sps: config.sps, pps: config.pps,
                                                             nalLengthSize: config.nalLengthSize)
            }
            return parameterSetDescription(track: track, units: NALParser.extractAnnexBNALUnits(from: data), lengthSize: 4)
        }

        guard let width = Int32(exactly: track.pixelWidth), width > 0,
              let height = Int32(exactly: track.pixelHeight), height > 0 else { return nil }
        let codec: CMVideoCodecType
        var atoms = [String: Data]()
        if track.isVP9 {
            codec = kCMVideoCodecType_VP9
            if let config = track.codecPrivate, config.count >= 12, config.prefix(4) == Data([1, 0, 0, 0]) {
                atoms["vpcC"] = config
            }
        } else if track.isAV1 {
            codec = kCMVideoCodecType_AV1
            if let config = track.codecPrivate, config.count >= 4, config.first == 0x81 {
                atoms["av1C"] = config
            }
        } else {
            switch track.codecID {
            case "jpeg", "V_MJPEG": codec = kCMVideoCodecType_JPEG
            case "dmb1": codec = kCMVideoCodecType_JPEG_OpenDML
            case "ap4x", "V_PRORES/4444XQ": codec = kCMVideoCodecType_AppleProRes4444XQ
            case "ap4h", "V_PRORES/4444": codec = kCMVideoCodecType_AppleProRes4444
            case "apch", "V_PRORES/422HQ": codec = kCMVideoCodecType_AppleProRes422HQ
            case "apcs", "V_PRORES/422LT": codec = kCMVideoCodecType_AppleProRes422LT
            case "apco", "V_PRORES/422PROXY": codec = kCMVideoCodecType_AppleProRes422Proxy
            case "apcn", "V_PRORES/422", "V_PRORES": codec = kCMVideoCodecType_AppleProRes422
            default: return nil
            }
        }
        let extensions = [kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: atoms] as CFDictionary
        var desc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: codec,
                                                    width: width, height: height, extensions: atoms.isEmpty ? nil : extensions,
                                                    formatDescriptionOut: &desc)
        return status == noErr ? desc : nil
    }

    private static func parameterSetDescription(track: DemuxedTrack, units: [Data], lengthSize: Int) -> CMVideoFormatDescription? {
        if track.isH264 {
            let sps = units.filter { ($0.first ?? 0) & 31 == 7 }
            let pps = units.filter { ($0.first ?? 0) & 31 == 8 }
            return NALParser.createH264FormatDescription(sps: sps, pps: pps, nalLengthSize: lengthSize)
        }
        let vps = units.filter { (($0.first ?? 0) >> 1) & 63 == 32 }
        let sps = units.filter { (($0.first ?? 0) >> 1) & 63 == 33 }
        let pps = units.filter { (($0.first ?? 0) >> 1) & 63 == 34 }
        return NALParser.createHEVCFormatDescription(vps: vps, sps: sps, pps: pps, nalLengthSize: lengthSize)
    }

    /// Some transport streams carry parameter sets in the first access unit.
    func bootstrap(from packet: DemuxedPacket) -> Bool {
        guard track.isH264 || track.isHEVC else { return false }
        let units = nalLengthSize.map { NALParser.lengthPrefixedUnits(in: packet.data, headerSize: $0) }
            ?? NALParser.extractAnnexBNALUnits(from: packet.data)
        guard let desc = Self.parameterSetDescription(track: track, units: units, lengthSize: nalLengthSize ?? 4) else { return false }
        return frameLock.withLock {
            formatDescription = desc
            return setupDecompressionSession(with: desc)
        }
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
        
        let codec = CMFormatDescriptionGetMediaSubType(formatDesc)
        if codec == kCMVideoCodecType_VP9 || codec == kCMVideoCodecType_AV1 {
            VTRegisterSupplementalVideoDecoderIfAvailable(codec)
        }
        let preferHardware = UserDefaults.standard.object(forKey: SettingsManager.hardwareAccelerationKey) as? Bool ?? true
        let specification = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: preferHardware]
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: specification as CFDictionary,
            imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary,
            decompressionSessionOut: &session
        )

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
                self.isHardwareAccelerated = isHW as? Bool ?? false
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
            if !hasSession && !bootstrap(from: packet) { return false }
            frameLock.lock()
            let currentFormatDesc = self.formatDescription
            frameLock.unlock()
            guard let formatDesc = currentFormatDesc else { return false }

            let payload = (track.isH264 || track.isHEVC) && isAnnexBStream
                ? NALParser.convertAnnexBToAVCC(packet.data) : packet.data

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
            frameLock.unlock()

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
