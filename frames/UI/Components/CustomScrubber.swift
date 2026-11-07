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

                let isExpanded = isHovering || engine.isScrubbing
                let trackHeight: CGFloat = isExpanded ? 7 : 5
                let thumbSize: CGFloat = isExpanded ? 15 : 11
                let thumbX = max(thumbSize / 2, min(totalWidth - thumbSize / 2, CGFloat(effectivePct) * totalWidth))

                ZStack(alignment: .leading) {
                    // Apple Liquid Glass Track Channel
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .frame(height: trackHeight)
                        .overlay(
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.40), location: 0.0),
                                            .init(color: Color.white.opacity(0.18), location: 0.5),
                                            .init(color: Color.white.opacity(0.08), location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.75
                                )
                        )

                    // Liquid Light Progress Bar
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color.white.opacity(0.85)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: max(0, min(totalWidth, totalWidth * CGFloat(effectivePct))), height: trackHeight)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
                        )

                    // Apple Liquid Glass Bead Thumb
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color(white: 0.88)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0.40)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.0
                            )
                        Ellipse()
                            .fill(Color.white.opacity(0.90))
                            .frame(width: thumbSize * 0.45, height: thumbSize * 0.22)
                            .offset(y: -thumbSize * 0.22)
                    }
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: Color.black.opacity(isExpanded ? 0.45 : 0.25), radius: 3, y: 1)
                    .position(x: thumbX, y: proxy.size.height / 2)
                }
                .frame(width: totalWidth, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let pct = max(0.0, min(1.0, Double(gesture.location.x / totalWidth)))
                            scrubProgress = pct
                            if !engine.isScrubbing {
                                engine.isScrubbing = true
                                wasPlayingBeforeScrub = engine.isPlaying
                                if engine.isPlaying {
                                    engine.pause()
                                }
                            }
                            engine.seek(to: pct * duration, exact: false)
                            hoverLocationX = gesture.location.x
                            hoverTime = pct * duration
                            isHovering = true
                        }
                        .onEnded { gesture in
                            let pct = max(0.0, min(1.0, Double(gesture.location.x / totalWidth)))
                            scrubProgress = pct
                            engine.seek(to: pct * duration, exact: true)
                            engine.endScrubbing()
                            if wasPlayingBeforeScrub {
                                engine.play()
                            }
                            isHovering = false
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if !engine.isScrubbing {
                            isHovering = true
                            hoverLocationX = location.x
                            let pct = max(0.0, min(1.0, location.x / totalWidth))
                            hoverTime = pct * duration
                        }
                    case .ended:
                        if !engine.isScrubbing {
                            isHovering = false
                        }
                    }
                }
                // Floating Liquid Glass Time Tooltip
                .overlay(alignment: .topLeading) {
                    if isHovering {
                        Text(TimeFormatting.format(seconds: hoverTime))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .environment(\.colorScheme, .dark)
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(white: 0.08, opacity: 0.82))
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            stops: [
                                                .init(color: Color.white.opacity(0.45), location: 0.0),
                                                .init(color: Color.white.opacity(0.15), location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.75
                                    )
                            )
                            .overlay(alignment: .top) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.35), Color.clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: 4)
                                    .allowsHitTesting(false)
                            }
                            .shadow(color: Color.black.opacity(0.35), radius: 6, y: 2)
                            .offset(x: max(6, min(totalWidth - 52, hoverLocationX - 22)), y: -26)
                            .allowsHitTesting(false)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovering)
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: engine.isScrubbing)
            }
            .frame(height: 24)
        }
        .frame(height: 24)
        .pointingHand()
        .environment(\.colorScheme, .dark)
    }
}
