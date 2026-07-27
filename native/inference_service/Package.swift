// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "InferenceService",
  platforms: [.macOS(.v12)],
  products: [
    .library(name: "InferenceService", targets: ["InferenceService"]),
    .executable(
      name: "LiteRTLMCompileSmoke",
      targets: ["LiteRTLMCompileSmoke"]
    ),
  ],
  dependencies: [
    .package(path: "../vendor/litert_lm"),
  ],
  targets: [
    .target(
      name: "InferenceService",
      dependencies: [
        .product(name: "LiteRTLM", package: "litert_lm"),
      ]
    ),
    .executableTarget(
      name: "LiteRTLMCompileSmoke",
      dependencies: [
        .product(name: "LiteRTLM", package: "litert_lm"),
      ]
    ),
    .testTarget(
      name: "InferenceServiceTests",
      dependencies: [
        "InferenceService",
        .product(name: "LiteRTLM", package: "litert_lm"),
      ]
    ),
  ]
)
