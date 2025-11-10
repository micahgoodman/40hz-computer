// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "40HzLaptop",
    platforms: [
        .macOS(.v10_13)
    ],
    dependencies: [],
    targets: [
        .target(
            name: "40HzLaptop",
            dependencies: [],
            path: ".",
            exclude: [
                "README.md",
                "Frameworks"
            ],
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
