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

        XCTAssertEqual(values.exposure, 2)
        XCTAssertEqual(values.noiseReduction, 0)
    }

    func testEditStateRoundTripsWithoutOriginalPixels() throws {
        var state = EditState()
        state.adjustments[.temperature] = 40
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

        let reopenedRepository = PhotoProjectRepository(root: root)
        let crashRecoveryProject = try await reopenedRepository.project(id: project.id)
        XCTAssertEqual(crashRecoveryProject?.currentVersion, 2)
        XCTAssertEqual(crashRecoveryProject?.versions.count, 2)
        XCTAssertEqual(crashRecoveryProject?.isFavorite, true)
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

    func testAllFifteenAdjustmentDescriptorsHaveValidDefaultsAndRanges() {
        XCTAssertEqual(AdjustmentKey.allCases.count, 15)
        var values = Adjustments()
        for key in AdjustmentKey.allCases {
            let descriptor = key.descriptor
            XCTAssertTrue(descriptor.range.contains(descriptor.defaultValue), key.rawValue)
            values[key] = descriptor.range.upperBound + 1
            XCTAssertEqual(values[key], descriptor.range.upperBound)
            values[key] = descriptor.defaultValue
            XCTAssertEqual(values[key], descriptor.defaultValue)
            XCTAssertFalse(descriptor.displayValue(values[key]).isEmpty)
        }
    }

    func testPipelineStageOrder() {
        XCTAssertEqual(
            RenderPipeline.stageOrder,
            [.orientation, .geometry, .light, .color, .detail, .filter, .local, .ai]
        )
    }

    func testHistoryCoalescesGestureAndInvalidatesRedo() {
        var history = EditHistory()
        let initial = EditState()
        var changed = initial
        history.begin(kind: .adjust, state: initial, summary: "Exposure")
        changed.adjustments[.exposure] = 0.2
        changed.adjustments[.exposure] = 0.8
        history.end(state: changed)
        XCTAssertEqual(history.undoCommands.count, 1)
        XCTAssertEqual(history.undo(current: changed), initial)
        XCTAssertTrue(history.canRedo)

        var alternate = initial
        alternate.adjustments[.contrast] = 20
        history.record(kind: .adjust, before: initial, after: alternate, summary: "Contrast")
        XCTAssertFalse(history.canRedo)
    }

    func testCropAspectRotationFlipAndCodable() throws {
        let landscape = CropLayout.rect(for: .landscapeSixteenNine, sourceAspectRatio: 4.0 / 3.0)
        XCTAssertEqual(landscape.width * (4.0 / 3.0) / landscape.height, 16.0 / 9.0, accuracy: 0.01)
        var crop = CropState()
        crop.normalizedRect = NormalizedRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
        crop.rotateRight()
        crop.rotationDegrees += 12
        crop.isFlippedHorizontally = true
        let decoded = try JSONDecoder().decode(CropState.self, from: JSONEncoder().encode(crop))
        XCTAssertEqual(decoded, crop)
    }

    func testAllFiltersRespectZeroAndFullIntensity() {
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let engine = CoreImageFilterEngine()
        for definition in FilterDefinition.all {
            let zero = engine.apply(FilterConfig(identifier: definition.id, intensity: 0), to: source)
            XCTAssertTrue(zero === source)
            let full = engine.apply(FilterConfig(identifier: definition.id, intensity: 100), to: source)
            XCTAssertEqual(full.extent, source.extent)
            let middle = engine.apply(FilterConfig(identifier: definition.id, intensity: 50), to: source)
            XCTAssertEqual(middle.extent, source.extent)
        }
    }

    func testFilterThumbnailCacheKeysVersionAndFilter() async {
        let cache = FilterThumbnailCache()
        let image = StubRenderer.makeImage()
        let first = FilterThumbnailCache.Key(projectID: UUID(), version: 1, filterID: "warm")
        await cache.insert(image, for: first)
        let cached = await cache.value(for: first)
        let count = await cache.count
        XCTAssertNotNil(cached)
        XCTAssertEqual(count, 1)
    }

    func testExportConfigurationSizingAndMetadataRewrite() {
        XCTAssertEqual(JPEGQuality.high.compressionValue, 0.86)
        XCTAssertEqual(
            ExportPlan.make(size: .fourK, outputAspectRatio: 4.0 / 3.0, originalLongEdge: 8000),
            ExportPlan(maximumDimension: 3840)
        )
        XCTAssertEqual(
            ExportPlan.make(size: .custom(width: 9000, height: 9000), outputAspectRatio: 0.75, originalLongEdge: 6000),
            ExportPlan(maximumDimension: 6000)
        )
        let metadata = ExportService.safeMetadata([
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyPixelWidth: 8000,
            kCGImagePropertyPixelHeight: 6000
        ], width: 2048, height: 1536)
        XCTAssertEqual(metadata[kCGImagePropertyOrientation] as? Int, 1)
        XCTAssertEqual(metadata[kCGImagePropertyPixelWidth] as? Int, 2048)
        XCTAssertEqual(metadata[kCGImagePropertyPixelHeight] as? Int, 1536)
    }

    func testAITaskTransitionsCodableAndCancellation() throws {
        let source = ImageAssetReference(identifier: "source", relativePath: "Originals/source.jpg")
        var task = AITask(type: .enhance, sourceImage: source)
        try task.begin()
        try task.updateProgress(0.5)
        XCTAssertThrowsError(try task.updateProgress(0.4))
        try task.cancel()
        XCTAssertEqual(task.status, .cancelled)
        XCTAssertEqual(try JSONDecoder().decode(AITask.self, from: JSONEncoder().encode(task)), task)
    }

    func testAIProposalAndGeneratedVersionPreserveEditState() async throws {
        let source = ImageAssetReference(identifier: "source", relativePath: "Originals/source.jpg")
        let provider = MockAIProvider()
        XCTAssertTrue(provider.isDevelopmentOnly)
        let result = try await provider.perform(AIProviderRequest(
            taskID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            capability: .enhance,
            source: source,
            prompt: nil,
            parameters: [:]
        ))
        let state = result.output.applyingProposal(to: EditState())
        XCTAssertEqual(state.adjustments.exposure, 0.2)

        let generated = AIOutput.generatedImage(ImageAssetReference(
            identifier: "generated",
            relativePath: "Generated/result.heic"
        ))
        XCTAssertEqual(generated.generatedVersion(number: 2, preserving: state)?.editState, state)
    }

    func testAPIClientMethodHeadersTokenAndDecoding() async throws {
        let transport = MockTransport()
        let client = APIClient(
            configuration: APIConfiguration(
                environment: .development,
                baseURL: URL(string: "https://example.invalid")!
            ),
            tokenProvider: FixedTokenProvider(),
            transport: transport
        )
        for method in HTTPMethod.allCases {
            let response: TestResponse = try await client.send(
                APIRequest(method: method, path: "test", body: TestBody(value: "safe")),
                response: TestResponse.self
            )
            XCTAssertEqual(response.ok, true)
            XCTAssertEqual(transport.lastRequest?.httpMethod, method.rawValue)
            XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
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
        RenderedImage(cgImage: Self.makeImage(), scale: 1, orientation: .up)
    }

    static func makeImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}

private struct TestBody: Codable, Sendable { let value: String }
private struct TestResponse: Codable, Sendable { let ok: Bool }

private struct FixedTokenProvider: TokenProvider {
    func token() async throws -> String? { "test-token" }
}

private final class MockTransport: HTTPTransport, @unchecked Sendable {
    var lastRequest: URLRequest?
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (try JSONEncoder().encode(TestResponse(ok: true)), response)
    }
}
