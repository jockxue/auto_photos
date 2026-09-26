import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PickedPhoto {
    let data: Data
    let suggestedName: String?
    /// Optional by design: PHPicker may withhold identifiers for privacy or for
    /// file-provider-backed selections while still supplying image data.
    let originalAssetIdentifier: String?
}

/// Thin SwiftUI bridge to Apple's PHPicker. UIKit is used only to host the
/// system picker; all product UI remains SwiftUI.
struct SystemPhotoPicker: UIViewControllerRepresentable {
    var maximumPixelSize: Int? = nil
    let onSelection: ([PickedPhoto]) -> Void
    let onCancel: () -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            maximumPixelSize: maximumPixelSize,
            onSelection: onSelection,
            onCancel: onCancel,
            onFailure: onFailure
        )
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
        private let maximumPixelSize: Int?
        private let onSelection: ([PickedPhoto]) -> Void
        private let onCancel: () -> Void
        private let onFailure: (Error) -> Void

        init(
            maximumPixelSize: Int?,
            onSelection: @escaping ([PickedPhoto]) -> Void,
            onCancel: @escaping () -> Void,
            onFailure: @escaping (Error) -> Void
        ) {
            self.maximumPixelSize = maximumPixelSize
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
                        let fitted = try Self.fittedData(data, maximumPixelSize: maximumPixelSize)
                        photos.append(PickedPhoto(
                            data: fitted,
                            suggestedName: provider.suggestedName,
                            originalAssetIdentifier: result.assetIdentifier
                        ))
                    }
                    await MainActor.run { onSelection(photos) }
                } catch {
                    await MainActor.run { onFailure(error) }
                }
            }
        }

        private static func fittedData(_ data: Data, maximumPixelSize: Int?) throws -> Data {
            guard let maximumPixelSize else { return data }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw ProjectRepositoryError.unreadableImage
            }
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else {
                throw ProjectRepositoryError.unreadableImage
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw ProjectRepositoryError.unreadableImage
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw ProjectRepositoryError.unreadableImage
            }
            return output as Data
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
