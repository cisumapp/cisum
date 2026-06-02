// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Search",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Search", targets: ["Search"])
    ],
    dependencies: [
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../../Shared/Caching"),
        .package(path: "../../Shared/Networking"),
        .package(path: "../Plugins"),
        .package(path: "../Library"),
        .package(path: "../Playlists"),
        .package(path: "../Player"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(path: "../../../Packages/StreamingKit/SpotifySDK"),
        .package(path: "../Tracks")
    ],
    targets: [
        .target(
            name: "Search",
            dependencies: [
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Caching", package: "Caching"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Plugins", package: "Plugins"),
                .product(name: "Library", package: "Library"),
                .product(name: "Playlists", package: "Playlists"),
                .product(name: "Player", package: "Player"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "SpotifySDK", package: "SpotifySDK"),
                .product(name: "Tracks", package: "Tracks")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
