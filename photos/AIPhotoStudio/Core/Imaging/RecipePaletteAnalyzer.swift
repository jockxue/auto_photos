import CoreImage
import Foundation

enum RecipePaletteAnalyzer {
    /// Hue is stored on a 0...1 circle. 40° keeps a color at a bin center
    /// overlapping its neighbors, instead of a hard 30° cutoff.
    private static let hueHalfWidth = 40.0 / 360.0
    private static let minimumChroma = 0.05
    private static let hueCenters = [0.0, 30, 60, 120, 180, 240, 270, 300].map { $0 / 360 }

    static func analyze(image: CIImage) async throws -> ReferencePalette {
        let samples = try await Task.detached(priority: .userInitiated) {
            try RecipeAnalyzer.rasterize(image)
        }.value
        return analyze(samples: samples.pixels)
    }

    static func analyze(samples: [RecipeSample]) -> ReferencePalette {
        var bins = Array(repeating: BinAccumulator(), count: hueCenters.count)
        for sample in samples {
            let hsl = hslComponents(sample)
            guard hsl.saturation >= minimumChroma else { continue }
            for index in hueCenters.indices {
                let weight = softWeight(hue: hsl.hue, center: hueCenters[index])
                guard weight > 0 else { continue }
                bins[index].add(hsl, weight: weight)
            }
        }

        let totalWeight = bins.reduce(0) { $0 + $1.weight }
        var means = bins.map { $0.mean() }
        if totalWeight > 0 {
            for index in means.indices {
                means[index].pixelRatio = bins[index].weight / totalWeight
            }
            for sample in samples {
                let hsl = hslComponents(sample)
                guard hsl.saturation >= minimumChroma else { continue }
                for index in hueCenters.indices {
                    let weight = softWeight(hue: hsl.hue, center: hueCenters[index])
                    guard weight > 0 else { continue }
                    means[index].addVariance(hsl, weight: weight, binWeight: bins[index].weight)
                }
            }
        }

        return ReferencePalette(bins: zip(hueCenters, means).map { center, mean in
            PaletteBin(
                hueCenter: center,
                saturation: mean.saturation,
                luminance: mean.lightness,
                pixelRatio: mean.pixelRatio,
                hueVariance: mean.hueVariance,
                saturationVariance: mean.saturationVariance,
                luminanceVariance: mean.lightnessVariance
            )
        })
    }

    static func circularHueDistance(_ first: Double, _ second: Double) -> Double {
        let delta = abs(first - second).truncatingRemainder(dividingBy: 1)
        return min(delta, 1 - delta)
    }

    private static func softWeight(hue: Double, center: Double) -> Double {
        let distance = circularHueDistance(hue, center)
        guard distance < hueHalfWidth else { return 0 }
        return 1 - distance / hueHalfWidth
    }

    private static func hslComponents(_ sample: RecipeSample) -> HSL {
        let red = min(max(sample.red, 0), 1)
        let green = min(max(sample.green, 0), 1)
        let blue = min(max(sample.blue, 0), 1)
        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        let delta = maxChannel - minChannel
        let lightness = (maxChannel + minChannel) / 2
        guard delta > 0 else { return HSL(hue: 0, saturation: 0, lightness: lightness) }

        let saturation = lightness > 0.5
            ? delta / (2 - maxChannel - minChannel)
            : delta / (maxChannel + minChannel)
        let hue: Double
        switch maxChannel {
        case red:
            hue = (green - blue) / delta + (green < blue ? 6 : 0)
        case green:
            hue = (blue - red) / delta + 2
        default:
            hue = (red - green) / delta + 4
        }
        return HSL(hue: (hue / 6).truncatingRemainder(dividingBy: 1), saturation: saturation, lightness: lightness)
    }

    private struct HSL {
        var hue: Double
        var saturation: Double
        var lightness: Double
    }

    private struct BinAccumulator {
        var weight = 0.0
        var weightedSaturation = 0.0
        var weightedLightness = 0.0
        var sumSin = 0.0
        var sumCos = 0.0

        mutating func add(_ hsl: HSL, weight sampleWeight: Double) {
            let angle = hsl.hue * 2 * Double.pi
            weight += sampleWeight
            weightedSaturation += hsl.saturation * sampleWeight
            weightedLightness += hsl.lightness * sampleWeight
            sumSin += sin(angle) * sampleWeight
            sumCos += cos(angle) * sampleWeight
        }

        func mean() -> BinMean {
            guard weight > 0 else { return BinMean() }
            var hue = atan2(sumSin, sumCos) / (2 * Double.pi)
            if hue < 0 { hue += 1 }
            return BinMean(
                hue: hue,
                saturation: weightedSaturation / weight,
                lightness: weightedLightness / weight
            )
        }
    }

    private struct BinMean {
        var hue = 0.0
        var saturation = 0.0
        var lightness = 0.0
        var pixelRatio = 0.0
        var hueVariance = 0.0
        var saturationVariance = 0.0
        var lightnessVariance = 0.0

        mutating func addVariance(_ hsl: HSL, weight sampleWeight: Double, binWeight: Double) {
            guard binWeight > 0 else { return }
            let hueDistance = RecipePaletteAnalyzer.circularHueDistance(hsl.hue, hue)
            hueVariance += sampleWeight * hueDistance * hueDistance / binWeight
            let saturationDelta = hsl.saturation - saturation
            saturationVariance += sampleWeight * saturationDelta * saturationDelta / binWeight
            let lightnessDelta = hsl.lightness - lightness
            lightnessVariance += sampleWeight * lightnessDelta * lightnessDelta / binWeight
        }
    }
}

#if DEBUG
extension RecipePaletteAnalyzer {
    static func debugSummary(_ palette: ReferencePalette) -> String {
        let names = ["Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "Magenta"]
        return zip(names, palette.bins).map { name, bin in
            "\(name): ratio=\(bin.pixelRatio) S=\(bin.saturation) L=\(bin.luminance) hueVariance=\(bin.hueVariance)"
        }.joined(separator: "\n")
    }
}
#endif
