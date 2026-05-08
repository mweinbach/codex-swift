import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct EncodedImage: Equatable, Sendable {
    public let bytes: Data
    public let mime: String
    public let width: Int
    public let height: Int

    public init(bytes: Data, mime: String, width: Int, height: Int) {
        self.bytes = bytes
        self.mime = mime
        self.width = width
        self.height = height
    }

    public var dataURL: String {
        "data:\(mime);base64,\(bytes.base64EncodedString())"
    }
}

public enum ImageProcessingError: Error, CustomStringConvertible, Sendable {
    case read(path: String, source: String)
    case decode(path: String, source: String, invalidImage: Bool)
    case encode(format: String, source: String)

    public var description: String {
        switch self {
        case let .read(path, source):
            "failed to read image at \(path): \(source)"
        case let .decode(path, source, _):
            "failed to decode image at \(path): \(source)"
        case let .encode(format, source):
            "failed to encode image as \(format): \(source)"
        }
    }

    public var isInvalidImage: Bool {
        if case let .decode(_, _, invalidImage) = self {
            return invalidImage
        }
        return false
    }
}

public enum LocalImageProcessor {
    public static let maxWidth = 2_048
    public static let maxHeight = 2_048

    private static let imageCache = BlockingLruCache<Data, EncodedImage>(capacity: 32)

    public static func loadAndResizeToFit(path: URL) throws -> EncodedImage {
        let fileBytes: Data
        do {
            fileBytes = try Data(contentsOf: path)
        } catch {
            throw ImageProcessingError.read(path: path.path, source: String(describing: error))
        }

        return try imageCache.getOrTryInsertWith(CacheUtils.sha1Digest(fileBytes)) {
            try loadAndResizeToFit(fileBytes: fileBytes, path: path)
        }
    }

    private static func loadAndResizeToFit(fileBytes: Data, path: URL) throws -> EncodedImage {
        guard let inputFormat = ImageFileFormat(fileBytes: fileBytes) else {
            throw ImageProcessingError.decode(
                path: path.path,
                source: "unsupported image format",
                invalidImage: false
            )
        }

        let image = try decodeImage(fileBytes, path: path, invalidImage: true)
        let width = image.width
        let height = image.height

        if width <= maxWidth && height <= maxHeight, inputFormat.canPreserveSourceBytes {
            return EncodedImage(
                bytes: fileBytes,
                mime: inputFormat.mime,
                width: width,
                height: height
            )
        }

        let resizedSize = if width <= maxWidth && height <= maxHeight {
            (width: width, height: height)
        } else {
            fittingSize(width: width, height: height)
        }
        let resized = try resize(
            image,
            width: resizedSize.width,
            height: resizedSize.height,
            outputFormat: inputFormat.promptOutputFormat
        )
        let bytes = try encode(resized, format: inputFormat.promptOutputFormat)

        return EncodedImage(
            bytes: bytes,
            mime: inputFormat.promptOutputFormat.mime,
            width: resized.width,
            height: resized.height
        )
    }

    public static func mimeType(forPath path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard !ext.isEmpty else {
            return nil
        }

        if let mime = UTType(filenameExtension: ext)?.preferredMIMEType {
            return mime
        }

        switch ext {
        case "jpg",
             "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "svg":
            return "image/svg+xml"
        case "json":
            return "application/json"
        case "txt":
            return "text/plain"
        default:
            return nil
        }
    }

    private static func decodeImage(_ data: Data, path: URL, invalidImage: Bool) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImageProcessingError.decode(
                path: path.path,
                source: "image data is invalid or unsupported",
                invalidImage: invalidImage
            )
        }

        return image
    }

    private static func fittingSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let scale = min(Double(maxWidth) / Double(width), Double(maxHeight) / Double(height))
        return (
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }

    private static func resize(
        _ image: CGImage,
        width: Int,
        height: Int,
        outputFormat: ImageFileFormat
    ) throws -> CGImage {
        let bitmapInfo: CGBitmapInfo
        switch outputFormat {
        case .jpeg:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        case .png,
             .gif:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw ImageProcessingError.encode(
                format: outputFormat.description,
                source: "failed to create bitmap context"
            )
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let resized = context.makeImage() else {
            throw ImageProcessingError.encode(
                format: outputFormat.description,
                source: "failed to create resized image"
            )
        }

        return resized
    }

    private static func encode(_ image: CGImage, format: ImageFileFormat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.identifier as CFString, 1, nil) else {
            throw ImageProcessingError.encode(
                format: format.description,
                source: "failed to create image destination"
            )
        }

        let options: CFDictionary?
        switch format {
        case .jpeg:
            options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        case .png,
             .gif:
            options = nil
        }

        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessingError.encode(
                format: format.description,
                source: "failed to finalize image destination"
            )
        }

        return data as Data
    }
}

private enum ImageFileFormat: CustomStringConvertible {
    case jpeg
    case png
    case gif

    init?(fileBytes: Data) {
        if fileBytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            self = .png
        } else if fileBytes.count >= 3,
                  fileBytes[fileBytes.startIndex] == 0xFF,
                  fileBytes[fileBytes.index(after: fileBytes.startIndex)] == 0xD8,
                  fileBytes[fileBytes.index(fileBytes.startIndex, offsetBy: 2)] == 0xFF
        {
            self = .jpeg
        } else if fileBytes.starts(with: Array("GIF87a".utf8))
            || fileBytes.starts(with: Array("GIF89a".utf8))
        {
            self = .gif
        } else {
            return nil
        }
    }

    var mime: String {
        switch self {
        case .jpeg:
            "image/jpeg"
        case .png:
            "image/png"
        case .gif:
            "image/gif"
        }
    }

    var identifier: String {
        switch self {
        case .jpeg:
            UTType.jpeg.identifier
        case .png:
            UTType.png.identifier
        case .gif:
            UTType.gif.identifier
        }
    }

    var canPreserveSourceBytes: Bool {
        switch self {
        case .jpeg,
             .png:
            true
        case .gif:
            false
        }
    }

    var promptOutputFormat: ImageFileFormat {
        switch self {
        case .jpeg,
             .png:
            self
        case .gif:
            .png
        }
    }

    var description: String {
        switch self {
        case .jpeg:
            "Jpeg"
        case .png:
            "Png"
        case .gif:
            "Gif"
        }
    }
}
