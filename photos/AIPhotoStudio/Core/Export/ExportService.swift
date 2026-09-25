import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Hashable, Sendable {
    case jpeg, heic, png

    var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .heic: .heic
        case .png: .png
        }
    }
}

enum JPEGQuality: String, CaseIterable, Hashable, Sendable {
    case low, medium, high, maximum

    var compressionValue: Double {
        switch self {
        case .low: 0.45
        case .medium: 0.68
        case .high: 0.86
        case .maximum: 1
        }
    }
}

enum ExportSize: Equatable, Sendable {
    case original
    case fourK
    case pixels2048
    /// Width/height are interpreted as a bounding box; aspect ratio is preserved.
    case custom(width: Int, height: Int)
}

struct ExportPlan: Equatable, Sendable {
    let maximumDimension: Int?

    static func make(size: ExportSize, outputAspectRatio: Double, originalLongEdge: Int) -> ExportPlan {
        let requested: Int?
        switch size {
        case .original: requested = nil
        case .fourK: requested = 3840
        case .pixels2048: requested = 2048
        case .custom(let width, let height):
            let safeWidth = min(max(width, 64), 20_000)
            let safeHeight = min(max(height, 64), 20_000)
            requested = outputAspectRatio >= 1 ? safeWidth : safeHeight
        }
        return ExportPlan(maximumDimension: requested.map { min($0, originalLongEdge) })
    }
}

enum ExportStage: Double, Sendable {
    case preparing = 0.1
    case rendering = 0.45
    case encoding = 0.8
    case completed = 1
}

enum ExportError: LocalizedError, Sendable {
    case unsupportedFormat(ExportFormat)
    case encodingFailed
    case invalidDimensions
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format): "\(format.rawValue.uppercased()) encoding is unavailable on this device."
        case .encodingFailed: "The exported image could not be encoded."
        case .invalidDimensions: "The requested export dimensions are invalid."
        case .cancelled: "Export was cancelled."
        }
    }
}

struct ExportRequest: Sendable {
    let project: PhotoProject
    let format: ExportFormat
    let jpegQuality: JPEGQuality
    let size: ExportSize

    init(
        project: PhotoProject,
        format: ExportFormat,
        jpegQuality: JPEGQuality = .high,
        size: ExportSize = .original
    ) {
        self.project = project
        self.format = format
        self.jpegQuality = jpegQuality
        self.size = size
    }
}

protocol ExportServiceProtocol: Sendable {
    func export(
        _ request: ExportRequest,
        progress: @escaping @Sendable (ExportStage) -> Void
    ) async throws -> URL
}

final class ExportService: ExportServiceProtocol, @unchecked Sendable {
    private let repository: PhotoProjectRepository
    private let renderer: any RenderEngineProtocol
    private let temporaryDirectory: URL

    init(
        repository: PhotoProjectRepository,
        renderer: any RenderEngineProtocol = CoreImageRenderEngine(),
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.repository = repository
        self.renderer = renderer
        self.temporaryDirectory = temporaryDirectory
    }

    func export(
        _ request: ExportRequest,
        progress: @escaping @Sendable (ExportStage) -> Void
    ) async throws -> URL {
        progress(.preparing)
        try Task.checkCancellation()
        guard Self.supports(request.format) else {
            throw ExportError.unsupportedFormat(request.format)
        }

        let sourceURL = try await repository.originalFileURL(for: request.project)
        guard
            let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
            let image = CIImage(contentsOf: sourceURL),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ProjectRepositoryError.unreadableImage }
        let orientationRaw = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        let original = OriginalImage(
            image: image,
            metadata: ImageMetadata(
                pixelSize: CGSize(
                    width: request.project.originalPixelWidth,
                    height: request.project.originalPixelHeight
                ),
                orientation: orientation,
                scale: 1,
                hasAlpha: request.format == .png,
                colorSpace: colorSpace
            )
        )
        let crop = request.project.editState.geometry.normalizedRect.clamped
        let croppedWidth = Double(request.project.originalPixelWidth) * crop.width
        let croppedHeight = Double(request.project.originalPixelHeight) * crop.height
        guard croppedWidth > 0, croppedHeight > 0 else { throw ExportError.invalidDimensions }
        let plan = ExportPlan.make(
            size: request.size,
            outputAspectRatio: croppedWidth / croppedHeight,
            originalLongEdge: max(Int(croppedWidth), Int(croppedHeight))
        )

        progress(.rendering)
        let rendered = try renderer.render(RenderRequest(
            original: original,
            edits: request.project.editState,
            maximumDimension: plan.maximumDimension.map(CGFloat.init)
        ))
        try Task.checkCancellation()

        progress(.encoding)
        let outputURL = temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(request.format == .jpeg ? "jpg" : request.format.rawValue)
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            request.format.type.identifier as CFString,
            1,
            nil
        ) else { throw ExportError.encodingFailed }
        var metadata = Self.safeMetadata(
            properties,
            width: rendered.cgImage.width,
            height: rendered.cgImage.height
        )
        if request.format != .png {
            metadata[kCGImageDestinationLossyCompressionQuality] = request.jpegQuality.compressionValue
        }
        CGImageDestinationAddImage(destination, rendered.cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.encodingFailed
        }
        progress(.completed)
        return outputURL
    }

    static func supports(_ format: ExportFormat) -> Bool {
        let types = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return types.contains(format.type.identifier)
    }

    static func safeMetadata(
        _ source: [CFString: Any],
        width: Int,
        height: Int
    ) -> [CFString: Any] {
        var result: [CFString: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary,
                    kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary] {
            if let value = source[key] { result[key] = value }
        }
        result[kCGImagePropertyOrientation] = 1
        result[kCGImagePropertyPixelWidth] = width
        result[kCGImagePropertyPixelHeight] = height
        return result
    }
}

enum PhotoSaveError: LocalizedError, Sendable {
    case denied
    case restricted
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .denied: "Photos add-only permission was denied."
        case .restricted: "Photos access is restricted."
        case .saveFailed: "The file could not be saved to Photos."
        }
    }
}

protocol PhotoSaving: Sendable {
    func save(fileURL: URL) async throws
}

struct PhotoLibrarySaver: PhotoSaving {
    func save(fileURL: URL) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        switch status {
        case .authorized, .limited:
            break
        case .restricted:
            throw PhotoSaveError.restricted
        default:
            throw PhotoSaveError.denied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
        }
    }
}
