import SwiftUI

// MARK: - Emil Kowalski Tactile Button Styles

private struct TactileSpeedPresetStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.fluidQuick, value: configuration.isPressed)
    }
}

private struct TactileSpeedCloseStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.fluidQuick, value: configuration.isPressed)
    }
}

// MARK: - Shadcn Playback Speed Selector Panel

public struct SpeedSelectorPanel: View {
    @Bindable var engine: VideoPlayerEngine
    @State private var hoveredSpeed: Float? = nil

    private let presets: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                Text("Playback Speed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)

                Spacer()

                Text(String(format: "%.2f×", engine.playbackRate))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(abs(engine.playbackRate - 1.0) > 0.01 ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)

                // Close Button with Fluid Spring Dismissal
                Button {
                    withAnimation(.fluidQuick) {
                        engine.activeInspectorSheet = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                        .frame(width: 22, height: 22)
                        .background(ShadcnTheme.secondary.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(TactileSpeedCloseStyle())
                .pointingHand()
                .help("Close (Esc)")
            }

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // Presets Grid with Subtle Hover Pill Fill and Tactile Press Feedback
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(presets, id: \.self) { speed in
                    presetButton(speed: speed)
                }
            }

            Rectangle()
                .fill(ShadcnTheme.borderSubtle)
                .frame(height: 1)

            // Custom Slider with Pointing Hand
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Fine Adjustment")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    Spacer()
                    if abs(engine.playbackRate - 1.0) > 0.01 {
                        Button("Reset (1.0×)") {
                            withAnimation(.fluidQuick) {
                                engine.playbackRate = 1.0
                            }
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ShadcnTheme.foreground)
                        .buttonStyle(TactileSpeedPresetStyle())
                        .pointingHand()
                    }
                }

                Slider(
                    value: Binding(
                        get: { Double(engine.playbackRate) },
                        set: { engine.playbackRate = Float(round($0 * 20.0) / 20.0) }
                    ),
                    in: 0.25...3.0,
                    step: 0.05
                )
                .tint(ShadcnTheme.foreground)
                .pointingHand()
            }
        }
        .padding(14)
        .frame(width: 250)
        .playerPanel()
        .environment(\.colorScheme, .dark)
    }

    private func presetButton(speed: Float) -> some View {
        let isSelected = abs(engine.playbackRate - speed) < 0.01
        let isHovered = hoveredSpeed == speed

        return Button {
            withAnimation(.fluidQuick) {
                engine.playbackRate = speed
            }
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(ShadcnTheme.foreground)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }

                Text(String(format: "%.2f×", speed))
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
            }
            .animation(.fluidQuick, value: isSelected)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .fill(isSelected ? ShadcnTheme.cardHover : (isHovered ? ShadcnTheme.muted.opacity(0.6) : ShadcnTheme.secondary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                    .strokeBorder(isSelected ? ShadcnTheme.borderActive : (isHovered ? ShadcnTheme.borderActive : ShadcnTheme.borderSubtle), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileSpeedPresetStyle())
        .pointingHand()
        .onHover { h in
            withAnimation(.fluidQuick) {
                hoveredSpeed = h ? speed : nil
            }
        }
    }
}
