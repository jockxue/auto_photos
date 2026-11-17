import XCTest
import UIKit
@testable import AIPhotoStudio

final class RecipeAnalyzerTests: XCTestCase {
    func testLowSaturationPhotoDoesNotInventTemperature() throws {
        let samples = (0..<64).map { index in
            let level = Double(index) / 63
            return RecipeSample(red: level, green: level, blue: level)
        }
        let recipe = try RecipeAnalyzer.makeRecipe(samples: samples, width: 8, height: 8, title: "Gray")
        XCTAssertEqual(recipe.adjustments.temperature, 0)
        XCTAssertEqual(recipe.adjustments.tint, 0)
        XCTAssertEqual(recipe.adjustments.saturation, 0)
    }

    func testHighContrastStaysInsideConservativeRange() throws {
        var samples: [RecipeSample] = []
        for index in 0..<100 {
            let level = index < 50 ? 0.02 : 0.98
            samples.append(RecipeSample(red: level, green: level, blue: level))
        }
        let recipe = try RecipeAnalyzer.makeRecipe(samples: samples, width: 10, height: 10, title: "Hard")
        XCTAssertGreaterThan(recipe.adjustments.contrast, 5)
        XCTAssertLessThanOrEqual(recipe.adjustments.contrast, 30)
    }

    func testLowContrastDoesNotBecomeExtreme() throws {
        let samples = (0..<64).map { index in
            let level = 0.46 + Double(index % 5) * 0.01
            return RecipeSample(red: level, green: level, blue: level)
        }
        let recipe = try RecipeAnalyzer.makeRecipe(samples: samples, width: 8, height: 8, title: "Flat")
        XCTAssertLessThanOrEqual(recipe.adjustments.contrast, 0)
        XCTAssertGreaterThanOrEqual(recipe.adjustments.contrast, -30)
    }

    func testGeneratedCurveStaysMonotone() throws {
        let samples = (0..<80).map { index in
            let level = Double(index) / 79
            return RecipeSample(red: level, green: level * 0.8, blue: level * 0.6)
        }
        let recipe = try RecipeAnalyzer.makeRecipe(samples: samples, width: 8, height: 10, title: "Ramp")
        XCTAssertTrue(RecipeCurveAnalyzer.isMonotone(recipe.curves.rgb))
        XCTAssertTrue(recipe.curves.red.isIdentity)
        XCTAssertTrue(recipe.curves.green.isIdentity)
        XCTAssertTrue(recipe.curves.blue.isIdentity)
    }

    func testEmptyAndMismatchedSamplesFail() {
        XCTAssertThrowsError(try RecipeAnalyzer.makeRecipe(samples: [], width: 0, height: 0, title: "Empty")) { error in
            XCTAssertEqual(error as? RecipeError, .emptyImage)
        }
        XCTAssertThrowsError(try RecipeAnalyzer.makeRecipe(samples: [RecipeSample(red: 1, green: 1, blue: 1)], width: 2, height: 2, title: "Bad")) { error in
            XCTAssertEqual(error as? RecipeError, .analysisFailed)
        }
    }

