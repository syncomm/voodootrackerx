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

            summary = json.loads((label_dir / "xm-corpus-001.metrics.json").read_text(encoding="utf-8"))
            self.assertEqual(summary["label"], "xm-corpus-001")
            self.assertEqual(summary["playback_timing_line_count"], 6)
            self.assertEqual(summary["runtime_mixer_metrics_line_count"], 1)
            self.assertTrue(summary["runtime_trace_written"])
            self.assertEqual(summary["stdout_log"], "xm-corpus-001.stdout.txt")
            self.assertEqual(summary["metadata"]["channel_count"], 8)
            self.assertEqual(summary["metadata"]["pattern_count"], 12)
            self.assertEqual(summary["timings_ms"]["load_total"], 15.0)
            self.assertEqual(summary["timings_ms"]["playback_song_builder_build"], 8.5)
            self.assertEqual(summary["timings_ms"]["runtime_adapter_plan_total"], 3.5)
            self.assertEqual(summary["timings_ms"]["play_total"], 4.0)
            self.assertEqual(summary["runtime_metrics"]["output_peak"], 0.25)
            self.assertEqual(summary["runtime_metrics"]["output_rms"], 0.05)
            self.assertEqual(summary["runtime_metrics"]["clipping_sample_count"], 0)
            self.assertFalse(summary["runtime_metrics"]["clipping_detected"])
            run_summary = json.loads((output_dir / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(run_summary["labels"], ["xm-corpus-001"])
            self.assertTrue((output_dir / "summary.md").exists())

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
print(f"private diagnostic path {source}", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=module_metadata_loader_load index=1 elapsed_ms=1.000 module_type=XM channel_count=8 order_count=4 pattern_count=12 instrument_count=3", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=playback_song_builder_build index=2 elapsed_ms=8.500", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=runtime_adapter_event_plan_make index=3 elapsed_ms=2.500", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=runtime_adapter_event_plan_configure index=4 elapsed_ms=1.000", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=load phase=total index=5 elapsed_ms=15.000 module_type=XM channel_count=8 order_count=4 pattern_count=12 instrument_count=3", file=sys.stderr)
print("vtx_playback_timing schema=1 lifecycle=play phase=total index=1 elapsed_ms=4.000", file=sys.stderr)
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
