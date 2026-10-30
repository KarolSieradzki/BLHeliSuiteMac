// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BLHeliSuiteMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BLHeliSuite", targets: ["BLHeliSuiteApp"]),
        .executable(name: "blheli-cli", targets: ["BLHeliCLI"]),
        .executable(name: "blheli-sim", targets: ["BLHeliSim"]),
        .executable(name: "blheli-selftest", targets: ["BLHeliSelfTest"]),
    ],
    targets: [
        .target(
            name: "BLHeliCore",
            path: "Sources/BLHeliCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "BLHeliSuiteApp",
            dependencies: ["BLHeliCore"],
            path: "Sources/BLHeliSuiteApp"
        ),
        .executableTarget(
            name: "BLHeliCLI",
            dependencies: ["BLHeliCore"],
            path: "Sources/BLHeliCLI"
        ),
        .executableTarget(
            name: "BLHeliSim",
            dependencies: ["BLHeliCore"],
            path: "Sources/BLHeliSim"
        ),
        .executableTarget(
            name: "BLHeliSelfTest",
            dependencies: ["BLHeliCore"],
            path: "Sources/BLHeliSelfTest"
        ),
    ]
)
