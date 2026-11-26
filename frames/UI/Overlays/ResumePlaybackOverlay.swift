import SwiftUI
import AppKit

public struct ResumePromptData: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let resumeSeconds: Double
    public let formattedTime: String
    public let formattedDuration: String
    public let progress: Double

    public var title: String { url.deletingPathExtension().lastPathComponent }
    public var format: String { url.pathExtension.uppercased() }

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
    @State private var pulse: Bool = false

    public init(prompt: ResumePromptData, onResume: @escaping (URL, Double) -> Void, onStartOver: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onResume = onResume
        self.onStartOver = onStartOver
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }
                .pointingHand()

            VStack {
                Spacer()

                HStack(spacing: 8) {
                    Text("Resume from \(prompt.formattedTime)?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foreground)

                    Button { onStartOver(prompt.url) } label: {
                        Text("Start Over")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(ShadcnTheme.cardHover))
                            .overlay(Capsule().strokeBorder(ShadcnTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(FramesOutlineButtonStyle())
                    .pointingHand()

                    Button { onResume(prompt.url, prompt.resumeSeconds) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                            Text("Continue").font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(ShadcnTheme.primaryForeground)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Capsule().fill(isHoveringResume ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary))
                    }
                    .buttonStyle(FramesOutlineButtonStyle())
                    .pointingHand()
                    .onHover { h in isHoveringResume = h }

                    // Hidden cancel for Escape
                    Button { onCancel() } label: { EmptyView() }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(ShadcnTheme.card)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(ShadcnTheme.primary.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                Spacer()

            }
        }
    }
}
