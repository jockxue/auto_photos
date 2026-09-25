import CoreGraphics
import Foundation

/// Every adjustment is normalized to `-1...1` (or `0...1` where noted).
/// This keeps the domain model independent from a particular render backend.
struct Adjustments: Codable, Equatable, Sendable {
    var exposure = 0.0
    var brilliance = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var contrast = 0.0
    var brightness = 0.0
    var blackPoint = 0.0
    var saturation = 0.0
    var vibrance = 0.0
    var warmth = 0.0
    var tint = 0.0
    var sharpness = 0.0
    var definition = 0.0
    var noiseReduction = 0.0
    var vignette = 0.0

    subscript(_ key: AdjustmentKey) -> Double {
        get {
            switch key {
            case .exposure: exposure
            case .brilliance: brilliance
            case .highlights: highlights
            case .shadows: shadows
            case .contrast: contrast
            case .brightness: brightness
            case .blackPoint: blackPoint
            case .saturation: saturation
            case .vibrance: vibrance
            case .warmth: warmth
            case .tint: tint
            case .sharpness: sharpness
            case .definition: definition
            case .noiseReduction: noiseReduction
            case .vignette: vignette
            }
        }
        set {
            let value = min(max(newValue, key.range.lowerBound), key.range.upperBound)
            switch key {
            case .exposure: exposure = value
            case .brilliance: brilliance = value
            case .highlights: highlights = value
            case .shadows: shadows = value
            case .contrast: contrast = value
            case .brightness: brightness = value
            case .blackPoint: blackPoint = value
            case .saturation: saturation = value
            case .vibrance: vibrance = value
            case .warmth: warmth = value
            case .tint: tint = value
            case .sharpness: sharpness = value
            case .definition: definition = value
            case .noiseReduction: noiseReduction = value
            case .vignette: vignette = value
            }
        }
    }
}

enum AdjustmentKey: String, CaseIterable, Codable, Identifiable, Sendable {
    case exposure, brilliance, highlights, shadows, contrast, brightness
    case blackPoint, saturation, vibrance, warmth, tint, sharpness
    case definition, noiseReduction, vignette

    var id: String { rawValue }
    var range: ClosedRange<Double> {
        switch self {
        case .noiseReduction, .vignette: 0...1
        default: -1...1
        }
    }

    var title: String {
        switch self {
        case .blackPoint: "Black Point"
        case .noiseReduction: "Noise Reduction"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

struct Crop: Codable, Equatable, Sendable {
    /// Unit-space rect, so edits remain valid for full-resolution re-renders.
    var x = 0.0
    var y = 0.0
    var width = 1.0
    var height = 1.0
}

struct GeometryEdits: Codable, Equatable, Sendable {
    var crop = Crop()
    var rotationDegrees = 0.0
    var isFlippedHorizontally = false
    var isFlippedVertically = false
}

struct FilterSelection: Codable, Equatable, Sendable {
    var identifier: String
    var intensity: Double
}

/// The complete, serializable edit recipe. Original pixels are never mutated.
struct EditState: Codable, Equatable, Sendable {
    var adjustments = Adjustments()
    var geometry = GeometryEdits()
    var filter: FilterSelection?
}
