import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.audio_compare_tests import (
    synthetic_discontinuity_diagnostics,
    write_float32_wav,
    write_pcm16_wav,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY_COMPARE = REPO_ROOT / "scripts" / "audio-compare.py"
LEGACY_SMOKE = REPO_ROOT / "scripts" / "local-reference-compare-smoke.py"
LEGACY_STEMS = REPO_ROOT / "scripts" / "stem-scaling-diagnostics.py"
LEGACY_DISCONTINUITIES = REPO_ROOT / "scripts" / "analyze-audio-discontinuities.py"
UNIFIED_AUDIO_COMPARE = [sys.executable, "-m", "tools.vtx_diag", "audio_compare"]


class AudioCompareMigrationTests(unittest.TestCase):
    def run_command(self, arguments: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            arguments,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_successful_legacy_unified_parity(
        self,
        legacy_script: Path,
        mode: str,
        shared_arguments: list[str],
        artifact_paths: tuple[Path, ...] = (),
    ) -> tuple[subprocess.CompletedProcess[str], dict[Path, bytes]]:
        legacy = self.run_command([sys.executable, str(legacy_script), *shared_arguments])
        self.assertEqual(legacy.returncode, 0, legacy.stderr)
        legacy_artifacts = {path: path.read_bytes() for path in artifact_paths}

        unified = self.run_command([*UNIFIED_AUDIO_COMPARE, mode, *shared_arguments])

        self.assertEqual(unified.returncode, legacy.returncode, unified.stderr)
        self.assertEqual(unified.stdout, legacy.stdout)
        self.assertEqual(unified.stderr, legacy.stderr)
        for path, legacy_bytes in legacy_artifacts.items():
            self.assertEqual(path.read_bytes(), legacy_bytes)
        return unified, legacy_artifacts

    def test_all_unified_audio_compare_mode_help_succeeds(self):
        expected_option = {
            "compare": "--candidate",
            "smoke": "--candidate",
            "stems": "--stem",
            "discontinuities": "--wav",
        }
        for mode, option in expected_option.items():
            with self.subTest(mode=mode):
                result = self.run_command([*UNIFIED_AUDIO_COMPARE, mode, "--help"])

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertIn(option, result.stdout)

    def test_legacy_and_unified_compare_reports_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            reference = directory / "reference.wav"
            candidate = directory / "candidate.wav"
            legacy_json = directory / "legacy.json"
            legacy_markdown = directory / "legacy.md"
            unified_json = directory / "unified.json"
            unified_markdown = directory / "unified.md"
            reference_frames = [0.0, 0.0, 0.8, 0.0, -0.8, 0.0, 0.8, 0.0, 0.0, 0.0]
            candidate_frames = [0.0, 0.0, 0.0, 0.8, 0.0, -0.8, 0.0, 0.8, 0.0, 0.0]
            write_pcm16_wav(reference, sample_rate=1000, frames=reference_frames)
            write_pcm16_wav(candidate, sample_rate=1000, frames=candidate_frames)
            shared_arguments = [
                "--reference",
                str(reference),
                "--candidate",
                str(candidate),
                "--seconds",
                "1",
                "--window-ms",
                "8",
                "--top-windows",
                "1",
                "--alignment-search-frames",
                "3",
            ]

            legacy = self.run_command(
                [
                    sys.executable,
                    str(LEGACY_COMPARE),
                    *shared_arguments,
                    "--json",
                    str(legacy_json),
                    "--markdown",
                    str(legacy_markdown),
                ]
            )
            unified = self.run_command(
                [
                    *UNIFIED_AUDIO_COMPARE,
                    "compare",
                    *shared_arguments,
                    "--json",
                    str(unified_json),
                    "--markdown",
                    str(unified_markdown),
                ]
            )

            self.assertEqual(legacy.returncode, 0, legacy.stderr)
            self.assertEqual(unified.returncode, 0, unified.stderr)
            self.assertEqual(legacy.stdout, unified.stdout)
            self.assertEqual(legacy.stderr, unified.stderr)
            self.assertEqual(legacy_json.read_bytes(), unified_json.read_bytes())
            self.assertEqual(legacy_markdown.read_bytes(), unified_markdown.read_bytes())
            comparison = json.loads(unified_json.read_text(encoding="utf-8"))
            alignment = comparison["sample_comparison"]["worst_windows"][0]["local_alignment"]
            self.assertEqual(alignment["best_shift"]["candidate_shift_frames"], 1)
            self.assertEqual(comparison["tool"], "scripts/audio-compare.py")

    def test_unified_compare_supports_pcm16_and_float32_wav(self):
        cases = (
            ("pcm", write_pcm16_wav, "pcm"),
            ("float", write_float32_wav, "ieee_float"),
        )
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            for label, writer, expected_format in cases:
                with self.subTest(sample_format=expected_format):
                    reference = directory / f"{label}-reference.wav"
                    candidate = directory / f"{label}-candidate.wav"
                    report = directory / f"{label}.json"
                    writer(reference, frames=[0.0, 0.25, -0.5, 0.75])
                    writer(candidate, frames=[0.0, 0.125, -0.25, 0.375])

                    result = self.run_command(
                        [
                            *UNIFIED_AUDIO_COMPARE,
                            "compare",
                            "--reference",
                            str(reference),
                            "--candidate",
                            str(candidate),
                            "--seconds",
                            "1",
                            "--json",
                            str(report),
                        ]
                    )

                    self.assertEqual(result.returncode, 0, result.stderr)
                    comparison = json.loads(report.read_text(encoding="utf-8"))
                    self.assertEqual(comparison["reference"]["info"]["sample_format"], expected_format)
                    self.assertTrue(comparison["format"]["sample_comparison_available"])
                    self.assertAlmostEqual(
                        comparison["sample_comparison"]["gain_normalized"]["candidate_scalar_to_reference"],
                        2.0,
                        places=3,
                    )

    def test_legacy_and_unified_smoke_share_default_report_placement(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            reference = directory / "reference.wav"
            candidate = directory / "candidate.wav"
            output_directory = directory / "reports"
            expected_json = output_directory / "migration-smoke-audio-compare.json"
            expected_markdown = output_directory / "migration-smoke-audio-compare.md"
            write_pcm16_wav(reference, frames=[0.0, 0.25, -0.25, 0.0])
            write_pcm16_wav(candidate, frames=[0.0, 0.25, -0.25, 0.0])
            shared_arguments = [
                "--reference",
                str(reference),
                "--candidate",
                str(candidate),
                "--output-dir",
                str(output_directory),
                "--label",
                "migration smoke",
                "--metadata",
                "synthetic input",
                "--seconds",
                "1",
            ]

            legacy = self.run_command([sys.executable, str(LEGACY_SMOKE), *shared_arguments])
            self.assertEqual(legacy.returncode, 0, legacy.stderr)
            legacy_json = expected_json.read_bytes()
            legacy_markdown = expected_markdown.read_bytes()
            unified = self.run_command([*UNIFIED_AUDIO_COMPARE, "smoke", *shared_arguments])

            self.assertEqual(unified.returncode, 0, unified.stderr)
            self.assertEqual(legacy.stdout, unified.stdout)
            self.assertEqual(legacy.stderr, unified.stderr)
            self.assertEqual(expected_json.read_bytes(), legacy_json)
            self.assertEqual(expected_markdown.read_bytes(), legacy_markdown)
            self.assertEqual(
                {path.relative_to(directory) for path in directory.rglob("*") if path.is_file()},
                {
                    Path("reference.wav"),
                    Path("candidate.wav"),
                    Path("reports/migration-smoke-audio-compare.json"),
                    Path("reports/migration-smoke-audio-compare.md"),
                },
            )

    def test_invalid_numeric_arguments_match_legacy_failure_behavior(self):
        shared_arguments = [
            "--reference",
            "/tmp/unused-reference.wav",
            "--candidate",
            "/tmp/unused-candidate.wav",
            "--seconds",
            "0",
        ]

        legacy = self.run_command([sys.executable, str(LEGACY_COMPARE), *shared_arguments])
        unified = self.run_command([*UNIFIED_AUDIO_COMPARE, "compare", *shared_arguments])

        self.assertEqual(legacy.returncode, 2)
        self.assertEqual(unified.returncode, legacy.returncode)
        self.assertEqual(unified.stdout, legacy.stdout)
        self.assertEqual(unified.stderr, legacy.stderr)
        self.assertEqual(unified.stderr, "--seconds must be greater than zero\n")

    def test_unified_smoke_refuses_tracked_repo_output_before_writing(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            reference = directory / "reference.wav"
            candidate = directory / "candidate.wav"
            markdown = directory / "report.md"
            refused_json = REPO_ROOT / "vtx-diag-output-confinement-probe.json"
            self.addCleanup(refused_json.unlink, missing_ok=True)
            self.assertFalse(refused_json.exists())
            write_pcm16_wav(reference, frames=[0.0, 0.25, -0.25, 0.0])
            write_pcm16_wav(candidate, frames=[0.0, 0.25, -0.25, 0.0])

            result = self.run_command(
                [
                    *UNIFIED_AUDIO_COMPARE,
                    "smoke",
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--json",
                    str(refused_json),
                    "--markdown",
                    str(markdown),
                ]
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("refusing to write JSON report inside a tracked repo path", result.stderr)
            self.assertFalse(refused_json.exists())
            self.assertFalse(markdown.exists())

    def test_legacy_and_unified_stem_reports_and_summed_wavs_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            reference_a = directory / "reference-a.wav"
            reference_b = directory / "reference-b.wav"
            candidate_a = directory / "candidate-a.wav"
            candidate_b = directory / "candidate-b.wav"
            full_render = directory / "full-render.wav"
            summed = directory / "summed.wav"
            report = directory / "stems.json"
            reference_a_frames = [0.0] * 40
            reference_a_frames[8:11] = [0.75, -0.5, 0.25]
            candidate_a_frames = [0.0] * 40
            candidate_a_frames[10:13] = [0.75, -0.5, 0.25]
            reference_b_frames = [0.0625 if 20 <= frame < 32 else 0.0 for frame in range(40)]
            candidate_b_frames = list(reference_b_frames)
            full_frames = [
                sample_a + sample_b
                for sample_a, sample_b in zip(reference_a_frames, reference_b_frames)
            ]
            for path, frames in (
                (reference_a, reference_a_frames),
                (reference_b, reference_b_frames),
                (candidate_a, candidate_a_frames),
                (candidate_b, candidate_b_frames),
                (full_render, full_frames),
            ):
                write_float32_wav(path, sample_rate=1000, frames=frames)
            shared_arguments = [
                "--stem", str(reference_a),
                "--stem", str(reference_b),
                "--candidate-stem", str(candidate_a),
                "--candidate-stem", str(candidate_b),
                "--sum-output", str(summed),
                "--full-render", str(full_render),
                "--focus-window", "0.004:0.018",
                "--focus-window", "0.020:0.034",
                "--top-channels", "2",
                "--alignment-analysis-frames", "10",
                "--alignment-search-frames", "4",
                "--window-ms", "8",
                "--top-windows", "2",
                "--json", str(report),
            ]

            _, legacy_artifacts = self.assert_successful_legacy_unified_parity(
                LEGACY_STEMS,
                "stems",
                shared_arguments,
                (summed, report),
            )

            diagnostics = json.loads(legacy_artifacts[report])
            self.assertEqual(diagnostics["tool"], "scripts/stem-scaling-diagnostics.py")
            self.assertEqual(
                diagnostics["full_render_reconstruction"]["classification"],
                "reconstructs_full_render",
            )
            windows = diagnostics["matched_stem_windows"]["windows"]
            self.assertEqual(len(windows), 2)
            self.assertEqual(windows[0]["top_channels"][0]["tracker_channel"], 1)
            self.assertEqual(
                windows[0]["top_channels"][0]["ranking"]["classification"],
                "timing_or_phase_shift",
            )
            self.assertTrue(
                windows[0]["top_channels"][0]["metrics"]["local_alignment_focus"]["truncated"]
            )
            self.assertEqual(
                {path.name for path in directory.iterdir()},
                {
                    "reference-a.wav", "reference-b.wav", "candidate-a.wav",
                    "candidate-b.wav", "full-render.wav", "summed.wav", "stems.json",
                },
            )

    def test_legacy_and_unified_stem_stdout_is_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            stem = directory / "stem.wav"
            summed = directory / "summed.wav"
            write_float32_wav(stem, sample_rate=1000, frames=[0.0, 0.25, -0.25, 0.0])

            result, _ = self.assert_successful_legacy_unified_parity(
                LEGACY_STEMS,
                "stems",
                ["--stem", str(stem), "--sum-output", str(summed)],
                (summed,),
            )

            self.assertEqual(json.loads(result.stdout)["summed_mix"]["frame_count"], 4)

    def test_legacy_and_unified_discontinuity_reports_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            wav = directory / "known-jump.wav"
            diagnostics = directory / "diagnostics.json"
            json_report = directory / "discontinuities.json"
            markdown_report = directory / "discontinuities.md"
            write_pcm16_wav(wav, sample_rate=1000, frames=[0.0] * 10 + [0.9] + [0.9] * 4)
            diagnostics.write_text(
                json.dumps(synthetic_discontinuity_diagnostics("gain_pan_update", frame=10)),
                encoding="utf-8",
            )
            shared_arguments = [
                "--wav", str(wav),
                "--diagnostics-json", str(diagnostics),
                "--json", str(json_report),
                "--markdown", str(markdown_report),
                "--top", "3",
                "--threshold", "12000",
                "--correlation-frames", "2",
            ]

            _, legacy_artifacts = self.assert_successful_legacy_unified_parity(
                LEGACY_DISCONTINUITIES,
                "discontinuities",
                shared_arguments,
                (json_report, markdown_report),
            )

            analysis = json.loads(legacy_artifacts[json_report])
            self.assertEqual(analysis["tool"], "scripts/analyze-audio-discontinuities.py")
            self.assertEqual(analysis["analysis"]["threshold_jump_count"], 1)
            top_jump = analysis["top_adjacent_sample_jumps"][0]
            self.assertEqual(top_jump["frame"], 10)
            self.assertIn("gain_pan_update", top_jump["nearby_event_categories"])
            self.assertIn(b"# Audio Discontinuity Report", legacy_artifacts[markdown_report])
            self.assertEqual(
                {path.name for path in directory.iterdir()},
                {
                    "known-jump.wav", "diagnostics.json", "discontinuities.json",
                    "discontinuities.md",
                },
            )

    def test_legacy_and_unified_clean_discontinuity_stdout_is_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            wav = directory / "clean.wav"
            frames = [-0.1 + (0.2 * index / 63.0) for index in range(64)]
            write_pcm16_wav(wav, sample_rate=1000, frames=frames)

            result, _ = self.assert_successful_legacy_unified_parity(
                LEGACY_DISCONTINUITIES,
                "discontinuities",
                ["--wav", str(wav), "--top", "0", "--threshold", "12000"],
            )

            self.assertIn("- Jumps above threshold: 0", result.stdout)
            self.assertIn("- None reported.", result.stdout)

    def test_new_modes_preserve_custom_validation_failures(self):
        cases = (
            (
                LEGACY_STEMS,
                "stems",
                [
                    "--stem",
                    "/tmp/unused-stem.wav",
                    "--sum-output",
                    "/tmp/unused-sum.wav",
                    "--seconds",
                    "0",
                ],
                "--seconds must be greater than zero\n",
            ),
            (
                LEGACY_DISCONTINUITIES,
                "discontinuities",
                ["--wav", "/tmp/unused.wav", "--threshold", "-1"],
                "--threshold must be zero or greater\n",
            ),
        )
        for legacy_script, mode, arguments, expected_stderr in cases:
            with self.subTest(mode=mode):
                legacy = self.run_command([sys.executable, str(legacy_script), *arguments])
                unified = self.run_command([*UNIFIED_AUDIO_COMPARE, mode, *arguments])

                self.assertEqual(legacy.returncode, 2)
                self.assertEqual(unified.returncode, legacy.returncode)
                self.assertEqual(unified.stdout, legacy.stdout)
                self.assertEqual(unified.stderr, legacy.stderr)
                self.assertEqual(unified.stderr, expected_stderr)


if __name__ == "__main__":
    unittest.main()
