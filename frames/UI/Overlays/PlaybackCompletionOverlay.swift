import SwiftUI

public struct PlaybackCompletionOverlay: View {
    public let title: String
    public var onReturnToDashboard: () -> Void
    public var onReplay: () -> Void

    @State private var isHoveringReturn: Bool = false
    @State private var isHoveringReplay: Bool = false

    public init(
        title: String,
        onReturnToDashboard: @escaping () -> Void,
        onReplay: @escaping () -> Void
    ) {
        self.title = title
        self.onReturnToDashboard = onReturnToDashboard
        self.onReplay = onReplay
    }

    public var body: some View {
        ZStack {
            // Subtle dimmed backdrop that can also be clicked to return
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    onReturnToDashboard()
                }

            // Glassmorphic Shadcn Completion Card
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Color(red: 0.22, green: 0.82, blue: 0.45))
                    .shadow(color: Color.green.opacity(0.35), radius: 10, x: 0, y: 0)

                VStack(spacing: 4) {
                    Text("Playback Complete")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foreground)

                    if !title.isEmpty {
                        Text(title)
                            .font(.system(size: 13))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                HStack(spacing: 12) {
                    // Primary Action: Return to Dashboard
                    Button(action: onReturnToDashboard) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Back to Dashboard")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(ShadcnTheme.primaryForeground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radius4xl, style: .continuous)
                                .fill(isHoveringReturn ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .scaleEffect(isHoveringReturn ? 1.02 : 1.0)
                    .animation(.fluidQuick, value: isHoveringReturn)
                    .onHover { h in
                        withAnimation(.fluidQuick) {
                            isHoveringReturn = h
                        }
                    }
                    .help("Return to Dashboard (Return or Esc)")

                    // Secondary Action: Replay Video
                    Button(action: onReplay) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Replay")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(ShadcnTheme.secondaryForeground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radius4xl, style: .continuous)
                                .fill(isHoveringReplay ? ShadcnTheme.cardHover : ShadcnTheme.secondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radius4xl, style: .continuous)
                                        .strokeBorder(isHoveringReplay ? ShadcnTheme.borderActive : ShadcnTheme.border, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .scaleEffect(isHoveringReplay ? 1.02 : 1.0)
                    .animation(.fluidQuick, value: isHoveringReplay)
                    .onHover { h in
                        withAnimation(.fluidQuick) {
                            isHoveringReplay = h
                        }
                    }
                    .help("Replay from beginning (Space or R)")
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .fill(ShadcnTheme.card.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 8)
            )
            .frame(maxWidth: 380)
        }
    }
}
