import Foundation

enum ColorSpace {
    struct RGBColor: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    struct HSLColor: Equatable, Sendable {
        var hue: Double
        var saturation: Double
        var lightness: Double
    }

    static func hsl(from rgb: RGBColor) -> HSLColor {
        let red = min(max(rgb.red, 0), 1)
        let green = min(max(rgb.green, 0), 1)
        let blue = min(max(rgb.blue, 0), 1)
        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        let delta = maxChannel - minChannel
        let lightness = (maxChannel + minChannel) / 2
        guard delta > 0 else { return HSLColor(hue: 0, saturation: 0, lightness: lightness) }

        let saturation = lightness > 0.5
            ? delta / (2 - maxChannel - minChannel)
            : delta / (maxChannel + minChannel)
        let sector: Double
        switch maxChannel {
        case red:
            sector = (green - blue) / delta + (green < blue ? 6 : 0)
        case green:
            sector = (blue - red) / delta + 2
        default:
            sector = (red - green) / delta + 4
        }
        return HSLColor(
            hue: normalizeHue(sector / 6),
            saturation: saturation,
            lightness: lightness
        )
    }

    static func rgb(from hsl: HSLColor) -> RGBColor {
        let hue = normalizeHue(hsl.hue)
        let saturation = min(max(hsl.saturation, 0), 1)
        let lightness = min(max(hsl.lightness, 0), 1)
        guard saturation > 0 else {
            return RGBColor(red: lightness, green: lightness, blue: lightness)
        }

        let chromaRange = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let base = 2 * lightness - chromaRange
        return RGBColor(
            red: channel(hue + 1.0 / 3.0, base: base, peak: chromaRange),
            green: channel(hue, base: base, peak: chromaRange),
            blue: channel(hue - 1.0 / 3.0, base: base, peak: chromaRange)
        )
    }

    static func circularHueDistance(_ first: Double, _ second: Double) -> Double {
        abs(signedCircularHueDelta(from: first, to: second))
    }

    /// Shortest signed turn from `source` to `destination`, in -0.5...0.5.
    static func signedCircularHueDelta(from source: Double, to destination: Double) -> Double {
        var delta = normalizeHue(destination) - normalizeHue(source)
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        return delta
    }

    static func circularHueMean(_ values: [(hue: Double, weight: Double)]) -> Double {
        var sumSin = 0.0
        var sumCos = 0.0
        for value in values where value.weight != 0 {
            let angle = normalizeHue(value.hue) * 2 * Double.pi
            sumSin += sin(angle) * value.weight
            sumCos += cos(angle) * value.weight
        }
        return circularHueMean(sumSin: sumSin, sumCos: sumCos)
    }

    static func circularHueMean(sumSin: Double, sumCos: Double) -> Double {
        guard sumSin != 0 || sumCos != 0 else { return 0 }
        return normalizeHue(atan2(sumSin, sumCos) / (2 * Double.pi))
    }

    static func normalizeHue(_ hue: Double) -> Double {
        let wrapped = hue.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }

    private static func channel(_ hue: Double, base: Double, peak: Double) -> Double {
        var position = hue
        if position < 0 { position += 1 }
        if position > 1 { position -= 1 }
        if position < 1.0 / 6.0 { return base + (peak - base) * 6 * position }
        if position < 0.5 { return peak }
        if position < 2.0 / 3.0 { return base + (peak - base) * (2.0 / 3.0 - position) * 6 }
        return base
    }
}
