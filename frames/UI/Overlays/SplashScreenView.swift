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

    private static let letters = Array("Frames")
    private static let exposureColors = [
        Color(red: 0.21, green: 0.13, blue: 0.99),
        Color(red: 0.09, green: 0.42, blue: 1),
        Color(red: 0.24, green: 0.78, blue: 1),
        Color(red: 0.76, green: 0.32, blue: 1),
        Color(red: 1, green: 0.52, blue: 0.39)
    ]

    private func artwork(at progress: Double) -> some View {

        return ZStack {
            Color.white

            ZStack {
                HStack(alignment: .firstTextBaseline, spacing: -3) {
                    ForEach(Self.letters.indices, id: \.self) { index in
                        glyph(at: index)
                            .foregroundStyle(Color.clear)
                            .background {
                                exposures(of: glyph(at: index), index: index, progress: progress)
                            }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: -3) {
                    ForEach(Self.letters.indices, id: \.self) { index in
                        glyph(at: index).foregroundStyle(Color.black)
                    }
                }
            }
            .fixedSize()
        }
    }

    private func glyph(at index: Int) -> Text {
        Text(String(Self.letters[index]))
            .font(.system(size: 72, weight: .semibold))
    }

    private func exposures(of letter: Text, index: Int, progress: Double) -> some View {
        ZStack {
            ForEach(Self.exposureColors.indices.reversed(), id: \.self) { layer in
                let depth = Double(layer + 1)
                let stagger = Double(index) * 0.021 + Double(layer) * 0.038
                let unfurl = min(1, max(0, (progress - 0.13 - stagger) / 0.51))
                let spread = 1 - pow(1 - unfurl, 2)
                let ripple = sin(progress * 9 + Double(index) * 0.82 + depth * 0.56)
                let color = Self.exposureColors[layer]

                letter
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.35), color, color.opacity(0.72)],
                            startPoint: .bottomLeading, endPoint: .topTrailing
                        )
                    )
                    .scaleEffect(x: 1 + depth * 0.06 * spread,
                                 y: 1 + depth * 0.16 * spread, anchor: .bottomLeading)
                    .rotationEffect(.degrees((depth * 2.1 + ripple * 2) * spread),
                                    anchor: .bottomLeading)
                    .blur(radius: 2.2 + depth * 1.55 * spread)
                    .offset(x: (depth * 5 + ripple * 3) * spread,
                            y: -(depth * 9 + ripple * 5) * spread)
                    .opacity(min(1, unfurl * 4) * 0.80 * (1 - Double(layer) * 0.09))
            }
        }
    }
}
