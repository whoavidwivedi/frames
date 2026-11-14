import SwiftUI
import AppKit

// MARK: - Tactile Button Styles for Sidebar Controls
public struct SidebarRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .animation(.fluidQuick, value: configuration.isPressed)
    }
}

public struct TactileIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1.0)
            .animation(.fluidQuick, value: configuration.isPressed)
    }
}

public struct DashboardSidebarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var library: LibraryManager
    public var width: CGFloat
    public var onPlayURL: (URL) -> Void
    @State private var hoveredFolderId: UUID? = nil
    @State private var hoveredRow: String? = nil
    @State private var isHoveringVersion: Bool = false
    @State private var windowManager = WindowManager.shared
    @State private var updateManager = UpdateManager.shared
    @Namespace private var sidebarNamespace

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
                            withAnimation(.fluidQuick) {
                                library.navigate(to: .allVideos)
                            }
                        }

                        let recentCount = library.videos.filter { $0.lastPlayedDate != nil }.count
                        sidebarRow(
                            title: "Recent",
                            icon: "clock",
                            badge: recentCount > 0 ? "\(recentCount)" : nil,
                            isSelected: library.selectedCategory == .recent
                        ) {
                            withAnimation(.fluidQuick) {
                                library.navigate(to: .recent)
                            }
                        }

                        let favCount = library.videos.filter { $0.isFavorite }.count
                        sidebarRow(
                            title: "Favorites",
                            icon: "star",
                            badge: favCount > 0 ? "\(favCount)" : nil,
                            isSelected: library.selectedCategory == .favorites
                        ) {
                            withAnimation(.fluidQuick) {
                                library.navigate(to: .favorites)
                            }
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
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(TactileIconButtonStyle())
                            .pointingHand()
                            .help("Add folder")
                        }
                        .padding(.trailing, 6)

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
                            .buttonStyle(SidebarRowButtonStyle())
                            .pointingHand()
                            .padding(.top, 4)
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
            .animation(.fluidQuick, value: library.selectedCategory)

            Spacer()

            // Settings Button
            VStack(alignment: .leading, spacing: 2) {
                sidebarRow(
                    title: "Settings",
                    icon: "gearshape",
                    isSelected: library.selectedCategory == .settings
                ) {
                    withAnimation(.fluidQuick) {
                        library.navigate(to: .settings)
                    }
                }
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            // Footer: shadcn badge showing latest version / update availability
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                    .overlay(ShadcnTheme.border)
                    .padding(.bottom, 4)

                Button {
                    if updateManager.hasUpdate {
                        withAnimation(.fluidQuick) {
                            updateManager.presentUpdatePrompt()
                        }
                    } else {
                        updateManager.checkForUpdates(manual: true)
                    }
                } label: {
                    HStack {
                        ShadcnBadge(
                            updateStatusText,
                            icon: updateBadgeIcon,
                            variant: updateBadgeVariant,
                            isLoading: updateBadgeLoading,
                            isHighlighted: isHoveringVersion
                        )

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SidebarRowButtonStyle())
                .pointingHand()
                .help("Frames v\(updateManager.currentVersionString) • \(updateStatusText) • Click to check for updates")
                .accessibilityLabel("Frames version \(updateManager.currentVersionString). \(updateStatusText)")
                .onHover { hovering in
                    withAnimation(.fluidQuick) {
                        isHoveringVersion = hovering
                    }
                }

                if case .downloading = updateManager.status {
                    ProgressView(value: updateManager.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(Color.blue)
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
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

    // MARK: - Update Status (Sidebar Footer)

    public static func updateStatusText(for status: UpdateStatus) -> String {
        switch status {
        case .idle:
            return "Check for updates"
        case .checking:
            return "Checking for updates…"
        case .upToDate(let checkedVersion):
            return "Latest · v\(checkedVersion)"
        case .available(let info):
            return "\(info.tagName) available"
        case .downloading:
            return "Downloading update…"
        case .extracting:
            return "Preparing update…"
        case .readyToRestart:
            return "Restart to update"
        case .error:
            return "Check failed — retry"
        }
    }

    private var updateStatusText: String {
        Self.updateStatusText(for: updateManager.status)
    }

    private var updateBadgeVariant: ShadcnBadgeVariant {
        switch updateManager.status {
        case .available, .readyToRestart:
            return .default
        case .error:
            return .destructive
        case .idle, .checking, .upToDate, .downloading, .extracting:
            return .secondary
        }
    }

    private var updateBadgeIcon: String? {
        switch updateManager.status {
        case .idle:
            return "arrow.clockwise"
        case .upToDate:
            return "checkmark"
        case .available:
            return "arrow.down.circle.fill"
        case .readyToRestart:
            return "restart"
        case .error:
            return "exclamationmark.triangle.fill"
        case .checking, .downloading, .extracting:
            return nil
        }
    }

    private var updateBadgeLoading: Bool {
        switch updateManager.status {
        case .checking, .downloading, .extracting:
            return true
        default:
            return false
        }
    }

    // MARK: - Row Components (Shadcn Sidebar Design System)
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
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected ? ShadcnTheme.foreground : (title == "Favorites" ? Color.yellow : ShadcnTheme.foregroundSecondary)
                    )
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                    .lineLimit(1)

                Spacer()

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(isSelected ? ShadcnTheme.card : ShadcnTheme.muted)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? ShadcnTheme.border : Color.clear, lineWidth: 0.5)
                        )
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.cardHover)
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "activeSidebarPill", in: sidebarNamespace)
                } else if hoveredRow == title {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.card.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
        }
        .buttonStyle(SidebarRowButtonStyle())
        .pointingHand()
        .onHover { h in
            withAnimation(.fluidQuick) {
                hoveredRow = h ? title : nil
            }
        }
    }

    private func folderRow(folder: FolderItem) -> some View {
        let isSelected = library.selectedCategory == .folder(id: folder.id)
        let isHovered = hoveredFolderId == folder.id

        return Button {
            withAnimation(.fluidQuick) {
                library.navigate(to: .folder(id: folder.id))
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                    .frame(width: 18)

                Text(folder.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
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
                        withAnimation(.fluidQuick) {
                            library.removeFolder(id: folder.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(TactileIconButtonStyle())
                    .pointingHand()
                    .help("Remove folder from library")
                    .opacity(isHovered ? 1.0 : 0.0)
                    .allowsHitTesting(isHovered)
                }
                .frame(width: 24, height: 20, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.cardHover)
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "activeSidebarPill", in: sidebarNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.accentActive)
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
        }
        .buttonStyle(SidebarRowButtonStyle())
        .pointingHand()
        .onHover { h in
            withAnimation(.fluidQuick) {
                hoveredFolderId = h ? folder.id : nil
            }
        }
        .contextMenu {
            Button("Rescan Folder") {
                library.scanFolder(folder: folder)
            }
            .pointingHand()
            Divider()
            Button("Remove from Library", role: .destructive) {
                library.removeFolder(id: folder.id)
            }
            .pointingHand()
        }
    }
}
