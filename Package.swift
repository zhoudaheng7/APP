// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScrollShotCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ScrollShotCore", targets: ["ScrollShotCore"])],
    targets: [
        .target(name: "ScrollShotCore", path: "Shared", exclude: ["PhotoSaver.swift"]),
        .testTarget(name: "ScrollShotCoreTests", dependencies: ["ScrollShotCore"], path: "Tests")
    ]
)
