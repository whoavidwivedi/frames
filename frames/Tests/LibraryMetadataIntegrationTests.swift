import Foundation

extension LibraryMetadataTests {
    @MainActor
    private struct LibrarySandbox {
        let root: URL
        let defaults: UserDefaults
        let mediaDir: URL
        let cacheDir: URL
        let recorder = ExtractionRecorder()

        func makeCache() -> LibraryCache {
            LibraryCache(directory: cacheDir)
        }

        func configuration(concurrency: Int = LibraryManager.defaultMetadataConcurrency) -> LibraryConfiguration {
            var config = LibraryConfiguration()
            config.defaults = defaults
            config.cache = makeCache()
            config.observesFileSystem = false
            config.metadataConcurrency = concurrency
            let recorder = recorder
            config.extractor = { url, includeThumbnail in
                recorder.begin(url)
                let meta = await MediaMetadataExtractor.extract(url: url, includeThumbnail: includeThumbnail)
                recorder.end()
                return meta
            }
            return config
        }

        func settled(_ lib: LibraryManager, count: Int = LibraryMetadataTests.fixtureCount) -> Bool {
            LibraryMetadataTests.pump { lib.videos.count == count && lib.pendingMetadataLoads == 0 && !lib.isScanning }
        }

        func item(_ lib: LibraryManager, _ name: String) -> VideoItem? {
            lib.videos.first { $0.url.lastPathComponent == name }
        }
    }

