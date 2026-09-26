import Foundation

struct LuminanceDistribution: Equatable, Sendable {
    var p1: Double
    var p5: Double
    var p10: Double
    var p25: Double
    var p50: Double
    var p75: Double
    var p90: Double
    var p95: Double
    var p99: Double
}

enum RecipeToneAnalyzer {
    static func distribution(of luminances: [Double]) -> LuminanceDistribution {
        LuminanceDistribution(
            p1: percentile(luminances, 0.01),
            p5: percentile(luminances, 0.05),
            p10: percentile(luminances, 0.10),
            p25: percentile(luminances, 0.25),
            p50: percentile(luminances, 0.50),
            p75: percentile(luminances, 0.75),
            p90: percentile(luminances, 0.90),
            p95: percentile(luminances, 0.95),
            p99: percentile(luminances, 0.99)
        )
    }

    static func adjustments(for samples: [RecipeSample]) -> Adjustments {
        let luminances = samples.map(\.luminance)
        let tone = distribution(of: luminances)
        var values = Adjustments()
        let midpoint = max(tone.p50, 0.02)
        values.exposure = clamp(log2(midpoint / 0.45), -1, 1)
        let spread = tone.p90 - tone.p10
        values.contrast = clamp((spread - 0.55) / 0.55 * 40, -30, 30)
        values.highlights = clamp((0.82 - tone.p90) * 80, -50, 50)
        values.shadows = clamp((tone.p10 - 0.12) * 120, -50, 50)
        values.whites = clamp((tone.p99 - 0.92) * 80, -30, 30)
        values.blacks = clamp((tone.p1 - 0.02) * 400, -30, 30)
        return values
    }

    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * fraction).rounded())))
        return sorted[index]
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
