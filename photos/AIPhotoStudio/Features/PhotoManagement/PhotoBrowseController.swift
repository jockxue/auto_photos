import Foundation
import Photos

enum PhotoLibraryAccess {
    static func needsPrompt(for status: PHAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .limited: false
        default: true
        }
    }
}

struct PhotoBrowseController: Equatable {
    var identifiers: [String] = []
    var index = 0
    var isDeleting = false
    var lastError: String?

    var isEmpty: Bool { identifiers.isEmpty }

    var positionText: String? {
        guard !identifiers.isEmpty, identifiers.indices.contains(index) else { return nil }
        return "\(index + 1) / \(identifiers.count)"
    }

    mutating func showNext() {
        guard canBrowse, index + 1 < identifiers.count else { return }
        index += 1
    }

    mutating func showPrevious() {
        guard canBrowse, index > 0 else { return }
        index -= 1
    }

    mutating func show(at newIndex: Int) {
        guard canBrowse, identifiers.indices.contains(newIndex) else { return }
        index = newIndex
    }

    /// Starts one delete and returns the identifier captured at this moment.
    mutating func startDeleting() -> String? {
        guard !isDeleting, identifiers.indices.contains(index) else { return nil }
        isDeleting = true
        lastError = nil
        return identifiers[index]
    }

    mutating func noteDeleteSucceeded(identifier: String) {
        defer {
            isDeleting = false
            lastError = nil
        }
        guard let removed = identifiers.firstIndex(of: identifier) else { return }
        identifiers.remove(at: removed)
        if identifiers.isEmpty {
            index = 0
        } else if index > removed {
            index -= 1
        } else if index >= identifiers.count {
            index = identifiers.count - 1
        }
    }

    mutating func noteDeleteFailed(_ message: String) {
        isDeleting = false
        lastError = message
    }

    private var canBrowse: Bool { !isDeleting }
}
