import SwiftUI

public enum ShadcnButtonVariant {
    case `default`
    case primary
    case secondary
    case outline
    case ghost
}

public enum ShadcnButtonSize {
    case sm
    case `default`
    case iconSm
    case icon
}

private struct ShadcnPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .fluidQuick, value: configuration.isPressed)
    }
}

public struct ShadcnButton: View {
    public let title: String?
    public let icon: String?
    public var shortcut: String? = nil
    public var variant: ShadcnButtonVariant = .default
    public var size: ShadcnButtonSize = .default
    public var isSelected: Bool = false
    public var accessibilityLabel: String?
    public let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ title: String? = nil,
        icon: String? = nil,
        shortcut: String? = nil,
        variant: ShadcnButtonVariant = .default,
        size: ShadcnButtonSize = .default,
        isSelected: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.variant = variant
        self.size = size
        self.isSelected = isSelected
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundStyle(foregroundColor)
                }

                if let title = title {
                    Text(title)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .lineLimit(1)
                }

                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(ShadcnTheme.accentActive)
                        )
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(width: isIconOnly ? height : nil, height: height)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(ShadcnPressStyle(reduceMotion: reduceMotion))
        .pointingHand()
        .accessibilityLabel(effectiveAccessibilityLabel)
        .help(effectiveAccessibilityLabel)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .fluidQuick, value: isHovering)
        .animation(reduceMotion ? nil : .fluidQuick, value: isSelected)
    }

    private var isIconOnly: Bool {
        return title == nil && icon != nil
    }

    private var effectiveAccessibilityLabel: String {
        accessibilityLabel ?? title ?? icon?.replacingOccurrences(of: ".", with: " ") ?? "Button"
    }

    private var height: CGFloat {
        switch size {
        case .sm, .iconSm: return 30
        case .default, .icon: return 34
        }
    }

    private var horizontalPadding: CGFloat {
        if isIconOnly { return 0 }
        switch size {
        case .sm: return 10
        case .default: return 14
        case .iconSm, .icon: return 0
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .sm, .iconSm: return 11
        case .default, .icon: return 12
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .sm, .iconSm: return 12
        case .default, .icon: return 14
        }
    }

    private var cornerRadius: CGFloat {
        return ShadcnTheme.radius4xl
    }

    private var foregroundColor: Color {
        switch variant {
        case .default, .primary:
            return ShadcnTheme.primaryForeground
        case .secondary:
            return isHovering || isSelected ? ShadcnTheme.foreground : ShadcnTheme.secondaryForeground
        case .outline, .ghost:
            return isHovering || isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .default, .primary:
            return isHovering ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary
        case .secondary:
            return isHovering ? ShadcnTheme.cardHover : ShadcnTheme.secondary
        case .outline:
            if isSelected {
                return ShadcnTheme.accentActive
            }
            return isHovering ? ShadcnTheme.muted.opacity(0.6) : Color.clear
        case .ghost:
            if isSelected {
                return ShadcnTheme.accentActive
            }
            return isHovering ? ShadcnTheme.muted.opacity(0.5) : Color.clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .default, .primary:
            return Color.clear
        case .secondary:
            return isHovering || isSelected ? ShadcnTheme.borderActive : ShadcnTheme.border
        case .outline:
            if isSelected {
                return ShadcnTheme.borderActive
            }
            return isHovering ? ShadcnTheme.borderActive : ShadcnTheme.border
        case .ghost:
            return isSelected ? ShadcnTheme.border : Color.clear
        }
    }
}
