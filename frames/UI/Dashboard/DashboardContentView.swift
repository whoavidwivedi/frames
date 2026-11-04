import SwiftUI
import AppKit

private let goldenFavoriteColor = Color(red: 1.0, green: 0.8, blue: 0.0)

public struct DashboardContentView: View {
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    @State private var hoveredVideoId: UUID? = nil
    @State private var windowManager = WindowManager.shared

    public init(library: LibraryManager, onPlayURL: @escaping (URL) -> Void) {
        self.library = library
        self.onPlayURL = onPlayURL
    }

    public var body: some View {
        GeometryReader { geo in
            let isNarrow = windowManager.isCompact || windowManager.isQuarterScreen || geo.size.width < 480
            let columns = [
                GridItem(.adaptive(minimum: isNarrow ? 140 : 180, maximum: 320), spacing: isNarrow ? 10 : 14)
            ]
            let contentPadding: CGFloat = isNarrow ? 12 : 20

            Group {
                if library.filteredVideos.isEmpty {
                    emptyStateView(isNarrow: isNarrow)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        if library.viewMode == .grid {
                            LazyVGrid(columns: columns, spacing: isNarrow ? 12 : 18) {
                                ForEach(library.filteredVideos) { video in
                                    VideoGridCardView(
                                        video: video,
                                        isHovered: hoveredVideoId == video.id,
                                        onHover: { h in
                                            withAnimation(.fluidQuick) {
                                                hoveredVideoId = h ? video.id : nil
                                            }
                                        },
                                        library: library,
                                        onPlayURL: onPlayURL
                                    )
                                }

                                if shouldShowAddCard {
                                    addMediaGridCard
                                }
                            }
                            .padding(contentPadding)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(library.filteredVideos) { video in
                                    VideoListRowView(
                                        video: video,
                                        isHovered: hoveredVideoId == video.id,
                                        containerWidth: geo.size.width,
                                        onHover: { h in
                                            withAnimation(.fluidQuick) {
                                                hoveredVideoId = h ? video.id : nil
                                            }
                                        },
                                        library: library,
                                        onPlayURL: onPlayURL
                                    )
                                }
                            }
                            .padding(contentPadding)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShadcnTheme.background)
            .animation(.fluidSpring, value: library.viewMode)
            .animation(.fluidSpring, value: isNarrow)
            .animation(.fluidSpring, value: library.selectedCategory)
            .animation(.fluidWindow, value: windowManager.currentLayoutState)
        }
    }

    private var shouldShowAddCard: Bool {
        library.searchQuery.isEmpty && (library.selectedCategory == .allVideos || isFolderCategory)
    }

    private var isFolderCategory: Bool {
        if case .folder = library.selectedCategory { return true }
        return false
    }

    // MARK: - Add Media Dashed-Border Grid Card
    private var addMediaGridCard: some View {
        Menu {
            Button {
                library.selectFilesToPlay { url in
                    onPlayURL(url)
                }
            } label: {
                Label("Select Files to Play...", systemImage: "doc.badge.plus")
            }

            Button {
                library.selectAndAddFolder()
            } label: {
                Label("Add Folder to Library...", systemImage: "folder.badge.plus")
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                        .fill(ShadcnTheme.card.opacity(0.35))
                        .aspectRatio(16/9, contentMode: .fill)
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                .strokeBorder(
                                    ShadcnTheme.border,
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                                )
                        )

                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)

                        Text("Add Media")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Media...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                        .lineLimit(1)

                    Text("Files or folder")
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundMuted.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .pointingHand()
        .help("Add video files or folder to library")
    }

    // MARK: - Responsive Empty States
    @ViewBuilder
    private func emptyStateView(isNarrow: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()

            if !library.searchQuery.isEmpty {
                // Search no results state
                searchEmptyState
            } else {
                switch library.selectedCategory {
                case .favorites:
                    favoritesEmptyState
                case .recent:
                    recentEmptyState
                case .allVideos, .folder:
                    genericLibraryEmptyState
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, isNarrow ? 16 : 24)
    }

    // Dedicated Favorites Empty State (Clean, no Select Files / Add Folder buttons)
    private var favoritesEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ShadcnTheme.card)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )

