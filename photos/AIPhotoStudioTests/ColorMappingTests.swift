import XCTest
@testable import AIPhotoStudio

final class ColorMappingTests: XCTestCase {
    func testIdenticalPalettesHaveZeroDeltas() {
        let palette = palette(orangeHue: 30, orangeSaturation: 0.5, orangeLuminance: 0.5, orangeRatio: 0.2)
        let mapping = ColorMappingBuilder.build(reference: palette, target: palette)
        let orange = mapping.bins[1]
        XCTAssertEqual(orange.hueDelta, 0, accuracy: 1e-6)
        XCTAssertEqual(orange.saturationDelta, 0, accuracy: 1e-6)
        XCTAssertEqual(orange.luminanceDelta, 0, accuracy: 1e-6)
    }

    func testOrangeHueMovesTowardReference() {
        let reference = palette(orangeHue: 28, orangeSaturation: 0.5, orangeLuminance: 0.5, orangeRatio: 0.2)
        let target = palette(orangeHue: 18, orangeSaturation: 0.5, orangeLuminance: 0.5, orangeRatio: 0.2)
        let orange = ColorMappingBuilder.build(reference: reference, target: target).bins[1]
        XCTAssertEqual(orange.hueDelta, 10.0 / 360.0, accuracy: 1e-6)
    }

    func testSaturationDelta() {
        let reference = palette(orangeHue: 30, orangeSaturation: 0.48, orangeLuminance: 0.5, orangeRatio: 0.2)
        let target = palette(orangeHue: 30, orangeSaturation: 0.65, orangeLuminance: 0.5, orangeRatio: 0.2)
        let orange = ColorMappingBuilder.build(reference: reference, target: target).bins[1]
        XCTAssertEqual(orange.saturationDelta, -0.17, accuracy: 1e-6)
    }

    func testLuminanceDelta() {
        let reference = palette(orangeHue: 30, orangeSaturation: 0.5, orangeLuminance: 0.62, orangeRatio: 0.2)
        let target = palette(orangeHue: 30, orangeSaturation: 0.5, orangeLuminance: 0.55, orangeRatio: 0.2)
        let orange = ColorMappingBuilder.build(reference: reference, target: target).bins[1]
        XCTAssertEqual(orange.luminanceDelta, 0.07, accuracy: 1e-6)
    }

    func testHueWrapUsesTheShortArc() {
        let reference = palette(orangeHue: 10, orangeSaturation: 0.5, orangeLuminance: 0.5, orangeRatio: 0.2)
        let target = palette(orangeHue: 350, orangeSaturation: 0.5, orangeLuminance: 0.5, orangeRatio: 0.2)
        let orange = ColorMappingBuilder.build(reference: reference, target: target).bins[1]
        XCTAssertEqual(orange.hueDelta, 20.0 / 360.0, accuracy: 1e-6)
        XCTAssertNotEqual(orange.hueDelta, -340.0 / 360.0, accuracy: 0.1)
    }

    func testMissingReferenceColorHasNoWeight() {
        var reference = palette(orangeHue: 30, orangeSaturation: 0.5, orangeLuminance: 0.5, orangeRatio: 0.2)
        var target = reference
        reference.bins[5].pixelRatio = 0
        target.bins[5].pixelRatio = 0.2
        let blue = ColorMappingBuilder.build(reference: reference, target: target).bins[5]
        XCTAssertEqual(blue.mappingWeight, 0, accuracy: 1e-6)
    }

    func testMissingTargetColorHasNoWeight() {
        var reference = palette(orangeHue: 30, orangeSaturation: 0.5, orangeLuminance: 0.5, orangeRatio: 0.2)
        var target = reference
        reference.bins[5].pixelRatio = 0.2
        target.bins[5].pixelRatio = 0
        let blue = ColorMappingBuilder.build(reference: reference, target: target).bins[5]
        XCTAssertEqual(blue.mappingWeight, 0, accuracy: 1e-6)
    }

    func testPresenceRisesSmoothlyThroughTheThresholdBand() {
        XCTAssertEqual(ColorMappingBuilder.presence(for: 0.01), 0, accuracy: 1e-6)
        XCTAssertEqual(ColorMappingBuilder.presence(for: 0.02), 0, accuracy: 1e-6)
        let midpoint = ColorMappingBuilder.presence(for: 0.05)
        XCTAssertGreaterThan(midpoint, 0)
        XCTAssertLessThan(midpoint, 1)
        XCTAssertEqual(ColorMappingBuilder.presence(for: 0.08), 1, accuracy: 1e-6)
        XCTAssertEqual(ColorMappingBuilder.presence(for: 0.2), 1, accuracy: 1e-6)
        let lower = ColorMappingBuilder.presence(for: 0.04)
        let upper = ColorMappingBuilder.presence(for: 0.06)
        XCTAssertLessThan(lower, midpoint)
        XCTAssertLessThan(midpoint, upper)
    }

    func testHigherHueVarianceLowersConfidence() {
        XCTAssertGreaterThan(
            ColorMappingBuilder.hueConfidence(for: 0.001),
            ColorMappingBuilder.hueConfidence(for: 0.2)
        )
    }

    func testMappingWeightIsTheProductOfTheThreeTerms() {
        let referenceVariance = 0.05
        let targetVariance = 0.01
        let reference = palette(
            orangeHue: 30,
            orangeSaturation: 0.5,
            orangeLuminance: 0.5,
            orangeRatio: 0.12,
            orangeHueVariance: referenceVariance
        )
        let target = palette(
            orangeHue: 30,
            orangeSaturation: 0.5,
            orangeLuminance: 0.5,
            orangeRatio: 0.1,
            orangeHueVariance: targetVariance
        )
        let orange = ColorMappingBuilder.build(reference: reference, target: target).bins[1]
        let expected = ColorMappingBuilder.presence(for: 0.1)
            * ColorMappingBuilder.presence(for: 0.12)
            * ColorMappingBuilder.hueConfidence(for: max(referenceVariance, targetVariance))
        XCTAssertEqual(orange.mappingWeight, expected, accuracy: 1e-6)
    }

    func testMappingAlwaysHasEightBins() {
        let palette = palette(orangeHue: 30, orangeSaturation: 0.5, orangeLuminance: 0.5, orangeRatio: 0.2)
        XCTAssertEqual(ColorMappingBuilder.build(reference: palette, target: palette).bins.count, 8)
    }

    private func palette(
        orangeHue: Double,
        orangeSaturation: Double,
        orangeLuminance: Double,
        orangeRatio: Double,
        orangeHueVariance: Double = 0
    ) -> ReferencePalette {
        let centers = [0.0, 30, 60, 120, 180, 240, 270, 300]
        let bins = centers.enumerated().map { index, center in
            PaletteBin(
                hueCenter: index == 1 ? orangeHue / 360 : center / 360,
                saturation: index == 1 ? orangeSaturation : 0,
                luminance: index == 1 ? orangeLuminance : 0,
                pixelRatio: index == 1 ? orangeRatio : 0,
                hueVariance: index == 1 ? orangeHueVariance : 0,
                saturationVariance: 0,
                luminanceVariance: 0
            )
        }
        return ReferencePalette(bins: bins)
    }
}
