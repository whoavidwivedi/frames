import Foundation

public enum SubtitleParser {
    public static func parse(content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard !lines.isEmpty else { continue }

            var timeLineIndex: Int?
            for (idx, line) in lines.enumerated() {
                if line.contains("-->") {
                    timeLineIndex = idx
                    break
                }
            }

            guard let timeIndex = timeLineIndex else { continue }
            let timeLine = lines[timeIndex]
            let timeParts = timeLine.components(separatedBy: "-->")
            guard timeParts.count == 2 else { continue }

            let startStr = timeParts[0].trimmingCharacters(in: .whitespaces)
            let endRaw = timeParts[1].trimmingCharacters(in: .whitespaces)
            let endStr = endRaw.components(separatedBy: .whitespaces).first(where: { !$0.isEmpty }) ?? endRaw

            guard let startTime = parseTimestamp(startStr),
                  let endTime = parseTimestamp(endStr),
                  endTime > startTime else { continue }

            let textLines = lines[(timeIndex + 1)...]
            guard !textLines.isEmpty else { continue }

            let rawText = textLines.joined(separator: "\n")
            let cleanText = cleanSubtitleText(rawText)

            if !cleanText.isEmpty {
                cues.append(SubtitleCue(startTime: startTime, endTime: endTime, text: cleanText))
            }
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    public static func parseTimestamp(_ str: String) -> Double? {
        let clean = str.replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ":")

        if parts.count == 3 {
            guard let h = Double(parts[0]),
                  let m = Double(parts[1]),
                  let s = Double(parts[2]) else { return nil }
            return h * 3600.0 + m * 60.0 + s
        } else if parts.count == 2 {
            guard let m = Double(parts[0]),
                  let s = Double(parts[1]) else { return nil }
            return m * 60.0 + s
        }
        return nil
    }

    private static func cleanSubtitleText(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
