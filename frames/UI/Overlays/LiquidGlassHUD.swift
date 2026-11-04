import SwiftUI

public struct LiquidGlassHUD: View {
    @Bindable var engine: VideoPlayerEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowManager = WindowManager.shared

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let winWidth = windowManager.currentWindowSize.width > 0 ? windowManager.currentWindowSize.width : 800
        let hudWidth = min(max(winWidth - 32, 380), 720)
        let isQuarter = windowManager.isQuarterScreen
        let isCompact = windowManager.isCompact || isQuarter || hudWidth < 540
        let showVolume = !isCompact && hudWidth >= 580
        let showHW = !isCompact && hudWidth >= 520

        VStack(spacing: 8) {
            // Inspector Popovers (Subtitles, Audio, Speed, Hardware Stats)
            if let sheet = engine.activeInspectorSheet {
                HStack {
                    Spacer()
                    Group {
                        switch sheet {
                        case .subtitles:
                            SubtitleSelectorPanel(engine: engine)
                        case .audio:
                            AudioSelectorPanel(engine: engine)
                        case .speed:
                            SpeedSelectorPanel(engine: engine)
                        case .stats:
                            HardwareStatsPanel(engine: engine)
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)).combined(with: .offset(y: 8)),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)).combined(with: .offset(y: 4))
                        )
                    )
                }
                .padding(.trailing, 20)
                .padding(.bottom, 2)
            }

            // Minimalist Control Bar (shadcn mira / neutral)
            VStack(spacing: 8) {
                // Hairline Scrubber (Fixed 24pt height to prevent any vertical jump on click)
                CustomScrubber(engine: engine)
                    .frame(height: 24)
                    .pointingHand()

                // Controls Row
                HStack(spacing: isCompact ? 5 : 8) {
                    // Play / Pause / Replay
                    ShadcnButton(
                        icon: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"),
                        variant: .ghost,
                        size: .icon,
                        accessibilityLabel: engine.isPlaying ? "Pause" : (engine.hasEnded ? "Replay" : "Play")
                    ) {
                        engine.togglePlayPause()
                    }

                    // Jump -10s
                    ShadcnButton(
                        icon: "gobackward.10",
                        variant: .ghost,
                        size: .iconSm,
                        accessibilityLabel: "Skip back 10 seconds"
                    ) {
                        engine.skip(seconds: -10)
                    }

                    // Jump +10s
                    ShadcnButton(
                        icon: "goforward.10",
                        variant: .ghost,
                        size: .iconSm,
                        accessibilityLabel: "Skip forward 10 seconds"
                    ) {
                        engine.skip(seconds: 10)
                    }

                    // Volume
                    HStack(spacing: 4) {
                        ShadcnButton(
                            icon: engine.isMuted ? "speaker.slash.fill" : (engine.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"),
                            variant: .ghost,
                            size: .iconSm,
                            accessibilityLabel: engine.isMuted ? "Unmute" : "Mute"
                        ) {
                            engine.toggleMute()
                        }

                        if showVolume {
                            Slider(
                                value: Binding(
                                    get: { Double(engine.volume) },
                                    set: { engine.volume = Float($0) }
                                ),
                                in: 0...1
                            )
                            .frame(width: 56)
                            .tint(Color.white)
                            .pointingHand()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }

                    // Timestamps (Tabular Numbers)
                    HStack(spacing: 3) {
                        Text(TimeFormatting.format(seconds: engine.currentTime))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("/")
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                        Text(TimeFormatting.format(seconds: engine.duration))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.leading, 4)

                    Spacer()

                    // Right Side: Options & Menus
                    HStack(spacing: isCompact ? 4 : 6) {
                        // Subtitles
                        ShadcnButton(
                            icon: "captions.bubble",
                            variant: .outline,
                            size: .iconSm,
                            isSelected: engine.activeInspectorSheet == .subtitles,
                            accessibilityLabel: engine.selectedSubtitleTrack.id == "off" ? "Subtitle tracks" : "Subtitle track: \(engine.selectedSubtitleTrack.title)"
                        ) {
                            toggleSheet(.subtitles)
                        }

                        // Audio
                        ShadcnButton(
                            icon: "waveform",
                            variant: .outline,
                            size: .iconSm,
                            isSelected: engine.activeInspectorSheet == .audio,
                            accessibilityLabel: engine.selectedAudioTrack.map { "Audio track: \($0.title)" } ?? "Audio tracks"
                        ) {
                            toggleSheet(.audio)
                        }

                        // Speed
                        ShadcnButton(
                            String(format: "%.2f×", engine.playbackRate),
                            variant: .outline,
                            size: .sm,
                            isSelected: engine.activeInspectorSheet == .speed,
                            accessibilityLabel: "Playback speed \(String(format: "%.2f", engine.playbackRate)) times"
                        ) {
                            toggleSheet(.speed)
                        }

                        // HW Info (Apple Silicon) - hide if narrow
                        if showHW {
                            ShadcnButton(
                                icon: "cpu",
                                variant: .ghost,
                                size: .iconSm,
                                isSelected: engine.activeInspectorSheet == .stats,
                                accessibilityLabel: "Playback statistics"
                            ) {
                                toggleSheet(.stats)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }

                        // Native Full Screen Toggle
                        let isNativeFs = windowManager.isNativeFullscreen
                        ShadcnButton(
                            icon: isNativeFs ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                            variant: .ghost,
                            size: .iconSm,
                            isSelected: isNativeFs,
                            accessibilityLabel: isNativeFs ? "Exit Full Screen" : "Enter Full Screen"
                        ) {
                            withAnimation(.fluidSpring) {
                                engine.activeInspectorSheet = nil
                            }
                            windowManager.toggleNativeFullscreen()
                        }
                    }
                }
            }
            .padding(.horizontal, isCompact ? 12 : 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .fill(ShadcnTheme.card.opacity(0.70))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
            )
            .shadow(
                color: Color(nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(white: 0, alpha: 0.35)
                        : NSColor(white: 0, alpha: 0.08)
                }),
                radius: 14,
                y: 6
            )
            .frame(maxWidth: 720)
        }
        .padding(.horizontal, isCompact ? 10 : 20)
        .padding(.bottom, 16)
        .animation(.fluidSpring, value: showVolume)
        .animation(.fluidSpring, value: showHW)
        .animation(.fluidSpring, value: isCompact)
        .animation(.fluidSpring, value: hudWidth)
        .animation(.fluidSpring, value: engine.activeInspectorSheet != nil)
        .animation(.fluidWindow, value: windowManager.currentLayoutState)
    }

    private func toggleSheet(_ sheet: VideoPlayerEngine.InspectorSheet) {
        withAnimation(.fluidSpring) {
            if engine.activeInspectorSheet == sheet {
                engine.activeInspectorSheet = nil
            } else {
                engine.activeInspectorSheet = sheet
            }
        }
    }

    private func toggleFullscreen() {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            window.toggleFullScreen(nil)
            engine.isFullscreen = window.styleMask.contains(.fullScreen)
        }
    }
}
