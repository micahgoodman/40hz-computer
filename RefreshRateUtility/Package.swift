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
            path: ".",
            resources: [
                .process("ShortenedPop.aiff")
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "CoreDisplay",
                    "-framework", "DisplayServices"
                ])
            ]
        )
    ]
)
