import Foundation
import AppKit

public struct FolderItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let path: String
    public let name: String
    public var videoCount: Int

    public var url: URL {
        URL(fileURLWithPath: path)
    }

    public init(id: UUID = UUID(), path: String, name: String, videoCount: Int = 0) {
        self.id = id
        self.path = path
        self.name = name
        self.videoCount = videoCount
    }
}

public struct VideoItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let folderName: String
    public var duration: Double
    public var fileSize: Int64
    public var resolution: String
    public var isHDR: Bool
    public var dateAdded: Date
    public var lastPlayedDate: Date?
    public var progress: Double // 0.0 to 1.0
    public var isFavorite: Bool
    public var thumbnail: NSImage?

    public init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        folderName: String = "",
        duration: Double = 0.0,
        fileSize: Int64 = 0,
        resolution: String = "HD",
        isHDR: Bool = false,
        dateAdded: Date = Date(),
        lastPlayedDate: Date? = nil,
        progress: Double = 0.0,
        isFavorite: Bool = false,
        thumbnail: NSImage? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.folderName = folderName.isEmpty ? url.deletingLastPathComponent().lastPathComponent : folderName
        self.duration = duration
        self.fileSize = fileSize
        self.resolution = resolution
        self.isHDR = isHDR
        self.dateAdded = dateAdded
        self.lastPlayedDate = lastPlayedDate
        self.progress = progress
        self.isFavorite = isFavorite
        self.thumbnail = thumbnail
    }

    public var formattedDuration: String {
        TimeFormatting.format(seconds: duration)
    }

    public var formattedFileSize: String {
        guard fileSize > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(url)
    }

    public static func == (lhs: VideoItem, rhs: VideoItem) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }
}
