import SwiftUI
import UniformTypeIdentifiers

@main
struct framesApp: App {
    init() {
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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open File...") {
                    openFileDialog()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(replacing: .windowArrangement) {
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

public extension Notification.Name {
    static let openVideoNotification = Notification.Name("FramesOpenVideoNotification")
    static let returnToDashboardNotification = Notification.Name("FramesReturnToDashboardNotification")
}
