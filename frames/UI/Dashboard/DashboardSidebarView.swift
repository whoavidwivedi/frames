import SwiftUI
import AppKit

public struct DashboardSidebarView: View {
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    @State private var hoveredFolderId: UUID? = nil
    @State private var isShowingAddMenu: Bool = false

    public init(library: LibraryManager, onPlayURL: @escaping (URL) -> Void) {
        self.library = library
        self.onPlayURL = onPlayURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header / App Wordmark & Plus Action
            HStack(alignment: .center, spacing: 8) {
                Text("frames")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(ShadcnTheme.foreground)
                    .tracking(-0.5)

                Spacer()

                // Plus Icon Button with Menu to add folders or select files
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
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ShadcnTheme.foreground)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(ShadcnTheme.secondary.opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                        .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                )
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add folders or select files to play")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Divider()
                .overlay(ShadcnTheme.border)
                .padding(.bottom, 12)

            // Scrollable Navigation List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Section 1: LIBRARY
                    VStack(alignment: .leading, spacing: 2) {
                        sectionHeader(title: "LIBRARY")

                        sidebarRow(
                            title: "All Videos",
                            icon: "play.rectangle",
                            badge: "\(library.videos.count)",
                            isSelected: library.selectedCategory == .allVideos
                        ) {
                            library.selectedCategory = .allVideos
                        }

                        let recentCount = library.videos.filter { $0.lastPlayedDate != nil }.count
                        sidebarRow(
                            title: "Recent",
                            icon: "clock",
                            badge: recentCount > 0 ? "\(recentCount)" : nil,
                            isSelected: library.selectedCategory == .recent
                        ) {
                            library.selectedCategory = .recent
                        }

                        let favCount = library.videos.filter { $0.isFavorite }.count
                        sidebarRow(
                            title: "Favorites",
                            icon: "star",
                            badge: favCount > 0 ? "\(favCount)" : nil,
                            isSelected: library.selectedCategory == .favorites
                        ) {
                            library.selectedCategory = .favorites
                        }
                    }

                    // Section 2: FOLDERS
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            sectionHeader(title: "FOLDERS")
                            Spacer()
                            Button {
                                library.selectAndAddFolder()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("Add folder")
                        }
                        .padding(.trailing, 12)

                        if library.folders.isEmpty {
                            Button {
                                library.selectAndAddFolder()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 12))
                                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                                    Text("Add a folder...")
                                        .font(.system(size: 12))
                                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                        .strokeBorder(ShadcnTheme.border.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        } else {
                            ForEach(library.folders) { folder in
                                folderRow(folder: folder)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            Spacer()

            // Footer: Apple Silicon Hardware Badge
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                    .overlay(ShadcnTheme.border)
                    .padding(.bottom, 6)

                let metrics = AppleSiliconMetrics.shared
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: 6, height: 6)

                    Text(metrics.chipName.isEmpty ? "Apple Silicon" : metrics.chipName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int(metrics.displayRefreshRate))Hz")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 210)
        .background(ShadcnTheme.card.opacity(0.95))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(ShadcnTheme.border),
            alignment: .trailing
        )
    }

    // MARK: - Row Components
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(ShadcnTheme.foregroundMuted)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    private func sidebarRow(title: String, icon: String, badge: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                    .lineLimit(1)

                Spacer()

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? ShadcnTheme.accentActive : Color.white.opacity(0.04))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isSelected ? ShadcnTheme.cardHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isSelected ? ShadcnTheme.border : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func folderRow(folder: FolderItem) -> some View {
        let isSelected = library.selectedCategory == .folder(id: folder.id)
        let isHovered = hoveredFolderId == folder.id

        return Button {
            library.selectedCategory = .folder(id: folder.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                    .frame(width: 16)

                Text(folder.name)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                    .lineLimit(1)

                Spacer()

                if isHovered {
                    Button {
                        library.removeFolder(id: folder.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                            .padding(3)
                    }
                    .buttonStyle(.plain)
                    .help("Remove folder from library")
                } else if folder.videoCount > 0 {
                    Text("\(folder.videoCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isSelected ? ShadcnTheme.cardHover : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isSelected ? ShadcnTheme.border : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredFolderId = h ? folder.id : nil
        }
        .contextMenu {
            Button("Rescan Folder") {
                library.scanFolder(folder: folder)
            }
            Divider()
            Button("Remove from Library", role: .destructive) {
                library.removeFolder(id: folder.id)
            }
        }
    }
}
