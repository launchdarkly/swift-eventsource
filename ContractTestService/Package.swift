// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "ContractTestService",
  platforms: [
    .iOS(.v11),
    .macOS(.v10_13),
    .watchOS(.v4),
    .tvOS(.v11),
  ],
  products: [
    .executable(
      name: "contract-test-service",
      targets: ["ContractTestService"]
    )
  ],
  dependencies: [
    // Local dependency to LDSwiftEventSource
    .package(path: ".."),
    .package(url: "https://github.com/Kitura/Kitura", from: "2.9.200")
  ],
  targets: [
    .target(
      name: "ContractTestService",
      dependencies: [
        "LDSwiftEventSource",
        "Kitura"
      ]
    )
  ]
)
