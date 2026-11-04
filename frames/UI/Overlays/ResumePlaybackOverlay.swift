import SwiftUI
import AppKit

public struct ResumePromptData: Identifiable {
    public let id = UUID()
    public let url: URL
    public let resumeSeconds: Double
    public let formattedTime: String
    public let formattedDuration: String
    public let progress: Double

    public var title: String {
        url.deletingPathExtension().lastPathComponent
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
    @State private var isHoveringRestart: Bool = false
    @State private var isHoveringCancel: Bool = false

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
            // Dismissible semi-transparent backdrop
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            // Floating Liquid Glass Dialog Card
            VStack(spacing: 18) {
                // Top row with clock icon and close button
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(ShadcnTheme.cardHover)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                            )

                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.primaryHighlight)
                    }

                    Spacer()

                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(isHoveringCancel ? ShadcnTheme.cardHover : Color.clear)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .onHover { h in
                        withAnimation(.fluidQuick) {
                            isHoveringCancel = h
                        }
                    }
                    .animation(.fluidQuick, value: isHoveringCancel)
                    .help("Dismiss (Esc)")
                }

                // Title and Media Information
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resume Playback?")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foreground)

                    Text(prompt.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("You left off at \(prompt.formattedTime) of \(prompt.formattedDuration).")
                        .font(.system(size: 12))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)

                    // Visual Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(ShadcnTheme.accentActive)
                                .frame(height: 5)

                            Capsule()
                                .fill(ShadcnTheme.primaryHighlight)
                                .frame(width: max(6, geo.size.width * CGFloat(min(max(prompt.progress, 0.0), 1.0))), height: 5)
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Action Buttons
                VStack(spacing: 8) {
                    // Option 1: Continue where you left off
                    Button {
                        onResume(prompt.url, prompt.resumeSeconds)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                            Text("Continue where you left off (at \(prompt.formattedTime))")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(ShadcnTheme.primaryForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                .fill(isHoveringResume ? ShadcnTheme.primaryHighlight : ShadcnTheme.primary)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .scaleEffect(isHoveringResume ? 1.01 : 1.0)
                    .animation(.fluidQuick, value: isHoveringResume)
                    .onHover { h in
                        withAnimation(.fluidQuick) {
                            isHoveringResume = h
                        }
                    }

                    // Option 2: Start over from beginning
                    Button {
                        onStartOver(prompt.url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12))
                            Text("Start over from beginning")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(ShadcnTheme.foreground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                .fill(isHoveringRestart ? ShadcnTheme.cardHover : ShadcnTheme.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                        .strokeBorder(isHoveringRestart ? ShadcnTheme.borderActive : ShadcnTheme.border, lineWidth: 1)
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                    .scaleEffect(isHoveringRestart ? 1.01 : 1.0)
                    .animation(.fluidQuick, value: isHoveringRestart)
                    .onHover { h in
                        withAnimation(.fluidQuick) {
                            isHoveringRestart = h
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 410)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .fill(ShadcnTheme.card.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.35),
                radius: 24,
                x: 0,
                y: 10
            )
        }
    }
}
