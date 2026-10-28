import Photos
import SwiftUI

struct PhotoSelectionView: View {
    let onPicked: ([PickedPhoto]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PhotoSelectionModel()
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            FilmToneTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Text(L10n.text("Choose one photo from your library to start editing."))
                    .font(FilmToneTheme.body)
                    .foregroundStyle(FilmToneTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                chips
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                sectionHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                Group {
                    if model.needsPermission {
                        permission
                    } else if model.source == .albums && model.selectedAlbum == nil {
                        albumList
                    } else {
                        photoGrid
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let errorMessage {
                    Text(errorMessage)
                        .font(FilmToneTheme.caption)
                        .foregroundStyle(FilmToneTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                bottomBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        ZStack {
            Text(L10n.text("Select a Photo"))
                .font(FilmToneTheme.pageTitle)
                .foregroundStyle(FilmToneTheme.primaryText)
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(FilmToneTheme.primaryText)
                        .frame(width: 22, height: 22)
                }
                .accessibilityLabel(L10n.text("Back"))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip(.all, title: "All Library Photos")
            chip(.albums, title: "Albums")
            chip(.recent, title: "Recent")
            Spacer(minLength: 0)
        }
    }

    private func chip(_ source: PhotoSource, title: String) -> some View {
        let selected = model.source == source
        return Button {
            model.select(source)
        } label: {
            Text(L10n.text(title))
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? FilmToneTheme.accentText : FilmToneTheme.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    selected ? FilmToneTheme.accent : FilmToneTheme.chipBackground,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var sectionHeader: some View {
        HStack {
            Text(sectionTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FilmToneTheme.primaryText)
                .lineLimit(1)
            Spacer()
            Text(L10n.text("Select multiple"))
                .font(FilmToneTheme.body)
                .foregroundStyle(FilmToneTheme.secondaryText)
        }
    }

    private var sectionTitle: String {
        switch model.source {
        case .all:
            L10n.text("Recents")
        case .recent:
            L10n.text("Recent")
        case .albums:
            model.selectedAlbum?.localizedTitle ?? L10n.text("Albums")
        }
    }

    private var permission: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(model.authorization == .notDetermined
                 ? L10n.text("Allow Photo Access")
                 : L10n.text("Photo Library access is denied. The private system picker can still share selected photos."))
                .font(FilmToneTheme.body)
                .foregroundStyle(FilmToneTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button(model.authorization == .notDetermined
                   ? L10n.text("Allow Photo Access")
                   : L10n.text("Open Settings")) {
                if model.authorization == .notDetermined {
                    model.start()
                } else {
                    model.openSettings()
                }
            }
            .font(FilmToneTheme.button)
            .foregroundStyle(FilmToneTheme.accentText)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(FilmToneTheme.accent, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var albumList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.albums.isEmpty {
                    Text(L10n.text("No photos in your library."))
                        .font(FilmToneTheme.body)
                        .foregroundStyle(FilmToneTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                ForEach(model.albums, id: \.localIdentifier) { album in
                    Button {
                        model.open(album)
                    } label: {
                        HStack {
                            Text(album.localizedTitle ?? L10n.text("Albums"))
                                .font(FilmToneTheme.body.weight(.semibold))
                                .foregroundStyle(FilmToneTheme.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(FilmToneTheme.caption.weight(.semibold))
                                .foregroundStyle(FilmToneTheme.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var photoGrid: some View {
        ScrollView {
            if model.assets.isEmpty {
                Text(L10n.text("No photos in your library."))
                    .font(FilmToneTheme.body)
                    .foregroundStyle(FilmToneTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 21)
                    .padding(.top, 8)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3),
                    spacing: 10
                ) {
                    ForEach(model.assets, id: \.localIdentifier) { asset in
                        Button {
                            model.toggle(asset)
                        } label: {
                            SelectionThumbnail(
                                asset: asset,
                                selected: model.isSelected(asset),
                                loader: model
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 21)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            SelectionThumbnail(
                asset: model.selectedAssets.last,
                selected: false,
                loader: model,
                side: 44,
                cornerRadius: 8
            )
            Text(L10n.format("Selected %lld photos", Int64(model.selectedAssets.count)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FilmToneTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: confirm) {
                Group {
                    if isPreparing {
                        ProgressView()
                            .tint(FilmToneTheme.accentText)
                    } else {
                        Text(L10n.text("Next Step"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(FilmToneTheme.accentText)
                .frame(width: 78, height: 36)
                .background(
                    FilmToneTheme.accent,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(model.selectedAssets.isEmpty || isPreparing)
            .opacity(model.selectedAssets.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(FilmToneTheme.tabBar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FilmToneTheme.divider)
                .frame(height: 1)
        }
    }

    private func confirm() {
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        Task {
            defer { isPreparing = false }
            guard let photos = await model.makePickedPhotos() else {
                errorMessage = L10n.text("The photo could not be loaded.")
                return
            }
            dismiss()
            onPicked(photos)
        }
    }
}

private struct SelectionThumbnail: View {
    let asset: PHAsset?
    let selected: Bool
    let loader: PhotoSelectionModel
    var side: CGFloat?
    /// Figma tile path on the 104×104 photo is the same on all four corners, about 5pt.
    var cornerRadius: CGFloat = 5

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(width: side)
            .overlay {
                GeometryReader { proxy in
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            FilmToneTheme.chipBackground
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FilmToneTheme.accentText)
                        .frame(width: 20, height: 20)
                        .background(FilmToneTheme.accent, in: Circle())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .circular))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .circular))
            .task(id: asset?.localIdentifier) {
                image = nil
                guard let asset else { return }
                image = await loader.thumbnail(for: asset)
            }
    }
}

private enum PhotoSource: Hashable {
    case all
    case albums
    case recent
}

@MainActor
private final class PhotoSelectionModel: NSObject, ObservableObject {
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var albums: [PHAssetCollection] = []
    @Published var source: PhotoSource = .all
    @Published var selectedAlbum: PHAssetCollection?
    @Published private(set) var selectedAssets: [PHAsset] = []

    private let imageManager = PHCachingImageManager()
    private var isObserving = false

    var needsPermission: Bool {
        PhotoLibraryAccess.needsPrompt(for: authorization)
    }

    func isSelected(_ asset: PHAsset) -> Bool {
        selectedAssets.contains { $0.localIdentifier == asset.localIdentifier }
    }

    func toggle(_ asset: PHAsset) {
        if let index = selectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            selectedAssets.remove(at: index)
        } else {
            selectedAssets.append(asset)
        }
    }

    func start() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            isObserving = true
        }
        guard !needsPermission else {
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
        if isObserving {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            isObserving = false
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func select(_ source: PhotoSource) {
        self.source = source
        if source != .albums {
            selectedAlbum = nil
        }
        reload()
    }

    func open(_ album: PHAssetCollection) {
        selectedAlbum = album
        reload()
    }

    func thumbnail(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            let gate = ResumeOnce<UIImage?>()
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 312, height: 312),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                guard !degraded else { return }
                gate.resume(continuation, with: cancelled ? nil : image)
            }
        }
    }

    func makePickedPhotos() async -> [PickedPhoto]? {
        guard !selectedAssets.isEmpty else { return nil }
        var photos: [PickedPhoto] = []
        for asset in selectedAssets {
            guard let photo = await pickedPhoto(for: asset) else { return nil }
            photos.append(photo)
        }
        return photos
    }

    private func pickedPhoto(for asset: PHAsset) async -> PickedPhoto? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        let data: Data? = await withCheckedContinuation { continuation in
            let gate = ResumeOnce<Data?>()
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                guard !degraded else { return }
                gate.resume(continuation, with: cancelled ? nil : data)
            }
        }
        guard let data else { return nil }
        let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename
        return PickedPhoto(
            data: data,
            suggestedName: filename,
            originalAssetIdentifier: asset.localIdentifier
        )
    }

    private func reload() {
        guard !needsPermission else {
            assets = []
            albums = []
            return
        }
        if source == .albums && selectedAlbum == nil {
            albums = Self.userAlbums()
            assets = []
            return
        }
        let result = Self.fetchImages(source: source, album: selectedAlbum)
        var fetched: [PHAsset] = []
        fetched.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched
    }

    private static func imageOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return options
    }

    private static func fetchImages(source: PhotoSource, album: PHAssetCollection?) -> PHFetchResult<PHAsset> {
        let options = imageOptions()
        switch source {
        case .all:
            return PHAsset.fetchAssets(with: .image, options: options)
        case .recent:
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumRecentlyAdded,
                options: nil
            )
            if let collection = collections.firstObject {
                return PHAsset.fetchAssets(in: collection, options: options)
            }
            return PHAsset.fetchAssets(with: .image, options: options)
        case .albums:
            if let album {
                return PHAsset.fetchAssets(in: album, options: options)
            }
            return PHAsset.fetchAssets(with: .image, options: options)
        }
    }

    private static func userAlbums() -> [PHAssetCollection] {
        let options = imageOptions()
        var list: [PHAssetCollection] = []
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        albums.enumerateObjects { collection, _, _ in
            if PHAsset.fetchAssets(in: collection, options: options).count > 0 {
                list.append(collection)
            }
        }
        return list
    }
}

extension PhotoSelectionModel: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.reload()
        }
    }
}

private final class ResumeOnce<T>: @unchecked Sendable {
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