    func testUnreadableDataFails() async {
        do {
            _ = try await RecipeAnalyzer.analyze(data: Data([0, 1, 2, 3]), title: "Bad")
            XCTFail("Expected unreadable image")
        } catch let error as RecipeError {
            XCTAssertEqual(error, .unreadableImage)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}

final class RecipeEngineTests: XCTestCase {
    func testApplyKeepsGeometry() {
        var state = EditState()
        state.geometry.quarterTurns = 1
        state.geometry.isFlippedHorizontally = true
        state.adjustments.exposure = 0.2
        var recipe = Recipe(title: "Look")
        recipe.adjustments.exposure = 1
        let applied = RecipeEngine.apply(recipe, to: state, strength: 1)
        XCTAssertEqual(applied.geometry, state.geometry)
        XCTAssertEqual(applied.adjustments.exposure, 1, accuracy: 0.001)
    }

    func testZeroStrengthLeavesCurrentAdjustments() {
        var state = EditState()
        state.adjustments.contrast = 12
        state.curves.rgb.setPoint(at: 2, y: 0.62)
        var recipe = Recipe(title: "Look")
        recipe.adjustments.contrast = 30
        recipe.curves.rgb.setPoint(at: 2, y: 0.4)
        let applied = RecipeEngine.apply(recipe, to: state, strength: 0)
        XCTAssertEqual(applied.adjustments.contrast, 12, accuracy: 0.001)
        XCTAssertEqual(applied.curves, state.curves)
        XCTAssertEqual(applied.geometry, state.geometry)
    }

    func testFullStrengthMatchesRecipe() {
        var state = EditState()
        state.adjustments.exposure = -0.4
        var recipe = Recipe(title: "Look")
        recipe.adjustments.exposure = 0.8
        recipe.adjustments.temperature = 10
        let applied = RecipeEngine.apply(recipe, to: state, strength: 1)
        XCTAssertEqual(applied.adjustments.exposure, recipe.adjustments.exposure, accuracy: 0.001)
        XCTAssertEqual(applied.adjustments.temperature, recipe.adjustments.temperature, accuracy: 0.001)
    }

    func testPartialStrengthInterpolatesParameters() {
        var state = EditState()
        state.adjustments.exposure = 0
        var recipe = Recipe(title: "Look")
        recipe.adjustments.exposure = 1
        let applied = RecipeEngine.apply(recipe, to: state, strength: 0.5)
        XCTAssertEqual(applied.adjustments.exposure, 0.5, accuracy: 0.001)
    }

    func testUndoRestoresStateBeforeRecipe() {
        var history = EditHistory()
        var state = EditState()
        state.geometry.quarterTurns = 2
        state.adjustments.saturation = 15
        let before = state
        var recipe = Recipe(title: "Look")
        recipe.adjustments.saturation = -20
        history.begin(kind: .recipe, state: state, summary: "Recipe")
        state = RecipeEngine.apply(recipe, to: state, strength: 1)
        history.end(state: state)
        let restored = history.undo(current: state)
        XCTAssertEqual(restored, before)
    }
}

final class RecipeStoreTests: XCTestCase {
    func testSaveFetchAndDeleteRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = RecipeStore(root: root)
        var recipe = Recipe(title: "Stored", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        recipe.adjustments.exposure = 0.3
        try await store.save(recipe)
        let loaded = try await store.get(id: recipe.id)
        let saved = try await store.fetchAll()
        XCTAssertEqual(loaded, recipe)
        XCTAssertEqual(saved.count, 1)
        try await store.delete(id: recipe.id)
        let remaining = try await store.fetchAll()
        XCTAssertEqual(remaining.count, 0)
        do {
            _ = try await store.get(id: recipe.id)
            XCTFail("Expected missing recipe")
        } catch let error as RecipeError {
            XCTAssertEqual(error, .recipeNotFound)
        }
    }
}


final class ReplicaSessionTests: XCTestCase {
    @MainActor
    func testStrengthChangesAndReferenceReplacementUseOriginalBaseline() {
        let session = EditorSession(original: ImageSourceFactory.makeTestImage(size: CGSize(width: 32, height: 24)))
        var first = Recipe(title: "Warm")
        first.adjustments.exposure = 1
        session.previewRecipe(first, strength: 0.7)
        XCTAssertEqual(session.editState.adjustments.exposure, 0.7, accuracy: 0.001)
        session.previewRecipe(first, strength: 0.3)
        XCTAssertEqual(session.editState.adjustments.exposure, 0.3, accuracy: 0.001)
        var replacement = Recipe(title: "Dark")
        replacement.adjustments.exposure = -1
        session.previewRecipe(replacement, strength: 0.7)
        XCTAssertEqual(session.editState.adjustments.exposure, -0.7, accuracy: 0.001)
        session.previewRecipe(replacement, strength: 0)
        XCTAssertEqual(session.editState, EditState())
        session.cancelRecipePreview()
    }

    @MainActor
    func testConfirmedPreviewSurvivesProjectReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PhotoProjectRepository(root: root)
        let original = ImageSourceFactory.makeTestImage(size: CGSize(width: 48, height: 32))
        let image = try CoreImageRenderEngine().render(RenderRequest(original: original, edits: .init(), maximumDimension: nil)).cgImage
        let data = try XCTUnwrap(UIImage(cgImage: image).pngData())
        let session = EditorSession(original: original)
        let recipe = try await RecipeAnalyzer.analyze(data: data, title: "Reference")
        session.previewRecipe(recipe, strength: 0.7)
        let expected = session.editState
        XCTAssertNotNil(expected.colorMapping)
        let project = try await repository.importPhoto(data: data, suggestedName: "Target.png")
        let saved = try await repository.saveEditState(projectID: project.id, editState: expected, commandSummary: "Match")
        let loaded = try await repository.project(id: saved.id)
        let resumed = EditorSession(original: original, project: try XCTUnwrap(loaded), repository: repository)
        XCTAssertEqual(resumed.editState, expected)
        let exported = try await resumed.renderExport()
        XCTAssertEqual(exported.cgImage.width, 48)
        XCTAssertEqual(exported.cgImage.height, 32)
        session.cancelRecipePreview()
    }
}


final class ReplicaPhotoSelectionTests: XCTestCase {
    @MainActor
    func testBothPickingOrdersRetainPhotoDataAndEnablePreview() throws {
        let target = photo(color: .red, size: CGSize(width: 48, height: 32))
        let reference = photo(color: .blue, size: CGSize(width: 24, height: 24))
        let orders: [[ReplicaPhotoSlot]] = [[.target, .reference], [.reference, .target]]
        for order in orders {
            var selection = ReplicaPhotoSelection()
            XCTAssertFalse(selection.isComplete)
            selection.select(order[0] == .target ? target : reference, for: order[0])
            XCTAssertFalse(selection.isComplete)
            selection.select(order[1] == .target ? target : reference, for: order[1])
            XCTAssertTrue(selection.isComplete)
            XCTAssertEqual(selection.target?.data, target.data)
            XCTAssertEqual(selection.reference?.data, reference.data)
        }
    }

