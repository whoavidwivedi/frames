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

nonisolated public final class FrameQueue: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var frames: [VideoToolboxDecoder.DecodedVideoFrame] = []
    private var minimumAcceptedPTS = -Double.infinity
    private var _nominalFrameDuration: Double = 1.0 / 30.0
    public let maxCount: Int
    
    public var nominalFrameDuration: Double {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _nominalFrameDuration
    }
    
    public init(maxCount: Int = 18, nominalFrameDuration: Double = 1.0 / 30.0) {
        self.maxCount = maxCount
        self._nominalFrameDuration = max(0.001, nominalFrameDuration)
    }
    
    public var count: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return frames.count
    }
    
    public func setNominalFrameDuration(_ duration: Double) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        if duration > 0.001 {
            self._nominalFrameDuration = duration
        }
    }
    
    public func enqueue(_ frame: VideoToolboxDecoder.DecodedVideoFrame) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard frame.pts >= minimumAcceptedPTS else { return }

        // Dynamically track nominal frame duration if reported by frame or consecutive delta
        if frame.duration > 0.001 && abs(_nominalFrameDuration - (1.0 / 30.0)) < 0.0001 {
            _nominalFrameDuration = frame.duration
        } else if let last = frames.last, abs(_nominalFrameDuration - (1.0 / 30.0)) < 0.0001 {
            let delta = frame.pts - last.pts
            if delta > 0.001 && delta < 0.25 {
                _nominalFrameDuration = delta
            }
        }

        // Fast path for monotonic presentation order
        if let last = frames.last, frame.pts >= last.pts {
            frames.append(frame)
        } else if let idx = frames.firstIndex(where: { $0.pts > frame.pts }) {
            frames.insert(frame, at: idx)
        } else {
            frames.append(frame)
        }

        // Discard from tail only if significantly beyond capacity to preserve upcoming display frames
        let hardLimit = maxCount + 16
        if frames.count > hardLimit {
            frames.removeLast(frames.count - hardLimit)
        }
    }
    
    public func firstFrame() -> CVPixelBuffer? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return frames.first?.pixelBuffer
    }
    
    public func frameClosest(to targetPTS: Double) -> (buffer: CVPixelBuffer, pts: Double)? {
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
    
    public func dequeueNext(forMasterClock masterClock: Double, frameDuration: Double? = nil) -> (buffer: CVPixelBuffer, pts: Double)? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let duration = (frameDuration ?? _nominalFrameDuration) > 0.001 ? (frameDuration ?? _nominalFrameDuration) : (1.0 / 30.0)
        let lagThreshold = max(0.033, 2.0 * duration)
        
        // Discard stale frames lagging behind masterClock by more than dynamic frame-rate-aware threshold
        while frames.count > 1 && frames[0].pts < masterClock - lagThreshold {
            frames.removeFirst()
        }
        guard let candidate = frames.first else { return nil }
        // Deliver frame if due within dynamic display cadence window (scaled for high refresh rates)
        let deliveryTolerance = min(0.020, max(0.005, duration * 0.75))
        if candidate.pts <= masterClock + deliveryTolerance {
            frames.removeFirst()
            return (candidate.pixelBuffer, candidate.pts)
        }
        return nil
    }
    
    public func removeAll() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        frames.removeAll()
    }

    public func reset(forSeek target: Double) {
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
    public var onSubtitleCue: (@MainActor @Sendable (SubtitleCue) -> Void)?
    
    // Decoded Frame Ring Buffer & Scrub Frame Cache
    private let frameQueue = FrameQueue(maxCount: 18)
    private let scrubCache = ScrubFrameCache(maxCapacity: 48)
    private let packetChunkBuffer = PacketChunkBuffer(maxCapacity: 256)
    private var lastReportedUIClock: Double = -1.0
    private var nominalFrameDuration: Double = 1.0 / 30.0
    
    public var currentNominalFrameDuration: Double {
        nominalFrameDuration
    }
    public var scrubCacheCapacity: Int {
        scrubCache.maxCapacity
    }
    
    // Concurrency & Feeder Task
    private let seekToken = SeekToken()
    private var feederTask: Task<Void, Never>?
    private var scrubTask: Task<Void, Never>?
    private var pendingScrubTarget: Double?
    private var isScrubbingActive: Bool = false
    private var scrubGeneration = 0
    private var scrubResumeOnExit = false
    private var audioSwitchTask: Task<Void, Never>?
    private var pendingAudioTrackNumber: UInt64?
    private var isPlaying = false
    private var playbackStartTime: CFTimeInterval = 0
    private var playbackStartPts: Double = 0
    private var lastAudioClock: Double = -1
    private var lastAudioClockDate: CFTimeInterval = 0
    private var audioClockStalled = false
    
    // Callbacks
    public var onTimeUpdate: (@MainActor @Sendable (Double) -> Void)?
    public var onStateChange: (@MainActor @Sendable (PlaybackState) -> Void)?
    public var onPlaybackEnded: (@MainActor @Sendable () -> Void)?
    
    // MARK: - Lifecycle
    
    public init() {
        self.renderer = MetalVideoRenderer()
    }
    
    deinit {
        feederTask?.cancel()
        scrubTask?.cancel()
        audioEngine?.stop()
        videoDecoder?.invalidate()
    }
    
    // MARK: - Load File
    
    /// Opens and prepares a media file for native zero-copy playback synchronously.
    @discardableResult
    public func loadSync(url: URL) -> Bool {
        stop()
        resetClockTracker()
        
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
            
            // Resolution-aware scrub cache scaling
            let trackWidth = vTrack.pixelWidth > 0 ? vTrack.pixelWidth : vTrack.displayWidth
            let trackHeight = vTrack.pixelHeight > 0 ? vTrack.pixelHeight : vTrack.displayHeight
            if trackWidth > 0 && trackHeight > 0 {
                scrubCache.updateCapacity(forWidth: trackWidth, height: trackHeight)
            } else if let dims = decoder.videoDimensions, dims.width > 0 && dims.height > 0 {
                scrubCache.updateCapacity(forWidth: dims.width, height: dims.height)
            }
            
            // Frame-rate aware nominal cadence configuration
            let nominalDuration: Double
            if let defaultDur = vTrack.defaultDurationNs, defaultDur > 0 {
                nominalDuration = Double(defaultDur) / 1_000_000_000.0
            } else if let fps = vTrack.estimatedFPS, fps > 0 {
                nominalDuration = 1.0 / fps
            } else {
                nominalDuration = 1.0 / 30.0
            }
            self.nominalFrameDuration = nominalDuration
            self.frameQueue.setNominalFrameDuration(nominalDuration)
            
            let q = self.frameQueue
            let cache = self.scrubCache
            decoder.setFrameHandler { frame in
                let w = CVPixelBufferGetWidth(frame.pixelBuffer)
                let h = CVPixelBufferGetHeight(frame.pixelBuffer)
                if w > 0 && h > 0 {
                    cache.updateCapacity(forWidth: w, height: h)
                }
                cache.insert(buffer: frame.pixelBuffer, pts: frame.pts)
                q.enqueue(frame)
            }
            self.videoDecoder = decoder
            
            // 3. Select primary audio track & setup CoreAudio engine
            let pref = SettingsManager.shared.defaultAudioLanguage
            let preferredAudio: DemuxedTrack? = {
                if pref == "System" {
                    let sysLang = Locale.current.language.languageCode?.identifier ?? "en"
                    let sysName = LanguageHelper.displayName(for: sysLang).lowercased()
                    return d.audioTracks.first {
                        let name = LanguageHelper.displayName(for: $0.language).lowercased()
                        return name == sysName || $0.language?.lowercased() == sysLang
                    }
                } else if pref == "Original" {
                    return d.audioTracks.first(where: { $0.isDefault }) ?? d.audioTracks.first
                } else {
                    let prefLower = pref.lowercased()
                    return d.audioTracks.first {
                        let name = LanguageHelper.displayName(for: $0.language).lowercased()
                        return name == prefLower || $0.language?.lowercased() == prefLower || ($0.name?.lowercased().contains(prefLower) ?? false)
                    }
                }
            }()
            let defaultAudio = preferredAudio ?? (d.audioTracks.first(where: { $0.isDefault }) ?? d.audioTracks.first)
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

        // Switching back to the track that is still active cancels any in-flight switch.
        if activeAudioTrackNumber == trackNumber {
            pendingAudioTrackNumber = nil
            audioSwitchTask?.cancel()
            audioSwitchTask = nil
            return
        }
        guard pendingAudioTrackNumber != trackNumber else { return }

        let previousTrackNumber = activeAudioTrackNumber
        let previousVolume = audioEngine?.currentVolume ?? 1.0
        pendingAudioTrackNumber = trackNumber

        audioSwitchTask?.cancel()
        // AVAudioEngine setup/start can block for hundreds of milliseconds. Build the
        // replacement engine off the main thread and keep the old one playing until ready.
        audioSwitchTask = Task.detached(priority: .userInitiated) { [weak self] in
            let newEngine = AudioEngineBridge(track: track)
            guard !Task.isCancelled else {
                newEngine?.stop()
                return
            }
            await MainActor.run { [weak self] in
                guard let self else {
                    newEngine?.stop()
                    return
                }
                guard self.pendingAudioTrackNumber == trackNumber else {
                    newEngine?.stop()
                    return
                }
                self.pendingAudioTrackNumber = nil
                guard let newEngine else {
                    self.activeAudioTrackNumber = previousTrackNumber
                    return
                }

                newEngine.setVolume(previousVolume)
                let resumeTime = self.currentPlaybackTime()
                let oldEngine = self.audioEngine
                self.audioEngine = newEngine
                self.activeAudioTrackNumber = trackNumber
                self.routing.updateAudio(engine: newEngine, trackNumber: trackNumber)
                self.resetClockTracker()
                newEngine.seek(to: resumeTime)
                if self.isPlaying {
                    newEngine.play()
                }
                if let oldEngine {
                    Task.detached(priority: .utility) {
                        oldEngine.stop()
                    }
                }
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
        
        isScrubbingActive = false
        pendingScrubTarget = nil
        // A scrub worker may still own the demuxer for a few milliseconds. Let it
        // finish and hand off to the feeder instead of racing it.
        let scrubInFlight = scrubTask != nil
        scrubResumeOnExit = scrubInFlight
        
        isPlaying = true
        playbackStartTime = CACurrentMediaTime()
        playbackStartPts = currentTime
        resetClockTracker()
        audioEngine?.play()
        transition(to: .playing)
        
        if !scrubInFlight {
            startFeederTask(demuxer: demuxer, targetSeekTime: nil, generation: gen)
        }
    }
    
    public func pause() {
        guard case .playing = state else { return }
        
        let finalTime = currentPlaybackTime()
        isPlaying = false
        isScrubbingActive = false
        pendingScrubTarget = nil
        scrubResumeOnExit = false
        scrubTask?.cancel()
        scrubTask = nil
        currentTime = min(duration > 0 ? duration : Double.infinity, finalTime)
        audioEngine?.pause()
        feederTask?.cancel()
        feederTask = nil
        transition(to: .paused)
    }
    
    public func stop() {
        isPlaying = false
        isScrubbingActive = false
        pendingScrubTarget = nil
        scrubResumeOnExit = false
        scrubTask?.cancel()
        scrubTask = nil
        audioSwitchTask?.cancel()
        audioSwitchTask = nil
        pendingAudioTrackNumber = nil
        feederTask?.cancel()
        feederTask = nil
        lastReportedUIClock = -1.0
        resetClockTracker()
        
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
        
        if isScrubbing {
            isScrubbingActive = true
            scrubResumeOnExit = false
            pendingScrubTarget = time
            currentTime = time
            onTimeUpdate?(time)

            // 1. Instant scrub cache check: if frame was recently decoded, display immediately
            if let cached = scrubCache.getFrame(forTargetPTS: time, tolerance: 0.50) ?? scrubCache.nearestFrame(to: time) {
                renderer?.updateFrame(cached.buffer)
            }

            // 2. Continuous dedicated scrubbing loop (coalesces high-frequency slider drag events)
            if scrubTask == nil {
                startScrubTask(demuxer: demuxer)
            }
            return
        }

        // Discrete timeline click or explicit seek
        isScrubbingActive = false
        pendingScrubTarget = nil
        scrubResumeOnExit = false
        scrubTask?.cancel()
        scrubTask = nil

        feederTask?.cancel()
        feederTask = nil
        
        frameQueue.reset(forSeek: time)
        packetChunkBuffer.removeAll()
        videoDecoder?.flush()
        audioEngine?.seek(to: time)
        
        // O(log N) binary search seek in Matroska index (prioritizing video keyframe cues)
        lastReportedUIClock = -1.0
        resetClockTracker()
        demuxer.seek(to: time)
        playbackStartTime = CACurrentMediaTime()
        playbackStartPts = time
        currentTime = time
        onTimeUpdate?(time)

        if let cached = scrubCache.getFrame(forTargetPTS: time, tolerance: 0.35) {
            renderer?.updateFrame(cached.buffer)
        }
        
        // Immediately restart feeder loop (continuous if playing, precision GOP preroll if paused/scrubbing)
        startFeederTask(demuxer: demuxer, targetSeekTime: isPlaying ? nil : time, generation: gen)
    }

    /// Ends a scrub gesture without seeking a second time. The scrub worker is
    /// already positioned at the displayed frame; playback hands off from there.
    public func endScrubbing() {
        guard isScrubbingActive || scrubTask != nil else { return }
        isScrubbingActive = false
        pendingScrubTarget = nil
        scrubResumeOnExit = true

        // Audio was paused before the gesture started; line it up with the frame on screen.
        audioEngine?.seek(to: currentTime)
        resetClockTracker()
        playbackStartTime = CACurrentMediaTime()
        playbackStartPts = currentTime

        if scrubTask == nil {
            scrubResumeOnExit = false
        }
    }

    private func scrubTaskDidExit(generation: Int) {
        guard generation == scrubGeneration else { return }
        scrubTask = nil
        guard scrubResumeOnExit else { return }
        scrubResumeOnExit = false
        guard isPlaying, let demuxer = demuxer else { return }
        frameQueue.reset(forSeek: currentTime)
        startFeederTask(demuxer: demuxer, targetSeekTime: nil, generation: seekToken.next())
    }

    // MARK: - Dedicated Scrubbing Worker (Ultra-Smooth Apple Silicon Native Scrub)

    private func startScrubTask(demuxer: MatroskaDemuxer) {
        scrubTask?.cancel()
        scrubGeneration &+= 1
        let generation = scrubGeneration
        
        let decoder = self.videoDecoder
        let cache = self.scrubCache
        let renderer = self.renderer
        
        scrubTask = Task.detached(priority: .userInitiated) { [weak self, weak demuxer] in
            guard let demuxer else { return }
            
            while !Task.isCancelled {
                let target = await MainActor.run { [weak self] () -> Double? in
                    guard let self, self.isScrubbingActive else { return nil }
                    let t = self.pendingScrubTarget
                    self.pendingScrubTarget = nil
                    return t
                }
                
                guard let targetPTS = target else {
                    let stillActive = await MainActor.run { [weak self] in self?.isScrubbingActive ?? false }
                    if !stillActive { break }
                    try? await Task.sleep(nanoseconds: 8_000_000) // 8ms poll for next scrub movement
                    continue
                }
                
                // Jump directly to the nearest keyframe cluster in O(log N) time
                demuxer.seek(to: targetPTS)
                
                guard let dec = decoder else { continue }
                
                var packetsRead = 0
                var foundKeyframe = false
                var keyframePTS: Double = targetPTS
                
                // Read until first keyframe in cluster
                while packetsRead < 45 && !Task.isCancelled {
                    guard let packet = try? demuxer.nextPacket() else { break }
                    packetsRead += 1
                    
                    if packet.trackNumber == dec.track.trackNumber {
                        if packet.isKeyframe {
                            keyframePTS = packet.pts
                            _ = dec.decode(packet: packet, doNotOutput: false)
                            foundKeyframe = true
                            break
                        }
                    }
                }
                
                guard foundKeyframe, !Task.isCancelled else { continue }
                dec.waitForFrames()
                
                // Deliver keyframe to Metal 3 canvas immediately (120fps direct presentation)
                if let matched = cache.getFrame(forTargetPTS: keyframePTS, tolerance: 1.0) ?? cache.nearestFrame(to: targetPTS) {
                    renderer?.updateFrame(matched.buffer)
                }
                
                // If cursor paused briefly on this position, progressively refine up to targetPTS (max 12 frames)
                let hasNewTarget = await MainActor.run { [weak self] in (self?.pendingScrubTarget != nil) || !(self?.isScrubbingActive ?? false) }
                if !hasNewTarget && targetPTS > keyframePTS + 0.04 {
                    var refinedPackets = 0
                    while refinedPackets < 15 && !Task.isCancelled {
                        let hasInterrupted = await MainActor.run { [weak self] in
                            (self?.pendingScrubTarget != nil) || !(self?.isScrubbingActive ?? false)
                        }
                        if hasInterrupted { break }
                        guard let packet = try? demuxer.nextPacket() else { break }
                        refinedPackets += 1
                        if packet.trackNumber == dec.track.trackNumber {
                            _ = dec.decode(packet: packet, doNotOutput: false)
                            if packet.pts >= targetPTS + 0.08 { break }
                        }
                    }
                    dec.waitForFrames()
                    if let exactMatched = cache.getFrame(forTargetPTS: targetPTS, tolerance: 0.35) {
                        renderer?.updateFrame(exactMatched.buffer)
                    }
                }
                
                await Task.yield()
            }
            await MainActor.run { [weak self] in
                self?.scrubTaskDidExit(generation: generation)
            }
        }
    }
    
    public func setVolume(_ volume: Float) {
        audioEngine?.setVolume(volume)
    }
    
    // MARK: - Frame Delivery for CADisplayLink
    
    /// Called by the 120Hz CADisplayLink to acquire the current frame matching the display cadence.
    public func nextFrameForDisplay() -> CVPixelBuffer? {
        let masterClock: Double
        if isPlaying {
            masterClock = currentPlaybackTime()

            // Throttle UI property changes and notifications to ~20Hz (every 50ms) to avoid SwiftUI invalidation floods
            if abs(masterClock - lastReportedUIClock) >= 0.048 {
                lastReportedUIClock = masterClock
                currentTime = masterClock
                onTimeUpdate?(masterClock)
            }

            if duration > 0 && masterClock >= duration {
                isPlaying = false
                audioEngine?.pause()
                feederTask?.cancel()
                feederTask = nil
                transition(to: .paused)
                onPlaybackEnded?()
                return nil
            }
        } else {
            masterClock = currentTime
        }
        
        guard let (frame, _) = frameQueue.dequeueNext(forMasterClock: masterClock, frameDuration: nominalFrameDuration) else {
            return nil
        }
        
        return frame
    }

    private func resetClockTracker() {
        lastAudioClock = -1
        lastAudioClockDate = 0
        audioClockStalled = false
    }

    /// Master clock synchronization: Audio Hardware DAC clock takes precedence, with high-precision monotonic clock fallback.
    private func currentPlaybackTime() -> Double {
        guard isPlaying else { return currentTime }

        let now = CACurrentMediaTime()
        let wallClock = playbackStartPts + (now - playbackStartTime) * Double(playbackRate)
        let audioClock = routing.currentAudioEngine?.currentMasterTime ?? -1

        guard audioClock > 0.05 else { return wallClock }
        // Once the hardware clock stalls it is not trustworthy for this playback session;
        // stay on wall time until the next seek/switch re-anchors it.
        if audioClockStalled { return wallClock }

        if audioClock > lastAudioClock + 0.0005 {
            lastAudioClock = audioClock
            lastAudioClockDate = now
            return audioClock
        }
        if audioClock < lastAudioClock - 0.5 {
            // Clock jumped (seek / engine swap): re-anchor to the new value.
            lastAudioClock = audioClock
            lastAudioClockDate = now
            return audioClock
        }
        if now - lastAudioClockDate > 0.25 {
            audioClockStalled = true
            return wallClock
        }
        return audioClock
    }
    
    // MARK: - Dedicated Feeder Task
    
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
                var videoKeyframesDecoded = 0
                
                while isCurrentGen() && !targetFrameFound && packetsRead < maxPackets {
                    guard let packet = try? demuxer.nextPacket() else { break }
                    packetsRead += 1
                    
                    if let dec = decoder, packet.trackNumber == dec.track.trackNumber {
                        if packet.isKeyframe {
                            videoKeyframesDecoded += 1
                            packetBuffer.recordGOP(keyframePTS: packet.pts, fileOffset: packet.fileOffset)
                            if videoKeyframesDecoded > 1 {
                                targetFrameFound = true
                                break
                            }
                        }

                        // Decode frame normally so VideoToolbox ASIC populates reference frames and decoded image
                        _ = dec.decode(packet: packet, doNotOutput: false)
                        
                        // Continue decoding until we pass the target PTS with sufficient margin to resolve any B-frame forward references
                        if packet.pts >= targetPTS + 0.12 {
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
                let videoBuffered = q.count >= q.maxCount
                let audioHasHeadroom = routing.currentAudioEngine?.hasBufferHeadroom ?? true
                let audioBuffered = !audioHasHeadroom

                // Throttle feeding if decoded frame queue and audio buffer have sufficient headroom
                if videoBuffered && audioBuffered {
                    try? await Task.sleep(nanoseconds: 15_000_000) // 15ms sleep
                    continue
                }

                // If video queue is full, throttle down slightly to allow audio replenishment without CPU spin
                if videoBuffered {
                    try? await Task.sleep(nanoseconds: 5_000_000) // 5ms sleep
                }

                guard isCurrentGen() else { break }

                // Fetch next demuxed packet from container
                guard let packet = try? demuxer.nextPacket() else {
                    // Container end-of-file reached
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    continue
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
                            if let onSubCue = onSubCue {
                                Task { @MainActor in
                                    onSubCue(cue)
                                }
                            }
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
