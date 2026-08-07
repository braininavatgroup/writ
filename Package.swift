// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Writ",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Writ", path: "Sources/Writ")
    ]
)
