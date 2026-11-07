<p align="center">
  <img src="assets/frames-icon-hd.png" width="120" alt="Frames App Icon" />
</p>

<h1 align="center">Frames</h1>

<p align="center">
  <strong>A minimal, native macOS video player and media dashboard engineered specifically for Apple Silicon.</strong>
</p>

<p align="center">
  <a href="https://github.com/whoavidwivedi/frames/releases/latest"><img src="https://img.shields.io/github/v/release/whoavidwivedi/frames?style=flat-square&color=black&label=Release" alt="Latest Release"></a>
  <a href="https://github.com/whoavidwivedi/frames/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/whoavidwivedi/frames/ci.yml?branch=main&style=flat-square&color=black&label=CI" alt="CI Status"></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-black?style=flat-square&logo=apple" alt="Platform: macOS 14.0+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-ARM64-black?style=flat-square&logo=apple" alt="Apple Silicon ARM64">
  <img src="https://img.shields.io/badge/Language-Swift%206-black?style=flat-square&logo=swift" alt="Swift 6">
  <img src="https://img.shields.io/badge/Design-shadcn%20base--luma%20%2F%20neutral-black?style=flat-square" alt="shadcn base-luma / neutral">
  <img src="https://img.shields.io/badge/Tests-458%20Passed%20(0%20warnings)-black?style=flat-square" alt="Tests">
  <a href="https://github.com/whoavidwivedi/frames/pulls"><img src="https://img.shields.io/badge/PRs-Welcome-black?style=flat-square" alt="PRs Welcome"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/whoavidwivedi/frames?style=flat-square&color=black" alt="License: MIT"></a>
</p>

<p align="center">
  <img src="assets/frames-splash.gif" width="720" alt="Frames Splash Animation" />
</p>

---

## Overview

**Frames** is an ultra-fast, zero-bloat video player and media management dashboard built from the ground up for macOS and Apple Silicon. 

Traditional desktop video players are often weighed down by multi-hundred-megabyte Electron wrappers or legacy codebases dating back decades. Frames is written in pure **Swift 6 and SwiftUI**, leveraging Apple Silicon's dedicated **VideoToolbox** media decoders and Unified Memory architecture to deliver fluid 60fps / 120fps playback, buttery timeline scrubbing, and sub-second cold starts with minimal battery drain.

The user interface adheres strictly to the **shadcn `base-luma`/`neutral`** (preset `b3lnoM3QO`) design language: matte charcoal dark surfaces (`oklch(0.145 0 0)` / `#0a0a0a`), subtle border contours (`Color.white.opacity(0.10)`), warm terracotta & copper accents, and smooth pill-radius controls.

---

## ⚡️ Download & Install

