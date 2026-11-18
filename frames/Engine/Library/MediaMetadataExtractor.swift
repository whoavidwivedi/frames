import AVFoundation
import CoreGraphics
import Foundation
import os

nonisolated struct ExtractedMetadata: Sendable, Equatable {
    var title: String?
    var artist: String?
    var duration: Double = 0
    var resolution: String = "HD"
    var isHDR: Bool = false
    var fileSize: Int64 = 0
    var thumbnailJPEG: Data?
}

nonisolated enum MediaMetadataExtractor {
    static let signposter = OSSignposter(subsystem: "whoavidwivedi.frames", category: "LibraryExtraction")

    static func extract(url: URL, includeThumbnail: Bool = true) async -> ExtractedMetadata {
        let state = signposter.beginInterval("extract", id: signposter.makeSignpostID())
        defer { signposter.endInterval("extract", state) }

        var meta = isEBML(url) ? extractMatroska(url: url, includeThumbnail: includeThumbnail)
            : await extractAVFoundation(url: url, includeThumbnail: includeThumbnail)
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
            meta.fileSize = Int64(size)
        }
        meta.title = normalized(meta.title)
        meta.artist = normalized(meta.artist)
        return meta
    }

    static func isEBML(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 4)
        return header.count == 4 && header.elementsEqual([0x1A, 0x45, 0xDF, 0xA3])
    }

    static func resolutionLabel(width: Double, height: Double) -> String {
        let maxDim = max(width, height)
        if maxDim >= 3800 {
            return "4K"
        }
        if maxDim >= 2500 {
            return "2K"
        }
        if maxDim >= 1800 {
            return "1080p"
        }
        if maxDim >= 1200 {
            return "720p"
        }
        return "SD"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - AVFoundation

    private static func extractAVFoundation(url: URL, includeThumbnail: Bool) async -> ExtractedMetadata {
        let asset = AVURLAsset(url: url)
        var meta = ExtractedMetadata()

        if let duration = try? await asset.load(.duration), duration.seconds.isFinite {
            meta.duration = duration.seconds
        }

        var artworkData: Data?
        if let items = try? await asset.load(.commonMetadata) {
            meta.title = await stringValue(in: items, key: .commonKeyTitle)
            meta.artist = await stringValue(in: items, key: .commonKeyArtist)
            if includeThumbnail {
                artworkData = await dataValue(in: items, key: .commonKeyArtwork)
            }
        }
        await fillTagsFromFormats(asset: asset, into: &meta)

        let videoTrack = try? await asset.loadTracks(withMediaType: .video).first
        if let track = videoTrack, let size = try? await track.load(.naturalSize) {
            meta.resolution = resolutionLabel(width: size.width, height: size.height)
        }

        guard includeThumbnail else { return meta }
        if let data = artworkData, let image = ThumbnailImaging.downscaledImage(fromEncoded: data) {
            meta.thumbnailJPEG = ThumbnailImaging.jpegData(image)
            return meta
        }
        if videoTrack != nil, let frame = await generatedFrame(asset: asset, duration: meta.duration) {
            meta.thumbnailJPEG = ThumbnailImaging.jpegData(frame)
        }
        return meta
    }

    private static func fillTagsFromFormats(asset: AVURLAsset, into meta: inout ExtractedMetadata) async {
        guard meta.title == nil || meta.artist == nil,
              let formats = try? await asset.load(.availableMetadataFormats) else { return }
        let titleSuffixes = ["TITLE", "TIT2", "title"]
        let artistSuffixes = ["ARTIST", "TPE1", "artist"]
        for format in formats {
            guard let items = try? await asset.loadMetadata(for: format) else { continue }
            if meta.title == nil {
                meta.title = await stringValue(in: items, identifierSuffixes: titleSuffixes)
            }
            if meta.artist == nil {
                meta.artist = await stringValue(in: items, identifierSuffixes: artistSuffixes)
            }
        }
    }

    private static func stringValue(in items: [AVMetadataItem], key: AVMetadataKey) async -> String? {
        for item in AVMetadataItem.metadataItems(from: items, withKey: key, keySpace: .common) {
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func stringValue(in items: [AVMetadataItem], identifierSuffixes: [String]) async -> String? {
        for item in items {
            guard let identifier = item.identifier?.rawValue,
                  let suffix = identifier.split(separator: "/").last,
                  identifierSuffixes.contains(where: {
                      suffix.caseInsensitiveCompare($0) == .orderedSame
                  }) else { continue }
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func dataValue(in items: [AVMetadataItem], key: AVMetadataKey) async -> Data? {
        for item in AVMetadataItem.metadataItems(from: items, withKey: key, keySpace: .common) {
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    private static func generatedFrame(asset: AVURLAsset, duration: Double) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: ThumbnailImaging.maxPixelSize, height: ThumbnailImaging.maxPixelSize)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var last: CGImage?
        for target in ThumbnailImaging.frameTargets(duration: duration) {
            let time = CMTime(seconds: target, preferredTimescale: 600)
            guard let (image, _) = try? await generator.image(at: time) else {
                continue
            }
            last = image
            if !ThumbnailImaging.isNearBlack(image) {
                return image
            }
        }
        return last
    }

    // MARK: - Matroska

    private static func extractMatroska(url: URL, includeThumbnail: Bool) -> ExtractedMetadata {
        var meta = ExtractedMetadata()
        guard let demuxer = try? MatroskaDemuxer(url: url, indexClusters: false) else { return meta }
        defer { demuxer.close() }

        meta.title = demuxer.embeddedTitle
        meta.artist = demuxer.embeddedArtist
        meta.duration = demuxer.duration
        if let track = demuxer.videoTracks.first {
            meta.resolution = resolutionLabel(width: Double(track.pixelWidth), height: Double(track.pixelHeight))
            meta.isHDR = track.isHDR
        }

        guard includeThumbnail else { return meta }
        if let cover = demuxer.coverAttachment, let image = ThumbnailImaging.downscaledImage(fromEncoded: cover) {
            meta.thumbnailJPEG = ThumbnailImaging.jpegData(image)
            return meta
        }
        guard !demuxer.videoTracks.isEmpty else { return meta }
        var last: CGImage?
        for target in ThumbnailImaging.frameTargets(duration: meta.duration) {
            guard let image = MatroskaFrameGrabber.grabFrame(from: demuxer, at: target) else { continue }
            last = image
            if !ThumbnailImaging.isNearBlack(image) {
                break
            }
        }
        if let image = last {
            meta.thumbnailJPEG = ThumbnailImaging.jpegData(image)
        }
        return meta
    }
}
