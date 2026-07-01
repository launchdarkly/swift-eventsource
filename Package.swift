// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "LDSwiftEventSource",
    platforms: [
        .iOS(.v15),
        .macOS(.v11),
        .tvOS(.v15),
        .watchOS(.v8),
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
            path: "Source"
        ),
        .testTarget(
            name: "LDSwiftEventSourceTests",
            dependencies: ["LDSwiftEventSource"],
            path: "Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
