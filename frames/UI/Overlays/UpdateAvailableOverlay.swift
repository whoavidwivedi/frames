import SwiftUI
import AppKit

/// Clean, native liquid-glass modal informing the user of an available OTA update.
/// Adheres strictly to the shadcn base-luma design tokens and macOS Apple Silicon aesthetics.
public struct UpdateAvailableOverlay: View {
    public let update: AppUpdateInfo
    @Bindable public var manager: UpdateManager
    public var onDismiss: () -> Void

    @State private var isHoveringClose: Bool = false
    @State private var isHoveringGitHub: Bool = false
    @State private var isHoveringSkip: Bool = false

    public init(
        update: AppUpdateInfo,
        manager: UpdateManager,
        onDismiss: @escaping () -> Void
    ) {
        self.update = update
        self.manager = manager
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Ambient semi-translucent backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isBusy {
                        onDismiss()
                    }
                }

            // Glass modal card
            VStack(alignment: .leading, spacing: 14) {
                // Header: Icon + Title + Version Badge + Dismiss button
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .fill(Color(red: 249/255.0, green: 115/255.0, blue: 22/255.0).opacity(0.15))
                            .frame(width: 34, height: 34)

                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(red: 249/255.0, green: 115/255.0, blue: 22/255.0))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("New Update Available")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ShadcnTheme.foreground)

                            // Version Badge
                            HStack(spacing: 3) {
                                Text("v\(manager.currentVersion.displayString)")
                                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                                Text("v\(update.version.displayString)")
                                    .foregroundStyle(Color(red: 249/255.0, green: 115/255.0, blue: 22/255.0))
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(ShadcnTheme.cardHover)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                                    )
                            )
                        }

                        Text(update.title)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if !isBusy {
                        Button {
                            onDismiss()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isHoveringClose ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(isHoveringClose ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                            }
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .keyboardShortcut(.cancelAction)
                        .help("Dismiss (Esc)")
                        .onHover { isHoveringClose = $0 }
                    }
                }

                // Metadata Details Strip
                HStack(spacing: 12) {
                    if let date = update.publishedDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                        Text(update.asset.formattedSize)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text("Apple Silicon (ARM64)")
                    }

                    Spacer()
                }
                .font(.system(size: 10))
                .foregroundStyle(ShadcnTheme.foregroundMuted)

                // Scrollable Changelog Highlights
                VStack(alignment: .leading, spacing: 6) {
                    Text("Release Highlights")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(cleanedReleaseNotes(update.releaseNotes))
                                .font(.system(size: 12))
                                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                    }
                    .frame(height: 140)
                    .background(ShadcnTheme.background.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                    )
                }

                // Download Progress State
                if case .downloading(let progress, let written, let total) = manager.status {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Downloading update...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ShadcnTheme.foreground)
                            Spacer()
                            Text("\(ByteCountFormatter.string(fromByteCount: written, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) (\(Int(progress * 100))%)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(ShadcnTheme.foregroundMuted)
                        }

                        GeometryReader { barGeo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(ShadcnTheme.cardHover)

                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color(red: 249/255.0, green: 115/255.0, blue: 22/255.0))
                                    .frame(width: max(0, min(barGeo.size.width * CGFloat(progress), barGeo.size.width)))
                                    .animation(.fluidQuick, value: progress)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 2)
                } else if case .extracting = manager.status {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                        Text("Verifying and extracting update package...")
                            .font(.system(size: 11))
                            .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    }
                    .padding(.vertical, 4)
                } else if case .readyToRestart = manager.status {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text("Update ready! Restarting Frames...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                    }
                    .padding(.vertical, 4)
                } else if case .error(let msg) = manager.status {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.red)
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }

                // Action Buttons Bar
                HStack(spacing: 8) {
                    if isBusy {
                        ShadcnButton(
                            "Cancel",
                            variant: .secondary,
                            size: .sm
                        ) {
                            manager.cancelDownload()
                        }

                        Spacer()
                    } else {
                        // Skip version button
                        Button {
                            manager.skipVersion(update.tagName)
                        } label: {
                            Text("Skip this version")
                                .font(.system(size: 11))
                                .foregroundStyle(isHoveringSkip ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .onHover { isHoveringSkip = $0 }

                        Spacer()

                        // View on GitHub button
                        Button {
                            manager.openReleasePage()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                    .font(.system(size: 11))
                                Text("Release Notes")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(isHoveringGitHub ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        }
                        .buttonStyle(.plain)
                        .pointingHand()
                        .onHover { isHoveringGitHub = $0 }
                        .padding(.trailing, 4)

                        // Later button
                        ShadcnButton(
                            "Later",
                            variant: .secondary,
                            size: .sm
                        ) {
                            onDismiss()
                        }

                        // Update & Restart Primary CTA
                        ShadcnButton(
                            "Update & Restart",
                            icon: "arrow.triangle.2.circlepath",
                            variant: .primary,
                            size: .sm
                        ) {
                            manager.startUpdateAndRestart()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.top, 4)
            }
            .padding(18)
            .frame(width: 470)
            .background(ShadcnTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusLg, style: .continuous)
                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
            )
        }
    }

    private var isBusy: Bool {
        switch manager.status {
        case .downloading, .extracting, .readyToRestart:
            return true
        default:
            return false
        }
    }

    private func cleanedReleaseNotes(_ raw: String) -> String {
        var text = raw
        // Strip markdown headers like # or ## if preferred, or leave intact
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No release notes provided." : text
    }
}
