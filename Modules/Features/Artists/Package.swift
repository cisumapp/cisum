// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Artists",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Artists",
            targets: ["Artists"]
        )
    ],
    dependencies: [
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../Shared/Aesthetics"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(path: "../Player"),
        .package(path: "../Albums"),
        .package(path: "../Tracks")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Artists",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "Player", package: "Player"),
                .product(name: "Albums", package: "Albums"),
                .product(name: "Tracks", package: "Tracks")
            ]
        )

    ],
    swiftLanguageModes: [.v6]
)
