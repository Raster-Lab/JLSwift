// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "JLSwift",
    products: [
        .library(
            name: "JLSwift",
            targets: ["JLSwift"]
        ),
        .library(
            name: "JPEGLS",
            targets: ["JPEGLS"]
        ),
        .executable(
            name: "jpegls",
            targets: ["jpegls"]
        ),
    ],
    targets: [
        .target(
            name: "JLSwift"
        ),
        .testTarget(
            name: "JLSwiftTests",
            dependencies: ["JLSwift"]
        ),
        .target(
            name: "JPEGLS"
        ),
        .executableTarget(
            name: "jpegls",
            dependencies: ["JPEGLS"]
        ),
        .testTarget(
            name: "JPEGLSTests",
            dependencies: ["JPEGLS"]
        ),
    ]
)
