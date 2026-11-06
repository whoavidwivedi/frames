import SwiftUI
import AppKit

/// An invisible AppKit view representable that provides native macOS window title bar interactions:
/// - Click & drag anywhere moves the window with native macOS Window Server momentum and snapping
/// - Double tap / double click triggers the macOS default title bar window management action (Zoom or Minimize)
public struct TitleBarDragArea: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> TitleBarDragNSView {
        TitleBarDragNSView()
    }

    public func updateNSView(_ nsView: TitleBarDragNSView, context: Context) {}
}

public final class TitleBarDragNSView: NSView {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
    }


    public override func mouseDown(with event: NSEvent) {
        // Double-click / double-tap the top bar: match the macOS title bar action
        // (Zoom to fill, then restore the previous frame; or Minimize per System Settings).
        if event.clickCount == 2 {
            WindowManager.shared.performTitleBarDoubleClickAction(window: window)
            return
        }
        // Single click starts the native window drag.
        guard event.clickCount == 1 else { return }
        window?.performDrag(with: event)
    }
}

public struct TitleBarAreaModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .background(TitleBarDragArea())
    }
}

public extension View {
    /// Applies native macOS window management behavior to any title bar or top header area:
    /// - Double-tapping with trackpad or mouse triggers the macOS default title bar action (Zoom/Fill or Minimize)
    /// - Clicking and dragging allows moving the window across the screen
    func macOSDefaultTitleBar() -> some View {
        modifier(TitleBarAreaModifier())
    }
}
