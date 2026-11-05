//
//  PlaybackPipeline.swift
//  frames
//
//  Ultra-high performance native media playback orchestrator coordinating
//  Matroska demuxing, VideoToolbox ASIC decoding, CoreAudio DAC timing,
//  and Metal 3 HDR presentation with zero memory copies.
//

import Foundation
import CoreMedia
import CoreVideo
import QuartzCore
import Combine
import os.lock

// MARK: - High-Throughput Unfair-Lock Frame Queue

nonisolated private final class FrameQueue: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var frames: [VideoToolboxDecoder.DecodedVideoFrame] = []
    private var minimumAcceptedPTS = -Double.infinity
    let maxCount: Int
    
    init(maxCount: Int = 18) {
        self.maxCount = maxCount
    }
    
    var count: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return frames.count
    }
    
    func enqueue(_ frame: VideoToolboxDecoder.DecodedVideoFrame) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard frame.pts >= minimumAcceptedPTS else { return }
        if let idx = frames.firstIndex(where: { $0.pts > frame.pts }) {
            frames.insert(frame, at: idx)
        } else {
            frames.append(frame)
        }
        if frames.count > maxCount + 4 {
            frames.removeFirst()
        }
    }
    
    func firstFrame() -> CVPixelBuffer? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return frames.first?.pixelBuffer
    }
    
    func frameClosest(to targetPTS: Double) -> (buffer: CVPixelBuffer, pts: Double)? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard !frames.isEmpty else { return nil }
        var bestIndex = 0
        var bestDiff = Double.infinity
        for (i, f) in frames.enumerated() {
            let diff = abs(f.pts - targetPTS)
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = i
            }
        }
        let matched = frames[bestIndex]
        return (matched.pixelBuffer, matched.pts)
    }
    
    func dequeueNext(forMasterClock masterClock: Double) -> (buffer: CVPixelBuffer, pts: Double)? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        while frames.count > 1 && frames[0].pts < masterClock - 0.030 {
            frames.removeFirst()
        }
        guard let candidate = frames.first else { return nil }
        if candidate.pts <= masterClock + 0.012 {
            frames.removeFirst()
            return (candidate.pixelBuffer, candidate.pts)
        }
        return nil
    }
    
    func removeAll() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        frames.removeAll()
    }

    func reset(forSeek target: Double) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        frames.removeAll()
        minimumAcceptedPTS = max(0.0, target - 0.25)
    }
}

// MARK: - Thread-Safe Seek Generation Token

nonisolated private final class SeekToken: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var gen: Int = 0
    
    func next() -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        gen &+= 1
        return gen
    }
    
    func isCurrent(_ expected: Int) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return gen == expected
    }
}

// MARK: - Thread-Safe Active Media Routing

nonisolated private final class ActiveMediaRouting: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var _audioEngine: AudioEngineBridge?
    private var _activeAudioTrackNumber: UInt64?
    private var _activeSubtitleTrackNumber: UInt64?
    private var _playbackRate: Float = 1.0

    func updateAudio(engine: AudioEngineBridge?, trackNumber: UInt64?) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        _audioEngine = engine
        _activeAudioTrackNumber = trackNumber
    }

    func updateSubtitle(trackNumber: UInt64?) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        _activeSubtitleTrackNumber = trackNumber
    }

    func setPlaybackRate(_ rate: Float) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        _playbackRate = rate
    }

    var playbackRate: Float {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _playbackRate
    }

    var currentAudioEngine: AudioEngineBridge? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _audioEngine
    }

    var activeAudioTrackNumber: UInt64? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _activeAudioTrackNumber
    }

    var activeSubtitleTrackNumber: UInt64? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _activeSubtitleTrackNumber
    }
}

// MARK: - Playback Pipeline

@MainActor
public final class PlaybackPipeline: ObservableObject {
    
    // MARK: - State
    
    public enum PlaybackState: Sendable, Equatable {
        case idle
        case loading
        case playing
        case paused
        case stopped
        case error(String)
    }
    
    // MARK: - Published Properties
    
    @Published public private(set) var state: PlaybackState = .idle
    @Published public private(set) var currentURL: URL?
    @Published public private(set) var duration: Double = 0.0
    @Published public private(set) var currentTime: Double = 0.0
    @Published public private(set) var playbackRate: Float = 1.0
    
    // Engine Subsystems
    public private(set) var demuxer: MatroskaDemuxer?
    private var videoDecoder: VideoToolboxDecoder?
    private var audioEngine: AudioEngineBridge?
    public let renderer: MetalVideoRenderer?

