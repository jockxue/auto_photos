import Foundation

enum RecipeError: LocalizedError, Equatable, Sendable {
    case unreadableImage
    case emptyImage
    case analysisFailed
    case saveFailed
    case readFailed
    case recipeNotFound
    case noEditablePhoto

    var errorDescription: String? {
        switch self {
        case .unreadableImage: L10n.text("The reference photo could not be read.")
        case .emptyImage: L10n.text("The reference photo is empty.")
        case .analysisFailed: L10n.text("The reference photo could not be analyzed.")
        case .saveFailed: L10n.text("The recipe could not be saved.")
        case .readFailed: L10n.text("Recipes could not be read.")
        case .recipeNotFound: L10n.text("The recipe no longer exists.")
        case .noEditablePhoto: L10n.text("There is no photo to edit.")
        }
    }
}

/// A reusable look. It never stores crop, rotation, or flip.
struct Recipe: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var adjustments: Adjustments
    var curves: CurveAdjustment
    var filter: FilterConfig?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        adjustments: Adjustments = Adjustments(),
        curves: CurveAdjustment = CurveAdjustment(),
        filter: FilterConfig? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.adjustments = adjustments
        self.curves = curves
        self.filter = filter
    }
}
