import SwiftUI

public struct SplashScreenView: View {
    public var onComplete: () -> Void

    @State private var textOpacity: Double = 0.0
    @State private var blurRadius: CGFloat = 14.0
    @State private var textTracking: CGFloat = 1.5
    @State private var textScale: CGFloat = 0.90
    @State private var bloomRadius: CGFloat = 10.0
    @State private var bloomOpacity: Double = 0.0
    @State private var exitScale: CGFloat = 1.0
    @State private var exitOpacity: Double = 1.0

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack(alignment: .center) {
            // Dynamic Shadcn neutral surface (Dark: #0a0a0a | Light: #ffffff)
            ShadcnTheme.background
                .ignoresSafeArea()

            // Centered Typographic Composition
            ZStack(alignment: .center) {
                // Base Typographic Layer (Emerges strictly from center)
                Text("frames")
                    .font(.googleSans(46, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)
                    .tracking(textTracking)
                    .blur(radius: blurRadius)
                    .scaleEffect(textScale, anchor: .center)
                    .opacity(textOpacity)

                // Symmetrical Radial Center Bloom (Emanates outward strictly from the center of the word)
                Text("frames")
                    .font(.googleSans(46, weight: .semibold))
                    .foregroundStyle(
                        RadialGradient(
                            stops: [
                                .init(color: ShadcnTheme.foreground, location: 0.0),
                                .init(color: ShadcnTheme.primaryHighlight.opacity(0.85), location: 0.4),
                                .init(color: Color.clear, location: 1.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: bloomRadius
                        )
                    )
                    .tracking(textTracking)
                    .scaleEffect(textScale, anchor: .center)
                    .opacity(bloomOpacity)
            }
            .scaleEffect(exitScale, anchor: .center)
            .opacity(exitOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea()
        .pointingHand()
        .contentShape(Rectangle())
        .onAppear {
            startTypographicSequence()
        }
        .onTapGesture {
            quickDismiss()
        }
    }

    private func startTypographicSequence() {
        // Stage 1: Text emerges symmetrically from the optical center (0.0s - 0.65s)
        withAnimation(.easeOut(duration: 0.65)) {
            textOpacity = 1.0
            blurRadius = 0.0
            textScale = 1.0
            textTracking = 3.5
        }

        // Stage 2: Symmetrical crystalline radial light bloom expanding outward from the center (0.3s - 0.95s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            bloomOpacity = 0.85
            withAnimation(.easeInOut(duration: 0.65)) {
                bloomRadius = 180.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    bloomOpacity = 0.0
                }
            }
        }

        // Stage 3: Gentle Cinematic Dissolve from the center into App (1.25s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeOut(duration: 0.22)) {
                exitScale = 1.04
                exitOpacity = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                onComplete()
            }
        }
    }

    private func quickDismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            exitScale = 1.02
            exitOpacity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onComplete()
        }
    }
}
