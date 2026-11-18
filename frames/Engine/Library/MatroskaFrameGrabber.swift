import CoreGraphics
import CoreVideo
import Foundation

nonisolated enum MatroskaFrameGrabber {
    private static let maxPacketsPerAttempt = 600
    private static let maxDecodeFeeds = 24

    static func grabFrame(from demuxer: MatroskaDemuxer, at targetSeconds: Double) -> CGImage? {
        guard let track = demuxer.videoTracks.first else { return nil }
        let box = PixelBufferBox()
        guard let decoder = VideoToolboxDecoder(track: track, onFrame: { box.store($0.pixelBuffer) }) else {
            return nil
        }
        defer { decoder.invalidate() }

        demuxer.seek(to: targetSeconds)
        guard let (keyframe, isExact) = findKeyframe(in: demuxer, track: track, target: targetSeconds) else {
            return nil
        }

        _ = decoder.decode(packet: keyframe)
        decoder.waitForFrames()
        if let buffer = box.take() {
            return ThumbnailImaging.image(from: buffer)
        }
        guard isExact else { return nil }
        return decodeFollowingPackets(from: demuxer, track: track, decoder: decoder, box: box)
    }

    private static func findKeyframe(
        in demuxer: MatroskaDemuxer,
        track: DemuxedTrack,
        target: Double
    ) -> (packet: DemuxedPacket, isExact: Bool)? {
        var fallback: DemuxedPacket?
        for _ in 0 ..< maxPacketsPerAttempt {
            guard let packet = try? demuxer.nextPacket() else { break }
            guard packet.trackNumber == track.trackNumber, packet.isKeyframe else { continue }
            if packet.pts >= target - 0.001 {
                return (packet, true)
            }
            fallback = packet
        }
        return fallback.map { ($0, false) }
    }

    private static func decodeFollowingPackets(
        from demuxer: MatroskaDemuxer,
        track: DemuxedTrack,
        decoder: VideoToolboxDecoder,
        box: PixelBufferBox
    ) -> CGImage? {
        for _ in 1 ..< maxDecodeFeeds {
            guard let packet = try? demuxer.nextPacket() else { break }
            guard packet.trackNumber == track.trackNumber else { continue }
            _ = decoder.decode(packet: packet)
            decoder.waitForFrames()
            if let buffer = box.take() {
                return ThumbnailImaging.image(from: buffer)
            }
        }
        return nil
    }
}

private final nonisolated class PixelBufferBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    func store(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        if buffer == nil {
            buffer = pixelBuffer
        }
        lock.unlock()
    }

    func take() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
