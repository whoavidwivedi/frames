import SwiftUI

public struct SpeedSelectorPanel: View {
    @Bindable var engine: VideoPlayerEngine

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
                    .foregroundStyle(Color.white.opacity(0.85))

                Text("Playback Speed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)

                Spacer()

                Text(String(format: "%.2f×", engine.playbackRate))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(abs(engine.playbackRate - 1.0) > 0.01 ? Color(red: 0.38, green: 0.85, blue: 0.65) : Color.white)

                Button {
                    withAnimation(.fluidSpring) {
                        engine.activeInspectorSheet = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Close (Esc)")
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            // Presets Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(presets, id: \.self) { speed in
                    presetButton(speed: speed)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            // Custom Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Fine Adjustment")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.60))
                    Spacer()
                    if abs(engine.playbackRate - 1.0) > 0.01 {
                        Button("Reset to 1.0×") {
                            withAnimation(.fluidQuick) {
                                engine.playbackRate = 1.0
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(red: 0.38, green: 0.85, blue: 0.65))
                        .buttonStyle(.plain)
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
                    .tint(Color.white.opacity(0.85))
                    .pointingHand()
            }
        }
        .padding(14)
        .frame(width: 250)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.08, opacity: 0.92))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.50), radius: 24, x: 0, y: 12)
        .environment(\.colorScheme, .dark)
    }

    private func presetButton(speed: Float) -> some View {
        let isSelected = abs(engine.playbackRate - speed) < 0.01
        let fillBg = isSelected ? Color.white.opacity(0.24) : Color.white.opacity(0.08)
        let strokeColor = isSelected ? Color.white.opacity(0.38) : Color.white.opacity(0.14)
        return Button {
            withAnimation(.fluidQuick) {
                engine.playbackRate = speed
            }
        } label: {
            Text(String(format: "%.2f×", speed))
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.80))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(fillBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHand()
    }
}
