import SwiftUI

public enum ShadcnTheme {
    // Backgrounds
    public static let background = Color(red: 0.035, green: 0.035, blue: 0.039) // #09090b
    public static let card = Color(red: 0.071, green: 0.071, blue: 0.078)       // #121214
    public static let cardHover = Color(red: 0.094, green: 0.094, blue: 0.106)  // #18181b
    public static let popover = Color(red: 0.071, green: 0.071, blue: 0.078)   // #121214
    
    // Foreground / Text
    public static let foreground = Color(red: 0.98, green: 0.98, blue: 0.98)    // #fafafa
    public static let foregroundSecondary = Color(red: 0.63, green: 0.63, blue: 0.67) // #a1a1aa (zinc-400)
    public static let foregroundMuted = Color(red: 0.44, green: 0.44, blue: 0.48)     // #71717a (zinc-500)
    
    // Borders
    public static let border = Color.white.opacity(0.10)                        // #27272a
    public static let borderSubtle = Color.white.opacity(0.05)
    public static let borderActive = Color.white.opacity(0.20)
    
    // Primary / Accent (Monochrome)
    public static let primary = Color(red: 0.98, green: 0.98, blue: 0.98)       // #ffffff
    public static let primaryForeground = Color(red: 0.05, green: 0.05, blue: 0.06) // #09090b
    public static let secondary = Color(red: 0.15, green: 0.15, blue: 0.17)     // #27272a
    public static let accent = Color.white.opacity(0.06)                        // Subtle hover
    public static let accentActive = Color.white.opacity(0.12)
    
    // Radii (mira / neutral: tight, rectangular with subtle corners)
    public static let radiusSm: CGFloat = 4
    public static let radiusMd: CGFloat = 6
    public static let radiusLg: CGFloat = 8
    public static let radiusXl: CGFloat = 10
}

// MARK: - Reusable Card Modifier
public struct ShadcnCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = ShadcnTheme.radiusLg
    public var padding: CGFloat = 12

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ShadcnTheme.card.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 8)
            )
    }
}

public extension View {
    func shadcnCard(cornerRadius: CGFloat = ShadcnTheme.radiusLg, padding: CGFloat = 12) -> some View {
        modifier(ShadcnCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}
