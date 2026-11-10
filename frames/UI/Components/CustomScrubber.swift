import SwiftUI

public struct CustomScrubber: View {
    @Bindable var engine: VideoPlayerEngine

    @State private var scrubProgress: Double = 0.0
    @State private var isHovering: Bool = false
    @State private var hoverLocationX: CGFloat = 0
    @State private var hoverTime: Double = 0
    @State private var wasPlayingBeforeScrub: Bool = false

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let refreshInterval = engine.isPlaying && !engine.isBuffering && !engine.isScrubbing ? (1.0 / 30.0) : 60.0
        // The decode and presentation pipeline remains display-paced; the control
        // surface does not need to redraw at 60/120 Hz. Thirty updates per second
        // keeps the clock visually fluid while avoiding needless SwiftUI work.
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            GeometryReader { proxy in
                let totalWidth = proxy.size.width
                let duration = engine.duration > 0 ? engine.duration : 1.0
                let effectivePct: Double = {
                    if engine.isScrubbing {
                        return scrubProgress
                    } else {
                        let t = engine.currentInterpolatedTime(at: context.date)
                        return max(0.0, min(1.0, t / duration))
                    }
                }()

                // Fixed-height, rock-solid Native Slider (Never shifts vertically on click)
                Slider(
                    value: Binding(
                        get: { effectivePct },
                        set: { newPct in
                            scrubProgress = newPct
                            engine.seek(to: newPct * duration, exact: false)
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        engine.isScrubbing = editing
                        if editing {
                            wasPlayingBeforeScrub = engine.isPlaying
                            if engine.isPlaying {
                                engine.pause()
                            }
                        } else {
                            // The scrub gesture already positioned playback; only resume.
                            engine.endScrubbing()
                            if wasPlayingBeforeScrub {
                                engine.play()
                            }
                        }
                    }
                )
                .tint(Color.white.opacity(0.9))
                .frame(width: totalWidth, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel("Playback progress")
                .accessibilityValue("\(TimeFormatting.format(seconds: engine.currentTime)) of \(TimeFormatting.format(seconds: duration))")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        engine.skip(seconds: 10)
                    case .decrement:
                        engine.skip(seconds: -10)
                    @unknown default:
                        break
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        isHovering = true
                        hoverLocationX = location.x
                        let pct = max(0.0, min(1.0, location.x / totalWidth))
                        hoverTime = pct * duration
                    case .ended:
                        isHovering = false
                    }
                }
                // Tooltip rendered as an overlay so it NEVER alters layout height or causes vertical jump
                .overlay(alignment: .topLeading) {
                    if isHovering && !engine.isScrubbing {
                        Text(TimeFormatting.format(seconds: hoverTime))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(Color(white: 0.12, opacity: 0.95))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                                    )
                            )
                            .offset(x: max(8, min(totalWidth - 48, hoverLocationX - 18)), y: -24)
                            .allowsHitTesting(false)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .animation(.fluidQuick, value: isHovering)
            }
            .frame(height: 24)
        }
        .frame(height: 24)
        .environment(\.colorScheme, .dark)
    }
}
