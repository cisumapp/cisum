// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Plugins",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Plugins",
            targets: ["Plugins"]
        ),
    ],
    dependencies: [
        .package(path: "../../../Packages/StreamingKit/ProviderSDK"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(path: "../../Shared/Networking"),
        .package(path: "../Authentication"),
        .package(path: "../../Shared/Caching"),
        .package(path: "../Player"),
    ],
    targets: [
        .target(
            name: "Plugins",
            dependencies: [
                .product(name: "ProviderSDK", package: "ProviderSDK"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Authentication", package: "Authentication"),
                .product(name: "Caching", package: "Caching"),
                .product(name: "Player", package: "Player"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
