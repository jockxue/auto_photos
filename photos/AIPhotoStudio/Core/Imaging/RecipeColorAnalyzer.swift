import Foundation

enum RecipeColorAnalyzer {
    static func apply(to adjustments: inout Adjustments, samples: [RecipeSample]) {
        let chromatic = samples.filter { $0.saturation > 0.08 }
        let meanSaturation = samples.reduce(0) { $0 + $1.saturation } / Double(max(samples.count, 1))
        guard meanSaturation >= 0.06, !chromatic.isEmpty else {
            adjustments.temperature = 0
            adjustments.tint = 0
            adjustments.saturation = 0
            adjustments.vibrance = 0
            return
        }

        let count = Double(chromatic.count)
        let warmCool = chromatic.reduce(0.0) { $0 + ($1.red - $1.blue) } / count
        let greenMagenta = chromatic.reduce(0.0) { $0 + ($1.green - ($1.red + $1.blue) / 2) } / count
        let saturationP75 = RecipeToneAnalyzer.percentile(samples.map(\.saturation), 0.75)

        adjustments.temperature = clamp(warmCool * 45, -25, 25)
        adjustments.tint = clamp(-greenMagenta * 40, -20, 20)
        adjustments.saturation = clamp((meanSaturation - 0.28) * 70, -40, 40)
        adjustments.vibrance = clamp((0.34 - saturationP75) * 25, -15, 15)
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
