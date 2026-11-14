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
    @State private var appeared: Bool = false

    public init(prompt: ResumePromptData, onResume: @escaping (URL, Double) -> Void, onStartOver: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onResume = onResume
        self.onStartOver = onStartOver
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(ShadcnTheme.primary.opacity(0.18)).frame(width: 34, height: 34)
                            Image(systemName: "play.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(ShadcnTheme.primary).offset(x: 1)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resume Playback").font(.system(size: 15, weight: .semibold)).foregroundStyle(ShadcnTheme.foreground)
                            Text(prompt.title).font(.system(size: 12, weight: .medium)).foregroundStyle(ShadcnTheme.foregroundSecondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { onCancel() } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(ShadcnTheme.foregroundMuted).frame(width: 24, height: 24).background(Circle().fill(ShadcnTheme.cardHover))
                        }.buttonStyle(.plain).pointingHand().keyboardShortcut(.cancelAction)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ShadcnTheme.border.opacity(0.6)).frame(height: 6)
                                Capsule().fill(LinearGradient(colors: [ShadcnTheme.primary, ShadcnTheme.primary.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, geo.size.width * CGFloat(min(max(prompt.progress, 0), 1))), height: 6)
                                Circle().fill(.white).frame(width: 12, height: 12).shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                                    .offset(x: max(0, geo.size.width * CGFloat(min(max(prompt.progress, 0), 1)) - 6))
                            }
                        }.frame(height: 12)
                        HStack {
                            Text(prompt.formattedTime).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(ShadcnTheme.foreground)
                            Spacer()
                            Text(prompt.formattedDuration).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(ShadcnTheme.foregroundMuted)
                        }
                    }

                    HStack(spacing: 10) {
                        Button { onStartOver(prompt.url) } label: {
                            Text("Start Over").font(.system(size: 13, weight: .medium)).foregroundStyle(ShadcnTheme.foregroundSecondary).frame(maxWidth: .infinity).frame(height: 36)
                                .background(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous).fill(ShadcnTheme.cardHover))
                                .overlay(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous).strokeBorder(ShadcnTheme.border, lineWidth: 1))
                        }.buttonStyle(.plain).pointingHand().keyboardShortcut("r", modifiers: [])

                        Button { onResume(prompt.url, prompt.resumeSeconds) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                                Text("Resume").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(ShadcnTheme.primaryForeground).frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous).fill(isHoveringResume ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary))
                        }.buttonStyle(.plain).pointingHand().keyboardShortcut(.defaultAction).onHover { h in isHoveringResume = h }
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .background(RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                .background(RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous).fill(ShadcnTheme.card.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous).strokeBorder(ShadcnTheme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 24)
                .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { appeared = true } }
            }
        }
    }
}
