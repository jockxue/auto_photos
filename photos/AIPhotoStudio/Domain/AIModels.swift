import Foundation

enum AICapability: String, CaseIterable, Codable, Hashable, Sendable {
    case enhance, portrait, remove, background, upscale, expand
    case generativeEdit, naturalLanguageEdit
}

enum AITaskStatus: String, Codable, Sendable {
    case pending, processing, success, failed, cancelled
}

enum AITaskInvariantError: Error, Equatable, Sendable {
    case invalidTransition
    case invalidProgress
    case missingResult
}

struct AITask: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let type: AICapability
    private(set) var status: AITaskStatus
    private(set) var progress: Double
    let sourceImage: ImageAssetReference
    private(set) var resultImage: ImageAssetReference?
    let prompt: String?
    let parameters: [String: String]
    let createdAt: Date
    private(set) var completedAt: Date?
    private(set) var error: String?

    init(
        id: UUID = UUID(),
        type: AICapability,
        sourceImage: ImageAssetReference,
        prompt: String? = nil,
        parameters: [String: String] = [:],
        createdAt: Date = .now
    ) {
        self.id = id
        self.type = type
        status = .pending
        progress = 0
        self.sourceImage = sourceImage
        self.prompt = prompt
        self.parameters = parameters
        self.createdAt = createdAt
    }

    mutating func begin() throws {
        guard status == .pending else { throw AITaskInvariantError.invalidTransition }
        status = .processing
    }

    mutating func updateProgress(_ value: Double) throws {
        guard status == .processing, value >= progress, value >= 0, value < 1 else {
            throw AITaskInvariantError.invalidProgress
        }
        progress = value
    }

    mutating func succeed(result: ImageAssetReference? = nil, at date: Date = .now) throws {
        guard status == .processing else { throw AITaskInvariantError.invalidTransition }
        if type != .enhance && type != .portrait && result == nil {
            throw AITaskInvariantError.missingResult
        }
        resultImage = result
        progress = 1
        status = .success
        completedAt = date
    }

    mutating func fail(safeMessage: String, at date: Date = .now) throws {
        guard status == .processing else { throw AITaskInvariantError.invalidTransition }
        status = .failed
        error = safeMessage
        completedAt = date
    }

    mutating func cancel(at date: Date = .now) throws {
        guard status == .pending || status == .processing else {
            throw AITaskInvariantError.invalidTransition
        }
        status = .cancelled
        completedAt = date
    }
}

enum AIOutput: Codable, Equatable, Sendable {
    case parameterProposal([String: Double])
    case generatedImage(ImageAssetReference)

    func applyingProposal(to editState: EditState) -> EditState {
        guard case .parameterProposal(let values) = self else { return editState }
        var result = editState
        for (name, value) in values {
            guard let key = AdjustmentKey(rawValue: name) else { continue }
            result.adjustments[key] = value
        }
        return result
    }

    func generatedVersion(number: Int, preserving state: EditState) -> ImageVersion? {
        guard case .generatedImage(let asset) = self else { return nil }
        return ImageVersion(
            number: number,
            editState: state,
            commandSummary: "AI generated asset",
            generatedAsset: asset
        )
    }
}
