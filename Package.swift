// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CloudDrop",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "CloudDropCore"),
        .executableTarget(name: "CloudDrop", dependencies: ["CloudDropCore"]),
        .testTarget(name: "CloudDropCoreTests", dependencies: ["CloudDropCore"]),
    ]
)
