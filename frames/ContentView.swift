import SwiftUI
import AVFoundation
import AppKit

@MainActor
struct ContentView: View {
    var engine: VideoPlayerEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var pointerOverTransport = false
    @State private var library = LibraryManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var windowManager = WindowManager.shared
    @State private var commandPalette = CommandPaletteManager.shared
    @State private var keyboardHandler: KeyboardHandler?
    @State private var hideControlsTimer: Timer?
    @State private var isTargetedForDrop: Bool = false
    @State private var hostWindow: NSWindow?
    @State private var lastControlsTimerReset = Date.distantPast
    @State private var pendingResumePrompt: ResumePromptData? = nil
    @State private var updateManager = UpdateManager.shared
    @State private var settings = SettingsManager.shared
    @State private var snapshotFailureMessage: String?

    @MainActor
    init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    @MainActor
    init() {
        self.engine = VideoPlayerEngine()
    }

    @ViewBuilder
    private var videoSurface: some View {
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
                .buttonStyle(FramesPressStyle())
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
            .pointingHand()
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
            .pointingHand()
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var windowOverlays: some View {
        // Subtitle Display (unmounted when empty to decouple overlay for direct hardware scanout)
        if !engine.activeSubtitleText.isEmpty {
            SubtitleOverlayView(
                text: engine.activeSubtitleText
            )
            .padding(.bottom, engine.controlsVisible ? 92 : 24)
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
                    engine.activeInspectorSheet = nil
                }
                .pointingHand()
        }
    }

    @ViewBuilder
    private var transportOverlays: some View {
        // Docked Top Bar (Title, format, badges, return to dashboard)
        if engine.controlsVisible {
            VStack(spacing: 0) {
                TopBarOverlay(engine: engine) {
                    returnToDashboard()
                }
                Spacer()
            }
        }

        // Tier 1: thin always-on progress line (fades out when the full controls appear)
        if !engine.controlsVisible && !windowManager.isAnyFullscreen {
            VStack(spacing: 0) {
                Spacer()
                PlayerProgressLine(engine: engine)
            }
            .allowsHitTesting(false)
        }

        // Docked Bottom Control Bar (Scrubber, Playback, Audio, Subtitles, Rate, PiP, Fullscreen)
        if engine.controlsVisible {
            VStack(spacing: 0) {
                Spacer()
                LiquidGlassHUD(engine: engine)
                    .onHover { hovering in
                        pointerOverTransport = hovering
                        resetControlsTimer()
                    }
            }
        }
    }

    @ViewBuilder
    private var statusOverlays: some View {
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
            .zIndex(60)
        }

