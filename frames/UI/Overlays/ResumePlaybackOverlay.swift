import SwiftUI
import AppKit

public struct ResumePromptData: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let resumeSeconds: Double
    public let formattedTime: String
    public let formattedDuration: String
    public let progress: Double

    public var title: String {
        url.deletingPathExtension().lastPathComponent
    }

    public var format: String {
        url.pathExtension.uppercased()
    }

    public init(url: URL, resumeSeconds: Double, formattedTime: String, formattedDuration: String, progress: Double) {
        self.url = url
        self.resumeSeconds = resumeSeconds
        self.formattedTime = formattedTime
        self.formattedDuration = formattedDuration
        self.progress = progress
    }
}

public struct ResumePlaybackOverlay: View {
    public let prompt: ResumePromptData
    public var onResume: (URL, Double) -> Void
    public var onStartOver: (URL) -> Void
    public var onCancel: () -> Void

    @State private var isHoveringResume: Bool = false
    @State private var isHoveringStartOver: Bool = false
    @State private var isHoveringClose: Bool = false

    public init(
        prompt: ResumePromptData,
        onResume: @escaping (URL, Double) -> Void,
        onStartOver: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.onResume = onResume
        self.onStartOver = onStartOver
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            // Minimal ambient backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Flat, clean & minimal card (zero drop shadows)
            VStack(alignment: .leading, spacing: 12) {
                // Header: Title + Close
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)

                    Text("Resume Playback?")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foreground)

                    Spacer()

                    Button {
                        onCancel()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                .fill(isHoveringClose ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isHoveringClose ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                        }
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .pointingHand()
                    .keyboardShortcut(.cancelAction)
                    .help("Dismiss (Esc)")
                    .onHover { h in
                        isHoveringClose = h
                    }
                }

                // File name & time left off
                VStack(alignment: .leading, spacing: 3) {
                    Text(prompt.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("Left off at \(prompt.formattedTime) of \(prompt.formattedDuration)")
                        .font(.system(size: 11))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                }

                // Flat progress line
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(ShadcnTheme.border)
                            .frame(height: 3)

                        Capsule()
                            .fill(ShadcnTheme.foreground)
                            .frame(width: max(3, geo.size.width * CGFloat(min(max(prompt.progress, 0.0), 1.0))), height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.vertical, 2)

                // Clean side-by-side action buttons
                HStack(spacing: 8) {
                    // Start Over
                    Button {
                        onStartOver(prompt.url)
                    } label: {
                        Text("Start Over")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isHoveringStartOver ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .pointingHand()
                    .keyboardShortcut("r", modifiers: [])
                    .onHover { h in
                        isHoveringStartOver = h
                    }

                    // Resume
                    Button {
                        onResume(prompt.url, prompt.resumeSeconds)
                    } label: {
                        Text("Resume")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.primaryForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isHoveringResume ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .pointingHand()
                    .keyboardShortcut(.defaultAction)
                    .onHover { h in
                        isHoveringResume = h
                    }
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                    .fill(ShadcnTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
            )
        }
    }
}
