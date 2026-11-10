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
            .scaleEffect(configuration.isPressed ? 0.93 : (isHovered ? 1.05 : 1.0))
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isHovered)
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
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
            withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .pointingHand()
        .help(helpText ?? "")
    }
}

// MARK: - Apple-Grade Liquid Glass Volume Slider

public struct LiquidGlassVolumeSlider: View {
    @Binding public var value: Double
    public var isMuted: Bool
    public var width: CGFloat
    public var height: CGFloat

    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false

    public init(
        value: Binding<Double>,
        isMuted: Bool = false,
        width: CGFloat = 58,
        height: CGFloat = 24
    ) {
        self._value = value
        self.isMuted = isMuted
        self.width = width
        self.height = height
    }

    public var body: some View {
        let effectivePct = isMuted ? 0.0 : max(0.0, min(1.0, value))
        let isExpanded = isHovered || isDragging
        let trackHeight: CGFloat = isExpanded ? 7 : 5
        let thumbSize: CGFloat = isExpanded ? 13 : 10

        GeometryReader { proxy in
            let sliderWidth = proxy.size.width
            let thumbX = max(thumbSize / 2, min(sliderWidth - thumbSize / 2, CGFloat(effectivePct) * sliderWidth))

            ZStack(alignment: .leading) {
                // Background Track Channel
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .frame(height: trackHeight)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.40), location: 0.0),
                                        .init(color: Color.white.opacity(0.18), location: 0.5),
                                        .init(color: Color.white.opacity(0.08), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )

                // Filled Liquid Glass Volume Level
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                isMuted ? Color.white.opacity(0.35) : Color.white.opacity(0.95),
                                isMuted ? Color.white.opacity(0.20) : Color.white.opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(0, min(sliderWidth, sliderWidth * CGFloat(effectivePct))), height: trackHeight)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.50), lineWidth: 0.5)
                    )

                // Liquid Glass Thumb Bead
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color(white: 0.88)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white, Color.white.opacity(0.40)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    Ellipse()
                        .fill(Color.white.opacity(0.90))
                        .frame(width: thumbSize * 0.45, height: thumbSize * 0.22)
                        .offset(y: -thumbSize * 0.22)
                }
                .frame(width: thumbSize, height: thumbSize)
                .shadow(color: Color.black.opacity(isExpanded ? 0.45 : 0.25), radius: 2.5, y: 1)
                .position(x: thumbX, y: proxy.size.height / 2)
            }
            .frame(width: sliderWidth, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let pct = max(0.0, min(1.0, Double(gesture.location.x / sliderWidth)))
                        value = pct
                    }
                    .onEnded { gesture in
                        let pct = max(0.0, min(1.0, Double(gesture.location.x / sliderWidth)))
                        value = pct
                        isDragging = false
                    }
            )
            .onHover { hovering in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                    isHovered = hovering
                }
            }
        }
        .frame(width: width, height: height)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isDragging)
        .pointingHand()
    }
}

// MARK: - macOS 27 Apple Liquid Glass Traffic Lights

