// swift-tools-version: 6.1

import PackageDescription

// A minimal consumer, resolved by path. It exists so that CI proves what a
// dependant actually sees: the product name, the supported platforms and the
// public API, without any of the package's own test scaffolding.
let package = Package(
    name: "BusinessIDConsumer",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "BusinessIDConsumer",
            dependencies: [.product(name: "BusinessID", package: "businessid-swift")]
        )
    ]
)
