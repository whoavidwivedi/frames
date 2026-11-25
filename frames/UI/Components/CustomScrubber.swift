import SwiftUI

public struct CustomScrubber: View {
    @Bindable var engine: VideoPlayerEngine

    @State private var scrubProgress: Double?
    @State private var wasPlayingBeforeScrub = false

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let clock = engine.clockStore
        let duration = clock.duration
        let canSeek = duration.isFinite && duration > 0
        let position = canSeek ? min(max(clock.currentTime / duration, 0), 1) : 0
        let progress = scrubProgress ?? position

        Slider(
            value: Binding(
                get: { progress },
                set: { newValue in
                    guard canSeek else { return }
                    let isDragging = scrubProgress != nil
                    if isDragging { scrubProgress = newValue }
                    engine.seek(to: newValue * duration, exact: !isDragging)
                }
            ),
            in: 0...1,
            onEditingChanged: { editing in
                guard canSeek else { return }
                if editing {
                    scrubProgress = position
                    wasPlayingBeforeScrub = engine.isPlaying
                    if wasPlayingBeforeScrub { engine.pause() }
                    engine.isScrubbing = true
                } else if let target = scrubProgress {
                    engine.seek(to: target * duration, exact: true)
                    engine.endScrubbing()
                    if wasPlayingBeforeScrub { engine.play() }
                    scrubProgress = nil
                }
            }
        )
        .controlSize(.small)
        .disabled(!canSeek)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(TimeFormatting.format(seconds: progress * duration)) of \(TimeFormatting.format(seconds: duration))")
    }
}
