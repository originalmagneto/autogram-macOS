// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chevron7",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Chevron7", targets: ["Chevron7App"]),
        .library(name: "Chevron7Kit", targets: ["Chevron7Kit"])
    ],
    targets: [
        .target(
            name: "Chevron7WebBridge",
            dependencies: []
        ),
        .target(
            name: "Chevron7Kit",
            dependencies: ["Chevron7WebBridge"]
        ),
        .executableTarget(
            name: "Chevron7App",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "pkcs11-helper",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "vision-eval",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "avm-probe",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "ezzk-probe",
            dependencies: ["Chevron7Kit"]
        ),
        .executableTarget(
            name: "Chevron7WebExtensionHandler",
            dependencies: ["Chevron7WebBridge"]
        ),
        .executableTarget(
            name: "chevron7-webbridge-agent",
            dependencies: ["Chevron7WebBridge"]
        ),
        .executableTarget(
            name: "webbridge-probe",
            dependencies: ["Chevron7WebBridge"]
        ),
        .testTarget(
            name: "Chevron7KitTests",
            dependencies: ["Chevron7Kit"]
        ),
        .testTarget(
            name: "Chevron7AppTests",
            dependencies: ["Chevron7App"]
        )
    ]
)
