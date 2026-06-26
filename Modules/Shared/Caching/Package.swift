// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Caching",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Caching",
            targets: ["Caching"]
        ),
    ],
    dependencies: [
        .package(path: "../Models"),
        .package(path: "../Utilities"),
    ],
    targets: [
        .target(
            name: "Caching",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
