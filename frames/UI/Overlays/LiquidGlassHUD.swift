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
    @State private var hoveredButton: String? = nil

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let isNarrow = windowManager.isCompact || windowManager.isQuarterScreen
        let showVolumeSlider = !isNarrow

        VStack(spacing: 8) {
            // MARK: - Native QuickTime Timeline Scrubber with Elapsed & Remaining Clocks
            HStack(spacing: 8) {
                Text(TimeFormatting.format(seconds: engine.currentTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.85))

                CustomScrubber(engine: engine)
                    .frame(height: 20)

                let remaining = max(0, engine.duration - engine.currentTime)
                Text("-\(TimeFormatting.format(seconds: remaining))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // MARK: - Primary Controls Dock (Default macOS QuickTime / Apple TV Controls)
            HStack(spacing: isNarrow ? 8 : 12) {
                // MARK: Left Controls (Volume)
                HStack(spacing: 6) {
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
                                    .fill(engine.isMuted ? Color.red.opacity(0.3) : (hoveredButton == "volume" ? Color.white.opacity(0.22) : Color.white.opacity(0.12)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(engine.isMuted ? "Unmute" : "Mute")
                    .accessibilityValue("\(Int(engine.volume * 100))%")
                    .help(isNarrow ? "Volume Slider" : (engine.isMuted ? "Unmute (M)" : "Mute (M)"))
                    .onHover { h in hoveredButton = h ? "volume" : nil }
                    .popover(isPresented: $showVolumePopover) {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Volume")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                Spacer()
                                Text("\(Int(engine.volume * 100))%")
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Color.white.opacity(0.7))
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
                            .tint(Color.white)
                            .accessibilityLabel("Volume")

                            Button(engine.isMuted ? "Unmute" : "Mute") {
                                engine.toggleMute()
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color(white: 0.12))
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
                        .frame(width: 58)
                        .tint(Color.white)
                        .accessibilityLabel("Volume")
                        .accessibilityValue("\(Int(engine.volume * 100))%")
                    }
                }

                Spacer(minLength: 8)

                // MARK: Center Controls (Skip -10s, QuickTime Play/Pause, Skip +10s)
                HStack(spacing: 8) {
                    // Skip -10s
                    dockedButton(
                        id: "skip_back",
                        icon: "gobackward.10",
                        help: "Skip back 10s (← or J)",
                        accessibilityLabel: "Skip backward 10 seconds"
                    ) {
                        engine.skip(seconds: -10)
                    }

                    // Play / Pause / Replay (QuickTime 36x36 Circular Button)
                    Button {
                        engine.togglePlayPause()
                    } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(hoveredButton == "play" ? Color.white.opacity(0.28) : Color.white.opacity(0.20))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(engine.isPlaying ? "Pause" : (engine.hasEnded ? "Replay" : "Play"))
                    .accessibilityHint("Toggles video playback")
                    .help(engine.isPlaying ? "Pause (Space)" : (engine.hasEnded ? "Replay (Space)" : "Play (Space)"))
                    .onHover { h in hoveredButton = h ? "play" : nil }

                    // Skip +10s
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

                // MARK: Right Controls (Audio, Subtitles, Speed, PiP, Fullscreen)
                HStack(spacing: 6) {
                    audioSelectorButton(isNarrow: isNarrow)
                    subtitlesSelectorButton(isNarrow: isNarrow)
                    speedSelectorButton()

                    // Picture-in-Picture Toggle
                    dockedButton(
                        id: "pip",
                        icon: PictureInPictureManager.shared.isPictureInPicture ? "pip.exit" : "pip.enter",
                        help: PictureInPictureManager.shared.isPictureInPicture ? "Exit Picture in Picture" : "Enter Picture in Picture (P)",
                        accessibilityLabel: PictureInPictureManager.shared.isPictureInPicture ? "Exit Picture in Picture" : "Enter Picture in Picture"
                    ) {
                        PictureInPictureManager.shared.toggle(engine: engine)
                    }

                    // Native Fullscreen Toggle
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
            .padding(.bottom, 10)
        }
        .frame(maxWidth: 720)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.08, opacity: 0.85))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 5)
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
        let fillBg = isOpen ? Color.white.opacity(0.25) : (isAudioHovered ? Color.white.opacity(0.20) : Color.white.opacity(0.12))
        let strokeCol = isOpen ? Color.white.opacity(0.40) : (isAudioHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.18))

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
        .accessibilityLabel("Audio track")
        .accessibilityValue(audioButtonLabel)
        .onHover { isAudioHovered = $0 }
        .help(isOpen ? "Close Audio Settings" : "Select Audio Track & Channels")
    }

    private func subtitlesSelectorButton(isNarrow: Bool) -> some View {
        let isOpen = engine.activeInspectorSheet == .subtitles
        let isSubOn = engine.selectedSubtitleTrack.id != SubtitleTrack.off.id
        let fillBg = isOpen ? Color.accentColor.opacity(0.3) : (isSubOn ? Color.white.opacity(0.24) : (isSubtitlesHovered ? Color.white.opacity(0.20) : Color.white.opacity(0.12)))
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
        .accessibilityLabel("Subtitles")
        .accessibilityValue(subTitle)
        .onHover { isSubtitlesHovered = $0 }
        .help(isOpen ? "Close Subtitle Settings" : "Subtitles, Captions & Timing")
    }

    private func speedSelectorButton() -> some View {
        let isOpen = engine.activeInspectorSheet == .speed
        let isNonStandard = abs(engine.playbackRate - 1.0) > 0.01
        let fillBg = isOpen ? Color.cyan.opacity(0.3) : (isNonStandard ? Color.cyan.opacity(0.18) : (isSpeedHovered ? Color.white.opacity(0.20) : Color.white.opacity(0.12)))
        let strokeCol = isOpen ? Color.cyan.opacity(0.6) : (isNonStandard ? Color.cyan.opacity(0.35) : (isSpeedHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.18)))

        return Button {
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .speed)
            }
        } label: {
            Text(Self.formatRate(engine.playbackRate))
                .font(.system(size: 11, weight: .bold).monospacedDigit())
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
        .accessibilityLabel("Playback speed")
        .accessibilityValue(Self.formatRate(engine.playbackRate))
        .onHover { isSpeedHovered = $0 }
        .help(isOpen ? "Close Speed Settings" : "Playback Speed")
    }

    private func dockedButton(id: String, icon: String, help: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hoveredButton == id ? Color.white.opacity(0.22) : Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel ?? help)
        .onHover { h in hoveredButton = h ? id : nil }
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
                    .foregroundStyle(Color.white)
                Text("/")
                    .foregroundStyle(Color.white.opacity(0.45))
                Text(showRemainingTime
                    ? "-\(TimeFormatting.format(seconds: max(0, clockStore.duration - clockStore.currentTime)))"
                    : TimeFormatting.format(seconds: clockStore.duration))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .padding(.leading, 4)
        }
        .buttonStyle(.plain)
        .help(showRemainingTime ? "Click to show duration" : "Click to show remaining time")
        .accessibilityLabel(showRemainingTime ? "Remaining time display" : "Playback time display")
        .accessibilityValue("\(TimeFormatting.format(seconds: clockStore.currentTime)) of \(TimeFormatting.format(seconds: clockStore.duration))")
    }
}
