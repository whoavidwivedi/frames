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
  <img src="https://img.shields.io/badge/Apple%20Silicon-M1%20%7C%20M2%20%7C%20M3%20%7C%20M4%2B-black?style=flat-square&logo=apple" alt="Apple Silicon M1 to Latest">
  <img src="https://img.shields.io/badge/Language-Swift%205-black?style=flat-square&logo=swift" alt="Swift 5">
  <img src="https://img.shields.io/badge/Design-shadcn%20base--luma%20%2F%20neutral%20(b1VlK05Q)-black?style=flat-square" alt="shadcn base-luma / neutral">
  <img src="https://img.shields.io/badge/Tests-XCTest%20CI-black?style=flat-square" alt="Tests: XCTest CI">
  <a href="https://github.com/whoavidwivedi/frames/pulls"><img src="https://img.shields.io/badge/PRs-Welcome-black?style=flat-square" alt="PRs Welcome"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/whoavidwivedi/frames?style=flat-square&color=black" alt="License: MIT"></a>
</p>

<p align="center">
  <img src="assets/frames-splash.gif" width="720" alt="Frames Splash Animation" />
</p>

---

## Frames 2.0

Frames is a native arm64 video player for macOS 14 and later. It uses first-party Swift container readers, VideoToolbox, Core Audio and native macOS presentation APIs. The player includes a folder library, resume history, external subtitles and keyboard transport controls.

| Container | Playback path |
| --- | --- |
| MP4, MOV, M4V | Native ISO media reader with AVFoundation fallback |
| MKV, WebM | Native Matroska reader |
| AVI | Native Motion JPEG support, including compatible PCM audio |
| IVF | VP9 and AV1 video on systems providing a suitable decoder |
| Other media | AVFoundation attempts playback using the installed macOS codecs |

Codec profile, hardware, and display capabilities affect resolution, HDR and decoding. Comparative battery life and maximum sustained playback resolution have yet to be benchmarked.

## Installation and updates

Download the installer from [GitHub Releases](https://github.com/whoavidwivedi/frames/releases/latest), or run the installer from the repository.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/whoavidwivedi/frames/main/scripts/install.sh)"
```

The installer verifies the archive checksum, bundle identity, version and signature. Ad-hoc builds require consent. If macOS blocks first launch, select **System Settings → Privacy & Security → Open Anyway** for Frames. Use **Frames → Check for Updates** for subsequent updates. Users on v1.9.4 or v1.9.5 can use the release’s migration installer.

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

... (comprehensive automated test suites) ...

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
Test Suite 'All tests' passed
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
