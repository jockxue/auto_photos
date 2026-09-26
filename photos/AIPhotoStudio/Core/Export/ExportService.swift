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

    var title: String {
        switch self {
        case .low: L10n.text("Low")
        case .medium: L10n.text("Medium")
        case .high: L10n.text("High")
        case .maximum: L10n.text("Maximum")
        }
    }

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

    static func make(
        size: ExportSize,
        outputSize: CGSize
    ) throws -> ExportPlan {
        guard outputSize.width > 0, outputSize.height > 0 else {
            throw ExportError.invalidDimensions
        }
        let width = Double(outputSize.width)
        let height = Double(outputSize.height)
        let longEdge = max(width, height)
        let scale: Double
        let maximumDimension: Int?
        switch size {
        case .original:
            scale = 1
            maximumDimension = nil
        case .fourK:
            scale = min(1, 3840 / longEdge)
            maximumDimension = Int(floor(longEdge * scale))
        case .pixels2048:
            scale = min(1, 2048 / longEdge)
            maximumDimension = Int(floor(longEdge * scale))
        case .custom(let requestedWidth, let requestedHeight):
            let safeWidth = min(max(requestedWidth, 64), 20_000)
            let safeHeight = min(max(requestedHeight, 64), 20_000)
            scale = min(1, min(
                Double(safeWidth) / width,
                Double(safeHeight) / height
            ))
            maximumDimension = Int(floor(longEdge * scale))
        }
        guard width * height * scale * scale <= Double(ImageMemoryPolicy.maximumRenderedPixels) else {
            throw ExportError.memoryBudgetExceeded
        }
        return ExportPlan(maximumDimension: maximumDimension)
    }
}

enum ImageMemoryPolicy {
    /// One RGBA8 output is at most ~96 MB. Core Image and encoding still add
    /// overhead, so larger sources are rejected until a tiled renderer exists.
    static let maximumRenderedPixels = 24_000_000
}

enum GeometryOutputPlanner {
    static func outputSize(
        originalWidth: Int,
        originalHeight: Int,
        orientation: CGImagePropertyOrientation,
        crop: NormalizedRect,
        rotationDegrees: Double
    ) -> CGSize {
        let swapsAxes = orientation == .left
            || orientation == .leftMirrored
            || orientation == .right
            || orientation == .rightMirrored
        let orientedWidth = Double(swapsAxes ? originalHeight : originalWidth)
        let orientedHeight = Double(swapsAxes ? originalWidth : originalHeight)
        let radians = rotationDegrees * .pi / 180
        let rotatedWidth = abs(orientedWidth * cos(radians)) + abs(orientedHeight * sin(radians))
        let rotatedHeight = abs(orientedWidth * sin(radians)) + abs(orientedHeight * cos(radians))
        let normalizedCrop = crop.clamped
        return CGSize(
            width: CGFloat(rotatedWidth * normalizedCrop.width),
            height: CGFloat(rotatedHeight * normalizedCrop.height)
        )
    }
}

enum ExportStage: Double, Sendable {
    case preparing = 0.1
    case rendering = 0.45
    case encoding = 0.8
    case completed = 1
}

struct ExportOperationState: Equatable, Sendable {
    private(set) var isRunning = false
    private(set) var isCancelling = false
    var canStart: Bool { !isRunning }

    mutating func begin() -> Bool {
        guard canStart else { return false }
        isRunning = true
        isCancelling = false
        return true
    }

    mutating func requestCancellation() {
        guard isRunning else { return }
        isCancelling = true
    }

    mutating func finish() {
        isRunning = false
        isCancelling = false
    }
}

enum ExportError: LocalizedError, Sendable {
    case unsupportedFormat(ExportFormat)
    case encodingFailed
    case invalidDimensions
    case memoryBudgetExceeded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format): L10n.format("%@ encoding is unavailable on this device.", format.rawValue.uppercased())
        case .encodingFailed: L10n.text("The exported image could not be encoded.")
        case .invalidDimensions: L10n.text("The requested export dimensions are invalid.")
        case .memoryBudgetExceeded: L10n.text("This edit exceeds the 24-megapixel export safety budget.")
        case .cancelled: L10n.text("Export was cancelled.")
        }
    }
}

struct ExportRequest: Sendable {
    let project: PhotoProject
    let editState: EditState
    let format: ExportFormat
    let jpegQuality: JPEGQuality
    let size: ExportSize

    init(
        project: PhotoProject,
        editState: EditState? = nil,
        format: ExportFormat,
        jpegQuality: JPEGQuality = .high,
        size: ExportSize = .original
    ) {
        self.project = project
        self.editState = editState ?? project.editState
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
        let geometrySize = GeometryOutputPlanner.outputSize(
            originalWidth: request.project.originalPixelWidth,
            originalHeight: request.project.originalPixelHeight,
            orientation: orientation,
            crop: request.editState.geometry.normalizedRect,
            rotationDegrees: request.editState.geometry.rotationDegrees
        )
        let plan = try ExportPlan.make(
            size: request.size,
            outputSize: geometrySize
        )

        progress(.rendering)
        let rendered = try renderer.render(RenderRequest(
            original: original,
            edits: request.editState,
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
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
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
        if var exif = source[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = width
            exif[kCGImagePropertyExifPixelYDimension] = height
            exif.removeValue(forKey: "Orientation" as CFString)
            result[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = source[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            for key in ["PixelWidth", "PixelHeight", "ImageWidth", "ImageLength"] {
                tiff.removeValue(forKey: key as CFString)
            }
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        // IPTC and GPS are intentionally preserved for an explicit
        // metadata-preserving export. A future privacy toggle can omit GPS.
        for key in [kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary] {
            if let value = source[key] {
                result[key] = value
            }
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
        case .denied: L10n.text("Photos add-only permission was denied.")
        case .restricted: L10n.text("Photos access is restricted.")
        case .saveFailed: L10n.text("The file could not be saved to Photos.")
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
