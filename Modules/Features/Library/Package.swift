// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Library",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Library", targets: ["Library"]),
    ],
    dependencies: [
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../Artists"),
        .package(path: "../Albums"),
        .package(path: "../Playlists"),
        .package(path: "../Plugins"),
        .package(path: "../Authentication"),
        .package(path: "../../../Packages/StreamingKit/SpotifySDK"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
        .package(url: "https://github.com/clerk/clerk-ios", from: "1.1.3"),
    ],
    targets: [
        .target(
            name: "Library",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Artists", package: "Artists"),
                .product(name: "Albums", package: "Albums"),
                .product(name: "Playlists", package: "Playlists"),
                .product(name: "Plugins", package: "Plugins"),
                .product(name: "Authentication", package: "Authentication"),
                .product(name: "SpotifySDK", package: "SpotifySDK"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "ClerkKit", package: "clerk-ios"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
