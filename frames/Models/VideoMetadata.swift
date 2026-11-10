import Foundation
import CoreGraphics

public struct VideoMetadata: Sendable, Equatable {
    public var title: String
    public var duration: Double
    public var naturalSize: CGSize
    public var frameRate: Float
    public var codec: String
    public var container: String
    public var isHDR: Bool
    public var colorPrimaries: String
    public var fileSize: Int64
    public var bitrate: Double
    public var isHardwareAccelerated: Bool
    public var decoderImplementationName: String

    public init(
        title: String = "Untitled",
        duration: Double = 0,
        naturalSize: CGSize = .zero,
        frameRate: Float = 0,
        codec: String = "Auto (Apple Silicon)",
        container: String = "",
        isHDR: Bool = false,
        colorPrimaries: String = "BT.709",
        fileSize: Int64 = 0,
        bitrate: Double = 0,
        isHardwareAccelerated: Bool = false,
        decoderImplementationName: String = ""
    ) {
        self.title = title
        self.duration = duration
        self.naturalSize = naturalSize
        self.frameRate = frameRate
        self.codec = codec
        self.container = container
        self.isHDR = isHDR
        self.colorPrimaries = colorPrimaries
        self.fileSize = fileSize
        self.bitrate = bitrate
        self.isHardwareAccelerated = isHardwareAccelerated
        self.decoderImplementationName = decoderImplementationName
    }

    public var decoderDescription: String {
        if !decoderImplementationName.isEmpty {
            return decoderImplementationName
        }
        return isHardwareAccelerated ? "VideoToolbox (Hardware ASIC)" : "Software (CPU / Emulation)"
    }

    public var resolutionDescription: String {
        guard naturalSize.width > 0 && naturalSize.height > 0 else { return "Unknown" }
        let w = Int(naturalSize.width)
        let h = Int(naturalSize.height)
        if (w >= 3840 && h >= 2160) || (w >= 2160 && h >= 3840) {
            return "4K UHD (\(w)×\(h))"
        } else if (w >= 2560 && h >= 1440) || (w >= 1440 && h >= 2560) {
            return "1440p QHD (\(w)×\(h))"
        } else if (w >= 1920 && h >= 1080) || (w >= 1080 && h >= 1920) {
            return "1080p FHD (\(w)×\(h))"
        } else if (w >= 1280 && h >= 720) {
            return "720p HD (\(w)×\(h))"
        } else {
            return "\(w)×\(h)"
        }
    }

    public var fileSizeDescription: String {
        guard fileSize > 0 else { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    public var frameRateDescription: String {
        if frameRate > 0 {
            return String(format: "%.2f fps", frameRate)
        }
        return "Unknown"
    }

    public var bitrateDescription: String {
        if bitrate > 0 {
            let mbps = bitrate / 1_000_000.0
            return String(format: "%.1f Mbps", mbps)
        }
        return "Variable"
    }
}
