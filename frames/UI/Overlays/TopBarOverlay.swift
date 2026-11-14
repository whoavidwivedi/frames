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
        Text(engine.metadata.title.isEmpty ? "Video Playback" : engine.metadata.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ShadcnTheme.foreground)
            .lineLimit(1)
            .truncationMode(.middle)
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

    /// Same circular cross as the PiP player, moved out of the centered title capsule.
    private var closeButton: some View {
        Button {
            if let onReturn = onReturnToDashboard {
                onReturn()
            } else {
                engine.unloadMedia()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.black.opacity(isCloseHovered ? 0.78 : 0.60)))
                .overlay(Circle().strokeBorder(Color.white.opacity(isCloseHovered ? 0.35 : 0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityLabel("Close player")
        .help("Close (Esc)")
        .onHover { hovering in
            withAnimation(.fluidQuick) {
                isCloseHovered = hovering
            }
        }
    }

    public var body: some View {
        // Keep stable 78pt margin in both windowed and fullscreen so controls don't jump
        let trafficLightSpacer: CGFloat = 78

        VStack(spacing: 0) {
            // Video Title (centered) & Close (top-right)
            ZStack {
                titleBadge
                    .padding(.horizontal, trafficLightSpacer + 48)

                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.trailing, 16)
            }
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
