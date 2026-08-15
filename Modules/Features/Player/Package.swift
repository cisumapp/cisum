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
        // Aesthetics is not here yet. The views below use plain SwiftUI and AsyncImage, which is
        // enough for a working player and keeps this package buildable from the command line.
        // Adding it back (for Vinyl, PlayerExpansionState, StretchySlider) pulls in Kingfisher and
        // makes this package Xcode-only — which is exactly why the playback logic already lives in
        // the separate PlaybackCore package, where it stays testable regardless.
        .package(path: "../PlaybackCore"),
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
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
