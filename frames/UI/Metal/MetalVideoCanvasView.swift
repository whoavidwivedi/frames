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
import CoreMedia
import AVFoundation

// MARK: - Zero-Copy CMSampleBuffer Factory

public enum SampleBufferFactory {
    /// Zero-copy wraps a decoded CVPixelBuffer into a hardware-scannable CMSampleBuffer.
    public static func makeSampleBuffer(
        from pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime = .invalid,
        duration: CMTime = .invalid,
        displayImmediately: Bool = true
    ) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDesc = formatDescription else {
            return nil
        }

        var pts = presentationTimeStamp
        if !pts.isValid {
            if let ptsNum = CVBufferCopyAttachment(pixelBuffer, "FramesPTS" as CFString, nil) as? NSNumber {
                pts = CMTime(seconds: ptsNum.doubleValue, preferredTimescale: 60000)
            } else {
                pts = CMTime(value: 0, timescale: 1000)
            }
        }

        var frameDuration = duration
        if !frameDuration.isValid {
            if let durNum = CVBufferCopyAttachment(pixelBuffer, "FramesDuration" as CFString, nil) as? NSNumber, durNum.doubleValue > 0 {
                frameDuration = CMTime(seconds: durNum.doubleValue, preferredTimescale: 60000)
            } else {
                frameDuration = CMTime(value: 1, timescale: 60)
            }
        }

        var timingInfo = CMSampleTimingInfo(
            duration: frameDuration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sample = sampleBuffer else {
            return nil
        }

        if displayImmediately {
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
               CFArrayGetCount(attachments) > 0 {
                let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                    Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                )
            }
        }

        return sample
    }
}

public final class NativeMetalView: NSView {
    
    // MARK: - Properties
    
