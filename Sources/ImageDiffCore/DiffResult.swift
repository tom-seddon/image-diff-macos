import Foundation

public struct DiffResult {
    /// Width of the compared area (the larger of the two image widths).
    public let width: Int

    /// Height of the compared area (the larger of the two image heights).
    public let height: Int

    /// One entry per pixel, row-major; true where the images differ.
    public let mask: [Bool]

    public let differentPixels: Int

    /// Largest single-channel difference found where the images overlap.
    public let maxChannelDelta: Int

    public let sizeMismatch: Bool

    public var totalPixels: Int { width * height }

    public var areIdentical: Bool { differentPixels == 0 }

    public var differentFraction: Double {
        totalPixels == 0 ? 0 : Double(differentPixels) / Double(totalPixels)
    }

    public var summary: String {
        if areIdentical {
            return "Images are identical."
        }
        let percent = String(format: "%.2f%%", differentFraction * 100)
        let text = "\(Self.grouped(differentPixels)) of \(Self.grouped(totalPixels)) pixels differ (\(percent)), max channel difference \(maxChannelDelta)."
        return sizeMismatch ? text + " Image sizes differ." : text
    }

    /// Formats with comma thousands separators, like "1,234,567", whatever the locale.
    static func grouped(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var out = ""
        for (i, c) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return value < 0 ? "-" + out : out
    }
}
