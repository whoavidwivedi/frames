import SwiftUI

public struct LiquidGlassHUD: View {
    @Bindable var engine: VideoPlayerEngine

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
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
                        case .fullscreen:
                            FullscreenSelectorPanel(engine: engine)
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 4)))
                }
                .padding(.trailing, 20)
                .padding(.bottom, 2)
            }

            // Minimalist Control Bar (shadcn mira / neutral)
            VStack(spacing: 8) {
                // Hairline Scrubber (Fixed 24pt height to prevent any vertical jump on click)
                CustomScrubber(engine: engine)
                    .frame(height: 24)

                // Controls Row
                HStack(spacing: 8) {
                    // Play / Pause
                    ShadcnButton(
                        icon: engine.isPlaying ? "pause.fill" : "play.fill",
                        variant: .ghost,
                        size: .icon
                    ) {
                        engine.togglePlayPause()
                    }

                    // Jump -10s
                    ShadcnButton(
                        icon: "gobackward.10",
                        variant: .ghost,
                        size: .iconSm
                    ) {
                        engine.skip(seconds: -10)
                    }

                    // Jump +10s
                    ShadcnButton(
                        icon: "goforward.10",
                        variant: .ghost,
                        size: .iconSm
                    ) {
                        engine.skip(seconds: 10)
                    }

                    // Volume
                    HStack(spacing: 4) {
                        ShadcnButton(
                            icon: engine.isMuted ? "speaker.slash.fill" : (engine.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"),
                            variant: .ghost,
                            size: .iconSm
                        ) {
                            engine.toggleMute()
                        }

                        Slider(
                            value: Binding(
                                get: { Double(engine.volume) },
                                set: { engine.volume = Float($0) }
                            ),
                            in: 0...1
                        )
                        .frame(width: 56)
                        .tint(Color.white)
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
                    HStack(spacing: 6) {
                        // Subtitles
                        ShadcnButton(
                            engine.selectedSubtitleTrack.id == "off" ? "Subtitles" : engine.selectedSubtitleTrack.title,
                            icon: "captions.bubble",
                            variant: .outline,
                            size: .sm,
                            isSelected: engine.activeInspectorSheet == .subtitles
                        ) {
                            toggleSheet(.subtitles)
                        }

                        // Audio
                        ShadcnButton(
                            engine.selectedAudioTrack?.title ?? "Audio",
                            icon: "waveform",
                            variant: .outline,
                            size: .sm,
                            isSelected: engine.activeInspectorSheet == .audio
                        ) {
                            toggleSheet(.audio)
                        }

                        // Speed
                        ShadcnButton(
                            String(format: "%.2f×", engine.playbackRate),
                            icon: "gauge.with.needle",
                            variant: .outline,
                            size: .sm,
                            isSelected: engine.activeInspectorSheet == .speed
                        ) {
                            toggleSheet(.speed)
                        }

                        // HW Info (Apple Silicon)
                        ShadcnButton(
                            icon: "cpu",
                            variant: .ghost,
                            size: .iconSm,
                            isSelected: engine.activeInspectorSheet == .stats
                        ) {
                            toggleSheet(.stats)
                        }

                        // Fullscreen
                        let isAnyFs = WindowManager.shared.isAnyFullscreen
                        ShadcnButton(
                            icon: isAnyFs ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                            variant: .ghost,
                            size: .iconSm,
                            isSelected: engine.activeInspectorSheet == .fullscreen
                        ) {
                            toggleSheet(.fullscreen)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                    .fill(ShadcnTheme.card.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.4), radius: 14, y: 6)
            .frame(maxWidth: 780)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animation(.easeInOut(duration: 0.15), value: engine.activeInspectorSheet)
    }

    private func toggleSheet(_ sheet: VideoPlayerEngine.InspectorSheet) {
        if engine.activeInspectorSheet == sheet {
            engine.activeInspectorSheet = nil
        } else {
            engine.activeInspectorSheet = sheet
        }
    }

    private func toggleFullscreen() {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            window.toggleFullScreen(nil)
            engine.isFullscreen = window.styleMask.contains(.fullScreen)
        }
    }
}
