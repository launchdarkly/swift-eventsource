// swift-tools-version:6.0

import PackageDescription

let package = Package(
  name: "ContractTestService",
  platforms: [
    // Hummingbird's Router/Application are @available(macOS 14, iOS 17, tvOS 17); no watchOS.
    .macOS(.v14),
    .iOS(.v17),
    .tvOS(.v17),
  ],
  products: [
    .executable(
      name: "contract-test-service",
      targets: ["ContractTestService"]
    )
  ],
  dependencies: [
    // Local dependency to LDSwiftEventSource
    .package(name: "LDSwiftEventSource", path: ".."),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0")
  ],
  targets: [
    .executableTarget(
      name: "ContractTestService",
      dependencies: [
        .product(name: "LDSwiftEventSource", package: "LDSwiftEventSource"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "HTTPTypes", package: "swift-http-types")
      ]
    )
  ]
)
