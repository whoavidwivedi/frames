import SwiftUI
import AppKit

// MARK: - Pointing Hand Mouse Cursor Modifier

/// A high-reliability pointer style modifier that ensures clickable elements display
/// an immediate, unmissable pointing hand cursor across their entire rectangular interactive bounds.
///
/// On macOS 15.0+, this combines native WindowServer `.pointerStyle(.link)` with an AppKit
/// NSCursor tracking area overlay (via `NSViewRepresentable`), ensuring that whenever the mouse hovers
/// anywhere within the clickable frame or its interactive padding, `NSCursor.pointingHand` is active
/// with zero delay or dropouts across all macOS versions.
public struct PointerCursorModifier: ViewModifier {
    @State private var isHovering = false

    public init() {}

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .contentShape(Rectangle())
                .pointerStyle(.link)
                .overlay(PointingHandCursorOverlay().allowsHitTesting(false))
        } else {
            content
                .contentShape(Rectangle())
                .overlay(PointingHandCursorOverlay().allowsHitTesting(false))
                .onHover { hovering in
                    if hovering {
                        if !isHovering {
                            isHovering = true
                            NSCursor.pointingHand.push()
                        }
                    } else {
                        if isHovering {
                            isHovering = false
                            NSCursor.pop()
                        }
                    }
                }
                .onDisappear {
                    if isHovering {
                        isHovering = false
                        NSCursor.pop()
                    }
                }
        }
    }
}

// MARK: - AppKit NSCursor Tracking Area Overlay

private struct PointingHandCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> PointingHandTrackingNSView {
        PointingHandTrackingNSView()
    }

    func updateNSView(_ nsView: PointingHandTrackingNSView, context: Context) {
        nsView.refreshTrackingArea()
    }
}

final class PointingHandTrackingNSView: NSView {
    private var trackingAreaRef: NSTrackingArea?
    private var isCursorActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// Transparent pass-through so all clicks, drags, and mouse events pass directly to SwiftUI controls underneath
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }

    func refreshTrackingArea() {
        setupTrackingArea()
        window?.invalidateCursorRects(for: self)
    }

    private func setupTrackingArea() {
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
            trackingAreaRef = nil
        }
        guard bounds.width > 0 && bounds.height > 0 else { return }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .cursorUpdate,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if bounds.width > 0 && bounds.height > 0 {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        if !isCursorActive {
            NSCursor.pointingHand.push()
            isCursorActive = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if isCursorActive {
            NSCursor.pop()
            isCursorActive = false
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil && isCursorActive {
            NSCursor.pop()
            isCursorActive = false
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupTrackingArea()
            window?.invalidateCursorRects(for: self)
        }
    }
}

public extension View {
    /// Applies a rock-solid pointing hand mouse cursor across the full interactive frame when hovered.
    func pointingHand() -> some View {
        modifier(PointerCursorModifier())
    }
}
