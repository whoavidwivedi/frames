import SwiftUI
import AVFoundation
import AppKit

@MainActor
struct ContentView: View {
    var engine: VideoPlayerEngine
    @State private var library = LibraryManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var windowManager = WindowManager.shared
    @State private var commandPalette = CommandPaletteManager.shared
    @State private var keyboardHandler: KeyboardHandler?
    @State private var hideControlsTimer: Timer?
    @State private var isTargetedForDrop: Bool = false
    @State private var lastControlsTimerReset = Date.distantPast
    @State private var showSplash: Bool = false
    @State private var pendingResumePrompt: ResumePromptData? = nil
    @State private var updateManager = UpdateManager.shared
    @State private var settings = SettingsManager.shared

    @MainActor
    init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    @MainActor
    init() {
        self.engine = VideoPlayerEngine()
    }

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
                            videoFrameRate: engine.metadata.frameRate > 0 ? engine.metadata.frameRate : 60.0,
                            isDecoupledFullscreen: WindowManager.shared.isAnyFullscreen
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

                    // Subtitle Display (unmounted when empty to decouple overlay for direct hardware scanout)
                    if !engine.activeSubtitleText.isEmpty {
                        SubtitleOverlayView(
                            text: engine.activeSubtitleText
                        )
                        .padding(.bottom, engine.controlsVisible ? 84 : 24)
                    }

                    // Top window drag & title bar management strip (when controls hidden in windowed mode)
                    if !engine.controlsVisible && !WindowManager.shared.isAnyFullscreen {
                        VStack {
                            Color.clear
                                .frame(height: 38)
                                .macOSDefaultTitleBar()
                            Spacer()
                        }
                    }

                    // Dismiss Active Inspector Sheets on outside click (Transparent, NO BLACK CURTAIN).
                    // Kept below the controls so panel rows stay clickable.
                    if engine.activeInspectorSheet != nil {
                        Color.clear
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.fluidQuick) {
                                    engine.activeInspectorSheet = nil
                                }
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

                    // Mid-left audio & subtitle cluster (panels open beside it)
                    if engine.controlsVisible {
                        PlayerSideControls(engine: engine)
                            .transition(.opacity)
                    }

                    // Tier 1: thin always-on progress line (fades out when the full controls appear)
                    if engine.currentURL != nil {
                        VStack(spacing: 0) {
                            Spacer()
                            PlayerProgressLine(engine: engine)
                        }
                        .opacity(engine.controlsVisible ? 0 : 1)
                        .allowsHitTesting(false)
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

                    // Top-anchored Hardware Stats Panel (when active)
                    if engine.activeInspectorSheet == .stats {
                        VStack {
                            HStack {
                                Spacer()
                                HardwareStatsPanel(engine: engine)
                                    .padding(.top, engine.controlsVisible ? 58 : 16)
                                    .padding(.trailing, 16)
                            }
                            Spacer()
                        }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.94)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            )
                        )
                        .zIndex(60)
                    }

                    // Transient volume readout (top-right, fades after adjustment)
                    VolumeReadout(engine: engine)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 58)
                        .padding(.trailing, 16)
                        .zIndex(70)

                    // Transient skip flow overlay (liquid glass, sides)
                    SkipReadout(engine: engine)
                        .zIndex(65)

                    // Transient watched/total time readout (top right, fades after T)
                    TimeReadout(engine: engine)
                        .zIndex(66)

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
                .background(Color.black.ignoresSafeArea())
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
                        withAnimation(.fluidQuick) {
                            pendingResumePrompt = nil
                        }
                        playVideo(url: url, seekTo: seekTime)
                    },
                    onStartOver: { url in
                        withAnimation(.fluidQuick) {
                            pendingResumePrompt = nil
                        }
                        library.resetPlaybackProgress(for: url)
                        playVideo(url: url, seekTo: 0.0)
                    },
                    onCancel: {
                        withAnimation(.fluidQuick) {
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

            // Non-Destructive Settings Modal Overlay during Video Playback
            if settings.isSettingsPresented && engine.currentURL != nil {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.fluidQuick) {
                                settings.closeSettings()
                            }
                        }

                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button {
                                settings.closeSettings()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .padding(.trailing, 16)
                            .padding(.top, 12)
                        }

                        SettingsView()
                    }
                    .frame(maxWidth: 820, maxHeight: 560)
                    .background(ShadcnTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
                }
                .zIndex(140)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if updateManager.isUpdatePromptPresented, let update = updateManager.availableUpdate {
                UpdateAvailableOverlay(
                    update: update,
                    manager: updateManager,
                    onDismiss: {
                        withAnimation(.fluidQuick) {
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
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 12)),
                    removal: .opacity.combined(with: .offset(y: 6))
                ))
                .zIndex(170)
            }

            // Splash Screen Animation on App Launch
            if showSplash {
                SplashScreenView {
                    withAnimation(.fluidQuick) {
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
        .animation(.fluidQuick, value: engine.currentURL != nil)
        .animation(.fluidQuick, value: engine.controlsVisible)
        .animation(.fluidOverlay, value: settings.isSettingsPresented)
        .animation(.fluidOverlay, value: updateManager.isUpdatePromptPresented)
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
                withAnimation(.fluidQuick) {
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
        .onChange(of: engine.metadata.title) { _, _ in
            updateWindowRepresentation(for: engine.currentURL)
        }
        .onChange(of: engine.currentURL) { _, newURL in
            updateWindowRepresentation(for: newURL)
        }
        .onAppear {
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
        guard FileManager.default.fileExists(atPath: url.path) || CommandLine.arguments.contains("--run-tests") else {
            library.verifyAndPruneMissingFiles()
            return
        }

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
            withAnimation(.fluidQuick) {
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
        updateWindowRepresentation(for: url)
    }

    private func returnToDashboard() {
        hideControlsTimer?.invalidate()
        NSCursor.setHiddenUntilMouseMoves(false)
        updateWindowRepresentation(for: nil)
        // Progress is saved and PiP is closed inside unloadMedia; doing both here as well
        // cost two extra UserDefaults persistence passes on the close path.
        withAnimation(.fluidQuick) {
            engine.controlsVisible = true
            engine.unloadMedia()
        }
    }

    private func updateWindowRepresentation(for url: URL?) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        if let url = url {
            let displayName = engine.metadata.title.isEmpty ? url.lastPathComponent : engine.metadata.title
            window.title = displayName
            window.representedURL = url
        } else {
            window.title = "Frames"
            window.representedURL = nil
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

        if !engine.controlsVisible {
            withAnimation(.fluidQuick) {
                engine.controlsVisible = true
            }
        }
        hideControlsTimer?.invalidate()

        // Only auto-hide if currently playing, not ended, and no inspector sheet is open
        if engine.isPlaying && !engine.hasEnded && engine.activeInspectorSheet == nil {
            hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                Task { @MainActor in
                    if engine.isPlaying && !engine.hasEnded && engine.activeInspectorSheet == nil && !engine.isScrubbing {
                        withAnimation(.fluidQuick) {
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
