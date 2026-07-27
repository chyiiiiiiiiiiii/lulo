// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "InferenceService",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "InferenceService", targets: ["InferenceService"]),
  ],
  targets: [
    .target(name: "InferenceService"),
    .testTarget(
      name: "InferenceServiceTests",
      dependencies: ["InferenceService"]
    ),
  ]
)
