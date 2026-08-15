// swift-tools-version: 6.3
import PackageDescription

// Plugins manages the plugin catalog: browse the registry, download a module, store it,
// enable/disable it, keep its settings, check for updates.
//
// It does NOT execute plugins and does NOT know what a MusicSource is. It vends its own
// InstalledPlugin value type; the composition root adapts that to ProviderSDK's PluginBundle.
// That is why ProviderSDK and YouTubeSDK and SpotifySDK and Player are all absent below, and
// scripts/check-boundaries.sh fails the build if any of them reappear.
let package = Package(
    name: "Plugins",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Plugins",
            targets: ["Plugins"]
        ),
    ],
    dependencies: [
        .package(path: "../../Shared/Utilities"),
    ],
    targets: [
        .target(
            name: "Plugins",
            dependencies: [
                .product(name: "Utilities", package: "Utilities"),
            ]
        ),
        .testTarget(
            name: "PluginsTests",
            dependencies: ["Plugins"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
