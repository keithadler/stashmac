// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StashMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "StashMac",
            path: "Sources/StashMac",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "StashMacTests", dependencies: ["StashMac"], path: "Tests/StashMacTests"),
    ]
)
