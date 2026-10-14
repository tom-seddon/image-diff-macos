public enum ViewMode: Equatable {
    /// Changed pixels highlighted over a faded copy of the left image.
    case difference

    /// One image at a time, switching instantly between left and right.
    case flip
}

public struct CommandLineOptions: Equatable {
    public var leftPath: String?
    public var rightPath: String?
    public var mode: ViewMode = .difference
    public var tolerance: Int = 0
    public var outputPath: String?
    public var show = false
    public var showHelp = false

    public init() {}
}

public struct CommandLineError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) { self.message = message }

    public var description: String { message }
}

/// Command-line parsing shared by the app and `imgdiff`. (Not called `CommandLine`, which the
/// standard library already uses.)
public enum Arguments {
    public static let guiUsage = """
        Usage: ImageDiff [left-image] [right-image] [options]

        Opens the comparison window. With no images it opens empty; pick images with
        Choose or drag them in. With two images the comparison is already set up.

        Options:
          -m, --mode <diff|flip>   View to open in (default: diff)
          -t, --tolerance <0-255>  Ignore channel differences up to this amount (default: 0)
          -o, --output <file.png>  Also save the highlighted difference image
          -h, --help               Show this help
        """

    public static let cliUsage = """
        Usage: imgdiff <left-image> <right-image> [options]

        Compares two images and prints the result without opening a window.
        Exit code: 0 identical, 1 different, 2 error.

        Options:
          -t, --tolerance <0-255>  Ignore channel differences up to this amount (default: 0)
          -o, --output <file.png>  Save the highlighted difference image
          -s, --show               Also open the comparison window (ImageDiff.app)
          -m, --mode <diff|flip>   View the window opens in, with --show (default: diff)
          -h, --help               Show this help
        """

    /// Parses arguments (without the program name). Throws `CommandLineError` on invalid input.
    public static func parse(_ args: [String]) throws -> CommandLineOptions {
        var options = CommandLineOptions()
        var positional: [String] = []

        var i = 0
        func takeValue(_ option: String) throws -> String {
            guard i + 1 < args.count else {
                throw CommandLineError("Option '\(option)' needs a value.")
            }
            i += 1
            return args[i]
        }

        while i < args.count {
            let arg = args[i]
            switch arg.lowercased() {
            case "-h", "--help", "/?":
                options.showHelp = true
            case "-m", "--mode":
                options.mode = try parseMode(try takeValue(arg))
            case "-t", "--tolerance":
                options.tolerance = try parseTolerance(try takeValue(arg))
            case "-o", "--output":
                options.outputPath = try takeValue(arg)
            case "-s", "--show":
                options.show = true
            default:
                if arg.hasPrefix("--") || (arg.hasPrefix("-") && arg.count > 1) {
                    throw CommandLineError("Unknown option '\(arg)'.")
                }
                positional.append(arg)
            }
            i += 1
        }

        if positional.count > 2 {
            throw CommandLineError("Expected at most two image paths, got \(positional.count).")
        }
        if positional.count > 0 { options.leftPath = positional[0] }
        if positional.count > 1 { options.rightPath = positional[1] }

        return options
    }

    /// Builds the app's arguments for a comparison, so `imgdiff --show` can hand it over to the window.
    public static func guiArguments(for options: CommandLineOptions) -> [String] {
        var args: [String] = []
        if let left = options.leftPath { args.append(left) }
        if let right = options.rightPath { args.append(right) }
        args += ["--mode", options.mode == .flip ? "flip" : "diff"]
        args += ["--tolerance", String(options.tolerance)]
        return args
    }

    public static func parseMode(_ value: String) throws -> ViewMode {
        switch value.lowercased() {
        case "diff", "difference", "highlight": return .difference
        case "flip", "toggle", "blink": return .flip
        default: throw CommandLineError("Unknown mode '\(value)'. Use diff or flip.")
        }
    }

    private static func parseTolerance(_ value: String) throws -> Int {
        guard let t = Int(value), (0...255).contains(t) else {
            throw CommandLineError("Tolerance must be a whole number from 0 to 255, got '\(value)'.")
        }
        return t
    }
}
