import Foundation

enum EditCommandKind: String, Codable, Sendable {
    case adjust, filter, crop, rotate
    case aiBoundary, maskBoundary, hslBoundary, curveBoundary
}

struct EditCommand: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: EditCommandKind
    let before: EditState
    let after: EditState
    let summary: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: EditCommandKind,
        before: EditState,
        after: EditState,
        summary: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.before = before
        self.after = after
        self.summary = summary
        self.createdAt = createdAt
    }
}

/// One source of truth for snapshot-based undo and persisted command summaries.
/// Gesture begin/end coalesces all intermediate slider frames into one command.
struct EditHistory: Sendable {
    private struct PendingCommand: Sendable {
        let kind: EditCommandKind
        let before: EditState
        let summary: String
    }

    private(set) var undoCommands: [EditCommand] = []
    private(set) var redoCommands: [EditCommand] = []
    private var pending: PendingCommand?

    var canUndo: Bool { !undoCommands.isEmpty }
    var canRedo: Bool { !redoCommands.isEmpty }
    var isCoalescing: Bool { pending != nil }
    var latestSummary: String? { undoCommands.last?.summary }

    mutating func begin(kind: EditCommandKind, state: EditState, summary: String) {
        if pending == nil { pending = PendingCommand(kind: kind, before: state, summary: summary) }
    }

    mutating func end(state: EditState) {
        guard let pending else { return }
        self.pending = nil
        record(kind: pending.kind, before: pending.before, after: state, summary: pending.summary)
    }

    mutating func record(
        kind: EditCommandKind,
        before: EditState,
        after: EditState,
        summary: String
    ) {
        guard before != after else { return }
        undoCommands.append(EditCommand(
            kind: kind,
            before: before,
            after: after,
            summary: summary
        ))
        redoCommands.removeAll()
    }

    mutating func undo(current: EditState) -> EditState? {
        guard let command = undoCommands.popLast() else { return nil }
        redoCommands.append(command)
        return command.before
    }

    mutating func redo(current: EditState) -> EditState? {
        guard let command = redoCommands.popLast() else { return nil }
        undoCommands.append(command)
        return command.after
    }
}
