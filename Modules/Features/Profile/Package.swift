// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Profile",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Profile", targets: ["Profile"]),
    ],
    dependencies: [
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../Shared/Networking"),
        .package(path: "../../Shared/Caching"),
        .package(path: "../Authentication"),
        .package(path: "../Player"),
        .package(path: "../Plugins"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(path: "../../../Packages/StreamingKit/SpotifySDK"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
        .package(url: "https://github.com/PostHog/posthog-ios.git", .upToNextMajor(from: "3.0.0")),
    ],
    targets: [
        .target(
            name: "Profile",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Caching", package: "Caching"),
                .product(name: "Authentication", package: "Authentication"),
                .product(name: "Player", package: "Player"),
                .product(name: "Plugins", package: "Plugins"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "SpotifySDK", package: "SpotifySDK"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "PostHog", package: "posthog-ios"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
