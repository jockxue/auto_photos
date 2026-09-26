import Foundation

enum RecipeEngine {
    /// Absolute parameters interpolate from the current edit toward the recipe.
    /// Geometry is copied through unchanged.
    static func apply(_ recipe: Recipe, to state: EditState, strength: Double) -> EditState {
        let amount = min(max(strength, 0), 1)
        var result = state
        result.geometry = state.geometry
        result.adjustments = blend(state.adjustments, toward: recipe.adjustments, amount: amount)
        result.curves = blend(state.curves, toward: recipe.curves, amount: amount)
        result.filter = blendFilter(current: state.filter, recipe: recipe.filter, amount: amount)
        return result
    }

    private static func blend(_ current: Adjustments, toward recipe: Adjustments, amount: Double) -> Adjustments {
        var values = Adjustments()
        for key in AdjustmentKey.allCases {
            values[key] = current[key] + (recipe[key] - current[key]) * amount
        }
        return values
    }

    private static func blend(_ current: CurveAdjustment, toward recipe: CurveAdjustment, amount: Double) -> CurveAdjustment {
        var values = CurveAdjustment()
        for channel in CurveChannel.allCases {
            values[channel] = blend(current[channel], toward: recipe[channel], amount: amount)
        }
        return values
    }

    private static func blend(_ current: ChannelCurve, toward recipe: ChannelCurve, amount: Double) -> ChannelCurve {
        let recipePoints = recipe.points.sorted { $0.x < $1.x }
        let currentPoints = current.points.sorted { $0.x < $1.x }
        let count = min(currentPoints.count, recipePoints.count)
        guard count > 0 else { return current }
        var points: [CurvePoint] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let start = currentPoints[index]
            let end = recipePoints[min(index, recipePoints.count - 1)]
            points.append(CurvePoint(
                x: start.x,
                y: min(max(start.y + (end.y - start.y) * amount, 0), 1)
            ))
        }
        return ChannelCurve(points: points)
    }

    private static func blendFilter(current: FilterConfig?, recipe: FilterConfig?, amount: Double) -> FilterConfig? {
        if amount == 0 { return current }
        if amount == 1 { return recipe }
        guard let recipe else { return current }
        let currentIntensity = current?.identifier == recipe.identifier ? (current?.intensity ?? 0) : 0
        return FilterConfig(
            identifier: recipe.identifier,
            intensity: currentIntensity + (recipe.intensity - currentIntensity) * amount
        )
    }
}
