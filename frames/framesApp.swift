import SwiftUI
import UniformTypeIdentifiers

@main
struct framesApp: App {
    init() {
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
        }
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        panel.message = "Choose a video to open in Frames"

        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(name: .openVideoNotification, object: url)
        }
    }
}

public extension Notification.Name {
    static let openVideoNotification = Notification.Name("FramesOpenVideoNotification")
}
