import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ProjectRepositoryError: LocalizedError {
    case unsupportedFormat
    case unreadableImage
    case imageTooLarge
    case missingOriginal

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Only HEIC, JPEG, and PNG photos are supported."
        case .unreadableImage: "The selected photo could not be read."
        case .imageTooLarge: "This photo exceeds the 200-megapixel safety limit."
        case .missingOriginal: "The project's original photo is missing."
        }
    }
}

actor PhotoProjectRepository {
    private let root: URL
    private let projectsURL: URL
    private let originalsURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = base.appendingPathComponent("AIPhotoStudio", isDirectory: true)
        projectsURL = self.root.appendingPathComponent("projects.json")
        originalsURL = self.root.appendingPathComponent("Originals", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func allProjects() throws -> [PhotoProject] {
        guard FileManager.default.fileExists(atPath: projectsURL.path) else { return [] }
        return try decoder.decode([PhotoProject].self, from: Data(contentsOf: projectsURL))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func project(id: UUID) throws -> PhotoProject? {
        try allProjects().first { $0.id == id }
    }

    func importPhoto(data: Data, suggestedName: String?) throws -> PhotoProject {
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
        try data.write(to: originalsURL.appendingPathComponent(filename), options: .atomic)
        var projects = try allProjects()
        let title = suggestedName?.deletingPathExtension.nonEmpty ?? "Untitled Photo"
        let project = PhotoProject(
            id: id,
            title: title,
            originalFilename: filename,
            originalFormat: format,
            originalPixelWidth: width,
            originalPixelHeight: height
        )
        projects.append(project)
        try write(projects)
        return project
    }

    func update(_ project: PhotoProject) throws {
        var projects = try allProjects()
        var updated = project
        updated.updatedAt = .now
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updated
        } else {
            projects.append(updated)
        }
        try write(projects)
    }

    func delete(id: UUID) throws {
        var projects = try allProjects()
        guard let project = projects.first(where: { $0.id == id }) else { return }
        projects.removeAll { $0.id == id }
        try write(projects)
        try? FileManager.default.removeItem(at: originalsURL.appendingPathComponent(project.originalFilename))
    }

    func originalData(for project: PhotoProject) throws -> Data {
        let url = originalsURL.appendingPathComponent(project.originalFilename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectRepositoryError.missingOriginal
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: originalsURL, withIntermediateDirectories: true)
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
