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
    private let bitDepth: Int
    
    // Feeder context for AudioConverterComplexInputDataProc
    private final class FeederContext: @unchecked Sendable {
        var data: Data = Data()
        var channels: UInt32 = 2
        let packetDescPtr: UnsafeMutablePointer<AudioStreamPacketDescription>
        var hasSupplied = false
        
        init() {
            self.packetDescPtr = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        }
        
        deinit {
            packetDescPtr.deallocate()
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
        guard let format = avFormat else { return nil }
        self.outputFormat = format
        
        let codec = track.codecID.uppercased()
        if codec.hasPrefix("A_PCM") {
            self.isPCM = true
            self.isFloatPCM = codec.contains("FLOAT")
            self.converter = nil
            return
        }
        
        self.isPCM = false
        self.isFloatPCM = false
        
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
            // Default fallback to AAC format ID
            formatID = kAudioFormatMPEG4AAC
            framesPerPacket = 1024
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
        return autoreleasepool {
            if isPCM {
                return decodePCM(data: packet.data)
            }
            
            lock.lock()
            defer { lock.unlock() }
            
            guard let conv = converter else { return nil }
            
            let framesExpected: UInt32 = 1536
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesExpected * 2) else {
                return nil
            }
            // Pre-set frameLength so that mutableAudioBufferList initializes valid mDataByteSize
            pcmBuffer.frameLength = framesExpected * 2
            
            feeder.data = packet.data
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
                
                feederCtx.data.withUnsafeBytes { raw in
                    let ptr = UnsafeMutableRawPointer(mutating: raw.baseAddress!)
                    ioData.pointee.mNumberBuffers = 1
                    ioData.pointee.mBuffers.mNumberChannels = feederCtx.channels
                    ioData.pointee.mBuffers.mDataByteSize = numBytes
                    ioData.pointee.mBuffers.mData = ptr
                }
                
                if let outDesc = outDataPacketDescription {
                    outDesc.pointee = feederCtx.packetDescPtr
                }
                feederCtx.hasSupplied = true
                return noErr
            }
            
            var ioOutputFrames: UInt32 = framesExpected * 2
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
    
    private func decodePCM(data: Data) -> AVAudioPCMBuffer? {
        let bytesPerSample = bitDepth / 8
        guard bytesPerSample > 0, channels > 0 else { return nil }
        
        let frameSize = bytesPerSample * channels
        let frameCount = UInt32(data.count / frameSize)
        guard frameCount > 0 else { return nil }
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return nil
        }
        pcmBuffer.frameLength = frameCount
        
        guard let channelData = pcmBuffer.floatChannelData else {
            return nil
        }
        let outChannels = Int(outputFormat.channelCount)
        
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            
            if isFloatPCM && bytesPerSample == 4 {
                let floatPtr = base.bindMemory(to: Float.self, capacity: Int(frameCount) * channels)
                for f in 0..<Int(frameCount) {
                    for ch in 0..<outChannels {
                        let srcCh = min(ch, channels - 1)
                        channelData[ch][f] = floatPtr[f * channels + srcCh]
                    }
                }
            } else if bytesPerSample == 2 {
                // 16-bit Signed Integer PCM
                let int16Ptr = base.bindMemory(to: Int16.self, capacity: Int(frameCount) * channels)
                let scale: Float = 1.0 / 32768.0
                for f in 0..<Int(frameCount) {
                    for ch in 0..<outChannels {
                        let srcCh = min(ch, channels - 1)
                        channelData[ch][f] = Float(int16Ptr[f * channels + srcCh]) * scale
                    }
                }
            } else if bytesPerSample == 3 {
                // 24-bit Signed Integer PCM
                let bytePtr = base.bindMemory(to: UInt8.self, capacity: data.count)
                let scale: Float = 1.0 / 8388608.0
                for f in 0..<Int(frameCount) {
                    for ch in 0..<outChannels {
                        let srcCh = min(ch, channels - 1)
                        let offset = (f * channels + srcCh) * 3
                        let val = Int32(Int8(bitPattern: bytePtr[offset + 2])) << 16 |
                                  Int32(bytePtr[offset + 1]) << 8 |
                                  Int32(bytePtr[offset])
                        channelData[ch][f] = Float(val) * scale
                    }
                }
            }
        }
        
        return pcmBuffer
    }
}
