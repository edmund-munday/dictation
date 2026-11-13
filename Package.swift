// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

var products: [Product] = [
    .library(name: "DictationCore", targets: ["DictationCore"]),
]
var targets: [Target] = [
    .target(name: "DictationCore"),
    .testTarget(
        name: "DictationCoreTests",
        dependencies: ["DictationCore"]
    ),
]

// The Mac shell needs AppKit, so it only exists on macOS; the core builds and tests on Linux too.
#if os(macOS)
products += [
    .library(name: "DictationMac", targets: ["DictationMac"]),
    .executable(name: "DictationApp", targets: ["DictationApp"]),
]
targets += [
    .target(name: "DictationMac", dependencies: ["DictationCore"], swiftSettings: v5),
    .executableTarget(name: "DictationApp", dependencies: ["DictationCore", "DictationMac"], swiftSettings: v5),
    .testTarget(
        name: "DictationMacTests",
        dependencies: ["DictationCore", "DictationMac"],
        swiftSettings: v5
    ),
]
#endif

let package = Package(
    name: "DictationCore",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
