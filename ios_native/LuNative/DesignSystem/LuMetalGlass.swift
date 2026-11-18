import SwiftUI
import UIKit
import Metal
import QuartzCore

// MARK: - 渲染器（全局一份）

/// 编译管线 + 设备。整个 App 共用一个，失败就返回 nil，让上层退回材质版玻璃。
final class LuGlassRenderer {
    static let shared = LuGlassRenderer()

    let device: MTLDevice?
    let queue: MTLCommandQueue?
    private(set) var pipeline: MTLRenderPipelineState?

    var isReady: Bool { device != nil && queue != nil && pipeline != nil }

    private init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            self.device = nil
            self.queue = nil
            return
        }
        self.device = device
        self.queue = queue

        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "glass_vertex"),
              let fragment = library.makeFunction(name: "glass_fragment")
        else {
            luLogWarn("Glass", "Metal 默认库/函数缺失，退回材质玻璃")
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // 非预乘 alpha，标准 over 混合
        if let attachment = descriptor.colorAttachments[0] {
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.sourceAlphaBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            luLogError("Glass", "管线编译失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 参数

struct LuGlassStyle: Equatable {
    var cornerRadius: CGFloat = 24
    var refraction: CGFloat = 16
    var aberration: CGFloat = 0.45
    var frost: CGFloat = 0.35
    var specular: CGFloat = 0.55
    var border: CGFloat = 1.2
    var saturation: CGFloat = 1.35
    var tint: Color = .clear
}

// MARK: - 视图

/// 玻璃层本体：抓背后内容 → 纹理 → shader 画回来。
///
/// 用裸 `CAMetalLayer` 而不是 `MTKView`：只要「画一帧」，不需要它的循环与代理，
/// 少一层生命周期也少一处并发告警。截图前会临时隐藏自己，避免自采样成回声。
final class MetalGlassView: UIView {

    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    var style = LuGlassStyle() {
        didSet { if style != oldValue { render() } }
    }

    private var texture: MTLTexture?
    private var lastCapture = Date.distantPast
    private var captureScheduled = false

    struct GlassUniforms {
        var size: SIMD2<Float> = .zero
        var cornerRadius: Float = 24
        var refraction: Float = 16
        var aberration: Float = 0.45
        var frost: Float = 0.35
        var specular: Float = 0.55
        var border: Float = 1.2
        var saturation: Float = 1.35
        var tint: SIMD4<Float> = .zero
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        metalLayer.device = LuGlassRenderer.shared.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.allowsNextDrawableTimeout = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleCapture(force: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.contentsScale = scale
        let size = CGSize(width: max(bounds.width, 1) * scale,
                          height: max(bounds.height, 1) * scale)
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
        }
        scheduleCapture(force: false)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            scheduleCapture(force: true)
        }
    }

    /// SwiftUI 侧内容变化后主动刷新（例如封面图加载完）
    func refresh() { scheduleCapture(force: true) }

    private func scheduleCapture(force: Bool) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        if !force, Date().timeIntervalSince(lastCapture) < 0.5 { return }
        if captureScheduled { return }
        captureScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.captureScheduled = false
            self.capture()
        }
    }

    // MARK: 抓底层

    private func capture() {
        guard let window, bounds.width > 1, bounds.height > 1 else { return }
        guard UIApplication.shared.applicationState == .active else { return }

        let rect = convert(bounds, to: window)
        guard rect.width > 1, rect.height > 1 else { return }

        // 截图时藏掉自己，否则会把自己的上一帧采进纹理形成回声
        let wasHidden = isHidden
        isHidden = true
        defer { isHidden = wasHidden }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1                    // 玻璃本来就要模糊，1x 足够，省一半带宽
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            window.layer.render(in: context.cgContext)
        }

        guard let cgImage = image.cgImage else { return }
        upload(cgImage)
        lastCapture = Date()
        render()
    }

    private func upload(_ cgImage: CGImage) {
        guard let device = LuGlassRenderer.shared.device else { return }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return }

        if texture == nil || texture!.width != width || texture!.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead]
            texture = device.makeTexture(descriptor: descriptor)
        }
        guard let texture else { return }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else { return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0, withBytes: pixels, bytesPerRow: bytesPerRow)
    }

    // MARK: 绘制

    private func render() {
        guard let texture,
              let pipeline = LuGlassRenderer.shared.pipeline,
              let queue = LuGlassRenderer.shared.queue,
              metalLayer.drawableSize.width > 0,
              metalLayer.drawableSize.height > 0,
              let drawable = metalLayer.nextDrawable() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        var value = uniforms(pixelSize: bounds.size, scale: metalLayer.contentsScale)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&value, length: MemoryLayout<GlassUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func uniforms(pixelSize: CGSize, scale: CGFloat) -> GlassUniforms {
        var value = GlassUniforms()
        let factor = Float(scale)
        value.size = SIMD2<Float>(Float(pixelSize.width) * factor,
                                  Float(pixelSize.height) * factor)
        value.cornerRadius = Float(style.cornerRadius) * factor
        value.refraction = Float(style.refraction) * factor
        value.aberration = Float(style.aberration)
        value.frost = Float(style.frost)
        value.specular = Float(style.specular)
        value.border = Float(style.border) * factor
        value.saturation = Float(style.saturation)
        value.tint = tintComponents()
        return value
    }

    private func tintComponents() -> SIMD4<Float> {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(style.tint).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return .zero
        }
        return SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
    }
}

// MARK: - SwiftUI 包装

struct LuMetalGlassBackground: UIViewRepresentable {
    var style: LuGlassStyle

    func makeUIView(context: Context) -> MetalGlassView {
        MetalGlassView()
    }

    func updateUIView(_ uiView: MetalGlassView, context: Context) {
        uiView.style = style
    }
}
