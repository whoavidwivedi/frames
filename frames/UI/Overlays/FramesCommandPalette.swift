import SwiftUI
import AppKit

public struct FramesCommandPalette: View {
    @Binding public var isPresented: Bool
    public var engine: VideoPlayerEngine
    public var library: LibraryManager
    public var themeManager: ThemeManager
    public var windowManager: WindowManager
    public var onPlayURL: (URL) -> Void
    public var onOpenFilePicker: () -> Void

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
        CommandDialog(isPresented: $isPresented) {
            CommandInput(placeholder: "Type a command or search...")

            CommandList {
                CommandEmpty("No results found.")

                // MARK: - 1. Active Playback Context
                if engine.currentURL != nil {
                    CommandGroup(heading: "Playback: \(engine.metadata.title.isEmpty ? "Current Media" : engine.metadata.title)") {
                        CommandItem(
                            engine.isPlaying ? "Pause" : "Play",
                            id: "playback-play-pause",
                            subtitle: engine.isPlaying ? "Pause playback" : "Resume playback",
                            icon: engine.isPlaying ? "pause.fill" : "play.fill",
                            shortcut: "Space",
                            keywords: ["playback", "play", "pause", "resume", "stop"]
                        ) {
                            engine.togglePlayPause()
                        }

                        CommandItem(
                            engine.isMuted ? "Unmute Audio" : "Mute Audio",
                            id: "playback-mute",
                            subtitle: "Volume: \(Int(engine.volume * 100))%",
                            icon: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            shortcut: "M",
                            keywords: ["mute", "unmute", "sound", "volume", "audio", "quiet"]
                        ) {
                            engine.toggleMute()
                        }

                        CommandItem(
                            "Skip Forward 5s",
                            id: "playback-skip-forward-5",
                            icon: "goforward.5",
                            shortcut: "→",
                            keywords: ["forward", "seek", "skip", "fast"]
                        ) {
                            engine.skip(seconds: 5)
                        }

                        CommandItem(
                            "Skip Backward 5s",
                            id: "playback-skip-backward-5",
                            icon: "gobackward.5",
                            shortcut: "←",
                            keywords: ["rewind", "seek", "skip", "back"]
                        ) {
                            engine.skip(seconds: -5)
                        }

                        CommandItem(
                            "Skip Forward 30s",
                            id: "playback-skip-forward-30",
                            icon: "goforward.30",
                            shortcut: "⇧→",
                            keywords: ["jump", "forward", "seek", "skip", "fast"]
                        ) {
                            engine.skip(seconds: 30)
                        }

                        CommandItem(
                            "Skip Backward 30s",
                            id: "playback-skip-backward-30",
                            icon: "gobackward.30",
                            shortcut: "⇧←",
                            keywords: ["jump", "rewind", "seek", "skip", "back"]
                        ) {
                            engine.skip(seconds: -30)
                        }

                        CommandItem(
                            "Next Frame (Step Forward)",
                            id: "playback-step-forward",
                            icon: "forward.frame",
                            shortcut: ".",
                            keywords: ["frame", "step", "precision"]
                        ) {
                            engine.stepFrame(forward: true)
                        }

                        CommandItem(
                            "Previous Frame (Step Backward)",
                            id: "playback-step-backward",
                            icon: "backward.frame",
                            shortcut: ",",
                            keywords: ["frame", "step", "precision"]
                        ) {
                            engine.stepFrame(forward: false)
                        }

                        CommandItem(
                            "Normal Speed (1.0x)",
                            id: "playback-speed-1x",
                            subtitle: abs(engine.playbackRate - 1.0) < 0.01 ? "Current" : nil,
                            icon: "speedometer",
                            keywords: ["speed", "rate", "1x", "normal"]
                        ) {
                            engine.playbackRate = 1.0
                        }

                        CommandItem(
                            "Fast Speed (1.25x)",
                            id: "playback-speed-125x",
                            subtitle: abs(engine.playbackRate - 1.25) < 0.01 ? "Current" : nil,
                            icon: "speedometer",
                            keywords: ["speed", "rate", "1.25x", "fast"]
                        ) {
                            engine.playbackRate = 1.25
                        }

                        CommandItem(
                            "Fast Speed (1.5x)",
                            id: "playback-speed-15x",
                            subtitle: abs(engine.playbackRate - 1.5) < 0.01 ? "Current" : nil,
                            icon: "speedometer",
                            keywords: ["speed", "rate", "1.5x", "fast"]
                        ) {
                            engine.playbackRate = 1.5
                        }

                        CommandItem(
                            "Double Speed (2.0x)",
                            id: "playback-speed-2x",
                            subtitle: abs(engine.playbackRate - 2.0) < 0.01 ? "Current" : nil,
                            icon: "speedometer",
                            keywords: ["speed", "rate", "2x", "double", "fast"]
                        ) {
                            engine.playbackRate = 2.0
                        }

                        CommandItem(
                            "Slow Motion (0.5x)",
                            id: "playback-speed-05x",
                            subtitle: abs(engine.playbackRate - 0.5) < 0.01 ? "Current" : nil,
                            icon: "speedometer",
                            keywords: ["speed", "rate", "0.5x", "slow"]
                        ) {
                            engine.playbackRate = 0.5
                        }

                        // Subtitle Tracks
                        for track in engine.availableSubtitleTracks {
                            CommandItem(
                                "Subtitle: \(track.title)",
                                id: "sub-\(track.id)",
                                subtitle: engine.selectedSubtitleTrack.id == track.id ? "Active" : nil,
                                icon: "captions.bubble",
                                keywords: ["subtitle", "cc", "captions", track.title]
                            ) {
                                engine.selectSubtitleTrack(track)
                            }
                        }

                        // Audio Tracks
                        for track in engine.availableAudioTracks {
                            CommandItem(
                                "Audio Track: \(track.title)",
                                id: "audio-\(track.id)",
                                subtitle: engine.selectedAudioTrack?.id == track.id ? "Active" : nil,
                                icon: "waveform",
                                keywords: ["audio", "sound", "track", track.title]
                            ) {
                                engine.selectAudioTrack(track)
                            }
                        }

                        CommandItem(
                            "Silicon & Hardware Metrics Inspector",
                            id: "playback-stats",
                            subtitle: "Display real-time Metal 3 & unified memory telemetry",
                            icon: "cpu",
                            shortcut: "I",
                            keywords: ["hardware", "silicon", "gpu", "metal", "stats", "telemetry", "fps", "inspector"]
                        ) {
                            engine.activeInspectorSheet = (engine.activeInspectorSheet == .stats ? nil : .stats)
                        }

                        CommandItem(
                            "Capture Frame Snapshot",
                            id: "playback-capture-snapshot",
                            subtitle: "Save high-res frame to ~/Pictures/Frames",
                            icon: "camera.viewfinder",
                            shortcut: "⌘S",
                            keywords: ["snapshot", "screenshot", "capture", "photo", "image", "frame", "save"]
                        ) {
                            if let currentURL = engine.currentURL {
                                _ = try? FrameCaptureEngine.shared.saveFrame(
                                    pixelBuffer: nil,
                                    videoTitle: currentURL.deletingPathExtension().lastPathComponent,
                                    timestampSeconds: engine.currentTime
                                )
                            }
                        }

                        CommandItem(
                            "Jump to Beginning (00:00)",
                            id: "playback-jump-beginning",
                            subtitle: "Seek to start of media",
                            icon: "backward.end.fill",
                            shortcut: "0",
                            keywords: ["beginning", "start", "reset", "0", "seek"]
                        ) {
                            engine.seek(to: 0.0)
                        }

                        if engine.duration > 0 {
                            CommandItem(
                                "Jump to Halfway (50%)",
                                id: "playback-jump-halfway",
                                subtitle: "Seek to middle of media",
                                icon: "arrow.right.to.line",
                                keywords: ["half", "halfway", "middle", "50%"]
                            ) {
                                engine.seek(to: engine.duration * 0.5)
                            }
                        }

                        if engine.hasEnded {
                            CommandItem(
                                "Replay Video",
                                id: "playback-replay",
                                icon: "arrow.counterclockwise",
                                shortcut: "R",
                                keywords: ["replay", "restart", "play again"]
                            ) {
                                engine.replay()
                            }
                        }

                        CommandItem(
                            "Return to Dashboard",
                            id: "playback-return-dashboard",
                            subtitle: "Save progress and return to library",
                            icon: "chevron.left",
                            shortcut: "Esc",
                            keywords: ["dashboard", "home", "exit", "close", "back", "library"]
                        ) {
                            NotificationCenter.default.post(name: .returnToDashboardNotification, object: nil)
                        }
                    }

                    CommandSeparator()
                }

                // MARK: - 2. Videos Context
                if !library.videos.isEmpty {
                    CommandGroup(heading: "Videos (\(library.videos.count))") {
                        for video in library.videos {
                            let format = video.url.pathExtension.uppercased()
                            CommandItem(
                                video.title,
                                id: "video-\(video.id.uuidString)",
                                subtitle: "\(TimeFormatting.format(seconds: video.duration)) • \(format)\(video.isFavorite ? " • ★ Favorite" : "")",
                                icon: video.isFavorite ? "star.fill" : "play.rectangle.fill",
                                iconColor: video.isFavorite ? Color(red: 1.0, green: 0.8, blue: 0.0) : nil,
                                keywords: [video.title, format, video.url.lastPathComponent, video.resolution, video.folderName, video.isFavorite ? "favorite" : ""]
                            ) {
                                onPlayURL(video.url)
                            }
                        }
                    }

                    CommandSeparator()
                }

                // MARK: - 3. Folders Context
                if !library.folders.isEmpty {
                    CommandGroup(heading: "Folders (\(library.folders.count))") {
                        for folder in library.folders {
                            CommandItem(
                                folder.name,
                                id: "folder-\(folder.id.uuidString)",
                                subtitle: "\(folder.videoCount) \(folder.videoCount == 1 ? "video" : "videos")",
                                icon: "folder.fill",
                                keywords: ["folder", "directory", folder.name, folder.url.path]
                            ) {
                                library.navigate(to: .folder(id: folder.id))
                            }
                        }
                    }

                    CommandSeparator()
                }

                // MARK: - 4. Navigation & Views Context
                CommandGroup(heading: "Navigation") {
                    CommandItem(
                        "All Videos",
                        id: "nav-all-videos",
                        subtitle: library.selectedCategory == .allVideos ? "Current" : nil,
                        icon: "film.stack",
                        keywords: ["all", "videos", "library", "home"]
                    ) {
                        library.navigate(to: .allVideos)
                    }

                    CommandItem(
                        "Recent Videos",
                        id: "nav-recent",
                        subtitle: library.selectedCategory == .recent ? "Current" : nil,
                        icon: "clock",
                        keywords: ["recent", "history", "watched", "continue"]
                    ) {
                        library.navigate(to: .recent)
                    }

                    CommandItem(
                        "Favorites",
                        id: "nav-favorites",
                        subtitle: library.selectedCategory == .favorites ? "Current" : nil,
                        icon: "heart.fill",
                        keywords: ["favorites", "starred", "bookmarks", "likes"]
                    ) {
                        library.navigate(to: .favorites)
                    }

                    CommandItem(
                        "Go Back",
                        id: "nav-back",
                        icon: "arrow.left",
                        shortcut: "⌘[",
                        isDisabled: !library.canGoBack
                    ) {
                        library.goBack()
                    }

                    CommandItem(
                        "Go Forward",
                        id: "nav-forward",
                        icon: "arrow.right",
                        shortcut: "⌘]",
                        isDisabled: !library.canGoForward
                    ) {
                        library.goForward()
                    }

                    CommandItem(
                        library.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                        id: "nav-toggle-sidebar",
                        icon: "sidebar.leading",
                        shortcut: "⌘B",
                        keywords: ["sidebar", "panel", "toggle", "navigation"]
                    ) {
                        library.toggleSidebar()
                    }
                }

                CommandSeparator()

                // MARK: - 5. Settings & Appearance Context
                CommandGroup(heading: "Settings & Appearance") {
                    CommandItem(
                        "Dark Mode",
                        id: "theme-dark",
                        subtitle: themeManager.mode == .dark ? "Current theme" : nil,
                        icon: "moon",
                        keywords: ["theme", "dark", "night", "black", "appearance"]
                    ) {
                        themeManager.mode = .dark
                    }

                    CommandItem(
                        "Light Mode",
                        id: "theme-light",
                        subtitle: themeManager.mode == .light ? "Current theme" : nil,
                        icon: "sun.max",
                        keywords: ["theme", "light", "day", "white", "bright", "appearance"]
                    ) {
                        themeManager.mode = .light
                    }

                    CommandItem(
                        "System Mode",
                        id: "theme-system",
                        subtitle: themeManager.mode == .system ? "Current theme" : nil,
                        icon: "circle.righthalf.filled",
                        keywords: ["theme", "system", "automatic", "default", "appearance"]
                    ) {
                        themeManager.mode = .system
                    }

                    CommandItem(
                        "Toggle Light / Dark Mode",
                        id: "theme-toggle",
                        icon: "circle.righthalf.filled",
                        keywords: ["toggle", "theme", "switch", "appearance"]
                    ) {
                        themeManager.toggleTheme()
                    }

                    CommandItem(
                        "Grid View",
                        id: "view-grid",
                        subtitle: library.viewMode == .grid ? "Current view" : nil,
                        icon: "square.grid.2x2",
                        keywords: ["view", "grid", "cards", "posters", "layout"]
                    ) {
                        library.viewMode = .grid
                    }

                    CommandItem(
                        "List View",
                        id: "view-list",
                        subtitle: library.viewMode == .list ? "Current view" : nil,
                        icon: "list.bullet",
                        keywords: ["view", "list", "table", "details", "layout"]
                    ) {
                        library.viewMode = .list
                    }

                    CommandItem(
                        "Sort by Date Added",
                        id: "sort-date-added",
                        subtitle: library.sortOption == .dateAdded ? "Current sort" : nil,
                        icon: "arrow.up.arrow.down",
                        keywords: ["sort", "date", "recent", "order"]
                    ) {
                        library.sortOption = .dateAdded
                    }

                    CommandItem(
                        "Sort by Title",
                        id: "sort-title",
                        subtitle: library.sortOption == .title ? "Current sort" : nil,
                        icon: "arrow.up.arrow.down",
                        keywords: ["sort", "title", "name", "alphabetical", "order"]
                    ) {
                        library.sortOption = .title
                    }

                    CommandItem(
                        "Sort by Duration",
                        id: "sort-duration",
                        subtitle: library.sortOption == .duration ? "Current sort" : nil,
                        icon: "arrow.up.arrow.down",
                        keywords: ["sort", "duration", "length", "runtime", "order"]
                    ) {
                        library.sortOption = .duration
                    }

                    CommandItem(
                        "Sort by File Size",
                        id: "sort-file-size",
                        subtitle: library.sortOption == .fileSize ? "Current sort" : nil,
                        icon: "arrow.up.arrow.down",
                        keywords: ["sort", "size", "bytes", "storage", "order"]
                    ) {
                        library.sortOption = .fileSize
                    }
                }

                CommandSeparator()

                // MARK: - 6. Window Controls Context
                CommandGroup(heading: "Window") {
                    CommandItem(
                        windowManager.isAnyFullscreen ? "Exit Full Screen" : "Enter Full Screen",
                        id: "window-native-fullscreen",
                        icon: "arrow.up.left.and.arrow.down.right",
                        shortcut: "⌃⌘F",
                        keywords: ["fullscreen", "window", "maximize", "display"]
                    ) {
                        windowManager.toggleNativeFullscreen()
                    }

                    CommandItem(
                        "Windowed Full Screen (Zoom)",
                        id: "window-windowed-fullscreen",
                        icon: "arrow.up.left.and.arrow.down.right.rectangle",
                        shortcut: "⌃⌥⌘F",
                        keywords: ["zoom", "windowed", "fill", "fullscreen"]
                    ) {
                        windowManager.toggleWindowedFullscreen()
                    }

                    CommandItem(
                        "Minimize Window",
                        id: "window-minimize",
                        icon: "minus",
                        shortcut: "⌘M",
                        keywords: ["minimize", "hide", "dock"]
                    ) {
                        NSApp.keyWindow?.miniaturize(nil)
                    }

                    CommandItem(
                        "Close Window",
                        id: "window-close",
                        icon: "xmark",
                        shortcut: "⌘W",
                        keywords: ["close", "window", "exit"]
                    ) {
                        NSApp.keyWindow?.performClose(nil)
                    }
                }

                CommandSeparator()

                // MARK: - 7. Quick Actions Context
                CommandGroup(heading: "Quick Actions") {
                    CommandItem(
                        "Open File...",
                        id: "action-open-file",
                        subtitle: "Open media file to play or add",
                        icon: "doc.badge.plus",
                        shortcut: "⌘O",
                        keywords: ["open", "file", "play", "video", "audio", "browse", "choose"]
                    ) {
                        onOpenFilePicker()
                    }

                    CommandItem(
                        "Add Folder to Library...",
                        id: "action-add-folder",
                        subtitle: "Scan and monitor folder for media",
                        icon: "folder.badge.plus",
                        keywords: ["folder", "add", "import", "scan", "directory", "library"]
                    ) {
                        library.selectAndAddFolder()
                    }

                    CommandItem(
                        "Check for Updates...",
                        id: "action-check-updates",
                        subtitle: "Check GitHub for new Frames releases",
                        icon: "arrow.triangle.2.circlepath",
                        keywords: ["update", "upgrade", "version", "github", "releases", "ota", "new"]
                    ) {
                        UpdateManager.shared.checkForUpdates(manual: true)
                    }
                }
            }
        }
    }
}
