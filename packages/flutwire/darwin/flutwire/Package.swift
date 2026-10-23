// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutwire",
    platforms: [
        .iOS("15.0"),
        .macOS("11.0"),
    ],
    products: [
        .library(name: "flutwire", targets: ["flutwire"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutwire",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
