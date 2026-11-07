import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct LiquidGlassHUD: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var windowManager = WindowManager.shared
    @State private var showVolumePopover = false

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
                HStack(spacing: 8) {
                    // Play / Pause / Replay
                    AppleLiquidGlassButton(
                        icon: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"),
                        iconSize: 15,
                        iconWeight: .bold,
                        shape: .circle,
                        tint: .standard,
                        size: 34,
                        helpText: engine.isPlaying ? "Pause (Space)" : (engine.hasEnded ? "Replay (Space)" : "Play (Space)")
                    ) {
                        engine.togglePlayPause()
                    }

                    // Skip -10s
                    AppleLiquidGlassButton(
                        icon: "gobackward.10",
                        iconSize: 13,
                        iconWeight: .semibold,
                        shape: .circle,
                        tint: .standard,
                        size: 30,
                        helpText: "Skip back 10s (← or J)"
                    ) {
                        engine.skip(seconds: -10)
                    }

                    // Skip +10s
                    AppleLiquidGlassButton(
                        icon: "goforward.10",
                        iconSize: 13,
                        iconWeight: .semibold,
                        shape: .circle,
                        tint: .standard,
                        size: 30,
                        helpText: "Skip forward 10s (→ or L)"
                    ) {
                        engine.skip(seconds: 10)
                    }

                    // Volume Mute Button + Interactive Slider / Popover
                    HStack(spacing: 6) {
                        AppleLiquidGlassButton(
                            icon: engine.isMuted ? "speaker.slash.fill" : (engine.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"),
                            iconSize: 13,
                            iconWeight: .medium,
                            shape: .circle,
                            tint: engine.isMuted ? .danger : .standard,
                            size: 30,
                            helpText: isNarrow ? "Volume Slider" : (engine.isMuted ? "Unmute (M)" : "Mute (M)")
                        ) {
                            if isNarrow {
                                showVolumePopover.toggle()
                            } else {
                                engine.toggleMute()
                            }
                        }
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
                            HStack(spacing: 0) {
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
                                .pointingHand()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.75)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                            )
                        }
                    }

                    // Tabular Precision Time Display
                    HStack(spacing: 4) {
                        Text(TimeFormatting.format(seconds: engine.currentTime))
                            .foregroundStyle(Color.white)
                        Text("/")
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(TimeFormatting.format(seconds: engine.duration))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.leading, 4)
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
                LinearGradient(
                    colors: [
                        Color(white: 0.06).opacity(0.68),
                        Color(white: 0.02).opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                startPoint: .leading,
                endPoint: .trailing
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

        return AppleLiquidGlassButton(
            shape: .roundedRectangle(cornerRadius: 7),
            tint: isOpen ? .accent : .standard,
            width: nil,
            height: 30,
            helpText: isOpen ? "Close Audio Settings" : "Select Audio Track & Channels"
        ) {
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .audio)
            }
        } content: {
            HStack(spacing: 5) {
                Image(systemName: isOpen ? "speaker.wave.2.bubble.fill" : "speaker.wave.2.bubble")
                    .font(.system(size: 12, weight: .semibold))
                if !isNarrow {
                    Text(audioButtonLabel)
                        .font(.system(size: 11, weight: isOpen ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 95)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private func subtitlesSelectorButton(isNarrow: Bool) -> some View {
        let isOpen = engine.activeInspectorSheet == .subtitles
        let isSubOn = engine.selectedSubtitleTrack.id != SubtitleTrack.off.id
        let subTitle = isSubOn ? engine.selectedSubtitleTrack.title : "Subtitles"

        return AppleLiquidGlassButton(
            shape: .roundedRectangle(cornerRadius: 7),
            tint: (isOpen || isSubOn) ? .accent : .standard,
            width: nil,
            height: 30,
            helpText: isOpen ? "Close Subtitle Settings" : "Subtitles, Captions & Timing"
        ) {
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .subtitles)
            }
        } content: {
            HStack(spacing: 5) {
                Image(systemName: (isOpen || isSubOn) ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 12, weight: .semibold))
                if !isNarrow {
                    Text(subTitle)
                        .font(.system(size: 11, weight: (isOpen || isSubOn) ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 100)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private func speedSelectorButton() -> some View {
        let isOpen = engine.activeInspectorSheet == .speed
        let isNonStandard = abs(engine.playbackRate - 1.0) > 0.01

        return AppleLiquidGlassButton(
            shape: .roundedRectangle(cornerRadius: 7),
            tint: (isOpen || isNonStandard) ? .cyan : .standard,
            width: nil,
            height: 30,
            helpText: isOpen ? "Close Speed Settings" : "Playback Speed"
        ) {
            withAnimation(.fluidSpring) {
                engine.activeInspectorSheet = (isOpen ? nil : .speed)
            }
        } content: {
            Text(Self.formatRate(engine.playbackRate))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
    }

    private func dockedButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        AppleLiquidGlassButton(
            icon: icon,
            iconSize: 12,
            iconWeight: .medium,
            shape: .circle,
            tint: .standard,
            size: 30,
            helpText: help,
            action: action
        )
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
