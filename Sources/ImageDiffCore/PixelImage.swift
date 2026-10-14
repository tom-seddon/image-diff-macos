/// A decoded image as tightly packed 32-bit BGRA pixels (4 bytes per pixel, no row padding),
/// with straight (not premultiplied) alpha.
public struct PixelImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var bgra: [UInt8]

    public init(width: Int, height: Int, bgra: [UInt8]) {
        precondition(width >= 0 && height >= 0, "Dimensions must be non-negative.")
        precondition(bgra.count == width * height * 4,
                     "Expected \(width * height * 4) bytes for a \(width)x\(height) image, got \(bgra.count).")
        self.width = width
        self.height = height
        self.bgra = bgra
    }

    /// A transparent black image.
    public init(width: Int, height: Int) {
        self.init(width: width, height: height, bgra: [UInt8](repeating: 0, count: width * height * 4))
    }

    public var stride: Int { width * 4 }

    /// The pixel at (x, y) as 0xAARRGGBB, or nil outside the image.
    public func argb(x: Int, y: Int) -> UInt32? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        return UInt32(bgra[i + 3]) << 24 | UInt32(bgra[i + 2]) << 16 | UInt32(bgra[i + 1]) << 8 | UInt32(bgra[i])
    }
}
