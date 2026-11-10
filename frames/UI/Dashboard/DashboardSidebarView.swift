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
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .help("Add folder")
                        }
                        .padding(.trailing, 6)

                        if library.folders.isEmpty {
                            Button {
                                library.selectAndAddFolder()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.secondary)
                                    Text("Add Folder...")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .padding(.top, 2)
                        } else {
                            ForEach(library.folders) { folder in
                                folderRow(folder: folder)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
            }

            Spacer()

            // Settings Button
            VStack(alignment: .leading, spacing: 2) {
                sidebarRow(
                    title: "Settings",
                    icon: "gearshape",
                    isSelected: library.selectedCategory == .settings
                ) {
                    library.navigate(to: .settings)
                }
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            // Footer: App Version & Check for Updates
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.35))
                    .padding(.bottom, 4)

                // App Version & Update Status
                Button {
                    updateManager.checkForUpdates(manual: true)
                } label: {
                    HStack(spacing: 6) {
                        Text("Frames")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.primary)

                        Text("v\(updateManager.currentVersionString)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)

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
                    .padding(.horizontal, 12)
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
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color(nsColor: .separatorColor).opacity(0.35)),
            alignment: .trailing
        )
        .clipped()
    }

    // MARK: - Row Components (Default macOS Sidebar Style)
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func sidebarRow(title: String, icon: String, badge: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected ? Color.white : (title == "Favorites" ? Color.yellow : Color.secondary)
                    )
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)

                Spacer()

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (hoveredRow == title ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "folder.fill" : "folder")
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: 18)

            Text(folder.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)

            Spacer()

            // Fixed-dimension trailing container: zero layout shift or row resizing on hover
            ZStack(alignment: .trailing) {
                if folder.videoCount > 0 {
                    Text("\(folder.videoCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .opacity(isHovered ? 0.0 : 1.0)
                }

                Button {
                    library.removeFolder(id: folder.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Remove folder from library")
                .opacity(isHovered ? 1.0 : 0.0)
                .allowsHitTesting(isHovered)
            }
            .frame(width: 24, height: 20, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
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
