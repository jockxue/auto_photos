import Photos
import UIKit

@MainActor
final class PhotoLibraryViewModel: NSObject, ObservableObject {
    @Published private(set) var controller = PhotoBrowseController()
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var image: UIImage?
    @Published private(set) var isLoadingImage = false

    private let imageManager = PHCachingImageManager()
    @Published private(set) var assets: [PHAsset] = []
    private var requestID: PHImageRequestID?
    private var isObserving = false

    var needsPermissionPrompt: Bool {
        PhotoLibraryAccess.needsPrompt(for: authorization)
    }

    func start() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            isObserving = true
        }
        if needsPermissionPrompt {
            if authorization == .notDetermined {
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                    Task { @MainActor in
                        self?.authorization = status
                        self?.reload()
                    }
                }
            }
            return
        }
        reload()
    }

    func stop() {
        cancelRequest()
        if isObserving {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            isObserving = false
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func showNext() {
        controller.showNext()
        loadCurrentImage()
    }

    func showPrevious() {
        controller.showPrevious()
        loadCurrentImage()
    }

    func show(at index: Int) {
        let before = controller.index
        controller.show(at: index)
        guard controller.index != before else { return }
        loadCurrentImage()
    }

    func noteMessage(_ message: String) {
        controller.lastError = message
    }

    func thumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let gate = OnceGate<UIImage?>()
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 240, height: 240),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                gate.resume(continuation, with: image)
            }
        }
    }

    func currentPhotoFile() async -> (data: Data, identifier: String, filename: String?)? {
        guard !controller.isDeleting, assets.indices.contains(controller.index) else { return nil }
        let asset = assets[controller.index]
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        let data: Data? = await withCheckedContinuation { continuation in
            let gate = OnceGate<Data?>()
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                gate.resume(continuation, with: cancelled ? nil : data)
            }
        }
        guard let data else { return nil }
        let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename
        return (data, asset.localIdentifier, filename)
    }

    func deleteCurrent() {
        guard let identifier = controller.startDeleting(),
              let asset = assets.first(where: { $0.localIdentifier == identifier }) else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.controller.noteDeleteSucceeded(identifier: identifier)
                    self.assets.removeAll { $0.localIdentifier == identifier }
                    self.loadCurrentImage()
                } else {
                    self.controller.noteDeleteFailed(
                        error?.localizedDescription ?? L10n.text("The photo could not be deleted.")
                    )
                }
            }
        }
    }

    private func reload() {
        guard !needsPermissionPrompt else {
            assets = []
            controller = PhotoBrowseController()
            image = nil
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var fetched: [PHAsset] = []
        fetched.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        let currentID = assets.indices.contains(controller.index) ? assets[controller.index].localIdentifier : nil
        assets = fetched
        controller.identifiers = fetched.map(\.localIdentifier)
        if fetched.isEmpty {
            controller.index = 0
            image = nil
        } else if let currentID, let kept = fetched.firstIndex(where: { $0.localIdentifier == currentID }) {
            controller.index = kept
        } else {
            controller.index = min(controller.index, fetched.count - 1)
        }
        loadCurrentImage()
    }

    private func loadCurrentImage() {
        cancelRequest()
        guard assets.indices.contains(controller.index) else {
            image = nil
            isLoadingImage = false
            return
        }
        let asset = assets[controller.index]
        let neighbors = [controller.index - 1, controller.index + 1].compactMap { index in
            assets.indices.contains(index) ? assets[index] : nil
        }
        imageManager.startCachingImages(
            for: neighbors,
            targetSize: Self.previewSize,
            contentMode: .aspectFit,
            options: nil
        )
        isLoadingImage = image == nil
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        requestID = imageManager.requestImage(
            for: asset,
            targetSize: Self.previewSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            Task { @MainActor in
                guard let self, !cancelled else { return }
                if let image {
                    self.image = image
                    self.isLoadingImage = false
                } else if (info?[PHImageErrorKey] as? Error) != nil {
                    self.controller.lastError = L10n.text("The photo could not be loaded.")
                    self.isLoadingImage = false
                }
            }
        }
    }

    private func cancelRequest() {
        if let requestID {
            imageManager.cancelImageRequest(requestID)
            self.requestID = nil
        }
    }

    private static let previewSize = CGSize(width: 1600, height: 1600)
}

private final class OnceGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<T, Never>, with value: T) {
        lock.lock()
        let shouldResume = !didResume
        didResume = true
        lock.unlock()
        if shouldResume {
            continuation.resume(returning: value)
        }
    }
}

extension PhotoLibraryViewModel: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.reload()
        }
    }
}
