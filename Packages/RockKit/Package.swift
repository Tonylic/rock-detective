// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RockKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RockKit", targets: ["RockKit"])
    ],
    targets: [
        .target(
            name: "RockKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RockKitTests",
            dependencies: ["RockKit"]
        )
    ]
)
