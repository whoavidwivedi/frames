import SwiftUI
import AppKit

public struct TopBarOverlay: View {
    @Bindable var engine: VideoPlayerEngine
    public var onReturnToDashboard: (() -> Void)?
    @State private var windowManager = WindowManager.shared

    public init(engine: VideoPlayerEngine, onReturnToDashboard: (() -> Void)? = nil) {
        self.engine = engine
        self.onReturnToDashboard = onReturnToDashboard
    }

    public var body: some View {
        let isFs = windowManager.isNativeFullscreen
        let trafficLightSpacer: CGFloat = isFs ? 14 : 78

        VStack(spacing: 0) {
            ZStack {
                // Back button placed on the left with native traffic light spacer
                HStack(spacing: 8) {
                    Color.clear
                        .frame(width: trafficLightSpacer, height: 32)
                        .fixedSize(horizontal: true, vertical: false)

                    // Default macOS Bordered Button
                    Button {
                        if let onReturn = onReturnToDashboard {
                            onReturn()
                        } else {
                            engine.unloadMedia()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityLabel("Back to Dashboard")
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
