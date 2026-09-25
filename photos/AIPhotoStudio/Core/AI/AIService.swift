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
    func execute(_ task: AITask) async throws -> AITask
    func analyzeImage(_ source: ImageAssetReference) async throws -> AIOutput
    func enhance(_ source: ImageAssetReference) async throws -> AIOutput
    func removeObject(_ source: ImageAssetReference, mask: ImageAssetReference) async throws -> AIOutput
    func changeBackground(_ source: ImageAssetReference, prompt: String) async throws -> AIOutput
    func upscale(_ source: ImageAssetReference, scale: Int) async throws -> AIOutput
    func expand(_ source: ImageAssetReference, parameters: [String: String]) async throws -> AIOutput
    func generateEdit(_ source: ImageAssetReference, prompt: String) async throws -> AIOutput
    func cancel(taskID: UUID) async
}

protocol AITaskStoreProtocol: Sendable {
    func save(_ task: AITask) async
    func saveUnlessCancelled(_ task: AITask) async -> AITask
    func task(id: UUID) async -> AITask?
    func requestCancellation(id: UUID) async
    func isCancellationRequested(id: UUID) async -> Bool
}

actor InMemoryAITaskStore: AITaskStoreProtocol {
    private var tasks: [UUID: AITask] = [:]
    private var cancellationRequests: Set<UUID> = []
    func save(_ task: AITask) { tasks[task.id] = task }
    func saveUnlessCancelled(_ task: AITask) -> AITask {
        if cancellationRequests.contains(task.id) {
            if var existing = tasks[task.id], existing.status != .cancelled {
                try? existing.cancel()
                tasks[task.id] = existing
            }
            return tasks[task.id] ?? task
        }
        tasks[task.id] = task
        return task
    }
    func task(id: UUID) -> AITask? { tasks[id] }
    func requestCancellation(id: UUID) { cancellationRequests.insert(id) }
    func isCancellationRequested(id: UUID) -> Bool { cancellationRequests.contains(id) }
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
    let taskStore: any AITaskStoreProtocol

    init(
        provider: any AIProviderProtocol,
        taskStore: any AITaskStoreProtocol = InMemoryAITaskStore()
    ) {
        self.provider = provider
        self.taskStore = taskStore
    }

    func execute(_ input: AITask) async throws -> AITask {
        guard provider.supportedCapabilities.contains(input.type) else {
            throw AIError.unsupportedCapability
        }
        var task = input
        await taskStore.save(task)
        if await taskStore.isCancellationRequested(id: task.id) {
            try task.cancel()
            await taskStore.save(task)
            return task
        }
        do {
            try task.begin()
            task = await taskStore.saveUnlessCancelled(task)
            if task.status == .cancelled { return task }
            try task.updateProgress(0.05)
            task = await taskStore.saveUnlessCancelled(task)
            if task.status == .cancelled { return task }
            let result = try await provider.perform(AIProviderRequest(
                taskID: task.id,
                capability: task.type,
                source: task.sourceImage,
                prompt: task.prompt,
                parameters: task.parameters
            ))
            try Task.checkCancellation()
            if let stored = await taskStore.task(id: task.id), stored.status == .cancelled {
                await provider.cancel(taskID: task.id)
                return stored
            }
            try task.updateProgress(0.9)
            task = await taskStore.saveUnlessCancelled(task)
            if task.status == .cancelled { return task }
            try task.succeed(output: result.output)
            task = await taskStore.saveUnlessCancelled(task)
            return task
        } catch is CancellationError {
            await provider.cancel(taskID: task.id)
            try? task.cancel()
            await taskStore.save(task)
            return task
        } catch {
            if await taskStore.isCancellationRequested(id: task.id) {
                if task.status == .processing { try? task.cancel() }
                await taskStore.save(task)
                return task
            } else if task.status == .processing {
                try? task.fail(safeMessage: AIError.providerFailure.localizedDescription)
                _ = await taskStore.saveUnlessCancelled(task)
            }
            throw error
        }
    }

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
        await taskStore.requestCancellation(id: taskID)
        await provider.cancel(taskID: taskID)
        if var task = await taskStore.task(id: taskID) {
            try? task.cancel()
            await taskStore.save(task)
        }
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
