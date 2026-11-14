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
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture { onCancel() }

                VStack {
                    Spacer()

                    // Resume marker on the timeline
                    GeometryReader { mgeo in
                        let rx = mgeo.size.width * CGFloat(min(max(prompt.progress, 0), 1))
                        Rectangle()
                            .fill(ShadcnTheme.primary)
                            .frame(width: 2, height: 14)
                            .position(x: rx, y: mgeo.size.height - 4)
                    }
                    .allowsHitTesting(false)

                    // Pill badge anchored to resume position on the timeline
                    VStack(spacing: 4) {
                        // tail
                        Triangle()
                            .fill(ShadcnTheme.card.opacity(0.9))
                            .frame(width: 12, height: 6)

                        HStack(spacing: 8) {
                            Text("Resume from \(prompt.formattedTime)?")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ShadcnTheme.foreground)

                            Button { onStartOver(prompt.url) } label: {
                                Text("Start Over")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(Capsule().fill(ShadcnTheme.cardHover))
                                    .overlay(Capsule().strokeBorder(ShadcnTheme.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .pointingHand()

                            Button { onResume(prompt.url, prompt.resumeSeconds) } label: {
                                Text("Continue")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ShadcnTheme.primaryForeground)
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                    .background(Capsule().fill(isHoveringResume ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary))
                            }
                            .buttonStyle(.plain)
                            .pointingHand()
                            .onHover { h in isHoveringResume = h }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .background(
                            Capsule(style: .continuous)
                                .fill(ShadcnTheme.card.opacity(0.7))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    }
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .position(x: max(110, min(geo.size.width - 110, resumeX)), y: geo.size.height - 86)
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
