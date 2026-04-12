// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchAgent",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchAgent", targets: ["NotchAgent"]),
        .executable(name: "NotchBridge", targets: ["NotchBridge"]),
    ],
    targets: [
        .executableTarget(
            name: "NotchAgent",
            path: "Sources/NotchAgent"
        ),
        .executableTarget(
            name: "NotchBridge",
            path: "Sources/NotchBridge"
        ),
    ]
)
