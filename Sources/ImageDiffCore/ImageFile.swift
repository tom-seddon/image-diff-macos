#if canImport(ImageIO)
import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageFileError: Error, CustomStringConvertible {
    public let message: String

    public var description: String { message }
}

/// Reads and writes images using ImageIO, so any format macOS can decode works
/// (PNG, JPEG, HEIC, WebP, GIF, BMP, TIFF, ICO and more).
public enum ImageFile {
    public static func load(_ path: String) throws -> PixelImage {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageFileError(message: "Could not find file '\(path)'.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageFileError(message: "Could not read '\(path)' as an image.")
        }
        return try pixels(of: image, name: path)
    }

    /// Converts to straight-alpha BGRA. Colour profiles are ignored, so the comparison sees the
    /// stored pixel values: RGB images keep their own colour space, so no colour conversion happens.
    public static func pixels(of image: CGImage, name: String = "image") throws -> PixelImage {
        let space: CGColorSpace
        if let own = image.colorSpace, own.model == .rgb {
            space = own
        } else if let base = image.colorSpace?.baseColorSpace, base.model == .rgb {
            space = base // indexed (palette) images
        } else {
            space = CGColorSpaceCreateDeviceRGB()
        }

        guard var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ) else {
            throw ImageFileError(message: "Could not convert '\(name)' to 32-bit pixels.")
        }

        var buffer = vImage_Buffer()
        let error = vImageBuffer_InitWithCGImage(&buffer, &format, nil, image, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else {
            throw ImageFileError(message: "Could not convert '\(name)' to 32-bit pixels (vImage error \(error)).")
        }
        defer { free(buffer.data) }

        let width = Int(buffer.width), height = Int(buffer.height)
        var bgra = [UInt8](repeating: 0, count: width * height * 4)
        bgra.withUnsafeMutableBytes { dst in
            for y in 0..<height {
                let row = buffer.data.advanced(by: y * buffer.rowBytes)
                dst.baseAddress!.advanced(by: y * width * 4).copyMemory(from: row, byteCount: width * 4)
            }
        }
        return PixelImage(width: width, height: height, bgra: bgra)
    }

    /// Wraps pixels in a CGImage (sRGB, straight alpha).
    public static func cgImage(_ image: PixelImage) -> CGImage? {
        guard image.width > 0, image.height > 0,
              let provider = CGDataProvider(data: Data(image.bgra) as CFData) else { return nil }
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: image.stride,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }

    public static func savePNG(_ image: PixelImage, to path: String) throws {
        guard let cg = cgImage(image) else {
            throw ImageFileError(message: "Could not save an empty image to '\(path)'.")
        }
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageFileError(message: "Could not create '\(path)'.")
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageFileError(message: "Could not write '\(path)'.")
        }
    }
}
#endif
