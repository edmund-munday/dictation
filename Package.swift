// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DictationCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DictationCore", targets: ["DictationCore"]),
    ],
    targets: [
        .target(name: "DictationCore"),
        .testTarget(
            name: "DictationCoreTests",
            dependencies: ["DictationCore"]
        ),
    ]
)
