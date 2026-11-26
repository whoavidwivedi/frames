import AVFoundation
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
        // This encoder emitted Main 10 with an unspecified transfer and no colr atom.
        XCTAssertFalse(video.isHDR)
        for transfer: UInt64 in [16, 18] {
            let hdr = DemuxedTrack(trackNumber: 1, type: .video, codecID: "hvc1",
                                   bitsPerChannel: 10, colorPrimaries: 9, transferCharacteristics: transfer)
            XCTAssertTrue(hdr.isHDR)
        }
        let sdr = DemuxedTrack(trackNumber: 1, type: .video, codecID: "hvc1",
                               bitsPerChannel: 10, colorPrimaries: 9, transferCharacteristics: 1)
        XCTAssertFalse(sdr.isHDR)
    }
}

final class StereoPCMTests: XCTestCase {
    func testChannelPlacementAcrossSampleFormats() throws {
        for (codec, width, big, floating) in [
            ("SOWT", 16, false, false), ("TWOS", 16, true, false),
            ("A_PCM/INT/LIT", 24, false, false), ("A_PCM/INT/BIG", 24, true, false),
            ("A_PCM/INT/LIT", 32, false, false), ("FL32", 32, true, true),
            ("A_PCM/FLOAT/IEEE", 32, false, true), ("A_PCM/FLOAT/IEEE", 64, false, true)
        ] {
            let track = DemuxedTrack(trackNumber: 1, type: .audio, codecID: codec, sampleRate: 48000, channels: 2, bitDepth: width)
            let decoder = try XCTUnwrap(NativeAudioDecoder(track: track))
            let signals = [0.5, 0, 0, -0.5, 0.25, 0.25]
            var bytes = Data()
            for level in signals {
                let bits: UInt64
                if floating { bits = width == 32 ? UInt64(Float(level).bitPattern) : level.bitPattern }
                else { bits = UInt64(bitPattern: Int64(level * pow(2, Double(width-1)))) }
                for i in 0..<width/8 {
                    let index = big ? width/8-1-i : i
                    bytes.append(UInt8(truncatingIfNeeded: bits >> (8*index)))
                }
            }
            let packet = DemuxedPacket(trackNumber: 1, pts: 0, dts: 0, isKeyframe: true, data: bytes)
            let pcm = try XCTUnwrap(decoder.decode(packet: packet))
            for i in signals.indices { XCTAssertEqual(pcm.floatChannelData![i % 2][i / 2], Float(signals[i]), "\(codec) at sample \(i)") }
        }
    }
}
