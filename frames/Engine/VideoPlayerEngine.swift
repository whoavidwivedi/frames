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
    public var currentTime: Double = 0.0
    public var lastSyncTime: Double = 0.0
    public var lastSyncDate: Date = Date()
    public var duration: Double = 0.0
    public var volume: Float = 1.0 {
        didSet {
            player.volume = min(max(volume, 0.0), 1.0)
        }
    }
    public var isMuted: Bool = false {
        didSet {
            player.isMuted = isMuted
        }
    }
    public var playbackRate: Float = 1.0 {
        didSet {
            if isPlaying {
                player.rate = playbackRate
            }
        }
    }
    public var audioGainBoost: Float = 1.0 // 1.0x (normal) to 2.0x (boosted)

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

    public enum InspectorSheet: String, Identifiable {
        case subtitles
        case audio
        case speed
        case stats
        case fullscreen

        public var id: String { rawValue }
    }

    // MARK: - Private Observers
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var itemDidPlayToEndObserver: NSObjectProtocol?
    private let securityBox = SecurityScopedBox()

    public init() {
        setupTimeObserver()
    }

    // MARK: - Loading Media
    public func loadMedia(from url: URL) {
        if url.startAccessingSecurityScopedResource() {
            securityBox.url = url
        } else {
            securityBox.url = nil
        }

        self.currentURL = url
        self.currentTime = 0.0
        self.lastSyncTime = 0.0
        self.lastSyncDate = Date()
        self.duration = 0.0
        self.activeSubtitleText = ""
        self.availableSubtitleTracks = [SubtitleTrack.off]
        self.selectedSubtitleTrack = SubtitleTrack.off
        self.availableAudioTracks = []
        self.selectedAudioTrack = nil

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // Apple Silicon low-latency audio/video configuration
        playerItem.audioTimePitchAlgorithm = .timeDomain // High quality pitch preservation during speed changes

        observePlayerItem(playerItem)
        player.replaceCurrentItem(with: playerItem)
        player.volume = volume
        player.isMuted = isMuted

        play()

        Task {
            await extractMetadata(from: asset, url: url)
            await extractTracks(from: playerItem)
            checkForExternalSubtitles(videoURL: url)
        }
    }

    // MARK: - Playback Controls
    private var isSeekInProgress = false
    private var chaseTime: CMTime = .zero
    private var displayTime: Double = 0.0

    public func play() {
        if currentTime >= duration && duration > 0 {
            seek(to: 0)
        }
        lastSyncTime = currentTime
        lastSyncDate = Date()
        displayTime = currentTime
        player.rate = playbackRate
        isPlaying = true
    }

    public func pause() {
        currentTime = currentInterpolatedTime()
        lastSyncTime = currentTime
        lastSyncDate = Date()
        displayTime = currentTime
        player.pause()
        isPlaying = false
    }

    public func togglePlayPause() {
        if isPlaying {
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

    public func seek(to seconds: Double, exact: Bool = false) {
        let clamped = max(0.0, min(seconds, duration > 0 ? duration : seconds))
        currentTime = clamped
        lastSyncTime = clamped
        lastSyncDate = Date()
        displayTime = clamped

        let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
        chaseTime = targetTime

        if exact {
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
                }
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        statusObserver?.invalidate()
        timeControlStatusObserver?.invalidate()
        if let endObserver = itemDidPlayToEndObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if playerItem.status == .readyToPlay {
                    let d = playerItem.duration.seconds
                    if !d.isNaN && !d.isInfinite {
                        self.duration = d
                    }
                }
            }
        }

        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isBuffering = (p.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                self.isPlaying = (p.timeControlStatus == .playing)
            }
        }

        itemDidPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                self?.currentTime = self?.duration ?? 0
            }
        }
    }

    // MARK: - Metadata Extraction
    private func extractMetadata(from asset: AVURLAsset, url: URL) async {
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

        self.metadata = meta
    }

    private func extractTracks(from item: AVPlayerItem) async {
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
