import XCTest
@testable import AIPhotoStudio

final class RecipeColorCubeBuilderTests: XCTestCase {
    func testDefaultCubeHasTheCoreImageLength() {
        let cube = RecipeColorCubeBuilder.build(zeroMapping())
        XCTAssertEqual(cube.dimension, 33)
        XCTAssertEqual(cube.samples.count, 33 * 33 * 33 * 4)
        XCTAssertTrue(cube.samples.allSatisfy(\.isFinite))
    }

    func testIdentityMappingPreservesSampleColors() {
        let mapping = zeroMapping()
        let colors = [
            ColorSpace.RGBColor(red: 0, green: 0, blue: 0),
            ColorSpace.RGBColor(red: 1, green: 1, blue: 1),
            ColorSpace.RGBColor(red: 0.5, green: 0.5, blue: 0.5),
            rgb(hueDegrees: 18),
            ColorSpace.RGBColor(red: 0.2, green: 0.7, blue: 0.4)
        ]
        for color in colors {
            let mapped = RecipeColorCubeBuilder.map(color, through: mapping)
            XCTAssertEqual(mapped.red, color.red, accuracy: 1e-5)
            XCTAssertEqual(mapped.green, color.green, accuracy: 1e-5)
            XCTAssertEqual(mapped.blue, color.blue, accuracy: 1e-5)
        }
    }

    func testZeroWeightsDoNotShiftColor() {
        let mapping = singleBin(sourceDegrees: 18, hueDeltaDegrees: 20, saturationDelta: 0.2, luminanceDelta: -0.1, weight: 0)
        let color = rgb(hueDegrees: 18, saturation: 0.8, lightness: 0.5)
        let mapped = RecipeColorCubeBuilder.map(color, through: mapping)
        XCTAssertEqual(mapped.red, color.red, accuracy: 1e-5)
        XCTAssertEqual(mapped.green, color.green, accuracy: 1e-5)
        XCTAssertEqual(mapped.blue, color.blue, accuracy: 1e-5)
    }

    func testHueMovesTwentyDegreesTowardTheReference() {
        let mapping = singleBin(sourceDegrees: 18, hueDeltaDegrees: 20, saturationDelta: 0, luminanceDelta: 0, weight: 1)
        let mapped = ColorSpace.hsl(from: RecipeColorCubeBuilder.map(
            rgb(hueDegrees: 18),
            through: mapping
        ))
        XCTAssertEqual(mapped.hue, 38.0 / 360.0, accuracy: 0.01)
    }

    func testMappingWeightScalesHueSaturationAndLightness() {
        let color = rgb(hueDegrees: 18, saturation: 0.6, lightness: 0.5)
        let shifts: [(Double, Double)] = [(0, 0), (0.5, 0.5), (1, 1)]
        for (weight, scale) in shifts {
            let mapping = singleBin(
                sourceDegrees: 18,
                hueDeltaDegrees: 20,
                saturationDelta: 0.2,
                luminanceDelta: -0.1,
                weight: weight
            )
            let mapped = ColorSpace.hsl(from: RecipeColorCubeBuilder.map(color, through: mapping))
            XCTAssertEqual(mapped.hue, (18.0 + 20.0 * scale) / 360.0, accuracy: 0.01)
            XCTAssertEqual(mapped.saturation, 0.6 + 0.2 * scale, accuracy: 0.02)
            XCTAssertEqual(mapped.lightness, 0.5 - 0.1 * scale, accuracy: 0.02)
        }
    }

    func testHueWrapUsesTheShortArc() {
        let forward = ColorSpace.hsl(from: RecipeColorCubeBuilder.map(
            rgb(hueDegrees: 350),
            through: singleBin(sourceDegrees: 350, hueDeltaDegrees: 20, saturationDelta: 0, luminanceDelta: 0, weight: 1)
        ))
        XCTAssertEqual(ColorSpace.circularHueDistance(forward.hue, 10.0 / 360.0), 0, accuracy: 0.02)

        let backward = ColorSpace.hsl(from: RecipeColorCubeBuilder.map(
            rgb(hueDegrees: 10),
            through: singleBin(sourceDegrees: 10, hueDeltaDegrees: -20, saturationDelta: 0, luminanceDelta: 0, weight: 1)
        ))
        XCTAssertEqual(ColorSpace.circularHueDistance(backward.hue, 350.0 / 360.0), 0, accuracy: 0.02)

        let cube = RecipeColorCubeBuilder.build(
            singleBin(sourceDegrees: 350, hueDeltaDegrees: 20, saturationDelta: 0, luminanceDelta: 0, weight: 1)
        )
        XCTAssertTrue(cube.samples.allSatisfy(\.isFinite))
    }

