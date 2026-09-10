import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.vtx_diag import residual_scan
from tools.vtx_diag.cli import main as unified_main


REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY_RESIDUAL_SCAN = REPO_ROOT / "scripts" / "summarize-xm-residual-effect-scan.py"
UNIFIED_RESIDUAL_SCAN = [
    sys.executable,
    "-m",
    "tools.vtx_diag",
    "residual_scan",
    "summarize",
]
EXPECTED_RECOMMENDATION = " ".join(
    (
        residual_scan.BACKEND_FREEZE_NEXT_PR_RECOMMENDATION,
        residual_scan.BACKEND_FREEZE_PRIORITIZATION_NOTE,
        residual_scan.BACKEND_FREEZE_PROMOTION_NOTE,
    )
)


def _fixed(value: str, length: int) -> bytes:
    return value.encode("ascii")[:length].ljust(length, b"\x00")


def _put16(data: bytearray, value: int) -> None:
    data.extend(int(value).to_bytes(2, "little"))


def _put32(data: bytearray, value: int) -> None:
    data.extend(int(value).to_bytes(4, "little"))


def _synthetic_xm(
    rows: list[tuple[int, int, int, int, int]],
    *,
    title: str = "synthetic",
    frequency_table: str = "linear",
) -> bytes:
    payload = b"".join(bytes(cell) for cell in rows)
    data = bytearray(b"Extended Module: ")
    data.extend(_fixed(title, 20))
    data.append(0x1A)
    data.extend(_fixed("synthetic-test", 20))
    _put16(data, 0x0104)
    _put32(data, 276)
    for value in (1, 0, 1, 1, 0, 1 if frequency_table == "linear" else 0, 6, 125):
        _put16(data, value)
    data.extend(bytes(256))
    _put32(data, 9)
    data.append(0)
    _put16(data, len(rows))
    _put16(data, len(payload))
    data.extend(payload)
    return bytes(data)


def _write_map(directory: Path, entries: list[dict[str, str]]) -> Path:
    path = directory / "maintainer-local-label-map.json"
    path.write_text(json.dumps({"entries": entries}), encoding="utf-8")
    return path


def _load_legacy_module():
    spec = importlib.util.spec_from_file_location("legacy_residual_scan", LEGACY_RESIDUAL_SCAN)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    finally:
        sys.modules.pop(spec.name, None)
    return module


