//
//  MP4Demuxer.swift
//  frames
//
//  Ultra-high performance pure Swift zero-dependency ISO Base Media File Format
//  (ISO BMFF / QuickTime container) demuxer engineered for Apple Silicon.
//  Extracts video, audio, and subtitle elementary streams with zero memory copies,
//  sub-millisecond O(log N) keyframe seeking, and native VideoToolbox / CoreAudio bridging.
//

import Foundation
import Darwin

// MARK: - FourCC Box Identifier

nonisolated public struct FourCC: Equatable, Hashable, CustomStringConvertible, ExpressibleByStringLiteral, Sendable {
    public let value: UInt32

    public init(_ value: UInt32) {
        self.value = value
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(_ string: String) {
        var val: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            val = (val << 8) | UInt32(byte)
        }
        self.value = val
    }

    public var description: String {
        let b1 = Character(UnicodeScalar((value >> 24) & 0xFF) ?? "?")
        let b2 = Character(UnicodeScalar((value >> 16) & 0xFF) ?? "?")
        let b3 = Character(UnicodeScalar((value >> 8) & 0xFF) ?? "?")
        let b4 = Character(UnicodeScalar(value & 0xFF) ?? "?")
        return "\(b1)\(b2)\(b3)\(b4)"
    }

    // Top-Level Boxes
    nonisolated public static let ftyp: FourCC = "ftyp"
    nonisolated public static let moov: FourCC = "moov"
    nonisolated public static let mdat: FourCC = "mdat"
    nonisolated public static let free: FourCC = "free"
    nonisolated public static let skip: FourCC = "skip"
    nonisolated public static let wide: FourCC = "wide"

    // Moov Hierarchy
    nonisolated public static let mvhd: FourCC = "mvhd"
    nonisolated public static let trak: FourCC = "trak"
    nonisolated public static let tkhd: FourCC = "tkhd"
    nonisolated public static let edts: FourCC = "edts"
    nonisolated public static let elst: FourCC = "elst"
    nonisolated public static let mdia: FourCC = "mdia"
    nonisolated public static let mdhd: FourCC = "mdhd"
    nonisolated public static let hdlr: FourCC = "hdlr"
    nonisolated public static let minf: FourCC = "minf"
    nonisolated public static let vmhd: FourCC = "vmhd"
    nonisolated public static let smhd: FourCC = "smhd"
    nonisolated public static let dinf: FourCC = "dinf"
    nonisolated public static let stbl: FourCC = "stbl"

    // Sample Table Hierarchy
    nonisolated public static let stsd: FourCC = "stsd"
    nonisolated public static let stts: FourCC = "stts"
    nonisolated public static let ctts: FourCC = "ctts"
    nonisolated public static let stss: FourCC = "stss"
    nonisolated public static let stsz: FourCC = "stsz"
    nonisolated public static let stsc: FourCC = "stsc"
    nonisolated public static let stco: FourCC = "stco"
    nonisolated public static let co64: FourCC = "co64"

    // Handlers
    nonisolated public static let vide: FourCC = "vide"
    nonisolated public static let soun: FourCC = "soun"
    nonisolated public static let subt: FourCC = "subt"
    nonisolated public static let text: FourCC = "text"
    nonisolated public static let sbtl: FourCC = "sbtl"
    nonisolated public static let clcp: FourCC = "clcp"

    // Video Codecs
    nonisolated public static let avc1: FourCC = "avc1"
    nonisolated public static let avc3: FourCC = "avc3"
    nonisolated public static let hvc1: FourCC = "hvc1"
    nonisolated public static let hev1: FourCC = "hev1"
    nonisolated public static let av01: FourCC = "av01"
    nonisolated public static let vp09: FourCC = "vp09"
    nonisolated public static let apch: FourCC = "apch"
    nonisolated public static let apcn: FourCC = "apcn"
    nonisolated public static let apcs: FourCC = "apcs"
    nonisolated public static let apco: FourCC = "apco"
    nonisolated public static let ap4h: FourCC = "ap4h"
    nonisolated public static let ap4x: FourCC = "ap4x"

    // Audio Codecs
    nonisolated public static let mp4a: FourCC = "mp4a"
    nonisolated public static let ac3: FourCC  = "ac-3"
    nonisolated public static let ec3: FourCC  = "ec-3"
    nonisolated public static let opus: FourCC = "Opus"
    nonisolated public static let alac: FourCC = "alac"
    nonisolated public static let flac: FourCC = "flac"
    nonisolated public static let fLaC: FourCC = "fLaC"

    // Extradata & Color Boxes
    nonisolated public static let avcC: FourCC = "avcC"
    nonisolated public static let hvcC: FourCC = "hvcC"
    nonisolated public static let av1C: FourCC = "av1C"
    nonisolated public static let vpcC: FourCC = "vpcC"
    nonisolated public static let esds: FourCC = "esds"
    nonisolated public static let dac3: FourCC = "dac3"
    nonisolated public static let dec3: FourCC = "dec3"
    nonisolated public static let dOps: FourCC = "dOps"
    nonisolated public static let dfLa: FourCC = "dfLa"
    nonisolated public static let colr: FourCC = "colr"
    nonisolated public static let nclx: FourCC = "nclx"

    // Subtitle formats
    nonisolated public static let tx3g: FourCC = "tx3g"
    nonisolated public static let wvtt: FourCC = "wvtt"
}

// MARK: - MP4 Demuxer Errors

public enum MP4DemuxerError: Error, CustomStringConvertible, Sendable {
    case fileOpenFailed(String)
    case invalidBoxHeader(offset: UInt64)
    case missingMoovBox
    case corruptedBox(FourCC)
    case noValidTracks
    case readFailed(offset: UInt64, expected: Int, actual: Int)
    case unexpectedEOF

    public var description: String {
        switch self {
        case .fileOpenFailed(let reason):
            return "MP4Demuxer: Failed to open file: \(reason)"
        case .invalidBoxHeader(let offset):
            return "MP4Demuxer: Invalid box header at offset \(offset)"
        case .missingMoovBox:
            return "MP4Demuxer: Missing 'moov' box in media container"
        case .corruptedBox(let fourCC):
            return "MP4Demuxer: Corrupted box '\(fourCC)'"
        case .noValidTracks:
            return "MP4Demuxer: No valid video, audio, or subtitle tracks found"
        case .readFailed(let offset, let expected, let actual):
            return "MP4Demuxer: Read failed at offset \(offset), expected \(expected) bytes, got \(actual)"
        case .unexpectedEOF:
            return "MP4Demuxer: Unexpected end of file"
        }
    }
}

// MARK: - Internal Sample Model

