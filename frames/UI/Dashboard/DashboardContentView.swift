import SwiftUI
import AppKit

private let goldenFavoriteColor = Color(red: 1.0, green: 0.8, blue: 0.0)

public struct DashboardContentView: View {
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    @State private var hoveredVideoId: UUID? = nil
    @State private var isHoveringAddTile: Bool = false
    @State private var isHoveringAddRow: Bool = false
    @State private var windowManager = WindowManager.shared

    public init(library: LibraryManager, onPlayURL: @escaping (URL) -> Void) {
        self.library = library
        self.onPlayURL = onPlayURL
    }

    public static let addListThumbnailWidth: CGFloat = VideoListRowView.thumbnailWidth
    public static let addListThumbnailHeight: CGFloat = VideoListRowView.thumbnailHeight

    public static func computeGridItemWidth(containerWidth: CGFloat, contentPadding: CGFloat, isNarrow: Bool) -> CGFloat {
        let gridSpacing: CGFloat = isNarrow ? 10 : 14
        let minColWidth: CGFloat = isNarrow ? 140 : 180
        let availableWidth = max(0, containerWidth - contentPadding * 2)
        if availableWidth <= minColWidth {
            return max(0, availableWidth)
        }
        let columnCount = max(1, Int((availableWidth + gridSpacing) / (minColWidth + gridSpacing)))
        return min(320, max(minColWidth, (availableWidth - CGFloat(columnCount - 1) * gridSpacing) / CGFloat(columnCount)))
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
                    if library.viewMode == .grid {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: isNarrow ? 12 : 18) {
                                // Add Video tile sits naturally as first cell alongside regular videos
                                if shouldShowAddCard {
                                    addVideoGridTile
                                }

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
                            }
                            .padding(contentPadding)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 8) {
                                // Top section: Dashed Add Video item matching video row dimensions
                                if shouldShowAddCard {
                                    addVideoListRow
                                }

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
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShadcnTheme.background)
            .clipped()
            .animation(.fluidSpring, value: library.viewMode)
            .animation(.fluidSpring, value: isNarrow)
            .animation(.fluidSpring, value: library.selectedCategory)
            .animation(.fluidWindow, value: windowManager.currentLayoutState)
        }
    }

    public static func shouldShowAddCard(searchQuery: String, category: SidebarCategory, showTile: Bool = true) -> Bool {
        guard showTile else { return false }
        guard searchQuery.isEmpty else { return false }
        switch category {
        case .allVideos, .folder:
            return true
        case .recent, .favorites:
            return false
        }
    }

    private var shouldShowAddCard: Bool {
        Self.shouldShowAddCard(
            searchQuery: library.searchQuery,
            category: library.selectedCategory,
            showTile: SettingsManager.shared.showAddVideoTile
        )
    }

    // MARK: - Add Video Dashed-Border Grid Tile (Shown exactly like other video tiles at the top)
    private var addVideoGridTile: some View {
        Button {
            library.selectAndAddVideos()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // 16:9 Dashed Video Frame matching other video cards
                ZStack {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                        .fill(isHoveringAddTile ? ShadcnTheme.cardHover : ShadcnTheme.card.opacity(0.35))

                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(isHoveringAddTile ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                }
                .aspectRatio(16/9, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                        .strokeBorder(
                            isHoveringAddTile ? ShadcnTheme.borderActive : ShadcnTheme.border,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                        )
                )

                // Title & Subtitle matching other video cards
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Video")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isHoveringAddTile ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        .lineLimit(1)

                    Text("Import video files")
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundMuted.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .pointingHand()
        .help("Add video files or folder to library")
        .onHover { h in
            withAnimation(.fluidQuick) {
                isHoveringAddTile = h
            }
        }
        .contextMenu {
            Button("Add Video Files...") {
                library.selectFilesToPlay { url in
                    onPlayURL(url)
                }
            }
            Button("Add Folder to Library...") {
                library.selectAndAddFolder()
            }
        }
    }

    // MARK: - Add Video Dashed-Border List Item (Compact single row matching VideoListRowView)
    private var addVideoListRow: some View {
        Button {
            library.selectAndAddVideos()
        } label: {
            HStack(spacing: 12) {
                // Mini 16:9 thumbnail preview with dashed border
                ZStack {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(isHoveringAddRow ? ShadcnTheme.cardHover : ShadcnTheme.card.opacity(0.45))

                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(isHoveringAddRow ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                }
                .frame(width: VideoListRowView.thumbnailWidth, height: VideoListRowView.thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(
                            isHoveringAddRow ? ShadcnTheme.borderActive : ShadcnTheme.border,
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                        )
                )

                // Title & Subtitle matching VideoListRowView layout & typography
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Video")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isHoveringAddRow ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        .lineLimit(1)

                    Text("Import video files or folders to library")
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isHoveringAddRow ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isHoveringAddRow ? ShadcnTheme.cardHover : ShadcnTheme.card.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(
                        isHoveringAddRow ? ShadcnTheme.borderActive : ShadcnTheme.border,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
        .pointingHand()
        .help("Add video files or folder to library")
        .accessibilityLabel("Add video files or folder")
        .onHover { h in
            withAnimation(.fluidQuick) {
                isHoveringAddRow = h
            }
        }
        .contextMenu {
            Button("Add Video Files...") {
                library.selectFilesToPlay { url in
                    onPlayURL(url)
                }
            }
            Button("Add Folder to Library...") {
                library.selectAndAddFolder()
            }
        }
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

    // Dedicated Favorites Empty State
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
                library.selectAndAddVideos()
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
            .contentShape(Rectangle())
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
                .contentShape(Rectangle())
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
                .contentShape(Rectangle())
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
            // 16:9 Movie-Type Thumbnail Poster Container
            ZStack(alignment: .bottomLeading) {
                // Uniform Movie-type thumbnail (matching the MKV file style for all videos)
                ZStack {
                    Rectangle()
                        .fill(ShadcnTheme.cardHover)
                        .aspectRatio(16/9, contentMode: .fill)

                    Image(systemName: "film")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(ShadcnTheme.foregroundMuted.opacity(0.55))
                }
                .aspectRatio(16/9, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

                // Hover Play Overlay (shows play button on hover without shadows)
                ZStack {
                    if isHovered {
                        Color.black.opacity(0.32)
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
                            )
                            .transition(.opacity)
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
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.65))

                            Image(systemName: video.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundStyle(video.isFavorite ? goldenFavoriteColor : Color.white.opacity(0.85))
                                .scaleEffect(video.isFavorite ? 1.05 : 0.95)
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .pointingHand()
                    .opacity(isHovered || video.isFavorite ? 1.0 : 0.0)
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
    public var onThumbnailHover: ((Bool) -> Void)? = nil

    // MARK: - Mini Thumbnail Dimensions & Spec Constants
    public static let thumbnailWidth: CGFloat = 76
    public static let thumbnailHeight: CGFloat = 43
    public static let playBadgeDiameter: CGFloat = 28
    public static let playIconSize: CGFloat = 10
    public static let scrimOpacity: Double = 0.32
    public static let badgeCardFillOpacity: Double = 0.65

    @State private var isThumbnailHovered: Bool = false

    public init(
        video: VideoItem,
        isHovered: Bool,
        containerWidth: CGFloat,
        onHover: @escaping (Bool) -> Void,
        library: LibraryManager,
        onPlayURL: @escaping (URL) -> Void,
        initialThumbnailHovered: Bool = false,
        onThumbnailHover: ((Bool) -> Void)? = nil
    ) {
        self.video = video
        self.isHovered = isHovered
        self.containerWidth = containerWidth
        self.onHover = onHover
        self._library = Bindable(wrappedValue: library)
        self.onPlayURL = onPlayURL
        self._isThumbnailHovered = State(initialValue: initialThumbnailHovered)
        self.onThumbnailHover = onThumbnailHover
    }

    public var isThumbnailHoveredValue: Bool {
        _isThumbnailHovered.wrappedValue
    }

    public mutating func simulateThumbnailHover(_ hovered: Bool) {
        _isThumbnailHovered = State(initialValue: hovered)
    }

    public var shouldShowThumbnailPlayOverlay: Bool {
        isThumbnailHoveredValue
    }

    public static func shouldShowPlayOverlay(isThumbnailHovered: Bool, isRowHovered: Bool) -> Bool {
        return isThumbnailHovered
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Mini 16:9 movie-type preview
            ZStack {
                Rectangle()
                    .fill(ShadcnTheme.cardHover)
                    .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)

                Image(systemName: "film")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(ShadcnTheme.foregroundMuted.opacity(0.65))

                // Hover Play Overlay (shows play button only on thumbnail hover)
                ZStack {
                    if isThumbnailHovered {
                        Color.black.opacity(Self.scrimOpacity)
                            .overlay(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: Self.playBadgeDiameter, height: Self.playBadgeDiameter)
                                    .overlay(
                                        Circle()
                                            .fill(ShadcnTheme.card.opacity(Self.badgeCardFillOpacity))
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(ShadcnTheme.borderActive, lineWidth: 1)
                                    )
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: Self.playIconSize))
                                            .foregroundStyle(ShadcnTheme.foreground)
                                            .offset(x: 1)
                                    )
                            )
                            .transition(.opacity)
                    }
                }
                .animation(.fluidQuick, value: isThumbnailHovered)
            }
            .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
            .onHover { hovering in
                isThumbnailHovered = hovering
                onThumbnailHover?(hovering)
            }

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
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.0001))

                    Image(systemName: video.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(video.isFavorite ? goldenFavoriteColor : ShadcnTheme.foregroundMuted)
                        .scaleEffect(video.isFavorite ? 1.08 : 0.95)
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .pointingHand()
            .opacity(isHovered || video.isFavorite ? 1.0 : 0.0)
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
        .onChange(of: isHovered) { _, hovered in
            if !hovered {
                isThumbnailHovered = false
            }
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
