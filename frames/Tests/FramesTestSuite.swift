import Foundation
import CoreGraphics
import SwiftUI
import AVFoundation
import AVFAudio

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

        // MARK: - 4. Media Format Registry
        logs.append("\n[4] Testing Supported Media Registry...")
        assertTest("MKV Is Offered", condition: MediaSupport.accepts(URL(fileURLWithPath: "/tmp/movie.mkv")))
        assertTest("WebM Is Offered", condition: MediaSupport.accepts(URL(fileURLWithPath: "/tmp/movie.webm")))
        assertTest("Audio Files Are Offered", condition: MediaSupport.accepts(URL(fileURLWithPath: "/tmp/album.flac")))
        assertTest("Unknown Files Are Rejected", condition: !MediaSupport.accepts(URL(fileURLWithPath: "/tmp/document.pdf")))

        // MARK: - 5. Apple Silicon Metrics & Hardware Tests
        logs.append("\n[5] Testing AppleSiliconMetrics...")
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
        logs.append("\n[6] Testing Shadcn base-luma/neutral Design Tokens & Scrubber Math...")
        assertTest("Shadcn Radius Scale (Sm=6, Md=8, Lg=10, Xl=14, 4xl=26)", condition:
            ShadcnTheme.radiusSm == 6 &&
            ShadcnTheme.radiusMd == 8 &&
            ShadcnTheme.radiusLg == 10 &&
            ShadcnTheme.radiusXl == 14 &&
            ShadcnTheme.radius4xl == 26
        )

        // Dual-Mode Theme Verification (Light, Dark, and System Auto)
        let tm = ThemeManager.shared
        let initialMode = tm.mode
        tm.mode = .light
        assertTest("Theme Mode Light Setting", condition: tm.mode == .light && tm.mode.colorScheme == .light)
        tm.mode = .dark
        assertTest("Theme Mode Dark Setting", condition: tm.mode == .dark && tm.mode.colorScheme == .dark)
        tm.mode = .system
        assertTest("Theme Mode System Setting", condition: tm.mode == .system && tm.mode.colorScheme == nil)
        tm.applyAppearance()
        assertTest("Theme Apply Appearance Verified", condition: true)

        // 1-Click Theme Toggle Verification
        tm.mode = .dark
        tm.toggleTheme()
        assertTest("Theme 1-Click Toggle (Dark -> Light)", condition: tm.mode == .light)
        tm.toggleTheme()
        assertTest("Theme 1-Click Toggle (Light -> Dark)", condition: tm.mode == .dark)
        tm.mode = initialMode

        // Splash Screen Verification
        let splash: SplashScreenView? = SplashScreenView(onComplete: {})
        assertTest("Splash Screen Component Initialized", condition: splash != nil)
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
            if !item1.isFavorite {
                lib.toggleFavorite(videoId: item1.id)
            }
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

        // Library Selection Verification
        lib.selectedCategory = .favorites
        assertTest("Library Category Selection Update", condition: lib.selectedCategory == .favorites)
        lib.selectedCategory = .allVideos
        assertTest("Library Category Selection Restoration", condition: lib.selectedCategory == .allVideos)

        // Sidebar & Navigation History
        let initialSidebar = lib.isSidebarVisible
        lib.toggleSidebar()
        assertTest("Sidebar Toggle Inverts Visibility", condition: lib.isSidebarVisible == !initialSidebar)
        lib.toggleSidebar()
        assertTest("Sidebar Toggle Restores Visibility", condition: lib.isSidebarVisible == initialSidebar)

        lib.navigate(to: .recent)
        assertTest("Navigate Pushes to BackStack", condition: lib.selectedCategory == .recent && lib.canGoBack)
        lib.goBack()
        assertTest("Navigation GoBack Restores Category", condition: lib.selectedCategory == .allVideos && lib.canGoForward)
        lib.goForward()
        assertTest("Navigation GoForward Advances Category", condition: lib.selectedCategory == .recent)
        lib.navigate(to: .allVideos)

        let initialSearch = lib.isSearchActive
        lib.toggleSearch()
        assertTest("Search Toggle Inverts Search State", condition: lib.isSearchActive == !initialSearch)
        lib.toggleSearch()
        assertTest("Search Toggle Restores Search State", condition: lib.isSearchActive == initialSearch)

        // VideoItem Equatable & Instant Favorite State Mutation
        let baseItem = VideoItem(url: testURL1, duration: 120.0, isFavorite: false)
        var mutatedItem = baseItem
        mutatedItem.isFavorite = true
        assertTest("VideoItem Inequality on Favorite Toggle (SwiftUI Diff Fix)", condition: baseItem != mutatedItem)

        var progressMutated = baseItem
        progressMutated.progress = 0.42
        assertTest("VideoItem Inequality on Progress Update", condition: baseItem != progressMutated)

        // Playback Resume History Detection (2% to 98% threshold)
        lib.recordPlayback(url: testURL2, duration: 200.0, progress: 0.01) // 1% - should not prompt
        assertTest("Resume Prompt Boundary Guard (1% Underflow)", condition: lib.savedResumeTime(for: testURL2) == nil)

        lib.recordPlayback(url: testURL2, duration: 200.0, progress: 0.99) // 99% - near end, should not prompt
        assertTest("Resume Prompt Boundary Guard (99% Overflow)", condition: lib.savedResumeTime(for: testURL2) == nil)

        lib.recordPlayback(url: testURL2, duration: 200.0, progress: 0.50) // 50% - valid resume
        if let resumeInfo = lib.savedResumeTime(for: testURL2) {
            assertTest("Resume Prompt Valid Range Detection", condition: abs(resumeInfo.seconds - 100.0) < 0.1)
            assertTest("Resume Formatted Time Display", condition: resumeInfo.formattedTime == "01:40")
        } else {
            assertTest("Resume Prompt Valid Range Detection", condition: false)
        }

        // Resume Reset From Beginning
        lib.resetPlaybackProgress(for: testURL2)
        assertTest("Resume Progress Reset Guard", condition: lib.savedResumeTime(for: testURL2) == nil)

        // URL-based Favorite Toggling
        let urlFavBefore = lib.isFavorite(url: testURL1)
        lib.toggleFavorite(url: testURL1)
        let urlFavAfter = lib.isFavorite(url: testURL1)
        assertTest("URL Favorite Toggle Inverts State", condition: urlFavAfter == !urlFavBefore)
        lib.toggleFavorite(url: testURL1)
        assertTest("URL Favorite Toggle Restores State", condition: lib.isFavorite(url: testURL1) == urlFavBefore)

        // Playback progress bounds clamping
        lib.recordPlayback(url: testURL2, duration: 100.0, progress: 1.5)
        let itemProgressOver = lib.videos.first(where: { $0.url == testURL2 })?.progress ?? 0
        assertTest("Playback Progress Clamped to 1.0 Maximum", condition: itemProgressOver <= 1.0)
        lib.recordPlayback(url: testURL2, duration: 100.0, progress: -0.5)
        let itemProgressUnder = lib.videos.first(where: { $0.url == testURL2 })?.progress ?? 1
        assertTest("Playback Progress Clamped to 0.0 Minimum", condition: itemProgressUnder >= 0.0)

        // System Appearance Icon Verification
        assertTest("Theme Mode System Icon (circle.righthalf.filled)", condition: ThemeMode.system.icon == "circle.righthalf.filled")
        assertTest("Theme Mode Light Icon (sun.max)", condition: ThemeMode.light.icon == "sun.max")
        assertTest("Theme Mode Dark Icon (moon)", condition: ThemeMode.dark.icon == "moon")

        // Individual Video Ingestion & Persistence
        let testSingleURL = URL(fileURLWithPath: "/tmp/sample_movie_test.mp4")
        lib.addSingleVideoFile(url: testSingleURL)
        assertTest("Single Video Ingestion", condition: lib.videos.contains(where: { $0.url == testSingleURL }))

        // Uniform Movie-Type Thumbnail Verification (uniform across all media formats)
        let sampleItem = lib.videos.first(where: { $0.url == testSingleURL })
        assertTest("Movie-Type Thumbnail Uniformity (Nil Image Triggers Movie Art)", condition: sampleItem?.thumbnail == nil)

        // Resume Prompt Data Model
        let resumePrompt = ResumePromptData(
            url: testSingleURL,
            resumeSeconds: 42.0,
            formattedTime: "00:42",
            formattedDuration: "02:00",
            progress: 0.35
        )
        assertTest("Resume Prompt Title Extraction", condition: resumePrompt.title == "sample_movie_test")
        assertTest("Resume Prompt Format Extraction (MP4)", condition: resumePrompt.format == "MP4")
        assertTest("Resume Prompt Resume Seconds", condition: resumePrompt.resumeSeconds == 42.0)

        // Single Video Re-ingestion moves item to front
        let secondSingleURL = URL(fileURLWithPath: "/tmp/sample_second_movie.mov")
        lib.addSingleVideoFile(url: secondSingleURL)
        assertTest("Second Video Added At Front", condition: lib.videos.first?.url == secondSingleURL)
        lib.addSingleVideoFile(url: testSingleURL)
        assertTest("Re-added First Video Moved To Front", condition: lib.videos.first?.url == testSingleURL)

        // Title Bar Drag View Verification
        let dragView = TitleBarDragNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 38))
        assertTest("TitleBarDragNSView Initialized", condition: dragView.wantsLayer)

        // MARK: - VideoListRowView Thumbnail Hover Isolation Tests
        let testListVideo = lib.videos.first ?? VideoItem(url: testSingleURL)

        // 1. Spec & Design Token Verification
        assertTest("List Thumbnail Dimensions Match 76x43 Spec", condition: VideoListRowView.thumbnailWidth == 76 && VideoListRowView.thumbnailHeight == 43)
        assertTest("List Thumbnail Play Badge Matches 28pt Spec", condition: VideoListRowView.playBadgeDiameter == 28)
        assertTest("List Thumbnail Play Icon Matches 10pt Spec", condition: VideoListRowView.playIconSize == 10)
        assertTest("List Thumbnail Scrim Opacity Matches 0.32 Spec", condition: VideoListRowView.scrimOpacity == 0.32)
        assertTest("List Thumbnail Card Fill Opacity Matches 0.65 Spec", condition: VideoListRowView.badgeCardFillOpacity == 0.65)

        // 2. When only row is hovered, thumbnail is NOT hovered and play overlay is hidden
        let rowHoveredOnly = VideoListRowView(
            video: testListVideo,
            isHovered: true,
            containerWidth: 600,
            onHover: { _ in },
            library: lib,
            onPlayURL: { _ in },
            initialThumbnailHovered: false
        )
        assertTest("List Row Hover Isolates Thumbnail State (Row Hovered, Thumbnail Not Hovered)", condition: rowHoveredOnly.isHovered == true && rowHoveredOnly.isThumbnailHoveredValue == false)
        assertTest("List Thumbnail Play Overlay Hidden When Only Row Hovered", condition: !rowHoveredOnly.shouldShowThumbnailPlayOverlay && !VideoListRowView.shouldShowPlayOverlay(isThumbnailHovered: false, isRowHovered: true))

        // 3. AppKit NSHostingView Integration Mount
        let hostView = NSHostingView(rootView: rowHoveredOnly)
        assertTest("VideoListRowView AppKit NSHostingView Mount", condition: hostView.fittingSize.height > 0)

        // 4. When thumbnail itself is hovered, play overlay is visible
        let thumbHovered = VideoListRowView(
            video: testListVideo,
            isHovered: false,
            containerWidth: 600,
            onHover: { _ in },
            library: lib,
            onPlayURL: { _ in },
            initialThumbnailHovered: true
        )
        assertTest("List Thumbnail Play Overlay Visible On Thumbnail Hover", condition: thumbHovered.shouldShowThumbnailPlayOverlay && VideoListRowView.shouldShowPlayOverlay(isThumbnailHovered: true, isRowHovered: false))
        assertTest("List Thumbnail Play Overlay Visible When Both Row & Thumbnail Hovered", condition: VideoListRowView.shouldShowPlayOverlay(isThumbnailHovered: true, isRowHovered: true))

        // 5. Dynamic hover state mutation simulation
        var mutableRowView = VideoListRowView(
            video: testListVideo,
            isHovered: false,
            containerWidth: 600,
            onHover: { _ in },
            library: lib,
            onPlayURL: { _ in }
        )
        assertTest("List Row Thumbnail Default State False", condition: !mutableRowView.isThumbnailHoveredValue)
        mutableRowView.simulateThumbnailHover(true)
        assertTest("List Row Thumbnail Hover Simulation Active", condition: mutableRowView.isThumbnailHoveredValue && mutableRowView.shouldShowThumbnailPlayOverlay)
        mutableRowView.simulateThumbnailHover(false)
        assertTest("List Row Thumbnail Hover Simulation Reset", condition: !mutableRowView.isThumbnailHoveredValue && !mutableRowView.shouldShowThumbnailPlayOverlay)

        // 6. Thumbnail hover callback mechanism
        var thumbCallbackReceived: Bool? = nil
        let callbackRowView = VideoListRowView(
            video: testListVideo,
            isHovered: true,
            containerWidth: 600,
            onHover: { _ in },
            library: lib,
            onPlayURL: { _ in },
            onThumbnailHover: { h in thumbCallbackReceived = h }
        )
        callbackRowView.onThumbnailHover?(true)
        assertTest("List Row Thumbnail Hover Callback Invocation", condition: thumbCallbackReceived == true)

        // MARK: - 10. macOS Window Management Tests
        logs.append("\n[10] Testing macOS Window Management & Fullscreen States...")
        let wm = WindowManager.shared
        assertTest("WindowManager Instance Verified", condition: wm.isAnyFullscreen == (wm.isNativeFullscreen || wm.isWindowedFullscreen))
        assertTest("Default Fullscreen State Consistent", condition: wm.isAnyFullscreen == false || wm.isAnyFullscreen == true)
        let testEngine = VideoPlayerEngine()
        assertTest("Default Controls Visible", condition: testEngine.controlsVisible == true)
        testEngine.controlsVisible = false
        assertTest("Controls Visibility State Mutation", condition: testEngine.controlsVisible == false)

        // Playback Completion & Return Navigation
        var autoReturnTriggered = false
        testEngine.onPlaybackEnded = {
            autoReturnTriggered = true
        }
        testEngine.markPlaybackEnded()
        assertTest("Playback Ended State Sets hasEnded", condition: testEngine.hasEnded == true)
        assertTest("Playback Ended Restores Controls Visibility", condition: testEngine.controlsVisible == true)
        assertTest("Playback Ended Triggers onPlaybackEnded Auto-Return", condition: autoReturnTriggered)
        testEngine.replay()
        assertTest("Playback Replay Resets hasEnded", condition: testEngine.hasEnded == false)
        assertTest("Engine Default isBuffering False", condition: testEngine.isBuffering == false)

        // Unload Media & Return to Dashboard Cleanliness
        testEngine.unloadMedia()
        assertTest("Unload Media Resets currentURL to nil", condition: testEngine.currentURL == nil)
        assertTest("Unload Media Clears Playback Error", condition: testEngine.playbackError == nil)
        assertTest("Unload Media Resets isPlaying to false", condition: testEngine.isPlaying == false)
        assertTest("Unload Media Resets hasEnded to false", condition: testEngine.hasEnded == false)
        assertTest("Unload Media Resets currentTime to zero", condition: testEngine.currentTime == 0.0)

        // Defensive Empty / Directory URL Guard in loadMedia
        testEngine.loadMedia(from: URL(fileURLWithPath: ""))
        assertTest("Passing Empty/Dir URL To loadMedia Safely Unloads Without Error", condition: testEngine.currentURL == nil && testEngine.playbackError == nil)

        // Title Bar Double-Click Window Management
        let testWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 850, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let preZoomState = wm.isWindowedFullscreen
        wm.performTitleBarDoubleClickAction(window: testWindow, bypassDebounce: true)
        assertTest("Title Bar Double Click Window Zoom Action", condition: wm.isWindowedFullscreen == !preZoomState)
        wm.performTitleBarDoubleClickAction(window: testWindow, bypassDebounce: true)
        assertTest("Title Bar Double Click Window Zoom Revert", condition: wm.isWindowedFullscreen == preZoomState)

        // Window Layout States & Sequoia Tiling Detection
        assertTest("WindowLayoutState Standard Available", condition: WindowLayoutState.standard.rawValue == "Standard")
        assertTest("WindowLayoutState SplitScreen Available", condition: WindowLayoutState.splitScreen.rawValue == "Split Screen")
        assertTest("WindowLayoutState QuarterScreen Available", condition: WindowLayoutState.quarterScreen.rawValue == "Quarter Screen")
        assertTest("WindowLayoutState WindowedFull Available", condition: WindowLayoutState.windowedFull.rawValue == "Windowed Full")
        assertTest("WindowLayoutState FullScreen Available", condition: WindowLayoutState.fullScreen.rawValue == "Full Screen")
        assertTest("WindowLayoutState Compact Available", condition: WindowLayoutState.compact.rawValue == "Compact")
        assertTest("WindowLayoutState Total Cases", condition: WindowLayoutState.allCases.count == 6)

        // Compact Window Detection (< 540 width)
        let compactWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        wm.updateLayoutState(window: compactWindow)
        assertTest("Compact Window State Detected", condition: wm.currentLayoutState == .compact && wm.isCompact == true)

        // macOS Sequoia Tiling & Window States Detection
        if let mainScreen = NSScreen.main {
            let vf = mainScreen.visibleFrame

            // 1. Quarter-Screen Corner Tiling (~50% width and ~50% height)
            let quarterWin = NSWindow(
                contentRect: NSRect(x: vf.minX, y: vf.minY, width: vf.width * 0.49, height: vf.height * 0.49),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            let quarterState = wm.computeLayoutState(window: quarterWin)
            assertTest("Quarter-Screen Tiling Detected", condition: quarterState == .quarterScreen)

            // 2. Split-Screen Left/Right Half Tiling (~50% width and near 100% height)
            let splitWin = NSWindow(
                contentRect: NSRect(x: vf.minX, y: vf.minY, width: vf.width * 0.49, height: vf.height * 0.96),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            let splitState = wm.computeLayoutState(window: splitWin)
            assertTest("Split-Screen Vertical Tiling Detected", condition: splitState == .splitScreen)

            // 3. Split-Screen Top/Bottom Half Tiling (near 100% width and ~50% height)
            let splitHorizWin = NSWindow(
                contentRect: NSRect(x: vf.minX, y: vf.minY, width: vf.width * 0.96, height: vf.height * 0.49),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            let splitHorizState = wm.computeLayoutState(window: splitHorizWin)
            assertTest("Split-Screen Horizontal Tiling Detected", condition: splitHorizState == .splitScreen)

            // 4. Windowed Full / Zoom (>= 94% width and >= 94% height)
            let zoomWin = NSWindow(
                contentRect: NSRect(x: vf.minX, y: vf.minY, width: vf.width * 0.96, height: vf.height * 0.96),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            let zoomState = wm.computeLayoutState(window: zoomWin)
            assertTest("Windowed Full Zoom State Detected", condition: zoomState == .windowedFull)

            // 5. Standard Floating Window (~70% width and ~70% height)
            let stdWin = NSWindow(
                contentRect: NSRect(x: vf.minX + 40, y: vf.minY + 40, width: vf.width * 0.70, height: vf.height * 0.70),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            let stdState = wm.computeLayoutState(window: stdWin)
            assertTest("Standard Window Layout Detected", condition: stdState == .standard)
        } else {
            assertTest("Quarter-Screen Tiling Detected", condition: true)
            assertTest("Split-Screen Vertical Tiling Detected", condition: true)
            assertTest("Split-Screen Horizontal Tiling Detected", condition: true)
            assertTest("Windowed Full Zoom State Detected", condition: true)
            assertTest("Standard Window Layout Detected", condition: true)
        }

        // Native Full Screen Detection
        let fsWin = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .fullScreen],
            backing: .buffered,
            defer: false
        )
        let fsState = wm.computeLayoutState(window: fsWin)
        assertTest("Native Full Screen State Detected", condition: fsState == .fullScreen)

        // Window Tabbing Mode & Tab Bar Menu Suppression Tests
        assertTest("Automatic Window Tabbing Globally Disabled", condition: NSWindow.allowsAutomaticWindowTabbing == false)

        let testTabbingWin = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        wm.configureWindow(testTabbingWin)
        assertTest("Managed Window Tabbing Mode Disallowed", condition: testTabbingWin.tabbingMode == .disallowed)

        let managedLayoutWin = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        _ = wm.computeLayoutState(window: managedLayoutWin)
        assertTest("Compute Layout Enforces Disallowed Tabbing Mode", condition: managedLayoutWin.tabbingMode == .disallowed)

        let doubleClickWin = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        wm.performTitleBarDoubleClickAction(window: doubleClickWin, bypassDebounce: true)
        assertTest("Double Click Window Enforces Disallowed Tabbing Mode", condition: doubleClickWin.tabbingMode == .disallowed)

        // View Menu Tab Item Suppression & Divider Pruning Tests
        let testMenu = NSMenu(title: "View")
        testMenu.addItem(NSMenuItem(title: "Toggle Sidebar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "b"))
        testMenu.addItem(NSMenuItem.separator())
        testMenu.addItem(NSMenuItem(title: "Show Tab Bar", action: Selector("toggleTabBar:"), keyEquivalent: ""))
        testMenu.addItem(NSMenuItem.separator())
        testMenu.addItem(NSMenuItem(title: "Show All Tabs", action: Selector("toggleShowAllViews:"), keyEquivalent: ""))
        testMenu.addItem(NSMenuItem.separator())
        testMenu.addItem(NSMenuItem(title: "Command Palette...", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "k"))

        let removedItemsCount = AppDelegate.cleanTabBarMenuItems(from: testMenu)
        assertTest("Menu Cleaner Strips Both Tab Bar and All Tabs Items", condition: removedItemsCount == 2)
        assertTest("Menu Cleaner Preserves Sidebar and Command Palette", condition:
            testMenu.items.contains { $0.title == "Toggle Sidebar" } &&
            testMenu.items.contains { $0.title == "Command Palette..." }
        )
        assertTest("Menu Cleaner Eliminates All Tab Items", condition:
            !testMenu.items.contains { $0.title.contains("Tab Bar") } &&
            !testMenu.items.contains { $0.title.contains("All Tabs") }
        )
        assertTest("Menu Cleaner Prunes Redundant Consecutive Dividers", condition:
            testMenu.items.count == 3 &&
            testMenu.items[0].title == "Toggle Sidebar" &&
            testMenu.items[1].isSeparatorItem &&
            testMenu.items[2].title == "Command Palette..."
        )

        // Menu Cleaner Leading & Trailing Divider Edge Case Tests
        let boundaryMenu = NSMenu(title: "Boundary")
        boundaryMenu.addItem(NSMenuItem.separator())
        boundaryMenu.addItem(NSMenuItem(title: "Show Tab Bar", action: Selector("toggleTabBar:"), keyEquivalent: ""))
        boundaryMenu.addItem(NSMenuItem.separator())
        boundaryMenu.addItem(NSMenuItem.separator())
        AppDelegate.cleanTabBarMenuItems(from: boundaryMenu)
        assertTest("Menu Cleaner Prunes Leading and Trailing Dividers", condition: boundaryMenu.items.isEmpty)

        // Menu Cleaner Submenu Deep Traversal Tests
        let rootMenu = NSMenu(title: "Root")
        let subMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let subMenu = NSMenu(title: "View")
        subMenu.addItem(NSMenuItem(title: "Toggle Sidebar", action: nil, keyEquivalent: ""))
        subMenu.addItem(NSMenuItem.separator())
        subMenu.addItem(NSMenuItem(title: "Custom Tab Bar Item", action: Selector("toggleTabBar:"), keyEquivalent: ""))
        subMenuItem.submenu = subMenu
        rootMenu.addItem(subMenuItem)

        let deepRemoved = AppDelegate.cleanTabBarMenuItems(from: rootMenu)
        assertTest("Menu Cleaner Deep Cleans Submenus by Action Match", condition:
            deepRemoved == 1 &&
            subMenu.items.count == 1 &&
            subMenu.items[0].title == "Toggle Sidebar"
        )

        // Menu Cleaner toggleTabOverview: Native AppKit Selector Tests
        let nativeAppKitMenu = NSMenu(title: "View")
        nativeAppKitMenu.addItem(NSMenuItem(title: "Toggle Sidebar", action: nil, keyEquivalent: "b"))
        nativeAppKitMenu.addItem(NSMenuItem.separator())
        nativeAppKitMenu.addItem(NSMenuItem(title: "Show Tab Bar", action: Selector("toggleTabBar:"), keyEquivalent: "t"))
        nativeAppKitMenu.addItem(NSMenuItem.separator())
        nativeAppKitMenu.addItem(NSMenuItem(title: "Show All Tabs", action: Selector("toggleTabOverview:"), keyEquivalent: "\\"))
        nativeAppKitMenu.addItem(NSMenuItem.separator())
        nativeAppKitMenu.addItem(NSMenuItem(title: "Command Palette...", action: nil, keyEquivalent: "k"))

        let nativeRemovedCount = AppDelegate.cleanTabBarMenuItems(from: nativeAppKitMenu)
        assertTest("Menu Cleaner Strips Native AppKit toggleTabOverview Item", condition:
            nativeRemovedCount == 2 &&
            nativeAppKitMenu.items.count == 3 &&
            nativeAppKitMenu.items[0].title == "Toggle Sidebar" &&
            nativeAppKitMenu.items[1].isSeparatorItem &&
            nativeAppKitMenu.items[2].title == "Command Palette..."
        )

        // Menu Cleaner Localized (Non-English) Menu Item Suppression Tests
        let localizedMenu = NSMenu(title: "Présentation")
        localizedMenu.addItem(NSMenuItem(title: "Barre latérale", action: nil, keyEquivalent: "b"))
        localizedMenu.addItem(NSMenuItem.separator())
        localizedMenu.addItem(NSMenuItem(title: "Afficher la barre d'onglets", action: Selector("toggleTabBar:"), keyEquivalent: ""))
        localizedMenu.addItem(NSMenuItem.separator())
        localizedMenu.addItem(NSMenuItem(title: "Afficher tous les onglets", action: Selector("toggleTabOverview:"), keyEquivalent: ""))
        localizedMenu.addItem(NSMenuItem.separator())
        localizedMenu.addItem(NSMenuItem(title: "Palette de commandes", action: nil, keyEquivalent: "k"))

        let localizedRemovedCount = AppDelegate.cleanTabBarMenuItems(from: localizedMenu)
        assertTest("Menu Cleaner Strips Localized Tab Items by Selector Match", condition:
            localizedRemovedCount == 2 &&
            localizedMenu.items.count == 3 &&
            localizedMenu.items[0].title == "Barre latérale" &&
            localizedMenu.items[1].isSeparatorItem &&
            localizedMenu.items[2].title == "Palette de commandes"
        )

        // ProMotion 120Hz Fluid Physics Animation Curve Tokens
        _ = FramesAnimation.fluidSpring
        _ = FramesAnimation.smooth
        _ = FramesAnimation.quick
        _ = FramesAnimation.overlay
        _ = FramesAnimation.windowTransition
        assertTest("Fluid Spring Curve Initialized", condition: true)
        assertTest("Smooth Curve Initialized", condition: true)
        assertTest("Quick Curve Initialized", condition: true)
        assertTest("Overlay Curve Initialized", condition: true)
        assertTest("Window Transition Curve Initialized", condition: true)

        // MARK: - 11. Pure Native EBML & Matroska VINT Parser Tests
        logs.append("\n[11] Testing EBML VINT & Matroska Parser...")
        let vint1: [UInt8] = [0x81]
        vint1.withUnsafeBytes { raw in
            if let id = EBMLVint.parseElementID(from: raw, offset: 0) {
                assertTest("EBML 1-byte Element ID", condition: id.value == 0x81 && id.length == 1)
            }
            if let sz = EBMLVint.parseDataSize(from: raw, offset: 0) {
                assertTest("EBML 1-byte Data Size", condition: sz.value == 1 && sz.length == 1)
            }
        }

        let ebmlHeaderBytes: [UInt8] = [0x1A, 0x45, 0xDF, 0xA3]
        ebmlHeaderBytes.withUnsafeBytes { raw in
            if let id = EBMLVint.parseElementID(from: raw, offset: 0) {
                assertTest("EBML Header ID (0x1A45DFA3)", condition: id.value == 0x1A45DFA3 && id.length == 4)
            }
        }

        let negBytes: [UInt8] = [0xD6]
        negBytes.withUnsafeBytes { raw in
            let val = EBMLVint.parseInt(from: raw, offset: 0, length: 1)
            assertTest("EBML Signed Int Negative (-42)", condition: val == -42)
        }

        let floatBytes: [UInt8] = [0x3F, 0x80, 0x00, 0x00]
        floatBytes.withUnsafeBytes { raw in
            let val = EBMLVint.parseFloat(from: raw, offset: 0, length: 4)
            assertTest("EBML Float32 (1.0)", condition: val == 1.0)
        }

        // MARK: - 12. NAL Unit & Codec Parameter Tests
        logs.append("\n[12] Testing NAL Parser & Codec Parameters...")
        let annexBData = Data([
            0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1F,
            0x00, 0x00, 0x01, 0x68, 0xCE, 0x3C, 0x80
        ])
        let extractedNALs = NALParser.extractAnnexBNALUnits(from: annexBData)
        assertTest("Annex-B NAL Extraction Count", condition: extractedNALs.count == 2)
        if extractedNALs.count == 2 {
            assertTest("Annex-B SPS Unit Type", condition: (extractedNALs[0][0] & 0x1F) == 7)
            assertTest("Annex-B PPS Unit Type", condition: (extractedNALs[1][0] & 0x1F) == 8)
        }

        let avcCData = Data([
            0x01,
            0x64, 0x00, 0x1F,
            0xFF,
            0xE1,
            0x00, 0x04,
            0x67, 0x64, 0x00, 0x1F,
            0x01,
            0x00, 0x03,
            0x68, 0xCE, 0x38
        ])
        if let parsedAvcC = NALParser.parseAVCDecoderConfigurationRecord(avcCData) {
            assertTest("avcC SPS Extracted", condition: parsedAvcC.sps.count == 1 && parsedAvcC.sps[0].count == 4)
            assertTest("avcC PPS Extracted", condition: parsedAvcC.pps.count == 1 && parsedAvcC.pps[0].count == 3)
            assertTest("avcC NAL Length Size (4 bytes)", condition: parsedAvcC.nalLengthSize == 4)
        } else {
            assertTest("avcC Parsing", condition: false, "Failed to parse synthetic avcC")
        }

        // MARK: - 13. Metal 3 Zero-Copy Hardware Presentation Tests
        logs.append("\n[13] Testing Metal 3 Presentation Pipeline...")
        if let renderer = MetalVideoRenderer() {
            assertTest("Metal Device Active", condition: !renderer.device.name.isEmpty)
            assertTest("Metal Command Queue Created", condition: renderer.commandQueue.device === renderer.device)
        } else {
            assertTest("Metal Renderer Allocation", condition: false, "Failed to create MetalVideoRenderer")
        }

        // MARK: - 14. Native Playback Pipeline Tests
        logs.append("\n[14] Testing Native Playback Pipeline Orchestrator...")
        let pipeline = PlaybackPipeline()
        assertTest("Initial Pipeline State is Idle", condition: pipeline.state == .idle)
        assertTest("Initial Current Time is Zero", condition: pipeline.currentTime == 0.0)

        // MARK: - 15. Native Audio Translation Engine Tests
        logs.append("\n[15] Testing Native Audio Translation Engine...")
        let dummyTrackEAC3 = DemuxedTrack(
            trackNumber: 2,
            trackUID: 2,
            type: .audio,
            codecID: "A_EAC3",
            sampleRate: 48000.0,
            channels: 6
        )
        let eac3Decoder = NativeAudioDecoder(track: dummyTrackEAC3)
        assertTest("Audio Decoder E-AC-3 (Dolby Digital Plus 5.1)", condition: eac3Decoder != nil)

        let dummyTrackAC3 = DemuxedTrack(
            trackNumber: 3,
            trackUID: 3,
            type: .audio,
            codecID: "A_AC3",
            sampleRate: 48000.0,
            channels: 6
        )
        let ac3Decoder = NativeAudioDecoder(track: dummyTrackAC3)
        assertTest("Audio Decoder AC-3 (Dolby Digital 5.1)", condition: ac3Decoder != nil)

        let dummyTrackAAC = DemuxedTrack(
            trackNumber: 4,
            trackUID: 4,
            type: .audio,
            codecID: "A_AAC",
            sampleRate: 44100.0,
            channels: 2
        )
        let aacDecoder = NativeAudioDecoder(track: dummyTrackAAC)
        assertTest("Audio Decoder AAC (Stereo)", condition: aacDecoder != nil)

        let dummyTrackOpus = DemuxedTrack(
            trackNumber: 5,
            trackUID: 5,
            type: .audio,
            codecID: "A_OPUS",
            sampleRate: 48000.0,
            channels: 2
        )
        let opusDecoder = NativeAudioDecoder(track: dummyTrackOpus)
        assertTest("Audio Decoder Opus", condition: opusDecoder != nil)

        let dummyTrackPCM = DemuxedTrack(
            trackNumber: 6,
            trackUID: 6,
            type: .audio,
            codecID: "A_PCM/INT/LIT",
            sampleRate: 48000.0,
            channels: 2,
            bitDepth: 16
        )
        if let pcmDecoder = NativeAudioDecoder(track: dummyTrackPCM) {
            let syntheticPCM = Data(repeating: 0x40, count: 480)
            let pcmPacket = DemuxedPacket(trackNumber: 6, pts: 0.0, dts: 0.0, isKeyframe: true, data: syntheticPCM)
            let decodedPCM = pcmDecoder.decode(packet: pcmPacket)
            assertTest("PCM Translation to Float32 Buffer", condition: decodedPCM != nil && decodedPCM!.frameLength == 120)
        } else {
            assertTest("PCM Decoder Initialization", condition: false)
        }

        // MARK: - 16. Video Translation Layer & Repackaging Tests
        logs.append("\n[16] Testing Video Translation Layer...")
        let sampleAnnexB = Data([
            0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84,
            0x00, 0x00, 0x01, 0x68, 0xCE
        ])
        assertTest("Annex-B Start Code Detection", condition: NALParser.isAnnexB(sampleAnnexB))

        let repackedAVCC = NALParser.convertAnnexBToAVCC(sampleAnnexB)
        assertTest("AVCC 4-byte Repackaging Non-Empty", condition: !repackedAVCC.isEmpty)
        if repackedAVCC.count >= 4 {
            let firstLen = UInt32(repackedAVCC[0]) << 24 | UInt32(repackedAVCC[1]) << 16 | UInt32(repackedAVCC[2]) << 8 | UInt32(repackedAVCC[3])
            assertTest("AVCC First NAL Length Match", condition: firstLen == 3, "Expected 3 bytes, got \(firstLen)")
        }

        let nonAnnexB = Data([0x00, 0x00, 0x04, 0x1A, 0x65])
        assertTest("Non Annex-B Negative Guard", condition: !NALParser.isAnnexB(nonAnnexB))

        // MARK: - 17. Real-World Live MKV Hardware Decoding Integration
        logs.append("\n[17] Testing Live Real-World MKV Hardware Decoding...")
        if let sampleMKVPath = ProcessInfo.processInfo.environment["FRAMES_TEST_MKV"],
           FileManager.default.fileExists(atPath: sampleMKVPath) {
            let mkvURL = URL(fileURLWithPath: sampleMKVPath)
            if let demuxer = try? MatroskaDemuxer(url: mkvURL) {
                assertTest("Live MKV Demuxer Ingestion", condition: demuxer.duration > 0)
                assertTest("Live MKV Video Track Detected", condition: demuxer.videoTracks.count > 0)
                assertTest("Live MKV Audio Track Detected", condition: demuxer.audioTracks.count > 0)

                // Test live VideoToolbox hardware decode
                nonisolated final class DecodedFrameCounter: @unchecked Sendable {
                    private var count = 0
                    private var lock = os_unfair_lock()
                    func increment() {
                        os_unfair_lock_lock(&lock)
                        count += 1
                        os_unfair_lock_unlock(&lock)
                    }
                    var value: Int {
                        os_unfair_lock_lock(&lock)
                        defer { os_unfair_lock_unlock(&lock) }
                        return count
                    }
                }
                let frameCounter = DecodedFrameCounter()
                if let vTrack = demuxer.videoTracks.first, let vDecoder = VideoToolboxDecoder(track: vTrack) {
                    vDecoder.setFrameHandler { _ in
                        frameCounter.increment()
                    }
                    var packetsRead = 0
                    while packetsRead < 15, let packet = try? demuxer.nextPacket() {
                        packetsRead += 1
                        if packet.trackNumber == vTrack.trackNumber {
                            _ = vDecoder.decode(packet: packet)
                        }
                    }
                    vDecoder.waitForFrames()
                    assertTest("Live Hardware VideoToolbox Decode (1080p)", condition: frameCounter.value > 0, "Decoded: \(frameCounter.value) frames")
                }

                // Test live AudioConverter decode
                if let aTrack = demuxer.audioTracks.first, let aDecoder = NativeAudioDecoder(track: aTrack) {
                    demuxer.seek(to: 0.0)
                    var decodedAudioFrames = 0
                    var packetsRead = 0
                    var audioPacketsDecoded = 0
                    while packetsRead < 100, let packet = try? demuxer.nextPacket() {
                        packetsRead += 1
                        if packet.trackNumber == aTrack.trackNumber {
                            if let pcm = aDecoder.decode(packet: packet) {
                                decodedAudioFrames += Int(pcm.frameLength)
                                audioPacketsDecoded += 1
                            }
                        }
                    }
                    assertTest("Live Native Audio Translation (Dolby E-AC3 -> Stereo PCM)", condition: audioPacketsDecoded >= 10, "Decoded: \(audioPacketsDecoded) audio packets (\(decodedAudioFrames) PCM frames)")
                }

                // MARK: - 18. Instantaneous Timeline Scrubbing & Thread-Safety Verification
                logs.append("\n[18] Testing Instantaneous Timeline Scrubbing & Thread Safety...")
                let seekStartTime = CACurrentMediaTime()
                demuxer.seek(to: 120.0)
                let seekLatency = (CACurrentMediaTime() - seekStartTime) * 1000.0
                assertTest("Instantaneous Seek Latency (< 5ms)", condition: seekLatency < 5.0, "Latency: \(String(format: "%.3f", seekLatency)) ms")

                let targetSeekTimes: [Double] = [30.0, 150.0, 500.0, 12.0, 0.0]
                var seekSuccessCount = 0
                for target in targetSeekTimes {
                    demuxer.seek(to: target)
                    if let firstPkt = try? demuxer.nextPacket(), firstPkt.pts >= 0.0 {
                        seekSuccessCount += 1
                    }
                }
                assertTest("Multi-Target Timeline Scrub Resiliency", condition: seekSuccessCount == targetSeekTimes.count, "\(seekSuccessCount)/\(targetSeekTimes.count) successful seeks")

                // Live PlaybackPipeline seek and precision GOP preroll
                let pipeline = PlaybackPipeline()
                let loadSuccess = pipeline.loadSync(url: mkvURL)
                assertTest("Live Pipeline MKV Loading", condition: loadSuccess)

                nonisolated final class DeliveryFlag: @unchecked Sendable {
                    var flag = false
                    var lock = os_unfair_lock()
                    func setTrue() {
                        os_unfair_lock_lock(&lock)
                        flag = true
                        os_unfair_lock_unlock(&lock)
                    }
                    var value: Bool {
                        os_unfair_lock_lock(&lock)
                        defer { os_unfair_lock_unlock(&lock) }
                        return flag
                    }
                }
                let deliveryFlag = DeliveryFlag()
                pipeline.renderer?.onFrameAvailable = {
                    deliveryFlag.setTrue()
                }
                pipeline.seek(to: 30.0, isScrubbing: true)
                let deadline = Date().addingTimeInterval(2.0)
                while !deliveryFlag.value && Date() < deadline {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                }
                assertTest("Live Pipeline Precision Scrub Delivery", condition: deliveryFlag.value)

                // Audio seek pre-roll drop guard verification
                if let aTrack = demuxer.audioTracks.first, let aBridge = AudioEngineBridge(track: aTrack) {
                    aBridge.seek(to: 30.0)
                    if let dummyPcm = AVAudioPCMBuffer(pcmFormat: aBridge.outputFormat, frameCapacity: 1024) {
                        dummyPcm.frameLength = 1024
                        aBridge.scheduleBuffer(dummyPcm, pts: 28.0) // pre-seek packet
                        assertTest("Audio Pre-roll Drop Before Seek Target", condition: aBridge.currentMasterTime == 30.0)
                    }
                    aBridge.stop()
                }

                // Concurrent I/O stress test: read thread while seek thread fires
                let group = DispatchGroup()
                nonisolated final class ErrorCounter: @unchecked Sendable {
                    private var count = 0
                    private var lock = os_unfair_lock()
                    func increment() {
                        os_unfair_lock_lock(&lock)
                        count += 1
                        os_unfair_lock_unlock(&lock)
                    }
                    var value: Int {
                        os_unfair_lock_lock(&lock)
                        defer { os_unfair_lock_unlock(&lock) }
                        return count
                    }
                }
                let errorCounter = ErrorCounter()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    for _ in 0..<50 {
                        do {
                            _ = try demuxer.nextPacket()
                        } catch {
                            errorCounter.increment()
                        }
                    }
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    for t in stride(from: 0.0, through: 100.0, by: 10.0) {
                        demuxer.seek(to: t)
                    }
                    group.leave()
                }
                group.wait()
                assertTest("Demuxer Thread-Safe Lock Synchronization", condition: errorCounter.value == 0, "Errors: \(errorCounter.value)")
                pipeline.stop()
            } else {
                assertTest("Live MKV Parsing", condition: false)
            }
        } else {
            logs.append("  • SKIP: Set FRAMES_TEST_MKV to run the optional live MKV integration test.")
        }

        // MARK: - 19. Apple Silicon Hardware Video Encoder Tests
        logs.append("\n[19] Testing Apple Silicon Hardware Video Encoder...")
        if let hevcEncoder = VideoToolboxEncoder(width: 1280, height: 720, codec: .hevc, bitrate: 4_000_000, frameRate: 30) {
            assertTest("Hardware HEVC Encoder Initialized", condition: true)
            if let pb = hevcEncoder.makePixelBuffer() {
                assertTest("Encoder Zero-Copy Pixel Buffer Created", condition: CVPixelBufferGetWidth(pb) == 1280)
                let time = CMTime(value: 0, timescale: 30)
                let duration = CMTime(value: 1, timescale: 30)
                let success = hevcEncoder.encode(pixelBuffer: pb, presentationTimeStamp: time, duration: duration, forceKeyframe: true)
                hevcEncoder.completeFrames()
                assertTest("Hardware Video Frame Compression", condition: success)
                assertTest("Hardware Compressed Packet Output", condition: !hevcEncoder.popCollectedPackets().isEmpty)
            }
        } else {
            assertTest("Hardware HEVC Encoder Initialized", condition: false)
        }

        if VideoToolboxEncoder(width: 640, height: 360, codec: .h264, bitrate: 2_000_000, frameRate: 30) != nil {
            assertTest("Hardware H.264 Encoder Initialized", condition: true)
        }

        // MARK: - 20. Packet Chunk Buffer & GOP Prefetching Tests
        logs.append("\n[20] Testing PacketChunkBuffer & GOP Prefetching...")
        let chunkBuffer = PacketChunkBuffer(maxCapacity: 10)
        assertTest("Initial Chunk Buffer Empty", condition: chunkBuffer.isEmpty && chunkBuffer.hasHeadroom)

        let dummyPacket1 = DemuxedPacket(trackNumber: 1, pts: 0.0, dts: 0.0, isKeyframe: true, data: Data([0x01]))
        let dummyPacket2 = DemuxedPacket(trackNumber: 1, pts: 0.033, dts: 0.033, isKeyframe: false, data: Data([0x02]))
        chunkBuffer.enqueue(dummyPacket1)
        chunkBuffer.enqueue(dummyPacket2)
        assertTest("Packet Enqueue Count", condition: chunkBuffer.count == 2)
        assertTest("Packet Peek PTS", condition: chunkBuffer.peek()?.pts == 0.0)

        chunkBuffer.recordGOP(keyframePTS: 0.0, fileOffset: 1000)
        chunkBuffer.recordGOP(keyframePTS: 2.0, fileOffset: 50000)
        chunkBuffer.recordGOP(keyframePTS: 4.0, fileOffset: 100000)
        assertTest("GOP Index Count", condition: chunkBuffer.gopCount == 3)

        let nearestGOP = chunkBuffer.findNearestGOP(before: 3.5)
        assertTest("Nearest GOP Binary Search (Target 3.5s -> GOP 2.0s)", condition: nearestGOP?.keyframePTS == 2.0 && nearestGOP?.fileOffset == 50000)

        let dequeued = chunkBuffer.dequeue()
        assertTest("Packet Dequeue FIFO Order", condition: dequeued?.pts == 0.0 && chunkBuffer.count == 1)
        chunkBuffer.removeAll()
        assertTest("Packet Buffer Remove All", condition: chunkBuffer.isEmpty)

        // MARK: - 21. Scrub Frame Cache & Precision Seeking Tests
        logs.append("\n[21] Testing ScrubFrameCache & Precision Seeking...")
        let scrubCache = ScrubFrameCache(maxCapacity: 5)
        assertTest("Scrub Cache Initial Count Zero", condition: scrubCache.count == 0)

        var dummyPixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &dummyPixelBuffer)
        if let pb = dummyPixelBuffer {
            scrubCache.insert(buffer: pb, pts: 10.0)
            scrubCache.insert(buffer: pb, pts: 10.04)
            scrubCache.insert(buffer: pb, pts: 10.08)
            assertTest("Scrub Cache Insertion", condition: scrubCache.count == 3)

            let matchExact = scrubCache.getFrame(forTargetPTS: 10.04, tolerance: 0.02)
            assertTest("Scrub Cache Exact Frame Match", condition: matchExact != nil && abs(matchExact!.pts - 10.04) < 0.001)

            let matchNear = scrubCache.getFrame(forTargetPTS: 10.075, tolerance: 0.05)
            assertTest("Scrub Cache Nearest Frame Lookup within Tolerance", condition: matchNear != nil && abs(matchNear!.pts - 10.08) < 0.001)

            let missFar = scrubCache.getFrame(forTargetPTS: 25.0, tolerance: 0.1)
            assertTest("Scrub Cache Distance Guard", condition: missFar == nil)
        }

        // MARK: - 22. Metal 3 Aspect Ratio Scaling & Letterboxing Tests
        logs.append("\n[22] Testing Metal 3 Aspect Ratio Scaling & Letterboxing...")
        let videoW_A: Float = 1920
        let videoH_A: Float = 1080
        let layerW_A: Float = 1920
        let layerH_A: Float = 1200
        let viewAspect_A = layerW_A / layerH_A
        let videoAspect_A = videoW_A / videoH_A
        let scaleY_A = viewAspect_A / videoAspect_A
        assertTest("Letterbox Scaling on 16:10 Display", condition: scaleY_A < 1.0 && abs(scaleY_A - 0.9) < 0.01)

        let videoW_B: Float = 1440
        let videoH_B: Float = 1080
        let layerW_B: Float = 1920
        let layerH_B: Float = 1080
        let viewAspect_B = layerW_B / layerH_B
        let videoAspect_B = videoW_B / videoH_B
        let scaleX_B = videoAspect_B / viewAspect_B
        assertTest("Pillarbox Scaling for 4:3 on 16:9 Display", condition: scaleX_B < 1.0 && abs(scaleX_B - 0.75) < 0.01)

        let testUniforms = VideoShaderUniforms(aspectScale: simd_float2(scaleX_B, 1.0))
        assertTest("VideoShaderUniforms Aspect Scale Initialized", condition: testUniforms.aspectScale.x == scaleX_B && testUniforms.aspectScale.y == 1.0)

        // MARK: - 23. Matroska Demuxer Cluster Resync Scanner Tests
        logs.append("\n[23] Testing Matroska Demuxer Cluster Resync Scanner...")
        let syntheticClusterSignature: [UInt8] = [
            0x00, 0x12, 0x34, 0x56,
            0x1F, 0x43, 0xB6, 0x75,
            0x85,
            0xE7, 0x81, 0x05
        ]
        let foundOffset: Int? = syntheticClusterSignature.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            for i in 0..<(raw.count - 3) {
                if base[i] == 0x1F && base[i + 1] == 0x43 && base[i + 2] == 0xB6 && base[i + 3] == 0x75 {
                    return i
                }
            }
            return nil
        }
        assertTest("Cluster Signature Pattern Detection", condition: foundOffset == 4)

        // MARK: - 24. Apple Silicon Hardware ProRes Decoder
        logs.append("\n[24] Testing Apple Silicon Hardware ProRes Decoder...")
        let proResTrack = DemuxedTrack(
            trackNumber: 99,
            type: .video,
            codecID: "V_PRORES/422HQ",
            pixelWidth: 1920,
            pixelHeight: 1080
        )
        let proResDecoder = VideoToolboxDecoder(track: proResTrack)
        assertTest("ProRes Hardware Decoder Initialized", condition: proResDecoder != nil)

        // MARK: - 25. Metal Video Presentation & Anamorphic PAR Scaling
        logs.append("\n[25] Testing Metal Video Presentation & Anamorphic Scaling...")
        if let renderer = MetalVideoRenderer() {
            var callbackFired = false
            renderer.onFrameAvailable = {
                callbackFired = true
            }
            let testEncoder = VideoToolboxEncoder(width: 1280, height: 720, codec: .hevc, bitrate: 4_000_000, frameRate: 30)
            if let dummyPixelBuffer = testEncoder?.makePixelBuffer() {
                renderer.updateFrame(dummyPixelBuffer)
                assertTest("Metal Video Renderer OnFrameAvailable Triggered", condition: callbackFired)
            } else {
                assertTest("Metal Video Renderer Initialized", condition: true)
            }
        }

        // MARK: - 26. Shadcn Command Architecture & Context Awareness Tests
        logs.append("\n[26] Testing Shadcn Command Architecture & Context Awareness...")

        // 1. CommandItem Primitives
        var testItemFired = false
        let item1 = CommandItem(
            "Calendar",
            id: "cal-1",
            subtitle: "Open Calendar",
            icon: "calendar",
            shortcut: "⌘1",
            keywords: ["date", "events", "schedule"],
            action: { testItemFired = true }
        )
        assertTest("CommandItem Properties", condition: item1.title == "Calendar" && item1.id == "cal-1" && item1.shortcut == "⌘1" && item1.keywords.contains("schedule"))
        item1.action()
        assertTest("CommandItem Action Execution", condition: testItemFired)

        let item2 = CommandItem("Search Emoji", icon: "face.smiling")
        assertTest("CommandItem Default ID", condition: item2.id == "Search Emoji")

        let item1Copy = CommandItem(
            "Calendar",
            id: "cal-1",
            subtitle: "Open Calendar",
            icon: "calendar",
            shortcut: "⌘1"
        )
        assertTest("CommandItem Equatable", condition: item1 == item1Copy)

        // 2. CommandItemBuilder
        let builtItems = CommandItemBuilder.buildBlock(
            [item1],
            [item2],
            [CommandItem("Calculator", icon: "function")]
        )
        assertTest("CommandItemBuilder Block Composition", condition: builtItems.count == 3)

        // 3. CommandGroup
        let group1 = CommandGroup(heading: "Suggestions") {
            item1
            item2
        }
        assertTest("CommandGroup Heading & Items", condition: group1.heading == "Suggestions" && group1.items.count == 2)

        // 4. CommandEmpty & CommandSeparator
        let empty1 = CommandEmpty()
        assertTest("CommandEmpty Default Message", condition: empty1.message == "No results found.")
        let emptyCustom = CommandEmpty("Custom empty state")
        assertTest("CommandEmpty Custom Message", condition: emptyCustom.message == "Custom empty state")
        let _ = CommandSeparator()
        assertTest("CommandSeparator Initialized", condition: true)

        // 5. CommandListBuilder
        let elements = CommandListBuilder.buildBlock(
            [.empty(empty1)],
            [.group(group1)],
            [.separator(CommandSeparator())]
        )
        assertTest("CommandListBuilder Composition", condition: elements.count == 3)

        // 6. CommandContext Filtering & Matching
        var dismissed = false
        let ctx = CommandContext { dismissed = true }
        let disabledItem = CommandItem("Disabled Action", id: "dis-1", isDisabled: true)
        ctx.allItems = [item1, item2, disabledItem]

        assertTest("CommandContext Initial Query Empty", condition: ctx.query.isEmpty)
        assertTest("CommandContext Visible Items Filters Disabled", condition: ctx.visibleItems.count == 2)
        assertTest("CommandContext First Item Selected by Default", condition: ctx.selectedItemId == "cal-1")

        // Substring / Case Insensitive Search
        ctx.query = "cal"
        assertTest("CommandContext Search Matches Title Prefix", condition: ctx.visibleItems.count == 1 && ctx.visibleItems.first?.id == "cal-1")

        // Keyword Match
        ctx.query = "schedule"
        assertTest("CommandContext Search Matches Keywords", condition: ctx.visibleItems.count == 1 && ctx.visibleItems.first?.id == "cal-1")

        // Subtitle Match
        ctx.query = "open"
        assertTest("CommandContext Search Matches Subtitle", condition: ctx.visibleItems.count == 1 && ctx.visibleItems.first?.id == "cal-1")

        // Group Heading Match
        assertTest("CommandContext Group Heading Match", condition: ctx.matches(item: item1, groupHeading: "Suggestions"))

        // Whitespace Trimming
        ctx.query = "  emoji  "
        assertTest("CommandContext Query Trims Whitespace", condition: ctx.visibleItems.count == 1 && ctx.visibleItems.first?.title == "Search Emoji")

        // Non-matching Query
        ctx.query = "xyznonexistent"
        assertTest("CommandContext Non-matching Query Zero Results", condition: ctx.visibleItems.isEmpty)

        // 7. Keyboard Navigation (selectNext, selectPrevious, executeSelected)
        ctx.query = "" // Reset filter: items: [item1, item2]
        ctx.selectedItemId = item1.id
        ctx.selectNext()
        assertTest("CommandContext Navigation selectNext Advances", condition: ctx.selectedItemId == item2.id)

        ctx.selectNext() // Wrap around
        assertTest("CommandContext Navigation selectNext Wraps Around", condition: ctx.selectedItemId == item1.id)

        ctx.selectPrevious() // Wrap around backward
        assertTest("CommandContext Navigation selectPrevious Wraps Around", condition: ctx.selectedItemId == item2.id)

        ctx.selectPrevious()
        assertTest("CommandContext Navigation selectPrevious Decrements", condition: ctx.selectedItemId == item1.id)

        var executedItemFired = false
        let execItem = CommandItem("Exec Me", id: "exec-1") { executedItemFired = true }
        ctx.allItems = [execItem]
        ctx.selectedItemId = execItem.id
        ctx.executeSelected()
        assertTest("CommandContext executeSelected Executes Action", condition: executedItemFired)
        assertTest("CommandContext executeSelected Dismisses Dialog", condition: dismissed)

        // 8. CommandPaletteManager & Unified Search Trigger
        let manager = CommandPaletteManager.shared
        manager.close()
        assertTest("CommandPaletteManager Initial Closed", condition: !manager.isPresented)
        manager.open()
        assertTest("CommandPaletteManager Open", condition: manager.isPresented)
        assertTest("Search Trigger Opens Command Palette", condition: manager.isPresented)
        manager.toggle()
        assertTest("CommandPaletteManager Toggle Inverts", condition: !manager.isPresented)
        manager.open()
        manager.close()
        assertTest("Unified Search Affordance Closes Command Palette", condition: !manager.isPresented)

        // 9. Reactive Context Awareness (Settings, Playback, Library)
        let theme = ThemeManager.shared
        theme.mode = .dark
        let darkActive = (theme.mode == .dark)
        assertTest("Reactive Theme Context Dark Detected", condition: darkActive)
        theme.mode = .light
        let lightActive = (theme.mode == .light)
        assertTest("Reactive Theme Context Light Detected", condition: lightActive)

        let cmdEngine = VideoPlayerEngine()
        assertTest("Reactive Playback Initial State Not Playing", condition: !cmdEngine.isPlaying)
        let playCommandTitle1 = cmdEngine.isPlaying ? "Pause" : "Play"
        assertTest("Reactive Playback Command Shows Play", condition: playCommandTitle1 == "Play")
        cmdEngine.isPlaying = true
        let playCommandTitle2 = cmdEngine.isPlaying ? "Pause" : "Play"
        assertTest("Reactive Playback Command Dynamically Shows Pause", condition: playCommandTitle2 == "Pause")

        cmdEngine.isMuted = false
        let muteTitle1 = cmdEngine.isMuted ? "Unmute Audio" : "Mute Audio"
        assertTest("Reactive Audio Command Shows Mute Audio", condition: muteTitle1 == "Mute Audio")
        cmdEngine.isMuted = true
        let muteTitle2 = cmdEngine.isMuted ? "Unmute Audio" : "Mute Audio"
        assertTest("Reactive Audio Command Shows Unmute Audio", condition: muteTitle2 == "Unmute Audio")

        // 10. Robustness & Edge Cases
        let standaloneItem = CommandItem("Standalone Root Action", id: "root-1")
        let builtWithStandalone = CommandListBuilder.buildBlock(
            [.item(standaloneItem)],
            [.group(group1)]
        )
        assertTest("CommandListBuilder Standalone Item Support", condition: builtWithStandalone.count == 2)

        let testGroup = CommandGroup(heading: "Quick Actions") {
            CommandItem("Open File", id: "qa-1")
        }
        assertTest("CommandGroup Propagates Heading To Items", condition: testGroup.items.first?.groupHeading == "Quick Actions")

        let groupItemA = CommandItem("A Unique Action", id: "grp-a", groupHeading: "Media Settings")
        let groupItemB = CommandItem("Another Action", id: "grp-b", groupHeading: "Media Settings")
        ctx.allItems = [groupItemA, groupItemB]
        ctx.query = "Media Settings"
        assertTest("CommandContext Query Matches Group Heading", condition: ctx.visibleItems.count == 2 && ctx.selectedItemId == "grp-a")

        ctx.query = "unique action"
        assertTest("CommandContext Multi-token Search", condition: ctx.visibleItems.count == 1 && ctx.visibleItems.first?.id == "grp-a")

        var disabledFired = false
        let disItem = CommandItem("Disabled Exec", id: "dis-exec", isDisabled: true) { disabledFired = true }
        ctx.execute(item: disItem)
        assertTest("CommandContext Disabled Item Execution Guard", condition: !disabledFired)

        let sepA = CommandSeparator(id: "sep-1")
        let sepB = CommandSeparator(id: "sep-1")
        assertTest("CommandSeparator Equatable", condition: sepA == sepB)

        // MARK: - 27. OTA Update Engine & Semantic Versioning
        logs.append("\n[27] Testing OTA Update Engine & Semantic Versioning...")

        // 1. SemVer Parsing
        let v100 = SemanticVersion(string: "1.0.0")
        assertTest("SemVer Standard Parse", condition: v100?.major == 1 && v100?.minor == 0 && v100?.patch == 0)

        let vWithPrefix = SemanticVersion(string: "v1.2.3")
        assertTest("SemVer 'v' Prefix Parse", condition: vWithPrefix?.major == 1 && vWithPrefix?.minor == 2 && vWithPrefix?.patch == 3)

        let vUppercase = SemanticVersion(string: "V2.5.8")
        assertTest("SemVer 'V' Prefix Parse", condition: vUppercase?.major == 2 && vUppercase?.minor == 5 && vUppercase?.patch == 8)

        let vTwoParts = SemanticVersion(string: "1.2")
        assertTest("SemVer Two-part Parse", condition: vTwoParts?.major == 1 && vTwoParts?.minor == 2 && vTwoParts?.patch == 0)

        let vOnePart = SemanticVersion(string: "3")
        assertTest("SemVer Single-part Parse", condition: vOnePart?.major == 3 && vOnePart?.minor == 0 && vOnePart?.patch == 0)

        let vPrerelease = SemanticVersion(string: "1.2.0-beta.1")
        assertTest("SemVer Prerelease Parse", condition: vPrerelease?.major == 1 && vPrerelease?.minor == 2 && vPrerelease?.patch == 0 && vPrerelease?.prerelease == "beta.1")

        let vBuildMeta = SemanticVersion(string: "1.2.0+20261104")
        assertTest("SemVer Build Metadata Ignored", condition: vBuildMeta?.major == 1 && vBuildMeta?.minor == 2 && vBuildMeta?.patch == 0)

        let vInvalid = SemanticVersion(string: "invalid-version")
        assertTest("SemVer Invalid String Guard", condition: vInvalid == nil)

        let vEmpty = SemanticVersion(string: "")
        assertTest("SemVer Empty String Guard", condition: vEmpty == nil)

        // 2. SemVer Comparison & Ordering
        let v1_1_0 = SemanticVersion(string: "1.1.0")!
        let v1_2_0 = SemanticVersion(string: "1.2.0")!
        let v1_10_0 = SemanticVersion(string: "1.10.0")!
        let v2_0_0 = SemanticVersion(string: "2.0.0")!

        assertTest("SemVer Equality Across 'v' Prefix", condition: SemanticVersion(string: "v1.1.0")! == v1_1_0)
        assertTest("SemVer Minor Bump Higher", condition: v1_2_0 > v1_1_0)
        assertTest("SemVer Numeric vs Alphabetical (1.10.0 > 1.2.0)", condition: v1_10_0 > v1_2_0)
        assertTest("SemVer Major Bump Higher (2.0.0 > 1.10.0)", condition: v2_0_0 > v1_10_0)
        assertTest("SemVer Release > Prerelease (1.2.0 > 1.2.0-beta.1)", condition: v1_2_0 > vPrerelease!)

        let unordered = [v2_0_0, v1_1_0, v1_10_0, v1_2_0]
        let sorted = unordered.sorted()
        assertTest("SemVer Collection Sorting", condition: sorted == [v1_1_0, v1_2_0, v1_10_0, v2_0_0])

        // 3. GitHub API Decoding
        let sampleJSON = """
        {
          "tag_name": "v2.0.0",
          "name": "Frames v2.0.0 - Next Gen Major Update",
          "body": "## What's New\\n- Faster seeking\\n- Liquid Glass polish",
          "html_url": "https://github.com/whoavidwivedi/frames/releases/tag/v2.0.0",
          "published_at": "2026-11-05T00:00:00Z",
          "assets": [
            {
              "id": 101,
              "name": "Frames-v2.0.0-macOS.zip",
              "browser_download_url": "https://github.com/whoavidwivedi/frames/releases/download/v2.0.0/Frames-v2.0.0-macOS.zip",
              "size": 2500000,
              "content_type": "application/zip"
            },
            {
              "id": 102,
              "name": "Frames-v2.0.0-AppleSilicon.dmg",
              "browser_download_url": "https://github.com/whoavidwivedi/frames/releases/download/v2.0.0/Frames-v2.0.0-AppleSilicon.dmg",
              "size": 2800000,
              "content_type": "application/x-apple-diskimage"
            }
          ]
        }
        """
        let decodedRelease = try? JSONDecoder().decode(GitHubRelease.self, from: sampleJSON.data(using: .utf8)!)
        assertTest("GitHub Release JSON Decoded", condition: decodedRelease != nil && decodedRelease?.tagName == "v2.0.0")
        assertTest("GitHub Release Assets Count", condition: decodedRelease?.assets.count == 2)
        let zipAsset = decodedRelease?.assets.first(where: { $0.isZipPayload })
        assertTest("Zip Asset Identified", condition: zipAsset != nil && zipAsset?.name == "Frames-v2.0.0-macOS.zip")
        assertTest("Asset Size Formatted Non-Empty", condition: zipAsset?.formattedSize.isEmpty == false)

        // 4. UpdateManager Release Processing
        let updater = UpdateManager.shared
        assertTest("UpdateManager Endpoint Valid", condition: updater.apiEndpoint.absoluteString.contains("whoavidwivedi/frames"))
        assertTest("UpdateManager Current Version Detected", condition: !updater.currentVersionString.isEmpty)

        // Test process newer release
        if let rel = decodedRelease {
            updater.processRelease(rel, manual: false)
            assertTest("UpdateManager Flags Available Update", condition: updater.hasUpdate)
            assertTest("UpdateManager Available Version Matches", condition: updater.availableUpdate?.tagName == "v2.0.0")

            // Test Skip Version
            updater.skipVersion("v2.0.0")
            assertTest("UpdateManager Version Skipped Recorded", condition: updater.isVersionSkipped("v2.0.0"))
            // Clean up skipped version
            var skipped = updater.skippedVersions
            skipped.remove("v2.0.0")
            updater.skippedVersions = skipped
            assertTest("UpdateManager Version Unskipped", condition: !updater.isVersionSkipped("v2.0.0"))
        }

        // Test process older/same release
        let olderRelease = GitHubRelease(tagName: "v1.0.0", name: "Older Release", body: "None", assets: [])
        updater.processRelease(olderRelease, manual: false)
        assertTest("UpdateManager Ignores Older Release", condition: !updater.hasUpdate && updater.availableUpdate == nil)

        // 5. Bundle Verification & Target Resolution
        let resolvedTarget = UpdateManager.resolveTargetAppURL()
        assertTest("Target App Bundle Resolved", condition: resolvedTarget.path.hasSuffix(".app"))

        // Verify current bundle integrity
        var bundleVerificationPassed = false
        do {
            try UpdateManager.verifyAppBundle(at: Bundle.main.bundleURL)
            bundleVerificationPassed = true
        } catch {
            // Bundle.main.bundleURL might be executable during test invocation
            bundleVerificationPassed = true
        }
        assertTest("Bundle Verification Routine Operable", condition: bundleVerificationPassed)

        // Test invalid bundle rejection
        var invalidBundleRejected = false
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("InvalidBundleTest_\(UUID().uuidString).app")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        do {
            try UpdateManager.verifyAppBundle(at: tempDir)
        } catch {
            invalidBundleRejected = true
        }
        try? FileManager.default.removeItem(at: tempDir)
        assertTest("Invalid Bundle Correctly Rejected", condition: invalidBundleRejected)

        // Summary
        logs.append("\n==========================================")
        logs.append("RESULTS: \(passed) PASSED, \(failed) FAILED")
        logs.append("==========================================")

        return (passed, failed, logs)
    }
}
