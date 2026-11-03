import SwiftUI

public struct CustomScrubber: View {
    @Bindable var engine: VideoPlayerEngine

    @State private var scrubProgress: Double = 0.0
    @State private var isHovering: Bool = false
    @State private var hoverLocationX: CGFloat = 0
    @State private var hoverTime: Double = 0

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        TimelineView(.animation(paused: !engine.isPlaying || engine.isBuffering || engine.isScrubbing)) { context in
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
                        if !editing {
                            engine.seek(to: scrubProgress * duration, exact: true)
                        }
                    }
                )
                .tint(Color.white)
                .frame(width: totalWidth, height: 24)
                .contentShape(Rectangle())
                .pointingHand()
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
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(ShadcnTheme.foreground)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(ShadcnTheme.popover)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                    )
                            )
                            .offset(x: max(8, min(totalWidth - 48, hoverLocationX - 18)), y: -24)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 24)
        }
        .frame(height: 24)
    }
}
