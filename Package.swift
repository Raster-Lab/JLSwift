// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "JLSwift",
    products: [
        .library(
            name: "JLSwift",
            targets: ["JLSwift"]
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
    ]
)
