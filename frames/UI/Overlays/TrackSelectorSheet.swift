import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SubtitleSelectorPanel: View {
    @Bindable var engine: VideoPlayerEngine

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Subtitles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)
                Spacer()
                ShadcnButton("Add .srt / .vtt", icon: "plus", variant: .outline, size: .sm) {
                    openExternalSubtitlePicker()
                }
            }

            Rectangle()
                .fill(ShadcnTheme.border)
                .frame(height: 1)

            // Subtitle Tracks List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(engine.availableSubtitleTracks) { track in
                        let isSelected = engine.selectedSubtitleTrack.id == track.id
                        Button {
                            engine.selectSubtitleTrack(track)
                        } label: {
                            HStack {
                                Text(track.title)
                                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                                    .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(ShadcnTheme.foreground)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isSelected ? ShadcnTheme.accentActive : Color.clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                    }
                }
            }
            .frame(maxHeight: 130)

            Rectangle()
                .fill(ShadcnTheme.border)
                .frame(height: 1)

            // Subtitle Delay Offset
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Sync Delay")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                    Spacer()
                    Text(String(format: "%+.1fs", engine.subtitleDelay))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foreground)
                    if engine.subtitleDelay != 0 {
                        Button("Reset") {
                            engine.subtitleDelay = 0.0
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .buttonStyle(.plain)
                        .pointingHand()
                    }
                }

                Slider(value: $engine.subtitleDelay, in: -5.0...5.0, step: 0.1)
                    .tint(ShadcnTheme.foreground)
                    .pointingHand()
            }

            // Subtitle Font Size
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Font Size")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                    Spacer()
                    Text("\(Int(engine.subtitleFontSize))pt")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foreground)
                }

                Slider(value: $engine.subtitleFontSize, in: 16...36, step: 2)
                    .tint(ShadcnTheme.foreground)
                    .pointingHand()
            }
        }
        .frame(width: 250)
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 12)
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
        panel.message = "Choose an SRT or WebVTT file"

        if panel.runModal() == .OK, let url = panel.url {
            engine.loadExternalSubtitleFile(from: url)
        }
    }
}

public struct AudioSelectorPanel: View {
    @Bindable var engine: VideoPlayerEngine

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Audio Streams")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)
                Spacer()
            }

            Rectangle()
                .fill(ShadcnTheme.border)
                .frame(height: 1)

            // Audio Tracks List
            if engine.availableAudioTracks.isEmpty {
                Text("Default Stream")
                    .font(.system(size: 12))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(engine.availableAudioTracks) { track in
                        let isSelected = engine.selectedAudioTrack?.id == track.id
                        Button {
                            engine.selectAudioTrack(track)
                        } label: {
                            HStack {
                                Text(track.title)
                                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                                    .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(ShadcnTheme.foreground)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isSelected ? ShadcnTheme.accentActive : Color.clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                    }
                }
            }

            Rectangle()
                .fill(ShadcnTheme.border)
                .frame(height: 1)

            // Volume Booster
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume Boost")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                    Spacer()
                    Text(String(format: "%d%%", Int(engine.audioGainBoost * 100)))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foreground)
                }

                Slider(value: $engine.audioGainBoost, in: 1.0...2.0, step: 0.1)
                    .tint(ShadcnTheme.foreground)
                    .pointingHand()
            }
        }
        .frame(width: 230)
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 12)
    }
}
