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
            .animation(reduceMotion ? nil : spring, value: configuration.isPressed)
    }
}

// MARK: - Fluid Volume Slider with Smooth Thumb Hover Expansion

public struct FluidVolumeSlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var volume: Float
    var onMuteToggle: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var dragVolume: Float? = nil

    private var effectiveVolume: Float {
        dragVolume ?? volume
    }

    public init(volume: Binding<Float>, onMuteToggle: (() -> Void)? = nil) {
        self._volume = volume
        self.onMuteToggle = onMuteToggle
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let thumbRadius: CGFloat = (isHovering || isDragging) ? 6 : 4
            let trackHeight: CGFloat = (isHovering || isDragging) ? 4.5 : 3.5
            let fillWidth = max(0, min(width, width * CGFloat(effectiveVolume)))

            ZStack(alignment: .leading) {
                // Inactive Track
                Capsule(style: .continuous)
                    .fill(ShadcnTheme.secondary.opacity(0.6))
                    .frame(height: trackHeight)

                // Active Filled Track (Preset b1VlK05Q Monochrome Neutral)
                Capsule(style: .continuous)
                    .fill(ShadcnTheme.foreground)
                    .frame(width: fillWidth, height: trackHeight)

                // Thumb with Smooth Spring Expansion on Hover & Drag
                Circle()
                    .fill(ShadcnTheme.foreground)
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(isHovering || isDragging ? 0.35 : 0.15), radius: 3, x: 0, y: 1)
                    .scaleEffect(isDragging ? 1.15 : 1.0)
                    .offset(x: max(0, min(width - thumbRadius * 2, fillWidth - thumbRadius)))
                    .animation(.spring(response: 0.22, dampingFraction: 0.74), value: isHovering)
                    .animation(.spring(response: 0.18, dampingFraction: 0.72), value: isDragging)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let clamped = max(0.0, min(1.0, value.location.x / width))
                        dragVolume = Float(clamped)
                        volume = Float(clamped)
                    }
                    .onEnded { value in
                        let clamped = max(0.0, min(1.0, value.location.x / width))
                        volume = Float(clamped)
                        dragVolume = nil
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        .pointingHand()
        .onHover { h in
            withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.74)) {
                isHovering = h
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(effectiveVolume * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                volume = min(1.0, volume + 0.05)
            case .decrement:
                volume = max(0.0, volume - 0.05)
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Shadcn Playback Dock HUD

public struct LiquidGlassHUD: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var windowManager = WindowManager.shared
    @State private var showVolumePopover = false
    @State private var isAudioHovered = false
    @State private var isSubtitlesHovered = false
    @State private var isSpeedHovered = false
    @State private var hoveredButton: String? = nil

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let isNarrow = windowManager.isCompact || windowManager.isQuarterScreen
        let showVolumeSlider = !isNarrow

        VStack(alignment: .trailing, spacing: 8) {
            // MARK: - Anchored Inspector Sheet (Subtitles, Audio, Speed)
            if let sheet = engine.activeInspectorSheet, sheet != .stats {
                HStack {
                    Spacer(minLength: 0)
                    Group {
                        switch sheet {
                        case .subtitles:
                            SubtitleSelectorPanel(engine: engine)
                        case .audio:
                            AudioSelectorPanel(engine: engine)
                        case .speed:
                            SpeedSelectorPanel(engine: engine)
                        case .stats:
                            EmptyView()
                        }
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)).combined(with: .offset(y: 6)),
                        removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)).combined(with: .offset(y: 4))
                    )
                )
            }

            // MARK: - Main Floating Dock Bar
            VStack(spacing: 8) {
                // MARK: - Timeline Scrubber & Monospaced Clocks
                HStack(spacing: 10) {
                    Text(TimeFormatting.format(seconds: engine.currentTime))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foreground)

                    CustomScrubber(engine: engine)
                        .frame(height: 20)
                        .pointingHand()

                    let remaining = max(0, engine.duration - engine.currentTime)
                    Text("-\(TimeFormatting.format(seconds: remaining))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 9)

            // MARK: - Primary Controls Bar
            HStack(spacing: isNarrow ? 8 : 12) {
                // MARK: Left Controls (Volume & Mute)
                HStack(spacing: 6) {
                    let isMuteHovered = hoveredButton == "volume"
                    Button {
                        if isNarrow {
                            showVolumePopover.toggle()
                        } else {
                            engine.toggleMute()
                        }
                    } label: {
                        Image(systemName: engine.isMuted ? "speaker.slash.fill" : (engine.volume < 0.25 ? "speaker.fill" : (engine.volume < 0.65 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(engine.isMuted ? ShadcnTheme.destructive : (isMuteHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(engine.isMuted ? ShadcnTheme.destructive.opacity(0.15) : (isMuteHovered ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .strokeBorder(engine.isMuted ? ShadcnTheme.destructive.opacity(0.35) : (isMuteHovered ? ShadcnTheme.borderActive : ShadcnTheme.borderSubtle), lineWidth: 1)
                            )
                            .shadow(color: isMuteHovered ? Color.white.opacity(0.06) : Color.clear, radius: 4, x: 0, y: 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TactileTransportButtonStyle())
                    .pointingHand()
                    .accessibilityLabel(engine.isMuted ? "Unmute" : "Mute")
                    .accessibilityValue("\(Int(engine.volume * 100))%")
                    .help(isNarrow ? "Volume Slider" : (engine.isMuted ? "Unmute (M)" : "Mute (M)"))
                    .onHover { h in
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                            hoveredButton = h ? "volume" : nil
                        }
                    }
                    .popover(isPresented: $showVolumePopover) {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Volume")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ShadcnTheme.foreground)
                                Spacer()
                                Text("\(Int(engine.volume * 100))%")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            }
                            FluidVolumeSlider(
                                volume: Binding(
                                    get: { engine.volume },
                                    set: {
                                        engine.volume = $0
                                        if engine.isMuted && $0 > 0 { engine.isMuted = false }
                                    }
                                )
                            )
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

                    if showVolumeSlider {
                        FluidVolumeSlider(
                            volume: Binding(
                                get: { engine.volume },
                                set: {
                                    engine.volume = $0
                                    if engine.isMuted && $0 > 0 {
                                        engine.isMuted = false
                                    }
                                }
                            )
                        )
                        .frame(width: 64)
                    }
                }

                Spacer(minLength: 8)

                // MARK: Center Transport Controls (Skip -10s, Primary Play/Pause, Skip +10s)
                HStack(spacing: 8) {
                    dockedButton(
                        id: "skip_back",
                        icon: "gobackward.10",
                        help: "Skip back 10s (← or J)",
                        accessibilityLabel: "Skip backward 10 seconds"
                    ) {
                        engine.skip(seconds: -10)
                    }

                    // Primary Play / Pause / Replay Button (High-Contrast Tactile Circle with Luminance Elevation)
                    let isPlayHovered = hoveredButton == "play"
                    Button {
                        engine.togglePlayPause()
                    } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ShadcnTheme.background)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(isPlayHovered ? ShadcnTheme.primaryHighlight : ShadcnTheme.foreground)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(isPlayHovered ? Color.white.opacity(0.4) : Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(isPlayHovered ? 0.35 : 0.22), radius: isPlayHovered ? 8 : 4, x: 0, y: isPlayHovered ? 3 : 2)
                            .contentShape(Circle())
                    }
                    .buttonStyle(TactileTransportButtonStyle(scale: 0.92))
                    .pointingHand()
                    .accessibilityLabel(engine.isPlaying ? "Pause" : (engine.hasEnded ? "Replay" : "Play"))
                    .accessibilityHint("Toggles video playback")
                    .help(engine.isPlaying ? "Pause (Space)" : (engine.hasEnded ? "Replay (Space)" : "Play (Space)"))
                    .onHover { h in
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                            hoveredButton = h ? "play" : nil
                        }
                    }

                    dockedButton(
                        id: "skip_fwd",
                        icon: "goforward.10",
                        help: "Skip forward 10s (→ or L)",
                        accessibilityLabel: "Skip forward 10 seconds"
                    ) {
                        engine.skip(seconds: 10)
                    }
                }

                Spacer(minLength: 8)

                // MARK: Right Utility Controls (Audio, Subtitles, Speed, PiP, Fullscreen)
                HStack(spacing: 6) {
                    audioSelectorButton(isNarrow: isNarrow)
                    subtitlesSelectorButton(isNarrow: isNarrow)
                    speedSelectorButton()

                    dockedButton(
                        id: "pip",
                        icon: PictureInPictureManager.shared.isPictureInPicture ? "pip.exit" : "pip.enter",
                        help: PictureInPictureManager.shared.isPictureInPicture ? "Exit Picture in Picture" : "Enter Picture in Picture (P)",
                        accessibilityLabel: PictureInPictureManager.shared.isPictureInPicture ? "Exit Picture in Picture" : "Enter Picture in Picture"
                    ) {
                        PictureInPictureManager.shared.toggle(engine: engine)
                    }

                    dockedButton(
                        id: "fullscreen",
                        icon: windowManager.isNativeFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        help: windowManager.isNativeFullscreen ? "Exit Fullscreen (Esc)" : "Enter Fullscreen (F)",
                        accessibilityLabel: windowManager.isNativeFullscreen ? "Exit Fullscreen" : "Enter Fullscreen"
                    ) {
                        windowManager.toggleNativeFullscreen()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 9)
        }
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 0)
    }
    .frame(maxWidth: 720)
    .padding(.horizontal, 20)
    .padding(.bottom, 20)
    .environment(\.colorScheme, .dark)
    .animation(.spring(response: 0.26, dampingFraction: 0.76), value: engine.activeInspectorSheet)
    }

    public static func formatRate(_ rate: Float) -> String {
        if abs(rate.truncatingRemainder(dividingBy: 0.5)) < 0.001 || abs(rate.truncatingRemainder(dividingBy: 1.0)) < 0.001 {
            return String(format: "%.1fx", rate)
        } else {
            return String(format: "%.2fx", rate)
        }
    }

    private var audioButtonLabel: String {
        if let track = engine.selectedAudioTrack {
            if let lang = track.languageCode, !lang.isEmpty {
                let d = LanguageHelper.displayName(for: lang)
                if d != "Undetermined" && d != "Unknown" {
                    return d
                }
            }
            return track.title
        }
        return "Audio"
    }

    private func audioSelectorButton(isNarrow: Bool) -> some View {
        let isOpen = engine.activeInspectorSheet == .audio

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) {
                engine.activeInspectorSheet = (isOpen ? nil : .audio)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOpen ? "speaker.wave.2.bubble.fill" : "speaker.wave.2.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOpen ? ShadcnTheme.foreground : (isAudioHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary))

                if !isNarrow {
                    Text(audioButtonLabel)
                        .font(.system(size: 11, weight: isOpen ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 95)
                        .truncationMode(.tail)
                        .foregroundStyle(isOpen ? ShadcnTheme.foreground : (isAudioHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary))
                }
            }
            .padding(.horizontal, isNarrow ? 7 : 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isOpen ? ShadcnTheme.card : (isAudioHovered ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isOpen ? ShadcnTheme.borderActive : (isAudioHovered ? ShadcnTheme.borderActive : ShadcnTheme.borderSubtle), lineWidth: 1)
            )
            .shadow(color: isAudioHovered ? Color.white.opacity(0.06) : Color.clear, radius: 4, x: 0, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileTransportButtonStyle(scale: 0.96))
        .pointingHand()
        .accessibilityLabel("Audio track")
        .accessibilityValue(audioButtonLabel)
        .onHover { h in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                isAudioHovered = h
            }
        }
        .help(isOpen ? "Close Audio Settings" : "Select Audio Track & Channels")
    }

    private func subtitlesSelectorButton(isNarrow: Bool) -> some View {
        let isOpen = engine.activeInspectorSheet == .subtitles
        let isSubOn = engine.selectedSubtitleTrack.id != SubtitleTrack.off.id
        let subTitle = isSubOn ? engine.selectedSubtitleTrack.title : "Subtitles"

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) {
                engine.activeInspectorSheet = (isOpen ? nil : .subtitles)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: (isOpen || isSubOn) ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSubOn ? ShadcnTheme.foreground : (isOpen ? ShadcnTheme.foreground : (isSubtitlesHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)))

                if !isNarrow {
                    Text(subTitle)
                        .font(.system(size: 11, weight: (isOpen || isSubOn) ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 100)
                        .truncationMode(.tail)
                        .foregroundStyle(isSubOn ? ShadcnTheme.foreground : (isOpen ? ShadcnTheme.foreground : (isSubtitlesHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)))
                }
            }
            .padding(.horizontal, isNarrow ? 7 : 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isOpen ? ShadcnTheme.card : (isSubtitlesHovered ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isOpen ? ShadcnTheme.borderActive : (isSubOn ? ShadcnTheme.borderActive : (isSubtitlesHovered ? ShadcnTheme.borderActive : ShadcnTheme.borderSubtle)), lineWidth: 1)
            )
            .shadow(color: isSubtitlesHovered ? Color.white.opacity(0.06) : Color.clear, radius: 4, x: 0, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileTransportButtonStyle(scale: 0.96))
        .pointingHand()
        .accessibilityLabel("Subtitles")
        .accessibilityValue(subTitle)
        .onHover { h in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                isSubtitlesHovered = h
            }
        }
        .help(isOpen ? "Close Subtitle Settings" : "Subtitles, Captions & Timing")
    }

    private func speedSelectorButton() -> some View {
        let isOpen = engine.activeInspectorSheet == .speed
        let isNonStandard = abs(engine.playbackRate - 1.0) > 0.01

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) {
                engine.activeInspectorSheet = (isOpen ? nil : .speed)
            }
        } label: {
            Text(Self.formatRate(engine.playbackRate))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isNonStandard ? ShadcnTheme.foreground : (isOpen ? ShadcnTheme.foreground : (isSpeedHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(isOpen ? ShadcnTheme.card : (isSpeedHovered ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(isOpen ? ShadcnTheme.borderActive : (isNonStandard ? ShadcnTheme.borderActive : (isSpeedHovered ? ShadcnTheme.borderActive : ShadcnTheme.borderSubtle)), lineWidth: 1)
                )
                .shadow(color: isSpeedHovered ? Color.white.opacity(0.06) : Color.clear, radius: 4, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(TactileTransportButtonStyle(scale: 0.96))
        .pointingHand()
        .accessibilityLabel("Playback speed")
        .accessibilityValue(Self.formatRate(engine.playbackRate))
        .onHover { h in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                isSpeedHovered = h
            }
        }
        .help(isOpen ? "Close Speed Settings" : "Playback Speed")
    }

    private func dockedButton(id: String, icon: String, help: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) -> some View {
        let isHovered = hoveredButton == id
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(isHovered ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(isHovered ? ShadcnTheme.borderActive : ShadcnTheme.borderSubtle, lineWidth: 1)
                )
                .shadow(color: isHovered ? Color.white.opacity(0.08) : Color.clear, radius: 4, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(TactileTransportButtonStyle())
        .pointingHand()
        .help(help)
        .accessibilityLabel(accessibilityLabel ?? help)
        .onHover { h in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                hoveredButton = h ? id : nil
            }
        }
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
