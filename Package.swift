// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoodooTrackerXCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ModuleCore", targets: ["ModuleCore"]),
        .library(name: "MixerCore", targets: ["MixerCore"]),
        .executable(name: "mc_dump", targets: ["mc_dump"]),
        .executable(name: "vtx_render_bounded_xm", targets: ["vtx_render_bounded_xm"]),
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
        .target(
            name: "MixerCore",
            path: "core/MixerCore",
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
        .executableTarget(
            name: "vtx_render_bounded_xm",
            dependencies: ["VoodooTrackerXPlaybackSupport"],
            path: "tools/vtx_render_bounded_xm"
        ),
        .target(
            name: "VoodooTrackerXPlaybackSupport",
            dependencies: ["ModuleCore", "MixerCore"],
            path: "app/VoodooTrackerX/VoodooTrackerX",
            exclude: [
                "AppDelegate.swift",
                "AudioEngine.swift",
                "ControlPanelView.swift",
                "LogoPanelView.swift",
                "ModuleCoreBridge.h",
                "PlaybackEffect.swift",
                "PlaybackEngine.swift",
                "PlaybackTrace.swift",
                "PlaybackTraceEvent.swift",
                "PlaybackTraceWriter.swift",
                "PlaybackTransport.swift",
                "PlaybackTypes.swift",
                "TrackerEditorView.swift",
                "TrackerTheme.swift",
                "TrackerWindowController.swift",
            ],
            sources: [
                "AudioTypes.swift",
                "BoundedXMRenderTool.swift",
                "ModuleMetadataLoader.swift",
                "PlaybackSongBuilder.swift",
                "PlaybackSong.swift",
                "PlaybackTiming.swift",
                "SoftwareMixer.swift",
                "CSoftwareMixer.swift",
            ]
        ),
        .testTarget(
            name: "ModuleCoreTests",
            dependencies: ["ModuleCore"],
            path: "tests",
            exclude: ["vtx_render_bounded_xm"],
            sources: ["core"],
            resources: [
                .copy("fixtures"),
                .copy("golden")
            ]
        ),
        .testTarget(
            name: "VTXRenderBoundedXMTests",
            dependencies: ["VoodooTrackerXPlaybackSupport"],
            path: "tests/vtx_render_bounded_xm"
        ),
    ]
)
