// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Player",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Player", targets: ["Player"]),
    ],
    dependencies: [
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../../Shared/Networking"),
        .package(path: "../../Shared/Caching"),
        .package(path: "../Radio"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(path: "../../../Packages/StreamingKit/ProviderSDK"),
        .package(path: "../../../Packages/StreamingKit/SpotifySDK"),
        .package(path: "../../../Packages/StreamingKit/iTunesKit"),
        .package(path: "../../../Packages/StreamingKit/LyricsKit"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
        .package(path: "../Tracks"),
    ],
    targets: [
        .target(
            name: "Player",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Caching", package: "Caching"),
                .product(name: "Radio", package: "Radio"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "ProviderSDK", package: "ProviderSDK"),
                .product(name: "SpotifySDK", package: "SpotifySDK"),
                .product(name: "iTunesKit", package: "iTunesKit"),
                .product(name: "LyricsKit", package: "LyricsKit"),
                .product(name: "Tracks", package: "Tracks"),
            ]
        ),
    ]
)
