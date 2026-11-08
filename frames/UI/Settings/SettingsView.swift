import SwiftUI
import AppKit

// MARK: - Reusable Settings Card Container

public struct SettingsSectionCard<Content: View>: View {
    public let title: String?
    public let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .textCase(.uppercase)
                    .padding(.leading, 2)
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                    .fill(ShadcnTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Root Settings View

public struct SettingsView: View {
    @Bindable private var settings = SettingsManager.shared
    public var onDismiss: (() -> Void)? = nil
    @State private var hoveredTab: SettingsTab? = nil
    @State private var hoveringClose: Bool = false

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar: Title + Tab Pills + Optional Close Button
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)

                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foreground)
                }

                Spacer()

                // Tab Switcher Pills
                HStack(spacing: 3) {
                    ForEach(SettingsTab.allCases) { tab in
                        let isSelected = settings.selectedSettingsTab == tab
                        Button {
                            withAnimation(.fluidQuick) {
                                settings.selectedSettingsTab = tab
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))

                                Text(tab.title)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isSelected ? ShadcnTheme.cardHover : (hoveredTab == tab ? ShadcnTheme.muted.opacity(0.4) : Color.clear))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .strokeBorder(isSelected ? ShadcnTheme.border : Color.clear, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .onHover { h in
                            withAnimation(.fluidQuick) {
                                hoveredTab = h ? tab : nil
                            }
                        }
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm + 2, style: .continuous)
                        .fill(ShadcnTheme.secondary.opacity(0.4))
                )

                if let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        ZStack {
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(hoveringClose ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(hoveringClose ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                        }
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help("Close (Esc)")
                    .onHover { hoveringClose = $0 }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(ShadcnTheme.card)

            Divider()
                .overlay(ShadcnTheme.border)

            // Active Tab Content
            Group {
                switch settings.selectedSettingsTab {
                case .general:
                    GeneralSettingsTab()
                case .playback:
                    PlaybackSettingsTab()
                case .audio:
                    AudioSettingsTab()
                case .subtitles:
                    SubtitlesSettingsTab()
                case .about:
                    AboutSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShadcnTheme.background)
        }
        .background(ShadcnTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - In-App Settings Dialog Overlay

public struct InAppSettingsDialog: View {
    public var onDismiss: () -> Void
    @State private var keyMonitor: Any? = nil

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed ambient backdrop with tap gesture to dismiss
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }

                // In-app Settings Card
                SettingsView(onDismiss: onDismiss)
                    .frame(
                        width: min(620, max(460, geo.size.width - 48)),
                        height: min(560, max(360, geo.size.height - 64))
                    )
                    .shadow(color: Color.black.opacity(0.38), radius: 24, x: 0, y: 12)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC
                    onDismiss()
                    return nil
                }
                if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) && event.keyCode == 43 { // ⌘,
                    onDismiss()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }
}

// MARK: - 1. General Settings Tab

public struct GeneralSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared
    @State private var showClearConfirm = false
    @State private var historyClearedNotice = false

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Section: Library & Presentation
                SettingsSectionCard("Library & Layout") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default View Mode on Launch")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Initial layout presentation when opening the media dashboard.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.defaultViewMode) {
                            Text("Grid").tag(ViewMode.grid)
                            Text("List").tag(ViewMode.list)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }

                    Rectangle()
                        .fill(ShadcnTheme.borderSubtle)
                        .frame(height: 1)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pinned 'Add Video' Tile")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Show dashed quick-import card in the All Videos grid.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.showAddVideoTile)
                            .toggleStyle(.switch)
                    }
                }

                // Section: Playback Behavior
                SettingsSectionCard("Playback Session") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Resume Playback")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Behavior when opening media that was previously paused.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.autoResumeMode) {
                            ForEach(AutoResumeMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 210)
                    }
                }

                // Section: History & Privacy
                SettingsSectionCard("Watch History") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear Recent Files & Watch History")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Wipe all saved timestamps and reset the recent videos list.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        ShadcnButton(
                            historyClearedNotice ? "Cleared" : "Clear History",
                            icon: historyClearedNotice ? "checkmark" : "trash",
                            variant: .outline,
                            size: .sm
                        ) {
                            showClearConfirm = true
                        }
                    }
                }
            }
            .padding(18)
        }
        .confirmationDialog(
            "Clear Watch History?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All Watch History", role: .destructive) {
                settings.clearWatchHistory()
                historyClearedNotice = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    historyClearedNotice = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset playback progress on all videos and empty the Recent Videos category. Your actual media files will not be touched.")
        }
    }
}

