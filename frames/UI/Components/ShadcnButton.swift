import SwiftUI

public enum ShadcnButtonVariant {
    case `default`
    case primary
    case secondary
    case outline
    case destructive
    case ghost
}

public enum ShadcnButtonSize {
    case sm
    case `default`
    case iconSm
    case icon
}

struct FramesPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.5)
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

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

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
            HStack(spacing: 6) {
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
            .background {
                if variant == .ghost {
                    backgroundColor
                } else {
                    LinearGradient(colors: [backgroundColor, lowerSurface],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(variant == .ghost ? 0 : (colorScheme == .dark ? 0.24 : 0.04)), radius: 1, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(FramesPressStyle())
        .contentShape(Rectangle())
        .pointingHand()
        .accessibilityLabel(effectiveAccessibilityLabel)
        .help(effectiveAccessibilityLabel)
        .onHover { isHovering = $0 }
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
        case .default, .icon: return 32
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
        case .default, .icon: return 14
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .sm, .iconSm: return 12
        case .default, .icon: return 16
        }
    }

    private var cornerRadius: CGFloat {
        return ShadcnTheme.radius4xl
    }

    private var foregroundColor: Color {
        switch variant {
        case .default, .primary:
            return ShadcnTheme.primaryForeground
        case .destructive:
            return ShadcnTheme.destructive
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
        case .destructive:
            return ShadcnTheme.destructive.opacity(isHovering ? 0.15 : 0.08)
        case .outline:
            if colorScheme == .dark { return Color(white: isHovering || isSelected ? 0.16 : 0.106) }
            return Color(white: isHovering || isSelected ? 0.96 : 1)
        case .ghost:
            if isSelected {
                return ShadcnTheme.accentActive
            }
            return isHovering ? ShadcnTheme.muted.opacity(0.5) : Color.black.opacity(0.0001)
        }
    }

    private var lowerSurface: Color {
        if variant == .outline {
            return Color(white: colorScheme == .dark ? (isHovering ? 0.14 : 0.09) : (isHovering ? 0.93 : 0.97))
        }
        return backgroundColor.opacity(0.92)
    }

    private var borderColor: Color {
        switch variant {
        case .default, .primary, .destructive, .ghost: return .clear
        case .secondary, .outline:
            return colorScheme == .dark ? Color(white: 0.16) : .black.opacity(0.09)
        }
    }
}
