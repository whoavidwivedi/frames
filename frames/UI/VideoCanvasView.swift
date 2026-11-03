import SwiftUI
import AVFoundation
import AppKit

public struct VideoCanvasView: NSViewRepresentable {
    public let player: AVPlayer
    public var onSingleClick: () -> Void
    public var onDoubleClick: () -> Void

    public init(
        player: AVPlayer,
        onSingleClick: @escaping () -> Void = {},
        onDoubleClick: @escaping () -> Void = {}
    ) {
        self.player = player
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
    }

    public func makeNSView(context: Context) -> PlayerContainerNSView {
        let view = PlayerContainerNSView()
        view.playerLayer.player = player
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    public func updateNSView(_ nsView: PlayerContainerNSView, context: Context) {
        if nsView.playerLayer.player != player {
            nsView.playerLayer.player = player
        }
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}

public final class PlayerContainerNSView: NSView {
    public let playerLayer = AVPlayerLayer()
    public var onSingleClick: (() -> Void)?
    public var onDoubleClick: (() -> Void)?

    private var clickTimer: Timer?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        playerLayer.videoGravity = .resizeAspect
        playerLayer.needsDisplayOnBoundsChange = true
        layer?.addSublayer(playerLayer)
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        if let window = window {
            playerLayer.contentsScale = window.backingScaleFactor
        }
        CATransaction.commit()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            playerLayer.contentsScale = window.backingScaleFactor
        }
    }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            clickTimer?.invalidate()
            clickTimer = nil
            onDoubleClick?()
        } else if event.clickCount == 1 {
            clickTimer?.invalidate()
            clickTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
                self?.onSingleClick?()
            }
        }
    }
}
