import Foundation

struct RecipeColorCube: Equatable, Sendable {
    var dimension: Int
    /// RGBA floats. Red changes fastest, then green, then blue, matching `CIColorCube`.
    var samples: [Float]
}

enum RecipeColorCubeBuilder {
    static let defaultDimension = 33

    static func build(_ mapping: ColorMapping, dimension: Int = defaultDimension) -> RecipeColorCube {
        let safeDimension = max(dimension, 2)
        let scale = Double(safeDimension - 1)
        var samples: [Float] = []
        samples.reserveCapacity(safeDimension * safeDimension * safeDimension * 4)
        for blue in 0..<safeDimension {
            for green in 0..<safeDimension {
                for red in 0..<safeDimension {
                    let mapped = map(
                        ColorSpace.RGBColor(
                            red: Double(red) / scale,
                            green: Double(green) / scale,
                            blue: Double(blue) / scale
                        ),
                        through: mapping
                    )
                    samples.append(Float(mapped.red))
                    samples.append(Float(mapped.green))
                    samples.append(Float(mapped.blue))
                    samples.append(1)
                }
            }
        }
        return RecipeColorCube(dimension: safeDimension, samples: samples)
    }

    /// Maps one color with the same blend used to fill the cube.
    static func map(_ rgb: ColorSpace.RGBColor, through mapping: ColorMapping) -> ColorSpace.RGBColor {
        let safe = ColorSpace.RGBColor(
            red: unit(rgb.red),
            green: unit(rgb.green),
            blue: unit(rgb.blue)
        )
        let hsl = ColorSpace.hsl(from: safe)
        let shift = shift(for: hsl, mapping: mapping)
        let chroma = chromaGate(hsl.saturation)
        return ColorSpace.rgb(from: ColorSpace.HSLColor(
            hue: ColorSpace.normalizeHue(hsl.hue + shift.hue * chroma),
            saturation: clampUnit(hsl.saturation + shift.saturation * chroma),
            lightness: clampUnit(hsl.lightness + shift.lightness)
        ))
    }

    /// `sourceHue` is the measured hue of the photo region. `hueCenter` is the
    /// reference region's measured hue and is not the interpolation anchor.
    /// Offsets blend as sum(delta × spatial × mappingWeight) / sum(spatial),
    /// so one centered region scales by mappingWeight and neighbors average
    /// instead of stacking.
    private static func shift(
        for hsl: ColorSpace.HSLColor,
        mapping: ColorMapping
    ) -> (hue: Double, saturation: Double, lightness: Double) {
        var hueShift = 0.0
        var saturationShift = 0.0
        var lightnessShift = 0.0
        var spatialTotal = 0.0
        for bin in mapping.bins {
            guard bin.mappingWeight.isFinite, bin.mappingWeight > 0 else { continue }
            let spatial = spatialWeight(inputHue: hsl.hue, regionHue: bin.sourceHue)
            guard spatial > 0 else { continue }
            let weight = min(bin.mappingWeight, 1) * spatial
            hueShift += finite(bin.hueDelta) * weight
            saturationShift += finite(bin.saturationDelta) * weight
            lightnessShift += finite(bin.luminanceDelta) * weight
            spatialTotal += spatial
        }
        guard spatialTotal > 0 else { return (0, 0, 0) }
        return (hueShift / spatialTotal, saturationShift / spatialTotal, lightnessShift / spatialTotal)
    }

    /// Smooth falloff across 40°, the same half-width used to assign palette bins.
    /// Regions are not equally spaced, so the kernel uses circular distance.
    private static func spatialWeight(inputHue: Double, regionHue: Double) -> Double {
        let distance = ColorSpace.circularHueDistance(inputHue, regionHue)
        let t = min(max(1 - distance / kernelHalfWidth, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Near-gray hues are unstable, so chromatic shifts fade out below this band.
    private static func chromaGate(_ saturation: Double) -> Double {
        let t = min(max((saturation - 0.02) / 0.06, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static let kernelHalfWidth = 40.0 / 360.0

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? clampUnit(value) : 0
    }

    private static func clampUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}
