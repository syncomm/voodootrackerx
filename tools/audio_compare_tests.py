import importlib.util
import json
import math
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "audio-compare.py"
SMOKE_SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "local-reference-compare-smoke.py"
CORRELATION_SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "correlate-audio-comparison.py"


def load_audio_compare_module():
    spec = importlib.util.spec_from_file_location("audio_compare", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


audio_compare = load_audio_compare_module()


def synthetic_comparison_json(start_frame=100, end_frame=150):
    return {
        "schema_version": 1,
        "tool": "scripts/audio-compare.py",
        "candidate": {"info": {"sample_rate": 1000}},
        "reference": {"info": {"sample_rate": 1000}},
        "sample_comparison": {
            "worst_windows": [
                {
                    "start_frame": start_frame,
                    "end_frame": end_frame,
                    "start_seconds": start_frame / 1000,
                    "end_seconds": end_frame / 1000,
                    "rms_difference": 0.25,
                    "max_abs_sample_difference": 0.75,
                }
            ]
        },
    }


def synthetic_diagnostics_json(event_start=110, event_end=145):
    source = {"order": 0, "pattern": 2, "row": 4}
    return {
        "schema_version": 1,
        "tool": "vtx_render_bounded_xm",
        "render": {
            "sample_rate": 1000,
            "rendered_frame_count": 400,
            "requested_start_order_index": 0,
            "requested_order_count": 1,
            "initial_speed": 6,
            "initial_bpm": 125,
        },
        "row_timing": [
            {
                "source": source,
                "synthetic_row": 4,
                "row_start_frame": 100,
                "row_end_frame": 160,
                "row_duration_frames": 60,
                "effective_speed": 6,
                "effective_bpm": 125,
            }
        ],
        "timing_changes": [
            {
                "source": source,
                "channel_index": 1,
                "effect_type": 15,
                "effect_param": 3,
                "row_start_frame": 100,
                "applies_to_synthetic_row_after": 5,
                "kind": "speed",
                "applied": True,
                "speed_before": 6,
                "bpm_before": 125,
                "speed_after": 3,
                "bpm_after": 125,
            }
        ],
        "events": [
            {
                "source": source,
                "channel_index": 1,
                "note": 49,
                "instrument_index": 7,
                "sample_index": 2,
                "synthetic_row": 4,
                "synthetic_tick": 0,
                "event_index": 0,
                "scheduled_start_frame": event_start,
                "estimated_end_frame": event_end,
                "estimated_duration_frames": event_end - event_start,
                "sample_frame_count": 35,
                "gain": 0.5,
                "pan": -0.25,
                "loop_mode": "forward",
                "volume_column": {
                    "raw_value": 48,
                    "command": {"name": "setVolume", "value": 32},
                    "classification": "supported",
                    "applied": True,
                    "ignored_as_empty_or_no_op": False,
                    "deferred": False,
                },
                "volume_envelope": {
                    "status": "mapped",
                    "source_point_count": 2,
                    "mapped_point_count": 2,
                    "has_deferred_sustain": False,
                    "has_deferred_loop": True,
                    "has_deferred_fadeout": False,
                },
                "pitch": {
                    "playback_step": 1.25,
                    "sample_base_sample_rate": 8363,
                    "sample_relative_note": 0,
                    "sample_finetune": 0,
                    "frequency_table_status": "linear_applied",
                },
            }
        ],
    }


def write_pcm16_wav(path, sample_rate=8000, channels=1, frames=None):
    frames = frames if frames is not None else sine_frames(sample_rate, channels)
    pcm = bytearray()
    for frame in frames:
        values = frame if isinstance(frame, tuple) else (frame,)
        if len(values) != channels:
            raise ValueError("frame channel count mismatch")
        for sample in values:
            clamped = max(-1.0, min(1.0, sample))
            value = -32768 if clamped <= -1.0 else int(clamped * 32767)
            pcm.extend(struct.pack("<h", value))

    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(bytes(pcm))


def sine_frames(sample_rate=8000, channels=1, seconds=0.25, amplitude=0.5):
    frame_count = int(sample_rate * seconds)
    frames = []
    for frame in range(frame_count):
        sample = math.sin(2.0 * math.pi * 440.0 * frame / sample_rate) * amplitude
        frames.append(tuple(sample for _ in range(channels)) if channels > 1 else sample)
    return frames


class AudioCompareTests(unittest.TestCase):
    def test_identical_stereo_files_report_zero_difference(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            frames = sine_frames(channels=2)
            write_pcm16_wav(reference, channels=2, frames=frames)
            write_pcm16_wav(candidate, channels=2, frames=frames)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            sample_comparison = comparison["sample_comparison"]

            self.assertTrue(comparison["format"]["sample_comparison_available"])
            self.assertEqual(sample_comparison["diff"]["overall_rms_difference"], 0.0)
            self.assertEqual(sample_comparison["diff"]["max_abs_sample_difference"], 0.0)
            self.assertEqual(sample_comparison["diff"]["per_channel_rms_difference"], [0.0, 0.0])
            self.assertEqual(sample_comparison["normalized_correlation"], 1.0)
            self.assertIsNone(sample_comparison["first_difference_seconds"])

    def test_amplitude_mismatch_reports_rms_and_max_difference(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, frames=sine_frames(amplitude=0.5))
            write_pcm16_wav(candidate, frames=sine_frames(amplitude=0.25))

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            diff = comparison["sample_comparison"]["diff"]

            self.assertGreater(diff["overall_rms_difference"], 0.17)
            self.assertGreater(diff["max_abs_sample_difference"], 0.24)
            self.assertGreater(diff["normalized_rms_difference"], 0.49)

    def test_localized_mismatch_appears_in_worst_window_output(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            reference_frames = [0.0] * 100
            candidate_frames = [0.0] * 100
            for index in range(50, 60):
                candidate_frames[index] = 0.8
            write_pcm16_wav(reference, sample_rate=1000, frames=reference_frames)
            write_pcm16_wav(candidate, sample_rate=1000, frames=candidate_frames)

            comparison = audio_compare.build_comparison(
                reference,
                candidate,
                seconds=1.0,
                window_ms=10.0,
                top_windows=3,
            )
            windows = comparison["sample_comparison"]["worst_windows"]

            self.assertEqual(windows[0]["start_frame"], 50)
            self.assertEqual(windows[0]["end_frame"], 60)
            self.assertGreater(windows[0]["rms_difference"], 0.79)

    def test_left_right_stereo_balance_mismatch_is_reported(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            reference_frames = [(0.4, 0.4)] * 32
            candidate_frames = [(0.8, 0.1)] * 32
            write_pcm16_wav(reference, channels=2, frames=reference_frames)
            write_pcm16_wav(candidate, channels=2, frames=candidate_frames)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            balance = comparison["candidate"]["stats"]["stereo_balance"]

            self.assertGreater(balance["left_minus_right_rms"], 0.69)
            self.assertGreater(balance["left_right_energy_difference"], 0.62)

    def test_duration_and_frame_count_mismatch_are_reported(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, sample_rate=1000, frames=[0.0] * 100)
            write_pcm16_wav(candidate, sample_rate=1000, frames=[0.0] * 125)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)

            self.assertEqual(comparison["format"]["frame_count_delta"], 25)
            self.assertEqual(comparison["format"]["analyzed_frame_count_delta"], 25)
            self.assertAlmostEqual(comparison["format"]["duration_delta_seconds"], 0.025)

    def test_sample_rate_mismatch_is_reported_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, sample_rate=8000)
            write_pcm16_wav(candidate, sample_rate=11025)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            report = audio_compare.build_markdown_report(comparison)

            self.assertFalse(comparison["format"]["sample_rate_matches"])
            self.assertIsNone(comparison["sample_comparison"])
            self.assertIn("Sample rate: mismatch (reference 8000 Hz, candidate 11025 Hz)", report)
            self.assertIn("Skipped because sample rate or channel count differs.", report)

    def test_channel_count_mismatch_is_reported_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, channels=1)
            write_pcm16_wav(candidate, channels=2)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            report = audio_compare.build_markdown_report(comparison)

            self.assertFalse(comparison["format"]["channel_count_matches"])
            self.assertIsNone(comparison["sample_comparison"])
            self.assertIn("Channels: mismatch (reference 1, candidate 2)", report)

    def test_clipping_count_is_detected(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, frames=[0.0, 1.0, -1.0, 0.5])
            write_pcm16_wav(candidate, frames=[0.0, 0.5, 0.25, 0.125])

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)

            self.assertEqual(comparison["reference"]["stats"]["clipping_count"], 2)
            self.assertEqual(comparison["candidate"]["stats"]["clipping_count"], 0)

    def test_silence_and_near_silence_are_reported(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, frames=[0.0, 0.0, 0.0, 0.0])
            write_pcm16_wav(candidate, frames=[0.0, 0.00001, 0.25, -0.25])

            comparison = audio_compare.build_comparison(
                reference,
                candidate,
                seconds=1.0,
                near_silence_threshold=0.00002,
            )

            self.assertEqual(comparison["reference"]["stats"]["near_silence_count"], 4)
            self.assertEqual(comparison["reference"]["stats"]["near_silence_ratio"], 1.0)
            self.assertEqual(comparison["candidate"]["stats"]["near_silence_count"], 2)

    def test_json_output_is_valid_deterministic_and_sanitizes_paths(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            reference = tmpdir_path / "reference.wav"
            candidate = tmpdir_path / "candidate.wav"
            json_report = tmpdir_path / "report.json"
            frames = sine_frames(seconds=0.05)
            write_pcm16_wav(reference, frames=frames)
            write_pcm16_wav(candidate, frames=frames)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--seconds",
                    "1",
                    "--json",
                    str(json_report),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            raw_json = json_report.read_text(encoding="utf-8")
            parsed = json.loads(raw_json)
            self.assertEqual(parsed["schema_version"], 1)
            self.assertEqual(parsed["reference"]["info"]["path_name"], "reference.wav")
            self.assertEqual(parsed["candidate"]["info"]["path_name"], "candidate.wav")
            self.assertNotIn(tmpdir, raw_json)
            self.assertEqual(raw_json, json.dumps(parsed, indent=2, sort_keys=True) + "\n")

    def test_markdown_cli_output_is_understandable(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, frames=[0.0, 0.0, 0.0, 0.0])
            write_pcm16_wav(candidate, frames=[0.0, 0.5, 0.0, 0.0])

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--seconds",
                    "1",
                    "--window-ms",
                    "1",
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("# Audio Comparison Report", result.stdout)
            self.assertIn("## Worst Mismatch Windows", result.stdout)
            self.assertIn("Diagnostic metrics only", result.stdout)

    def test_missing_file_cli_returns_clear_error(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "missing-reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(candidate)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("audio-compare:", result.stderr)
            self.assertIn("missing-reference.wav", result.stderr)

    def test_invalid_file_cli_returns_clear_error(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            reference.write_text("not a wav", encoding="utf-8")
            write_pcm16_wav(candidate)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("audio-compare:", result.stderr)

    def test_local_reference_smoke_wrapper_writes_requested_reports(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            reference = tmpdir_path / "tiny-reference.wav"
            candidate = tmpdir_path / "tiny-candidate.wav"
            json_report = tmpdir_path / "tiny-audio-compare.json"
            markdown_report = tmpdir_path / "tiny-audio-compare.md"
            frames = sine_frames(seconds=0.05)
            write_pcm16_wav(reference, frames=frames)
            write_pcm16_wav(candidate, frames=frames)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SMOKE_SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--json",
                    str(json_report),
                    "--markdown",
                    str(markdown_report),
                    "--label",
                    "tiny smoke",
                    "--metadata",
                    "order 0 row 0",
                    "--seconds",
                    "1",
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json_report.exists())
            self.assertTrue(markdown_report.exists())
            parsed = json.loads(json_report.read_text(encoding="utf-8"))
            self.assertEqual(parsed["tool"], "scripts/audio-compare.py")
            self.assertIn("# Audio Comparison Report", markdown_report.read_text(encoding="utf-8"))
            self.assertIn("Delegating metric generation to scripts/audio-compare.py", result.stdout)
            self.assertIn("local artifacts and must not be committed", result.stdout)

    def test_local_reference_smoke_wrapper_default_outputs_are_under_tmp(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            reference = tmpdir_path / "reference.wav"
            candidate = tmpdir_path / "candidate.wav"
            output_dir = Path("/tmp/vtx-local-reference-comparison")
            expected_json = output_dir / "unittest-default-audio-compare.json"
            expected_markdown = output_dir / "unittest-default-audio-compare.md"
            expected_json.unlink(missing_ok=True)
            expected_markdown.unlink(missing_ok=True)
            write_pcm16_wav(reference)
            write_pcm16_wav(candidate)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SMOKE_SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--label",
                    "unittest default",
                    "--seconds",
                    "1",
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(expected_json.exists())
            self.assertTrue(expected_markdown.exists())
            self.assertIn(str(expected_json), result.stdout)
            self.assertIn(str(expected_markdown), result.stdout)
            expected_json.unlink(missing_ok=True)
            expected_markdown.unlink(missing_ok=True)

    def test_local_reference_smoke_wrapper_missing_candidate_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "missing-candidate.wav"
            write_pcm16_wav(reference)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SMOKE_SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--json",
                    str(Path(tmpdir) / "report.json"),
                    "--markdown",
                    str(Path(tmpdir) / "report.md"),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing candidate WAV", result.stderr)
            self.assertIn("missing-candidate.wav", result.stderr)

    def test_local_reference_smoke_wrapper_missing_reference_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "missing-reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(candidate)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SMOKE_SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--json",
                    str(Path(tmpdir) / "report.json"),
                    "--markdown",
                    str(Path(tmpdir) / "report.md"),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing reference WAV", result.stderr)
            self.assertIn("missing-reference.wav", result.stderr)


class AudioCorrelationTests(unittest.TestCase):
    def test_correlation_maps_synthetic_window_to_overlapping_adapter_event(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("Window 1: 0.100000-0.150000 s", markdown)
            self.assertIn("order 0 pattern 2 row 4", markdown)
            self.assertIn("| order 0 pattern 2 row 4 | 1 | 49 | 7/2 | 110-145 |", markdown)

    def test_correlation_includes_rich_adapter_diagnostic_fields(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, label="synthetic rich fields", metadata="order 0 rows 4-5")
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("- Label: synthetic rich fields", markdown)
            self.assertIn("- Metadata: order 0 rows 4-5", markdown)
            self.assertIn("1.25000000", markdown)
            self.assertIn("0.50000000/-0.25000000", markdown)
            self.assertIn("raw 48 setVolume(32) / supported", markdown)
            self.assertIn("speed F03 6/125->3/125", markdown)
            self.assertIn("mapped 2/2; deferred loop", markdown)
            self.assertIn("| forward |", markdown)

    def test_correlation_reports_no_overlapping_events_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(
                tmpdir,
                diagnostics=synthetic_diagnostics_json(event_start=10, event_end=20),
            )
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("No candidate event frame range overlapped this mismatch window", markdown)
            self.assertIn("#### Recent Preceding Candidate Events", markdown)
            self.assertIn("| order 0 pattern 2 row 4 | 1 | 49 | 7/2 | 10-20 |", markdown)

    def test_correlation_missing_optional_diagnostics_fields_degrades_gracefully(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics={})
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("- Candidate diagnostic events: 0", markdown)
            self.assertIn("No row timing diagnostics overlap this mismatch window.", markdown)
            self.assertIn("No candidate event frame range overlapped this mismatch window", markdown)

    def test_correlation_missing_comparison_json_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            diagnostics_path = tmpdir_path / "diagnostics.json"
            output_path = tmpdir_path / "correlation.md"
            diagnostics_path.write_text(json.dumps(synthetic_diagnostics_json()), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(CORRELATION_SCRIPT_PATH),
                    "--comparison-json",
                    str(tmpdir_path / "missing-comparison.json"),
                    "--diagnostics-json",
                    str(diagnostics_path),
                    "--output-markdown",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing comparison JSON", result.stderr)

    def test_correlation_missing_diagnostics_json_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            comparison_path = tmpdir_path / "comparison.json"
            output_path = tmpdir_path / "correlation.md"
            comparison_path.write_text(json.dumps(synthetic_comparison_json()), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(CORRELATION_SCRIPT_PATH),
                    "--comparison-json",
                    str(comparison_path),
                    "--diagnostics-json",
                    str(tmpdir_path / "missing-diagnostics.json"),
                    "--output-markdown",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing diagnostics JSON", result.stderr)

    def test_correlation_malformed_json_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            comparison_path = tmpdir_path / "comparison.json"
            diagnostics_path = tmpdir_path / "diagnostics.json"
            output_path = tmpdir_path / "correlation.md"
            comparison_path.write_text("{not valid json", encoding="utf-8")
            diagnostics_path.write_text(json.dumps(synthetic_diagnostics_json()), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(CORRELATION_SCRIPT_PATH),
                    "--comparison-json",
                    str(comparison_path),
                    "--diagnostics-json",
                    str(diagnostics_path),
                    "--output-markdown",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("malformed JSON in comparison JSON", result.stderr)

    def test_correlation_missing_expected_comparison_fields_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            comparison_path = tmpdir_path / "comparison.json"
            diagnostics_path = tmpdir_path / "diagnostics.json"
            output_path = tmpdir_path / "correlation.md"
            comparison_path.write_text(json.dumps({"sample_comparison": None}), encoding="utf-8")
            diagnostics_path.write_text(json.dumps(synthetic_diagnostics_json()), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(CORRELATION_SCRIPT_PATH),
                    "--comparison-json",
                    str(comparison_path),
                    "--diagnostics-json",
                    str(diagnostics_path),
                    "--output-markdown",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("sample_comparison.worst_windows", result.stderr)

    def run_correlation(self, tmpdir, comparison=None, diagnostics=None, label=None, metadata=None):
        tmpdir_path = Path(tmpdir)
        comparison_path = tmpdir_path / "comparison.json"
        diagnostics_path = tmpdir_path / "diagnostics.json"
        output_path = tmpdir_path / "correlation.md"
        comparison_payload = synthetic_comparison_json() if comparison is None else comparison
        diagnostics_payload = synthetic_diagnostics_json() if diagnostics is None else diagnostics
        comparison_path.write_text(json.dumps(comparison_payload), encoding="utf-8")
        diagnostics_path.write_text(json.dumps(diagnostics_payload), encoding="utf-8")

        command = [
            sys.executable,
            str(CORRELATION_SCRIPT_PATH),
            "--comparison-json",
            str(comparison_path),
            "--diagnostics-json",
            str(diagnostics_path),
            "--output-markdown",
            str(output_path),
        ]
        if label is not None:
            command.extend(["--label", label])
        if metadata is not None:
            command.extend(["--metadata", metadata])

        result = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(output_path.exists())
        self.assertTrue(output_path.is_relative_to(tmpdir_path))
        self.assertIn("Correlation report:", result.stdout)
        return output_path


if __name__ == "__main__":
    unittest.main()
