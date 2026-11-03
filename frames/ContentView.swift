import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @State private var engine = VideoPlayerEngine()
    @State private var library = LibraryManager.shared
    @State private var keyboardHandler: KeyboardHandler?
    @State private var hideControlsTimer: Timer?
    @State private var isWindowHovered: Bool = false
    @State private var isTargetedForDrop: Bool = false
    @State private var showSplash: Bool = true

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.039).ignoresSafeArea()

            if engine.currentURL == nil || engine.currentURL?.path.isEmpty == true {
                // Full Dashboard with Sidebar
                DashboardView(library: library) { url in
                    playVideo(url: url)
                }
                .transition(.opacity)
            } else {
                // Active Video Player Surface
                ZStack {
                    // Direct Hardware AVPlayerLayer Canvas (Apple Silicon 0-Copy)
                    VideoCanvasView(
                        player: engine.player,
                        onSingleClick: {
                            engine.togglePlayPause()
                            resetControlsTimer()
                        },
                        onDoubleClick: {
                            toggleFullscreen()
                        }
                    )
                    .ignoresSafeArea()

                    // Subtitle Display
                    SubtitleOverlayView(
                        text: engine.activeSubtitleText,
                        fontSize: engine.subtitleFontSize
                    )

                    // Top Bar (Title, format, badges, return to dashboard, eject)
                    if engine.controlsVisible {
                        VStack {
                            TopBarOverlay(engine: engine) {
                                returnToDashboard()
                            }
                            Spacer()
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    }

                    // Floating Liquid Glass HUD
                    if engine.controlsVisible {
                        VStack {
                            Spacer()
                            LiquidGlassHUD(engine: engine)
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    }

                    // Buffering Indicator
                    if engine.isBuffering {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.4)
                            .tint(.white)
                            .padding(20)
                            .background(ShadcnTheme.card.opacity(0.8))
                            .clipShape(Circle())
                    }
                }
                .onContinuousHover { _ in
                    resetControlsTimer()
                }
                .transition(.opacity)
            }

            // Splash Screen Animation on App Open
            if showSplash {
                SplashScreenView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .frame(minWidth: 850, minHeight: 520)
        .onAppear {
            keyboardHandler = KeyboardHandler(engine: engine)
            resetControlsTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVideoNotification)) { notification in
            if let url = notification.object as? URL {
                handleDroppedURL(url)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        handleDroppedURL(url)
                    }
                }
            }
            return true
        }
    }

    private func playVideo(url: URL) {
        library.addSingleVideoFile(url: url)
        engine.loadMedia(from: url)
    }

    private func returnToDashboard() {
        if let url = engine.currentURL, !url.path.isEmpty {
            let progress = engine.duration > 0 ? (engine.currentTime / engine.duration) : 0.0
            library.recordPlayback(url: url, duration: engine.duration, progress: progress)
        }
        engine.pause()
        withAnimation(.easeInOut(duration: 0.2)) {
            engine.loadMedia(from: URL(fileURLWithPath: ""))
        }
    }

    private func handleDroppedURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "srt" || ext == "vtt" {
            engine.loadExternalSubtitleFile(from: url)
        } else {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                library.addFolder(url: url)
            } else {
                playVideo(url: url)
            }
        }
    }

    private func resetControlsTimer() {
        withAnimation(.easeInOut(duration: 0.2)) {
            engine.controlsVisible = true
        }
        hideControlsTimer?.invalidate()

        // Only auto-hide if currently playing and no inspector sheet is open
        if engine.isPlaying && engine.activeInspectorSheet == nil {
            hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { _ in
                Task { @MainActor in
                    if engine.isPlaying && engine.activeInspectorSheet == nil && !engine.isScrubbing {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            engine.controlsVisible = false
                        }
                    }
                }
            }
        }
    }

    private func toggleFullscreen() {
        if WindowManager.shared.isAnyFullscreen {
            WindowManager.shared.exitAnyFullscreen()
        } else {
            WindowManager.shared.toggleNativeFullscreen()
        }
    }
}

#Preview {
    ContentView()
}
