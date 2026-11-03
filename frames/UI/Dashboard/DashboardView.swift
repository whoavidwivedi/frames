import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct DashboardView: View {
    @Bindable var library: LibraryManager
    public var onPlayURL: (URL) -> Void
    @State private var isTargetedForDrop: Bool = false

    public init(library: LibraryManager, onPlayURL: @escaping (URL) -> Void) {
        self.library = library
        self.onPlayURL = onPlayURL
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar with Plus button and folder navigation
            DashboardSidebarView(library: library, onPlayURL: onPlayURL)

            // Main Dashboard Canvas
            DashboardContentView(library: library, onPlayURL: onPlayURL)
        }
        .frame(minWidth: 850, minHeight: 520)
        .overlay(
            // Visual feedback when dragging files/folders over dashboard
            Group {
                if isTargetedForDrop {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                        .background(Color.black.opacity(0.3))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.white)
                                Text("Drop video files or folders to add to Frames")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.white)
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
