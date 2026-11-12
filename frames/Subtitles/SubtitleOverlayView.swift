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

    public var backgroundColor: Color {
        settings.subtitleBackgroundColor
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
                    .font(.system(size: activeFontSize, weight: .medium, design: .default))
                    .foregroundStyle(activeTextColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(backgroundColor.opacity(activeScrimOpacity))
                    )
                    .padding(.horizontal, 28)
                    .transition(.opacity)
            }
            .allowsHitTesting(false)
        }
    }
}
