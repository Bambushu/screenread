// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screenread",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "screenread", targets: ["screenread"]),
        .executable(name: "screenread-mcp", targets: ["screenread-mcp"]),
        .library(name: "ScreenReadCore", targets: ["ScreenReadCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "ScreenReadCore",
            dependencies: []
        ),
        .executableTarget(
            name: "screenread",
            dependencies: [
                "ScreenReadCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "screenread-mcp",
            dependencies: ["ScreenReadCore"]
        ),
        .testTarget(
            name: "ScreenReadCoreTests",
            dependencies: ["ScreenReadCore"]
        ),
    ]
)
