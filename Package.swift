// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "DictationCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DictationCore", targets: ["DictationCore"]),
        .library(name: "DictationMac", targets: ["DictationMac"]),
        .executable(name: "DictationApp", targets: ["DictationApp"]),
    ],
    targets: [
        .target(name: "DictationCore"),
        .target(name: "DictationMac", dependencies: ["DictationCore"], swiftSettings: v5),
        .executableTarget(name: "DictationApp", dependencies: ["DictationCore", "DictationMac"], swiftSettings: v5),
        .testTarget(
            name: "DictationCoreTests",
            dependencies: ["DictationCore"]
        ),
        .testTarget(
            name: "DictationMacTests",
            dependencies: ["DictationCore", "DictationMac"],
            swiftSettings: v5
        ),
    ]
)
