// swift-tools-version: 6.0
import PackageDescription

/// The playback logic that has no UI: the AVPlayer engine, the queue, the matcher, and stream
/// resolution.
///
/// This is a separate package rather than a target inside Player for one practical reason. Player's
/// UI needs Aesthetics, Aesthetics pulls in Kingfisher, and Kingfisher does not compile for a macOS
/// command-line build (its PhotosPickerItem provider needs PhotosUI). SwiftPM builds every target in
/// a package before running any test, so a single package would mean these tests could only run
/// through a full Xcode iOS build.
///
/// Splitting the package keeps `swift test` at about a second for the most logic-dense code in the
/// app — the matcher, the queue, the stream selector — which is exactly the code worth testing
/// often. It also enforces the dependency direction at the package level: UI depends on playback
/// logic, never the reverse.
let package = Package(
    name: "PlaybackCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PlaybackCore", targets: ["PlaybackCore"]),
    ],
    dependencies: [
        .package(path: "../../Shared/Models"),
        .package(path: "../../Shared/Utilities"),
        .package(path: "../../../Packages/StreamingKit/ProviderSDK"),
    ],
    targets: [
        .target(
            name: "PlaybackCore",
            dependencies: [
                .product(name: "Models", package: "Models"),
                .product(name: "Utilities", package: "Utilities"),
                .product(name: "ProviderSDK", package: "ProviderSDK"),
            ]
        ),
        .testTarget(
            name: "PlaybackCoreTests",
            dependencies: ["PlaybackCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
