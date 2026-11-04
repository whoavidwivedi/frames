import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct DropZoneView: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var isTargeted: Bool = false

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        ZStack {
            // Dark Neutral Background (oklch 0.145 0 0 / #09090b)
            ShadcnTheme.background
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // Dashed Drag & Drop Box (shadcn / Linear aesthetic)
                VStack(spacing: 16) {
                    // Minimal Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .fill(ShadcnTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                            )
                            .frame(width: 40, height: 40)

                        Image(systemName: "film")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    }

                    // Clean Typography
                    VStack(spacing: 4) {
                        Text("Frames")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.foreground)

                        Text("Drag and drop video files to play")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                    }

                    // Action Buttons (shadcn button variants)
                    HStack(spacing: 8) {
                        ShadcnButton(
                            "Choose File",
                            icon: "arrow.up.doc",
                            shortcut: "⌘O",
                            variant: .primary,
                            size: .default
                        ) {
                            openFilePicker()
                        }

                        ShadcnButton(
                            "Play Demo",
                            icon: "play",
                            variant: .secondary,
                            size: .default
                        ) {
                            loadSampleVideo()
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(width: 420, height: 240)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                        .fill(ShadcnTheme.card.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                        .strokeBorder(
                            isTargeted ? ShadcnTheme.primary : ShadcnTheme.border,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                )

                // Supported Formats Muted Caption
                HStack(spacing: 6) {
                    Text("Apple Silicon Hardware Engine")
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    Text("·")
                        .foregroundStyle(ShadcnTheme.border)
                    Text("H.264 · HEVC · ProRes · AV1 · SRT · VTT")
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        engine.loadMedia(from: url)
                    }
                }
            }
            return true
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = MediaSupport.contentTypes
        panel.message = "Choose a video or audio file to open in Frames"

        if panel.runModal() == .OK, let url = panel.url {
            engine.loadMedia(from: url)
        }
    }

    private func loadSampleVideo() {
        if let sampleURL = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4") {
            engine.loadMedia(from: sampleURL)
        }
    }
}
