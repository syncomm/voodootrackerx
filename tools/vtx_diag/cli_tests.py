import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from .cli import COMMAND_REGISTRY, ExitCode, main


EXPECTED_COMMANDS = (
    "audio_compare",
    "reference_triage",
    "effect_coverage",
    "residual_scan",
    "runtime_trace",
    "corpus_map",
)
REPO_ROOT = Path(__file__).resolve().parents[2]


class UnifiedDiagnosticCLITests(unittest.TestCase):
    def invoke(self, *arguments: str) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = main(arguments)
        return exit_code, stdout.getvalue(), stderr.getvalue()

    def test_top_level_help_lists_exact_command_registry(self):
        with mock.patch.dict(os.environ, {"COLUMNS": "40"}):
            narrow_result = self.invoke("--help")
        with mock.patch.dict(os.environ, {"COLUMNS": "120"}):
            wide_result = self.invoke("--help")
        exit_code, stdout, stderr = narrow_result

        self.assertEqual(narrow_result, wide_result)
        self.assertEqual(exit_code, ExitCode.SUCCESS)
        self.assertEqual(stderr, "")
        self.assertEqual(tuple(COMMAND_REGISTRY), EXPECTED_COMMANDS)
        for command_name in EXPECTED_COMMANDS:
            self.assertIn(f"    {command_name}", stdout)

    def test_module_entrypoint_help_succeeds(self):
        result = subprocess.run(
            [sys.executable, "-m", "tools.vtx_diag", "--help"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, ExitCode.SUCCESS, result.stderr)
        self.assertEqual(result.stderr, "")
        for command_name in EXPECTED_COMMANDS:
            self.assertIn(f"    {command_name}", result.stdout)

    def test_corpus_map_help_lists_only_update_mode(self):
        exit_code, stdout, stderr = self.invoke("corpus_map", "--help")

        self.assertEqual(exit_code, ExitCode.SUCCESS)
        self.assertEqual(stderr, "")
        self.assertIn("    update", stdout)
        self.assertNotIn("runtime-metrics", stdout)

    def test_corpus_map_requires_a_mode(self):
        exit_code, stdout, stderr = self.invoke("corpus_map")

        self.assertEqual(exit_code, ExitCode.USAGE_ERROR)
        self.assertEqual(stdout, "")
        self.assertIn("the following arguments are required: MODE", stderr)

    def test_audio_compare_help_lists_all_migrated_modes(self):
        exit_code, stdout, stderr = self.invoke("audio_compare", "--help")

        self.assertEqual(exit_code, ExitCode.SUCCESS)
        self.assertEqual(stderr, "")
        for mode in ("compare", "smoke", "stems", "discontinuities"):
            self.assertIn(f"    {mode}", stdout)

    def test_audio_compare_requires_a_mode(self):
        exit_code, stdout, stderr = self.invoke("audio_compare")

        self.assertEqual(exit_code, ExitCode.USAGE_ERROR)
        self.assertEqual(stdout, "")
        self.assertIn("the following arguments are required: MODE", stderr)

    def test_reference_triage_help_lists_only_migrated_modes(self):
        exit_code, stdout, stderr = self.invoke("reference_triage", "--help")

        self.assertEqual(exit_code, ExitCode.SUCCESS)
        self.assertEqual(stderr, "")
        for mode in ("correlate", "focused-window"):
            self.assertIn(f"    {mode}", stdout)
        self.assertNotIn("focused-channel", stdout)
        self.assertNotIn("summarize", stdout)

    def test_reference_triage_requires_a_mode(self):
        exit_code, stdout, stderr = self.invoke("reference_triage")

        self.assertEqual(exit_code, ExitCode.USAGE_ERROR)
        self.assertEqual(stdout, "")
        self.assertIn("the following arguments are required: MODE", stderr)

    def test_effect_coverage_help_lists_summarize_mode(self):
        exit_code, stdout, stderr = self.invoke("effect_coverage", "--help")

        self.assertEqual(exit_code, ExitCode.SUCCESS)
        self.assertEqual(stderr, "")
        self.assertIn("    summarize", stdout)

    def test_effect_coverage_requires_a_mode(self):
        exit_code, stdout, stderr = self.invoke("effect_coverage")

        self.assertEqual(exit_code, ExitCode.USAGE_ERROR)
        self.assertEqual(stdout, "")
        self.assertIn("the following arguments are required: MODE", stderr)

    def test_residual_scan_help_lists_summarize_mode(self):
        exit_code, stdout, stderr = self.invoke("residual_scan", "--help")

        self.assertEqual(exit_code, ExitCode.SUCCESS)
        self.assertEqual(stderr, "")
        self.assertIn("    summarize", stdout)

    def test_residual_scan_requires_a_mode(self):
        exit_code, stdout, stderr = self.invoke("residual_scan")

        self.assertEqual(exit_code, ExitCode.USAGE_ERROR)
        self.assertEqual(stdout, "")
        self.assertIn("the following arguments are required: MODE", stderr)

    def test_runtime_trace_help_lists_only_migrated_modes(self):
        exit_code, stdout, stderr = self.invoke("runtime_trace", "--help")

        self.assertEqual(exit_code, ExitCode.SUCCESS)
        self.assertEqual(stderr, "")
        for mode in ("summarize", "correlate-window"):
            self.assertIn(f"    {mode}", stdout)
        self.assertNotIn("corpus-metrics", stdout)

    def test_runtime_trace_requires_a_mode(self):
        exit_code, stdout, stderr = self.invoke("runtime_trace")

        self.assertEqual(exit_code, ExitCode.USAGE_ERROR)
        self.assertEqual(stdout, "")
        self.assertIn("the following arguments are required: MODE", stderr)

    def test_unknown_command_handling_is_deterministic(self):
        with mock.patch.dict(os.environ, {"COLUMNS": "40"}):
            first = self.invoke("unknown_command")
        with mock.patch.dict(os.environ, {"COLUMNS": "120"}):
            second = self.invoke("unknown_command")

        self.assertEqual(first, second)
        self.assertEqual(first[0], ExitCode.USAGE_ERROR)
        self.assertEqual(first[1], "")
        self.assertIn("invalid choice: 'unknown_command'", first[2])

    def test_import_does_not_require_local_inputs_or_emit_output(self):
        with tempfile.TemporaryDirectory() as directory:
            environment = os.environ.copy()
            environment["PYTHONPATH"] = str(REPO_ROOT)
            result = subprocess.run(
                [sys.executable, "-B", "-c", "import tools.vtx_diag"],
                cwd=directory,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, ExitCode.SUCCESS, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")
            self.assertEqual(list(Path(directory).iterdir()), [])

if __name__ == "__main__":
    unittest.main()
