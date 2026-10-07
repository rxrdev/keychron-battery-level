// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BatteryKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BatteryKit", targets: ["BatteryKit"])
    ],
    targets: [
        .target(name: "BatteryKit"),
        .testTarget(name: "BatteryKitTests", dependencies: ["BatteryKit"])
    ]
)