    @MainActor
    func testSelectedReferenceProducesPreviewDestinationPayload() async throws {
        let target = photo(color: .red, size: CGSize(width: 48, height: 32))
        let reference = photo(color: .blue, size: CGSize(width: 24, height: 24))
        var selection = ReplicaPhotoSelection()
        selection.select(target, for: .target)
        selection.select(reference, for: .reference)
        let payload = try await selection.makePreview()
        let expected = try await RecipeAnalyzer.analyze(data: reference.data, title: "Reference")
        XCTAssertEqual(payload.target.data, target.data)
        XCTAssertEqual(payload.reference.data, reference.data)
        XCTAssertEqual(payload.original.metadata.pixelSize, CGSize(width: 48, height: 32))
        XCTAssertEqual(payload.recipe.palette, expected.palette)
        XCTAssertEqual(payload.recipe.adjustments, expected.adjustments)

        let replacement = photo(color: .green, size: CGSize(width: 24, height: 24))
        selection.select(replacement, for: .reference)
        let updated = try await selection.makePreview()
        XCTAssertEqual(updated.reference.data, replacement.data)
        XCTAssertEqual(updated.target.data, target.data)
        XCTAssertNotEqual(updated.recipe.palette, payload.recipe.palette)
    }

    func testIncompleteSelectionCannotGeneratePreview() async {
        do {
            _ = try await ReplicaPhotoSelection().makePreview()
            XCTFail("A missing photo must not create a preview destination")
        } catch {
            XCTAssertEqual(error as? RecipeError, .emptyImage)
        }
    }

    @MainActor
    private func photo(color: UIColor, size: CGSize) -> PickedPhoto {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return PickedPhoto(data: data, suggestedName: "Sample.png", originalAssetIdentifier: nil)
    }
}
