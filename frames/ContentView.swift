import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @State private var engine = VideoPlayerEngine()
    @State private var library = LibraryManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var windowManager = WindowManager.shared
    @State private var keyboardHandler: KeyboardHandler?
    @State private var hideControlsTimer: Timer?
    @State private var isTargetedForDrop: Bool = false
    @State private var lastControlsTimerReset = Date.distantPast
    @State private var showSplash: Bool = true
    @State private var pendingResumePrompt: ResumePromptData? = nil

    var body: some View {
        ZStack {
            ShadcnTheme.background.ignoresSafeArea()

            if engine.currentURL == nil || engine.currentURL?.path.isEmpty == true {
                // Full Dashboard with Sidebar
                DashboardView(library: library) { url in
                    requestPlayVideo(url: url)
                }
                .ignoresSafeArea(.all, edges: .top)
                .transition(.opacity)
            } else {
                // Active Video Player Surface
                ZStack {
                    // Direct Hardware Video Surface (Zero-Copy Metal 3 HDR or AVPlayerLayer)
                    if engine.isNativePipelineActive {
                        MetalVideoCanvasView(renderer: engine.nativePipeline.renderer) {
                            engine.nativePipeline.nextFrameForDisplay()
                        }
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            toggleFullscreen()
                        }
                        .onTapGesture(count: 1) {
                            engine.togglePlayPause()
                            resetControlsTimer()
                        }
                    } else {
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
                    }

                    // Subtitle Display
                    SubtitleOverlayView(
                        text: engine.activeSubtitleText,
                        fontSize: engine.subtitleFontSize
                    )

                    // Top window drag & title bar management strip
                    VStack {
                        Color.clear
                            .frame(height: 38)
                            .macOSDefaultTitleBar()
                        Spacer()
                    }

                    // Top Bar (Title, format, badges, return to dashboard, eject)
                    if engine.controlsVisible {
                        VStack {
                            TopBarOverlay(engine: engine) {
                                returnToDashboard()
                            }
                            Spacer()
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -14)),
                                removal: .opacity.combined(with: .offset(y: -14))
                            )
                        )
                    }

                    // Floating Liquid Glass HUD
                    if engine.controlsVisible {
                        VStack {
                            Spacer()
                            LiquidGlassHUD(engine: engine)
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 16)),
                                removal: .opacity.combined(with: .offset(y: 16))
                            )
                        )
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

                    if let playbackError = engine.playbackError {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                                .foregroundStyle(ShadcnTheme.foreground)
                            Text("Can’t play this media")
                                .font(.headline)
                            Text(playbackError)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)

                            ShadcnButton(
                                "Back to Dashboard",
                                icon: "chevron.left",
                                variant: .secondary,
                                size: .sm
                            ) {
                                returnToDashboard()
                            }
                            .padding(.top, 4)
                        }
                        .foregroundStyle(ShadcnTheme.foreground)
                        .padding(20)
                        .frame(maxWidth: 380)
                        .background(ShadcnTheme.card.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                    }

                    // Playback Completion Overlay
                    if engine.hasEnded {
                        PlaybackCompletionOverlay(
                            title: engine.metadata.title,
                            onReturnToDashboard: {
                                returnToDashboard()
                            },
                            onReplay: {
                                engine.replay()
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .onContinuousHover { _ in
                    resetControlsTimer(force: false)
                }
                .transition(.opacity)
            }

            // Resume Playback Prompt Dialog
            if let prompt = pendingResumePrompt {
                ResumePlaybackOverlay(
                    prompt: prompt,
                    onResume: { url, seekTime in
                        withAnimation(.fluidSpring) {
                            pendingResumePrompt = nil
                        }
                        playVideo(url: url, seekTo: seekTime)
                    },
                    onStartOver: { url in
                        withAnimation(.fluidSpring) {
                            pendingResumePrompt = nil
                        }
                        library.resetPlaybackProgress(for: url)
                        playVideo(url: url, seekTo: 0.0)
                    },
                    onCancel: {
                        withAnimation(.fluidSpring) {
                            pendingResumePrompt = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(90)
            }

            // Splash Screen Animation on App Launch
            if showSplash {
                SplashScreenView {
                    withAnimation(.fluidSmooth) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .frame(minWidth: 460, minHeight: 320)
        .animation(.fluidSpring, value: engine.currentURL != nil)
        .animation(.fluidSpring, value: engine.controlsVisible)
        .animation(.fluidWindow, value: windowManager.currentLayoutState)
        .onChange(of: engine.controlsVisible) { _, visible in
            if !visible && engine.isPlaying {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
        .onChange(of: engine.isPlaying) { _, isPlaying in
            if isPlaying && !engine.hasEnded {
                resetControlsTimer(force: true)
            } else {
                hideControlsTimer?.invalidate()
                withAnimation(.fluidSpring) {
                    engine.controlsVisible = true
                }
                if engine.hasEnded {
                    NSCursor.setHiddenUntilMouseMoves(false)
                }
            }
        }
        .onChange(of: engine.hasEnded) { _, hasEnded in
            if hasEnded {
                hideControlsTimer?.invalidate()
                withAnimation(.fluidSpring) {
                    engine.controlsVisible = true
                }
                NSCursor.setHiddenUntilMouseMoves(false)
            }
        }
        .onAppear {
            keyboardHandler = KeyboardHandler(engine: engine)
            resetControlsTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVideoNotification)) { notification in
            if let url = notification.object as? URL {
                handleDroppedURL(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .returnToDashboardNotification)) { _ in
            returnToDashboard()
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
        .preferredColorScheme(themeManager.mode.colorScheme)
    }

    private func requestPlayVideo(url: URL) {
        if let resume = library.savedResumeTime(for: url) {
            let item = library.videos.first(where: { $0.url == url })
            let dur = item?.duration ?? 0.0
            withAnimation(.fluidSpring) {
                pendingResumePrompt = ResumePromptData(
                    url: url,
                    resumeSeconds: resume.seconds,
                    formattedTime: resume.formattedTime,
                    formattedDuration: TimeFormatting.format(seconds: dur),
                    progress: resume.progress
                )
            }
        } else {
            playVideo(url: url, seekTo: 0.0)
        }
    }

    private func playVideo(url: URL, seekTo: Double = 0.0) {
        library.addSingleVideoFile(url: url)
        engine.loadMedia(from: url, initialSeekTime: seekTo > 0 ? seekTo : nil)
    }

    private func returnToDashboard() {
        if let url = engine.currentURL, !url.path.isEmpty {
            let progress = engine.hasEnded ? 1.0 : (engine.duration > 0 ? (engine.currentTime / engine.duration) : 0.0)
            library.recordPlayback(url: url, duration: engine.duration, progress: progress)
        }
        hideControlsTimer?.invalidate()
        NSCursor.setHiddenUntilMouseMoves(false)
        withAnimation(.fluidSpring) {
            engine.controlsVisible = true
            engine.unloadMedia()
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
                guard MediaSupport.accepts(url) else { return }
                requestPlayVideo(url: url)
            }
        }
    }

    private func resetControlsTimer(force: Bool = true) {
        let now = Date()
        guard force || now.timeIntervalSince(lastControlsTimerReset) >= 0.25 else { return }
        lastControlsTimerReset = now

        withAnimation(.fluidSpring) {
            engine.controlsVisible = true
        }
        hideControlsTimer?.invalidate()

        // Only auto-hide if currently playing, not ended, and no inspector sheet is open
        if engine.isPlaying && !engine.hasEnded && engine.activeInspectorSheet == nil {
            hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { _ in
                Task { @MainActor in
                    if engine.isPlaying && !engine.hasEnded && engine.activeInspectorSheet == nil && !engine.isScrubbing {
                        withAnimation(.fluidSmooth) {
                            engine.controlsVisible = false
                        }
                        NSCursor.setHiddenUntilMouseMoves(true)
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
