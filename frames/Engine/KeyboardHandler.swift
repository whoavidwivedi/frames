import AppKit
import SwiftUI

@MainActor
public final class KeyboardHandler {
    public enum KeyAction: Equatable, Sendable {
        case playPause
        case toggleMute
        case stepForward
        case stepBackward
        case showTime
        case faster
        case slower
        case toggleFullscreen
        case togglePictureInPicture
        case toggleSubtitles
        case toggleMetrics
        case skip(Double)
        case volumeDelta(Float)
        case returnToDashboard
        case replay
        case escape
    }

    public static func resolveAction(
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        isShift: Bool = false,
        isCommand: Bool = false,
        isControl: Bool = false,
        isOption: Bool = false
    ) -> KeyAction? {
        if isCommand || isControl || isOption {
            return nil
        }

        switch keyCode {
        case 123: // Left Arrow
            let interval = Double(SettingsManager.shared.defaultSkipInterval)
            return .skip(isShift ? -30.0 : -interval)
        case 124: // Right Arrow
            let interval = Double(SettingsManager.shared.defaultSkipInterval)
            return .skip(isShift ? 30.0 : interval)
        case 126: // Up Arrow
            return .volumeDelta(0.05)
        case 125: // Down Arrow
            return .volumeDelta(-0.05)
        case 36: // Return key
            return .returnToDashboard
        case 51: // Backspace / Delete
            return .returnToDashboard
        case 53: // Escape key
            return .escape
        default:
            break
        }

        guard let chars = charactersIgnoringModifiers?.lowercased() else {
            if keyCode == 49 {
                return .playPause
            }
            return nil
        }

        switch chars {
        case " ":
            return .playPause
        case "m":
            return .toggleMute
        case "f":
            return .toggleFullscreen
        case "p":
            return .togglePictureInPicture
        case "s":
            return .toggleSubtitles
        case "i":
            return .toggleMetrics
        case ".":
            return .stepForward
        case ",":
            return .stepBackward
        case "]":
            return .faster
        case "[":
            return .slower
        case "r":
            return .replay
        case "e":
            return .stepForward
        case "t":
            return .showTime
        default:
            if keyCode == 49 {
                return .playPause
            }
            return nil
        }
    }

    public static func resolveKeyAction(event: NSEvent) -> KeyAction? {
        return resolveAction(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            isShift: event.modifierFlags.contains(.shift),
            isCommand: event.modifierFlags.contains(.command),
            isControl: event.modifierFlags.contains(.control),
            isOption: event.modifierFlags.contains(.option)
        )
    }

    private var localMonitor: Any?
    public let engine: VideoPlayerEngine

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
        setupMonitor(engine: engine)
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @discardableResult
    public func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        return Self.handleKeyEvent(event, engine: engine)
    }

    private func setupMonitor(engine: VideoPlayerEngine) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKeyEvent(event)
        }
    }

    @discardableResult
    public static func handleKeyEvent(_ event: NSEvent, engine: VideoPlayerEngine) -> NSEvent? {
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

            // MARK: - 2. Media Player & App Shortcuts (Unmodified Keys / International Layout Compatible)
            guard let action = resolveAction(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                keyCode: keyCode,
                isShift: isShift,
                isCommand: isCommand,
                isControl: isControl,
                isOption: isOption
            ) else {
                return event
            }

            switch action {
            case .playPause:
                Task { @MainActor in engine.togglePlayPause() }
                return nil

            case .skip(let delta):
                Task { @MainActor in engine.skip(seconds: delta) }
                return nil

            case .volumeDelta(let delta):
                Task { @MainActor in engine.setVolumeDelta(delta) }
                return nil

            case .toggleMute:
                Task { @MainActor in engine.toggleMute() }
                return nil

            case .toggleFullscreen:
                Task { @MainActor in
                    WindowManager.shared.toggleNativeFullscreen()
                }
                return nil

            case .togglePictureInPicture:
                Task { @MainActor in
                    PictureInPictureManager.shared.toggle(engine: engine)
                }
                return nil

            case .toggleSubtitles:
                Task { @MainActor in
                    if engine.activeInspectorSheet == .subtitles {
                        engine.activeInspectorSheet = nil
                    } else {
                        engine.activeInspectorSheet = .subtitles
                    }
                }
                return nil

            case .toggleMetrics:
                Task { @MainActor in
                    if engine.activeInspectorSheet == .stats {
                        engine.activeInspectorSheet = nil
                    } else {
                        engine.activeInspectorSheet = .stats
                    }
                }
                return nil

            case .showTime:
                Task { @MainActor in engine.timeHUDToken &+= 1 }
                return nil

            case .stepForward:
                Task { @MainActor in engine.stepFrame(forward: true) }
                return nil

            case .stepBackward:
                Task { @MainActor in engine.stepFrame(forward: false) }
                return nil

            case .faster:
                Task { @MainActor in
                    engine.playbackRate = min(3.0, ((engine.playbackRate + 0.1) * 10).rounded() / 10)
                }
                return nil

            case .slower:
                Task { @MainActor in
                    engine.playbackRate = max(0.25, ((engine.playbackRate - 0.1) * 10).rounded() / 10)
                }
                return nil

            case .returnToDashboard:
                if keyCode == 36 && !engine.hasEnded {
                    return event
                }
                if keyCode == 51 && engine.currentURL == nil {
                    return event
                }
                Task { @MainActor in
                    NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                }
                return nil

            case .replay:
                if engine.hasEnded {
                    Task { @MainActor in
                        engine.replay()
                    }
                    return nil
                }
                return event

            case .escape:
                Task { @MainActor in
                    if SettingsManager.shared.isSettingsPresented {
                        SettingsManager.shared.closeSettings()
                        return
                    }
                    // Escape always leaves the player for the dashboard.
                    if engine.currentURL != nil {
                        if WindowManager.shared.isAnyFullscreen {
                            WindowManager.shared.exitAnyFullscreen()
                        }
                        NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                    } else if WindowManager.shared.isAnyFullscreen {
                        WindowManager.shared.exitAnyFullscreen()
                    }
                }
                return nil
            }
        }
    }
