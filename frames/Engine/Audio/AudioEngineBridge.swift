//
//  AudioEngineBridge.swift
//  frames
//
//  Bit-perfect low-latency CoreAudio engine powered by AVAudioEngine,
//  AudioConverter, and hardware-coupled DAC sample clock synchronization.
//

import Foundation
import AVFoundation
import AudioToolbox

nonisolated public final class AudioEngineBridge: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let decoder: NativeAudioDecoder?
    
    public let track: DemuxedTrack
    public let sampleRate: Double
    public let channels: Int
    
    public let outputFormat: AVAudioFormat
    private var isPlaying = false
    private let lock = NSLock()
    
    // Hardware Master Clock State
    private var anchorSampleTime: AVAudioFramePosition = 0
    private var anchorPts: Double = 0
    private var lastReportedTime: Double = 0
    private var hasAnchored = false
    private var hasScheduledFirstBuffer = false
    private var minimumSeekPTS: Double = 0.0
    
    // MARK: - Lifecycle
    
    public init?(track: DemuxedTrack) {
        guard track.isAudio else { return nil }
        self.track = track
        self.sampleRate = track.sampleRate > 0 ? track.sampleRate : 48000.0
        self.channels = track.channels > 0 ? track.channels : 2
        
        // Target standard floating-point stereo format for audio hardware
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: self.sampleRate,
            channels: 2
        ) else {
            return nil
        }
        self.outputFormat = format
        self.decoder = NativeAudioDecoder(track: track)
        
        setupAudioEngine()
    }
    
    deinit {
        stop()
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        if #available(macOS 27.0, *) {
            try? audioEngine.connectNode(playerNode, to: audioEngine.mainMixerNode, format: outputFormat)
        } else {
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: outputFormat)
        }
        playerNode.volume = 1.0
        audioEngine.mainMixerNode.outputVolume = 1.0
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("[AudioEngineBridge] Engine startup error: \(error)")
        }
    }
    
    // MARK: - Packet Processing & Decoding
    
    /// Translates an elementary demuxed packet into uncompressed PCM and schedules it for DAC playback.
    public func process(packet: DemuxedPacket) {
        guard let pcm = decoder?.decode(packet: packet) else { return }
        scheduleBuffer(pcm, pts: packet.pts)
    }
    
    private func startPlayerNode() {
        if #available(macOS 27.0, *) {
            try? playerNode.playAudio()
        } else {
            playerNode.play()
        }
    }
    
    // MARK: - Playback Controls
    
    public func play() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isPlaying else { return }
        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
        startPlayerNode()
        isPlaying = true
    }
    
    public func pause() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isPlaying else { return }
        playerNode.pause()
        isPlaying = false
        anchorPts = lastReportedTime
        hasAnchored = false
    }
    
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        playerNode.stop()
        audioEngine.stop()
        isPlaying = false
        anchorPts = 0
        anchorSampleTime = 0
        lastReportedTime = 0
        hasAnchored = false
        hasScheduledFirstBuffer = false
        minimumSeekPTS = 0
    }
    
    public func setVolume(_ volume: Float) {
        playerNode.volume = max(0.0, min(volume, 1.0))
    }

    public var currentVolume: Float {
        return playerNode.volume
    }
    
    public func seek(to pts: Double) {
        lock.lock()
        defer { lock.unlock() }
        
        playerNode.stop()
        decoder?.reset()
        anchorPts = pts
        anchorSampleTime = 0
        lastReportedTime = pts
        hasAnchored = false
        hasScheduledFirstBuffer = false
        minimumSeekPTS = max(0.0, pts - 0.035)
        
        if isPlaying {
            startPlayerNode()
        }
    }
    
    // MARK: - Buffer Scheduling
    
    /// Schedules an uncompressed PCM buffer directly to the CoreAudio hardware queue.
    public func scheduleBuffer(_ pcmBuffer: AVAudioPCMBuffer, pts: Double) {
        lock.lock()
        // Guard against pre-seek audio packets from earlier in the cluster
        if pts < minimumSeekPTS {
            lock.unlock()
            return
        }
        if !hasScheduledFirstBuffer {
            anchorPts = pts
            lastReportedTime = pts
            hasScheduledFirstBuffer = true
            hasAnchored = false
        }
        // Keep scheduling serialized with stop()/seek() so stale packets can never
        // land in the player queue after a track switch or seek.
        playerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        lock.unlock()
    }
    
    // MARK: - Master Clock Synchronization
    
    /// Returns the true monotonic nanosecond-accurate hardware clock time (in seconds).
    public var currentMasterTime: Double {
        lock.lock()
        defer { lock.unlock() }
        
        guard isPlaying else { return lastReportedTime }
        
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
           playerTime.sampleRate > 0 {
            if !hasAnchored {
                anchorSampleTime = playerTime.sampleTime
                hasAnchored = true
            }
            let elapsedSamples = max(0, playerTime.sampleTime - anchorSampleTime)
            let elapsedSeconds = Double(elapsedSamples) / playerTime.sampleRate
            let current = max(0.0, anchorPts + elapsedSeconds)
            lastReportedTime = current
            return current
        }
        
        // No render clock yet (device switch / unsupported stream). Report invalid
        // so the pipeline falls back to wall-clock timing instead of freezing.
        return -1
    }
}
