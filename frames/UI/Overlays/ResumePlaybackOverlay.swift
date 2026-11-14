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
        GeometryReader { geo in
            let resumeX = geo.size.width * CGFloat(min(max(prompt.progress, 0), 1))

            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { onCancel() }

                // Badge anchored to the resume position on the timeline
                VStack(spacing: 0) {
                    Spacer()

                    ZStack(alignment: .bottom) {
                        // pointer / tail
                        Triangle()
                            .fill(ShadcnTheme.card.opacity(0.95))
                            .frame(width: 14, height: 8)
                            .offset(y: 8)

                        VStack(spacing: 6) {
                            Text("Resume from \(prompt.formattedTime)?")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ShadcnTheme.foreground)

                            HStack(spacing: 6) {
                                Button { onStartOver(prompt.url) } label: {
                                    Text("Start Over")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                        .padding(.horizontal, 10)
                                        .frame(height: 26)
                                        .background(Capsule().fill(ShadcnTheme.cardHover))
                                        .overlay(Capsule().strokeBorder(ShadcnTheme.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .pointingHand()

                                Button { onResume(prompt.url, prompt.resumeSeconds) } label: {
                                    Text("Continue")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(ShadcnTheme.primaryForeground)
                                        .padding(.horizontal, 12)
                                        .frame(height: 26)
                                        .background(Capsule().fill(isHoveringResume ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary))
                                }
                                .buttonStyle(.plain)
                                .pointingHand()
                                .onHover { h in isHoveringResume = h }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(ShadcnTheme.card.opacity(0.85))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                    }
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .position(x: max(80, min(geo.size.width - 80, resumeX)), y: geo.size.height - 90)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.76)) {
                        appeared = true
                    }
                }
            }
        }
    }
}

// Small triangle for the badge tail
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
