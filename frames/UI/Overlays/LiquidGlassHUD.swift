import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct LiquidGlassHUD: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var windowManager = WindowManager.shared
    @State private var showVolumePopover = false
    @State private var isAudioHovered = false
    @State private var isSubtitlesHovered = false
    @State private var isSpeedHovered = false

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let isNarrow = windowManager.isCompact || windowManager.isQuarterScreen
        let showVolumeSlider = !isNarrow

        VStack(spacing: 8) {
            // Full-Width Precision Scrubber with Hover Tooltip
            CustomScrubber(engine: engine)
                .frame(height: 24)
                .padding(.horizontal, 16)
                .pointingHand()

            // Primary Playback Controls Dock
            HStack(spacing: isNarrow ? 8 : 12) {
                // MARK: - Left Controls Cluster
                HStack(spacing: 6) {
                    // Play / Pause / Replay
                    Button {
                        engine.togglePlayPause()
                    } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help(engine.isPlaying ? "Pause (Space)" : (engine.hasEnded ? "Replay (Space)" : "Play (Space)"))

                    // Skip -10s
                    dockedButton(icon: "gobackward.10", help: "Skip back 10s (← or J)") {
                        engine.skip(seconds: -10)
                    }

                    // Skip +10s
                    dockedButton(icon: "goforward.10", help: "Skip forward 10s (→ or L)") {
                        engine.skip(seconds: 10)
                    }

                    // Volume Mute Button + Interactive Slider / Popover
                    HStack(spacing: 4) {
                        Button {
                            if isNarrow {
                                showVolumePopover.toggle()
                            } else {
                                engine.toggleMute()
                            }
                        } label: {
                            Image(systemName: engine.isMuted ? "speaker.slash.fill" : (engine.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(engine.isMuted ? Color.red.opacity(0.25) : Color.white.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help(isNarrow ? "Volume Slider" : (engine.isMuted ? "Unmute (M)" : "Mute (M)"))
                        .popover(isPresented: $showVolumePopover) {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Volume")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                    Spacer()
                                    Text("\(Int(engine.volume * 100))%")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.7))
                                }
                                LiquidGlassVolumeSlider(
                                    value: Binding(
                                        get: { Double(engine.volume) },
                                        set: {
                                            engine.volume = Float($0)
                                            if engine.isMuted && $0 > 0 { engine.isMuted = false }
                                        }
                                    ),
                                    isMuted: engine.isMuted,
                                    width: 130
                                )

                                Button(engine.isMuted ? "Unmute" : "Mute") {
                                    engine.toggleMute()
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.9))
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .environment(\.colorScheme, .dark)
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(white: 0.08, opacity: 0.82))
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.12)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .environment(\.colorScheme, .dark)
                        }

                        if showVolumeSlider {
                            LiquidGlassVolumeSlider(
                                value: Binding(
                                    get: { Double(engine.volume) },
                                    set: {
                                        engine.volume = Float($0)
                                        if engine.isMuted && $0 > 0 {
                                            engine.isMuted = false
                                        }
                                    }
                                ),
                                isMuted: engine.isMuted,
                                width: 62
                            )
                        }
                    }

                    // Tabular Precision Time Display (Decoupled Isolated Clock Store)
                    PlaybackTimeDisplay(clockStore: engine.clockStore)
                }

                Spacer(minLength: 8)

                // MARK: - Right Controls Cluster
                HStack(spacing: 6) {
                    audioSelectorButton(isNarrow: isNarrow)
                    subtitlesSelectorButton(isNarrow: isNarrow)
                    speedSelectorButton()

                    // Picture-in-Picture Toggle
                    dockedButton(
                        icon: PictureInPictureManager.shared.isPictureInPicture ? "pip.exit" : "pip.enter",
                        help: PictureInPictureManager.shared.isPictureInPicture ? "Exit Picture in Picture" : "Enter Picture in Picture (P)"
                    ) {
                        PictureInPictureManager.shared.toggle(engine: engine)
                    }

                    // Native Fullscreen Toggle
                    dockedButton(
                        icon: windowManager.isNativeFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        help: windowManager.isNativeFullscreen ? "Exit Fullscreen (Esc)" : "Enter Fullscreen (F)"
                    ) {
                        windowManager.toggleNativeFullscreen()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                Rectangle()
                    .fill(Color(white: 0.08, opacity: 0.70))
            }
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
        }
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
        let fillBg = isOpen ? Color.white.opacity(0.25) : (isAudioHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.12))
        let strokeCol = isOpen ? Color.white.opacity(0.4) : (isAudioHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.18))

        return Button {
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .audio)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOpen ? "speaker.wave.2.bubble.fill" : "speaker.wave.2.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOpen ? Color.white : Color.white.opacity(0.9))
                if !isNarrow {
                    Text(audioButtonLabel)
                        .font(.system(size: 11, weight: isOpen ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 95)
                        .truncationMode(.tail)
                        .foregroundStyle(Color.white)
                }
            }
            .padding(.horizontal, isNarrow ? 7 : 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(strokeCol, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { isAudioHovered = $0 }
        .help(isOpen ? "Close Audio Settings" : "Select Audio Track & Channels")
    }

    private func subtitlesSelectorButton(isNarrow: Bool) -> some View {
        let isOpen = engine.activeInspectorSheet == .subtitles
        let isSubOn = engine.selectedSubtitleTrack.id != SubtitleTrack.off.id
        let fillBg = isOpen ? Color.accentColor.opacity(0.3) : (isSubOn ? Color.white.opacity(0.24) : (isSubtitlesHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.12)))
        let strokeCol = isOpen ? Color.accentColor.opacity(0.5) : (isSubOn ? Color.white.opacity(0.35) : (isSubtitlesHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.18)))
        let subTitle = isSubOn ? engine.selectedSubtitleTrack.title : "Subtitles"

        return Button {
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .subtitles)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: (isOpen || isSubOn) ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSubOn ? Color.accentColor : Color.white)
                if !isNarrow {
                    Text(subTitle)
                        .font(.system(size: 11, weight: (isOpen || isSubOn) ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 100)
                        .truncationMode(.tail)
                        .foregroundStyle(Color.white)
                }
            }
            .padding(.horizontal, isNarrow ? 7 : 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(strokeCol, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { isSubtitlesHovered = $0 }
        .help(isOpen ? "Close Subtitle Settings" : "Subtitles, Captions & Timing")
    }

    private func speedSelectorButton() -> some View {
        let isOpen = engine.activeInspectorSheet == .speed
        let isNonStandard = abs(engine.playbackRate - 1.0) > 0.01
        let fillBg = isOpen ? Color.cyan.opacity(0.3) : (isNonStandard ? Color.cyan.opacity(0.18) : (isSpeedHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.12)))
        let strokeCol = isOpen ? Color.cyan.opacity(0.6) : (isNonStandard ? Color.cyan.opacity(0.35) : (isSpeedHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.18)))

        return Button {
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .speed)
            }
        } label: {
            Text(Self.formatRate(engine.playbackRate))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isNonStandard ? Color.cyan : Color.white)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(fillBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(strokeCol, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { isSpeedHovered = $0 }
        .help(isOpen ? "Close Speed Settings" : "Playback Speed")
    }

    private func dockedButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(help)
    }

    private func openExternalSubtitlePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .item,
            UTType(filenameExtension: "vtt") ?? .item
        ]
        panel.message = "Choose an SRT or WebVTT subtitle file"

        if panel.runModal() == .OK, let url = panel.url {
            engine.loadExternalSubtitleFile(from: url)
        }
    }
}

// MARK: - Decoupled Playback Time Display
public struct PlaybackTimeDisplay: View {
    public let clockStore: PlaybackClockStore

    public init(clockStore: PlaybackClockStore) {
        self.clockStore = clockStore
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(TimeFormatting.format(seconds: clockStore.currentTime))
                .foregroundStyle(Color.white)
            Text("/")
                .foregroundStyle(Color.white.opacity(0.45))
            Text(TimeFormatting.format(seconds: clockStore.duration))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.leading, 4)
    }
}
