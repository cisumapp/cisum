// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Search",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Search", targets: ["Search"]),
    ],
    dependencies: [
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../Shared/Catalog"),
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../../Shared/Caching"),
        .package(path: "../../Shared/Networking"),
        .package(path: "../Authentication"),
        .package(path: "../Library"),
        .package(path: "../Playlists"),
        .package(path: "../Player"),
        .package(path: "../../../Packages/StreamingKit/iTunesKit"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(path: "../../../Packages/StreamingKit/SpotifySDK"),
        .package(path: "../Tracks"),
        .package(path: "../Artists"),
        .package(path: "../Plugins"),
    ],
    targets: [
        .target(
            name: "Search",
            dependencies: [
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Catalog", package: "Catalog"),
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Caching", package: "Caching"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Authentication", package: "Authentication"),
                .product(name: "Library", package: "Library"),
                .product(name: "Playlists", package: "Playlists"),
                .product(name: "Player", package: "Player"),
                .product(name: "iTunesKit", package: "iTunesKit"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "SpotifySDK", package: "SpotifySDK"),
                .product(name: "Tracks", package: "Tracks"),
                .product(name: "Artists", package: "Artists"),
                .product(name: "Plugins", package: "Plugins"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
