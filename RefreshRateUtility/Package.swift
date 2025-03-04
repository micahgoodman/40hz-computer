// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "RefreshRateUtility",
    platforms: [
        .macOS(.v10_13)
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RefreshRateUtility",
            dependencies: [],
            path: "."
        )
    ]
)
