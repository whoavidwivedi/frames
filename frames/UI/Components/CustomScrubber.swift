import SwiftUI

public struct CustomScrubber: View {
    @Bindable var engine: VideoPlayerEngine

    @State private var scrubProgress: Double = 0.0
    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false
    @State private var hoverLocationX: CGFloat = 0
    @State private var hoverTime: Double = 0
    @State private var wasPlayingBeforeScrub: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let refreshInterval = engine.isPlaying && !engine.isBuffering && !engine.isScrubbing && !isDragging ? (1.0 / 30.0) : 60.0
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            GeometryReader { proxy in
                let totalWidth = proxy.size.width
                let duration = engine.duration > 0 ? engine.duration : 1.0
                let effectivePct: Double = {
                    if engine.isScrubbing || isDragging {
                        return scrubProgress
                    } else {
                        let t = engine.currentInterpolatedTime(at: context.date)
                        return max(0.0, min(1.0, t / duration))
                    }
                }()
                let progressWidth = max(0.0, min(totalWidth, effectivePct * totalWidth))
                let isInteracting = isHovering || isDragging

                ZStack(alignment: .leading) {
                    // Inactive background track
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 4)

                    // Hover preview track highlight
                    if isHovering && !isDragging {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: max(0, min(totalWidth, hoverLocationX)), height: 4)
                    }

                    // Glowing scrub line (ambient soft glow)
                    Capsule(style: .continuous)
                        .fill(ShadcnTheme.primary.opacity(isInteracting ? 0.45 : 0.2))
                        .frame(width: progressWidth, height: 4)
                        .blur(radius: isInteracting ? 4 : 2)

                    // Foreground crisp scrub progress line
                    Capsule(style: .continuous)
                        .fill(ShadcnTheme.primary)
                        .frame(width: progressWidth, height: 4)
                        .shadow(
                            color: ShadcnTheme.primary.opacity(isInteracting ? 0.6 : 0.25),
                            radius: isInteracting ? 5 : 2,
                            x: 0,
                            y: 0
                        )

                    // Hover preview indicator marker (subtle pip at hover location)
                    if isHovering && !isDragging {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.65))
                            .frame(width: 2, height: 8)
                            .position(x: max(2, min(totalWidth - 2, hoverLocationX)), y: proxy.size.height / 2)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }

                    // Scrubber thumb with Emil Kowalski spring expansion (scale smoothly 4pt -> 8pt)
                    Circle()
                        .fill(ShadcnTheme.primary)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: isInteracting ? 3 : 1.5, x: 0, y: 1)
                        .shadow(color: ShadcnTheme.primary.opacity(isInteracting ? 0.5 : 0.0), radius: 4, x: 0, y: 0)
                        .scaleEffect(isInteracting ? 1.0 : 0.5)
                        .animation(.fluidQuick, value: isInteracting)
                        .position(x: max(4, min(totalWidth - 4, progressWidth)), y: proxy.size.height / 2)
                        .allowsHitTesting(false)
                }
                .frame(height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                wasPlayingBeforeScrub = engine.isPlaying
                                if engine.isPlaying {
                                    engine.pause()
                                }
                                engine.isScrubbing = true
                            }
                            let clampedX = max(0, min(totalWidth, value.location.x))
                            let newPct = totalWidth > 0 ? (clampedX / totalWidth) : 0
                            scrubProgress = newPct
                            engine.seek(to: newPct * duration, exact: false)
                        }
                        .onEnded { value in
                            let clampedX = max(0, min(totalWidth, value.location.x))
                            let newPct = totalWidth > 0 ? (clampedX / totalWidth) : 0
                            scrubProgress = newPct
                            engine.seek(to: newPct * duration, exact: true)
                            engine.endScrubbing()
                            if wasPlayingBeforeScrub {
                                engine.play()
                            }
                            isDragging = false
                        }
                )
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
                .overlay(alignment: .topLeading) {
                    if isHovering && !isDragging && !engine.isScrubbing {
                        Text(TimeFormatting.format(seconds: hoverTime))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ShadcnTheme.foreground)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(ShadcnTheme.popover)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
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
        .contentShape(Rectangle())
        .pointingHand()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(TimeFormatting.format(seconds: engine.currentTime)) of \(TimeFormatting.format(seconds: engine.duration > 0 ? engine.duration : 1.0))")
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
        .environment(\.colorScheme, .dark)
    }
}
