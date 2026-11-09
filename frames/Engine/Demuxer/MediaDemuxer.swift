import Foundation

/// Unified media container demuxer interface for streaming playback, scrubbing, and frame extraction.
nonisolated public protocol MediaDemuxer: AnyObject, Sendable {
    var duration: Double { get }
    var fileSize: UInt64 { get }
    var videoTracks: [DemuxedTrack] { get }
    var audioTracks: [DemuxedTrack] { get }
    var subtitleTracks: [DemuxedTrack] { get }
    func seek(to targetSeconds: Double)
    func nextPacket() throws -> DemuxedPacket?
    func extractSubtitleCues(for targetTrackNumber: UInt64) -> [SubtitleCue]
    @discardableResult
    func adviseBurstPrefetch(offset: UInt64, length: Int) -> Bool
    func close()
}

extension MediaDemuxer {
    public func extractSubtitleCues(for targetTrackNumber: UInt64) -> [SubtitleCue] {
        return []
    }

    @discardableResult
    public func adviseBurstPrefetch(offset: UInt64, length: Int = 16 * 1024 * 1024) -> Bool {
        return false
    }
}
