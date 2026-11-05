import Foundation

/// Matroska (RFC 8794) and WebM Element Identifiers.
nonisolated public enum EBMLID: UInt64, Sendable {
    // MARK: - EBML Header
    case ebml = 0x1A45DFA3
    case ebmlVersion = 0x4286
    case ebmlReadVersion = 0x42F7
    case ebmlMaxIDLength = 0x42F2
    case ebmlMaxSizeLength = 0x42F3
    case docType = 0x4282
    case docTypeVersion = 0x4287
    case docTypeReadVersion = 0x4285

    // MARK: - Global Elements
    case void = 0xEC
    case crc32 = 0xBF

    // MARK: - Segment & Navigation
    case segment = 0x18538067
    case seekHead = 0x114D9B74
    case seek = 0x4DBB
    case seekID = 0x53AB
    case seekPosition = 0x53AC

    // MARK: - Segment Info
    case info = 0x1549A966
    case timestampScale = 0x2AD7B1 // Default 1,000,000ns = 1ms
    case duration = 0x4489
    case dateUTC = 0x4461
    case title = 0x7BA9
    case muxingApp = 0x4D80
    case writingApp = 0x5741

    // MARK: - Tracks
    case tracks = 0x1654AE6B
    case trackEntry = 0xAE
    case trackNumber = 0xD7
    case trackUID = 0x73C5
    case trackType = 0x83
    case flagEnabled = 0xB9
    case flagDefault = 0x88
    case flagForced = 0x55AA
    case flagLacing = 0x9C
    case defaultDuration = 0x23E383 // Nanoseconds per frame
    case name = 0x536E
    case language = 0x22B59C
    case languageBCP47 = 0x22B59D
    case codecID = 0x86
    case codecPrivate = 0x63A2
    case codecName = 0x258688
    case codecDelay = 0x56AA
    case seekPreRoll = 0x56BB

    // MARK: - Video Details
    case video = 0xE0
    case flagInterlaced = 0x9A
    case pixelWidth = 0xB0
    case pixelHeight = 0xBA
    case pixelCropBottom = 0x54AA
    case pixelCropTop = 0x54BB
    case pixelCropLeft = 0x54CC
    case pixelCropRight = 0x54DD
    case displayWidth = 0x54B0
    case displayHeight = 0x54BA
    case displayUnit = 0x54B2
    case colour = 0x55B0
    case matrixCoefficients = 0x55B1
    case bitsPerChannel = 0x55B2
    case transferCharacteristics = 0x55BA
    case primaries = 0x55BB
    case maxCLL = 0x55BC
    case maxFALL = 0x55BD
    case masteringMetadata = 0x55D0

    // MARK: - Audio Details
    case audio = 0xE1
    case samplingFrequency = 0xB5
    case outputSamplingFrequency = 0x78B5
    case channels = 0x9F
    case bitDepth = 0x6264

    // MARK: - Cues (Seeking Index)
    case cues = 0x1C53BB6B
    case cuePoint = 0xBB
    case cueTime = 0xB3
    case cueTrackPositions = 0xB7
    case cueTrack = 0xF7
    case cueClusterPosition = 0xF1
    case cueBlockNumber = 0x5378

    // MARK: - Clusters & Blocks
    case cluster = 0x1F43B675
    case timestamp = 0xE7 // Cluster timestamp
    case position = 0xA7
    case prevSize = 0xAB
    case simpleBlock = 0xA3
    case blockGroup = 0xA0
    case block = 0xA1
    case blockDuration = 0x9B
    case referenceBlock = 0xFB

    /// Identifies whether this element ID is a Master Element containing child elements.
    public var isMasterElement: Bool {
        switch self {
        case .ebml, .segment, .seekHead, .seek, .info, .tracks, .trackEntry,
             .video, .audio, .colour, .masteringMetadata, .cues, .cuePoint,
             .cueTrackPositions, .cluster, .blockGroup:
            return true
        default:
            return false
        }
    }
}
