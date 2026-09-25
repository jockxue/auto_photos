import CoreGraphics
import CoreImage
import Foundation

struct FilterDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    fileprivate let operations: [FilterOperation]

    static let all: [FilterDefinition] = [
        .init(id: "original", title: "Original", operations: []),
        .init(id: "natural", title: "Natural", operations: [
            .filter("CIColorControls", ["inputSaturation": 1.06, "inputContrast": 1.03])
        ]),
        .init(id: "portrait", title: "Portrait", operations: [
            .filter("CIHighlightShadowAdjust", ["inputHighlightAmount": 0.85, "inputShadowAmount": 0.35]),
            .filter("CIColorControls", ["inputSaturation": 0.96, "inputContrast": 1.04])
        ]),
        .init(id: "warm", title: "Warm", operations: [
            .temperature(neutral: 6500, target: 7900)
        ]),
        .init(id: "cool", title: "Cool", operations: [
            .temperature(neutral: 6500, target: 5000)
        ]),
        .init(id: "film", title: "Film", operations: [.filter("CIPhotoEffectProcess", [:])]),
        .init(id: "blackWhite", title: "Black & White", operations: [.filter("CIPhotoEffectMono", [:])]),
        .init(id: "vintage", title: "Vintage", operations: [.filter("CIPhotoEffectTransfer", [:])])
    ]

    static func definition(id: String) -> FilterDefinition? {
        all.first { $0.id == id }
    }
}

fileprivate enum FilterOperation: Equatable, Sendable {
    case filter(String, [String: Double])
    case temperature(neutral: Double, target: Double)
}

protocol FilterEngineProtocol: Sendable {
    func apply(_ config: FilterConfig?, to image: CIImage) -> CIImage
}

struct CoreImageFilterEngine: FilterEngineProtocol {
    func apply(_ config: FilterConfig?, to source: CIImage) -> CIImage {
        guard
            let config,
            config.intensity > 0,
            let definition = FilterDefinition.definition(id: config.identifier),
            !definition.operations.isEmpty
        else { return source }

        let effected = definition.operations.reduce(source) { image, operation in
            switch operation {
            case .filter(let name, let values):
                return image.applyingFilter(name, parameters: values)
            case .temperature(let neutral, let target):
                return image.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: neutral, y: 0),
                    "inputTargetNeutral": CIVector(x: target, y: 0)
                ])
            }
        }
        let amount = min(max(config.intensity / 100, 0), 1)
        if amount == 1 { return effected }
        return source.applyingFilter("CIDissolveTransition", parameters: [
            "inputTargetImage": effected,
            "inputTime": amount
        ]).cropped(to: source.extent)
    }
}

actor FilterThumbnailCache {
    struct Key: Hashable {
        let projectID: UUID
        let version: Int
        let filterID: String
    }

    private var storage: [Key: CGImage] = [:]

    func value(for key: Key) -> CGImage? { storage[key] }
    func insert(_ image: CGImage, for key: Key) { storage[key] = image }
    func remove(projectID: UUID) { storage = storage.filter { $0.key.projectID != projectID } }
    var count: Int { storage.count }
}