Download the latest pre-compiled binary from the [Releases](https://github.com/whoavidwivedi/frames/releases) page:

| Release | Version | macOS Architecture | Download |
| :--- | :--- | :--- | :--- |
| **Latest** | **v1.3.4** | Apple Silicon (`arm64`) | [**Frames-v1.3.4-macOS.zip**](https://github.com/whoavidwivedi/frames/releases/download/v1.3.4/Frames-v1.3.4-macOS.zip) |
| Previous | v1.3.3 | Apple Silicon (`arm64`) | [Frames-v1.3.3-macOS.zip](https://github.com/whoavidwivedi/frames/releases/download/v1.3.3/Frames-v1.3.3-macOS.zip) |
| Previous | v1.3.2 | Apple Silicon (`arm64`) | [Frames-v1.3.2-macOS.zip](https://github.com/whoavidwivedi/frames/releases/download/v1.3.2/Frames-v1.3.2-macOS.zip) |
| Previous | v1.3.1 | Apple Silicon (`arm64`) | [Frames-v1.3.1-macOS.zip](https://github.com/whoavidwivedi/frames/releases/download/v1.3.1/Frames-v1.3.1-macOS.zip) |
| Previous | v1.3.0 | Apple Silicon (`arm64`) | [Frames-v1.3.0-macOS.zip](https://github.com/whoavidwivedi/frames/releases/download/v1.3.0/Frames-v1.3.0-macOS.zip) |
| Previous | v1.2.0 | Apple Silicon (`arm64`) | [Frames-v1.2.0-macOS.zip](https://github.com/whoavidwivedi/frames/releases/download/v1.2.0/Frames-v1.2.0-macOS.zip) |
| Previous | v1.1.0 | Apple Silicon (`arm64`) | [Frames-v1.1.0-macOS.zip](https://github.com/whoavidwivedi/frames/releases/download/v1.1.0/Frames-v1.1.0-macOS.zip) |
| Previous | v1.0.2 | Apple Silicon (`arm64`) | [Frames-v1.0.2-macOS.zip](https://github.com/whoavidwivedi/frames/releases/download/v1.0.2/Frames-v1.0.2-macOS.zip) |
| Previous | v1.0.1 | Apple Silicon (`arm64`) | [Frames-v1.0.1-macOS.zip](https://github.com/whoavidwivedi/frames/releases/download/v1.0.1/Frames-v1.0.1-macOS.zip) |
| Initial | v1.0.0 | Apple Silicon (`arm64`) | [Frames-v1.0.0-macOS.zip](https://github.com/whoavidwivedi/frames/releases/download/v1.0.0/Frames-v1.0.0-macOS.zip) |

1. Download `Frames-v1.3.4-macOS.zip`.
2. Move `frames.app` into your `/Applications` folder.
3. Open Frames and enjoy fluid hardware-accelerated playback with built-in in-app OTA update support.

---

## Key Features

### 1. Pure Native Apple Silicon Media Engine
* **Zero-Bloat Custom Architecture**: Built completely from scratch in Swift 6 without VLC or legacy C/C++ media player bloat.
* **Pure Swift Matroska & WebM Demuxer**: High-performance zero-allocation EBML VINT streaming parser with $O(\log N)$ binary-search keyframe seeking for `.mkv` and `.webm`.
* **Hardware-First VideoToolbox ASIC Pipeline**: Direct hardware decode for H.264, HEVC (8/10-bit HDR), VP9, AV1, and ProRes. Decoded frames live directly in Apple Silicon Unified Memory (`IOSurface`).
* **Zero-Copy Metal 3 HDR Presentation**: Custom Metal shaders converting bi-planar NV12/P010 textures to RGB in 16-bit floating point with Rec.709, Rec.2020, and ST 2084 PQ / HLG EOTF optical transfer functions.
* **120Hz ProMotion CADisplayLink Cadence**: Synced directly with macOS display refresh intervals, eliminating judder, frame tearing, and timing drift.
* **Bit-Perfect CoreAudio Master Clock**: Hardware-driven audio DAC crystal oscillator timing synchronization keeps video and audio aligned to $< 1\text{ms}$.
* **Ultra-Low Battery & Thermal Footprint**: Designed to sip less power than QuickTime and draw 2–4× less battery than VLC on Apple Silicon.

### 2. Media Dashboard & Library Sidebar
* **Folder Management**: Connect any folder on your Mac; subdirectories are recursively indexed asynchronously without blocking the UI.
* **Smart Organization**: Instant navigation across *All Videos*, *Recent*, *Favorites*, or custom pinned directories with live item counts.
* **Sub-Millisecond Search & Sort**: Filter thousands of titles instantly by name, date added, duration, or file size with keyboard focus management.
* **Adaptive View Modes**: Switch seamlessly between a 16:9 cinematic card grid and a compact list table.
* **Persistent Progress**: Remembers playback timestamps and resumes where you left off.

### 3. Native macOS Window & Fullscreen Architecture
* **Native Spaces Fullscreen (`⌃⌘F` / `F`)**: Full macOS Spaces immersion with automatic menu bar and dock suppression using the standard macOS shortcut `⌃⌘F` (or `F` during playback).
* **Windowed Desktop Fill / Zoom (`⌃⌥⌘F` / `Window -> Zoom`)**: Fills the current display space instantly without creating a new Space; accessible via macOS Zoom or `⌃⌥⌘F`.

### 4. Precision Subtitle Engine
* Seamless support for external `.srt` and `.vtt` subtitles via drag-and-drop or file picker.
* Real-time HTML tag stripping (`<i>`, `<b>`, `<font>`) and sub-millisecond timestamp parsing.

### 5. In-App Production OTA Update Engine
* **Non-Intrusive Update Discovery**: Asynchronous background query against GitHub Releases API with SemVer 2.0.0 parsing. Never forces disruptive silent updates.
* **Liquid Glass Update Modal**: Sleek adaptive modal displaying version diff (`v1.2.0 → v1.3.0`), release notes highlights, download size, and real-time download progress.
* **Granular User Control**: "Update & Restart", "Later", and "Skip this version" options, plus manual check affordance in App Menu (`Frames -> Check for Updates...`) and Command Palette.
* **Atomic Bundle Swap & Clean Restart**: Validates package signature and bundle integrity, atomically replaces the application bundle, cleans quarantine flags, and smoothly restarts.

### 6. Command Palette (`⌘K`) & High-Res Frame Capture (`⌘S`)
* **Instant Keyboard Access**: Press `⌘K` from anywhere in the app to search and execute any command, switch themes, navigate folders, adjust audio/video playback, or check for updates.
* **High-Res Frame Snapshot Engine (`⌘S`)**: Instant capture of native resolution video frames directly exported to `~/Pictures/Frames`.
* **Timestamp Jump Expressions**: Jump directly to any position using expressions such as `1:23`, `01:15:00`, `90s`, `15m`, or relative offsets `+30s` / `-15s` via Command Palette.

### 7. Native Settings Window (`⌘,`)
* Comprehensive 5-tab native macOS preferences: General, Playback, Audio, Subtitles, and About.
* Configurable hardware acceleration, ProMotion 120Hz sync, HDR tone mapping, subtitle styling, and battery saver guard.

---

## Keyboard Shortcuts

Designed for native macOS and keyboard-first navigation:

| Key | Action |
| :--- | :--- |
| `Space` | Play / Pause |
| `←` / `→` | Seek backward / forward 5 seconds |
| `⇧←` / `⇧→` | Seek backward / forward 30 seconds |
| `.` / `,` | Frame step forward / backward |
| `↑` / `↓` | Volume adjust ($\pm 5\%$) |
| `M` | Toggle mute |
| `⌘S` | Capture high-resolution video frame snapshot |
| `⌘K` | Open Command Palette |
| `⌘,` | Open Preferences / Settings |
| `⌃⌘F` or `F` | Toggle native macOS fullscreen (macOS default) |
| `⌃⌥⌘F` / `Zoom` | Toggle windowed fullscreen / Zoom (macOS default) |
| `⌘M` | Minimize window (macOS default) |
| `⌘W` | Close window (macOS default) |
| `[` / `]` | Decrease / Increase playback rate ($\pm 0.1\times$) |
| `S` | Toggle subtitle track selector sheet |
| `I` | Toggle Apple Silicon hardware stats HUD |
| `⌘O` | Open video file(s) via native macOS dialog |
| `Esc` | Return to Dashboard / Exit Fullscreen / Resign Search |

---

## Testing & Optimization Suite

Frames includes a built-in automated test suite covering demuxing, decoding, Metal 3 rendering, design tokens, time formatting, and memory benchmarks.

Run tests directly from terminal:

```bash
build/DerivedData/Build/Products/Debug/frames.app/Contents/MacOS/frames --run-tests
```

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

... (34 comprehensive test suites) ...

[33] Testing Timestamp Jump Parser & Expression Engine...
  ✔ PASS: TimeJumpParser MM:SS Parse (1:23 -> 83s)
  ✔ PASS: TimeJumpParser HH:MM:SS Parse (01:23:45 -> 5025s)
  ✔ PASS: TimeJumpParser Leading Colon (:45 -> 45s)
  ✔ PASS: TimeJumpParser Unit Suffix Seconds (90s -> 90s)
  ✔ PASS: TimeJumpParser Unit Suffix Minutes (15m -> 900s)
  ✔ PASS: TimeJumpParser Unit Suffix Hours (2h -> 7200s)
  ✔ PASS: TimeJumpParser Relative Forward (+30s from 60s -> 90s)
  ✔ PASS: TimeJumpParser Relative Backward (-15s from 60s -> 45s)
  ✔ PASS: TimeJumpParser Negative Underflow Clamped to 0.0
  ✔ PASS: TimeJumpParser Duration Overflow Clamped to Duration
  ✔ PASS: TimeJumpParser Invalid Input Rejected
  ✔ PASS: TimeJumpParser Empty Input Rejected

[34] Testing High-Resolution Frame Capture Engine...
  ✔ PASS: FrameCaptureEngine Directory Creation
  ✔ PASS: FrameCaptureEngine Standard Filename Format
  ✔ PASS: FrameCaptureEngine File Persistence & Metadata

==========================================
RESULTS: 458 PASSED, 0 FAILED
==========================================
```

---

## Building from Source

### Prerequisites
* macOS 14.0 or higher
* Xcode 16.0 or higher with Command Line Tools
* Apple Silicon Mac (M1, M2, M3, M4 series)

### Build Commands

```bash
# 1. Clone the repository
git clone https://github.com/whoavidwivedi/frames.git
cd frames

# 2. Build Release configuration with xcodebuild
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project frames.xcodeproj \
  -scheme frames \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath ./build/DerivedData \
  build
```

---

## Contributing & Community

Contributions, feedback, and pull requests are warmly welcomed!

- Read our [Contributing Guidelines](CONTRIBUTING.md) for details on code style, branch workflows, and PR verification.
- Review our [Code of Conduct](CODE_OF_CONDUCT.md) for community standards.
- Check our [Security Policy](SECURITY.md) for responsible vulnerability reporting.

---

## License

This project is open source and licensed under the [MIT License](LICENSE).
