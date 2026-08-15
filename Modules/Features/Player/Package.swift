// swift-tools-version: 6.0
import PackageDescription

/// Player answers one question: given an already-identified track, how do I obtain playable audio
/// and manage playback?
///
/// It consumes MusicSource from ProviderSDK and never talks to a network itself. It does not know
/// that plugins exist — check-boundaries.sh fails the build if `import Plugins` appears here.
///
/// This package is the UI and the surface other feature modules call. The playback logic lives in
/// the sibling PlaybackCore package — see its Package.swift for why the split exists. `import
/// Player` re-exports it, so call sites need only one import.
///
/// Dropped from the previous manifest and why:
///   ffmpeg-kit-spm   artwork video processing (729 LOC) is not a playback concern
///   LyricsKit        Player displays lyrics; fetching them belongs elsewhere
///   iTunesKit        artwork lookup, same reason
///   Radio, Tracks    a feature package should not depend on two sibling feature packages;
///                    the 470 LOC of radio queue seeding belongs in Radio
let package = Package(
    name: "Player",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Player", targets: ["Player"]),
    ],
    dependencies: [
        // The player UI needs these: Aesthetics for Vinyl / PlayerExpansionState / StretchySlider,
        // Kingfisher for artwork, Tracks for TrackListItem, YouTubeSDK for the media ref types the
        // views still name. Kingfisher does not build for a macOS command-line `swift build`, so
        // this package is Xcode-only — which is precisely why the playback logic lives in the
        // separate PlaybackCore package, where `swift test` still runs in milliseconds.
        .package(path: "../PlaybackCore"),
        .package(path: "../../Shared/Aesthetics"),
        .package(path: "../../Shared/Caching"),
        .package(path: "../Tracks"),
        .package(path: "../../../Packages/StreamingKit/YouTubeSDK"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "8.9.0")),
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../../Packages/StreamingKit/ProviderSDK"),
    ],
    targets: [
        .target(
            name: "Player",
            dependencies: [
                .product(name: "PlaybackCore", package: "PlaybackCore"),
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "ProviderSDK", package: "ProviderSDK"),
                .product(name: "Aesthetics", package: "Aesthetics"),
                .product(name: "Caching", package: "Caching"),
                .product(name: "Tracks", package: "Tracks"),
                .product(name: "YouTubeSDK", package: "YouTubeSDK"),
                .product(name: "Kingfisher", package: "Kingfisher"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
