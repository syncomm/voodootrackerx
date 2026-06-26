import contextlib
import importlib.util
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "run-local-corpus-runtime-metrics.py"
REPO_ROOT = Path(__file__).resolve().parents[1]


def load_module():
    spec = importlib.util.spec_from_file_location("local_corpus_runtime_metrics", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class LocalCorpusRuntimeMetricsTests(unittest.TestCase):
    def test_dry_run_prints_only_selected_anonymized_labels(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            private_module = directory / "private-title.xm"
            private_module.write_bytes(b"synthetic")
            label_map = write_label_map(directory, [("xm-corpus-001", private_module)])

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                result = module.main(["--label-map", str(label_map), "--labels", "xm-corpus-001", "--dry-run"])

            self.assertEqual(result, 0)
            self.assertEqual(stdout.getvalue().strip(), "xm-corpus-001")
            self.assertNotIn(str(private_module), stdout.getvalue())
            self.assertNotIn(private_module.name, stdout.getvalue())

    def test_run_writes_label_based_redacted_outputs_and_summary(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            private_module = directory / "secret-module-name.xm"
            private_module.write_bytes(b"synthetic")
            label_map = write_label_map(directory, [("xm-corpus-001", private_module)])
            fake_app = write_fake_app(directory)
            output_dir = directory / "metrics"

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                result = module.main(
                    [
                        "--label-map",
                        str(label_map),
                        "--labels",
                        "xm-corpus-001",
                        "--output-dir",
                        str(output_dir),
                        "--app-path",
                        str(fake_app),
                        "--seconds",
                        "1",
                        "--pre-play-delay-seconds",
                        "5",
                        "--allow-repo-output",
                    ]
                )

            self.assertEqual(result, 0)
            self.assertIn("xm-corpus-001: exited_zero", stdout.getvalue())
            label_dir = output_dir / "xm-corpus-001"
            output_names = sorted(path.name for path in label_dir.iterdir())
            self.assertEqual(
                output_names,
                [
                    "xm-corpus-001.metrics.json",
                    "xm-corpus-001.runtime-c-mixer-trace.jsonl",
                    "xm-corpus-001.stderr.txt",
                    "xm-corpus-001.stdout.txt",
                ],
            )
            combined = "\n".join(path.read_text(encoding="utf-8") for path in label_dir.iterdir() if path.is_file())
            self.assertNotIn(str(private_module), combined)
            self.assertNotIn(private_module.name, combined)
            self.assertNotIn(private_module.stem, combined)
            self.assertIn("pre_play_delay=5", (label_dir / "xm-corpus-001.stdout.txt").read_text(encoding="utf-8"))

            summary = json.loads((label_dir / "xm-corpus-001.metrics.json").read_text(encoding="utf-8"))
            self.assertEqual(summary["label"], "xm-corpus-001")
            self.assertTrue(summary["replay_after_stop"])
            self.assertEqual(summary["pre_play_delay_seconds"], 5.0)
            self.assertEqual(summary["playback_timing_line_count"], 13)
            self.assertEqual(summary["adapter_plan_profile_line_count"], 11)
            self.assertEqual(summary["runtime_mixer_metrics_line_count"], 2)
            self.assertTrue(summary["runtime_trace_written"])
            self.assertEqual(summary["stdout_log"], "xm-corpus-001.stdout.txt")
            self.assertEqual(summary["metadata"]["channel_count"], 8)
            self.assertEqual(summary["metadata"]["pattern_count"], 12)
            self.assertEqual(summary["timings_ms"]["load_total"], 15.0)
            self.assertEqual(summary["timings_ms"]["playback_song_builder_build"], 8.5)
            self.assertIsNone(summary["timings_ms"]["runtime_adapter_plan_total"])
            self.assertEqual(summary["timings_ms"]["prewarm_runtime_adapter_plan_total"], 3.5)
            self.assertTrue(summary["timings_ms"]["prewarm_completed_before_first_play"])
            self.assertEqual(summary["timings_ms"]["first_play_runtime_adapter_plan_mode"], "prewarmed")
            self.assertIsNone(summary["timings_ms"]["first_play_runtime_adapter_plan_total"])
            self.assertEqual(summary["timings_ms"]["first_play_total"], 4.0)
            self.assertEqual(summary["timings_ms"]["second_play_runtime_adapter_plan_mode"], "cached_reuse")
            self.assertEqual(summary["timings_ms"]["second_play_total"], 1.5)
            self.assertTrue(summary["timings_ms"]["second_play_reused_runtime_adapter_plan"])
            self.assertTrue(summary["adapter_plan_profile"]["available"])
            self.assertEqual(summary["adapter_plan_profile"]["adapter_plan_total_ms"], 3.8)
            self.assertEqual(summary["adapter_plan_profile"]["adapt_total_ms"], 3.0)
            self.assertEqual(summary["adapter_plan_profile"]["backend_configure_ms"], 0.9)
            self.assertEqual(summary["adapter_plan_profile"]["planned_event_count"], 7)
            self.assertEqual(summary["adapter_plan_profile"]["order_count"], 4)
            self.assertEqual(summary["adapter_plan_profile"]["pattern_count"], 12)
            self.assertEqual(summary["adapter_plan_profile"]["row_count"], 256)
            self.assertEqual(summary["adapter_plan_profile"]["category_count"], 3)
            self.assertEqual(summary["adapter_plan_profile"]["planned_song_end_frame"], 100)
            self.assertEqual(summary["adapter_plan_profile"]["top_phases"][0]["phase"], "pattern_row_iteration")
            self.assertEqual(summary["runtime_metrics"]["output_peak"], 0.3)
            self.assertEqual(summary["runtime_metrics"]["output_rms"], 0.06)
            self.assertEqual(summary["runtime_metrics"]["clipping_sample_count"], 0)
            self.assertFalse(summary["runtime_metrics"]["clipping_detected"])
            run_summary = json.loads((output_dir / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(run_summary["labels"], ["xm-corpus-001"])
            self.assertEqual(run_summary["adapter_plan_profile_line_counts"]["xm-corpus-001"], 11)
            self.assertTrue((output_dir / "summary.md").exists())
            self.assertIn("pattern_row_iteration=1.5ms", (output_dir / "summary.md").read_text(encoding="utf-8"))

    def test_refuses_repo_output_without_override(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            private_module = directory / "private.xm"
            private_module.write_bytes(b"synthetic")
            label_map = write_label_map(directory, [("xm-corpus-001", private_module)])
            fake_app = write_fake_app(directory)
            stderr = io.StringIO()

            with contextlib.redirect_stderr(stderr):
                result = module.main(
                    [
                        "--label-map",
                        str(label_map),
                        "--limit",
                        "1",
                        "--output-dir",
                        str(REPO_ROOT / "local-corpus-runtime-metrics-test-output"),
                        "--app-path",
                        str(fake_app),
                    ]
                )

            self.assertEqual(result, 1)
            self.assertIn("refusing to write diagnostics inside the repository", stderr.getvalue())

    def test_missing_map_is_user_facing_error(self):
        module = load_module()
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            result = module.main(["--label-map", "/tmp/definitely-missing-map.json", "--limit", "1", "--dry-run"])

        self.assertEqual(result, 1)
        self.assertIn("label map does not exist", stderr.getvalue())


def write_label_map(directory, entries):
    path = directory / "label-map.json"
    path.write_text(
        json.dumps({"entries": [{"label": label, "path": str(module_path)} for label, module_path in entries]}),
        encoding="utf-8",
    )
    return path


def write_fake_app(directory):
    path = directory / "fake-vtx-app.py"
    path.write_text(
        """#!/usr/bin/env python3
import os
import sys

source = os.environ.get("VTX_OPEN_PATH", "")
print(f"opened {source}")
print(f"pre_play_delay={os.environ.get('VTX_DEBUG_PRE_PLAY_DELAY_SECONDS', '')}")
print(f"private diagnostic path {source}", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=module_metadata_loader_load index=1 elapsed_ms=1.000 module_type=XM channel_count=8 order_count=4 pattern_count=12 instrument_count=3", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=playback_song_builder_build index=2 elapsed_ms=8.500", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=runtime_adapter_event_plan_invalidated index=3 elapsed_ms=0.010", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=runtime_adapter_event_plan_prewarm_scheduled index=4 elapsed_ms=0.010", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=total index=5 elapsed_ms=15.000 module_type=XM channel_count=8 order_count=4 pattern_count=12 instrument_count=3", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=prewarm phase=runtime_adapter_event_plan_prewarm_scheduled index=1 elapsed_ms=0.010", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=prewarm phase=runtime_adapter_event_plan_prewarm_make index=2 elapsed_ms=2.500 plan_generated=true planned_event_count=1 category_count=1 planned_song_end_frame=100", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=prewarm phase=runtime_adapter_event_plan_prewarm_configure index=3 elapsed_ms=1.000 plan_generated=true planned_event_count=1 category_count=1 planned_song_end_frame=100", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=prewarm phase=total index=4 elapsed_ms=3.750 prewarm_outcome=installed", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=order_traversal index=1 elapsed_ms=0.500 order_count=4 pattern_count=12 source_row_count=256 row_count=256 adapted_order_count=4 traversal_diagnostic_count=2 traversal_guard_hit=false traversal_stop_reason=song_end", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=timing_frame_calculation index=2 elapsed_ms=0.250 row_count=256 timing_change_count=1 initial_speed=6 initial_bpm=125 final_speed=6 final_bpm=125", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=traversal_effect_status_indexing index=3 elapsed_ms=0.125 traversal_diagnostic_count=2 traversal_effect_status_count=2", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=event_generation index=4 elapsed_ms=1.250 row_count=256 synthetic_event_count=5 event_mapping_count=5 ignored_cell_count=2 voice_state_update_count=1", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=pattern_row_iteration index=5 elapsed_ms=1.500 row_count=256 row_diagnostic_count=256 synthetic_event_count=5", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=playback_song_synthetic_adapter_adapt_total index=6 elapsed_ms=3.000 order_count=4 pattern_count=12 source_row_count=256 row_count=256 synthetic_row_count=256 synthetic_event_count=5 event_mapping_count=5 timing_change_count=1 traversal_diagnostic_count=2 traversal_guard_hit=false traversal_stop_reason=song_end", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=adapter_diagnostic_indexing index=7 elapsed_ms=0.200 event_mapping_count=5 key_off_diagnostic_group_count=0 applied_vibrato_volume_slide_event_count=0 applied_axy_volume_slide_event_count=0 applied_arpeggio_event_count=0 extra_fine_portamento_event_count=0 portamento_slide_trigger_count=0", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=adapter_event_generation index=8 elapsed_ms=0.400 synthetic_event_count=5 generated_adapter_event_count=7 voice_state_update_count=1 tone_portamento_effect_count=0 portamento_slide_effect_count=0 arpeggio_effect_count=0 vibrato_effect_count=0 note_cut_effect_count=0", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=event_sorting_grouping index=9 elapsed_ms=0.100 plan_generated=true planned_event_count=7 category_count=3 planned_song_end_frame=100 unsorted_event_count=7", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=runtime_c_mixer_adapter_event_plan_make_total index=10 elapsed_ms=3.800 order_count=4 pattern_count=12 row_count=256 planned_event_count=7 category_count=3 planned_song_end_frame=100", file=sys.stderr)
print("vtx_adapter_plan_profile schema=1 lifecycle=prewarm phase=backend_plan_configuration index=11 elapsed_ms=0.900 plan_generated=true planned_event_count=7 category_count=3 planned_song_end_frame=100", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=play phase=runtime_adapter_event_plan_ready_for_play index=1 elapsed_ms=0.010 play_adapter_plan_mode=prewarmed plan_generated=true planned_event_count=1 category_count=1 planned_song_end_frame=100", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=play phase=total index=2 elapsed_ms=4.000", file=sys.stderr)
if os.environ.get("VTX_DEBUG_REPLAY_AFTER_STOP") == "1":
    print("vtx_runtime_mixer_metrics schema=1 phase=stop_summary rendered_frame_count=48000 output_peak=0.250000 output_rms=0.050000 overrange_sample_count=0 clipping_sample_count=0 clipping_detected=false output_discontinuity_count=0 adjacent_jump_count_gt_0_25=0 adjacent_jump_count_gt_0_35=0 adjacent_jump_count_gt_0_50=0 max_output_adjacent_sample_jump=0.125000 runtime_output_gain=0.251189 runtime_headroom_policy=default_runtime_headroom_db runtime_default_headroom_db=-12.000000 runtime_gain_policy_source=default runtime_auto_headroom_enabled=false", file=sys.stderr)
    print("vtx_playback_timing schema=1 lifecycle=play phase=runtime_adapter_event_plan_ready_for_play index=1 elapsed_ms=0.010 play_adapter_plan_mode=cached_reuse plan_generated=true planned_event_count=1 category_count=1 planned_song_end_frame=100", file=sys.stderr)
    print("vtx_playback_timing schema=1 lifecycle=play phase=total index=2 elapsed_ms=1.500", file=sys.stderr)
    print("vtx_runtime_mixer_metrics schema=1 phase=stop_summary rendered_frame_count=96000 output_peak=0.300000 output_rms=0.060000 overrange_sample_count=0 clipping_sample_count=0 clipping_detected=false output_discontinuity_count=0 adjacent_jump_count_gt_0_25=0 adjacent_jump_count_gt_0_35=0 adjacent_jump_count_gt_0_50=0 max_output_adjacent_sample_jump=0.125000 runtime_output_gain=0.251189 runtime_headroom_policy=default_runtime_headroom_db runtime_default_headroom_db=-12.000000 runtime_gain_policy_source=default runtime_auto_headroom_enabled=false", file=sys.stderr)
else:
    print("vtx_runtime_mixer_metrics schema=1 phase=stop_summary rendered_frame_count=48000 output_peak=0.250000 output_rms=0.050000 overrange_sample_count=0 clipping_sample_count=0 clipping_detected=false output_discontinuity_count=0 adjacent_jump_count_gt_0_25=0 adjacent_jump_count_gt_0_35=0 adjacent_jump_count_gt_0_50=0 max_output_adjacent_sample_jump=0.125000 runtime_output_gain=0.251189 runtime_headroom_policy=default_runtime_headroom_db runtime_default_headroom_db=-12.000000 runtime_gain_policy_source=default runtime_auto_headroom_enabled=false", file=sys.stderr)
trace = os.environ.get("VTX_C_MIXER_RUNTIME_TRACE_PATH")
if trace:
    with open(trace, "w", encoding="utf-8") as handle:
        handle.write('{"runtimeAction":"fake"}\\n')
""",
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


if __name__ == "__main__":
    unittest.main()
