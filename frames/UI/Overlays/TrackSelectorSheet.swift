import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shadcn Subtitle Selector Panel

public struct SubtitleSelectorPanel: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var hoveredTrackId: String? = nil
    @State private var selectedTab: SubtitleTab = .tracks
    @State private var settings = SettingsManager.shared

    public enum SubtitleTab: String, CaseIterable, Identifiable {
        case tracks = "Tracks"
        case style = "Sync & Style"

        public var id: String { rawValue }
    }

    private let colorPresets: [(name: String, color: Color, hex: String)] = [
        ("Green", Color(red: 0.29, green: 0.87, blue: 0.50), "#4ADE80"),
        ("Mint", Color(red: 0.20, green: 0.83, blue: 0.60), "#34D399"),
        ("Yellow", Color(red: 0.98, green: 0.80, blue: 0.08), "#FACC15"),
        ("White", Color.white, "#FFFFFF"),
        ("Cyan", Color(red: 0.22, green: 0.74, blue: 0.97), "#38BDF8")
    ]

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Bar
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
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(ShadcnTheme.secondary)
                        .clipShape(Capsule())
                }

                Spacer()

                // Close Button
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

            // Shadcn Segmented Tab Bar (Tracks vs Sync & Style)
            HStack(spacing: 3) {
                ForEach(SubtitleTab.allCases) { tab in
                    let isTabActive = selectedTab == tab
                    Button {
                        withAnimation(.fluidQuick) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: isTabActive ? .semibold : .medium))
                            .foregroundStyle(isTabActive ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4.5)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isTabActive ? ShadcnTheme.card : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .strokeBorder(isTabActive ? ShadcnTheme.border : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                }
            }
            .padding(2.5)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm + 2, style: .continuous)
                    .fill(ShadcnTheme.secondary.opacity(0.45))
            )

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // Content per Tab
            if selectedTab == .tracks {
                tracksView
            } else {
                syncAndStyleView
            }
        }
        .padding(14)
        .frame(width: 318)
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 0)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Tracks Tab View

    private var tracksView: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .frame(maxHeight: 180)

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // Add Subtitle File Button
            Button {
                openExternalSubtitlePicker()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Add Subtitle File (.srt, .vtt)...")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(ShadcnTheme.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(ShadcnTheme.secondary.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .pointingHand()
        }
    }

    // MARK: - Sync & Style Tab View

    private var syncAndStyleView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Timing Offset
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Subtitle Sync Offset")
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
                    delayStepButton(label: "0.0s", isReset: true) { engine.subtitleDelay = 0 }
                    delayStepButton(label: "+100ms") { engine.subtitleDelay += 0.1 }
                    delayStepButton(label: "+250ms") { engine.subtitleDelay += 0.25 }
                }
            }

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // 2. Font Size
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Typography Size")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    Spacer()
                    Text("\(Int(engine.subtitleFontSize))pt")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foreground)
                }

                HStack(spacing: 4) {
                    fontSizePresetButton(label: "Small", size: 16)
                    fontSizePresetButton(label: "Standard", size: 20)
                    fontSizePresetButton(label: "Large", size: 24)
                    fontSizePresetButton(label: "XL", size: 28)
                }

                Slider(value: $engine.subtitleFontSize, in: 14...34, step: 2)
                    .tint(ShadcnTheme.primaryHighlight)
                    .pointingHand()
            }

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // 3. Text Color Quick Presets
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Text Color")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    Spacer()
                }

                HStack(spacing: 5) {
                    ForEach(colorPresets, id: \.hex) { preset in
                        let isSelected = settings.subtitleTextColorHex.uppercased() == preset.hex.uppercased()
                        Button {
                            withAnimation(.snappy(duration: 0.15)) {
                                settings.subtitleTextColorHex = preset.hex
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 8, height: 8)
                                Text(preset.name)
                                    .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isSelected ? ShadcnTheme.cardHover : ShadcnTheme.secondary.opacity(0.35))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(isSelected ? ShadcnTheme.border : Color.clear, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                    }
                }
            }
        }
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
                .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
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
            UTType(filenameExtension: "vtt") ?? .item,
            UTType(filenameExtension: "ass") ?? .item,
            UTType(filenameExtension: "sub") ?? .item
        ]
        panel.message = "Choose an SRT, WebVTT, ASS, or Sub file"

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
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.primaryHighlight)

                Text("Audio Streams")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                if !engine.availableAudioTracks.isEmpty {
                    Text("\(engine.availableAudioTracks.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
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

            // Audio Streams List
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
        .frame(width: 308)
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 0)
        .environment(\.colorScheme, .dark)
    }
}
