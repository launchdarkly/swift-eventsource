// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "LDSwiftEventSource",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0"),
        .watchOS("9.0"),
        .tvOS("15.0")
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
