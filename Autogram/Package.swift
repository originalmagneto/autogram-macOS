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
            name: "AutogramWebBridge",
            dependencies: []
        ),
        .target(
            name: "AutogramKit",
            dependencies: ["AutogramWebBridge"]
        ),
        .executableTarget(
            name: "AutogramApp",
            dependencies: ["AutogramKit"]
        ),
        .executableTarget(
            name: "pkcs11-helper",
            dependencies: ["AutogramKit"]
        ),
        .executableTarget(
            name: "vision-eval",
            dependencies: ["AutogramKit"]
        ),
        .executableTarget(
            name: "avm-probe",
            dependencies: ["AutogramKit"]
        ),
        .executableTarget(
            name: "AutogramWebExtensionHandler",
            dependencies: ["AutogramWebBridge"]
        ),
        .executableTarget(
            name: "autogram-webbridge-agent",
            dependencies: ["AutogramWebBridge"]
        ),
        .executableTarget(
            name: "webbridge-probe",
            dependencies: ["AutogramWebBridge"]
        ),
        .testTarget(
            name: "AutogramKitTests",
            dependencies: ["AutogramKit"]
        ),
        .testTarget(
            name: "AutogramAppTests",
            dependencies: ["AutogramApp"]
        )
    ]
)
