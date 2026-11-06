import Foundation
import SwiftUI
import AVFoundation
import AppKit

private actor MetadataLoadGate {
    private var availableSlots: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrentLoads: Int) {
        self.availableSlots = maxConcurrentLoads
    }

    func acquire() async {
        guard availableSlots == 0 else {
            availableSlots -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            availableSlots += 1
        }
    }
}

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
    public var isSidebarVisible: Bool = true
    public var isSearchActive: Bool = false
    public private(set) var backStack: [SidebarCategory] = []
    public private(set) var forwardStack: [SidebarCategory] = []

    public var canGoBack: Bool {
        !backStack.isEmpty
    }

    public var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    public func navigate(to category: SidebarCategory) {
        guard category != selectedCategory else { return }
        backStack.append(selectedCategory)
        forwardStack.removeAll()
        withAnimation(.fluidSpring) {
            selectedCategory = category
        }
    }

    public func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(selectedCategory)
        withAnimation(.fluidSpring) {
            selectedCategory = prev
        }
    }

    public func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(selectedCategory)
        withAnimation(.fluidSpring) {
            selectedCategory = next
        }
    }

    public func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    public func toggleSearch() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isSearchActive.toggle()
            if !isSearchActive {
                searchQuery = ""
            }
        }
    }

    private let supportedExtensions = MediaSupport.fileExtensions
    private let foldersKey = "frames_saved_folders_v1"
    private let progressKey = "frames_saved_progress_v1"
    private let favoritesKey = "frames_saved_favorites_v1"
    private let individualVideosKey = "frames_saved_individual_videos_v1"
    private static let metadataLoadGate = MetadataLoadGate(maxConcurrentLoads: 2)
    private var persistedFavoritePaths: Set<String> = []
    private var persistedIndividualVideoPaths: Set<String> = []
    private var persistedProgress: [String: [String: Double]] = [:]
    private var activeScanCount = 0

    public init() {
        self.viewMode = SettingsManager.shared.defaultViewMode
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
        panel.allowedContentTypes = MediaSupport.contentTypes
        panel.prompt = "Open"
        panel.message = "Select video or audio file(s) to play"

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

    public func selectAndAddVideos(onAdded: (([URL]) -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = MediaSupport.contentTypes + [.folder, .directory]
        panel.prompt = "Add"
        panel.message = "Select video files or folder to add to library"

        if panel.runModal() == .OK {
            let urls = panel.urls
            var addedURLs: [URL] = []
            for url in urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    addFolder(url: url)
                    addedURLs.append(url)
                } else {
                    addSingleVideoFile(url: url)
                    addedURLs.append(url)
                }
            }
            if selectedCategory == .favorites || selectedCategory == .recent {
                selectedCategory = .allVideos
            }
            onAdded?(addedURLs)
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

    public func isFavorite(url: URL) -> Bool {
        if let item = videos.first(where: { $0.url == url }) {
            return item.isFavorite
        }
        return persistedFavoritePaths.contains(url.path)
    }

    public func toggleFavorite(url: URL) {
        if let item = videos.first(where: { $0.url == url }) {
            toggleFavorite(videoId: item.id)
        } else {
            let path = url.path
            if persistedFavoritePaths.contains(path) {
                persistedFavoritePaths.remove(path)
            } else {
                persistedFavoritePaths.insert(path)
            }
            savePersistedState()
        }
    }

    public func toggleFavorite(videoId: UUID) {
        if let idx = videos.firstIndex(where: { $0.id == videoId }) {
            videos[idx].isFavorite.toggle()
            let path = videos[idx].url.path
            if videos[idx].isFavorite {
                persistedFavoritePaths.insert(path)
            } else {
                persistedFavoritePaths.remove(path)
            }
            savePersistedState()
        }
    }

    /// Checks if a video has valid saved playback progress to prompt resume (between 2% and 98%)
    public func savedResumeTime(for url: URL) -> (seconds: Double, formattedTime: String, progress: Double)? {
        let item = videos.first(where: { $0.url == url })
        let progress = item?.progress ?? (persistedProgress[url.path]?["progress"] ?? 0.0)
        let duration = item?.duration ?? (persistedProgress[url.path]?["duration"] ?? 0.0)

        guard progress > 0.02, progress < 0.98, duration > 0 else { return nil }
        let resumeSecs = progress * duration
        guard resumeSecs >= 3.0 else { return nil }

        return (
            seconds: resumeSecs,
            formattedTime: TimeFormatting.format(seconds: resumeSecs),
            progress: progress
        )
    }

    /// Clears saved progress for a video when restarting from beginning
    public func resetPlaybackProgress(for url: URL) {
        if let idx = videos.firstIndex(where: { $0.url == url }) {
            videos[idx].progress = 0.0
        }
        if var entry = persistedProgress[url.path] {
            entry["progress"] = 0.0
            persistedProgress[url.path] = entry
        }
        savePersistedState()
    }

    /// Clears watch history and resets recent videos
    public func clearRecentAndHistory() {
        for i in 0..<videos.count {
            videos[i].lastPlayedDate = nil
            videos[i].progress = 0.0
        }
        persistedProgress.removeAll()
        UserDefaults.standard.removeObject(forKey: progressKey)
        if selectedCategory == .recent {
            selectedCategory = .allVideos
        }
        savePersistedState()
    }

    public func recordPlayback(url: URL, duration: Double, progress: Double) {
        let validProgress = min(max(progress, 0.0), 1.0)
        if let idx = videos.firstIndex(where: { $0.url == url }) {
            videos[idx].lastPlayedDate = Date()
            videos[idx].progress = validProgress
            if duration > 0 {
                videos[idx].duration = duration
            }
        } else {
            // New video not yet in library
            var item = restoredItem(VideoItem(url: url))
            item.duration = duration
            item.progress = validProgress
            item.lastPlayedDate = Date()
            videos.insert(item, at: 0)
            loadMetadataAsync(for: item)
        }
        persistedProgress[url.path] = [
            "progress": validProgress,
            "lastPlayed": Date().timeIntervalSince1970,
            "duration": duration
        ]
        savePersistedState()
    }

    public func addSingleVideoFile(url: URL) {
        let cleanURL = url.standardizedFileURL
        if let existingIdx = videos.firstIndex(where: { $0.url.standardizedFileURL == cleanURL }) {
            let item = videos.remove(at: existingIdx)
            videos.insert(item, at: 0)
            persistedIndividualVideoPaths.insert(cleanURL.path)
            savePersistedState()
        } else {
            let item = restoredItem(VideoItem(url: cleanURL))
            videos.insert(item, at: 0)
            persistedIndividualVideoPaths.insert(cleanURL.path)
            savePersistedState()
            loadMetadataAsync(for: item)
        }
    }

    // MARK: - Background Scanning
    public func scanFolder(folder: FolderItem) {
        activeScanCount += 1
        isScanning = true
        let folderURL = folder.url
        let folderId = folder.id
        let folderName = folder.name
        let exts = self.supportedExtensions

        Task.detached(priority: .utility) {
            let foundURLs = Self.scanDirectory(at: folderURL, exts: exts)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.activeScanCount = max(0, self.activeScanCount - 1)
                self.isScanning = self.activeScanCount > 0

                // A folder may have been removed while its scan was in flight.
                guard self.folders.contains(where: { $0.id == folderId }) else { return }

                if let idx = self.folders.firstIndex(where: { $0.id == folderId }) {
                    self.folders[idx].videoCount = foundURLs.count
                }

                for url in foundURLs {
                    if !self.videos.contains(where: { $0.url == url }) {
                        let video = self.restoredItem(VideoItem(url: url, folderName: folderName))
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

        Task.detached(priority: .utility) {
            await Self.metadataLoadGate.acquire()
            let meta = await Self.extractMetadata(for: url)
            await Self.metadataLoadGate.release()
            guard !Task.isCancelled else { return }
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

    private func restoredItem(_ item: VideoItem) -> VideoItem {
        var restored = item
        let path = item.url.path
        restored.isFavorite = persistedFavoritePaths.contains(path) || item.isFavorite
        if let entry = persistedProgress[path] {
            restored.progress = entry["progress"] ?? item.progress
            if let timestamp = entry["lastPlayed"], timestamp > 0 {
                restored.lastPlayedDate = Date(timeIntervalSince1970: timestamp)
            }
            if let duration = entry["duration"], duration > 0 {
                restored.duration = duration
            }
        }
        return restored
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

        return ExtractedMetadata(
            duration: dur,
            resolution: res,
            isHDR: isHDR,
            fileSize: fileSize,
            thumbnail: nil
        )
    }

    // MARK: - Persistence
    private func savePersistedState() {
        if let encoded = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(encoded, forKey: foldersKey)
        }

        UserDefaults.standard.set(Array(persistedIndividualVideoPaths), forKey: individualVideosKey)

        // Save favorites: sync with in-memory videos while preserving existing paths
        for v in videos {
            let path = v.url.path
            if v.isFavorite {
                persistedFavoritePaths.insert(path)
            } else {
                persistedFavoritePaths.remove(path)
            }
        }
        UserDefaults.standard.set(Array(persistedFavoritePaths), forKey: favoritesKey)

        // Save progress & recent timestamps: merge into persistedProgress
        for v in videos where v.progress > 0 || v.lastPlayedDate != nil {
            persistedProgress[v.url.path] = [
                "progress": v.progress,
                "lastPlayed": v.lastPlayedDate?.timeIntervalSince1970 ?? 0,
                "duration": v.duration
            ]
        }
        UserDefaults.standard.set(persistedProgress, forKey: progressKey)
    }

    private func loadPersistedState() {
        persistedFavoritePaths = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        persistedIndividualVideoPaths = Set(UserDefaults.standard.stringArray(forKey: individualVideosKey) ?? [])
        persistedProgress = UserDefaults.standard.dictionary(forKey: progressKey) as? [String: [String: Double]] ?? [:]

        // Restore individually added videos
        for path in persistedIndividualVideoPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path), !videos.contains(where: { $0.url == url }) {
                let item = restoredItem(VideoItem(url: url))
                videos.append(item)
                loadMetadataAsync(for: item)
            }
        }

        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let savedFolders = try? JSONDecoder().decode([FolderItem].self, from: data) {
            self.folders = savedFolders
            for f in savedFolders {
                scanFolder(folder: f)
            }
        }

        // Restore any videos already known
        for i in 0..<videos.count {
            videos[i] = restoredItem(videos[i])
        }
    }
}
