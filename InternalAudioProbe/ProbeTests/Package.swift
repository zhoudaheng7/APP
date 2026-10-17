// swift-tools-version: 5.10
import PackageDescription

// CI copies ../Probe/ProbeSignalStats.swift into the ignored Sources directory.
// This avoids changing the existing AudioCore package or maintaining a source fork.
let package = Package(
    name: "ProbeSignalStatistics",
    platforms: [.macOS("15.0")],
    products: [.library(name: "ProbeStats", targets: ["ProbeStats"])],
    targets: [
        .target(name: "ProbeStats", path: "Sources/ProbeStats"),
        .testTarget(name: "ProbeStatsTests", dependencies: ["ProbeStats"], path: "Tests/ProbeStatsTests")
    ]
)
