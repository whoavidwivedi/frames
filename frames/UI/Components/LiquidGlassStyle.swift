import SwiftUI
import AppKit

// MARK: - Dual-Mode Liquid Glass (macOS Material + Shadcn b3lnoM3QO Tokens)
public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = ShadcnTheme.radiusLg
    public var padding: CGFloat = 12

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ShadcnTheme.card.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
            )
            .shadow(
                color: Color(nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(white: 0, alpha: 0.35)
                        : NSColor(white: 0, alpha: 0.08)
                }),
                radius: 14,
                y: 6
            )
    }
}

public struct LiquidGlassPillModifier: ViewModifier {
    public var isSelected: Bool = false

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isSelected ? ShadcnTheme.accentActive : ShadcnTheme.card.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isSelected ? ShadcnTheme.borderActive : ShadcnTheme.border, lineWidth: 1)
            )
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = ShadcnTheme.radiusLg, padding: CGFloat = 12) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func liquidGlassPill(isSelected: Bool = false) -> some View {
        modifier(LiquidGlassPillModifier(isSelected: isSelected))
    }
}

public struct GlassIconButton: View {
    public let systemName: String
    public var size: CGFloat = 12
    public var isHighlighted: Bool = false
    public var action: () -> Void

    public init(systemName: String, size: CGFloat = 12, isHighlighted: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName
        self.size = size
        self.isHighlighted = isHighlighted
        self.action = action
    }

    public var body: some View {
        ShadcnButton(
            icon: systemName,
            variant: isHighlighted ? .secondary : .ghost,
            size: .iconSm,
            isSelected: isHighlighted,
            action: action
        )
    }
}
