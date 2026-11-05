import Foundation
import AVFoundation
import Combine
import CoreMedia
import SwiftUI

@MainActor
@Observable
public final class VideoPlayerEngine {
    // MARK: - Core Playback State
    public private(set) var player: AVPlayer = AVPlayer()
    public private(set) var currentURL: URL?
    public var isPlaying: Bool = false
    public var isBuffering: Bool = false
    public var hasEnded: Bool = false
    public var onPlaybackEnded: (() -> Void)?
    public var currentTime: Double = 0.0
    public var lastSyncTime: Double = 0.0
    public var lastSyncDate: Date = Date()
    public var duration: Double = 0.0
    public var volume: Float = 1.0 {
        didSet {
            let clamped = min(max(volume, 0.0), 1.0)
            player.volume = isMuted ? 0.0 : clamped
            if isNativePipelineActive {
                nativePipeline.setVolume(isMuted ? 0.0 : clamped)
            }
        }
    }
    public var isMuted: Bool = false {
        didSet {
            player.isMuted = isMuted
            let clamped = isMuted ? 0.0 : min(max(volume, 0.0), 1.0)
            player.volume = clamped
            if isNativePipelineActive {
                nativePipeline.setVolume(clamped)
            }
        }
    }
    public var playbackRate: Float = 1.0 {
        didSet {
            if isPlaying {
                player.rate = playbackRate
            }
        }
    }
    // MARK: - Metadata & Hardware
    public var metadata: VideoMetadata = VideoMetadata()

    // MARK: - Audio & Subtitle Tracks
    public var availableAudioTracks: [AudioTrack] = []
    public var selectedAudioTrack: AudioTrack?

    public var availableSubtitleTracks: [SubtitleTrack] = [SubtitleTrack.off]
    public var selectedSubtitleTrack: SubtitleTrack = SubtitleTrack.off
    public var activeSubtitleText: String = ""
    public var subtitleDelay: Double = 0.0 // in seconds
    public var subtitleFontSize: CGFloat = 22.0

    // MARK: - UI Interaction State
    public var isScrubbing: Bool = false
    public var controlsVisible: Bool = true
    public var isFullscreen: Bool = false
    public var activeInspectorSheet: InspectorSheet? = nil

    // MARK: - Native Metal & Demuxer Pipeline (Zero-Copy Apple Silicon)
    public let nativePipeline = PlaybackPipeline()
    public private(set) var isNativePipelineActive: Bool = false
    public private(set) var playbackError: String?

    public enum InspectorSheet: String, Identifiable {
        case subtitles
        case audio
        case speed
        case stats

        public var id: String { rawValue }
    }

    // MARK: - Private Observers
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var itemDidPlayToEndObserver: NSObjectProtocol?
    private var bufferingTimer: Timer?
    private let securityBox = SecurityScopedBox()
    private var loadGeneration: UInt = 0
    private var pendingInitialSeekTime: Double?

