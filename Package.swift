// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bifrost",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Bifrost",
            path: "Sources/Bifrost",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
