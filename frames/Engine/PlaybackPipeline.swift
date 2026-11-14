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

// MARK: - Lock-Free Cache-Aligned SPSC Frame Queue (128-byte Apple Silicon Cache Lines)

nonisolated public final class FrameQueue: @unchecked Sendable {
    // Apple Silicon M-series L1/L2 cache line size is 128 bytes
    private static let cacheLineSize = 128
    private static let ringCapacity = 256
    private static let ringMask = 255
    
    // Aligned ring buffer storage (256 slots)
    private let rawStorage: UnsafeMutableRawPointer
    private let storage: UnsafeMutablePointer<VideoToolboxDecoder.DecodedVideoFrame?>
    
    // Separate 128-byte cache lines for Producer and Consumer to eliminate false sharing:
    // Offset 0..<128:   PRODUCER CACHE LINE (head: UInt64, lastPTS: Double, cachedTail: UInt64)
    // Offset 128..<256: CONSUMER CACHE LINE (tail: UInt64, cachedHead: UInt64)
    private let rawControl: UnsafeMutableRawPointer
    private let producerHead: UnsafeMutablePointer<UInt64>
    private let producerLastPTS: UnsafeMutablePointer<Double>
    private let producerCachedTail: UnsafeMutablePointer<UInt64>
    
    private let consumerTail: UnsafeMutablePointer<UInt64>
    private let consumerCachedHead: UnsafeMutablePointer<UInt64>
    
    private var queueLock = os_unfair_lock()
    private var configLock = os_unfair_lock()
    private var baseMaxCount: Int
    private var customMaxCount: Int? = nil
    private var _nominalFrameDuration: Double = 1.0 / 30.0
    private var minimumAcceptedPTS = -Double.infinity
    
    public var onHeadroomAvailable: (@Sendable () -> Void)?
    
    public var maxCount: Int {
        os_unfair_lock_lock(&configLock)
        defer { os_unfair_lock_unlock(&configLock) }
        return dynamicCapacityLocked
    }
    
    private var dynamicCapacityLocked: Int {
        if let custom = customMaxCount {
            return custom
        }
        // Dynamic temporal headroom scaling:
        // 120fps (duration <= 0.009s): scale to 48 frames (~400ms buffer)
        // 60fps (duration <= 0.018s): scale to 32 frames (~530ms buffer)
        // <= 30fps: baseMaxCount (default 18, ~600ms buffer)
        if _nominalFrameDuration <= 0.009 {
            return max(baseMaxCount, 48)
        } else if _nominalFrameDuration <= 0.018 {
            return max(baseMaxCount, 32)
        } else {
            return baseMaxCount
        }
    }
    
    public var nominalFrameDuration: Double {
        os_unfair_lock_lock(&configLock)
        defer { os_unfair_lock_unlock(&configLock) }
        return _nominalFrameDuration
    }
    
    public init(maxCount: Int = 18, nominalFrameDuration: Double = 1.0 / 30.0) {
        self.baseMaxCount = maxCount
        self._nominalFrameDuration = max(0.001, nominalFrameDuration)
        
        var sPtr: UnsafeMutableRawPointer? = nil
        let stride = MemoryLayout<VideoToolboxDecoder.DecodedVideoFrame?>.stride
        posix_memalign(&sPtr, Self.cacheLineSize, Self.ringCapacity * stride)
        self.rawStorage = sPtr!
        self.storage = rawStorage.bindMemory(to: VideoToolboxDecoder.DecodedVideoFrame?.self, capacity: Self.ringCapacity)
        self.storage.initialize(repeating: nil, count: Self.ringCapacity)
        
        var cPtr: UnsafeMutableRawPointer? = nil
        posix_memalign(&cPtr, Self.cacheLineSize, 256)
        self.rawControl = cPtr!
        
        // Cache Line 0 (Producer: bytes 0..<128)
        self.producerHead = rawControl.advanced(by: 0).bindMemory(to: UInt64.self, capacity: 1)
        self.producerHead.initialize(to: 0)
        self.producerLastPTS = rawControl.advanced(by: 8).bindMemory(to: Double.self, capacity: 1)
        self.producerLastPTS.initialize(to: 0.0)
        self.producerCachedTail = rawControl.advanced(by: 16).bindMemory(to: UInt64.self, capacity: 1)
        self.producerCachedTail.initialize(to: 0)
        
        // Cache Line 1 (Consumer: bytes 128..<256)
        self.consumerTail = rawControl.advanced(by: 128).bindMemory(to: UInt64.self, capacity: 1)
        self.consumerTail.initialize(to: 0)
        self.consumerCachedHead = rawControl.advanced(by: 136).bindMemory(to: UInt64.self, capacity: 1)
        self.consumerCachedHead.initialize(to: 0)
    }
    
    deinit {
        removeAll()
        storage.deinitialize(count: Self.ringCapacity)
        free(rawStorage)
        free(rawControl)
    }
    
    public var count: Int {
        os_unfair_lock_lock(&queueLock)
        defer { os_unfair_lock_unlock(&queueLock) }
        let head = producerHead.pointee
        let tail = consumerTail.pointee
        return head >= tail ? Int(head - tail) : 0
    }
    
    public func setNominalFrameDuration(_ duration: Double) {
        os_unfair_lock_lock(&configLock)
        defer { os_unfair_lock_unlock(&configLock) }
        if duration > 0.001 {
            self._nominalFrameDuration = duration
        }
    }
    
    public func setMaxCount(_ newMax: Int) {
        os_unfair_lock_lock(&configLock)
        defer { os_unfair_lock_unlock(&configLock) }
        if newMax > 0 {
            self.customMaxCount = newMax
        }
    }
    
    public func configureBuffering(isNetworkOrNAS: Bool, bitrate: Double = 0) {
        os_unfair_lock_lock(&configLock)
        defer { os_unfair_lock_unlock(&configLock) }
        if isNetworkOrNAS || bitrate > 30_000_000 {
            if _nominalFrameDuration <= 0.009 {
                self.customMaxCount = 64
            } else if _nominalFrameDuration <= 0.018 {
                self.customMaxCount = 48
            } else {
                self.customMaxCount = 32
            }
        } else {
            self.customMaxCount = nil
        }
    }
    
    public func enqueue(_ frame: VideoToolboxDecoder.DecodedVideoFrame) {
        os_unfair_lock_lock(&configLock)
        let minPTS = minimumAcceptedPTS
        let nominal = _nominalFrameDuration
        os_unfair_lock_unlock(&configLock)
        
        guard frame.pts >= minPTS else { return }
        
        os_unfair_lock_lock(&queueLock)
        defer { os_unfair_lock_unlock(&queueLock) }
        
        let head = producerHead.pointee
        let tail = consumerTail.pointee
        
        // Dynamically track nominal frame duration if reported by frame
        if frame.duration > 0.001 && abs(nominal - (1.0 / 30.0)) < 0.0001 {
            os_unfair_lock_lock(&configLock)
            _nominalFrameDuration = frame.duration
            os_unfair_lock_unlock(&configLock)
        }
        producerLastPTS.pointee = frame.pts
        
        // Handle buffer full condition without mutating consumer state
        if head >= tail + UInt64(Self.ringCapacity) {
            // Buffer is completely full (256 slots). Drop incoming frame to preserve saturation safety.
            return
        }
        
        // PTS monotonic insertion: maintain queue strictly sorted by presentation timestamp (PTS)
        // to cleanly handle out-of-order decode order (B-frames) emitted by VideoToolbox.
        var insertIndex = head
        while insertIndex > tail {
            let prevSlot = Int((insertIndex - 1) & UInt64(Self.ringMask))
            guard let prevFrame = storage[prevSlot] else { break }
            if prevFrame.pts > frame.pts {
                let targetSlot = Int(insertIndex & UInt64(Self.ringMask))
                storage[targetSlot] = prevFrame
                insertIndex -= 1
            } else {
                break
            }
        }
        
        let slot = Int(insertIndex & UInt64(Self.ringMask))
        storage[slot] = frame
        
        // In sorted display order, derive accurate frame cadence from adjacent frames
        if frame.duration <= 0.001 && abs(nominal - (1.0 / 30.0)) < 0.0001 {
            if insertIndex > tail {
                let prevSlot = Int((insertIndex - 1) & UInt64(Self.ringMask))
                if let prev = storage[prevSlot] {
                    let delta = frame.pts - prev.pts
                    if delta > 0.005 && delta < 0.25 {
                        os_unfair_lock_lock(&configLock)
                        _nominalFrameDuration = delta
                        os_unfair_lock_unlock(&configLock)
                    }
                }
            } else if insertIndex < head {
                let nextSlot = Int((insertIndex + 1) & UInt64(Self.ringMask))
                if let next = storage[nextSlot] {
                    let delta = next.pts - frame.pts
                    if delta > 0.005 && delta < 0.25 {
                        os_unfair_lock_lock(&configLock)
                        _nominalFrameDuration = delta
                        os_unfair_lock_unlock(&configLock)
                    }
                }
            }
        }
        
        // Release barrier: ensure frame data is visible before publishing new head cursor
        OSMemoryBarrier()
        producerHead.pointee = head + 1
    }
    
    public func firstFrame() -> CVPixelBuffer? {
        os_unfair_lock_lock(&queueLock)
        defer { os_unfair_lock_unlock(&queueLock) }
        let tail = consumerTail.pointee
        let head = producerHead.pointee
        guard head > tail else { return nil }
        let slot = Int(tail & UInt64(Self.ringMask))
        return storage[slot]?.pixelBuffer
    }
    
    public func frameClosest(to targetPTS: Double) -> (buffer: CVPixelBuffer, pts: Double)? {
        os_unfair_lock_lock(&queueLock)
        defer { os_unfair_lock_unlock(&queueLock) }
        let tail = consumerTail.pointee
        let head = producerHead.pointee
        guard head > tail else { return nil }
        
        var bestFrame: VideoToolboxDecoder.DecodedVideoFrame? = nil
        var bestDiff = Double.infinity
        
        var curr = tail
        while curr < head {
            let slot = Int(curr & UInt64(Self.ringMask))
            if let f = storage[slot] {
                let diff = abs(f.pts - targetPTS)
                if diff < bestDiff {
                    bestDiff = diff
                    bestFrame = f
                }
            }
            curr += 1
        }
        
        if let matched = bestFrame {
            return (matched.pixelBuffer, matched.pts)
        }
        return nil
    }
    
    public func dequeueNext(forMasterClock masterClock: Double, frameDuration: Double? = nil) -> (buffer: CVPixelBuffer, pts: Double)? {
        os_unfair_lock_lock(&configLock)
        let nominal = _nominalFrameDuration
        os_unfair_lock_unlock(&configLock)
        
        let duration = (frameDuration ?? nominal) > 0.001 ? (frameDuration ?? nominal) : (1.0 / 30.0)
        let lagThreshold = max(0.033, 2.0 * duration)
        
        var headroomCallback: (@Sendable () -> Void)? = nil
        var result: (buffer: CVPixelBuffer, pts: Double)? = nil
        
        os_unfair_lock_lock(&queueLock)
        
        var tail = consumerTail.pointee
        let head = producerHead.pointee
        
        if head > tail {
            // Discard stale frames lagging behind masterClock by dynamic frame-rate-aware threshold.
            // Since queue is strictly sorted by PTS, we can prune stale frames from the head of the queue.
            var dropped = false
            while (head > tail) && ((head - tail) > 1) {
                let slot = Int(tail & UInt64(Self.ringMask))
                guard let candidate = storage[slot] else { break }
                if candidate.pts < masterClock - lagThreshold {
                    storage[slot] = nil
                    tail += 1
                    dropped = true
                } else {
                    break
                }
            }
            
            if dropped {
                OSMemoryBarrier()
                consumerTail.pointee = tail
                headroomCallback = onHeadroomAvailable
            }
            
            if head > tail {
                let slot = Int(tail & UInt64(Self.ringMask))
                if let candidate = storage[slot] {
                    // Deliver frame if due within dynamic display cadence window
                    let deliveryTolerance = min(0.020, max(0.005, duration * 0.75))
                    if candidate.pts <= masterClock + deliveryTolerance {
                        storage[slot] = nil
                        OSMemoryBarrier()
                        consumerTail.pointee = tail + 1
                        headroomCallback = onHeadroomAvailable
                        result = (candidate.pixelBuffer, candidate.pts)
                    }
                }
            }
        }
        
        os_unfair_lock_unlock(&queueLock)
        
        if let cb = headroomCallback {
            cb()
        }
        
        return result
    }
    
    public func removeAll() {
        var headroomCallback: (@Sendable () -> Void)? = nil
        os_unfair_lock_lock(&queueLock)
        let head = producerHead.pointee
        var curr = consumerTail.pointee
        while curr < head {
            let slot = Int(curr & UInt64(Self.ringMask))
            storage[slot] = nil
            curr += 1
        }
        OSMemoryBarrier()
        consumerTail.pointee = head
        consumerCachedHead.pointee = head
        producerCachedTail.pointee = head
        producerLastPTS.pointee = -1.0
        headroomCallback = onHeadroomAvailable
        os_unfair_lock_unlock(&queueLock)
        
        headroomCallback?()
    }

    public func reset(forSeek target: Double) {
        os_unfair_lock_lock(&configLock)
        minimumAcceptedPTS = target > 0.0 ? max(0.0, target - 0.25) : -Double.infinity
        os_unfair_lock_unlock(&configLock)
        removeAll()
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

// MARK: - POSIX Thread QoS Configuration

@inline(__always)
public func pthread_set_qos_class_np(_ thread: pthread_t, _ qosClass: qos_class_t, _ relativePriority: Int32 = 0) -> Int32 {
    return pthread_set_qos_class_self_np(qosClass, relativePriority)
}

// MARK: - Dedicated E-Core Feeder Thread Controller

nonisolated public final class FeederTaskController: @unchecked Sendable {
    private var _isCancelled: Bool = false
    private var cancelLock = os_unfair_lock()
    private let semaphore = DispatchSemaphore(value: 0)
    public let generation: Int
    
    init(generation: Int) {
        self.generation = generation
    }
    
    var isCancelled: Bool {
        os_unfair_lock_lock(&cancelLock)
        defer { os_unfair_lock_unlock(&cancelLock) }
        return _isCancelled
    }
    
    func cancel() {
        os_unfair_lock_lock(&cancelLock)
        _isCancelled = true
        os_unfair_lock_unlock(&cancelLock)
        semaphore.signal()
    }
    
    func signalHeadroom() {
        semaphore.signal()
    }
    
    func waitForHeadroom(timeoutMs: Int = 50) {
        // Drain any stale accumulated signals from unblocked dequeues so we actually sleep for new headroom
        while semaphore.wait(timeout: .now()) == .success {}
        guard !isCancelled else { return }
        _ = semaphore.wait(timeout: .now() + .milliseconds(timeoutMs))
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
    public private(set) var demuxer: (any MediaDemuxer)?
    public var matroskaDemuxer: MatroskaDemuxer? { demuxer as? MatroskaDemuxer }
    public var mp4Demuxer: MP4Demuxer? { demuxer as? MP4Demuxer }
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
    public var isHardwareAccelerated: Bool {
        videoDecoder?.isHardwareAccelerated ?? false
    }
    public var decoderImplementationName: String {
        videoDecoder?.decoderImplementationName ?? "VideoToolbox"
    }
    @Published public private(set) var activeAudioTrackNumber: UInt64?
    @Published public private(set) var activeSubtitleTrackNumber: UInt64?
    public var onSubtitleCue: (@MainActor @Sendable (SubtitleCue) -> Void)?

    public enum ContainerType: Sendable {
        case matroska
        case mp4
    }

    public nonisolated static func probeContainerType(at url: URL) -> ContainerType {
        // 1. Sniff magic bytes
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let header = handle.readData(ofLength: 16)
            if header.count >= 4 {
                // EBML Header: 0x1A 0x45 0xDF 0xA3
                if header[0] == 0x1A && header[1] == 0x45 && header[2] == 0xDF && header[3] == 0xA3 {
                    return .matroska
                }
                // ISO BMFF: bytes 4..<8 are 'ftyp', 'moov', 'wide', 'mdat', 'free', 'skip', 'styp'
                if header.count >= 8 {
                    let fourCC = String(decoding: header[4..<8], as: UTF8.self)
                    if ["ftyp", "moov", "wide", "mdat", "free", "skip", "styp"].contains(fourCC) {
                        return .mp4
                    }
                }
            }
        }

        // 2. Fallback to path extension
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "m4v", "m4a", "3gp", "3g2"].contains(ext) {
            return .mp4
        }
        return .matroska
    }

    // MARK: - Container Verification & Probing

    /// Determines whether the native pipeline (MatroskaDemuxer or MP4Demuxer) can demux this container.
    public static func isSupportedContainer(at url: URL) -> Bool {
        // 1. Sniff magic bytes for EBML or ISO BMFF signatures
        if url.isFileURL,
           let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
           values.isRegularFile == true,
           let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let header = handle.readData(ofLength: 16)
            if header.count >= 4 {
                // EBML Header: 0x1A 0x45 0xDF 0xA3
                if header[0] == 0x1A && header[1] == 0x45 && header[2] == 0xDF && header[3] == 0xA3 {
                    return true
                }
                // ISO BMFF: bytes 4..<8 are 'ftyp', 'moov', 'wide', 'mdat', 'free', 'skip', 'styp'
                if header.count >= 8 {
                    let fourCC = String(decoding: header[4..<8], as: UTF8.self)
                    if ["ftyp", "moov", "wide", "mdat", "free", "skip", "styp"].contains(fourCC) {
                        return true
                    }
                }
            }
        }

        // 2. Check known container extensions
        let ext = url.pathExtension.lowercased()
        return ["mkv", "webm", "mka", "mp4", "mov", "m4v", "m4a", "3gp", "3g2"].contains(ext)
    }
    
    // Decoded Frame Ring Buffer & Scrub Frame Cache
    public let frameQueue = FrameQueue(maxCount: 18)
    private let scrubCache = ScrubFrameCache(maxCapacity: 48)
    public let packetChunkBuffer = PacketChunkBuffer(maxCapacity: 256)
    private var lastReportedUIClock: Double = -1.0
    public private(set) var nominalFrameDuration: Double = 1.0 / 30.0
    
    public var currentNominalFrameDuration: Double {
        nominalFrameDuration
    }
    public var scrubCacheCapacity: Int {
        scrubCache.maxCapacity
    }
    
    // Concurrency & Feeder Task
    private let seekToken = SeekToken()
    private let feederQueue = DispatchQueue(label: "com.frames.playback.feeder", qos: .utility)
    public private(set) var feederTask: FeederTaskController?
    public private(set) var scrubTask: Task<Void, Never>?
    private var pendingScrubTarget: Double?
    private var isScrubbingActive: Bool = false
    private var scrubGeneration = 0
    private var scrubResumeOnExit = false
    private var scrubResiduePending: Bool = false
    private var audioSwitchTask: Task<Void, Never>?
    private var pendingAudioTrackNumber: UInt64?
    private var loadToken: UInt64 = 0
    private var isPlaying = false
    private var playbackStartTime: CFTimeInterval = 0
    private var playbackStartPts: Double = 0
    private var lastAudioClock: Double = -1
    private var lastAudioClockDate: CFTimeInterval = 0
    private var audioClockStalled = false

    // Demuxer Stream End Tracking
    private var eofLock = os_unfair_lock()
    private var _isDemuxerEOF: Bool = false
    public var isDemuxerEOF: Bool {
        get {
            os_unfair_lock_lock(&eofLock)
            defer { os_unfair_lock_unlock(&eofLock) }
            return _isDemuxerEOF
        }
        set {
            os_unfair_lock_lock(&eofLock)
            _isDemuxerEOF = newValue
            os_unfair_lock_unlock(&eofLock)
        }
    }
    
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

    public enum PlaybackLoadError: LocalizedError {
        case demuxFailed(Error)
        case decoderUnavailable

        public var errorDescription: String? {
            switch self {
            case .demuxFailed(let error):
                return "Failed to demux container: \(error.localizedDescription)"
            case .decoderUnavailable:
                return "Failed to initialize VideoToolbox hardware decoder"
            }
        }
    }

    /// Demuxer + decoder + audio engine built off the main actor, then installed in one hop.
    public struct PreparedPlayback: @unchecked Sendable {
        let demuxer: any MediaDemuxer
        let decoder: VideoToolboxDecoder
        let audioEngine: AudioEngineBridge?
        let audioTrackNumber: UInt64?
    }

    /// Opens the container, spins up VideoToolbox and CoreAudio. Blocking work, safe off-main.
    nonisolated static func prepare(url: URL, preferredAudioLanguage pref: String, playbackRate: Float) throws -> PreparedPlayback {
        let containerType = probeContainerType(at: url)
        let demuxer: any MediaDemuxer
        do {
            if containerType == .mp4 {
                do {
                    demuxer = try MP4Demuxer(url: url)
                } catch {
                    demuxer = try MatroskaDemuxer(url: url)
                }
            } else {
                do {
                    demuxer = try MatroskaDemuxer(url: url)
                } catch {
                    demuxer = try MP4Demuxer(url: url)
                }
            }
        } catch {
            throw PlaybackLoadError.demuxFailed(error)
        }

        guard let videoTrack = demuxer.videoTracks.first,
              let decoder = VideoToolboxDecoder(track: videoTrack) else {
            throw PlaybackLoadError.decoderUnavailable
        }

        let audioTrack = preferredAudioTrack(in: demuxer, pref: pref)
        let audioEngine: AudioEngineBridge? = audioTrack.flatMap {
            AudioEngineBridge(track: $0, initialRate: playbackRate)
        }
        return PreparedPlayback(
            demuxer: demuxer,
            decoder: decoder,
            audioEngine: audioEngine,
            audioTrackNumber: audioTrack?.trackNumber
        )
    }

    nonisolated static func preferredAudioTrack(in demuxer: any MediaDemuxer, pref: String) -> DemuxedTrack? {
        if pref == "System" {
            let sysLang = Locale.current.language.languageCode?.identifier ?? "en"
            let sysName = LanguageHelper.displayName(for: sysLang).lowercased()
            return demuxer.audioTracks.first {
                let name = LanguageHelper.displayName(for: $0.language).lowercased()
                return name == sysName || $0.language?.lowercased() == sysLang
            }
        } else if pref == "Original" {
            return demuxer.audioTracks.first(where: { $0.isDefault }) ?? demuxer.audioTracks.first
        } else {
            let prefLower = pref.lowercased()
            return demuxer.audioTracks.first {
                let name = LanguageHelper.displayName(for: $0.language).lowercased()
                return name == prefLower || $0.language?.lowercased() == prefLower || ($0.name?.lowercased().contains(prefLower) ?? false)
            }
        }
    }

    /// Opens and prepares a media file asynchronously; heavy setup never runs on the main actor.
    @discardableResult
    public func load(url: URL) async -> Bool {
        let pref = SettingsManager.shared.defaultAudioLanguage
        let rate = playbackRate
        stopDeferringHeavyTeardown()
        loadToken &+= 1
        let token = loadToken
        resetClockTracker()
        isDemuxerEOF = false
        transition(to: .loading)
        currentURL = url

        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try Self.prepare(url: url, preferredAudioLanguage: pref, playbackRate: rate)
            }.value
            guard token == loadToken else {
                prepared.audioEngine?.stop()
                prepared.decoder.invalidate()
                prepared.demuxer.close()
                return false
            }
            return install(prepared, url: url)
        } catch {
            guard token == loadToken else { return false }
            transition(to: .error(error.localizedDescription))
            return false
        }
    }

    /// Opens and prepares a media file synchronously (tests and callers that cannot await).
    @discardableResult
    public func loadSync(url: URL) -> Bool {
        let pref = SettingsManager.shared.defaultAudioLanguage
        stop()
        loadToken &+= 1
        resetClockTracker()
        self.isDemuxerEOF = false

        transition(to: .loading)
        self.currentURL = url

        do {
            let prepared = try Self.prepare(url: url, preferredAudioLanguage: pref, playbackRate: playbackRate)
            return install(prepared, url: url)
        } catch {
            transition(to: .error(error.localizedDescription))
            return false
        }
    }

    private func install(_ prepared: PreparedPlayback, url: URL) -> Bool {
        let demuxer = prepared.demuxer
        let videoTrack = demuxer.videoTracks.first
        self.demuxer = demuxer
        self.duration = demuxer.duration
        self.videoDecoder = prepared.decoder

        // Resolution-aware scrub cache scaling
        if let videoTrack {
            let trackWidth = videoTrack.pixelWidth > 0 ? videoTrack.pixelWidth : videoTrack.displayWidth
            let trackHeight = videoTrack.pixelHeight > 0 ? videoTrack.pixelHeight : videoTrack.displayHeight
            if trackWidth > 0 && trackHeight > 0 {
                scrubCache.updateCapacity(forWidth: trackWidth, height: trackHeight)
            } else if let dims = prepared.decoder.videoDimensions, dims.width > 0, dims.height > 0 {
                scrubCache.updateCapacity(forWidth: dims.width, height: dims.height)
            }

            // Frame-rate aware nominal cadence configuration
            let nominalDuration: Double
            if let defaultDur = videoTrack.defaultDurationNs, defaultDur > 0 {
                nominalDuration = Double(defaultDur) / 1_000_000_000.0
            } else if let fps = videoTrack.estimatedFPS, fps > 0 {
                nominalDuration = 1.0 / fps
            } else {
                nominalDuration = 1.0 / 30.0
            }
            self.nominalFrameDuration = nominalDuration
            self.frameQueue.setNominalFrameDuration(nominalDuration)
        }

        let isNetworkOrNAS = url.path.hasPrefix("/Volumes/") || url.scheme == "smb" || url.scheme == "afp" || url.scheme == "nfs"
        let estBitrate = (demuxer.duration > 0 && demuxer.fileSize > 0) ? (Double(demuxer.fileSize * 8) / demuxer.duration) : 0.0
        self.frameQueue.configureBuffering(isNetworkOrNAS: isNetworkOrNAS, bitrate: estBitrate)
        self.packetChunkBuffer.setCapacity(isNetworkOrNAS || estBitrate > 30_000_000 ? 512 : 256)

        let q = self.frameQueue
        let cache = self.scrubCache
        prepared.decoder.setFrameHandler { frame in
            let w = CVPixelBufferGetWidth(frame.pixelBuffer)
            let h = CVPixelBufferGetHeight(frame.pixelBuffer)
            if w > 0 && h > 0 {
                cache.updateCapacity(forWidth: w, height: h)
            }
            cache.insert(buffer: frame.pixelBuffer, pts: frame.pts)
            q.enqueue(frame)
        }

        self.audioEngine = prepared.audioEngine
        self.activeAudioTrackNumber = prepared.audioTrackNumber
        if let audio = prepared.audioEngine, let trackNumber = prepared.audioTrackNumber {
            routing.updateAudio(engine: audio, trackNumber: trackNumber)
        } else {
            routing.updateAudio(engine: nil, trackNumber: nil)
        }
        self.activeSubtitleTrackNumber = nil
        routing.updateSubtitle(trackNumber: nil)
        routing.setPlaybackRate(playbackRate)

        transition(to: .paused)
        return true
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
            let currentRate = await MainActor.run { [weak self] in self?.playbackRate ?? 1.0 }
            let newEngine = AudioEngineBridge(track: track, initialRate: currentRate)
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

                // The demuxer reads ahead of the audible position, so the replacement
                // engine would be fed packets from the future and re-anchor the master
                // clock forward (timeline jump). Re-seek so packets resume at the
                // position the listener is actually at; this also positions a switch
                // made while paused for the next play. seek() seeks the new engine too.
                self.seek(to: resumeTime)
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
        let now = CACurrentMediaTime()
        let current = currentPlaybackTime()
        self.playbackRate = clamped
        routing.setPlaybackRate(clamped)
        self.playbackStartPts = current
        self.playbackStartTime = now
        resetClockTracker()
        audioEngine?.setPlaybackRate(clamped)
    }
    
    // MARK: - Playback Control
    
    public func play() {
        guard (state == .paused || state == .idle), let demuxer = demuxer else { return }
        
        let gen = seekToken.next()
        self.isDemuxerEOF = false
        
        let wasScrubbing = isScrubbingActive || scrubResiduePending
        isScrubbingActive = false
        pendingScrubTarget = nil
        // A scrub worker may still own the demuxer for a few milliseconds. Let it
        // finish and hand off to the feeder instead of racing it.
        let scrubInFlight = scrubTask != nil
        scrubResumeOnExit = scrubInFlight
        
        if !scrubInFlight && wasScrubbing {
            frameQueue.reset(forSeek: currentTime)
            packetChunkBuffer.removeAll()
            scrubResiduePending = false
        }
        
        isPlaying = true
        playbackStartTime = CACurrentMediaTime()
        playbackStartPts = currentTime
        resetClockTracker()
        audioEngine?.setPlaybackRate(playbackRate)
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
    
    /// Cleanly terminates playback upon reaching stream EOF or container duration.
    public func markPlaybackEnded() {
        guard isPlaying else { return }
        self.isDemuxerEOF = true
        isPlaying = false
        audioEngine?.pause()
        feederTask?.cancel()
        feederTask = nil
        transition(to: .paused)
        onPlaybackEnded?()
    }
    
    public func stop() {
        let subsystems = resetForStop()
        subsystems?.teardown()
    }

    /// Stops playback and tears down decoders/demuxer off the main thread so UI returns instantly.
    public func stopDeferringHeavyTeardown() {
        guard let subsystems = resetForStop() else { return }
        Task.detached(priority: .userInitiated) {
            subsystems.teardown()
        }
    }

    private struct PlaybackSubsystems: @unchecked Sendable {
        let audioEngine: AudioEngineBridge?
        let videoDecoder: VideoToolboxDecoder?
        let demuxer: (any MediaDemuxer)?

        func teardown() {
            audioEngine?.stop()
            videoDecoder?.invalidate()
            demuxer?.close()
        }
    }

    @discardableResult
    private func resetForStop() -> PlaybackSubsystems? {
        loadToken &+= 1
        isPlaying = false
        self.isDemuxerEOF = false
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

        let subsystems = PlaybackSubsystems(audioEngine: audioEngine, videoDecoder: videoDecoder, demuxer: demuxer)
        audioEngine = nil
        videoDecoder = nil
        demuxer = nil

        frameQueue.removeAll()
        scrubCache.clear()
        packetChunkBuffer.removeAll()
        renderer?.clearFrame()
        currentTime = 0
        transition(to: .stopped)

        guard subsystems.audioEngine != nil || subsystems.videoDecoder != nil || subsystems.demuxer != nil else {
            return nil
        }
        return subsystems
    }
    
    /// Seeks to target timestamp with artifact-free GOP preroll decoding and scrub cache lookup.
    public func seek(to time: Double, isScrubbing: Bool = false) {
        guard let demuxer = demuxer else { return }
        
        let gen = seekToken.next()
        self.isDemuxerEOF = false
        
        // Unconditionally cancel active feeder to eliminate concurrent demuxer reads during scrubbing or seek
        feederTask?.cancel()
        feederTask = nil
        
        if isScrubbing {
            isScrubbingActive = true
            scrubResiduePending = true
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
        scrubResiduePending = false
        pendingScrubTarget = nil
        scrubResumeOnExit = false
        scrubTask?.cancel()
        scrubTask = nil
        
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

    /// Drives the scrub worker to an intermediate target during a programmatic
    /// skip so the video visibly traverses the skipped range.
    public func setScrubTarget(_ time: Double) {
        guard isScrubbingActive else { return }
        let clamped = duration > 0 ? max(0.0, min(time, duration)) : max(0.0, time)
        pendingScrubTarget = clamped
        currentTime = clamped
        onTimeUpdate?(clamped)
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
            frameQueue.reset(forSeek: currentTime)
            packetChunkBuffer.removeAll()
            scrubResiduePending = false
        }
    }

    private func scrubTaskDidExit(generation: Int) {
        guard generation == scrubGeneration else { return }
        scrubTask = nil
        
        // Sanitize frame queue and packet chunk buffer immediately upon scrub task exit
        frameQueue.reset(forSeek: currentTime)
        packetChunkBuffer.removeAll()
        scrubResiduePending = false
        
        guard scrubResumeOnExit else { return }
        scrubResumeOnExit = false
        guard isPlaying, let demuxer = demuxer else { return }
        startFeederTask(demuxer: demuxer, targetSeekTime: nil, generation: seekToken.next())
    }

    // MARK: - Dedicated Scrubbing Worker (Ultra-Smooth Apple Silicon Native Scrub)

    private func startScrubTask(demuxer: any MediaDemuxer) {
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
                    let shouldBreak: Bool = autoreleasepool {
                        guard let packet = try? demuxer.nextPacket() else { return true }
                        packetsRead += 1
                        
                        if packet.trackNumber == dec.track.trackNumber {
                            if packet.isKeyframe {
                                keyframePTS = packet.pts
                                _ = dec.decode(packet: packet, doNotOutput: false)
                                foundKeyframe = true
                                return true
                            }
                        }
                        return false
                    }
                    if shouldBreak { break }
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
                        let reachedEnd: Bool = autoreleasepool {
                            guard let packet = try? demuxer.nextPacket() else { return true }
                            refinedPackets += 1
                            if packet.trackNumber == dec.track.trackNumber {
                                _ = dec.decode(packet: packet, doNotOutput: false)
                                if packet.pts >= targetPTS + 0.08 { return true }
                            }
                            return false
                        }
                        if reachedEnd { break }
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
        return autoreleasepool {
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
                    markPlaybackEnded()
                    return nil
                }
            } else {
                masterClock = currentTime
            }
            
            guard let (frame, _) = frameQueue.dequeueNext(forMasterClock: masterClock, frameDuration: nominalFrameDuration) else {
                if isPlaying && isDemuxerEOF && packetChunkBuffer.isEmpty && frameQueue.count == 0 {
                    markPlaybackEnded()
                }
                return nil
            }
            
            return frame
        }
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
    
    private func startFeederTask(demuxer: any MediaDemuxer, targetSeekTime: Double? = nil, generation: Int) {
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
        
        let controller = FeederTaskController(generation: generation)
        self.feederTask = controller
        
        q.onHeadroomAvailable = { [weak controller] in
            controller?.signalHeadroom()
        }
        
        feederQueue.async { [weak demuxer] in
            _ = pthread_set_qos_class_np(pthread_self(), QOS_CLASS_UTILITY, 0)
            guard let demuxer = demuxer else { return }
            
            func isCurrentGen() -> Bool {
                return token.isCurrent(generation) && !controller.isCancelled
            }
            
            // Mode A: Precision Seek Preroll (Decodes keyframe and intermediate frames up to target PTS)
            if isSingleSeek {
                var packetsRead = 0
                let maxPackets = 450
                var targetFrameFound = false
                var videoKeyframesDecoded = 0
                
                while isCurrentGen() && !targetFrameFound && packetsRead < maxPackets {
                    autoreleasepool {
                        guard let packet = try? demuxer.nextPacket() else {
                            targetFrameFound = true
                            return
                        }
                        packetsRead += 1
                        
                        if let dec = decoder, packet.trackNumber == dec.track.trackNumber {
                            if packet.isKeyframe {
                                videoKeyframesDecoded += 1
                                packetBuffer.recordGOP(keyframePTS: packet.pts, fileOffset: packet.fileOffset)
                                if videoKeyframesDecoded > 1 {
                                    targetFrameFound = true
                                    return
                                }
                            }

                            // Decode frame normally so VideoToolbox ASIC populates reference frames and decoded image
                            _ = dec.decode(packet: packet, doNotOutput: false)
                            
                            // Continue decoding until we pass the target PTS with sufficient margin to resolve any B-frame forward references
                            if packet.pts >= targetPTS + 0.12 {
                                targetFrameFound = true
                            }
                        } else if let subNum = routing.activeSubtitleTrackNumber, packet.trackNumber == subNum {
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
            
            // Mode B: Continuous Streaming Playback with Chunked Packet Prefetching & Backpressure
            while isCurrentGen() {
                let videoBuffered = q.count >= q.maxCount
                let activeAudio = routing.currentAudioEngine
                let audioHasHeadroom = activeAudio?.hasBufferHeadroom ?? false
                let audioBuffered = !audioHasHeadroom

                // Throttle feeding if decoded frame queue and audio buffer have sufficient headroom
                // Also throttle if packetBuffer has accumulated enough deferred video packets
                // Event-based backpressure: sleep until headroom becomes available or cancelled
                if videoBuffered && (audioBuffered || packetBuffer.count >= packetBuffer.maxCapacity) {
                    controller.waitForHeadroom(timeoutMs: 50)
                    continue
                }

                guard isCurrentGen() else { break }

                var shouldSleepAfterEOF = false
                autoreleasepool {
                    // 1. Prioritize deferred video packets if video queue has headroom:
                    // If video has drained below maxCount, decode the next packet from packetBuffer
                    if !videoBuffered, let deferredPacket = packetBuffer.dequeue() {
                        if let dec = decoder {
                            _ = dec.decode(packet: deferredPacket)
                        }
                        return
                    }

                    // 2. Read next packet from container
                    guard let packet = try? demuxer.nextPacket() else {
                        self.isDemuxerEOF = true
                        shouldSleepAfterEOF = true
                        return
                    }

                    // Route packet to hardware video decoder or native audio translation engine
                    let activeAudioNum = routing.activeAudioTrackNumber
                    let activeSubNum = routing.activeSubtitleTrackNumber

                    if let dec = decoder, packet.trackNumber == dec.track.trackNumber {
                        if packet.isKeyframe {
                            packetBuffer.recordGOP(keyframePTS: packet.pts, fileOffset: packet.fileOffset)
                        }
                        // Backpressure: If video is already buffered, defer video decode to prevent
                        // uncompressed CVPixelBuffer memory leak while waiting for audio packets.
                        if videoBuffered {
                            packetBuffer.enqueue(packet)
                        } else {
                            _ = dec.decode(packet: packet)
                        }
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

                if shouldSleepAfterEOF {
                    if packetBuffer.isEmpty && q.count == 0 {
                        Task { @MainActor [weak self] in
                            self?.markPlaybackEnded()
                        }
                        break
                    }
                    controller.waitForHeadroom(timeoutMs: 30)
                }
            }
        }
    }
    
    private func transition(to newState: PlaybackState) {
        self.state = newState
        onStateChange?(newState)
    }
}
