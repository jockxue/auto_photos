import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum RenderStage: String, CaseIterable, Codable, Sendable {
    case orientation, geometry, light, color, detail, filter, local, ai
}

protocol RenderStageProcessor: Sendable {
    var stage: RenderStage { get }
    func process(_ image: CIImage, edits: EditState) -> CIImage
}

struct RenderPipeline: Sendable {
    static let stageOrder = RenderStage.allCases
    private let processors: [any RenderStageProcessor]

    init(filterEngine: any FilterEngineProtocol = CoreImageFilterEngine()) {
        processors = [
            GeometryProcessor(),
            LightProcessor(),
            ColorProcessor(),
            DetailProcessor(),
            FilterProcessor(engine: filterEngine),
            PlaceholderProcessor(stage: .local),
            PlaceholderProcessor(stage: .ai)
        ]
    }

    var configuredStages: [RenderStage] {
        [.orientation] + processors.map { $0.stage }
    }

    func process(
        original: CIImage,
        orientation: CGImagePropertyOrientation,
        edits: EditState
    ) -> CIImage {
        let oriented = original.oriented(orientation)
        return processors.reduce(oriented) { $1.process($0, edits: edits) }
    }
}

enum AdjustmentMapping {
    static func highlightShadow(_ values: Adjustments) -> (highlight: Double, shadow: Double) {
        (
            1 - max(0, values.highlights) / 100,
            max(0, values.shadows) / 100
        )
    }

    static func clarity(_ value: Double) -> (unsharpIntensity: Double, blurRadius: Double) {
        if value >= 0 {
            return (min(value / 100, 1), 0)
        }
        return (0, min(abs(value) / 100 * 1.5, 1.5))
    }
}

private struct GeometryProcessor: RenderStageProcessor {
    let stage = RenderStage.geometry

    func process(_ source: CIImage, edits: EditState) -> CIImage {
        let geometry = edits.geometry
        var image = source
        if geometry.rotationDegrees != 0 {
            image = image.transformed(by: CGAffineTransform(
                rotationAngle: geometry.rotationDegrees * .pi / 180
            ))
        }
        if geometry.isFlippedHorizontally || geometry.isFlippedVertically {
            let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .scaledBy(
                    x: geometry.isFlippedHorizontally ? -1 : 1,
                    y: geometry.isFlippedVertically ? -1 : 1
                )
                .translatedBy(x: -center.x, y: -center.y)
            image = image.transformed(by: transform)
        }
        let extent = image.extent
        let crop = geometry.normalizedRect.clamped
        return image.cropped(to: CGRect(
            x: extent.minX + extent.width * crop.x,
            y: extent.minY + extent.height * crop.y,
            width: extent.width * crop.width,
            height: extent.height * crop.height
        ).intersection(extent))
    }
}

private struct LightProcessor: RenderStageProcessor {
    let stage = RenderStage.light

    func process(_ source: CIImage, edits: EditState) -> CIImage {
        let value = edits.adjustments
        var image = source.applyingFilter("CIExposureAdjust", parameters: ["inputEV": value.exposure])
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: value.brightness / 400,
            kCIInputContrastKey: 1 + value.contrast / 200
        ])
        let highlightShadow = AdjustmentMapping.highlightShadow(value)
        image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": highlightShadow.highlight,
            "inputShadowAmount": highlightShadow.shadow
        ])
        let black = value.blacks / 500
        let white = value.whites / 500
        let shadowPoint = 0.25 + min(0, value.shadows) / 500
        let highlightPoint = 0.75 - min(0, value.highlights) / 500
        return image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: black),
            "inputPoint1": CIVector(x: 0.25, y: shadowPoint),
            "inputPoint2": CIVector(x: 0.5, y: 0.5),
            "inputPoint3": CIVector(x: 0.75, y: highlightPoint),
            "inputPoint4": CIVector(x: 1, y: 1 + white)
        ])
    }
}

private struct ColorProcessor: RenderStageProcessor {
    let stage = RenderStage.color

    func process(_ source: CIImage, edits: EditState) -> CIImage {
        let value = edits.adjustments
        var image = source.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(
                x: 6500 + value.temperature * 25,
                y: value.tint
            )
        ])
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: max(0, 1 + value.saturation / 100)
        ])
        image = image.applyingFilter("CIVibrance", parameters: [
            "inputAmount": value.vibrance / 100
        ])
        return CurveRenderer.apply(edits.curves, to: image)
    }
}

enum CurveRenderer {
    static func apply(_ curves: CurveAdjustment, to image: CIImage) -> CIImage {
        guard !curves.isIdentity else { return image }
        let dimension = 33
        let scale = Double(dimension - 1)
        var samples = [Float]()
        samples.reserveCapacity(dimension * dimension * dimension * 4)
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    let mapped = curves.lookup(
                        red: Double(red) / scale,
                        green: Double(green) / scale,
                        blue: Double(blue) / scale
                    )
                    samples.append(Float(mapped.0))
                    samples.append(Float(mapped.1))
                    samples.append(Float(mapped.2))
                    samples.append(1)
                }
            }
        }
        let data = samples.withUnsafeBytes { Data($0) }
        return image.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": data
        ])
    }
}

private struct DetailProcessor: RenderStageProcessor {
    let stage = RenderStage.detail

    func process(_ source: CIImage, edits: EditState) -> CIImage {
        let value = edits.adjustments
        var image = source
        if value.sharpness > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [
                "inputSharpness": value.sharpness / 50
            ])
        }
        let clarity = AdjustmentMapping.clarity(value.clarity)
        if clarity.unsharpIntensity > 0 {
            image = image.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 2.5,
                kCIInputIntensityKey: clarity.unsharpIntensity
            ])
        } else if clarity.blurRadius > 0 {
            let extent = image.extent
            image = image.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: clarity.blurRadius
            ]).cropped(to: extent)
        }
        if value.noiseReduction > 0 {
            image = image.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": value.noiseReduction / 2000,
                "inputSharpness": 0.4
            ])
        }
        if value.grain > 0 {
            guard let noiseSource = CIFilter(name: "CIRandomGenerator")?.outputImage else {
                return image
            }
            let noise = noiseSource
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0,
                    kCIInputContrastKey: 1.2
                ])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: value.grain / 500)
                ])
                .cropped(to: image.extent)
            image = noise.applyingFilter("CIOverlayBlendMode", parameters: [
                kCIInputBackgroundImageKey: image
            ]).cropped(to: image.extent)
        }
        return image
    }
}

private struct FilterProcessor: RenderStageProcessor {
    let stage = RenderStage.filter
    let engine: any FilterEngineProtocol

    func process(_ image: CIImage, edits: EditState) -> CIImage {
        engine.apply(edits.filter, to: image)
    }
}

/// Typed boundaries for future local-mask and AI stages. They are intentional
/// no-ops until those domains produce a real operation; no CIFilter is invented.
private struct PlaceholderProcessor: RenderStageProcessor {
    let stage: RenderStage
    func process(_ image: CIImage, edits: EditState) -> CIImage { image }
}
