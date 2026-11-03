import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct TopBarOverlay: View {
    @Bindable var engine: VideoPlayerEngine
    public var onReturnToDashboard: (() -> Void)?

    public init(engine: VideoPlayerEngine, onReturnToDashboard: (() -> Void)? = nil) {
        self.engine = engine
        self.onReturnToDashboard = onReturnToDashboard
    }

    public var body: some View {
        HStack(spacing: 10) {
            // macOS traffic lights spacer
            Spacer()
                .frame(width: 72)

            // Return to Dashboard button
            if let onReturn = onReturnToDashboard {
                Button(action: onReturn) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 11, weight: .medium))
                        Text("Dashboard")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(ShadcnTheme.foreground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .fill(ShadcnTheme.card.opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Return to Dashboard (Esc)")
            }

            // Video Title & Format
            HStack(spacing: 6) {
                Text(engine.metadata.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ShadcnTheme.foreground)
                    .lineLimit(1)

                if !engine.metadata.container.isEmpty {
                    Text(engine.metadata.container)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                }

                if engine.metadata.isHDR {
                    Text("HDR")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foreground)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                    .fill(ShadcnTheme.card.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
            )

            Spacer()

            // Actions
            HStack(spacing: 4) {
                ShadcnButton(icon: "folder", variant: .ghost, size: .iconSm) {
                    openNewFile()
                }

                ShadcnButton(icon: "xmark", variant: .ghost, size: .iconSm) {
                    engine.pause()
                    engine.loadMedia(from: URL(fileURLWithPath: ""))
                    onReturnToDashboard?()
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                    .fill(ShadcnTheme.card.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
            )
            .padding(.trailing, 16)
        }
        .padding(.top, 12)
    }

    private func openNewFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        panel.message = "Choose a video to play"

        if panel.runModal() == .OK, let url = panel.url {
            engine.loadMedia(from: url)
        }
    }
}
