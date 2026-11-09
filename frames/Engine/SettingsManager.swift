import Foundation
import SwiftUI
import AppKit
import IOKit.ps

// MARK: - Enums for Settings Specifications

public enum AutoResumeMode: String, CaseIterable, Identifiable, Sendable {
    case ask = "ask"
    case alwaysResume = "alwaysResume"
    case startBeginning = "startBeginning"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ask: return "Ask Every Time"
        case .alwaysResume: return "Always Resume"
        case .startBeginning: return "Always Start from Beginning"
        }
    }

    public var icon: String {
        switch self {
        case .ask: return "questionmark.circle"
        case .alwaysResume: return "play.circle"
        case .startBeginning: return "backward.end.circle"
        }
    }
}

public enum VideoPresentationEngine: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case directHardwareScanout = "directHardwareScanout"
    case metalShaders = "metalShaders"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto (Direct Hardware Scanout / Metal Adaptive)"
        case .directHardwareScanout: return "Direct Hardware Scanout (0% GPU DCP)"
        case .metalShaders: return "Metal 3 Shaders (CAMetalLayer FP16)"
        }
    }

    public var icon: String {
        switch self {
        case .auto: return "sparkles"
        case .directHardwareScanout: return "display"
        case .metalShaders: return "cpu"
        }
    }
}

public enum HDRToneMappingMode: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case sdrOnly = "sdrOnly"
    case hdrPassthrough = "hdrPassthrough"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto (ST 2084 PQ / HLG)"
        case .sdrOnly: return "Rec. 709 SDR (Clamped)"
        case .hdrPassthrough: return "Direct HDR Passthrough"
        }
    }
}

