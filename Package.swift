// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "LDSwiftEventSource",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "LDSwiftEventSource", targets: ["LDSwiftEventSource"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LDSwiftEventSource",
            path: "Source",
            swiftSettings: [
                // Sendable annotations land first under v5 (mismatches are warnings);
                // the .v6 flip comes with the delegate/logging Sendable cleanup.
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "LDSwiftEventSourceTests",
            dependencies: ["LDSwiftEventSource"],
            path: "Tests",
            swiftSettings: [
                // Sendable annotations land first under v5 (mismatches are warnings);
                // the .v6 flip comes with the delegate/logging Sendable cleanup.
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
