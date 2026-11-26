import SwiftUI
import AppKit

public struct TopBarOverlay: View {
    @Bindable var engine: VideoPlayerEngine
    public var onReturnToDashboard: (() -> Void)?
    @State private var windowManager = WindowManager.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isCloseHovered = false

    public init(engine: VideoPlayerEngine, onReturnToDashboard: (() -> Void)? = nil) {
        self.engine = engine
        self.onReturnToDashboard = onReturnToDashboard
    }

    private var closeButton: some View {
        Button {
            if let onReturn = onReturnToDashboard {
                onReturn()
            } else {
                engine.unloadMedia()
            }
        } label: {
            Image(systemName: "arrow.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(isCloseHovered ? 0.78 : 0.60)))
                .overlay(Circle().strokeBorder(Color.white.opacity(isCloseHovered ? 0.35 : 0.20), lineWidth: 1))
        }
        .buttonStyle(FramesPressStyle())
        .pointingHand()
        .accessibilityLabel("Return to library")
        .help("Return to library")
        .onHover { hovering in
            isCloseHovered = hovering
        }
    }

    public var body: some View {
        HStack(spacing: 12) {
            closeButton
            Text(engine.metadata.title.isEmpty ? (engine.currentURL?.lastPathComponent ?? "Video") : engine.metadata.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, windowManager.isAnyFullscreen ? 20 : 80)
        .padding(.trailing, 20)
        .frame(height: 52)
        .background {
            if reduceTransparency {
                Color.black
            } else {
                LinearGradient(colors: [.black.opacity(0.88), .black.opacity(0.64), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            WindowManager.shared.performTitleBarDoubleClickAction()
        }
        .pointingHand()
        .macOSDefaultTitleBar()
        .environment(\.colorScheme, .dark)
    }
}
