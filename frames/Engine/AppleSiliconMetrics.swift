import Foundation
import AppKit
import Darwin

public final class AppleSiliconMetrics: @unchecked Sendable {
    public static let shared = AppleSiliconMetrics()

    public let chipName: String
    public let physicalMemoryGB: Int
    public let activeCores: Int

    private init() {
        self.chipName = Self.querySysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        self.physicalMemoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        self.activeCores = ProcessInfo.processInfo.activeProcessorCount
    }

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
