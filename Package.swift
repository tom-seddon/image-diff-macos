// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ImageDiff",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ImageDiffCore", targets: ["ImageDiffCore"]),
        .executable(name: "imgdiff", targets: ["imgdiff"]),
        .executable(name: "ImageDiff", targets: ["ImageDiff"]),
    ],
    targets: [
        .target(name: "ImageDiffCore"),
        .executableTarget(name: "imgdiff", dependencies: ["ImageDiffCore"]),
        .executableTarget(name: "ImageDiff", dependencies: ["ImageDiffCore"]),
        .testTarget(name: "ImageDiffCoreTests", dependencies: ["ImageDiffCore"]),
    ]
)
