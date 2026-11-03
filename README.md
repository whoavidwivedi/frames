# Frames

<p align="left">
  <strong>Native, hardware-accelerated video player built exclusively for Apple Silicon and macOS.</strong>
</p>

<p align="left">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-black?style=flat-square&logo=apple" alt="Platform: macOS 14.0+">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(ARM64)-black?style=flat-square&logo=apple" alt="Apple Silicon ARM64">
  <img src="https://img.shields.io/badge/Language-Swift%206-black?style=flat-square&logo=swift" alt="Swift 6">
  <img src="https://img.shields.io/badge/Design-shadcn%20mira%20%2F%20neutral-black?style=flat-square" alt="shadcn mira / neutral">
  <img src="https://img.shields.io/badge/Display-120Hz%20ProMotion-black?style=flat-square" alt="120Hz ProMotion">
  <img src="https://img.shields.io/badge/Tests-38%20Passed%20(0%20warnings)-black?style=flat-square" alt="Tests">
</p>

---

## Overview

**Frames** is an ultra-fast, minimal video player and media dashboard designed to feel right at home on modern macOS. Built with pure Swift and SwiftUI, it leverages Apple Silicon's hardware video decoders and Unified Memory architecture to deliver fluid 60fps / 120fps ProMotion playback with near-zero CPU overhead and a lightweight memory footprint (< 120MB).

Adheres strictly to the **shadcn `mira`/`neutral`** monochrome design language: deep obsidian backgrounds (`#09090b`), crisp 1px borders (`#27272a`), tight corners, and refined liquid-glass overlays.

---

## Key Features

### 1. Apple Silicon Hardware Acceleration
* **Zero-Copy Decoding**: Direct hardware decoding via Apple VideoToolbox and CoreMedia through native `AVPlayerLayer`.
* **ProMotion Monotonic Clock**: Interpolates playback time against system display refresh intervals ($60\text{Hz} / 120\text{Hz}$) for micro-stutter-free progress bar rendering without AVPlayer clock jitter.
* **Non-Blocking Chase-Seek**: Apple Chase-Seek queue prevents thread starvation and buffer stalls during rapid scrubber dragging.

### 2. Media Dashboard & Sidebar
* **Folder Management**: Connect any folder on your Mac; subdirectories are scanned asynchronously without blocking the UI.
* **Live Library Navigation**: Browse *All Videos*, *Recent*, *Favorites*, or custom directories with live video counts.
* **Instant Filtering & Search**: Sub-millisecond title and folder search with customizable sorting (Date Added, Title, Duration, File Size).
* **View Modes**: Switch seamlessly between 16:9 cinematic poster card grid and a compact list table.
* **Smart Progress Tracking**: Automatically tracks and resumes watched videos.

### 3. Dual Fullscreen Architecture
* **Native Spaces Fullscreen (`F`)**: Full macOS Spaces immersion with automatic menu bar and dock suppression.
* **Windowed Desktop Fill (`⌥F` / `W`)**: Fills the current workspace instantly without space-switching animations or dual-monitor stutter.

### 4. Precision Subtitle Engine
* Support for external `.srt` and `.vtt` files via drag-and-drop or file picker.
* Real-time HTML tag stripping (`<i>`, `<b>`, `<font>`) and sub-millisecond timestamp parsing.

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Space` | Play / Pause |
| `←` / `→` | Seek backward / forward 5 seconds |
| `⇧←` / `⇧→` | Seek backward / forward 30 seconds |
| `.` / `,` | Frame step forward / backward |
| `↑` / `↓` | Volume adjust ($\pm 5\%$) |
| `M` | Toggle mute |
| `F` | Toggle native macOS fullscreen (Spaces) |
| `⌥F` or `W` | Toggle windowed fullscreen (Desktop fill) |
| `[` / `]` | Decrease / Increase playback rate ($\pm 0.1\times$) |
| `S` | Toggle subtitle track selector |
| `I` | Toggle Apple Silicon hardware stats HUD |
| `⌘O` | Open video file(s) |
| `Esc` | Return to Library Dashboard / Exit Fullscreen |

---

## Testing & Optimization Suite

Frames includes a built-in test runner covering core subsystems, hardware metrics, and performance benchmarks.

Run all tests directly from terminal:

```bash
./build/frames.app/Contents/MacOS/frames --run-tests
```

Output:
```
==========================================
       FRAMES TEST & OPTIMIZATION SUITE   
==========================================

[1] Testing TimeFormatting...
  ✔ PASS: Zero Seconds
  ✔ PASS: Seconds Under A Minute
  ✔ PASS: Minutes and Seconds
  ✔ PASS: One Hour and Above
  ✔ PASS: Negative Value Guard
  ✔ PASS: NaN Value Guard

[2] Testing SubtitleParser (SRT & WebVTT)...
  ✔ PASS: SRT Count
  ✔ PASS: SRT Cue 1 Timing
  ✔ PASS: SRT Cue 1 HTML Stripping
  ✔ PASS: SRT Cue 2 Timing
  ✔ PASS: WebVTT Count
  ✔ PASS: WebVTT Timing
  ✔ PASS: WebVTT Text

[3] Testing VideoMetadata...
  ✔ PASS: 4K Resolution String
  ✔ PASS: 1080p Resolution String
  ✔ PASS: 720p Resolution String
  ✔ PASS: Bitrate Description

[4] Testing AppleSiliconMetrics...
  ✔ PASS: Apple Silicon Detected
  ✔ PASS: Active CPU Cores
  ✔ PASS: Physical Memory Detected
  ✔ PASS: Display Refresh Rate Valid
  ✔ PASS: Low Memory Footprint (< 200MB)

[5] Testing Monotonic Time Interpolation...
  ✔ PASS: Time Interpolation Monotonicity (120fps Zero Jitter)

[6] Testing Shadcn mira/neutral Design Tokens & Scrubber Math...
  ✔ PASS: Shadcn Radius Scale (Sm=4, Md=6, Lg=8, Xl=10)
  ✔ PASS: Scrubber Zero Duration Division Guard
  ✔ PASS: Scrubber Seek Underflow Clamp
  ✔ PASS: Scrubber Seek Overflow Clamp

[7] Testing Subtitle Parser Performance Benchmark (1,000 cues)...
  ✔ PASS: 1,000 Cues Correctly Parsed
  ✔ PASS: 1,000 Cues Parse Latency < 100ms
  ✔ PASS: Active Cue Lookup at Time T

[8] Testing Apple Silicon Architecture & Unified Memory...
  ✔ PASS: ARM64 Architecture Verified
  ✔ PASS: Memory Footprint Under 150MB

[9] Testing Library & Dashboard Manager...
  ✔ PASS: Library Video Item Ingestion
  ✔ PASS: Duplicate Ingestion Guard
  ✔ PASS: Dashboard Search Filter
  ✔ PASS: Dashboard Favorites Filter
  ✔ PASS: Playback Progress Recorded (50%)
  ✔ PASS: Recent Timestamp Recorded

==========================================
RESULTS: 38 PASSED, 0 FAILED
==========================================
```

---

## Build from Source

### Prerequisites
* macOS 14.0 or higher
* Xcode 16.0 or higher with Command Line Tools
* Apple Silicon Mac (M1, M2, M3, M4 series)

### Build with `xcodebuild`

```bash
# Clone the repository
git clone https://github.com/whoavidwivedi/frames.git
cd frames

# Build Debug or Release scheme
xcodebuild -project frames.xcodeproj -scheme frames -configuration Release build
```

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
