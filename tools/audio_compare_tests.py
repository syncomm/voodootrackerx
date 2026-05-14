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


def load_audio_compare_module():
    spec = importlib.util.spec_from_file_location("audio_compare", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


audio_compare = load_audio_compare_module()


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


if __name__ == "__main__":
    unittest.main()
