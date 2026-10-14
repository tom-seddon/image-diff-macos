import XCTest
@testable import ImageDiffCore

final class ArgumentsTests: XCTestCase {
    func testNoArgumentsOpensEmpty() throws {
        let o = try Arguments.parse([])
        XCTAssertNil(o.leftPath)
        XCTAssertNil(o.rightPath)
        XCTAssertEqual(o.mode, .difference)
        XCTAssertEqual(o.tolerance, 0)
    }

    func testParsesPathsAndOptions() throws {
        let o = try Arguments.parse(["a.png", "b.png", "--mode", "flip", "-t", "12", "-o", "out.png", "--show"])
        XCTAssertEqual(o.leftPath, "a.png")
        XCTAssertEqual(o.rightPath, "b.png")
        XCTAssertEqual(o.mode, .flip)
        XCTAssertEqual(o.tolerance, 12)
        XCTAssertEqual(o.outputPath, "out.png")
        XCTAssertTrue(o.show)
    }

    func testModeNames() throws {
        XCTAssertEqual(try Arguments.parseMode("diff"), .difference)
        XCTAssertEqual(try Arguments.parseMode("FLIP"), .flip)
        XCTAssertEqual(try Arguments.parseMode("toggle"), .flip)
    }

    func testInvalidArgumentsThrow() {
        let cases: [[String]] = [
            ["--mode", "slider"],
            ["-t", "300"],
            ["-t", "abc"],
            ["--bogus"],
            ["a", "b", "c"],
            ["-o"],
        ]
        for args in cases {
            XCTAssertThrowsError(try Arguments.parse(args), "\(args)") { error in
                XCTAssertTrue(error is CommandLineError, "\(args)")
            }
        }
    }

    func testHelpFlags() throws {
        XCTAssertTrue(try Arguments.parse(["/?"]).showHelp)
        XCTAssertTrue(try Arguments.parse(["--help"]).showHelp)
    }

    func testGuiArgumentsRoundTrip() throws {
        let original = try Arguments.parse(["a.png", "b.png", "-m", "flip", "-t", "7", "--show"])
        let parsed = try Arguments.parse(Arguments.guiArguments(for: original))
        XCTAssertEqual(parsed.leftPath, "a.png")
        XCTAssertEqual(parsed.rightPath, "b.png")
        XCTAssertEqual(parsed.mode, .flip)
        XCTAssertEqual(parsed.tolerance, 7)
        XCTAssertFalse(parsed.show)
    }
}
