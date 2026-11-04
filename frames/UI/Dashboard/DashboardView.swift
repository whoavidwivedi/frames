import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct DashboardView: View {
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    @State private var windowManager = WindowManager.shared
    @State private var isTargetedForDrop: Bool = false

    public init(library: LibraryManager, onPlayURL: @escaping (URL) -> Void) {
        self.library = library
        self.onPlayURL = onPlayURL
    }

    public var body: some View {
        GeometryReader { geo in
            let isQuarter = windowManager.isQuarterScreen
            let isCompact = windowManager.isCompact || isQuarter || geo.size.width < 560
            let sidebarWidth: CGFloat = isCompact ? 160 : (geo.size.width < 720 ? 180 : 210)
            VStack(spacing: 0) {
                // Unified Top Navigation Bar (Antigravity Style: Traffic Lights + Sidebar Toggle + Back + Forward + Search + Divider + Title + Actions)
                DashboardTopBarView(library: library, onPlayURL: onPlayURL)

                Divider()
                    .overlay(ShadcnTheme.border)

                // Content Area: Collapsible Sidebar + Main Content Canvas
                HStack(spacing: 0) {
                    if library.isSidebarVisible {
                        DashboardSidebarView(library: library, width: sidebarWidth, onPlayURL: onPlayURL)
                            .transition(.move(edge: .leading).combined(with: .opacity))

                        Divider()
                            .overlay(ShadcnTheme.border)
                            .transition(.opacity)
                    }

                    DashboardContentView(library: library, onPlayURL: onPlayURL)
                }
            }
            .animation(.fluidSpring, value: library.isSidebarVisible)
            .animation(.fluidWindow, value: windowManager.currentLayoutState)
        }
        .frame(minWidth: 460, minHeight: 320)
        .overlay(
            // Visual feedback when dragging files/folders over dashboard
            Group {
                if isTargetedForDrop {
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg)
                        .strokeBorder(ShadcnTheme.primary, style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                        .background(ShadcnTheme.card.opacity(0.9))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(ShadcnTheme.primary)
                                Text("Drop video files or folders to add to Frames")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(ShadcnTheme.foreground)
                            }
                        )
                }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                            library.addFolder(url: url)
                        } else {
                            library.addSingleVideoFile(url: url)
                            onPlayURL(url)
                        }
                    }
                }
            }
            return true
        }
    }
}
