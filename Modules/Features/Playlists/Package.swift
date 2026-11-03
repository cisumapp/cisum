// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Playlists",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Playlists",
            targets: ["Playlists"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../Player"),
        .package(path: "../Tracks"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(path: "../../../Packages/StreamingKit/SpotifySDK"),
        .package(path: "../../../Packages/StreamingKit/ProviderSDK"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
    ],
    targets: [
        .target(
            name: "Playlists",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Player", package: "Player"),
                .product(name: "Tracks", package: "Tracks"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "SpotifySDK", package: "SpotifySDK"),
                .product(name: "ProviderSDK", package: "ProviderSDK"),
                .product(name: "Kingfisher", package: "Kingfisher"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