        // Transient volume readout (top-right, fades after adjustment)
        VolumeReadout(engine: engine)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 58)
            .padding(.trailing, 16)
            .zIndex(70)

        // Transient watched/total time readout (top right, fades after T)
        TimeReadout(engine: engine)
            .zIndex(66)

        // Buffering Indicator
        if engine.isBuffering {
            Label("Buffering…", systemImage: "hourglass").foregroundStyle(.white)
                .padding(20)
                .background(ShadcnTheme.card.opacity(0.8))
                .clipShape(Capsule())
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

    private var sceneContent: some View {
        ZStack {
            ShadcnTheme.background.ignoresSafeArea()

            if engine.currentURL == nil || engine.currentURL?.path.isEmpty == true {
                // Full Dashboard with Sidebar
                DashboardView(library: library) { url in
                    requestPlayVideo(url: url)
                }
                .ignoresSafeArea(.all, edges: .top)
            } else {
                // Active Video Player Surface
                ZStack {
                    videoSurface
                    windowOverlays
                    transportOverlays
                    statusOverlays
                }
                .background(Color.black.ignoresSafeArea())
                .onContinuousHover { _ in
                    resetControlsTimer(force: false)
                }
            }

            // Resume Playback Prompt Dialog
            if let prompt = pendingResumePrompt {
                ResumePlaybackOverlay(
                    prompt: prompt,
                    onResume: { url, seekTime in
                        pendingResumePrompt = nil
                        engine.seek(to: seekTime, exact: true)
                        engine.play()
                    },
                    onStartOver: { url in
                        pendingResumePrompt = nil
                        library.resetPlaybackProgress(for: url)
                        engine.seek(to: 0, exact: true)
                        engine.play()
                    },
                    onCancel: {
                        pendingResumePrompt = nil
                    }
                )
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
                            settings.closeSettings()
                        }
                        .pointingHand()

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
                            .buttonStyle(FramesPressStyle())
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
            }
            if updateManager.isUpdatePromptPresented, let update = updateManager.availableUpdate {
                UpdateAvailableOverlay(
                    update: update,
                    manager: updateManager,
                    onDismiss: {
                        updateManager.dismissPrompt()
                    }
                )
                .zIndex(160)
            }

            // Manual Check Notice Toast
            if let notice = updateManager.manualCheckNotice {
                UpdateNoticeToast(notice: notice) {
                    updateManager.dismissNotice()
                }
                .zIndex(170)
            }

        }
    }

    private var windowContent: some View {
        sceneContent
        .frame(minWidth: 460, minHeight: 320)
        .background(HostWindowAccessor(window: $hostWindow))
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var playbackContent: some View {
        windowContent
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
                engine.controlsVisible = true
                if engine.hasEnded {
                    NSCursor.setHiddenUntilMouseMoves(false)
                }
            }
        }
        .onChange(of: engine.activeInspectorSheet) { _, _ in resetControlsTimer() }
        .onChange(of: voiceOverEnabled) { _, _ in resetControlsTimer() }
        .onDisappear {
            hideControlsTimer?.invalidate()
            hideControlsTimer = nil
        }
        .onChange(of: engine.metadata.title) { _, _ in
            updateWindowRepresentation(for: engine.currentURL)
        }
        .onChange(of: engine.currentURL) { _, newURL in
            updateWindowRepresentation(for: newURL)
        }
    }

    private var eventContent: some View {
        playbackContent
        .onAppear {
            keyboardHandler = KeyboardHandler(engine: engine)
            // The engine is shared by every window, so this closure must not capture a
            // particular view's window. Broadcast instead and let the active window
            // handle the transition via the receiver below.
            engine.onPlaybackEnded = {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .playbackEndedNotification, object: nil)
                }
            }
            resetControlsTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVideoNotification)) { notification in
            guard isActiveWindow, let url = notification.object as? URL else { return }
            handleDroppedURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .returnToDashboardNotification)) { _ in
            guard isActiveWindow else { return }
            returnToDashboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playbackEndedNotification)) { _ in
            guard isActiveWindow else { return }
            returnToDashboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapshotFailedNotification)) { notification in
            guard isActiveWindow else { return }
            snapshotFailureMessage = notification.object as? String ?? "Unknown error."
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPaletteNotification)) { _ in
            guard isActiveWindow else { return }
            commandPalette.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenFilePickerNotification)) { _ in
            guard isActiveWindow else { return }
            openFileDialog()
        }
    }

    var body: some View {
        eventContent
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
                do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
                updateManager.checkForUpdates(manual: false)
            }
        }
        .tint(ShadcnTheme.actionTint)
        .preferredColorScheme(themeManager.mode.colorScheme)
        .onChange(of: engine.currentURL) { _, newURL in
            windowManager.isPlayerActive = (newURL != nil && !(newURL?.path.isEmpty ?? true))
        }
        .alert(
            "Couldn’t Save Snapshot",
            isPresented: Binding(
                get: { snapshotFailureMessage != nil },
                set: { presented in
                    if !presented { snapshotFailureMessage = nil }
                }
            ),
            presenting: snapshotFailureMessage
        ) { _ in
            Button("OK", role: .cancel) { snapshotFailureMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private func requestPlayVideo(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) || TestEnvironment.isRunningTests else {
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
            // Load the video paused at the resume position so the prompt sits
            // inside the player, over the timeline.
            playVideo(url: url, seekTo: resume.seconds, autoPlay: false)
            pendingResumePrompt = ResumePromptData(
                url: url,
                resumeSeconds: resume.seconds,
                formattedTime: resume.formattedTime,
                formattedDuration: TimeFormatting.format(seconds: dur),
                progress: resume.progress
            )
        } else {
            playVideo(url: url, seekTo: 0.0)
        }
    }

    private func playVideo(url: URL, seekTo: Double = 0.0, autoPlay: Bool = true) {
        library.addSingleVideoFile(url: url)
        engine.loadMedia(from: url, initialSeekTime: seekTo > 0 ? seekTo : nil, autoPlay: autoPlay)
        updateWindowRepresentation(for: url)
    }

    private func returnToDashboard() {
        pendingResumePrompt = nil
        hideControlsTimer?.invalidate()
        if WindowManager.shared.isAnyFullscreen {
            WindowManager.shared.exitAnyFullscreen()
        }
        NSCursor.setHiddenUntilMouseMoves(false)
        updateWindowRepresentation(for: nil)
        // Progress is saved and PiP is closed inside unloadMedia; doing both here as well
        // cost two extra UserDefaults persistence passes on the close path.
        engine.controlsVisible = true
        engine.unloadMedia()
    }

    private var isActiveWindow: Bool {
        guard let hostWindow else { return true }
        return hostWindow === NSApp.keyWindow || hostWindow === NSApp.mainWindow
    }

    private func updateWindowRepresentation(for url: URL?) {
        guard let window = hostWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
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
            engine.controlsVisible = true
        }
        hideControlsTimer?.invalidate()

        // Only auto-hide if currently playing, not ended, and no inspector sheet is open
        if shouldHideControls {
            hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                Task { @MainActor in
                    if shouldHideControls {
                        engine.controlsVisible = false
                        NSCursor.setHiddenUntilMouseMoves(true)
                    }
                }
            }
        }
    }

    private var shouldHideControls: Bool {
        engine.isPlaying && !engine.hasEnded && !engine.isScrubbing && engine.activeInspectorSheet == nil
            && !voiceOverEnabled && !pointerOverTransport
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

#if DEBUG
#Preview {
    ContentView()
}
#endif

private struct HostWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window !== nsView.window {
            window = nsView.window
        }
    }
}
