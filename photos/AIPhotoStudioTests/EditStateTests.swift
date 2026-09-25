import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AIPhotoStudio

final class EditStateTests: XCTestCase {
    func testAdjustmentValuesAreClampedToDeclaredRange() {
        var values = Adjustments()
        values[.exposure] = 4
        values[.noiseReduction] = -1

        XCTAssertEqual(values.exposure, 1)
        XCTAssertEqual(values.noiseReduction, 0)
    }

    func testEditStateRoundTripsWithoutOriginalPixels() throws {
        var state = EditState()
        state.adjustments[.warmth] = 0.4
        state.geometry.rotationDegrees = 90

        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(EditState.self, from: data), state)
    }

    func testRenderProtocolCanBeReplacedByTestDouble() throws {
        let renderer = StubRenderer()
        let original = ImageSourceFactory.makeTestImage(size: CGSize(width: 2, height: 2))
        let result = try renderer.render(RenderRequest(original: original, edits: .init(), maximumDimension: 2))
        XCTAssertEqual(result.cgImage.width, 1)
    }

    func testCanvasZoomPanResetAndBeforeAfterAreViewOnly() {
        var canvas = CanvasPresentationState()
        canvas.transform.zoom(by: 3)
        canvas.transform.pan(by: CGSize(width: 24, height: -12))
        canvas.setComparing(true)

        XCTAssertEqual(canvas.transform.scale, 3)
        XCTAssertEqual(canvas.transform.offset, CGSize(width: 24, height: -12))
        XCTAssertTrue(canvas.showsOriginal)

        canvas.setComparing(false)
        canvas.transform.reset()
        XCTAssertEqual(canvas, CanvasPresentationState())
    }

    func testOversizedImagePolicyRejectsMoreThan200Megapixels() {
        XCTAssertThrowsError(try PhotoProjectRepository.validateDimensions(width: 20_001, height: 10_001))
        XCTAssertNoThrow(try PhotoProjectRepository.validateDimensions(width: 20_000, height: 10_000))
    }

    func testProjectCanBeUpdatedAndReopenedWithoutChangingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoProjectRepository(root: root)
        let source = try makeImageData(width: 120, height: 80, type: .jpeg)
        var project = try await repository.importPhoto(
            data: source,
            suggestedName: "Landscape.jpg",
            originalAssetIdentifier: "photos-library-id"
        )
        XCTAssertEqual(project.currentVersion, 1)
        XCTAssertEqual(project.originalAssetIdentifier, "photos-library-id")
        XCTAssertTrue(project.originalImagePath.hasPrefix("Originals/"))
        XCTAssertTrue(project.thumbnailPath.hasPrefix("Thumbnails/"))
        XCTAssertFalse(project.originalImagePath.hasPrefix("/"))
        let thumbnailExists = try await repository.fileExists(atRelativePath: project.thumbnailPath)
        XCTAssertTrue(thumbnailExists)

        project.editState.adjustments[.exposure] = 0.5
        project.isFavorite = true
        project = try await repository.update(project)

        let reopened = try await repository.project(id: project.id)
        let preservedSource = try await repository.originalData(for: project)
        XCTAssertEqual(reopened?.editState.adjustments.exposure, 0.5)
        XCTAssertEqual(reopened?.currentVersion, 2)
        XCTAssertEqual(reopened?.isFavorite, true)
        XCTAssertEqual(preservedSource, source)
        let thumbnailData = try await repository.thumbnailData(for: project)
        XCTAssertFalse(thumbnailData.isEmpty)

        let roundTrip = try JSONDecoder().decode(
            PhotoProject.self,
            from: JSONEncoder().encode(project)
        )
        XCTAssertEqual(roundTrip, project)
    }

    func testDeletingProjectCleansOriginalAndThumbnail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoProjectRepository(root: root)
        let project = try await repository.importPhoto(
            data: makeImageData(width: 32, height: 32, type: .png),
            suggestedName: "Delete.png"
        )
        let originalExistsBeforeDelete = try await repository.fileExists(atRelativePath: project.originalImagePath)
        let thumbnailExistsBeforeDelete = try await repository.fileExists(atRelativePath: project.thumbnailPath)
        XCTAssertTrue(originalExistsBeforeDelete)
        XCTAssertTrue(thumbnailExistsBeforeDelete)

        try await repository.delete(id: project.id)

        let reopened = try await repository.project(id: project.id)
        let originalExistsAfterDelete = try await repository.fileExists(atRelativePath: project.originalImagePath)
        let thumbnailExistsAfterDelete = try await repository.fileExists(atRelativePath: project.thumbnailPath)
        XCTAssertNil(reopened)
        XCTAssertFalse(originalExistsAfterDelete)
        XCTAssertFalse(thumbnailExistsAfterDelete)
    }

    func testJPEGPNGAndHEICPortraitLandscapeImports() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoProjectRepository(root: root)
        let cases: [(UTType, Int, Int)] = [
            (.jpeg, 120, 80),
            (.png, 80, 120),
            (.heic, 96, 64)
        ]

        for (type, width, height) in cases {
            let data = try makeImageData(width: width, height: height, type: type)
            let project = try await repository.importPhoto(data: data, suggestedName: "Fixture")
            XCTAssertEqual(project.originalPixelWidth, width)
            XCTAssertEqual(project.originalPixelHeight, height)
        }
    }

    private func makeImageData(width: Int, height: Int, type: UTType) throws -> Data {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil),
            let image = context.makeImage()
        else { throw FixtureError.encodingUnavailable(type.identifier) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.encodingUnavailable(type.identifier)
        }
        return output as Data
    }
}

private enum FixtureError: Error {
    case encodingUnavailable(String)
}

private struct StubRenderer: RenderEngineProtocol {
    func render(_ request: RenderRequest) throws -> RenderedImage {
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return RenderedImage(cgImage: context.makeImage()!, scale: 1, orientation: .up)
    }
}
