import SwiftUI
import AppKit

// MARK: - Theme Mode (Light, Dark, System)
public enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var icon: String {
        switch self {
        case .system: return "circle.righthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Theme Manager
@MainActor
@Observable
public final class ThemeManager {
    public static let shared = ThemeManager()
    private let key = "frames_theme_mode_v2"

    public var mode: ThemeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: key)
            applyAppearance()
        }
    }

    public var isDark: Bool {
        switch mode {
        case .dark: return true
        case .light: return false
        case .system:
            return NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    public init() {
        let saved = UserDefaults.standard.string(forKey: key) ?? ThemeMode.system.rawValue
        self.mode = ThemeMode(rawValue: saved) ?? .system
        applyAppearance()
    }

    public func applyAppearance() {
        switch mode {
        case .system:
            NSApp?.appearance = nil
        case .light:
            NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// One-click direct toggle between light and dark mode
    public func toggleTheme() {
        if isDark {
            mode = .light
        } else {
            mode = .dark
        }
    }

    public func toggleLightDark() {
        toggleTheme()
    }
}

// MARK: - Dynamic Color Helper
func dynamicColor(
    light: (r: Double, g: Double, b: Double, a: Double),
    dark: (r: Double, g: Double, b: Double, a: Double)
) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        let isDark = match == .darkAqua
        let val = isDark ? dark : light
        return NSColor(srgbRed: val.r, green: val.g, blue: val.b, alpha: val.a)
    })
}

// MARK: - Shadcn Design Tokens: Preset `b3lnoM3QO` (base-luma + neutral, dual-mode)
public enum ShadcnTheme {
    // MARK: - Background Surfaces (Neutral Base)
    /// Light: oklch(1 0 0) -> #ffffff | Dark: oklch(0.145 0 0) -> #0a0a0a
    public static let background: Color = dynamicColor(
        light: (1.0, 1.0, 1.0, 1.0),
        dark: (0.039, 0.039, 0.039, 1.0)
    )

    /// Light: oklch(1 0 0) -> #ffffff | Dark: oklch(0.205 0 0) -> #171717
    public static let card: Color = dynamicColor(
        light: (1.0, 1.0, 1.0, 1.0),
        dark: (0.091, 0.091, 0.091, 1.0)
    )

    /// Light: oklch(0.97 0 0) -> #f5f5f5 | Dark: oklch(0.24 0 0) -> #202020
    public static let cardHover: Color = dynamicColor(
        light: (0.961, 0.961, 0.961, 1.0),
        dark: (0.125, 0.125, 0.125, 1.0)
    )

    /// Light: oklch(1 0 0) -> #ffffff | Dark: oklch(0.205 0 0) -> #171717
    public static let popover: Color = dynamicColor(
        light: (1.0, 1.0, 1.0, 1.0),
        dark: (0.091, 0.091, 0.091, 1.0)
    )

    /// Light: oklch(0.985 0 0) -> #fafafa | Dark: oklch(0.205 0 0) -> #171717
    public static let sidebar: Color = dynamicColor(
        light: (0.98, 0.98, 0.98, 1.0),
        dark: (0.091, 0.091, 0.091, 1.0)
    )

    // MARK: - Foreground & Typography
    /// Light: oklch(0.145 0 0) -> #0a0a0a | Dark: oklch(0.985 0 0) -> #fafafa
    public static let foreground: Color = dynamicColor(
        light: (0.039, 0.039, 0.039, 1.0),
        dark: (0.98, 0.98, 0.98, 1.0)
    )

    /// Light: oklch(0.556 0 0) -> #737373 | Dark: oklch(0.708 0 0) -> #a1a1a1
    public static let foregroundSecondary: Color = dynamicColor(
        light: (0.452, 0.452, 0.452, 1.0),
        dark: (0.63, 0.63, 0.63, 1.0)
    )

    /// Light: #616161 (contrast ratio ~5.8:1 against #ffffff) | Dark: #adadad (contrast ratio ~6.5:1 against #0a0a0a)
    public static let foregroundMuted: Color = dynamicColor(
        light: (0.38, 0.38, 0.38, 1.0),
        dark: (0.68, 0.68, 0.68, 1.0)
    )

    // MARK: - Borders & Outlines
    /// Light: oklch(0.922 0 0) -> #e5e5e5 | Dark: oklch(1 0 0 / 10%)
    public static let border: Color = dynamicColor(
        light: (0.898, 0.898, 0.898, 1.0),
        dark: (1.0, 1.0, 1.0, 0.10)
    )

    /// Subtle border
    public static let borderSubtle: Color = dynamicColor(
        light: (0.0, 0.0, 0.0, 0.06),
        dark: (1.0, 1.0, 1.0, 0.05)
    )

    /// Active / Hover border
    public static let borderActive: Color = dynamicColor(
        light: (0.63, 0.63, 0.63, 1.0),
        dark: (1.0, 1.0, 1.0, 0.22)
    )

    /// Input outline
    public static let input: Color = dynamicColor(
        light: (0.898, 0.898, 0.898, 1.0),
        dark: (1.0, 1.0, 1.0, 0.15)
    )

    /// Focus ring
    public static let ring: Color = dynamicColor(
        light: (0.63, 0.63, 0.63, 1.0),
        dark: (0.452, 0.452, 0.452, 1.0)
    )

