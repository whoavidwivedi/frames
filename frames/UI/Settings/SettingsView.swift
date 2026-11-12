import SwiftUI
import AppKit

// MARK: - Color Panel Presenter for Seamless Native AppKit Integration

@MainActor
public final class ColorPanelPresenter: NSObject {
    public static let shared = ColorPanelPresenter()
    private var onColorChanged: ((Color) -> Void)?

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        let nsColor = sender.color
        if let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor.usingColorSpace(.deviceRGB) {
            let color = Color(
                red: Double(srgb.redComponent),
                green: Double(srgb.greenComponent),
                blue: Double(srgb.blueComponent),
                opacity: Double(srgb.alphaComponent)
            )
            onColorChanged?(color)
        }
    }

    public func show(color: Color, onColorChanged: @escaping (Color) -> Void) {
        self.onColorChanged = onColorChanged
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))

        let nsColor = NSColor(color)
        if let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor.usingColorSpace(.deviceRGB) {
            panel.color = srgb
        } else {
            panel.color = nsColor
        }

        panel.isContinuous = true
        panel.showsAlpha = false
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        if NSColorPanel.shared.isVisible {
            NSColorPanel.shared.orderOut(nil)
        }
    }
}

// MARK: - Reusable Shadcn Settings Card Container

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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)
                    .padding(.leading, 2)
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .fill(ShadcnTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
            )
        }
    }
}

// MARK: - Reusable Settings Divider

public struct SettingsDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(ShadcnTheme.borderSubtle)
            .frame(height: 1)
    }
}

// MARK: - Emil Kowalski Tactile Button Styles
public struct SettingsPillButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .animation(.fluidQuick, value: configuration.isPressed)
    }
}

// MARK: - Custom Fluid Slider with Thumb Hover Expansion
public struct SettingsSlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @State private var isHovered = false
    @State private var isDragging = false

    public init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1.0) {
        self._value = value
        self.range = range
        self.step = step
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbDiameter: CGFloat = isDragging ? 16 : (isHovered ? 16 : 12)
            let span = range.upperBound - range.lowerBound
            let normalized = span > 0 ? max(0.0, min(1.0, (value - range.lowerBound) / span)) : 0.0
            let availableWidth = max(0, width - thumbDiameter)
            let xOffset = normalized * availableWidth

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(ShadcnTheme.secondary)
                    .frame(height: 5)
                    .overlay(
                        Capsule().strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 0.5)
                    )

                // Active Track
                Capsule()
                    .fill(ShadcnTheme.primary)
                    .frame(width: max(5, min(width, xOffset + thumbDiameter / 2)), height: 5)

                // Expanding Thumb
                Circle()
                    .fill(ShadcnTheme.primaryHighlight)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(
                        Circle().strokeBorder(isHovered || isDragging ? ShadcnTheme.borderActive : ShadcnTheme.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(isHovered ? 0.30 : 0.12), radius: isHovered ? 4 : 2, x: 0, y: 1)
                    .offset(x: xOffset)
                    .animation(.fluidQuick, value: isHovered)
                    .animation(.fluidQuick, value: isDragging)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointingHand()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let pct = max(0.0, min(1.0, gesture.location.x / width))
                        let rawValue = range.lowerBound + pct * (range.upperBound - range.lowerBound)
                        let stepped = (rawValue / step).rounded() * step
                        let clamped = max(range.lowerBound, min(range.upperBound, stepped))
                        withAnimation(.fluidQuick) {
                            value = clamped
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { h in
                withAnimation(.fluidQuick) {
                    isHovered = h
                }
            }
        }
        .frame(height: 22)
    }
}

// MARK: - Root Settings View

private struct SettingsCompactEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var settingsCompact: Bool {
        get { self[SettingsCompactEnvironmentKey.self] }
        set { self[SettingsCompactEnvironmentKey.self] = newValue }
    }
}

