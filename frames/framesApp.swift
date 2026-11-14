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
        _ = GoogleSansFontManager.registerIfNeeded()
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
                .font(.googleSans(13))
                .onOpenURL { url in
                    NotificationCenter.default.post(name: .openVideoNotification, object: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 620)
        .commands {
            // Keep the menu bar to the essentials: app menu (About/Settings/Updates/Quit),
            // File, Edit, View (fullscreen), Window and Help.
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

                Divider()

                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            SwiftUI.CommandGroup(replacing: .sidebar) {
                Button(WindowManager.shared.isAnyFullscreen ? "Exit Full Screen" : "Enter Full Screen") {
                    WindowManager.shared.toggleNativeFullscreen()
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
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
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                window.tabbingMode = .disallowed
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false
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
                    window.standardWindowButton(.closeButton)?.isHidden = false
                    window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                    window.standardWindowButton(.zoomButton)?.isHidden = false
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
