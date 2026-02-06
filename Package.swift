// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenshotSpace",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScreenshotSpace",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
