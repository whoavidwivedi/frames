import SwiftUI
import AppKit

// MARK: - Dual-Mode Liquid Glass (macOS Material + Shadcn b1VlK05Q Tokens)
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

    /// Glass shell shared by the player's audio, subtitle and speed panels.
    func playerPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
        return self
            .background(shape.fill(.ultraThinMaterial))
            .background(shape.fill(ShadcnTheme.card.opacity(0.72)))
            .overlay(shape.strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
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

// MARK: - Apple-Grade Liquid Glass Button System

public enum AppleLiquidGlassShape: Equatable {
    case circle
    case capsule
    case roundedRectangle(cornerRadius: CGFloat)
}

public enum AppleLiquidGlassTint: Equatable {
    case standard
    case accent
    case danger
    case cyan
    case custom(Color)
}

public struct AppleLiquidGlassNativeButtonStyle: ButtonStyle {
    public var shape: AppleLiquidGlassShape = .circle
    public var tint: AppleLiquidGlassTint = .standard
    public var isHovered: Bool = false

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(iconColor)
            .shadow(color: Color.black.opacity(0.40), radius: 1, x: 0, y: 1)
            .background(glassBackground(isPressed: configuration.isPressed))
            .clipShape(resolvedClipShape)
            .overlay(rimBorder)
            .overlay(alignment: .top) {
                specularTopGlint
            }
            .shadow(
                color: Color.black.opacity(isHovered ? 0.38 : 0.22),
                radius: isHovered ? 7 : 4,
                x: 0,
                y: isHovered ? 3 : 2
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.fluidQuick, value: isHovered)
            .animation(.fluidQuick, value: configuration.isPressed)
    }

    @ViewBuilder
    private func glassBackground(isPressed: Bool) -> some View {
        ZStack {
            // Optical backdrop material blur through underlying media
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            // Specular directional gradient
            fillGradient(isPressed: isPressed)

            // Dynamic hover/press specular flare
            if isHovered || isPressed {
                RadialGradient(
                    colors: [Color.white.opacity(isPressed ? 0.28 : 0.18), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 28
                )
            }
        }
    }

    private var iconColor: Color {
        switch tint {
        case .standard:
            return Color.white
        case .danger:
            return Color(red: 1.0, green: 0.40, blue: 0.40)
        case .accent:
            return Color.white
        case .cyan:
            return Color(red: 0.35, green: 0.88, blue: 1.0)
        case .custom(let color):
            return color
        }
    }

    private func fillGradient(isPressed: Bool) -> some View {
        let topOpacity: Double
        let bottomOpacity: Double

        switch tint {
        case .standard:
            topOpacity = isPressed ? 0.36 : (isHovered ? 0.30 : 0.18)
            bottomOpacity = isPressed ? 0.18 : (isHovered ? 0.14 : 0.07)
            return LinearGradient(
                colors: [Color.white.opacity(topOpacity), Color.white.opacity(bottomOpacity)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .danger:
            topOpacity = isPressed ? 0.52 : (isHovered ? 0.44 : 0.32)
            bottomOpacity = isPressed ? 0.26 : (isHovered ? 0.20 : 0.14)
            return LinearGradient(
                colors: [Color.red.opacity(topOpacity), Color.red.opacity(bottomOpacity)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .accent:
            topOpacity = isPressed ? 0.52 : (isHovered ? 0.44 : 0.32)
            bottomOpacity = isPressed ? 0.26 : (isHovered ? 0.20 : 0.14)
            return LinearGradient(
                colors: [Color.accentColor.opacity(topOpacity), Color.accentColor.opacity(bottomOpacity)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cyan:
            topOpacity = isPressed ? 0.46 : (isHovered ? 0.38 : 0.26)
            bottomOpacity = isPressed ? 0.22 : (isHovered ? 0.16 : 0.10)
            return LinearGradient(
                colors: [Color.cyan.opacity(topOpacity), Color.cyan.opacity(bottomOpacity)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .custom(let col):
            topOpacity = isPressed ? 0.46 : (isHovered ? 0.38 : 0.26)
            bottomOpacity = isPressed ? 0.22 : (isHovered ? 0.16 : 0.10)
            return LinearGradient(
                colors: [col.opacity(topOpacity), col.opacity(bottomOpacity)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var rimTopOpacity: Double {
        switch tint {
        case .standard: return isHovered ? 0.72 : 0.46
        case .danger: return isHovered ? 0.78 : 0.56
        case .accent: return isHovered ? 0.82 : 0.62
        case .cyan: return isHovered ? 0.82 : 0.62
        case .custom: return isHovered ? 0.75 : 0.52
        }
    }

    private var rimMidOpacity: Double {
        switch tint {
        case .standard: return isHovered ? 0.35 : 0.20
        case .danger: return isHovered ? 0.42 : 0.28
        case .accent: return isHovered ? 0.44 : 0.30
        case .cyan: return isHovered ? 0.42 : 0.28
        case .custom: return isHovered ? 0.38 : 0.24
        }
    }

    private var rimBottomOpacity: Double {
        switch tint {
        case .standard: return isHovered ? 0.16 : 0.08
        case .danger: return isHovered ? 0.22 : 0.12
        case .accent: return isHovered ? 0.22 : 0.12
        case .cyan: return isHovered ? 0.20 : 0.10
        case .custom: return isHovered ? 0.18 : 0.10
        }
    }

    @ViewBuilder
    private var rimBorder: some View {
        let borderGradient = LinearGradient(
            stops: [
                .init(color: Color.white.opacity(rimTopOpacity), location: 0.0),
                .init(color: Color.white.opacity(rimMidOpacity), location: 0.45),
                .init(color: Color.white.opacity(rimBottomOpacity), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        switch shape {
        case .circle:
            Circle().strokeBorder(borderGradient, lineWidth: 1)
        case .capsule:
            Capsule().strokeBorder(borderGradient, lineWidth: 1)
        case .roundedRectangle(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(borderGradient, lineWidth: 1)
        }
    }

    private var specularTopGlint: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isHovered ? 0.36 : 0.22),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: 11)
            .padding(.horizontal, 4)
            .padding(.top, 1)
            .blur(radius: 0.6)
            .allowsHitTesting(false)
    }

    private var resolvedClipShape: AnyShape {
        switch shape {
        case .circle:
            return AnyShape(Circle())
        case .capsule:
            return AnyShape(Capsule())
        case .roundedRectangle(let radius):
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

public struct AppleLiquidGlassButton<Content: View>: View {
    public var shape: AppleLiquidGlassShape
    public var tint: AppleLiquidGlassTint
    public var width: CGFloat?
    public var height: CGFloat
    public var helpText: String?
    public var action: () -> Void
    public var content: () -> Content

    @State private var isHovered: Bool = false

    public init(
        shape: AppleLiquidGlassShape = .circle,
        tint: AppleLiquidGlassTint = .standard,
        width: CGFloat? = 32,
        height: CGFloat = 32,
        helpText: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.shape = shape
        self.tint = tint
        self.width = width
        self.height = height
        self.helpText = helpText
        self.action = action
        self.content = content
    }

    public init(
        icon: String,
        iconSize: CGFloat = 13,
        iconWeight: Font.Weight = .semibold,
        shape: AppleLiquidGlassShape = .circle,
        tint: AppleLiquidGlassTint = .standard,
        size: CGFloat = 32,
        helpText: String? = nil,
        action: @escaping () -> Void
    ) where Content == AnyView {
        self.shape = shape
        self.tint = tint
        self.width = size
        self.height = size
        self.helpText = helpText
        self.action = action
        self.content = {
            AnyView(
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: iconWeight))
            )
        }
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if let w = width {
                    content()
                        .frame(width: w, height: height)
                } else {
                    content()
                        .frame(height: height)
                        .padding(.horizontal, 10)
                }
            }
        }
        .buttonStyle(AppleLiquidGlassNativeButtonStyle(
            shape: shape,
            tint: tint,
            isHovered: isHovered
        ))
        .onHover { hovering in
            withAnimation(.fluidQuick) {
                isHovered = hovering
            }
        }
        .pointingHand()
        .help(helpText ?? "")
    }
}
