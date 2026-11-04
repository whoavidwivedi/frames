//
//  TimeJumpParser.swift
//  frames
//
//  Fast timestamp expression parser for instant media seeking and Command Palette navigation.
//  Supports absolute formats (HH:MM:SS, MM:SS, :SS, 90s, 15m) and relative jumps (+30s, -15s).
//

import Foundation

public struct TimeJumpResult: Equatable {
    public let targetSeconds: Double
    public let isRelative: Bool
    public let relativeDelta: Double
    public let formattedTarget: String
}

public enum TimeJumpParser {

    /// Parses an arbitrary query string into a valid seek target in seconds.
    ///
    /// - Parameters:
    ///   - query: Input string (e.g., "1:23", "01:23:45", ":45", "90s", "12m", "+30", "-15s")
    ///   - currentTime: Current media playback position in seconds (for relative jumps)
    ///   - duration: Total duration of the media file (for boundary clamping)
    /// - Returns: `TimeJumpResult` if the query is a recognized timestamp format, or `nil` if invalid.
    public static func parse(query: String, currentTime: Double = 0.0, duration: Double = Double.infinity) -> TimeJumpResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Strip leading colon if used as prefix indicator in command menu (e.g. ":1:30")
        var raw = trimmed
        if raw.hasPrefix(":") && raw.count > 1 && !raw.dropFirst().contains(":") {
            // E.g., ":45" -> treat as 45 seconds
            if let seconds = Double(raw.dropFirst()) {
                let clamped = clamp(seconds, duration: duration)
                return TimeJumpResult(
                    targetSeconds: clamped,
                    isRelative: false,
                    relativeDelta: 0,
                    formattedTarget: formatTime(clamped)
                )
            }
        }

        // Relative Jumps: "+30", "+30s", "-15", "-15s"
        if raw.hasPrefix("+") || raw.hasPrefix("-") {
            let isPositive = raw.hasPrefix("+")
            let numberPart = raw.dropFirst().replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)
            if let deltaSeconds = Double(numberPart) {
                let signedDelta = isPositive ? deltaSeconds : -deltaSeconds
                let target = clamp(currentTime + signedDelta, duration: duration)
                return TimeJumpResult(
                    targetSeconds: target,
                    isRelative: true,
                    relativeDelta: signedDelta,
                    formattedTarget: formatTime(target)
                )
            }
        }

        // Unit-suffixed numbers: "90s", "15m", "1.5h"
        if raw.hasSuffix("s") || raw.hasSuffix("m") || raw.hasSuffix("h") {
            let suffix = raw.suffix(1)
            let valString = raw.dropLast().trimmingCharacters(in: .whitespaces)
            if let val = Double(valString) {
                var seconds: Double = val
                switch suffix {
                case "m": seconds = val * 60.0
                case "h": seconds = val * 3600.0
                default: break
                }
                let target = clamp(seconds, duration: duration)
                return TimeJumpResult(
                    targetSeconds: target,
                    isRelative: false,
                    relativeDelta: 0,
                    formattedTarget: formatTime(target)
                )
            }
        }

        // Colon-delimited formats: "HH:MM:SS" or "MM:SS"
        if raw.contains(":") {
            let components = raw.split(separator: ":").map { String($0) }
            if components.count == 2 {
                // MM:SS
                guard let minutes = Double(components[0]),
                      let seconds = Double(components[1]) else { return nil }
                let total = (minutes * 60.0) + seconds
                let target = clamp(total, duration: duration)
                return TimeJumpResult(
                    targetSeconds: target,
                    isRelative: false,
                    relativeDelta: 0,
                    formattedTarget: formatTime(target)
                )
            } else if components.count == 3 {
                // HH:MM:SS
                guard let hours = Double(components[0]),
                      let minutes = Double(components[1]),
                      let seconds = Double(components[2]) else { return nil }
                let total = (hours * 3600.0) + (minutes * 60.0) + seconds
                let target = clamp(total, duration: duration)
                return TimeJumpResult(
                    targetSeconds: target,
                    isRelative: false,
                    relativeDelta: 0,
                    formattedTarget: formatTime(target)
                )
            }
        }

        return nil
    }

    private static func clamp(_ seconds: Double, duration: Double) -> Double {
        if seconds.isNaN || seconds.isInfinite { return 0.0 }
        let lowerClamped = max(0.0, seconds)
        if duration.isFinite && duration > 0 {
            return min(lowerClamped, duration)
        }
        return lowerClamped
    }

    private static func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}
