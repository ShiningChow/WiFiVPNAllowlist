// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WiFiVPNAllowlist",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VPNGuardCore",
            targets: ["VPNGuardCore"]
        ),
        .executable(
            name: "WiFiVPNAllowlist",
            targets: ["WiFiVPNAllowlist"]
        )
    ],
    targets: [
        .target(
            name: "VPNGuardCore"
        ),
        .executableTarget(
            name: "WiFiVPNAllowlist",
            dependencies: ["VPNGuardCore"]
        ),
        .testTarget(
            name: "VPNGuardCoreTests",
            dependencies: ["VPNGuardCore"]
        )
    ]
)
