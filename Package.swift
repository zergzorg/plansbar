// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlansBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PlansCore", targets: ["PlansCore"]),
        .executable(name: "PlansBarApp", targets: ["PlansBar"]),
        .executable(name: "plansbar", targets: ["PlansBarCLI"])
    ],
    targets: [
        .target(name: "PlansCore"),
        .executableTarget(name: "PlansBar", dependencies: ["PlansCore"]),
        .executableTarget(
            name: "PlansBarCLI",
            dependencies: ["PlansCore"],
            path: "Sources/plansbar-cli"
        ),
        .testTarget(
            name: "PlansCoreTests",
            dependencies: ["PlansCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
