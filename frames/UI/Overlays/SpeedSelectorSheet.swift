import SwiftUI

public struct SpeedSelectorPanel: View {
    @Bindable var engine: VideoPlayerEngine

    private let presets: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Speed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)
                Spacer()
                Text(String(format: "%.2f×", engine.playbackRate))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
            }

            Rectangle()
                .fill(ShadcnTheme.border)
                .frame(height: 1)

            // Presets Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(presets, id: \.self) { speed in
                    let isSelected = abs(engine.playbackRate - speed) < 0.01
                    Button {
                        engine.playbackRate = speed
                    } label: {
                        Text(String(format: "%.2f×", speed))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                    .fill(isSelected ? ShadcnTheme.accentActive : ShadcnTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                                            .strokeBorder(isSelected ? ShadcnTheme.borderActive : ShadcnTheme.border, lineWidth: 1)
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointingHand()
                }
            }

            // Custom Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Fine Adjustment")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)
                    Spacer()
                    if engine.playbackRate != 1.0 {
                        Button("Reset") {
                            engine.playbackRate = 1.0
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .buttonStyle(.plain)
                        .pointingHand()
                    }
                }

                Slider(value: $engine.playbackRate, in: 0.25...3.0, step: 0.05)
                    .tint(ShadcnTheme.foreground)
                    .pointingHand()
            }
        }
        .frame(width: 220)
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 12)
    }
}
