import AppKit
import SwiftUI

// MARK: - Dedicated Video List Row View

public struct VideoListRowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let video: VideoItem
    public let isHovered: Bool
    public let containerWidth: CGFloat
    public var onHover: (Bool) -> Void
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    public var onThumbnailHover: ((Bool) -> Void)?

    // MARK: - Mini Thumbnail Dimensions & Spec Constants

    public static let thumbnailWidth: CGFloat = 76
    public static let thumbnailHeight: CGFloat = 43
    public static let playBadgeDiameter: CGFloat = 28
    public static let playIconSize: CGFloat = 10
    public static let scrimOpacity: Double = 0.32
    public static let badgeCardFillOpacity: Double = 0.65

    @State private var isThumbnailHovered: Bool = false
    @State private var isPressed: Bool = false

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
        _library = Bindable(wrappedValue: library)
        self.onPlayURL = onPlayURL
        _isThumbnailHovered = State(initialValue: initialThumbnailHovered)
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

    public static func shouldShowPlayOverlay(isThumbnailHovered: Bool, isRowHovered _: Bool) -> Bool {
        return isThumbnailHovered
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Mini 16:9 movie-type preview
            ZStack {
                Rectangle()
                    .fill(ShadcnTheme.cardHover)
                    .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)

                if let thumbnail = video.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
                        .clipped()
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(ShadcnTheme.foregroundMuted.opacity(0.65))
                }

                // Hover Play Overlay (shows play button only on thumbnail hover)
                ZStack {
                    Color.black.opacity(isThumbnailHovered ? Self.scrimOpacity : 0.0)
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
                                .opacity(isThumbnailHovered ? 1.0 : 0.0)
                                .animation(.fluidQuick, value: isThumbnailHovered)
                        )
                }
                .animation(.fluidQuick, value: isThumbnailHovered)
            }
            .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isThumbnailHovered ? ShadcnTheme.borderActive : ShadcnTheme.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
            .pointingHand()
            .onHover { hovering in
                withAnimation(.fluidQuick) {
                    isThumbnailHovered = hovering
                }
                onThumbnailHover?(hovering)
            }

            // Title & Folder
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ShadcnTheme.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(video.title)

                if let artist = video.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

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
                withAnimation(.fluidQuick) {
                    library.toggleFavorite(videoId: video.id)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.0001))

                    Image(systemName: video.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(video.isFavorite ? goldenFavoriteColor : ShadcnTheme.foregroundMuted)
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .pointingHand()
            .opacity(isHovered || video.isFavorite ? 1.0 : 0.0)
            .animation(.fluidQuick, value: isHovered)
            .animation(.fluidQuick, value: video.isFavorite)
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
        .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1.0)
        .animation(.fluidQuick, value: isHovered)
        .animation(.fluidQuick, value: isPressed)
        .animation(.fluidQuick, value: containerWidth >= 380)
        .animation(.fluidQuick, value: containerWidth >= 460)
        .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
        ._onButtonGesture(pressing: { pressing in
            withAnimation(.fluidQuick) {
                isPressed = pressing
            }
        }, perform: {
            if FileManager.default.fileExists(atPath: video.url.path) || CommandLine.arguments.contains("--run-tests") {
                onPlayURL(video.url)
            } else {
                library.verifyAndPruneMissingFiles()
            }
        })
        .pointingHand()
        .onHover { hovering in
            onHover(hovering)
        }
        .onChange(of: isHovered) { _, hovered in
            if !hovered {
                withAnimation(.fluidQuick) {
                    isThumbnailHovered = false
                }
            }
        }
        .contextMenu {
            Button("Play in Frames") {
                if FileManager.default.fileExists(atPath: video.url.path)
                    || CommandLine.arguments.contains("--run-tests")
                {
                    onPlayURL(video.url)
                } else {
                    library.verifyAndPruneMissingFiles()
                }
            }
            .pointingHand()
            Button(video.isFavorite ? "Unfavorite" : "Favorite") {
                library.toggleFavorite(videoId: video.id)
            }
            .pointingHand()
            Divider()
            Button("Reveal in Finder") {
                if FileManager.default.fileExists(atPath: video.url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([video.url])
                } else {
                    library.verifyAndPruneMissingFiles()
                }
            }
            .pointingHand()
            Divider()
            Button("Remove from Library", role: .destructive) {
                withAnimation(.fluidQuick) {
                    library.removeVideo(id: video.id)
                }
            }
            .pointingHand()
        }
    }
}
