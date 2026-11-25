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

        // Legacy releases also used short forms such as v1 and v1.2.
        let metadata = clean.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard let version = metadata.first,
              metadata.count == 1 || Self.validIdentifiers(metadata[1], allowLeadingZeros: true) else { return nil }
        let pieces = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = pieces.first,
              pieces.count == 1 || Self.validIdentifiers(pieces[1], allowLeadingZeros: false) else { return nil }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part == "0" || part.first != "0",
                  part.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(part)
        }
        guard numbers.count == parts.count else { return nil }
        major = numbers[0]
        minor = numbers.count > 1 ? numbers[1] : 0
        patch = numbers.count > 2 ? numbers[2] : 0
        prerelease = pieces.count == 2 ? String(pieces[1]) : nil
    }

    private static func validIdentifiers(_ value: Substring, allowLeadingZeros: Bool) -> Bool {
        !value.isEmpty && value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { identifier in
            let bytes = identifier.utf8
            return !bytes.isEmpty && bytes.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
            } && (allowLeadingZeros || identifier.count == 1 || identifier.first != "0" || !identifier.allSatisfy(\.isNumber))
        }
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
            let left = l.split(separator: ".")
            let right = r.split(separator: ".")
            for (a, b) in zip(left, right) where a != b {
                let numericA = a.allSatisfy(\.isNumber)
                let numericB = b.allSatisfy(\.isNumber)
                if numericA != numericB { return numericA }
                if numericA && a.count != b.count { return a.count < b.count }
                return a.utf8.lexicographicallyPrecedes(b.utf8)
            }
            return left.count < right.count
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        return lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch &&
               lhs.prerelease == rhs.prerelease
    }
}
