import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PickedPhoto {
    let data: Data
    let suggestedName: String?
}

/// Thin SwiftUI bridge to Apple's PHPicker. UIKit is used only to host the
/// system picker; all product UI remains SwiftUI.
struct SystemPhotoPicker: UIViewControllerRepresentable {
    let onSelection: ([PickedPhoto]) -> Void
    let onCancel: () -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection, onCancel: onCancel, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onSelection: ([PickedPhoto]) -> Void
        private let onCancel: () -> Void
        private let onFailure: (Error) -> Void

        init(
            onSelection: @escaping ([PickedPhoto]) -> Void,
            onCancel: @escaping () -> Void,
            onFailure: @escaping (Error) -> Void
        ) {
            self.onSelection = onSelection
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                onCancel()
                return
            }
            Task {
                do {
                    var photos: [PickedPhoto] = []
                    for result in results {
                        let provider = result.itemProvider
                        guard let identifier = provider.registeredTypeIdentifiers.first(where: {
                            UTType($0)?.conforms(to: .image) == true
                        }) else {
                            throw ProjectRepositoryError.unsupportedFormat
                        }
                        let data = try await provider.dataRepresentation(for: identifier)
                        photos.append(PickedPhoto(data: data, suggestedName: provider.suggestedName))
                    }
                    await MainActor.run { onSelection(photos) }
                } catch {
                    await MainActor.run { onFailure(error) }
                }
            }
        }
    }
}

private extension NSItemProvider {
    func dataRepresentation(for typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? ProjectRepositoryError.unreadableImage)
                }
            }
        }
    }
}
