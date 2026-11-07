import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct TopBarOverlay: View {
    @Bindable var engine: VideoPlayerEngine
    public var onReturnToDashboard: (() -> Void)?
    @State private var windowManager = WindowManager.shared

    public init(engine: VideoPlayerEngine, onReturnToDashboard: (() -> Void)? = nil) {
        self.engine = engine
        self.onReturnToDashboard = onReturnToDashboard
    }

    public var body: some View {
        let isFs = windowManager.isAnyFullscreen
        let isNarrow = windowManager.isCompact || windowManager.isQuarterScreen
        let trafficLightSpacer: CGFloat = isFs ? 14 : (isNarrow ? 66 : 74)

        HStack(spacing: isNarrow ? 8 : 12) {
            // macOS traffic lights spacer in windowed mode
            Color.clear
                .frame(width: trafficLightSpacer, height: 1)

            // Left Section: Return to Dashboard + Video Title & Badges
            HStack(spacing: 8) {
                // Return to Dashboard Button
                Button {
                    if let onReturn = onReturnToDashboard {
                        onReturn()
                    } else {
                        engine.unloadMedia()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        if !isNarrow {
                            Text("Dashboard")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, isNarrow ? 8 : 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Back to Dashboard (Esc or ⌘[)")

                // Subtle Vertical Divider
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 1, height: 16)

                // Video Title & Format Badges
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.metadata.title.isEmpty ? "Video Playback" : engine.metadata.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 5) {
                        if !engine.metadata.container.isEmpty {
                            formatBadge(engine.metadata.container)
                        }
                        if let res = engine.metadata.resolutionDescription.components(separatedBy: " ").first, !res.isEmpty {
                            formatBadge(res)
                        }
                        if engine.metadata.isHDR {
                            formatBadge("HDR")
                        }
                        if !engine.metadata.codec.isEmpty {
                            let shortCodec = engine.metadata.codec.components(separatedBy: " ").first ?? engine.metadata.codec
                            formatBadge(shortCodec)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 8)

            // Right Section: Quick Action Controls (Star, Search, Open, Close)
            HStack(spacing: 4) {
                if let url = engine.currentURL {
                    let isFav = LibraryManager.shared.isFavorite(url: url)
                    Button {
                        withAnimation(.fluidSpring) {
                            LibraryManager.shared.toggleFavorite(url: url)
                        }
                    } label: {
                        Image(systemName: isFav ? "star.fill" : "star")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isFav ? Color(red: 1.0, green: 0.82, blue: 0.1) : Color.white.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isFav ? Color(red: 1.0, green: 0.82, blue: 0.1).opacity(0.20) : Color.white.opacity(0.10))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help(isFav ? "Remove from Favorites" : "Add to Favorites")
                }

                dockedTopButton(icon: "cpu", help: "Playback & Hardware Statistics (I)") {
                    withAnimation(.fluidSpring) {
                        engine.activeInspectorSheet = (engine.activeInspectorSheet == .stats ? nil : .stats)
                    }
                }

                dockedTopButton(icon: "magnifyingglass", help: "Search & Commands (⌘K, ⌘F)") {
                    CommandPaletteManager.shared.toggle()
                }

                dockedTopButton(icon: "folder", help: "Open media file (⌘O)") {
                    openNewFile()
                }

                dockedTopButton(icon: "xmark", help: "Back to Dashboard (Esc)") {
                    if let onReturn = onReturnToDashboard {
                        onReturn()
                    } else {
                        engine.unloadMedia()
                    }
                }
            }
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                Rectangle()
                    .fill(Color(white: 0.08, opacity: 0.85))
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
        }
        .macOSDefaultTitleBar()
        .environment(\.colorScheme, .dark)
    }

    private func formatBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
    }

    private func dockedTopButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help(help)
    }

    private func openNewFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = MediaSupport.contentTypes
        panel.message = "Choose a video or audio file to open in Frames"

        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(name: .openVideoNotification, object: url)
        }
    }
}
