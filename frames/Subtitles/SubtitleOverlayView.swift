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
                    .font(.system(size: fontSize, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                            .overlay(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 28)
                    .transition(.opacity.animation(.fluidQuick))
            }
            .allowsHitTesting(false)
        }
    }
}
