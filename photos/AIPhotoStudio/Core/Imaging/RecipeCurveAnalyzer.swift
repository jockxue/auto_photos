import Foundation

enum RecipeCurveAnalyzer {
    /// A conservative RGB curve. Red, green, and blue stay on the identity line.
    static func curve(for samples: [RecipeSample]) -> CurveAdjustment {
        let tone = RecipeToneAnalyzer.distribution(of: samples.map(\.luminance))
        var curve = ChannelCurve.identity
        curve.setPoint(at: 1, y: 0.25 + clamp((tone.p25 - 0.22) * 0.28, -0.06, 0.06))
        curve.setPoint(at: 2, y: 0.50 + clamp((tone.p50 - 0.45) * 0.22, -0.05, 0.05))
        curve.setPoint(at: 3, y: 0.75 + clamp((tone.p75 - 0.68) * 0.22, -0.05, 0.05))
        curve.points = monotone(curve.points)
        var adjustment = CurveAdjustment()
        adjustment.rgb = curve
        return adjustment
    }

    static func isMonotone(_ curve: ChannelCurve) -> Bool {
        let points = curve.points.sorted { $0.x < $1.x }
        for index in 1..<points.count where points[index].y + 0.000_001 < points[index - 1].y {
            return false
        }
        return true
    }

    private static func monotone(_ points: [CurvePoint]) -> [CurvePoint] {
        guard points.count >= 2 else { return points }
        var result = points.sorted { $0.x < $1.x }
        result[0].y = 0
        result[result.count - 1].y = 1
        for index in 1..<result.count {
            result[index].y = min(max(result[index].y, result[index - 1].y + 0.01), 1)
        }
        result[result.count - 1].y = 1
        for index in stride(from: result.count - 2, through: 1, by: -1) {
            result[index].y = min(result[index].y, result[index + 1].y - 0.01)
        }
        return result
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
