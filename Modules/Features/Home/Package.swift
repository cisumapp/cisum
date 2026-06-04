// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Home",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Home",
            targets: ["Home"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../Shared/Models"),
        .package(path: "../Tracks"),
        .package(path: "../Player"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
    ],
    targets: [
        .target(
            name: "Home",
            dependencies: [
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Models", package: "Models"),
                .product(name: "Tracks", package: "Tracks"),
                .product(name: "Player", package: "Player"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
