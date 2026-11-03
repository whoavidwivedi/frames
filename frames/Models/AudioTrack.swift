import Foundation
import AVFoundation

public struct AudioTrack: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let languageCode: String?
    public let channelLayout: String
    public let formatDescription: String
    public let avOption: AVMediaSelectionOption?

    public init(
        id: String,
        title: String,
        languageCode: String? = nil,
        channelLayout: String = "Stereo",
        formatDescription: String = "AAC",
        avOption: AVMediaSelectionOption? = nil
    ) {
        self.id = id
        self.title = title
        self.languageCode = languageCode
        self.channelLayout = channelLayout
        self.formatDescription = formatDescription
        self.avOption = avOption
    }
}
