//
//  MetalVideoCanvasView.swift
//  frames
//
//  Zero-copy Metal 3 HDR Presentation Canvas with 120Hz ProMotion
//  display link synchronization and dynamic Extended Dynamic Range (EDR).
//

import SwiftUI
import AppKit
import Metal
import QuartzCore
import CoreVideo

public final class NativeMetalView: NSView {
    
    // MARK: - Properties
    
    public let renderer: MetalVideoRenderer?
    private var metalLayer: CAMetalLayer?
    private var displayLink: CADisplayLink?
    private var needsRender = true
    
    public var onFrameRequested: (@MainActor () -> CVPixelBuffer?)?
    
    // MARK: - Init
    
    public init(renderer: MetalVideoRenderer?) {
        self.renderer = renderer
        super.init(frame: .zero)
        self.wantsLayer = true
        setupMetalLayer()
    }
    
    required init?(coder: NSCoder) {
        self.renderer = MetalVideoRenderer()
        super.init(coder: coder)
        self.wantsLayer = true
        setupMetalLayer()
    }
    
    deinit {
        stopDisplayLink()
    }
    
    // MARK: - Setup
    
    private func setupMetalLayer() {
        guard let renderer = renderer else { return }
        
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .rgba16Float
        // Wide color gamut & HDR extended linear P3 space
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        layer.wantsExtendedDynamicRangeContent = true
        layer.presentsWithTransaction = false
        layer.framebufferOnly = true
        
        self.layer = layer
        self.metalLayer = layer
        
        renderer.onFrameAvailable = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.needsRender = true
                self.renderNow()
            }
        }
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }
    
    public override func layout() {
        super.layout()
        if let metalLayer = metalLayer {
            metalLayer.frame = bounds
            metalLayer.drawableSize = convertToBacking(bounds).size
            needsRender = true
        }
    }
    
    // MARK: - Display Link Pacing (120Hz ProMotion)
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = self.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func displayLinkDidFire(_ sender: CADisplayLink) {
        guard let renderer = renderer, let layer = metalLayer else { return }
        
        var receivedFrame = false
        if let getNextBuffer = onFrameRequested, let buffer = getNextBuffer() {
            renderer.updateFrame(buffer)
            receivedFrame = true
        }

        // Preserve the last drawable. Re-rendering the same frame on every
        // display tick wastes GPU power without improving the image.
        guard receivedFrame || needsRender else { return }
        needsRender = false
        renderer.render(to: layer)
    }
    
    /// Trigger an immediate render pass outside the display link loop
    public func renderNow() {
        guard let renderer = renderer, let layer = metalLayer else { return }
        needsRender = false
        renderer.render(to: layer)
    }
}

// MARK: - SwiftUI Representable

public struct MetalVideoCanvasView: NSViewRepresentable {
    public let renderer: MetalVideoRenderer?
    public var onFrameRequested: (@MainActor () -> CVPixelBuffer?)?
    
    public init(
        renderer: MetalVideoRenderer?,
        onFrameRequested: (@MainActor () -> CVPixelBuffer?)? = nil
    ) {
        self.renderer = renderer
        self.onFrameRequested = onFrameRequested
    }
    
    public func makeNSView(context: Context) -> NativeMetalView {
        let view = NativeMetalView(renderer: renderer)
        view.onFrameRequested = onFrameRequested
        return view
    }
    
    public func updateNSView(_ nsView: NativeMetalView, context: Context) {
        nsView.onFrameRequested = onFrameRequested
    }
}
