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
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
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
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "LDSwiftEventSource",
            path: "Source"),
        .testTarget(
            name: "LDSwiftEventSourceTests",
            dependencies: ["LDSwiftEventSource"],
            path: "Tests"),
    ],
    swiftLanguageVersions: [.v5])
