// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifeOSCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LifeOSDomain", targets: ["LifeOSDomain"]),
        .library(name: "LifeOSApplication", targets: ["LifeOSApplication"]),
        .library(name: "LifeOSPersistence", targets: ["LifeOSPersistence"]),
        .library(name: "LifeOSPresentation", targets: ["LifeOSPresentation"]),
    ],
    targets: [
        .target(name: "LifeOSDomain"),
        .target(name: "LifeOSApplication", dependencies: ["LifeOSDomain"]),
        .target(name: "LifeOSPersistence", dependencies: ["LifeOSDomain", "LifeOSApplication"]),
        .target(name: "LifeOSPresentation"),
        .testTarget(name: "LifeOSCoreTests", dependencies: ["LifeOSDomain", "LifeOSApplication"]),
    ],
    swiftLanguageModes: [.v6]
)