public enum LiveCaptionsEngine: String, CaseIterable, Identifiable, Sendable {
    case appleNeuralEngine = "appleNeuralEngine"
    case whisperCoreML = "whisperCoreML"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleNeuralEngine: return "Apple Neural Engine (SFSpeechRecognizer)"
        case .whisperCoreML: return "Whisper CoreML"
        }
    }
}

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "general"
    case playback = "playback"
    case audio = "audio"
    case subtitles = "subtitles"
    case about = "about"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .playback: return "Playback"
        case .audio: return "Audio"
        case .subtitles: return "Subtitles"
        case .about: return "About"
        }
    }

    public var icon: String {
        switch self {
        case .general: return "gearshape"
        case .playback: return "play.circle"
        case .audio: return "speaker.wave.3"
        case .subtitles: return "captions.bubble"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Color Hex Conversion Helper

public extension Color {
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if str.hasPrefix("#") {
            str.removeFirst()
        }
        guard let intVal = UInt64(str, radix: 16) else { return nil }
        if str.count == 6 {
            let r = Double((intVal >> 16) & 0xFF) / 255.0
            let g = Double((intVal >> 8) & 0xFF) / 255.0
            let b = Double(intVal & 0xFF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
        } else if str.count == 8 {
            let r = Double((intVal >> 24) & 0xFF) / 255.0
            let g = Double((intVal >> 16) & 0xFF) / 255.0
            let b = Double((intVal >> 8) & 0xFF) / 255.0
            let a = Double(intVal & 0xFF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        } else {
            return nil
        }
    }

    func toHex() -> String? {
        let nsColor = NSColor(self)
        guard let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor.usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(srgb.redComponent * 255))
        let g = Int(round(srgb.greenComponent * 255))
        let b = Int(round(srgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

// MARK: - Settings Manager

@MainActor
@Observable
public final class SettingsManager {
    public static let shared = SettingsManager()

    // MARK: - UserDefaults Keys
    public static let defaultViewModeKey = "frames_settings_default_view_mode_v1"
    public static let autoResumeModeKey = "frames_settings_auto_resume_mode_v1"
    public static let showAddVideoTileKey = "frames_settings_show_add_video_tile_v1"
    public nonisolated static let hardwareAccelerationKey = "frames_settings_hardware_acceleration_v1"
    public static let videoPresentationEngineKey = "frames_settings_video_presentation_engine_v1"
    public static let animeDebandingKey = "frames_settings_anime_debanding_v1"
    public static let customVideoAdjustmentsKey = "frames_settings_custom_video_adjustments_v1"
    public static let hdrToneMappingKey = "frames_settings_hdr_tone_mapping_v1"
    public static let proMotionSyncKey = "frames_settings_promotion_sync_v1"
    public static let defaultSkipIntervalKey = "frames_settings_default_skip_interval_v1"
    public static let spatialAudioKey = "frames_settings_spatial_audio_v1"
    public static let defaultAudioLanguageKey = "frames_settings_default_audio_language_v1"
    public static let volumeNormalizationKey = "frames_settings_volume_normalization_v1"
    public static let subtitleFontSizeKey = "frames_settings_subtitle_font_size_v1"
    public static let subtitleTextColorHexKey = "frames_settings_subtitle_text_color_hex_v1"
    public static let subtitleScrimOpacityKey = "frames_settings_subtitle_scrim_opacity_v1"
    public static let liveCaptionsEnabledKey = "frames_settings_live_captions_enabled_v1"
    public static let liveCaptionsEngineKey = "frames_settings_live_captions_engine_v1"
    public static let batterySaverGuardKey = "frames_settings_battery_saver_guard_v1"
    public static let autoCheckUpdatesKey = "frames_settings_auto_check_updates_v1"
    public static let updateChannelKey = "frames_settings_update_channel_v1"

    // MARK: - 1. General Settings
    public var defaultViewMode: ViewMode {
        didSet {
            UserDefaults.standard.set(defaultViewMode.rawValue, forKey: Self.defaultViewModeKey)
        }
    }

    public var autoResumeMode: AutoResumeMode {
        didSet {
            UserDefaults.standard.set(autoResumeMode.rawValue, forKey: Self.autoResumeModeKey)
        }
    }

    public var showAddVideoTile: Bool {
        didSet {
            UserDefaults.standard.set(showAddVideoTile, forKey: Self.showAddVideoTileKey)
        }
    }

    // MARK: - 2. Playback & Video Settings
    public var videoPresentationEngine: VideoPresentationEngine {
        didSet {
            UserDefaults.standard.set(videoPresentationEngine.rawValue, forKey: Self.videoPresentationEngineKey)
        }
    }

    public var animeDebandingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(animeDebandingEnabled, forKey: Self.animeDebandingKey)
        }
    }

    public var customVideoAdjustmentsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(customVideoAdjustmentsEnabled, forKey: Self.customVideoAdjustmentsKey)
        }
    }

    public var isCustomPostProcessingActive: Bool {
        return (hdrToneMapping == .sdrOnly) || animeDebandingEnabled || customVideoAdjustmentsEnabled
    }

    public var effectivePresentationEngine: VideoPresentationEngine {
        switch videoPresentationEngine {
        case .directHardwareScanout:
            return .directHardwareScanout
        case .metalShaders:
            return .metalShaders
        case .auto:
            return isCustomPostProcessingActive ? .metalShaders : .directHardwareScanout
        }
    }

    public var hardwareAccelerationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hardwareAccelerationEnabled, forKey: Self.hardwareAccelerationKey)
        }
    }

    public var hdrToneMapping: HDRToneMappingMode {
        didSet {
            UserDefaults.standard.set(hdrToneMapping.rawValue, forKey: Self.hdrToneMappingKey)
        }
    }

    public var proMotionSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(proMotionSyncEnabled, forKey: Self.proMotionSyncKey)
        }
    }

    public var defaultSkipInterval: Int {
        didSet {
            UserDefaults.standard.set(defaultSkipInterval, forKey: Self.defaultSkipIntervalKey)
        }
    }

    // MARK: - 3. Audio & Spatial Settings
    public var spatialAudioEnabled: Bool {
        didSet {
            UserDefaults.standard.set(spatialAudioEnabled, forKey: Self.spatialAudioKey)
        }
    }

    public var defaultAudioLanguage: String {
        didSet {
            UserDefaults.standard.set(defaultAudioLanguage, forKey: Self.defaultAudioLanguageKey)
        }
    }

    public var volumeNormalizationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(volumeNormalizationEnabled, forKey: Self.volumeNormalizationKey)
        }
    }

    // MARK: - 4. Subtitles & Live Captions Settings
    public var subtitleFontSize: Double {
        didSet {
            UserDefaults.standard.set(subtitleFontSize, forKey: Self.subtitleFontSizeKey)
        }
    }

    public var subtitleTextColorHex: String {
        didSet {
            UserDefaults.standard.set(subtitleTextColorHex, forKey: Self.subtitleTextColorHexKey)
        }
    }

    public var subtitleTextColor: Color {
        get {
            Color(hex: subtitleTextColorHex) ?? Color(red: 0.29, green: 0.87, blue: 0.50)
        }
        set {
            subtitleTextColorHex = newValue.toHex() ?? "#4ADE80"
        }
    }

    public var subtitleBackgroundScrimOpacity: Double {
        didSet {
            UserDefaults.standard.set(subtitleBackgroundScrimOpacity, forKey: Self.subtitleScrimOpacityKey)
        }
    }

    public var liveCaptionsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(liveCaptionsEnabled, forKey: Self.liveCaptionsEnabledKey)
        }
    }

    public var liveCaptionsEngine: LiveCaptionsEngine {
        didSet {
            UserDefaults.standard.set(liveCaptionsEngine.rawValue, forKey: Self.liveCaptionsEngineKey)
        }
    }

    public var batterySaverGuardEnabled: Bool {
        didSet {
            UserDefaults.standard.set(batterySaverGuardEnabled, forKey: Self.batterySaverGuardKey)
        }
    }

    // MARK: - 5. Updates & About Settings
    public var automaticallyCheckForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyCheckForUpdates, forKey: Self.autoCheckUpdatesKey)
        }
    }

    public var updateChannel: UpdateChannel {
        didSet {
            UserDefaults.standard.set(updateChannel.rawValue, forKey: Self.updateChannelKey)
        }
    }

    public var isBetaUpdatesEnabled: Bool {
        get {
            updateChannel == .beta
        }
        set {
            updateChannel = newValue ? .beta : .stable
        }
    }

    // MARK: - In-App Presentation State
    public var isSettingsPresented: Bool {
        get {
            LibraryManager.shared.selectedCategory == .settings
        }
        set {
            if newValue {
                LibraryManager.shared.navigate(to: .settings)
            } else if LibraryManager.shared.selectedCategory == .settings {
                LibraryManager.shared.goBack()
            }
        }
    }
    public var selectedSettingsTab: SettingsTab = .general

    // MARK: - Initialization
    public init() {
        let defaults = UserDefaults.standard

        // General
        if let modeStr = defaults.string(forKey: Self.defaultViewModeKey),
           let mode = ViewMode(rawValue: modeStr) {
            self.defaultViewMode = mode
        } else {
            self.defaultViewMode = .grid
        }

        if let resumeStr = defaults.string(forKey: Self.autoResumeModeKey),
           let resume = AutoResumeMode(rawValue: resumeStr) {
            self.autoResumeMode = resume
        } else {
            self.autoResumeMode = .ask
        }

        if defaults.object(forKey: Self.showAddVideoTileKey) != nil {
            self.showAddVideoTile = defaults.bool(forKey: Self.showAddVideoTileKey)
        } else {
            self.showAddVideoTile = true
        }

        // Playback
        if let engStr = defaults.string(forKey: Self.videoPresentationEngineKey),
           let eng = VideoPresentationEngine(rawValue: engStr) {
            self.videoPresentationEngine = eng
        } else {
            self.videoPresentationEngine = .auto
        }

        if defaults.object(forKey: Self.animeDebandingKey) != nil {
            self.animeDebandingEnabled = defaults.bool(forKey: Self.animeDebandingKey)
        } else {
            self.animeDebandingEnabled = false
        }

        if defaults.object(forKey: Self.customVideoAdjustmentsKey) != nil {
            self.customVideoAdjustmentsEnabled = defaults.bool(forKey: Self.customVideoAdjustmentsKey)
        } else {
            self.customVideoAdjustmentsEnabled = false
        }

        if defaults.object(forKey: Self.hardwareAccelerationKey) != nil {
            self.hardwareAccelerationEnabled = defaults.bool(forKey: Self.hardwareAccelerationKey)
        } else {
            self.hardwareAccelerationEnabled = true
        }

        if let hdrStr = defaults.string(forKey: Self.hdrToneMappingKey),
           let hdr = HDRToneMappingMode(rawValue: hdrStr) {
            self.hdrToneMapping = hdr
        } else {
            self.hdrToneMapping = .auto
        }

        if defaults.object(forKey: Self.proMotionSyncKey) != nil {
            self.proMotionSyncEnabled = defaults.bool(forKey: Self.proMotionSyncKey)
        } else {
            self.proMotionSyncEnabled = true
        }

        if defaults.object(forKey: Self.defaultSkipIntervalKey) != nil {
            self.defaultSkipInterval = defaults.integer(forKey: Self.defaultSkipIntervalKey)
        } else {
            self.defaultSkipInterval = 5
        }

        // Audio
        if defaults.object(forKey: Self.spatialAudioKey) != nil {
            self.spatialAudioEnabled = defaults.bool(forKey: Self.spatialAudioKey)
        } else {
            self.spatialAudioEnabled = true
        }

        self.defaultAudioLanguage = defaults.string(forKey: Self.defaultAudioLanguageKey) ?? "System"

        if defaults.object(forKey: Self.volumeNormalizationKey) != nil {
            self.volumeNormalizationEnabled = defaults.bool(forKey: Self.volumeNormalizationKey)
        } else {
            self.volumeNormalizationEnabled = false
        }

        // Subtitles
        if defaults.object(forKey: Self.subtitleFontSizeKey) != nil {
            self.subtitleFontSize = defaults.double(forKey: Self.subtitleFontSizeKey)
        } else {
            self.subtitleFontSize = 20.0
        }

        self.subtitleTextColorHex = defaults.string(forKey: Self.subtitleTextColorHexKey) ?? "#4ADE80"

        if defaults.object(forKey: Self.subtitleScrimOpacityKey) != nil {
            self.subtitleBackgroundScrimOpacity = defaults.double(forKey: Self.subtitleScrimOpacityKey)
        } else {
            self.subtitleBackgroundScrimOpacity = 0.85
        }

        if defaults.object(forKey: Self.liveCaptionsEnabledKey) != nil {
            self.liveCaptionsEnabled = defaults.bool(forKey: Self.liveCaptionsEnabledKey)
        } else {
            self.liveCaptionsEnabled = false
        }

        if let lcStr = defaults.string(forKey: Self.liveCaptionsEngineKey),
           let lc = LiveCaptionsEngine(rawValue: lcStr) {
            self.liveCaptionsEngine = lc
        } else {
            self.liveCaptionsEngine = .appleNeuralEngine
        }

        if defaults.object(forKey: Self.batterySaverGuardKey) != nil {
            self.batterySaverGuardEnabled = defaults.bool(forKey: Self.batterySaverGuardKey)
        } else {
            self.batterySaverGuardEnabled = true
        }

        // Updates
        if defaults.object(forKey: Self.autoCheckUpdatesKey) != nil {
            self.automaticallyCheckForUpdates = defaults.bool(forKey: Self.autoCheckUpdatesKey)
        } else {
            self.automaticallyCheckForUpdates = true
        }

        if let channelStr = defaults.string(forKey: Self.updateChannelKey),
           let channel = UpdateChannel(rawValue: channelStr) {
            self.updateChannel = channel
        } else {
            self.updateChannel = .stable
        }
    }

    // MARK: - Battery & Power Guard (< 20%)
    /// Senses whether Mac is running on battery power and charge is below 20%.
    public var isBatteryBelowTwentyPercent: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for ps in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
               let state = desc[kIOPSPowerSourceStateKey as String] as? String,
               state == (kIOPSBatteryPowerValue as String),
               let currentCapacity = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let maxCapacity = desc[kIOPSMaxCapacityKey as String] as? Int,
               maxCapacity > 0 {
                let percent = (Double(currentCapacity) / Double(maxCapacity)) * 100.0
                return percent < 20.0
            }
        }
        return false
    }

    /// Automatically pauses live neural transcription when battery saver guard is active and battery < 20%.
    public var shouldPauseLiveCaptionsForBattery: Bool {
        batterySaverGuardEnabled && isBatteryBelowTwentyPercent
    }

    // MARK: - Actions
    public func clearWatchHistory() {
        LibraryManager.shared.clearRecentAndHistory()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    public func resetToDefaults() {
        defaultViewMode = .grid
        LibraryManager.shared.viewMode = .grid
        autoResumeMode = .ask
        showAddVideoTile = true
        videoPresentationEngine = .auto
        animeDebandingEnabled = false
        customVideoAdjustmentsEnabled = false
        hardwareAccelerationEnabled = true
        hdrToneMapping = .auto
        proMotionSyncEnabled = true
        defaultSkipInterval = 5
        spatialAudioEnabled = true
        defaultAudioLanguage = "System"
        volumeNormalizationEnabled = false
        subtitleFontSize = 20.0
        subtitleTextColorHex = "#4ADE80"
        subtitleBackgroundScrimOpacity = 0.85
        liveCaptionsEnabled = false
        liveCaptionsEngine = .appleNeuralEngine
        batterySaverGuardEnabled = true
        automaticallyCheckForUpdates = true
    }

    @MainActor
    public func openSettings(tab: SettingsTab? = nil) {
        if let tab = tab {
            self.selectedSettingsTab = tab
        }
        LibraryManager.shared.navigate(to: .settings)
    }

    @MainActor
    public func closeSettings() {
        if LibraryManager.shared.selectedCategory == .settings {
            LibraryManager.shared.goBack()
        }
    }

    @MainActor
    public func toggleSettings() {
        if LibraryManager.shared.selectedCategory == .settings {
            LibraryManager.shared.goBack()
        } else {
            LibraryManager.shared.navigate(to: .settings)
        }
    }
}
