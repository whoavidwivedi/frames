import Foundation
import UniformTypeIdentifiers

/// Formats that Frames can offer to AVFoundation for playback.
/// AVFoundation selects hardware decoding whenever it is available on the Mac.
nonisolated public enum MediaSupport: Sendable {
    public static let fileExtensions: Set<String> = [
        "3gp", "3g2", "asf", "avi", "dv", "f4v", "flv", "m2ts", "m4v", "mkv",
        "mov", "mp4", "mpeg", "mpg", "mts", "mxf", "ogv", "ts", "vob", "webm", "wmv",
        "aac", "aif", "aiff", "alac", "caf", "flac", "m4a", "mka", "mp3", "oga", "ogg",
        "opus", "wav", "wma"
    ]

    public static let contentTypes: [UTType] = {
        let standard: [UTType] = [.movie, .video, .audio, .quickTimeMovie, .mpeg4Movie]
        let extensionTypes = fileExtensions.compactMap { UTType(filenameExtension: $0) }
        return Array(Set(standard + extensionTypes)).sorted { $0.identifier < $1.identifier }
    }()

    public static func accepts(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }
}