                Image(systemName: "star")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(goldenFavoriteColor)
            }

            VStack(spacing: 6) {
                Text("No Favorites Yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                Text("Add videos to favorites by clicking the star icon on any video.")
                    .font(.system(size: 12))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
    }

    // Dedicated Recent Empty State
    private var recentEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ShadcnTheme.card)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )

                Image(systemName: "clock")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
            }

            VStack(spacing: 6) {
                Text("No Recent Videos")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                Text("Videos you play will appear here so you can continue where you left off.")
                    .font(.system(size: 12))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
    }

    // Search Empty State
    private var searchEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ShadcnTheme.card)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
            }

            VStack(spacing: 6) {
                Text("No results for \"\(library.searchQuery)\"")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                Text("Try adjusting your search query or clear the filter.")
                    .font(.system(size: 12))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
    }

    // Generic Empty State with Dashed Frame + Plus Icon & Action Buttons
    private var genericLibraryEmptyState: some View {
        VStack(spacing: 16) {
            // Iconic dashed-line frame with plus icon
            Button {
                library.selectFilesToPlay { url in
                    onPlayURL(url)
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                        .fill(ShadcnTheme.card.opacity(0.4))
                        .frame(width: 72, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                                .strokeBorder(
                                    ShadcnTheme.border,
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                                )
                        )

                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .help("Select files to play")

            VStack(spacing: 6) {
                Text("No videos found")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                Text("Add a folder in the sidebar or select video files to start playing.")
                    .font(.system(size: 12))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            HStack(spacing: 12) {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .foregroundStyle(ShadcnTheme.primaryForeground)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                            .fill(ShadcnTheme.primary)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointingHand()

                Button {
                    library.selectAndAddFolder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11))
                        Text("Add Folder")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .foregroundStyle(ShadcnTheme.foreground)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                            .fill(ShadcnTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointingHand()
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Dedicated Video Grid Card View
public struct VideoGridCardView: View {
    public let video: VideoItem
    public let isHovered: Bool
    public var onHover: (Bool) -> Void
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void

    public var body: some View {
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

                // Hover Play Overlay (Liquid Glass)
                ZStack {
                    if isHovered {
                        Color.black.opacity(0.30)
                            .overlay(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .fill(ShadcnTheme.card.opacity(0.65))
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(ShadcnTheme.borderActive, lineWidth: 1)
                                    )
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(ShadcnTheme.foreground)
                                            .offset(x: 1.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .animation(.fluidQuick, value: isHovered)

                // Top Badges (Resolution / Instant Favorite Star)
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

                    // Instant Golden Star Button
                    Button {
                        withAnimation(.fluidSpring) {
                            library.toggleFavorite(videoId: video.id)
                        }
                    } label: {
                        Image(systemName: video.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(video.isFavorite ? goldenFavoriteColor : Color.white.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Circle())
                            .scaleEffect(video.isFavorite ? 1.05 : 0.95)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .opacity(isHovered || video.isFavorite ? 1.0 : 0.0)
                    .scaleEffect(isHovered || video.isFavorite ? 1.0 : 0.85)
                    .animation(.fluidQuick, value: isHovered)
                    .animation(.fluidSpring, value: video.isFavorite)
                    .help(video.isFavorite ? "Remove from Favorites" : "Add to Favorites")
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
                            .fill(ShadcnTheme.primaryHighlight)
                            .frame(width: geo.size.width * video.progress, height: 3)
                    }
                    .frame(height: 3)
                    .background(Color.white.opacity(0.15))
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
                    .truncationMode(.middle)

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
        .contentShape(Rectangle())
        .offset(y: isHovered ? -3 : 0)
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.22 : 0.0), radius: 12, x: 0, y: 6)
        .animation(.fluidQuick, value: isHovered)
        .onTapGesture {
            onPlayURL(video.url)
        }
        .pointingHand()
        .onHover { h in
            onHover(h)
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
}

// MARK: - Dedicated Video List Row View
public struct VideoListRowView: View {
    public let video: VideoItem
    public let isHovered: Bool
    public let containerWidth: CGFloat
    public var onHover: (Bool) -> Void
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void

    public var body: some View {
        HStack(spacing: 12) {
            // Mini 16:9 preview
            ZStack {
                if let thumb = video.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(width: 76, height: 43)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(ShadcnTheme.cardHover)
                        .frame(width: 76, height: 43)
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
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
            )
            .animation(.fluidQuick, value: isHovered)

            // Title & Folder
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ShadcnTheme.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(video.folderName)
                    .font(.system(size: 11))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Resolution (hide if split-screen width is very constrained)
            if containerWidth >= 380 {
                Text(video.resolution)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    .frame(width: 44, alignment: .trailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Duration
            Text(video.formattedDuration)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ShadcnTheme.foregroundMuted)
                .frame(width: 54, alignment: .trailing)

            // Size (hide if split-screen width is constrained)
            if containerWidth >= 460 {
                Text(video.formattedFileSize)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                    .frame(width: 60, alignment: .trailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Instant Favorite Star Button
            Button {
                withAnimation(.fluidSpring) {
                    library.toggleFavorite(videoId: video.id)
                }
            } label: {
                Image(systemName: video.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(video.isFavorite ? goldenFavoriteColor : ShadcnTheme.foregroundMuted)
                    .frame(width: 26, height: 26)
                    .scaleEffect(video.isFavorite ? 1.08 : 0.95)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .opacity(isHovered || video.isFavorite ? 1.0 : 0.0)
            .scaleEffect(isHovered || video.isFavorite ? 1.0 : 0.85)
            .animation(.fluidQuick, value: isHovered)
            .animation(.fluidSpring, value: video.isFavorite)
            .help(video.isFavorite ? "Remove from Favorites" : "Add to Favorites")
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
        .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
        .scaleEffect(isHovered ? 1.008 : 1.0)
        .animation(.fluidQuick, value: isHovered)
        .animation(.fluidSpring, value: containerWidth >= 380)
        .animation(.fluidSpring, value: containerWidth >= 460)
        .onTapGesture {
            onPlayURL(video.url)
        }
        .pointingHand()
        .onHover { h in
            onHover(h)
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
}
