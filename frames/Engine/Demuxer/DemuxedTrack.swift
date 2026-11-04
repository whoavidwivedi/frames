import Foundation

nonisolated public enum DemuxedTrackType: UInt64, Sendable {
    case video = 1
    case audio = 2
    case complex = 3
    case logo = 16
    case subtitle = 17
    case buttons = 18
    case control = 32
    case unknown = 0
}

/// Represents a media track extracted from a Matroska or WebM container.
nonisolated public struct DemuxedTrack: Sendable, Identifiable {
    public var id: UInt64 { trackNumber }

    public let trackNumber: UInt64
    public let trackUID: UInt64
    public let type: DemuxedTrackType
    public let codecID: String
    public let codecPrivate: Data?

    // Video Properties
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let displayWidth: Int
    public let displayHeight: Int
    public let defaultDurationNs: UInt64?
    public let bitsPerChannel: Int

    // Color & HDR Metadata
    public let colorPrimaries: UInt64?
    public let transferCharacteristics: UInt64?
    public let matrixCoefficients: UInt64?

    // Audio Properties
    public let sampleRate: Double
    public let channels: Int
    public let bitDepth: Int

    // Metadata
    public let name: String?
    public let language: String?

    public init(
        trackNumber: UInt64,
        trackUID: UInt64 = 0,
        type: DemuxedTrackType,
        codecID: String,
        codecPrivate: Data? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        displayWidth: Int = 0,
        displayHeight: Int = 0,
        defaultDurationNs: UInt64? = nil,
        bitsPerChannel: Int = 8,
        colorPrimaries: UInt64? = nil,
        transferCharacteristics: UInt64? = nil,
        matrixCoefficients: UInt64? = nil,
        sampleRate: Double = 0,
        channels: Int = 0,
        bitDepth: Int = 16,
        name: String? = nil,
        language: String? = nil
    ) {
        self.trackNumber = trackNumber
        self.trackUID = trackUID
        self.type = type
        self.codecID = codecID
        self.codecPrivate = codecPrivate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.displayWidth = displayWidth > 0 ? displayWidth : pixelWidth
        self.displayHeight = displayHeight > 0 ? displayHeight : pixelHeight
        self.defaultDurationNs = defaultDurationNs
        self.bitsPerChannel = bitsPerChannel
        self.colorPrimaries = colorPrimaries
        self.transferCharacteristics = transferCharacteristics
        self.matrixCoefficients = matrixCoefficients
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.name = name
        self.language = language
    }

    public var isVideo: Bool { type == .video }
    public var isAudio: Bool { type == .audio }
    public var isSubtitle: Bool { type == .subtitle }

    // MARK: - Codec Identification
    public var isH264: Bool {
        codecID == "V_MPEG4/ISO/AVC" || codecID == "V_MS/VFW/FOURCC"
    }

    public var isHEVC: Bool {
        codecID == "V_MPEGH/ISO/HEVC"
    }

    public var isVP9: Bool {
        codecID == "V_VP9"
    }

    public var isAV1: Bool {
        codecID == "V_AV1"
    }

    public var isProRes: Bool {
        codecID.starts(with: "V_PRORES")
    }

    public var isAAC: Bool {
        codecID == "A_AAC" || codecID.starts(with: "A_AAC")
    }

    public var isFLAC: Bool {
        codecID == "A_FLAC"
    }

    public var isOpus: Bool {
        codecID == "A_OPUS"
    }

    public var isAC3: Bool {
        codecID == "A_AC3"
    }

    public var isEAC3: Bool {
        codecID == "A_EAC3"
    }

    public var isDTS: Bool {
        codecID.starts(with: "A_DTS")
    }

    public var isTrueHD: Bool {
        codecID == "A_TRUEHD" || codecID == "A_MLP"
    }

    public var isHDR: Bool {
        // BT.2020 Primaries (9) and SMPTE ST 2084 PQ (16) or ARIB STD-B67 HLG (18)
        transferCharacteristics == 16 || transferCharacteristics == 18 || bitsPerChannel > 8
    }

    public var estimatedFPS: Double? {
        guard let defaultDurationNs = defaultDurationNs, defaultDurationNs > 0 else { return nil }
        return 1_000_000_000.0 / Double(defaultDurationNs)
    }
}
