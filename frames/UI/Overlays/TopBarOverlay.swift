import SwiftUI
import AppKit

public struct TopBarOverlay: View {
    @Bindable var engine: VideoPlayerEngine
    public var onReturnToDashboard: (() -> Void)?
    @State private var windowManager = WindowManager.shared
    @State private var isCloseHovered = false

    public init(engine: VideoPlayerEngine, onReturnToDashboard: (() -> Void)? = nil) {
        self.engine = engine
        self.onReturnToDashboard = onReturnToDashboard
    }

    /// Floating neutral capsule that keeps the title legible over any frame without a
    /// full-width gradient wash across the video.
    private var titleBadge: some View {
        HStack(spacing: 8) {
            Text(engine.metadata.title.isEmpty ? "Video Playback" : engine.metadata.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShadcnTheme.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            // Close button trailing the title
            Button {
                if let onReturn = onReturnToDashboard {
                    onReturn()
                } else {
                    engine.unloadMedia()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isCloseHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(isCloseHovered ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35))
                    )
            }
            .buttonStyle(.plain)
            .pointingHand()
            .accessibilityLabel("Close player")
            .help("Close (Esc)")
            .onHover { isCloseHovered = $0 }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            Capsule(style: .continuous)
                .fill(ShadcnTheme.card.opacity(0.55))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 2)
        .environment(\.colorScheme, .dark)
    }

    public var body: some View {
        // Keep stable 78pt margin in both windowed and fullscreen so controls don't jump
        let trafficLightSpacer: CGFloat = 78

        VStack(spacing: 0) {
            // Video Title, Format Badge & Close Button (Centered Floating Capsule)
            titleBadge
                .padding(.horizontal, trafficLightSpacer + 48)
                .frame(maxWidth: .infinity)
                .frame(height: 32)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            WindowManager.shared.performTitleBarDoubleClickAction()
        }
        .macOSDefaultTitleBar()
        .environment(\.colorScheme, .dark)
    }
}
