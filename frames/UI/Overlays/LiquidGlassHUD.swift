import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct LiquidGlassHUD: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var windowManager = WindowManager.shared
    @State private var showVolumePopover = false

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        let isNarrow = windowManager.isCompact || windowManager.isQuarterScreen
        let showVolumeSlider = !isNarrow

        VStack(spacing: 8) {
            // Full-Width Precision Scrubber with Hover Tooltip
            CustomScrubber(engine: engine)
                .frame(height: 24)
                .padding(.horizontal, 16)
                .pointingHand()

            // Primary Playback Controls Dock
            HStack(spacing: isNarrow ? 8 : 12) {
                // MARK: - Left Controls Cluster
                HStack(spacing: 6) {
                    // Play / Pause / Replay
                    Button {
                        engine.togglePlayPause()
                    } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : (engine.hasEnded ? "arrow.counterclockwise" : "play.fill"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help(engine.isPlaying ? "Pause (Space)" : (engine.hasEnded ? "Replay (Space)" : "Play (Space)"))

                    // Skip -10s
                    dockedButton(icon: "gobackward.10", help: "Skip back 10s (← or J)") {
                        engine.skip(seconds: -10)
                    }

                    // Skip +10s
                    dockedButton(icon: "goforward.10", help: "Skip forward 10s (→ or L)") {
                        engine.skip(seconds: 10)
                    }

                    // Volume Mute Button + Interactive Slider / Popover
                    HStack(spacing: 4) {
                        Button {
                            if isNarrow {
                                showVolumePopover.toggle()
                            } else {
                                engine.toggleMute()
                            }
                        } label: {
                            Image(systemName: engine.isMuted ? "speaker.slash.fill" : (engine.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(engine.isMuted ? Color.red.opacity(0.25) : Color.white.opacity(0.12))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help(isNarrow ? "Volume Slider" : (engine.isMuted ? "Unmute (M)" : "Mute (M)"))
                        .popover(isPresented: $showVolumePopover) {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Volume")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                    Spacer()
                                    Text("\(Int(engine.volume * 100))%")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.7))
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(engine.volume) },
                                        set: {
                                            engine.volume = Float($0)
                                            if engine.isMuted && $0 > 0 { engine.isMuted = false }
                                        }
                                    ),
                                    in: 0...1
                                )
                                .frame(width: 120)
                                .tint(Color.white)

                                Button(engine.isMuted ? "Unmute" : "Mute") {
                                    engine.toggleMute()
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.9))
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(white: 0.12))
                            .environment(\.colorScheme, .dark)
                        }

                        if showVolumeSlider {
                            Slider(
                                value: Binding(
                                    get: { Double(engine.volume) },
                                    set: {
                                        engine.volume = Float($0)
                                        if engine.isMuted && $0 > 0 {
                                            engine.isMuted = false
                                        }
                                    }
                                ),
                                in: 0...1
                            )
                            .frame(width: 58)
                            .tint(Color.white)
                            .pointingHand()
                        }
                    }

                    // Tabular Precision Time Display
                    HStack(spacing: 4) {
                        Text(TimeFormatting.format(seconds: engine.currentTime))
                            .foregroundStyle(Color.white)
                        Text("/")
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(TimeFormatting.format(seconds: engine.duration))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.leading, 4)
                }

                Spacer(minLength: 8)

                // MARK: - Right Controls Cluster
                HStack(spacing: 6) {
                    // Audio Streams Menu Picker
                    Menu {
                        Section("Audio Streams") {
                            if engine.availableAudioTracks.isEmpty {
                                Button {} label: {
                                    Label("Default Audio", systemImage: "checkmark")
                                }
                            } else {
                                ForEach(engine.availableAudioTracks) { track in
                                    Button {
                                        engine.selectAudioTrack(track)
                                    } label: {
                                        if engine.selectedAudioTrack?.id == track.id {
                                            Label(track.title, systemImage: "checkmark")
                                        } else {
                                            Text(track.title)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "speaker.wave.2.bubble")
                                .font(.system(size: 12, weight: .semibold))
                            if !isNarrow {
                                Text(audioButtonLabel)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .frame(maxWidth: 100)
                                    .truncationMode(.tail)
                            }
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .pointingHand()
                    .help("Select Audio Track")

                    // Subtitles Menu Picker
                    Menu {
                        Section("Subtitles") {
                            Button {
                                engine.selectSubtitleTrack(SubtitleTrack.off)
                            } label: {
                                if engine.selectedSubtitleTrack.id == SubtitleTrack.off.id {
                                    Label("Off", systemImage: "checkmark")
                                } else {
                                    Text("Off")
                                }
                            }

                            Divider()

                            ForEach(engine.availableSubtitleTracks.filter { $0.id != SubtitleTrack.off.id }) { track in
                                Button {
                                    engine.selectSubtitleTrack(track)
                                } label: {
                                    if engine.selectedSubtitleTrack.id == track.id {
                                        Label(track.title, systemImage: "checkmark")
                                    } else {
                                        Text(track.title)
                                    }
                                }
                            }

                            Divider()

                            Button {
                                openExternalSubtitlePicker()
                            } label: {
                                Label("Add Subtitle File (.srt, .vtt)...", systemImage: "plus")
                            }

                            if engine.selectedSubtitleTrack.id != SubtitleTrack.off.id {
                                Menu("Subtitle Delay (\(String(format: "%+.1fs", engine.subtitleDelay)))") {
                                    Button("-1.0s") { engine.subtitleDelay -= 1.0 }
                                    Button("-0.5s") { engine.subtitleDelay -= 0.5 }
                                    Button("0.0s (Reset)") { engine.subtitleDelay = 0.0 }
                                    Button("+0.5s") { engine.subtitleDelay += 0.5 }
                                    Button("+1.0s") { engine.subtitleDelay += 1.0 }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: engine.selectedSubtitleTrack.id == SubtitleTrack.off.id ? "captions.bubble" : "captions.bubble.fill")
                                .font(.system(size: 12, weight: .semibold))
                            if !isNarrow {
                                Text(engine.selectedSubtitleTrack.id == SubtitleTrack.off.id ? "Subtitles" : engine.selectedSubtitleTrack.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .frame(maxWidth: 110)
                                    .truncationMode(.tail)
                            }
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(engine.selectedSubtitleTrack.id == SubtitleTrack.off.id ? Color.white.opacity(0.14) : Color.white.opacity(0.26))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .pointingHand()
                    .help("Select Subtitles")

                    // Playback Rate Menu Picker
                    Menu {
                        Section("Playback Speed") {
                            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0] as [Float], id: \.self) { rate in
                                Button {
                                    engine.playbackRate = rate
                                } label: {
                                    if abs(engine.playbackRate - rate) < 0.01 {
                                        Label(Self.formatRate(rate), systemImage: "checkmark")
                                    } else {
                                        Text(Self.formatRate(rate))
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(Self.formatRate(engine.playbackRate))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .pointingHand()
                    .help("Playback Speed")

                    // Picture-in-Picture Toggle
                    dockedButton(
                        icon: windowManager.isPictureInPicture ? "pip.exit" : "pip.enter",
                        help: windowManager.isPictureInPicture ? "Exit Picture in Picture" : "Enter Picture in Picture"
                    ) {
                        windowManager.togglePictureInPicture()
                    }

                    // Native Fullscreen Toggle
                    dockedButton(
                        icon: windowManager.isNativeFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        help: windowManager.isNativeFullscreen ? "Exit Fullscreen (Esc)" : "Enter Fullscreen (F)"
                    ) {
                        windowManager.toggleNativeFullscreen()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                Rectangle()
                    .fill(Color(white: 0.08, opacity: 0.88))
            }
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    public static func formatRate(_ rate: Float) -> String {
        if abs(rate.truncatingRemainder(dividingBy: 0.5)) < 0.001 || abs(rate.truncatingRemainder(dividingBy: 1.0)) < 0.001 {
            return String(format: "%.1fx", rate)
        } else {
            return String(format: "%.2fx", rate)
        }
    }

    private var audioButtonLabel: String {
        if let track = engine.selectedAudioTrack {
            if let lang = track.languageCode, !lang.isEmpty {
                let d = LanguageHelper.displayName(for: lang)
                if d != "Undetermined" && d != "Unknown" {
                    return d
                }
            }
            return track.title
        }
        return "Audio"
    }

    private func dockedButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(help)
    }

    private func openExternalSubtitlePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .item,
            UTType(filenameExtension: "vtt") ?? .item
        ]
        panel.message = "Choose an SRT or WebVTT subtitle file"

        if panel.runModal() == .OK, let url = panel.url {
            engine.loadExternalSubtitleFile(from: url)
        }
    }
}
