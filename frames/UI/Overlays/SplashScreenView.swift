import SwiftUI
import CoreText

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

    private static let wordmarkFont: Font = {
        guard let url = Bundle.main.url(forResource: "GoogleSansFlex", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return .system(size: 72, weight: .semibold)
        }
        let font = CTFontCreateWithFontDescriptor(descriptor, 72, nil)
        return Font(font).weight(.semibold)
    }()

    private static let exposureColors = [
        Color(red: 0.12, green: 0.08, blue: 0.92),
        Color(red: 0.05, green: 0.23, blue: 1),
        Color(red: 0.08, green: 0.48, blue: 1),
        Color(red: 0.21, green: 0.68, blue: 1),
        Color(red: 0.58, green: 0.26, blue: 1),
        Color(red: 0.95, green: 0.27, blue: 0.79),
        Color(red: 1, green: 0.46, blue: 0.61),
        Color(red: 1, green: 0.56, blue: 0.29)
    ]

    private func artwork(at progress: Double) -> some View {
        let reveal = min(1, max(0, (progress - 0.24) / 0.26))
        let ink = Color(red: 0.03, green: 0.034, blue: 0.052)

        return ZStack {
            Color(red: 0.90, green: 0.91, blue: 0.96)

            ZStack {
                ZStack {
                    flames(at: progress)
                        .frame(width: 270, height: 138)
                        .offset(y: -42)
                    ForEach(Self.exposureColors.indices.reversed(), id: \.self) { index in
                        exposure(at: index, progress: progress)
                    }
                    wordmark
                        .foregroundStyle(Color(red: 0.07, green: 0.06, blue: 0.25))
                        .scaleEffect(x: 1 + 0.085 * reveal, y: 1 + 0.23 * reveal)
                        .blur(radius: 6)
                        .opacity(0.84 * reveal)

                    wordmark
                        .foregroundStyle(ink)
                        .scaleEffect(x: 1 + 0.035 * reveal, y: 1 + 0.12 * reveal)
                        .blur(radius: 2.8)
                        .opacity(0.75 * reveal)
                }
                .padding(64)
                .compositingGroup()
                .overlay {
                    if let grain = Self.grain {
                        Image(decorative: grain, scale: 1)
                            .resizable(resizingMode: .tile)
                            .blendMode(.sourceAtop)
                    }
                }
                .compositingGroup()

                wordmark.foregroundStyle(ink)
                    .opacity(reveal * reveal * (3 - 2 * reveal))
            }
            .fixedSize()
        }
    }

    // Generate one fixed texture so the grain stays still as the light moves.
    private static let grain: CGImage? = {
        let side = 128
        var seed: UInt32 = 1973
        var pixels = [UInt8]()
        pixels.reserveCapacity(side * side * 4)
        for _ in 0..<(side * side) {
            seed = seed &* 1664525 &+ 1013904223
            let alpha = UInt8((seed >> 25) % 44)
            let value = seed & 0x01000000 == 0 ? alpha : 0
            pixels.append(contentsOf: [value, value, value, alpha])
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()

    private var wordmark: some View {
        Text("Frames")
            .font(Self.wordmarkFont)
            .tracking(-3)
            .fixedSize()
    }

    private func flames(at progress: Double) -> some View {
        Canvas { context, size in
            let heights: [Double] = [0.84, 0.48, 0.71, 0.59, 0.80, 0.51]
            let base = size.height * 0.84
            for (index, height) in heights.enumerated() {
                let lane = Double(index)
                let elapsed = max(0, progress - lane * 0.022)
                let rise = min(1, elapsed / 0.53)
                let growth = 1 - pow(1 - rise, 2)
                let sway = sin(progress * 15 - lane * 1.3)
                let x = size.width * (0.13 + lane * 0.147)
                let width = size.width * 0.105
                let tip = CGPoint(x: x + (10 + sway * 13) * growth,
                                  y: base - size.height * height * growth * (1 + sway * 0.13))

                var silhouette = Path()
                silhouette.move(to: CGPoint(x: x - width, y: base))
                silhouette.addQuadCurve(
                    to: tip,
                    control: CGPoint(x: x - width * 0.9 + sway * 9, y: tip.y + 34)
                )
                silhouette.addCurve(
                    to: CGPoint(x: x + width, y: base),
                    control1: CGPoint(x: tip.x - sway * 16, y: tip.y + 35),
                    control2: CGPoint(x: x + width * 1.3, y: base - 13)
                )
                silhouette.closeSubpath()

                var glow = context
                glow.addFilter(.blur(radius: 6))
                glow.opacity = min(1, elapsed * 7) * 0.83
                glow.fill(silhouette, with: .linearGradient(
                    Gradient(colors: [Self.exposureColors[7], Self.exposureColors[5],
                                      Self.exposureColors[2], Self.exposureColors[0]]),
                    startPoint: tip,
                    endPoint: CGPoint(x: tip.x, y: base)
                ))
            }
        }
    }

    private func exposure(at index: Int, progress: Double) -> some View {
        let layer = Double(index + 1)
        let elapsed = max(0, progress - Double(index) * 0.031)
        let growth = min(1, elapsed / 0.62)
        let depth = layer * (1 - pow(1 - growth, 2))
        let fadeIn = min(1, elapsed * 7)
        let intensity = 0.92 - layer * 0.048
        let color = Self.exposureColors[index]
        let fold = sin(progress * 6 + layer * 0.69)
        let next = Self.exposureColors[min(index + 1, Self.exposureColors.count - 1)]
        let band = LinearGradient(
            stops: [
                .init(color: color.opacity(0.60), location: 0),
                .init(color: next, location: 0.35 + 0.12 * fold),
                .init(color: color, location: 0.57 + 0.12 * fold),
                .init(color: color.opacity(0.52), location: 1)
            ],
            startPoint: UnitPoint(x: 0.18 + 0.12 * fold, y: 0),
            endPoint: UnitPoint(x: 0.82 - 0.12 * fold, y: 1)
        )

        return wordmark.hidden()
            .overlay {
                Rectangle().fill(band).mask {
                    wordmark
                        .background(alignment: .bottom) {
                            Capsule()
                                .fill(.white)
                                .frame(height: 23)
                                .padding(.horizontal, 7)
                                .padding(.bottom, 12)
                        }
                }
            }
            .scaleEffect(x: 1 + depth * 0.058, y: 1 + depth * (0.115 + 0.019 * fold))
            .offset(y: -depth * 2.4)
            .blur(radius: 1.2 + depth * 0.76)
            .opacity(fadeIn * intensity)
    }
}
