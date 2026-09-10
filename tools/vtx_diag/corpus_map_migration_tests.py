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

from tools.vtx_diag import corpus_map
from tools.vtx_diag.cli import main as unified_main


REPO_ROOT = Path(__file__).resolve().parents[2]
LEGACY_CORPUS_MAP = REPO_ROOT / "scripts" / "update-private-xm-corpus-label-map.py"
UNIFIED_CORPUS_MAP = [
    sys.executable,
    "-m",
    "tools.vtx_diag",
    "corpus_map",
    "update",
]
FIXED_TIME = "2026-09-10T12:00:00Z"


def _fixed(value: str, length: int) -> bytes:
    return value.encode("ascii")[:length].ljust(length, b"\x00")


def _put16(data: bytearray, value: int) -> None:
    data.extend(int(value).to_bytes(2, "little"))


def _put32(data: bytearray, value: int) -> None:
    data.extend(int(value).to_bytes(4, "little"))


def _synthetic_xm(
    *,
    title: str = "synthetic",
    tracker_name: str = "fixture-tracker",
    version: int = 0x0104,
    flags: int = 1,
    channels: int = 4,
    sample_counts: list[int] | None = None,
) -> bytes:
    sample_counts = [0] if sample_counts is None else sample_counts
    data = bytearray(b"Extended Module: ")
    data.extend(_fixed(title, 20))
    data.append(0x1A)
    data.extend(_fixed(tracker_name, 20))
    _put16(data, version)
    _put32(data, 276)
    for value in (1, 0, channels, 1, len(sample_counts), flags, 6, 125):
        _put16(data, value)
    data.extend(bytes(256))
    _put32(data, 9)
    data.append(0)
    _put16(data, 64)
    _put16(data, 0)
    for sample_count in sample_counts:
        _append_instrument(data, sample_count)
    return bytes(data)


def _append_instrument(data: bytearray, sample_count: int) -> None:
    if sample_count == 0:
        _put32(data, 29)
        data.extend(_fixed("instrument", 22))
        data.append(0)
        _put16(data, 0)
        return
    _put32(data, 263)
    data.extend(_fixed("instrument", 22))
    data.append(0)
    _put16(data, sample_count)
    _put32(data, 40)
    data.extend(bytes(230))
    for _ in range(sample_count):
        data.extend(bytes(18))
        data.extend(_fixed("sample", 22))


def _load_legacy_module():
    spec = importlib.util.spec_from_file_location("legacy_corpus_map", LEGACY_CORPUS_MAP)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    finally:
        sys.modules.pop(spec.name, None)
    return module


