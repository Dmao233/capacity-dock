// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CapacityDock",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CapacityDock", targets: ["CapacityDock"])
    ],
    targets: [
        .executableTarget(
            name: "CapacityDock",
            path: "Sources/CapacityDock",
            resources: [
                .process("Resources/ProviderIcons"),
                .process("Resources/zh-Hans.lproj")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CapacityDockTests",
            dependencies: ["CapacityDock"],
            path: "Tests/CapacityDockTests"
        )
    ]
)
