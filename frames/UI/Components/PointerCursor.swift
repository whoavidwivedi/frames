import SwiftUI
import AppKit

public struct PointerCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isEnabled ? .link : nil)
        } else {
            content.overlay {
                if isEnabled {
                    CursorRegion().allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
    }
}

private struct CursorRegion: NSViewRepresentable {
    final class Region: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(visibleRect, cursor: .pointingHand)
        }
    }

    func makeNSView(context: Context) -> Region { Region() }
    func updateNSView(_ view: Region, context: Context) {}
}

public extension View {
    func pointingHand() -> some View { modifier(PointerCursorModifier()) }
}