class CorpusMapMigrationTests(unittest.TestCase):
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

    def invoke_failure(self, callback) -> tuple[type[Exception], str, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                callback()
            except Exception as error:  # The legacy command intentionally lets these propagate.
                return type(error), str(error), stdout.getvalue(), stderr.getvalue()
        self.fail("expected corpus-map update to fail")

    def arguments(self, source: Path, output: Path) -> list[str]:
        return [
            "--source-dir",
            str(source),
            "--map",
            str(output / "label-map.json"),
            "--summary-json",
            str(output / "summary.json"),
            "--summary-markdown",
            str(output / "summary.md"),
        ]

    def assert_success_parity(
        self, arguments: list[str]
    ) -> tuple[tuple[int, str, str], dict[str, bytes]]:
        legacy = _load_legacy_module()
        output_paths = [Path(arguments[index]) for index in (3, 5, 7)]
        initial_outputs = {
            path: path.read_bytes() if path.exists() else None for path in output_paths
        }
        with mock.patch.object(corpus_map, "utc_now", return_value=FIXED_TIME):
            legacy_result = self.invoke(lambda: legacy.main(arguments))
        legacy_bytes = {path.name: path.read_bytes() for path in output_paths}
        for path, initial in initial_outputs.items():
            if initial is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(initial)
        with mock.patch.object(corpus_map, "utc_now", return_value=FIXED_TIME):
            unified_result = self.invoke(
                lambda: unified_main(["corpus_map", "update", *arguments])
            )

        self.assertEqual(unified_result, legacy_result)
        for path in output_paths:
            self.assertEqual(path.read_bytes(), legacy_bytes[path.name])
        return unified_result, legacy_bytes

    def test_update_help_and_legacy_wrapper_are_executable(self):
        family = self.run_command(
            [sys.executable, "-m", "tools.vtx_diag", "corpus_map", "--help"]
        )
        update = self.run_command([*UNIFIED_CORPUS_MAP, "--help"])
        legacy = self.run_command([str(LEGACY_CORPUS_MAP), "--help"])

        self.assertTrue(os.access(LEGACY_CORPUS_MAP, os.X_OK))
        for result in (family, update, legacy):
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
        self.assertIn("    update", family.stdout)
        self.assertNotIn("runtime-metrics", family.stdout)
        for option in ("--source-dir", "--map", "--summary-json", "--summary-markdown"):
            self.assertIn(option, update.stdout)
            self.assertIn(option, legacy.stdout)

    def test_legacy_wrapper_reexports_existing_helpers(self):
        legacy = _load_legacy_module()

        self.assertIs(legacy.parse_xm, corpus_map.parse_xm)
        self.assertIs(legacy.update_label_map, corpus_map.update_label_map)
        self.assertIs(legacy.build_summary, corpus_map.build_summary)
        self.assertIs(legacy.write_markdown, corpus_map.write_markdown)

    def test_new_map_reports_and_output_streams_are_byte_identical_and_redacted(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            source = directory / "private-looking-corpus"
            output = directory / "explicit-output"
            source.mkdir()
            private_title = "PRIVATE SYNTH TITLE"
            first = source / "z-private-looking-module.xm"
            second = source / "A-private-looking-module.XM"
            malformed = source / "m-private-looking-malformed.xm"
            first.write_bytes(_synthetic_xm(title=private_title, flags=0, channels=3))
            second.write_bytes(_synthetic_xm(title=private_title, sample_counts=[1, 2]))
            malformed.write_bytes(b"synthetic truncated XM")
            (source / "ignored-private-looking-module.txt").write_bytes(b"not an XM")
            arguments = self.arguments(source, output)
            output_paths = [Path(arguments[index]) for index in (3, 5, 7)]

            unified_result, _ = self.assert_success_parity(arguments)
            self.assertEqual(
                unified_result,
                (0, "Updated private XM corpus label map: 3 mapped modules, 3 new labels.\n", ""),
            )

            label_map = json.loads(output_paths[0].read_text(encoding="utf-8"))
            summary_json = output_paths[1].read_text(encoding="utf-8")
            summary_markdown = output_paths[2].read_text(encoding="utf-8")
            public_output = summary_json + summary_markdown + unified_result[1] + unified_result[2]
            self.assertEqual(
                [entry["label"] for entry in label_map["entries"]],
                ["xm-corpus-001", "xm-corpus-002", "xm-corpus-003"],
            )
            self.assertEqual(
                [entry["filename"] for entry in label_map["entries"]],
                [second.name, malformed.name, first.name],
            )
            self.assertEqual(label_map["entries"][1]["format"], "unknown")
            self.assertEqual(
                label_map["entries"][1]["parse_warnings"],
                ["missing or truncated XM header"],
            )
            self.assertEqual(label_map["generated_at_utc"], FIXED_TIME)
            self.assertEqual(label_map["total_xm_files_discovered"], 3)
            self.assertEqual(label_map["total_mapped_modules"], 3)
            self.assertEqual(
                label_map["newly_added_labels"],
                ["xm-corpus-001", "xm-corpus-002", "xm-corpus-003"],
            )
            self.assertIn(str(source.resolve()), output_paths[0].read_text(encoding="utf-8"))
            self.assertNotIn(private_title, output_paths[0].read_text(encoding="utf-8"))
            self.assertIn("xm-corpus-001", public_output)
            for private_value in (
                str(directory),
                str(source),
                str(output_paths[0]),
                first.name,
                second.name,
                malformed.name,
                private_title,
            ):
                self.assertNotIn(private_value, public_output)
            self.assertEqual(
                {path.name for path in directory.iterdir()},
                {source.name, output.name},
            )
            self.assertEqual(
                {path.name for path in output.iterdir()},
                {"label-map.json", "summary.json", "summary.md"},
            )

    def test_update_preserves_removed_entries_stabilizes_labels_and_adds_at_tail(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            source = directory / "corpus"
            output = directory / "output"
            source.mkdir()
            alpha = source / "alpha.xm"
            beta = source / "beta.xm"
            alpha.write_bytes(_synthetic_xm())
            beta.write_bytes(_synthetic_xm(flags=0))
            arguments = self.arguments(source, output)

            with mock.patch.object(corpus_map, "utc_now", return_value=FIXED_TIME):
                self.assertEqual(self.invoke(lambda: corpus_map.main(arguments))[0], 0)
                alpha.unlink()
                beta.write_bytes(_synthetic_xm(flags=1, channels=6))
                gamma = source / "gamma.xm"
                gamma.write_bytes(_synthetic_xm())
            self.assertEqual(self.assert_success_parity(arguments)[0][0], 0)

            updated = json.loads((output / "label-map.json").read_text(encoding="utf-8"))
            self.assertEqual(
                [(entry["filename"], entry["label"]) for entry in updated["entries"]],
                [
                    ("alpha.xm", "xm-corpus-001"),
                    ("beta.xm", "xm-corpus-002"),
                    ("gamma.xm", "xm-corpus-003"),
                ],
            )
            self.assertEqual(updated["entries"][1]["channel_count"], 6)
            self.assertEqual(updated["total_xm_files_discovered"], 2)
            self.assertEqual(updated["total_mapped_modules"], 3)
            self.assertEqual(updated["newly_added_labels"], ["xm-corpus-003"])

            with mock.patch.object(corpus_map, "utc_now", return_value=FIXED_TIME):
                self.assertEqual(self.invoke(lambda: corpus_map.main(arguments))[0], 0)
            repeated = json.loads((output / "label-map.json").read_text(encoding="utf-8"))
            self.assertEqual(
                [entry["label"] for entry in repeated["entries"]],
                ["xm-corpus-001", "xm-corpus-002", "xm-corpus-003"],
            )
            self.assertEqual(repeated["newly_added_labels"], [])

    def test_duplicate_filename_collision_allocates_a_new_label(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            source = directory / "corpus"
            output = directory / "output"
            source.mkdir()
            collision = source / "collision.xm"
            collision.write_bytes(_synthetic_xm())
            output.mkdir()
            map_path = output / "label-map.json"
            map_path.write_text(
                json.dumps(
                    {
                        "entries": [
                            {"label": "xm-corpus-005", "filename": collision.name, "path": "/old/one.xm"},
                            {"label": "xm-corpus-008", "filename": collision.name, "path": "/old/two.xm"},
                        ]
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(self.assert_success_parity(self.arguments(source, output))[0][0], 0)

            label_map = json.loads(map_path.read_text(encoding="utf-8"))
            self.assertEqual(
                [entry["label"] for entry in label_map["entries"]],
                ["xm-corpus-005", "xm-corpus-008", "xm-corpus-009"],
            )
            self.assertEqual(label_map["newly_added_labels"], ["xm-corpus-009"])

    def test_empty_corpus_is_supported(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            source = directory / "empty-corpus"
            output = directory / "output"
            source.mkdir()

            result, _ = self.assert_success_parity(self.arguments(source, output))

            self.assertEqual(result, (0, "Updated private XM corpus label map: 0 mapped modules, 0 new labels.\n", ""))
            label_map = json.loads((output / "label-map.json").read_text(encoding="utf-8"))
            summary = json.loads((output / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(label_map["entries"], [])
            self.assertEqual(summary["total_mapped_modules"], 0)
            self.assertEqual(summary["channel_count_range"], {"max": None, "min": None})

    def test_malformed_map_and_invalid_source_fail_identically_without_partial_output(self):
        legacy = _load_legacy_module()
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            source = directory / "corpus"
            source.mkdir()
            (source / "synthetic.xm").write_bytes(_synthetic_xm())

            for case in ("malformed-map", "missing-source"):
                with self.subTest(case=case):
                    output = directory / case
                    output.mkdir()
                    arguments = self.arguments(source, output)
                    map_path = output / "label-map.json"
                    if case == "malformed-map":
                        map_path.write_text('{"entries": [', encoding="utf-8")
                        original_map = map_path.read_bytes()
                    else:
                        arguments[1] = str(directory / "missing-private-looking-corpus")
                        original_map = None

                    legacy_failure = self.invoke_failure(lambda: legacy.main(arguments))
                    unified_failure = self.invoke_failure(
                        lambda: unified_main(["corpus_map", "update", *arguments])
                    )

                    self.assertEqual(unified_failure, legacy_failure)
                    self.assertIn(unified_failure[0], (json.JSONDecodeError, FileNotFoundError))
                    if original_map is None:
                        self.assertFalse(map_path.exists())
                    else:
                        self.assertEqual(map_path.read_bytes(), original_map)
                    self.assertFalse((output / "summary.json").exists())
                    self.assertFalse((output / "summary.md").exists())

    def test_import_help_and_environment_default_create_no_artifacts(self):
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            environment = os.environ.copy()
            environment["PYTHONPATH"] = str(REPO_ROOT)
            environment[corpus_map.PRIVATE_LABEL_MAP_ENV] = str(directory / "local-map.json")
            imported = self.run_command(
                [
                    sys.executable,
                    "-B",
                    "-c",
                    (
                        "from tools.vtx_diag import corpus_map; "
                        "assert str(corpus_map.DEFAULT_MAP).endswith('local-map.json')"
                    ),
                ],
                cwd=directory,
                environment=environment,
            )
            unified_help = self.run_command(
                [*UNIFIED_CORPUS_MAP, "--help"], cwd=directory, environment=environment
            )
            legacy_help = self.run_command(
                [str(LEGACY_CORPUS_MAP), "--help"], cwd=directory, environment=environment
            )

            for result in (imported, unified_help, legacy_help):
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
            self.assertEqual(imported.stdout, "")
            self.assertEqual(list(directory.iterdir()), [])

    def test_already_migrated_families_remain_present_and_dispatch_help(self):
        for family, mode in (
            ("audio_compare", "compare"),
            ("audio_compare", "smoke"),
            ("audio_compare", "stems"),
            ("audio_compare", "discontinuities"),
            ("reference_triage", "correlate"),
            ("reference_triage", "focused-window"),
            ("effect_coverage", "summarize"),
            ("residual_scan", "summarize"),
            ("runtime_trace", "summarize"),
            ("runtime_trace", "correlate-window"),
        ):
            with self.subTest(family=family, mode=mode):
                result = self.run_command(
                    [sys.executable, "-m", "tools.vtx_diag", family, mode, "--help"]
                )
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
