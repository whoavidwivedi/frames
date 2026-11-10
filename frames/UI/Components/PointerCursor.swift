import SwiftUI
import AppKit

// MARK: - Pointing Hand Mouse Cursor Modifier

public struct PointerCursorModifier: ViewModifier {
    @State private var isHovering = false

    public init() {}

    public func body(content: Content) -> some View {
        content
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

public extension View {
    /// Applies a pointing hand mouse cursor when hovered, indicating interactivity.
    func pointingHand() -> some View {
        modifier(PointerCursorModifier())
    }
}
