// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AWSSSOToolkit",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "AWSSSOToolkit",
      targets: ["AWSSSOToolkit"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
    .package(
      url: "https://github.com/awslabs/aws-sdk-swift",
      from: "1.2.0"
    ),
    .package(
      url: "https://github.com/groue/GRDB.swift",
      from: "7.3.0"
    )
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "AWSSSOToolkit",
      dependencies: [
        .product(name: "AWSSSOOIDC", package: "aws-sdk-swift"),
        .product(name: "AWSSSO", package: "aws-sdk-swift"),
        .product(name: "AWSSTS", package: "aws-sdk-swift"),
        .product(name: "GRDB", package: "GRDB.swift"),
      ],
      plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
    ),
    .testTarget(
      name: "AWSSSOToolkitTests",
      dependencies: ["AWSSSOToolkit"]
    ),
  ]
)
