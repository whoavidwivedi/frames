import SwiftUI
import AppKit

// MARK: - Pointing Hand Mouse Cursor Modifier

/// A high-reliability pointer style modifier that ensures clickable elements display
/// an immediate, unmissable pointing hand cursor across their entire rectangular interactive bounds.
///
/// On macOS 15.0+, this uses the native WindowServer `.pointerStyle(.link)` API, completely
/// bypassing fragile AppKit cursor stack (`NSCursor.push()` / `NSCursor.pop()`) desynchronizations.
/// On earlier macOS versions, it falls back to a guarded `NSCursor.pointingHand` hover tracking
/// coupled with `.contentShape(Rectangle())` so transparent padding and spacing are never dead zones.
public struct PointerCursorModifier: ViewModifier {
    @State private var isHovering = false

    public init() {}

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .contentShape(Rectangle())
                .pointerStyle(.link)
        } else {
            content
                .contentShape(Rectangle())
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

public extension View {
    /// Applies a rock-solid pointing hand mouse cursor across the full interactive frame when hovered.
    func pointingHand() -> some View {
        modifier(PointerCursorModifier())
    }
}
