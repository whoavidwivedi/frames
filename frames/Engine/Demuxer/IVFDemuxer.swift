import Foundation

/// IVF has no seek table. Index packet headers and random access frames without loading the video payloads.
nonisolated public final class IVFDemuxer: MediaDemuxer, @unchecked Sendable {
    public let duration: Double
    public let fileSize: UInt64
    public let videoTracks: [DemuxedTrack]
    public let audioTracks: [DemuxedTrack] = []
    public let subtitleTracks: [DemuxedTrack] = []

    private struct Frame {
        let headerOffset: UInt64
        let pts: Double
        let length: Int
        let isKeyframe: Bool
    }

    private let frames: [Frame]
    private let keyframes: [Int]
    private let lock = NSLock()
    private var handle: FileHandle?
    private var position = 0

    public init(url: URL) throws {
        let source = try FileHandle(forReadingFrom: url)
        let length = try source.seekToEnd()
        try source.seek(toOffset: 0)
        guard let header = try source.read(upToCount: 32), header.count == 32,
              header.prefix(4) == Data("DKIF".utf8), header.ivfUInt16(at: 4) == 0 else { throw IVFError.header }
        let codec = String(decoding: header[8..<12], as: UTF8.self)
        let width = Int(header.ivfUInt16(at: 12)), height = Int(header.ivfUInt16(at: 14))
        let rate = header.ivfUInt32(at: 16), scale = header.ivfUInt32(at: 20)
        var offset = UInt64(header.ivfUInt16(at: 6))
        guard offset >= 32, offset < length, width > 0, height > 0, rate > 0, scale > 0 else { throw IVFError.header }
        guard codec == "VP90" || codec == "AV01" else { throw IVFError.codec }
        let tick = Double(scale) / Double(rate)

        var buffer = Data(), bufferStart = UInt64(0)
        var index: [Frame] = [], sync: [Int] = []
        var origin: UInt64?
        var configuration: IVFConfiguration?
        while offset < length {
            // Large packets need only a small prefix for indexing. Nearby small packets reuse the same read.
            let prefix = Int(min(512, length - offset))
            if offset < bufferStart || offset - bufferStart + UInt64(prefix) > UInt64(buffer.count) {
                try source.seek(toOffset: offset)
                buffer = try source.read(upToCount: 4096) ?? Data()
                bufferStart = offset
            }
            let i = Int(offset - bufferStart)
            guard prefix >= 13, i + prefix <= buffer.count, index.count < 2_000_000 else { throw IVFError.frame }
            let size = Int(buffer.ivfUInt32(at: i))
            let timestamp = buffer.ivfUInt64(at: i + 4)
            guard size > 0, size <= 64 * 1024 * 1024, UInt64(size) <= length - offset - 12 else { throw IVFError.frame }
            let bytes = buffer[(i + 12)..<(i + min(prefix, size + 12))]
            let info = try IVFConfiguration.randomAccessFrame(codec: codec, bytes: bytes)
            if let info {
                if let configuration, configuration != info { throw IVFError.codec }
                configuration = info
                sync.append(index.count)
            }
            guard configuration != nil else { throw IVFError.codec }
            let start = origin ?? timestamp
            origin = start
            guard timestamp >= start else { throw IVFError.frame }
            let pts = Double(timestamp - start) * tick
            guard pts >= (index.last?.pts ?? 0), pts < Double(Int32.max) else { throw IVFError.frame }
            index.append(Frame(headerOffset: offset, pts: pts, length: size, isKeyframe: info != nil))
            offset += 12 + UInt64(size)
        }
        guard let configuration, let last = index.last, !sync.isEmpty else { throw IVFError.frame }
        let lastInterval = index.count > 1 ? last.pts - index[index.count - 2].pts : tick
        let end = last.pts + (lastInterval > 0 ? lastInterval : tick)
        let meanInterval = end / Double(index.count)
        self.duration = end
        self.frames = index
        self.keyframes = sync
        self.fileSize = length
        self.handle = source
        self.videoTracks = [DemuxedTrack(trackNumber: 1, type: .video, codecID: codec == "VP90" ? "vp09" : "av01",
                                        codecPrivate: configuration.atom, pixelWidth: width, pixelHeight: height,
                                        defaultDurationNs: UInt64(meanInterval * 1e9), bitsPerChannel: configuration.depth,
                                        colorPrimaries: configuration.primaries, transferCharacteristics: configuration.transfer,
                                        matrixCoefficients: configuration.matrix, isDefault: true)]
    }

    public func seek(to targetSeconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        var low = 0, high = keyframes.count
        while low < high {
            let mid = low + (high - low) / 2
            if frames[keyframes[mid]].pts <= targetSeconds { low = mid + 1 } else { high = mid }
        }
        position = keyframes[max(0, low - 1)]
    }

    public func nextPacket() throws -> DemuxedPacket? {
        lock.lock()
        defer { lock.unlock() }
        guard let handle, position < frames.count else { return nil }
        let frame = frames[position]
        let offset = frame.headerOffset + 12
        try handle.seek(toOffset: offset)
        guard let bytes = try handle.read(upToCount: frame.length), bytes.count == frame.length else { throw IVFError.frame }
        position += 1
        let end = position < frames.count ? frames[position].pts : duration
        return DemuxedPacket(trackNumber: 1, pts: frame.pts, dts: frame.pts, duration: end - frame.pts,
                             isKeyframe: frame.isKeyframe, data: bytes, fileOffset: offset)
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        handle = nil
    }
}

