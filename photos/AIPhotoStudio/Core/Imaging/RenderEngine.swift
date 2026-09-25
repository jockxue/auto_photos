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

    var errorDescription: String? { "The renderer could not create an output image." }
}

/// Core Image implementation backed by a Metal CIContext whenever Metal is available.
/// It contains no SwiftUI or View dependency, and can be replaced by a test double.
final class CoreImageRenderEngine: RenderEngineProtocol, @unchecked Sendable {
    private let context: CIContext
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

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
        var image = request.original.image.oriented(request.original.metadata.orientation)
        image = apply(request.edits.adjustments, to: image)
        image = apply(request.edits.geometry, to: image)

        if let maximumDimension = request.maximumDimension {
            let extent = image.extent
            let ratio = min(1, maximumDimension / max(extent.width, extent.height))
            image = image.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
        }

        guard let output = context.createCGImage(
            image,
            from: image.extent.integral,
            format: request.original.metadata.hasAlpha ? .RGBA8 : .RGBX8,
            colorSpace: request.original.metadata.colorSpace ?? outputColorSpace
        ) else {
            throw RenderError.outputCreationFailed
        }
        return RenderedImage(cgImage: output, scale: request.original.metadata.scale, orientation: .up)
    }

    private func apply(_ values: Adjustments, to source: CIImage) -> CIImage {
        var image = source
        image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": values.exposure * 2])
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: values.brightness * 0.25,
            kCIInputContrastKey: 1 + values.contrast * 0.5,
            kCIInputSaturationKey: 1 + values.saturation
        ])
        image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": values.vibrance])
        image = image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: 6500 + values.warmth * 2500, y: values.tint * 100)
        ])

        let highlightAmount = 1 - max(0, values.highlights)
        image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": highlightAmount,
            "inputShadowAmount": max(0, values.shadows)
        ])
        let sharpness = max(0, values.sharpness + values.definition * 0.5)
        if sharpness > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": sharpness * 1.5])
        }
        if values.noiseReduction > 0 {
            image = image.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": values.noiseReduction * 0.05,
                "inputSharpness": 0.4
            ])
        }
        if values.vignette > 0 {
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: values.vignette * 2,
                kCIInputRadiusKey: min(image.extent.width, image.extent.height) * 0.35
            ])
        }
        // Brilliance and black point are explicit domain values; their tuned render
        // curves are intentionally deferred so the serialized recipe stays stable.
        return image
    }

    private func apply(_ geometry: GeometryEdits, to source: CIImage) -> CIImage {
        var image = source
        let extent = image.extent
        let crop = geometry.crop
        let cropRect = CGRect(
            x: extent.minX + extent.width * crop.x,
            y: extent.minY + extent.height * crop.y,
            width: extent.width * crop.width,
            height: extent.height * crop.height
        ).intersection(extent)
        image = image.cropped(to: cropRect)

        let radians = geometry.rotationDegrees * .pi / 180
        if radians != 0 {
            image = image.transformed(by: CGAffineTransform(rotationAngle: radians))
        }
        if geometry.isFlippedHorizontally || geometry.isFlippedVertically {
            image = image.transformed(by: CGAffineTransform(
                scaleX: geometry.isFlippedHorizontally ? -1 : 1,
                y: geometry.isFlippedVertically ? -1 : 1
            ))
        }
        return image
    }
}
