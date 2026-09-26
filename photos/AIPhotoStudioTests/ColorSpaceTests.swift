import XCTest
@testable import AIPhotoStudio

final class ColorSpaceTests: XCTestCase {
    func testPureRedConvertsToHSL() {
        let hsl = ColorSpace.hsl(from: ColorSpace.RGBColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(hsl.hue, 0, accuracy: 1e-6)
        XCTAssertEqual(hsl.saturation, 1, accuracy: 1e-6)
        XCTAssertEqual(hsl.lightness, 0.5, accuracy: 1e-6)
    }

    func testPureGreenConvertsToHSL() {
        let hsl = ColorSpace.hsl(from: ColorSpace.RGBColor(red: 0, green: 1, blue: 0))
        XCTAssertEqual(hsl.hue, 1.0 / 3.0, accuracy: 1e-6)
        XCTAssertEqual(hsl.saturation, 1, accuracy: 1e-6)
        XCTAssertEqual(hsl.lightness, 0.5, accuracy: 1e-6)
    }

    func testPureBlueConvertsToHSL() {
        let hsl = ColorSpace.hsl(from: ColorSpace.RGBColor(red: 0, green: 0, blue: 1))
        XCTAssertEqual(hsl.hue, 2.0 / 3.0, accuracy: 1e-6)
        XCTAssertEqual(hsl.saturation, 1, accuracy: 1e-6)
        XCTAssertEqual(hsl.lightness, 0.5, accuracy: 1e-6)
    }

    func testGrayHasNoUsableSaturation() {
        let hsl = ColorSpace.hsl(from: ColorSpace.RGBColor(red: 0.5, green: 0.5, blue: 0.5))
        XCTAssertEqual(hsl.saturation, 0, accuracy: 1e-6)
        XCTAssertEqual(hsl.lightness, 0.5, accuracy: 1e-6)
    }

    func testRGBRoundTripsThroughHSL() {
        let colors = [
            ColorSpace.RGBColor(red: 1, green: 0, blue: 0),
            ColorSpace.RGBColor(red: 0, green: 1, blue: 0),
            ColorSpace.RGBColor(red: 0, green: 0, blue: 1),
            ColorSpace.RGBColor(red: 1, green: 0.5, blue: 0),
            ColorSpace.RGBColor(red: 0.2, green: 0.7, blue: 0.4),
            ColorSpace.RGBColor(red: 0.5, green: 0.5, blue: 0.5)
        ]
        for color in colors {
            let roundTrip = ColorSpace.rgb(from: ColorSpace.hsl(from: color))
            XCTAssertEqual(roundTrip.red, color.red, accuracy: 1e-6)
            XCTAssertEqual(roundTrip.green, color.green, accuracy: 1e-6)
            XCTAssertEqual(roundTrip.blue, color.blue, accuracy: 1e-6)
        }
    }

    func testHueWrapDistanceIsTwentyDegrees() {
        let distance = ColorSpace.circularHueDistance(350.0 / 360.0, 10.0 / 360.0)
        XCTAssertEqual(distance, 20.0 / 360.0, accuracy: 1e-6)
    }

    func testWrappedHuesAverageNearZero() {
        let mean = ColorSpace.circularHueMean([
            (hue: 350.0 / 360.0, weight: 1),
            (hue: 10.0 / 360.0, weight: 1)
        ])
        XCTAssertEqual(ColorSpace.circularHueDistance(mean, 0), 0, accuracy: 1e-6)
    }

    func testOrdinaryHuesAverageToTwentyDegrees() {
        let mean = ColorSpace.circularHueMean([
            (hue: 10.0 / 360.0, weight: 1),
            (hue: 30.0 / 360.0, weight: 1)
        ])
        XCTAssertEqual(mean, 20.0 / 360.0, accuracy: 1e-6)
    }

    func testZeroAndFullTurnHaveNoDistance() {
        XCTAssertEqual(ColorSpace.circularHueDistance(0, 1), 0, accuracy: 1e-6)
    }

    func testOppositeHuesAreHalfTurnApart() {
        XCTAssertEqual(ColorSpace.circularHueDistance(0, 0.5), 0.5, accuracy: 1e-6)
    }
}
