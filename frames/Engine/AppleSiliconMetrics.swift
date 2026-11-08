//
//  AppleSiliconMetrics.swift
//  frames
//
//  High-precision Apple Silicon hardware identification, capability profiling,
//  and unified memory architecture telemetry supporting all Apple Silicon generations
//  from M1 to the latest (M1, M2, M3, M4, and future M-series).
//

import Foundation
import AppKit
import Darwin
import Metal

public final class AppleSiliconMetrics: @unchecked Sendable {
    public static let shared = AppleSiliconMetrics()

    // MARK: - Generation & Tier Enumerations

    public enum ChipGeneration: Sendable, Equatable {
        case m1
        case m2
        case m3
        case m4
        case m5
        case appleSilicon(String)
        case intel

        public var displayName: String {
            switch self {
            case .m1: return "Apple M1"
            case .m2: return "Apple M2"
            case .m3: return "Apple M3"
            case .m4: return "Apple M4"
            case .m5: return "Apple M5"
            case .appleSilicon(let name): return name
            case .intel: return "Intel (Rosetta)"
            }
        }
    }

    public enum ChipTier: String, Sendable, CaseIterable {
        case base = "Base"
        case pro = "Pro"
        case max = "Max"
        case ultra = "Ultra"
        case standard = "Standard"
    }

    public enum UnifiedMemoryTier: String, Sendable {
        case lean8GB = "8 GB Unified Memory (Ultra-Lean)"
        case balanced16to24GB = "16–24 GB Unified Memory (Balanced)"
        case performance32to64GB = "32–64 GB Unified Memory (High Performance)"
        case workstation96GBPlus = "96+ GB Unified Memory (Workstation Ultra)"
    }

    // MARK: - Hardware Telemetry Properties

    public let chipName: String
    public let physicalMemoryGB: Int
    public let activeCores: Int
    public let isAppleSilicon: Bool
    public let generation: ChipGeneration
    public let tier: ChipTier
    public let memoryTier: UnifiedMemoryTier
    public let gpuFamilyName: String

    // MARK: - Media Engine ASIC Capabilities

    /// Dedicated hardware AV1 video decompression ASIC (Apple Silicon M3, M4, and later).
    public let supportsHardwareAV1Decode: Bool

    /// Hardware ProRes / ProRes RAW dual decode/encode media engines (M1 Pro/Max/Ultra and all M2, M3, M4 chips).
    public let supportsHardwareProRes: Bool

    /// Hardware HEVC (H.265) 10-bit HDR / Dolby Vision ASIC decode/encode (all Apple Silicon M-series).
    public let supportsHardwareHEVC10Bit: Bool

    /// Hardware H.264 / AVC ASIC decode/encode (all Apple Silicon M-series).
    public let supportsHardwareH264: Bool

    // MARK: - Lifecycle

