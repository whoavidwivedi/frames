//
//  FrameCaptureEngine.swift
//  frames
//
//  High-resolution frame snapshot capture engine for Apple Silicon Metal & VideoToolbox pipelines.
//  Exports current playback frame or scrub frame at native resolution to ~/Pictures/Frames.
//

import AppKit
import CoreVideo
import Foundation

public final class FrameCaptureEngine {
    public static let shared = FrameCaptureEngine()

    public struct SnapshotMetadata: Equatable {
        public let fileName: String
        public let fileURL: URL
        public let timestampSeconds: Double
        public let formattedTime: String
        public let width: Int
        public let height: Int
    }

    private let picturesFolder: URL

    public init(customFolder: URL? = nil) {
        if let custom = customFolder {
            self.picturesFolder = custom
        } else {
            let defaultPics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
            self.picturesFolder = defaultPics.appendingPathComponent("Frames", isDirectory: true)
        }
    }

    /// Resolves the destination directory, creating it if needed.
    public func ensureDestinationDirectoryExists() throws -> URL {
        if !FileManager.default.fileExists(atPath: picturesFolder.path) {
            try FileManager.default.createDirectory(at: picturesFolder, withIntermediateDirectories: true, attributes: nil)
        }
        return picturesFolder
    }

    /// Generates a standardized snapshot filename.
    /// Format: `Frames_<VideoTitle>_<HH-MM-SS>_<UUID>.png`
    public func generateSnapshotFileName(videoTitle: String, timestampSeconds: Double) -> String {
        let cleanTitle = videoTitle
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let titlePart = cleanTitle.isEmpty ? "Video" : String(cleanTitle.prefix(32))

        let totalSeconds = Int(max(0, timestampSeconds))
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        let timePart = String(format: "%02d-%02d-%02d", h, m, s)
        let shortId = String(UUID().uuidString.prefix(6))

        return "Frames_\(titlePart)_\(timePart)_\(shortId).png"
    }

    /// Saves a `CGImage` or `CVPixelBuffer` to the snapshots folder.
    public func saveFrame(
        pixelBuffer: CVPixelBuffer?,
        videoTitle: String,
        timestampSeconds: Double
    ) throws -> SnapshotMetadata {
        let destinationDir = try ensureDestinationDirectoryExists()
        let fileName = generateSnapshotFileName(videoTitle: videoTitle, timestampSeconds: timestampSeconds)
        let fileURL = destinationDir.appendingPathComponent(fileName)

        var imageWidth = 0
        var imageHeight = 0

        if let buffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

            imageWidth = CVPixelBufferGetWidth(buffer)
            imageHeight = CVPixelBufferGetHeight(buffer)

            let ciImage = CIImage(cvPixelBuffer: buffer)
            let context = CIContext(options: [.useSoftwareRenderer: false])
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    try pngData.write(to: fileURL, options: .atomic)
                }
            }
        } else {
            // Fallback placeholder PNG generation if no buffer active (e.g. paused on unsupported frame)
            imageWidth = 1920
            imageHeight = 1080
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: imageWidth,
                pixelsHigh: imageHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: imageWidth * 4,
                bitsPerPixel: 32
            )
            if let rep = rep, let data = rep.representation(using: .png, properties: [:]) {
                try data.write(to: fileURL, options: .atomic)
            }
        }

        let totalSeconds = Int(max(0, timestampSeconds))
        let formattedTime = String(format: "%02d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)

        return SnapshotMetadata(
            fileName: fileName,
            fileURL: fileURL,
            timestampSeconds: timestampSeconds,
            formattedTime: formattedTime,
            width: imageWidth,
            height: imageHeight
        )
    }

    /// Opens the captured file or directory in macOS Finder.
    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
