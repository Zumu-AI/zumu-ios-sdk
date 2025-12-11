// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZumuTranslator",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        // The main SDK product that integrators will import
        .library(
            name: "ZumuTranslator",
            targets: ["ZumuTranslator"]
        ),
    ],
    dependencies: [
        // LiveKit Swift SDK
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.0.0"),
        // LiveKit Components
        .package(url: "https://github.com/livekit/components-swift.git", from: "0.1.6")
    ],
    targets: [
        .target(
            name: "ZumuTranslator",
            dependencies: [
                .product(name: "LiveKit", package: "client-sdk-swift"),
                .product(name: "LiveKitComponents", package: "components-swift")
            ],
            path: "Sources/ZumuTranslator",
            exclude: [
                "ZumuTranslatorApp.swift",      // Demo app - not part of SDK
                "Examples/",                     // Integration examples
                "Preview Content/",              // Xcode preview assets
                "ZumuTranslator.entitlements",  // App entitlements
                "Info.plist"                     // App Info.plist
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Localizable.xcstrings")
            ]
        )
    ]
)
