import SwiftUI

public struct FullscreenSelectorPanel: View {
    @Bindable var engine: VideoPlayerEngine
    let windowManager = WindowManager.shared

    public init(engine: VideoPlayerEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Full Screen Mode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ShadcnTheme.foreground)

            Rectangle()
                .fill(ShadcnTheme.border)
                .frame(height: 1)

            // Option 1: Windowed Full Screen
            Button {
                windowManager.toggleWindowedFullscreen()
                engine.activeInspectorSheet = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 12))
                        .foregroundStyle(windowManager.isWindowedFullscreen ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Windowed Full Screen")
                            .font(.system(size: 12, weight: windowManager.isWindowedFullscreen ? .semibold : .medium))
                            .foregroundStyle(windowManager.isWindowedFullscreen ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        Text("Fills display on current Space")
                            .font(.system(size: 10))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                    }

                    Spacer()

                    Text("⌥F")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)

                    if windowManager.isWindowedFullscreen {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.foreground)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(windowManager.isWindowedFullscreen ? ShadcnTheme.accentActive : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointingHand()

            // Option 2: Native Full Screen
            Button {
                windowManager.toggleNativeFullscreen()
                engine.activeInspectorSheet = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundStyle(windowManager.isNativeFullscreen ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Native Full Screen")
                            .font(.system(size: 12, weight: windowManager.isNativeFullscreen ? .semibold : .medium))
                            .foregroundStyle(windowManager.isNativeFullscreen ? ShadcnTheme.foreground : ShadcnTheme.foregroundSecondary)
                        Text("Dedicated macOS Space")
                            .font(.system(size: 10))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                    }

                    Spacer()

                    Text("F")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ShadcnTheme.foregroundMuted)

                    if windowManager.isNativeFullscreen {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ShadcnTheme.foreground)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                        .fill(windowManager.isNativeFullscreen ? ShadcnTheme.accentActive : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointingHand()

            if windowManager.isAnyFullscreen {
                Rectangle()
                    .fill(ShadcnTheme.border)
                    .frame(height: 1)

                Button {
                    windowManager.exitAnyFullscreen()
                    engine.activeInspectorSheet = nil
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 11))
                        Text("Exit Full Screen")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("Esc")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ShadcnTheme.foregroundMuted)
                    }
                    .foregroundStyle(ShadcnTheme.foregroundSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: ShadcnTheme.radiusSm, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointingHand()
            }
        }
        .frame(width: 250)
        .shadcnCard(cornerRadius: ShadcnTheme.radiusLg, padding: 12)
    }
}
