import SwiftUI

public struct HardwareStatsPanel: View {
    let engine: VideoPlayerEngine
    let metrics = AppleSiliconMetrics.shared

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Hardware Metrics")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShadcnTheme.foreground)
                Spacer()
                Text("Apple Silicon")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ShadcnTheme.foregroundMuted)
            }

            Rectangle()
                .fill(ShadcnTheme.border)
                .frame(height: 1)

            // System Specs
            VStack(alignment: .leading, spacing: 6) {
                row(label: "Chip", value: metrics.chipName)
                row(label: "Architecture", value: "\(metrics.activeCores) cores (ARM64)")
                row(label: "Memory Footprint", value: String(format: "%.1f MB", metrics.memoryFootprintMB))
                row(label: "Decoder Engine", value: "VideoToolbox (HW)")
            }

            Rectangle()
                .fill(ShadcnTheme.border)
                .frame(height: 1)

            // Video Stream Specs
            VStack(alignment: .leading, spacing: 6) {
                row(label: "Codec", value: engine.metadata.codec)
                row(label: "Resolution", value: engine.metadata.resolutionDescription)
                row(label: "Frame Rate", value: engine.metadata.frameRateDescription)
                row(label: "Display Rate", value: "\(metrics.displayRefreshRate)Hz")
                row(label: "Color Space", value: engine.metadata.colorPrimaries)
            }
        }
        .frame(width: 270)
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 12)
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(ShadcnTheme.foregroundMuted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ShadcnTheme.foreground)
                .multilineTextAlignment(.trailing)
        }
    }
}
