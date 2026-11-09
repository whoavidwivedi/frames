//
//  MetalVideoRenderer.swift
//  frames
//
//  Ultra-low-power zero-copy Metal 3 video presentation pipeline with
//  Unified Memory IOSurface direct binding and 10-bit HDR / EDR color reproduction.
//

import Foundation
import Metal
import CoreVideo
import QuartzCore
import simd

nonisolated public struct VideoShaderUniforms: Sendable {
    public var colorMatrix: simd_float3x3
    public var yuvOffset: simd_float3
    public var colorSpaceMode: Int32 // 0: BT.709 SDR, 1: BT.2020 SDR, 2: BT.2020 PQ HDR, 3: BT.2020 HLG HDR
    public var maxContentLightLevel: Float // in nits, e.g. 1000.0
    public var aspectScale: simd_float2
    
    public init(
        colorMatrix: simd_float3x3 = simd_float3x3(1.0),
        yuvOffset: simd_float3 = simd_float3(0, 0, 0),
        colorSpaceMode: Int32 = 0,
        maxContentLightLevel: Float = 1000.0,
        aspectScale: simd_float2 = simd_float2(1.0, 1.0)
    ) {
        self.colorMatrix = colorMatrix
        self.yuvOffset = yuvOffset
        self.colorSpaceMode = colorSpaceMode
        self.maxContentLightLevel = maxContentLightLevel
        self.aspectScale = aspectScale
    }
}

