// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "ZumuTranslator",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ZumuTranslator",
            targets: ["ZumuTranslator"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/client-sdk-swift", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "ZumuTranslator",
            dependencies: [
                .product(name: "LiveKit", package: "client-sdk-swift")
            ],
            path: "Sources/ZumuTranslator"
        ),
        .testTarget(
            name: "ZumuTranslatorTests",
            dependencies: ["ZumuTranslator"],
            path: "Tests/ZumuTranslatorTests"
        ),
    ]
)
