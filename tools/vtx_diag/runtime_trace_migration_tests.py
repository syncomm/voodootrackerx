import importlib.util
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

from tools.vtx_diag import runtime_trace_correlate_window, runtime_trace_summary


REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY_SUMMARY = REPO_ROOT / "scripts" / "summarize-runtime-c-mixer-trace.py"
LEGACY_CORRELATE = REPO_ROOT / "scripts" / "correlate-runtime-offline-window.py"
UNIFIED_SUMMARY = [sys.executable, "-m", "tools.vtx_diag", "runtime_trace", "summarize"]
UNIFIED_CORRELATE = [
    sys.executable,
    "-m",
    "tools.vtx_diag",
    "runtime_trace",
    "correlate-window",
]


def load_legacy(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def write_trace(path: Path, events: list[dict[str, object]]) -> None:
    path.write_text(
        "".join(json.dumps(event, sort_keys=True) + "\n" for event in events),
        encoding="utf-8",
    )


def write_pcm16_wav(path: Path, frames: list[float], sample_rate: int = 1000) -> None:
    encoded = b"".join(
        struct.pack("<h", max(-32768, min(32767, round(sample * 32767))))
        for sample in frames
    )
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(encoded)


def rich_summary_events() -> list[dict[str, object]]:
    common = {
        "schemaVersion": 1,
        "runtimeAudioBackend": "c_mixer_coreaudio",
        "runtimeOutputHostType": "coreaudio_default_output_unit",
        "sampleRate": 1000,
        "orderIndex": 0,
        "patternIndex": 2,
        "rowIndex": 0,
        "tickInRow": 0,
        "channelIndex": 0,
    }
    return [
        {
            **common,
            "runtimeAction": "backend_selected",
            "backendFlagValue": "c_mixer_coreaudio",
            "runtimeOutputHostRunning": True,
            "runtimeOutputHostStartCount": 1,
            "selectedRuntimeSampleRate": 1000,
            "cMixerRuntimeSampleRate": 1000,
            "cMixerRenderSampleRate": 1000,
            "cMixerRenderChannelCount": 1,
            "audioHardwareNominalSampleRate": 1000,
            "audioHardwareDeviceID": 7,
            "audioHardwareDeviceUIDHash": "synthetic-device-hash",
            "audioOutputRouteLabel": "synthetic-route",
            "audioHardwareIOBufferFrameSize": 64,
            "audioHardwareIOBufferDuration": 0.064,
            "audioHardwareLatencyFrames": 4,
            "audioHardwareSafetyOffsetFrames": 2,
            "audioHardwareTransportTypeName": "synthetic",
            "audioFormatConversionLikely": False,
            "runtimeCaptureMatchesHardwareSampleRate": True,
            "runtimeCaptureEnabled": True,
            "runtimeCapturePathName": "synthetic-runtime.wav",
            "runtimeCaptureSampleRate": 1000,
            "runtimeCaptureChannelCount": 1,
            "runtimeCaptureSeconds": 1,
            "runtimeCaptureFrameLimit": 1000,
            "runtimeCapturedFrameCount": 256,
            "runtimeCaptureDurationSeconds": 0.256,
            "runtimeCaptureTruncated": False,
            "runtimeCaptureOutputPeak": 0.5,
            "runtimeCaptureOutputRMS": 0.1,
            "runtimeCaptureOverrangeSampleCount": 0,
            "runtimeCaptureClippingSampleCount": 0,
            "runtimeCaptureWriteSucceeded": True,
            "runtimeOutputGain": 0.251188643,
            "runtimeHeadroomPolicy": "default_runtime_headroom_db",
            "runtimeGainPolicyLabel": "default_runtime_headroom_db",
            "runtimeDefaultHeadroomDB": -12,
            "runtimeFixedHeadroomDB": -12,
            "runtimeGainPolicySource": "default",
            "runtimeGainPolicyIsEnvironmentOverride": False,
            "runtimeAutoHeadroomEnabled": False,
            "renderCallbackCount": 4,
            "callbackRequestedFrameCount": 64,
            "callbackDurationMinMS": 0.2,
            "callbackDurationMaxMS": 1.2,
            "callbackDurationAverageMS": 0.6,
            "callbackDurationWarningCount": 1,
            "callbackRenderQuantumDurationMS": 1.0,
            "callbackOverRenderQuantumBudgetCount": 1,
            "callbackNearBudgetWarningCount": 1,
            "callbackIntervalMinMS": 0.9,
            "callbackIntervalMaxMS": 1.1,
            "callbackRealtimeSafeDiagnostics": True,
            "callbackRingBufferCapacity": 64,
            "callbackDiagnosticDropCount": 0,
            "callbackLockAttemptCount": 4,
            "callbackTryLockFailureCount": 0,
            "outputBufferCopyAttemptCount": 4,
            "outputBufferCopyFailureCount": 0,
            "outputBufferCopyLastSucceeded": True,
            "outputBufferCopyLayout": "interleaved",
            "outputBufferCopyRequestedFrameCount": 64,
            "outputBufferCopySourceChannelCount": 1,
            "outputBufferCopyOutputBufferCount": 1,
            "outputBufferCopyOutputChannelCount": 1,
            "outputBufferCopyCopiedFrameCount": 64,
            "outputBufferCopyCopiedSampleCount": 64,
            "outputBufferCopyExpectedSampleCount": 64,
            "outputBufferCopyFilledRequestedFrames": True,
            "outputBufferCopyChannelCountMatches": True,
            "outputBufferCopyPartialCopy": False,
            "outputBufferCopyScratchHash": 101,
            "outputBufferCopyCaptureHash": 101,
            "outputBufferCopyOutputHash": 101,
            "outputBufferCopyScratchCaptureHashMatches": True,
            "outputBufferCopyScratchOutputHashMatches": True,
        },
        {
            **common,
            "runtimeAction": "c_mixer_stop_channel_ramped",
            "eventAppliedFrame": 64,
            "runtimeEventCategory": "replacement_stop_ramp",
            "rampedVoiceCount": 1,
            "replacementRampFrames": 32,
            "replacementVoicesOverlap": True,
            "replacementRampCount": 1,
            "replacementGainPanAppliedBeforeRamp": True,
            "replacementStepAppliedBeforeRamp": True,
            "rampingOutVoiceCount": 1,
            "rampDownStartCount": 1,
            "rampDownCompletionCount": 0,
            "abruptRampDownStopCount": 0,
            "activeVoiceCountBefore": 1,
            "activeVoiceCountAfter": 2,
            "loadedVoiceCountBefore": 1,
            "loadedVoiceCountAfter": 2,
        },
        {
            **common,
            "runtimeAction": "c_mixer_add_voice",
            "runtimeEventSource": "offline_adapter_plan",
            "runtimeEventCategory": "note_trigger",
            "plannedRuntimeFrame": 64,
            "runtimeApplicationFrame": 66,
            "eventAppliedFrame": 66,
            "plannedVsAppliedDelta": 2,
            "eventFrameDelta": 2,
            "eventApplicationTiming": "callback_start",
            "inCallbackOffset": 2,
            "appliedPlannedEventCount": 1,
            "callbackBoundaryAppliedEventCount": 1,
            "maxPlannedVsAppliedDelta": 2,
            "activeVoiceCount": 2,
            "loadedVoiceCount": 2,
        },
        {
            **common,
            "runtimeAction": "row_transition",
            "rowIndex": 1,
            "cMixerSampleTimeFrame": 128,
            "cMixerRenderedFrames": 128,
            "cMixerSampleTimePositionStatus": "resolved",
            "cMixerSampleTimeOrderIndex": 0,
            "cMixerSampleTimePatternIndex": 2,
            "cMixerSampleTimeRowIndex": 2,
            "cMixerSampleTimeTickInRow": 0,
            "playbackEngineOrderIndex": 0,
            "playbackEnginePatternIndex": 2,
            "playbackEngineRowIndex": 1,
            "playbackEngineTickInRow": 0,
            "playbackEngineToCMixerFrameDelta": 8,
            "playbackEngineToCMixerPositionMismatch": True,
        },
        {
            **common,
            "runtimeAction": "playback_follow_position_published",
            "cMixerRenderedFrames": 192,
            "cMixerSampleTimeFrame": 192,
            "cMixerSampleTimeOrderIndex": 0,
            "cMixerSampleTimePatternIndex": 2,
            "cMixerSampleTimeRowIndex": 3,
            "cMixerSampleTimeTickInRow": 0,
            "publishedPlaybackFollowPositionSource": "c_mixer_sample_time",
            "publishedPlaybackFollowOrderIndex": 0,
            "publishedPlaybackFollowPatternIndex": 2,
            "publishedPlaybackFollowRowIndex": 3,
            "publishedPlaybackFollowTickInRow": 0,
            "publishedPlaybackFollowSampleTimeFrame": 190,
            "publishedPlaybackFollowToCMixerFrameDelta": 2,
            "publishedPlaybackFollowToCMixerRowDelta": 0,
        },
    ]


class RuntimeTraceMigrationTests(unittest.TestCase):
    def run_command(self, command: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_process_parity(
        self,
        legacy_arguments: list[str],
        unified_arguments: list[str],
    ) -> tuple[subprocess.CompletedProcess[str], subprocess.CompletedProcess[str]]:
        legacy = self.run_command([sys.executable, *legacy_arguments])
        unified = self.run_command(unified_arguments)
        self.assertEqual(unified.returncode, legacy.returncode)
        self.assertEqual(unified.stdout, legacy.stdout)
        self.assertEqual(unified.stderr, legacy.stderr)
        return legacy, unified

    def test_help_and_legacy_helper_reexports(self):
        legacy_summary = load_legacy(LEGACY_SUMMARY, "legacy_runtime_trace_summary")
        legacy_correlate = load_legacy(LEGACY_CORRELATE, "legacy_runtime_trace_correlate")

        self.assertTrue(os.access(LEGACY_SUMMARY, os.X_OK))
        self.assertTrue(os.access(LEGACY_CORRELATE, os.X_OK))
        self.assertIs(legacy_summary.build_summary, runtime_trace_summary.build_summary)
        self.assertIs(legacy_summary.load_trace, runtime_trace_summary.load_trace)
        self.assertIs(legacy_correlate.build_report, runtime_trace_correlate_window.build_report)
        self.assertIs(legacy_correlate.alignment_metrics, runtime_trace_correlate_window.alignment_metrics)
        for command in (
            [sys.executable, str(LEGACY_SUMMARY), "--help"],
            [*UNIFIED_SUMMARY, "--help"],
            [sys.executable, str(LEGACY_CORRELATE), "--help"],
            [*UNIFIED_CORRELATE, "--help"],
        ):
            result = self.run_command(command)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")

    def test_summary_rich_json_markdown_and_live_mode_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            trace = directory / "synthetic-runtime.jsonl"
            json_report = directory / "summary.json"
            markdown = directory / "summary.md"
            write_trace(trace, rich_summary_events())
            shared = [
                str(trace),
                "--live-artifact-reported",
                "yes",
                "--json",
                str(json_report),
                "--markdown",
                str(markdown),
            ]

            legacy = self.run_command([sys.executable, str(LEGACY_SUMMARY), *shared])
            legacy_json = json_report.read_bytes()
            legacy_markdown = markdown.read_bytes()
            unified = self.run_command([*UNIFIED_SUMMARY, *shared])

            self.assertEqual((unified.returncode, unified.stdout, unified.stderr), (legacy.returncode, legacy.stdout, legacy.stderr))
            self.assertEqual(json_report.read_bytes(), legacy_json)
            self.assertEqual(markdown.read_bytes(), legacy_markdown)
            report = json.loads(legacy_json)
            self.assertEqual(report["tool"], "scripts/summarize-runtime-c-mixer-trace.py")
            self.assertEqual(report["backend"]["selection_mode"], "explicit")
            self.assertEqual(report["callback_timing"]["over_render_quantum_budget_count"], 1)
            self.assertEqual(report["output_buffer_copy"]["failure_count"], 0)
            self.assertEqual(report["runtime_policy"]["default_headroom_db"], -12)
            self.assertEqual(report["stops"]["ramped_replacement_stop_events"], 1)
            self.assertEqual(report["sample_time_alignment"]["max_planned_vs_applied_delta"], 2)
            self.assertEqual(report["sample_time_alignment"]["max_playback_engine_vs_c_mixer_abs_frame_delta"], 8)
            self.assertEqual(report["sample_time_alignment"]["max_published_playback_follow_vs_c_mixer_abs_frame_delta"], 2)
            self.assertEqual(report["audio_graph"]["route_label"], "synthetic-route")
            self.assertEqual(report["audio_graph"]["hardware_device_uid_hash"], "synthetic-device-hash")
            self.assertEqual(report["clean_source_dirty_live"]["live_artifact_manually_reported"], "true")
            self.assertEqual(
                sorted(path.name for path in directory.iterdir()),
                ["summary.json", "summary.md", "synthetic-runtime.jsonl"],
            )

    def test_summary_minimal_empty_malformed_and_backend_modes_match(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            trace = directory / "trace.jsonl"
            for events in ([], [{"runtimeAction": "row_transition"}]):
                write_trace(trace, events)
                self.assert_process_parity(
                    [str(LEGACY_SUMMARY), str(trace)],
                    [*UNIFIED_SUMMARY, str(trace)],
                )

            scenarios = (
                ({"runtimeAction": "backend_selected", "runtimeAudioBackend": "c_mixer"}, "default"),
                ({"runtimeAction": "backend_selected", "runtimeAudioBackend": "c_mixer_coreaudio", "backendFlagValue": "c_mixer_coreaudio"}, "explicit"),
                ({"runtimeAction": "backend_selected", "runtimeAudioBackend": "c_mixer", "backendFlagValue": "unknown", "fallbackReason": "unknown_backend"}, "fallback_default"),
            )
            json_report = directory / "backend.json"
            for event, expected in scenarios:
                write_trace(trace, [event])
                shared = [str(trace), "--json", str(json_report)]
                legacy = self.run_command([sys.executable, str(LEGACY_SUMMARY), *shared])
                legacy_bytes = json_report.read_bytes()
                unified = self.run_command([*UNIFIED_SUMMARY, *shared])
                self.assertEqual((unified.returncode, unified.stdout, unified.stderr), (legacy.returncode, legacy.stdout, legacy.stderr))
                self.assertEqual(json_report.read_bytes(), legacy_bytes)
                self.assertEqual(json.loads(legacy_bytes)["backend"]["selection_mode"], expected)

            trace.write_text("{malformed\n", encoding="utf-8")
            legacy, _ = self.assert_process_parity(
                [str(LEGACY_SUMMARY), str(trace)],
                [*UNIFIED_SUMMARY, str(trace)],
            )
            self.assertEqual(legacy.returncode, 2)
            self.assertIn("line 1", legacy.stderr)

    def test_summary_all_live_artifact_modes_match(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            trace = directory / "trace.jsonl"
            report = directory / "summary.json"
            write_trace(trace, rich_summary_events())
            expected = {"yes": "true", "no": "false", "unknown": "unknown"}
            for mode, value in expected.items():
                shared = [str(trace), "--live-artifact-reported", mode, "--json", str(report)]
                legacy = self.run_command([sys.executable, str(LEGACY_SUMMARY), *shared])
                legacy_bytes = report.read_bytes()
                unified = self.run_command([*UNIFIED_SUMMARY, *shared])
                self.assertEqual((unified.returncode, unified.stdout, unified.stderr), (legacy.returncode, legacy.stdout, legacy.stderr))
                self.assertEqual(report.read_bytes(), legacy_bytes)
                self.assertEqual(json.loads(legacy_bytes)["clean_source_dirty_live"]["live_artifact_manually_reported"], value)

    def make_window_fixture(self, directory: Path) -> dict[str, Path]:
        offline = directory / "offline.wav"
        runtime = directory / "runtime.wav"
        trace = directory / "runtime.jsonl"
        comparison = directory / "comparison.json"
        diagnostics = directory / "offline-diagnostics.json"
        frames = [math.sin(2 * math.pi * index / 17) * 0.6 for index in range(128)]
        write_pcm16_wav(offline, frames)
        write_pcm16_wav(runtime, ([0.0] * 3 + frames)[: len(frames)])
        write_trace(
            trace,
            [
                {"runtimeAction": "c_mixer_add_voice", "eventAppliedFrame": 20, "runtimeEventCategory": "note_trigger", "sameFrameBurstID": 9, "sameFrameBurstSize": 3, "sameFrameBurstEventOrdinal": 0, "activeVoiceCountBefore": 1, "activeVoiceCountAfter": 2, "loadedVoiceCountBefore": 1, "loadedVoiceCountAfter": 2, "orderIndex": 0, "patternIndex": 2, "rowIndex": 4, "tickInRow": 0, "channelIndex": 0},
                {"runtimeAction": "c_mixer_stop_channel_ramped", "eventAppliedFrame": 20, "runtimeEventCategory": "replacement_stop_ramp", "sameFrameBurstID": 9, "sameFrameBurstSize": 3, "sameFrameBurstEventOrdinal": 1, "rampDownStartCount": 1, "rampingOutVoiceCount": 1, "activeVoiceCountBefore": 2, "activeVoiceCountAfter": 3, "loadedVoiceCountBefore": 2, "loadedVoiceCountAfter": 3, "orderIndex": 0, "patternIndex": 2, "rowIndex": 4, "tickInRow": 0, "channelIndex": 0},
                {"runtimeAction": "c_mixer_update_step_applied", "eventAppliedFrame": 20, "runtimeEventCategory": "step_pitch_update", "sameFrameBurstID": 9, "sameFrameBurstSize": 3, "sameFrameBurstEventOrdinal": 2, "adapterSustainedVoiceUpdate": True, "adapterChannelAssociationRetained": True, "adapterActiveEventIndex": 4, "activeVoiceCount": 3, "loadedVoiceCount": 4, "orderIndex": 0, "patternIndex": 2, "rowIndex": 4, "tickInRow": 0, "channelIndex": 0},
            ],
        )
        comparison.write_text(
            json.dumps({"sample_comparison": {"worst_windows": [{"start_frame": 20, "end_frame": 60}]}}),
            encoding="utf-8",
        )
        diagnostics.write_text(
            json.dumps({"events": [{"scheduled_frame": 20, "status": "applied", "source": {"order": 0, "pattern": 2, "row": 4}, "channel_index": 0}]}),
            encoding="utf-8",
        )
        return {"offline": offline, "runtime": runtime, "trace": trace, "comparison": comparison, "diagnostics": diagnostics}

    def test_correlate_window_full_reports_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            paths = self.make_window_fixture(directory)
            json_report = directory / "correlation.json"
            markdown = directory / "correlation.md"
            shared = [
                "--runtime-wav", str(paths["runtime"]),
                "--offline-wav", str(paths["offline"]),
                "--runtime-trace", str(paths["trace"]),
                "--window", "0.020:0.060",
                "--window-frames", "70:90",
                "--comparison-json", str(paths["comparison"]),
                "--comparison-window-limit", "1",
                "--offline-diagnostics-json", str(paths["diagnostics"]),
                "--alignment-search-frames", "8",
                "--trace-padding-frames", "4",
                "--trace-event-limit", "10",
                "--json", str(json_report),
                "--markdown", str(markdown),
            ]
            legacy = self.run_command([sys.executable, str(LEGACY_CORRELATE), *shared])
            legacy_json = json_report.read_bytes()
            legacy_markdown = markdown.read_bytes()
            unified = self.run_command([*UNIFIED_CORRELATE, *shared])

            self.assertEqual((unified.returncode, unified.stdout, unified.stderr), (legacy.returncode, legacy.stdout, legacy.stderr))
            self.assertEqual(json_report.read_bytes(), legacy_json)
            self.assertEqual(markdown.read_bytes(), legacy_markdown)
            report = json.loads(legacy_json)
            self.assertEqual(report["tool"], "scripts/correlate-runtime-offline-window.py")
            self.assertEqual(len(report["windows"]), 2)
            first = report["windows"][0]
            self.assertEqual(first["audio"]["alignment"]["best_shift"]["runtime_shift_frames"], 3)
            self.assertTrue(first["offline_diagnostics_correlation"]["provided"])
            self.assertEqual(first["runtime_trace_correlation"]["same_frame_bursts"][0]["event_count"], 3)
            self.assertEqual(first["runtime_trace_correlation"]["active_voice_range"], {"min": 1, "max": 3})
            self.assertEqual(first["runtime_trace_correlation"]["loaded_voice_range"], {"min": 1, "max": 4})
            self.assertTrue(report["recommended_next_pr"])
            self.assertEqual(
                sorted(path.name for path in directory.iterdir()),
                [
                    "comparison.json",
                    "correlation.json",
                    "correlation.md",
                    "offline-diagnostics.json",
                    "offline.wav",
                    "runtime.jsonl",
                    "runtime.wav",
                ],
            )

    def test_correlate_window_stdout_and_invalid_bounds_match(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            paths = self.make_window_fixture(directory)
            base = [
                "--runtime-wav", str(paths["runtime"]),
                "--offline-wav", str(paths["offline"]),
                "--runtime-trace", str(paths["trace"]),
            ]
            legacy, _ = self.assert_process_parity(
                [str(LEGACY_CORRELATE), *base, "--window", "0.020:0.060"],
                [*UNIFIED_CORRELATE, *base, "--window", "0.020:0.060"],
            )
            self.assertIn("Runtime / Offline Window Correlation", legacy.stdout)

            for invalid in (
                [*base, "--window", "0.060:0.020"],
                [*base, "--window", "0.020:0.060", "--alignment-search-frames", "-1"],
            ):
                legacy, _ = self.assert_process_parity(
                    [str(LEGACY_CORRELATE), *invalid],
                    [*UNIFIED_CORRELATE, *invalid],
                )
                self.assertNotEqual(legacy.returncode, 0)

            paths["trace"].write_text("{malformed\n", encoding="utf-8")
            legacy, _ = self.assert_process_parity(
                [str(LEGACY_CORRELATE), *base, "--window", "0.020:0.060"],
                [*UNIFIED_CORRELATE, *base, "--window", "0.020:0.060"],
            )
            self.assertEqual(legacy.returncode, 1)
            self.assertIn("malformed runtime trace", legacy.stderr)


if __name__ == "__main__":
    unittest.main()