    public let renderer: MetalVideoRenderer?
    public private(set) var metalLayer: CAMetalLayer?
    public private(set) var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
    private var lastEnqueuedBuffer: CVPixelBuffer?
    private var displayLink: CADisplayLink?
    private var settingsObserver: AnyObject?
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
        registerSettingsObserver()
    }
    
    required init?(coder: NSCoder) {
        self.renderer = MetalVideoRenderer()
        super.init(coder: coder)
        self.wantsLayer = true
        setupMetalLayer()
        registerSettingsObserver()
    }
    
    deinit {
        stopDisplayLink()
        if let obs = settingsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
    
    private func registerSettingsObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: SettingsManager.presentationEngineDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySettings()
        }
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
        layer.isOpaque = true
        
        self.layer = layer
        self.metalLayer = layer
        self.canDrawSubviewsIntoLayer = false

        // Ultra-low-power AVSampleBufferDisplayLayer direct hardware scanout target
        let sbdl = AVSampleBufferDisplayLayer()
        sbdl.preventsDisplaySleepDuringVideoPlayback = true
        sbdl.videoGravity = .resizeAspect
        sbdl.isOpaque = true
        sbdl.frame = bounds
        layer.addSublayer(sbdl)
        self.sampleBufferDisplayLayer = sbdl
        
        updatePresentationEngineLayers()
        
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

    private func updatePresentationEngineLayers() {
        let isDirect = (SettingsManager.shared.effectivePresentationEngine == .directHardwareScanout)
        sampleBufferDisplayLayer?.isHidden = !isDirect
    }

    public override var isOpaque: Bool {
        return true
    }

    public private(set) var isDecoupledFullscreen: Bool = false

    /// Decouples transparent overlay views and subview compositing in fullscreen mode
    /// to grant macOS WindowServer direct hardware plane scanout promotion.
    public func decoupleOverlaysForFullscreen(_ decouple: Bool) {
        self.isDecoupledFullscreen = decouple
        if let layer = metalLayer {
            layer.isOpaque = true
        }
        if let sbdl = sampleBufferDisplayLayer {
            sbdl.isOpaque = true
        }
        if decouple {
            self.canDrawSubviewsIntoLayer = false
        }
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            sampleBufferDisplayLayer?.contentsScale = window.backingScaleFactor
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }
    
    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let metalLayer = metalLayer {
            metalLayer.drawableSize = convertToBacking(bounds).size
        }
        if let sbdl = sampleBufferDisplayLayer {
            sbdl.frame = bounds
            if let window = window {
                sbdl.contentsScale = window.backingScaleFactor
            }
        }
        CATransaction.commit()
        needsRender = true
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
        let settings = SettingsManager.shared
        if let layer = metalLayer {
            layer.isOpaque = true
            let hdrMode = settings.hdrToneMapping
            if hdrMode == .sdrOnly {
                layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
                layer.wantsExtendedDynamicRangeContent = false
            } else {
                layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
                layer.wantsExtendedDynamicRangeContent = true
            }
        }
        if let sbdl = sampleBufferDisplayLayer {
            sbdl.isOpaque = true
            sbdl.preventsDisplaySleepDuringVideoPlayback = true
            sbdl.videoGravity = .resizeAspect
            sbdl.frame = bounds
            if let window = window {
                sbdl.contentsScale = window.backingScaleFactor
            }
            let isDirect = (settings.effectivePresentationEngine == .directHardwareScanout)
            sbdl.isHidden = !isDirect
        }
        updateFrameRateCadence()
        needsRender = true
        renderNow()
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func displayLinkDidFire(_ sender: CADisplayLink) {
        let engine = SettingsManager.shared.effectivePresentationEngine
        
        var receivedFrame = false
        var nextBuffer: CVPixelBuffer? = nil
        if let getNextBuffer = onFrameRequested, let buffer = getNextBuffer() {
            nextBuffer = buffer
            receivedFrame = true
            lastEnqueuedBuffer = buffer
            renderer?.setBufferForDisplay(buffer)
        }

        switch engine {
        case .directHardwareScanout:
            sampleBufferDisplayLayer?.isHidden = false
            if let buffer = nextBuffer {
                presentDirectHardwareBuffer(buffer)
            } else if needsRender, let buffer = lastEnqueuedBuffer ?? renderer?.currentBuffer {
                presentDirectHardwareBuffer(buffer)
            }
            needsRender = false

        case .metalShaders:
            sampleBufferDisplayLayer?.isHidden = true
            guard let renderer = renderer, let layer = metalLayer else { return }
            guard receivedFrame || needsRender else { return }
            needsRender = false
            renderer.render(to: layer)

        case .auto:
            break
        }
    }
    
    /// Trigger an immediate render pass outside the display link loop
    public func renderNow() {
        needsRender = false
        let engine = SettingsManager.shared.effectivePresentationEngine
        switch engine {
        case .directHardwareScanout:
            sampleBufferDisplayLayer?.isHidden = false
            if let buffer = lastEnqueuedBuffer ?? renderer?.currentBuffer {
                presentDirectHardwareBuffer(buffer)
            }
        case .metalShaders, .auto:
            sampleBufferDisplayLayer?.isHidden = true
            guard let renderer = renderer, let layer = metalLayer else { return }
            renderer.render(to: layer)
        }
    }

    /// Enqueues pixel buffer directly to AVSampleBufferDisplayLayer for 0% GPU DCP hardware scanout.
    public func presentDirectHardwareBuffer(_ buffer: CVPixelBuffer) {
        lastEnqueuedBuffer = buffer
        renderer?.setBufferForDisplay(buffer)
        guard let sbdl = sampleBufferDisplayLayer else { return }
        if sbdl.status == .failed {
            sbdl.flush()
        }
        if let sample = SampleBufferFactory.makeSampleBuffer(from: buffer) {
            sbdl.enqueue(sample)
        }
    }
}

public typealias VideoPresentationCanvasView = MetalVideoCanvasView

// MARK: - SwiftUI Representable

public struct MetalVideoCanvasView: NSViewRepresentable {
    public let renderer: MetalVideoRenderer?
    public var isPlaying: Bool = true
    public var videoFrameRate: Float = 60.0
    public var isDecoupledFullscreen: Bool = false
    public var onFrameRequested: (@MainActor () -> CVPixelBuffer?)?
    
    public init(
        renderer: MetalVideoRenderer?,
        isPlaying: Bool = true,
        videoFrameRate: Float = 60.0,
        isDecoupledFullscreen: Bool = false,
        onFrameRequested: (@MainActor () -> CVPixelBuffer?)? = nil
    ) {
        self.renderer = renderer
        self.isPlaying = isPlaying
        self.videoFrameRate = videoFrameRate
        self.isDecoupledFullscreen = isDecoupledFullscreen
        self.onFrameRequested = onFrameRequested
    }
    
    public func makeNSView(context: Context) -> NativeMetalView {
        let view = NativeMetalView(renderer: renderer)
        view.onFrameRequested = onFrameRequested
        view.setPlaybackState(isPlaying: isPlaying, frameRate: videoFrameRate)
        view.decoupleOverlaysForFullscreen(isDecoupledFullscreen)
        return view
    }
    
    public func updateNSView(_ nsView: NativeMetalView, context: Context) {
        nsView.onFrameRequested = onFrameRequested
        nsView.setPlaybackState(isPlaying: isPlaying, frameRate: videoFrameRate)
        nsView.decoupleOverlaysForFullscreen(isDecoupledFullscreen)
        nsView.applySettings()
    }
}
