// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ccpulse",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "ccpulse",
            dependencies: ["Sparkle"],
            path: "Sources",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "ccpulseTests",
            dependencies: ["ccpulse"],
            path: "Tests"
        )
    ]
)
