# Contributing to Frames 🎬

Thank you for your interest in contributing to **Frames** — the high-performance, native macOS video player and media dashboard engineered specifically for Apple Silicon in Swift, Metal 3, VideoToolbox, and SwiftUI.

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) and [Security Policy](SECURITY.md) before contributing.

---

## 🧭 Engineering Principles

1. **Native Performance First**: Zero-copy frame pipelines, direct `CVPixelBuffer` rendering via Metal 3, minimal CPU wakeups, and strictly keeping idle Unified Memory footprint under 150MB.
2. **Liquid Glass & Shadcn Theme System**: All components adhere to the design system in `ShadcnTheme.swift` (`base-luma`/`neutral`). Avoid ad-hoc inline gradients, random drop shadows, or un-tokenized paddings.
3. **Flawless Window Management**: Native macOS interaction semantics — double-click window bars zoom/fill, button bounding boxes pass full hit tests, and live resizes use fluid spring physics without constraint recursion.
4. **Zero-Flake Automated Testing**: Any new subsystem, parser, command, or workflow must come with automated unit and integration tests added to `FramesTestSuite.swift`.
5. **Zero Compiler Warnings**: All code must build cleanly with **0 errors and 0 warnings** under Swift 6 strict concurrency checking.

---

## 🛠️ Local Development & Environment

- **Prerequisites**: macOS Sonoma (14.0+) or Sequoia (15.0+), Apple Silicon (M1/M2/M3/M4), Xcode 16.0+.
- **Building via Command Line**:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project frames.xcodeproj \
    -scheme frames \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    build
  ```
- **Running the Test Suite**:
  ```bash
  # Execute the 426+ automated tests directly via headless CLI flag
  build/DerivedData/Build/Products/Debug/frames.app/Contents/MacOS/frames --run-tests
  ```

---

## 🌿 Branch Naming & Git Conventions

We follow conventional commit specifications:

- `feat/...` for new features (e.g. `feat/timestamp-jump-and-frame-capture`)
- `fix/...` for bug fixes (e.g. `fix/window-interaction-and-button-hitboxes`)
- `ci/...` for continuous integration & automation (e.g. `ci/github-actions-test-suite-and-pr-framework`)
- `docs/...` for documentation enhancements
- `refactor/...` for code refactoring with no behavioral change

---

## 📬 Pull Request Submission Process

1. Create a descriptive feature branch from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
2. Implement your changes maintaining high code quality, Swift 6 idioms, and documentation integrity.
3. Add unit test assertions in `frames/Tests/FramesTestSuite.swift`.
4. Run `frames --run-tests` and verify all tests pass with **0 failures and 0 warnings**.
5. Push your branch and open a Pull Request using `gh pr create` or the GitHub Web UI.
6. Ensure CI passes on `macos-15` before requesting review.
