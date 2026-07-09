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
            path: "tools/vtx_render_bounded_xm",
            exclude: ["Support"],
            sources: ["main.swift"]
        ),
        // Explicitly spans app playback support plus the tool-owned render CLI body.
        .target(
            name: "VoodooTrackerXPlaybackSupport",
            dependencies: ["ModuleCore", "MixerCore"],
            path: ".",
            exclude: [
                ".build",
                ".claude",
                ".derivedData",
                ".DS_Store",
                ".github",
                ".gitignore",
                ".gitmodules",
                "AGENTS.md",
                "LICENSE",
                "Package.swift",
                "README.md",
                "app/VoodooTrackerX/VoodooTrackerX.xcodeproj",
                "app/VoodooTrackerX/VoodooTrackerX/AppDelegate.swift",
                "app/VoodooTrackerX/VoodooTrackerX/ApplicationMenuBuilder.swift",
                "app/VoodooTrackerX/VoodooTrackerX/AudioBackendSelection.swift",
                "app/VoodooTrackerX/VoodooTrackerX/AudioEngine.swift",
                "app/VoodooTrackerX/VoodooTrackerX/BlankTrackerDocument.swift",
                "app/VoodooTrackerX/VoodooTrackerX/ControlPanelDisplayState.swift",
                "app/VoodooTrackerX/VoodooTrackerX/ControlPanelView.swift",
                "app/VoodooTrackerX/VoodooTrackerX/EditorControlPrimitives.swift",
                "app/VoodooTrackerX/VoodooTrackerX/EditorKnobControls.swift",
                "app/VoodooTrackerX/VoodooTrackerX/EditorNoteAuditionAudioSink.swift",
                "app/VoodooTrackerX/VoodooTrackerX/EditableXMWriter.swift",
                "app/VoodooTrackerX/VoodooTrackerX/ExportXMCoordinator.swift",
                "app/VoodooTrackerX/VoodooTrackerX/WAVExportCoordinator.swift",
                "app/VoodooTrackerX/VoodooTrackerX/LoadedModuleEditableCopyCoordinator.swift",
                "app/VoodooTrackerX/VoodooTrackerX/LogoPanelView.swift",
                "app/VoodooTrackerX/VoodooTrackerX/ModuleCoreBridge.h",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackEffect.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackEngine.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackTrace.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackTraceEvent.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackTraceWriter.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackTransport.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackTypes.swift",
                "app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerCapture.swift",
                "app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerDiagnostics.swift",
                "app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerOutputRouteDiagnostics.swift",
                "app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerRenderCore.swift",
                "app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerBackend.swift",
                "app/VoodooTrackerX/VoodooTrackerX/SongOrderEditorWindowController.swift",
                "app/VoodooTrackerX/VoodooTrackerX/TrackerEditorView.swift",
                "app/VoodooTrackerX/VoodooTrackerX/TrackerTheme.swift",
                "app/VoodooTrackerX/VoodooTrackerX/TrackerWindowController.swift",
                "app/VoodooTrackerX/VoodooTrackerXTests",
                "assets",
                "build",
                "build-release",
                "core",
                "default.profraw",
                "dist",
                "docs",
                "legacy",
                "scripts",
                "tests",
                "tools/__pycache__",
                "tools/audio_compare_tests.py",
                "tools/mc_dump",
                "tools/private_xm_corpus_label_map_tests.py",
                "tools/synthetic_xm_fixture_generator_tests.py",
                "tools/vtx_render_bounded_xm/main.swift",
                "tools/xm_residual_effect_scan_tests.py",
            ],
            sources: [
                "app/VoodooTrackerX/VoodooTrackerX/AudioTypes.swift",
                "app/VoodooTrackerX/VoodooTrackerX/ModuleMetadataLoader.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackModel.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+Diagnostics.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+PitchEffects.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+RuntimeEvents.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+SampleEffects.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+Timing.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+Traversal.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+VolumeColumn.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongAdapter+VolumeEffects.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongBuilder.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongDiagnostics.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackSongOfflineRender.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackTiming.swift",
                "app/VoodooTrackerX/VoodooTrackerX/PlaybackVolumeColumnDecoder.swift",
                "app/VoodooTrackerX/VoodooTrackerX/RuntimeCMixerAdapterEventPlan.swift",
                "app/VoodooTrackerX/VoodooTrackerX/SoftwareMixer.swift",
                "app/VoodooTrackerX/VoodooTrackerX/CSoftwareMixer.swift",
                "app/VoodooTrackerX/VoodooTrackerX/XMEffectCommandDisplay.swift",
                "tools/vtx_render_bounded_xm/Support/BoundedXMRenderTool.swift",
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
                .copy("golden"),
                .copy("reference-xm")
            ]
        ),
        .testTarget(
            name: "VTXRenderBoundedXMTests",
            dependencies: ["VoodooTrackerXPlaybackSupport"],
            path: "tests/vtx_render_bounded_xm"
        ),
    ]
)