class ResidualScanMigrationTests(unittest.TestCase):
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

    def invoke(self, callback) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = callback()
        return exit_code, stdout.getvalue(), stderr.getvalue()

    def make_mixed_corpus(self, directory: Path) -> Path:
        modules = (
            (
                "xm-corpus-010",
                "private-volume-source.xm",
                [(0, 0, 0xB3, 0, 0), (0, 0, 0, 0x07, 0)],
            ),
            (
                "xm-corpus-005",
                "private-implemented-source.xm",
                [(48, 0, 0, 0x0C, 0x20)],
            ),
            (
                "xm-corpus-002",
                "private-memory-source.xm",
                [(0, 0, 0, 0x0A, 0), (0, 0, 0xA2, 0, 0)],
            ),
        )
        entries = []
        for label, filename, rows in modules:
            module_path = directory / filename
            module_path.write_bytes(_synthetic_xm(rows, title="UNREDACTED PRIVATE TITLE"))
            entries.append(
                {
                    "stable_anonymized_label": label,
                    "path": str(module_path),
                    "frequency_table": "linear",
                }
            )
        return _write_map(directory, entries)

    def test_family_summarize_and_legacy_help_succeed(self):
        family = self.run_command(
            [sys.executable, "-m", "tools.vtx_diag", "residual_scan", "--help"]
        )
        summarize = self.run_command([*UNIFIED_RESIDUAL_SCAN, "--help"])
        legacy = self.run_command([str(LEGACY_RESIDUAL_SCAN), "--help"])

        self.assertTrue(os.access(LEGACY_RESIDUAL_SCAN, os.X_OK))
        for result in (family, summarize, legacy):
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
        self.assertIn("    summarize", family.stdout)
        for option in (
            "--label-map",
            "--docs",
            "--coverage-json",
            "--json",
            "--markdown",
            "--triage-json",
            "--triage-markdown",
        ):
            self.assertIn(option, summarize.stdout)
            self.assertIn(option, legacy.stdout)

    def test_legacy_wrapper_reexports_existing_helpers(self):
        legacy = _load_legacy_module()

        self.assertIs(legacy.build_scan, residual_scan.build_scan)
        self.assertIs(legacy.scan_module, residual_scan.scan_module)
        self.assertIs(legacy.build_gap_triage, residual_scan.build_gap_triage)

    def test_reports_and_output_streams_are_byte_identical(self):
        legacy = _load_legacy_module()
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            label_map = self.make_mixed_corpus(directory)
            outputs = {
                "json": directory / "residual.json",
                "markdown": directory / "residual.md",
                "triage_json": directory / "triage.json",
                "triage_markdown": directory / "triage.md",
            }
            shared = [
                "--label-map",
                str(label_map),
                "--docs",
                str(REPO_ROOT / "docs" / "xm-effect-support.md"),
                "--json",
                str(outputs["json"]),
                "--markdown",
                str(outputs["markdown"]),
                "--triage-json",
                str(outputs["triage_json"]),
                "--triage-markdown",
                str(outputs["triage_markdown"]),
            ]
            with mock.patch.object(
                residual_scan,
                "utc_now",
                return_value="2026-09-09T12:00:00Z",
            ):
                legacy_result = self.invoke(lambda: legacy.main(shared))
                legacy_bytes = {name: path.read_bytes() for name, path in outputs.items()}
                unified_result = self.invoke(
                    lambda: unified_main(["residual_scan", "summarize", *shared])
                )

            self.assertEqual(unified_result, legacy_result)
            self.assertEqual(unified_result, (0, "", ""))
            for name, path in outputs.items():
                with self.subTest(report=name):
                    self.assertEqual(path.read_bytes(), legacy_bytes[name])

            report = json.loads(outputs["json"].read_text(encoding="utf-8"))
            all_buckets = report["groups"]["all"]["buckets"]
            self.assertEqual(report["schema_version"], 1)
            self.assertEqual(report["tool"], "scripts/summarize-xm-residual-effect-scan.py")
            self.assertEqual(report["input_count"], 3)
            self.assertEqual(report["recommended_next_implementation_pr"], EXPECTED_RECOMMENDATION)
            self.assertEqual(all_buckets["axy"]["counts"]["missing_memory_count"], 1)
            self.assertEqual(all_buckets["vol_a"]["counts"]["count"], 1)
            self.assertEqual(all_buckets["vol_b"]["counts"]["count"], 1)
            self.assertEqual(all_buckets["7xy"]["counts"]["700_count"], 1)
            self.assertEqual(all_buckets["axy"]["best_target_label"], "xm-corpus-002")
            self.assertEqual(residual_scan.load_label_map(label_map)[0]["label"], "xm-corpus-002")

            implemented_group = residual_scan.ScanGroup("implemented-only")
            implemented_module = residual_scan.parse_xm_module(
                directory / "private-implemented-source.xm",
                "xm-corpus-005",
                "linear",
            )
            residual_scan.scan_module(implemented_module, [implemented_group])
            self.assertFalse(any(bucket.counts for bucket in implemented_group.buckets.values()))

    def test_empty_corpus_stdout_and_freeze_recommendation_match(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            label_map = _write_map(directory, [])
            legacy = self.run_command(
                [sys.executable, str(LEGACY_RESIDUAL_SCAN), "--label-map", str(label_map)]
            )
            unified = self.run_command([*UNIFIED_RESIDUAL_SCAN, "--label-map", str(label_map)])

            self.assertEqual(unified.returncode, legacy.returncode)
            self.assertEqual(unified.stdout, legacy.stdout)
            self.assertEqual(unified.stderr, legacy.stderr)
            self.assertIn("Corpus scanned: 0 modules.", unified.stdout)
            self.assertIn(EXPECTED_RECOMMENDATION, unified.stdout)

    def test_explicit_label_map_overrides_environment_and_environment_default_works(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            label_map = self.make_mixed_corpus(directory)
            environment = os.environ.copy()
            environment[residual_scan.PRIVATE_LABEL_MAP_ENV] = str(directory / "missing.json")
            explicit = self.run_command(
                [*UNIFIED_RESIDUAL_SCAN, "--label-map", str(label_map)],
                environment=environment,
            )

            environment[residual_scan.PRIVATE_LABEL_MAP_ENV] = str(label_map)
            unified_default = self.run_command(UNIFIED_RESIDUAL_SCAN, environment=environment)
            legacy_default = self.run_command(
                [sys.executable, str(LEGACY_RESIDUAL_SCAN)],
                environment=environment,
            )

            self.assertEqual(explicit.returncode, 0, explicit.stdout)
            self.assertEqual(unified_default.returncode, 0, unified_default.stdout)
            self.assertEqual(unified_default.stdout, legacy_default.stdout)
            self.assertEqual(unified_default.stderr, legacy_default.stderr)

    def test_malformed_missing_map_and_missing_module_failures_match(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            malformed = directory / "malformed-map.json"
            malformed.write_text('{"entries": [', encoding="utf-8")
            missing_map = directory / "missing-map.json"
            missing_module_map = _write_map(
                directory,
                [
                    {
                        "stable_anonymized_label": "xm-corpus-077",
                        "path": str(directory / "PRIVATE MISSING MODULE.xm"),
                        "frequency_table": "linear",
                    }
                ],
            )

            for label_map, message in (
                (malformed, "malformed label map JSON"),
                (missing_map, "could not read label map"),
                (missing_module_map, "could not read module for xm-corpus-077"),
            ):
                with self.subTest(label_map=label_map.name):
                    json_output = directory / f"{label_map.stem}.report.json"
                    markdown_output = directory / f"{label_map.stem}.report.md"
                    arguments = [
                        "--label-map",
                        str(label_map),
                        "--json",
                        str(json_output),
                        "--markdown",
                        str(markdown_output),
                    ]
                    legacy = self.run_command(
                        [sys.executable, str(LEGACY_RESIDUAL_SCAN), *arguments]
                    )
                    unified = self.run_command([*UNIFIED_RESIDUAL_SCAN, *arguments])

                    self.assertEqual(unified.returncode, 1)
                    self.assertEqual(unified.returncode, legacy.returncode)
                    self.assertEqual(unified.stdout, legacy.stdout)
                    self.assertEqual(unified.stderr, legacy.stderr)
                    self.assertIn(message, unified.stdout)
                    self.assertNotIn(str(directory), unified.stdout)
                    self.assertNotIn("PRIVATE MISSING MODULE.xm", unified.stdout)
                    self.assertFalse(json_output.exists())
                    self.assertFalse(markdown_output.exists())

    def test_outputs_are_explicit_temp_only_and_redact_private_identity(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            source = directory / "TOP SECRET MODULE NAME.xm"
            source.write_bytes(
                _synthetic_xm(
                    [(0, 0, 0, 0x0A, 0), (0, 0, 0xA4, 0, 0)],
                    title="TOP SECRET TITLE",
                )
            )
            label_map = _write_map(
                directory,
                [
                    {
                        "stable_anonymized_label": "xm-corpus-042",
                        "path": str(source),
                        "frequency_table": "linear",
                    }
                ],
            )
            json_output = directory / "safe.json"
            markdown_output = directory / "safe.md"
            result = self.run_command(
                [
                    *UNIFIED_RESIDUAL_SCAN,
                    "--label-map",
                    str(label_map),
                    "--json",
                    str(json_output),
                    "--markdown",
                    str(markdown_output),
                ]
            )

            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")
            self.assertEqual(
                {path.name for path in directory.iterdir()},
                {
                    source.name,
                    label_map.name,
                    json_output.name,
                    markdown_output.name,
                },
            )
            emitted = json_output.read_text(encoding="utf-8") + markdown_output.read_text(
                encoding="utf-8"
            )
            self.assertIn("xm-corpus-042", emitted)
            for private_value in (
                str(directory),
                str(source),
                source.name,
                label_map.name,
                "TOP SECRET TITLE",
            ):
                self.assertNotIn(private_value, emitted)
            self.assertEqual(
                json.loads(json_output.read_text(encoding="utf-8"))["privacy"],
                {
                    "private_filenames_redacted": True,
                    "private_paths_redacted": True,
                    "outputs_intended_for_tmp": True,
                },
            )

    def test_import_and_help_need_no_private_corpus_or_output_files(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            environment = os.environ.copy()
            environment["PYTHONPATH"] = str(REPO_ROOT)
            environment[residual_scan.PRIVATE_LABEL_MAP_ENV] = str(
                directory / "does-not-exist.json"
            )
            imported = self.run_command(
                [sys.executable, "-B", "-c", "import tools.vtx_diag.residual_scan"],
                cwd=directory,
                environment=environment,
            )
            helped = self.run_command(
                [*UNIFIED_RESIDUAL_SCAN, "--help"],
                cwd=REPO_ROOT,
                environment=environment,
            )

            self.assertEqual(imported.returncode, 0, imported.stderr)
            self.assertEqual(imported.stdout, "")
            self.assertEqual(imported.stderr, "")
            self.assertEqual(helped.returncode, 0, helped.stderr)
            self.assertEqual(list(directory.iterdir()), [])

    def test_already_migrated_help_dispatch_remains_green(self):
        for family, mode in (
            ("audio_compare", "compare"),
            ("audio_compare", "smoke"),
            ("audio_compare", "stems"),
            ("audio_compare", "discontinuities"),
            ("reference_triage", "correlate"),
            ("reference_triage", "focused-window"),
            ("effect_coverage", "summarize"),
        ):
            with self.subTest(family=family, mode=mode):
                result = self.run_command(
                    [sys.executable, "-m", "tools.vtx_diag", family, mode, "--help"]
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
