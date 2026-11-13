import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Emil Kowalski Tactile Button & Row Styles

private struct TactileSheetRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.fluidQuick, value: configuration.isPressed)
    }
}

private struct TactileSheetButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.fluidQuick, value: configuration.isPressed)
    }
}

// MARK: - Selected Option Spring Checkmark Indicator

private struct SpringCheckmarkIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? ShadcnTheme.foreground : Color.clear)
                .frame(width: 15, height: 15)
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? ShadcnTheme.foreground : ShadcnTheme.border, lineWidth: 1.2)
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(ShadcnTheme.background)
                    .transition(.scale(scale: 0.90).combined(with: .opacity))
            }
        }
        .animation(.fluidQuick, value: isSelected)
    }
}

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
        ("White", Color.white, "#FFFFFF"),
        ("Yellow", Color(red: 0.98, green: 0.80, blue: 0.08), "#FACC15"),
        ("Cyan", Color(red: 0.22, green: 0.74, blue: 0.97), "#38BDF8"),
        ("Green", Color(red: 0.20, green: 0.84, blue: 0.29), "#32D74B")
    ]

    private let backgroundPresets: [(name: String, color: Color, hex: String)] = [
        ("Black", .black, "#000000"),
        ("Charcoal", Color(red: 0.11, green: 0.11, blue: 0.12), "#1C1C1E"),
        ("Navy", Color(red: 0.06, green: 0.09, blue: 0.16), "#0F172A"),
        ("White", .white, "#FFFFFF")
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
                    .foregroundStyle(ShadcnTheme.foreground)

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

                // Close Button with Fluid Spring Dismissal
                Button {
                    withAnimation(.fluidQuick) {
                        engine.activeInspectorSheet = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .frame(width: 22, height: 22)
                        .background(ShadcnTheme.secondary.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(TactileSheetButtonStyle(scale: 0.90))
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
                    .buttonStyle(TactileSheetButtonStyle(scale: 0.98))
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
        .playerPanel()
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
                            SpringCheckmarkIndicator(isSelected: isOff)

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
                                .fill(isOff ? ShadcnTheme.cardHover : (hoveredTrackId == "off" ? ShadcnTheme.muted.opacity(0.6) : Color.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(isOff ? ShadcnTheme.borderActive : (hoveredTrackId == "off" ? ShadcnTheme.borderSubtle : Color.clear), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TactileSheetRowStyle())
                    .pointingHand()
                    .onHover { h in
                        withAnimation(.fluidQuick) {
                            hoveredTrackId = h ? "off" : nil
                        }
                    }

                    // Available Subtitle Tracks
                    ForEach(engine.availableSubtitleTracks.filter { $0.id != SubtitleTrack.off.id }) { track in
                        let isSelected = engine.selectedSubtitleTrack.id == track.id
                        Button {
                            withAnimation(.fluidQuick) {
                                engine.selectSubtitleTrack(track)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                SpringCheckmarkIndicator(isSelected: isSelected)

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
                                        .foregroundStyle(ShadcnTheme.foreground)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1.5)
                                        .background(ShadcnTheme.secondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isSelected ? ShadcnTheme.cardHover : (hoveredTrackId == track.id ? ShadcnTheme.muted.opacity(0.6) : Color.clear))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .strokeBorder(isSelected ? ShadcnTheme.borderActive : (hoveredTrackId == track.id ? ShadcnTheme.borderSubtle : Color.clear), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TactileSheetRowStyle())
                        .pointingHand()
                        .onHover { h in
                            withAnimation(.fluidQuick) {
                                hoveredTrackId = h ? track.id : nil
                            }
                        }
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
                .contentShape(Rectangle())
            }
            .buttonStyle(TactileSheetButtonStyle(scale: 0.98))
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
                        .foregroundStyle(engine.subtitleDelay != 0 ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
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

            // 2. Background Color Quick Presets
            VStack(alignment: .leading, spacing: 5) {
                Text("Background Color")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)

                HStack(spacing: 5) {
                    ForEach(backgroundPresets, id: \.hex) { preset in
                        let isSelected = settings.subtitleBackgroundColorHex.uppercased() == preset.hex.uppercased()
                        Button {
                            withAnimation(.fluidQuick) {
                                settings.subtitleBackgroundColorHex = preset.hex
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                                    )
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
                                            .strokeBorder(isSelected ? ShadcnTheme.borderActive : Color.clear, lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TactileSheetButtonStyle(scale: 0.96))
                        .pointingHand()
                    }
                }
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
                            withAnimation(.fluidQuick) {
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
                                            .strokeBorder(isSelected ? ShadcnTheme.borderActive : Color.clear, lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TactileSheetButtonStyle(scale: 0.96))
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
                .foregroundStyle(isReset && engine.subtitleDelay != 0 ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(ShadcnTheme.secondary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(TactileSheetButtonStyle(scale: 0.96))
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
                    .foregroundStyle(ShadcnTheme.foreground)

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

                // Close Button with Fluid Spring Dismissal
                Button {
                    withAnimation(.fluidQuick) {
                        engine.activeInspectorSheet = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .frame(width: 22, height: 22)
                        .background(ShadcnTheme.secondary.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(TactileSheetButtonStyle(scale: 0.90))
                .pointingHand()
                .help("Close (Esc)")
            }

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // Audio Streams List
            if engine.availableAudioTracks.isEmpty {
                HStack(spacing: 8) {
                    SpringCheckmarkIndicator(isSelected: true)

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
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
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
                                    SpringCheckmarkIndicator(isSelected: isSelected)

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
                                        .fill(isSelected ? ShadcnTheme.cardHover : (hoveredTrackId == track.id ? ShadcnTheme.muted.opacity(0.6) : Color.clear))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                        .strokeBorder(isSelected ? ShadcnTheme.borderActive : (hoveredTrackId == track.id ? ShadcnTheme.borderSubtle : Color.clear), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(TactileSheetRowStyle())
                            .pointingHand()
                            .onHover { h in
                                withAnimation(.fluidQuick) {
                                    hoveredTrackId = h ? track.id : nil
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(14)
        .frame(width: 308)
        .playerPanel()
        .environment(\.colorScheme, .dark)
    }
}
