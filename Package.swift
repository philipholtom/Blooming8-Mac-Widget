// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blooming8",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Blooming8Widget", targets: ["Blooming8Widget"]),
        .executable(name: "Blooming8App", targets: ["Blooming8App"])
    ],
    targets: [
        // Everything that isn't tied to a particular presentation: the device
        // client, the photo/content controller, settings, BLE wake, and the
        // generated content sources. Shared verbatim by the menu bar widget
        // and the windowed app so fixes land once.
        .target(
            name: "Blooming8Core",
            path: "Sources/Blooming8Core"
        ),
        // The menu bar widget: status item + transient popover.
        .executableTarget(
            name: "Blooming8Widget",
            dependencies: ["Blooming8Core"],
            path: "Sources/Blooming8Widget"
        ),
        // The full window app: sidebar + gallery grid.
        .executableTarget(
            name: "Blooming8App",
            dependencies: ["Blooming8Core"],
            path: "Sources/Blooming8App"
        )
    ]
)