public struct SettingsView: View {
    @State private var windowManager = WindowManager.shared

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let isSplit = windowManager.isSplitScreen || windowManager.isQuarterScreen || windowManager.isCompact
            let isCompact = isSplit || proxy.size.width < 620

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("Playback, audio, subtitles, and app preferences.")
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    }
                    .padding(.top, 4)

                    categorySection("General") {
                        GeneralSettingsTab()
                    }

                    categorySection("Playback") {
                        PlaybackSettingsTab()
                    }

                    categorySection("Audio") {
                        AudioSettingsTab()
                    }

                    categorySection("Subtitles") {
                        SubtitlesSettingsTab()
                    }

                    categorySection("About") {
                        AboutSettingsTab()
                    }
                }
                .padding(.horizontal, isCompact ? 14 : 24)
                .padding(.vertical, isCompact ? 16 : 24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.top)
            .environment(\.settingsCompact, isCompact)
        }
        .background(ShadcnTheme.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categorySection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)
                .padding(.bottom, 18)

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ShadcnTheme.foreground)
                .padding(.bottom, 12)

            content()
        }
    }
}

// MARK: - 1. General Settings Tab

public struct GeneralSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared
    @State private var showClearConfirm = false
    @State private var historyClearedNotice = false
    @Environment(\.settingsCompact) private var isCompact
    @Namespace private var viewModeNamespace

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section: Library & Layout
            SettingsSectionCard("Library & Layout") {
                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default View Mode on Launch")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Initial layout presentation when opening the media dashboard.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        viewModeButtonsGroup
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default View Mode on Launch")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Initial layout presentation when opening the media dashboard.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 16)
                        viewModeButtonsGroup
                    }
                }

                SettingsDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pinned 'Add Video' Tile")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("Show dashed quick-import card in the All Videos grid.")
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $settings.showAddVideoTile)
                        .toggleStyle(.switch)
                        .pointingHand()
                        .animation(.fluidQuick, value: settings.showAddVideoTile)
                }
            }

            // Section: Playback Behavior
            SettingsSectionCard("Playback Session") {
                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Resume Playback")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Behavior when opening media that was previously paused.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Picker("", selection: $settings.autoResumeMode) {
                            ForEach(AutoResumeMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pointingHand()
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Resume Playback")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Behavior when opening media that was previously paused.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 16)
                        Picker("", selection: $settings.autoResumeMode) {
                            ForEach(AutoResumeMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 210)
                        .pointingHand()
                    }
                }
            }

            // Section: History & Privacy
            SettingsSectionCard("Watch History") {
                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear Recent Files & Watch History")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Wipe all saved timestamps and reset the recent videos list.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ShadcnButton(
                            historyClearedNotice ? "Cleared" : "Clear History",
                            icon: historyClearedNotice ? "checkmark" : "trash",
                            variant: .outline,
                            size: .sm
                        ) {
                            showClearConfirm = true
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear Recent Files & Watch History")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Wipe all saved timestamps and reset the recent videos list.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 16)
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

    private var viewModeButtonsGroup: some View {
        HStack(spacing: 2) {
            viewModeButton(mode: .grid, icon: "square.grid.2x2", title: "Grid")
            viewModeButton(mode: .list, icon: "list.bullet", title: "List")
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ShadcnTheme.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func viewModeButton(mode: ViewMode, icon: String, title: String) -> some View {
        let isSelected = settings.defaultViewMode == mode
        return Button {
            withAnimation(.fluidQuick) {
                settings.defaultViewMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: 72, height: 26)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                        .matchedGeometryEffect(id: "activeViewModePill", in: viewModeNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPillButtonStyle())
        .pointingHand()
    }
}

// MARK: - 2. Playback & Video Settings Tab

public struct PlaybackSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared
    @Environment(\.settingsCompact) private var isCompact
    @Namespace private var skipIntervalNamespace

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $settings.hardwareAccelerationEnabled)
                        .toggleStyle(.switch)
                        .pointingHand()
                        .animation(.fluidQuick, value: settings.hardwareAccelerationEnabled)
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 6) {
                    if isCompact {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "cpu")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ShadcnTheme.primary)
                                Text(AppleSiliconMetrics.shared.chipName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(ShadcnTheme.foreground)
                            }
                            BadgeView(text: "\(AppleSiliconMetrics.shared.physicalMemoryGB) GB Unified Memory", icon: "memorychip")
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "cpu")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.primary)
                            Text(AppleSiliconMetrics.shared.chipName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShadcnTheme.foreground)
                            BadgeView(text: "\(AppleSiliconMetrics.shared.physicalMemoryGB) GB Unified Memory", icon: "memorychip")
                        }
                    }

                    Text(AppleSiliconMetrics.shared.gpuFamilyName + " • " + (AppleSiliconMetrics.shared.supportsHardwareAV1Decode ? "AV1 HW ASIC • " : "") + (AppleSiliconMetrics.shared.supportsHardwareProRes ? "ProRes HW ASIC • " : "") + "HEVC & H.264 Hardware Engines")
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Display & Refresh
            SettingsSectionCard("Display & Color Presentation") {
                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Presentation Engine")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Direct hardware scanout (0% GPU) or CAMetalLayer shaders.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Picker("", selection: $settings.videoPresentationEngine) {
                            ForEach(VideoPresentationEngine.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pointingHand()
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Presentation Engine")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Direct hardware scanout (0% GPU) or CAMetalLayer shaders.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 16)
                        Picker("", selection: $settings.videoPresentationEngine) {
                            ForEach(VideoPresentationEngine.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 210)
                        .pointingHand()
                    }
                }

                SettingsDivider()

                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HDR Tone Mapping")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Opto-electronic transfer function (ST 2084 PQ / HLG / Rec. 709).")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Picker("", selection: $settings.hdrToneMapping) {
                            ForEach(HDRToneMappingMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pointingHand()
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HDR Tone Mapping")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Opto-electronic transfer function (ST 2084 PQ / HLG / Rec. 709).")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 16)
                        Picker("", selection: $settings.hdrToneMapping) {
                            ForEach(HDRToneMappingMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 210)
                        .pointingHand()
                    }
                }

                SettingsDivider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ProMotion 120Hz Synchronization")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("Lock CADisplayLink cadence to ProMotion 120Hz display refresh.")
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $settings.proMotionSyncEnabled)
                        .toggleStyle(.switch)
                        .pointingHand()
                        .animation(.fluidQuick, value: settings.proMotionSyncEnabled)
                }
            }

            // Navigation & Seeking
            SettingsSectionCard("Seeking & Shortcuts") {
                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Skip Interval")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Seconds jumped when tapping Left / Right arrow keys (Shift jumps 30s).")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        skipIntervalButtonsGroup
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Skip Interval")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Seconds jumped when tapping Left / Right arrow keys (Shift jumps 30s).")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 16)
                        skipIntervalButtonsGroup
                    }
                }
            }
        }
    }

    private var skipIntervalButtonsGroup: some View {
        HStack(spacing: 2) {
            ForEach([5, 10, 15, 30], id: \.self) { seconds in
                let isSelected = settings.defaultSkipInterval == seconds
                Button {
                    withAnimation(.fluidQuick) {
                        settings.defaultSkipInterval = seconds
                    }
                } label: {
                    Text("\(seconds)s")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(width: 44, height: 26)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(ShadcnTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "activeSkipIntervalPill", in: skipIntervalNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(SettingsPillButtonStyle())
                .pointingHand()
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ShadcnTheme.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                )
        )
    }
}

// MARK: - 3. Audio & Spatial Settings Tab

public struct AudioSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared
    @Environment(\.settingsCompact) private var isCompact

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
        VStack(alignment: .leading, spacing: 18) {
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $settings.spatialAudioEnabled)
                        .toggleStyle(.switch)
                        .pointingHand()
                        .animation(.fluidQuick, value: settings.spatialAudioEnabled)
                }
            }

            // Language Preferences
            SettingsSectionCard("Stream Selection") {
                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Audio Language Preference")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Automatically selects matching audio stream on multi-language videos.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Picker("", selection: $settings.defaultAudioLanguage) {
                            ForEach(languages, id: \.self) { lang in
                                Text(lang == "System" ? "System Default" : lang).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pointingHand()
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Audio Language Preference")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Automatically selects matching audio stream on multi-language videos.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 16)
                        Picker("", selection: $settings.defaultAudioLanguage) {
                            ForEach(languages, id: \.self) { lang in
                                Text(lang == "System" ? "System Default" : lang).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        .pointingHand()
                    }
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $settings.volumeNormalizationEnabled)
                        .toggleStyle(.switch)
                        .pointingHand()
                        .animation(.fluidQuick, value: settings.volumeNormalizationEnabled)
                }
            }
        }
    }
}

