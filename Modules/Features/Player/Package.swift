// swift-tools-version: 6.0
import PackageDescription

// Player answers one question: given an already-identified track, how do I obtain playable audio
// and manage playback?
//
// It consumes MusicSource from ProviderSDK and never talks to a network itself. It does not know
// that plugins exist — check-boundaries.sh fails the build if `import Plugins` appears here.
//
// Dropped from the previous manifest and why:
//   ffmpeg-kit-spm   artwork video processing (729 LOC) is not a playback concern
//   LyricsKit        Player displays lyrics; fetching them belongs elsewhere
//   iTunesKit        artwork lookup, same reason
//   Radio, Tracks    a feature package should not depend on two sibling feature packages;
//                    the 470 LOC of radio queue seeding belongs in Radio
let package = Package(
    name: "Player",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Player", targets: ["Player"]),
    ],
    dependencies: [
        // Aesthetics is intentionally absent until the UI lands. It pulls in Kingfisher, which
        // does not build for a macOS command-line `swift build` (PhotosPickerItem needs PhotosUI),
        // and keeping it out means the engine, queue, matching, and resolution layers stay
        // testable with `swift test` instead of only through an Xcode iOS build.
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../../Packages/StreamingKit/ProviderSDK"),
    ],
    targets: [
        .target(
            name: "Player",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "ProviderSDK", package: "ProviderSDK"),
            ]
        ),
        .testTarget(
            name: "PlayerTests",
            dependencies: ["Player"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