    // Multi-Track Audio & Subtitle State
    private let routing = ActiveMediaRouting()
    public var demuxedAudioTracks: [DemuxedTrack] {
        demuxer?.audioTracks ?? []
    }
    public var demuxedSubtitleTracks: [DemuxedTrack] {
        demuxer?.subtitleTracks ?? []
    }
    @Published public private(set) var activeAudioTrackNumber: UInt64?
    @Published public private(set) var activeSubtitleTrackNumber: UInt64?
    public var onSubtitleCue: (@Sendable (SubtitleCue) -> Void)?
    
    // Decoded Frame Ring Buffer & Scrub Frame Cache
    private let frameQueue = FrameQueue(maxCount: 12)
    private let scrubCache = ScrubFrameCache(maxCapacity: 64)
    private let packetChunkBuffer = PacketChunkBuffer(maxCapacity: 256)
    
    // Concurrency & Feeder Task
    private let seekToken = SeekToken()
    private var feederTask: Task<Void, Never>?
    private var isPlaying = false
    private var playbackStartTime: CFTimeInterval = 0
    private var playbackStartPts: Double = 0
    
    // Callbacks
    public var onTimeUpdate: (@Sendable (Double) -> Void)?
    public var onStateChange: (@Sendable (PlaybackState) -> Void)?
    public var onPlaybackEnded: (@Sendable () -> Void)?
    
    // MARK: - Lifecycle
    
    public init() {
        self.renderer = MetalVideoRenderer()
    }
    
    deinit {
        feederTask?.cancel()
        audioEngine?.stop()
        videoDecoder?.invalidate()
    }
    
    // MARK: - Load File
    
    /// Opens and prepares a media file for native zero-copy playback synchronously.
    @discardableResult
    public func loadSync(url: URL) -> Bool {
        stop()
        
        transition(to: .loading)
        self.currentURL = url
        
        // 1. Initialize pure Swift streaming Matroska demuxer
        do {
            let d = try MatroskaDemuxer(url: url)
            self.demuxer = d
            self.duration = d.duration
            
            // 2. Select primary video track & setup VideoToolbox decoder
            guard let vTrack = d.videoTracks.first,
                  let decoder = VideoToolboxDecoder(track: vTrack) else {
                transition(to: .error("Failed to initialize VideoToolbox hardware decoder"))
                return false
            }
            
            let q = self.frameQueue
            let cache = self.scrubCache
            decoder.setFrameHandler { frame in
                cache.insert(buffer: frame.pixelBuffer, pts: frame.pts)
                q.enqueue(frame)
            }
            self.videoDecoder = decoder
            
            // 3. Select primary audio track & setup CoreAudio engine
            let defaultAudio = d.audioTracks.first(where: { $0.isDefault }) ?? d.audioTracks.first
            if let aTrack = defaultAudio {
                let bridge = AudioEngineBridge(track: aTrack)
                self.audioEngine = bridge
                self.activeAudioTrackNumber = aTrack.trackNumber
                routing.updateAudio(engine: bridge, trackNumber: aTrack.trackNumber)
            } else {
                self.activeAudioTrackNumber = nil
                routing.updateAudio(engine: nil, trackNumber: nil)
            }
            self.activeSubtitleTrackNumber = nil
            routing.updateSubtitle(trackNumber: nil)
            routing.setPlaybackRate(playbackRate)
            
            transition(to: .paused)
            return true
        } catch {
            transition(to: .error("Failed to demux container: \(error.localizedDescription)"))
            return false
        }
    }
    
    // MARK: - Track Switching
    public func selectAudioTrack(trackNumber: UInt64) {
        guard let d = demuxer, let track = d.audioTracks.first(where: { $0.trackNumber == trackNumber }) else { return }
        guard activeAudioTrackNumber != trackNumber else { return }

        let previousVolume = audioEngine?.currentVolume ?? 1.0
        let wasPlaying = isPlaying
        audioEngine?.stop()

        if let newEngine = AudioEngineBridge(track: track) {
            newEngine.setVolume(previousVolume)
            self.audioEngine = newEngine
            self.activeAudioTrackNumber = trackNumber
            routing.updateAudio(engine: newEngine, trackNumber: trackNumber)
            newEngine.seek(to: currentTime)
            if wasPlaying {
                newEngine.play()
            }
        }
    }

    public func selectSubtitleTrack(trackNumber: UInt64?) {
        self.activeSubtitleTrackNumber = trackNumber
        routing.updateSubtitle(trackNumber: trackNumber)
    }

