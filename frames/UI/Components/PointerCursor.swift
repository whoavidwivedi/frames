import SwiftUI
import AppKit

public struct PointerCursorModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        // macOS HIG Compliance: Standard interactive controls maintain the standard arrow cursor.
        // Hyperlink hand cursor on UI controls is a web convention that violates macOS HIG.
        content
    }
}

public extension View {
    /// Applies a pointing hand mouse cursor when hovered, indicating interactivity.
    func pointingHand() -> some View {
        modifier(PointerCursorModifier())
    }
}
