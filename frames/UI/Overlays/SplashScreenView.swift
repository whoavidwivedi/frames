import SwiftUI

public struct SplashScreenView: View {
    private static let duration = 1.08
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

    private var wordmark: some View {
        Text("Frames")
            .font(.system(size: 72, weight: .semibold))
            .tracking(-5)
    }

    private func artwork(at progress: Double) -> some View {
        let dark = colorScheme == .dark
        let ink = dark ? Color.white : Color(red: 0.055, green: 0.067, blue: 0.13)
        let paper = dark ? Color(red: 0.045, green: 0.049, blue: 0.086)
            : Color(red: 0.92, green: 0.93, blue: 0.98)
        let sweep = -0.42 + 1.82 * progress
        let energy = sin(.pi * min(1, progress / 0.85))
        let colors: [Color] = [
            Color(red: 0.17, green: 0.11, blue: 0.86),
            Color(red: 0.17, green: 0.43, blue: 1),
            Color(red: 0.31, green: 0.76, blue: 1),
            Color(red: 0.72, green: 0.32, blue: 1),
            Color(red: 1, green: 0.54, blue: 0.39)
        ]
        let band = LinearGradient(
            colors: [ink, ink] + colors + [ink, ink],
            startPoint: UnitPoint(x: sweep - 0.53, y: 0.78),
            endPoint: UnitPoint(x: sweep + 0.53, y: 0.22)
        )

        return ZStack {
            paper

            ZStack {
                ForEach(colors.indices.reversed(), id: \.self) { index in
                    let depth = Double(index + 1)
                    wordmark
                        .foregroundStyle(colors[index])
                        .mask {
                            LinearGradient(
                                colors: [.clear, .black, .clear],
                                startPoint: UnitPoint(x: sweep - 0.42, y: 0.82),
                                endPoint: UnitPoint(x: sweep + 0.30, y: 0.18)
                            )
                        }
                        .blur(radius: 1.5 + depth * 1.35)
                        .offset(x: depth * 4.2 * energy, y: -depth * 1.5 * energy)
                        .opacity(energy * (dark ? 0.74 : 0.57))
                }

                wordmark.foregroundStyle(band)
            }
            .offset(x: -8 * (1 - progress))
        }
    }
}
