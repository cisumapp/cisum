// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Caching",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Caching",
            targets: ["Caching"]
        )
    ],
    dependencies: [
        .package(path: "../Models"),
        .package(path: "../Utilities"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(path: "../../../Packages/StreamingKit/SpotifySDK"),
        .package(path: "../../../Packages/StreamingKit/ProviderSDK")
    ],
    targets: [
        .target(
            name: "Caching",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "SpotifySDK", package: "SpotifySDK"),
                .product(name: "ProviderSDK", package: "ProviderSDK")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
