import Foundation
import AVFoundation

public struct SubtitleCue: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let startTime: Double
    public let endTime: Double
    public let text: String

    public init(id: UUID = UUID(), startTime: Double, endTime: Double, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public struct SubtitleTrack: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let languageCode: String?
    public let isExternal: Bool
    public var cues: [SubtitleCue]
    public let avOption: AVMediaSelectionOption?

    public init(
        id: String,
        title: String,
        languageCode: String? = nil,
        isExternal: Bool = false,
        cues: [SubtitleCue] = [],
        avOption: AVMediaSelectionOption? = nil
    ) {
        self.id = id
        self.title = title
        self.languageCode = languageCode
        self.isExternal = isExternal
        self.cues = cues
        self.avOption = avOption
    }

    public static let off = SubtitleTrack(id: "off", title: "Off")
}
