import Foundation

struct ColorMappingBin: Codable, Equatable, Sendable {
    var hueCenter: Double
    /// Hue of this region in the photo being edited.
    var sourceHue: Double
    var sourceSaturation: Double
    var sourceLuminance: Double
    /// Hue of the same region in the reference photo.
    var targetHue: Double
    var targetSaturation: Double
    var targetLuminance: Double
    var hueDelta: Double
    var saturationDelta: Double
    var luminanceDelta: Double
    var mappingWeight: Double
}

struct ColorMapping: Codable, Equatable, Sendable {
    var bins: [ColorMappingBin]
}

enum ColorMappingBuilder {
    /// `reference` is the sample look. `target` is the photo being edited.
    /// Mapping direction is target photo color → reference color.
    static func build(reference: ReferencePalette, target: ReferencePalette) -> ColorMapping {
        ColorMapping(bins: reference.bins.enumerated().map { index, referenceBin in
            let targetBin = index < target.bins.count ? target.bins[index] : nil
            return bin(reference: referenceBin, target: targetBin)
        })
    }

    static func presence(for pixelRatio: Double) -> Double {
        let t = min(max((pixelRatio - presenceFloor) / (presenceCeiling - presenceFloor), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// `hueVariance` is the mean squared circular distance, where 1 is a full turn.
    /// The largest possible value is 0.25, so confidence uses that as the 0...1 scale.
    static func hueConfidence(for hueVariance: Double) -> Double {
        let normalized = min(max(hueVariance, 0), maximumHueVariance) / maximumHueVariance
        return 1 / (1 + normalized)
    }

    private static let presenceFloor = 0.02
    private static let presenceCeiling = 0.08
    private static let maximumHueVariance = 0.25

    private static func bin(reference: PaletteBin, target: PaletteBin?) -> ColorMappingBin {
        let source = target ?? reference
        let active = reference.pixelRatio > 0 && (target?.pixelRatio ?? 0) > 0
        let sourceHue = active ? source.hueCenter : reference.hueCenter
        let targetHue = active ? reference.hueCenter : reference.hueCenter
        let sourceSaturation = active ? source.saturation : 0
        let sourceLuminance = active ? source.luminance : 0
        let targetSaturation = active ? reference.saturation : 0
        let targetLuminance = active ? reference.luminance : 0
        let hueDelta = active ? ColorSpace.signedCircularHueDelta(from: sourceHue, to: targetHue) : 0
        let saturationDelta = active ? targetSaturation - sourceSaturation : 0
        let luminanceDelta = active ? targetLuminance - sourceLuminance : 0
        let variance = max(reference.hueVariance, source.hueVariance)
        let weight = active
            ? min(max(
                presence(for: source.pixelRatio)
                    * presence(for: reference.pixelRatio)
                    * hueConfidence(for: variance),
                0
            ), 1)
            : 0
        return ColorMappingBin(
            hueCenter: reference.hueCenter,
            sourceHue: sourceHue,
            sourceSaturation: sourceSaturation,
            sourceLuminance: sourceLuminance,
            targetHue: targetHue,
            targetSaturation: targetSaturation,
            targetLuminance: targetLuminance,
            hueDelta: hueDelta,
            saturationDelta: saturationDelta,
            luminanceDelta: luminanceDelta,
            mappingWeight: weight
        )
    }
}
