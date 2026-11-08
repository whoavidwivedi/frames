import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @State private var engine = VideoPlayerEngine()
    @State private var library = LibraryManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var windowManager = WindowManager.shared
    @State private var commandPalette = CommandPaletteManager.shared
    @State private var keyboardHandler: KeyboardHandler?
    @State private var hideControlsTimer: Timer?
    @State private var isTargetedForDrop: Bool = false
    @State private var lastControlsTimerReset = Date.distantPast
    @State private var showSplash: Bool = true
    @State private var pendingResumePrompt: ResumePromptData? = nil
    @State private var updateManager = UpdateManager.shared
    @State private var settings = SettingsManager.shared
    @Environment(\.openSettings) private var openSettings

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
                    if PictureInPictureManager.shared.isPictureInPicture {
                        VStack(spacing: 16) {
                            Image(systemName: "pip.enter")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(Color.white.opacity(0.70))

                            Text("Playing in Picture-in-Picture")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)

                            Text(engine.metadata.title.isEmpty ? (engine.currentURL?.deletingPathExtension().lastPathComponent ?? "Current Media") : engine.metadata.title)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .lineLimit(1)

                            Button {
                                PictureInPictureManager.shared.exitPictureInPicture()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "pip.exit")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Restore to Window")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.16))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    } else if engine.isNativePipelineActive {
                        MetalVideoCanvasView(
                            renderer: engine.nativePipeline.renderer,
                            isPlaying: engine.isPlaying,
                            videoFrameRate: engine.metadata.frameRate > 0 ? engine.metadata.frameRate : 60.0
                        ) {
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
                        text: engine.activeSubtitleText
                    )
                    .padding(.bottom, engine.controlsVisible ? 84 : 24)

                    // Top window drag & title bar management strip (when controls hidden)
                    if !engine.controlsVisible {
                        VStack {
                            Color.clear
                                .frame(height: 38)
                                .macOSDefaultTitleBar()
                            Spacer()
                        }
                    }

                    // Docked Top Bar (Title, format, badges, return to dashboard)
                    if engine.controlsVisible {
                        VStack(spacing: 0) {
                            TopBarOverlay(engine: engine) {
                                returnToDashboard()
                            }
                            Spacer()
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -8)),
                                removal: .opacity
                            )
                        )
                    }

                    // Docked Bottom Control Bar (Scrubber, Playback, Audio, Subtitles, Rate, PiP, Fullscreen)
                    if engine.controlsVisible {
                        VStack(spacing: 0) {
                            Spacer()
                            LiquidGlassHUD(engine: engine)
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)),
                                removal: .opacity
                            )
                        )
                    }

                    // Inspector Popover Panels (Hardware Stats, Subtitles, Audio, Speed Shortcuts)
                    if let sheet = engine.activeInspectorSheet {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.fluidSpring) {
                                    engine.activeInspectorSheet = nil
                                }
                            }

                        VStack {
                            if sheet == .stats {
                                HStack {
                                    Spacer()
                                    HardwareStatsPanel(engine: engine)
                                        .padding(.top, engine.controlsVisible ? 58 : 16)
                                        .padding(.trailing, 16)
                                }
                                Spacer()
                            } else {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Group {
                                        switch sheet {
                                        case .subtitles:
                                            SubtitleSelectorPanel(engine: engine)
                                        case .audio:
                                            AudioSelectorPanel(engine: engine)
                                        case .speed:
                                            SpeedSelectorPanel(engine: engine)
                                        case .stats:
                                            EmptyView()
                                        }
                                    }
                                    .padding(.bottom, engine.controlsVisible ? 84 : 20)
                                    .padding(.trailing, 16)
                                }
                            }
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.94)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            )
                        )
                        .zIndex(60)
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

            // Command Palette Modal Dialog
            if commandPalette.isPresented {
                FramesCommandPalette(
                    isPresented: $commandPalette.isPresented,
                    engine: engine,
                    library: library,
                    themeManager: themeManager,
                    windowManager: windowManager,
                    onPlayURL: { url in
                        requestPlayVideo(url: url)
                    },
                    onOpenFilePicker: {
                        openFileDialog()
                    }
                )
                .zIndex(150)
            }

            // Update Available Modal Dialog
            if updateManager.isUpdatePromptPresented, let update = updateManager.availableUpdate {
                UpdateAvailableOverlay(
                    update: update,
                    manager: updateManager,
                    onDismiss: {
                        withAnimation(.fluidSpring) {
                            updateManager.dismissPrompt()
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(160)
            }

            // Manual Check Notice Toast
            if let notice = updateManager.manualCheckNotice {
                UpdateNoticeToast(notice: notice) {
                    withAnimation(.fluidQuick) {
                        updateManager.dismissNotice()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(170)
            }

            // Splash Screen Animation on App Launch
            if showSplash {
                SplashScreenView {
                    withAnimation(.fluidSmooth) {
                        showSplash = false
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .frame(minWidth: 460, minHeight: 320)
        .animation(.fluidSpring, value: engine.currentURL != nil)
        .animation(engine.controlsVisible ? .fluidSpring : .easeInOut(duration: 0.22), value: engine.controlsVisible)
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
                returnToDashboard()
            }
        }
        .onAppear {
            SettingsManager.shared.openSettingsAction = {
                openSettings()
            }
            keyboardHandler = KeyboardHandler(engine: engine)
            engine.onPlaybackEnded = {
                Task { @MainActor in
                    returnToDashboard()
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPaletteNotification)) { _ in
            commandPalette.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenFilePickerNotification)) { _ in
            openFileDialog()
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
        .task {
            // Delayed background check so startup is instant and non-blocking
            if SettingsManager.shared.automaticallyCheckForUpdates {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                updateManager.checkForUpdates(manual: false)
            }
        }
        .preferredColorScheme(themeManager.mode.colorScheme)
    }

    private func requestPlayVideo(url: URL) {
        let resumeMode = SettingsManager.shared.autoResumeMode
        if resumeMode == .startBeginning {
            playVideo(url: url, seekTo: 0.0)
            return
        }

        if let resume = library.savedResumeTime(for: url) {
            if resumeMode == .alwaysResume {
                playVideo(url: url, seekTo: resume.seconds)
                return
            }

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
        PictureInPictureManager.shared.exitPictureInPicture()
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
            hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                Task { @MainActor in
                    if engine.isPlaying && !engine.hasEnded && engine.activeInspectorSheet == nil && !engine.isScrubbing {
                        withAnimation(.easeInOut(duration: 0.22)) {
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

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = MediaSupport.contentTypes
        panel.message = "Choose a video or audio file to open in Frames"

        if panel.runModal() == .OK, let url = panel.url {
            handleDroppedURL(url)
        }
    }
}

#Preview {
    ContentView()
}
