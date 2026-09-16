// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "ContractTestService",
  platforms: [
    .iOS("15.0"),
    .macOS("12.0"),
    .watchOS("9.0"),
    .tvOS("15.0"),
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
