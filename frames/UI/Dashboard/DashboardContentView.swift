import SwiftUI
import AppKit

// MARK: - Tactile Card Press Button Style
public struct TactileCardPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .animation(.fluidQuick, value: configuration.isPressed)
    }
}

public struct DashboardContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                if library.selectedCategory == .settings {
                    SettingsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if library.filteredVideos.isEmpty {
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
            .animation(.fluidQuick, value: library.viewMode)
            .animation(.fluidQuick, value: library.selectedCategory)
        }
    }

    public static func shouldShowAddCard(searchQuery: String, category: SidebarCategory, showTile: Bool = true) -> Bool {
        guard showTile else { return false }
        guard searchQuery.isEmpty else { return false }
        switch category {
        case .allVideos, .folder:
            return true
        case .recent, .favorites, .settings:
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
                        .animation(.fluidQuick, value: isHoveringAddTile)
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
        .buttonStyle(TactileCardPressButtonStyle())
        .animation(.fluidQuick, value: isHoveringAddTile)
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
            .pointingHand()
            Button("Add Folder to Library...") {
                library.selectAndAddFolder()
            }
            .pointingHand()
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
                        .animation(.fluidQuick, value: isHoveringAddRow)
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
        .buttonStyle(TactileCardPressButtonStyle())
        .animation(.fluidQuick, value: isHoveringAddRow)
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
            .pointingHand()
            Button("Add Folder to Library...") {
                library.selectAndAddFolder()
            }
            .pointingHand()
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
                case .allVideos, .folder, .settings:
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
