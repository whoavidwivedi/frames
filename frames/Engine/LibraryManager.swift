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

@MainActor
final class LibraryDirectoryWatcher {
    private var watchedDescriptors: [String: (source: DispatchSourceFileSystemObject, fd: Int32)] = [:]
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.frames.directorywatcher", qos: .utility)
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func updateWatchedPaths(_ paths: Set<String>) {
        let currentPaths = Set(watchedDescriptors.keys)
        let toRemove = currentPaths.subtracting(paths)
        for path in toRemove {
            stopWatching(path: path)
        }

        let toAdd = paths.subtracting(currentPaths)
        for path in toAdd {
            startWatching(path: path)
        }
    }

    private func startWatching(path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self, queue] in
            queue.async {
                self?.scheduleDebouncedChange()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        watchedDescriptors[path] = (source: source, fd: fd)
        source.resume()
    }

    private func stopWatching(path: String) {
        guard let item = watchedDescriptors.removeValue(forKey: path) else { return }
        item.source.cancel()
    }

    func stopAll() {
        for (_, item) in watchedDescriptors {
            item.source.cancel()
        }
        watchedDescriptors.removeAll()
    }

    private func scheduleDebouncedChange() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.onChange()
            }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}

public enum SidebarCategory: Hashable {
    case allVideos
    case recent
    case favorites
    case folder(id: UUID)
    case settings
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
        withAnimation(.fluidQuick) {
            selectedCategory = category
        }
    }

    public func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(selectedCategory)
        withAnimation(.fluidQuick) {
            selectedCategory = prev
        }
    }

    public func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(selectedCategory)
        withAnimation(.fluidQuick) {
            selectedCategory = next
        }
    }

    public func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    public func toggleViewMode() {
        viewMode = (viewMode == .grid) ? .list : .grid
    }

    public func cycleSortOption() {
        let all = SortOption.allCases
        if let idx = all.firstIndex(of: sortOption) {
            let nextIdx = (idx + 1) % all.count
            sortOption = all[nextIdx]
        } else {
            sortOption = .dateAdded
        }
    }

    public func toggleSearch() {
        withAnimation(.fluidQuick) {
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
    private var directoryWatcher: LibraryDirectoryWatcher?
    private var notificationObservers: [NSObjectProtocol] = []
    private var syncTimer: Timer?

    public init() {
        self.viewMode = SettingsManager.shared.defaultViewMode
        self.directoryWatcher = LibraryDirectoryWatcher { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFileSystemEvent()
            }
        }
        loadPersistedState()
        setupLifecycleObservers()
        setupPeriodicSync()
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
        case .settings:
            return []
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
        case .settings:
            return "Settings"
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
        updateDirectoryWatcher()
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
        updateDirectoryWatcher()
    }

    public func removeVideo(id: UUID) {
        guard let idx = videos.firstIndex(where: { $0.id == id }) else { return }
        let item = videos.remove(at: idx)
        let path = item.url.path
        persistedIndividualVideoPaths.remove(path)
        persistedFavoritePaths.remove(path)
        persistedProgress.removeValue(forKey: path)
        for i in 0..<folders.count {
            let f = folders[i]
            folders[i].videoCount = videos.filter { $0.url.path.hasPrefix(f.path) }.count
        }
        savePersistedState()
        updateDirectoryWatcher()
    }

    public func removeVideo(url: URL) {
        let cleanURL = url.standardizedFileURL
        if let item = videos.first(where: { $0.url.standardizedFileURL == cleanURL }) {
            removeVideo(id: item.id)
        } else {
            persistedIndividualVideoPaths.remove(cleanURL.path)
            persistedFavoritePaths.remove(cleanURL.path)
            persistedProgress.removeValue(forKey: cleanURL.path)
            savePersistedState()
            updateDirectoryWatcher()
        }
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
        // Guard against recording or resurrecting deleted files
        guard FileManager.default.fileExists(atPath: url.path) || CommandLine.arguments.contains("--run-tests") else {
            verifyAndPruneMissingFiles()
            return
        }

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
        updateDirectoryWatcher()
    }

    public func addSingleVideoFile(url: URL) {
        let cleanURL = url.standardizedFileURL
        if !CommandLine.arguments.contains("--run-tests") && !FileManager.default.fileExists(atPath: cleanURL.path) {
            return
        }

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
        updateDirectoryWatcher()
    }

    // MARK: - Background Scanning
    public func scanFolder(folder: FolderItem) {
        activeScanCount += 1
        isScanning = true
        let folderURL = folder.url
        let folderId = folder.id
        let folderName = folder.name
        let folderPath = folder.path
        let exts = self.supportedExtensions

        Task.detached(priority: .utility) {
            let foundURLs = Self.scanDirectory(at: folderURL, exts: exts)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.activeScanCount = max(0, self.activeScanCount - 1)
                self.isScanning = self.activeScanCount > 0

                // A folder may have been removed while its scan was in flight.
                guard self.folders.contains(where: { $0.id == folderId }) else { return }

                let foundSet = Set(foundURLs)

                // 1. Remove videos from this folder that no longer exist on disk
                var removedAny = false
                self.videos.removeAll { video in
                    if video.url.path.hasPrefix(folderPath) {
                        let missing = !foundSet.contains(video.url)
                        if missing { removedAny = true }
                        return missing
                    }
                    return false
                }

                // 2. Update folder video count
                if let idx = self.folders.firstIndex(where: { $0.id == folderId }) {
                    self.folders[idx].videoCount = foundURLs.count
                }

                // 3. Add newly discovered files
                var addedAny = false
                for url in foundURLs {
                    if !self.videos.contains(where: { $0.url == url }) {
                        let video = self.restoredItem(VideoItem(url: url, folderName: folderName))
                        self.videos.append(video)
                        self.loadMetadataAsync(for: video)
                        addedAny = true
                    }
                }

                if removedAny || addedAny {
                    self.savePersistedState()
                    self.updateDirectoryWatcher()
                }
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

        // Restore individually added videos, pruning any missing paths
        var validIndividualPaths = Set<String>()
        for path in persistedIndividualVideoPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                validIndividualPaths.insert(path)
                if !videos.contains(where: { $0.url == url }) {
                    let item = restoredItem(VideoItem(url: url))
                    videos.append(item)
                    loadMetadataAsync(for: item)
                }
            }
        }
        persistedIndividualVideoPaths = validIndividualPaths

        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let savedFolders = try? JSONDecoder().decode([FolderItem].self, from: data) {
            var validFolders: [FolderItem] = []
            for f in savedFolders {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: f.path, isDirectory: &isDir), isDir.boolValue {
                    validFolders.append(f)
                    scanFolder(folder: f)
                }
            }
            self.folders = validFolders
        }

        // Restore any videos already known
        for i in 0..<videos.count {
            videos[i] = restoredItem(videos[i])
        }

        savePersistedState()
        updateDirectoryWatcher()
    }

    // MARK: - Dynamic File Verification & Synchronization
    @discardableResult
    public func verifyAndPruneMissingFiles() -> Bool {
        var stateChanged = false

        // 1. Verify existence of all tracked folders
        var invalidFolderIDs: [UUID] = []
        for folder in folders {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir)
            if !exists || !isDir.boolValue {
                invalidFolderIDs.append(folder.id)
            }
        }
        for folderId in invalidFolderIDs {
            if let folder = folders.first(where: { $0.id == folderId }) {
                let folderPath = folder.path
                folders.removeAll { $0.id == folderId }
                videos.removeAll { $0.url.path.hasPrefix(folderPath) }
                if selectedCategory == .folder(id: folderId) {
                    selectedCategory = .allVideos
                }
                stateChanged = true
            }
        }

        // 2. Verify existence of each video in `videos`
        let videosBefore = videos.count
        videos.removeAll { video in
            !FileManager.default.fileExists(atPath: video.url.path)
        }
        if videos.count != videosBefore {
            stateChanged = true
        }

        // 3. Verify individual video paths
        let missingIndividual = persistedIndividualVideoPaths.filter { !FileManager.default.fileExists(atPath: $0) }
        if !missingIndividual.isEmpty {
            persistedIndividualVideoPaths.subtract(missingIndividual)
            stateChanged = true
        }

        // 4. Clean up favorites for missing files
        let missingFavorites = persistedFavoritePaths.filter { !FileManager.default.fileExists(atPath: $0) }
        if !missingFavorites.isEmpty {
            persistedFavoritePaths.subtract(missingFavorites)
            stateChanged = true
        }

        // 5. Clean up progress for missing files
        let missingProgress = persistedProgress.keys.filter { !FileManager.default.fileExists(atPath: $0) }
        if !missingProgress.isEmpty {
            for path in missingProgress {
                persistedProgress.removeValue(forKey: path)
            }
            stateChanged = true
        }

        // 6. Recalculate folder video counts
        for i in 0..<folders.count {
            let folder = folders[i]
            let count = videos.filter { $0.url.path.hasPrefix(folder.path) }.count
            if folders[i].videoCount != count {
                folders[i].videoCount = count
                stateChanged = true
            }
        }

        if stateChanged {
            savePersistedState()
            updateDirectoryWatcher()
        }

        return stateChanged
    }

    public func updateDirectoryWatcher() {
        guard !CommandLine.arguments.contains("--run-tests") else { return }

        var dirsToWatch = Set<String>()
        for folder in folders {
            dirsToWatch.insert(folder.path)
        }
        for video in videos {
            let parentDir = video.url.deletingLastPathComponent().path
            dirsToWatch.insert(parentDir)
        }
        for path in persistedIndividualVideoPaths {
            let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
            dirsToWatch.insert(parentDir)
        }

        directoryWatcher?.updateWatchedPaths(dirsToWatch)
    }

    private func handleFileSystemEvent() {
        verifyAndPruneMissingFiles()
        for folder in folders {
            scanFolder(folder: folder)
        }
    }

    private func setupLifecycleObservers() {
        guard !CommandLine.arguments.contains("--run-tests") else { return }

        let center = NotificationCenter.default
        let activeObs = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.verifyAndPruneMissingFiles()
            }
        }
        let keyObs = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.verifyAndPruneMissingFiles()
            }
        }
        notificationObservers = [activeObs, keyObs]
    }

    private func setupPeriodicSync() {
        guard !CommandLine.arguments.contains("--run-tests") else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.videos.isEmpty || !self.folders.isEmpty else { return }
                self.verifyAndPruneMissingFiles()
            }
        }
    }
}
