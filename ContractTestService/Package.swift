// swift-tools-version:5.9

import PackageDescription

let package = Package(
  name: "ContractTestService",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .watchOS(.v9),
    .tvOS(.v16),
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
    .package(url: "https://github.com/Kitura/Kitura", from: "2.9.200")
  ],
  targets: [
    .target(
      name: "ContractTestService",
      dependencies: [
        .product(name: "LDSwiftEventSource", package: "LDSwiftEventSource"),
        "Kitura"
      ]
    )
  ]
)
