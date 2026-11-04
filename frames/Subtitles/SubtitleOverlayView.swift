import SwiftUI

public struct SubtitleOverlayView: View {
    public let text: String
    public var fontSize: CGFloat = 20

    public init(text: String, fontSize: CGFloat = 20) {
        self.text = text
        self.fontSize = fontSize
    }

    public var body: some View {
        if !text.isEmpty {
            VStack {
                Spacer()
                Text(text)
                    .font(.system(size: fontSize, weight: .medium, design: .default))
                    .foregroundStyle(ShadcnTheme.foreground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .fill(ShadcnTheme.background.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                    .strokeBorder(ShadcnTheme.border, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 28)
                    .padding(.bottom, 72)
                    .transition(.opacity.animation(.fluidQuick))
            }
            .allowsHitTesting(false)
        }
    }
}
