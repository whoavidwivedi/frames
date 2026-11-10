import SwiftUI
import AppKit

public struct DashboardTopBarView: View {
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    @State private var themeManager = ThemeManager.shared
    @State private var windowManager = WindowManager.shared
    @State private var updateManager = UpdateManager.shared

    public init(library: LibraryManager, onPlayURL: @escaping (URL) -> Void) {
        self.library = library
        self.onPlayURL = onPlayURL
    }

    public var body: some View {
        GeometryReader { geo in
            let isQuarter = windowManager.isQuarterScreen
            let isCompact = windowManager.isCompact || isQuarter || geo.size.width < 540
            let isNarrow = isCompact || geo.size.width < 640
            let isUltraNarrow = isCompact || geo.size.width < 500
            let showBadge = !isCompact && geo.size.width >= 660
            let isCompactSort = isCompact || geo.size.width < 580
            let trafficSpacerWidth: CGFloat = windowManager.isNativeFullscreen ? 12 : 78

            HStack(spacing: isNarrow ? 6 : 8) {
                // Standard native macOS traffic lights spacer & double-click area
                Color.clear
                    .frame(width: trafficSpacerWidth, height: 32)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        WindowManager.shared.performTitleBarDoubleClickAction()
                    }

                // MARK: - Navigation & Sidebar Toolbar Controls (Default macOS Buttons)
                HStack(spacing: 4) {
                    // 1. Sidebar Toggle Button (Default macOS Bordered Button)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            library.toggleSidebar()
                        }
                    } label: {
                        Image(systemName: "sidebar.leading")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Toggle Sidebar (⌘B)")

                    // 2. Navigation Controls: Back & Forward (Default macOS Navigation ControlGroup)
                    ControlGroup {
                        Button {
                            library.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!library.canGoBack)
                        .help("Back (⌘[)")

                        Button {
                            library.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!library.canGoForward)
                        .help("Forward (⌘])")
                    }
                    .controlGroupStyle(.navigation)
                    .controlSize(.regular)

                    // 3. Search & Command Menu (⌘K, ⌘F) Button (Default macOS Bordered Button)
                    Button {
                        CommandPaletteManager.shared.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Search Videos & Commands (⌘K, ⌘F)")
                }

                // Vertical hairline separator between toolbar buttons and app title
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.35))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 2)

                // MARK: - App Wordmark / Breadcrumb (hide in ultra-narrow when search is active)
                if !isUltraNarrow || (!library.isSearchActive && library.searchQuery.isEmpty) {
                    HStack(spacing: 5) {
                        Text("frames")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary)

                        if !isNarrow && library.selectedCategory != .allVideos {
                            Text("/")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary.opacity(0.6))

                            Text(library.selectedCategoryTitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                // MARK: - macOS Standard Search Field
                if library.isSearchActive || !library.searchQuery.isEmpty {
                    let searchWidth: CGFloat = isUltraNarrow ? 110 : (isNarrow ? 135 : 180)
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)

                        TextField("Search videos...", text: $library.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary)
                            .frame(width: searchWidth)

                        if !library.searchQuery.isEmpty {
                            Button {
                                withAnimation(.fluidQuick) {
                                    library.searchQuery = ""
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.borderless)
                            .pointingHand()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                            )
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading)),
                            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading))
                        )
                    )
                }

                // MARK: - Central Draggable Spacer & Title Bar Double-Click Area
                Spacer(minLength: 4)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        WindowManager.shared.performTitleBarDoubleClickAction()
                    }

                // MARK: - Trailing Controls (Count, Sort, View Mode, Theme)
                HStack(spacing: isNarrow ? 6 : 8) {
                    if library.selectedCategory != .settings {
                        // Video Count Badge (visible when sufficient room)
                        if showBadge {
                            Text("\(library.filteredVideos.count) \(library.filteredVideos.count == 1 ? "video" : "videos")")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                                .padding(.trailing, 2)
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }

                        // Dedicated Sort Pop-up Menu (Default macOS Bordered Menu Button)
                        Menu {
                            Picker("Sort By", selection: $library.sortOption) {
                                ForEach(SortOption.allCases) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 11, weight: .medium))
                                if !isCompactSort {
                                    Text(library.sortOption.rawValue)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Sort videos: \(library.sortOption.rawValue)")

                        // View Mode Switcher: Grid vs List (Default macOS Segmented Picker)
                        Picker("", selection: $library.viewMode) {
                            Image(systemName: "square.grid.2x2")
                                .tag(ViewMode.grid)
                                .help("Switch to Grid View")
                            Image(systemName: "list.bullet")
                                .tag(ViewMode.list)
                                .help("Switch to List View")
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.regular)
                        .labelsHidden()
                        .frame(width: 64)
                    }

                    // OTA Update Available Button (Default macOS Bordered Button)
                    if updateManager.hasUpdate {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                updateManager.presentUpdatePrompt()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)

                                if !isNarrow {
                                    Text("Update")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Update Available: \(updateManager.availableUpdate?.tagName ?? "")")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    // Theme Toggle Button (Default macOS Bordered Button)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            themeManager.toggleTheme()
                        }
                    } label: {
                        Image(systemName: "circle.righthalf.filled")
                            .font(.system(size: 12, weight: .regular))
                            .rotationEffect(.degrees(themeManager.isDark ? 180 : 0))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .animation(.snappy(duration: 0.2), value: themeManager.isDark)
                    .help(themeManager.isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
                }
                .padding(.trailing, isNarrow ? 10 : 16)
            }
            .frame(width: geo.size.width, height: 32)
            .background(
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    TitleBarDragArea()
                }
            )
            .animation(.snappy(duration: 0.2), value: library.isSearchActive)
            .animation(.snappy(duration: 0.2), value: library.viewMode)
        }
        .frame(height: 32)
        .macOSDefaultTitleBar()
    }
}
