import AppKit
import SwiftUI

public enum WindowLayoutState: String, CaseIterable, Sendable {
    case standard = "Standard"
    case splitScreen = "Split Screen"
    case quarterScreen = "Quarter Screen"
    case windowedFull = "Windowed Full"
    case fullScreen = "Full Screen"
    case compact = "Compact"
}

@MainActor
@Observable
public final class WindowManager {
    public static let shared = WindowManager()

    public var isNativeFullscreen: Bool = false
    public var isWindowedFullscreen: Bool = false
    public var currentLayoutState: WindowLayoutState = .standard
    public var isLiveResizing: Bool = false
    public var isTransitioning: Bool = false
    public var currentWindowSize: CGSize = .zero

    public var isSplitScreen: Bool {
        currentLayoutState == .splitScreen
    }

    public var isQuarterScreen: Bool {
        currentLayoutState == .quarterScreen
    }

    public var isCompact: Bool {
        currentLayoutState == .compact || currentLayoutState == .quarterScreen
    }

    public var isAnyFullscreen: Bool {
        isNativeFullscreen || isWindowedFullscreen
    }

    private var savedWindowFrame: NSRect?
    private var lastDoubleClickTime: TimeInterval = 0

    public init() {
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                withAnimation(.fluidWindow) {
                    self?.isTransitioning = true
                    self?.isNativeFullscreen = true
                    self?.updateLayoutState()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                withAnimation(.fluidWindow) {
                    self?.isTransitioning = false
                    self?.isNativeFullscreen = true
                    self?.updateLayoutState()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                withAnimation(.fluidWindow) {
                    self?.isTransitioning = true
                    self?.isNativeFullscreen = false
                    self?.updateLayoutState()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                withAnimation(.fluidWindow) {
                    self?.isTransitioning = false
                    self?.isNativeFullscreen = false
                    self?.updateLayoutState()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willStartLiveResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLiveResizing = true
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLiveResizing = false
                withAnimation(.fluidWindow) {
                    self?.updateLayoutState()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, !self.isLiveResizing else { return }
                self.updateLayoutState()
            }
        }
    }

    public func toggleNativeFullscreen() {
        guard let window = activeWindow else { return }

        // If currently in windowed fullscreen, revert first
        if isWindowedFullscreen {
            exitWindowedFullscreen(window: window, animated: false)
        }

        window.toggleFullScreen(nil)
    }

    public func toggleWindowedFullscreen(window: NSWindow? = nil) {
        guard let win = window ?? activeWindow else { return }

        // If currently in native fullscreen, exit it first
        if isNativeFullscreen {
            win.toggleFullScreen(nil)
            return
        }

        if isWindowedFullscreen {
            exitWindowedFullscreen(window: win, animated: true)
        } else {
            enterWindowedFullscreen(window: win)
        }
    }

    public func exitAnyFullscreen() {
        guard let window = activeWindow else { return }

        if isWindowedFullscreen {
            exitWindowedFullscreen(window: window, animated: true)
        } else if isNativeFullscreen {
            window.toggleFullScreen(nil)
        }
    }

    /// Executes the standard macOS title bar double-click window management behavior:
    /// Respects the user's System Settings (Desktop & Dock > Double-click a window's title bar to):
    /// - "Maximize" / "Zoom": Toggles window Zoom/Fill (smoothly fits to visible desktop area)
    /// - "Minimize": Miniaturizes the window to the Dock
    /// - "None": Does nothing
    public func performTitleBarDoubleClickAction(window: NSWindow? = nil, bypassDebounce: Bool = false) {
        let now = CACurrentMediaTime()
        if !bypassDebounce {
            guard now - lastDoubleClickTime > 0.35 else { return }
            lastDoubleClickTime = now
        }

        guard let targetWindow = window ?? activeWindow else { return }

        // If in native full screen Space, toggle back to standard windowed mode
        if isNativeFullscreen {
            targetWindow.toggleFullScreen(nil)
            return
        }

        // Check macOS System Settings for Title Bar Double-Click Action
        let defaults = UserDefaults.standard
        if let action = defaults.string(forKey: "AppleActionOnDoubleClick") {
            switch action.lowercased() {
            case "minimize":
                targetWindow.miniaturize(nil)
                return
            case "none":
                return
            default:
                break
            }
        } else if defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick") {
            targetWindow.miniaturize(nil)
            return
        }

        // macOS Default Behavior: Zoom / Fill the window
        toggleWindowedFullscreen(window: targetWindow)
    }

    public func computeLayoutState(window: NSWindow? = nil) -> WindowLayoutState {
        guard let win = window ?? activeWindow else { return .standard }

        if isNativeFullscreen || win.styleMask.contains(.fullScreen) {
            return .fullScreen
        }

        if isWindowedFullscreen {
            return .windowedFull
        }

        guard let screen = win.screen ?? NSScreen.main else {
            return (win.frame.width < 540 || win.frame.height < 400) ? .compact : .standard
        }

        let frame = win.frame
        let vf = screen.visibleFrame

        guard vf.width > 0, vf.height > 0 else {
            return (win.frame.width < 540 || win.frame.height < 400) ? .compact : .standard
        }

        let widthRatio = frame.width / vf.width
        let heightRatio = frame.height / vf.height

        // Windowed full / zoomed (occupies >= 94% of visible screen in both dimensions)
        if widthRatio >= 0.94 && heightRatio >= 0.94 {
            return .windowedFull
        }

        // Tolerance for half-width and half-height (accounting for Sequoia tiling margins of 8-12pt)
        let isHalfWidth = abs(widthRatio - 0.5) <= 0.10
        let isFullHeight = heightRatio >= 0.85
        let isHalfHeight = abs(heightRatio - 0.5) <= 0.10
        let isFullWidth = widthRatio >= 0.90

        // Quarter screen: corner tiling (~50% width and ~50% height)
        if isHalfWidth && isHalfHeight {
            return .quarterScreen
        }

        // Split screen: vertical half (left/right) or horizontal half (top/bottom)
        if (isHalfWidth && isFullHeight) || (isFullWidth && isHalfHeight) {
            return .splitScreen
        }

        if frame.width < 540 || frame.height < 400 {
            return .compact
        }

        return .standard
    }

    public func updateLayoutState(window: NSWindow? = nil) {
        guard let win = window ?? activeWindow else { return }
        currentWindowSize = win.frame.size
        let newState = computeLayoutState(window: win)
        if newState != currentLayoutState {
            if isLiveResizing {
                currentLayoutState = newState
            } else {
                withAnimation(.fluidWindow) {
                    currentLayoutState = newState
                }
            }
        }
    }

    private func enterWindowedFullscreen(window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        savedWindowFrame = window.frame
        withAnimation(.fluidWindow) {
            isWindowedFullscreen = true
            currentLayoutState = .windowedFull
        }

        // Smoothly expand to fill entire visible display area (macOS native Zoom standard)
        window.setFrame(screen.visibleFrame, display: true, animate: true)
    }

    private func exitWindowedFullscreen(window: NSWindow, animated: Bool) {
        withAnimation(.fluidWindow) {
            isWindowedFullscreen = false
        }
        if let saved = savedWindowFrame {
            window.setFrame(saved, display: true, animate: animated)
            savedWindowFrame = nil
        } else if window.isZoomed {
            window.performZoom(nil)
        }
        withAnimation(.fluidWindow) {
            updateLayoutState(window: window)
        }
    }

    private var activeWindow: NSWindow? {
        let app = NSApplication.shared
        return app.keyWindow ?? app.mainWindow ?? app.windows.first { $0.canBecomeKey }
    }
}
