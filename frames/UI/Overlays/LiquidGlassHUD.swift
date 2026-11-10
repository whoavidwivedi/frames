import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

        VStack(spacing: 8) {
            // MARK: - Timeline Scrubber & Monospaced Clocks
            HStack(spacing: 10) {
                Text(TimeFormatting.format(seconds: engine.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foreground)

                CustomScrubber(engine: engine)
                    .frame(height: 20)

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
                    Button {
                        if isNarrow {
                            showVolumePopover.toggle()
                        } else {
                            engine.toggleMute()
                        }
                    } label: {
                        Image(systemName: engine.isMuted ? "speaker.slash.fill" : (engine.volume < 0.25 ? "speaker.fill" : (engine.volume < 0.65 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(engine.isMuted ? ShadcnTheme.destructive : ShadcnTheme.foreground)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(engine.isMuted ? ShadcnTheme.destructive.opacity(0.15) : (hoveredButton == "volume" ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .strokeBorder(engine.isMuted ? ShadcnTheme.destructive.opacity(0.35) : (hoveredButton == "volume" ? ShadcnTheme.borderActive : ShadcnTheme.borderSubtle), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .accessibilityLabel(engine.isMuted ? "Unmute" : "Mute")
                    .accessibilityValue("\(Int(engine.volume * 100))%")
                    .help(isNarrow ? "Volume Slider" : (engine.isMuted ? "Unmute (M)" : "Mute (M)"))
                    .onHover { h in hoveredButton = h ? "volume" : nil }
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
                            Slider(
                                value: Binding(
                                    get: { Double(engine.volume) },
                                    set: {
                                        engine.volume = Float($0)
                                        if engine.isMuted && $0 > 0 { engine.isMuted = false }
                                    }
                                ),
                                in: 0...1
                            )
                            .frame(width: 120)
                            .tint(ShadcnTheme.primary)
                            .accessibilityLabel("Volume")

                            Button(engine.isMuted ? "Unmute" : "Mute") {
                                engine.toggleMute()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                            .buttonStyle(.plain)
                            .pointingHand()
                        }
                        .padding(10)
                        .background(ShadcnTheme.popover)
                        .environment(\.colorScheme, .dark)
                    }

                    if showVolumeSlider {
                        Slider(
                            value: Binding(
                                get: { Double(engine.volume) },
                                set: {
                                    engine.volume = Float($0)
                                    if engine.isMuted && $0 > 0 {
                                        engine.isMuted = false
                                    }
                                }
                            ),
                            in: 0...1
                        )
                        .frame(width: 60)
                        .tint(ShadcnTheme.primary)
                        .accessibilityLabel("Volume")
                        .accessibilityValue("\(Int(engine.volume * 100))%")
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

                    // Primary Play / Pause / Replay Button (High-Contrast Shadcn Circle)
                    Button {
                        engine.togglePlayPause()
                    } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ShadcnTheme.background)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(hoveredButton == "play" ? ShadcnTheme.foreground.opacity(0.92) : ShadcnTheme.foreground)
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .accessibilityLabel(engine.isPlaying ? "Pause" : (engine.hasEnded ? "Replay" : "Play"))
                    .accessibilityHint("Toggles video playback")
                    .help(engine.isPlaying ? "Pause (Space)" : (engine.hasEnded ? "Replay (Space)" : "Play (Space)"))
                    .onHover { h in hoveredButton = h ? "play" : nil }

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
        .frame(maxWidth: 720)
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 0)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .environment(\.colorScheme, .dark)
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
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .audio)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOpen ? "speaker.wave.2.bubble.fill" : "speaker.wave.2.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOpen ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)

                if !isNarrow {
                    Text(audioButtonLabel)
                        .font(.system(size: 11, weight: isOpen ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 95)
                        .truncationMode(.tail)
                        .foregroundStyle(isOpen ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                }
            }
            .padding(.horizontal, isNarrow ? 7 : 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isOpen ? ShadcnTheme.cardHover : (isAudioHovered ? ShadcnTheme.muted.opacity(0.4) : ShadcnTheme.secondary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isOpen ? ShadcnTheme.border : ShadcnTheme.borderSubtle, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityLabel("Audio track")
        .accessibilityValue(audioButtonLabel)
        .onHover { isAudioHovered = $0 }
        .help(isOpen ? "Close Audio Settings" : "Select Audio Track & Channels")
    }

    private func subtitlesSelectorButton(isNarrow: Bool) -> some View {
        let isOpen = engine.activeInspectorSheet == .subtitles
        let isSubOn = engine.selectedSubtitleTrack.id != SubtitleTrack.off.id
        let subTitle = isSubOn ? engine.selectedSubtitleTrack.title : "Subtitles"

        return Button {
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .subtitles)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: (isOpen || isSubOn) ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSubOn ? ShadcnTheme.primaryHighlight : (isOpen ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary))

                if !isNarrow {
                    Text(subTitle)
                        .font(.system(size: 11, weight: (isOpen || isSubOn) ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 100)
                        .truncationMode(.tail)
                        .foregroundStyle(isSubOn ? ShadcnTheme.foreground : (isOpen ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary))
                }
            }
            .padding(.horizontal, isNarrow ? 7 : 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isOpen ? ShadcnTheme.cardHover : (isSubtitlesHovered ? ShadcnTheme.muted.opacity(0.4) : ShadcnTheme.secondary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isOpen ? ShadcnTheme.border : (isSubOn ? ShadcnTheme.primaryHighlight.opacity(0.4) : ShadcnTheme.borderSubtle), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityLabel("Subtitles")
        .accessibilityValue(subTitle)
        .onHover { isSubtitlesHovered = $0 }
        .help(isOpen ? "Close Subtitle Settings" : "Subtitles, Captions & Timing")
    }

    private func speedSelectorButton() -> some View {
        let isOpen = engine.activeInspectorSheet == .speed
        let isNonStandard = abs(engine.playbackRate - 1.0) > 0.01

        return Button {
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .speed)
            }
        } label: {
            Text(Self.formatRate(engine.playbackRate))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isNonStandard ? ShadcnTheme.primaryHighlight : (isOpen ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(isOpen ? ShadcnTheme.cardHover : (isSpeedHovered ? ShadcnTheme.muted.opacity(0.4) : ShadcnTheme.secondary.opacity(0.35)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(isOpen ? ShadcnTheme.border : (isNonStandard ? ShadcnTheme.primaryHighlight.opacity(0.4) : ShadcnTheme.borderSubtle), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityLabel("Playback speed")
        .accessibilityValue(Self.formatRate(engine.playbackRate))
        .onHover { isSpeedHovered = $0 }
        .help(isOpen ? "Close Speed Settings" : "Playback Speed")
    }

    private func dockedButton(id: String, icon: String, help: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hoveredButton == id ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(hoveredButton == id ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(hoveredButton == id ? ShadcnTheme.borderActive : ShadcnTheme.borderSubtle, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(help)
        .accessibilityLabel(accessibilityLabel ?? help)
        .onHover { h in hoveredButton = h ? id : nil }
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
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(showRemainingTime ? "Click to show duration" : "Click to show remaining time")
        .accessibilityLabel(showRemainingTime ? "Remaining time display" : "Playback time display")
        .accessibilityValue("\(TimeFormatting.format(seconds: clockStore.currentTime)) of \(TimeFormatting.format(seconds: clockStore.duration))")
    }
}