nonisolated public final class MetalVideoRenderer: @unchecked Sendable {
    
    // MARK: - Properties
    
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    
    private let renderLock = NSLock()
    private var currentPixelBuffer: CVPixelBuffer?
    private var currentColorSpaceMode: Int32 = 0
    private var is10Bit: Bool = false
    public var onFrameAvailable: (@Sendable () -> Void)?

    public var currentBuffer: CVPixelBuffer? {
        renderLock.lock()
        defer { renderLock.unlock() }
        return currentPixelBuffer
    }
    
    // MARK: - Lifecycle
    
    public init?() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            return nil
        }
        self.device = dev
        self.commandQueue = queue
        
        // Create zero-copy CVMetalTextureCache
        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            dev,
            nil,
            &cache
        )
        guard cacheStatus == kCVReturnSuccess, let c = cache else {
            return nil
        }
        self.textureCache = c
        
        setupPipeline()
    }
    
    private func setupPipeline() {
        do {
            let library = try device.makeLibrary(source: VideoShaderSource.source, options: nil)
            guard let vertexFunc = library.makeFunction(name: "videoVertexShader"),
                  let fragmentFunc = library.makeFunction(name: "videoFragmentShader") else {
                return
            }
            
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFunc
            desc.fragmentFunction = fragmentFunc
            // Render in 16-bit float extended linear space for perfect HDR headroom
            desc.colorAttachments[0].pixelFormat = .rgba16Float
            
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("[MetalVideoRenderer] Pipeline setup error: \(error)")
        }
    }
    
    private var frameCount: UInt64 = 0
    public var preferredAspectRatio: Float? = nil {
        didSet {
            renderLock.lock()
            cachedAspectScale = simd_float2(1.0, 1.0)
            lastBufferWidth = 0
            renderLock.unlock()
        }
    }
    private var lastPreferredAspectRatio: Float? = nil
    private var lastBufferWidth: Int = 0
    private var lastBufferHeight: Int = 0
    private var lastPixelFormat: OSType = 0
    private var lastLayerWidth: Float = 0
    private var lastLayerHeight: Float = 0
    private var cachedAspectScale = simd_float2(1.0, 1.0)
    private var cachedColorSpaceMode: Int32 = 0
    private var isFlushPending: Bool = false
    private let flushLock = NSLock()

    private struct TextureCacheBox: @unchecked Sendable {
        let cache: CVMetalTextureCache
    }

    private func flushTextureCacheAsync(cache: CVMetalTextureCache) {
        flushLock.lock()
        if isFlushPending {
            flushLock.unlock()
            return
        }
        isFlushPending = true
        flushLock.unlock()

        let cacheBox = TextureCacheBox(cache: cache)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            CVMetalTextureCacheFlush(cacheBox.cache, 0)
            guard let self = self else { return }
            self.flushLock.lock()
            self.isFlushPending = false
            self.flushLock.unlock()
        }
    }

    // MARK: - Frame Submission
    
    /// Directly updates the current frame for display link rendering without invoking external callbacks.
    public func setBufferForDisplay(_ pixelBuffer: CVPixelBuffer, colorSpaceMode: Int32 = 0, is10Bit: Bool = false) {
        renderLock.lock()
        self.currentPixelBuffer = pixelBuffer
        self.currentColorSpaceMode = colorSpaceMode
        self.is10Bit = is10Bit
        renderLock.unlock()
    }

    /// Updates the current frame to display with zero-copy IOSurface binding and notifies listeners.
    public func updateFrame(_ pixelBuffer: CVPixelBuffer, colorSpaceMode: Int32 = 0, is10Bit: Bool = false) {
        renderLock.lock()
        self.currentPixelBuffer = pixelBuffer
        self.currentColorSpaceMode = colorSpaceMode
        self.is10Bit = is10Bit
        let callback = onFrameAvailable
        renderLock.unlock()
        callback?()
    }
    
    public func clearFrame() {
        renderLock.lock()
        self.currentPixelBuffer = nil
        self.lastBufferWidth = 0
        self.lastBufferHeight = 0
        self.lastPixelFormat = 0
        self.lastLayerWidth = 0
        self.lastLayerHeight = 0
        self.lastPreferredAspectRatio = nil
        self.cachedAspectScale = simd_float2(1.0, 1.0)
        self.cachedColorSpaceMode = 0
        let cache = textureCache
        let callback = onFrameAvailable
        renderLock.unlock()
        if let cache = cache {
            flushTextureCacheAsync(cache: cache)
        }
        callback?()
    }
    
    // MARK: - Rendering
    
    /// Renders the current frame into the given CAMetalLayer drawable.
    public func render(to layer: CAMetalLayer) {
        renderLock.lock()
        guard let buffer = currentPixelBuffer,
              let pipeline = pipelineState,
              let cache = textureCache else {
            let shouldClear = (currentPixelBuffer == nil)
            renderLock.unlock()
            if shouldClear, let drawable = layer.nextDrawable() {
                let renderPass = MTLRenderPassDescriptor()
                renderPass.colorAttachments[0].texture = drawable.texture
                renderPass.colorAttachments[0].loadAction = .clear
                renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                renderPass.colorAttachments[0].storeAction = .store
                if let cmdBuffer = commandQueue.makeCommandBuffer(),
                   let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
                    encoder.endEncoding()
                    cmdBuffer.present(drawable)
                    cmdBuffer.commit()
                }
            }
            return
        }
        let mode = currentColorSpaceMode
        let isTenBit = is10Bit
        renderLock.unlock()
        
        guard let drawable = layer.nextDrawable() else { return }
        
        // Extract zero-copy Metal textures directly from Unified Memory CVPixelBuffer planes
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        let isTenBitEffective = isTenBit || (pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
                                            pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange)

        if lastBufferWidth > 0 && (width != lastBufferWidth || height != lastBufferHeight || pixelFormat != lastPixelFormat) {
            flushTextureCacheAsync(cache: cache)
        }
        lastPixelFormat = pixelFormat
        
        let lumaFormat: MTLPixelFormat = isTenBitEffective ? .r16Unorm : .r8Unorm
        let chromaFormat: MTLPixelFormat = isTenBitEffective ? .rg16Unorm : .rg8Unorm
        
        var yTextureRef: CVMetalTexture?
        let yStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            buffer,
            nil,
            lumaFormat,
            width,
            height,
            0,
            &yTextureRef
        )
        
        var uvTextureRef: CVMetalTexture?
        let uvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            buffer,
            nil,
            chromaFormat,
            width / 2,
            height / 2,
            1,
            &uvTextureRef
        )
        
        guard yStatus == kCVReturnSuccess, let yRef = yTextureRef,
              uvStatus == kCVReturnSuccess, let uvRef = uvTextureRef,
              let yTex = CVMetalTextureGetTexture(yRef),
              let uvTex = CVMetalTextureGetTexture(uvRef) else {
            return
        }
        
        // Calculate aspect-ratio preservation scale with dimensions caching
        let layerWidth = Float(layer.drawableSize.width)
        let layerHeight = Float(layer.drawableSize.height)
        var aspectScale = cachedAspectScale

        if width != lastBufferWidth || height != lastBufferHeight || layerWidth != lastLayerWidth || layerHeight != lastLayerHeight || preferredAspectRatio != lastPreferredAspectRatio {
            lastBufferWidth = width
            lastBufferHeight = height
            lastLayerWidth = layerWidth
            lastLayerHeight = layerHeight
            lastPreferredAspectRatio = preferredAspectRatio

            if layerWidth > 0 && layerHeight > 0 && width > 0 && height > 0 {
                var par: Float = 1.0
                if let parDict = CVBufferCopyAttachment(buffer, kCVImageBufferPixelAspectRatioKey, nil) as? [String: Any] {
                    let hSpacing = (parDict[kCVImageBufferPixelAspectRatioHorizontalSpacingKey as String] as? NSNumber)?.floatValue ?? 1.0
                    let vSpacing = (parDict[kCVImageBufferPixelAspectRatioVerticalSpacingKey as String] as? NSNumber)?.floatValue ?? 1.0
                    if vSpacing > 0 {
                        par = hSpacing / vSpacing
                    }
                }
                let viewAspect = layerWidth / layerHeight
                let videoAspect: Float
                if let preferred = preferredAspectRatio, preferred > 0 {
                    videoAspect = preferred
                } else if let clapDict = CVBufferCopyAttachment(buffer, kCVImageBufferCleanApertureKey, nil) as? [String: Any],
                          let clapW = (clapDict[kCVImageBufferCleanApertureWidthKey as String] as? NSNumber)?.floatValue,
                          let clapH = (clapDict[kCVImageBufferCleanApertureHeightKey as String] as? NSNumber)?.floatValue,
                          clapW > 0 && clapH > 0 {
                    videoAspect = (clapW * par) / clapH
                } else {
                    videoAspect = (Float(width) * par) / Float(height)
                }

                if viewAspect > videoAspect {
                    aspectScale = simd_float2(videoAspect / viewAspect, 1.0)
                } else {
                    aspectScale = simd_float2(1.0, viewAspect / videoAspect)
                }
                cachedAspectScale = aspectScale
            }

            var detected = mode
            if mode == 0 {
                if let transfer = CVBufferCopyAttachment(buffer, kCVImageBufferTransferFunctionKey, nil) as? String {
                    if transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String) {
                        detected = 2
                    } else if transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String) {
                        detected = 3
                    }
                } else if let primaries = CVBufferCopyAttachment(buffer, kCVImageBufferColorPrimariesKey, nil) as? String {
                    if primaries == (kCVImageBufferColorPrimaries_ITU_R_2020 as String) {
                        detected = 1
                    }
                }
            }
            cachedColorSpaceMode = detected
        }
        let effectiveMode = (mode != 0) ? mode : cachedColorSpaceMode

        // Prepare Uniforms
        var uniforms = createUniforms(for: effectiveMode)
        uniforms.aspectScale = aspectScale
        
        // Set up render pass
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = drawable.texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPass.colorAttachments[0].storeAction = .store
        
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return
        }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<VideoShaderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(yTex, index: 0)
        encoder.setFragmentTexture(uvTex, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<VideoShaderUniforms>.stride, index: 0)
        
        // Draw quad triangle strip (4 vertices)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        cmdBuffer.present(drawable)
        cmdBuffer.commit()

        // Periodic texture cache maintenance to release unused IOSurfaces back to system pool
        frameCount &+= 1
        if (frameCount & 0x7F) == 0 { // Every 128 frames
            flushTextureCacheAsync(cache: cache)
        }
    }
    
    // MARK: - Color Transforms
    
    private func createUniforms(for mode: Int32) -> VideoShaderUniforms {
        var uniforms = VideoShaderUniforms()
        uniforms.colorSpaceMode = mode
        
        if mode == 0 {
            // Rec.709 Limited Range standard SDR
            uniforms.yuvOffset = simd_float3(-16.0 / 255.0, -128.0 / 255.0, -128.0 / 255.0)
            
            // Rec.709 conversion matrix
            // [ 1.164383,  0.000000,  1.792741 ]
            // [ 1.164383, -0.213249, -0.532909 ]
            // [ 1.164383,  2.112402,  0.000000 ]
            let col0 = simd_float3(1.164383, 1.164383, 1.164383)
            let col1 = simd_float3(0.000000, -0.213249, 2.112402)
            let col2 = simd_float3(1.792741, -0.532909, 0.000000)
            uniforms.colorMatrix = simd_float3x3(col0, col1, col2)
        } else {
            // Rec.2020 Limited Range (HDR / Wide Color)
            uniforms.yuvOffset = simd_float3(-16.0 / 255.0, -128.0 / 255.0, -128.0 / 255.0)
            
            // Rec.2020 conversion matrix
            // [ 1.164384,  0.000000,  1.678674 ]
            // [ 1.164384, -0.187326, -0.650424 ]
            // [ 1.164384,  2.141772,  0.000000 ]
            let col0 = simd_float3(1.164384, 1.164384, 1.164384)
            let col1 = simd_float3(0.000000, -0.187326, 2.141772)
            let col2 = simd_float3(1.678674, -0.650424, 0.000000)
            uniforms.colorMatrix = simd_float3x3(col0, col1, col2)
            uniforms.maxContentLightLevel = 1000.0
        }
        
        return uniforms
    }
}
