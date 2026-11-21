//
//  PacketChunkBuffer.swift
//  frames
//
//  High-throughput thread-safe packet chunking and GOP prefetch buffer
//  for zero-copy Apple Silicon media demuxing and hardware decoding.
//

import Foundation
import os.lock

/// A contiguous chunk of demuxed elementary packets, typically corresponding to a GOP or container cluster.
nonisolated public struct DemuxedChunk: Sendable {
    public let startPTS: Double
    public let endPTS: Double
    public let packets: [DemuxedPacket]
    public let hasKeyframe: Bool

    public init(startPTS: Double, endPTS: Double, packets: [DemuxedPacket], hasKeyframe: Bool) {
        self.startPTS = startPTS
        self.endPTS = endPTS
        self.packets = packets
        self.hasKeyframe = hasKeyframe
    }
}

/// Thread-safe packet chunking and GOP index buffer for smooth, artifact-free scrubbing and playback.
nonisolated public final class PacketChunkBuffer: @unchecked Sendable {

    // MARK: - Properties

    private var lock = os_unfair_lock()
    private var ring: [DemuxedPacket?]
    private var head: Int = 0
    private var itemCount: Int = 0
    private var _maxCapacity: Int

    /// A two-hour file at 30 fps has ~216k keyframes; 512 indexed GOPs is ample
    /// for seek locality while keeping the index bounded under repeated seeks.
    private let maxGOPIndexEntries = 512

    public var maxCapacity: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _maxCapacity
    }

    public func setCapacity(_ capacity: Int) {
        guard capacity > 0 else { return }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard capacity != _maxCapacity else { return }
        rebuildRing(capacity: capacity)
    }

    // GOP index: Maps keyframe PTS to (fileOffset, keyframePTS, endPTS)
    public struct GOPIndexEntry: Sendable, Comparable {
        public let keyframePTS: Double
        public var endPTS: Double
        public let fileOffset: UInt64

        public static func < (lhs: GOPIndexEntry, rhs: GOPIndexEntry) -> Bool {
            lhs.keyframePTS < rhs.keyframePTS
        }
    }
    private var gopIndex: [GOPIndexEntry] = []

    // MARK: - Lifecycle

    public init(maxCapacity: Int = 256) {
        let clamped = max(1, maxCapacity)
        self._maxCapacity = clamped
        self.ring = Array(repeating: nil, count: clamped)
    }

    // MARK: - Queue Operations

    public var count: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return itemCount
    }

    public var isEmpty: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return itemCount == 0
    }

    public var hasHeadroom: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return itemCount < (_maxCapacity * 3 / 4)
    }

    public func enqueue(_ packet: DemuxedPacket) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        append(packet)
    }

    public func enqueue(packets: [DemuxedPacket]) {
        guard !packets.isEmpty else { return }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        for packet in packets {
            append(packet)
        }
    }

    public func dequeue() -> DemuxedPacket? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard itemCount > 0 else { return nil }
        let index = head
        head = (head + 1) % _maxCapacity
        itemCount -= 1
        let packet = ring[index]
        ring[index] = nil
        return packet
    }

    public func peek() -> DemuxedPacket? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard itemCount > 0 else { return nil }
        return ring[head]
    }

    public func removeAll() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        for i in 0..<itemCount {
            ring[(head + i) % _maxCapacity] = nil
        }
        head = 0
        itemCount = 0
        gopIndex.removeAll(keepingCapacity: true)
    }

    /// O(1) ring-buffer append. Caller must hold `lock`.
    private func append(_ packet: DemuxedPacket) {
        if itemCount == _maxCapacity {
            // Drop the oldest packet instead of shifting the whole array.
            ring[head] = nil
            head = (head + 1) % _maxCapacity
            itemCount -= 1
        }
        let index = (head + itemCount) % _maxCapacity
        ring[index] = packet
        itemCount += 1
    }

    /// Rebuilds storage after a capacity change. Caller must hold `lock`.
    private func rebuildRing(capacity: Int) {
        var items: [DemuxedPacket] = []
        items.reserveCapacity(min(itemCount, capacity))
        for i in 0..<itemCount {
            if let packet = ring[(head + i) % _maxCapacity] {
                items.append(packet)
            }
        }
        if items.count > capacity {
            items.removeFirst(items.count - capacity)
        }
        _maxCapacity = capacity
        ring = Array(repeating: nil, count: capacity)
        for (i, packet) in items.enumerated() {
            ring[i] = packet
        }
        head = 0
        itemCount = items.count
    }

    // MARK: - GOP Indexing

    public func recordGOP(keyframePTS: Double, fileOffset: UInt64) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let idx = gopLowerBound(for: keyframePTS)
        if idx < gopIndex.count, gopIndex[idx].keyframePTS == keyframePTS {
            return
        }
        gopIndex.insert(
            GOPIndexEntry(keyframePTS: keyframePTS, endPTS: keyframePTS, fileOffset: fileOffset),
            at: idx
        )
        if gopIndex.count > maxGOPIndexEntries {
            gopIndex.removeFirst(gopIndex.count - maxGOPIndexEntries)
        }
    }

    public func updateGOPEnd(keyframePTS: Double, endPTS: Double) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let idx = gopLowerBound(for: keyframePTS)
        if idx < gopIndex.count, gopIndex[idx].keyframePTS == keyframePTS {
            gopIndex[idx].endPTS = max(gopIndex[idx].endPTS, endPTS)
        }
    }

    /// First index whose keyframePTS is >= the target. Caller must hold `lock`.
    private func gopLowerBound(for pts: Double) -> Int {
        var low = 0
        var high = gopIndex.count
        while low < high {
            let mid = (low + high) / 2
            if gopIndex[mid].keyframePTS < pts {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// Finds the nearest GOP keyframe at or immediately before the target PTS.
    public func findNearestGOP(before targetPTS: Double) -> GOPIndexEntry? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard !gopIndex.isEmpty else { return nil }

        var low = 0
        var high = gopIndex.count - 1
        var bestIndex: Int? = nil

        while low <= high {
            let mid = (low + high) / 2
            if gopIndex[mid].keyframePTS <= targetPTS {
                bestIndex = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        if let idx = bestIndex {
            return gopIndex[idx]
        }
        return gopIndex.first
    }

    public var gopCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return gopIndex.count
    }
}
