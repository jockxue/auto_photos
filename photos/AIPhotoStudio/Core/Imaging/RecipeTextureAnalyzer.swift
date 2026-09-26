import Foundation

enum RecipeTextureAnalyzer {
    /// Conservative texture estimate. Uncertain grain and sharpness stay at zero.
    static func apply(to adjustments: inout Adjustments, samples: [RecipeSample], width: Int, height: Int) {
        guard width > 2, height > 2, samples.count == width * height else { return }
        let laplacian = meanAbsoluteLaplacian(samples: samples, width: width, height: height)
        if laplacian > 0.18 {
            adjustments.sharpness = min((laplacian - 0.18) * 40, 12)
        }
        if laplacian > 0.22 {
            adjustments.clarity = min((laplacian - 0.22) * 30, 8)
        }
        let grainSignal = highFrequencyResidue(samples: samples, width: width, height: height)
        if grainSignal > 0.16 {
            adjustments.grain = min((grainSignal - 0.16) * 25, 8)
        }
    }

    private static func meanAbsoluteLaplacian(samples: [RecipeSample], width: Int, height: Int) -> Double {
        var total = 0.0
        var count = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = samples[y * width + x].luminance
                let neighbors = samples[y * width + x - 1].luminance
                    + samples[y * width + x + 1].luminance
                    + samples[(y - 1) * width + x].luminance
                    + samples[(y + 1) * width + x].luminance
                total += abs(neighbors - 4 * center)
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }

    private static func highFrequencyResidue(samples: [RecipeSample], width: Int, height: Int) -> Double {
        var total = 0.0
        var count = 0
        for y in 1..<(height - 1) {
            for x in stride(from: 1, to: width - 1, by: 2) {
                let left = samples[y * width + x - 1].luminance
                let center = samples[y * width + x].luminance
                let right = samples[y * width + x + 1].luminance
                let local = (left + right) / 2
                total += abs(center - local)
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }
}
