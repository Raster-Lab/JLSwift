// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "JLSwift",
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
    targets: [
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
