// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppAttestKit",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "AppAttestKit",
            targets: ["AppAttestKit"]
        ),
    ],
    targets: [
        .target(
            name: "AppAttestKit"
        ),
        .testTarget(
            name: "AppAttestKitTests",
            dependencies: ["AppAttestKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
