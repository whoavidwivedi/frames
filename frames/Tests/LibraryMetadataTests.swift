import AppKit
import CoreGraphics
import Foundation
import ImageIO

final nonisolated class LibraryTestBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?

    var value: T? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ newValue: T) {
        lock.lock()
        stored = newValue
        lock.unlock()
    }
}

final nonisolated class ExtractionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var paths: [String] = []
    private(set) var maxActive = 0

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    var peakConcurrency: Int {
        lock.lock()
        defer { lock.unlock() }
        return maxActive
    }

    func begin(_ url: URL) {
        lock.lock()
        active += 1
        maxActive = max(maxActive, active)
        paths.append(url.lastPathComponent)
        lock.unlock()
    }

    func end() {
        lock.lock()
        active -= 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        paths.removeAll()
        maxActive = 0
        lock.unlock()
    }
}

@MainActor
enum LibraryMetadataTests {
    struct Check {
        let report: (String, Bool, String) -> Void

        func callAsFunction(_ name: String, _ condition: Bool, _ message: String = "") {
            report(name, condition, message)
        }
    }

    static let fixtureDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("assets/test-fixtures/library", isDirectory: true)

    nonisolated static let fixtureCount = 8

    static func run(_ report: @escaping (String, Bool, String) -> Void) {
        let check = Check(report: report)
        runFrameTargetChecks(check)
        runExtractionChecks(check)
        runSortingChecks(check)
        runLibraryChecks(check)
    }

