import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    public static let openVideoNotification = Notification.Name("FramesOpenVideoNotification")
    public static let returnToDashboardNotification = Notification.Name("FramesReturnToDashboardNotification")
    public static let toggleCommandPaletteNotification = Notification.Name("FramesToggleCommandPaletteNotification")
    public static let requestOpenFilePickerNotification = Notification.Name("FramesRequestOpenFilePickerNotification")
    public static let triggerSnapshotNotification = Notification.Name("FramesTriggerSnapshotNotification")
}

@main
struct framesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var engine = VideoPlayerEngine()

    init() {
        UserDefaults.standard.register(defaults: [
            "NSQuitAlwaysKeepsWindows": false,
            "ApplePersistenceIgnoreState": true
        ])
        NSWindow.allowsAutomaticWindowTabbing = false
        ThemeManager.shared.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
                .onOpenURL { url in
                    NotificationCenter.default.post(name: .openVideoNotification, object: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 620)
        .commands {
            SwiftUI.CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdateManager.shared.checkForUpdates(manual: true)
                }
            }

            SwiftUI.CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    SettingsManager.shared.toggleSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            SwiftUI.CommandGroup(replacing: .newItem) {
                Button("Open File...") {
                    openFileDialog()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    let recentVideos = LibraryManager.shared.videos.filter { $0.lastPlayedDate != nil }
                    if recentVideos.isEmpty {
                        Text("No Recent Videos")
                    } else {
                        ForEach(recentVideos) { video in
                            Button(video.title) {
                                NotificationCenter.default.post(name: .openVideoNotification, object: video.url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            SettingsManager.shared.clearWatchHistory()
                        }
                    }
                }

                Divider()

                Button("Save Frame Snapshot") {
                    NotificationCenter.default.post(
                        name: .triggerSnapshotNotification,
                        object: nil
                    )
                    if let currentURL = engine.currentURL {
                        do {
                            let metadata = try FrameCaptureEngine.shared.saveFrame(
                                pixelBuffer: nil,
                                videoTitle: currentURL.deletingPathExtension().lastPathComponent,
                                timestampSeconds: engine.currentTime
                            )
                            NotificationCenter.default.post(
                                name: Notification.Name("FramesSnapshotCapturedNotification"),
                                object: metadata
                            )
                        } catch {
                            print("Frame capture error: \(error)")
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(engine.currentURL == nil)

                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            SwiftUI.CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    LibraryManager.shared.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider()

                Button(WindowManager.shared.isAnyFullscreen ? "Exit Full Screen" : "Enter Full Screen") {
                    WindowManager.shared.toggleNativeFullscreen()
                }
                .keyboardShortcut("f", modifiers: [.control, .command])

                Button(PictureInPictureManager.shared.isPictureInPicture ? "Exit Picture in Picture" : "Picture in Picture") {
                    PictureInPictureManager.shared.toggle(engine: engine)
                }
                .keyboardShortcut("p", modifiers: [])
                .disabled(engine.currentURL == nil)

                Button("Hardware Metrics Inspector") {
                    engine.activeInspectorSheet = (engine.activeInspectorSheet == .stats ? nil : .stats)
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(engine.currentURL == nil)

                Divider()

                Button("Command Palette...") {
                    CommandPaletteManager.shared.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            CommandMenu("Playback") {
                Button(engine.isPlaying ? "Pause" : (engine.hasEnded ? "Replay" : "Play")) {
                    engine.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(engine.currentURL == nil)

                Divider()

                Button("Skip Forward 10s") {
                    engine.skip(seconds: 10)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(engine.currentURL == nil)

                Button("Skip Backward 10s") {
                    engine.skip(seconds: -10)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(engine.currentURL == nil)

                Button("Next Frame") {
                    engine.stepFrame(forward: true)
                }
                .keyboardShortcut(".", modifiers: [])
                .disabled(engine.currentURL == nil)

                Button("Previous Frame") {
                    engine.stepFrame(forward: false)
                }
                .keyboardShortcut(",", modifiers: [])
                .disabled(engine.currentURL == nil)

                Divider()

                Button("Faster") {
                    engine.playbackRate = min(3.0, ((engine.playbackRate + 0.1) * 10).rounded() / 10)
                }
                .keyboardShortcut("]", modifiers: [])
                .disabled(engine.currentURL == nil)

                Button("Slower") {
                    engine.playbackRate = max(0.25, ((engine.playbackRate - 0.1) * 10).rounded() / 10)
                }
                .keyboardShortcut("[", modifiers: [])
                .disabled(engine.currentURL == nil)

                Button("Normal Speed (1.0×)") {
                    engine.playbackRate = 1.0
                }
                .disabled(engine.currentURL == nil)

                Divider()

                Button("Volume Up") {
                    engine.setVolumeDelta(0.05)
                }
                .keyboardShortcut(.upArrow, modifiers: [])

                Button("Volume Down") {
                    engine.setVolumeDelta(-0.05)
                }
                .keyboardShortcut(.downArrow, modifiers: [])

                Button(engine.isMuted ? "Unmute" : "Mute") {
                    engine.toggleMute()
                }
                .keyboardShortcut("m", modifiers: [])

                Divider()

                Menu("Subtitles") {
                    Button("Off") {
                        engine.selectSubtitleTrack(SubtitleTrack.off)
                    }
                    ForEach(engine.availableSubtitleTracks.filter { $0.id != SubtitleTrack.off.id }) { track in
                        Button(track.title) {
                            engine.selectSubtitleTrack(track)
                        }
                    }
                }
                .disabled(engine.currentURL == nil)

                Menu("Audio Track") {
                    ForEach(engine.availableAudioTracks) { track in
                        Button(track.title) {
                            engine.selectAudioTrack(track)
                        }
                    }
                }
                .disabled(engine.currentURL == nil)
            }

            CommandMenu("Navigate") {
                Button("Back") {
                    NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                    LibraryManager.shared.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    LibraryManager.shared.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!LibraryManager.shared.canGoForward)
            }

            CommandMenu("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { ThemeManager.shared.mode },
                    set: { ThemeManager.shared.mode = $0 }
                )) {
                    ForEach(ThemeMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.icon).tag(mode)
                    }
                }
            }
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
            NotificationCenter.default.post(name: .openVideoNotification, object: url)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        for window in NSApp.windows {
            window.tabbingMode = .disallowed
        }

        if CommandLine.arguments.contains("--run-tests") {
            let result = FramesTestSuite.runAllTests()
            for line in result.logs {
                print(line)
            }
            fflush(stdout)
            exit(result.failed == 0 ? 0 : 1)
        }

        if let smokeIndex = CommandLine.arguments.firstIndex(of: "--smoke-test") {
            var mediaURL: URL? = nil
            if smokeIndex + 1 < CommandLine.arguments.count {
                let candidate = CommandLine.arguments[smokeIndex + 1]
                if !candidate.hasPrefix("-") {
                    let url = URL(fileURLWithPath: candidate)
                    var isDir: ObjCBool = false
                    if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) || isDir.boolValue {
                        print("✖ ERROR: Specified smoke test media file not found or is a directory: \(candidate)")
                        fflush(stdout)
                        exit(1)
                    }
                    mediaURL = url
                }
            }
            let result = FramesTestSuite.runSmokeTest(mediaURL: mediaURL)
            for line in result.logs {
                print(line)
            }
            fflush(stdout)
            exit(result.passed ? 0 : 1)
        }

        if let mainMenu = NSApp.mainMenu {
            Self.cleanTabBarMenuItems(from: mainMenu)
            Self.deduplicateMenus(in: mainMenu)
        }

        DispatchQueue.main.async {
            if let mainMenu = NSApp.mainMenu {
                Self.cleanTabBarMenuItems(from: mainMenu)
                Self.deduplicateMenus(in: mainMenu)
            }
            for window in NSApp.windows {
                window.tabbingMode = .disallowed
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                window.tabbingMode = .disallowed
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                if let window = notification.object as? NSWindow {
                    window.tabbingMode = .disallowed
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                if let menu = notification.object as? NSMenu {
                    AppDelegate.cleanTabBarMenuItems(from: menu)
                }
                if let mainMenu = NSApp.mainMenu {
                    AppDelegate.cleanTabBarMenuItems(from: mainMenu)
                }
            }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        NotificationCenter.default.post(name: .openVideoNotification, object: url)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else { return }
        let url = URL(fileURLWithPath: first)
        NotificationCenter.default.post(name: .openVideoNotification, object: url)
        sender.reply(toOpenOrPrint: .success)
    }

    private static let tabActionSelectors: Set<String> = [
        "toggleTabBar:",
        "_toggleTabBar:",
        "toggleTabOverview:",
        "_toggleTabOverview:",
        "toggleShowAllViews:",
        "_toggleShowAllViews:",
        "toggleShowAllTabs:",
        "_toggleShowAllTabs:"
    ]

    @discardableResult
    public static func cleanTabBarMenuItems(from menu: NSMenu) -> Int {
        var removedCount = 0
        var index = menu.items.count - 1
        while index >= 0 {
            let item = menu.items[index]
            let actionString = item.action.map { NSStringFromSelector($0) } ?? ""
            let title = item.title

            let lowerAction = actionString.lowercased()
            let matchesAction = tabActionSelectors.contains(actionString) ||
                                lowerAction.contains("toggletabbar") ||
                                lowerAction.contains("toggletaboverview") ||
                                lowerAction.contains("toggleshowallviews") ||
                                lowerAction.contains("toggleshowalltabs")

            let matchesTitle = title.localizedCaseInsensitiveContains("Tab Bar") ||
                               title.localizedCaseInsensitiveContains("All Tabs") ||
                               title.localizedCaseInsensitiveContains("Tab Overview")

            if matchesAction || matchesTitle {
                menu.removeItem(at: index)
                removedCount += 1
            } else if let submenu = item.submenu {
                removedCount += cleanTabBarMenuItems(from: submenu)
            }
            index -= 1
        }

        pruneDividers(in: menu)
        return removedCount
    }

    public static func pruneDividers(in menu: NSMenu) {
        var i = 0
        while i < menu.items.count {
            if menu.items[i].isSeparatorItem {
                while i + 1 < menu.items.count && menu.items[i + 1].isSeparatorItem {
                    menu.removeItem(at: i + 1)
                }
            }
            i += 1
        }

        while let first = menu.items.first, first.isSeparatorItem {
            menu.removeItem(at: 0)
        }

        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(at: menu.items.count - 1)
        }
    }

    @discardableResult
    public static func deduplicateMenus(in mainMenu: NSMenu) -> Int {
        var seenTitles = Set<String>()
        var removed = 0
        var index = 0
        while index < mainMenu.items.count {
            let item = mainMenu.items[index]
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                if seenTitles.contains(title) {
                    mainMenu.removeItem(at: index)
                    removed += 1
                    continue
                } else {
                    seenTitles.insert(title)
                }
            }
            index += 1
        }
        return removed
    }
}
