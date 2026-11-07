import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SubtitleSelectorPanel: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var hoveredTrackId: String? = nil

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.38, green: 0.85, blue: 0.65))

                Text("Subtitles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)

                let nonOffTracks = engine.availableSubtitleTracks.filter { $0.id != SubtitleTrack.off.id }
                if !nonOffTracks.isEmpty {
                    Text("\(nonOffTracks.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    openExternalSubtitlePicker()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Add File...")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Import external .srt or .vtt subtitle file")

                Button {
                    withAnimation(.fluidSpring) {
                        engine.activeInspectorSheet = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Close (Esc)")
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            // Subtitle Tracks List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 3) {
                    // Off Option
                    let isOff = engine.selectedSubtitleTrack.id == SubtitleTrack.off.id
                    Button {
                        withAnimation(.fluidQuick) {
                            engine.selectSubtitleTrack(SubtitleTrack.off)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .strokeBorder(isOff ? Color(red: 0.38, green: 0.85, blue: 0.65) : Color.white.opacity(0.30), lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                                if isOff {
                                    Circle()
                                        .fill(Color(red: 0.38, green: 0.85, blue: 0.65))
                                        .frame(width: 7, height: 7)
                                }
                            }

                            Text("Off")
                                .font(.system(size: 12, weight: isOff ? .semibold : .medium))
                                .foregroundStyle(isOff ? Color.white : Color.white.opacity(0.75))

                            Text("Disabled")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.40))

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isOff ? Color.white.opacity(0.15) : (hoveredTrackId == "off" ? Color.white.opacity(0.08) : Color.clear))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .onHover { h in hoveredTrackId = h ? "off" : nil }

                    // Available Subtitle Tracks
                    ForEach(engine.availableSubtitleTracks.filter { $0.id != SubtitleTrack.off.id }) { track in
                        let isSelected = engine.selectedSubtitleTrack.id == track.id
                        Button {
                            withAnimation(.fluidQuick) {
                                engine.selectSubtitleTrack(track)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(isSelected ? Color(red: 0.38, green: 0.85, blue: 0.65) : Color.white.opacity(0.30), lineWidth: 1.5)
                                        .frame(width: 14, height: 14)
                                    if isSelected {
                                        Circle()
                                            .fill(Color(red: 0.38, green: 0.85, blue: 0.65))
                                            .frame(width: 7, height: 7)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.88))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    if let lang = track.languageCode, !lang.isEmpty {
                                        Text(LanguageHelper.displayName(for: lang))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(Color.white.opacity(0.50))
                                    }
                                }

                                Spacer()

                                if track.isExternal {
                                    Text("EXTERNAL")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.55, green: 0.75, blue: 1.0))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1.5)
                                        .background(Color(red: 0.20, green: 0.40, blue: 0.80).opacity(0.30))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                } else if let lang = track.languageCode, !lang.isEmpty {
                                    Text(lang.uppercased())
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.60))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1.5)
                                        .background(Color.white.opacity(0.10))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.15) : (hoveredTrackId == track.id ? Color.white.opacity(0.08) : Color.clear))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .onHover { h in hoveredTrackId = h ? track.id : nil }
                    }
                }
            }
            .frame(maxHeight: 160)

            if engine.selectedSubtitleTrack.id != SubtitleTrack.off.id {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)

                // Subtitle Delay Offset Section
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.60))
                        Text("Sync Delay")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                        Spacer()
                        Text(String(format: "%+.1fs", engine.subtitleDelay))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(engine.subtitleDelay != 0 ? Color(red: 0.38, green: 0.85, blue: 0.65) : Color.white)
                    }

                    HStack(spacing: 4) {
                        delayStepButton(label: "-0.5s") { engine.subtitleDelay -= 0.5 }
                        delayStepButton(label: "-0.1s") { engine.subtitleDelay -= 0.1 }
                        delayStepButton(label: "Reset", isReset: true) { engine.subtitleDelay = 0.0 }
                        delayStepButton(label: "+0.1s") { engine.subtitleDelay += 0.1 }
                        delayStepButton(label: "+0.5s") { engine.subtitleDelay += 0.5 }
                    }

                    Slider(value: $engine.subtitleDelay, in: -5.0...5.0, step: 0.1)
                        .tint(Color(red: 0.38, green: 0.85, blue: 0.65))
                        .pointingHand()
                }

                // Subtitle Font Size Section
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: "textformat.size")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.60))
                        Text("Font Size")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                        Spacer()
                        Text("\(Int(engine.subtitleFontSize))pt")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                    }

                    HStack(spacing: 5) {
                        fontSizePresetButton(label: "Small", size: 18)
                        fontSizePresetButton(label: "Medium", size: 24)
                        fontSizePresetButton(label: "Large", size: 30)
                        fontSizePresetButton(label: "XL", size: 36)
                    }

                    Slider(value: $engine.subtitleFontSize, in: 16...36, step: 2)
                        .tint(Color.white.opacity(0.85))
                        .pointingHand()
                }
            }
        }
        .padding(14)
        .frame(width: 290)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.08, opacity: 0.92))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 24, x: 0, y: 12)
        .environment(\.colorScheme, .dark)
    }

    private func delayStepButton(label: String, isReset: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: isReset ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isReset && engine.subtitleDelay != 0 ? Color(red: 0.38, green: 0.85, blue: 0.65) : Color.white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .pointingHand()
    }

    private func fontSizePresetButton(label: String, size: CGFloat) -> some View {
        let isSelected = abs(engine.subtitleFontSize - size) < 1.0
        return Button {
            withAnimation(.fluidQuick) {
                engine.subtitleFontSize = size
            }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3.5)
                .background(isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.35) : Color.white.opacity(0.15), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .pointingHand()
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
    @State private var hoveredTrackId: String? = nil

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))

                Text("Audio Streams")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)

                if !engine.availableAudioTracks.isEmpty {
                    Text("\(engine.availableAudioTracks.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    withAnimation(.fluidSpring) {
                        engine.activeInspectorSheet = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Close (Esc)")
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            // Audio Tracks List
            if engine.availableAudioTracks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Audio Output")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white)
                        Text("Primary mixed track (Stereo)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(engine.availableAudioTracks) { track in
                            let isSelected = engine.selectedAudioTrack?.id == track.id
                            Button {
                                withAnimation(.fluidQuick) {
                                    engine.selectAudioTrack(track)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .strokeBorder(isSelected ? Color(red: 0.35, green: 0.65, blue: 1.0) : Color.white.opacity(0.30), lineWidth: 1.5)
                                            .frame(width: 14, height: 14)
                                        if isSelected {
                                            Circle()
                                                .fill(Color(red: 0.35, green: 0.65, blue: 1.0))
                                                .frame(width: 7, height: 7)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(track.title)
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.88))
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        if let lang = track.languageCode, !lang.isEmpty {
                                            Text(LanguageHelper.displayName(for: lang))
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(Color.white.opacity(0.50))
                                        }
                                    }

                                    Spacer()

                                    // Channels & Codec Badges
                                    HStack(spacing: 4) {
                                        if !track.channelLayout.isEmpty && track.channelLayout != "Unknown" {
                                            Text(track.channelLayout == "5.1 Surround" ? "5.1" : (track.channelLayout == "7.1 Surround" ? "7.1" : track.channelLayout))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.60))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1.5)
                                                .background(Color(red: 0.20, green: 0.60, blue: 0.35).opacity(0.25))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }

                                        if !track.formatDescription.isEmpty && track.formatDescription != "Unknown" {
                                            Text(LanguageHelper.audioCodecDescription(codecID: track.formatDescription))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundStyle(Color.white.opacity(0.65))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1.5)
                                                .background(Color.white.opacity(0.10))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? Color.white.opacity(0.15) : (hoveredTrackId == track.id ? Color.white.opacity(0.08) : Color.clear))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .onHover { h in hoveredTrackId = h ? track.id : nil }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(14)
        .frame(width: 290)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.08, opacity: 0.92))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 24, x: 0, y: 12)
        .environment(\.colorScheme, .dark)
    }
}