private enum IVFError: LocalizedError {
    case header, frame, codec
    var errorDescription: String? {
        switch self {
        case .header: return "The IVF video header is incomplete or invalid."
        case .frame: return "The IVF packet index is incomplete or exceeds the supported limits."
        case .codec: return "Frames could not identify a supported VP9 or AV1 video configuration in this IVF file."
        }
    }
}

nonisolated private extension Data {
    func ivfUInt16(at i: Int) -> UInt16 { withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: i, as: UInt16.self)) } }
    func ivfUInt32(at i: Int) -> UInt32 { withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: i, as: UInt32.self)) } }
    func ivfUInt64(at i: Int) -> UInt64 { withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: i, as: UInt64.self)) } }
}

/// ISO codec configuration records passed directly to VideoToolbox. IVF itself carries neither record.
nonisolated private struct IVFConfiguration: Equatable {
    let atom: Data
    let depth: Int
    var primaries: UInt64? = nil
    var transfer: UInt64? = nil
    var matrix: UInt64? = nil

    static func randomAccessFrame(codec: String, bytes: Data.SubSequence) throws -> Self? {
        if codec == "VP90" {
            var bits = IVFBitReader(data: bytes)
            guard try bits.read(2) == 2 else { throw IVFError.frame }
            let profile = try bits.read(1) + 2 * bits.read(1)
            guard profile == 0 || profile == 2 else { throw IVFError.codec }
            guard try bits.read(1) == 0, try bits.read(1) == 0 else { return nil }
            try bits.skip(2)
            guard try bits.read(24) == 0x498342 else { throw IVFError.frame }
            let depth = try profile == 2 ? (bits.read(1) == 1 ? 12 : 10) : 8
            let colorSpace = try bits.read(3)
            guard colorSpace != 7 else { throw IVFError.codec }
            let fullRange = try bits.read(1)
            // The VP9 color space signals a set of characteristics, not a transfer function for BT.2020.
            let colors: (UInt8, UInt8, UInt8)
            switch colorSpace {
            case 1, 3: colors = (6, 6, 6)
            case 2: colors = (1, 1, 1)
            case 4: colors = (7, 7, 7)
            case 5: colors = (9, 2, 9)
            default: colors = (2, 2, 2)
            }
            let record = Data([1, 0, 0, 0, UInt8(profile), 0, UInt8(depth << 4 | 2 | fullRange),
                               colors.0, colors.1, colors.2, 0, 0])
            return Self(atom: record, depth: depth, primaries: UInt64(colors.0),
                        transfer: UInt64(colors.1), matrix: UInt64(colors.2))
        }

        var cursor = bytes.startIndex
        var sequence: (configuration: Self, still: Bool)?
        while cursor < bytes.endIndex {
            let start = cursor
            let header = bytes[cursor]
            guard header & 0x83 == 0x02 else { return nil }
            cursor += header & 4 == 0 ? 1 : 2
            var size = 0
            for byteIndex in 0..<8 {
                guard cursor < bytes.endIndex else { return nil }
                let byte = bytes[cursor]
                cursor += 1
                size |= Int(byte & 127) << (7 * byteIndex)
                if byte & 128 == 0 { break }
                guard byteIndex < 7 else { throw IVFError.frame }
            }
            switch (header >> 3) & 15 {
            case 1:
                guard size > 0, size <= bytes.endIndex - cursor else { throw IVFError.frame }
                let obu = bytes[start..<(cursor + size)]
                sequence = try av1Sequence(bytes[cursor..<(cursor + size)], obu: obu)
            case 3, 6:
                guard let sequence, size > 0, cursor < bytes.endIndex else { return nil }
                // A seek must restore sequence state and land on a shown keyframe.
                guard sequence.still || bytes[cursor] & 0xF0 == 0x10 else { return nil }
                return sequence.configuration
            default: break
            }
            guard size <= bytes.endIndex - cursor else { return nil }
            cursor += size
        }
        return nil
    }

    // AV1 sequence_header_obu, section 5.5. Read operating point zero and color_config for av1C.
    private static func av1Sequence(_ payload: Data.SubSequence, obu: Data.SubSequence) throws -> (Self, Bool) {
        var bits = IVFBitReader(data: payload)
        let profile = try bits.read(3)
        guard profile == 0 else { throw IVFError.codec } // Main profile, 4:2:0
        try bits.skip(1)
        let still = try bits.read(1) == 1
        var level = 0, tier = 0
        if still {
            level = try bits.read(5)
        } else {
            var delayBits = 0
            if try bits.read(1) == 1 {
                try bits.skip(64)
                if try bits.read(1) == 1 {
                    var zeros = 0
                    while try bits.read(1) == 0 { zeros += 1; guard zeros < 32 else { throw IVFError.header } }
                    try bits.skip(zeros)
                }
                if try bits.read(1) == 1 {
                    delayBits = try bits.read(5) + 1
                    try bits.skip(42)
                }
            }
            let hasDelay = try bits.read(1) == 1
            let count = try bits.read(5) + 1
            for i in 0..<count {
                try bits.skip(12)
                let opLevel = try bits.read(5)
                let opTier = try opLevel > 7 ? bits.read(1) : 0
                if i == 0 { level = opLevel; tier = opTier }
                if delayBits > 0, try bits.read(1) == 1 { try bits.skip(2 * delayBits + 1) }
                if hasDelay, try bits.read(1) == 1 { try bits.skip(4) }
            }
        }
        let widthBits = try bits.read(4) + 1
        let heightBits = try bits.read(4) + 1
        try bits.skip(widthBits + heightBits)
        if !still, try bits.read(1) == 1 { try bits.skip(7) }
        try bits.skip(3)
        if !still {
            try bits.skip(4)
            let orderHints = try bits.read(1) == 1
            if orderHints { try bits.skip(2) }
            let screenTools = try bits.read(1) == 1 ? 2 : bits.read(1)
            if screenTools > 0, try bits.read(1) == 0 { try bits.skip(1) }
            if orderHints { try bits.skip(3) }
        }
        try bits.skip(3)
        let highDepth = try bits.read(1), mono = try bits.read(1)
        var primaries = 2, transfer = 2, matrix = 2
        if try bits.read(1) == 1 {
            primaries = try bits.read(8)
            transfer = try bits.read(8)
            matrix = try bits.read(8)
        }
        guard !(primaries == 1 && transfer == 13 && matrix == 0) else { throw IVFError.codec }
        try bits.skip(1)
        let chromaPosition = try mono == 0 ? bits.read(2) : 0
        let flags = tier << 7 | highDepth << 6 | mono << 4 | 12 | chromaPosition
        var atom = Data([0x81, UInt8(level), UInt8(flags), 0])
        atom.append(obu)
        return (Self(atom: atom, depth: highDepth == 1 ? 10 : 8, primaries: UInt64(primaries),
                     transfer: UInt64(transfer), matrix: UInt64(matrix)), still)
    }
}

nonisolated private struct IVFBitReader {
    let data: Data.SubSequence
    var offset = 0

    mutating func skip(_ count: Int) throws {
        guard count <= data.count * 8 - offset else { throw IVFError.frame }
        offset += count
    }

    mutating func read(_ count: Int) throws -> Int {
        let start = offset
        try skip(count)
        var value = 0
        for bit in start..<offset {
            let byte = data[data.startIndex + bit / 8]
            value = value << 1 | Int((byte >> (7 - bit % 8)) & 1)
        }
        return value
    }
}