// MARK: - 4. Subtitles & Live Captions Settings Tab

private struct SubtitleColorPreset: Identifiable {
    let id: String
    let name: String
    let hex: String
    let color: Color
}

public struct SubtitlesSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared
    @Environment(\.settingsCompact) private var isCompact
    @State private var sampleCueIndex = 0

    private let sampleLines = [
        "The stars don't look bigger, but they look brighter.",
        "All we have to decide is what to do with the time given us.",
        "Houston, Tranquility Base here. The Eagle has landed."
    ]

    private let textColorPresets: [SubtitleColorPreset] = [
        SubtitleColorPreset(id: "white", name: "White", hex: "#FFFFFF", color: Color.white),
        SubtitleColorPreset(id: "yellow", name: "Yellow", hex: "#FACC15", color: Color(red: 0.98, green: 0.80, blue: 0.08)),
        SubtitleColorPreset(id: "cyan", name: "Cyan", hex: "#38BDF8", color: Color(red: 0.22, green: 0.74, blue: 0.97)),
        SubtitleColorPreset(id: "green", name: "Green", hex: "#32D74B", color: Color(red: 0.20, green: 0.84, blue: 0.29))
    ]

    private let backgroundColorPresets: [SubtitleColorPreset] = [
        SubtitleColorPreset(id: "black", name: "Black", hex: "#000000", color: .black),
        SubtitleColorPreset(id: "charcoal", name: "Charcoal", hex: "#1C1C1E", color: Color(red: 0.11, green: 0.11, blue: 0.12)),
        SubtitleColorPreset(id: "navy", name: "Navy", hex: "#0F172A", color: Color(red: 0.06, green: 0.09, blue: 0.16)),
        SubtitleColorPreset(id: "white", name: "White", hex: "#FFFFFF", color: .white)
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Cinematic Live Preview Stage
            SettingsSectionCard("Cinematic Live Preview") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Real-Time Player Rendering")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)

                        Spacer()

                        Button {
                            withAnimation(.fluidQuick) {
                                sampleCueIndex = (sampleCueIndex + 1) % sampleLines.count
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 9.5))
                                Text("Next Cue")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(ShadcnTheme.secondary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SettingsPillButtonStyle())
                        .pointingHand()
                        .help("Cycle sample dialogue text")
                    }

                    // 16:9 Letterboxed Cinema Display Mockup
                    ZStack {
                        // Deep cinematic canvas
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.07, blue: 0.11),
                                Color(red: 0.02, green: 0.03, blue: 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        // Soft cinematic anamorphic backlight
                        RadialGradient(
                            colors: [
                                Color(red: 0.14, green: 0.22, blue: 0.32).opacity(0.35),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 180
                        )

                        // HUD Badges
                        VStack {
                            HStack {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color(red: 0.95, green: 0.25, blue: 0.25))
                                        .frame(width: 5, height: 5)
                                    Text("4K HDR • 24 FPS")
                                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.70))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(Color.black.opacity(0.50))
                                )

                                Spacer()

                                Text("01:24:18 / 02:48:30")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.65))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(Color.black.opacity(0.50))
                                    )
                            }
                            .padding(10)

                            Spacer()

                            // Default macOS-style subtitle rendering
                            SubtitleOverlayView(text: sampleLines[sampleCueIndex])
                                .padding(.bottom, 4)
                                .id(sampleCueIndex)
                        }
                    }
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
                }
            }

            // 2. Subtitle Appearance
            SettingsSectionCard("Subtitle Appearance") {
                VStack(alignment: .leading, spacing: 14) {
                    SubtitleColorRow(
                        title: "Text Color",
                        subtitle: "Dialogue color for all subtitle tracks.",
                        hex: $settings.subtitleTextColorHex,
                        presets: textColorPresets
                    )

                    SettingsDivider()

                    SubtitleColorRow(
                        title: "Background Color",
                        subtitle: "Color behind subtitle text.",
                        hex: $settings.subtitleBackgroundColorHex,
                        presets: backgroundColorPresets
                    )
                }
            }

            // 4. Real-Time On-Device Live Captions
            SettingsSectionCard("Real-Time On-Device Live Captions") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Real-Time Live Captions")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("Transcribes media speech locally without network requests.")
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $settings.liveCaptionsEnabled)
                        .toggleStyle(.switch)
                        .pointingHand()
                        .animation(.fluidQuick, value: settings.liveCaptionsEnabled)
                }

                if settings.liveCaptionsEnabled {
                    SettingsDivider()

                    if isCompact {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Neural Transcription Engine")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ShadcnTheme.foreground)
                                Text("Select the hardware-accelerated model backend.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Picker("", selection: $settings.liveCaptionsEngine) {
                                ForEach(LiveCaptionsEngine.allCases) { eng in
                                    Text(eng.displayName).tag(eng)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pointingHand()
                        }
                    } else {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Neural Transcription Engine")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ShadcnTheme.foreground)
                                Text("Select the hardware-accelerated model backend.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 16)
                            Picker("", selection: $settings.liveCaptionsEngine) {
                                ForEach(LiveCaptionsEngine.allCases) { eng in
                                    Text(eng.displayName).tag(eng)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 250)
                            .pointingHand()
                        }
                    }

                    SettingsDivider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Battery Saver Guard (< 20%)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Automatically pause transcription on low battery.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Toggle("", isOn: $settings.batterySaverGuardEnabled)
                            .toggleStyle(.switch)
                            .pointingHand()
                            .animation(.fluidQuick, value: settings.batterySaverGuardEnabled)
                    }
                }
            }
        }
    }
}

