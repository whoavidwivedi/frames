//
//  NativeAudioDecoder.swift
//  frames
//
//  High-performance Apple Silicon audio translation and decoding engine.
//  Bridges compressed formats (E-AC3, AC3, AAC, Opus, MP3, ALAC, FLAC) and
//  raw linear PCM into CoreAudio AVAudioPCMBuffers with zero latency.
//

import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

nonisolated private let kAudioDecoderEndOfBatchStatus: OSStatus = 0x454F5042 // 'EOPB'

nonisolated public final class NativeAudioDecoder: @unchecked Sendable {
    
    // MARK: - Properties
    
    public let track: DemuxedTrack
    public let sampleRate: Double
    public let channels: Int
    public let outputFormat: AVAudioFormat
    
    private var converter: AudioConverterRef?
    private let isPCM: Bool
    private let isFloatPCM: Bool
    private let isBigEndianPCM: Bool
    private let bitDepth: Int
    
    // Feeder context for AudioConverterComplexInputDataProc
    private final class FeederContext: @unchecked Sendable {
        var data: Data = Data()
        var channels: UInt32 = 2
        let packetDescPtr: UnsafeMutablePointer<AudioStreamPacketDescription>
        var hasSupplied = false

        /// Stable storage for the current packet. CoreAudio keeps the pointer
        /// supplied by the input callback until the conversion completes, so a
        /// pointer into `Data.withUnsafeBytes` would dangle after that closure.
        private var inputBuffer: UnsafeMutableRawPointer?
        private var inputCapacity: Int = 0

        init() {
            self.packetDescPtr = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        }

        func ensureInputBuffer(_ byteCount: Int) {
            guard byteCount > 0 else { return }
            if inputCapacity < byteCount {
                inputBuffer?.deallocate()
                inputBuffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
                inputCapacity = byteCount
            }
        }

        func copyInputBytes(from data: Data) {
            ensureInputBuffer(data.count)
            data.withUnsafeBytes { raw in
                guard let source = raw.baseAddress, let destination = inputBuffer else { return }
                memcpy(destination, source, data.count)
            }
        }

        var inputBytes: UnsafeMutableRawPointer? { inputBuffer }

        deinit {
            packetDescPtr.deallocate()
            inputBuffer?.deallocate()
        }
    }
    private let feeder = FeederContext()
    private let lock = NSLock()
    
    // MARK: - Init
    
    public init?(track: DemuxedTrack) {
        guard track.isAudio else { return nil }
        self.track = track
        self.sampleRate = track.sampleRate > 0 ? track.sampleRate : 48000.0
        self.channels = track.channels > 0 ? track.channels : 2
        self.bitDepth = track.bitDepth > 0 ? track.bitDepth : 16
        
        // Output format: standard multi/stereo 32-bit Float Linear PCM matching track channels
        let sRate = self.sampleRate
        let channelCount = AVAudioChannelCount(max(1, min(self.channels, 8)))
        let avFormat: AVAudioFormat?
        if channelCount <= 2 {
            avFormat = AVAudioFormat(standardFormatWithSampleRate: sRate, channels: channelCount)
        } else {
            let layoutTag: AudioChannelLayoutTag
            switch channelCount {
            case 6: layoutTag = kAudioChannelLayoutTag_MPEG_5_1_D
            case 8: layoutTag = kAudioChannelLayoutTag_MPEG_7_1_B
            default: layoutTag = kAudioChannelLayoutTag_Stereo
            }
            if let layout = AVAudioChannelLayout(layoutTag: layoutTag) {
                avFormat = AVAudioFormat(standardFormatWithSampleRate: sRate, channelLayout: layout)
            } else {
                avFormat = AVAudioFormat(standardFormatWithSampleRate: sRate, channels: 2)
            }
        }
        guard let format = avFormat, Int(format.channelCount) == channels else { return nil }
        
        let codec = track.codecID.uppercased()
        // MP4/QuickTime use four-character PCM sample entries (IN32, IN24,
        // IN16, IF32, ...) rather than Matroska's A_PCM/* IDs. These are raw
        // linear samples, so they must take the PCM path instead of being fed
        // to an AAC AudioConverter, which cannot decode them.
        // IN08 is intentionally excluded: the sample translator handles 16/24/32-bit
        // integer and 32-bit float samples, so an 8-bit entry cannot be decoded here.
        let pcmSampleEntries: Set<String> = ["IN32", "IN24", "IN16", "TWOS", "SOWT", "IF32", "FL32", "LPCM"]
        if codec.hasPrefix("A_PCM") || pcmSampleEntries.contains(codec) {
            self.isPCM = true
            // QuickTime v2 lpcm format flags: 0x1 = float, 0x2 = big-endian.
            self.isFloatPCM = codec.contains("FLOAT") || ["IF32", "FL32"].contains(codec)
                || (track.pcmFormatFlags & 0x1) != 0
            // An explicit `enda` box wins over the codec's default byte order.
            let codecBigEndian = codec.contains("/BIG")
                || ["IN32", "IN24", "IN16", "TWOS", "FL32"].contains(codec)
            self.isBigEndianPCM = track.pcmBigEndian
                ?? (codecBigEndian || (track.pcmFormatFlags & 0x2) != 0)
            guard [8, 16, 24, 32, 64].contains(bitDepth),
                  isFloatPCM ? [32, 64].contains(bitDepth) : bitDepth <= 32,
                  track.pcmFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 else { return nil }

            let stride = UInt32(self.channels * bitDepth / 8)
            var flags = kAudioFormatFlagIsPacked | (isFloatPCM ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger)
            if isBigEndianPCM { flags |= kAudioFormatFlagIsBigEndian }
            var source = AudioStreamBasicDescription(
                mSampleRate: sRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: flags,
                mBytesPerPacket: stride, mFramesPerPacket: 1, mBytesPerFrame: stride,
                mChannelsPerFrame: format.channelCount, mBitsPerChannel: UInt32(bitDepth), mReserved: 0
            )
            var destination = format.streamDescription.pointee
            var pcmConverter: AudioConverterRef?
            guard AudioConverterNew(&source, &destination, &pcmConverter) == noErr,
                  let pcmConverter else { return nil }
            self.outputFormat = format
            self.converter = pcmConverter
            return
        }
        
        self.isPCM = false
        self.isFloatPCM = false
        self.isBigEndianPCM = false
        
        // Map codec to CoreAudio AudioFormatID
        let formatID: AudioFormatID
        var framesPerPacket: UInt32 = 1536
        
        if codec == "A_EAC3" || codec == "EC-3" {
            formatID = kAudioFormatEnhancedAC3
            framesPerPacket = 1536
        } else if codec == "A_AC3" || codec == "AC-3" {
            formatID = kAudioFormatAC3
            framesPerPacket = 1536
        } else if codec == "A_AAC" || codec.contains("AAC") || codec == "MP4A" {
            formatID = kAudioFormatMPEG4AAC
            framesPerPacket = 1024
        } else if codec == "A_OPUS" || codec.contains("OPUS") {
            formatID = kAudioFormatOpus
            framesPerPacket = 960
        } else if codec == "A_MPEG/L3" || codec.contains("MP3") {
            formatID = kAudioFormatMPEGLayer3
            framesPerPacket = 1152
        } else if codec == "A_ALAC" || codec.contains("ALAC") || codec == "ALAC" {
            formatID = kAudioFormatAppleLossless
            framesPerPacket = 4096
        } else if codec == "A_FLAC" || codec.contains("FLAC") {
            formatID = kAudioFormatFLAC
            framesPerPacket = 4096
        } else {
            return nil
        }
        
        var asbdIn = AudioStreamBasicDescription(
            mSampleRate: self.sampleRate,
            mFormatID: formatID,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: framesPerPacket,
            mBytesPerFrame: 0,
            mChannelsPerFrame: format.channelCount,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        
        var asbdOut = format.streamDescription.pointee
        var conv: AudioConverterRef?
        let status = AudioConverterNew(&asbdIn, &asbdOut, &conv)
        guard status == noErr, let c = conv else {
            return nil
        }
        
        // Set magic cookie (e.g. AAC AudioSpecificConfig, Opus header, etc.) if provided
        if let cookie = track.codecPrivate, !cookie.isEmpty {
            cookie.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    AudioConverterSetProperty(
                        c,
                        kAudioConverterDecompressionMagicCookie,
                        UInt32(cookie.count),
                        base
                    )
                }
            }
        }
        
        if channels > 2 {
            // The ASBD describes the channel count, but carries no speaker labels.
            // Use the order the codec actually emits before handing buffers to the mixer.
            var size: UInt32 = 0
            guard AudioConverterGetPropertyInfo(c, kAudioConverterOutputChannelLayout, &size, nil) == noErr,
                  size >= 12 else {
                AudioConverterDispose(c)
                return nil
            }
            let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioChannelLayout>.alignment)
            defer { storage.deallocate() }
            guard AudioConverterGetProperty(c, kAudioConverterOutputChannelLayout, &size, storage) == noErr else {
                AudioConverterDispose(c)
                return nil
            }
            let layout = AVAudioChannelLayout(layout: storage.assumingMemoryBound(to: AudioChannelLayout.self))
            guard layout.channelCount == format.channelCount else {
                AudioConverterDispose(c)
                return nil
            }
            self.outputFormat = AVAudioFormat(standardFormatWithSampleRate: sRate, channelLayout: layout)
        } else {
            self.outputFormat = format
        }
        self.converter = c
    }
    
    deinit {
        if let c = converter {
            AudioConverterDispose(c)
        }
    }
    
    // MARK: - Reset State on Seek
    
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        if let c = converter {
            AudioConverterReset(c)
        }
        feeder.data = Data()
        feeder.hasSupplied = false
    }
    
    // MARK: - Decoding
    
    /// Translates an elementary demuxed audio packet into an uncompressed 32-bit Float AVAudioPCMBuffer.
    public func decode(packet: DemuxedPacket) -> AVAudioPCMBuffer? {
        return autoreleasepool { () -> AVAudioPCMBuffer? in
            lock.lock()
            defer { lock.unlock() }
            
            guard let conv = converter else { return nil }
            if isPCM { return decodePCM(data: packet.data, converter: conv) }
            
            // ALAC/FLAC packets can hold 4096 frames; 3072 was too small and truncated output.
            let outputFrameCapacity: UInt32 = 4096
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
                return nil
            }
            // Pre-set frameLength so that mutableAudioBufferList initializes valid mDataByteSize
            pcmBuffer.frameLength = outputFrameCapacity
            
            feeder.data = packet.data
            feeder.copyInputBytes(from: packet.data)
            feeder.channels = UInt32(self.channels)
            feeder.packetDescPtr.pointee = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(packet.data.count)
            )
            feeder.hasSupplied = false
            
            let inputProc: AudioConverterComplexInputDataProc = { (
                _,
                ioNumberDataPackets,
                ioData,
                outDataPacketDescription,
                inUserData
            ) -> OSStatus in
                guard let userData = inUserData else {
                    ioNumberDataPackets.pointee = 0
                    return -1
                }
                let feederCtx = Unmanaged<FeederContext>.fromOpaque(userData).takeUnretainedValue()
                if feederCtx.hasSupplied || feederCtx.data.isEmpty {
                    ioNumberDataPackets.pointee = 0
                    ioData.pointee.mBuffers.mDataByteSize = 0
                    if let outDesc = outDataPacketDescription {
                        outDesc.pointee = nil
                    }
                    return kAudioDecoderEndOfBatchStatus
                }
                
                ioNumberDataPackets.pointee = 1
                let numBytes = UInt32(feederCtx.data.count)
                
                ioData.pointee.mNumberBuffers = 1
                ioData.pointee.mBuffers.mNumberChannels = feederCtx.channels
                ioData.pointee.mBuffers.mDataByteSize = numBytes
                ioData.pointee.mBuffers.mData = feederCtx.inputBytes
                
                if let outDesc = outDataPacketDescription {
                    outDesc.pointee = feederCtx.packetDescPtr
                }
                feederCtx.hasSupplied = true
                return noErr
            }
            
            var ioOutputFrames: UInt32 = outputFrameCapacity
            let feederPtr = Unmanaged.passUnretained(feeder).toOpaque()
            let abl = pcmBuffer.mutableAudioBufferList
            
            let status = AudioConverterFillComplexBuffer(
                conv,
                inputProc,
                feederPtr,
                &ioOutputFrames,
                abl,
                nil
            )
            
            guard (status == noErr || status == kAudioDecoderEndOfBatchStatus), ioOutputFrames > 0 else {
                return nil
            }
            pcmBuffer.frameLength = ioOutputFrames
            return pcmBuffer
        }
    }
    
    // MARK: - PCM Translation
    
    private func decodePCM(data: Data, converter: AudioConverterRef) -> AVAudioPCMBuffer? {
        let stride = channels * bitDepth / 8
        guard !data.isEmpty, data.count.isMultiple(of: stride),
              let byteCount = UInt32(exactly: data.count) else { return nil }
        let frames = byteCount / UInt32(stride)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frames) else { return nil }
        output.frameLength = frames

        let status = data.withUnsafeBytes { bytes in
            var input = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: UInt32(channels), mDataByteSize: byteCount,
                mData: UnsafeMutableRawPointer(mutating: bytes.baseAddress)
            ))
            return AudioConverterConvertComplexBuffer(converter, frames, &input, output.mutableAudioBufferList)
        }
        return status == noErr ? output : nil
    }
}
