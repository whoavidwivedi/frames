//
//  VideoToolboxEncoder.swift
//  frames
//
//  Ultra-high-performance hardware-accelerated video compression engine
//  powered by Apple Silicon VideoToolbox ASIC media engines and Unified Memory.
//

import Foundation
import CoreMedia
import VideoToolbox
import CoreVideo
import os.lock

nonisolated public final class VideoToolboxEncoder: @unchecked Sendable {
    
    // MARK: - Types
    
    public enum Codec: Sendable {
        case h264
        case hevc
        case proRes
        
        public var codecType: CMVideoCodecType {
            switch self {
            case .h264: return kCMVideoCodecType_H264
            case .hevc: return kCMVideoCodecType_HEVC
            case .proRes: return kCMVideoCodecType_AppleProRes422
            }
        }
    }
    
    public struct EncodedPacket: @unchecked Sendable {
        public let data: Data
        public let pts: CMTime
        public let dts: CMTime
        public let isKeyframe: Bool
        public let duration: CMTime
        public let parameterSets: [Data]
        
        public init(
            data: Data,
            pts: CMTime,
            dts: CMTime,
            isKeyframe: Bool,
            duration: CMTime,
            parameterSets: [Data] = []
        ) {
            self.data = data
            self.pts = pts
            self.dts = dts
            self.isKeyframe = isKeyframe
            self.duration = duration
            self.parameterSets = parameterSets
        }
    }
    
    public typealias OutputHandler = @Sendable (Result<EncodedPacket, Error>) -> Void
    
    // MARK: - Properties
    
    private var session: VTCompressionSession?
    public let width: Int32
    public let height: Int32
    public let codec: Codec
    public let bitrate: Int
    public let frameRate: Int
    
    private var lock = os_unfair_lock()
    private var onEncodedPacket: OutputHandler?
    private var collectedPackets: [EncodedPacket] = []
    
    // MARK: - Init
    
    public init?(
        width: Int32,
        height: Int32,
        codec: Codec = .hevc,
        bitrate: Int = 10_000_000,
        frameRate: Int = 30,
        keyframeInterval: Int = 60,
        onPacket: OutputHandler? = nil
    ) {
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
        self.codec = codec
        self.bitrate = bitrate
        self.frameRate = frameRate
        self.onEncodedPacket = onPacket
        
        // Encoder specification: explicitly mandate Apple Silicon hardware ASIC
        let encoderSpecification: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any
        ]
        
        // Pixel buffer source attributes: Metal & IOSurface zero-copy compatibility
        let sourceImageBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        
        var compressionSession: VTCompressionSession?
        var status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codec.codecType,
            encoderSpecification: encoderSpecification as CFDictionary,
            imageBufferAttributes: sourceImageBufferAttributes as CFDictionary,
            compressedDataAllocator: kCFAllocatorDefault,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &compressionSession
        )

        // Fallback to enable-only if hardware require fails (e.g. ProRes on base M1 or constrained hardware)
        if status != noErr {
            let fallbackSpec: [CFString: Any] = [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any
            ]
            status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: width,
                height: height,
                codecType: codec.codecType,
                encoderSpecification: fallbackSpec as CFDictionary,
                imageBufferAttributes: sourceImageBufferAttributes as CFDictionary,
                compressedDataAllocator: kCFAllocatorDefault,
                outputCallback: nil,
                refcon: nil,
                compressionSessionOut: &compressionSession
            )
        }
        
        guard status == noErr, let session = compressionSession else {
            return nil
        }
        self.session = session
        
        // Configure compression properties
        configureSession(session, keyframeInterval: keyframeInterval)
        
        // Prepare session for encoding
        guard VTCompressionSessionPrepareToEncodeFrames(session) == noErr else {
            VTCompressionSessionInvalidate(session)
            return nil
        }
    }
    
    deinit {
        invalidate()
    }
    
    private func configureSession(_ session: VTCompressionSession, keyframeInterval: Int) {
        // Real-time low-latency mode
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        
        // Keyframe cadence
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: keyframeInterval as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: (Double(keyframeInterval) / Double(frameRate)) as CFNumber)
        
        // Expected frame rate
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: frameRate as CFNumber)
        
        if codec != .proRes {
            // Target bitrate
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
            
            // Peak data rate limit: allow 1.5x burst
            let dataRateLimits: [Int] = [bitrate * 3 / 2, 1]
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits as CFArray)
            
            // Profile & Level
            if codec == .h264 {
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
            } else if codec == .hevc {
                VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
            }
        }
    }
    
    public func setOutputHandler(_ handler: @escaping OutputHandler) {
        os_unfair_lock_lock(&lock)
        self.onEncodedPacket = handler
        os_unfair_lock_unlock(&lock)
    }
    
    public func invalidate() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        if let s = session {
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(s)
            session = nil
        }
        collectedPackets.removeAll()
    }
    
    // MARK: - Frame Encoding
    
    /// Compresses a zero-copy CVPixelBuffer using the Apple Silicon hardware video encoder.
    public func encode(
        pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime,
        duration: CMTime = .invalid,
        forceKeyframe: Bool = false
    ) -> Bool {
        guard let session = session else { return false }
        
        var frameProperties: [CFString: Any] = [:]
        if forceKeyframe {
            frameProperties[kVTEncodeFrameOptionKey_ForceKeyFrame] = kCFBooleanTrue
        }
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: frameProperties.isEmpty ? nil : (frameProperties as CFDictionary),
            infoFlagsOut: nil
        ) { [weak self] status, infoFlags, sampleBuffer in
            guard let self = self else { return }
            self.handleEncodedFrame(status: status, sampleBuffer: sampleBuffer)
        }
        
        return status == noErr
    }
    
    /// Flushes any buffered frames from the hardware encoder pipeline.
    public func completeFrames() {
        guard let s = session else { return }
        VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
    }
    
    // MARK: - Pixel Buffer Factory
    
    /// Creates a pixel buffer from the session's hardware-optimized pool.
    public func makePixelBuffer() -> CVPixelBuffer? {
        guard let s = session, let pool = VTCompressionSessionGetPixelBufferPool(s) else {
            return nil
        }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        return status == noErr ? pixelBuffer : nil
    }
    
    // MARK: - Callback Handling
    
    private func handleEncodedFrame(status: OSStatus, sampleBuffer: CMSampleBuffer?) {
        guard status == noErr, let sb = sampleBuffer else {
            if status != noErr {
                deliverResult(.failure(NSError(domain: "VideoToolboxEncoder", code: Int(status), userInfo: nil)))
            }
            return
        }
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sb) else { return }
        
        let totalLength = CMBlockBufferGetDataLength(blockBuffer)
        var bufferData = Data(count: totalLength)
        _ = bufferData.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: totalLength, destination: raw.baseAddress!)
        }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        let dts = CMSampleBufferGetDecodeTimeStamp(sb)
        let duration = CMSampleBufferGetDuration(sb)
        
        // Detect keyframe via sample attachments
        var isKeyframe = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) {
            let count = CFArrayGetCount(attachments)
            if count > 0 {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
                if CFDictionaryContainsKey(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()) {
                    isKeyframe = false
                }
            }
        }
        
        // Extract parameter sets if keyframe
        var parameterSets: [Data] = []
        if isKeyframe, let formatDesc = CMSampleBufferGetFormatDescription(sb) {
            if codec == .h264 {
                var count: Int = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
                for i in 0..<count {
                    var ptr: UnsafePointer<UInt8>?
                    var size: Int = 0
                    if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: i, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let p = ptr, size > 0 {
                        parameterSets.append(Data(bytes: p, count: size))
                    }
                }
            } else if codec == .hevc {
                var count: Int = 0
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
                for i in 0..<count {
                    var ptr: UnsafePointer<UInt8>?
                    var size: Int = 0
                    if CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDesc, parameterSetIndex: i, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let p = ptr, size > 0 {
                        parameterSets.append(Data(bytes: p, count: size))
                    }
                }
            }
        }
        
        let packet = EncodedPacket(
            data: bufferData,
            pts: pts,
            dts: dts,
            isKeyframe: isKeyframe,
            duration: duration,
            parameterSets: parameterSets
        )
        
        deliverResult(.success(packet))
    }
    
    private func deliverResult(_ result: Result<EncodedPacket, Error>) {
        os_unfair_lock_lock(&lock)
        let handler = onEncodedPacket
        if case .success(let pkt) = result {
            collectedPackets.append(pkt)
        }
        os_unfair_lock_unlock(&lock)
        
        handler?(result)
    }
    
    public func popCollectedPackets() -> [EncodedPacket] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let pkts = collectedPackets
        collectedPackets.removeAll(keepingCapacity: true)
        return pkts
    }
}