// MARK: - Subtitle Color Row

private struct SubtitleColorRow: View {
    let title: String
    let subtitle: String
    @Binding var hex: String
    let presets: [SubtitleColorPreset]

    private var currentColor: Color {
        Color(hex: hex) ?? .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ShadcnTheme.foreground)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 135), spacing: 8)], spacing: 8) {
                ForEach(presets) { preset in
                    let isSelected = hex.uppercased() == preset.hex.uppercased()

                    Button {
                        withAnimation(.fluidQuick) {
                            hex = preset.hex
                            ColorPanelPresenter.shared.close()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 12, height: 12)

                            Text(preset.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(isSelected ? ShadcnTheme.border : ShadcnTheme.borderSubtle.opacity(0.5), lineWidth: 1)
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                    .pointingHand()
                }

                let isCustom = !presets.contains { $0.hex.uppercased() == hex.uppercased() }

                Button {
                    ColorPanelPresenter.shared.show(color: currentColor) { newColor in
                        hex = newColor.toHex() ?? hex
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isCustom {
                            Circle()
                                .fill(currentColor)
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                                )
                        } else {
                            AngularGradient(
                                gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                                center: .center
                            )
                            .frame(width: 12, height: 12)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 0.5)
                            )
                        }

                        Text("Custom")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isCustom ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isCustom ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isCustom ? ShadcnTheme.border : ShadcnTheme.borderSubtle.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsPillButtonStyle())
                .pointingHand()
                .help("Choose custom subtitle \(title.lowercased())")
            }
        }
    }
}

