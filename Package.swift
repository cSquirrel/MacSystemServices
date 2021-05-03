// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacSystemServices",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "MacSystemServices",
            targets: ["MacSystemServices"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "MacSystemServices",
            dependencies: []),
        .testTarget(
            name: "MacSystemServicesTests",
            dependencies: ["MacSystemServices"]),
    ]
)
