public enum ImageComparerError: Error, Equatable, CustomStringConvertible {
    case toleranceOutOfRange(Int)

    public var description: String {
        switch self {
        case .toleranceOutOfRange(let t): return "Tolerance must be between 0 and 255, got \(t)."
        }
    }
}

public enum ImageComparer {
    /// Compares two images pixel by pixel, aligned at the top-left corner.
    /// A pixel counts as different when any channel (B, G, R or A) differs by more than
    /// `tolerance`. Where the images have different sizes, every pixel that only exists in
    /// one of them counts as different.
    public static func compare(_ left: PixelImage, _ right: PixelImage, tolerance: Int = 0) throws -> DiffResult {
        guard (0...255).contains(tolerance) else {
            throw ImageComparerError.toleranceOutOfRange(tolerance)
        }

        let width = max(left.width, right.width)
        let height = max(left.height, right.height)
        let overlapW = min(left.width, right.width)
        let overlapH = min(left.height, right.height)

        var mask = [Bool](repeating: false, count: width * height)
        var different = 0
        var maxDelta = 0

        left.bgra.withUnsafeBufferPointer { a in
            right.bgra.withUnsafeBufferPointer { b in
                mask.withUnsafeMutableBufferPointer { m in
                    for y in 0..<height {
                        for x in 0..<width {
                            let diff: Bool
                            if x < overlapW && y < overlapH {
                                let ia = (y * left.width + x) * 4
                                let ib = (y * right.width + x) * 4
                                var d = abs(Int(a[ia]) - Int(b[ib]))
                                d = max(d, abs(Int(a[ia + 1]) - Int(b[ib + 1])))
                                d = max(d, abs(Int(a[ia + 2]) - Int(b[ib + 2])))
                                d = max(d, abs(Int(a[ia + 3]) - Int(b[ib + 3])))
                                if d > maxDelta { maxDelta = d }
                                diff = d > tolerance
                            } else {
                                diff = true
                            }

                            if diff {
                                m[y * width + x] = true
                                different += 1
                            }
                        }
                    }
                }
            }
        }

        return DiffResult(width: width, height: height, mask: mask, differentPixels: different,
                          maxChannelDelta: maxDelta,
                          sizeMismatch: left.width != right.width || left.height != right.height)
    }

    /// Builds a highlight image: `background` shown faded and greyscale, with every differing
    /// pixel painted in `highlightARGB` (0xAARRGGBB).
    public static func renderHighlight(_ diff: DiffResult, background: PixelImage,
                                       highlightARGB: UInt32 = 0xFFFF_00FF) -> PixelImage {
        let hb = UInt8(truncatingIfNeeded: highlightARGB)
        let hg = UInt8(truncatingIfNeeded: highlightARGB >> 8)
        let hr = UInt8(truncatingIfNeeded: highlightARGB >> 16)
        let ha = UInt8(truncatingIfNeeded: highlightARGB >> 24)
        var output = PixelImage(width: diff.width, height: diff.height)

        output.bgra.withUnsafeMutableBufferPointer { dst in
            background.bgra.withUnsafeBufferPointer { src in
                for y in 0..<diff.height {
                    for x in 0..<diff.width {
                        let o = (y * diff.width + x) * 4
                        if diff.mask[y * diff.width + x] {
                            dst[o] = hb; dst[o + 1] = hg; dst[o + 2] = hr; dst[o + 3] = ha
                            continue
                        }

                        var grey: UInt8 = 255
                        if x < background.width && y < background.height {
                            let i = (y * background.width + x) * 4
                            // Rec. 601 luma, composited over white, then faded towards white.
                            let luma = (Int(src[i]) * 29 + Int(src[i + 1]) * 150 + Int(src[i + 2]) * 77) >> 8
                            let alpha = Int(src[i + 3])
                            let over = (luma * alpha + 255 * (255 - alpha)) / 255
                            grey = UInt8(over / 3 + 170)
                        }

                        dst[o] = grey; dst[o + 1] = grey; dst[o + 2] = grey; dst[o + 3] = 255
                    }
                }
            }
        }

        return output
    }
}
