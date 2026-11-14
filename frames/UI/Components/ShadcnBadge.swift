import SwiftUI

public enum ShadcnBadgeVariant {
    case `default`
    case secondary
    case destructive
    case outline
    case ghost
}

/// shadcn badge: compact inline label with a soft rounded rectangle, icon and spinner support.
public struct ShadcnBadge: View {
    public let title: String
    public var icon: String? = nil
    public var variant: ShadcnBadgeVariant = .default
    public var isLoading: Bool = false
    public var isHighlighted: Bool = false

    public init(
        _ title: String,
        icon: String? = nil,
        variant: ShadcnBadgeVariant = .default,
        isLoading: Bool = false,
        isHighlighted: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.isLoading = isLoading
        self.isHighlighted = isHighlighted
    }

    public var body: some View {
        HStack(spacing: 4) {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                    .frame(width: 9, height: 9)
                    .tint(foregroundColor)
            } else if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }

            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .animation(.fluidQuick, value: isHighlighted)
    }

    private var foregroundColor: Color {
        switch variant {
        case .default:
            return ShadcnTheme.primaryForeground
        case .secondary:
            return ShadcnTheme.foregroundSecondary
        case .destructive:
            return .white
        case .outline, .ghost:
            return ShadcnTheme.foregroundSecondary
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .default:
            return isHighlighted ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary
        case .secondary:
            return isHighlighted ? ShadcnTheme.cardHover : ShadcnTheme.secondary
        case .destructive:
            return isHighlighted ? ShadcnTheme.destructive.opacity(0.85) : ShadcnTheme.destructive
        case .outline:
            return isHighlighted ? ShadcnTheme.accentActive : Color.clear
        case .ghost:
            return isHighlighted ? ShadcnTheme.muted.opacity(0.5) : Color.clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .outline:
            return isHighlighted ? ShadcnTheme.borderActive : ShadcnTheme.border
        case .default, .secondary, .destructive, .ghost:
            return Color.clear
        }
    }
}
