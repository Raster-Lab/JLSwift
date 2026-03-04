// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "JLSwift",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "JPEGLS",
            targets: ["JPEGLS"]
        ),
        .executable(
            name: "jpegls",
            targets: ["jpegls"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "JPEGLS",
            resources: [
                .process("Platform/Metal/JPEGLSShaders.metal")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "jpegls",
            dependencies: [
                "JPEGLS",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/jpeglscli",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "JPEGLSTests",
            dependencies: [
                "JPEGLS",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            resources: [
                .copy("TestFixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
