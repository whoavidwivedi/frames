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
            // Don't intercept if user is typing into a text field, EXCEPT for Escape (dismiss focus) or Cmd+K
            if let firstResponder = NSApp.keyWindow?.firstResponder, firstResponder is NSTextView || firstResponder is NSTextField {
                if CommandPaletteManager.shared.isPresented {
                    return event
                }

                if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.option) && event.keyCode == 40 {
                    Task { @MainActor in
                        CommandPaletteManager.shared.toggle()
                    }
                    return nil
                }

                if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.option) && event.keyCode == 43 {
                    Task { @MainActor in
                        SettingsManager.shared.toggleSettings()
                    }
                    return nil
                }

                if event.keyCode == 53 {
                    Task { @MainActor in
                        if SettingsManager.shared.isSettingsPresented {
                            SettingsManager.shared.closeSettings()
                            return
                        }
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        LibraryManager.shared.searchQuery = ""
                    }
                    return nil
                }
                return event
            }

            if CommandPaletteManager.shared.isPresented {
                return event
            }

            let keyCode = event.keyCode
            let isShift = event.modifierFlags.contains(.shift)
            let isOption = event.modifierFlags.contains(.option)
            let isCommand = event.modifierFlags.contains(.command)
            let isControl = event.modifierFlags.contains(.control)

            // MARK: - 1. Standard macOS Window Management & System Shortcuts
            // macOS Default Full Screen: Control + Command + F (⌃⌘F)
            if isControl && isCommand && !isOption && keyCode == 3 {
                Task { @MainActor in
                    WindowManager.shared.toggleNativeFullscreen()
                }
                return nil
            }

            // macOS Windowed Full Screen / Zoom: Control + Option + Command + F (⌃⌥⌘F)
            if isControl && isOption && isCommand && keyCode == 3 {
                Task { @MainActor in
                    WindowManager.shared.toggleWindowedFullscreen()
                }
                return nil
            }

            // macOS Default Minimize: Command + M (⌘M)
            if isCommand && !isControl && !isOption && keyCode == 46 {
                Task { @MainActor in
                    NSApp.keyWindow?.miniaturize(nil)
                }
                return nil
            }

            // macOS Default Close Window: Command + W (⌘W)
            if isCommand && !isControl && !isOption && keyCode == 13 {
                Task { @MainActor in
                    NSApp.keyWindow?.performClose(nil)
                }
                return nil
            }

            // macOS Default Navigation Back: Command + [ (⌘[)
            if isCommand && !isControl && !isOption && keyCode == 33 {
                Task { @MainActor in
                    if engine.currentURL != nil {
                        NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                    } else {
                        LibraryManager.shared.goBack()
                    }
                }
                return nil
            }

            // macOS Navigation Forward: Command + ] (⌘])
            if isCommand && !isControl && !isOption && keyCode == 30 {
                Task { @MainActor in
                    if engine.currentURL == nil {
                        LibraryManager.shared.goForward()
                    }
                }
                return nil
            }

            // Toggle Sidebar: Command + B (⌘B)
            if isCommand && !isControl && !isOption && keyCode == 11 {
                Task { @MainActor in
                    LibraryManager.shared.toggleSidebar()
                }
                return nil
            }

            // Search & Command Palette: Command + F (⌘F) or Command + K (⌘K)
            if isCommand && !isControl && !isOption && (keyCode == 3 || keyCode == 40) {
                Task { @MainActor in
                    CommandPaletteManager.shared.toggle()
                }
                return nil
            }

            // Settings: Command + , (⌘,)
            if isCommand && !isControl && !isOption && keyCode == 43 {
                Task { @MainActor in
                    SettingsManager.shared.toggleSettings()
                }
                return nil
            }

            // Capture Frame Snapshot: Command + S (⌘S)
            if isCommand && !isControl && !isOption && keyCode == 1 {
                Task { @MainActor in
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
                            print("Frame snapshot error: \(error)")
                        }
                    }
                }
                return nil
            }

            // If any other Command or Control combination is pressed, let macOS handle it natively (e.g. ⌘Q, ⌘H, ⌥⌘H, ⌘O, ⌘`)
            if isCommand || isControl {
                return event
            }

            // NOTE: Option+F was intentionally removed per macOS defaults. Windowed fullscreen is accessed via macOS Zoom / ⌃⌥⌘F.
            if isOption {
                return event
            }

            // MARK: - 2. Media Player & App Shortcuts (Unmodified Keys)
            switch keyCode {
            case 49: // Space
                Task { @MainActor in engine.togglePlayPause() }
                return nil

            case 123: // Left Arrow
                let interval = Double(SettingsManager.shared.defaultSkipInterval)
                let delta = isShift ? -30.0 : -interval
                Task { @MainActor in engine.skip(seconds: delta) }
                return nil

            case 124: // Right Arrow
                let interval = Double(SettingsManager.shared.defaultSkipInterval)
                let delta = isShift ? 30.0 : interval
                Task { @MainActor in engine.skip(seconds: delta) }
                return nil

            case 126: // Up Arrow
                Task { @MainActor in engine.setVolumeDelta(0.05) }
                return nil

            case 125: // Down Arrow
                Task { @MainActor in engine.setVolumeDelta(-0.05) }
                return nil

            case 46: // M key (Mute)
                Task { @MainActor in engine.toggleMute() }
                return nil

            case 3: // F key (Standard video player toggle for Native Fullscreen)
                Task { @MainActor in
                    WindowManager.shared.toggleNativeFullscreen()
                }
                return nil

            case 35: // P key (Picture-in-Picture)
                Task { @MainActor in
                    PictureInPictureManager.shared.toggle(engine: engine)
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

            case 36: // Return key (Back to Dashboard on completion)
                if engine.hasEnded {
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                    }
                    return nil
                }
                return event

            case 15: // R key (Replay on completion)
                if engine.hasEnded {
                    Task { @MainActor in
                        engine.replay()
                    }
                    return nil
                }
                return event

            case 51: // Backspace / Delete (Return to Dashboard)
                if engine.currentURL != nil {
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                    }
                    return nil
                }
                return event

            case 53: // Escape key
                Task { @MainActor in
                    if engine.activeInspectorSheet != nil {
                        engine.activeInspectorSheet = nil
                    } else if engine.playbackError != nil {
                        if WindowManager.shared.isAnyFullscreen {
                            WindowManager.shared.exitAnyFullscreen()
                        }
                        NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                    } else if engine.hasEnded {
                        if WindowManager.shared.isAnyFullscreen {
                            WindowManager.shared.exitAnyFullscreen()
                        }
                        NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                    } else if WindowManager.shared.isAnyFullscreen {
                        WindowManager.shared.exitAnyFullscreen()
                    } else if engine.currentURL != nil {
                        NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                    }
                }
                return nil

            default:
                return event
            }
        }
    }
}
