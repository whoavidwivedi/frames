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
    private var queue: [DemuxedPacket] = []
    private var _maxCapacity: Int
    
    public var maxCapacity: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _maxCapacity
    }
    
    public func setCapacity(_ capacity: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        if capacity > 0 {
            self._maxCapacity = capacity
        }
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
        self._maxCapacity = maxCapacity
    }
    
    // MARK: - Queue Operations
    
    public var count: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return queue.count
    }
    
    public var isEmpty: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return queue.isEmpty
    }
    
    public var hasHeadroom: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return queue.count < (_maxCapacity * 3 / 4)
    }
    
    public func enqueue(_ packet: DemuxedPacket) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        queue.append(packet)
        if queue.count > _maxCapacity {
            queue.removeFirst(queue.count - _maxCapacity)
        }
    }
    
    public func enqueue(packets: [DemuxedPacket]) {
        guard !packets.isEmpty else { return }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        queue.append(contentsOf: packets)
        if queue.count > _maxCapacity {
            queue.removeFirst(queue.count - _maxCapacity)
        }
    }
    
    public func dequeue() -> DemuxedPacket? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }
    
    public func peek() -> DemuxedPacket? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return queue.first
    }
    
    public func removeAll() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        queue.removeAll(keepingCapacity: true)
    }
    
    // MARK: - GOP Indexing
    
    public func recordGOP(keyframePTS: Double, fileOffset: UInt64) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        if let last = gopIndex.last, last.keyframePTS == keyframePTS {
            return
        }
        
        if let idx = gopIndex.firstIndex(where: { $0.keyframePTS == keyframePTS }) {
            gopIndex[idx] = GOPIndexEntry(keyframePTS: keyframePTS, endPTS: max(gopIndex[idx].endPTS, keyframePTS), fileOffset: fileOffset)
        } else {
            let entry = GOPIndexEntry(keyframePTS: keyframePTS, endPTS: keyframePTS, fileOffset: fileOffset)
            gopIndex.append(entry)
            gopIndex.sort()
        }
    }
    
    public func updateGOPEnd(keyframePTS: Double, endPTS: Double) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        if let idx = gopIndex.firstIndex(where: { $0.keyframePTS == keyframePTS }) {
            gopIndex[idx].endPTS = max(gopIndex[idx].endPTS, endPTS)
        }
    }
    
    /// Finds the nearest GOP keyframe at or immediately before the target PTS.
    public func findNearestGOP(before targetPTS: Double) -> GOPIndexEntry? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        guard !gopIndex.isEmpty else { return nil }
        
        // Binary search for closest keyframePTS <= targetPTS
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
