// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "LDSwiftEventSource",
    platforms: [
        .iOS(.v10),
        .macOS(.v10_12),
        .watchOS(.v3),
        .tvOS(.v10)
    ],
    products: [
        .library(
            name: "LDSwiftEventSource",
            type: .dynamic,
            targets: ["LDSwiftEventSource"]),
        .library(
            name: "LDSwiftEventSourceStatic",
            type: .static,
            targets: ["LDSwiftEventSource"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LDSwiftEventSource",
            path: "Source"),
        .testTarget(
            name: "LDSwiftEventSourceTests",
            dependencies: ["LDSwiftEventSource"],
            path: "Tests"),
    ],
    swiftLanguageVersions: [.v5])
