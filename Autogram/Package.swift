// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Autogram",
    platforms: [.macOS("27.0")],
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
        .executableTarget(
            name: "pkcs11-helper",
            dependencies: ["AutogramKit"]
        ),
        .testTarget(
            name: "AutogramKitTests",
            dependencies: ["AutogramKit"]
        )
    ]
)