    // MARK: - Primary & Brand Highlights (Luma Terracotta & Copper)
    /// Light: oklch(0.553 0.195 38.402) -> #ca3500 | Dark: oklch(0.47 0.157 37.304) -> #9f2d00
    public static let primary: Color = dynamicColor(
        light: (0.792, 0.207, 0.0, 1.0),
        dark: (0.624, 0.177, 0.0, 1.0)
    )

    /// Light: oklch(0.98 0.016 73.684) -> #fff7ed | Dark: oklch(0.98 0.016 73.684) -> #fff7ed
    public static let primaryForeground: Color = Color(red: 1.0, green: 0.969, blue: 0.929)

    /// Light: oklch(0.646 0.222 41.116) -> #f54900 | Dark: oklch(0.705 0.213 47.604) -> #ff6900
    public static let primaryHighlight: Color = dynamicColor(
        light: (0.961, 0.288, 0.0, 1.0),
        dark: (1.0, 0.411, 0.0, 1.0)
    )

    /// Secondary container
    /// Light: oklch(0.967 0.001 286.375) -> #f4f4f5 | Dark: oklch(0.274 0.006 286.033) -> #27272a
    public static let secondary: Color = dynamicColor(
        light: (0.956, 0.956, 0.959, 1.0),
        dark: (0.153, 0.153, 0.166, 1.0)
    )

    /// Secondary text
    /// Light: oklch(0.21 0.006 285.885) -> #18181b | Dark: oklch(0.985 0 0) -> #fafafa
    public static let secondaryForeground: Color = dynamicColor(
        light: (0.094, 0.094, 0.106, 1.0),
        dark: (0.98, 0.98, 0.98, 1.0)
    )

    /// Muted / Accent
    /// Light: oklch(0.97 0 0) -> #f5f5f5 | Dark: oklch(0.269 0 0) -> #262626
    public static let muted: Color = dynamicColor(
        light: (0.961, 0.961, 0.961, 1.0),
        dark: (0.149, 0.149, 0.149, 1.0)
    )

    public static let accent: Color = dynamicColor(
        light: (0.961, 0.961, 0.961, 1.0),
        dark: (0.149, 0.149, 0.149, 1.0)
    )

    public static let accentActive: Color = dynamicColor(
        light: (0.0, 0.0, 0.0, 0.08),
        dark: (1.0, 1.0, 1.0, 0.12)
    )

    /// Destructive action
    /// Light: oklch(0.577 0.245 27.325) -> #e7000b | Dark: oklch(0.704 0.191 22.216) -> #ff6467
    public static let destructive: Color = dynamicColor(
        light: (0.906, 0.0, 0.042, 1.0),
        dark: (1.0, 0.391, 0.404, 1.0)
    )

    // MARK: - Radii (base-luma scale with base 10pt / 0.625rem)
    public static let radiusSm: CGFloat = 6   // calc(var(--radius) * 0.6)
    public static let radiusMd: CGFloat = 8   // calc(var(--radius) * 0.8)
    public static let radiusLg: CGFloat = 10  // var(--radius)
    public static let radiusXl: CGFloat = 14  // calc(var(--radius) * 1.4)
    public static let radius2xl: CGFloat = 18 // calc(var(--radius) * 1.8)
    public static let radius3xl: CGFloat = 22 // calc(var(--radius) * 2.2)
    public static let radius4xl: CGFloat = 26 // calc(var(--radius) * 2.6) - Luma pill radius
}

// MARK: - Reusable Card Modifier (Liquid Glass Layered)
public struct ShadcnCardModifier: ViewModifier {
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
                    .fill(ShadcnTheme.card.opacity(0.85))
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
                radius: 16,
                x: 0,
                y: 6
            )
    }
}

public extension View {
    func shadcnCard(cornerRadius: CGFloat = ShadcnTheme.radiusLg, padding: CGFloat = 12) -> some View {
        modifier(ShadcnCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Fluid Physics & Curves (Optimized for Apple Silicon ProMotion 120Hz Displays)
public enum FramesAnimation {
    /// Fluid continuous spring curve optimized for ProMotion 120Hz displays
    /// Smooth response (0.35s) and gentle damping (0.86) eliminating all bounce and visual jitter
    public static let fluidSpring = Animation.spring(response: 0.35, dampingFraction: 0.86)

    /// Smooth continuous transition curve (0.35s)
    public static let smooth = Animation.smooth(duration: 0.35)

    /// Fast interactive spring for micro-interactions (hover, press, quick toggles)
    public static let quick = Animation.spring(response: 0.22, dampingFraction: 0.88)

    /// Gentle fluid curve for overlays, popovers, and dialogs
    public static let overlay = Animation.spring(response: 0.38, dampingFraction: 0.84)

    /// Layout resizing and window state transition curve (quarter-screen, split-screen, full-screen)
    public static let windowTransition = Animation.spring(response: 0.36, dampingFraction: 0.86)
}

public extension Animation {
    /// Fluid continuous spring curve optimized for ProMotion 120Hz displays
    static let fluidSpring = FramesAnimation.fluidSpring

    /// Smooth continuous transition curve (0.35s)
    static let fluidSmooth = FramesAnimation.smooth

    /// Fast interactive spring for micro-interactions (0.22s)
    static let fluidQuick = FramesAnimation.quick

    /// Gentle fluid curve for overlays, sheets, and popovers (0.38s)
    static let fluidOverlay = FramesAnimation.overlay

    /// Window state and layout transition animation curve (0.36s)
    static let fluidWindow = FramesAnimation.windowTransition
}
