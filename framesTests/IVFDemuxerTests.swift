import XCTest
@testable import frames

final class IVFDemuxerTests: XCTestCase {
    func testIndexedDecodeOrderAndKeyframeSeek() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        for codec in ["vp9", "av1"] {
            let source = try IVFDemuxer(url: fixtures.appendingPathComponent(codec + ".ivf"))
            defer { source.close() }
            XCTAssertEqual(source.duration, 1, accuracy: 0.001)
            for i in 0..<6 {
                let packet = try XCTUnwrap(source.nextPacket())
                XCTAssertEqual(packet.pts, Double(i) / 6, accuracy: 0.001)
                XCTAssertEqual(packet.isKeyframe, i % 3 == 0)
            }
            XCTAssertNil(try source.nextPacket())
            source.seek(to: 0.9)
            XCTAssertEqual(try source.nextPacket()?.pts, 0.5)
        }
    }
}

extension IVFDemuxerTests {
    func testMain10AndSDRRemainDistinct() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let source = try MP4Demuxer(url: fixtures.appendingPathComponent("uhd-main10.mp4"))
        defer { source.close() }
        let video = try XCTUnwrap(source.videoTracks.first)
        XCTAssertEqual(video.pixelWidth, 3840)
        XCTAssertEqual(video.pixelHeight, 2160)
        XCTAssertEqual(video.bitsPerChannel, 10)
        XCTAssertTrue(video.isHDR)
        let sdr = DemuxedTrack(trackNumber: 1, type: .video, codecID: "hvc1",
                               bitsPerChannel: 10, colorPrimaries: 9, transferCharacteristics: 1)
        XCTAssertFalse(sdr.isHDR)
    }
}
