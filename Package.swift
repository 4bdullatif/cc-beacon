// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cc-beacon",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "cc-beacon",
            path: "Sources"
        )
    ]
)
