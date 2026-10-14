#if canImport(ImageIO)
import XCTest
@testable import ImageDiffCore

final class ImageFileTests: XCTestCase {
    func testPNGRoundTripKeepsExactPixels() throws {
        var image = PixelImage(width: 3, height: 2)
        // Include partial alpha, which premultiplication would distort.
        let pixels: [[UInt8]] = [[1, 2, 3, 255], [200, 100, 50, 128], [255, 255, 255, 0],
                                 [10, 20, 30, 1], [0, 0, 0, 255], [17, 34, 51, 254]]
        image.bgra = pixels.flatMap { $0 }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("imgdiff-test-\(UUID().uuidString).png").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        try ImageFile.savePNG(image, to: path)
        let loaded = try ImageFile.load(path)

        XCTAssertEqual(loaded.width, 3)
        XCTAssertEqual(loaded.height, 2)
        // Fully transparent pixels may lose their colour; compare only the visible ones exactly.
        for i in 0..<6 where pixels[i][3] > 0 {
            XCTAssertEqual(Array(loaded.bgra[i * 4..<i * 4 + 4]), pixels[i], "pixel \(i)")
        }
        XCTAssertEqual(loaded.bgra[2 * 4 + 3], 0)
    }

    func testMissingFileThrows() {
        XCTAssertThrowsError(try ImageFile.load("/nonexistent/image.png"))
    }
}
#endif
