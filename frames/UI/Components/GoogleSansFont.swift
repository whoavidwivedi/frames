import SwiftUI
import AppKit
import CoreText
import Foundation

// MARK: - Google Sans Flex Font Manager

public final class GoogleSansFontManager {
    public static let shared = GoogleSansFontManager()
    private static var isRegistered = false
    private static let lock = NSLock()

    private init() {}

    /// Registers Google Sans Flex font with CoreText for runtime usage in SwiftUI and AppKit.
    @discardableResult
    public static func registerIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if isRegistered { return true }

        // Candidate URLs in priority order:
        var candidateURLs: [URL] = []

        // 1. Bundle main resources
        if let bundleURL = Bundle.main.url(forResource: "GoogleSansFlex", withExtension: "ttf") {
            candidateURLs.append(bundleURL)
        }
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("GoogleSansFlex.ttf"),
           FileManager.default.fileExists(atPath: resURL.path) {
            candidateURLs.append(resURL)
        }
        if let subURL = Bundle.main.resourceURL?.appendingPathComponent("Fonts/GoogleSansFlex.ttf"),
           FileManager.default.fileExists(atPath: subURL.path) {
            candidateURLs.append(subURL)
        }

        // 2. User Fonts directory fallback
        let userFontsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Fonts/GoogleSansFlex.ttf")
        if FileManager.default.fileExists(atPath: userFontsURL.path) {
            candidateURLs.append(userFontsURL)
        }

        for url in candidateURLs {
            var errorRef: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef) {
                isRegistered = true
                return true
            } else {
                // If already registered or harmless duplicate, treat as registered
                if let error = errorRef?.takeRetainedValue() {
                    let code = CFErrorGetCode(error)
                    if code == 105 || code == 305 { // kCTFontManagerErrorAlreadyRegistered
                        isRegistered = true
                        return true
                    }
                }
            }
        }

        // Check if font is already accessible to the system
        if NSFont(name: "Google Sans Flex", size: 12) != nil ||
           NSFont(name: "GoogleSansFlex-Regular", size: 12) != nil {
            isRegistered = true
            return true
        }

        return false
    }
}

// MARK: - SwiftUI Font Extension

extension Font {
    /// Returns Google Sans Flex font configured for the requested size and weight.
    public static func googleSans(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        _ = GoogleSansFontManager.registerIfNeeded()

        // Map weight to explicit PostScript name for 100% deterministic rendering across macOS versions
        let postScriptName = postScriptName(for: weight)
        if let _ = NSFont(name: postScriptName, size: size) {
            return Font.custom(postScriptName, size: size)
        }

        // Fallback to family + weight
        return Font.custom("Google Sans Flex", size: size).weight(weight)
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin:
            return "GoogleSansFlex-Thin"
        case .light:
            return "GoogleSansFlex-Light"
        case .regular:
            return "GoogleSansFlex-Regular"
        case .medium:
            return "GoogleSansFlex-Medium"
        case .semibold:
            return "GoogleSansFlex-SemiBold"
        case .bold:
            return "GoogleSansFlex-Bold"
        case .heavy:
            return "GoogleSansFlex-ExtraBold"
        case .black:
            return "GoogleSansFlex-Black"
        default:
            return "GoogleSansFlex-Regular"
        }
    }
}

// MARK: - AppKit NSFont Extension

extension NSFont {
    /// Returns Google Sans Flex NSFont configured for the requested size and weight.
    public static func googleSans(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        _ = GoogleSansFontManager.registerIfNeeded()

        let name: String
        switch weight {
        case .ultraLight, .thin:
            name = "GoogleSansFlex-Thin"
        case .light:
            name = "GoogleSansFlex-Light"
        case .regular:
            name = "GoogleSansFlex-Regular"
        case .medium:
            name = "GoogleSansFlex-Medium"
        case .semibold:
            name = "GoogleSansFlex-SemiBold"
        case .bold:
            name = "GoogleSansFlex-Bold"
        case .heavy:
            name = "GoogleSansFlex-ExtraBold"
        case .black:
            name = "GoogleSansFlex-Black"
        default:
            name = "GoogleSansFlex-Regular"
        }

        if let font = NSFont(name: name, size: size) {
            return font
        }
        if let font = NSFont(name: "Google Sans Flex", size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
}
