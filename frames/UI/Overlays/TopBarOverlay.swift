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
        // Keep stable 78pt margin in both windowed and fullscreen so controls don't jump to the left
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isBackHovered ? Color.white.opacity(0.24) : Color.white.opacity(0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to Dashboard")
                    .onHover { isBackHovered = $0 }
                    .help("Back (Esc or ⌘[)")

                    Spacer()
                }
                .frame(height: 32)

                // Video title centered horizontally with no background
                Text(engine.metadata.title.isEmpty ? "Video Playback" : engine.metadata.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.75), radius: 3, x: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
                colors: [Color.black.opacity(0.60), Color.black.opacity(0.20), Color.clear],
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
