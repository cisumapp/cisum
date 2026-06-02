// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    dependencies: [
        .package(path: "../Shared/Aesthetics"),
        .package(path: "../Shared/Models"),
        .package(path: "../Shared/Networking"),
        .package(path: "../Shared/Caching"),
        .package(path: "../Shared/Utilities"),

        .package(path: "../Features/Authentication"),
        .package(path: "../Features/Onboarding"),
        .package(path: "../Features/Plugins"),

        .package(path: "../Features/Artists"),
        .package(path: "../Features/Albums"),
        .package(path: "../Features/Playlists"),
        .package(path: "../Features/Tracks"),

        .package(path: "../Features/Home"),
        .package(path: "../Features/Discover"),
        .package(path: "../Features/Library"),
        .package(path: "../Features/Player"),
        .package(path: "../Features/Search"),
        .package(path: "../Features/Profile"),
        .package(path: "../Features/Radio")
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Models", package: "Models"),
                .product(name: "Networking", package: "Networking"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "Caching", package: "Caching"),

                .product(name: "Authentication", package: "Authentication"),
                .product(name: "Onboarding", package: "Onboarding"),
                .product(name: "Plugins", package: "Plugins"),

                .product(name: "Artists", package: "Artists"),
                .product(name: "Albums", package: "Albums"),
                .product(name: "Tracks", package: "Tracks"),
                .product(name: "Playlists", package: "Playlists"),

                .product(name: "Home", package: "Home"),
                .product(name: "Discover", package: "Discover"),
                .product(name: "Library", package: "Library"),
                .product(name: "Player", package: "Player"),
                .product(name: "Search", package: "Search"),
                .product(name: "Profile", package: "Profile"),
                .product(name: "Radio", package: "Radio")
            ]
        )
    ]
)
