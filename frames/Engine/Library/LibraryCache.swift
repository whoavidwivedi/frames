import CryptoKit
import Foundation

nonisolated struct LibraryCacheEntry: Codable, Sendable, Equatable {
    let path: String
    let fileSize: Int64
    let modificationTime: Double
    let title: String?
    let artist: String?
    let duration: Double
    let resolution: String
    let isHDR: Bool
    let hasThumbnail: Bool
    let thumbnailRequested: Bool
}

nonisolated struct LibraryCacheHit: Sendable {
    let entry: LibraryCacheEntry
    let thumbnailJPEG: Data?

    var metadata: ExtractedMetadata {
        ExtractedMetadata(
            title: entry.title,
            artist: entry.artist,
            duration: entry.duration,
            resolution: entry.resolution,
            isHDR: entry.isHDR,
            fileSize: entry.fileSize,
            thumbnailJPEG: thumbnailJPEG
        )
    }
}

actor LibraryCache {
    static let defaultDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("whoavidwivedi.frames/library", isDirectory: true)
    }()

    let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL = LibraryCache.defaultDirectory) {
        self.directory = directory
    }

    nonisolated static func key(for path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func fileStamp(for url: URL) -> (size: Int64, mtime: Double)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let date = attributes[.modificationDate] as? Date else { return nil }
        return (size.int64Value, date.timeIntervalSince1970)
    }

    func lookup(url: URL) -> LibraryCacheHit? {
        let path = url.path
        let key = Self.key(for: path)
        guard let data = try? Data(contentsOf: jsonURL(key)),
              let entry = try? JSONDecoder().decode(LibraryCacheEntry.self, from: data),
              entry.path == path,
              let stamp = Self.fileStamp(for: url),
              stamp.size == entry.fileSize,
              stamp.mtime == entry.modificationTime else { return nil }
        var thumbnail: Data?
        if entry.hasThumbnail {
            guard let jpeg = try? Data(contentsOf: jpegURL(key)) else { return nil }
            thumbnail = jpeg
        }
        return LibraryCacheHit(entry: entry, thumbnailJPEG: thumbnail)
    }

    @discardableResult
    func store(url: URL, metadata: ExtractedMetadata, thumbnailRequested: Bool = true) -> Bool {
        guard let stamp = Self.fileStamp(for: url) else { return false }
        let path = url.path
        let key = Self.key(for: path)
        let entry = LibraryCacheEntry(
            path: path,
            fileSize: stamp.size,
            modificationTime: stamp.mtime,
            title: metadata.title,
            artist: metadata.artist,
            duration: metadata.duration,
            resolution: metadata.resolution,
            isHDR: metadata.isHDR,
            hasThumbnail: metadata.thumbnailJPEG != nil,
            thumbnailRequested: thumbnailRequested
        )
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if let jpeg = metadata.thumbnailJPEG {
                try jpeg.write(to: jpegURL(key), options: .atomic)
            } else {
                try? fileManager.removeItem(at: jpegURL(key))
            }
            try JSONEncoder().encode(entry).write(to: jsonURL(key), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func remove(path: String) {
        let key = Self.key(for: path)
        try? fileManager.removeItem(at: jsonURL(key))
        try? fileManager.removeItem(at: jpegURL(key))
    }

    func remove(pathPrefix: String) {
        let prefix = pathPrefix.hasSuffix("/") ? pathPrefix : pathPrefix + "/"
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? JSONDecoder().decode(LibraryCacheEntry.self, from: data),
                  entry.path.hasPrefix(prefix) else { continue }
            remove(path: entry.path)
        }
    }

    func removeAll() {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    func cachedFileCount() -> Int {
        (try? fileManager.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    private func jsonURL(_ key: String) -> URL {
        directory.appendingPathComponent(key + ".json")
    }

    private func jpegURL(_ key: String) -> URL {
        directory.appendingPathComponent(key + ".jpg")
    }
}
