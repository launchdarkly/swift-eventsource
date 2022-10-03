// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "LDSwiftEventSource",
    platforms: [
        .iOS(.v11),
        .macOS(.v10_13),
        .watchOS(.v4),
        .tvOS(.v11)
    ],
    products: [
        .library(name: "LDSwiftEventSource", targets: ["LDSwiftEventSource"]),
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
