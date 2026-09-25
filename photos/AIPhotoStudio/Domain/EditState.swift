import CoreGraphics
import Foundation

enum AdjustmentCategory: String, CaseIterable, Hashable, Sendable {
    case light = "Light"
    case color = "Color"
    case detail = "Detail"
}

enum AdjustmentDisplayFormat: Sendable {
    case exposure
    case signedInteger
    case unsignedInteger
    case temperature

    func string(for value: Double) -> String {
        switch self {
        case .exposure: String(format: "%+.2f EV", value)
        case .signedInteger: String(format: "%+.0f", value)
        case .unsignedInteger: String(format: "%.0f", value)
        case .temperature: String(format: "%+.0f", value)
        }
    }
}

struct AdjustmentDescriptor: Sendable {
    let key: AdjustmentKey
    let title: String
    let category: AdjustmentCategory
    let range: ClosedRange<Double>
    let defaultValue: Double
    let displayFormat: AdjustmentDisplayFormat

    func displayValue(_ value: Double) -> String {
        displayFormat.string(for: value)
    }
}

struct Adjustments: Codable, Equatable, Sendable {
    var exposure = 0.0
    var brightness = 0.0
    var contrast = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var whites = 0.0
    var blacks = 0.0
    var temperature = 0.0
    var tint = 0.0
    var saturation = 0.0
    var vibrance = 0.0
    var sharpness = 0.0
    var clarity = 0.0
    var noiseReduction = 0.0
    var grain = 0.0

    private enum CodingKeys: String, CodingKey {
        case exposure, brightness, contrast, highlights, shadows, whites, blacks
        case temperature, tint, saturation, vibrance, sharpness, clarity, noiseReduction, grain
        case warmth, definition, blackPoint
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys) -> Double {
            (try? values.decodeIfPresent(Double.self, forKey: key)) ?? 0
        }
        exposure = value(.exposure)
        brightness = value(.brightness)
        contrast = value(.contrast)
        highlights = value(.highlights)
        shadows = value(.shadows)
        whites = value(.whites)
        blacks = (try? values.decodeIfPresent(Double.self, forKey: .blacks))
            ?? (try? values.decodeIfPresent(Double.self, forKey: .blackPoint))
            ?? 0
        temperature = (try? values.decodeIfPresent(Double.self, forKey: .temperature))
            ?? (try? values.decodeIfPresent(Double.self, forKey: .warmth))
            ?? 0
        tint = value(.tint)
        saturation = value(.saturation)
        vibrance = value(.vibrance)
        sharpness = value(.sharpness)
        clarity = (try? values.decodeIfPresent(Double.self, forKey: .clarity))
            ?? (try? values.decodeIfPresent(Double.self, forKey: .definition))
            ?? 0
        noiseReduction = value(.noiseReduction)
        grain = value(.grain)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        for key in AdjustmentKey.allCases {
            try values.encode(self[key], forKey: CodingKeys(stringValue: key.rawValue)!)
        }
    }

    subscript(_ key: AdjustmentKey) -> Double {
        get {
            switch key {
            case .exposure: exposure
            case .brightness: brightness
            case .contrast: contrast
            case .highlights: highlights
            case .shadows: shadows
            case .whites: whites
            case .blacks: blacks
            case .temperature: temperature
            case .tint: tint
            case .saturation: saturation
            case .vibrance: vibrance
            case .sharpness: sharpness
            case .clarity: clarity
            case .noiseReduction: noiseReduction
            case .grain: grain
            }
        }
        set {
            let range = key.descriptor.range
            let value = min(max(newValue, range.lowerBound), range.upperBound)
            switch key {
            case .exposure: exposure = value
            case .brightness: brightness = value
            case .contrast: contrast = value
            case .highlights: highlights = value
            case .shadows: shadows = value
            case .whites: whites = value
            case .blacks: blacks = value
            case .temperature: temperature = value
            case .tint: tint = value
            case .saturation: saturation = value
            case .vibrance: vibrance = value
            case .sharpness: sharpness = value
            case .clarity: clarity = value
            case .noiseReduction: noiseReduction = value
            case .grain: grain = value
            }
        }
    }
}

enum AdjustmentKey: String, CaseIterable, Codable, Identifiable, Sendable {
    case exposure, brightness, contrast, highlights, shadows, whites, blacks
    case temperature, tint, saturation, vibrance
    case sharpness, clarity, noiseReduction, grain

