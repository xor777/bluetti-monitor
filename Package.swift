// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BluettiMonitor",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BluettiCore", targets: ["BluettiCore"]),
        .executable(name: "BluettiMonitor", targets: ["BluettiMonitor"]),
        .executable(name: "BluettiCoreTests", targets: ["BluettiCoreTests"]),
    ],
    targets: [
        .target(
            name: "BluettiCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "BluettiMonitor",
            dependencies: ["BluettiCore"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .executableTarget(
            name: "BluettiCoreTests",
            dependencies: ["BluettiCore"],
            path: "Tests/BluettiCoreTests"
        ),
    ]
)