// MARK: - 2. Playback & Video Settings Tab

public struct PlaybackSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Hardware Acceleration
                SettingsSectionCard("Apple Silicon Hardware Engine") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("VideoToolbox Hardware Acceleration")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ShadcnTheme.foreground)
                                Text("ASIC")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(ShadcnTheme.primaryForeground)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(ShadcnTheme.primary)
                                    )
                            }
                            Text("Direct hardware decode for H.264, HEVC, VP9, and ProRes with zero CPU load.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.hardwareAccelerationEnabled)
                            .toggleStyle(.switch)
                    }
                }

                // Display & Refresh
                SettingsSectionCard("Display & Color Presentation") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HDR Tone Mapping")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Opto-electronic transfer function (ST 2084 PQ / HLG / Rec. 709).")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.hdrToneMapping) {
                            ForEach(HDRToneMappingMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 210)
                    }

                    Rectangle()
                        .fill(ShadcnTheme.borderSubtle)
                        .frame(height: 1)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ProMotion 120Hz Synchronization")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Lock CADisplayLink cadence to ProMotion 120Hz display refresh.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.proMotionSyncEnabled)
                            .toggleStyle(.switch)
                    }
                }

                // Navigation & Seeking
                SettingsSectionCard("Seeking & Shortcuts") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Skip Interval")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Seconds jumped when tapping Left / Right arrow keys (⇧ jumps 30s).")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.defaultSkipInterval) {
                            Text("5s").tag(5)
                            Text("10s").tag(10)
                            Text("15s").tag(15)
                            Text("30s").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - 3. Audio & Spatial Settings Tab

public struct AudioSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared

    private let languages = [
        "System",
        "English",
        "Japanese",
        "Spanish",
        "French",
        "German",
        "Chinese",
        "Hindi",
        "Original"
    ]

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Spatial Audio
                SettingsSectionCard("Spatial Immersion") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spatial Audio with Dynamic Head Tracking")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Multichannel CoreAudio binaural rendering for AirPods Pro and AirPods Max.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.spatialAudioEnabled)
                            .toggleStyle(.switch)
                    }
                }

                // Language Preferences
                SettingsSectionCard("Stream Selection") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Audio Language Preference")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Automatically selects matching audio stream on multi-language videos.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.defaultAudioLanguage) {
                            ForEach(languages, id: \.self) { lang in
                                Text(lang == "System" ? "System Default" : lang).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }
                }

                // Audio Normalization
                SettingsSectionCard("Night Mode & Equalization") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Volume Normalization (Night Mode)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Dynamic range compression for balanced dialogue and restrained sound effects.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.volumeNormalizationEnabled)
                            .toggleStyle(.switch)
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - 4. Subtitles & Live Captions Settings Tab

public struct SubtitlesSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Subtitle Display Styling
                SettingsSectionCard("Subtitle Styling") {
                    // Font Size Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Font Size")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Spacer()
                            Text("\(Int(settings.subtitleFontSize)) pt")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Slider(value: $settings.subtitleFontSize, in: 14...36, step: 1)
                            .tint(ShadcnTheme.primary)
                    }

                    Rectangle()
                        .fill(ShadcnTheme.borderSubtle)
                        .frame(height: 1)

                    // Text Color Picker
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Text Color")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Foreground color used for rendered subtitle cues.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { settings.subtitleTextColor },
                            set: { settings.subtitleTextColor = $0 }
                        ), supportsOpacity: false)
                        .labelsHidden()
                    }

                    Rectangle()
                        .fill(ShadcnTheme.borderSubtle)
                        .frame(height: 1)

                    // Scrim Opacity Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Background Scrim Opacity")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Spacer()
                            Text("\(Int(settings.subtitleBackgroundScrimOpacity * 100))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Slider(value: $settings.subtitleBackgroundScrimOpacity, in: 0.0...1.0, step: 0.05)
                            .tint(ShadcnTheme.primary)
                    }

                    // Live Interactive Preview Box
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live Preview")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)

                        ZStack {
                            // Cinematic preview backdrop
                            LinearGradient(
                                colors: [Color(red: 0.08, green: 0.12, blue: 0.16), Color(red: 0.18, green: 0.12, blue: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .overlay(
                                Image(systemName: "film")
                                    .font(.system(size: 48))
                                    .foregroundStyle(Color.white.opacity(0.06))
                            )

                            // Preview subtitle cue
                            Text("The quick brown fox jumps over the lazy dog.")
                                .font(.system(size: CGFloat(settings.subtitleFontSize), weight: .semibold))
                                .foregroundStyle(settings.subtitleTextColor)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                        .fill(Color.black.opacity(settings.subtitleBackgroundScrimOpacity))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                        )
                                )
                                .padding(.horizontal, 16)
                        }
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                    }
                    .padding(.top, 4)
                }

                // Real-Time On-Device Live Captions
                SettingsSectionCard("Real-Time On-Device Live Captions") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Real-Time Live Captions")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Transcribes media speech locally without network requests.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.liveCaptionsEnabled)
                            .toggleStyle(.switch)
                    }

                    if settings.liveCaptionsEnabled {
                        Rectangle()
                            .fill(ShadcnTheme.borderSubtle)
                            .frame(height: 1)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Neural Transcription Engine")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ShadcnTheme.foreground)
                                Text("Select the hardware-accelerated model backend.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.liveCaptionsEngine) {
                                ForEach(LiveCaptionsEngine.allCases) { eng in
                                    Text(eng.displayName).tag(eng)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 250)
                        }

                        Rectangle()
                            .fill(ShadcnTheme.borderSubtle)
                            .frame(height: 1)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Battery Saver Guard (< 20%)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ShadcnTheme.foreground)
                                Text("Automatically pause transcription on low battery.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settings.batterySaverGuardEnabled)
                                .toggleStyle(.switch)
                        }
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - 5. About & Updates Settings Tab

