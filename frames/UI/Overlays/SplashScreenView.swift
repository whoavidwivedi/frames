import SwiftUI

public struct SplashScreenView: View {
    public var onComplete: () -> Void

    @State private var textOpacity: Double = 0.0
    @State private var blurRadius: CGFloat = 16.0
    @State private var textTracking: CGFloat = -1.0
    @State private var textScale: CGFloat = 0.94
    @State private var shimmerOffset: CGFloat = -180
    @State private var shimmerOpacity: Double = 0.0
    @State private var exitScale: CGFloat = 1.0
    @State private var exitOpacity: Double = 1.0

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            // Dynamic Shadcn neutral surface (Dark: #0a0a0a | Light: #ffffff)
            ShadcnTheme.background
                .ignoresSafeArea()

            // Just Text: "frames"
            ZStack {
                // Base Typographic Layer
                Text("frames")
                    .font(.system(size: 46, weight: .semibold, design: .default))
                    .foregroundStyle(ShadcnTheme.foreground)
                    .tracking(textTracking)
                    .blur(radius: blurRadius)
                    .scaleEffect(textScale)
                    .opacity(textOpacity)

                // Projector Optical Light Sweep (Sweeps across the letterforms)
                Text("frames")
                    .font(.system(size: 46, weight: .semibold, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: ShadcnTheme.primaryHighlight.opacity(0.4), location: 0.35),
                                .init(color: ShadcnTheme.foreground, location: 0.5),
                                .init(color: ShadcnTheme.primaryHighlight.opacity(0.4), location: 0.65),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .tracking(textTracking)
                    .offset(x: shimmerOffset)
                    .mask(
                        Text("frames")
                            .font(.system(size: 46, weight: .semibold, design: .default))
                            .tracking(textTracking)
                    )
                    .scaleEffect(textScale)
                    .opacity(shimmerOpacity)
            }
            .scaleEffect(exitScale)
            .opacity(exitOpacity)
        }
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
        // Stage 1: Text emerges from optical lens blur & breathes open (0.0s - 0.6s)
        withAnimation(.easeOut(duration: 0.65)) {
            textOpacity = 1.0
            blurRadius = 0.0
            textScale = 1.0
            textTracking = 4.0
        }

        // Stage 2: Crystalline Light Sweep across the word (0.3s - 0.9s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            shimmerOpacity = 1.0
            withAnimation(.easeInOut(duration: 0.65)) {
                shimmerOffset = 180
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.2)) {
                    shimmerOpacity = 0.0
                }
            }
        }

        // Stage 3: Gentle Cinematic Dissolve into App (1.25s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeInOut(duration: 0.35)) {
                exitScale = 1.03
                exitOpacity = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
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
