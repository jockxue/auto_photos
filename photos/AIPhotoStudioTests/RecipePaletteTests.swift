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
}
