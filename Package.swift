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
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "LDSwiftEventSource",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Source",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "LDSwiftEventSourceTests",
            dependencies: ["LDSwiftEventSource"],
            path: "Tests",
            swiftSettings: [
                // Library is on the v6 language mode; the test target follows in a
                // later step once the test doubles are made Sendable.
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
