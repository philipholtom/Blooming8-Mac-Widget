// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blooming8Widget",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Blooming8Widget",
            path: "Sources/Blooming8Widget"
        )
    ]
)
