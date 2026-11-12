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
    public var isPictureInPicture: Bool = false
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

    private var prePipWindowFrame: NSRect?
    private var lastDoubleClickTime: TimeInterval = 0

    public init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        setupNotifications()
    }

    public func configureWindow(_ window: NSWindow) {
        window.tabbingMode = .disallowed
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }

    /// File pickers and sheets are NSPanels. Their resize/key notifications must
    /// never drive the main window's layout, or the dashboard shrinks while Finder opens.
    private func contentWindow(from notification: Notification) -> NSWindow? {
        guard let window = notification.object as? NSWindow, !(window is NSPanel) else { return nil }
        return window
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                if let window = self?.contentWindow(from: notification) {
                    self?.configureWindow(window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                if let window = self?.contentWindow(from: notification) {
                    self?.configureWindow(window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = self?.contentWindow(from: notification) else { return }
                self?.configureWindow(window)
                withAnimation(.fluidQuick) {
                    self?.isTransitioning = true
                    self?.isNativeFullscreen = true
                    self?.updateLayoutState(window: window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = self?.contentWindow(from: notification) else { return }
                self?.configureWindow(window)
                withAnimation(.fluidQuick) {
                    self?.isTransitioning = false
                    self?.isNativeFullscreen = true
                    self?.updateLayoutState(window: window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = self?.contentWindow(from: notification) else { return }
                self?.configureWindow(window)
                withAnimation(.fluidQuick) {
                    self?.isTransitioning = true
                    self?.isNativeFullscreen = false
                    self?.updateLayoutState(window: window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = self?.contentWindow(from: notification) else { return }
                self?.configureWindow(window)
                withAnimation(.fluidQuick) {
                    self?.isTransitioning = false
                    self?.isNativeFullscreen = false
                    self?.updateLayoutState(window: window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willStartLiveResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = self?.contentWindow(from: notification) else { return }
                self?.configureWindow(window)
                self?.isLiveResizing = true
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            DispatchQueue.main.async {
                guard let self = self,
                      let window = self.contentWindow(from: notification) else { return }
                self.configureWindow(window)
                self.isLiveResizing = false
                withAnimation(.fluidQuick) {
                    self.updateLayoutState(window: window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            DispatchQueue.main.async {
                guard let self = self, !self.isLiveResizing,
                      let window = self.contentWindow(from: notification) else { return }
                self.configureWindow(window)
                self.updateLayoutState(window: window)
            }
        }
    }

    public func toggleNativeFullscreen() {
        guard let window = activeWindow else { return }
        configureWindow(window)
        // Native AppKit fullscreen; the Window Server handles the transition and
        // restores whatever window frame the user came from.
        window.toggleFullScreen(nil)
    }

    public func toggleWindowedFullscreen(window: NSWindow? = nil) {
        guard let win = window ?? activeWindow else { return }
        configureWindow(win)

        // If currently in native fullscreen, revert first
        if isNativeFullscreen {
            win.toggleFullScreen(nil)
            return
        }

        let beforeZoom = win.isZoomed
        win.performZoom(nil)
        if win.isZoomed != beforeZoom {
            isWindowedFullscreen = win.isZoomed
        } else {
            isWindowedFullscreen.toggle()
        }
        updateLayoutState(window: win)
    }

    public func exitAnyFullscreen() {
        guard let window = activeWindow else { return }
        configureWindow(window)

        if isWindowedFullscreen {
            if window.isZoomed {
                window.performZoom(nil)
            }
            updateLayoutState(window: window)
        } else if isNativeFullscreen {
            window.toggleFullScreen(nil)
        }
    }

    public func togglePictureInPicture(window: NSWindow? = nil) {
        if PictureInPictureManager.shared.isPictureInPicture {
            PictureInPictureManager.shared.exitPictureInPicture()
        }
        isPictureInPicture = PictureInPictureManager.shared.isPictureInPicture
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
        configureWindow(targetWindow)

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
        configureWindow(win)

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

        // Sequoia tiling edge-docking alignment (accounting for Sequoia tiling margins of 0-20pt)
        let edgeTolerance: CGFloat = 24.0
        let isNearLeft = abs(frame.minX - vf.minX) <= edgeTolerance
        let isNearRight = abs(frame.maxX - vf.maxX) <= edgeTolerance
        let isNearBottom = abs(frame.minY - vf.minY) <= edgeTolerance
        let isNearTop = abs(frame.maxY - vf.maxY) <= edgeTolerance

        // Quarter screen: corner tiling (~50% width and ~50% height docked to a screen corner)
        if isHalfWidth && isHalfHeight && (isNearLeft || isNearRight) && (isNearTop || isNearBottom) {
            return .quarterScreen
        }

        // Split screen: vertical half (left/right) or horizontal half (top/bottom) docked to screen edges
        let isVerticalSplit = isHalfWidth && isFullHeight && (isNearLeft || isNearRight)
        let isHorizontalSplit = isFullWidth && isHalfHeight && (isNearTop || isNearBottom)
        if isVerticalSplit || isHorizontalSplit {
            return .splitScreen
        }

        if frame.width < 540 || frame.height < 400 {
            return .compact
        }

        return .standard
    }

    public func updateLayoutState(window: NSWindow? = nil) {
        guard let win = window ?? activeWindow else { return }
        configureWindow(win)
        currentWindowSize = win.frame.size
        if !isNativeFullscreen && !isPictureInPicture {
            // Native Window > Zoom and Option-click green button bypass our menu,
            // so mirror AppKit's actual zoom state instead of tracking it ourselves.
            isWindowedFullscreen = win.isZoomed
        }
        let newState = computeLayoutState(window: win)
        // Window resizing and tiling are driven by the Window Server. Animating the
        // responsive layout after the frame has already changed causes the whole
        // dashboard to lag behind the pointer, so apply state changes immediately.
        if newState != currentLayoutState {
            currentLayoutState = newState
        }
    }

    private var activeWindow: NSWindow? {
        let app = NSApplication.shared
        let win = app.keyWindow ?? app.mainWindow ?? app.windows.first { $0.canBecomeKey }
        if let win = win {
            configureWindow(win)
        }
        return win
    }
}
