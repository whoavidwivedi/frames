import SwiftUI
import AppKit

// MARK: - Emil Kowalski Command Palette Model

public struct PaletteCommand: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let iconColor: Color?
    public let shortcut: String?
    public let keywords: [String]
    public let isDestructive: Bool
    public let isDisabled: Bool
    public let group: String
    public let action: () -> Void

    public static func == (lhs: PaletteCommand, rhs: PaletteCommand) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.icon == rhs.icon &&
        lhs.shortcut == rhs.shortcut &&
        lhs.group == rhs.group &&
        lhs.isDisabled == rhs.isDisabled &&
        lhs.isDestructive == rhs.isDestructive
    }

    public init(
        _ title: String,
        id: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        shortcut: String? = nil,
        keywords: [String] = [],
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        group: String,
        action: @escaping () -> Void
    ) {
        self.id = id ?? title
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.shortcut = shortcut
        self.keywords = keywords
        self.isDestructive = isDestructive
        self.isDisabled = isDisabled
        self.group = group
        self.action = action
    }
}

// MARK: - Tactile Palette Command Row

private struct PaletteRowItem: View {
    let item: PaletteCommand
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.iconColor ?? (item.isDestructive ? ShadcnTheme.destructive : (isSelected ? ShadcnTheme.foreground : (isHovered ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary))))
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(item.isDestructive ? ShadcnTheme.destructive : ShadcnTheme.foreground)
                    .lineLimit(1)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let shortcut = item.shortcut, !shortcut.isEmpty {
                CommandShortcut(shortcut)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, item.subtitle == nil ? 6 : 7)
        .background(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                .fill(isSelected ? ShadcnTheme.accentActive : (isHovered ? ShadcnTheme.muted.opacity(0.6) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                .strokeBorder(isSelected ? ShadcnTheme.borderActive : (isHovered ? ShadcnTheme.borderSubtle : Color.clear), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .scaleEffect(isSelected ? 1.0 : (isHovered ? 1.004 : 1.0))
        .opacity(item.isDisabled ? 0.4 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isSelected)
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isHovered)
        .pointingHand()
        .onHover { h in
            isHovered = h && !item.isDisabled
        }
        .onTapGesture {
            if !item.isDisabled {
                onSelect()
            }
        }
    }
}

// MARK: - Frames Command Palette

public struct FramesCommandPalette: View {
    @Binding public var isPresented: Bool
    public var engine: VideoPlayerEngine
    public var library: LibraryManager
    public var themeManager: ThemeManager
    public var windowManager: WindowManager
    public var onPlayURL: (URL) -> Void
    public var onOpenFilePicker: () -> Void

    @State private var searchQuery: String = ""
    @State private var selectedItemId: String? = nil
    @State private var keyMonitor: Any? = nil
    @FocusState private var isInputFocused: Bool

    public init(
        isPresented: Binding<Bool>,
        engine: VideoPlayerEngine,
        library: LibraryManager,
        themeManager: ThemeManager,
        windowManager: WindowManager,
        onPlayURL: @escaping (URL) -> Void,
        onOpenFilePicker: @escaping () -> Void
    ) {
        self._isPresented = isPresented
        self.engine = engine
        self.library = library
        self.themeManager = themeManager
        self.windowManager = windowManager
        self.onPlayURL = onPlayURL
        self.onOpenFilePicker = onOpenFilePicker
    }

    public var body: some View {
        if isPresented {
            ZStack {
                // MARK: - Modal Backdrop with Fluid Blur (Emil Kowalski Grade)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.48))
                    .ignoresSafeArea()
                    .onTapGesture {
                        closePalette()
                    }

                // MARK: - Floating Command Palette Card
                VStack(spacing: 0) {
                    // Search Input Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)

                        TextField("Type a command or search...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(ShadcnTheme.foreground)
                            .focused($isInputFocused)

                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .pointingHand()
                        }

                        Button {
                            closePalette()
                        } label: {
                            CommandShortcut("ESC")
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay(
                        Rectangle()
                            .fill(ShadcnTheme.border)
                            .frame(height: 1),
                        alignment: .bottom
                    )

                    // Filtered Command List
                    let commands = filteredCommands
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            if commands.isEmpty {
                                CommandEmpty("No results found.")
                            } else {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    let grouped = groupCommands(commands)
                                    ForEach(grouped, id: \.heading) { group in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.heading)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(ShadcnTheme.foregroundMuted)
                                                .padding(.horizontal, 10)
                                                .padding(.top, 6)
                                                .padding(.bottom, 2)

                                            ForEach(group.items) { item in
                                                PaletteRowItem(
                                                    item: item,
                                                    isSelected: selectedItemId == item.id
                                                ) {
                                                    executeItem(item)
                                                }
                                                .id(item.id)
                                            }
                                        }

                                        if group.heading != grouped.last?.heading {
                                            Rectangle()
                                                .fill(ShadcnTheme.borderSubtle)
                                                .frame(height: 1)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                        }
                                    }
                                }
                                .padding(6)
                            }
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selectedItemId) { _, newId in
                            if let id = newId {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                .frame(width: 580)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                        .fill(ShadcnTheme.card.opacity(0.92))
                )
                .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                        .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.40), radius: 32, x: 0, y: 16)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.97).combined(with: .opacity)
                    )
                )
            }
            .environment(\.colorScheme, .dark)
            .onAppear {
                searchQuery = ""
                updateSelectionForFilter()
                setupKeyMonitor()
                DispatchQueue.main.async {
                    isInputFocused = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    isInputFocused = true
                }
            }
            .onDisappear {
                removeKeyMonitor()
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    searchQuery = ""
                    updateSelectionForFilter()
                    setupKeyMonitor()
                    DispatchQueue.main.async {
                        isInputFocused = true
                    }
                } else {
                    removeKeyMonitor()
                }
            }
            .onChange(of: searchQuery) { _, _ in
                updateSelectionForFilter()
            }
        }
    }

    // MARK: - Actions & Navigation

    private func closePalette() {
        // Instant dismissal on keyboard-initiated actions / ESC (100+/day: Raycast rule)
        isPresented = false
    }

    private func executeItem(_ item: PaletteCommand) {
        closePalette()
        item.action()
    }

    private func updateSelectionForFilter() {
        let matching = filteredCommands.filter { !$0.isDisabled }
        if let current = selectedItemId, matching.contains(where: { $0.id == current }) {
            // Keep current selection
        } else {
            selectedItemId = matching.first?.id
        }
    }

    private func selectNext() {
        let list = filteredCommands.filter { !$0.isDisabled }
        guard !list.isEmpty else { return }
        if let current = selectedItemId, let idx = list.firstIndex(where: { $0.id == current }) {
            let nextIdx = (idx + 1) % list.count
            selectedItemId = list[nextIdx].id
        } else {
            selectedItemId = list.first?.id
        }
    }

    private func selectPrevious() {
        let list = filteredCommands.filter { !$0.isDisabled }
        guard !list.isEmpty else { return }
        if let current = selectedItemId, let idx = list.firstIndex(where: { $0.id == current }) {
            let prevIdx = (idx - 1 + list.count) % list.count
            selectedItemId = list[prevIdx].id
        } else {
            selectedItemId = list.last?.id
        }
    }

    private func executeSelected() {
        let list = filteredCommands.filter { !$0.isDisabled }
        guard let current = selectedItemId, let item = list.first(where: { $0.id == current }) else {
            return
        }
        executeItem(item)
    }

    private func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isPresented else { return event }

            let isCmd = event.modifierFlags.contains(.command)
            let isCtrl = event.modifierFlags.contains(.control)
            let isOpt = event.modifierFlags.contains(.option)
            let isShift = event.modifierFlags.contains(.shift)
            let keyCode = event.keyCode

            // Cmd+K to toggle/close
            if isCmd && !isCtrl && !isOpt && keyCode == 40 {
                Task { @MainActor in closePalette() }
                return nil
            }

            // Escape to close
            if keyCode == 53 {
                Task { @MainActor in closePalette() }
                return nil
            }

            // Down Arrow (125), Ctrl+N (45), or Tab (48 without Shift)
            if keyCode == 125 || (isCtrl && keyCode == 45) || (!isShift && !isCmd && !isCtrl && !isOpt && keyCode == 48) {
                Task { @MainActor in selectNext() }
                return nil
            }

            // Up Arrow (126), Ctrl+P (35), or Shift+Tab (48 with Shift)
            if keyCode == 126 || (isCtrl && keyCode == 35) || (isShift && !isCmd && !isCtrl && !isOpt && keyCode == 48) {
                Task { @MainActor in selectPrevious() }
                return nil
            }

            // Enter / Return / NumPad Enter
            if keyCode == 36 || keyCode == 76 {
                Task { @MainActor in executeSelected() }
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Filtering & Grouping

    private struct GroupedCommandSection {
        let heading: String
        let items: [PaletteCommand]
    }

    private func groupCommands(_ commands: [PaletteCommand]) -> [GroupedCommandSection] {
        var groups: [String: [PaletteCommand]] = [:]
        var order: [String] = []

        for cmd in commands {
            if groups[cmd.group] == nil {
                groups[cmd.group] = []
                order.append(cmd.group)
            }
            groups[cmd.group]?.append(cmd)
        }

        return order.compactMap { name in
            guard let items = groups[name], !items.isEmpty else { return nil }
            return GroupedCommandSection(heading: name, items: items)
        }
    }

    private var filteredCommands: [PaletteCommand] {
        let all = buildAllCommands()
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }

        let tokens = q.split(separator: " ").map(String.init)
        return all.filter { item in
            if item.title.localizedCaseInsensitiveContains(q) { return true }
            if let sub = item.subtitle, sub.localizedCaseInsensitiveContains(q) { return true }
            if item.group.localizedCaseInsensitiveContains(q) { return true }
            for kw in item.keywords {
                if kw.localizedCaseInsensitiveContains(q) { return true }
            }

            if tokens.count > 1 {
                return tokens.allSatisfy { token in
                    item.title.localizedCaseInsensitiveContains(token) ||
                    (item.subtitle?.localizedCaseInsensitiveContains(token) ?? false) ||
                    item.group.localizedCaseInsensitiveContains(token) ||
                    item.keywords.contains(where: { $0.localizedCaseInsensitiveContains(token) })
                }
            }
            return false
        }
    }

    // MARK: - Command Definitions

    private func buildAllCommands() -> [PaletteCommand] {
        var items: [PaletteCommand] = []

        // MARK: - 1. Active Playback Context
        if engine.currentURL != nil {
            let playbackGroup = "Playback: \(engine.metadata.title.isEmpty ? "Current Media" : engine.metadata.title)"

            items.append(PaletteCommand(
                engine.isPlaying ? "Pause" : "Play",
                id: "playback-play-pause",
                subtitle: engine.isPlaying ? "Pause playback" : "Resume playback",
                icon: engine.isPlaying ? "pause.fill" : "play.fill",
                shortcut: "Space",
                keywords: ["playback", "play", "pause", "resume", "stop"],
                group: playbackGroup
            ) {
                engine.togglePlayPause()
            })

            items.append(PaletteCommand(
                engine.isMuted ? "Unmute Audio" : "Mute Audio",
                id: "playback-mute",
                subtitle: "Volume: \(Int(engine.volume * 100))%",
                icon: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                shortcut: "M",
                keywords: ["mute", "unmute", "sound", "volume", "audio", "quiet"],
                group: playbackGroup
            ) {
                engine.toggleMute()
            })

            let skipInterval = SettingsManager.shared.defaultSkipInterval
            items.append(PaletteCommand(
                "Skip Forward \(skipInterval)s",
                id: "playback-skip-forward-\(skipInterval)",
                icon: "goforward.\(skipInterval)",
                shortcut: "→",
                keywords: ["forward", "seek", "skip", "fast"],
                group: playbackGroup
            ) {
                engine.skip(seconds: Double(skipInterval))
            })

            items.append(PaletteCommand(
                "Skip Backward \(skipInterval)s",
                id: "playback-skip-backward-\(skipInterval)",
                icon: "gobackward.\(skipInterval)",
                shortcut: "←",
                keywords: ["rewind", "seek", "skip", "back"],
                group: playbackGroup
            ) {
                engine.skip(seconds: -Double(skipInterval))
            })

            items.append(PaletteCommand(
                "Skip Forward 30s",
                id: "playback-skip-forward-30",
                icon: "goforward.30",
                shortcut: "⇧→",
                keywords: ["jump", "forward", "seek", "skip", "fast"],
                group: playbackGroup
            ) {
                engine.skip(seconds: 30)
            })

            items.append(PaletteCommand(
                "Skip Backward 30s",
                id: "playback-skip-backward-30",
                icon: "gobackward.30",
                shortcut: "⇧←",
                keywords: ["jump", "rewind", "seek", "skip", "back"],
                group: playbackGroup
            ) {
                engine.skip(seconds: -30)
            })

            items.append(PaletteCommand(
                "Next Frame (Step Forward)",
                id: "playback-step-forward",
                icon: "forward.frame",
                shortcut: ".",
                keywords: ["frame", "step", "precision"],
                group: playbackGroup
            ) {
                engine.stepFrame(forward: true)
            })

            items.append(PaletteCommand(
                "Previous Frame (Step Backward)",
                id: "playback-step-backward",
                icon: "backward.frame",
                shortcut: ",",
                keywords: ["frame", "step", "precision"],
                group: playbackGroup
            ) {
                engine.stepFrame(forward: false)
            })

            items.append(PaletteCommand(
                "Normal Speed (1.0x)",
                id: "playback-speed-1x",
                subtitle: abs(engine.playbackRate - 1.0) < 0.01 ? "Current" : nil,
                icon: "speedometer",
                keywords: ["speed", "rate", "1x", "normal"],
                group: playbackGroup
            ) {
                engine.playbackRate = 1.0
            })

            items.append(PaletteCommand(
                "Fast Speed (1.25x)",
                id: "playback-speed-125x",
                subtitle: abs(engine.playbackRate - 1.25) < 0.01 ? "Current" : nil,
                icon: "speedometer",
                keywords: ["speed", "rate", "1.25x", "fast"],
                group: playbackGroup
            ) {
                engine.playbackRate = 1.25
            })

            items.append(PaletteCommand(
                "Fast Speed (1.5x)",
                id: "playback-speed-15x",
                subtitle: abs(engine.playbackRate - 1.5) < 0.01 ? "Current" : nil,
                icon: "speedometer",
                keywords: ["speed", "rate", "1.5x", "fast"],
                group: playbackGroup
            ) {
                engine.playbackRate = 1.5
            })

            items.append(PaletteCommand(
                "Double Speed (2.0x)",
                id: "playback-speed-2x",
                subtitle: abs(engine.playbackRate - 2.0) < 0.01 ? "Current" : nil,
                icon: "speedometer",
                keywords: ["speed", "rate", "2x", "double", "fast"],
                group: playbackGroup
            ) {
                engine.playbackRate = 2.0
            })

            items.append(PaletteCommand(
                "Slow Motion (0.5x)",
                id: "playback-speed-05x",
                subtitle: abs(engine.playbackRate - 0.5) < 0.01 ? "Current" : nil,
                icon: "speedometer",
                keywords: ["speed", "rate", "0.5x", "slow"],
                group: playbackGroup
            ) {
                engine.playbackRate = 0.5
            })

            // Subtitle Tracks
            for track in engine.availableSubtitleTracks {
                items.append(PaletteCommand(
                    "Subtitle: \(track.title)",
                    id: "sub-\(track.id)",
                    subtitle: engine.selectedSubtitleTrack.id == track.id ? "Active" : nil,
                    icon: "captions.bubble",
                    keywords: ["subtitle", "cc", "captions", track.title],
                    group: playbackGroup
                ) {
                    engine.selectSubtitleTrack(track)
                })
            }

            // Audio Tracks
            for track in engine.availableAudioTracks {
                items.append(PaletteCommand(
                    "Audio Track: \(track.title)",
                    id: "audio-\(track.id)",
                    subtitle: engine.selectedAudioTrack?.id == track.id ? "Active" : nil,
                    icon: "waveform",
                    keywords: ["audio", "sound", "track", track.title],
                    group: playbackGroup
                ) {
                    engine.selectAudioTrack(track)
                })
            }

            items.append(PaletteCommand(
                "Silicon & Hardware Metrics Inspector",
                id: "playback-stats",
                subtitle: "Display real-time Metal 3 & unified memory telemetry",
                icon: "cpu",
                shortcut: "I",
                keywords: ["hardware", "silicon", "gpu", "metal", "stats", "telemetry", "fps", "inspector"],
                group: playbackGroup
            ) {
                engine.activeInspectorSheet = (engine.activeInspectorSheet == .stats ? nil : .stats)
            })

            items.append(PaletteCommand(
                "Capture Frame Snapshot",
                id: "playback-capture-snapshot",
                subtitle: "Save high-res frame to ~/Pictures/Frames",
                icon: "camera.viewfinder",
                shortcut: "⌘S",
                keywords: ["snapshot", "screenshot", "capture", "photo", "image", "frame", "save"],
                group: playbackGroup
            ) {
                if let currentURL = engine.currentURL {
                    _ = try? FrameCaptureEngine.shared.saveFrame(
                        pixelBuffer: nil,
                        videoTitle: currentURL.deletingPathExtension().lastPathComponent,
                        timestampSeconds: engine.currentTime
                    )
                }
            })

            items.append(PaletteCommand(
                "Jump to Beginning (00:00)",
                id: "playback-jump-beginning",
                subtitle: "Seek to start of media",
                icon: "backward.end.fill",
                shortcut: "0",
                keywords: ["beginning", "start", "reset", "0", "seek"],
                group: playbackGroup
            ) {
                engine.seek(to: 0.0)
            })

            if engine.duration > 0 {
                items.append(PaletteCommand(
                    "Jump to Halfway (50%)",
                    id: "playback-jump-halfway",
                    subtitle: "Seek to middle of media",
                    icon: "arrow.right.to.line",
                    keywords: ["half", "halfway", "middle", "50%"],
                    group: playbackGroup
                ) {
                    engine.seek(to: engine.duration * 0.5)
                })
            }

            if engine.hasEnded {
                items.append(PaletteCommand(
                    "Replay Video",
                    id: "playback-replay",
                    icon: "arrow.counterclockwise",
                    shortcut: "R",
                    keywords: ["replay", "restart", "play again"],
                    group: playbackGroup
                ) {
                    engine.replay()
                })
            }

            items.append(PaletteCommand(
                "Return to Dashboard",
                id: "playback-return-dashboard",
                subtitle: "Save progress and return to library",
                icon: "chevron.left",
                shortcut: "Esc",
                keywords: ["dashboard", "home", "exit", "close", "back", "library"],
                group: playbackGroup
            ) {
                NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
            })
        }

        // MARK: - 2. Videos Context
        if !library.videos.isEmpty {
            let videosGroup = "Videos (\(library.videos.count))"
            for video in library.videos {
                let format = video.url.pathExtension.uppercased()
                items.append(PaletteCommand(
                    video.title,
                    id: "video-\(video.id.uuidString)",
                    subtitle: "\(TimeFormatting.format(seconds: video.duration)) • \(format)\(video.isFavorite ? " • ★ Favorite" : "")",
                    icon: video.isFavorite ? "star.fill" : "play.rectangle.fill",
                    iconColor: video.isFavorite ? Color(red: 1.0, green: 0.8, blue: 0.0) : nil,
                    keywords: [video.title, format, video.url.lastPathComponent, video.resolution, video.folderName, video.isFavorite ? "favorite" : ""],
                    group: videosGroup
                ) {
                    onPlayURL(video.url)
                })
            }
        }

        // MARK: - 3. Folders Context
        if !library.folders.isEmpty {
            let foldersGroup = "Folders (\(library.folders.count))"
            for folder in library.folders {
                items.append(PaletteCommand(
                    folder.name,
                    id: "folder-\(folder.id.uuidString)",
                    subtitle: "\(folder.videoCount) \(folder.videoCount == 1 ? "video" : "videos")",
                    icon: "folder.fill",
                    keywords: ["folder", "directory", folder.name, folder.url.path],
                    group: foldersGroup
                ) {
                    library.navigate(to: .folder(id: folder.id))
                })
            }
        }

        // MARK: - 4. Navigation & Views Context
        let navGroup = "Navigation"
        items.append(PaletteCommand(
            "All Videos",
            id: "nav-all-videos",
            subtitle: library.selectedCategory == .allVideos ? "Current" : nil,
            icon: "film.stack",
            keywords: ["all", "videos", "library", "home"],
            group: navGroup
        ) {
            library.navigate(to: .allVideos)
        })

        items.append(PaletteCommand(
            "Recent Videos",
            id: "nav-recent",
            subtitle: library.selectedCategory == .recent ? "Current" : nil,
            icon: "clock",
            keywords: ["recent", "history", "watched", "continue"],
            group: navGroup
        ) {
            library.navigate(to: .recent)
        })

        items.append(PaletteCommand(
            "Favorites",
            id: "nav-favorites",
            subtitle: library.selectedCategory == .favorites ? "Current" : nil,
            icon: "heart.fill",
            keywords: ["favorites", "starred", "bookmarks", "likes"],
            group: navGroup
        ) {
            library.navigate(to: .favorites)
        })

        items.append(PaletteCommand(
            "Go Back",
            id: "nav-back",
            icon: "arrow.left",
            shortcut: "⌘[",
            isDisabled: !library.canGoBack,
            group: navGroup
        ) {
            library.goBack()
        })

        items.append(PaletteCommand(
            "Go Forward",
            id: "nav-forward",
            icon: "arrow.right",
            shortcut: "⌘]",
            isDisabled: !library.canGoForward,
            group: navGroup
        ) {
            library.goForward()
        })

        items.append(PaletteCommand(
            library.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
            id: "nav-toggle-sidebar",
            icon: "sidebar.leading",
            shortcut: "⌘B",
            keywords: ["sidebar", "panel", "toggle", "navigation"],
            group: navGroup
        ) {
            library.toggleSidebar()
        })

        // MARK: - 5. Settings & Appearance Context
        let settingsGroup = "Settings & Appearance"
        items.append(PaletteCommand(
            "Open Settings...",
            id: "open-settings",
            subtitle: "Preferences & System Configuration",
            icon: "gearshape",
            shortcut: "⌘,",
            keywords: ["settings", "preferences", "config", "options", "setup", "controls"],
            group: settingsGroup
        ) {
            SettingsManager.shared.openSettings()
        })

        items.append(PaletteCommand(
            "Dark Mode",
            id: "theme-dark",
            subtitle: themeManager.mode == .dark ? "Current theme" : nil,
            icon: "moon",
            keywords: ["theme", "dark", "night", "black", "appearance"],
            group: settingsGroup
        ) {
            themeManager.mode = .dark
        })

        items.append(PaletteCommand(
            "Light Mode",
            id: "theme-light",
            subtitle: themeManager.mode == .light ? "Current theme" : nil,
            icon: "sun.max",
            keywords: ["theme", "light", "day", "white", "bright", "appearance"],
            group: settingsGroup
        ) {
            themeManager.mode = .light
        })

        items.append(PaletteCommand(
            "System Mode",
            id: "theme-system",
            subtitle: themeManager.mode == .system ? "Current theme" : nil,
            icon: "circle.righthalf.filled",
            keywords: ["theme", "system", "automatic", "default", "appearance"],
            group: settingsGroup
        ) {
            themeManager.mode = .system
        })

        items.append(PaletteCommand(
            "Toggle Light / Dark Mode",
            id: "theme-toggle",
            icon: "circle.righthalf.filled",
            keywords: ["toggle", "theme", "switch", "appearance"],
            group: settingsGroup
        ) {
            themeManager.toggleTheme()
        })

        items.append(PaletteCommand(
            "Grid View",
            id: "view-grid",
            subtitle: library.viewMode == .grid ? "Current view" : nil,
            icon: "square.grid.2x2",
            keywords: ["view", "grid", "cards", "posters", "layout"],
            group: settingsGroup
        ) {
            library.viewMode = .grid
        })

        items.append(PaletteCommand(
            "List View",
            id: "view-list",
            subtitle: library.viewMode == .list ? "Current view" : nil,
            icon: "list.bullet",
            keywords: ["view", "list", "table", "details", "layout"],
            group: settingsGroup
        ) {
            library.viewMode = .list
        })

        items.append(PaletteCommand(
            "Sort by Date Added",
            id: "sort-date-added",
            subtitle: library.sortOption == .dateAdded ? "Current sort" : nil,
            icon: "arrow.up.arrow.down",
            keywords: ["sort", "date", "recent", "order"],
            group: settingsGroup
        ) {
            library.sortOption = .dateAdded
        })

        items.append(PaletteCommand(
            "Sort by Title",
            id: "sort-title",
            subtitle: library.sortOption == .title ? "Current sort" : nil,
            icon: "arrow.up.arrow.down",
            keywords: ["sort", "title", "name", "alphabetical", "order"],
            group: settingsGroup
        ) {
            library.sortOption = .title
        })

        items.append(PaletteCommand(
            "Sort by Duration",
            id: "sort-duration",
            subtitle: library.sortOption == .duration ? "Current sort" : nil,
            icon: "arrow.up.arrow.down",
            keywords: ["sort", "duration", "length", "runtime", "order"],
            group: settingsGroup
        ) {
            library.sortOption = .duration
        })

        items.append(PaletteCommand(
            "Sort by File Size",
            id: "sort-file-size",
            subtitle: library.sortOption == .fileSize ? "Current sort" : nil,
            icon: "arrow.up.arrow.down",
            keywords: ["sort", "size", "bytes", "storage", "order"],
            group: settingsGroup
        ) {
            library.sortOption = .fileSize
        })

        // MARK: - 6. Window Controls Context
        let windowGroup = "Window"
        items.append(PaletteCommand(
            windowManager.isAnyFullscreen ? "Exit Full Screen" : "Enter Full Screen",
            id: "window-native-fullscreen",
            icon: "arrow.up.left.and.arrow.down.right",
            shortcut: "⌃⌘F",
            keywords: ["fullscreen", "window", "maximize", "display"],
            group: windowGroup
        ) {
            windowManager.toggleNativeFullscreen()
        })

        items.append(PaletteCommand(
            "Windowed Full Screen (Zoom)",
            id: "window-windowed-fullscreen",
            icon: "arrow.up.left.and.arrow.down.right.rectangle",
            shortcut: "⌃⌥⌘F",
            keywords: ["zoom", "windowed", "fill", "fullscreen"],
            group: windowGroup
        ) {
            windowManager.toggleWindowedFullscreen()
        })

        items.append(PaletteCommand(
            "Minimize Window",
            id: "window-minimize",
            icon: "minus",
            shortcut: "⌘M",
            keywords: ["minimize", "hide", "dock"],
            group: windowGroup
        ) {
            NSApp.keyWindow?.miniaturize(nil)
        })

        items.append(PaletteCommand(
            "Close Window",
            id: "window-close",
            icon: "xmark",
            shortcut: "⌘W",
            keywords: ["close", "window", "exit"],
            group: windowGroup
        ) {
            NSApp.keyWindow?.performClose(nil)
        })

        // MARK: - 7. Quick Actions Context
        let actionsGroup = "Quick Actions"
        items.append(PaletteCommand(
            "Open File...",
            id: "action-open-file",
            subtitle: "Open media file to play or add",
            icon: "doc.badge.plus",
            shortcut: "⌘O",
            keywords: ["open", "file", "play", "video", "audio", "browse", "choose"],
            group: actionsGroup
        ) {
            onOpenFilePicker()
        })

        items.append(PaletteCommand(
            "Add Folder to Library...",
            id: "action-add-folder",
            subtitle: "Scan and monitor folder for media",
            icon: "folder.badge.plus",
            keywords: ["folder", "add", "import", "scan", "directory", "library"],
            group: actionsGroup
        ) {
            library.selectAndAddFolder()
        })

        items.append(PaletteCommand(
            "Check for Updates...",
            id: "action-check-updates",
            subtitle: "Check GitHub for new Frames releases",
            icon: "arrow.triangle.2.circlepath",
            keywords: ["update", "upgrade", "version", "github", "releases", "ota", "new"],
            group: actionsGroup
        ) {
            UpdateManager.shared.checkForUpdates(manual: true)
        })

        return items
    }
}