// MARK: - 5. About & Updates Settings Tab

public struct SoftwareUpdatesSettingsCard: View {
    @Bindable private var settings = SettingsManager.shared
    private var updateManager = UpdateManager.shared
    @State private var windowManager = WindowManager.shared
    @Namespace private var channelNamespace
    public var isCompact: Bool = false

    public init(isCompact: Bool = false) {
        self.isCompact = isCompact
    }

    private var lastCheckedString: String {
        if let date = updateManager.lastCheckedDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Last checked: \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
        return "Automatically checks periodically"
    }

    public var body: some View {
        let isChecking = updateManager.status == .checking
        let isSplit = windowManager.isSplitScreen || windowManager.isQuarterScreen || windowManager.isCompact
        let compact = isCompact || isSplit

        SettingsSectionCard("Software Updates") {
            // 1. Automatic Update Check
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for Updates Automatically")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foreground)
                    Text("Silently query GitHub Releases on launch for new updates.")
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: $settings.automaticallyCheckForUpdates)
                    .toggleStyle(.switch)
                    .pointingHand()
                    .animation(.fluidQuick, value: settings.automaticallyCheckForUpdates)
            }

            SettingsDivider()

            // 2. Beta & Canary Updates Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receive Beta & Canary Updates")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foreground)
                    Text("Opt into preview builds and canary features before public release.")
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { settings.isBetaUpdatesEnabled },
                    set: { newValue in
                        settings.isBetaUpdatesEnabled = newValue
                    }
                ))
                .toggleStyle(.switch)
                .pointingHand()
                .animation(.fluidQuick, value: settings.isBetaUpdatesEnabled)
            }

            SettingsDivider()

            // 3. Update Channel Selector
            channelSelectorRow(compact: compact)

            SettingsDivider()

            // 4. Manual Update Check
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manual Update Check")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("Stream: \(settings.updateChannel.displayName) • \(lastCheckedString)")
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ShadcnButton(
                        isChecking ? "Checking for Updates..." : "Check for Updates",
                        icon: "arrow.triangle.2.circlepath",
                        variant: .primary,
                        size: .sm
                    ) {
                        guard !isChecking else { return }
                        updateManager.checkForUpdates(manual: true)
                    }
                    .disabled(isChecking)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manual Update Check")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("Stream: \(settings.updateChannel.displayName) • \(lastCheckedString)")
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    ShadcnButton(
                        isChecking ? "Checking for Updates..." : "Check for Updates",
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
        }
    }

    @ViewBuilder
    private func channelSelectorRow(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update Channel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("Select which release stream Frames downloads updates from.")
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    channelButtonsGroup
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update Channel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("Select which release stream Frames downloads updates from.")
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    channelButtonsGroup
                }
            }

            ChannelInfoBanner(channel: settings.updateChannel)
        }
    }

    private var channelButtonsGroup: some View {
        HStack(spacing: 2) {
            ForEach(UpdateChannel.allCases) { channel in
                ChannelButton(
                    channel: channel,
                    isSelected: settings.updateChannel == channel,
                    namespace: channelNamespace
                ) {
                    settings.updateChannel = channel
                }
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ShadcnTheme.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                )
        )
    }
}

