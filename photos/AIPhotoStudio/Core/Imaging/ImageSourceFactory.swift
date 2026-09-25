import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum ImageSourceFactory {
    static func makeTestImage(size: CGSize = CGSize(width: 1400, height: 1050)) -> OriginalImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
        let background = CIImage(color: CIColor(red: 0.08, green: 0.12, blue: 0.22))
            .cropped(to: CGRect(origin: .zero, size: size))
        let glow = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: size.width * 0.68, y: size.height * 0.62),
            "inputRadius0": 10,
            "inputRadius1": size.width * 0.65,
            "inputColor0": CIColor(red: 1, green: 0.48, blue: 0.28, alpha: 1),
            "inputColor1": CIColor(red: 0.12, green: 0.2, blue: 0.62, alpha: 0)
        ])?.outputImage?.cropped(to: background.extent) ?? background
        let image = glow.composited(over: background)
        return OriginalImage(
            image: image,
            metadata: ImageMetadata(
                pixelSize: size,
                orientation: .up,
                scale: 1,
                hasAlpha: false,
                colorSpace: colorSpace
            )
        )
    }

    static func decode(data: Data, scale: CGFloat = 1, maximumDimension: Int? = nil) -> OriginalImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let cgImage: CGImage?
        if let maximumDimension {
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceCreateThumbnailWithTransform: false,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        } else {
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
        guard let cgImage else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        let originalWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? cgImage.width
        let originalHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? cgImage.height
        let alpha = cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipFirst && cgImage.alphaInfo != .noneSkipLast

        return OriginalImage(
            image: CIImage(cgImage: cgImage),
            metadata: ImageMetadata(
                pixelSize: CGSize(width: originalWidth, height: originalHeight),
                orientation: orientation,
                scale: scale,
                hasAlpha: alpha,
                colorSpace: cgImage.colorSpace
            )
        )
    }
}
