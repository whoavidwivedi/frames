import Foundation
import SwiftUI
import AVFoundation
import AppKit

public enum SidebarCategory: Hashable {
    case allVideos
    case recent
    case favorites
    case folder(id: UUID)
}

public enum ViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"

    public var id: String { rawValue }
}

public enum SortOption: String, CaseIterable, Identifiable {
    case dateAdded = "Date Added"
    case title = "Title"
    case duration = "Duration"
    case fileSize = "Size"

    public var id: String { rawValue }
}

@Observable
@MainActor
public final class LibraryManager {
    public static let shared = LibraryManager()

    public var folders: [FolderItem] = []
    public var videos: [VideoItem] = []
    public var selectedCategory: SidebarCategory = .allVideos
    public var searchQuery: String = ""
    public var viewMode: ViewMode = .grid
    public var sortOption: SortOption = .dateAdded
    public var isScanning: Bool = false

    private let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "ts", "mts", "m2ts", "flv"
    ]
    private var thumbnailCache = NSCache<NSURL, NSImage>()
    private let foldersKey = "frames_saved_folders_v1"
    private let progressKey = "frames_saved_progress_v1"
    private let favoritesKey = "frames_saved_favorites_v1"

    public init() {
        thumbnailCache.countLimit = 200
        loadPersistedState()
    }

    // MARK: - Filtered & Sorted Videos
    public var filteredVideos: [VideoItem] {
        var result = videos

        // Category filter
        switch selectedCategory {
        case .allVideos:
            break
        case .recent:
            result = result.filter { $0.lastPlayedDate != nil }
                .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .folder(let id):
            if let folder = folders.first(where: { $0.id == id }) {
                result = result.filter { $0.url.path.hasPrefix(folder.path) }
            }
        }

        // Search query filter
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) || $0.folderName.lowercased().contains(q)
            }
        }

        // Sorting
        if selectedCategory != .recent {
            switch sortOption {
            case .dateAdded:
                result.sort { $0.dateAdded > $1.dateAdded }
            case .title:
                result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .duration:
                result.sort { $0.duration > $1.duration }
            case .fileSize:
                result.sort { $0.fileSize > $1.fileSize }
            }
        }

        return result
    }

    public var selectedCategoryTitle: String {
        switch selectedCategory {
        case .allVideos:
            return "All Videos"
        case .recent:
            return "Recent Videos"
        case .favorites:
            return "Favorites"
        case .folder(let id):
            return folders.first(where: { $0.id == id })?.name ?? "Folder"
        }
    }

    // MARK: - Folder Management
    public func selectAndAddFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        panel.message = "Choose a folder containing videos to add to Frames"

        if panel.runModal() == .OK, let url = panel.url {
            addFolder(url: url)
        }
    }

    public func selectFilesToPlay(onSelected: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        panel.prompt = "Open"
        panel.message = "Select video file(s) to play"

        if panel.runModal() == .OK {
            let urls = panel.urls
            if let first = urls.first {
                // Add all selected files to library
                for url in urls {
                    addSingleVideoFile(url: url)
                }
                onSelected(first)
            }
        }
    }

    public func addFolder(url: URL) {
        let path = url.path
        if folders.contains(where: { $0.path == path }) {
            // Already added, select it
            if let existing = folders.first(where: { $0.path == path }) {
                selectedCategory = .folder(id: existing.id)
            }
            return
        }

        let newFolder = FolderItem(path: path, name: url.lastPathComponent, videoCount: 0)
        folders.append(newFolder)
        selectedCategory = .folder(id: newFolder.id)
        savePersistedState()
        scanFolder(folder: newFolder)
    }

    public func removeFolder(id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        let folderPath = folder.path
        folders.removeAll { $0.id == id }
        videos.removeAll { $0.url.path.hasPrefix(folderPath) }
        if selectedCategory == .folder(id: id) {
            selectedCategory = .allVideos
        }
        savePersistedState()
    }

    public func toggleFavorite(videoId: UUID) {
        if let idx = videos.firstIndex(where: { $0.id == videoId }) {
            videos[idx].isFavorite.toggle()
            savePersistedState()
        }
    }

    public func recordPlayback(url: URL, duration: Double, progress: Double) {
        if let idx = videos.firstIndex(where: { $0.url == url }) {
            videos[idx].lastPlayedDate = Date()
            videos[idx].progress = progress
            if duration > 0 {
                videos[idx].duration = duration
            }
        } else {
            // New video not yet in library
            let item = VideoItem(url: url, duration: duration, lastPlayedDate: Date(), progress: progress)
            videos.insert(item, at: 0)
            loadMetadataAsync(for: item)
        }
        savePersistedState()
    }

    public func addSingleVideoFile(url: URL) {
        if !videos.contains(where: { $0.url == url }) {
            let item = VideoItem(url: url)
            videos.insert(item, at: 0)
            loadMetadataAsync(for: item)
        }
    }

    // MARK: - Background Scanning
    public func scanFolder(folder: FolderItem) {
        isScanning = true
        let folderURL = folder.url
        let folderId = folder.id
        let folderName = folder.name
        let exts = self.supportedExtensions

        Task.detached(priority: .userInitiated) {
            let foundURLs = Self.scanDirectory(at: folderURL, exts: exts)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.isScanning = false

                if let idx = self.folders.firstIndex(where: { $0.id == folderId }) {
                    self.folders[idx].videoCount = foundURLs.count
                }

                for url in foundURLs {
                    if !self.videos.contains(where: { $0.url == url }) {
                        let video = VideoItem(url: url, folderName: folderName)
                        self.videos.append(video)
                        self.loadMetadataAsync(for: video)
                    }
                }
                self.savePersistedState()
            }
        }
    }

    private nonisolated static func scanDirectory(at folderURL: URL, exts: Set<String>) -> [URL] {
        var foundURLs: [URL] = []
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey]

        if let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            while let item = enumerator.nextObject() as? URL {
                let pathExt = item.pathExtension.lowercased()
                if exts.contains(pathExt) {
                    foundURLs.append(item)
                }
            }
        }
        return foundURLs
    }

    private struct ExtractedMetadata: Sendable {
        let duration: Double
        let resolution: String
        let isHDR: Bool
        let fileSize: Int64
        let thumbnail: NSImage?
    }

    private func loadMetadataAsync(for item: VideoItem) {
        let url = item.url
        let videoId = item.id

        Task.detached(priority: .background) {
            let meta = await Self.extractMetadata(for: url)
            await MainActor.run { [weak self] in
                guard let self = self, let idx = self.videos.firstIndex(where: { $0.id == videoId }) else { return }
                self.videos[idx].duration = meta.duration
                self.videos[idx].resolution = meta.resolution
                self.videos[idx].isHDR = meta.isHDR
                self.videos[idx].fileSize = meta.fileSize
                if let thumb = meta.thumbnail {
                    self.videos[idx].thumbnail = thumb
                }
            }
        }
    }

    private nonisolated static func extractMetadata(for url: URL) async -> ExtractedMetadata {
        let asset = AVURLAsset(url: url)
        var dur: Double = 0.0
        var res = "HD"
        let isHDR = false
        var fileSize: Int64 = 0

        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
            fileSize = Int64(size)
        }

        if let durationCM = try? await asset.load(.duration) {
            dur = durationCM.seconds.isFinite ? durationCM.seconds : 0.0
        }

        if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
            if let size = try? await track.load(.naturalSize) {
                let maxDim = max(size.width, size.height)
                if maxDim >= 3800 {
                    res = "4K"
                } else if maxDim >= 2500 {
                    res = "2K"
                } else if maxDim >= 1800 {
                    res = "1080p"
                } else if maxDim >= 1200 {
                    res = "720p"
                } else {
                    res = "SD"
                }
            }
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        let thumbTime = CMTime(seconds: min(5.0, dur * 0.1), preferredTimescale: 600)
        var thumbImage: NSImage?

        if let cgImage = try? await generator.image(at: thumbTime).image {
            thumbImage = NSImage(cgImage: cgImage, size: NSSize(width: 480, height: 270))
        }

        return ExtractedMetadata(
            duration: dur,
            resolution: res,
            isHDR: isHDR,
            fileSize: fileSize,
            thumbnail: thumbImage
        )
    }

    // MARK: - Persistence
    private func savePersistedState() {
        if let encoded = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(encoded, forKey: foldersKey)
        }

        // Save favorites
        let favs = videos.filter { $0.isFavorite }.map { $0.url.path }
        UserDefaults.standard.set(favs, forKey: favoritesKey)

        // Save progress & recent timestamps
        var progressMap: [String: [String: Double]] = [:]
        for v in videos where v.progress > 0 || v.lastPlayedDate != nil {
            progressMap[v.url.path] = [
                "progress": v.progress,
                "lastPlayed": v.lastPlayedDate?.timeIntervalSince1970 ?? 0,
                "duration": v.duration
            ]
        }
        UserDefaults.standard.set(progressMap, forKey: progressKey)
    }

    private func loadPersistedState() {
        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let savedFolders = try? JSONDecoder().decode([FolderItem].self, from: data) {
            self.folders = savedFolders
            for f in savedFolders {
                scanFolder(folder: f)
            }
        }

        let favPaths = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        let progressMap = UserDefaults.standard.dictionary(forKey: progressKey) as? [String: [String: Double]] ?? [:]

        // Restore any videos already known
        for i in 0..<videos.count {
            let path = videos[i].url.path
            if favPaths.contains(path) {
                videos[i].isFavorite = true
            }
            if let entry = progressMap[path] {
                videos[i].progress = entry["progress"] ?? 0.0
                if let ts = entry["lastPlayed"], ts > 0 {
                    videos[i].lastPlayedDate = Date(timeIntervalSince1970: ts)
                }
                if let dur = entry["duration"], dur > 0 {
                    videos[i].duration = dur
                }
            }
        }
    }
}