    @discardableResult
    static func pump(timeout: TimeInterval = 15, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    static func blocking<T: Sendable>(_ operation: @escaping @Sendable () async -> T) -> T? {
        let box = LibraryTestBox<T>()
        Task.detached { box.set(await operation()) }
        pump { box.value != nil }
        return box.value
    }

    static func realPath(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    static func scratchDefaults(in directory: URL) -> UserDefaults? {
        UserDefaults(suiteName: directory.appendingPathComponent("defaults-\(UUID().uuidString)").path)
    }

    struct RGBAverage {
        var red: Double
        var green: Double
        var blue: Double
    }

    static func averageRGB(_ data: Data?) -> RGBAverage? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let size = 8
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        var sums = RGBAverage(red: 0, green: 0, blue: 0)
        for idx in stride(from: 0, to: pixels.count, by: 4) {
            sums.red += Double(pixels[idx])
            sums.green += Double(pixels[idx + 1])
            sums.blue += Double(pixels[idx + 2])
        }
        let count = Double(size * size)
        return RGBAverage(red: sums.red / count, green: sums.green / count, blue: sums.blue / count)
    }

    static func isCoverRed(_ data: Data?) -> Bool {
        guard let avg = averageRGB(data) else { return false }
        return avg.red > 180 && avg.green < 130 && avg.blue < 110
    }

    static func isOrangeFrame(_ data: Data?) -> Bool {
        guard let avg = averageRGB(data) else { return false }
        return avg.red > 180 && avg.green > 100 && avg.blue < 90
    }

    static func describe<T>(_ value: T?) -> String {
        String(describing: value)
    }

    // MARK: - Frame targets

    private static func runFrameTargetChecks(_ check: Check) {
        let short = ThumbnailImaging.frameTargets(duration: 100)
        check("Thumbnail Frame Target Starts At 10% Of Duration", short.first == 10, "\(short)")
        let long = ThumbnailImaging.frameTargets(duration: 3600)
        check("Thumbnail Frame Target Capped At 60 Seconds", long.first == 60, "\(long)")
        check("Thumbnail Frame Targets Advance Past First Candidate", long.count > 1 && long[1] > long[0], "\(long)")
    }

    // MARK: - Extraction

    private static func extract(_ name: String) -> ExtractedMetadata? {
        let url = fixtureDirectory.appendingPathComponent(name)
        return blocking { await MediaMetadataExtractor.extract(url: url, includeThumbnail: true) }
    }

    private static func runExtractionChecks(_ check: Check) {
        let taggedMP4 = fixtureDirectory.appendingPathComponent("tagged-cover.mp4")
        let present = FileManager.default.fileExists(atPath: taggedMP4.path)
        check("Library Fixtures Present", present, fixtureDirectory.path)
        guard present else { return }
        runTaggedExtractionChecks(check)
        runUntaggedExtractionChecks(check)
    }

    private static func runTaggedExtractionChecks(_ check: Check) {
        let mp4 = extract("tagged-cover.mp4")
        let mp4Thumb = mp4?.thumbnailJPEG
        check("MP4 Embedded Title Extracted", mp4?.title == "Fixture Tagged Title", describe(mp4?.title))
        check("MP4 Embedded Artist Extracted", mp4?.artist == "Fixture Artist", describe(mp4?.artist))
        check("MP4 Embedded Cover Used As Thumbnail", isCoverRed(mp4Thumb), describe(averageRGB(mp4Thumb)))

        let mkv = extract("tagged-cover.mkv")
        let mkvThumb = mkv?.thumbnailJPEG
        check("MKV Embedded Title Extracted", mkv?.title == "Fixture MKV Title", describe(mkv?.title))
        check("MKV Embedded Artist Extracted", mkv?.artist == "Fixture MKV Artist", describe(mkv?.artist))
        check("MKV Cover Attachment Used As Thumbnail", isCoverRed(mkvThumb), describe(averageRGB(mkvThumb)))

        let mp3 = extract("tagged-cover.mp3")
        let mp3Thumb = mp3?.thumbnailJPEG
        check("MP3 Embedded Title Extracted", mp3?.title == "Fixture MP3 Title", describe(mp3?.title))
        check("MP3 Embedded Artist Extracted", mp3?.artist == "Fixture MP3 Artist", describe(mp3?.artist))
        check("MP3 Embedded Cover Used As Thumbnail", isCoverRed(mp3Thumb), describe(averageRGB(mp3Thumb)))

        let flac = extract("tagged.flac")
        check("FLAC Embedded Title Extracted", flac?.title == "Fixture FLAC Title", describe(flac?.title))
        check("FLAC Embedded Artist Extracted", flac?.artist == "Fixture FLAC Artist", describe(flac?.artist))
        check("Audio Without Art Has No Thumbnail", flac != nil && flac?.thumbnailJPEG == nil)
    }

    private static func runUntaggedExtractionChecks(_ check: Check) {
        let m4a = extract("untagged.m4a")
        check(
            "Untagged Audio Has No Title, Artist Or Thumbnail",
            m4a != nil && m4a?.title == nil && m4a?.artist == nil && m4a?.thumbnailJPEG == nil
        )

        let untaggedMP4 = extract("untagged.mp4")
        let mp4Thumb = untaggedMP4?.thumbnailJPEG
        check("Untagged MP4 Has No Embedded Title", untaggedMP4 != nil && untaggedMP4?.title == nil)
        check(
            "Untagged MP4 Generated Frame Skips Black Lead-In",
            isOrangeFrame(mp4Thumb),
            describe(averageRGB(mp4Thumb))
        )

        let untaggedMKV = extract("untagged.mkv")
        let mkvThumb = untaggedMKV?.thumbnailJPEG
        check("Untagged MKV Has No Embedded Title", untaggedMKV != nil && untaggedMKV?.title == nil)
        check(
            "Untagged MKV Generated Frame Skips Black Lead-In",
            isOrangeFrame(mkvThumb),
            describe(averageRGB(mkvThumb))
        )

        let corrupt = extract("corrupt.mp4")
        check("Corrupt MP4 Extraction Returns Without Thumbnail", corrupt != nil && corrupt?.thumbnailJPEG == nil)

        let taggedURL = fixtureDirectory.appendingPathComponent("tagged-cover.mp4")
        let metaOnly = blocking {
            await MediaMetadataExtractor.extract(url: taggedURL, includeThumbnail: false)
        }
        check(
            "Metadata-Only Extraction Skips Thumbnail",
            metaOnly?.title == "Fixture Tagged Title" && metaOnly?.thumbnailJPEG == nil
        )
    }

    // MARK: - Sorting

    private static func runSortingChecks(_ check: Check) {
        var zed = VideoItem(url: URL(fileURLWithPath: "/tmp/a.mp4"))
        zed.artist = "Zed"
        var amy = VideoItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
        amy.artist = "amy"
        let none = VideoItem(url: URL(fileURLWithPath: "/tmp/c.mp4"))
        let sorted = [none, zed, amy].sorted { LibraryManager.artistOrder($0, $1) }
        check("Artist Sort Orders A To Z Case-Insensitively With Missing Artists Last",
              sorted.map(\.artist) == ["amy", "Zed", nil], "\(sorted.map(\.artist))")
    }
}
