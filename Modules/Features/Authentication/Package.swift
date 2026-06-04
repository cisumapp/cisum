// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Authentication",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "Authentication",
            targets: ["Authentication"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/Aesthetics"),
        .package(url: "https://github.com/clerk/clerk-ios", from: "1.1.3"),
    ],
    targets: [
        .target(
            name: "Authentication",
            dependencies: [
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "ClerkKit", package: "clerk-ios"),
            ]
        ),

    ],
    swiftLanguageModes: [.v6]
)
