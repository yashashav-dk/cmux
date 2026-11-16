// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxClaudeLimits",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CmuxClaudeLimits",
            targets: ["CmuxClaudeLimits"]
        ),
    ],
    dependencies: [
        .package(path: "../CmuxFoundation"),
        .package(path: "../CmuxSettings"),
        .package(path: "../CMUXDebugLog"),
    ],
    targets: [
        .target(
            name: "CmuxClaudeLimits",
            dependencies: [
                "CmuxFoundation",
                "CmuxSettings",
                .product(name: "CMUXDebugLog", package: "CMUXDebugLog"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxClaudeLimitsTests",
            dependencies: [
                "CmuxClaudeLimits",
                .product(name: "CmuxFoundation", package: "CmuxFoundation"),
                .product(name: "CmuxSettings", package: "CmuxSettings"),
            ]
        ),
    ]
)
