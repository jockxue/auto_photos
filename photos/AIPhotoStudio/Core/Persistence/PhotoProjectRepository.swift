import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ProjectRepositoryError: LocalizedError {
    case unsupportedFormat
    case unreadableImage
    case imageTooLarge
    case missingOriginal
    case unsafePath
    case immutableOriginal
    case projectNotFound
    case versionConflict

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Only HEIC, JPEG, and PNG photos are supported."
        case .unreadableImage: "The selected photo could not be read."
        case .imageTooLarge: "This photo exceeds the 200-megapixel safety limit."
        case .missingOriginal: "The project's original photo is missing."
        case .unsafePath: "The project contains an unsafe storage path."
        case .immutableOriginal: "The immutable original reference cannot be changed."
        case .projectNotFound: "The project no longer exists."
        case .versionConflict: "The project was updated elsewhere. Reopen it before saving."
        }
    }
}

actor PhotoProjectRepository {
    private let root: URL
    private let projectsURL: URL
    private let originalsURL: URL
    private let thumbnailsURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = base.appendingPathComponent("AIPhotoStudio", isDirectory: true)
        projectsURL = self.root.appendingPathComponent("projects.json")
        originalsURL = self.root.appendingPathComponent("Originals", isDirectory: true)
        thumbnailsURL = self.root.appendingPathComponent("Thumbnails", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func allProjects() throws -> [PhotoProject] {
        guard FileManager.default.fileExists(atPath: projectsURL.path) else { return [] }
        try prepareDirectories()
        let projects = try decoder.decode([PhotoProject].self, from: Data(contentsOf: projectsURL))
        for project in projects {
            _ = try storageURL(for: project.originalImagePath)
            let thumbnailURL = try storageURL(for: project.thumbnailPath)
            if !FileManager.default.fileExists(atPath: thumbnailURL.path) {
                let originalURL = try storageURL(for: project.originalImagePath)
                guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil) else {
                    throw ProjectRepositoryError.missingOriginal
                }
                try Self.thumbnailData(from: source).write(to: thumbnailURL, options: .atomic)
            }
        }
        return projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    func project(id: UUID) throws -> PhotoProject? {
        try allProjects().first { $0.id == id }
    }

    func importPhoto(
        data: Data,
        suggestedName: String?,
        originalAssetIdentifier: String? = nil
    ) throws -> PhotoProject {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ProjectRepositoryError.unreadableImage
        }
        let format = try Self.format(for: CGImageSourceGetType(source))
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw ProjectRepositoryError.unreadableImage }
        try Self.validateDimensions(width: width, height: height)

        try prepareDirectories()
        let id = UUID()
        let filename = "\(id.uuidString).\(format.fileExtension)"
        let originalImagePath = "Originals/\(filename)"
        let thumbnailPath = "Thumbnails/\(id.uuidString).jpg"
        let originalURL = try storageURL(for: originalImagePath)
        let thumbnailURL = try storageURL(for: thumbnailPath)
        do {
            try data.write(to: originalURL, options: .atomic)
            try Self.thumbnailData(from: source).write(to: thumbnailURL, options: .atomic)
            var projects = try allProjects()
            let title = suggestedName?.deletingPathExtension.nonEmpty ?? "Untitled Photo"
            let project = PhotoProject(
                id: id,
                title: title,
                originalAssetIdentifier: originalAssetIdentifier,
                originalImagePath: originalImagePath,
                thumbnailPath: thumbnailPath,
                originalFormat: format,
                originalPixelWidth: width,
                originalPixelHeight: height
            )
            projects.append(project)
            try write(projects)
            return project
        } catch {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: thumbnailURL)
            throw error
        }
    }

    @discardableResult
    func update(
        _ project: PhotoProject,
        commandSummary: String = "Edit"
    ) throws -> PhotoProject {
        var projects = try allProjects()
        var updated = project
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            throw ProjectRepositoryError.projectNotFound
        }
        let stored = projects[index]
        guard
            stored.originalAssetIdentifier == project.originalAssetIdentifier,
            stored.originalImagePath == project.originalImagePath,
            stored.thumbnailPath == project.thumbnailPath,
            stored.originalFormat == project.originalFormat,
            stored.originalPixelWidth == project.originalPixelWidth,
            stored.originalPixelHeight == project.originalPixelHeight
        else { throw ProjectRepositoryError.immutableOriginal }
        guard project.currentVersion == stored.currentVersion else {
            throw ProjectRepositoryError.versionConflict
        }
        let originalURL = try storageURL(for: project.originalImagePath)
        let thumbnailURL = try storageURL(for: project.thumbnailPath)
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            throw ProjectRepositoryError.missingOriginal
        }
        if !FileManager.default.fileExists(atPath: thumbnailURL.path) {
            guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil) else {
                throw ProjectRepositoryError.unreadableImage
            }
            try Self.thumbnailData(from: source).write(to: thumbnailURL, options: .atomic)
        }
        if project.editState != stored.editState {
            updated.recordVersion(
                version: stored.currentVersion + 1,
                state: project.editState,
                summary: commandSummary
            )
        } else {
            updated.markMetadataUpdated()
        }
        projects[index] = updated
        try write(projects)
        return updated
    }

    func rename(id: UUID, title: String) throws -> PhotoProject {
        guard var project = try project(id: id) else {
            throw ProjectRepositoryError.projectNotFound
        }
        project.title = title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled Photo"
        return try update(project)
    }

    func restore(projectID: UUID, version: Int) throws -> PhotoProject {
        guard var project = try project(id: projectID) else {
            throw ProjectRepositoryError.projectNotFound
        }
        guard let snapshot = project.versions.first(where: { $0.number == version }) else {
            throw ProjectRepositoryError.projectNotFound
        }
        project.editState = snapshot.editState
        return try update(project)
    }

    func delete(id: UUID) throws {
        var projects = try allProjects()
        guard let project = projects.first(where: { $0.id == id }) else { return }
        projects.removeAll { $0.id == id }
        try write(projects)
        var firstError: Error?
        do {
            try removeIfPresent(try storageURL(for: project.originalImagePath))
        } catch {
            firstError = error
        }
        do {
            try removeIfPresent(try storageURL(for: project.thumbnailPath))
        } catch {
            firstError = firstError ?? error
        }
        if let firstError { throw firstError }
    }

    func originalData(for project: PhotoProject) throws -> Data {
        let url = try storageURL(for: project.originalImagePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectRepositoryError.missingOriginal
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    func originalFileURL(for project: PhotoProject) throws -> URL {
        let url = try storageURL(for: project.originalImagePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectRepositoryError.missingOriginal
        }
        return url
    }

    func thumbnailData(for project: PhotoProject) throws -> Data {
        try Data(contentsOf: storageURL(for: project.thumbnailPath), options: .mappedIfSafe)
    }

    func replaceThumbnail(_ image: CGImage, for project: PhotoProject) throws {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw ProjectRepositoryError.unreadableImage }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ProjectRepositoryError.unreadableImage
        }
        try (output as Data).write(to: storageURL(for: project.thumbnailPath), options: .atomic)
    }

    func fileExists(atRelativePath path: String) throws -> Bool {
        FileManager.default.fileExists(atPath: try storageURL(for: path).path)
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: originalsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
    }

    private func write(_ projects: [PhotoProject]) throws {
        try prepareDirectories()
        try encoder.encode(projects).write(to: projectsURL, options: .atomic)
    }

    private static func format(for type: CFString?) throws -> PhotoFormat {
        guard let type else { throw ProjectRepositoryError.unsupportedFormat }
        let identifier = type as String
        if identifier == UTType.jpeg.identifier { return .jpeg }
        if identifier == UTType.png.identifier { return .png }
        if identifier == UTType.heic.identifier || identifier == UTType.heif.identifier { return .heic }
        throw ProjectRepositoryError.unsupportedFormat
    }

    static func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0, Int64(width) * Int64(height) <= 200_000_000 else {
            throw ProjectRepositoryError.imageTooLarge
        }
    }

    private func storageURL(for relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw ProjectRepositoryError.unsafePath
        }
        let standardizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = standardizedRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(standardizedRoot.path + "/") else {
            throw ProjectRepositoryError.unsafePath
        }
        return candidate
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func thumbnailData(from source: CGImageSource) throws -> Data {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
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
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ProjectRepositoryError.unreadableImage
        }
        return output as Data
    }
}

private extension PhotoFormat {
    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .heic: "heic"
        case .png: "png"
        }
    }
}

private extension String {
    var deletingPathExtension: String { (self as NSString).deletingPathExtension }
    var nonEmpty: String? { isEmpty ? nil : self }
}
