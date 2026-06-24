// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Utilities",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Utilities", targets: ["Utilities"]),
    ],
    targets: [
        .target(
            name: "Utilities"
        ),
    ],
    swiftLanguageModes: [.v6]
)
