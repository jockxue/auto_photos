import XCTest
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