public struct AboutSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared
    private var updateManager = UpdateManager.shared
    @State private var showResetConfirm = false
    @State private var defaultsRestoredNotice = false

    public init() {}

    public var body: some View {
        let isChecking = updateManager.status == .checking

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // In-App OTA Updates
                SettingsSectionCard("Software Updates") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check for Updates Automatically")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Silently query GitHub Releases on launch for new updates.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $settings.automaticallyCheckForUpdates)
                            .toggleStyle(.switch)
                    }

                    Rectangle()
                        .fill(ShadcnTheme.borderSubtle)
                        .frame(height: 1)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manual Update Check")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text(lastCheckedString)
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        ShadcnButton(
                            isChecking ? "Checking for Updates..." : "Check for Updates Now...",
                            icon: "arrow.triangle.2.circlepath",
                            variant: .primary,
                            size: .sm
                        ) {
                            guard !isChecking else { return }
                            updateManager.checkForUpdates(manual: true)
                        }
                        .disabled(isChecking)
                    }
                }

                // Application & Architecture Badges
                SettingsSectionCard("About Frames") {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("Frames")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(ShadcnTheme.foreground)

                                Text("v\(updateManager.currentVersionString)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(ShadcnTheme.accentActive)
                                    )
                            }

                            Text("Minimal Apple Silicon Video Player & Media Dashboard")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)

                            HStack(spacing: 6) {
                                BadgeView(text: "Apple Silicon Native", icon: "cpu")
                                BadgeView(text: "VideoToolbox ASIC", icon: "bolt.fill")
                                BadgeView(text: "Metal 3 HDR", icon: "sparkles")
                            }
                            .padding(.top, 2)
                        }
                    }

                    Rectangle()
                        .fill(ShadcnTheme.borderSubtle)
                        .frame(height: 1)

                    // Privacy Guarantee
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(ShadcnTheme.primary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("100% Telemetry-Free Guarantee")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Frames is engineered for complete privacy. Zero analytics, crash reports, or user telemetry are ever collected or transmitted. All decoders and models run strictly on your Mac.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Rectangle()
                        .fill(ShadcnTheme.borderSubtle)
                        .frame(height: 1)

                    // Restore Defaults
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore Settings")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Reset all Frames preferences to initial factory defaults.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        }
                        Spacer()
                        ShadcnButton(
                            defaultsRestoredNotice ? "Defaults Restored" : "Restore All Defaults",
                            icon: defaultsRestoredNotice ? "checkmark" : "arrow.counterclockwise",
                            variant: .outline,
                            size: .sm
                        ) {
                            showResetConfirm = true
                        }
                    }
                }
            }
            .padding(18)
        }
        .confirmationDialog(
            "Restore All Defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore Factory Defaults", role: .destructive) {
                settings.resetToDefaults()
                defaultsRestoredNotice = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    defaultsRestoredNotice = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all playback, display, audio, and subtitle preferences back to their original values.")
        }
    }

    private var lastCheckedString: String {
        if let date = updateManager.lastCheckedDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Last checked: \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        return "Automatically checks periodically"
    }
}

// MARK: - Badge View Helper

private struct BadgeView: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(ShadcnTheme.foregroundMuted)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(ShadcnTheme.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
        )
    }
}
