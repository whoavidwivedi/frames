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

public struct ShadcnButton: View {
    public let title: String?
    public let icon: String?
    public var shortcut: String? = nil
    public var variant: ShadcnButtonVariant = .default
    public var size: ShadcnButtonSize = .default
    public var isSelected: Bool = false
    public let action: () -> Void

    @State private var isHovering = false

    public init(
        _ title: String? = nil,
        icon: String? = nil,
        shortcut: String? = nil,
        variant: ShadcnButtonVariant = .default,
        size: ShadcnButtonSize = .default,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.variant = variant
        self.size = size
        self.isSelected = isSelected
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
                                .fill(Color.white.opacity(0.08))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private var isIconOnly: Bool {
        return title == nil && icon != nil
    }

    private var height: CGFloat {
        switch size {
        case .sm, .iconSm: return 24
        case .default, .icon: return 28
        }
    }

    private var horizontalPadding: CGFloat {
        if isIconOnly { return 0 }
        switch size {
        case .sm: return 8
        case .default: return 10
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
        case .sm, .iconSm: return 11
        case .default, .icon: return 12
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .sm, .iconSm: return ShadcnTheme.radiusSm
        case .default, .icon: return ShadcnTheme.radiusMd
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .default, .primary:
            return ShadcnTheme.primaryForeground
        case .secondary, .outline:
            return isHovering || isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary
        case .ghost:
            return isHovering || isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .default, .primary:
            return isHovering ? Color.white.opacity(0.9) : ShadcnTheme.primary
        case .secondary:
            return isHovering ? ShadcnTheme.cardHover : ShadcnTheme.card
        case .outline:
            if isSelected {
                return Color.white.opacity(0.12)
            }
            return isHovering ? Color.white.opacity(0.06) : Color.clear
        case .ghost:
            if isSelected {
                return Color.white.opacity(0.12)
            }
            return isHovering ? Color.white.opacity(0.07) : Color.clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .default, .primary:
            return Color.clear
        case .secondary, .outline:
            if isSelected {
                return ShadcnTheme.borderActive
            }
            return isHovering ? ShadcnTheme.borderActive : ShadcnTheme.border
        case .ghost:
            return isSelected ? ShadcnTheme.border : Color.clear
        }
    }
}