    public func setPlaybackRate(_ rate: Float) {
        let clamped = max(0.25, min(rate, 4.0))
        self.playbackRate = clamped
        routing.setPlaybackRate(clamped)
    }
    
    /// Opens and prepares a media file for native zero-copy playback.
    @discardableResult
    public func load(url: URL) async -> Bool {
        return loadSync(url: url)
    }
    
    // MARK: - Playback Control
    
    public func play() {
        guard (state == .paused || state == .idle), let demuxer = demuxer else { return }
        
        let gen = seekToken.next()
        
        isPlaying = true
        playbackStartTime = CACurrentMediaTime()
        playbackStartPts = currentTime
        audioEngine?.play()
        transition(to: .playing)
        
        startFeederTask(demuxer: demuxer, targetSeekTime: nil, generation: gen)
    }
    
    public func pause() {
        guard case .playing = state else { return }
        
        isPlaying = false
        let elapsed = CACurrentMediaTime() - playbackStartTime
        currentTime = min(duration > 0 ? duration : Double.infinity, playbackStartPts + elapsed)
        audioEngine?.pause()
        feederTask?.cancel()
        feederTask = nil
        transition(to: .paused)
    }
    
    public func stop() {
        isPlaying = false
        feederTask?.cancel()
        feederTask = nil
        
        audioEngine?.stop()
        videoDecoder?.invalidate()
        videoDecoder = nil
        demuxer = nil
        
        frameQueue.removeAll()
        scrubCache.clear()
        packetChunkBuffer.removeAll()
        renderer?.clearFrame()
        currentTime = 0
        transition(to: .stopped)
    }
    
    /// Seeks to target timestamp with artifact-free GOP preroll decoding and scrub cache lookup.
    public func seek(to time: Double, isScrubbing: Bool = false) {
        guard let demuxer = demuxer else { return }
        
        let gen = seekToken.next()
        
        // 1. Instant scrub cache check: if frame was recently decoded, display immediately
        if isScrubbing, let cached = scrubCache.getFrame(forTargetPTS: time, tolerance: 0.12) {
            currentTime = time
            onTimeUpdate?(time)
            renderer?.updateFrame(cached.buffer)
            if !isPlaying { return }
        }
        
        feederTask?.cancel()
        feederTask = nil
        
        frameQueue.reset(forSeek: time)
        packetChunkBuffer.removeAll()
        videoDecoder?.flush()
        audioEngine?.seek(to: time)
        
        // $O(\log N)$ binary search seek in Matroska index (prioritizing video keyframe cues)
        demuxer.seek(to: time)
        playbackStartTime = CACurrentMediaTime()
        playbackStartPts = time
        currentTime = time
        onTimeUpdate?(time)
        
        // Immediately restart feeder loop (continuous if playing, precision GOP preroll if paused/scrubbing)
        startFeederTask(demuxer: demuxer, targetSeekTime: isPlaying ? nil : time, generation: gen)
    }
    
    public func setVolume(_ volume: Float) {
        audioEngine?.setVolume(volume)
    }
    
    // MARK: - Frame Delivery for CADisplayLink
    
    /// Called by the 120Hz CADisplayLink to acquire the current frame matching the display cadence.
    public func nextFrameForDisplay() -> CVPixelBuffer? {
        let masterClock: Double
        if isPlaying {
            let audioClock = audioEngine?.currentMasterTime ?? 0.0
            if audioClock > 0.05 {
                masterClock = audioClock
            } else {
                let elapsed = (CACurrentMediaTime() - playbackStartTime) * Double(playbackRate)
                masterClock = playbackStartPts + elapsed
            }
            currentTime = masterClock
            onTimeUpdate?(masterClock)

            if duration > 0 && masterClock >= duration {
                isPlaying = false
                audioEngine?.pause()
                feederTask?.cancel()
                feederTask = nil
                transition(to: .paused)
                onPlaybackEnded?()
            }
        } else {
            masterClock = currentTime
        }
        
        guard let next = frameQueue.dequeueNext(forMasterClock: masterClock) else {
            return nil
        }
        
        return next.buffer
    }
    
    // MARK: - Background Feeder Loop
    
