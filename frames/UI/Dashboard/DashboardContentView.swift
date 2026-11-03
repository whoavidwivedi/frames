import SwiftUI
import AppKit

public struct DashboardContentView: View {
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    @State private var hoveredVideoId: UUID? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)
    ]

    public init(library: LibraryManager, onPlayURL: @escaping (URL) -> Void) {
        self.library = library
        self.onPlayURL = onPlayURL
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Dashboard Top Navigation Bar
            topBar

            Divider()
                .overlay(ShadcnTheme.border)

            // Main Content Area
            if library.filteredVideos.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    if library.viewMode == .grid {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(library.filteredVideos) { video in
                                videoGridCard(video: video)
                            }
                        }
                        .padding(20)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(library.filteredVideos) { video in
                                videoListRow(video: video)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .background(ShadcnTheme.background)
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 12) {
            // Category Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(library.selectedCategoryTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                Text("\(library.filteredVideos.count) \(library.filteredVideos.count == 1 ? "video" : "videos")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
            }

            Spacer()

            // Search Bar (shadcn input style)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)

                TextField("Search videos...", text: $library.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(ShadcnTheme.foreground)

                if !library.searchQuery.isEmpty {
                    Button {
                        library.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 200)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(ShadcnTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
            )

            // Sort Menu
            Menu {
                ForEach(SortOption.allCases) { opt in
                    Button {
                        library.sortOption = opt
                    } label: {
                        HStack {
                            Text(opt.rawValue)
                            if library.sortOption == opt {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                    Text(library.sortOption.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // View Mode Toggle (Grid vs List)
            HStack(spacing: 2) {
                Button {
                    library.viewMode = .grid
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(library.viewMode == .grid ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                        .frame(width: 26, height: 26)
                        .background(library.viewMode == .grid ? ShadcnTheme.cardHover : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                Button {
                    library.viewMode = .list
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(library.viewMode == .list ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                        .frame(width: 26, height: 26)
                        .background(library.viewMode == .list ? ShadcnTheme.cardHover : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(ShadcnTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
            )

            // Quick Open File Button
            Button {
                library.selectFilesToPlay { url in
                    onPlayURL(url)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                    Text("Open File")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(ShadcnTheme.primaryForeground)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.primary)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Video Grid Card
    private func videoGridCard(video: VideoItem) -> some View {
        let isHovered = hoveredVideoId == video.id

        return Button {
            onPlayURL(video.url)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // 16:9 Thumbnail Poster Container
                ZStack(alignment: .bottomLeading) {
                    // Thumbnail / Placeholder
                    if let thumb = video.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [ShadcnTheme.cardHover, ShadcnTheme.card],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .aspectRatio(16/9, contentMode: .fill)
                            .overlay(
                                Image(systemName: "film")
                                    .font(.system(size: 26))
                                    .foregroundStyle(ShadcnTheme.foregroundMuted.opacity(0.4))
                            )
                    }

                    // Hover Play Overlay
                    if isHovered {
                        Color.black.opacity(0.35)
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.95))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color.black)
                                            .offset(x: 1.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                            )
                            .transition(.opacity)
                    }

                    // Top Badges (Resolution / HDR)
                    HStack {
                        if !video.resolution.isEmpty {
                            Text(video.resolution)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.75))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()

                        Button {
                            library.toggleFavorite(videoId: video.id)
                        } label: {
                            Image(systemName: video.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundStyle(video.isFavorite ? Color.yellow : Color.white.opacity(0.8))
                                .padding(5)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered || video.isFavorite ? 1.0 : 0.0)
                    }
                    .padding(8)
                    .frame(maxHeight: .infinity, alignment: .top)

                    // Bottom Duration Badge
                    if video.duration > 0 {
                        HStack {
                            Spacer()
                            Text(video.formattedDuration)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .padding(8)
                    }

                    // Playback progress bar
                    if video.progress > 0 && video.progress < 0.98 {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: geo.size.width * video.progress, height: 3)
                        }
                        .frame(height: 3)
                        .background(Color.white.opacity(0.2))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                        .strokeBorder(isHovered ? ShadcnTheme.borderActive : ShadcnTheme.border, lineWidth: 1)
                )

                // Title and Meta Information
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foreground)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(video.folderName)
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .lineLimit(1)

                        if !video.formattedFileSize.isEmpty {
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundStyle(ShadcnTheme.foregroundMuted)

                            Text(video.formattedFileSize)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ShadcnTheme.foregroundMuted)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredVideoId = h ? video.id : nil
        }
        .contextMenu {
            Button("Play in Frames") {
                onPlayURL(video.url)
            }
            Button(video.isFavorite ? "Unfavorite" : "Favorite") {
                library.toggleFavorite(videoId: video.id)
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([video.url])
            }
        }
    }

    // MARK: - Video List Row
    private func videoListRow(video: VideoItem) -> some View {
        let isHovered = hoveredVideoId == video.id

        return Button {
            onPlayURL(video.url)
        } label: {
            HStack(spacing: 14) {
                // Mini 16:9 preview
                ZStack {
                    if let thumb = video.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: 80, height: 45)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(ShadcnTheme.cardHover)
                            .frame(width: 80, height: 45)
                            .overlay(
                                Image(systemName: "film")
                                    .font(.system(size: 14))
                                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                            )
                    }

                    if isHovered {
                        Color.black.opacity(0.4)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white)
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                )

                // Title & Folder
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foreground)
                        .lineLimit(1)

                    Text(video.folderName)
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                }

                Spacer()

                // Resolution
                Text(video.resolution)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    .frame(width: 50, alignment: .trailing)

                // Duration
                Text(video.formattedDuration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .frame(width: 60, alignment: .trailing)

                // Size
                Text(video.formattedFileSize)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .frame(width: 65, alignment: .trailing)

                // Favorite
                Button {
                    library.toggleFavorite(videoId: video.id)
                } label: {
                    Image(systemName: video.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(video.isFavorite ? Color.yellow : ShadcnTheme.foregroundMuted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isHovered ? ShadcnTheme.cardHover : ShadcnTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isHovered ? ShadcnTheme.borderActive : ShadcnTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredVideoId = h ? video.id : nil
        }
        .contextMenu {
            Button("Play in Frames") {
                onPlayURL(video.url)
            }
            Button(video.isFavorite ? "Unfavorite" : "Favorite") {
                library.toggleFavorite(videoId: video.id)
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([video.url])
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(ShadcnTheme.card)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 24))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
            }

            VStack(spacing: 6) {
                Text(library.searchQuery.isEmpty ? "No videos found" : "No results for \"\(library.searchQuery)\"")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                Text(library.searchQuery.isEmpty ? "Add a folder in the sidebar or select video files to start playing." : "Try adjusting your search query.")
                    .font(.system(size: 12))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            if library.searchQuery.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        library.selectFilesToPlay { url in
                            onPlayURL(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "film")
                                .font(.system(size: 11))
                            Text("Select Files")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(ShadcnTheme.primaryForeground)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(ShadcnTheme.primary)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        library.selectAndAddFolder()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11))
                            Text("Add Folder")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(ShadcnTheme.foreground)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(ShadcnTheme.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                        .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
