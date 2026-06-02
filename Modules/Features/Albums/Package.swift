// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Albums",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Albums",
            targets: ["Albums"]
        )
    ],
    dependencies: [
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../../Shared/Models"),
        .package(path: "../Tracks"),
        .package(path: "../Player"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Albums",
            dependencies: [
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Models", package: "Models"),
                .product(name: "Tracks", package: "Tracks"),
                .product(name: "Player", package: "Player"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "Kingfisher", package: "Kingfisher")
            ]
        ),
        .testTarget(
            name: "AlbumsTests",
            dependencies: ["Albums"]
        )
    ]
)
