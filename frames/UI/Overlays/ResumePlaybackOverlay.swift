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
    @State private var appeared: Bool = false

    public init(prompt: ResumePromptData, onResume: @escaping (URL, Double) -> Void, onStartOver: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onResume = onResume
        self.onStartOver = onStartOver
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack {
                Spacer()

                // Floating glass pill
                HStack(spacing: 14) {
                    // Progress + label
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShadcnTheme.primary)
                            Text("Resume from \(prompt.formattedTime)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ShadcnTheme.foreground)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ShadcnTheme.border.opacity(0.5)).frame(height: 4)
                                Capsule().fill(ShadcnTheme.primary)
                                    .frame(width: max(4, geo.size.width * CGFloat(min(max(prompt.progress, 0), 1))), height: 4)
                            }
                        }
                        .frame(height: 4)
                        .frame(width: 150)
                    }

                    Divider().frame(height: 34).opacity(0.3)

                    // Start Over
                    Button { onStartOver(prompt.url) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Start Over")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(isHoveringStartOver ? ShadcnTheme.cardHover : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .keyboardShortcut("r", modifiers: [])
                    .onHover { h in isHoveringStartOver = h }

                    // Resume
                    Button { onResume(prompt.url, prompt.resumeSeconds) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Resume")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(ShadcnTheme.primaryForeground)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(isHoveringResume ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary))
                        .shadow(color: ShadcnTheme.primary.opacity(0.35), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .keyboardShortcut(.defaultAction)
                    .onHover { h in isHoveringResume = h }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .background(
                    Capsule(style: .continuous)
                        .fill(ShadcnTheme.card.opacity(0.55))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .padding(.bottom, 28)
                .onAppear {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
                        appeared = true
                    }
                }
            }
        }
    }
}
