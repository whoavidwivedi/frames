import AppKit
import SwiftUI

public final class KeyboardHandler {
    private var localMonitor: Any?

    public init(engine: VideoPlayerEngine) {
        setupMonitor(engine: engine)
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupMonitor(engine: VideoPlayerEngine) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Don't intercept if user is typing into a text field, EXCEPT for Escape (dismiss focus)
            if let firstResponder = NSApp.keyWindow?.firstResponder, firstResponder is NSTextView || firstResponder is NSTextField {
                if event.keyCode == 53 {
                    Task { @MainActor in
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        LibraryManager.shared.searchQuery = ""
                    }
                    return nil
                }
                return event
            }

            let keyCode = event.keyCode
            let isShift = event.modifierFlags.contains(.shift)

            let isOption = event.modifierFlags.contains(.option)

            switch keyCode {
            case 49: // Space
                Task { @MainActor in engine.togglePlayPause() }
                return nil

            case 123: // Left Arrow
                let delta = isShift ? -30.0 : -5.0
                Task { @MainActor in engine.skip(seconds: delta) }
                return nil

            case 124: // Right Arrow
                let delta = isShift ? 30.0 : 5.0
                Task { @MainActor in engine.skip(seconds: delta) }
                return nil

            case 126: // Up Arrow
                Task { @MainActor in engine.setVolumeDelta(0.05) }
                return nil

            case 125: // Down Arrow
                Task { @MainActor in engine.setVolumeDelta(-0.05) }
                return nil

            case 46: // M key
                Task { @MainActor in engine.toggleMute() }
                return nil

            case 3: // F key (F for Native Fullscreen, Option+F for Windowed Fullscreen)
                Task { @MainActor in
                    if isOption {
                        WindowManager.shared.toggleWindowedFullscreen()
                    } else {
                        WindowManager.shared.toggleNativeFullscreen()
                    }
                }
                return nil

            case 13: // W key (Windowed Fullscreen shortcut)
                Task { @MainActor in
                    WindowManager.shared.toggleWindowedFullscreen()
                }
                return nil

            case 1: // S key (Subtitles)
                Task { @MainActor in
                    if engine.activeInspectorSheet == .subtitles {
                        engine.activeInspectorSheet = nil
                    } else {
                        engine.activeInspectorSheet = .subtitles
                    }
                }
                return nil

            case 34: // I key (Hardware Stats)
                Task { @MainActor in
                    if engine.activeInspectorSheet == .stats {
                        engine.activeInspectorSheet = nil
                    } else {
                        engine.activeInspectorSheet = .stats
                    }
                }
                return nil

            case 47: // Period (.) - Frame step forward
                Task { @MainActor in engine.stepFrame(forward: true) }
                return nil

            case 43: // Comma (,) - Frame step backward
                Task { @MainActor in engine.stepFrame(forward: false) }
                return nil

            case 30: // ] key (Speed up)
                Task { @MainActor in
                    engine.playbackRate = min(3.0, engine.playbackRate + 0.1)
                }
                return nil

            case 33: // [ key (Slow down)
                Task { @MainActor in
                    engine.playbackRate = max(0.25, engine.playbackRate - 0.1)
                }
                return nil

            case 53: // Escape key
                Task { @MainActor in
                    if engine.activeInspectorSheet != nil {
                        engine.activeInspectorSheet = nil
                    } else if WindowManager.shared.isAnyFullscreen {
                        WindowManager.shared.exitAnyFullscreen()
                    } else if engine.currentURL != nil && !(engine.currentURL?.path.isEmpty ?? true) {
                        let progress = engine.duration > 0 ? (engine.currentTime / engine.duration) : 0.0
                        LibraryManager.shared.recordPlayback(url: engine.currentURL!, duration: engine.duration, progress: progress)
                        engine.pause()
                        engine.loadMedia(from: URL(fileURLWithPath: ""))
                    }
                }
                return nil

            default:
                return event
            }
        }
    }
}
