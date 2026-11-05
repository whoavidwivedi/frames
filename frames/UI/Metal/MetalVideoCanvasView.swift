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
    private var isPlaying = false
    private var videoFrameRate: Float = 60.0
    
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
        // Dynamic Range & Color Space configuration matching SettingsManager
        let hdrMode = SettingsManager.shared.hdrToneMapping
        if hdrMode == .sdrOnly {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.wantsExtendedDynamicRangeContent = false
        } else {
            layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
            layer.wantsExtendedDynamicRangeContent = true
        }
        layer.presentsWithTransaction = false
        layer.framebufferOnly = true
        layer.allowsNextDrawableTimeout = true
        
        self.layer = layer
        self.metalLayer = layer
        
        // Single-frame listener for seeks / paused scrubbing updates
        renderer.onFrameAvailable = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Avoid redundant rendering if display link is already actively ticking
                if !self.isPlaying {
                self.needsRender = true
                self.renderNow()
            }
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
    
    // MARK: - Display Link Pacing & Dynamic Frame Rate Cadence
    
    public func setPlaybackState(isPlaying: Bool, frameRate: Float) {
        let wasPlaying = self.isPlaying
        self.isPlaying = isPlaying
        if frameRate > 0 {
            self.videoFrameRate = frameRate
        }

        if isPlaying != wasPlaying {
            if isPlaying {
                updateFrameRateCadence()
                displayLink?.isPaused = false
        } else {
                displayLink?.isPaused = true
            }
        } else if isPlaying {
            updateFrameRateCadence()
        }
    }

    private func updateFrameRateCadence() {
        guard let link = displayLink else { return }
        let settings = SettingsManager.shared
        let isLowBattery = settings.batterySaverGuardEnabled && settings.isBatteryBelowTwentyPercent

        if settings.proMotionSyncEnabled && !isLowBattery {
            let fps = videoFrameRate
            if fps > 23.0 && fps < 25.0 {
                // 24fps cinema cadence on ProMotion: 48Hz (2:2 pulldown) or 24Hz
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 48)
            } else if fps >= 25.0 && fps < 35.0 {
                // 25fps / 30fps standard video: 60Hz
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            } else if fps >= 55.0 && fps <= 65.0 {
                // 60fps high frame rate: 60Hz
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            } else if fps > 100.0 {
                // 120fps high-refresh rate: 120Hz
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            } else {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
        } else if isLowBattery {
            // Power saver on low battery: down-clock cadence to match video or drop to 30Hz
            let fps = videoFrameRate
            if fps <= 30.0 {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
            } else {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            }
        } else {
            // ProMotion sync disabled in settings: standard 60Hz cap
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = self.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        self.displayLink = link
        updateFrameRateCadence()
        link.add(to: .main, forMode: .common)
        // Keep CADisplayLink paused when not playing to eliminate idle CPU/GPU consumption
        link.isPaused = !isPlaying
    }
    
    public func applySettings() {
        if let layer = metalLayer {
            let hdrMode = SettingsManager.shared.hdrToneMapping
            if hdrMode == .sdrOnly {
                layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
                layer.wantsExtendedDynamicRangeContent = false
            } else {
                layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
                layer.wantsExtendedDynamicRangeContent = true
            }
        }
        updateFrameRateCadence()
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func displayLinkDidFire(_ sender: CADisplayLink) {
        guard let renderer = renderer, let layer = metalLayer else { return }
        
        var receivedFrame = false
        if let getNextBuffer = onFrameRequested, let buffer = getNextBuffer() {
            // Feed directly into renderer without triggering asynchronous renderNow loop
            renderer.setBufferForDisplay(buffer)
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
    public var isPlaying: Bool = true
    public var videoFrameRate: Float = 60.0
    public var onFrameRequested: (@MainActor () -> CVPixelBuffer?)?
    
    public init(
        renderer: MetalVideoRenderer?,
        isPlaying: Bool = true,
        videoFrameRate: Float = 60.0,
        onFrameRequested: (@MainActor () -> CVPixelBuffer?)? = nil
    ) {
        self.renderer = renderer
        self.isPlaying = isPlaying
        self.videoFrameRate = videoFrameRate
        self.onFrameRequested = onFrameRequested
    }
    
    public func makeNSView(context: Context) -> NativeMetalView {
        let view = NativeMetalView(renderer: renderer)
        view.onFrameRequested = onFrameRequested
        view.setPlaybackState(isPlaying: isPlaying, frameRate: videoFrameRate)
        return view
    }
    
    public func updateNSView(_ nsView: NativeMetalView, context: Context) {
        nsView.onFrameRequested = onFrameRequested
        nsView.setPlaybackState(isPlaying: isPlaying, frameRate: videoFrameRate)
    }
}
