// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FlickCore", platforms: [.macOS(.v13)], products: [.library(name: "FlickCore", targets: ["FlickCore"])], targets: [.target(name: "FlickCore", path: "Core"), .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"], path: "Tests")])
