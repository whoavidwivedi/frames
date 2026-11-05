import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct framesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        ThemeManager.shared.applyAppearance()
        if CommandLine.arguments.contains("--run-tests") {
            let result = FramesTestSuite.runAllTests()
            for line in result.logs {
                print(line)
            }
            exit(result.failed == 0 ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 620)
        .commands {
            SwiftUI.CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdateManager.shared.checkForUpdates(manual: true)
                }
            }

            SwiftUI.CommandGroup(replacing: .newItem) {
                Button("Open File...") {
                    openFileDialog()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            SwiftUI.CommandGroup(replacing: .windowArrangement) {
                Button("Minimize") {
                    NSApp.keyWindow?.miniaturize(nil)
                }
                .keyboardShortcut("m", modifiers: .command)

                Button("Zoom") {
                    WindowManager.shared.toggleWindowedFullscreen()
                }

                Divider()

                Button(WindowManager.shared.isNativeFullscreen ? "Exit Full Screen" : "Enter Full Screen") {
                    WindowManager.shared.toggleNativeFullscreen()
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }

            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    LibraryManager.shared.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider()

                Button("Command Palette...") {
                    CommandPaletteManager.shared.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)
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

        if let mainMenu = NSApp.mainMenu {
            Self.cleanTabBarMenuItems(from: mainMenu)
        }

        DispatchQueue.main.async {
            if let mainMenu = NSApp.mainMenu {
                Self.cleanTabBarMenuItems(from: mainMenu)
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
}

public extension Notification.Name {
    static let openVideoNotification = Notification.Name("FramesOpenVideoNotification")
    static let returnToDashboardNotification = Notification.Name("FramesReturnToDashboardNotification")
    static let toggleCommandPaletteNotification = Notification.Name("FramesToggleCommandPaletteNotification")
    static let requestOpenFilePickerNotification = Notification.Name("FramesRequestOpenFilePickerNotification")
}
