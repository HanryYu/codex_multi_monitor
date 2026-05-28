// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexMonitor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CodexMonitor",
            path: "Sources/CodexMonitor"
        )
    ]
)
