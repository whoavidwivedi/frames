import SwiftUI
import AppKit
import AVFoundation

@MainActor
@Observable
public final class PictureInPictureManager {
    public static let shared = PictureInPictureManager()

    public private(set) var isPictureInPicture: Bool = false
    private var pipPanel: NSPanel?
    private weak var currentEngine: VideoPlayerEngine?

    private init() {}

    public func toggle(engine: VideoPlayerEngine) {
        if isPictureInPicture {
            exitPictureInPicture()
        } else {
            enterPictureInPicture(engine: engine)
        }
    }

    public func enterPictureInPicture(engine: VideoPlayerEngine) {
        guard !isPictureInPicture else { return }
        self.currentEngine = engine
        self.isPictureInPicture = true
        WindowManager.shared.isPictureInPicture = true

        let pipView = PictureInPictureContentView(engine: engine)
        let hostingView = NSHostingView(rootView: pipView)

        let initialWidth: CGFloat = 460
        let initialHeight: CGFloat = 260
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 800, height: 600)
        let margin: CGFloat = 24
        let pipX = screen.maxX - initialWidth - margin
        let pipY = screen.minY + margin
        let frame = NSRect(x: pipX, y: pipY, width: initialWidth, height: initialHeight)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .resizable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .black
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.minSize = NSSize(width: 280, height: 158)
        panel.maxSize = NSSize(width: 960, height: 540)
        panel.aspectRatio = NSSize(width: 16, height: 9)

        panel.orderFrontRegardless()
        self.pipPanel = panel
    }

    public func exitPictureInPicture() {
        guard isPictureInPicture else { return }
        isPictureInPicture = false
        WindowManager.shared.isPictureInPicture = false
        pipPanel?.close()
        pipPanel = nil
    }

    public func closePictureInPicture(stopPlayback: Bool = true) {
        if stopPlayback {
            currentEngine?.pause()
        }
        exitPictureInPicture()
    }
}

public struct PictureInPictureContentView: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var isHovered: Bool = false
    @State private var hideTimer: Timer?

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video Presentation Surface
            if engine.isNativePipelineActive {
                MetalVideoCanvasView(
                    renderer: engine.nativePipeline.renderer,
                    isPlaying: engine.isPlaying,
                    videoFrameRate: engine.metadata.frameRate > 0 ? engine.metadata.frameRate : 60.0
                ) {
                    engine.nativePipeline.nextFrameForDisplay()
                }
                .ignoresSafeArea()
            } else {
                VideoCanvasView(
                    player: engine.player,
                    onSingleClick: {
                        engine.togglePlayPause()
                        showControlsTemporarily()
                    },
                    onDoubleClick: {
                        PictureInPictureManager.shared.exitPictureInPicture()
                    }
                )
                .ignoresSafeArea()
            }

            // Subtitle Display
            if !engine.activeSubtitleText.isEmpty {
                VStack {
                    Spacer()
                    SubtitleOverlayView(text: engine.activeSubtitleText)
                        .padding(.bottom, isHovered ? 64 : 12)
                }
            }

            // Controls Overlay
            if isHovered {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack {
                    // Top Bar: Close (Left) & Restore (Right)
                    HStack {
                        // Close Button
                        AppleLiquidGlassButton(
                            icon: "xmark",
                            iconSize: 11,
                            iconWeight: .bold,
                            shape: .circle,
                            tint: .standard,
                            size: 26,
                            helpText: "Close Picture in Picture"
                        ) {
                            PictureInPictureManager.shared.closePictureInPicture(stopPlayback: true)
                        }

                        Spacer()

                        // Go-back-to-non-picture-in-picture-mode Button
                        AppleLiquidGlassButton(
                            icon: "pip.exit",
                            iconSize: 11,
                            iconWeight: .semibold,
                            shape: .circle,
                            tint: .standard,
                            size: 26,
                            helpText: "Return to Main Window"
                        ) {
                            PictureInPictureManager.shared.exitPictureInPicture()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    Spacer()

                    // Center / Bottom Dock: Skip Back, Play/Pause, Skip Forward, Mute
                    HStack(spacing: 12) {
                        // 10s Backward
                        AppleLiquidGlassButton(
                            icon: "gobackward.10",
                            iconSize: 13,
                            iconWeight: .semibold,
                            shape: .circle,
                            tint: .standard,
                            size: 32,
                            helpText: "Skip back 10s"
                        ) {
                            engine.skip(seconds: -10)
                            showControlsTemporarily()
                        }

                        // Play / Pause Button
                        AppleLiquidGlassButton(
                            icon: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"),
                            iconSize: 15,
                            iconWeight: .bold,
                            shape: .circle,
                            tint: .standard,
                            size: 38,
                            helpText: engine.isPlaying ? "Pause" : "Play"
                        ) {
                            engine.togglePlayPause()
                            showControlsTemporarily()
                        }

                        // 10s Forward
                        AppleLiquidGlassButton(
                            icon: "goforward.10",
                            iconSize: 13,
                            iconWeight: .semibold,
                            shape: .circle,
                            tint: .standard,
                            size: 32,
                            helpText: "Skip forward 10s"
                        ) {
                            engine.skip(seconds: 10)
                            showControlsTemporarily()
                        }

                        // Mute Button
                        AppleLiquidGlassButton(
                            icon: engine.isMuted ? "speaker.slash.fill" : (engine.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"),
                            iconSize: 13,
                            iconWeight: .semibold,
                            shape: .circle,
                            tint: engine.isMuted ? .danger : .standard,
                            size: 32,
                            helpText: engine.isMuted ? "Unmute" : "Mute"
                        ) {
                            engine.toggleMute()
                            showControlsTemporarily()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .padding(.bottom, 12)
                }
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
            if hovering {
                showControlsTemporarily()
            } else {
                hideTimer?.invalidate()
                hideTimer = nil
            }
        }
    }

    private func showControlsTemporarily() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.22)) {
                    isHovered = false
                }
            }
        }
    }
}
