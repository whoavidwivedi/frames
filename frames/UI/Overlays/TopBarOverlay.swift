import SwiftUI
import AppKit

public struct TopBarOverlay: View {
    @Bindable var engine: VideoPlayerEngine
    public var onReturnToDashboard: (() -> Void)?
    @State private var windowManager = WindowManager.shared
    @State private var isBackHovered = false

    public init(engine: VideoPlayerEngine, onReturnToDashboard: (() -> Void)? = nil) {
        self.engine = engine
        self.onReturnToDashboard = onReturnToDashboard
    }

    public var body: some View {
        // Keep stable 78pt margin in both windowed and fullscreen so controls don't jump
        let trafficLightSpacer: CGFloat = 78

        VStack(spacing: 0) {
            ZStack {
                // Back button placed on the left with native traffic light spacer
                HStack(spacing: 8) {
                    Color.clear
                        .frame(width: trafficLightSpacer, height: 32)
                        .fixedSize(horizontal: true, vertical: false)

                    Button {
                        if let onReturn = onReturnToDashboard {
                            onReturn()
                        } else {
                            engine.unloadMedia()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isBackHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isBackHovered ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .strokeBorder(isBackHovered ? ShadcnTheme.borderActive : ShadcnTheme.borderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .accessibilityLabel("Back to Dashboard")
                    .onHover { isBackHovered = $0 }
                    .help("Back (Esc or ⌘[)")

                    Spacer()
                }
                .frame(height: 32)

                // Video Title & Format Badges (Centered)
                HStack(spacing: 8) {
                    Text(engine.metadata.title.isEmpty ? "Video Playback" : engine.metadata.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !engine.metadata.codec.isEmpty && engine.metadata.codec != "Unknown" {
                        Text(engine.metadata.codec)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(ShadcnTheme.secondary.opacity(0.40))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                            )
                    }
                }
                .shadow(color: Color.black.opacity(0.70), radius: 4, x: 0, y: 1)
                .padding(.horizontal, trafficLightSpacer + 48)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.70), Color.black.opacity(0.25), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            WindowManager.shared.performTitleBarDoubleClickAction()
        }
        .macOSDefaultTitleBar()
        .environment(\.colorScheme, .dark)
    }
}
