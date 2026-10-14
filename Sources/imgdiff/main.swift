import Foundation
import ImageDiffCore

let identical: Int32 = 0, different: Int32 = 1, failed: Int32 = 2

func printError(_ text: String = "") {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
}

func run() -> Int32 {
    let options: CommandLineOptions
    do {
        options = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
    } catch {
        printError("imgdiff: \(error)")
        printError()
        printError(Arguments.cliUsage)
        return failed
    }

    if options.showHelp {
        print("imgdiff \(AppVersion.current)")
        print()
        print(Arguments.cliUsage)
        return identical
    }

    guard let leftPath = options.leftPath, let rightPath = options.rightPath else {
        printError("imgdiff: two image paths are needed.")
        printError()
        printError(Arguments.cliUsage)
        return failed
    }

    let diff: DiffResult
    do {
        let left = try ImageFile.load(leftPath)
        let right = try ImageFile.load(rightPath)
        diff = try ImageComparer.compare(left, right, tolerance: options.tolerance)

        print("Left:  \(leftPath) (\(left.width)x\(left.height))")
        print("Right: \(rightPath) (\(right.width)x\(right.height))")
        print(diff.summary)

        if let outputPath = options.outputPath {
            try ImageFile.savePNG(ImageComparer.renderHighlight(diff, background: left), to: outputPath)
            print("Difference image saved to \(outputPath)")
        }
    } catch {
        printError("imgdiff: \(error)")
        return failed
    }

    if options.show {
        openWindow(options)
    }

    return diff.areIdentical ? identical : different
}

/// Opens the comparison in ImageDiff.app: the copy next to this executable (or the app this
/// executable is inside) if there is one, otherwise whichever copy macOS knows about.
func openWindow(_ options: CommandLineOptions) {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var guiArgs = Arguments.guiArguments(for: options)
    // `open` starts the app in a different directory, so relative paths must be made absolute.
    for (i, arg) in guiArgs.enumerated() where !arg.hasPrefix("/") && FileManager.default.fileExists(atPath: arg) {
        guiArgs[i] = URL(fileURLWithPath: arg, relativeTo: cwd).standardizedFileURL.path
    }

    let exe = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: cwd).resolvingSymlinksInPath()
    let dir = exe.deletingLastPathComponent()
    let candidates = [
        dir.appendingPathComponent("ImageDiff.app"),
        dir.deletingLastPathComponent().deletingLastPathComponent(), // .../ImageDiff.app/Contents/MacOS
    ]
    var openArgs = ["-n"]
    if let app = candidates.first(where: { $0.pathExtension == "app" && FileManager.default.fileExists(atPath: $0.path) }) {
        openArgs += ["-a", app.path]
    } else {
        openArgs += ["-b", "io.github.tom-seddon.ImageDiff"]
    }
    openArgs += ["--args"] + guiArgs

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = openArgs
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            printError("imgdiff: could not open the window (is ImageDiff.app installed?)")
        }
    } catch {
        printError("imgdiff: could not open the window: \(error)")
    }
}

exit(run())
