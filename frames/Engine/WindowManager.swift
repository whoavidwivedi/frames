import AppKit
import SwiftUI

@MainActor
@Observable
public final class WindowManager {
    public static let shared = WindowManager()

    public var isNativeFullscreen: Bool = false
    public var isWindowedFullscreen: Bool = false

    public var isAnyFullscreen: Bool {
        isNativeFullscreen || isWindowedFullscreen
    }

    private var savedWindowFrame: NSRect?

    public init() {
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isNativeFullscreen = true
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isNativeFullscreen = false
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

    public func toggleWindowedFullscreen() {
        guard let window = activeWindow else { return }

        // If currently in native fullscreen, exit it first
        if isNativeFullscreen {
            window.toggleFullScreen(nil)
        }

        if isWindowedFullscreen {
            exitWindowedFullscreen(window: window, animated: true)
        } else {
            enterWindowedFullscreen(window: window)
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

    private func enterWindowedFullscreen(window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        savedWindowFrame = window.frame
        isWindowedFullscreen = true

        // Smoothly expand to fill entire display on the current Space
        window.setFrame(screen.frame, display: true, animate: true)
    }

    private func exitWindowedFullscreen(window: NSWindow, animated: Bool) {
        isWindowedFullscreen = false
        if let saved = savedWindowFrame {
            window.setFrame(saved, display: true, animate: animated)
            savedWindowFrame = nil
        }
    }

    private var activeWindow: NSWindow? {
        return NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.canBecomeKey }
    }
}
