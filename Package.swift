// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMonitor",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "CodexMonitor",
            path: "Sources/CodexMonitor",
            exclude: ["Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
