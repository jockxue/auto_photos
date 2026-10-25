import CoreImage
import XCTest
@testable import AIPhotoStudio

final class RecipeColorRenderTests: XCTestCase {
    func testDisabledColorMappingMatchesTheExistingColorPath() {
        let image = solid(hueDegrees: 18)
        let plain = pixel(RenderPipeline().process(original: image, orientation: .up, edits: EditState()))
        var explicit = EditState()
        explicit.colorMapping = nil
        let skipped = pixel(RenderPipeline().process(original: image, orientation: .up, edits: explicit))
        XCTAssertEqual(plain, skipped)
    }

    func testZeroDeltaMappingStaysCloseToTheUnmappedImage() {
        let image = solid(hueDegrees: 18)
        let plain = pixel(RenderPipeline().process(original: image, orientation: .up, edits: EditState()))
        var edits = EditState()
        edits.colorMapping = ColorMapping(bins: [bin(
            sourceDegrees: 18,
            hueDeltaDegrees: 0,
            weight: 1
        )])
        let mapped = pixel(RenderPipeline().process(original: image, orientation: .up, edits: edits))
        XCTAssertEqual(plain[0], mapped[0], accuracy: 8)
        XCTAssertEqual(plain[1], mapped[1], accuracy: 8)
        XCTAssertEqual(plain[2], mapped[2], accuracy: 8)
    }

    func testOrangeMovesTowardTheReferenceHue() {
        let image = solid(hueDegrees: 18)
        let plain = RenderPipeline().process(original: image, orientation: .up, edits: EditState())
        var edits = EditState()
        edits.colorMapping = ColorMapping(bins: [bin(
            sourceDegrees: 18,
            hueDeltaDegrees: 20,
            weight: 1
        )])
        let mapped = RenderPipeline().process(original: image, orientation: .up, edits: edits)
        let delta = ColorSpace.signedCircularHueDelta(from: hue(of: plain), to: hue(of: mapped))
        XCTAssertEqual(delta, 20.0 / 360.0, accuracy: 0.04)
    }

    func testCurveAndColorMappingBothApply() {
        let image = solid(hueDegrees: 18)
        var curveOnly = EditState()
        curveOnly.curves.rgb.setPoint(at: 1, y: 0.05)
        curveOnly.curves.rgb.setPoint(at: 2, y: 0.1)
        curveOnly.curves.rgb.setPoint(at: 3, y: 0.15)
        curveOnly.curves.rgb.setPoint(at: 4, y: 0.2)
        var mappingOnly = EditState()
        mappingOnly.colorMapping = ColorMapping(bins: [bin(
            sourceDegrees: 18,
            hueDeltaDegrees: 20,
            weight: 1
        )])
        var both = curveOnly
        both.colorMapping = mappingOnly.colorMapping

        let curveImage = RenderPipeline().process(original: image, orientation: .up, edits: curveOnly)
        let mappingImage = RenderPipeline().process(original: image, orientation: .up, edits: mappingOnly)
        let combined = RenderPipeline().process(original: image, orientation: .up, edits: both)
        XCTAssertGreaterThan(
            ColorSpace.circularHueDistance(hue(of: combined), hue(of: curveImage)),
            0.02
        )
        XCTAssertNotEqual(pixel(combined), pixel(mappingImage))
    }

    func testPreviewAndExportUseTheSameMapping() throws {
        let color = ColorSpace.rgb(from: ColorSpace.HSLColor(hue: 18.0 / 360.0, saturation: 1, lightness: 0.5))
        let image = CIImage(color: CIColor(red: color.red, green: color.green, blue: color.blue))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let original = OriginalImage(
            image: image,
            metadata: ImageMetadata(
                pixelSize: CGSize(width: 4, height: 4),
                orientation: .up,
                scale: 1,
                hasAlpha: false,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
        )
        var edits = EditState()
        edits.colorMapping = ColorMapping(bins: [bin(
            sourceDegrees: 18,
            hueDeltaDegrees: 20,
            weight: 1
        )])
        let engine = CoreImageRenderEngine()
        let preview = try engine.render(RenderRequest(original: original, edits: edits, maximumDimension: 2048))
        let exported = try engine.render(RenderRequest(original: original, edits: edits, maximumDimension: nil))
        XCTAssertEqual(sample(preview.cgImage), sample(exported.cgImage))
    }

    private func bin(sourceDegrees: Double, hueDeltaDegrees: Double, weight: Double) -> ColorMappingBin {
        let source = sourceDegrees / 360
        let delta = hueDeltaDegrees / 360
        return ColorMappingBin(
            hueCenter: ColorSpace.normalizeHue(source + delta),
            sourceHue: source,
            sourceSaturation: 1,
            sourceLuminance: 0.5,
            targetHue: ColorSpace.normalizeHue(source + delta),
            targetSaturation: 1,
            targetLuminance: 0.5,
            hueDelta: delta,
            saturationDelta: 0,
            luminanceDelta: 0,
            mappingWeight: weight
        )
    }

    private func solid(hueDegrees: Double) -> CIImage {
        let color = ColorSpace.rgb(from: ColorSpace.HSLColor(
            hue: hueDegrees / 360,
            saturation: 1,
            lightness: 0.5
        ))
        return CIImage(color: CIColor(red: color.red, green: color.green, blue: color.blue))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    private func pixel(_ image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return bytes
    }

    private func hue(of image: CIImage) -> Double {
        let bytes = pixel(image)
        return ColorSpace.hsl(from: ColorSpace.RGBColor(
            red: Double(bytes[0]) / 255,
            green: Double(bytes[1]) / 255,
            blue: Double(bytes[2]) / 255
        )).hue
    }

    private func lightness(of image: CIImage) -> Double {
        let bytes = pixel(image)
        return ColorSpace.hsl(from: ColorSpace.RGBColor(
            red: Double(bytes[0]) / 255,
            green: Double(bytes[1]) / 255,
            blue: Double(bytes[2]) / 255
        )).lightness
    }

    private func sample(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return bytes }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes
    }
}
