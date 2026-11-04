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
        GeometryReader { geo in
            let isNarrow = windowManager.isCompact || windowManager.isQuarterScreen || geo.size.width < 540
            let spacerWidth: CGFloat = isNarrow ? 66 : 72

            HStack(spacing: isNarrow ? 6 : 10) {
                // macOS traffic lights spacer
                Color.clear
                    .frame(width: spacerWidth, height: 1)

                HStack(spacing: 8) {
                    Button(action: {
                        if let onReturn = onReturnToDashboard {
                            onReturn()
                        } else {
                            engine.unloadMedia()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            if !isNarrow {
                                Text("Dashboard")
                                    .font(.system(size: 12, weight: .medium))
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                        .foregroundStyle(ShadcnTheme.foreground)
                        .padding(.horizontal, isNarrow ? 7 : 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radius4xl, style: .continuous)
                                .fill(ShadcnTheme.secondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radius4xl, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .help("Back to Dashboard (Esc or ⌘[)")

                    Rectangle()
                        .fill(ShadcnTheme.border)
                        .frame(width: 1, height: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.metadata.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.foreground)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 5) {
                            if !engine.metadata.container.isEmpty {
                                Text(engine.metadata.container)
                            }
                            if engine.metadata.isHDR {
                                Text("HDR")
                            }
                        }
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(chromeBackground)

                Spacer(minLength: 4)

                // Actions (Favorite star, Open folder, Close/Back)
                HStack(spacing: 4) {
                    if let url = engine.currentURL {
                        let isFav = LibraryManager.shared.isFavorite(url: url)
                        Button {
                            withAnimation(.fluidSpring) {
                                LibraryManager.shared.toggleFavorite(url: url)
                            }
                        } label: {
                            Image(systemName: isFav ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundStyle(isFav ? Color(red: 1.0, green: 0.8, blue: 0.0) : ShadcnTheme.foregroundSecondary)
                                .frame(width: 26, height: 26)
                                .scaleEffect(isFav ? 1.08 : 0.95)
                                .background(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                        .fill(isFav ? Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.15) : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .animation(.fluidSpring, value: isFav)
                        .help(isFav ? "Remove from Favorites" : "Add to Favorites")
                    }

                    ShadcnButton(icon: "folder", variant: .ghost, size: .iconSm, accessibilityLabel: "Open media") {
                        openNewFile()
                    }

                    ShadcnButton(icon: "xmark", variant: .ghost, size: .iconSm, accessibilityLabel: "Back to Dashboard") {
                        if let onReturn = onReturnToDashboard {
                            onReturn()
                        } else {
                            engine.unloadMedia()
                        }
                    }
                }
                .padding(5)
                .background(chromeBackground)
                .padding(.trailing, isNarrow ? 10 : 16)
            }
            .padding(.top, 12)
            .frame(width: geo.size.width)
            .animation(.fluidSpring, value: isNarrow)
            .animation(.fluidSpring, value: spacerWidth)
            .animation(.fluidWindow, value: windowManager.currentLayoutState)
        }
        .frame(height: 52)
        .macOSDefaultTitleBar()
    }

    private var chromeBackground: some View {
        RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .fill(ShadcnTheme.card.opacity(0.70))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
            )
            .shadow(
                color: Color(nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(white: 0, alpha: 0.30)
                        : NSColor(white: 0, alpha: 0.08)
                }),
                radius: 10,
                y: 4
            )
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
