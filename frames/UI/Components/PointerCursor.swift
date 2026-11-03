import SwiftUI
import AppKit

public struct PointerCursorModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .pointerStyle(.link)
        } else {
            content
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
    }
}

public extension View {
    /// Applies a pointing hand mouse cursor when hovered, indicating interactivity.
    func pointingHand() -> some View {
        modifier(PointerCursorModifier())
    }
}
