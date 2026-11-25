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
