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

    public override func updateConstraints() {
        super.updateConstraints()
    }

    public override func mouseDown(with event: NSEvent) {
        // AppKit's -[NSWindow performDragWithEvent:] internally checks event.clickCount.
        // If event.clickCount >= 2, AppKit triggers the titlebar double-click action (Zoom / Windowed Full / Miniaturize).
        // By guarding for clickCount == 1, we ensure that:
        // 1. Single click & drag still smoothly moves the window.
        // 2. Double clicks, double taps, and rapid clicks are ignored by performDrag,
        //    preventing the window from toggling to its original state or full windowed.
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
