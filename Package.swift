// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tablet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tablet",
            path: "Sources/Tablet",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(
            name: "TabletTests",
            dependencies: ["Tablet"],
            path: "Tests/TabletTests"
        ),
    ]
)
