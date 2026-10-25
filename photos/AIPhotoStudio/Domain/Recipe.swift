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

struct PaletteBin: Codable, Equatable, Sendable {
    var hueCenter: Double
    var saturation: Double
    var luminance: Double
    var pixelRatio: Double
    var hueVariance: Double
    var saturationVariance: Double
    var luminanceVariance: Double
}

struct ReferencePalette: Codable, Equatable, Sendable {
    var bins: [PaletteBin]
}

/// A reusable look. It never stores crop, rotation, or flip.
struct Recipe: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var adjustments: Adjustments
    var curves: CurveAdjustment
    var filter: FilterConfig?
    /// Measured reference palette. Absent on recipes saved before color mapping.
    var palette: ReferencePalette?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        adjustments: Adjustments = Adjustments(),
        curves: CurveAdjustment = CurveAdjustment(),
        filter: FilterConfig? = nil,
        palette: ReferencePalette? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.adjustments = adjustments
        self.curves = curves
        self.filter = filter
        self.palette = palette
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, adjustments, curves, filter, palette
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        adjustments = try values.decode(Adjustments.self, forKey: .adjustments)
        curves = try values.decode(CurveAdjustment.self, forKey: .curves)
        filter = try values.decodeIfPresent(FilterConfig.self, forKey: .filter)
        palette = try values.decodeIfPresent(ReferencePalette.self, forKey: .palette)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(adjustments, forKey: .adjustments)
        try values.encode(curves, forKey: .curves)
        try values.encodeIfPresent(filter, forKey: .filter)
        try values.encodeIfPresent(palette, forKey: .palette)
    }
}
