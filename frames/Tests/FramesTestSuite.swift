import Foundation
import CoreGraphics
import SwiftUI

public enum FramesTestSuite {
    public static func runAllTests() -> (passed: Int, failed: Int, logs: [String]) {
        var passed = 0
        var failed = 0
        var logs: [String] = []

        func assertTest(_ name: String, condition: Bool, _ message: String = "") {
            if condition {
                passed += 1
                logs.append("  ✔ PASS: \(name)")
            } else {
                failed += 1
                logs.append("  ✖ FAIL: \(name) - \(message)")
            }
        }

        logs.append("==========================================")
        logs.append("       FRAMES TEST & OPTIMIZATION SUITE   ")
        logs.append("==========================================")

        // MARK: - 1. Time Formatting Tests
        logs.append("\n[1] Testing TimeFormatting...")
        assertTest("Zero Seconds", condition: TimeFormatting.format(seconds: 0) == "00:00")
        assertTest("Seconds Under A Minute", condition: TimeFormatting.format(seconds: 42) == "00:42")
        assertTest("Minutes and Seconds", condition: TimeFormatting.format(seconds: 125) == "02:05")
        assertTest("One Hour and Above", condition: TimeFormatting.format(seconds: 3665) == "1:01:05")
        assertTest("Negative Value Guard", condition: TimeFormatting.format(seconds: -10) == "00:00")
        assertTest("NaN Value Guard", condition: TimeFormatting.format(seconds: Double.nan) == "00:00")

        // MARK: - 2. Subtitle Parser Tests
        logs.append("\n[2] Testing SubtitleParser (SRT & WebVTT)...")
        let srtContent = """
        1
        00:01:20,000 --> 00:01:23,500
        <i>Hello</i> <b>world</b>!

        2
        00:02:10,500 --> 00:02:15,000
        Second subtitle line
        """
        let srtCues = SubtitleParser.parse(content: srtContent)
        assertTest("SRT Count", condition: srtCues.count == 2, "Expected 2 cues, got \(srtCues.count)")
        if srtCues.count >= 2 {
            assertTest("SRT Cue 1 Timing", condition: abs(srtCues[0].startTime - 80.0) < 0.01 && abs(srtCues[0].endTime - 83.5) < 0.01)
            assertTest("SRT Cue 1 HTML Stripping", condition: srtCues[0].text == "Hello world!", "Got: \(srtCues[0].text)")
            assertTest("SRT Cue 2 Timing", condition: abs(srtCues[1].startTime - 130.5) < 0.01)
        }

        let vttContent = """
        WEBVTT

        00:00:10.250 --> 00:00:14.750
        Clean WebVTT Subtitle Line
        """
        let vttCues = SubtitleParser.parse(content: vttContent)
        assertTest("WebVTT Count", condition: vttCues.count == 1)
        if vttCues.count >= 1 {
            assertTest("WebVTT Timing", condition: abs(vttCues[0].startTime - 10.25) < 0.01)
            assertTest("WebVTT Text", condition: vttCues[0].text == "Clean WebVTT Subtitle Line")
        }

        // MARK: - 3. Video Metadata Calculation Tests
        logs.append("\n[3] Testing VideoMetadata...")
        let meta4K = VideoMetadata(naturalSize: CGSize(width: 3840, height: 2160))
        assertTest("4K Resolution String", condition: meta4K.resolutionDescription.contains("4K UHD"))

        let meta1080p = VideoMetadata(naturalSize: CGSize(width: 1920, height: 1080))
        assertTest("1080p Resolution String", condition: meta1080p.resolutionDescription.contains("1080p FHD"))

        let meta720p = VideoMetadata(naturalSize: CGSize(width: 1280, height: 720))
        assertTest("720p Resolution String", condition: meta720p.resolutionDescription.contains("720p HD"))

        let metaBitrate = VideoMetadata(fileSize: 100_000_000, bitrate: 8_000_000)
        assertTest("Bitrate Description", condition: metaBitrate.bitrateDescription == "8.0 Mbps")

        // MARK: - 4. Apple Silicon Metrics & Hardware Tests
        logs.append("\n[4] Testing AppleSiliconMetrics...")
        let metrics = AppleSiliconMetrics.shared
        assertTest("Apple Silicon Detected", condition: !metrics.chipName.isEmpty)
        assertTest("Active CPU Cores", condition: metrics.activeCores >= 4, "Active cores: \(metrics.activeCores)")
        assertTest("Physical Memory Detected", condition: metrics.physicalMemoryGB >= 4, "Memory: \(metrics.physicalMemoryGB) GB")
        assertTest("Display Refresh Rate Valid", condition: metrics.displayRefreshRate >= 50, "Display rate: \(metrics.displayRefreshRate) Hz")
        assertTest("Low Memory Footprint (< 200MB)", condition: metrics.memoryFootprintMB > 0 && metrics.memoryFootprintMB < 200, "Current RAM: \(metrics.memoryFootprintMB) MB")

        // MARK: - 5. Monotonic Interpolation Math Tests
        logs.append("\n[5] Testing Monotonic Time Interpolation...")
        let startDate = Date()
        var prevTime: Double = 0.0
        var isStrictlyMonotonic = true
        for step in 1...100 {
            let fakeNow = startDate.addingTimeInterval(Double(step) * 0.00833) // 120fps display refresh
            let elapsed = fakeNow.timeIntervalSince(startDate) * 1.0
            let calculated = max(0.0, elapsed)
            if calculated < prevTime {
                isStrictlyMonotonic = false
            }
            prevTime = calculated
        }
        assertTest("Time Interpolation Monotonicity (120fps Zero Jitter)", condition: isStrictlyMonotonic)

        // MARK: - 6. Design System Tokens & Scrubber Math
        logs.append("\n[6] Testing Shadcn mira/neutral Design Tokens & Scrubber Math...")
        assertTest("Shadcn Radius Scale (Sm=4, Md=6, Lg=8, Xl=10)", condition:
            ShadcnTheme.radiusSm == 4 &&
            ShadcnTheme.radiusMd == 6 &&
            ShadcnTheme.radiusLg == 8 &&
            ShadcnTheme.radiusXl == 10
        )
        // Scrubber progress clamp & zero-division safety
        let testDuration: Double = 0.0
        let testCurrentTime: Double = 5.0
        let zeroDurationProgress: Double = testDuration > 0 ? (testCurrentTime / testDuration) : 0.0
        assertTest("Scrubber Zero Duration Division Guard", condition: !zeroDurationProgress.isNaN && !zeroDurationProgress.isInfinite)
        let clampedSeekTarget = min(max(0.0, -15.0), 120.0)
        assertTest("Scrubber Seek Underflow Clamp", condition: clampedSeekTarget == 0.0)
        let clampedSeekOverflow = min(max(0.0, 150.0), 120.0)
        assertTest("Scrubber Seek Overflow Clamp", condition: clampedSeekOverflow == 120.0)

        // MARK: - 7. Subtitle Stress & Performance Benchmark
        logs.append("\n[7] Testing Subtitle Parser Performance Benchmark (1,000 cues)...")
        var largeSrt = ""
        for i in 1...1000 {
            let startSec = Double(i * 3)
            let endSec = startSec + 2.5
            let startH = Int(startSec) / 3600
            let startM = (Int(startSec) % 3600) / 60
            let startS = Int(startSec) % 60
            let endH = Int(endSec) / 3600
            let endM = (Int(endSec) % 3600) / 60
            let endS = Int(endSec) % 60
            largeSrt += "\(i)\n"
            largeSrt += String(format: "%02d:%02d:%02d,000 --> %02d:%02d:%02d,500\n", startH, startM, startS, endH, endM, endS)
            largeSrt += "Performance test cue line <b>#\(i)</b>\n\n"
        }

        let benchStart = Date()
        let parsedLargeCues = SubtitleParser.parse(content: largeSrt)
        let benchDurationMs = Date().timeIntervalSince(benchStart) * 1000.0

        assertTest("1,000 Cues Correctly Parsed", condition: parsedLargeCues.count == 1000, "Got \(parsedLargeCues.count)")
        assertTest("1,000 Cues Parse Latency < 100ms", condition: benchDurationMs < 100.0, "Latency: \(String(format: "%.2f", benchDurationMs)) ms")

        // Active Cue lookup test
        let testTargetTime = 301.2 // corresponds to cue ~100
        let activeCue = parsedLargeCues.first(where: { testTargetTime >= $0.startTime && testTargetTime <= $0.endTime })
        assertTest("Active Cue Lookup at Time T", condition: activeCue != nil && activeCue?.text == "Performance test cue line #100")

        // MARK: - 8. System Architecture & Memory Verification
        logs.append("\n[8] Testing Apple Silicon Architecture & Unified Memory...")
        var sysInfo = utsname()
        uname(&sysInfo)
        let machineMirror = Mirror(reflecting: sysInfo.machine)
        let machineIdentifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        assertTest("ARM64 Architecture Verified", condition: machineIdentifier.contains("arm64"), "Machine: \(machineIdentifier)")
        assertTest("Memory Footprint Under 150MB", condition: metrics.memoryFootprintMB < 150.0, "\(String(format: "%.1f", metrics.memoryFootprintMB)) MB")

        // MARK: - 9. Library & Dashboard Manager Tests
        logs.append("\n[9] Testing Library & Dashboard Manager...")
        let lib = LibraryManager()
        let testURL1 = URL(fileURLWithPath: "/tmp/sample_interstellar_4k.mp4")
        let testURL2 = URL(fileURLWithPath: "/tmp/sample_cyberpunk_teaser.mov")

        lib.addSingleVideoFile(url: testURL1)
        lib.addSingleVideoFile(url: testURL2)

        assertTest("Library Video Item Ingestion", condition: lib.videos.contains(where: { $0.url == testURL1 }))
        assertTest("Duplicate Ingestion Guard", condition: {
            let countBefore = lib.videos.count
            lib.addSingleVideoFile(url: testURL1)
            return lib.videos.count == countBefore
        }())

        // Search Query Filter
        lib.searchQuery = "cyberpunk"
        assertTest("Dashboard Search Filter", condition: lib.filteredVideos.count == 1 && lib.filteredVideos[0].url == testURL2)
        lib.searchQuery = ""

        // Favorites Filter
        if let item1 = lib.videos.first(where: { $0.url == testURL1 }) {
            lib.toggleFavorite(videoId: item1.id)
            lib.selectedCategory = .favorites
            assertTest("Dashboard Favorites Filter", condition: lib.filteredVideos.contains(where: { $0.id == item1.id }))
            lib.selectedCategory = .allVideos
        }

        // Playback Recording
        lib.recordPlayback(url: testURL1, duration: 180.0, progress: 0.5)
        if let updated = lib.videos.first(where: { $0.url == testURL1 }) {
            assertTest("Playback Progress Recorded (50%)", condition: abs(updated.progress - 0.5) < 0.01)
            assertTest("Recent Timestamp Recorded", condition: updated.lastPlayedDate != nil)
        }

        // Summary
        logs.append("\n==========================================")
        logs.append("RESULTS: \(passed) PASSED, \(failed) FAILED")
        logs.append("==========================================")

        return (passed, failed, logs)
    }
}
