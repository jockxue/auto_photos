import Foundation
import CoreImage
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
        case .imageTooLarge: "This photo exceeds the 24-megapixel memory safety limit."
        case .missingOriginal: "The project's original photo is missing."
        case .unsafePath: "The project contains an unsafe storage path."
        case .immutableOriginal: "The immutable original reference cannot be changed."
        case .projectNotFound: "The project no longer exists."
        case .versionConflict: "The project was updated elsewhere. Reopen it before saving."
        }
    }
}

actor PhotoProjectRepository {
    private struct DeleteJournal: Codable {
        struct Entry: Codable {
            let relativePath: String
            let stagedName: String
        }

        let projectID: UUID
        let entries: [Entry]
    }

    private let root: URL
    private let projectsURL: URL
    private let originalsURL: URL
    private let thumbnailsURL: URL
    private let trashURL: URL
    private let generatedURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = base.appendingPathComponent("AIPhotoStudio", isDirectory: true)
        projectsURL = self.root.appendingPathComponent("projects.json")
        originalsURL = self.root.appendingPathComponent("Originals", isDirectory: true)
        thumbnailsURL = self.root.appendingPathComponent("Thumbnails", isDirectory: true)
        trashURL = self.root.appendingPathComponent(".Trash", isDirectory: true)
        generatedURL = self.root.appendingPathComponent("Generated", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func allProjects() throws -> [PhotoProject] {
        guard FileManager.default.fileExists(atPath: projectsURL.path) else { return [] }
        try prepareDirectories()
        let projects = try decoder.decode([PhotoProject].self, from: Data(contentsOf: projectsURL))
        try recoverDeleteTransactions(projects: projects)
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
        return try update(project, commandSummary: "Restore v\(version)")
    }

    /// Actor-isolated edit save avoids stale caller versions during autosave,
    /// Done, background flush, and export flush races.
    func saveEditState(
        projectID: UUID,
        editState: EditState,
        commandSummary: String
    ) throws -> PhotoProject {
        var projects = try allProjects()
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectRepositoryError.projectNotFound
        }
        var project = projects[index]
        if project.editState != editState {
            project.recordVersion(
                version: project.currentVersion + 1,
                state: editState,
                summary: commandSummary
            )
            projects[index] = project
            try write(projects)
        }
        return project
    }

    func appendGeneratedVersion(
        projectID: UUID,
        asset: ImageAssetReference,
        editState: EditState,
        summary: String
    ) throws -> PhotoProject {
        let assetURL = try generatedAssetURL(for: asset.relativePath)
        guard FileManager.default.fileExists(atPath: assetURL.path) else {
            throw ProjectRepositoryError.missingOriginal
        }
        var projects = try allProjects()
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectRepositoryError.projectNotFound
        }
        var project = projects[index]
        project.recordVersion(
            version: project.currentVersion + 1,
            state: editState,
            summary: summary,
            generatedAsset: asset
        )
        projects[index] = project
        try write(projects)
        return project
    }

    func delete(id: UUID) throws {
        var projects = try allProjects()
        let transactionURL = trashURL.appendingPathComponent(id.uuidString, isDirectory: true)
        guard let project = projects.first(where: { $0.id == id }) else {
            try? FileManager.default.removeItem(at: transactionURL)
            return
        }
        let referencedByOthers = Set(projects
            .filter { $0.id != id }
            .flatMap { $0.versions.compactMap { $0.generatedAsset?.relativePath } })
        var relativePaths = [project.originalImagePath, project.thumbnailPath]
        let generatedPaths = Set(project.versions.compactMap { $0.generatedAsset?.relativePath })
        relativePaths += generatedPaths.filter {
            (try? generatedAssetURL(for: $0)) != nil && !referencedByOthers.contains($0)
        }
        relativePaths.append("Cache/\(project.id.uuidString)")
        let entries = try relativePaths.enumerated().compactMap { index, relativePath -> DeleteJournal.Entry? in
            let source = try storageURL(for: relativePath)
            guard FileManager.default.fileExists(atPath: source.path) else { return nil }
            return DeleteJournal.Entry(
                relativePath: relativePath,
                stagedName: "\(index)-\(source.lastPathComponent)"
            )
        }
        try FileManager.default.createDirectory(at: transactionURL, withIntermediateDirectories: true)
        let journal = DeleteJournal(projectID: id, entries: entries)
        try encoder.encode(journal).write(
            to: transactionURL.appendingPathComponent("journal.json"),
            options: .atomic
        )
        var moves: [(source: URL, staged: URL)] = []
        do {
            for entry in entries {
                let source = try storageURL(for: entry.relativePath)
                let staged = transactionURL.appendingPathComponent(entry.stagedName)
                try FileManager.default.moveItem(at: source, to: staged)
                moves.append((source, staged))
            }
        } catch {
            for move in moves.reversed() {
                try? FileManager.default.moveItem(at: move.staged, to: move.source)
            }
            throw error
        }

        projects.removeAll { $0.id == id }
        do {
            try write(projects)
        } catch {
            for move in moves.reversed() {
                try? FileManager.default.createDirectory(
                    at: move.source.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.moveItem(at: move.staged, to: move.source)
            }
            throw error
        }
        // Metadata commit is authoritative. Cleanup is idempotent and retried
        // on the next repository read if immediate removal fails.
        try? FileManager.default.removeItem(at: transactionURL)
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
        let maximumDimension = max(image.width, image.height)
        let thumbnail: CGImage
        if maximumDimension > 512 {
            let scale = 512 / CGFloat(maximumDimension)
            let source = CIImage(cgImage: image)
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let resized = CIContext(options: [.useSoftwareRenderer: false])
                .createCGImage(source, from: source.extent.integral) else {
                throw ProjectRepositoryError.unreadableImage
            }
            thumbnail = resized
        } else {
            thumbnail = image
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw ProjectRepositoryError.unreadableImage }
        CGImageDestinationAddImage(destination, thumbnail, [
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
        try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generatedURL, withIntermediateDirectories: true)
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
        guard
            width > 0,
            height > 0,
            Int64(width) * Int64(height) <= Int64(ImageMemoryPolicy.maximumRenderedPixels)
        else {
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

    private func generatedAssetURL(for relativePath: String) throws -> URL {
        let candidate = try storageURL(for: relativePath)
        let generatedRoot = generatedURL.standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(generatedRoot.path + "/") else {
            throw ProjectRepositoryError.unsafePath
        }
        return candidate
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func recoverDeleteTransactions(projects: [PhotoProject]) throws {
        guard let transactions = try? FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for transaction in transactions {
            let journalURL = transaction.appendingPathComponent("journal.json")
            guard
                let data = try? Data(contentsOf: journalURL),
                let journal = try? decoder.decode(DeleteJournal.self, from: data)
            else {
                // Unknown trash is never deleted automatically.
                continue
            }
            if projects.contains(where: { $0.id == journal.projectID }) {
                for entry in journal.entries {
                    guard
                        !entry.stagedName.contains("/"),
                        !entry.stagedName.contains("\\"),
                        URL(fileURLWithPath: entry.stagedName).lastPathComponent == entry.stagedName
                    else {
                        throw ProjectRepositoryError.unsafePath
                    }
                    let source = try storageURL(for: entry.relativePath)
                    let staged = transaction.appendingPathComponent(entry.stagedName)
                    guard FileManager.default.fileExists(atPath: staged.path) else { continue }
                    if FileManager.default.fileExists(atPath: source.path) {
                        try FileManager.default.removeItem(at: staged)
                    } else {
                        try FileManager.default.createDirectory(
                            at: source.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try FileManager.default.moveItem(at: staged, to: source)
                    }
                }
            }
            try FileManager.default.removeItem(at: transaction)
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
