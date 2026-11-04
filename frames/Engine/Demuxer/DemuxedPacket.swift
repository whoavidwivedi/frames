import Foundation

/// Represents a single elementary media packet extracted from a container.
nonisolated public struct DemuxedPacket: Sendable {
    public let trackNumber: UInt64
    public let pts: Double       // Presentation timestamp in seconds
    public let dts: Double       // Decode timestamp in seconds
    public let duration: Double? // Duration in seconds
    public let isKeyframe: Bool
    public let isDiscardable: Bool
    public let data: Data
    public let fileOffset: UInt64

    public init(
        trackNumber: UInt64,
        pts: Double,
        dts: Double,
        duration: Double? = nil,
        isKeyframe: Bool,
        isDiscardable: Bool = false,
        data: Data,
        fileOffset: UInt64 = 0
    ) {
        self.trackNumber = trackNumber
        self.pts = pts
        self.dts = dts
        self.duration = duration
        self.isKeyframe = isKeyframe
        self.isDiscardable = isDiscardable
        self.data = data
        self.fileOffset = fileOffset
    }
}

/// Represents a fast-seek entry from Matroska Cues.
nonisolated public struct CuePointEntry: Sendable, Comparable {
    public let timeSeconds: Double
    public let clusterPosition: UInt64
    public let trackNumber: UInt64

    public init(timeSeconds: Double, clusterPosition: UInt64, trackNumber: UInt64 = 1) {
        self.timeSeconds = timeSeconds
        self.clusterPosition = clusterPosition
        self.trackNumber = trackNumber
    }

    public static func < (lhs: CuePointEntry, rhs: CuePointEntry) -> Bool {
        lhs.timeSeconds < rhs.timeSeconds
    }
}
