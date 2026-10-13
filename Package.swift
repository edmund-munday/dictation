// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DictationCore",
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
