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

        let videoSize = engine.metadata.naturalSize
        let aspect: CGFloat = (videoSize.width > 0 && videoSize.height > 0) ? (videoSize.width / videoSize.height) : (16.0 / 9.0)
        let initialWidth: CGFloat = 460
        let initialHeight: CGFloat = initialWidth / aspect
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
        panel.minSize = NSSize(width: 240, height: 240 / aspect)
        panel.maxSize = NSSize(width: 960, height: 960 / aspect)
        panel.aspectRatio = (videoSize.width > 0 && videoSize.height > 0) ? NSSize(width: videoSize.width, height: videoSize.height) : NSSize(width: 16, height: 9)

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
                        Button {
                            PictureInPictureManager.shared.closePictureInPicture(stopPlayback: true)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.black.opacity(0.60)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help("Close Picture in Picture")

                        Spacer()

                        // Go-back-to-non-picture-in-picture-mode Button
                        Button {
                            PictureInPictureManager.shared.exitPictureInPicture()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pip.exit")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(Color.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.black.opacity(0.60)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help("Return to Main Window")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    Spacer()

                    // Center / Bottom Dock: Skip Back, Play/Pause, Skip Forward, Mute
                    HStack(spacing: 12) {
                        // 10s Backward
                        Button {
                            engine.skip(seconds: -10)
                            showControlsTemporarily()
                        } label: {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.18)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help("Skip back 10s")

                        // Play / Pause Button
                        Button {
                            engine.togglePlayPause()
                            showControlsTemporarily()
                        } label: {
                            Image(systemName: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.white.opacity(0.24)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help(engine.isPlaying ? "Pause" : "Play")

                        // 10s Forward
                        Button {
                            engine.skip(seconds: 10)
                            showControlsTemporarily()
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.18)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help("Skip forward 10s")

                        // Mute Button
                        Button {
                            engine.toggleMute()
                            showControlsTemporarily()
                        } label: {
                            Image(systemName: engine.isMuted ? "speaker.slash.fill" : (engine.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.18)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help(engine.isMuted ? "Unmute" : "Mute")
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
