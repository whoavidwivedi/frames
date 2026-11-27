# Engineering Frames

## Product brief

Build an original native macOS player for Apple Silicon, targeting macOS Golden Gate 27 and later. Optimize for the person opening a movie from Finder, the viewer watching a long film on battery, and the editor inspecting an individual frame. Choose an interaction because it serves one of those tasks. QuickTime and VLC may supply comparison measurements. Frames owns its layout, visual identity and behavior.

Keep the picture prominent. Make pause, seek, volume, fullscreen and return to library accessible by pointer and keyboard. Expose track selection, external subtitles, playback speed, frame stepping, picture-in-picture and snapshots when needed. Respect Reduce Motion, Reduce Transparency and VoiceOver. Check narrow windows and fullscreen, especially popovers and the auto-hide timer.

## Trace a change through the app

- Start with framesApp and ContentView. Trace Finder, drag-and-drop, the file picker and a library item through VideoPlayerEngine. Check that the selected file, resume position and autoplay intent survive fallback. Opening a second file must retire callbacks from the previous session.
- Follow PlaybackPipeline into Demuxer, Decoder, Audio and UI/Metal. Keep blocking reads and decoder teardown off the main actor. Bound queued packets, decoded surfaces and scrub caches. The display loop should present new frames and yield while idle. Verify seeks against the presentation clock and a decodable random access point.
- Own new media features in this repository using public Apple frameworks. A picker extension means that Frames will attempt a file. Record container, codec, profile, bit depth, audio configuration and actual decode result before expanding a support claim. Surface actionable errors for unsupported tracks.
- Keep library paths, favorites, subtitles, resume history and update settings compatible with existing installations. Exercise migration with a copy of the old state. Keep tests isolated from a real library or installed application.
- Treat file availability, malformed input, canceled loads, sleep/wake and unplugged storage as normal runtime conditions. Validate offsets, lengths and timestamps before allocation or arithmetic.

## Build and verify

From the repository root with full Xcode selected, run the same scheme and architecture as CI.

```sh
xcodebuild -project frames.xcodeproj -scheme frames -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
bash scripts/test-install.sh
bash scripts/release.sh 2.0.0 --dry-run
```

Use the project's marketing version in the last command. Add new Swift files to the appropriate Xcode target. Prefer fixtures with actual elementary streams. For a format change test decoded image dimensions, timestamps, seeking and EOF, plus an unsupported or truncated sample. Use a representative audiovisual file to check sound, track switching and sync. A demuxer test establishes packet correctness. A render test establishes visible playback. Record which level ran.

For performance changes record commit, Mac, memory, OS, power mode, screen brightness, refresh rate, media properties and playback duration. Repeat cold open, seek, uninterrupted playback, pause and close. Record time to first displayed frame, seek-to-frame latency, dropped frames, memory and energy over the same interval. Use Instruments or equivalent macOS tools. Compare releases on the same equipment. Publish only measured results and identify unavailable hardware coverage.

## Delivery

Fetch origin, check the working tree, inspect open issues and PRs, and branch from the intended base. Preserve unrelated work. Include the reason, user-visible behavior, tested scenarios and remaining limits in the PR. Use focused commits and regression tests. Check the current head SHA and its checks after the last push. Diagnose failed jobs from their logs and rerun the affected workflow. Merge only after every required check succeeds.

CI exercises Debug, XCTest, installer failure paths, Release packaging and architecture verification. Test fresh install, upgrade, wrong identity, checksum mismatch and rollback using temporary directories. Keep architecture, bundle identity, version, signing policy and release asset naming consistent between the installer, updater and packager. Ad-hoc distribution requires informed consent. Preserve macOS per-app approval.

Release from the reviewed main revision. A PR artifact is a preview. Publishing a release makes it discoverable by existing installations. Verify the release ZIP, manifest, version, migration asset and update discovery before reporting public availability. Report the PR, checks and release state separately.
