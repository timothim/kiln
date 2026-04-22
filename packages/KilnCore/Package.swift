// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KilnCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "KilnCore",
            targets: ["KilnCore"]
        )
    ],
    targets: [
        .target(
            name: "KilnCore",
            path: "Sources/KilnCore"
        ),
        .testTarget(
            name: "KilnCoreTests",
            dependencies: ["KilnCore"],
            path: "Tests/KilnCoreTests"
        )
    ]
)
