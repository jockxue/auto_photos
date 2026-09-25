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

    func process(
        original: CIImage,
        orientation: CGImagePropertyOrientation,
        edits: EditState
    ) -> CIImage {
        let oriented = original.oriented(orientation)
        return processors.reduce(oriented) { $1.process($0, edits: edits) }
    }
}

private struct GeometryProcessor: RenderStageProcessor {
    let stage = RenderStage.geometry

    func process(_ source: CIImage, edits: EditState) -> CIImage {
        let geometry = edits.geometry
        let extent = source.extent
        let crop = geometry.normalizedRect.clamped
        var image = source.cropped(to: CGRect(
            x: extent.minX + extent.width * crop.x,
            y: extent.minY + extent.height * crop.y,
            width: extent.width * crop.width,
            height: extent.height * crop.height
        ).intersection(extent))

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
        return image
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
        image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": 1 - value.highlights / 140,
            "inputShadowAmount": value.shadows / 100
        ])
        let black = value.blacks / 500
        let white = value.whites / 500
        return image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: black),
            "inputPoint1": CIVector(x: 0.25, y: 0.25),
            "inputPoint2": CIVector(x: 0.5, y: 0.5),
            "inputPoint3": CIVector(x: 0.75, y: 0.75),
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
        return image.applyingFilter("CIVibrance", parameters: [
            "inputAmount": value.vibrance / 100
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
        if value.clarity != 0 {
            image = image.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 2.5,
                kCIInputIntensityKey: value.clarity / 100
            ])
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
