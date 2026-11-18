import AppKit
import SwiftUI

let goldenFavoriteColor = Color(red: 1.0, green: 0.8, blue: 0.0)

// MARK: - Dedicated Video Grid Card View

public struct VideoGridCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let video: VideoItem
    public let isHovered: Bool
    public var onHover: (Bool) -> Void
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    @State private var isPressed: Bool = false

    public init(
        video: VideoItem,
        isHovered: Bool,
        onHover: @escaping (Bool) -> Void,
        library: LibraryManager,
        onPlayURL: @escaping (URL) -> Void
    ) {
        self.video = video
        self.isHovered = isHovered
        self.onHover = onHover
        _library = Bindable(wrappedValue: library)
        self.onPlayURL = onPlayURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 16:9 Movie-Type Thumbnail Poster Container
            ZStack(alignment: .bottomLeading) {
                // Uniform Movie-type thumbnail (matching the MKV file style for all videos)
                ZStack {
                    Rectangle()
                        .fill(ShadcnTheme.cardHover)
                        .overlay {
                            if let thumbnail = video.thumbnail {
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                        .clipped()

                    if video.thumbnail == nil {
                        Image(systemName: "film")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(ShadcnTheme.foregroundMuted.opacity(0.55))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()

                // Hover Play Overlay
                ZStack {
                    Color.black.opacity(isHovered ? 0.32 : 0.0)
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
                                .opacity(isHovered ? 1.0 : 0.0)
                                .animation(.fluidQuick, value: isHovered)
                        )
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
                        withAnimation(.fluidQuick) {
                            library.toggleFavorite(videoId: video.id)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.65))

                            Image(systemName: video.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundStyle(video.isFavorite ? goldenFavoriteColor : Color.white.opacity(0.85))
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
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(video.title)

                if let artist = video.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

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
        .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1.0)
        .animation(.fluidQuick, value: isHovered)
        .animation(.fluidQuick, value: isPressed)
        .contentShape(Rectangle())
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
