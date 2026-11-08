// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Unscrew",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Unscrew",
            path: "Sources/Unscrew"
        ),
        .executableTarget(
            name: "scroll-invert",
            path: "Sources/scroll-invert"
        ),
        .executableTarget(
            name: "mic-guard",
            path: "Sources/mic-guard"
        )
    ]
)
