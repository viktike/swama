// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swama",
    platforms: [
        .macOS("15.4")
    ],
    products: [
        .library(
            name: "SwamaKit",
            targets: ["SwamaKit"]
        ),
        .executable(
            name: "swama",
            targets: ["Swama"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/viktike/vmlx-swift-lm.git", branch: "new"),
        .package(url: "https://github.com/osaurus-ai/mlx-swift", branch: "osaurus-0.31.3"),
        .package(url: "https://github.com/viktike/mlx-swift-audio.git", branch: "new"),
    ],
    targets: [
        .target(
            name: "SwamaKit",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "MLXLLM", package: "vmlx-swift-lm"),
                .product(name: "MLXVLM", package: "vmlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "vmlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "vmlx-swift-lm"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXAudio", package: "mlx-swift-audio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SwamaKit",
            resources: []
        ),
        .executableTarget(
            name: "Swama",
            dependencies: [
                .target(name: "SwamaKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Swama",
            sources: ["CLI"]
        ),
        // Tests for SwamaKit
        .testTarget(
            name: "SwamaKitTests",
            dependencies: ["SwamaKit"]
        ),
    ]
)
