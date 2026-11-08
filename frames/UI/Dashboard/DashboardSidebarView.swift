import SwiftUI
import AppKit

public struct DashboardSidebarView: View {
    @Bindable var library: LibraryManager
    public var width: CGFloat
    public var onPlayURL: (URL) -> Void
    @State private var hoveredFolderId: UUID? = nil
    @State private var hoveredRow: String? = nil
    @State private var windowManager = WindowManager.shared
    @State private var updateManager = UpdateManager.shared

    public init(library: LibraryManager, width: CGFloat = 210, onPlayURL: @escaping (URL) -> Void) {
        self.library = library
        self.width = width
        self.onPlayURL = onPlayURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                            library.navigate(to: .allVideos)
                        }

                        let recentCount = library.videos.filter { $0.lastPlayedDate != nil }.count
                        sidebarRow(
                            title: "Recent",
                            icon: "clock",
                            badge: recentCount > 0 ? "\(recentCount)" : nil,
                            isSelected: library.selectedCategory == .recent
                        ) {
                            library.navigate(to: .recent)
                        }

                        let favCount = library.videos.filter { $0.isFavorite }.count
                        sidebarRow(
                            title: "Favorites",
                            icon: "star",
                            badge: favCount > 0 ? "\(favCount)" : nil,
                            isSelected: library.selectedCategory == .favorites
                        ) {
                            library.navigate(to: .favorites)
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
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .help("Add folder")
                        }
                        .padding(.trailing, 8)

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
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                        .strokeBorder(ShadcnTheme.border.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .padding(.top, 4)
                        } else {
                            ForEach(library.folders) { folder in
                                folderRow(folder: folder)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }

            Spacer()

            // Settings Button
            VStack(alignment: .leading, spacing: 2) {
                sidebarRow(
                    title: "Settings",
                    icon: "gearshape",
                    isSelected: false
                ) {
                    SettingsManager.shared.openSettings()
                }
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            // Footer: App Version & Apple Silicon Hardware Badge
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                    .overlay(ShadcnTheme.border)
                    .padding(.bottom, 4)

                // App Version & Update Status
                Button {
                    updateManager.checkForUpdates(manual: true)
                } label: {
                    HStack(spacing: 6) {
                        Text("Frames")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.foreground)

                        Text("v\(updateManager.currentVersionString)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(ShadcnTheme.card.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(ShadcnTheme.border.opacity(0.7), lineWidth: 0.5)
                            )

                        Spacer()

                        if updateManager.status == .checking {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.75)
                        } else if updateManager.hasUpdate {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 5, height: 5)
                                Text("New")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.blue)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Frames v\(updateManager.currentVersionString) • Click to check for updates")
                .padding(.bottom, 8)
            }
        }
        .frame(width: width)
        .background(ShadcnTheme.sidebar)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(ShadcnTheme.border),
            alignment: .trailing
        )
        .clipped()
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
                                .fill(isSelected ? ShadcnTheme.accentActive : ShadcnTheme.muted)
                        )
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isSelected ? ShadcnTheme.cardHover : (hoveredRow == title ? ShadcnTheme.card.opacity(0.6) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isSelected ? ShadcnTheme.border : (hoveredRow == title ? ShadcnTheme.borderSubtle : Color.clear), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { h in
            withAnimation(.fluidQuick) {
                hoveredRow = h ? title : nil
            }
        }
        .animation(.fluidQuick, value: isSelected)
        .animation(.fluidQuick, value: hoveredRow == title)
    }

    private func folderRow(folder: FolderItem) -> some View {
        let isSelected = library.selectedCategory == .folder(id: folder.id)
        let isHovered = hoveredFolderId == folder.id

        return HStack(spacing: 9) {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                .frame(width: 16)

            Text(folder.name)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                .lineLimit(1)

            Spacer()

            // Fixed-dimension trailing container: zero layout shift or row resizing on hover
            ZStack(alignment: .trailing) {
                if folder.videoCount > 0 {
                    Text("\(folder.videoCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                        .opacity(isHovered ? 0.0 : 1.0)
                }

                Button {
                    library.removeFolder(id: folder.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Remove folder from library")
                .opacity(isHovered ? 1.0 : 0.0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: 28, height: 22, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                .fill(isSelected ? ShadcnTheme.cardHover : (isHovered ? ShadcnTheme.accentActive : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                .strokeBorder(isSelected ? ShadcnTheme.border : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .pointingHand()
        .onTapGesture {
            library.navigate(to: .folder(id: folder.id))
        }
        .onHover { h in
            withAnimation(.fluidQuick) {
                hoveredFolderId = h ? folder.id : nil
            }
        }
        .animation(.fluidQuick, value: isHovered)
        .animation(.fluidQuick, value: isSelected)
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
