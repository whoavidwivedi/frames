import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shadcn Subtitle Selector Panel

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
                    .foregroundStyle(ShadcnTheme.primaryHighlight)

                Text("Subtitles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                let nonOffTracks = engine.availableSubtitleTracks.filter { $0.id != SubtitleTrack.off.id }
                if !nonOffTracks.isEmpty {
                    Text("\(nonOffTracks.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(ShadcnTheme.secondary)
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
                    .foregroundStyle(ShadcnTheme.foreground)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(ShadcnTheme.secondary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                            .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
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
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .frame(width: 20, height: 20)
                        .background(ShadcnTheme.secondary.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Close (Esc)")
            }

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
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
                                    .strokeBorder(isOff ? ShadcnTheme.primaryHighlight : ShadcnTheme.border, lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                                if isOff {
                                    Circle()
                                        .fill(ShadcnTheme.primaryHighlight)
                                        .frame(width: 7, height: 7)
                                }
                            }

                            Text("Off")
                                .font(.system(size: 12, weight: isOff ? .semibold : .medium))
                                .foregroundStyle(isOff ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)

                            Text("Disabled")
                                .font(.system(size: 10))
                                .foregroundStyle(ShadcnTheme.foregroundMuted)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(isOff ? ShadcnTheme.cardHover : (hoveredTrackId == "off" ? ShadcnTheme.muted.opacity(0.4) : Color.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(isOff ? ShadcnTheme.border : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
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
                                        .strokeBorder(isSelected ? ShadcnTheme.primaryHighlight : ShadcnTheme.border, lineWidth: 1.5)
                                        .frame(width: 14, height: 14)
                                    if isSelected {
                                        Circle()
                                            .fill(ShadcnTheme.primaryHighlight)
                                            .frame(width: 7, height: 7)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.title)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    if let lang = track.languageCode, !lang.isEmpty {
                                        Text(LanguageHelper.displayName(for: lang))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                                    }
                                }

                                Spacer()

                                if track.isExternal {
                                    Text("EXTERNAL")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(ShadcnTheme.primaryHighlight)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1.5)
                                        .background(ShadcnTheme.primaryHighlight.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isSelected ? ShadcnTheme.cardHover : (hoveredTrackId == track.id ? ShadcnTheme.muted.opacity(0.4) : Color.clear))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .strokeBorder(isSelected ? ShadcnTheme.border : Color.clear, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .onHover { h in hoveredTrackId = h ? track.id : nil }
                    }
                }
            }
            .frame(maxHeight: 160)

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // Subtitle Delay Adjustment
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Subtitle Delay")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    Spacer()
                    Text(String(format: "%+.2fs", engine.subtitleDelay))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(engine.subtitleDelay != 0 ? ShadcnTheme.primaryHighlight : ShadcnTheme.foreground)
                }

                HStack(spacing: 4) {
                    delayStepButton(label: "-250ms") { engine.subtitleDelay -= 0.25 }
                    delayStepButton(label: "-100ms") { engine.subtitleDelay -= 0.1 }
                    delayStepButton(label: "Reset", isReset: true) { engine.subtitleDelay = 0 }
                    delayStepButton(label: "+100ms") { engine.subtitleDelay += 0.1 }
                    delayStepButton(label: "+250ms") { engine.subtitleDelay += 0.25 }
                }
            }

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // Subtitle Font Size
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Typography Size")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    Spacer()
                    Text("\(Int(engine.subtitleFontSize))pt")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foreground)
                }

                HStack(spacing: 5) {
                    fontSizePresetButton(label: "Small", size: 18)
                    fontSizePresetButton(label: "Medium", size: 24)
                    fontSizePresetButton(label: "Large", size: 30)
                    fontSizePresetButton(label: "XL", size: 36)
                }

                Slider(value: $engine.subtitleFontSize, in: 16...36, step: 2)
                    .tint(ShadcnTheme.primaryHighlight)
                    .pointingHand()
            }
        }
        .padding(14)
        .frame(width: 290)
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 0)
        .environment(\.colorScheme, .dark)
    }

    private func delayStepButton(label: String, isReset: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: isReset ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isReset && engine.subtitleDelay != 0 ? ShadcnTheme.primaryHighlight : ShadcnTheme.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(ShadcnTheme.secondary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
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
                .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(isSelected ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(isSelected ? ShadcnTheme.border : ShadcnTheme.borderSubtle, lineWidth: 1)
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

// MARK: - Shadcn Audio Selector Panel

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
                    .foregroundStyle(ShadcnTheme.primaryHighlight)

                Text("Audio Streams")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                if !engine.availableAudioTracks.isEmpty {
                    Text("\(engine.availableAudioTracks.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(ShadcnTheme.secondary)
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
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .frame(width: 20, height: 20)
                        .background(ShadcnTheme.secondary.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Close (Esc)")
            }

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // Audio Tracks List
            if engine.availableAudioTracks.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ShadcnTheme.primaryHighlight)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Audio Output")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Text("Primary mixed track (Stereo)")
                            .font(.system(size: 10))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.secondary.opacity(0.35))
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
                                            .strokeBorder(isSelected ? ShadcnTheme.primaryHighlight : ShadcnTheme.border, lineWidth: 1.5)
                                            .frame(width: 14, height: 14)
                                        if isSelected {
                                            Circle()
                                                .fill(ShadcnTheme.primaryHighlight)
                                                .frame(width: 7, height: 7)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(track.title)
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)

                                        if let lang = track.languageCode, !lang.isEmpty {
                                            Text(LanguageHelper.displayName(for: lang))
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(ShadcnTheme.foregroundMuted)
                                        }
                                    }

                                    Spacer()

                                    // Channels & Codec Badges
                                    HStack(spacing: 4) {
                                        if !track.channelLayout.isEmpty && track.channelLayout != "Unknown" {
                                            Text(track.channelLayout == "5.1 Surround" ? "5.1" : (track.channelLayout == "7.1 Surround" ? "7.1" : track.channelLayout))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1.5)
                                                .background(ShadcnTheme.secondary)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                                                )
                                        }

                                        if !track.formatDescription.isEmpty && track.formatDescription != "Unknown" {
                                            Text(LanguageHelper.audioCodecDescription(codecID: track.formatDescription))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundStyle(ShadcnTheme.foregroundMuted)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1.5)
                                                .background(ShadcnTheme.secondary.opacity(0.6))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                        .fill(isSelected ? ShadcnTheme.cardHover : (hoveredTrackId == track.id ? ShadcnTheme.muted.opacity(0.4) : Color.clear))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                        .strokeBorder(isSelected ? ShadcnTheme.border : Color.clear, lineWidth: 1)
                                )
                                .contentShape(Rectangle())
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
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 0)
        .environment(\.colorScheme, .dark)
    }
}
