import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.audio_compare_tests import synthetic_effect_coverage_diagnostics
from tools.vtx_diag import effect_coverage


REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY_EFFECT_COVERAGE = REPO_ROOT / "scripts" / "summarize-xm-effect-coverage.py"
UNIFIED_EFFECT_COVERAGE = [
    sys.executable, "-m", "tools.vtx_diag", "effect_coverage", "summarize",
]
EXPECTED_BACKEND_FREEZE_RECOMMENDATION = (
    "No behavior-changing XM effect PR is recommended under the current backend freeze; "
    "use docs/xm-effect-support.md and docs/reports/xm-backend-freeze-hardening-audit.md "
    "for current prioritization; promote a backend PR only if a freeze-exit criterion is met."
)


def synthetic_runtime_trace() -> list[dict[str, object]]:
    """Return public-safe runtime events spanning applied, unsupported, and no-op states."""

    return [
        {
            "runtimeAction": "c_mixer_update_gain_pan_applied",
            "runtimeAudioBackend": "c_mixer",
            "orderIndex": 0,
            "patternIndex": 2,
            "rowIndex": 10,
            "tickInRow": 0,
            "channelIndex": 1,
            "effectType": "11",
            "effectParam": "02",
            "volumeColumn": "00",
        },
        {
            "runtimeAction": "c_mixer_update_deferred_unsupported",
            "runtimeAudioBackend": "c_mixer",
            "orderIndex": 0,
            "patternIndex": 2,
            "rowIndex": 11,
            "tickInRow": 1,
            "channelIndex": 2,
            "effectType": "07",
            "effectParam": "34",
            "volumeColumn": "00",
        },
        {
            "runtimeAction": "c_mixer_update_deferred_no_active_voice",
            "runtimeAudioBackend": "c_mixer",
            "orderIndex": 0,
            "patternIndex": 2,
            "rowIndex": 12,
            "tickInRow": 2,
            "channelIndex": 3,
            "effectType": "1D",
            "effectParam": "12",
            "volumeColumn": "00",
        },
    ]


def synthetic_offline_diagnostics() -> dict[str, object]:
    """Extend the established synthetic diagnostics with traversal and volume-portamento rows."""

    diagnostics = synthetic_effect_coverage_diagnostics()
    diagnostics["pattern_traversal_timing_effects"].append(
        {
            "source": {"order": 1, "pattern": 3, "row": 21},
            "channel_index": 2,
            "effect_type": 0x0B,
            "effect_param": 0x02,
            "effect_label": "Bxx position jump",
            "status": "applied",
            "current_status": "applied",
        }
    )
    diagnostics["volume_column_mappings"].append(
        {
            "source": {"order": 1, "pattern": 3, "row": 22},
            "channel_index": 2,
            "synthetic_tick": 1,
            "volume_column": {
                "raw_value": 0xF4,
                "command": {"name": "tonePortamento"},
                "applied": True,
                "deferred": False,
                "ignored_as_empty_or_no_op": False,
                "classification": "supported",
            },
        }
    )
    diagnostics.setdefault("portamento_slide_effects", []).append(
        {
            "source": {"order": 1, "pattern": 3, "row": 23},
            "channel_index": 2,
            "synthetic_tick": 0,
            "effect_type": 0x01,
            "effect_param": 0x00,
            "status": "zero_param_effect_memory_deferred",
            "current_status": "zero_param_effect_memory_deferred",
            "applied": False,
            "deferred": True,
            "ignored_as_no_op": True,
            "effect_memory_missing": True,
            "memory_unavailable_reason": "missing_1xx_portamento_effect_memory",
        }
    )
    return diagnostics