public struct LiquidGlassTrafficLights: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var isClusterHovered: Bool = false
    @State private var hoveredButton: TrafficButtonType? = nil
    @State private var pressedButton: TrafficButtonType? = nil
    @State private var isOptionPressed: Bool = false

    public var buttonSize: CGFloat = 13.5
    public var spacing: CGFloat = 7.0
    public var onClose: (() -> Void)? = nil
    public var onMinimize: (() -> Void)? = nil
    public var onZoom: (() -> Void)? = nil

    public enum TrafficButtonType: Hashable, Sendable {
        case close
        case minimize
        case zoom
    }

    public init(
        buttonSize: CGFloat = 13.5,
        spacing: CGFloat = 7.0,
        onClose: (() -> Void)? = nil,
        onMinimize: (() -> Void)? = nil,
        onZoom: (() -> Void)? = nil
    ) {
        self.buttonSize = buttonSize
        self.spacing = spacing
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.onZoom = onZoom
    }

    public var body: some View {
        HStack(spacing: spacing) {
            trafficOrb(type: .close)
            trafficOrb(type: .minimize)
            trafficOrb(type: .zoom)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.75)) {
                isClusterHovered = hovering
                if hovering {
                    isOptionPressed = NSEvent.modifierFlags.contains(.option)
                }
            }
        }
    }

    @ViewBuilder
    private func trafficOrb(type: TrafficButtonType) -> some View {
        let isHovered = hoveredButton == type
        let isPressed = pressedButton == type
        let isActive = controlActiveState != .inactive

        Button {
            triggerAction(for: type)
        } label: {
            ZStack {
                // Optical Ultra-Thin Material Base
                Circle()
                    .fill(.ultraThinMaterial)

                // Translucent Jewel Glass Fill
                Circle()
                    .fill(glassFill(for: type, isActive: isActive, isHovered: isHovered, isPressed: isPressed))

                // Top Specular Refraction Glint
                Ellipse()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isHovered ? 0.70 : 0.45), location: 0.0),
                                .init(color: Color.white.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: buttonSize * 0.65, height: buttonSize * 0.35)
                    .offset(y: -buttonSize * 0.22)
                    .allowsHitTesting(false)

                // Liquid Glass Specular Rim Border
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isHovered ? 0.75 : 0.50), location: 0.0),
                                .init(color: Color.white.opacity(0.20), location: 0.45),
                                .init(color: Color.black.opacity(0.30), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )

                // macOS Micro-Glyph (Appears on Cluster Hover)
                if isClusterHovered {
                    glyphIcon(for: type)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .shadow(
                color: Color.black.opacity(isHovered ? 0.35 : 0.16),
                radius: isHovered ? 2.5 : 1.2,
                x: 0,
                y: isHovered ? 1.5 : 0.8
            )
            .scaleEffect(isPressed ? 0.90 : (isHovered ? 1.06 : 1.0))
            .animation(.spring(response: 0.20, dampingFraction: 0.72), value: isHovered)
            .animation(.spring(response: 0.14, dampingFraction: 0.80), value: isPressed)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { hovering in
            hoveredButton = hovering ? type : nil
            if hovering {
                isOptionPressed = NSEvent.modifierFlags.contains(.option)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressedButton = type }
                .onEnded { _ in pressedButton = nil }
        )
        .accessibilityLabel(accessibilityTitle(for: type))
    }

    @ViewBuilder
    private func glyphIcon(for type: TrafficButtonType) -> some View {
        Group {
            switch type {
            case .close:
                Image(systemName: "xmark")
                    .font(.system(size: buttonSize * 0.52, weight: .bold))
            case .minimize:
                Image(systemName: "minus")
                    .font(.system(size: buttonSize * 0.52, weight: .black))
            case .zoom:
                if isOptionPressed {
                    Image(systemName: "plus")
                        .font(.system(size: buttonSize * 0.52, weight: .heavy))
                } else {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: buttonSize * 0.42, weight: .heavy))
                }
            }
        }
        .foregroundStyle(Color.black.opacity(0.70))
        .shadow(color: Color.white.opacity(0.35), radius: 0.3, x: 0, y: 0.5)
        .allowsHitTesting(false)
    }

    private func glassFill(for type: TrafficButtonType, isActive: Bool, isHovered: Bool, isPressed: Bool) -> LinearGradient {
        guard isActive else {
            let opacity = isPressed ? 0.55 : (isHovered ? 0.45 : 0.35)
            return LinearGradient(
                colors: [Color(white: 0.72).opacity(opacity), Color(white: 0.48).opacity(opacity * 0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        switch type {
        case .close:
            let top = isPressed ? Color(red: 0.85, green: 0.22, blue: 0.18) : (isHovered ? Color(red: 1.0, green: 0.44, blue: 0.40) : Color(red: 1.0, green: 0.36, blue: 0.33))
            let bot = isPressed ? Color(red: 0.70, green: 0.14, blue: 0.12) : (isHovered ? Color(red: 0.95, green: 0.24, blue: 0.20) : Color(red: 0.90, green: 0.19, blue: 0.16))
            return LinearGradient(colors: [top, bot], startPoint: .top, endPoint: .bottom)

        case .minimize:
            let top = isPressed ? Color(red: 0.88, green: 0.58, blue: 0.08) : (isHovered ? Color(red: 1.0, green: 0.82, blue: 0.26) : Color(red: 1.0, green: 0.75, blue: 0.18))
            let bot = isPressed ? Color(red: 0.75, green: 0.48, blue: 0.04) : (isHovered ? Color(red: 0.95, green: 0.65, blue: 0.10) : Color(red: 0.90, green: 0.59, blue: 0.06))
            return LinearGradient(colors: [top, bot], startPoint: .top, endPoint: .bottom)

        case .zoom:
            let top = isPressed ? Color(red: 0.12, green: 0.65, blue: 0.22) : (isHovered ? Color(red: 0.24, green: 0.88, blue: 0.40) : Color(red: 0.18, green: 0.82, blue: 0.32))
            let bot = isPressed ? Color(red: 0.08, green: 0.52, blue: 0.16) : (isHovered ? Color(red: 0.14, green: 0.72, blue: 0.22) : Color(red: 0.10, green: 0.66, blue: 0.18))
            return LinearGradient(colors: [top, bot], startPoint: .top, endPoint: .bottom)
        }
    }

    private func triggerAction(for type: TrafficButtonType) {
        switch type {
        case .close:
            if let custom = onClose {
                custom()
            } else if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                window.performClose(nil)
            } else {
                NSApp.terminate(nil)
            }
        case .minimize:
            if let custom = onMinimize {
                custom()
            } else if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                window.miniaturize(nil)
            }
        case .zoom:
            if let custom = onZoom {
                custom()
            } else if NSEvent.modifierFlags.contains(.option) {
                WindowManager.shared.performTitleBarDoubleClickAction()
            } else if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                window.toggleFullScreen(nil)
            }
        }
    }

    private func accessibilityTitle(for type: TrafficButtonType) -> String {
        switch type {
        case .close: return "Close window"
        case .minimize: return "Minimize window"
        case .zoom: return isOptionPressed ? "Zoom window" : "Toggle Full Screen"
        }
    }
}
