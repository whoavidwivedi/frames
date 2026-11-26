import SwiftUI

public struct SplashScreenView: View {
    private static let duration = 1.55
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    public var onComplete: () -> Void

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        Group {
            if reduceMotion {
                artwork(at: 0)
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

    private static let heatColors: [Color] = [
        Color(red: 0.38, green: 0.30, blue: 0.98),
        Color(red: 0.18, green: 0.43, blue: 1),
        Color(red: 0.28, green: 0.73, blue: 1),
        Color(red: 0.80, green: 0.40, blue: 0.98),
        Color(red: 1, green: 0.48, blue: 0.68),
        Color(red: 1, green: 0.65, blue: 0.46)
    ]

    private func artwork(at progress: Double) -> some View {
        ZStack {
            Color.white

            Canvas { context, size in
                let expansion = min(1, max(0, (progress - 0.10) / 0.66))
                guard expansion > 0 else { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let spread = expansion * expansion * (3 - 2 * expansion)
                let width = 110 + (size.width * 0.83 - 110) * spread
                let height = 15 + (size.height * 0.83 - 15) * spread
                let strength = min(1, expansion * 7)

                for index in Self.heatColors.indices.reversed() {
                    let band = Double(index)
                    let scale = 0.31 + band * 0.145
                    var contour = Path()
                    for step in 0...96 {
                        let angle = Double(step) * 2 * .pi / 96
                        let fold = 1 + 0.088 * sin(5 * angle + progress * 6 + band * 0.6)
                            + 0.047 * cos(8 * angle - progress * 5)
                        let point = CGPoint(
                            x: center.x + cos(angle) * width * scale * fold,
                            y: center.y + sin(angle) * height * scale * fold
                        )
                        if step == 0 {
                            contour.move(to: point)
                        } else {
                            contour.addLine(to: point)
                        }
                    }
                    contour.closeSubpath()

                    var layer = context
                    layer.addFilter(.blur(radius: 4 + spread * 7 + band * 0.6))
                    layer.fill(contour, with: .color(Self.heatColors[index].opacity(strength * 0.76)))
                }
            }

            Text("Frames")
                .font(.system(size: 72, weight: .semibold))
                .tracking(-3)
                .foregroundStyle(Color.black)
        }
    }
}
