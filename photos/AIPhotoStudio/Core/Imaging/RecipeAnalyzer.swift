import CoreGraphics
import CoreImage
import Foundation

struct RecipeSample: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    var saturation: Double {
        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        guard maxChannel > 0.001 else { return 0 }
        return (maxChannel - minChannel) / maxChannel
    }
}

enum RecipeAnalyzer {
    private static let analysisEdge = 256

    static func analyze(data: Data, title: String) async throws -> Recipe {
        guard let decoded = ImageSourceFactory.decode(data: data, maximumDimension: analysisEdge) else {
            throw RecipeError.unreadableImage
        }
        return try await analyze(image: decoded.image, title: title)
    }

    static func analyze(image: CIImage, title: String) async throws -> Recipe {
        let samples = try await Task.detached(priority: .userInitiated) {
            try rasterize(image)
        }.value
        return try makeRecipe(samples: samples.pixels, width: samples.width, height: samples.height, title: title)
    }

    static func makeRecipe(samples: [RecipeSample], width: Int, height: Int, title: String) throws -> Recipe {
        guard width > 0, height > 0, samples.count == width * height else {
            throw samples.isEmpty ? RecipeError.emptyImage : RecipeError.analysisFailed
        }
        var adjustments = RecipeToneAnalyzer.adjustments(for: samples)
        RecipeColorAnalyzer.apply(to: &adjustments, samples: samples)
        RecipeTextureAnalyzer.apply(to: &adjustments, samples: samples, width: width, height: height)
        return Recipe(
            title: title,
            adjustments: adjustments,
            curves: RecipeCurveAnalyzer.curve(for: samples),
            filter: nil
        )
    }

    static func rasterize(_ image: CIImage) throws -> (pixels: [RecipeSample], width: Int, height: Int) {
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1 else { throw RecipeError.emptyImage }
        let scale = min(1, Double(analysisEdge) / max(extent.width, extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = scaled.extent.integral
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let rendered = context.createCGImage(scaled, from: bounds, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw RecipeError.analysisFailed
        }
        guard
            let data = rendered.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data),
            rendered.width > 0,
            rendered.height > 0
        else {
            throw RecipeError.emptyImage
        }
        let width = rendered.width
        let height = rendered.height
        var samples: [RecipeSample] = []
        samples.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rendered.bytesPerRow + x * 4
                samples.append(RecipeSample(
                    red: Double(bytes[offset]) / 255,
                    green: Double(bytes[offset + 1]) / 255,
                    blue: Double(bytes[offset + 2]) / 255
                ))
            }
        }
        return (samples, width, height)
    }
}
