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
        // Defer so NSApp is ready, then follow the system appearance.
        DispatchQueue.main.async { [weak self] in
            self?.applyAppearance()
        }
        // Re-apply when the system theme changes so "System" mode tracks it.
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.mode == .system else { return }
            self.applyAppearance()
        }
    }

    public func applyAppearance() {
        guard let app = NSApp else { return }
        switch mode {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
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

// Shared Frames surfaces and action colors.
public enum ShadcnTheme {
    // A deeper gold for light surfaces and a brighter gold for dark surfaces.
    static let favorite = dynamicColor(
        light: (0.50, 0.32, 0.02, 1),
        dark: (1, 0.77, 0.29, 1)
    )

    static let favoriteOnThumbnail = Color(red: 1, green: 0.77, blue: 0.29)

    public static let actionTint = dynamicColor(
        light: (0.12, 0.12, 0.12, 1),
        dark: (0.94, 0.94, 0.94, 1)
    )

    public static let background = dynamicColor(
        light: (0.965, 0.965, 0.965, 1),
        dark: (0.075, 0.075, 0.075, 1)
    )

    public static let card = dynamicColor(
        light: (1, 1, 1, 1),
        dark: (0.125, 0.125, 0.125, 1)
    )

    public static let cardHover = dynamicColor(
        light: (0.865, 0.865, 0.865, 1),
        dark: (0.25, 0.25, 0.25, 1)
    )

    public static let popover = card

    public static let sidebar = dynamicColor(
        light: (0.92, 0.92, 0.92, 1),
        dark: (0.105, 0.105, 0.105, 1)
    )

    // MARK: - Foreground & Typography
    /// Light: oklch(0.145 0 0) -> #0a0a0a | Dark: oklch(0.985 0 0) -> #fafafa
    public static let foreground: Color = dynamicColor(
        light: (0.039, 0.039, 0.039, 1.0),
        dark: (0.98, 0.98, 0.98, 1.0)
    )

    public static let foregroundSecondary: Color = dynamicColor(
        light: (0.36, 0.36, 0.36, 1),
        dark: (0.74, 0.74, 0.74, 1)
    )

    public static let foregroundMuted: Color = dynamicColor(
        light: (0.37, 0.37, 0.37, 1),
        dark: (0.70, 0.70, 0.70, 1)
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
        light: (0.41, 0.41, 0.41, 1),
        dark: (0.65, 0.65, 0.65, 1)
    )

    // MARK: - Primary & Brand Highlights (Preset b1VlK05Q: Monochrome Neutral)
    /// Light: oklch(0.205 0 0) -> #171717 | Dark: oklch(0.985 0 0) -> #fafafa
    public static let primary: Color = dynamicColor(
        light: (0.091, 0.091, 0.091, 1.0),
        dark: (0.980, 0.980, 0.980, 1.0)
    )

    /// Light: oklch(0.985 0 0) -> #fafafa | Dark: oklch(0.205 0 0) -> #171717
    public static let primaryForeground: Color = dynamicColor(
        light: (0.980, 0.980, 0.980, 1.0),
        dark: (0.091, 0.091, 0.091, 1.0)
    )

    /// Light: oklch(0.145 0 0) -> #0a0a0a | Dark: oklch(1 0 0) -> #ffffff
    public static let primaryHighlight: Color = dynamicColor(
        light: (0.039, 0.039, 0.039, 1.0),
        dark: (1.0, 1.0, 1.0, 1.0)
    )

    /// Secondary container
    public static let secondary: Color = dynamicColor(
        light: (0.905, 0.905, 0.905, 1),
        dark: (0.195, 0.195, 0.195, 1)
    )

    /// Secondary text
    /// Light: oklch(0.205 0 0) -> #171717 | Dark: oklch(0.985 0 0) -> #fafafa
    public static let secondaryForeground: Color = dynamicColor(
        light: (0.091, 0.091, 0.091, 1.0),
        dark: (0.980, 0.980, 0.980, 1.0)
    )

    /// Muted / Accent
    public static let muted: Color = dynamicColor(
        light: (0.925, 0.925, 0.925, 1),
        dark: (0.17, 0.17, 0.17, 1)
    )

    public static let accent: Color = dynamicColor(
        light: (0.88, 0.88, 0.88, 1),
        dark: (0.225, 0.225, 0.225, 1)
    )

    public static let accentActive: Color = dynamicColor(
        light: (0.0, 0.0, 0.0, 0.08),
        dark: (1.0, 1.0, 1.0, 0.12)
    )

    /// Destructive action
    public static let destructive: Color = dynamicColor(
        light: (0.68, 0.13, 0.16, 1),
        dark: (1, 0.45, 0.46, 1)
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
