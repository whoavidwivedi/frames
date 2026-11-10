import SwiftUI
import AppKit

public struct DashboardTopBarView: View {
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    @State private var hoveredButton: HoveredButton? = nil
    @State private var themeManager = ThemeManager.shared
    @State private var windowManager = WindowManager.shared
    @State private var updateManager = UpdateManager.shared

    private enum HoveredButton {
        case sidebar
        case back
        case forward
        case search
        case sort
        case viewMode
        case theme
    }

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
            // Keep stable 78pt margin in both windowed and fullscreen so controls don't jump to the left
            let trafficSpacerWidth: CGFloat = 78

            HStack(spacing: isNarrow ? 6 : 8) {
                // Standard native macOS traffic lights spacer & double-click area
                Color.clear
                    .frame(width: trafficSpacerWidth, height: 32)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        WindowManager.shared.performTitleBarDoubleClickAction()
                    }

                // MARK: - Navigation & Sidebar Toolbar Controls (Sleek Icon Style)
                HStack(spacing: 4) {
                    // 1. Sidebar Toggle Icon
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            library.toggleSidebar()
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(hoveredButton == .sidebar ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                            Image(systemName: "sidebar.leading")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(library.isSidebarVisible ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help("Toggle Sidebar (⌘B)")
                    .onHover { h in
                        hoveredButton = h ? .sidebar : nil
                    }

                    // 2. Back Arrow Icon
                    Button {
                        library.goBack()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(hoveredButton == .back && library.canGoBack ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(library.canGoBack ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted.opacity(0.35))
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .disabled(!library.canGoBack)
                    .help("Back (⌘[)")
                    .onHover { h in
                        hoveredButton = h ? .back : nil
                    }

                    // 3. Forward Arrow Icon (hide when disabled in ultra-narrow)
                    if !isUltraNarrow || library.canGoForward {
                        Button {
                            library.goForward()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(hoveredButton == .forward && library.canGoForward ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(library.canGoForward ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted.opacity(0.35))
                            }
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .disabled(!library.canGoForward)
                        .help("Forward (⌘])")
                        .onHover { h in
                            hoveredButton = h ? .forward : nil
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    // 4. Search & Command Menu (⌘K, ⌘F) Icon
                    Button {
                        CommandPaletteManager.shared.toggle()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(hoveredButton == .search || CommandPaletteManager.shared.isPresented ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(hoveredButton == .search || CommandPaletteManager.shared.isPresented ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help("Search Videos & Commands (⌘K, ⌘F)")
                    .onHover { h in
                        hoveredButton = h ? .search : nil
                    }
                }

                // Vertical hairline separator between toolbar buttons and app title
                Rectangle()
                    .fill(ShadcnTheme.border)
                    .frame(width: 1, height: 12)
                    .padding(.horizontal, 2)

                // MARK: - App Wordmark / Breadcrumb (hide in ultra-narrow when search is active)
                if !isUltraNarrow || (!library.isSearchActive && library.searchQuery.isEmpty) {
                    HStack(spacing: 5) {
                        Text("frames")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.foreground)

                        if !isNarrow && library.selectedCategory != .allVideos {
                            Text("/")
                                .font(.system(size: 11))
                                .foregroundStyle(ShadcnTheme.foregroundMuted)

                            Text(library.selectedCategoryTitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                // MARK: - Expandable Search Field
                if library.isSearchActive || !library.searchQuery.isEmpty {
                    let searchWidth: CGFloat = isUltraNarrow ? 95 : (isNarrow ? 120 : 160)
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)

                        TextField("Search...", text: $library.searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foreground)
                            .frame(width: searchWidth)

                        if !library.searchQuery.isEmpty {
                            Button {
                                withAnimation(.fluidQuick) {
                                    library.searchQuery = ""
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .frame(height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(ShadcnTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(ShadcnTheme.borderActive, lineWidth: 1)
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
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ShadcnTheme.foregroundMuted)
                                .padding(.trailing, 2)
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }

                        // Dedicated Sort Button (Click to cycle, right-click for direct choice)
                        Button {
                            withAnimation(.snappy(duration: 0.15)) {
                                library.cycleSortOption()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 10, weight: .medium))
                                if !isCompactSort {
                                    Text(library.sortOption.rawValue)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                            }
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .frame(width: isCompactSort ? 28 : 92, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(hoveredButton == .sort ? ShadcnTheme.cardHover : ShadcnTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .contextMenu {
                            ForEach(SortOption.allCases) { opt in
                                Button {
                                    withAnimation(.snappy(duration: 0.15)) {
                                        library.sortOption = opt
                                    }
                                } label: {
                                    HStack {
                                        Text(opt.rawValue)
                                        if library.sortOption == opt {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        .help("Sort: \(library.sortOption.rawValue) (Click to cycle)")
                        .onHover { h in
                            hoveredButton = h ? .sort : nil
                        }

                        // 1-Click View Mode Toggle Button (Grid <-> List) - Icon-Only
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                library.toggleViewMode()
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(hoveredButton == .viewMode ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                                Image(systemName: library.viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            }
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .animation(.snappy(duration: 0.18), value: library.viewMode)
                        .help(library.viewMode == .grid ? "Switch to List View" : "Switch to Grid View")
                        .onHover { h in
                            hoveredButton = h ? .viewMode : nil
                        }
                    }

                    // OTA Update Available Pill Button
                    if updateManager.hasUpdate {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                updateManager.presentUpdatePrompt()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(red: 249/255.0, green: 115/255.0, blue: 22/255.0))
                                    .frame(width: 5, height: 5)

                                if !isNarrow {
                                    Text("Update")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(ShadcnTheme.foreground)
                                }
                            }
                            .padding(.horizontal, isNarrow ? 5 : 7)
                            .padding(.vertical, 2)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(ShadcnTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(Color(red: 249/255.0, green: 115/255.0, blue: 22/255.0).opacity(0.4), lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .help("Update Available: \(updateManager.availableUpdate?.tagName ?? "")")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    // 1-Click Theme Toggle Button - Icon-Only
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            themeManager.toggleTheme()
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(hoveredButton == .theme ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                            Image(systemName: "circle.righthalf.filled")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .rotationEffect(.degrees(themeManager.isDark ? 180 : 0))
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .animation(.snappy(duration: 0.2), value: themeManager.isDark)
                    .help(themeManager.isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
                    .onHover { h in
                        hoveredButton = h ? .theme : nil
                    }
                }
                .padding(.trailing, isNarrow ? 10 : 16)
            }
            .frame(width: geo.size.width, height: 32)
            .background(
                ZStack {
                    ShadcnTheme.background
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
