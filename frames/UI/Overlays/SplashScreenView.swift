import SwiftUI

public struct SplashScreenView: View {
    private static let duration = 1.35
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var start = Date()

    public var onComplete: () -> Void

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        Group {
            if reduceMotion {
                artwork(at: 0.64)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let progress = min(1, max(0, context.date.timeIntervalSince(start) / Self.duration))
                    artwork(at: progress)
                        .opacity(1 - min(1, max(0, (progress - 0.79) / 0.21)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            start = Date()
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.35 : Self.duration))
                onComplete()
            } catch {
                // Opening a file or closing the window can remove the splash early.
            }
        }
    }

    private func artwork(at progress: Double) -> some View {
        let dark = colorScheme == .dark
        let reveal = min(1, max(0, (progress - 0.29) / 0.26))
        let easedReveal = reveal * reveal * (3 - 2 * reveal)
        return ZStack {
            dark ? Color(red: 0.045, green: 0.049, blue: 0.086) : Color(red: 0.92, green: 0.93, blue: 0.98)

            Canvas { context, size in
                let unit = min(size.width, size.height)
                let origin = CGPoint(x: size.width * (0.33 + 0.10 * progress), y: size.height * 0.53)
                let reach = size.width * (0.16 + 0.53 * progress)
                let lift = CGFloat(sin(progress * .pi)) * unit * 0.13
                let colors: [Color] = [
                    Color(red: 0.16, green: 0.12, blue: 0.90),
                    Color(red: 0.19, green: 0.42, blue: 1),
                    Color(red: 0.31, green: 0.76, blue: 1),
                    Color(red: 0.72, green: 0.32, blue: 1),
                    Color(red: 1, green: 0.54, blue: 0.39)
                ]

                for (index, color) in colors.enumerated() {
                    let layer = CGFloat(index)
                    let y = origin.y + (layer - 2) * unit * 0.022
                    let end = CGPoint(x: origin.x + reach, y: y - unit * (0.02 + layer * 0.065) - lift)
                    var trail = Path()
                    trail.move(to: CGPoint(x: origin.x, y: y))
                    trail.addCurve(
                        to: end,
                        control1: CGPoint(x: origin.x + reach * 0.28, y: y + unit * (0.13 - layer * 0.012)),
                        control2: CGPoint(x: origin.x + reach * 0.64, y: end.y + unit * 0.10)
                    )

                    var glow = context
                    glow.addFilter(.blur(radius: unit * (0.049 - layer * 0.005)))
                    glow.stroke(
                        trail,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: color.opacity(0), location: 0),
                                .init(color: color.opacity(dark ? 0.83 : 0.76), location: 0.38),
                                .init(color: color.opacity(0), location: 1)
                            ]),
                            startPoint: CGPoint(x: origin.x, y: y),
                            endPoint: end
                        ),
                        style: StrokeStyle(lineWidth: unit * (0.16 - layer * 0.023), lineCap: .round)
                    )
                }
            }

            Text("Frames")
                .font(.system(size: 72, weight: .semibold))
                .tracking(-5)
                .foregroundStyle(dark ? Color.white : Color(red: 0.055, green: 0.067, blue: 0.13))
                .opacity(easedReveal)
                .offset(y: 6 * (1 - easedReveal))
        }
    }
}