    private func startFeederTask(demuxer: MatroskaDemuxer, targetSeekTime: Double? = nil, generation: Int) {
        feederTask?.cancel()
        
        let token = self.seekToken
        let decoder = self.videoDecoder
        let routing = self.routing
        let q = self.frameQueue
        let cache = self.scrubCache
        let packetBuffer = self.packetChunkBuffer
        let renderer = self.renderer
        let isSingleSeek = (targetSeekTime != nil)
        let targetPTS = targetSeekTime ?? 0.0
        let onSubCue = self.onSubtitleCue
        
        feederTask = Task.detached(priority: .userInitiated) { [weak demuxer] in
            guard let demuxer = demuxer else { return }
            
            func isCurrentGen() -> Bool {
                return token.isCurrent(generation) && !Task.isCancelled
            }
            
            // Mode A: Precision Seek Preroll (Decodes keyframe and intermediate frames up to target PTS)
            if isSingleSeek {
                var packetsRead = 0
                let maxPackets = 450
                var targetFrameFound = false
                
                while isCurrentGen() && !targetFrameFound && packetsRead < maxPackets {
                    guard let packet = try? demuxer.nextPacket() else { break }
                    packetsRead += 1
                    
                    if let dec = decoder, packet.trackNumber == dec.track.trackNumber {
                        // Decode frame normally so VideoToolbox ASIC populates reference frames and decoded image
                        _ = dec.decode(packet: packet, doNotOutput: false)
                        
                        if packet.isKeyframe {
                            packetBuffer.recordGOP(keyframePTS: packet.pts, fileOffset: packet.fileOffset)
                        }
                        
                        // Continue decoding until we pass the target PTS with sufficient margin to resolve any B-frame forward references
                        if packet.pts >= targetPTS + 0.12 || (packet.isKeyframe && packetsRead > 1) {
                            targetFrameFound = true
                        }
                    }
                }
                
                guard isCurrentGen() else { return }
                decoder?.waitForFrames()
                
                // Select frame closest to targetPTS from scrub cache or frameQueue
                if let matched = cache.getFrame(forTargetPTS: targetPTS, tolerance: 0.35) {
                    renderer?.updateFrame(matched.buffer)
                } else if let candidate = q.frameClosest(to: targetPTS) {
                    cache.insert(buffer: candidate.buffer, pts: candidate.pts)
                    renderer?.updateFrame(candidate.buffer)
                } else if let nearest = cache.nearestFrame(to: targetPTS) {
                    renderer?.updateFrame(nearest.buffer)
                } else if let first = q.firstFrame() {
                    renderer?.updateFrame(first)
                }
                return
            }
            
            // Mode B: Continuous Streaming Playback with Chunked Packet Prefetching
            while isCurrentGen() {
                // Throttle feeding if decoded frame queue has sufficient headroom
                if q.count >= q.maxCount {
                    try? await Task.sleep(nanoseconds: 6_000_000) // 6ms sleep
                    continue
                }
                
                // Prefetch packet chunk if buffer needs replenishment
                if packetBuffer.hasHeadroom {
                    if let chunk = try? demuxer.nextPacketChunk(maxPackets: 24), !chunk.isEmpty {
                        for p in chunk where p.isKeyframe && p.trackNumber == decoder?.track.trackNumber {
                            packetBuffer.recordGOP(keyframePTS: p.pts, fileOffset: p.fileOffset)
                        }
                        packetBuffer.enqueue(packets: chunk)
                    }
                }
                
                // Dequeue next packet from chunk buffer or directly from demuxer
                guard let packet = packetBuffer.dequeue() ?? (try? demuxer.nextPacket()) else {
                    break
                }
                
                // Route packet to hardware video decoder or native audio translation engine
                let activeAudio = routing.currentAudioEngine
                let activeAudioNum = routing.activeAudioTrackNumber
                let activeSubNum = routing.activeSubtitleTrackNumber

                if let dec = decoder, packet.trackNumber == dec.track.trackNumber {
                    if packet.isKeyframe {
                        packetBuffer.recordGOP(keyframePTS: packet.pts, fileOffset: packet.fileOffset)
                    }
                    _ = dec.decode(packet: packet)
                } else if let a = activeAudio, packet.trackNumber == activeAudioNum {
                    a.process(packet: packet)
                } else if let subNum = activeSubNum, packet.trackNumber == subNum {
                    if let text = String(data: packet.data, encoding: .utf8) {
                        let clean = SubtitleParser.cleanSubtitleCueText(text)
                        if !clean.isEmpty {
                            let dur = (packet.duration ?? 0) > 0 ? packet.duration! : 3.0
                            let cue = SubtitleCue(startTime: packet.pts, endTime: packet.pts + dur, text: clean)
                            onSubCue?(cue)
                        }
                    }
                }
            }
        }
    }
    
    private func transition(to newState: PlaybackState) {
        self.state = newState
        onStateChange?(newState)
    }
}
