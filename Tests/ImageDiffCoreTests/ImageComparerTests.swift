import XCTest
@testable import ImageDiffCore

func solid(_ w: Int, _ h: Int, _ b: UInt8, _ g: UInt8, _ r: UInt8, _ a: UInt8 = 255) -> PixelImage {
    var img = PixelImage(width: w, height: h)
    for i in stride(from: 0, to: img.bgra.count, by: 4) {
        img.bgra[i] = b; img.bgra[i + 1] = g; img.bgra[i + 2] = r; img.bgra[i + 3] = a
    }
    return img
}

final class ImageComparerTests: XCTestCase {
    func testIdenticalImagesHaveNoDifferences() throws {
        let diff = try ImageComparer.compare(solid(4, 3, 10, 20, 30), solid(4, 3, 10, 20, 30))
        XCTAssertTrue(diff.areIdentical)
        XCTAssertEqual(diff.totalPixels, 12)
        XCTAssertEqual(diff.maxChannelDelta, 0)
        XCTAssertEqual(diff.summary, "Images are identical.")
    }

    func testChangedPixelIsFoundAndMasked() throws {
        let left = solid(4, 3, 0, 0, 0)
        var right = solid(4, 3, 0, 0, 0)
        right.bgra[(2 * 4 + 1) * 4 + 2] = 200 // red channel of pixel (1, 2)

        let diff = try ImageComparer.compare(left, right)

        XCTAssertEqual(diff.differentPixels, 1)
        XCTAssertEqual(diff.maxChannelDelta, 200)
        XCTAssertTrue(diff.mask[2 * 4 + 1])
        XCTAssertFalse(diff.sizeMismatch)
    }

    func testAlphaDifferencesCount() throws {
        let diff = try ImageComparer.compare(solid(2, 2, 5, 5, 5, 255), solid(2, 2, 5, 5, 5, 0))
        XCTAssertEqual(diff.differentPixels, 4)
    }

    func testToleranceIgnoresSmallDifferences() throws {
        for (tolerance, expected) in [(0, 4), (9, 4), (10, 0), (255, 0)] {
            let diff = try ImageComparer.compare(solid(2, 2, 100, 100, 100), solid(2, 2, 110, 95, 100), tolerance: tolerance)
            XCTAssertEqual(diff.differentPixels, expected, "tolerance \(tolerance)")
            XCTAssertEqual(diff.maxChannelDelta, 10)
        }
    }

    func testExtraAreaOfLargerImageCountsAsDifferent() throws {
        let diff = try ImageComparer.compare(solid(2, 2, 1, 2, 3), solid(3, 4, 1, 2, 3))
        XCTAssertEqual(diff.width, 3)
        XCTAssertEqual(diff.height, 4)
        XCTAssertTrue(diff.sizeMismatch)
        XCTAssertEqual(diff.differentPixels, 12 - 4)
        XCTAssertFalse(diff.mask[0])
        XCTAssertTrue(diff.mask[2])     // (2, 0) only in right
        XCTAssertTrue(diff.mask[3 * 3]) // (0, 3) only in right
        XCTAssertTrue(diff.summary.hasSuffix("Image sizes differ."))
    }

    func testInvalidToleranceThrows() {
        XCTAssertThrowsError(try ImageComparer.compare(solid(1, 1, 0, 0, 0), solid(1, 1, 0, 0, 0), tolerance: 256))
    }

    func testHighlightPaintsDifferencesAndFadesTheRest() throws {
        let left = solid(2, 1, 0, 0, 0)
        var right = solid(2, 1, 0, 0, 0)
        right.bgra[4] = 255 // pixel (1, 0)

        let diff = try ImageComparer.compare(left, right)
        let highlight = ImageComparer.renderHighlight(diff, background: left, highlightARGB: 0xFFFF_00FF)

        // Unchanged black pixel becomes light grey.
        XCTAssertEqual(Array(highlight.bgra[0..<4]), [170, 170, 170, 255])
        // Changed pixel is magenta (B=255, G=0, R=255, A=255).
        XCTAssertEqual(Array(highlight.bgra[4..<8]), [255, 0, 255, 255])
    }

    func testHighlightCoversAreaOutsideBackground() throws {
        let diff = try ImageComparer.compare(solid(1, 1, 0, 0, 0), solid(2, 1, 0, 0, 0))
        let highlight = ImageComparer.renderHighlight(diff, background: solid(1, 1, 0, 0, 0))
        XCTAssertEqual(highlight.width, 2)
        XCTAssertEqual(Array(highlight.bgra[4..<8]), [255, 0, 255, 255])
    }

    func testSummaryFormatting() throws {
        let left = PixelImage(width: 800, height: 600)
        var right = left
        for i in 0..<1234 { right.bgra[i * 4] = 87 }
        let diff = try ImageComparer.compare(left, right)
        XCTAssertEqual(diff.summary, "1,234 of 480,000 pixels differ (0.26%), max channel difference 87.")
    }
}