class EffectCoverageMigrationTests(unittest.TestCase):
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

    def assert_report_parity(
        self,
        inputs: list[Path],
        json_report: Path,
        markdown_report: Path,
    ) -> dict[str, object]:
        shared_arguments = [
            *(str(path) for path in inputs),
            "--json",
            str(json_report),
            "--markdown",
            str(markdown_report),
        ]
        legacy = self.run_command(
            [sys.executable, str(LEGACY_EFFECT_COVERAGE), *shared_arguments]
        )
        self.assertEqual(legacy.returncode, 0, legacy.stderr)
        legacy_json = json_report.read_bytes()
        legacy_markdown = markdown_report.read_bytes()

        unified = self.run_command([*UNIFIED_EFFECT_COVERAGE, *shared_arguments])

        self.assertEqual(unified.returncode, legacy.returncode, unified.stderr)
        self.assertEqual(unified.stdout, legacy.stdout)
        self.assertEqual(unified.stderr, legacy.stderr)
        self.assertEqual(json_report.read_bytes(), legacy_json)
        self.assertEqual(markdown_report.read_bytes(), legacy_markdown)
        return json.loads(legacy_json)

    def test_effect_coverage_family_and_summarize_help_succeed(self):
        family = self.run_command(
            [sys.executable, "-m", "tools.vtx_diag", "effect_coverage", "--help"]
        )
        summarize = self.run_command([*UNIFIED_EFFECT_COVERAGE, "--help"])
        legacy = self.run_command(
            [sys.executable, str(LEGACY_EFFECT_COVERAGE), "--help"]
        )

        for result in (family, summarize, legacy):
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
        self.assertIn("    summarize", family.stdout)
        for option in ("inputs", "--json", "--markdown", "--top"):
            self.assertIn(option, summarize.stdout)
            self.assertIn(option, legacy.stdout)

    def test_runtime_offline_and_mixed_reports_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            runtime = directory / "synthetic-runtime.jsonl"
            offline = directory / "synthetic-offline.effect-coverage.json"
            runtime.write_text(
                "".join(json.dumps(event) + "\n" for event in synthetic_runtime_trace()),
                encoding="utf-8",
            )
            offline.write_text(
                json.dumps(synthetic_offline_diagnostics()),
                encoding="utf-8",
            )

            summaries = {}
            for label, inputs in (
                ("runtime", [runtime]),
                ("offline", [offline]),
                ("mixed", [runtime, offline]),
            ):
                with self.subTest(input_kind=label):
                    summaries[label] = self.assert_report_parity(
                        inputs,
                        directory / f"{label}.json",
                        directory / f"{label}.md",
                    )

            runtime_rows = summaries["runtime"]["effect_coverage"]
            self.assertEqual(
                {row["runtime_offline_category"] for row in runtime_rows},
                {"runtime_c_mixer_trace"},
            )
            offline_rows = summaries["offline"]["effect_coverage"]
            self.assertEqual(
                {row["runtime_offline_category"] for row in offline_rows},
                {"offline_bounded_render"},
            )
            mixed = summaries["mixed"]
            mixed_rows = {row["command"]: row for row in mixed["effect_coverage"]}
            self.assertEqual(mixed["schema_version"], 1)
            self.assertEqual(mixed["tool"], "scripts/summarize-xm-effect-coverage.py")
            self.assertGreater(mixed["summary"]["applied_count"], 0)
            self.assertGreater(mixed["summary"]["deferred_count"], 0)
            self.assertGreater(mixed["summary"]["unsupported_count"], 0)
            self.assertGreater(
                mixed["summary"]["no_op_effect_memory_deferred_count"],
                0,
            )
            self.assertGreater(mixed["summary"]["effect_memory_missing_count"], 0)
            self.assertEqual(
                mixed["summary"]["recommended_next_pr"],
                EXPECTED_BACKEND_FREEZE_RECOMMENDATION,
            )
            self.assertEqual(
                effect_coverage.BACKEND_FREEZE_NEXT_PR_RECOMMENDATION,
                EXPECTED_BACKEND_FREEZE_RECOMMENDATION,
            )
            self.assertEqual(
                mixed_rows["Hxy global volume slide"]["first_coordinate"],
                "order 0 pattern 2 row 10 ch 1 tick 0",
            )
            self.assertEqual(mixed_rows["Bxx position jump"]["applied_count"], 1)
            self.assertEqual(
                mixed_rows["volume-column tone portamento"]["applied_count"],
                1,
            )
            self.assertEqual(
                {
                    row["runtime_offline_category"]
                    for row in mixed["effect_coverage"]
                },
                {"runtime_c_mixer_trace", "offline_bounded_render"},
            )
            self.assertNotIn(directory_name, json.dumps(mixed))

    def test_empty_input_stdout_is_byte_identical(self):
        with tempfile.TemporaryDirectory() as directory_name:
            empty = Path(directory_name) / "empty.json"
            empty.write_text("{}\n", encoding="utf-8")

            legacy = self.run_command(
                [sys.executable, str(LEGACY_EFFECT_COVERAGE), str(empty)]
            )
            unified = self.run_command([*UNIFIED_EFFECT_COVERAGE, str(empty)])

            self.assertEqual(unified.returncode, legacy.returncode)
            self.assertEqual(unified.stdout, legacy.stdout)
            self.assertEqual(unified.stderr, legacy.stderr)
            self.assertIn("Detected commands: 0", unified.stdout)
            self.assertIn("| none | n/a | n/a |", unified.stdout)

    def test_malformed_and_missing_inputs_match_legacy_failures(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            malformed = directory / "malformed.json"
            malformed_jsonl = directory / "malformed.jsonl"
            missing = directory / "missing.json"
            malformed.write_text('{"broken":\n', encoding="utf-8")
            malformed_jsonl.write_text('{"broken":\n', encoding="utf-8")

            for input_path, expected_message in (
                (malformed, "malformed JSON input"),
                (malformed_jsonl, "malformed JSONL input"),
                (missing, "missing input"),
            ):
                with self.subTest(input_path=input_path.name):
                    legacy = self.run_command(
                        [sys.executable, str(LEGACY_EFFECT_COVERAGE), str(input_path)]
                    )
                    unified = self.run_command(
                        [*UNIFIED_EFFECT_COVERAGE, str(input_path)]
                    )

                    self.assertEqual(legacy.returncode, 1)
                    self.assertEqual(unified.returncode, legacy.returncode)
                    self.assertEqual(unified.stdout, legacy.stdout)
                    self.assertEqual(unified.stderr, legacy.stderr)
                    self.assertIn(expected_message, unified.stderr)

    def test_legacy_wrapper_reexports_the_existing_helper_surface(self):
        spec = importlib.util.spec_from_file_location(
            "legacy_effect_coverage",
            LEGACY_EFFECT_COVERAGE,
        )
        module = importlib.util.module_from_spec(spec)
        self.assertIsNotNone(spec.loader)
        sys.modules[spec.name] = module
        try:
            spec.loader.exec_module(module)
        finally:
            sys.modules.pop(spec.name, None)

        self.assertIs(
            module.build_summary_from_payloads,
            effect_coverage.build_summary_from_payloads,
        )
        self.assertIs(module.build_markdown_report, effect_coverage.build_markdown_report)

    def test_output_is_confined_to_requested_temp_paths(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            offline = directory / "offline.json"
            json_report = directory / "summary.json"
            markdown_report = directory / "summary.md"
            offline.write_text(json.dumps(synthetic_offline_diagnostics()), encoding="utf-8")

            result = self.run_command(
                [
                    *UNIFIED_EFFECT_COVERAGE,
                    str(offline),
                    "--json",
                    str(json_report),
                    "--markdown",
                    str(markdown_report),
                ]
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")
            self.assertEqual(
                {path.name for path in directory.iterdir()},
                {"offline.json", "summary.json", "summary.md"},
            )

    def test_package_import_needs_no_private_or_local_inputs(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            environment = os.environ.copy()
            environment["PYTHONPATH"] = str(REPO_ROOT)
            result = self.run_command(
                [sys.executable, "-B", "-c", "import tools.vtx_diag.effect_coverage"],
                cwd=directory,
                environment=environment,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")
            self.assertEqual(list(directory.iterdir()), [])

    def test_already_migrated_command_help_remains_available(self):
        for family, mode in (
            ("audio_compare", "compare"),
            ("audio_compare", "smoke"),
            ("audio_compare", "stems"),
            ("audio_compare", "discontinuities"),
            ("reference_triage", "correlate"),
            ("reference_triage", "focused-window"),
        ):
            with self.subTest(family=family, mode=mode):
                result = self.run_command(
                    [sys.executable, "-m", "tools.vtx_diag", family, mode, "--help"]
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
