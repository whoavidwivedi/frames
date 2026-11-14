import Foundation
import AVFoundation
import Combine
import CoreMedia
import SwiftUI
import VideoToolbox

// MARK: - Isolated High-Frequency Playback Clock Store
/// Decouples high-frequency presentation clock updates from VideoPlayerEngine
/// to isolate main-thread SwiftUI view invalidations from top-level UI hierarchies.
@MainActor
@Observable
public final class PlaybackClockStore {
    public var currentTime: Double = 0.0
    public var duration: Double = 0.0
    public var isPlaying: Bool = false
    public var isScrubbing: Bool = false

    public init(currentTime: Double = 0.0, duration: Double = 0.0, isPlaying: Bool = false, isScrubbing: Bool = false) {
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.isScrubbing = isScrubbing
    }

    public func update(currentTime: Double) {
        if abs(self.currentTime - currentTime) >= 0.001 {
            self.currentTime = currentTime
        }
    }

    public var formattedCurrentTime: String {
        TimeFormatting.format(seconds: currentTime)
    }

    public var formattedDuration: String {
        TimeFormatting.format(seconds: duration)
    }
}

@MainActor
@Observable
public final class VideoPlayerEngine {
    // MARK: - Core Playback State
    public let clockStore = PlaybackClockStore()
    public private(set) var player: AVPlayer = AVPlayer()
    public private(set) var currentURL: URL?
    public var isPlaying: Bool = false {
        didSet {
            clockStore.isPlaying = isPlaying
        }
    }
    public var isBuffering: Bool = false
    public var hasEnded: Bool = false
    public var onPlaybackEnded: (() -> Void)?

    @ObservationIgnored
    private var _currentTime: Double = 0.0

    public var currentTime: Double {
        get {
            _currentTime
        }
        set {
            _currentTime = newValue
            clockStore.update(currentTime: newValue)
        }
    }

