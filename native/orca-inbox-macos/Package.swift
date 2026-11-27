// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OrcaInbox",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "InboxCore"),
        .target(name: "InboxUI", dependencies: ["InboxCore"]),
        .executableTarget(name: "OrcaInbox", dependencies: ["InboxCore", "InboxUI"]),
        .testTarget(name: "InboxCoreTests", dependencies: ["InboxCore", "InboxUI"])
    ]
)
