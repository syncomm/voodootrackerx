// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoodooTrackerXCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ModuleCore", targets: ["ModuleCore"]),
        .executable(name: "mc_dump", targets: ["mc_dump"]),
    ],
    targets: [
        .target(
            name: "ModuleCore",
            path: "core/ModuleCore",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .executableTarget(
            name: "mc_dump",
            dependencies: ["ModuleCore"],
            path: "tools/mc_dump"
        ),
        .testTarget(
            name: "ModuleCoreTests",
            dependencies: ["ModuleCore"],
            path: "tests",
            sources: ["core"],
            resources: [
                .copy("fixtures")
            ]
        ),
    ]
)
