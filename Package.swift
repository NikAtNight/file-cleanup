// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenshotCleanup",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ScreenshotCleanup", targets: ["ScreenshotCleanup"])],
    targets: [
        .target(name: "CleanupCore"),
        .executableTarget(name: "ScreenshotCleanup", dependencies: ["CleanupCore"]),
        .testTarget(name: "CleanupCoreTests", dependencies: ["CleanupCore"])
    ]
)