private struct ChannelButton: View {
    let channel: UpdateChannel
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: {
            withAnimation(.fluidQuick) {
                action()
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: channel.badgeIcon)
                    .font(.system(size: 10, weight: .medium))
                Text(channel.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(width: 86, height: 26)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                        .matchedGeometryEffect(id: "activeChannelPill", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPillButtonStyle())
        .pointingHand()
    }
}

private struct ChannelInfoBanner: View {
    let channel: UpdateChannel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: channel == .beta ? "info.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(ShadcnTheme.foreground)
            Text(channel.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                .fill(ShadcnTheme.secondary.opacity(0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                )
        )
    }
}

public struct AboutSettingsTab: View {
    @Bindable private var settings = SettingsManager.shared
    private var updateManager = UpdateManager.shared
    @Environment(\.settingsCompact) private var isCompact
    @State private var showResetConfirm = false
    @State private var defaultsRestoredNotice = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // In-App OTA Updates
            SoftwareUpdatesSettingsCard(isCompact: isCompact)

            // Application & Architecture Badges
            SettingsSectionCard("About Frames") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: isCompact ? 44 : 56, height: isCompact ? 44 : 56)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Frames")
                                .font(.system(size: isCompact ? 16 : 18, weight: .bold))
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
                            .fixedSize(horizontal: false, vertical: true)

                        if isCompact {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    BadgeView(text: AppleSiliconMetrics.shared.generation.displayName, icon: "cpu")
                                    BadgeView(text: "VideoToolbox ASIC", icon: "bolt.fill")
                                }
                                BadgeView(text: "Metal 3 HDR", icon: "display")
                            }
                            .padding(.top, 2)
                        } else {
                            HStack(spacing: 6) {
                                BadgeView(text: AppleSiliconMetrics.shared.generation.displayName, icon: "cpu")
                                BadgeView(text: "VideoToolbox ASIC", icon: "bolt.fill")
                                BadgeView(text: "Metal 3 HDR", icon: "display")
                            }
                            .padding(.top, 2)
                        }
                    }
                }

                SettingsDivider()

                // Privacy Guarantee
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(ShadcnTheme.primary.opacity(0.12))
                        )

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
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                        .fill(ShadcnTheme.secondary.opacity(0.40))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                )

                SettingsDivider()

                // Restore Defaults
                if isCompact {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore Settings")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Reset all Frames preferences to initial factory defaults.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ShadcnButton(
                            defaultsRestoredNotice ? "Defaults Restored" : "Restore All Defaults",
                            icon: defaultsRestoredNotice ? "checkmark" : "arrow.counterclockwise",
                            variant: .outline,
                            size: .sm
                        ) {
                            showResetConfirm = true
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore Settings")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Reset all Frames preferences to initial factory defaults.")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 16)
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
