// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeepCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeepCleaner", targets: ["DeepCleaner"]),
        .library(name: "DeepCleanerCore", targets: ["DeepCleanerCore"]),
    ],
    targets: [
        .target(name: "DeepCleanerCore"),
        .executableTarget(name: "DeepCleaner", dependencies: ["DeepCleanerCore"]),
        .testTarget(name: "DeepCleanerCoreTests", dependencies: ["DeepCleanerCore"]),
    ]
)