    private init() {
        let brand = Self.querySysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        self.chipName = brand
        let memGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        self.physicalMemoryGB = memGB
        self.activeCores = ProcessInfo.processInfo.activeProcessorCount

        // Verify architecture via utsname
        var sysInfo = utsname()
        uname(&sysInfo)
        let machineIdentifier = Mirror(reflecting: sysInfo.machine).children.reduce("") { id, el in
            guard let val = el.value as? Int8, val != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(val)))
        }

        let isArm = machineIdentifier.contains("arm64") || brand.localizedCaseInsensitiveContains("Apple")
        self.isAppleSilicon = isArm

        // Classify Chip Generation (M1 through latest M4 and future M5+)
        if brand.contains("M1") {
            self.generation = .m1
        } else if brand.contains("M2") {
            self.generation = .m2
        } else if brand.contains("M3") {
            self.generation = .m3
        } else if brand.contains("M4") {
            self.generation = .m4
        } else if brand.contains("M5") {
            self.generation = .m5
        } else if isArm {
            self.generation = .appleSilicon(brand)
        } else {
            self.generation = .intel
        }

        // Classify Chip Tier
        if brand.localizedCaseInsensitiveContains("Ultra") {
            self.tier = .ultra
        } else if brand.localizedCaseInsensitiveContains("Max") {
            self.tier = .max
        } else if brand.localizedCaseInsensitiveContains("Pro") {
            self.tier = .pro
        } else if isArm {
            self.tier = .base
        } else {
            self.tier = .standard
        }

        // Classify Unified Memory Tier
        if memGB <= 8 {
            self.memoryTier = .lean8GB
        } else if memGB <= 24 {
            self.memoryTier = .balanced16to24GB
        } else if memGB <= 64 {
            self.memoryTier = .performance32to64GB
        } else {
            self.memoryTier = .workstation96GBPlus
        }

        // Detect Metal GPU Architecture & Family
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            if metalDevice.supportsFamily(.apple9) {
                self.gpuFamilyName = "Metal 3 (Apple9 GPU)"
            } else if metalDevice.supportsFamily(.apple8) {
                self.gpuFamilyName = "Metal 3 (Apple8 GPU)"
            } else if metalDevice.supportsFamily(.apple7) {
                self.gpuFamilyName = "Metal 3 (Apple7 GPU)"
            } else {
                self.gpuFamilyName = "Metal 3 (\(metalDevice.name))"
            }
        } else {
            self.gpuFamilyName = "Integrated GPU"
        }

        // Hardware AV1 ASIC Decoding: M3, M4, M5+ or Metal Apple9 family on ARM64
        var av1Supported = false
        if isArm {
            switch self.generation {
            case .m3, .m4, .m5:
                av1Supported = true
            case .appleSilicon:
                if let dev = MTLCreateSystemDefaultDevice(), dev.supportsFamily(.apple9) {
                    av1Supported = true
                }
            default:
                break
            }
        }
        self.supportsHardwareAV1Decode = av1Supported

        // Hardware ProRes ASIC Decoding/Encoding:
        // Available on M1 Pro/Max/Ultra and standard across all M2, M3, M4, and M5 chips
        var proResSupported = false
        if isArm {
            switch self.generation {
            case .m2, .m3, .m4, .m5:
                proResSupported = true
            case .m1:
                proResSupported = (self.tier == .pro || self.tier == .max || self.tier == .ultra)
            case .appleSilicon:
                proResSupported = true
            case .intel:
                proResSupported = false
            }
        }
        self.supportsHardwareProRes = proResSupported

        // H.264 & HEVC 10-bit hardware decode/encode is natively built into all Apple Silicon M-series
        self.supportsHardwareHEVC10Bit = isArm
        self.supportsHardwareH264 = isArm
    }

    // MARK: - Dynamic Memory & Cache Scaling

    /// Recommended pipeline frame buffer capacity scaled to unified memory availability.
    public var recommendedPlaybackBufferCapacity: Int {
        switch memoryTier {
        case .lean8GB: return 6
        case .balanced16to24GB: return 12
        case .performance32to64GB: return 24
        case .workstation96GBPlus: return 36
        }
    }

    /// Dynamic scrub cache memory allocation (MB) to prevent system memory pressure.
    public var recommendedScrubCacheCapacityMB: Int {
        switch memoryTier {
        case .lean8GB: return 64
        case .balanced16to24GB: return 128
        case .performance32to64GB: return 256
        case .workstation96GBPlus: return 512
        }
    }

    /// Comprehensive summary of Apple Silicon capabilities for diagnostics and Settings.
    public var hardwareSummary: String {
        var engines: [String] = []
        if supportsHardwareH264 { engines.append("H.264") }
        if supportsHardwareHEVC10Bit { engines.append("HEVC 10-bit") }
        if supportsHardwareProRes { engines.append("ProRes") }
        if supportsHardwareAV1Decode { engines.append("AV1 HW") }
        let enginesStr = engines.isEmpty ? "Software" : engines.joined(separator: ", ")

        return "\(chipName) • \(physicalMemoryGB) GB Unified Memory • \(activeCores) Cores • \(gpuFamilyName) • Media Engines: \(enginesStr)"
    }

    // MARK: - Process & Display Metrics

    public var memoryFootprintMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 0.0
    }

    public var displayRefreshRate: Int {
        guard let screen = NSScreen.main else { return 60 }
        let maxFPS = screen.maximumFramesPerSecond
        return maxFPS > 0 ? maxFPS : 60
    }

    public var isProMotionActive: Bool {
        return displayRefreshRate >= 120
    }

    private static func querySysctlString(_ name: String) -> String? {
        var size: Int = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
