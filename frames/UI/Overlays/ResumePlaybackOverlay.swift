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
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(ShadcnTheme.primary.opacity(0.18)).frame(width: 32, height: 32)
                            Image(systemName: "play.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(ShadcnTheme.primary).offset(x: 1)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Resume Playback").font(.system(size: 14, weight: .semibold)).foregroundStyle(ShadcnTheme.foreground)
                            Text(prompt.title).font(.system(size: 11, weight: .medium)).foregroundStyle(ShadcnTheme.foregroundSecondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { onCancel() } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(ShadcnTheme.foregroundMuted).frame(width: 22, height: 22).background(Circle().fill(ShadcnTheme.cardHover))
                        }.buttonStyle(.plain).pointingHand().keyboardShortcut(.cancelAction)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ShadcnTheme.border.opacity(0.5)).frame(height: 5)
                                Capsule().fill(LinearGradient(colors: [ShadcnTheme.primary, ShadcnTheme.primary.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(5, geo.size.width * CGFloat(min(max(prompt.progress, 0), 1))), height: 5)
                            }
                        }.frame(height: 5)
                        HStack {
                            Text(prompt.formattedTime).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(ShadcnTheme.foreground)
                            Spacer()
                            Text(prompt.formattedDuration).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(ShadcnTheme.foregroundMuted)
                        }
                    }

                    HStack(spacing: 8) {
                        Button { onStartOver(prompt.url) } label: {
                            Text("Start Over").font(.system(size: 12, weight: .medium)).foregroundStyle(ShadcnTheme.foregroundSecondary).frame(maxWidth: .infinity).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ShadcnTheme.cardHover))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ShadcnTheme.border, lineWidth: 1))
                        }.buttonStyle(.plain).pointingHand().keyboardShortcut("r", modifiers: [])

                        Button { onResume(prompt.url, prompt.resumeSeconds) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                                Text("Resume").font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(ShadcnTheme.primaryForeground).frame(maxWidth: .infinity).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isHoveringResume ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary))
                        }.buttonStyle(.plain).pointingHand().keyboardShortcut(.defaultAction).onHover { h in isHoveringResume = h }
                    }
                }
                .padding(16)
                .frame(width: 340)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ShadcnTheme.card.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ShadcnTheme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .padding(.bottom, 24)
                .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.76)) { appeared = true } }
            }
        }
    }
}
