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

    func testEditStateWithoutCurvesDecodesAsIdentity() throws {
        let json = #"{"adjustments":{},"geometry":{}}"#
        let decoded = try JSONDecoder().decode(EditState.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.curves.isIdentity)
    }

    func testCurveLookupLiftsMidtones() {
        var curve = ChannelCurve.identity
        curve.setPoint(at: 2, y: 0.8)
        XCTAssertEqual(curve.evaluated(0.5), 0.8, accuracy: 0.001)
        XCTAssertEqual(curve.evaluated(0), 0, accuracy: 0.001)
        XCTAssertEqual(curve.evaluated(1), 1, accuracy: 0.001)
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

    func testImagePolicyRejectsMoreThan24Megapixels() {
        XCTAssertThrowsError(try PhotoProjectRepository.validateDimensions(width: 6_000, height: 8_000))
        XCTAssertNoThrow(try PhotoProjectRepository.validateDimensions(width: 6_000, height: 4_000))
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
        let thumbnailSource = CGImageSourceCreateWithData(thumbnailData as CFData, nil)!
        let thumbnailProperties = CGImageSourceCopyPropertiesAtIndex(thumbnailSource, 0, nil) as! [CFString: Any]
        let thumbnailWidth = thumbnailProperties[kCGImagePropertyPixelWidth] as! Int
        let thumbnailHeight = thumbnailProperties[kCGImagePropertyPixelHeight] as! Int
        XCTAssertLessThanOrEqual(max(thumbnailWidth, thumbnailHeight), 512)

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

    func testEditedPreviewThumbnailIsDownsampledTo512() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoProjectRepository(root: root)
        let project = try await repository.importPhoto(
            data: makeImageData(width: 120, height: 80, type: .jpeg),
            suggestedName: "Thumbnail.jpg"
        )
        let previewData = try makeImageData(width: 1600, height: 1200, type: .png)
        let previewSource = CGImageSourceCreateWithData(previewData as CFData, nil)!
        let preview = CGImageSourceCreateImageAtIndex(previewSource, 0, nil)!
        try await repository.replaceThumbnail(preview, for: project)

        let data = try await repository.thumbnailData(for: project)
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        let width = properties[kCGImagePropertyPixelWidth] as! Int
        let height = properties[kCGImagePropertyPixelHeight] as! Int
        XCTAssertEqual(max(width, height), 512)
    }

    func testVersionRestoreAndDeleteCleanGeneratedAssets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoProjectRepository(root: root)
        var project = try await repository.importPhoto(
            data: makeImageData(width: 64, height: 64, type: .png),
            suggestedName: "Versions.png"
        )
        project.editState.adjustments[.contrast] = 30
        project = try await repository.update(project, commandSummary: "Contrast")
        let restored = try await repository.restore(projectID: project.id, version: 1)
        XCTAssertEqual(restored.currentVersion, 3)
        XCTAssertEqual(restored.versions.last?.commandSummary, "Restore v1")
        XCTAssertEqual(restored.editState, project.versions.first?.editState)

        let relativePath = "Generated/\(project.id.uuidString)/result.png"
        let generatedURL = root.appendingPathComponent("AIPhotoStudio/\(relativePath)")
        try FileManager.default.createDirectory(
            at: generatedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("generated".utf8).write(to: generatedURL)
        _ = try await repository.appendGeneratedVersion(
            projectID: project.id,
            asset: ImageAssetReference(identifier: "generated", relativePath: relativePath),
            editState: restored.editState,
            summary: "Generated"
        )
        _ = try await repository.appendGeneratedVersion(
            projectID: project.id,
            asset: ImageAssetReference(identifier: "generated-again", relativePath: relativePath),
            editState: restored.editState,
            summary: "Generated reference reused"
        )
        do {
            _ = try await repository.appendGeneratedVersion(
                projectID: project.id,
                asset: ImageAssetReference(
                    identifier: "unsafe",
                    relativePath: "Generated/../Originals/\(project.originalImagePath)"
                ),
                editState: restored.editState,
                summary: "Unsafe"
            )
            XCTFail("Expected generated path rejection")
        } catch ProjectRepositoryError.unsafePath {}

        try await repository.delete(id: project.id)
        try await repository.delete(id: project.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: generatedURL.path))
    }

    func testInterruptedDeleteJournalRestoresFilesWhenProjectStillIndexed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoProjectRepository(root: root)
        let project = try await repository.importPhoto(
            data: makeImageData(width: 32, height: 32, type: .png),
            suggestedName: "Recover.png"
        )
        let appRoot = root.appendingPathComponent("AIPhotoStudio")
        let source = appRoot.appendingPathComponent(project.originalImagePath)
        let transaction = appRoot.appendingPathComponent(".Trash/\(project.id.uuidString)")
        try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: true)
        let stagedName = "0-\(source.lastPathComponent)"
        try FileManager.default.moveItem(at: source, to: transaction.appendingPathComponent(stagedName))
        let journal: [String: Any] = [
            "projectID": project.id.uuidString,
            "entries": [[
                "relativePath": project.originalImagePath,
                "stagedName": stagedName
            ]]
        ]
        let journalData = try JSONSerialization.data(withJSONObject: journal)
        try journalData.write(to: transaction.appendingPathComponent("journal.json"))

        let reopenedRepository = PhotoProjectRepository(root: root)
        _ = try await reopenedRepository.allProjects()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transaction.path))
    }

    func testDeleteJournalRejectsPathTraversal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoProjectRepository(root: root)
        let project = try await repository.importPhoto(
            data: makeImageData(width: 32, height: 32, type: .png),
            suggestedName: "Unsafe.png"
        )
        let appRoot = root.appendingPathComponent("AIPhotoStudio")
        let transaction = appRoot.appendingPathComponent(".Trash/\(project.id.uuidString)")
        try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: true)
        let victim = appRoot.appendingPathComponent(".Trash/victim")
        try Data("safe".utf8).write(to: victim)
        let journal: [String: Any] = [
            "projectID": project.id.uuidString,
            "entries": [[
                "relativePath": project.originalImagePath,
                "stagedName": "../victim"
            ]]
        ]
        try JSONSerialization.data(withJSONObject: journal)
            .write(to: transaction.appendingPathComponent("journal.json"))

        do {
            _ = try await PhotoProjectRepository(root: root).allProjects()
            XCTFail("Expected unsafe journal rejection")
        } catch ProjectRepositoryError.unsafePath {
            XCTAssertEqual(try Data(contentsOf: victim), Data("safe".utf8))
        }
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
        XCTAssertEqual(RenderPipeline().configuredStages, RenderPipeline.stageOrder)
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
        crop.fineRotationDegrees = 12
        crop.isFlippedHorizontally = true
        let decoded = try JSONDecoder().decode(CropState.self, from: JSONEncoder().encode(crop))
        XCTAssertEqual(decoded, crop)
    }

    func testViewportCropMappingUsesDisplayedImageRectAndMovingImage() {
        let mapper = ImageViewportMapper(
            canvasSize: CGSize(width: 400, height: 400),
            imageSize: CGSize(width: 400, height: 200),
            mode: .fit,
            transform: .init()
        )
        XCTAssertEqual(mapper.displayRect, CGRect(x: 0, y: 100, width: 400, height: 200))
        let source = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        XCTAssertEqual(mapper.viewportRect(for: source), CGRect(x: 100, y: 150, width: 200, height: 100))

        let movedFrame = mapper.sourceRect(moving: source, byViewport: CGSize(width: 40, height: 20))
        XCTAssertEqual(movedFrame.x, 0.35, accuracy: 0.0001)
        XCTAssertEqual(movedFrame.y, 0.15, accuracy: 0.0001)
        let movedImage = mapper.sourceRect(movingImageFor: source, byViewport: CGSize(width: 40, height: 20))
        XCTAssertEqual(movedImage.x, 0.15, accuracy: 0.0001)
        XCTAssertEqual(movedImage.y, 0.35, accuracy: 0.0001)
    }

    func testAdjustmentMappingsStayInsideCoreImageRanges() {
        for value in stride(from: -100.0, through: 100.0, by: 10) {
            var adjustments = Adjustments()
            adjustments.highlights = value
            adjustments.shadows = value
            let mapped = AdjustmentMapping.highlightShadow(adjustments)
            XCTAssertTrue((0...1).contains(mapped.highlight))
            XCTAssertTrue((0...1).contains(mapped.shadow))
            let clarity = AdjustmentMapping.clarity(value)
            XCTAssertTrue((0...1).contains(clarity.unsharpIntensity))
            XCTAssertTrue((0...1.5).contains(clarity.blurRadius))
            XCTAssertFalse(clarity.unsharpIntensity > 0 && clarity.blurRadius > 0)
        }
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

    func testFilterIntensityProducesPixelBlendNotOnlyMatchingExtent() {
        let source = CIImage(color: CIColor(red: 0.82, green: 0.24, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let engine = CoreImageFilterEngine()
        let zero = pixel(engine.apply(FilterConfig(identifier: "film", intensity: 0), to: source))
        let middle = pixel(engine.apply(FilterConfig(identifier: "film", intensity: 50), to: source))
        let full = pixel(engine.apply(FilterConfig(identifier: "film", intensity: 100), to: source))
        XCTAssertNotEqual(zero, full)
        for index in 0..<3 {
            let lower = min(zero[index], full[index])
            let upper = max(zero[index], full[index])
            XCTAssertTrue((lower...upper).contains(middle[index]))
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

    func testExportConfigurationSizingAndMetadataRewrite() throws {
        XCTAssertEqual(JPEGQuality.high.compressionValue, 0.86)
        XCTAssertEqual(
            try ExportPlan.make(size: .fourK, outputSize: CGSize(width: 6000, height: 4000)),
            ExportPlan(maximumDimension: 3840)
        )
        XCTAssertEqual(
            try ExportPlan.make(size: .custom(width: 1000, height: 500), outputSize: CGSize(width: 4000, height: 3000)),
            ExportPlan(maximumDimension: 666)
        )
        XCTAssertThrowsError(
            try ExportPlan.make(size: .original, outputSize: CGSize(width: 6000, height: 8000))
        )
        XCTAssertEqual(
            try ExportPlan.make(size: .pixels2048, outputSize: CGSize(width: 8000, height: 8000)),
            ExportPlan(maximumDimension: 2048)
        )
        let rotated = GeometryOutputPlanner.outputSize(
            originalWidth: 4000,
            originalHeight: 3000,
            orientation: .up,
            crop: .init(),
            rotationDegrees: 90
        )
        XCTAssertEqual(rotated.width, 3000, accuracy: 0.01)
        XCTAssertEqual(rotated.height, 4000, accuracy: 0.01)
        let oriented = GeometryOutputPlanner.outputSize(
            originalWidth: 4000,
            originalHeight: 3000,
            orientation: .right,
            crop: .init(),
            rotationDegrees: 0
        )
        XCTAssertEqual(oriented.width, 3000, accuracy: 0.01)
        XCTAssertEqual(oriented.height, 4000, accuracy: 0.01)
        let metadata = ExportService.safeMetadata([
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyPixelWidth: 8000,
            kCGImagePropertyPixelHeight: 6000,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifPixelXDimension: 8000,
                kCGImagePropertyExifPixelYDimension: 6000
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFOrientation: 6,
                "ImageWidth" as CFString: 8000
            ]
        ], width: 2048, height: 1536)
        XCTAssertEqual(metadata[kCGImagePropertyOrientation] as? Int, 1)
        XCTAssertEqual(metadata[kCGImagePropertyPixelWidth] as? Int, 2048)
        XCTAssertEqual(metadata[kCGImagePropertyPixelHeight] as? Int, 1536)
        let exif = metadata[kCGImagePropertyExifDictionary] as! [CFString: Any]
        let tiff = metadata[kCGImagePropertyTIFFDictionary] as! [CFString: Any]
        XCTAssertEqual(exif[kCGImagePropertyExifPixelXDimension] as? Int, 2048)
        XCTAssertEqual(exif[kCGImagePropertyExifPixelYDimension] as? Int, 1536)
        XCTAssertEqual(tiff[kCGImagePropertyTIFFOrientation] as? Int, 1)
        XCTAssertNil(tiff["ImageWidth" as CFString])
    }

    func testExportCancellationBlocksConcurrentRestartUntilOldTaskFinishes() {
        var operation = ExportOperationState()
        XCTAssertTrue(operation.begin())
        operation.requestCancellation()
        XCTAssertTrue(operation.isCancelling)
        XCTAssertFalse(operation.begin())
        operation.finish()
        XCTAssertTrue(operation.begin())
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

        let taskStore = InMemoryAITaskStore()
        let service = AIService(provider: provider, taskStore: taskStore)
        let inputTask = AITask(
            type: .naturalLanguageEdit,
            sourceImage: source,
            prompt: "make it brighter"
        )
        let completed = try await service.execute(inputTask)
        XCTAssertEqual(completed.status, .success)
        XCTAssertEqual(completed.progress, 1)
        XCTAssertNil(completed.resultImage)
        let persistedTask = await taskStore.task(id: inputTask.id)
        XCTAssertEqual(persistedTask?.status, .success)
    }

    func testAIServiceCancellationCannotBeOverwrittenByLateProviderSuccess() async throws {
        let store = InMemoryAITaskStore()
        let service = AIService(provider: SlowMockProvider(), taskStore: store)
        let input = AITask(
            type: .enhance,
            sourceImage: ImageAssetReference(identifier: "source", relativePath: "Originals/source.jpg")
        )
        let execution = Task { try await service.execute(input) }
        for _ in 0..<20 {
            if await store.task(id: input.id)?.status == .processing { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        await service.cancel(taskID: input.id)
        let result = try await execution.value
        XCTAssertEqual(result.status, .cancelled)
        let stored = await store.task(id: input.id)
        XCTAssertEqual(stored?.status, .cancelled)
    }

    func testAIServiceCancellationCannotBeOverwrittenByLateProviderFailure() async throws {
        let store = InMemoryAITaskStore()
        let service = AIService(provider: SlowFailingProvider(), taskStore: store)
        let input = AITask(
            type: .enhance,
            sourceImage: ImageAssetReference(identifier: "source", relativePath: "Originals/source.jpg")
        )
        let execution = Task { try await service.execute(input) }
        for _ in 0..<20 {
            if await store.task(id: input.id)?.status == .processing { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        await service.cancel(taskID: input.id)
        let result = try await execution.value
        XCTAssertEqual(result.status, .cancelled)
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

    @MainActor
    func testEditorFlushSerializesAutosaveAndExportsCurrentState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoProjectRepository(root: root)
        let data = try makeImageData(width: 120, height: 80, type: .jpeg)
        let project = try await repository.importPhoto(data: data, suggestedName: "Current.jpg")
        let original = try XCTUnwrap(ImageSourceFactory.decode(data: data, maximumDimension: 2048))
        let session = EditorSession(original: original, project: project, repository: repository, renderer: StubRenderer())
        session.beginAdjustment(.exposure)
        session.setValue(1.25, for: .exposure)
        session.endAdjustment()

        async let firstFlush: Void = session.flushPendingSave()
        async let secondFlush: Void = session.flushPendingSave()
        _ = try await (firstFlush, secondFlush)

        let (exportProject, exportState, _) = try await session.prepareExport()
        XCTAssertEqual(exportState.adjustments.exposure, 1.25)
        XCTAssertEqual(exportProject.editState, exportState)
        XCTAssertNil(session.persistenceError)
        let reopened = try await repository.project(id: project.id)
        XCTAssertEqual(reopened?.editState.adjustments.exposure, 1.25)
        XCTAssertEqual(reopened?.versions.count, 2)
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

private struct SlowMockProvider: AIProviderProtocol {
    let supportedCapabilities = Set(AICapability.allCases)
    let isDevelopmentOnly = true

    func perform(_ request: AIProviderRequest) async throws -> AIProviderResult {
        try? await Task.sleep(nanoseconds: 30_000_000)
        return AIProviderResult(output: .parameterProposal([
            AdjustmentKey.exposure.rawValue: 0.1
        ]))
    }

    func cancel(taskID: UUID) async {}
}

private struct SlowFailingProvider: AIProviderProtocol {
    let supportedCapabilities = Set(AICapability.allCases)
    let isDevelopmentOnly = true

    func perform(_ request: AIProviderRequest) async throws -> AIProviderResult {
        try? await Task.sleep(nanoseconds: 30_000_000)
        throw AIError.providerFailure
    }

    func cancel(taskID: UUID) async {}
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