public struct MP4Sample: Sendable {
    public let sampleIndex: Int
    public let fileOffset: UInt64
    public let size: UInt32
    public let dts: Int64
    public let pts: Int64
    public let duration: UInt32
    public let ptsSeconds: Double
    public let dtsSeconds: Double
    public let durationSeconds: Double
    public let isKeyframe: Bool
}

// MARK: - Internal Track Playback State

nonisolated private final class MP4TrackPlaybackState: @unchecked Sendable {
    let track: DemuxedTrack
    let timescale: UInt32
    let samples: [MP4Sample]
    let keyframeIndices: [Int] // 0-based indices of sync samples
    var cursor: Int = 0

    init(track: DemuxedTrack, timescale: UInt32, samples: [MP4Sample], keyframeIndices: [Int]) {
        self.track = track
        self.timescale = timescale
        self.samples = samples
        self.keyframeIndices = keyframeIndices
    }

    var currentSample: MP4Sample? {
        guard cursor < samples.count else { return nil }
        return samples[cursor]
    }

    func advance() {
        cursor += 1
    }

    func seek(to targetSeconds: Double) -> Double {
        guard !samples.isEmpty else {
            cursor = 0
            return 0.0
        }

        if keyframeIndices.isEmpty {
            // Intra-only track or no keyframe table: binary search all samples
            var low = 0
            var high = samples.count - 1
            var bestIdx = 0
            while low <= high {
                let mid = (low + high) / 2
                if samples[mid].ptsSeconds <= targetSeconds {
                    bestIdx = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            cursor = bestIdx
            return samples[bestIdx].ptsSeconds
        }

        // Binary search sync sample keyframe table: O(log N)
        var low = 0
        var high = keyframeIndices.count - 1
        var bestKeyframeIndex = keyframeIndices[0]

        while low <= high {
            let mid = (low + high) / 2
            let sIdx = keyframeIndices[mid]
            let sPTS = samples[sIdx].ptsSeconds
            if sPTS <= targetSeconds {
                bestKeyframeIndex = sIdx
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        cursor = bestKeyframeIndex
        return samples[bestKeyframeIndex].ptsSeconds
    }

    func seekToNearestSample(targetPTS: Double) {
        guard !samples.isEmpty else {
            cursor = 0
            return
        }
        var low = 0
        var high = samples.count - 1
        var bestIdx = 0
        while low <= high {
            let mid = (low + high) / 2
            if samples[mid].ptsSeconds <= targetPTS {
                bestIdx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        cursor = bestIdx
    }
}

// MARK: - Zero-Copy Memory Mapped Region

nonisolated public final class MappedFileRegion: @unchecked Sendable {
    public let pointer: UnsafeMutableRawPointer
    public let size: Int

    public init?(fd: Int32, size: UInt64) {
        guard size > 0, size <= UInt64(Int.max) else { return nil }
        let ptr = mmap(nil, Int(size), PROT_READ, MAP_SHARED, fd, 0)
        guard ptr != MAP_FAILED, let validPtr = ptr else { return nil }
        self.pointer = validPtr
        self.size = Int(size)
        // Sequential access advisory to optimize hardware memory bus and unified cache prefetching
        madvise(validPtr, Int(size), MADV_SEQUENTIAL)
    }

    deinit {
        munmap(pointer, size)
    }

    /// Advises the Darwin kernel VM subsystem to burst-read the given range into physical page cache
    /// using MADV_WILLNEED, allowing PCIe NVMe storage controllers to return to ASPM L1.2 low-power sleep.
    @discardableResult
    public func adviseBurst(offset: UInt64, length: Int) -> Bool {
        guard offset < UInt64(size), length > 0 else { return false }
        let pageSize = Int(vm_page_size)
        let pageMask = pageSize - 1
        let alignedOffset = Int(offset) & ~pageMask
        let offsetDiff = Int(offset) - alignedOffset
        let unalignedLength = min(length + offsetDiff, size - alignedOffset)
        let alignedLength = min(((unalignedLength + pageMask) / pageSize) * pageSize, ((size - alignedOffset + pageMask) / pageSize) * pageSize)
        guard alignedLength > 0 else { return false }
        let targetPtr = pointer.advanced(by: alignedOffset)
        return madvise(targetPtr, alignedLength, MADV_WILLNEED) == 0
    }
}

// MARK: - Native MP4 / MOV Demuxer

nonisolated public final class MP4Demuxer: @unchecked Sendable, MediaDemuxer {

    public static let burstChunkSize: Int = 16 * 1024 * 1024 // 16MB burst chunk (16MB - 32MB)
    public private(set) var burstPrefetchCount: Int = 0
    private var lastBurstPrefetchOffset: UInt64 = UInt64.max

    public let fileURL: URL?
    public let fileSize: UInt64
    private var fileDescriptor: Int32 = -1
    private let inMemoryData: Data?
    public private(set) var mappedRegion: MappedFileRegion?

    @discardableResult
    public func adviseBurstPrefetch(offset: UInt64, length: Int = MP4Demuxer.burstChunkSize) -> Bool {
        guard let region = mappedRegion else { return false }
        let success = region.adviseBurst(offset: offset, length: length)
        if success {
            burstPrefetchCount += 1
            lastBurstPrefetchOffset = offset
        }
        return success
    }

    public private(set) var majorBrand: FourCC = .ftyp
    public private(set) var minorVersion: UInt32 = 0
    public private(set) var compatibleBrands: [FourCC] = []

    public private(set) var movieTimescale: UInt32 = 1000
    public private(set) var movieDurationUnits: UInt64 = 0
    public private(set) var duration: Double = 0.0

    public private(set) var tracks: [UInt64: DemuxedTrack] = [:]
    private var trackPlaybackStates: [UInt64: MP4TrackPlaybackState] = [:]
    private let ioLock = NSLock()

    // MARK: - Track Categorization

    public var videoTracks: [DemuxedTrack] {
        tracks.values
            .filter { $0.isVideo }
            .sorted { (t1, t2) -> Bool in
                let t1IsCover = t1.codecID.contains("JPEG") || t1.codecID.contains("PNG") || (t1.pixelWidth > 0 && t1.pixelWidth <= 320 && t1.pixelHeight <= 240)
                let t2IsCover = t2.codecID.contains("JPEG") || t2.codecID.contains("PNG") || (t2.pixelWidth > 0 && t2.pixelWidth <= 320 && t2.pixelHeight <= 240)
                if t1IsCover != t2IsCover {
                    return !t1IsCover
                }
                return (t1.pixelWidth * t1.pixelHeight) > (t2.pixelWidth * t2.pixelHeight)
            }
    }

    public var audioTracks: [DemuxedTrack] {
        tracks.values.filter { $0.isAudio }.sorted { $0.trackNumber < $1.trackNumber }
    }

    public var subtitleTracks: [DemuxedTrack] {
        tracks.values.filter { $0.isSubtitle }.sorted { $0.trackNumber < $1.trackNumber }
    }

    public var sampleCount: Int {
        ioLock.lock()
        defer { ioLock.unlock() }
        return trackPlaybackStates.values.reduce(0) { $0 + $1.samples.count }
    }

    public func sampleCount(for trackNumber: UInt64) -> Int {
        ioLock.lock()
        defer { ioLock.unlock() }
        return trackPlaybackStates[trackNumber]?.samples.count ?? 0
    }

    public func keyframeIndices(for trackNumber: UInt64) -> [Int] {
        ioLock.lock()
        defer { ioLock.unlock() }
        return trackPlaybackStates[trackNumber]?.keyframeIndices ?? []
    }

    // MARK: - Initializers

    public init(url: URL) throws {
        self.fileURL = url
        self.inMemoryData = nil

        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else {
            throw MP4DemuxerError.fileOpenFailed(String(cString: strerror(errno)))
        }
        self.fileDescriptor = fd

        var st = stat()
        if fstat(fd, &st) == 0 {
            self.fileSize = UInt64(max(0, st.st_size))
        } else {
            self.fileSize = 0
        }

        // Establish hardware zero-copy mmap backing across file descriptor
        if self.fileSize > 0 {
            self.mappedRegion = MappedFileRegion(fd: fd, size: self.fileSize)
        }

        try parseContainer()
    }

    public init(data: Data) throws {
        self.fileURL = nil
        self.inMemoryData = data
        self.fileDescriptor = -1
        self.fileSize = UInt64(data.count)

        try parseContainer()
    }

    deinit {
        close()
    }

    public func close() {
        ioLock.lock()
        defer { ioLock.unlock() }
        self.mappedRegion = nil
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // MARK: - Top-Level Container Parsing

    private func parseContainer() throws {
        var offset: UInt64 = 0
        var foundMoov = false

        while offset + 8 <= fileSize {
            let header = try readRawBytes(offset: offset, count: 8)
            let size32 = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
            let type32 = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian }
            let boxType = FourCC(type32)

            var boxSize: UInt64 = UInt64(size32)
            var headerSize: UInt64 = 8

            if size32 == 1 {
                guard offset + 16 <= fileSize else { break }
                let largeData = try readRawBytes(offset: offset + 8, count: 8)
                boxSize = largeData.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
                headerSize = 16
            } else if size32 == 0 {
                // Box extends to end of file
                boxSize = fileSize - offset
            }

            guard boxSize >= headerSize else {
                throw MP4DemuxerError.invalidBoxHeader(offset: offset)
            }

            let payloadOffset = offset + headerSize
            let payloadSize = boxSize - headerSize

            switch boxType {
            case .ftyp:
                try parseFtyp(offset: payloadOffset, size: payloadSize)
            case .moov:
                try parseMoov(offset: payloadOffset, size: payloadSize)
                foundMoov = true
            case .mdat, .free, .skip, .wide:
                // Fast-skip media payloads and free space without loading into memory
                break
            default:
                break
            }

            let (nextOffset, overflow) = offset.addingReportingOverflow(boxSize)
            guard !overflow else {
                throw MP4DemuxerError.invalidBoxHeader(offset: offset)
            }
            offset = nextOffset
        }

        guard foundMoov else {
            throw MP4DemuxerError.missingMoovBox
        }

        guard !tracks.isEmpty else {
            throw MP4DemuxerError.noValidTracks
        }
    }

    // MARK: - Box Parsers

    private func parseFtyp(offset: UInt64, size: UInt64) throws {
        guard size >= 8 else { return }
        let data = try readRawBytes(offset: offset, count: Int(min(size, 1024)))
        guard data.count >= 8 else { return }

        let mb = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        let mv = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian }
        self.majorBrand = FourCC(mb)
        self.minorVersion = mv

        var brands: [FourCC] = []
        var pos = 8
        while pos + 4 <= data.count {
            let brandVal = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: pos, as: UInt32.self).bigEndian }
            brands.append(FourCC(brandVal))
            pos += 4
        }
        self.compatibleBrands = brands
    }

    private func parseMoov(offset: UInt64, size: UInt64) throws {
        // moov metadata box is loaded into memory for recursive box traversal
        guard size <= 64 * 1024 * 1024 else {
            throw MP4DemuxerError.corruptedBox(.moov)
        }
        let moovData = try readRawBytes(offset: offset, count: Int(size))
        let childBoxes = parseBoxList(data: moovData)

        // 1. Parse mvhd first to obtain movie timescale and duration
        if let mvhd = childBoxes.first(where: { $0.type == .mvhd }) {
            parseMvhd(data: mvhd.payload)
        }

        // 2. Parse trak boxes
        let trakBoxes = childBoxes.filter { $0.type == .trak }
        for trakBox in trakBoxes {
            if let parsedTrack = parseTrak(data: trakBox.payload) {
                tracks[parsedTrack.track.trackNumber] = parsedTrack.track
                trackPlaybackStates[parsedTrack.track.trackNumber] = parsedTrack
            }
        }

        // 3. Fallback duration calculation if mvhd duration is 0
        if self.duration <= 0 {
            var maxTrackDur: Double = 0.0
            for state in trackPlaybackStates.values {
                if let lastSample = state.samples.last {
                    let sampleEnd = lastSample.ptsSeconds + lastSample.durationSeconds
                    if sampleEnd > maxTrackDur {
                        maxTrackDur = sampleEnd
                    }
                }
            }
            if maxTrackDur > 0 {
                self.duration = maxTrackDur
            }
        }
    }

    private func parseMvhd(data: Data) {
        guard data.count >= 20 else { return }
        let version = data[0]
        if version == 0 {
            // Version 0: 32-bit creation, modification, timescale, duration
            let tScale = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self).bigEndian }
            let dur = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt32.self).bigEndian }
            self.movieTimescale = tScale > 0 ? tScale : 1000
            self.movieDurationUnits = UInt64(dur)
            self.duration = Double(dur) / Double(self.movieTimescale)
        } else if version == 1 && data.count >= 32 {
            // Version 1: 64-bit creation, modification, 32-bit timescale, 64-bit duration (requires 32 bytes)
            let tScale = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 20, as: UInt32.self).bigEndian }
            let dur = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt64.self).bigEndian }
            self.movieTimescale = tScale > 0 ? tScale : 1000
            self.movieDurationUnits = dur
            self.duration = Double(dur) / Double(self.movieTimescale)
        }
    }

    private func parseTrak(data: Data) -> MP4TrackPlaybackState? {
        let childBoxes = parseBoxList(data: data)

        // 1. Track Header Box (tkhd)
        guard let tkhdBox = childBoxes.first(where: { $0.type == .tkhd }), tkhdBox.payload.count >= 24 else {
            return nil
        }
        let tkhd = tkhdBox.payload
        let version = tkhd[0]
        var trackID: UInt32 = 1
        var trackDurationUnits: UInt64 = 0
        var displayWidth: Int = 0
        var displayHeight: Int = 0

        if version == 0 && tkhd.count >= 84 {
            trackID = tkhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self).bigEndian }
            trackDurationUnits = UInt64(tkhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 20, as: UInt32.self).bigEndian })
            let rawW = tkhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 76, as: UInt32.self).bigEndian }
            let rawH = tkhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self).bigEndian }
            displayWidth = Int(rawW >> 16)
            displayHeight = Int(rawH >> 16)
        } else if version == 1 && tkhd.count >= 96 {
            trackID = tkhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 20, as: UInt32.self).bigEndian }
            trackDurationUnits = tkhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 28, as: UInt64.self).bigEndian }
            let rawW = tkhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 88, as: UInt32.self).bigEndian }
            let rawH = tkhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 92, as: UInt32.self).bigEndian }
            displayWidth = Int(rawW >> 16)
            displayHeight = Int(rawH >> 16)
        }

        // 2. Media Box (mdia)
        guard let mdiaBox = childBoxes.first(where: { $0.type == .mdia }) else { return nil }
        let mdiaChildren = parseBoxList(data: mdiaBox.payload)

        // 3. Media Header Box (mdhd)
        guard let mdhdBox = mdiaChildren.first(where: { $0.type == .mdhd }), mdhdBox.payload.count >= 24 else {
            return nil
        }
        let mdhd = mdhdBox.payload
        let mdhdVersion = mdhd[0]
        var mediaTimescale: UInt32 = 1000
        var mediaDurationUnits: UInt64 = 0
        var langCode: UInt16 = 0

        if mdhdVersion == 0 && mdhd.count >= 24 {
            mediaTimescale = mdhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self).bigEndian }
            mediaDurationUnits = UInt64(mdhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt32.self).bigEndian })
            langCode = mdhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 20, as: UInt16.self).bigEndian }
        } else if mdhdVersion == 1 && mdhd.count >= 34 {
            mediaTimescale = mdhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 20, as: UInt32.self).bigEndian }
            mediaDurationUnits = mdhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt64.self).bigEndian }
            langCode = mdhd.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: UInt16.self).bigEndian }
        }
        if mediaTimescale == 0 { mediaTimescale = 1000 }

        let language = decodeLanguageCode(langCode)

        // 4. Handler Box (hdlr)
        guard let hdlrBox = mdiaChildren.first(where: { $0.type == .hdlr }), hdlrBox.payload.count >= 16 else {
            return nil
        }
        let hdlrTypeVal = hdlrBox.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).bigEndian }
        let handlerType = FourCC(hdlrTypeVal)
        let trackType = mapHandlerToTrackType(handlerType)

        // 5. Media Information Box (minf) -> Sample Table Box (stbl)
        guard let minfBox = mdiaChildren.first(where: { $0.type == .minf }) else { return nil }
        let minfChildren = parseBoxList(data: minfBox.payload)
        guard let stblBox = minfChildren.first(where: { $0.type == .stbl }) else { return nil }
        let stblChildren = parseBoxList(data: stblBox.payload)

        // 6. Sample Description Box (stsd)
        guard let stsdBox = stblChildren.first(where: { $0.type == .stsd }) else { return nil }
        let sampleDescription = parseStsd(data: stsdBox.payload, trackType: trackType)

        // 7. Time-to-Sample Box (stts)
        let sttsEntries = parseStts(box: stblChildren.first(where: { $0.type == .stts }))

        // 8. Composition Time-to-Sample Box (ctts)
        let cttsEntries = parseCtts(box: stblChildren.first(where: { $0.type == .ctts }))

        // 9. Sync Sample Table Box (stss)
        let syncSamples = parseStss(box: stblChildren.first(where: { $0.type == .stss }))

        // 10. Sample Size Box (stsz)
        let (uniformSize, sampleSizes) = parseStsz(box: stblChildren.first(where: { $0.type == .stsz }))

        // 11. Sample-to-Chunk Box (stsc)
        let stscEntries = parseStsc(box: stblChildren.first(where: { $0.type == .stsc }))

        // 12. Chunk Offset Boxes (stco / co64)
        let chunkOffsets = parseChunkOffsets(stco: stblChildren.first(where: { $0.type == .stco }),
                                             co64: stblChildren.first(where: { $0.type == .co64 }))

        // 13. Build complete sample index
        let totalSamples = sampleSizes.count
        guard totalSamples > 0 || !chunkOffsets.isEmpty else {
            return nil
        }

        let samples = buildSampleIndex(
            totalSamples: totalSamples,
            uniformSize: uniformSize,
            sampleSizes: sampleSizes,
            stscEntries: stscEntries,
            chunkOffsets: chunkOffsets,
            sttsEntries: sttsEntries,
            cttsEntries: cttsEntries,
            syncSamples: syncSamples,
            timescale: mediaTimescale
        )

        guard !samples.isEmpty else {
            return nil
        }

        let keyframeIndices = samples.filter { $0.isKeyframe }.map { $0.sampleIndex }

        // Compute default duration in nanoseconds
        let defaultDurationNs: UInt64? = {
            if let firstDelta = sttsEntries.first?.delta, firstDelta > 0, mediaTimescale > 0 {
                return UInt64(Double(firstDelta) / Double(mediaTimescale) * 1_000_000_000.0)
            }
            return nil
        }()

        let demuxedTrack = DemuxedTrack(
            trackNumber: UInt64(trackID),
            trackUID: UInt64(trackID),
            type: trackType,
            codecID: sampleDescription.codecID,
            codecPrivate: sampleDescription.codecPrivate,
            pixelWidth: sampleDescription.pixelWidth > 0 ? sampleDescription.pixelWidth : displayWidth,
            pixelHeight: sampleDescription.pixelHeight > 0 ? sampleDescription.pixelHeight : displayHeight,
            displayWidth: displayWidth > 0 ? displayWidth : sampleDescription.pixelWidth,
            displayHeight: displayHeight > 0 ? displayHeight : sampleDescription.pixelHeight,
            defaultDurationNs: defaultDurationNs,
            bitsPerChannel: sampleDescription.bitsPerChannel,
            colorPrimaries: sampleDescription.colorPrimaries,
            transferCharacteristics: sampleDescription.transferCharacteristics,
            matrixCoefficients: sampleDescription.matrixCoefficients,
            sampleRate: sampleDescription.sampleRate > 0 ? sampleDescription.sampleRate : Double(mediaTimescale),
            channels: sampleDescription.channels,
            bitDepth: sampleDescription.bitDepth,
            name: sampleDescription.name,
            language: language,
            isDefault: (tkhd[3] & 0x01) != 0,
            isForced: false
        )

        return MP4TrackPlaybackState(
            track: demuxedTrack,
            timescale: mediaTimescale,
            samples: samples,
            keyframeIndices: keyframeIndices
        )
    }

    // MARK: - stsd Sample Description Parser

    private struct ParsedSampleDescription {
        var codecID: String = ""
        var codecPrivate: Data? = nil
        var pixelWidth: Int = 0
        var pixelHeight: Int = 0
        var bitsPerChannel: Int = 8
        var colorPrimaries: UInt64? = nil
        var transferCharacteristics: UInt64? = nil
        var matrixCoefficients: UInt64? = nil
        var sampleRate: Double = 0.0
        var channels: Int = 0
        var bitDepth: Int = 16
        var name: String? = nil
    }

    private func parseStsd(data: Data, trackType: DemuxedTrackType) -> ParsedSampleDescription {
        var result = ParsedSampleDescription()
        guard data.count >= 8 else { return result }

        let entryCount = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian }
        guard entryCount > 0 else { return result }

        var offset = 8
        guard offset + 8 <= data.count else { return result }

        let entrySize = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian })
        let formatVal = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).bigEndian }
        let format = FourCC(formatVal)
        result.codecID = format.description

        guard entrySize >= 8, offset + entrySize <= data.count else { return result }
        let entryData = data.subdata(in: offset..<(offset + entrySize))

        if trackType == .video {
            // Video Sample Entry layout:
            // 0..3: size, 4..7: format, 8..13: reserved (6 bytes), 14..15: dataRefIndex
            // 16..31: predefined & reserved (16 bytes)
            // 32..33: width (UInt16), 34..35: height (UInt16)
            // 36..43: horiz / vert resolution (8 bytes)
            // 44..47: reserved (4 bytes), 48..49: frame_count (UInt16)
            // 50..81: compressorname (32 bytes)
            // 82..83: depth (UInt16), 84..85: pre_defined (2 bytes)
            if entryData.count >= 86 {
                let w = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: UInt16.self).bigEndian }
                let h = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 34, as: UInt16.self).bigEndian }
                result.pixelWidth = Int(w)
                result.pixelHeight = Int(h)

                let depth = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 82, as: UInt16.self).bigEndian }
                result.bitsPerChannel = depth == 30 ? 10 : 8

                // Parse nested boxes after byte 86: avcC, hvcC, av1C, vpcC, colr
                let childBoxes = parseBoxList(data: entryData.subdata(in: 86..<entryData.count))
                for box in childBoxes {
                    switch box.type {
                    case .avcC, .hvcC, .av1C, .vpcC:
                        result.codecPrivate = box.payload
                    case .colr:
                        if box.payload.count >= 11 {
                            let colorTypeVal = box.payload.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
                            if FourCC(colorTypeVal) == .nclx {
                                let prim = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt16.self).bigEndian }
                                let trans = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 6, as: UInt16.self).bigEndian }
                                let matrix = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt16.self).bigEndian }
                                result.colorPrimaries = UInt64(prim)
                                result.transferCharacteristics = UInt64(trans)
                                result.matrixCoefficients = UInt64(matrix)
                            }
                        }
                    default:
                        break
                    }
                }
            }
        } else if trackType == .audio {
            // Audio Sample Entry layout:
            // 0..7: header, 8..13: reserved, 14..15: dataRefIndex
            // 16..17: version (UInt16), 18..19: revision (UInt16), 20..23: vendor
            // 24..25: channelCount (UInt16), 26..27: sampleSize (UInt16)
            // 28..31: compressionId & packetSize
            // 32..35: sampleRate (UInt32: 16.16 fixed-point)
            if entryData.count >= 36 {
                let soundVersion = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 16, as: UInt16.self).bigEndian }
                let channels = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt16.self).bigEndian }
                let sampleSize = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 26, as: UInt16.self).bigEndian }
                let rawSR = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 32, as: UInt32.self).bigEndian }

                result.channels = Int(channels)
                result.bitDepth = sampleSize > 0 ? Int(sampleSize) : 16
                result.sampleRate = Double(rawSR >> 16)

                var childBoxOffset = 36
                if soundVersion == 1 && entryData.count >= 52 {
                    childBoxOffset = 52
                } else if soundVersion == 2 && entryData.count >= 72 {
                    childBoxOffset = 72
                    // QuickTime Sound Sample Description Version 2 extensions:
                    // 64-bit IEEE float sample rate at offset 40, channel count at offset 48, bits per channel at 56
                    let sr64 = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 40, as: UInt64.self).bigEndian }
                    let trueSampleRate = Double(bitPattern: sr64)
                    if trueSampleRate > 0 && !trueSampleRate.isNaN && !trueSampleRate.isInfinite {
                        result.sampleRate = trueSampleRate
                    }
                    let trueChannels = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 48, as: UInt32.self).bigEndian }
                    if trueChannels > 0 {
                        result.channels = Int(trueChannels)
                    }
                    let trueBits = entryData.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 56, as: UInt32.self).bigEndian }
                    if trueBits > 0 {
                        result.bitDepth = Int(trueBits)
                    }
                }

                if childBoxOffset < entryData.count {
                    let childBoxes = parseBoxList(data: entryData.subdata(in: childBoxOffset..<entryData.count))
                    for box in childBoxes {
                        switch box.type {
                        case .esds:
                            // Extract AudioSpecificConfig from MPEG-4 esds descriptor
                            if let asc = extractAudioSpecificConfig(from: box.payload) {
                                result.codecPrivate = asc
                            } else {
                                result.codecPrivate = box.payload
                            }
                        case .alac:
                            // If ALAC box contains 4-byte FullBox header + 24-byte cookie (28 bytes total),
                            // extract the 24-byte ALACSpecificConfig for native CoreAudio decoder.
                            if box.payload.count == 28 && box.payload[0] == 0 {
                                result.codecPrivate = box.payload.subdata(in: 4..<28)
                            } else {
                                result.codecPrivate = box.payload
                            }
                        case .dac3, .dec3, .dOps, .dfLa:
                            result.codecPrivate = box.payload
                        default:
                            break
                        }
                    }
                }
            }
        }

        return result
    }

    // MARK: - Sample Table Helper Parsers

    private func parseStts(box: (type: FourCC, payload: Data)?) -> [(count: UInt32, delta: UInt32)] {
        guard let box = box, box.payload.count >= 8 else { return [] }
        let entryCount = Int(box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian })
        var entries: [(count: UInt32, delta: UInt32)] = []
        entries.reserveCapacity(min(entryCount, 16384))

        var offset = 8
        for _ in 0..<entryCount {
            guard offset + 8 <= box.payload.count else { break }
            let c = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
            let d = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).bigEndian }
            entries.append((count: c, delta: d))
            offset += 8
        }
        return entries
    }

    private func parseCtts(box: (type: FourCC, payload: Data)?) -> [(count: UInt32, offset: Int32)] {
        guard let box = box, box.payload.count >= 8 else { return [] }
        let version = box.payload[0]
        let entryCount = Int(box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian })
        var entries: [(count: UInt32, offset: Int32)] = []
        entries.reserveCapacity(min(entryCount, 16384))

        var offset = 8
        for _ in 0..<entryCount {
            guard offset + 8 <= box.payload.count else { break }
            let c = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
            let rawOff: Int32
            if version == 0 {
                let unsignedVal = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).bigEndian }
                rawOff = Int32(bitPattern: unsignedVal)
            } else {
                rawOff = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 4, as: Int32.self).bigEndian }
            }
            entries.append((count: c, offset: rawOff))
            offset += 8
        }
        return entries
    }

    private func parseStss(box: (type: FourCC, payload: Data)?) -> Set<Int>? {
        guard let box = box, box.payload.count >= 8 else { return nil }
        let entryCount = Int(box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian })
        var set = Set<Int>()
        set.reserveCapacity(min(entryCount, 65536))

        var offset = 8
        for _ in 0..<entryCount {
            guard offset + 4 <= box.payload.count else { break }
            let sNum = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
            if sNum > 0 {
                set.insert(Int(sNum - 1)) // Convert 1-based sample number to 0-based index
            }
            offset += 4
        }
        return set
    }

    private func parseStsz(box: (type: FourCC, payload: Data)?) -> (uniformSize: UInt32, sizes: [UInt32]) {
        guard let box = box, box.payload.count >= 12 else { return (0, []) }
        let uniform = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian }
        let count = Int(box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).bigEndian })

        if uniform > 0 {
            return (uniform, Array(repeating: uniform, count: count))
        }

        var sizes: [UInt32] = []
        sizes.reserveCapacity(min(count, 131072))
        var offset = 12
        for _ in 0..<count {
            guard offset + 4 <= box.payload.count else { break }
            let sz = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
            sizes.append(sz)
            offset += 4
        }
        return (0, sizes)
    }

    private func parseStsc(box: (type: FourCC, payload: Data)?) -> [(firstChunk: UInt32, samplesPerChunk: UInt32, descIndex: UInt32)] {
        guard let box = box, box.payload.count >= 8 else { return [] }
        let entryCount = Int(box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian })
        var entries: [(firstChunk: UInt32, samplesPerChunk: UInt32, descIndex: UInt32)] = []
        entries.reserveCapacity(min(entryCount, 16384))

        var offset = 8
        for _ in 0..<entryCount {
            guard offset + 12 <= box.payload.count else { break }
            let fc = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
            let spc = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).bigEndian }
            let di = box.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self).bigEndian }
            entries.append((firstChunk: fc, samplesPerChunk: spc, descIndex: di))
            offset += 12
        }
        return entries
    }

    private func parseChunkOffsets(stco: (type: FourCC, payload: Data)?, co64: (type: FourCC, payload: Data)?) -> [UInt64] {
        if let co64 = co64, co64.payload.count >= 8 {
            let entryCount = Int(co64.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian })
            var offsets: [UInt64] = []
            offsets.reserveCapacity(min(entryCount, 65536))
            var offset = 8
            for _ in 0..<entryCount {
                guard offset + 8 <= co64.payload.count else { break }
                let off = co64.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self).bigEndian }
                offsets.append(off)
                offset += 8
            }
            return offsets
        }

        if let stco = stco, stco.payload.count >= 8 {
            let entryCount = Int(stco.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian })
            var offsets: [UInt64] = []
            offsets.reserveCapacity(min(entryCount, 65536))
            var offset = 8
            for _ in 0..<entryCount {
                guard offset + 4 <= stco.payload.count else { break }
                let off = stco.payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
                offsets.append(UInt64(off))
                offset += 4
            }
            return offsets
        }

        return []
    }

    // MARK: - Sample Index Assembly

    private func buildSampleIndex(
        totalSamples: Int,
        uniformSize: UInt32,
        sampleSizes: [UInt32],
        stscEntries: [(firstChunk: UInt32, samplesPerChunk: UInt32, descIndex: UInt32)],
        chunkOffsets: [UInt64],
        sttsEntries: [(count: UInt32, delta: UInt32)],
        cttsEntries: [(count: UInt32, offset: Int32)],
        syncSamples: Set<Int>?,
        timescale: UInt32
    ) -> [MP4Sample] {
        guard totalSamples > 0, !chunkOffsets.isEmpty, !stscEntries.isEmpty else { return [] }

        // 1. Compute file offsets for each sample
        var sampleOffsets = [UInt64]()
        sampleOffsets.reserveCapacity(totalSamples)

        var sampleIdx = 0
        var stscIdx = 0
        let numChunks = chunkOffsets.count

        for chunkIdx in 1...numChunks {
            while stscIdx + 1 < stscEntries.count && stscEntries[stscIdx + 1].firstChunk <= UInt32(chunkIdx) {
                stscIdx += 1
            }
            let spc = Int(stscEntries[stscIdx].samplesPerChunk)
            var currentChunkOffset = chunkOffsets[chunkIdx - 1]

            for _ in 0..<spc {
                guard sampleIdx < totalSamples else { break }
                sampleOffsets.append(currentChunkOffset)
                let sSize = sampleIdx < sampleSizes.count ? sampleSizes[sampleIdx] : uniformSize
                currentChunkOffset += UInt64(sSize)
                sampleIdx += 1
            }
            if sampleIdx >= totalSamples { break }
        }

        let resolvedSampleCount = min(totalSamples, sampleOffsets.count)
        guard resolvedSampleCount > 0 else { return [] }

        // 2. Expand DTS and durations from stts
        var dtsArray = [Int64]()
        var durationArray = [UInt32]()
        dtsArray.reserveCapacity(resolvedSampleCount)
        durationArray.reserveCapacity(resolvedSampleCount)

        var curDTS: Int64 = 0
        for entry in sttsEntries {
            for _ in 0..<entry.count {
                guard dtsArray.count < resolvedSampleCount else { break }
                dtsArray.append(curDTS)
                durationArray.append(entry.delta)
                curDTS += Int64(entry.delta)
            }
            if dtsArray.count >= resolvedSampleCount { break }
        }

        // Pad if stts has fewer entries than total samples
        let lastDelta = durationArray.last ?? 1
        while dtsArray.count < resolvedSampleCount {
            dtsArray.append(curDTS)
            durationArray.append(lastDelta)
            curDTS += Int64(lastDelta)
        }

        // 3. Expand composition offsets from ctts
        var cttsOffsets = [Int32]()
        if !cttsEntries.isEmpty {
            cttsOffsets.reserveCapacity(resolvedSampleCount)
            for entry in cttsEntries {
                for _ in 0..<entry.count {
                    guard cttsOffsets.count < resolvedSampleCount else { break }
                    cttsOffsets.append(entry.offset)
                }
                if cttsOffsets.count >= resolvedSampleCount { break }
            }
            while cttsOffsets.count < resolvedSampleCount {
                cttsOffsets.append(0)
            }
        }

        // 4. Construct final sample records
        let tsDouble = Double(timescale > 0 ? timescale : 1000)
        var samples = [MP4Sample]()
        samples.reserveCapacity(resolvedSampleCount)

        for i in 0..<resolvedSampleCount {
            let offset = sampleOffsets[i]
            let sz = i < sampleSizes.count ? sampleSizes[i] : uniformSize
            let dts = dtsArray[i]
            let cttsOff = i < cttsOffsets.count ? Int64(cttsOffsets[i]) : 0
            let pts = dts + cttsOff
            let dur = durationArray[i]
            let isKeyframe = (syncSamples == nil) ? true : syncSamples!.contains(i)

            samples.append(MP4Sample(
                sampleIndex: i,
                fileOffset: offset,
                size: sz,
                dts: dts,
                pts: pts,
                duration: dur,
                ptsSeconds: Double(pts) / tsDouble,
                dtsSeconds: Double(dts) / tsDouble,
                durationSeconds: Double(dur) / tsDouble,
                isKeyframe: isKeyframe
            ))
        }

        return samples
    }

    // MARK: - Streaming Zero-Copy Packet Extraction

    public func nextPacket() throws -> DemuxedPacket? {
        ioLock.lock()
        defer { ioLock.unlock() }

        // Find track with pending samples that has the lowest fileOffset on disk
        // to maximize contiguous disk pread throughput and match interleaving.
        var candidateTrack: MP4TrackPlaybackState? = nil
        var minOffset: UInt64 = UInt64.max

        for state in trackPlaybackStates.values {
            if let sample = state.currentSample {
                if sample.fileOffset < minOffset {
                    minOffset = sample.fileOffset
                    candidateTrack = state
                }
            }
        }

        guard let chosenTrack = candidateTrack, let sample = chosenTrack.currentSample else {
            return nil // End of file across all tracks
        }

        // Race-to-sleep burst storage I/O optimization: advise next 16MB-32MB chunk into page cache
        if sample.fileOffset < lastBurstPrefetchOffset ||
           sample.fileOffset >= lastBurstPrefetchOffset + UInt64(Self.burstChunkSize) / 2 {
            adviseBurstPrefetch(offset: sample.fileOffset, length: Self.burstChunkSize)
        }

        chosenTrack.advance()

        let rawPayload = try readRawBytes(offset: sample.fileOffset, count: Int(sample.size))
        var packetData = rawPayload

        // For subtitle tracks (tx3g, text, subt), strip container length prefix to deliver clean text
        if chosenTrack.track.isSubtitle {
            if rawPayload.count >= 2 {
                let textLen = Int(UInt16(rawPayload[0]) << 8 | UInt16(rawPayload[1]))
                if textLen > 0 && textLen + 2 <= rawPayload.count {
                    packetData = rawPayload.subdata(in: 2..<(2 + textLen))
                }
            }
        }

        return DemuxedPacket(
            trackNumber: chosenTrack.track.trackNumber,
            pts: sample.ptsSeconds,
            dts: sample.dtsSeconds,
            duration: sample.durationSeconds,
            isKeyframe: sample.isKeyframe,
            data: packetData,
            fileOffset: sample.fileOffset
        )
    }

    // MARK: - O(log N) Keyframe Seeking

    public func seek(to targetSeconds: Double) {
        ioLock.lock()
        defer { ioLock.unlock() }

        // 1. Identify primary video track
        let primaryVideo = videoTracks.first

        if let vTrack = primaryVideo, let vState = trackPlaybackStates[vTrack.trackNumber] {
            // Seek video track to nearest preceding sync keyframe
            let targetKeyframePTS = vState.seek(to: targetSeconds)

            // 2. Synchronize all secondary tracks (audio/subtitles) to match video seek point
            for (tNum, state) in trackPlaybackStates where tNum != vTrack.trackNumber {
                state.seekToNearestSample(targetPTS: targetKeyframePTS)
            }
        } else {
            // Audio-only or non-video container: seek all tracks directly to targetSeconds
            for state in trackPlaybackStates.values {
                _ = state.seek(to: targetSeconds)
            }
        }

        // 3. Issue burst prefetch for upcoming packets around seek location
        if let primarySample = primaryVideo.flatMap({ trackPlaybackStates[$0.trackNumber]?.currentSample }) {
            adviseBurstPrefetch(offset: primarySample.fileOffset, length: Self.burstChunkSize)
        } else if let anySample = trackPlaybackStates.values.compactMap({ $0.currentSample }).first {
            adviseBurstPrefetch(offset: anySample.fileOffset, length: Self.burstChunkSize)
        }
    }

    // MARK: - Subtitle Extraction

    public func extractSubtitleCues(for targetTrackNumber: UInt64) -> [SubtitleCue] {
        return extractAllSubtitleCues()[targetTrackNumber] ?? []
    }

    public func extractAllSubtitleCues() -> [UInt64: [SubtitleCue]] {
        ioLock.lock()
        defer { ioLock.unlock() }

        var results: [UInt64: [SubtitleCue]] = [:]

        for (tNum, state) in trackPlaybackStates where state.track.isSubtitle {
            var cues: [SubtitleCue] = []
            for sample in state.samples {
                if let payload = try? readRawBytes(offset: sample.fileOffset, count: Int(sample.size)) {
                    // tx3g subtitle text box begins with a 2-byte text length
                    var textStr: String? = nil
                    if payload.count >= 2 {
                        let textLen = Int(UInt16(payload[0]) << 8 | UInt16(payload[1]))
                        if textLen > 0 && textLen + 2 <= payload.count {
                            textStr = String(data: payload.subdata(in: 2..<(2 + textLen)), encoding: .utf8)
                        }
                    }
                    if textStr == nil {
                        textStr = String(data: payload, encoding: .utf8)
                    }

                    if let text = textStr {
                        let clean = SubtitleParser.cleanSubtitleCueText(text)
                        if !clean.isEmpty {
                            let dur = sample.durationSeconds > 0 ? sample.durationSeconds : 3.0
                            cues.append(SubtitleCue(startTime: sample.ptsSeconds, endTime: sample.ptsSeconds + dur, text: clean))
                        }
                    }
                }
            }
            results[tNum] = cues
        }

        return results
    }

    // MARK: - Low-Level I/O & Parsing Helpers

    private func readRawBytes(offset: UInt64, count: Int) throws -> Data {
        guard count > 0 else { return Data() }

        if count >= Self.burstChunkSize {
            adviseBurstPrefetch(offset: offset, length: count)
        }

        if let inMemoryData = inMemoryData {
            let start = Int(offset)
            let end = start + count
            guard start >= 0, end <= inMemoryData.count else {
                throw MP4DemuxerError.unexpectedEOF
            }
            return inMemoryData.subdata(in: start..<end)
        }

        // True hardware zero-copy slicing backed by mapped virtual memory
        if let region = mappedRegion {
            guard offset + UInt64(count) <= fileSize else {
                throw MP4DemuxerError.unexpectedEOF
            }
            let ptr = region.pointer.advanced(by: Int(offset))
            return Data(bytesNoCopy: ptr, count: count, deallocator: .custom { [region] _, _ in
                _ = region
            })
        }

        guard fileDescriptor >= 0 else {
            throw MP4DemuxerError.fileOpenFailed("File descriptor is closed")
        }

        var buffer = Data(count: count)
        let bytesRead = buffer.withUnsafeMutableBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return 0 }
            return pread(fileDescriptor, base, count, off_t(offset))
        }

        guard bytesRead == count else {
            throw MP4DemuxerError.readFailed(offset: offset, expected: count, actual: bytesRead)
        }

        return buffer
    }

    private func parseBoxList(data: Data) -> [(type: FourCC, payload: Data)] {
        var results: [(type: FourCC, payload: Data)] = []
        var offset = 0

        while offset + 8 <= data.count {
            let size32 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
            let type32 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).bigEndian }
            let boxType = FourCC(type32)

            var boxSize: Int = Int(size32)
            var headerSize: Int = 8

            if size32 == 1 {
                guard offset + 16 <= data.count else { break }
                let size64 = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self).bigEndian }
                boxSize = Int(min(UInt64(Int.max), size64))
                headerSize = 16
            } else if size32 == 0 {
                boxSize = data.count - offset
            }

            guard boxSize >= headerSize, boxSize <= data.count - offset else { break }
            let payload = data.subdata(in: (offset + headerSize)..<(offset + boxSize))
            results.append((type: boxType, payload: payload))
            offset += boxSize
        }

        return results
    }

    private func decodeLanguageCode(_ code: UInt16) -> String? {
        guard code != 0 && code != 0x55C4 else { return nil } // 0x55C4 = 'und'
        let val1 = (code >> 10) & 0x1F
        let val2 = (code >> 5) & 0x1F
        let val3 = code & 0x1F
        guard val1 >= 1 && val1 <= 26 && val2 >= 1 && val2 <= 26 && val3 >= 1 && val3 <= 26 else {
            return nil
        }
        let c1 = Character(UnicodeScalar(val1 + 0x60) ?? "?")
        let c2 = Character(UnicodeScalar(val2 + 0x60) ?? "?")
        let c3 = Character(UnicodeScalar(val3 + 0x60) ?? "?")
        return "\(c1)\(c2)\(c3)"
    }

    private func mapHandlerToTrackType(_ handler: FourCC) -> DemuxedTrackType {
        switch handler {
        case .vide: return .video
        case .soun: return .audio
        case .subt, .text, .sbtl, .clcp: return .subtitle
        default: return .unknown
        }
    }

    /// Parses MPEG-4 AudioSpecificConfig from an esds box payload
    private func extractAudioSpecificConfig(from data: Data) -> Data? {
        guard data.count > 4 else { return nil }
        return parseDescriptors(data: data, offset: 4)
    }

    private func parseDescriptors(data: Data, offset: Int) -> Data? {
        var pos = offset
        while pos < data.count {
            let tag = data[pos]
            pos += 1
            guard let len = parseDescriptorLength(data: data, offset: &pos) else { break }
            guard pos + len <= data.count else { break }

            if tag == 0x03 {
                // ES_Descriptor: 2 bytes ES_ID, 1 byte flags
                guard len >= 3 else { break }
                let flags = data[pos + 2]
                var descOffset = pos + 3
                if (flags & 0x80) != 0 { descOffset += 2 } // streamDependenceFlag
                if (flags & 0x40) != 0 { // URL_Flag
                    guard descOffset < data.count else { break }
                    let urlLen = Int(data[descOffset])
                    descOffset += 1 + urlLen
                }
                if (flags & 0x20) != 0 { descOffset += 2 } // OCRstreamFlag

                guard descOffset <= pos + len else { break }
                let inner = data.subdata(in: descOffset..<(pos + len))
                if let config = parseDescriptors(data: inner, offset: 0) {
                    return config
                }
            } else if tag == 0x04 {
                // DecoderConfigDescriptor: 13 bytes header, followed by DecSpecificInfo
                guard len >= 13, pos + 13 <= pos + len else { break }
                let inner = data.subdata(in: (pos + 13)..<(pos + len))
                if let config = parseDescriptors(data: inner, offset: 0) {
                    return config
                }
            } else if tag == 0x05 {
                // DecSpecificInfoTag: payload is AudioSpecificConfig
                return data.subdata(in: pos..<(pos + len))
            }

            pos += len
        }

        return nil
    }

    private func parseDescriptorLength(data: Data, offset: inout Int) -> Int? {
        var length = 0
        for _ in 0..<4 {
            guard offset < data.count else { return nil }
            let b = data[offset]
            offset += 1
            length = (length << 7) | Int(b & 0x7F)
            if (b & 0x80) == 0 { break }
        }
        return length
    }
}
