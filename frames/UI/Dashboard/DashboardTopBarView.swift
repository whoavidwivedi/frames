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
            let trafficSpacerWidth: CGFloat = isUltraNarrow ? 66 : (isNarrow ? 70 : 76)

            HStack(spacing: isNarrow ? 6 : 8) {
                // Standard macOS traffic lights spacer
                Color.clear
                    .frame(width: trafficSpacerWidth, height: 1)

                // MARK: - Navigation & Sidebar Toolbar Controls (Antigravity Style)
                HStack(spacing: 4) {
                    // 1. Sidebar Toggle Button
                    Button {
                        library.toggleSidebar()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(hoveredButton == .sidebar ? ShadcnTheme.cardHover : (library.isSidebarVisible ? ShadcnTheme.accentActive : Color.black.opacity(0.0001)))

                            Image(systemName: "sidebar.leading")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(library.isSidebarVisible ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .pointingHand()
                    .help("Toggle Sidebar (⌘B)")
                    .onHover { h in
                        withAnimation(.fluidQuick) {
                            hoveredButton = h ? .sidebar : nil
                        }
                    }

                    // 2. Back Arrow Button
                    Button {
                        library.goBack()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(hoveredButton == .back && library.canGoBack ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                            Image(systemName: "arrow.left")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(library.canGoBack ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted.opacity(0.35))
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!library.canGoBack)
                    .contentShape(Rectangle())
                    .pointingHand()
                    .help("Back (⌘[)")
                    .onHover { h in
                        withAnimation(.fluidQuick) {
                            hoveredButton = h ? .back : nil
                        }
                    }

                    // 3. Forward Arrow Button (hide when disabled in ultra-narrow)
                    if !isUltraNarrow || library.canGoForward {
                        Button {
                            library.goForward()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(hoveredButton == .forward && library.canGoForward ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(library.canGoForward ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted.opacity(0.35))
                            }
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!library.canGoForward)
                        .contentShape(Rectangle())
                        .pointingHand()
                        .help("Forward (⌘])")
                        .onHover { h in
                            withAnimation(.fluidQuick) {
                                hoveredButton = h ? .forward : nil
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    // 4. Search & Command Menu (⌘K, ⌘F)
                    Button {
                        CommandPaletteManager.shared.toggle()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(hoveredButton == .search ? ShadcnTheme.cardHover : (CommandPaletteManager.shared.isPresented ? ShadcnTheme.accentActive : Color.black.opacity(0.0001)))

                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(hoveredButton == .search || CommandPaletteManager.shared.isPresented ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .pointingHand()
                    .help("Search Videos & Commands (⌘K, ⌘F)")
                    .onHover { h in
                        withAnimation(.fluidQuick) {
                            hoveredButton = h ? .search : nil
                        }
                    }
                }

                // Vertical hairline separator between toolbar buttons and app title
                Rectangle()
                    .fill(ShadcnTheme.border)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 3)

                // MARK: - App Wordmark / Breadcrumb (hide in ultra-narrow when search is active)
                if !isUltraNarrow || (!library.isSearchActive && library.searchQuery.isEmpty) {
                    HStack(spacing: 5) {
                        Text("frames")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.foreground)

                        if !isNarrow && library.selectedCategory != .allVideos {
                            Text("/")
                                .font(.system(size: 12))
                                .foregroundStyle(ShadcnTheme.foregroundMuted)

                            Text(library.selectedCategoryTitle)
                                .font(.system(size: 12, weight: .medium))
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
                    HStack(spacing: 5) {
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
                                ZStack {
                                    Color.black.opacity(0.0001)
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                                }
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .pointingHand()
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                            .fill(ShadcnTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
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

                Spacer(minLength: 4)

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
                            withAnimation(.fluidSpring) {
                                library.cycleSortOption()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: isCompactSort ? 11 : 10))
                                if !isCompactSort {
                                    Text(library.sortOption.rawValue)
                                        .font(.system(size: 11, weight: .medium))
                                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }
                            }
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .padding(.horizontal, isCompactSort ? 7 : 8)
                            .padding(.vertical, 5)
                            .frame(minHeight: 28)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(ShadcnTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .pointingHand()
                        .contextMenu {
                            ForEach(SortOption.allCases) { opt in
                                Button {
                                    withAnimation(.fluidSpring) {
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

                        // 1-Click View Mode Toggle Button (Grid <-> List)
                        Button {
                            withAnimation(.fluidSpring) {
                                library.toggleViewMode()
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(ShadcnTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                    )

                                Image(systemName: library.viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            }
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .pointingHand()
                        .animation(.fluidSpring, value: library.viewMode)
                        .help(library.viewMode == .grid ? "Switch to List View" : "Switch to Grid View")
                    }

                    // OTA Update Available Pill Button
                    if updateManager.hasUpdate {
                        Button {
                            withAnimation(.fluidSpring) {
                                updateManager.presentUpdatePrompt()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(red: 249/255.0, green: 115/255.0, blue: 22/255.0))
                                    .frame(width: 6, height: 6)

                                if !isNarrow {
                                    Text("Update Available")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(ShadcnTheme.foreground)
                                }
                            }
                            .padding(.horizontal, isNarrow ? 6 : 8)
                            .padding(.vertical, 5)
                            .frame(minHeight: 28)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(ShadcnTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
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

                    // 1-Click Theme Toggle Button (Apple Native System Appearance Icon)
                    Button {
                        withAnimation(.fluidSmooth) {
                            themeManager.toggleTheme()
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(ShadcnTheme.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                        .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                )

                            Image(systemName: "circle.righthalf.filled")
                                .font(.system(size: 12))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .rotationEffect(.degrees(themeManager.isDark ? 180 : 0))
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .pointingHand()
                    .animation(.fluidSpring, value: themeManager.isDark)
                    .help(themeManager.isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
                }
                .padding(.trailing, isNarrow ? 10 : 16)
            }
            .frame(width: geo.size.width, height: 38)
            .background(ShadcnTheme.background)
            .animation(.fluidSpring, value: library.isSearchActive)
            .animation(.fluidSpring, value: library.viewMode)
        }
        .frame(height: 38)
        .macOSDefaultTitleBar()
    }
}
