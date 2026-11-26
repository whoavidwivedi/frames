import SwiftUI
import AppKit

/// Floating notification toast displayed when the user performs a manual update check.
/// Matches the shadcn liquid-glass aesthetic.
public struct UpdateNoticeToast: View {
    public let notice: ManualCheckNotice
    public var onDismiss: () -> Void

    @State private var isHoveringClose: Bool = false

    public init(notice: ManualCheckNotice, onDismiss: @escaping () -> Void) {
        self.notice = notice
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            if notice.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking for Updates")
            } else {
                Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                Text(notice.message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !notice.isLoading {
                Button {
                    onDismiss()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                            .fill(isHoveringClose ? ShadcnTheme.cardHover : Color.black.opacity(0.0001))

                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(isHoveringClose ? ShadcnTheme.foreground : ShadcnTheme.foregroundMuted)
                    }
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FramesPressStyle())
                .pointingHand()
                .onHover { isHoveringClose = $0 }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ShadcnTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
        .frame(maxWidth: 380)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .task(id: notice.id) {
            guard !notice.isLoading else { return }
            do {
                try await Task.sleep(for: .seconds(4.5))
                onDismiss()
            } catch {
                // A newer notice or a dismissed view cancels this timer.
            }
        }
    }
}
