// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Tracks",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Tracks",
            targets: ["Tracks"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/Aesthetics"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
    ],
    targets: [
        .target(
            name: "Tracks",
            dependencies: [
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Kingfisher", package: "Kingfisher"),
            ]
        ),

    ],
    swiftLanguageModes: [.v6]
)
