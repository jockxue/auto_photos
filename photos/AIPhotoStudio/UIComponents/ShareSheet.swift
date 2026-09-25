import SwiftUI
import UIKit

final class SharePayload: Identifiable {
    let id = UUID()
    let fileURL: URL
    private let deleteWhenReleased: Bool

    init(fileURL: URL, deleteWhenReleased: Bool = true) {
        self.fileURL = fileURL
        self.deleteWhenReleased = deleteWhenReleased
    }

    deinit {
        if deleteWhenReleased {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

/// SwiftUI boundary around the system share controller. Export/business
/// services only produce a completed file URL and never depend on View/UIKit.
struct ShareSheet: UIViewControllerRepresentable {
    let payload: SharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [payload.fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
