// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Catalog",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Catalog", targets: ["Catalog"]),
    ],
    dependencies: [
        .package(path: "../Models"),
        .package(path: "../Utilities"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(path: "../../../Packages/StreamingKit/iTunesKit"),
    ],
    targets: [
        .target(
            name: "Catalog",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "iTunesKit", package: "iTunesKit"),
            ]
        ),
        .testTarget(name: "CatalogTests", dependencies: ["Catalog"]),
    ],
    swiftLanguageModes: [.v6]
)
