import Foundation

enum AIError: LocalizedError, Sendable {
    case unsupportedCapability
    case invalidRequest
    case providerFailure
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedCapability: "This AI capability is unavailable."
        case .invalidRequest: "The AI request is invalid."
        case .providerFailure: "The AI provider could not complete the request."
        case .cancelled: "The AI task was cancelled."
        }
    }
}

struct AIProviderRequest: Codable, Sendable {
    let taskID: UUID
    let capability: AICapability
    let source: ImageAssetReference
    let prompt: String?
    let parameters: [String: String]
}

struct AIProviderResult: Codable, Equatable, Sendable {
    let output: AIOutput
}

protocol AIProviderProtocol: Sendable {
    var supportedCapabilities: Set<AICapability> { get }
    var isDevelopmentOnly: Bool { get }
    func perform(_ request: AIProviderRequest) async throws -> AIProviderResult
    func cancel(taskID: UUID) async
}

protocol AIServiceProtocol: Sendable {
    func analyzeImage(_ source: ImageAssetReference) async throws -> AIOutput
    func enhance(_ source: ImageAssetReference) async throws -> AIOutput
    func removeObject(_ source: ImageAssetReference, mask: ImageAssetReference) async throws -> AIOutput
    func changeBackground(_ source: ImageAssetReference, prompt: String) async throws -> AIOutput
    func upscale(_ source: ImageAssetReference, scale: Int) async throws -> AIOutput
    func expand(_ source: ImageAssetReference, parameters: [String: String]) async throws -> AIOutput
    func generateEdit(_ source: ImageAssetReference, prompt: String) async throws -> AIOutput
    func cancel(taskID: UUID) async
}

/// DEVELOPMENT ONLY. This deterministic provider performs no network request and
/// never represents itself as a real AI backend.
struct MockAIProvider: AIProviderProtocol {
    let isDevelopmentOnly = true
    let supportedCapabilities = Set(AICapability.allCases)

    func perform(_ request: AIProviderRequest) async throws -> AIProviderResult {
        try Task.checkCancellation()
        switch request.capability {
        case .enhance, .portrait, .naturalLanguageEdit:
            return AIProviderResult(output: .parameterProposal([
                AdjustmentKey.exposure.rawValue: 0.2,
                AdjustmentKey.vibrance.rawValue: 12,
                AdjustmentKey.clarity.rawValue: 8
            ]))
        default:
            return AIProviderResult(output: .generatedImage(ImageAssetReference(
                identifier: "development-only-\(request.taskID.uuidString)",
                relativePath: "Generated/\(request.taskID.uuidString).mock"
            )))
        }
    }

    func cancel(taskID: UUID) async {}
}

struct AIService: AIServiceProtocol {
    let provider: any AIProviderProtocol

    func analyzeImage(_ source: ImageAssetReference) async throws -> AIOutput {
        try await perform(.naturalLanguageEdit, source: source, prompt: nil)
    }

    func enhance(_ source: ImageAssetReference) async throws -> AIOutput {
        try await perform(.enhance, source: source, prompt: nil)
    }

    func removeObject(_ source: ImageAssetReference, mask: ImageAssetReference) async throws -> AIOutput {
        try await perform(.remove, source: source, prompt: nil, parameters: ["mask": mask.identifier])
    }

    func changeBackground(_ source: ImageAssetReference, prompt: String) async throws -> AIOutput {
        try await perform(.background, source: source, prompt: prompt)
    }

    func upscale(_ source: ImageAssetReference, scale: Int) async throws -> AIOutput {
        try await perform(.upscale, source: source, prompt: nil, parameters: ["scale": String(scale)])
    }

    func expand(_ source: ImageAssetReference, parameters: [String: String]) async throws -> AIOutput {
        try await perform(.expand, source: source, prompt: nil, parameters: parameters)
    }

    func generateEdit(_ source: ImageAssetReference, prompt: String) async throws -> AIOutput {
        try await perform(.generativeEdit, source: source, prompt: prompt)
    }

    func cancel(taskID: UUID) async {
        await provider.cancel(taskID: taskID)
    }

    private func perform(
        _ capability: AICapability,
        source: ImageAssetReference,
        prompt: String?,
        parameters: [String: String] = [:]
    ) async throws -> AIOutput {
        guard provider.supportedCapabilities.contains(capability) else {
            throw AIError.unsupportedCapability
        }
        let id = UUID()
        do {
            return try await provider.perform(AIProviderRequest(
                taskID: id,
                capability: capability,
                source: source,
                prompt: prompt,
                parameters: parameters
            )).output
        } catch is CancellationError {
            await provider.cancel(taskID: id)
            throw AIError.cancelled
        }
    }
}
