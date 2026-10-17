// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "InternalAudioProbe",
    platforms: [.macOS("15.0"), .iOS("27.0")],
    products: [.library(name: "AudioCore", targets: ["AudioCore"])],
    targets: [
        .target(name: "AudioCore", path: "Sources/AudioCore"),
        .testTarget(name: "AudioCoreTests", dependencies: ["AudioCore"], path: "Tests/AudioCoreTests")
    ]
)
