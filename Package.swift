// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoodooTrackerXCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "VTXModuleCore", targets: ["VTXModuleCore"]),
        .executable(name: "vtxmoddump", targets: ["vtxmoddump"]),
    ],
    targets: [
        .target(
            name: "VTXModuleCore",
            path: "core",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .executableTarget(
            name: "vtxmoddump",
            dependencies: ["VTXModuleCore"],
            path: "tools/vtxmoddump"
        ),
        .testTarget(
            name: "VTXModuleCoreTests",
            dependencies: ["VTXModuleCore"],
            path: "tests",
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