    private func updateBufferingStatus(_ isWaiting: Bool) {
        bufferingTimer?.invalidate()
        bufferingTimer = nil

        if isWaiting {
            // Debounce buffering indicator by 350ms so local file transitions and seeks never flash
            bufferingTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isPlaying else { return }
                    self.isBuffering = true
                }
            }
        } else {
            self.isBuffering = false
        }
    }

    public init() {
        setupTimeObserver()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, let url = self.currentURL, !url.path.isEmpty, self.duration > 0 else { return }
                let progress = self.hasEnded ? 1.0 : (self.currentTime / self.duration)
                LibraryManager.shared.recordPlayback(url: url, duration: self.duration, progress: progress)
            }
        }
    }

    // MARK: - Media Lifecycle
    public func unloadMedia() {
        if let url = currentURL, !url.path.isEmpty, duration > 0 {
            let progress = hasEnded ? 1.0 : (currentTime / duration)
            LibraryManager.shared.recordPlayback(url: url, duration: duration, progress: progress)
        }

        loadGeneration &+= 1
        clearPlayerItemObservers()

        if isNativePipelineActive {
            nativePipeline.stop()
            isNativePipelineActive = false
        }

        player.pause()
        player.replaceCurrentItem(with: nil)
        securityBox.url = nil

        currentURL = nil
        pendingInitialSeekTime = nil
        currentTime = 0.0
        lastSyncTime = 0.0
        lastSyncDate = Date()
        duration = 0.0
        isPlaying = false
        isBuffering = false
        hasEnded = false
        playbackError = nil
        activeSubtitleText = ""
        availableSubtitleTracks = [SubtitleTrack.off]
        selectedSubtitleTrack = SubtitleTrack.off
        availableAudioTracks = []
        selectedAudioTrack = nil
        metadata = VideoMetadata()
        activeInspectorSheet = nil
        updateBufferingStatus(false)
    }

    // MARK: - Loading Media
    public func loadMedia(from url: URL, initialSeekTime: Double? = nil) {
        // Defensive check: if empty or a directory (except HLS movpkg bundles), unload cleanly
        var isDir: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if url.path.isEmpty || (fileExists && isDir.boolValue && url.pathExtension.lowercased() != "movpkg") {
            unloadMedia()
            return
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        clearPlayerItemObservers()

        if isNativePipelineActive {
            nativePipeline.stop()
            isNativePipelineActive = false
        }

        if url.startAccessingSecurityScopedResource() {
            securityBox.url = url
        } else {
            securityBox.url = nil
        }

        self.currentURL = url
        self.pendingInitialSeekTime = (initialSeekTime != nil && initialSeekTime! > 0) ? initialSeekTime : nil
        let startSecs = initialSeekTime ?? 0.0
        self.currentTime = startSecs
        self.lastSyncTime = startSecs
        self.lastSyncDate = Date()
        self.duration = 0.0
        self.hasEnded = false
        self.updateBufferingStatus(false)
        self.activeSubtitleText = ""
        self.availableSubtitleTracks = [SubtitleTrack.off]
        self.selectedSubtitleTrack = SubtitleTrack.off
        self.availableAudioTracks = []
        self.selectedAudioTrack = nil
        self.playbackError = nil

        // If format is a Matroska-family container, immediately start native pipeline
        if canUseNativeMatroskaPipeline(for: url) {
            startNativePipeline(url: url, initialSeekTime: initialSeekTime)
            return
        }

        self.isNativePipelineActive = false

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // Apple Silicon low-latency audio/video configuration
        playerItem.audioTimePitchAlgorithm = .timeDomain

        observePlayerItem(playerItem)
        player.replaceCurrentItem(with: playerItem)
        player.volume = volume
        player.isMuted = isMuted

        if let initialSeekTime, initialSeekTime > 0 {
            let target = CMTime(seconds: initialSeekTime, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        play()

        Task { [weak self] in
            guard let self else { return }
            await self.extractMetadata(from: asset, url: url, generation: generation)
            await self.extractTracks(from: playerItem, generation: generation)
            guard self.loadGeneration == generation, self.currentURL == url else { return }
            self.checkForExternalSubtitles(videoURL: url)
        }
    }

    // MARK: - Playback Controls
    private var isSeekInProgress = false
    private var chaseTime: CMTime = .zero
    private var displayTime: Double = 0.0

    public func play() {
        if hasEnded || (currentTime >= duration && duration > 0) {
            hasEnded = false
            seek(to: 0)
        }
        lastSyncTime = currentTime
        lastSyncDate = Date()
        displayTime = currentTime
        if isNativePipelineActive {
            nativePipeline.play()
        } else {
            player.rate = playbackRate
        }
        isPlaying = true
    }

    public func pause() {
        currentTime = currentInterpolatedTime()
        lastSyncTime = currentTime
        lastSyncDate = Date()
        displayTime = currentTime
        if isNativePipelineActive {
            nativePipeline.pause()
        } else {
            player.pause()
        }
        isPlaying = false
        if let url = currentURL, !url.path.isEmpty, duration > 0 {
            let progress = currentTime / duration
            LibraryManager.shared.recordPlayback(url: url, duration: duration, progress: progress)
        }
    }

    public func replay() {
        hasEnded = false
        seek(to: 0)
        play()
    }

    public func markPlaybackEnded() {
        guard !hasEnded else { return }
        isPlaying = false
        hasEnded = true
        currentTime = duration > 0 ? duration : currentTime
        controlsVisible = true
        updateBufferingStatus(false)
        NSCursor.setHiddenUntilMouseMoves(false)
        if let url = currentURL, !url.path.isEmpty {
            LibraryManager.shared.recordPlayback(url: url, duration: duration, progress: 1.0)
        }
        onPlaybackEnded?()
    }

    public func togglePlayPause() {
        if hasEnded {
            replay()
        } else if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func currentInterpolatedTime(at date: Date = Date()) -> Double {
        if isNativePipelineActive {
            return currentTime
        }
        guard duration > 0 else { return currentTime }
        if isScrubbing {
            return currentTime
        }
        if isPlaying && !isBuffering {
            let elapsed = date.timeIntervalSince(lastSyncDate) * Double(playbackRate)
            let estimated = lastSyncTime + elapsed
            if estimated >= displayTime {
                displayTime = min(duration, estimated)
            } else if abs(estimated - displayTime) > 0.3 {
                displayTime = estimated
            }
            return displayTime
        }
        displayTime = currentTime
        return currentTime
    }

    public func seek(to seconds: Double, exact: Bool = false) {
        hasEnded = false
        let clamped = max(0.0, min(seconds, duration > 0 ? duration : seconds))
        currentTime = clamped
        lastSyncTime = clamped
        lastSyncDate = Date()
        displayTime = clamped

        if isNativePipelineActive {
            nativePipeline.seek(to: clamped, isScrubbing: !exact)
            return
        }

        let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
        chaseTime = targetTime

        if exact {
            isSeekInProgress = false
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentTime = clamped
                    self.lastSyncTime = clamped
                    self.lastSyncDate = Date()
                    self.displayTime = clamped
                }
            }
        } else {
            guard !isSeekInProgress else { return }
            performChaseSeek()
        }
    }

    private func performChaseSeek() {
        isSeekInProgress = true
        let seekTarget = chaseTime
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)

        player.seek(to: seekTarget, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isSeekInProgress = false
                if CMTimeCompare(seekTarget, self.chaseTime) != 0 {
                    self.performChaseSeek()
                }
            }
        }
    }

    public func skip(seconds: Double) {
        seek(to: currentTime + seconds, exact: true)
    }

    public func stepFrame(forward: Bool) {
        pause()
        player.currentItem?.step(byCount: forward ? 1 : -1)
    }

    public func toggleMute() {
        isMuted.toggle()
    }

    public func setVolumeDelta(_ delta: Float) {
        let newVol = min(max(volume + delta, 0.0), 1.0)
        volume = newVol
        if isMuted && newVol > 0 {
            isMuted = false
        }
    }

    // MARK: - Subtitles Management
    public func selectSubtitleTrack(_ track: SubtitleTrack) {
        selectedSubtitleTrack = track

        guard let item = player.currentItem else { return }

        Task {
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                if let avOption = track.avOption {
                    item.select(avOption, in: group)
                } else {
                    item.select(nil, in: group)
                }
            }
        }

        updateActiveSubtitle(at: currentTime)
    }

    public func loadExternalSubtitleFile(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let cues = SubtitleParser.parse(content: content)
            let trackName = url.deletingPathExtension().lastPathComponent
            let newTrack = SubtitleTrack(
                id: UUID().uuidString,
                title: trackName + " (External)",
                languageCode: "ext",
                isExternal: true,
                cues: cues
            )
            availableSubtitleTracks.append(newTrack)
            selectSubtitleTrack(newTrack)
        } catch {
            print("Failed to read subtitle file: \(error.localizedDescription)")
        }
    }

    private func checkForExternalSubtitles(videoURL: URL) {
        let base = videoURL.deletingPathExtension()
        let extensions = ["srt", "vtt"]
        for ext in extensions {
            let candidateURL = base.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                loadExternalSubtitleFile(from: candidateURL)
                break
            }
        }
    }

    private func updateActiveSubtitle(at time: Double) {
        guard selectedSubtitleTrack.isExternal else {
            activeSubtitleText = ""
            return
        }

        let adjustedTime = time - subtitleDelay
        if let match = selectedSubtitleTrack.cues.first(where: { adjustedTime >= $0.startTime && adjustedTime <= $0.endTime }) {
            activeSubtitleText = match.text
        } else {
            activeSubtitleText = ""
        }
    }

    // MARK: - Audio Tracks Management
    public func selectAudioTrack(_ track: AudioTrack) {
        selectedAudioTrack = track
        guard let item = player.currentItem, let option = track.avOption else { return }

        Task {
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
                item.select(option, in: group)
            }
        }
    }

    // MARK: - Internal Observers & Engine Logic
    private var lastRecordedProgressTime: CFAbsoluteTime = 0

    private func throttledRecordProgress() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRecordedProgressTime >= 5.0, let url = currentURL, !url.path.isEmpty, duration > 0 else { return }
        lastRecordedProgressTime = now
        let progress = currentTime / duration
        LibraryManager.shared.recordPlayback(url: url, duration: duration, progress: progress)
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isScrubbing else { return }
                let secs = time.seconds
                if !secs.isNaN && !secs.isInfinite {
                    self.currentTime = secs
                    self.lastSyncTime = secs
                    self.lastSyncDate = Date()
                    self.updateActiveSubtitle(at: secs)
                    self.throttledRecordProgress()
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        clearPlayerItemObservers()

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if playerItem.status == .readyToPlay {
                    let d = playerItem.duration.seconds
                    if !d.isNaN && !d.isInfinite {
                        self.duration = d
                    }
                    if let seekTime = self.pendingInitialSeekTime, seekTime > 0 {
                        let targetTime = seekTime
                        self.pendingInitialSeekTime = nil
                        let target = CMTime(seconds: targetTime, preferredTimescale: 600)
                        self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                self?.currentTime = targetTime
                                self?.lastSyncTime = targetTime
                                self?.lastSyncDate = Date()
                            }
                        }
                    }
                } else if playerItem.status == .failed {
                    guard self.player.currentItem === playerItem else { return }
                    if let url = self.currentURL, self.canUseNativeMatroskaPipeline(for: url) {
                        self.startNativePipeline(url: url, initialSeekTime: self.pendingInitialSeekTime)
                        return
                    }
                    self.isBuffering = false
                    self.isPlaying = false
                    self.playbackError = playerItem.error?.localizedDescription ?? "macOS cannot decode this media on this Mac."
                }
            }
        }

        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isPlaying = (p.timeControlStatus == .playing)
                self.updateBufferingStatus(p.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            }
        }

        itemDidPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.markPlaybackEnded()
            }
        }
    }

    private func clearPlayerItemObservers() {
        bufferingTimer?.invalidate()
        bufferingTimer = nil
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlStatusObserver?.invalidate()
        timeControlStatusObserver = nil
        if let endObserver = itemDidPlayToEndObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        itemDidPlayToEndObserver = nil
    }

    private func canUseNativeMatroskaPipeline(for url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "mkv", "webm", "mka":
            return true
        default:
            return false
        }
    }

    /// Falls back only after AVFoundation rejects a Matroska-family container.
    /// The new generation invalidates pending AVFoundation metadata tasks.
    private func startNativePipeline(url: URL, initialSeekTime: Double? = nil) {
        loadGeneration &+= 1
        let generation = loadGeneration
        clearPlayerItemObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        isNativePipelineActive = true
        isPlaying = false
        isBuffering = false
        playbackError = nil

        metadata.title = url.deletingPathExtension().lastPathComponent
        metadata.container = url.pathExtension.uppercased()

        Task { [weak self] in
            guard let self else { return }
            let success = await nativePipeline.load(url: url)
            guard loadGeneration == generation, currentURL == url else {
                if success { nativePipeline.stop() }
                return
            }

            guard success else {
                isNativePipelineActive = false
                playbackError = "This \(url.pathExtension.uppercased()) file uses a codec that Frames cannot decode on this Mac."
                return
            }

            duration = nativePipeline.duration
            metadata.duration = nativePipeline.duration
            nativePipeline.setVolume(isMuted ? 0.0 : volume)
            nativePipeline.onPlaybackEnded = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.markPlaybackEnded()
                }
            }
            nativePipeline.onTimeUpdate = { [weak self] pts in
                Task { @MainActor [weak self] in
                    guard let self, !self.isScrubbing else { return }
                    self.currentTime = pts
                    self.lastSyncTime = pts
                    self.lastSyncDate = Date()
                    self.updateActiveSubtitle(at: pts)
                    self.throttledRecordProgress()
                }
            }
            if let initialSeekTime, initialSeekTime > 0 {
                seek(to: initialSeekTime, exact: true)
            }
            play()
            checkForExternalSubtitles(videoURL: url)
        }
    }

    // MARK: - Metadata Extraction
    private func extractMetadata(from asset: AVURLAsset, url: URL, generation: UInt) async {
        var meta = VideoMetadata()
        meta.title = url.deletingPathExtension().lastPathComponent
        meta.container = url.pathExtension.uppercased()

        if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = resources.fileSize {
            meta.fileSize = Int64(size)
        }

        if let durationTime = try? await asset.load(.duration) {
            let secs = durationTime.seconds
            if !secs.isNaN && !secs.isInfinite {
                meta.duration = secs
                if meta.fileSize > 0 && secs > 0 {
                    meta.bitrate = Double(meta.fileSize * 8) / secs
                }
            }
        }

        if let videoTracks = try? await asset.loadTracks(withMediaType: .video),
           let videoTrack = videoTracks.first {
            if let size = try? await videoTrack.load(.naturalSize) {
                meta.naturalSize = size
            }
            if let rate = try? await videoTrack.load(.nominalFrameRate) {
                meta.frameRate = rate
            }

            // Inspect video codec & Apple Silicon hardware acceleration
            if let formatDescriptions = try? await videoTrack.load(.formatDescriptions),
               let desc = formatDescriptions.first {
                let subType = CMFormatDescriptionGetMediaSubType(desc)
                let fourCC = subType.fourCCString
                meta.codec = friendlyCodecName(fourCC)

                // Inspect color primaries
                if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
                    if let primaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String {
                        meta.colorPrimaries = friendlyColorPrimaries(primaries)
                        meta.isHDR = primaries.contains("2020") || extensions[kCVImageBufferTransferFunctionKey as String] as? String == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
                    }
                }
            }
        }

        guard loadGeneration == generation, currentURL == url else { return }
        self.metadata = meta
    }

    private func extractTracks(from item: AVPlayerItem, generation: UInt) async {
        // Extract audible (audio) tracks
        if let audioGroup = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
            var audios: [AudioTrack] = []
            for option in audioGroup.options {
                let title = option.displayName
                let lang = option.locale?.localizedString(forIdentifier: option.locale?.identifier ?? "") ?? option.extendedLanguageTag
                let track = AudioTrack(
                    id: option.displayName + (lang ?? ""),
                    title: title,
                    languageCode: lang,
                    avOption: option
                )
                audios.append(track)
            }
            guard loadGeneration == generation, player.currentItem === item else { return }
            self.availableAudioTracks = audios
            self.selectedAudioTrack = audios.first
        }

        // Extract legible (subtitles) tracks
        if let subtitleGroup = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
            var subs: [SubtitleTrack] = [SubtitleTrack.off]
            for option in subtitleGroup.options {
                let title = option.displayName
                let lang = option.locale?.localizedString(forIdentifier: option.locale?.identifier ?? "") ?? option.extendedLanguageTag
                let track = SubtitleTrack(
                    id: option.displayName + (lang ?? ""),
                    title: title,
                    languageCode: lang,
                    isExternal: false,
                    avOption: option
                )
                subs.append(track)
            }
            guard loadGeneration == generation, player.currentItem === item else { return }
            self.availableSubtitleTracks = subs
        }
    }

    private func friendlyCodecName(_ fourCC: String) -> String {
        switch fourCC.lowercased() {
        case "avc1", "h264": return "H.264 / AVC (Apple Silicon HW)"
        case "hvc1", "hev1": return "HEVC / H.265 (Apple Silicon HW)"
        case "dvh1", "dvhe": return "Dolby Vision HEVC (Apple Silicon HW)"
        case "apch", "apcn", "apcs", "apco", "ap4h", "ap4x": return "Apple ProRes (Apple Silicon HW)"
        case "av01": return "AV1 (Apple Silicon HW)"
        case "vp09": return "VP9"
        default: return fourCC.uppercased()
        }
    }

    private func friendlyColorPrimaries(_ primaries: String) -> String {
        if primaries.contains("2020") {
            return "BT.2020 Wide Color (HDR)"
        } else if primaries.contains("P3") || primaries.contains("DCI") {
            return "Display P3 Wide Color"
        } else {
            return "BT.709 Standard Color"
        }
    }
}

// MARK: - Security Scoped Resource Box
private final class SecurityScopedBox: @unchecked Sendable {
    var url: URL? {
        didSet {
            oldValue?.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        url?.stopAccessingSecurityScopedResource()
    }
}

// MARK: - FourCC Helper
private extension FourCharCode {
    var fourCCString: String {
        let bytes: [CChar] = [
            CChar((self >> 24) & 0xff),
            CChar((self >> 16) & 0xff),
            CChar((self >> 8) & 0xff),
            CChar(self & 0xff),
            0
        ]
        return String(cString: bytes).trimmingCharacters(in: .whitespaces)
    }
}
