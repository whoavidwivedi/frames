//
//  ScrubFrameCache.swift
//  frames
//
//  Zero-copy Unified Memory decoded frame cache for instantaneous,
//  artifact-free timeline scrubbing across Apple Silicon media engines.
//

import Foundation
import CoreVideo
import os.lock

nonisolated public final class ScrubFrameCache: @unchecked Sendable {
    
    // MARK: - Types
    
    public struct CachedFrame: @unchecked Sendable {
        public let buffer: CVPixelBuffer
        public let pts: Double
        public let accessTime: UInt64
        
        public init(buffer: CVPixelBuffer, pts: Double, accessTime: UInt64) {
            self.buffer = buffer
            self.pts = pts
            self.accessTime = accessTime
        }
    }
    
    // MARK: - Properties
    
    private var lock = os_unfair_lock()
    private var frames: [CachedFrame] = []
    private var _maxCapacity: Int
    private var accessCounter: UInt64 = 0
    
    public var maxCapacity: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _maxCapacity
    }
    
    // MARK: - Resolution-Aware Scaling
    
    /// Calculates the recommended scrub cache frame capacity based on video resolution.
    /// Memory consumption scaling:
    /// - <= 1080p (e.g. 1920x1080): 48 frames (~190MB in 8-bit YUV)
    /// - 1440p (e.g. 2560x1440): 24 frames (~175MB in 8-bit YUV)
    /// - 4K UHD (e.g. 3840x2160): 16 frames (~265MB in 10-bit YUV)
    /// - 8K UHD (e.g. 7680x4320): 8 frames (~530MB in 10-bit YUV)
    public static func recommendedCapacity(width: Int, height: Int) -> Int {
        guard width > 0 && height > 0 else { return 48 }
        let pixels = width * height
        let maxDim = max(width, height)
        if pixels > 4096 * 2304 || maxDim > 4096 {
            return 8
        } else if pixels > 2560 * 1440 || maxDim > 2560 {
            return 16
        } else if pixels > 1920 * 1080 || maxDim > 1920 {
            return 24
        } else {
            return 48
        }
    }
    
    // MARK: - Lifecycle
    
    public init(maxCapacity: Int = 48) {
        self._maxCapacity = max(1, maxCapacity)
    }
    
    public convenience init(width: Int, height: Int) {
        self.init(maxCapacity: ScrubFrameCache.recommendedCapacity(width: width, height: height))
    }
    
    /// Dynamically resizes the cache capacity to match the given video resolution.
    /// Any frames exceeding the new capacity are evicted based on least-recently-used order.
    public func updateCapacity(forWidth width: Int, height: Int) {
        let capacity = ScrubFrameCache.recommendedCapacity(width: width, height: height)
        setCapacity(capacity)
    }
    
    /// Dynamically adjusts the maximum capacity and trims excess LRU frames if needed.
    public func setCapacity(_ newCapacity: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        _maxCapacity = max(1, newCapacity)
        while frames.count > _maxCapacity {
            if let lruIdx = frames.indices.min(by: { frames[$0].accessTime < frames[$1].accessTime }) {
                frames.remove(at: lruIdx)
            } else {
                break
            }
        }
    }
    
    public var count: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return frames.count
    }
    
    // MARK: - Operations
    
    /// Inserts a decoded frame into the scrub cache.
    public func insert(buffer: CVPixelBuffer, pts: Double) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        accessCounter &+= 1
        let entry = CachedFrame(buffer: buffer, pts: pts, accessTime: accessCounter)
        
        // Replace existing entry if within 1ms
        if let idx = frames.firstIndex(where: { abs($0.pts - pts) < 0.001 }) {
            frames[idx] = entry
            return
        }
        
        // Insert maintaining sorted PTS order
        if let insertIdx = frames.firstIndex(where: { $0.pts > pts }) {
            frames.insert(entry, at: insertIdx)
        } else {
            frames.append(entry)
        }
        
        // Evict least-recently-accessed entry if over capacity
        while frames.count > _maxCapacity {
            if let lruIdx = frames.indices.min(by: { frames[$0].accessTime < frames[$1].accessTime }) {
                frames.remove(at: lruIdx)
            } else {
                break
            }
        }
    }
    
    /// Retrieves the cached frame closest to the target PTS within the specified tolerance.
    public func getFrame(forTargetPTS targetPTS: Double, tolerance: Double = 0.25) -> (buffer: CVPixelBuffer, pts: Double)? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        guard !frames.isEmpty else { return nil }
        
        var bestIndex: Int? = nil
        var bestDelta = Double.infinity
        
        for (i, frame) in frames.enumerated() {
            let delta = abs(frame.pts - targetPTS)
            if delta <= tolerance && delta < bestDelta {
                bestDelta = delta
                bestIndex = i
            }
        }
        
        guard let idx = bestIndex else { return nil }
        
        accessCounter &+= 1
        let matched = frames[idx]
        frames[idx] = CachedFrame(buffer: matched.buffer, pts: matched.pts, accessTime: accessCounter)
        return (matched.buffer, matched.pts)
    }
    
    /// Retrieves the absolute closest cached frame regardless of tolerance (fallback for long GOP seeks).
    public func nearestFrame(to targetPTS: Double) -> (buffer: CVPixelBuffer, pts: Double)? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        guard !frames.isEmpty else { return nil }
        var bestIndex = 0
        var bestDelta = Double.infinity
        for (i, frame) in frames.enumerated() {
            let delta = abs(frame.pts - targetPTS)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = i
            }
        }
        return (frames[bestIndex].buffer, frames[bestIndex].pts)
    }
    
    /// Clears all cached frames.
    public func clear() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        frames.removeAll(keepingCapacity: true)
    }
}