    private static func makeSandbox(_ check: Check) -> LibrarySandbox? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fixtureDirectory.path) else { return nil }
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("frames-library-tests-\(UUID().uuidString)", isDirectory: true)
        let mediaURL = root.appendingPathComponent("media", isDirectory: true)
        guard let defaults = scratchDefaults(in: root),
              (try? fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)) != nil,
              let names = try? fileManager.contentsOfDirectory(atPath: fixtureDirectory.path)
        else {
            check("Library Test Sandbox Created", false, root.path)
            return nil
        }
        let mediaDir = realPath(mediaURL)
        for name in names {
            let source = fixtureDirectory.appendingPathComponent(name)
            try? fileManager.copyItem(at: source, to: mediaDir.appendingPathComponent(name))
        }
        return LibrarySandbox(
            root: root,
            defaults: defaults,
            mediaDir: mediaDir,
            cacheDir: root.appendingPathComponent("cache", isDirectory: true)
        )
    }

    static func runLibraryChecks(_ check: Check) {
        guard let sandbox = makeSandbox(check) else { return }
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let lib = LibraryManager(configuration: sandbox.configuration(concurrency: 3))
        lib.addFolder(url: sandbox.mediaDir)
        runImportChecks(check, sandbox, lib)
        runSearchAndSortChecks(check, lib)

        let cache = sandbox.makeCache()
        let cachedFiles = blocking { await cache.cachedFileCount() } ?? 0
        check("Metadata And Thumbnails Cached On Disk", cachedFiles >= fixtureCount, "files=\(cachedFiles)")

        let relaunched = runRelaunchChecks(check, sandbox)
        runCacheClearChecks(check, sandbox, relaunched)
        runRemovalChecks(check, relaunched, cache)
    }

    private static func runImportChecks(_ check: Check, _ sandbox: LibrarySandbox, _ lib: LibraryManager) {
        let recorder = sandbox.recorder
        check(
            "Library Import Settles For All Fixtures (Corrupt File Included)",
            sandbox.settled(lib),
            "videos=\(lib.videos.count) pending=\(lib.pendingMetadataLoads)"
        )
        check(
            "Metadata Concurrency Limit Is Configurable And Respected",
            recorder.peakConcurrency == 3,
            "peak=\(recorder.peakConcurrency)"
        )

        let tagged = sandbox.item(lib, "tagged-cover.mp4")
        check(
            "Library Shows Embedded Title Instead Of Filename",
            tagged?.title == "Fixture Tagged Title",
            describe(tagged?.title)
        )
        check("Library Keeps Filename Title For Search", tagged?.fileTitle == "tagged-cover")
        check("Library Shows Embedded Artist", tagged?.artist == "Fixture Artist")
        check("Library Shows Embedded Cover Thumbnail", tagged?.thumbnail != nil)
        let untagged = sandbox.item(lib, "untagged.mp4")
        check(
            "Library Falls Back To Filename Without Extension",
            untagged?.title == "untagged",
            describe(untagged?.title)
        )
        check("Library Shows No Artist When Untagged", untagged != nil && untagged?.artist == nil)
        check("Library Shows Generated Frame For Untagged Video", untagged?.thumbnail != nil)
        check("Library Keeps Placeholder For Untagged Audio", sandbox.item(lib, "untagged.m4a")?.thumbnail == nil)
        check(
            "Library Keeps Placeholder For Corrupt File",
            sandbox.item(lib, "corrupt.mp4").map { $0.thumbnail == nil } == true
        )
    }

    private static func runSearchAndSortChecks(_ check: Check, _ lib: LibraryManager) {
        lib.searchQuery = "fixture mkv artist"
        check(
            "Search Matches Artist Case-Insensitively",
            lib.filteredVideos.map(\.url.lastPathComponent) == ["tagged-cover.mkv"]
        )
        lib.searchQuery = "FIXTURE TAGGED"
        check(
            "Search Matches Embedded Title",
            lib.filteredVideos.map(\.url.lastPathComponent) == ["tagged-cover.mp4"]
        )
        lib.searchQuery = "tagged-cover"
        check(
            "Search Matches Filename",
            lib.filteredVideos.count == 3,
            "\(lib.filteredVideos.map(\.url.lastPathComponent))"
        )
        lib.searchQuery = ""

        lib.sortOption = .title
        let titles = lib.filteredVideos.map(\.title)
        let titlesSorted = titles == titles.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        check("Title Sort Uses Displayed Title", titlesSorted && titles.contains("Fixture MKV Title"), "\(titles)")
        lib.sortOption = .artist
        let artists = lib.filteredVideos.map(\.artist)
        let expectedArtists = ["Fixture Artist", "Fixture FLAC Artist", "Fixture MKV Artist", "Fixture MP3 Artist"]
        check(
            "Artist Sort Puts Tagged Files First A To Z",
            Array(artists.prefix(4)) == expectedArtists && artists.dropFirst(4).allSatisfy { $0 == nil },
            "\(artists)"
        )
    }

    private static func runRelaunchChecks(_ check: Check, _ sandbox: LibrarySandbox) -> LibraryManager {
        let changedURL = sandbox.mediaDir.appendingPathComponent("untagged.mp4")
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(120)],
            ofItemAtPath: changedURL.path
        )
        sandbox.recorder.reset()
        let relaunched = LibraryManager(configuration: sandbox.configuration())
        check(
            "Relaunch Restores Library From Cache",
            sandbox.settled(relaunched),
            "videos=\(relaunched.videos.count)"
        )
        check(
            "Relaunch Re-Extracts Only The Modified File",
            sandbox.recorder.calls == ["untagged.mp4"],
            "\(sandbox.recorder.calls)"
        )
        check(
            "Relaunch Shows Cached Title, Artist And Thumbnail",
            sandbox.item(relaunched, "tagged-cover.mp4").map {
                $0.title == "Fixture Tagged Title" && $0.artist == "Fixture Artist" && $0.thumbnail != nil
            } == true
        )
        check(
            "Relaunch Shows Cached Duration And Resolution",
            sandbox.item(relaunched, "tagged-cover.mkv").map { $0.duration > 1 && $0.resolution == "SD" } == true
        )
        return relaunched
    }

    private static func runCacheClearChecks(_ check: Check, _ sandbox: LibrarySandbox, _ lib: LibraryManager) {
        let cleared = lib.clearThumbnailCache()
        sandbox.recorder.reset()
        _ = blocking { await cleared.value }
        let regenerated = pump {
            lib.pendingMetadataLoads == 0 && lib.videos.filter { $0.thumbnail != nil }.count == 5
        }
        check(
            "Clear Thumbnail Cache Regenerates Thumbnails",
            regenerated && sandbox.recorder.calls.count == fixtureCount,
            "calls=\(sandbox.recorder.calls.count)"
        )
    }

    private static func runRemovalChecks(_ check: Check, _ lib: LibraryManager, _ cache: LibraryCache) {
        if let removed = lib.videos.first(where: { $0.url.lastPathComponent == "tagged-cover.mp3" }) {
            let removedURL = removed.url
            lib.removeVideo(id: removed.id)
            let evicted = pump { blocking { await cache.lookup(url: removedURL) == nil } == true }
            check("Removing A Video Deletes Its Cache Entry", evicted)
        }
        if let folder = lib.folders.first {
            lib.removeFolder(id: folder.id)
            let emptied = pump { (blocking { await cache.cachedFileCount() } ?? -1) == 0 }
            check("Removing A Folder Deletes Its Cache Entries", emptied)
        }
    }
}