    var id: String { rawValue }
    var descriptor: AdjustmentDescriptor {
        switch self {
        case .exposure: .init(key: self, title: "Exposure", category: .light, range: -2...2, defaultValue: 0, displayFormat: .exposure)
        case .brightness: .init(key: self, title: "Brightness", category: .light, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .contrast: .init(key: self, title: "Contrast", category: .light, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .highlights: .init(key: self, title: "Highlights", category: .light, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .shadows: .init(key: self, title: "Shadows", category: .light, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .whites: .init(key: self, title: "Whites", category: .light, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .blacks: .init(key: self, title: "Blacks", category: .light, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .temperature: .init(key: self, title: "Temperature", category: .color, range: -100...100, defaultValue: 0, displayFormat: .temperature)
        case .tint: .init(key: self, title: "Tint", category: .color, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .saturation: .init(key: self, title: "Saturation", category: .color, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .vibrance: .init(key: self, title: "Vibrance", category: .color, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .sharpness: .init(key: self, title: "Sharpness", category: .detail, range: 0...100, defaultValue: 0, displayFormat: .unsignedInteger)
        case .clarity: .init(key: self, title: "Clarity", category: .detail, range: -100...100, defaultValue: 0, displayFormat: .signedInteger)
        case .noiseReduction: .init(key: self, title: "Noise Reduction", category: .detail, range: 0...100, defaultValue: 0, displayFormat: .unsignedInteger)
        case .grain: .init(key: self, title: "Grain", category: .detail, range: 0...100, defaultValue: 0, displayFormat: .unsignedInteger)
        }
    }

    var range: ClosedRange<Double> { descriptor.range }
    var title: String { descriptor.title }
}

struct NormalizedRect: Codable, Equatable, Sendable {
    var x = 0.0
    var y = 0.0
    var width = 1.0
    var height = 1.0

    var clamped: NormalizedRect {
        let safeWidth = min(max(width, 0.01), 1)
        let safeHeight = min(max(height, 0.01), 1)
        return NormalizedRect(
            x: min(max(x, 0), 1 - safeWidth),
            y: min(max(y, 0), 1 - safeHeight),
            width: safeWidth,
            height: safeHeight
        )
    }
}

typealias Crop = NormalizedRect

enum CropAspectRatio: String, CaseIterable, Codable, Hashable, Sendable {
    case free, original, square, landscapeFourThree, portraitThreeFour
    case landscapeSixteenNine, portraitNineSixteen

    var ratio: Double? {
        switch self {
        case .free, .original: nil
        case .square: 1
        case .landscapeFourThree: 4.0 / 3.0
        case .portraitThreeFour: 3.0 / 4.0
        case .landscapeSixteenNine: 16.0 / 9.0
        case .portraitNineSixteen: 9.0 / 16.0
        }
    }

    var title: String {
        switch self {
        case .free: "Free"
        case .original: "Original"
        case .square: "1:1"
        case .landscapeFourThree: "4:3"
        case .portraitThreeFour: "3:4"
        case .landscapeSixteenNine: "16:9"
        case .portraitNineSixteen: "9:16"
        }
    }
}

struct CropState: Codable, Equatable, Sendable {
    var normalizedRect = NormalizedRect()
    var quarterTurns = 0
    var fineRotationDegrees = 0.0
    var aspectRatio = CropAspectRatio.free
    var isFlippedHorizontally = false
    var isFlippedVertically = false

    /// Compatibility with the phase-one geometry contract.
    var crop: Crop {
        get { normalizedRect }
        set { normalizedRect = newValue.clamped }
    }

    var rotationDegrees: Double {
        get { Double(quarterTurns) * 90 + fineRotationDegrees }
        set {
            let turns = Int((newValue / 90).rounded())
            quarterTurns = ((turns % 4) + 4) % 4
            fineRotationDegrees = min(max(newValue - Double(turns) * 90, -45), 45)
        }
    }

    mutating func rotateLeft() {
        quarterTurns = (quarterTurns + 3) % 4
    }

    mutating func rotateRight() {
        quarterTurns = (quarterTurns + 1) % 4
    }

    private enum CodingKeys: String, CodingKey {
        case normalizedRect, crop, rotationDegrees, quarterTurns, fineRotationDegrees, aspectRatio
        case isFlippedHorizontally, isFlippedVertically
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        normalizedRect = try values.decodeIfPresent(NormalizedRect.self, forKey: .normalizedRect)
            ?? values.decodeIfPresent(NormalizedRect.self, forKey: .crop)
            ?? .init()
        if let storedTurns = try values.decodeIfPresent(Int.self, forKey: .quarterTurns) {
            quarterTurns = ((storedTurns % 4) + 4) % 4
            fineRotationDegrees = min(max(
                try values.decodeIfPresent(Double.self, forKey: .fineRotationDegrees) ?? 0,
                -45
            ), 45)
        } else {
            let angle = try values.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
            let turns = Int((angle / 90).rounded())
            quarterTurns = ((turns % 4) + 4) % 4
            fineRotationDegrees = min(max(angle - Double(turns) * 90, -45), 45)
        }
        aspectRatio = try values.decodeIfPresent(CropAspectRatio.self, forKey: .aspectRatio) ?? .free
        isFlippedHorizontally = try values.decodeIfPresent(Bool.self, forKey: .isFlippedHorizontally) ?? false
        isFlippedVertically = try values.decodeIfPresent(Bool.self, forKey: .isFlippedVertically) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(normalizedRect, forKey: .normalizedRect)
        try values.encode(rotationDegrees, forKey: .rotationDegrees)
        try values.encode(quarterTurns, forKey: .quarterTurns)
        try values.encode(fineRotationDegrees, forKey: .fineRotationDegrees)
        try values.encode(aspectRatio, forKey: .aspectRatio)
        try values.encode(isFlippedHorizontally, forKey: .isFlippedHorizontally)
        try values.encode(isFlippedVertically, forKey: .isFlippedVertically)
    }
}

typealias GeometryEdits = CropState

enum CropLayout {
    static func rect(
        for preset: CropAspectRatio,
        sourceAspectRatio: Double
    ) -> NormalizedRect {
        let target = preset == .original ? sourceAspectRatio : preset.ratio
        guard let target, target > 0 else { return .init() }
        if target >= sourceAspectRatio {
            let height = sourceAspectRatio / target
            return NormalizedRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        } else {
            let width = target / sourceAspectRatio
            return NormalizedRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }
    }
}

struct FilterConfig: Codable, Equatable, Sendable {
    var identifier: String
    /// 0 is bypass, 100 is the full configured effect.
    var intensity: Double

    init(identifier: String, intensity: Double = 100) {
        self.identifier = identifier
        self.intensity = min(max(intensity, 0), 100)
    }
}

typealias FilterSelection = FilterConfig

/// The complete, serializable edit recipe. Original pixels are never mutated.
struct EditState: Codable, Equatable, Sendable {
    var adjustments = Adjustments()
    var geometry = GeometryEdits()
    var filter: FilterSelection?
}
