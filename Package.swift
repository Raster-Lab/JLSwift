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
            name: "JPEGLS"
        ),
        .executableTarget(
            name: "jpegls",
            dependencies: [
                "JPEGLS",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
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
            ]
        ),
    ]
)
