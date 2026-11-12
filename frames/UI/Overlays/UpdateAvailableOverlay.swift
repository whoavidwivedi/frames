import SwiftUI
import AppKit

/// Full-page update experience: release highlights, update details, download
/// progress, and update actions presented as a dedicated page rather than a
/// small modal card.
public struct UpdateAvailableOverlay: View {
    public let update: AppUpdateInfo
    @Bindable public var manager: UpdateManager
    public var onDismiss: () -> Void

    @State private var isHoveringClose = false
    @State private var isHoveringGitHub = false
    @State private var isHoveringSkip = false

    private let accent = Color(red: 249 / 255.0, green: 115 / 255.0, blue: 22 / 255.0)

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
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 26) {
                    hero
                    statusSection
                    whatsNewSection
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            actionBar
        }
        .background(ShadcnTheme.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Software Update")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)
                Text("Frames v\(manager.currentVersion.displayString) → v\(update.version.displayString)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
            }

            Spacer()

            if !isBusy {
                Button {
                    onDismiss()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                            .fill(isHoveringClose ? ShadcnTheme.cardHover : Color.clear)

                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isHoveringClose ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
                .onHover { isHoveringClose = $0 }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                channelBadge

                if let date = update.publishedDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10.5))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                }
            }

            Text("Frames \(update.version.displayString)")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(ShadcnTheme.foreground)

            Text("A new version is available. You're currently running v\(manager.currentVersion.displayString).")
                .font(.system(size: 13))
                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                metaItem(icon: "arrow.down.circle", text: update.asset.formattedSize)
                metaItem(icon: "cpu", text: "Apple Silicon (ARM64)")
                metaItem(icon: "shippingbox", text: update.asset.name)
            }
            .padding(.top, 2)
        }
    }

    private var channelBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: update.isPrerelease ? "flame.fill" : "checkmark.shield.fill")
                .font(.system(size: 8))
            Text(update.isPrerelease ? "BETA" : "STABLE")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(update.isPrerelease ? accent : Color.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                .fill((update.isPrerelease ? Color.orange : Color.green).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder((update.isPrerelease ? Color.orange : Color.green).opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10.5))
        }
        .foregroundStyle(ShadcnTheme.foregroundMuted)
    }

    // MARK: - What's New

    private var whatsNewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's New")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ShadcnTheme.foreground)
                .padding(.leading, 2)

            pageCard {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(releaseNoteBlocks.enumerated()), id: \.offset) { _, block in
                        noteBlockView(block)
                    }
                }
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        switch manager.status {
        case .downloading(let progress, let written, let total):
            pageCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Downloading update…")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(ShadcnTheme.foreground)
                        Spacer()
                        Text("\(ByteCountFormatter.string(fromByteCount: written, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) · \(Int(progress * 100))%")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                    }

                    GeometryReader { barGeo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(ShadcnTheme.cardHover)

                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(accent)
                                .frame(width: max(0, min(barGeo.size.width * CGFloat(progress), barGeo.size.width)))
                                .animation(.linear(duration: 0.2), value: progress)
                        }
                    }
                    .frame(height: 6)
                }
            }

        case .extracting:
            pageCard {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                    Text("Verifying and extracting update package…")
                        .font(.system(size: 12))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                }
            }

        case .readyToRestart:
            pageCard {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text("Update ready — restarting Frames…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foreground)
                }
            }

        case .error(let message):
            pageCard {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            if isBusy {
                ShadcnButton("Cancel", variant: .secondary, size: .sm) {
                    manager.cancelDownload()
                }

                Spacer()

                if case .downloading(let progress, _, _) = manager.status {
                    Text("Downloading \(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                }
            } else {
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

                Button {
                    manager.openReleasePage()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                            .font(.system(size: 11))
                        Text("GitHub Release")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(isHoveringGitHub ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                }
                .buttonStyle(.plain)
                .pointingHand()
                .onHover { isHoveringGitHub = $0 }
                .padding(.trailing, 4)

                ShadcnButton("Later", variant: .secondary, size: .sm) {
                    onDismiss()
                }

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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var isBusy: Bool {
        switch manager.status {
        case .downloading, .extracting, .readyToRestart:
            return true
        default:
            return false
        }
    }

    // MARK: - Card Container

    private func pageCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .fill(ShadcnTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusXl, style: .continuous)
                    .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
            )
    }

    // MARK: - Release Notes Rendering

    @ViewBuilder
    private func noteBlockView(_ block: ReleaseNoteBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(.system(size: level <= 2 ? 15 : 12.5, weight: .semibold))
                .foregroundStyle(ShadcnTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 12.5))
                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                Text(inlineMarkdown(text))
                    .font(.system(size: 12.5))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
                Text(inlineMarkdown(text))
                    .font(.system(size: 12.5))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .code(let text):
            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(ShadcnTheme.foregroundSecondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(ShadcnTheme.background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .strokeBorder(ShadcnTheme.borderSubtle, lineWidth: 1)
                )
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private var releaseNoteBlocks: [ReleaseNoteBlock] {
        var blocks = parseReleaseNotes(update.releaseNotes)

        // Keep only the What's New section; drop install steps, checksums, and other trailing sections.
        if let start = blocks.firstIndex(where: { block in
            guard case .heading(_, let text) = block else { return false }
            let lower = text.lowercased()
            return lower.contains("what's new") || lower.contains("whats new")
        }) {
            blocks.removeSubrange(0...start)
        }

        if let end = blocks.firstIndex(where: { block in
            guard case .heading(_, let text) = block else { return false }
            let lower = text.lowercased()
            return lower.contains("installation") || lower.contains("checksum")
        }) {
            blocks.removeSubrange(end...)
        }

        if blocks.isEmpty {
            blocks = [.paragraph(text: "General improvements and optimizations.")]
        }

        return blocks
    }

    private func parseReleaseNotes(_ raw: String) -> [ReleaseNoteBlock] {
        var blocks: [ReleaseNoteBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(text: paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(text: codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }

            if inCode {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("• ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(text: String(trimmed.dropFirst(2))))
            } else if let dot = trimmed.firstIndex(of: "."),
                      dot > trimmed.startIndex,
                      trimmed[..<dot].allSatisfy(\.isNumber) {
                let marker = String(trimmed[...dot])
                let body = trimmed[trimmed.index(after: dot)...].trimmingCharacters(in: .whitespaces)
                if !body.isEmpty {
                    flushParagraph()
                    blocks.append(.numbered(marker: marker, text: body))
                } else {
                    paragraph.append(trimmed)
                }
            } else {
                paragraph.append(trimmed)
            }
        }

        if inCode, !codeLines.isEmpty {
            blocks.append(.code(text: codeLines.joined(separator: "\n")))
        }

        flushParagraph()

        if blocks.isEmpty {
            blocks.append(.paragraph(text: "General improvements and optimizations."))
        }

        return blocks
    }
}

private enum ReleaseNoteBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bullet(text: String)
    case numbered(marker: String, text: String)
    case code(text: String)
}
