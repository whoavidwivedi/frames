import Foundation

/// Robust, production-grade Semantic Versioning representation following SemVer 2.0.0.
/// Supports comparison, sorting, parsing with or without 'v' prefix, and pre-release identifiers.
public struct SemanticVersion: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let rawString: String

    public init(major: Int, minor: Int = 0, patch: Int = 0, prerelease: String? = nil, rawString: String? = nil) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
        self.prerelease = prerelease?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? prerelease : nil

        if let raw = rawString {
            self.rawString = raw
        } else {
            var s = "\(self.major).\(self.minor).\(self.patch)"
            if let pre = self.prerelease {
                s += "-\(pre)"
            }
            self.rawString = s
        }
    }

    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        self.rawString = trimmed

        var clean = trimmed
        if clean.lowercased().hasPrefix("v") {
            clean = String(clean.dropFirst())
        }

        // Split off build metadata (e.g. +build.123)
        if let plusIdx = clean.firstIndex(of: "+") {
            clean = String(clean[..<plusIdx])
        }

        // Split off pre-release (e.g. -beta.1)
        var pre: String? = nil
        if let hyphenIdx = clean.firstIndex(of: "-") {
            pre = String(clean[clean.index(after: hyphenIdx)...])
            clean = String(clean[..<hyphenIdx])
        }

        let parts = clean.split(separator: ".")
        guard !parts.isEmpty else { return nil }

        let parsedParts = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parsedParts.count == parts.count else { return nil }

        self.major = parsedParts[0]
        self.minor = parsedParts.count > 1 ? parsedParts[1] : 0
        self.patch = parsedParts.count > 2 ? parsedParts[2] : 0
        self.prerelease = pre
    }

    public var displayString: String {
        var s = "\(major).\(minor).\(patch)"
        if let pre = prerelease {
            s += "-\(pre)"
        }
        return s
    }

    public var tagString: String {
        return "v\(displayString)"
    }

    public var description: String {
        return rawString
    }

    // MARK: - Comparable & Equatable

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        // If numeric components are identical:
        // A release without a prerelease has higher precedence than one with a prerelease.
        // e.g., 1.0.0-alpha < 1.0.0
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case let (l?, r?):
            return l.localizedStandardCompare(r) == .orderedAscending
        }
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        return lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch &&
               lhs.prerelease == rhs.prerelease
    }
}