    func testNeighboringRegionsChangeContinuously() {
        var bins = emptyBins()
        bins[1] = bin(sourceDegrees: 30, hueDeltaDegrees: 15, weight: 1)
        bins[2] = bin(sourceDegrees: 60, hueDeltaDegrees: -10, weight: 1)
        let mapping = ColorMapping(bins: bins)
        var previous = ColorSpace.hsl(from: RecipeColorCubeBuilder.map(rgb(hueDegrees: 30), through: mapping)).hue
        for degrees in stride(from: 32.0, through: 60.0, by: 2.0) {
            let hue = ColorSpace.hsl(from: RecipeColorCubeBuilder.map(rgb(hueDegrees: degrees), through: mapping)).hue
            XCTAssertTrue(hue.isFinite)
            XCTAssertLessThan(ColorSpace.circularHueDistance(previous, hue), 8.0 / 360.0)
            previous = hue
        }
    }

    func testNeutralAndBoundaryColorsStayFiniteWithoutACast() {
        let mapping = singleBin(sourceDegrees: 18, hueDeltaDegrees: 40, saturationDelta: 0.4, luminanceDelta: 0.2, weight: 1)
        let neutrals = [
            ColorSpace.RGBColor(red: 0, green: 0, blue: 0),
            ColorSpace.RGBColor(red: 1, green: 1, blue: 1),
            ColorSpace.RGBColor(red: 0.5, green: 0.5, blue: 0.5),
            rgb(hueDegrees: 18, saturation: 0.01, lightness: 0.5)
        ]
        for color in neutrals {
            let mapped = RecipeColorCubeBuilder.map(color, through: mapping)
            XCTAssertTrue(mapped.red.isFinite && mapped.green.isFinite && mapped.blue.isFinite)
            let spread = max(mapped.red, mapped.green, mapped.blue) - min(mapped.red, mapped.green, mapped.blue)
            XCTAssertLessThan(spread, 0.05)
        }
        let edges = [
            rgb(hueDegrees: 200, saturation: 1, lightness: 0.02),
            rgb(hueDegrees: 200, saturation: 1, lightness: 0.98),
            rgb(hueDegrees: 200, saturation: 1, lightness: 0.5)
        ]
        for color in edges {
            let mapped = RecipeColorCubeBuilder.map(color, through: mapping)
            XCTAssertTrue(mapped.red.isFinite && mapped.green.isFinite && mapped.blue.isFinite)
            XCTAssertGreaterThanOrEqual(mapped.red, 0)
            XCTAssertLessThanOrEqual(mapped.red, 1)
        }
    }

    func testCubeLayoutMatchesCoreImageOrder() {
        let cube = RecipeColorCubeBuilder.build(zeroMapping(), dimension: 33)
        let redIndex = ((0 * 33 + 0) * 33 + 32) * 4
        XCTAssertEqual(cube.samples[redIndex], 1, accuracy: 0.001)
        XCTAssertEqual(cube.samples[redIndex + 1], 0, accuracy: 0.001)
        XCTAssertEqual(cube.samples[redIndex + 2], 0, accuracy: 0.001)
        XCTAssertEqual(cube.samples[redIndex + 3], 1, accuracy: 0.001)
    }

    private func zeroMapping() -> ColorMapping {
        ColorMapping(bins: emptyBins())
    }

    private func singleBin(
        sourceDegrees: Double,
        hueDeltaDegrees: Double,
        saturationDelta: Double,
        luminanceDelta: Double,
        weight: Double
    ) -> ColorMapping {
        var bins = emptyBins()
        bins[1] = bin(
            sourceDegrees: sourceDegrees,
            hueDeltaDegrees: hueDeltaDegrees,
            saturationDelta: saturationDelta,
            luminanceDelta: luminanceDelta,
            weight: weight
        )
        return ColorMapping(bins: bins)
    }

    private func emptyBins() -> [ColorMappingBin] {
        [0.0, 30, 60, 120, 180, 240, 270, 300].map { center in
            ColorMappingBin(
                hueCenter: center / 360,
                sourceHue: center / 360,
                sourceSaturation: 0,
                sourceLuminance: 0,
                targetHue: center / 360,
                targetSaturation: 0,
                targetLuminance: 0,
                hueDelta: 0,
                saturationDelta: 0,
                luminanceDelta: 0,
                mappingWeight: 0
            )
        }
    }

    private func bin(
        sourceDegrees: Double,
        hueDeltaDegrees: Double,
        saturationDelta: Double = 0,
        luminanceDelta: Double = 0,
        weight: Double
    ) -> ColorMappingBin {
        let source = sourceDegrees / 360
        let delta = hueDeltaDegrees / 360
        return ColorMappingBin(
            hueCenter: ColorSpace.normalizeHue(source + delta),
            sourceHue: source,
            sourceSaturation: 0.6,
            sourceLuminance: 0.5,
            targetHue: ColorSpace.normalizeHue(source + delta),
            targetSaturation: 0.6 + saturationDelta,
            targetLuminance: 0.5 + luminanceDelta,
            hueDelta: delta,
            saturationDelta: saturationDelta,
            luminanceDelta: luminanceDelta,
            mappingWeight: weight
        )
    }

    private func rgb(hueDegrees: Double, saturation: Double = 1, lightness: Double = 0.5) -> ColorSpace.RGBColor {
        ColorSpace.rgb(from: ColorSpace.HSLColor(
            hue: hueDegrees / 360,
            saturation: saturation,
            lightness: lightness
        ))
    }
}
