// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Aesthetics",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Aesthetics", targets: ["Aesthetics"]),
    ],
    dependencies: [
        .package(path: "../Utilities"),
        .package(path: "../../../Packages/StreamingKit/SpotifySDK"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
    ],
    targets: [
        .target(
            name: "Aesthetics",
            dependencies: [
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "SpotifySDK", package: "SpotifySDK"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
