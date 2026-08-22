// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Autogram",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Autogram", targets: ["AutogramApp"]),
        .library(name: "AutogramKit", targets: ["AutogramKit"])
    ],
    targets: [
        .target(
            name: "AutogramKit",
            dependencies: []
        ),
        .executableTarget(
            name: "AutogramApp",
            dependencies: ["AutogramKit"]
        ),
        .testTarget(
            name: "AutogramKitTests",
            dependencies: ["AutogramKit"]
        )
    ]
)
