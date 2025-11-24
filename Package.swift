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
        // No external dependencies - pure Swift SDK
    ],
    targets: [
        .target(
            name: "ZumuTranslator",
            dependencies: [],
            path: "Sources/ZumuTranslator"
        ),
    ]
)
