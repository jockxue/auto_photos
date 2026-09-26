import CoreGraphics
import CoreImage
import Foundation
import Metal

struct RenderRequest: @unchecked Sendable {
    let original: OriginalImage
    let edits: EditState
    let maximumDimension: CGFloat?
}

struct RenderedImage: @unchecked Sendable {
    let cgImage: CGImage
    let scale: CGFloat
    let orientation: CGImagePropertyOrientation
}

protocol RenderEngineProtocol: Sendable {
    func render(_ request: RenderRequest) throws -> RenderedImage
}

enum RenderError: LocalizedError {
    case outputCreationFailed

    var errorDescription: String? { L10n.text("The renderer could not create an output image.") }
}

/// Core Image implementation backed by a Metal CIContext whenever Metal is available.
/// It contains no SwiftUI or View dependency, and can be replaced by a test double.
final class CoreImageRenderEngine: RenderEngineProtocol, @unchecked Sendable {
    private let context: CIContext
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let pipeline = RenderPipeline()

    init(metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        if let metalDevice {
            context = CIContext(mtlDevice: metalDevice, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            ])
        } else {
            // Simulator/unsupported-hardware fallback; CIContext still selects the best available renderer.
            context = CIContext(options: [.useSoftwareRenderer: false])
        }
    }

    func render(_ request: RenderRequest) throws -> RenderedImage {
        var image = pipeline.process(
            original: request.original.image,
            orientation: request.original.metadata.orientation,
            edits: request.edits
        )

        if let maximumDimension = request.maximumDimension {
            let extent = image.extent
            let ratio = min(1, maximumDimension / max(extent.width, extent.height))
            image = image.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
        }

        guard let output = context.createCGImage(
            image,
            from: image.extent.integral,
            format: .RGBA8,
            colorSpace: request.original.metadata.colorSpace ?? outputColorSpace
        ) else {
            throw RenderError.outputCreationFailed
        }
        return RenderedImage(cgImage: output, scale: request.original.metadata.scale, orientation: .up)
    }
}
