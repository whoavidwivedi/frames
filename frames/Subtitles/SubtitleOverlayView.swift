import SwiftUI

@MainActor
public struct SubtitleOverlayView: View {
    public let text: String
    private let overrideFontSize: CGFloat?
    private let overrideTextColor: Color?
    private let overrideScrimOpacity: Double?

    @Bindable private var settings = SettingsManager.shared

    public init(
        text: String,
        fontSize: CGFloat? = nil,
        textColor: Color? = nil,
        scrimOpacity: Double? = nil
    ) {
        self.text = text
        self.overrideFontSize = fontSize
        self.overrideTextColor = textColor
        self.overrideScrimOpacity = scrimOpacity
    }

    public var fontSize: CGFloat {
        overrideFontSize ?? CGFloat(settings.subtitleFontSize)
    }

    public var textColor: Color {
        overrideTextColor ?? settings.subtitleTextColor
    }

    public var scrimOpacity: Double {
        overrideScrimOpacity ?? settings.subtitleBackgroundScrimOpacity
    }

    public var body: some View {
        let activeFontSize = overrideFontSize ?? CGFloat(settings.subtitleFontSize)
        let activeTextColor = overrideTextColor ?? settings.subtitleTextColor
        let activeScrimOpacity = overrideScrimOpacity ?? settings.subtitleBackgroundScrimOpacity

        if !text.isEmpty {
            VStack {
                Spacer()
                Text(text)
                    .font(.system(size: activeFontSize, weight: .semibold, design: .default))
                    .foregroundStyle(activeTextColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusMd, style: .continuous)
                            .fill(Color.black.opacity(activeScrimOpacity))
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
