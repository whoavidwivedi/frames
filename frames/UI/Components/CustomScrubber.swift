import SwiftUI

public struct CustomScrubber: View {
    @Bindable var engine: VideoPlayerEngine

    @State private var scrubProgress: Double = 0.0
    @State private var isDragging: Bool = false
    @State private var wasPlayingBeforeScrub: Bool = false

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let duration = engine.duration > 0 ? engine.duration : 1.0

        // Default macOS slider look; the clock store drives it between scrubs.
        Slider(
            value: Binding(
                get: {
                    if isDragging || engine.isScrubbing {
                        return min(max(scrubProgress, 0), 1)
                    }
                    return min(max(engine.clockStore.currentTime / duration, 0), 1)
                },
                set: {
                    scrubProgress = $0
                    engine.seek(to: $0 * duration, exact: false)
                }
            ),
            in: 0...1,
            onEditingChanged: { editing in
                if editing {
                    isDragging = true
                    wasPlayingBeforeScrub = engine.isPlaying
                    if engine.isPlaying { engine.pause() }
                    engine.isScrubbing = true
                } else {
                    engine.seek(to: min(max(scrubProgress, 0), 1) * duration, exact: true)
                    engine.endScrubbing()
                    if wasPlayingBeforeScrub { engine.play() }
                    isDragging = false
                }
            }
        )
        .controlSize(.small)
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(TimeFormatting.format(seconds: engine.clockStore.currentTime)) of \(TimeFormatting.format(seconds: duration))")
    }
}
