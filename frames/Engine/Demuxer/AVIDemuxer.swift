import Foundation

/// Independent JPEG frames and PCM audio in RIFF AVI. Only headers are touched
/// while indexing. Per-stream cursors also handle non-interleaved recordings.
nonisolated final class AVIDemuxer: MediaDemuxer, @unchecked Sendable {
    enum ReadError: LocalizedError {
        case malformed, unsupported, indexLimit

        var errorDescription: String? {
            switch self {
            case .malformed: return "The AVI file has a truncated or invalid chunk."
            case .unsupported: return "Frames’ AVI reader supports Motion JPEG video and PCM audio."
            case .indexLimit: return "The AVI file exceeds the native reader’s packet index limit."
            }
        }
    }

    private struct Sample {
        let range: Range<Int>
        let pts: Double
        let duration: Double
    }

    private struct Stream {
        let track: DemuxedTrack
        let start: Double
        let secondsPerUnit: Double
        let blockAlign: Int
        var units = 0
        var samples: [Sample] = []
        var cursor = 0

        var endTime: Double { start + Double(units) * secondsPerUnit }
    }

    let duration: Double
    let fileSize: UInt64
    let videoTracks: [DemuxedTrack]
    let audioTracks: [DemuxedTrack]
    let subtitleTracks: [DemuxedTrack] = []

    private let lock = NSLock()
    private var file: Data?
    private var streams: [Stream]

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let tracks = try data.withUnsafeBytes { bytes in
            var reader = Reader(bytes: bytes)
            return try reader.index()
        }
        file = data
        fileSize = UInt64(data.count)
        streams = tracks
        videoTracks = tracks.map(\.track).filter(\.isVideo)
        audioTracks = tracks.map(\.track).filter(\.isAudio)
        duration = tracks.map(\.endTime).max() ?? 0
    }

    func close() {
        lock.withLock {
            file = nil
            streams.removeAll()
        }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        lock.withLock {
            for i in streams.indices {
                let samples = streams[i].samples
                var low = 0
                var high = samples.count
                while low < high {
                    let mid = low + (high - low) / 2
                    if samples[mid].pts <= seconds { low = mid + 1 } else { high = mid }
                }
                streams[i].cursor = seconds >= streams[i].endTime ? samples.count : max(0, low - 1)
            }
        }
    }

    func nextPacket() throws -> DemuxedPacket? {
        lock.withLock {
            guard let file else { return nil }
            var selected: Int?
            var earliest = Double.infinity
            for i in streams.indices where streams[i].cursor < streams[i].samples.count {
                let time = streams[i].samples[streams[i].cursor].pts
                if time < earliest {
                    selected = i
                    earliest = time
                }
            }
            guard let i = selected else { return nil }
            let sample = streams[i].samples[streams[i].cursor]
            streams[i].cursor += 1
            return DemuxedPacket(trackNumber: streams[i].track.trackNumber, pts: sample.pts,
                                 dts: sample.pts, duration: sample.duration, isKeyframe: true,
                                 data: file.subdata(in: sample.range), fileOffset: UInt64(sample.range.lowerBound))
        }
    }

    private struct Reader {
        let bytes: UnsafeRawBufferPointer
        var streams: [Stream] = []
        var streamCount = 0
        var packetCount = 0

        func u16(_ offset: Int) -> Int {
            Int(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
        }

        func u32(_ offset: Int) -> Int {
            Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
        }

        func id(_ offset: Int) -> FourCC {
            FourCC(UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
        }

        // RIFF lengths exclude both the eight-byte header and the WORD padding.
        func chunk(at offset: Int, end: Int) throws -> (id: FourCC, payload: Range<Int>, next: Int) {
            guard end - offset >= 8 else { throw ReadError.malformed }
            let start = offset + 8
            let size = u32(offset + 4)
            let padded = size + size % 2
            guard padded <= end - start else { throw ReadError.malformed }
            return (id(offset), start..<(start + size), start + padded)
        }

        mutating func index() throws -> [Stream] {
            var offset = 0
            while offset < bytes.count {
                let riff = try chunk(at: offset, end: bytes.count)
                guard riff.id == "RIFF", riff.payload.count >= 4,
                      id(riff.payload.lowerBound) == (offset == 0 ? "AVI " : "AVIX") else { throw ReadError.malformed }
                var cursor = riff.payload.lowerBound + 4
                while cursor < riff.payload.upperBound {
                    let part = try chunk(at: cursor, end: riff.payload.upperBound)
                    if part.id == "LIST", part.payload.count >= 4 {
                        let kind = id(part.payload.lowerBound)
                        let children = part.payload.dropFirst(4)
                        if kind == "hdrl" { try readHeader(children) }
                        if kind == "movi" { try readMovie(children, allowRecords: true) }
                    }
                    cursor = part.next
                }
                offset = riff.next
            }
            guard streams.contains(where: { $0.track.isVideo && !$0.samples.isEmpty }) else { throw ReadError.unsupported }
            return streams.filter { !$0.samples.isEmpty }
        }

        mutating func readHeader(_ range: Range<Int>) throws {
            var cursor = range.lowerBound
            while cursor < range.upperBound {
                let list = try chunk(at: cursor, end: range.upperBound)
                if list.id == "LIST", list.payload.count >= 4, id(list.payload.lowerBound) == "strl" {
                    guard streamCount < 100 else { throw ReadError.unsupported }
                    let number = UInt64(streamCount)
                    streamCount += 1
                    if let stream = try readStream(list.payload.dropFirst(4), number: number) { streams.append(stream) }
                }
                cursor = list.next
            }
        }

        func readStream(_ range: Range<Int>, number: UInt64) throws -> Stream? {
            var header: Range<Int>?
            var format: Range<Int>?
            var cursor = range.lowerBound
            while cursor < range.upperBound {
                let part = try chunk(at: cursor, end: range.upperBound)
                if part.id == "strh" { header = part.payload }
                if part.id == "strf" { format = part.payload }
                cursor = part.next
            }
            guard let header, header.count >= 48 else { throw ReadError.malformed }
            let h = header.lowerBound
            let kind = id(h)
            guard kind == "vids" || kind == "auds" else { return nil }
            guard let format, u32(h + 20) > 0, u32(h + 24) > 0 else { throw ReadError.malformed }
            let f = format.lowerBound
            let tick = Double(u32(h + 20)) / Double(u32(h + 24))
            let start = Double(u32(h + 28)) * tick
            if kind == "vids" {
                guard format.count >= 40, u32(f) >= 40 else { throw ReadError.malformed }
                let codec = id(f + 16).description.uppercased()
                guard ["MJPG", "JPEG", "DMB1"].contains(codec) else { throw ReadError.unsupported }
                let width = u32(f + 4)
                let height = u32(f + 8)
                guard (1...32768).contains(width), (1...32768).contains(height) else { throw ReadError.unsupported }
                let track = DemuxedTrack(trackNumber: number, type: .video, codecID: "jpeg",
                                         pixelWidth: width, pixelHeight: height,
                                         defaultDurationNs: UInt64((tick * 1e9).rounded()))
                return Stream(track: track, start: start, secondsPerUnit: tick, blockAlign: 0)
            }
            guard format.count >= 16 else { throw ReadError.malformed }
            let tag = u16(f)
            let channels = u16(f + 2)
            let rate = u32(f + 4)
            let align = u16(f + 12)
            let bits = u16(f + 14)
            guard (tag == 1 && [16, 24, 32].contains(bits)) || (tag == 3 && bits == 32),
                  (1...32).contains(channels), (1...768000).contains(rate), align == channels * (bits / 8)
            else { throw ReadError.unsupported }
            let track = DemuxedTrack(trackNumber: number, type: .audio, codecID: tag == 3 ? "A_PCM/FLOAT/IEEE" : "A_PCM/INT/LIT",
                                     sampleRate: Double(rate), channels: channels, bitDepth: bits)
            return Stream(track: track, start: start, secondsPerUnit: 1.0 / Double(rate), blockAlign: align)
        }

        mutating func readMovie(_ range: Range<Int>, allowRecords: Bool) throws {
            var cursor = range.lowerBound
            while cursor < range.upperBound {
                let part = try chunk(at: cursor, end: range.upperBound)
                if part.id == "LIST", allowRecords, part.payload.count >= 4, id(part.payload.lowerBound) == "rec " {
                    try readMovie(part.payload.dropFirst(4), allowRecords: false)
                } else {
                    let tens = Int(bytes[cursor]) - 48
                    let ones = Int(bytes[cursor + 1]) - 48
                    if (0...9).contains(tens), (0...9).contains(ones),
                       let i = streams.firstIndex(where: { $0.track.trackNumber == UInt64(tens * 10 + ones) }) {
                        let tag = part.id.value & 0xffff
                        let isVideo = streams[i].track.isVideo
                        if (isVideo && (tag == 0x6463 || tag == 0x6462)) || (!isVideo && tag == 0x7762) {
                            guard packetCount < 2_000_000, part.payload.count <= 128 * 1024 * 1024 else { throw ReadError.indexLimit }
                            let align = streams[i].blockAlign
                            guard isVideo || part.payload.count.isMultiple(of: align) else { throw ReadError.malformed }
                            let units = isVideo ? 1 : part.payload.count / align
                            if !part.payload.isEmpty {
                                let sample = Sample(range: part.payload, pts: streams[i].endTime,
                                                    duration: Double(units) * streams[i].secondsPerUnit)
                                streams[i].samples.append(sample)
                                packetCount += 1
                            }
                            // Empty video chunks repeat the previous frame for one tick.
                            streams[i].units += units
                        }
                    }
                }
                cursor = part.next
            }
        }
    }
}
