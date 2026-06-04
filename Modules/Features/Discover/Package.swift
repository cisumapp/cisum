// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Discover",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Discover", targets: ["Discover"]),
    ],
    dependencies: [
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
        .package(path: "../Player"),
        .package(path: "../Tracks"),
    ],
    targets: [
        .target(
            name: "Discover",
            dependencies: [
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "Player", package: "Player"),
                .product(name: "Tracks", package: "Tracks"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
