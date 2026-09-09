import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.audio_compare_tests import (
    synthetic_comparison_json,
    synthetic_diagnostics_json,
    synthetic_focused_window_timeline_diagnostics,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY_CORRELATE = REPO_ROOT / "scripts" / "correlate-audio-comparison.py"
LEGACY_FOCUSED_WINDOW = REPO_ROOT / "scripts" / "focused-window-voice-timeline.py"
UNIFIED_REFERENCE_TRIAGE = [
    sys.executable,
    "-m",
    "tools.vtx_diag",
    "reference_triage",
]
ARCHIVE_CANDIDATES = {
    "focused-xm-channel-diagnostics.py": "FocusedXMChannelDiagnosticsTests",
    "summarize-reference-render-triage.py": "ReferenceRenderTriageTests",
}


class ReferenceTriageMigrationTests(unittest.TestCase):
    def run_command(
        self,
        arguments: list[str],
        *,
        cwd: Path = REPO_ROOT,
        environment: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            arguments,
            cwd=cwd,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_successful_legacy_unified_parity(
        self,
        legacy_script: Path,
        mode: str,
        shared_arguments: list[str],
        artifact_paths: tuple[Path, ...],
    ) -> dict[Path, bytes]:
        legacy = self.run_command([sys.executable, str(legacy_script), *shared_arguments])
        self.assertEqual(legacy.returncode, 0, legacy.stderr)
        legacy_artifacts = {path: path.read_bytes() for path in artifact_paths}

        unified = self.run_command(
            [*UNIFIED_REFERENCE_TRIAGE, mode, *shared_arguments]
        )

        self.assertEqual(unified.returncode, legacy.returncode, unified.stderr)
        self.assertEqual(unified.stdout, legacy.stdout)
        self.assertEqual(unified.stderr, legacy.stderr)
        for path, legacy_bytes in legacy_artifacts.items():
            self.assertEqual(path.read_bytes(), legacy_bytes)
        return legacy_artifacts

    def test_unified_mode_help_succeeds(self):
        expected_option = {
            "correlate": "--comparison-json",
            "focused-window": "--diagnostics-json",
        }
        for mode, option in expected_option.items():
            with self.subTest(mode=mode):
                result = self.run_command(
                    [*UNIFIED_REFERENCE_TRIAGE, mode, "--help"]
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                self.assertIn(option, result.stdout)

    def test_legacy_and_unified_correlation_reports_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            comparison = directory / "comparison.json"
            diagnostics = directory / "diagnostics.json"
            report = directory / "reports" / "correlation.md"
            comparison.write_text(
                json.dumps(synthetic_comparison_json()),
                encoding="utf-8",
            )
            diagnostics.write_text(
                json.dumps(synthetic_diagnostics_json()),
                encoding="utf-8",
            )
            shared_arguments = [
                "--comparison-json",
                str(comparison),
                "--diagnostics-json",
                str(diagnostics),
                "--output-markdown",
                str(report),
                "--label",
                "synthetic migration parity",
                "--metadata",
                "public-safe synthetic inputs",
                "--focus-sample",
                "7:2",
                "--focus-channels",
                "1",
            ]

            artifacts = self.assert_successful_legacy_unified_parity(
                LEGACY_CORRELATE,
                "correlate",
                shared_arguments,
                (report,),
            )

            markdown = artifacts[report].decode("utf-8")
            self.assertIn("Window 1: 0.100000-0.150000 s", markdown)
            self.assertIn("order 0 pattern 2 row 4", markdown)
            self.assertIn("- Label: synthetic migration parity", markdown)
            self.assertEqual(
                {path.relative_to(directory) for path in directory.rglob("*") if path.is_file()},
                {
                    Path("comparison.json"),
                    Path("diagnostics.json"),
                    Path("reports/correlation.md"),
                },
            )

    def test_legacy_and_unified_focused_window_reports_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            diagnostics = directory / "diagnostics.json"
            diagnostics.write_text(
                json.dumps(synthetic_focused_window_timeline_diagnostics()),
                encoding="utf-8",
            )

            for output_format in ("json", "markdown"):
                with self.subTest(output_format=output_format):
                    report = directory / "reports" / f"focused-window.{output_format}"
                    shared_arguments = [
                        "--diagnostics-json",
                        str(diagnostics),
                        "--window",
                        "0.10:0.20",
                        "--window",
                        "0.20:0.25",
                        "--label",
                        "synthetic migration parity",
                        "--format",
                        output_format,
                        "--output",
                        str(report),
                    ]

                    artifacts = self.assert_successful_legacy_unified_parity(
                        LEGACY_FOCUSED_WINDOW,
                        "focused-window",
                        shared_arguments,
                        (report,),
                    )

                    if output_format == "json":
                        summary = json.loads(artifacts[report])
                        self.assertEqual(
                            summary["tool"],
                            "scripts/focused-window-voice-timeline.py",
                        )
                        self.assertEqual(summary["window_count"], 2)
                        self.assertEqual(
                            [
                                summary["windows"][0]["start_frame"],
                                summary["windows"][0]["end_frame"],
                            ],
                            [100, 200],
                        )
                        self.assertEqual(
                            [
                                voice["event_index"]
                                for voice in summary["windows"][0]["active_voices"]
                            ],
                            [0, 2, 1],
                        )
                    else:
                        self.assertIn(
                            b"# Focused Window Voice Timeline: synthetic migration parity",
                            artifacts[report],
                        )

            self.assertEqual(
                {path.relative_to(directory) for path in directory.rglob("*") if path.is_file()},
                {
                    Path("diagnostics.json"),
                    Path("reports/focused-window.json"),
                    Path("reports/focused-window.markdown"),
                },
            )

    def test_invalid_focused_window_matches_legacy_failure(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            diagnostics = directory / "diagnostics.json"
            report = directory / "should-not-exist.md"
            diagnostics.write_text(
                json.dumps(synthetic_focused_window_timeline_diagnostics()),
                encoding="utf-8",
            )
            shared_arguments = [
                "--diagnostics-json",
                str(diagnostics),
                "--window",
                "0.20:0.10",
                "--output",
                str(report),
            ]

            legacy = self.run_command(
                [sys.executable, str(LEGACY_FOCUSED_WINDOW), *shared_arguments]
            )
            unified = self.run_command(
                [*UNIFIED_REFERENCE_TRIAGE, "focused-window", *shared_arguments]
            )

            self.assertEqual(legacy.returncode, 1)
            self.assertEqual(unified.returncode, legacy.returncode)
            self.assertEqual(unified.stdout, legacy.stdout)
            self.assertEqual(unified.stderr, legacy.stderr)
            self.assertIn("window end must be greater than start", unified.stderr)
            self.assertFalse(report.exists())

    def test_missing_correlation_input_matches_legacy_failure(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            diagnostics = directory / "diagnostics.json"
            report = directory / "should-not-exist.md"
            diagnostics.write_text(
                json.dumps(synthetic_diagnostics_json()),
                encoding="utf-8",
            )
            shared_arguments = [
                "--comparison-json",
                str(directory / "missing-comparison.json"),
                "--diagnostics-json",
                str(diagnostics),
                "--output-markdown",
                str(report),
            ]

            legacy = self.run_command(
                [sys.executable, str(LEGACY_CORRELATE), *shared_arguments]
            )
            unified = self.run_command(
                [*UNIFIED_REFERENCE_TRIAGE, "correlate", *shared_arguments]
            )

            self.assertEqual(legacy.returncode, 1)
            self.assertEqual(unified.returncode, legacy.returncode)
            self.assertEqual(unified.stdout, legacy.stdout)
            self.assertEqual(unified.stderr, legacy.stderr)
            self.assertIn("missing comparison JSON", unified.stderr)
            self.assertFalse(report.exists())

    def test_package_imports_require_no_local_or_private_inputs(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            environment = os.environ.copy()
            environment["PYTHONPATH"] = str(REPO_ROOT)
            result = self.run_command(
                [
                    sys.executable,
                    "-B",
                    "-c",
                    (
                        "import tools.vtx_diag.reference_triage_correlate; "
                        "import tools.vtx_diag.reference_triage_focused_window"
                    ),
                ],
                cwd=directory,
                environment=environment,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")
            self.assertEqual(list(directory.iterdir()), [])

    def test_archive_candidate_classification_has_repository_evidence(self):
        test_source = (REPO_ROOT / "tools" / "audio_compare_tests.py").read_text(
            encoding="utf-8"
        )
        inventory = (REPO_ROOT / "docs" / "diagnostic-tools.md").read_text(
            encoding="utf-8"
        )
        archived_history = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (REPO_ROOT / "docs" / "reports").glob("*.md")
        )
        active_documentation = []
        for path in REPO_ROOT.rglob("*.md"):
            relative_path = path.relative_to(REPO_ROOT)
            if relative_path.parts[:2] == ("docs", "reports"):
                continue
            if relative_path == Path("docs/diagnostic-tools.md"):
                continue
            if any(part in {".git", "build"} for part in relative_path.parts):
                continue
            active_documentation.append(path.read_text(encoding="utf-8"))
        active_documentation_text = "\n".join(active_documentation)

        for script_name, test_class in ARCHIVE_CANDIDATES.items():
            with self.subTest(script_name=script_name):
                self.assertIn(script_name, test_source)
                self.assertIn(test_class, test_source)
                self.assertIn(script_name, inventory)
                self.assertIn(script_name, archived_history)
                self.assertNotIn(script_name, active_documentation_text)
        self.assertIn(
            "active automated tests; archived workflow references only",
            inventory,
        )
        self.assertIn(
            "Candidate for archive after a dedicated removal/reference scan",
            inventory,
        )


if __name__ == "__main__":
    unittest.main()
