import XCTest
@testable import AIPhotoStudio

final class RecipePaletteTests: XCTestCase {
    func testGrayImageDoesNotEnterHueBins() {
        let palette = RecipePaletteAnalyzer.analyze(samples: Array(
            repeating: RecipeSample(red: 0.45, green: 0.45, blue: 0.45),
            count: 64
        ))
        XCTAssertEqual(palette.bins.count, 8)
        for bin in palette.bins {
            XCTAssertEqual(bin.pixelRatio, 0, accuracy: 0.001)
        }
    }

    func testPureRedBelongsToRedBin() {
        let palette = RecipePaletteAnalyzer.analyze(samples: Array(
            repeating: RecipeSample(red: 1, green: 0, blue: 0),
            count: 32
        ))
        let red = palette.bins[0].pixelRatio
        XCTAssertGreaterThan(red, palette.bins.dropFirst().map(\.pixelRatio).max() ?? 0)
        XCTAssertEqual(palette.bins.dropFirst().dropFirst().dropFirst().map(\.pixelRatio).reduce(0, +), 0, accuracy: 0.001)
    }

    func testPureOrangeOverlapsNeighbors() {
        let palette = RecipePaletteAnalyzer.analyze(samples: Array(
            repeating: RecipeSample(red: 1, green: 0.5, blue: 0),
            count: 32
        ))
        let orange = palette.bins[1].pixelRatio
        XCTAssertGreaterThan(orange, palette.bins[0].pixelRatio)
        XCTAssertGreaterThan(orange, palette.bins[2].pixelRatio)
        XCTAssertGreaterThan(palette.bins[0].pixelRatio, 0.05)
        XCTAssertGreaterThan(palette.bins[2].pixelRatio, 0.05)
    }

    func testOrangeAndYellowBothReceiveWeight() {
        var samples = Array(repeating: RecipeSample(red: 1, green: 0.5, blue: 0), count: 20)
        samples += Array(repeating: RecipeSample(red: 1, green: 1, blue: 0), count: 20)
        let palette = RecipePaletteAnalyzer.analyze(samples: samples)
        XCTAssertGreaterThan(palette.bins[1].pixelRatio, 0.2)
        XCTAssertGreaterThan(palette.bins[2].pixelRatio, 0.2)
    }

    func testHueWrapDistanceIsTheShortArc() {
        let distance = RecipePaletteAnalyzer.circularHueDistance(350.0 / 360.0, 10.0 / 360.0)
        XCTAssertEqual(distance, 20.0 / 360.0, accuracy: 0.001)
        XCTAssertNotEqual(distance, 340.0 / 360.0, accuracy: 0.1)
    }

    func testBlueImagePeaksInBlueBin() {
        let palette = RecipePaletteAnalyzer.analyze(samples: Array(
            repeating: RecipeSample(red: 0, green: 0, blue: 1),
            count: 40
        ))
        let blue = palette.bins[5].pixelRatio
        XCTAssertGreaterThan(blue, 0.5)
        XCTAssertEqual(palette.bins[0].pixelRatio, 0, accuracy: 0.001)
        XCTAssertEqual(palette.bins[3].pixelRatio, 0, accuracy: 0.001)
    }

    func testPixelRatiosSumToOne() {
        var samples: [RecipeSample] = []
        samples += Array(repeating: RecipeSample(red: 1, green: 0, blue: 0), count: 20)
        samples += Array(repeating: RecipeSample(red: 0, green: 1, blue: 0), count: 20)
        samples += Array(repeating: RecipeSample(red: 0, green: 0, blue: 1), count: 20)
        let palette = RecipePaletteAnalyzer.analyze(samples: samples)
        XCTAssertEqual(palette.bins.reduce(0) { $0 + $1.pixelRatio }, 1, accuracy: 0.001)
    }

    func testOrangeBinStoresMeasuredHue() {
        let palette = RecipePaletteAnalyzer.analyze(samples: Array(
            repeating: sample(hueDegrees: 35),
            count: 40
        ))
        XCTAssertEqual(palette.bins[1].hueCenter, 35.0 / 360.0, accuracy: 0.01)
    }

    func testWrappedHuesAverageNearZeroInsteadOfHalfway() {
        var samples = Array(repeating: sample(hueDegrees: 350), count: 20)
        samples += Array(repeating: sample(hueDegrees: 10), count: 20)
        let red = RecipePaletteAnalyzer.analyze(samples: samples).bins[0]
        XCTAssertEqual(ColorSpace.circularHueDistance(red.hueCenter, 0), 0, accuracy: 0.02)
        XCTAssertGreaterThan(ColorSpace.circularHueDistance(red.hueCenter, 0.5), 0.4)
    }

    func testMeasuredOrangeHuesMapByTwentyDegrees() {
        let reference = RecipePaletteAnalyzer.analyze(samples: Array(repeating: sample(hueDegrees: 38), count: 30))
        let target = RecipePaletteAnalyzer.analyze(samples: Array(repeating: sample(hueDegrees: 18), count: 30))
        let orange = ColorMappingBuilder.build(reference: reference, target: target).bins[1]
        XCTAssertEqual(orange.sourceHue, 18.0 / 360.0, accuracy: 0.01)
        XCTAssertEqual(orange.targetHue, 38.0 / 360.0, accuracy: 0.01)
        XCTAssertEqual(orange.hueDelta, 20.0 / 360.0, accuracy: 0.01)
    }

    func testWrappedHuesMapByTheShortPositiveArc() {
        let reference = RecipePaletteAnalyzer.analyze(samples: Array(repeating: sample(hueDegrees: 10), count: 30))
        let target = RecipePaletteAnalyzer.analyze(samples: Array(repeating: sample(hueDegrees: 350), count: 30))
        let red = ColorMappingBuilder.build(reference: reference, target: target).bins[0]
        XCTAssertEqual(red.hueDelta, 20.0 / 360.0, accuracy: 0.02)
    }

    func testEmptyBinsStayFinite() {
        let palette = RecipePaletteAnalyzer.analyze(samples: Array(
            repeating: RecipeSample(red: 0.4, green: 0.4, blue: 0.4),
            count: 16
        ))
        for bin in palette.bins {
            XCTAssertTrue(bin.hueCenter.isFinite)
            XCTAssertTrue(bin.saturation.isFinite)
            XCTAssertTrue(bin.luminance.isFinite)
            XCTAssertTrue(bin.pixelRatio.isFinite)
            XCTAssertTrue(bin.hueVariance.isFinite)
            XCTAssertEqual(bin.pixelRatio, 0, accuracy: 0.001)
            XCTAssertEqual(bin.hueCenter, 0, accuracy: 1e-6)
        }
    }

    func testVarianceIsMeasuredInsideAHueBin() {
        let samples = [
            RecipeSample(red: 1, green: 0.35, blue: 0),
            RecipeSample(red: 0.7, green: 0.55, blue: 0.2),
            RecipeSample(red: 1, green: 0.7, blue: 0.1)
        ]
        let palette = RecipePaletteAnalyzer.analyze(samples: samples)
        let orange = palette.bins[1]
        XCTAssertGreaterThan(orange.pixelRatio, 0)
        XCTAssertGreaterThan(orange.hueVariance, 0)
        XCTAssertGreaterThan(orange.saturationVariance, 0)
        XCTAssertGreaterThan(orange.luminanceVariance, 0)
    }

    private func sample(hueDegrees: Double) -> RecipeSample {
        let rgb = ColorSpace.rgb(from: ColorSpace.HSLColor(
            hue: hueDegrees / 360,
            saturation: 1,
            lightness: 0.5
        ))
        return RecipeSample(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
