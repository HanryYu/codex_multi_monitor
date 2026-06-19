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
            exclude: ["Info.plist", "Resources", "CodexMonitor.entitlements"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
