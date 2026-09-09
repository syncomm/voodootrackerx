import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.audio_compare_tests import write_float32_wav, write_pcm16_wav


REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY_COMPARE = REPO_ROOT / "scripts" / "audio-compare.py"
LEGACY_SMOKE = REPO_ROOT / "scripts" / "local-reference-compare-smoke.py"
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

    def test_unified_compare_and_smoke_help_succeed(self):
        for mode in ("compare", "smoke"):
            with self.subTest(mode=mode):
                result = self.run_command([*UNIFIED_AUDIO_COMPARE, mode, "--help"])

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertIn("--candidate", result.stdout)
                self.assertIn("--reference", result.stdout)

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


if __name__ == "__main__":
    unittest.main()
