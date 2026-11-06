import Foundation

/// Pure Swift 6 zero-dependency streaming Matroska (.mkv) and WebM (.webm) demuxer.
nonisolated public final class MatroskaDemuxer: @unchecked Sendable {
    public let fileURL: URL
    private let fileHandle: FileHandle
    private let fileSize: UInt64

    public private(set) var docType: String = ""
    public private(set) var duration: Double = 0.0
    public private(set) var timestampScale: UInt64 = 1_000_000 // Default 1ms in nanoseconds
    public private(set) var tracks: [UInt64: DemuxedTrack] = [:]
    public private(set) var cuePoints: [CuePointEntry] = []

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
        tracks.values.filter { $0.isAudio }
    }
    public var subtitleTracks: [DemuxedTrack] {
        tracks.values.filter { $0.isSubtitle }
    }

    private var segmentDataOffset: UInt64 = 0
    private var firstClusterOffset: UInt64? = nil
    private var currentClusterTimestamp: Int64 = 0
    private var currentOffset: UInt64 = 0
    private let readBufferCapacity: Int = 1024 * 1024 // 1 MB chunk buffer
    private var buffer = Data()
    private var bufferFileOffset: UInt64 = 0
    private let ioLock = NSLock()

    public init(url: URL) throws {
        self.fileURL = url
        self.fileHandle = try FileHandle(forReadingFrom: url)
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = (attr[.size] as? UInt64) ?? 0

        try parseMetadata()
    }

    deinit {
        try? fileHandle.close()
    }

    // MARK: - Metadata Ingestion
    private func parseMetadata() throws {
        guard let ebmlElement = readElement(at: 0), ebmlElement.id == .ebml else {
            throw DemuxerError.invalidEBMLHeader
        }

        // Parse EBML Header
        let ebmlPayload = try readBytes(offset: ebmlElement.payloadOffset, length: Int(ebmlElement.payloadSize))
        parseEBMLHeader(data: ebmlPayload)

        // Find Segment Element
        let searchOffset = ebmlElement.payloadOffset + ebmlElement.payloadSize
        guard let segmentElement = readElement(at: searchOffset), segmentElement.id == .segment else {
            throw DemuxerError.segmentNotFound
        }

        self.segmentDataOffset = segmentElement.payloadOffset
        self.currentOffset = segmentDataOffset

        // Scan primary master elements under Segment (SeekHead, Info, Tracks, Cues)
        var offset = segmentDataOffset
        self.firstClusterOffset = nil
        let scanLimit = min(fileSize, segmentDataOffset + (50 * 1024 * 1024)) // Read first 50MB for headers

        while offset < scanLimit {
            guard let elem = readElement(at: offset) else { break }

            switch elem.id {
            case .seekHead:
                if let payload = try? readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    parseSeekHead(data: payload)
                }
            case .info:
                if let payload = try? readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    parseInfo(data: payload)
                }
            case .tracks:
                if let payload = try? readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    parseTracks(data: payload)
                }
            case .cues:
                if let payload = try? readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    parseCues(data: payload)
                }
            case .cluster:
                if firstClusterOffset == nil {
                    firstClusterOffset = offset
                }
                // Once we find tracks, info, and first cluster, we can stop sequential header scanning
                if !tracks.isEmpty && duration > 0 {
                    offset = scanLimit // Break out of top-level scan
                    continue
                }
            default:
                break
            }

            offset = elem.payloadOffset + elem.payloadSize
        }

        // If cues haven't been discovered yet, scan file tail (where muxers place Cues)
        if cuePoints.isEmpty {
            scanForCuesAtTail()
        }

        // Sort cue points for O(log N) binary search seeks
        cuePoints.sort()

        // Set playback start to first cluster
        if firstClusterOffset == nil {
            firstClusterOffset = resyncToCluster(from: segmentDataOffset)
        }
        self.currentOffset = firstClusterOffset ?? segmentDataOffset
    }

    // MARK: - Element Reading Helper
    private struct ElementHeader {
        let id: EBMLID
        let rawID: UInt64
        let payloadOffset: UInt64
        let payloadSize: UInt64
        let totalHeaderSize: Int
    }

    private func readElement(at offset: UInt64) -> ElementHeader? {
        guard offset < fileSize else { return nil }
        guard let headerData = try? readBytes(offset: offset, length: 16), !headerData.isEmpty else { return nil }

        return headerData.withUnsafeBytes { rawPtr -> ElementHeader? in
            guard let idVint = EBMLVint.parseElementID(from: rawPtr, offset: 0) else { return nil }
            guard let sizeVint = EBMLVint.parseDataSize(from: rawPtr, offset: idVint.length) else { return nil }

            let totalHeaderLen = idVint.length + sizeVint.length
            let payloadOffset = offset + UInt64(totalHeaderLen)
            let ebmlID = EBMLID(rawValue: idVint.value) ?? .void

            return ElementHeader(
                id: ebmlID,
                rawID: idVint.value,
                payloadOffset: payloadOffset,
                payloadSize: sizeVint.isUnknownSize ? (fileSize - payloadOffset) : sizeVint.value,
                totalHeaderSize: totalHeaderLen
            )
        }
    }

    // MARK: - Header & Info Parsers
    private func parseEBMLHeader(data: Data) {
        data.withUnsafeBytes { raw in
            var cursor = 0
            while cursor < raw.count {
                guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
                cursor += idVint.length
                guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
                cursor += sizeVint.length
                let elemLen = Int(sizeVint.value)

                if idVint.value == EBMLID.docType.rawValue {
                    self.docType = EBMLVint.parseString(from: raw, offset: cursor, length: elemLen) ?? ""
                }
                cursor += elemLen
            }
        }
    }

    private func parseInfo(data: Data) {
        data.withUnsafeBytes { raw in
            var cursor = 0
            while cursor < raw.count {
                guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
                cursor += idVint.length
                guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
                cursor += sizeVint.length
                let elemLen = Int(sizeVint.value)

                switch idVint.value {
                case EBMLID.timestampScale.rawValue:
                    self.timestampScale = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 1_000_000
                case EBMLID.duration.rawValue:
                    if let d = EBMLVint.parseFloat(from: raw, offset: cursor, length: elemLen) {
                        // Duration in EBML is in timestampScale units
                        self.duration = (d * Double(timestampScale)) / 1_000_000_000.0
                    }
                default:
                    break
                }
                cursor += elemLen
            }
        }
    }

    private func parseSeekHead(data: Data) {
        data.withUnsafeBytes { raw in
            var cursor = 0
            while cursor < raw.count {
                guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
                cursor += idVint.length
                guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
                cursor += sizeVint.length
                let elemLen = Int(sizeVint.value)

                if idVint.value == EBMLID.seek.rawValue {
                    parseSingleSeek(raw: raw, offset: cursor, length: elemLen)
                }
                cursor += elemLen
            }
        }
    }

    private func parseSingleSeek(raw: UnsafeRawBufferPointer, offset: Int, length: Int) {
        var cursor = offset
        let limit = offset + length
        var seekID: UInt64 = 0
        var seekPos: UInt64 = 0

        while cursor < limit {
            guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
            cursor += idVint.length
            guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
            cursor += sizeVint.length
            let elemLen = Int(sizeVint.value)

            if idVint.value == EBMLID.seekID.rawValue {
                seekID = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0
            } else if idVint.value == EBMLID.seekPosition.rawValue {
                seekPos = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0
            }
            cursor += elemLen
        }

        // 1. Secondary SeekHead (e.g. pointing to Cues at the end of the file)
        if seekID == EBMLID.seekHead.rawValue {
            let shOffset = segmentDataOffset + seekPos
            if let elem = readElement(at: shOffset), elem.id == .seekHead {
                if let payload = try? readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    parseSeekHead(data: payload)
                }
            } else if let elem = readElement(at: seekPos), elem.id == .seekHead {
                if let payload = try? readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    parseSeekHead(data: payload)
                }
            }
        }

        // 2. If Seek points to Cues, parse them on demand
        if seekID == EBMLID.cues.rawValue && cuePoints.isEmpty {
            let cuesAbsoluteOffset = segmentDataOffset + seekPos
            if let elem = readElement(at: cuesAbsoluteOffset), elem.id == .cues {
                if let payload = try? readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    parseCues(data: payload)
                }
            } else if let elem = readElement(at: seekPos), elem.id == .cues {
                if let payload = try? readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    parseCues(data: payload)
                }
            }
        }
    }

    // MARK: - Tracks Parser
    private func parseTracks(data: Data) {
        data.withUnsafeBytes { raw in
            var cursor = 0
            while cursor < raw.count {
                guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
                cursor += idVint.length
                guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
                cursor += sizeVint.length
                let elemLen = Int(sizeVint.value)

                if idVint.value == EBMLID.trackEntry.rawValue {
                    if let track = parseTrackEntry(raw: raw, offset: cursor, length: elemLen) {
                        self.tracks[track.trackNumber] = track
                    }
                }
                cursor += elemLen
            }
        }
    }

    private func parseTrackEntry(raw: UnsafeRawBufferPointer, offset: Int, length: Int) -> DemuxedTrack? {
        var cursor = offset
        let limit = offset + length

        var trackNumber: UInt64 = 0
        var trackUID: UInt64 = 0
        var trackType: DemuxedTrackType = .unknown
        var codecID: String = ""
        var codecPrivate: Data? = nil
        var defaultDurationNs: UInt64? = nil
        var name: String? = nil
        var language: String? = nil
        var isDefault: Bool = true
        var isForced: Bool = false

        var pixelWidth = 0
        var pixelHeight = 0
        var displayWidth = 0
        var displayHeight = 0
        var bitsPerChannel = 8
        var colorPrimaries: UInt64? = nil
        var transferCharacteristics: UInt64? = nil
        var matrixCoefficients: UInt64? = nil

        var sampleRate: Double = 0.0
        var channels: Int = 0
        var bitDepth: Int = 16

        while cursor < limit {
            guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
            cursor += idVint.length
            guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
            cursor += sizeVint.length
            let elemLen = Int(sizeVint.value)

            switch idVint.value {
            case EBMLID.trackNumber.rawValue:
                trackNumber = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0
            case EBMLID.trackUID.rawValue:
                trackUID = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0
            case EBMLID.trackType.rawValue:
                let rawType = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0
                trackType = DemuxedTrackType(rawValue: rawType) ?? .unknown
            case EBMLID.codecID.rawValue:
                codecID = EBMLVint.parseString(from: raw, offset: cursor, length: elemLen) ?? ""
            case EBMLID.codecPrivate.rawValue:
                codecPrivate = Data(bytes: raw.baseAddress!.advanced(by: cursor), count: elemLen)
            case EBMLID.defaultDuration.rawValue:
                defaultDurationNs = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen)
            case EBMLID.name.rawValue:
                name = EBMLVint.parseString(from: raw, offset: cursor, length: elemLen)
            case EBMLID.language.rawValue:
                let lang = EBMLVint.parseString(from: raw, offset: cursor, length: elemLen)
                if language == nil || language == "und" {
                    language = lang
                }
            case EBMLID.languageBCP47.rawValue:
                let bcp47 = EBMLVint.parseString(from: raw, offset: cursor, length: elemLen)
                if let bcp47, !bcp47.isEmpty {
                    language = bcp47
                }
            case EBMLID.flagDefault.rawValue:
                let flag = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 1
                isDefault = (flag != 0)
            case EBMLID.flagForced.rawValue:
                let flag = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0
                isForced = (flag != 0)

            // Video sub-element
            case EBMLID.video.rawValue:
                parseVideoDetails(raw: raw, offset: cursor, length: elemLen,
                                  width: &pixelWidth, height: &pixelHeight,
                                  dispWidth: &displayWidth, dispHeight: &displayHeight,
                                  bpc: &bitsPerChannel, primaries: &colorPrimaries,
                                  transfer: &transferCharacteristics, matrix: &matrixCoefficients)

            // Audio sub-element
            case EBMLID.audio.rawValue:
                parseAudioDetails(raw: raw, offset: cursor, length: elemLen,
                                  rate: &sampleRate, ch: &channels, depth: &bitDepth)

            default:
                break
            }
            cursor += elemLen
        }

        guard trackNumber > 0, !codecID.isEmpty else { return nil }

        return DemuxedTrack(
            trackNumber: trackNumber,
            trackUID: trackUID,
            type: trackType,
            codecID: codecID,
            codecPrivate: codecPrivate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            defaultDurationNs: defaultDurationNs,
            bitsPerChannel: bitsPerChannel,
            colorPrimaries: colorPrimaries,
            transferCharacteristics: transferCharacteristics,
            matrixCoefficients: matrixCoefficients,
            sampleRate: sampleRate,
            channels: channels,
            bitDepth: bitDepth,
            name: name,
            language: language,
            isDefault: isDefault,
            isForced: isForced
        )
    }

    private func parseVideoDetails(raw: UnsafeRawBufferPointer, offset: Int, length: Int,
                                   width: inout Int, height: inout Int,
                                   dispWidth: inout Int, dispHeight: inout Int,
                                   bpc: inout Int,
                                   primaries: inout UInt64?,
                                   transfer: inout UInt64?,
                                   matrix: inout UInt64?) {
        var cursor = offset
        let limit = offset + length
        while cursor < limit {
            guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
            cursor += idVint.length
            guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
            cursor += sizeVint.length
            let elemLen = Int(sizeVint.value)

            switch idVint.value {
            case EBMLID.pixelWidth.rawValue:
                width = Int(EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0)
            case EBMLID.pixelHeight.rawValue:
                height = Int(EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0)
            case EBMLID.displayWidth.rawValue:
                dispWidth = Int(EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0)
            case EBMLID.displayHeight.rawValue:
                dispHeight = Int(EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0)
            case EBMLID.bitsPerChannel.rawValue:
                bpc = Int(EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 8)
            case EBMLID.colour.rawValue:
                // Parse nested Colour element
                parseColourElement(raw: raw, offset: cursor, length: elemLen, primaries: &primaries, transfer: &transfer, matrix: &matrix)
            default:
                break
            }
            cursor += elemLen
        }
    }

    private func parseColourElement(raw: UnsafeRawBufferPointer, offset: Int, length: Int,
                                    primaries: inout UInt64?, transfer: inout UInt64?, matrix: inout UInt64?) {
        var cursor = offset
        let limit = offset + length
        while cursor < limit {
            guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
            cursor += idVint.length
            guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
            cursor += sizeVint.length
            let elemLen = Int(sizeVint.value)

            switch idVint.value {
            case EBMLID.primaries.rawValue:
                primaries = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen)
            case EBMLID.transferCharacteristics.rawValue:
                transfer = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen)
            case EBMLID.matrixCoefficients.rawValue:
                matrix = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen)
            default:
                break
            }
            cursor += elemLen
        }
    }

    private func parseAudioDetails(raw: UnsafeRawBufferPointer, offset: Int, length: Int,
                                   rate: inout Double, ch: inout Int, depth: inout Int) {
        var cursor = offset
        let limit = offset + length
        while cursor < limit {
            guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
            cursor += idVint.length
            guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
            cursor += sizeVint.length
            let elemLen = Int(sizeVint.value)

            switch idVint.value {
            case EBMLID.samplingFrequency.rawValue, EBMLID.outputSamplingFrequency.rawValue:
                rate = EBMLVint.parseFloat(from: raw, offset: cursor, length: elemLen) ?? 0.0
            case EBMLID.channels.rawValue:
                ch = Int(EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 2)
            case EBMLID.bitDepth.rawValue:
                depth = Int(EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 16)
            default:
                break
            }
            cursor += elemLen
        }
    }

    // MARK: - Cues Parser
    private func parseCues(data: Data) {
        data.withUnsafeBytes { raw in
            var cursor = 0
            while cursor < raw.count {
                guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
                cursor += idVint.length
                guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
                cursor += sizeVint.length
                let elemLen = Int(sizeVint.value)

                if idVint.value == EBMLID.cuePoint.rawValue {
                    let entries = parseCuePoints(raw: raw, offset: cursor, length: elemLen)
                    self.cuePoints.append(contentsOf: entries)
                }
                cursor += elemLen
            }
        }
    }

    private func parseCuePoints(raw: UnsafeRawBufferPointer, offset: Int, length: Int) -> [CuePointEntry] {
        var cursor = offset
        let limit = min(raw.count, offset + length)
        var cueTime: UInt64 = 0
        var entries: [CuePointEntry] = []

        while cursor < limit {
            guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
            cursor += idVint.length
            guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
            cursor += sizeVint.length
            let elemLen = Int(sizeVint.value)

            if idVint.value == EBMLID.cueTime.rawValue {
                cueTime = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen) ?? 0
            } else if idVint.value == EBMLID.cueTrackPositions.rawValue {
                // Parse nested CueTrackPositions
                var subCursor = cursor
                let subLimit = min(raw.count, cursor + elemLen)
                var trackNum: UInt64 = 1
                var clusterPos: UInt64 = 0

                while subCursor < subLimit {
                    guard let subId = EBMLVint.parseElementID(from: raw, offset: subCursor) else { break }
                    subCursor += subId.length
                    guard let subSize = EBMLVint.parseDataSize(from: raw, offset: subCursor) else { break }
                    subCursor += subSize.length
                    let subLen = Int(subSize.value)

                    if subId.value == EBMLID.cueTrack.rawValue {
                        trackNum = EBMLVint.parseUInt(from: raw, offset: subCursor, length: subLen) ?? 1
                    } else if subId.value == EBMLID.cueClusterPosition.rawValue {
                        clusterPos = EBMLVint.parseUInt(from: raw, offset: subCursor, length: subLen) ?? 0
                    }
                    subCursor += subLen
                }

                if clusterPos > 0 {
                    let timeInSeconds = (Double(cueTime) * Double(timestampScale)) / 1_000_000_000.0
                    entries.append(CuePointEntry(timeSeconds: timeInSeconds, clusterPosition: clusterPos, trackNumber: trackNum))
                }
            }
            cursor += elemLen
        }

        return entries
    }

    /// Scans the tail of the file for the Cues element (standard in MKV files muxed on the fly).
    private func scanForCuesAtTail() {
        guard cuePoints.isEmpty, fileSize > segmentDataOffset else { return }
        let tailSpan: UInt64 = min(fileSize - segmentDataOffset, 48 * 1024 * 1024)
        let tailStart = fileSize - tailSpan

        var searchOffset = tailStart
        let chunkSize = 512 * 1024

        while searchOffset < fileSize {
            let toRead = min(chunkSize, Int(fileSize - searchOffset))
            guard let data = try? readBytes(offset: searchOffset, length: toRead), data.count >= 4 else { break }

            let match = data.withUnsafeBytes { raw -> Int? in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                let count = raw.count
                for i in 0..<(count - 3) {
                    if base[i] == 0x1C && base[i + 1] == 0x53 && base[i + 2] == 0xBB && base[i + 3] == 0x6B {
                        return i
                    }
                }
                return nil
            }

            if let idx = match {
                let candidateOffset = searchOffset + UInt64(idx)
                if let elem = readElement(at: candidateOffset), elem.id == .cues {
                    if let payload = try? readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                        parseCues(data: payload)
                        if !cuePoints.isEmpty {
                            return
                        }
                    }
                }
                searchOffset = candidateOffset + 4
            } else {
                searchOffset += UInt64(max(1, toRead - 3))
            }
        }
    }

    private var pendingPackets: [DemuxedPacket] = []

    // MARK: - Streaming Packet Generator
    /// Reads the next media packet from the stream. Returns nil when end of file is reached.
    public func nextPacket() throws -> DemuxedPacket? {
        ioLock.lock()
        defer { ioLock.unlock() }

        if !pendingPackets.isEmpty {
            return pendingPackets.removeFirst()
        }

        while currentOffset < fileSize {
            guard let elem = readElement(at: currentOffset) else {
                // If not at EOF, attempt resynchronization to the nearest cluster
                if currentOffset < fileSize, let nextCluster = resyncToCluster(from: currentOffset) {
                    currentOffset = nextCluster
                    continue
                }
                currentOffset = fileSize
                return nil
            }

            switch elem.id {
            case .cluster:
                // Enter Cluster payload to read cluster timestamp and blocks
                currentOffset = elem.payloadOffset
                continue

            case .timestamp:
                // Cluster timestamp
                let tsData = try readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize))
                tsData.withUnsafeBytes { raw in
                    self.currentClusterTimestamp = EBMLVint.parseInt(from: raw, offset: 0, length: Int(elem.payloadSize)) ?? 0
                }
                currentOffset = elem.payloadOffset + elem.payloadSize
                continue

            case .simpleBlock, .block:
                // Elementary media block
                let blockData = try readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize))
                let pkts = parseBlock(data: blockData, isSimpleBlock: (elem.id == .simpleBlock), fileOffset: elem.payloadOffset)
                currentOffset = elem.payloadOffset + elem.payloadSize
                if !pkts.isEmpty {
                    if pkts.count > 1 {
                        pendingPackets.append(contentsOf: pkts.dropFirst())
                    }
                    return pkts.first
                }

            case .blockGroup:
                let bgData = try readBytes(offset: elem.payloadOffset, length: Int(elem.payloadSize))
                let pkts = parseBlockGroup(data: bgData, fileOffset: elem.payloadOffset)
                currentOffset = elem.payloadOffset + elem.payloadSize
                if !pkts.isEmpty {
                    if pkts.count > 1 {
                        pendingPackets.append(contentsOf: pkts.dropFirst())
                    }
                    return pkts.first
                }

            default:
                // Skip non-media elements (prevSize, position, padding)
                currentOffset = elem.payloadOffset + elem.payloadSize
            }
        }

        return nil
    }

    /// Reads a chunk of packets in a single high-efficiency demuxing batch.
    public func nextPacketChunk(maxPackets: Int = 32) throws -> [DemuxedPacket] {
        var chunk: [DemuxedPacket] = []
        chunk.reserveCapacity(maxPackets)
        for _ in 0..<maxPackets {
            guard let packet = try nextPacket() else { break }
            chunk.append(packet)
        }
        return chunk
    }

    private func parseBlockGroup(data: Data, fileOffset: UInt64, clusterTimestamp: Int64? = nil) -> [DemuxedPacket] {
        return data.withUnsafeBytes { raw -> [DemuxedPacket] in
            var cursor = 0
            var blockData: Data? = nil
            var hasReferenceBlock = false
            var blockDuration: UInt64? = nil

            while cursor < raw.count {
                guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
                cursor += idVint.length
                guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
                cursor += sizeVint.length
                let elemLen = Int(sizeVint.value)

                if idVint.value == EBMLID.block.rawValue {
                    blockData = Data(bytes: raw.baseAddress!.advanced(by: cursor), count: elemLen)
                } else if idVint.value == EBMLID.referenceBlock.rawValue {
                    hasReferenceBlock = true
                } else if idVint.value == EBMLID.blockDuration.rawValue {
                    blockDuration = EBMLVint.parseUInt(from: raw, offset: cursor, length: elemLen)
                }
                cursor += elemLen
            }

            guard let bData = blockData else { return [] }
            let isKeyframe = !hasReferenceBlock
            var pkts = parseBlock(data: bData, isSimpleBlock: false, fileOffset: fileOffset, explicitKeyframe: isKeyframe, clusterTimestamp: clusterTimestamp)
            if let dur = blockDuration {
                let durSecs = (Double(dur) * Double(timestampScale)) / 1_000_000_000.0
                pkts = pkts.map { p in
                    DemuxedPacket(
                        trackNumber: p.trackNumber,
                        pts: p.pts,
                        dts: p.dts,
                        duration: durSecs,
                        isKeyframe: p.isKeyframe,
                        isDiscardable: p.isDiscardable,
                        data: p.data,
                        fileOffset: p.fileOffset
                    )
                }
            }
            return pkts
        }
    }

    private func parseBlock(data: Data, isSimpleBlock: Bool, fileOffset: UInt64, explicitKeyframe: Bool? = nil, clusterTimestamp: Int64? = nil) -> [DemuxedPacket] {
        return data.withUnsafeBytes { raw -> [DemuxedPacket] in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return [] }
            var cursor = 0
            guard let trackVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { return [] }
            cursor += trackVint.length

            // Relative timecode (2 bytes signed Int16 big endian)
            guard cursor + 2 <= raw.count else { return [] }
            let relTime = Int16(bitPattern: (UInt16(base[cursor]) << 8) | UInt16(base[cursor + 1]))
            cursor += 2

            // Flags (1 byte)
            guard cursor < raw.count else { return [] }
            let flags = base[cursor]
            cursor += 1

            let isKeyframe: Bool
            if let explicit = explicitKeyframe {
                isKeyframe = explicit
            } else {
                isKeyframe = isSimpleBlock ? ((flags & 0x80) != 0) : true
            }
            let isDiscardable = (flags & 0x01) != 0

            // Absolute PTS in seconds
            let clusterTs = clusterTimestamp ?? currentClusterTimestamp
            let absTimeTicks = clusterTs + Int64(relTime)
            let basePts = (Double(absTimeTicks) * Double(timestampScale)) / 1_000_000_000.0

            let lacing = (flags & 0x06) >> 1
            var frameSizes: [Int] = []

            if lacing == 0 {
                // No lacing: single frame
                frameSizes.append(raw.count - cursor)
            } else {
                guard cursor < raw.count else { return [] }
                let numFrames = Int(base[cursor]) + 1
                cursor += 1

                if lacing == 1 {
                    // Xiph lacing
                    var sum = 0
                    for _ in 0..<(numFrames - 1) {
                        var size = 0
                        while cursor < raw.count {
                            let b = base[cursor]
                            cursor += 1
                            size += Int(b)
                            if b < 255 { break }
                        }
                        frameSizes.append(size)
                        sum += size
                    }
                    let last = (raw.count - cursor) - sum
                    if last > 0 { frameSizes.append(last) }
                } else if lacing == 2 {
                    // Fixed-size lacing
                    let remaining = raw.count - cursor
                    let size = remaining / numFrames
                    for _ in 0..<numFrames {
                        frameSizes.append(size)
                    }
                } else if lacing == 3 {
                    // EBML lacing
                    var sum = 0
                    var prevSize = 0
                    for i in 0..<(numFrames - 1) {
                        if i == 0 {
                            if let vint = EBMLVint.parseDataSize(from: raw, offset: cursor) {
                                cursor += vint.length
                                prevSize = Int(vint.value)
                                frameSizes.append(prevSize)
                                sum += prevSize
                            }
                        } else {
                            if let vint = EBMLVint.parseElementID(from: raw, offset: cursor) {
                                cursor += vint.length
                                let mask = UInt64(1) << (vint.length * 7 - 1)
                                let bias = Int(mask - 1)
                                let diff = Int(vint.value & ~mask) - bias
                                prevSize += diff
                                frameSizes.append(prevSize)
                                sum += prevSize
                            }
                        }
                    }
                    let last = (raw.count - cursor) - sum
                    if last > 0 { frameSizes.append(last) }
                }
            }

            var packets: [DemuxedPacket] = []
            var offsetInPayload = cursor
            let trackNumber = trackVint.value
            let trackInfo = tracks[trackNumber]
            let durationPerFrame: Double = (trackInfo?.isAudio == true && (trackInfo?.sampleRate ?? 0) > 0) ? (1536.0 / trackInfo!.sampleRate) : 0.0

            for (idx, size) in frameSizes.enumerated() {
                guard offsetInPayload + size <= raw.count, size > 0 else { break }
                let frameData = Data(bytes: base + offsetInPayload, count: size)
                let pts = basePts + (Double(idx) * durationPerFrame)
                packets.append(
                    DemuxedPacket(
                        trackNumber: trackNumber,
                        pts: pts,
                        dts: pts,
                        isKeyframe: isKeyframe,
                        isDiscardable: isDiscardable,
                        data: frameData,
                        fileOffset: fileOffset
                    )
                )
                offsetInPayload += size
            }

            return packets
        }
    }

    // MARK: - Fast Seeking
    /// Instantaneous O(log N) seek to target timestamp in seconds.
    public func seek(to targetSeconds: Double) {
        ioLock.lock()
        defer { ioLock.unlock() }

        let clampedTarget = max(0.0, min(targetSeconds, duration > 0 ? duration : targetSeconds))

        // Prefer video track cue points so seek lands on video keyframe cluster
        let targetTrackNumber = videoTracks.first?.trackNumber
        let relevantCues: [CuePointEntry]
        if let targetTrack = targetTrackNumber {
            let matched = cuePoints.filter { $0.trackNumber == targetTrack }
            relevantCues = matched.isEmpty ? cuePoints : matched
        } else {
            relevantCues = cuePoints
        }

        if clampedTarget <= 0.05 || (relevantCues.first != nil && clampedTarget < relevantCues[0].timeSeconds) {
            self.currentOffset = firstClusterOffset ?? segmentDataOffset
        } else if !relevantCues.isEmpty {
            // Binary search for closest cue point <= target
            var low = 0
            var high = relevantCues.count - 1
            var bestIndex = 0

            while low <= high {
                let mid = (low + high) / 2
                if relevantCues[mid].timeSeconds <= clampedTarget {
                    bestIndex = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }

            let cue = relevantCues[bestIndex]
            let offsetA = segmentDataOffset + cue.clusterPosition
            let offsetB = cue.clusterPosition
            if let elem = readElement(at: offsetA), elem.id == .cluster {
                self.currentOffset = offsetA
            } else if let elem = readElement(at: offsetB), elem.id == .cluster {
                self.currentOffset = offsetB
            } else if let resynced = resyncToCluster(from: offsetA, maxScanBytes: 15 * 1024 * 1024) {
                self.currentOffset = resynced
            } else {
                self.currentOffset = offsetA
            }
        } else {
            // Fallback: estimate cluster position via ratio and resynchronize
            let ratio = duration > 0 ? (clampedTarget / duration) : 0.0
            let estimatedOffset = segmentDataOffset + UInt64(Double(fileSize - segmentDataOffset) * ratio)
            if let resynced = resyncToCluster(from: estimatedOffset, maxScanBytes: 64 * 1024 * 1024) {
                self.currentOffset = resynced
            } else {
                self.currentOffset = firstClusterOffset ?? segmentDataOffset
            }
        }

        // Invalidate read buffer cache and pending laced packets
        pendingPackets.removeAll()
        buffer = Data()
        bufferFileOffset = 0
    }

    /// Scans forward from an offset to locate the 4-byte Matroska cluster element signature (0x1F43B675).
    public func resyncToCluster(from startOffset: UInt64, maxScanBytes: Int = 64 * 1024 * 1024) -> UInt64? {
        let scanLimit = min(fileSize, startOffset + UInt64(maxScanBytes))
        var searchOffset = startOffset
        let chunkSize = 64 * 1024

        while searchOffset < scanLimit {
            let bytesToRead = min(chunkSize, Int(scanLimit - searchOffset))
            guard let data = try? readBytes(offset: searchOffset, length: bytesToRead), data.count >= 4 else {
                break
            }

            let match = data.withUnsafeBytes { raw -> Int? in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                let count = raw.count
                for i in 0..<(count - 3) {
                    if base[i] == 0x1F && base[i + 1] == 0x43 && base[i + 2] == 0xB6 && base[i + 3] == 0x75 {
                        return i
                    }
                }
                return nil
            }

            if let offsetInChunk = match {
                let candidateOffset = searchOffset + UInt64(offsetInChunk)
                if let elem = readElement(at: candidateOffset), elem.id == .cluster {
                    return candidateOffset
                }
                searchOffset = candidateOffset + 4
            } else {
                searchOffset += UInt64(max(1, bytesToRead - 3))
            }
        }
        return nil
    }

    // MARK: - Buffered I/O Engine
    private func readBytes(offset: UInt64, length: Int) throws -> Data {
        guard length > 0, offset + UInt64(length) <= fileSize else { return Data() }

        // If requested region is inside current buffer, slice directly without disk I/O
        if offset >= bufferFileOffset && (offset + UInt64(length)) <= (bufferFileOffset + UInt64(buffer.count)) {
            let localOffset = Int(offset - bufferFileOffset)
            return buffer.subdata(in: localOffset..<(localOffset + length))
        }

        try fileHandle.seek(toOffset: offset)

        if length <= readBufferCapacity {
            let chunkToRead = max(length, readBufferCapacity)
            var newChunk = Data()
            newChunk.reserveCapacity(chunkToRead)

            while newChunk.count < chunkToRead {
                let needed = min(chunkToRead - newChunk.count, 512 * 1024)
                guard let part = try fileHandle.read(upToCount: needed), !part.isEmpty else {
                    break
                }
                newChunk.append(part)
            }

            self.buffer = newChunk
            self.bufferFileOffset = offset
            return newChunk.prefix(length)
        } else {
            // For oversized payloads (e.g. 4K high-bitrate intra frames, Cues table), read directly without truncating
            var result = Data()
            result.reserveCapacity(length)

            while result.count < length {
                let needed = min(length - result.count, 1024 * 1024)
                guard let part = try fileHandle.read(upToCount: needed), !part.isEmpty else {
                    break
                }
                result.append(part)
            }
            return result
        }
    }

    // MARK: - Subtitle Cue Extraction
    /// High-performance single-pass extractor for all embedded text subtitle tracks.
    /// Skips large video/audio payload reads to avoid memory pressure and disk thrashing.
    public func extractAllSubtitleCues() -> [UInt64: [SubtitleCue]] {
        guard let subFileHandle = try? FileHandle(forReadingFrom: fileURL) else { return [:] }
        defer { try? subFileHandle.close() }

        let targetTrackNumbers = Set(subtitleTracks.map { $0.trackNumber })
        guard !targetTrackNumbers.isEmpty else { return [:] }

        var result: [UInt64: [SubtitleCue]] = [:]
        for tNum in targetTrackNumbers {
            result[tNum] = []
        }

        var offset = firstClusterOffset ?? segmentDataOffset
        var clusterTime: Int64 = 0
        let limit = fileSize

        var readBuffer = Data()
        var readBufferOffset: UInt64 = 0
        let bufferChunkSize = 128 * 1024 // 128 KB chunk buffer

        func readBuffered(offset: UInt64, length: Int) -> Data? {
            guard length > 0, offset + UInt64(length) <= limit else { return nil }
            if offset >= readBufferOffset && (offset + UInt64(length)) <= (readBufferOffset + UInt64(readBuffer.count)) {
                let start = Int(offset - readBufferOffset)
                return readBuffer.subdata(in: start..<(start + length))
            }
            guard (try? subFileHandle.seek(toOffset: offset)) != nil else { return nil }
            let toRead = max(length, bufferChunkSize)
            guard let newChunk = try? subFileHandle.read(upToCount: toRead), newChunk.count >= length else { return nil }
            readBuffer = newChunk
            readBufferOffset = offset
            return newChunk.prefix(length)
        }

        while offset < limit {
            guard offset < fileSize else { break }
            guard let headerData = readBuffered(offset: offset, length: 16), !headerData.isEmpty else { break }
            guard let elem = parseElementHeader(data: headerData, baseOffset: offset) else { break }

            if elem.id == .cluster {
                offset = elem.payloadOffset
                continue
            } else if elem.id == .timestamp {
                if let tsData = readBuffered(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    tsData.withUnsafeBytes { raw in
                        clusterTime = EBMLVint.parseInt(from: raw, offset: 0, length: Int(elem.payloadSize)) ?? 0
                    }
                }
            } else if elem.id == .simpleBlock || elem.id == .block {
                // Read only the first 8 bytes of the block to inspect track number
                if let headerBytes = readBuffered(offset: elem.payloadOffset, length: min(8, Int(elem.payloadSize))),
                   let trackVint = headerBytes.withUnsafeBytes({ EBMLVint.parseDataSize(from: $0, offset: 0) }) {
                    if !targetTrackNumbers.contains(trackVint.value) {
                        // Skip video / audio payload without reading it from disk
                        offset = elem.payloadOffset + elem.payloadSize
                        continue
                    }
                }

                // Subtitle block matched - read payload and parse
                if let blkData = readBuffered(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                    let packets = parseBlock(data: blkData, isSimpleBlock: (elem.id == .simpleBlock), fileOffset: elem.payloadOffset, clusterTimestamp: clusterTime)
                    for pkt in packets where targetTrackNumbers.contains(pkt.trackNumber) {
                        if let text = String(data: pkt.data, encoding: .utf8) {
                            let clean = SubtitleParser.cleanSubtitleCueText(text)
                            if !clean.isEmpty {
                                let dur = (pkt.duration ?? 0) > 0 ? pkt.duration! : 3.0
                                result[pkt.trackNumber, default: []].append(SubtitleCue(startTime: pkt.pts, endTime: pkt.pts + dur, text: clean))
                            }
                        }
                    }
                }
            } else if elem.id == .blockGroup {
                if let bgData = readBuffered(offset: elem.payloadOffset, length: min(64, Int(elem.payloadSize))) {
                    let hasSubtitleTrack = bgData.withUnsafeBytes { raw -> Bool in
                        var cursor = 0
                        while cursor < raw.count {
                            guard let idVint = EBMLVint.parseElementID(from: raw, offset: cursor) else { break }
                            cursor += idVint.length
                            guard let sizeVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
                            cursor += sizeVint.length
                            if idVint.value == EBMLID.block.rawValue {
                                guard let trackVint = EBMLVint.parseDataSize(from: raw, offset: cursor) else { break }
                                return targetTrackNumbers.contains(trackVint.value)
                            }
                            cursor += Int(sizeVint.value)
                        }
                        return false
                    }
                    if hasSubtitleTrack, let fullBgData = readBuffered(offset: elem.payloadOffset, length: Int(elem.payloadSize)) {
                        let packets = parseBlockGroup(data: fullBgData, fileOffset: elem.payloadOffset, clusterTimestamp: clusterTime)
                        for pkt in packets where targetTrackNumbers.contains(pkt.trackNumber) {
                            if let text = String(data: pkt.data, encoding: .utf8) {
                                let clean = SubtitleParser.cleanSubtitleCueText(text)
                                if !clean.isEmpty {
                                    let dur = (pkt.duration ?? 0) > 0 ? pkt.duration! : 3.0
                                    result[pkt.trackNumber, default: []].append(SubtitleCue(startTime: pkt.pts, endTime: pkt.pts + dur, text: clean))
                                }
                            }
                        }
                    }
                }
            }

            offset = elem.payloadOffset + elem.payloadSize
        }

        var sortedResult: [UInt64: [SubtitleCue]] = [:]
        for (k, v) in result {
            sortedResult[k] = v.sorted { $0.startTime < $1.startTime }
        }
        return sortedResult
    }

    /// Extracts all subtitle cues for an embedded text-based subtitle track without altering current playback position.
    public func extractSubtitleCues(for targetTrackNumber: UInt64) -> [SubtitleCue] {
        return extractAllSubtitleCues()[targetTrackNumber] ?? []
    }

    private func readBytesAt(handle: FileHandle, offset: UInt64, length: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: length) ?? Data()
    }

    private func parseElementHeader(data: Data, baseOffset: UInt64) -> ElementHeader? {
        data.withUnsafeBytes { rawPtr -> ElementHeader? in
            guard let idVint = EBMLVint.parseElementID(from: rawPtr, offset: 0) else { return nil }
            guard let sizeVint = EBMLVint.parseDataSize(from: rawPtr, offset: idVint.length) else { return nil }

            let totalHeaderLen = idVint.length + sizeVint.length
            let payloadOffset = baseOffset + UInt64(totalHeaderLen)
            let ebmlID = EBMLID(rawValue: idVint.value) ?? .void

            return ElementHeader(
                id: ebmlID,
                rawID: idVint.value,
                payloadOffset: payloadOffset,
                payloadSize: sizeVint.isUnknownSize ? (fileSize - payloadOffset) : sizeVint.value,
                totalHeaderSize: totalHeaderLen
            )
        }
    }
}

nonisolated public enum DemuxerError: Error {
    case invalidEBMLHeader
    case segmentNotFound
    case elementNotFound
}
