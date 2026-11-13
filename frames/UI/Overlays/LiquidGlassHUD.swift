import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Emil Kowalski Tactile Button Styles

private struct TactileTransportButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.93
    var spring: Animation = .spring(response: 0.24, dampingFraction: 0.74)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .animation(.fluidQuick, value: configuration.isPressed)
    }
}

// MARK: - Fluid Volume Slider with Smooth Thumb Hover Expansion

public struct FluidVolumeSlider: View {
    @Binding var volume: Float
    var isMuted: Bool = false

    public init(volume: Binding<Float>, isMuted: Bool = false) {
        self._volume = volume
        self.isMuted = isMuted
    }

    public var body: some View {
        // Default macOS slider look: native track, accent fill and round knob.
        Slider(
            value: Binding(
                get: { isMuted ? 0 : Double(volume) },
                set: { volume = Float($0) }
            ),
            in: 0...1
        )
        .controlSize(.small)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(isMuted ? 0 : Int(volume * 100))%")
    }
}

// MARK: - Shadcn Playback Dock HUD

public struct LiquidGlassHUD: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var windowManager = WindowManager.shared
    @State private var showVolumePopover = false
    @State private var hoveredButton: String? = nil

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let isNarrow = windowManager.isCompact || windowManager.isQuarterScreen

        VStack(alignment: .trailing, spacing: 8) {
            // MARK: - Anchored Speed Sheet (Audio & Subtitles live in the side cluster)
            if engine.activeInspectorSheet == .speed {
                HStack {
                    Spacer(minLength: 0)
                    SpeedSelectorPanel(engine: engine)
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)).combined(with: .offset(y: 6)),
                        removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)).combined(with: .offset(y: 4))
                    )
                )
            }

            // MARK: - Tier 2: Large centered transport (fades in with the controls)
            HStack(spacing: 22) {
                circleButton(
                    id: "skip_back",
                    icon: "gobackward.10",
                    size: 40,
                    help: "Skip back 10s (← or J)",
                    accessibilityLabel: "Skip backward 10 seconds"
                ) {
                    engine.skip(seconds: -10)
                }

                playPauseButton()

                circleButton(
                    id: "skip_fwd",
                    icon: "goforward.10",
                    size: 40,
                    help: "Skip forward 10s (→ or L)",
                    accessibilityLabel: "Skip forward 10 seconds"
                ) {
                    engine.skip(seconds: 10)
                }
            }
            .frame(maxWidth: .infinity)

            // MARK: - Compact utility pill
            HStack(spacing: 3) {
                muteButton(isNarrow: isNarrow)

                if !isNarrow {
                    FluidVolumeSlider(volume: volumeBinding, isMuted: engine.isMuted)
                        .frame(width: 74)
                        .padding(.horizontal, 4)
                }

                utilityDivider

                rateButton()

                utilityDivider

                circleButton(
                    id: "pip",
                    icon: PictureInPictureManager.shared.isPictureInPicture ? "pip.exit" : "pip.enter",
                    help: PictureInPictureManager.shared.isPictureInPicture ? "Exit Picture in Picture (P)" : "Enter Picture in Picture (P)",
                    accessibilityLabel: PictureInPictureManager.shared.isPictureInPicture ? "Exit Picture in Picture" : "Enter Picture in Picture"
                ) {
                    PictureInPictureManager.shared.toggle(engine: engine)
                }

                circleButton(
                    id: "fullscreen",
                    icon: windowManager.isNativeFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: windowManager.isNativeFullscreen ? "Exit Fullscreen (Esc)" : "Enter Fullscreen (F)",
                    accessibilityLabel: windowManager.isNativeFullscreen ? "Exit Fullscreen" : "Enter Fullscreen"
                ) {
                    windowManager.toggleNativeFullscreen()
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .background(Capsule(style: .continuous).fill(ShadcnTheme.card.opacity(0.55)))
            .overlay(Capsule(style: .continuous).strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
            .frame(maxWidth: .infinity)

            // MARK: - Tier 2: Expanded timeline
            PlaybackTimelineRow(engine: engine)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .environment(\.colorScheme, .dark)
        .animation(.fluidQuick, value: engine.activeInspectorSheet)
    }

    public static func formatRate(_ rate: Float) -> String {
        if abs(rate.truncatingRemainder(dividingBy: 0.5)) < 0.001 || abs(rate.truncatingRemainder(dividingBy: 1.0)) < 0.001 {
            return String(format: "%.1fx", rate)
        } else {
            return String(format: "%.2fx", rate)
        }
    }

    private var volumeBinding: Binding<Float> {
        Binding(
            get: { engine.volume },
            set: {
                engine.volume = $0
                if engine.isMuted && $0 > 0 { engine.isMuted = false }
            }
        )
    }

    private func toggleInspector(_ sheet: VideoPlayerEngine.InspectorSheet) {
        withAnimation(.fluidQuick) {
            engine.activeInspectorSheet = (engine.activeInspectorSheet == sheet ? nil : sheet)
        }
    }

    private var utilityDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
    }

    /// Large centered glass play / pause / replay control.
    private func playPauseButton() -> some View {
        let isHovered = hoveredButton == "play"
        return Button {
            engine.togglePlayPause()
        } label: {
            Image(systemName: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ShadcnTheme.background)
                .frame(width: 54, height: 54)
                .background(Circle().fill(isHovered ? ShadcnTheme.primaryHighlight : ShadcnTheme.foreground))
                .overlay(Circle().strokeBorder(Color.white.opacity(isHovered ? 0.40 : 0.15), lineWidth: 1))
                .shadow(
                    color: Color.black.opacity(isHovered ? 0.35 : 0.22),
                    radius: isHovered ? 10 : 5,
                    x: 0,
                    y: isHovered ? 4 : 2
                )
                .contentShape(Circle())
        }
        .buttonStyle(TactileTransportButtonStyle(scale: 0.92))
        .pointingHand()
        .accessibilityLabel(engine.isPlaying ? "Pause" : (engine.hasEnded ? "Replay" : "Play"))
        .accessibilityHint("Toggles video playback")
        .help(engine.isPlaying ? "Pause (Space)" : (engine.hasEnded ? "Replay (Space)" : "Play (Space)"))
        .onHover { h in
            withAnimation(.fluidQuick) {
                hoveredButton = h ? "play" : nil
            }
        }
    }

    private func circleButton(
        id: String,
        icon: String,
        size: CGFloat = 30,
        iconSize: CGFloat = 12,
        active: Bool = false,
        help: String,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredButton == id
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(active || isHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(active ? ShadcnTheme.cardHover : (isHovered ? Color.white.opacity(0.10) : Color.clear))
                )
                .overlay(
                    Circle().strokeBorder(active || isHovered ? ShadcnTheme.borderActive : Color.clear, lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(TactileTransportButtonStyle(scale: 0.92))
        .pointingHand()
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
        .onHover { h in
            withAnimation(.fluidQuick) {
                hoveredButton = h ? id : nil
            }
        }
    }

    private func rateButton() -> some View {
        let isOpen = engine.activeInspectorSheet == .speed
        let isHovered = hoveredButton == "speed"
        let isNonStandard = abs(engine.playbackRate - 1.0) > 0.01
        return Button {
            toggleInspector(.speed)
        } label: {
            Text(Self.formatRate(engine.playbackRate))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isNonStandard || isOpen || isHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                .frame(height: 30)
                .padding(.horizontal, 8)
                .background(
                    Capsule().fill(isOpen ? ShadcnTheme.cardHover : (isHovered ? Color.white.opacity(0.10) : Color.clear))
                )
                .overlay(
                    Capsule().strokeBorder(isOpen || isNonStandard ? ShadcnTheme.borderActive : Color.clear, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(TactileTransportButtonStyle(scale: 0.94))
        .pointingHand()
        .help(isOpen ? "Close Speed Settings" : "Playback Speed")
        .accessibilityLabel("Playback speed")
        .accessibilityValue(Self.formatRate(engine.playbackRate))
        .onHover { h in
            withAnimation(.fluidQuick) {
                hoveredButton = h ? "speed" : nil
            }
        }
    }

    private func muteButton(isNarrow: Bool) -> some View {
        let isHovered = hoveredButton == "mute"
        return Button {
            if isNarrow {
                showVolumePopover.toggle()
            } else {
                engine.toggleMute()
            }
        } label: {
            Image(systemName: engine.isMuted
                  ? "speaker.slash.fill"
                  : (engine.volume < 0.25 ? "speaker.fill" : (engine.volume < 0.65 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(engine.isMuted ? ShadcnTheme.destructive : (isHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(engine.isMuted ? ShadcnTheme.destructive.opacity(0.15) : (isHovered ? Color.white.opacity(0.10) : Color.clear))
                )
                .overlay(
                    Circle().strokeBorder(engine.isMuted ? ShadcnTheme.destructive.opacity(0.35) : Color.clear, lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(TactileTransportButtonStyle(scale: 0.92))
        .pointingHand()
        .accessibilityLabel(engine.isMuted ? "Unmute" : "Mute")
        .accessibilityValue("\(engine.isMuted ? 0 : Int(engine.volume * 100))%")
        .help(isNarrow ? "Volume Slider" : (engine.isMuted ? "Unmute (M)" : "Mute (M)"))
        .onHover { h in
            withAnimation(.fluidQuick) {
                hoveredButton = h ? "mute" : nil
            }
        }
        .popover(isPresented: $showVolumePopover) {
            VStack(spacing: 8) {
                HStack {
                    Text("Volume")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foreground)
                    Spacer()
                    Text("\(engine.isMuted ? 0 : Int(engine.volume * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                }
                FluidVolumeSlider(volume: volumeBinding, isMuted: engine.isMuted)
                    .frame(width: 130)

                Button(engine.isMuted ? "Unmute" : "Mute") {
                    engine.toggleMute()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ShadcnTheme.foreground)
                .buttonStyle(TactileTransportButtonStyle(scale: 0.96))
                .pointingHand()
            }
            .padding(10)
            .background(ShadcnTheme.popover)
            .environment(\.colorScheme, .dark)
        }
    }
}

// MARK: - Decoupled Playback Timeline Row
/// Reads the isolated PlaybackClockStore so only this row invalidates at the clock cadence,
/// instead of re-evaluating the whole dock (materials, shadows, every transport button) 20×/s.
public struct PlaybackTimelineRow: View {
    @Bindable var engine: VideoPlayerEngine

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let clock = engine.clockStore

        HStack(spacing: 10) {
            Text(TimeFormatting.format(seconds: clock.currentTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ShadcnTheme.foreground)

            CustomScrubber(engine: engine)
                .frame(height: 20)
                .pointingHand()

            Text("-\(TimeFormatting.format(seconds: max(0, clock.duration - clock.currentTime)))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ShadcnTheme.foregroundSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
    }
}

// MARK: - Decoupled Playback Time Display
public struct PlaybackTimeDisplay: View {
    public let clockStore: PlaybackClockStore
    @State private var showRemainingTime: Bool = false

    public init(clockStore: PlaybackClockStore) {
        self.clockStore = clockStore
    }

    public var body: some View {
        Button {
            showRemainingTime.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(TimeFormatting.format(seconds: clockStore.currentTime))
                    .foregroundStyle(ShadcnTheme.foreground)
                Text("/")
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                Text(showRemainingTime
                    ? "-\(TimeFormatting.format(seconds: max(0, clockStore.duration - clockStore.currentTime)))"
                    : TimeFormatting.format(seconds: clockStore.duration))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.leading, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileTransportButtonStyle(scale: 0.98))
        .pointingHand()
        .help(showRemainingTime ? "Click to show duration" : "Click to show remaining time")
        .accessibilityLabel(showRemainingTime ? "Remaining time display" : "Playback time display")
        .accessibilityValue("\(TimeFormatting.format(seconds: clockStore.currentTime)) of \(TimeFormatting.format(seconds: clockStore.duration))")
    }
}

// MARK: - Tier 1: Always-on Progress Line
/// Thin always-visible playback line pinned to the bottom edge. When the controls are
/// shown, the expanded timeline above it takes over and this line fades out.
public struct PlayerProgressLine: View {
    @Bindable var engine: VideoPlayerEngine

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let clock = engine.clockStore
        let pct = clock.duration > 0 ? min(max(clock.currentTime / clock.duration, 0), 1) : 0

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: proxy.size.width * pct)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .shadow(color: Color.black.opacity(0.30), radius: 3, x: 0, y: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Mid-Left Audio & Subtitle Cluster

/// Audio and subtitle settings float vertically centered on the left edge of the video,
/// with their panels opening beside the cluster instead of under the transport.
public struct PlayerSideControls: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var hoveredButton: String? = nil

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    private var audioLabel: String {
        if let track = engine.selectedAudioTrack {
            if let lang = track.languageCode, !lang.isEmpty {
                let display = LanguageHelper.displayName(for: lang)
                if display != "Undetermined" && display != "Unknown" {
                    return display
                }
            }
            return track.title
        }
        return "Audio"
    }

    private var isSubtitlesOn: Bool {
        engine.selectedSubtitleTrack.id != SubtitleTrack.off.id
    }

    private var subtitleLabel: String {
        isSubtitlesOn ? engine.selectedSubtitleTrack.title : "Subtitles"
    }

    private func toggle(_ sheet: VideoPlayerEngine.InspectorSheet) {
        withAnimation(.fluidQuick) {
            engine.activeInspectorSheet = (engine.activeInspectorSheet == sheet ? nil : sheet)
        }
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 4) {
                sideButton(
                    id: "audio",
                    icon: engine.activeInspectorSheet == .audio ? "speaker.wave.2.bubble.fill" : "speaker.wave.2.bubble",
                    active: engine.activeInspectorSheet == .audio || engine.selectedAudioTrack != nil,
                    help: "\(audioLabel) (Audio Track)",
                    accessibilityLabel: "Audio track",
                    accessibilityValue: audioLabel
                ) {
                    toggle(.audio)
                }

                sideButton(
                    id: "subtitles",
                    icon: isSubtitlesOn || engine.activeInspectorSheet == .subtitles ? "captions.bubble.fill" : "captions.bubble",
                    active: isSubtitlesOn || engine.activeInspectorSheet == .subtitles,
                    help: "Subtitles, Captions & Timing",
                    accessibilityLabel: "Subtitles",
                    accessibilityValue: subtitleLabel
                ) {
                    toggle(.subtitles)
                }
            }
            .padding(5)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .background(Capsule(style: .continuous).fill(ShadcnTheme.card.opacity(0.55)))
            .overlay(Capsule(style: .continuous).strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)

            if engine.activeInspectorSheet == .audio {
                AudioSelectorPanel(engine: engine)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -8)), removal: .opacity))
            } else if engine.activeInspectorSheet == .subtitles {
                SubtitleSelectorPanel(engine: engine)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -8)), removal: .opacity))
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 18)
        .animation(.fluidQuick, value: engine.activeInspectorSheet)
        .environment(\.colorScheme, .dark)
    }

    private func sideButton(
        id: String,
        icon: String,
        active: Bool,
        help: String,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredButton == id
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active || isHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(active ? ShadcnTheme.cardHover : (isHovered ? Color.white.opacity(0.10) : Color.clear))
                )
                .overlay(
                    Circle().strokeBorder(active || isHovered ? ShadcnTheme.borderActive : Color.clear, lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
        .onHover { isHovering in
            withAnimation(.fluidQuick) {
                hoveredButton = isHovering ? id : nil
            }
        }
    }
}