    @ObservationIgnored
    public var lastSyncTime: Double = 0.0
    @ObservationIgnored
    public var lastSyncDate: Date = Date()
    public var duration: Double = 0.0 {
        didSet {
            clockStore.duration = duration
        }
    }
    public var volume: Float = 1.0 {
        didSet {
            let clamped = min(max(volume, 0.0), 1.0)
            player.volume = isMuted ? 0.0 : clamped
            if isNativePipelineActive {
                nativePipeline.setVolume(isMuted ? 0.0 : clamped)
            }
            volumeHUDToken &+= 1
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
            volumeHUDToken &+= 1
        }
    }
    /// Bumped on every volume or mute change so the transient top-right readout can re-show.
    public var volumeHUDToken: Int = 0
    public var playbackRate: Float = 1.0 {
        didSet {
            guard oldValue != playbackRate else { return }
            let clamped = max(0.25, min(playbackRate, 4.0))
            player.defaultRate = clamped
            if isPlaying {
                player.rate = clamped
            }
            lastSyncTime = currentTime
            lastSyncDate = Date()
            displayTime = currentTime
            if isNativePipelineActive {
                nativePipeline.setPlaybackRate(clamped)
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
    public var subtitleFontSize: CGFloat = CGFloat(SettingsManager.shared.subtitleFontSize) {
        didSet {
            SettingsManager.shared.subtitleFontSize = Double(subtitleFontSize)
        }
    }

    // MARK: - UI Interaction State
    public var isScrubbing: Bool = false {
        didSet {
            clockStore.isScrubbing = isScrubbing
        }
    }
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
    private var seekGeneration: UInt = 0
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
        self.subtitleFontSize = CGFloat(SettingsManager.shared.subtitleFontSize)
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

        PictureInPictureManager.shared.exitPictureInPicture()
        loadGeneration &+= 1
        let teardownGeneration = loadGeneration
        seekGeneration &+= 1
        isSeekInProgress = false
        chaseTime = .zero
        clearPlayerItemObservers()

        // Switch the UI to the dashboard first. VideoToolbox invalidation and demuxer
        // teardown block the main thread for a noticeable moment on close, so run them
        // after the state change (skipped if another video loads in the meantime).
        let pipelineToStop = isNativePipelineActive
        isNativePipelineActive = false

        player.pause()
        player.replaceCurrentItem(with: nil)
        securityBox.url = nil

        currentURL = nil
        pendingInitialSeekTime = nil
        currentTime = 0.0
        lastSyncTime = 0.0
        lastSyncDate = Date()
        displayTime = 0.0
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
        nativePipeline.renderer?.preferredAspectRatio = nil
        activeInspectorSheet = nil
        updateBufferingStatus(false)

        if pipelineToStop {
            let pipeline = nativePipeline
            Task { [weak self] in
                guard let self, self.loadGeneration == teardownGeneration else { return }
                pipeline.stop()
            }
        }
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

        // Milestone 2 Unified Playback Core: Route all supported media containers
        // (MKV, WebM, MKA, MP4, MOV, M4V, 3GP) to the zero-copy Apple Silicon native pipeline.
        if canUseNativePipeline(for: url) {
            startNativePipeline(url: url, initialSeekTime: initialSeekTime)
            return
        }

        loadAVPlayerPipeline(url: url, initialSeekTime: initialSeekTime, generation: generation)
    }

    /// Secondary fallback pipeline leveraging AVFoundation for streaming protocols
    /// and formats outside of Frames' native binary demuxer suite.
    private func loadAVPlayerPipeline(url: URL, initialSeekTime: Double?, generation: UInt) {
        self.isNativePipelineActive = false

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // Apple Silicon low-latency audio/video configuration with broad time-pitch scaling
        playerItem.audioTimePitchAlgorithm = .spectral
        playerItem.allowedAudioSpatializationFormats = SettingsManager.shared.spatialAudioEnabled
            ? .monoStereoAndMultichannel
            : []

        observePlayerItem(playerItem)
        player.replaceCurrentItem(with: playerItem)
        player.defaultRate = playbackRate
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
    @ObservationIgnored
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
            nativePipeline.setPlaybackRate(playbackRate)
            nativePipeline.play()
        } else {
            player.defaultRate = playbackRate
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
            currentTime = nativePipeline.currentTime
            lastSyncTime = currentTime
            displayTime = currentTime
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

    /// Ends a scrub gesture. The native pipeline resumes from the already
    /// displayed frame instead of seeking twice (which caused a visible restart).
    public func endScrubbing() {
        isScrubbing = false
        if isNativePipelineActive {
            nativePipeline.endScrubbing()
        }
    }

    public func seek(to seconds: Double, exact: Bool = false) {
        // Guard against NaN, positive infinity, and negative infinity
        guard seconds.isFinite else { return }

        // If no media is loaded and native pipeline is inactive, clamp to zero and exit
        guard currentURL != nil || isNativePipelineActive else {
            currentTime = 0.0
            lastSyncTime = 0.0
            lastSyncDate = Date()
            displayTime = 0.0
            return
        }

        hasEnded = false
        let effectiveDuration = duration > 0 ? duration : (metadata.duration > 0 ? metadata.duration : 0.0)
        let clamped = effectiveDuration > 0 ? max(0.0, min(seconds, effectiveDuration)) : max(0.0, seconds)
        currentTime = clamped
        lastSyncTime = clamped
        lastSyncDate = Date()
        displayTime = clamped

        if isNativePipelineActive {
            nativePipeline.seek(to: clamped, isScrubbing: !exact)
            return
        }

        let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
        guard targetTime.isValid else { return }
        chaseTime = targetTime
        seekGeneration &+= 1
        let currentSeekGen = seekGeneration
        let currentLoadGen = loadGeneration

        if exact {
            isSeekInProgress = false
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    guard finished,
                          self.seekGeneration == currentSeekGen,
                          self.loadGeneration == currentLoadGen,
                          self.currentURL != nil,
                          self.player.currentItem != nil else { return }
                    let finalTime = self.duration > 0 ? min(clamped, self.duration) : clamped
                    self.currentTime = finalTime
                    self.lastSyncTime = finalTime
                    self.lastSyncDate = Date()
                    self.displayTime = finalTime
                }
            }
        } else {
            guard !isSeekInProgress else { return }
            performChaseSeek()
        }
    }

    private func performChaseSeek() {
        guard currentURL != nil, player.currentItem != nil else {
            isSeekInProgress = false
            return
        }
        isSeekInProgress = true
        let seekTarget = chaseTime
        let currentLoadGen = loadGeneration
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)

        player.seek(to: seekTarget, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.loadGeneration == currentLoadGen,
                      self.currentURL != nil,
                      self.player.currentItem != nil else {
                    self.isSeekInProgress = false
                    return
                }
                self.isSeekInProgress = false
                if finished && CMTimeCompare(seekTarget, self.chaseTime) != 0 {
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
        var targetTrack = track
        if let idx = availableSubtitleTracks.firstIndex(where: { $0.id == track.id }) {
            targetTrack = availableSubtitleTracks[idx]
        }
        selectedSubtitleTrack = targetTrack
        // Never show stale text from the previously selected track while cues load.
        activeSubtitleText = ""

        if isNativePipelineActive {
            if track.id == SubtitleTrack.off.id {
                nativePipeline.selectSubtitleTrack(trackNumber: nil)
            } else {
                // Cues are streamed on-the-fly and preserved in memory without full-file scanning.
                nativePipeline.selectSubtitleTrack(trackNumber: track.trackNumber)
                updateActiveSubtitle(at: currentTime)
            }
            return
        }

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

    public func updateActiveSubtitle(at time: Double) {
        guard selectedSubtitleTrack.id != SubtitleTrack.off.id else {
            if !activeSubtitleText.isEmpty {
                activeSubtitleText = ""
            }
            return
        }

        if !selectedSubtitleTrack.cues.isEmpty {
            let adjustedTime = time - subtitleDelay
            let newText = selectedSubtitleTrack.cues.first(where: { adjustedTime >= $0.startTime && adjustedTime <= $0.endTime })?.text ?? ""
            if activeSubtitleText != newText {
                activeSubtitleText = newText
            }
        } else if !activeSubtitleText.isEmpty {
            activeSubtitleText = ""
        }
    }

    // MARK: - Audio Tracks Management
    public func selectAudioTrack(_ track: AudioTrack) {
        selectedAudioTrack = track

        if isNativePipelineActive {
            if let trackNumber = track.trackNumber {
                nativePipeline.selectAudioTrack(trackNumber: trackNumber)
            }
            return
        }

        guard let item = player.currentItem else { return }

        if let option = track.avOption {
            Task {
                if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
                    item.select(option, in: group)
                }
            }
        } else if let trackNumber = track.trackNumber {
            for itemTrack in item.tracks where itemTrack.assetTrack?.mediaType == .audio {
                if UInt64(itemTrack.assetTrack?.trackID ?? 0) == trackNumber {
                    itemTrack.isEnabled = true
                } else {
                    itemTrack.isEnabled = false
                }
            }
        }
    }

    /// Selects the preferred audio track matching SettingsManager.shared.defaultAudioLanguage
    public func findPreferredAudioTrack(in tracks: [AudioTrack]) -> AudioTrack? {
        guard !tracks.isEmpty else { return nil }
        let pref = SettingsManager.shared.defaultAudioLanguage
        if pref == "System" {
            let sysLang = Locale.current.language.languageCode?.identifier ?? "en"
            let sysName = LanguageHelper.displayName(for: sysLang).lowercased()
            return tracks.first { track in
                let langName = LanguageHelper.displayName(for: track.languageCode).lowercased()
                return langName == sysName || track.languageCode?.lowercased() == sysLang
            }
        } else if pref == "Original" {
            return tracks.first
        } else {
            let prefLower = pref.lowercased()
            return tracks.first { track in
                let langName = LanguageHelper.displayName(for: track.languageCode).lowercased()
                return langName == prefLower ||
                       (track.languageCode?.lowercased() == prefLower) ||
                       track.title.lowercased().contains(prefLower)
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
                guard let self = self,
                      !self.isScrubbing,
                      self.currentURL != nil,
                      self.player.currentItem != nil else { return }
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
                    if !d.isNaN && !d.isInfinite && d > 0 {
                        self.duration = d
                        if self.currentTime > d {
                            self.currentTime = d
                            self.lastSyncTime = d
                            self.lastSyncDate = Date()
                            self.displayTime = d
                        }
                    }
                    if self.isPlaying {
                        self.player.defaultRate = self.playbackRate
                        self.player.rate = self.playbackRate
                    }
                    if let seekTime = self.pendingInitialSeekTime, seekTime > 0 {
                        let targetTime = seekTime
                        self.pendingInitialSeekTime = nil
                        let target = CMTime(seconds: targetTime, preferredTimescale: 600)
                        let currentLoadGen = self.loadGeneration
                        self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                            Task { @MainActor [weak self] in
                                guard let self = self, finished,
                                      self.loadGeneration == currentLoadGen,
                                      self.currentURL != nil,
                                      self.player.currentItem != nil else { return }
                                self.currentTime = targetTime
                                self.lastSyncTime = targetTime
                                self.lastSyncDate = Date()
                                self.displayTime = targetTime
                            }
                        }
                    }
                } else if playerItem.status == .failed {
                    guard self.player.currentItem === playerItem else { return }
                    if let url = self.currentURL, self.canFallbackToNativePipeline(for: url) {
                        let resumeTime = (self.currentTime > 0) ? self.currentTime : self.pendingInitialSeekTime
                        self.startNativePipeline(url: url, initialSeekTime: resumeTime)
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

    private func canFallbackToNativePipeline(for url: URL) -> Bool {
        return PlaybackPipeline.isSupportedContainer(at: url)
    }

    public func canUseNativePipeline(for url: URL) -> Bool {
        return PlaybackPipeline.isSupportedContainer(at: url)
    }

    @available(*, deprecated, renamed: "canUseNativePipeline")
    public func canUseNativeMatroskaPipeline(for url: URL) -> Bool {
        return canUseNativePipeline(for: url)
    }

    /// Launches the zero-copy Apple Silicon native pipeline (Metal + VideoToolbox).
    /// If the native demuxer or hardware decoder rejects the stream, it gracefully
    /// falls back to AVFoundation without interrupting user playback.
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
                // Milestone 2 Fallback: Gracefully fall back to AVFoundation
                // if the native demuxer encounters an unsupported track layout or codec.
                self.loadAVPlayerPipeline(url: url, initialSeekTime: initialSeekTime, generation: generation)
                return
            }

            duration = nativePipeline.duration
            metadata.duration = nativePipeline.duration
            nativePipeline.setVolume(isMuted ? 0.0 : volume)
            nativePipeline.setPlaybackRate(playbackRate)

            // Extract audio tracks from native demuxer
            var audios: [AudioTrack] = []
            for t in self.nativePipeline.demuxedAudioTracks {
                let langCode = t.language
                let channelStr = LanguageHelper.channelDescription(channels: t.channels)
                let codecStr = LanguageHelper.audioCodecDescription(codecID: t.codecID)
                let title = LanguageHelper.formattedTrackTitle(displayName: t.name, language: langCode, details: channelStr)
                audios.append(AudioTrack(
                    id: "native_audio_\(t.trackNumber)",
                    title: title,
                    languageCode: langCode,
                    channelLayout: channelStr,
                    formatDescription: codecStr,
                    avOption: nil,
                    trackNumber: t.trackNumber
                ))
            }
            self.availableAudioTracks = audios
            if let preferred = self.findPreferredAudioTrack(in: audios) {
                self.selectedAudioTrack = preferred
                if let tNum = preferred.trackNumber {
                    self.nativePipeline.selectAudioTrack(trackNumber: tNum)
                }
            } else if let defaultTrack = self.nativePipeline.demuxedAudioTracks.first(where: { $0.isDefault }) ?? self.nativePipeline.demuxedAudioTracks.first {
                self.selectedAudioTrack = audios.first(where: { $0.trackNumber == defaultTrack.trackNumber }) ?? audios.first
            } else {
                self.selectedAudioTrack = audios.first
            }

            // Extract subtitle tracks from native demuxer
            var subs: [SubtitleTrack] = [SubtitleTrack.off]
            for t in self.nativePipeline.demuxedSubtitleTracks {
                let langCode = t.language
                let title = LanguageHelper.formattedTrackTitle(displayName: t.name, language: langCode)
                subs.append(SubtitleTrack(
                    id: "native_sub_\(t.trackNumber)",
                    title: title,
                    languageCode: langCode,
                    isExternal: false,
                    cues: [],
                    avOption: nil,
                    trackNumber: t.trackNumber
                ))
            }
            self.availableSubtitleTracks = subs
            self.selectedSubtitleTrack = SubtitleTrack.off

            // Inspect video metadata from demuxer
            if let vTrack = self.nativePipeline.demuxer?.videoTracks.first {
                self.metadata.naturalSize = CGSize(width: vTrack.displayWidth, height: vTrack.displayHeight)
                if vTrack.displayWidth > 0 && vTrack.displayHeight > 0 {
                    self.nativePipeline.renderer?.preferredAspectRatio = Float(vTrack.displayWidth) / Float(vTrack.displayHeight)
                }
                if let fps = vTrack.estimatedFPS {
                    self.metadata.frameRate = Float(fps)
                }
                self.metadata.codec = vTrack.codecID
                self.metadata.isHDR = vTrack.isHDR
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    self.metadata.fileSize = Int64(size)
                    if self.duration > 0 {
                        self.metadata.bitrate = Double(Int64(size) * 8) / self.duration
                    }
                }
                self.metadata.isHardwareAccelerated = self.nativePipeline.isHardwareAccelerated
                self.metadata.decoderImplementationName = self.nativePipeline.decoderImplementationName
            }

            self.nativePipeline.onSubtitleCue = { [weak self] cue in
                    guard let self else { return }
                    let activeTrackNum = self.nativePipeline.activeSubtitleTrackNumber
                    if let activeTrackNum {
                        if let idx = self.availableSubtitleTracks.firstIndex(where: { $0.trackNumber == activeTrackNum }) {
                            if !self.availableSubtitleTracks[idx].cues.contains(where: { abs($0.startTime - cue.startTime) < 0.1 }) {
                                self.availableSubtitleTracks[idx].cues.append(cue)
                            }
                        }
                    }
                    guard self.selectedSubtitleTrack.id != SubtitleTrack.off.id else { return }
                    if self.selectedSubtitleTrack.trackNumber == activeTrackNum {
                        if !self.selectedSubtitleTrack.cues.contains(where: { abs($0.startTime - cue.startTime) < 0.1 }) {
                            self.selectedSubtitleTrack.cues.append(cue)
                        }
                        if self.currentTime >= cue.startTime && self.currentTime <= cue.endTime {
                            self.activeSubtitleText = cue.text
                        }
                    }
                }

            nativePipeline.onPlaybackEnded = { [weak self] in
                    self?.markPlaybackEnded()
                }
            nativePipeline.onTimeUpdate = { [weak self] pts in
                    guard let self, !self.isScrubbing else { return }
                    self.currentTime = pts
                    self.lastSyncTime = pts
                    self.lastSyncDate = Date()
                    self.updateActiveSubtitle(at: pts)
                    self.throttledRecordProgress()
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
            if !secs.isNaN && !secs.isInfinite && secs > 0 {
                meta.duration = secs
                if self.duration <= 0 {
                    self.duration = secs
                }
                if meta.fileSize > 0 && secs > 0 {
                    meta.bitrate = Double(meta.fileSize * 8) / secs
                }
            }
        }

        if let videoTracks = try? await asset.loadTracks(withMediaType: .video),
           let videoTrack = videoTracks.first {
            if let size = try? await videoTrack.load(.naturalSize) {
                meta.naturalSize = size
                if size.width > 0 && size.height > 0 {
                    self.nativePipeline.renderer?.preferredAspectRatio = Float(size.width / size.height)
                }
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

                let isHW = VTIsHardwareDecodeSupported(subType)
                meta.isHardwareAccelerated = isHW
                meta.decoderImplementationName = isHW ? "AVFoundation (Apple Silicon Hardware Engine)" : "AVFoundation (Software Fallback)"

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
        var audios: [AudioTrack] = []
        var detectedSelectedAudio: AudioTrack? = nil

        if let audioGroup = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
            let activeAudibleOption = item.currentMediaSelection.selectedMediaOption(in: audioGroup)
            for (idx, option) in audioGroup.options.enumerated() {
                let displayName = option.displayName
                let lang = option.locale?.language.languageCode?.identifier ?? option.extendedLanguageTag ?? option.locale?.identifier
                
                let channelLayout = "Stereo"
                var formatDesc = "AAC"
                if let subType = option.mediaSubTypes.first {
                    let fourCC = subType.uint32Value.fourCCString
                    formatDesc = LanguageHelper.audioCodecDescription(codecID: fourCC)
                }

                let trackTitle = LanguageHelper.formattedTrackTitle(
                    displayName: displayName,
                    language: lang,
                    details: channelLayout
                )

                let track = AudioTrack(
                    id: "av_audio_opt_\(idx)_\(displayName)_\(lang ?? "")",
                    title: trackTitle,
                    languageCode: lang,
                    channelLayout: channelLayout,
                    formatDescription: formatDesc,
                    avOption: option
                )
                audios.append(track)
                if activeAudibleOption == option {
                    detectedSelectedAudio = track
                }
            }
        }

        if audios.isEmpty, let tracks = try? await item.asset.loadTracks(withMediaType: .audio) {
            for (idx, track) in tracks.enumerated() {
                let extendedTag = try? await track.load(.extendedLanguageTag)
                let languageCode = try? await track.load(.languageCode)
                let lang = extendedTag ?? languageCode
                var channels = 2
                var formatDesc = "AAC"
                if let formats = try? await track.load(.formatDescriptions), let desc = formats.first {
                    let subType = CMFormatDescriptionGetMediaSubType(desc)
                    formatDesc = LanguageHelper.audioCodecDescription(codecID: subType.fourCCString)
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                        channels = Int(asbd.pointee.mChannelsPerFrame)
                    }
                }
                let channelLayout = LanguageHelper.channelDescription(channels: channels)
                let trackTitle = LanguageHelper.formattedTrackTitle(
                    displayName: "Track \(idx + 1)",
                    language: lang,
                    details: channelLayout
                )
                let audioTrack = AudioTrack(
                    id: "av_audio_track_\(track.trackID)_\(idx)",
                    title: trackTitle,
                    languageCode: lang,
                    channelLayout: channelLayout,
                    formatDescription: formatDesc,
                    avOption: nil,
                    trackNumber: UInt64(track.trackID)
                )
                audios.append(audioTrack)
            }
        }

        guard loadGeneration == generation, player.currentItem === item else { return }
        self.availableAudioTracks = audios
        if let preferred = self.findPreferredAudioTrack(in: audios) {
            self.selectedAudioTrack = preferred
            self.selectAudioTrack(preferred)
        } else {
            self.selectedAudioTrack = detectedSelectedAudio ?? audios.first
        }

        // Extract legible (subtitles) tracks
        var subs: [SubtitleTrack] = [SubtitleTrack.off]
        var detectedSelectedSub: SubtitleTrack? = nil

        if let subtitleGroup = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
            let activeLegibleOption = item.currentMediaSelection.selectedMediaOption(in: subtitleGroup)
            for (idx, option) in subtitleGroup.options.enumerated() {
                let title = option.displayName
                let lang = option.locale?.language.languageCode?.identifier ?? option.extendedLanguageTag ?? option.locale?.identifier
                let displayTitle = LanguageHelper.formattedTrackTitle(displayName: title, language: lang)
                let track = SubtitleTrack(
                    id: "av_sub_opt_\(idx)_\(title)_\(lang ?? "")",
                    title: displayTitle,
                    languageCode: lang,
                    isExternal: false,
                    avOption: option
                )
                subs.append(track)
                if activeLegibleOption == option {
                    detectedSelectedSub = track
                }
            }
        }

        if subs.count <= 1, let tracks = try? await item.asset.loadTracks(withMediaType: .subtitle) {
            for (idx, track) in tracks.enumerated() {
                let extendedTag = try? await track.load(.extendedLanguageTag)
                let languageCode = try? await track.load(.languageCode)
                let lang = extendedTag ?? languageCode
                let title = LanguageHelper.formattedTrackTitle(displayName: "Subtitle \(idx + 1)", language: lang)
                subs.append(SubtitleTrack(
                    id: "av_sub_track_\(track.trackID)_\(idx)",
                    title: title,
                    languageCode: lang,
                    isExternal: false,
                    avOption: nil,
                    trackNumber: UInt64(track.trackID)
                ))
            }
        }

        guard loadGeneration == generation, player.currentItem === item else { return }
        self.availableSubtitleTracks = subs
        self.selectedSubtitleTrack = detectedSelectedSub ?? SubtitleTrack.off
    }

    private func friendlyCodecName(_ fourCC: String) -> String {
        switch fourCC.lowercased() {
        case "avc1", "h264": return "H.264 / AVC (Apple Silicon HW)"
        case "hvc1", "hev1": return "HEVC / H.265 (Apple Silicon HW)"
        case "dvh1", "dvhe": return "Dolby Vision HEVC (Apple Silicon HW)"
        case "apch", "apcn", "apcs", "apco", "ap4h", "ap4x":
            return AppleSiliconMetrics.shared.supportsHardwareProRes ? "Apple ProRes (Hardware ASIC)" : "Apple ProRes (Apple Silicon)"
        case "av01":
            return AppleSiliconMetrics.shared.supportsHardwareAV1Decode ? "AV1 (Apple Silicon HW ASIC)" : "AV1 (Apple Silicon Accelerated)"
        case "vp09": return "VP9 (Apple Silicon Accelerated)"
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
