// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TerraFlyerSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "TerraFlyerSDK",
            targets: ["TerraFlyerSDK"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TerraFlyerSDK",
            dependencies: [],
            path: "Sources/TerraFlyerSDK")
    ]
)
