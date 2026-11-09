"""Fast structural/provenance checks; never construct a playback plan."""

import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts/generate-synthetic-xm-fixtures.py"
RECIPE = REPO / "tests/reference-xm/source/planner-dense-vibrato-v1.manifest.json"
NAME = "planner-dense-vibrato-v1.xm"


class PlannerWorkloadFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("planner_fixture_generator", SCRIPT)
        cls.generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.generator)

    def temporary_directory(self):
        """Use owned test directories within the maintainer artifact boundary."""
        return tempfile.TemporaryDirectory(
            prefix="vtx-planner-fixture-test-",
            dir="/private/tmp" if sys.platform == "darwin" else os.environ.get("TMPDIR", "/tmp"),
        )

    def manifest(self):
        """Read the committed compact workload recipe."""
        return self.generator.load_source_manifest(RECIPE)

    def test_independent_xm_structure_and_original_sample_source(self):
        manifest = self.manifest()
        fixture = manifest["fixtures"][0]
        data = self.generator.fixture_xm_bytes(manifest, NAME)
        u16 = lambda offset: int.from_bytes(data[offset:offset + 2], "little")
        u32 = lambda offset: int.from_bytes(data[offset:offset + 4], "little")
        self.assertEqual(len(data), fixture["xm_size_bytes"])
        self.assertEqual(hashlib.sha256(data).hexdigest(), fixture["xm_sha256"])
        self.assertEqual(data[:17], b"Extended Module: ")
        self.assertEqual(u16(58), 0x0104)
        self.assertEqual([u16(p) for p in [64, 66, 68, 70, 72, 74, 76, 78]],
                         [24, 0, 32, 24, 1, 1, 6, 125])
        self.assertEqual(data[80:104], bytes(range(24)))
        position, rows, cells = 60 + u32(60), 0, 0
        for _ in range(24):
            self.assertEqual(u32(position), 9)
            self.assertEqual(data[position + 4], 0)
            row_count, packed_size = u16(position + 5), u16(position + 7)
            self.assertEqual((row_count, packed_size), (256, 40_960))
            position += u32(position)
            end = position + packed_size
            for _ in range(row_count * 32):
                marker = data[position]
                position += 1
                values = [0] * 5
                if marker & 0x80:
                    for field in range(5):
                        if marker & (1 << field):
                            values[field] = data[position]
                            position += 1
                else:
                    values = [marker, *data[position:position + 4]]
                    position += 4
                self.assertEqual(values, [49, 1, 0, 4, 71])
                cells += 1
            self.assertEqual(position, end)
            rows += row_count
        self.assertEqual((rows, cells), (6_144, 196_608))
        fingerprint = manifest["structural_fingerprint"]
        self.assertEqual((fingerprint["visited_rows"], fingerprint["populated_cells"]), (rows, cells))
        self.assertEqual((fingerprint["sample_frames"], fingerprint["sample_encoding_bits"]), (64, 8))
        profile = manifest["planning_profile"]
        self.assertEqual([profile[k] for k in ["sample_rate", "rows", "note_births", "vibrato_children", "adapter_events"]],
                         [48_000, 6_144, 196_608, 983_040, 1_376_256])
        basic = (REPO / "tests/reference-xm/generated/basic-instrument-sample.xm").read_bytes()
        self.assertEqual(hashlib.sha256(basic).hexdigest(),
                         "79d1643434db33e9f268cd25ac3135b2b3049ae9f00a46526eec8212bf8ea957")
        basic_pattern = 60 + int.from_bytes(basic[60:64], "little")
        basic_tail = basic_pattern + int.from_bytes(basic[basic_pattern:basic_pattern + 4], "little")
        basic_tail += int.from_bytes(basic[basic_pattern + 7:basic_pattern + 9], "little")
        self.assertEqual(data[position:], basic[basic_tail:])
        self.assertEqual(len(data) - position, 367)

    def test_two_fresh_directories_preflight_and_compact_manifest(self):
        with self.temporary_directory() as first, self.temporary_directory() as second:
            outputs = []
            for directory in [first, second]:
                args = ["--manifest", str(RECIPE), "--fixture", NAME,
                        "--output-dir", directory, "--write-xm", "--verify"]
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    self.assertEqual(self.generator.main(args), 0)
                self.assertIn(str((Path(directory) / "generated" / NAME).resolve()), output.getvalue())
                outputs.append((Path(directory) / "generated" / NAME).read_bytes())
            self.assertEqual(outputs[0], outputs[1])
            written = self.generator.write_source_manifest(Path(first), self.manifest())
            self.assertEqual(written.relative_to(Path(first)), RECIPE.relative_to(RECIPE.parent.parent))
            canonical = json.loads(written.read_text())
            self.assertIn("fill", canonical["fixtures"][0]["module"]["patterns"][0])
            self.assertNotIn("events", canonical["fixtures"][0]["module"]["patterns"][0])

    def test_stale_hash_size_and_pcm_source_fail(self):
        for field, value in [("xm_sha256", "0" * 64), ("xm_size_bytes", 1)]:
            invalid = self.manifest()
            invalid["fixtures"][0][field] = value
            with self.assertRaises(ValueError):
                self.generator.validate_manifest(invalid)
        invalid = self.manifest()
        invalid["fixtures"][0]["module"]["instruments"][0]["samples"][0]["pcm_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            self.generator.validate_manifest(invalid)
        with self.temporary_directory() as directory:
            root = Path(directory)
            self.generator.write_xm_fixtures(root, self.manifest(), [NAME])
            (root / "generated" / NAME).write_bytes(b"corrupted")
            with self.assertRaises(ValueError):
                self.generator.verify_xm_fixtures(root, self.manifest(), [NAME])

    def test_missing_and_malformed_recipe_cli_fail_visibly(self):
        with self.temporary_directory() as directory:
            recipe = Path(directory) / "missing.json"
            for text in [None, "{broken", '{"schema_version":3}']:
                if text is not None:
                    recipe.write_text(text)
                error = io.StringIO()
                with contextlib.redirect_stderr(error):
                    self.assertEqual(self.generator.main(["--manifest", str(recipe), "--validate"]), 1)
                self.assertIn("error:", error.getvalue())

    def test_invalid_fill_and_source_path_are_rejected(self):
        for mutate in [
            lambda m: m.update(source_manifest="../outside.json"),
            lambda m: m["structural_fingerprint"].update(visited_rows=1),
            lambda m: m["planning_profile"].update(adapter_events=1),
            lambda m: m["fixtures"][0]["module"].update(instruments=[]),
            lambda m: m["fixtures"][0]["module"]["patterns"][0].update(fill=None),
            lambda m: m["fixtures"][0]["module"]["patterns"][0]["fill"].update(note=98),
        ]:
            invalid = copy.deepcopy(self.manifest())
            mutate(invalid)
            with self.assertRaises(ValueError):
                self.generator.validate_manifest(invalid)

    def test_traversal_and_symlink_escape_are_rejected(self):
        with self.temporary_directory() as directory:
            root = Path(directory)
            pack, outside = root / "pack", root / "outside"
            pack.mkdir()
            outside.mkdir()
            with self.assertRaises(ValueError):
                self.generator.resolved_child(pack, "../outside.xm")
            (pack / "generated").symlink_to(outside, target_is_directory=True)
            with self.assertRaises(ValueError):
                self.generator.write_xm_fixtures(pack, self.manifest(), [NAME])
            self.assertEqual(list(outside.iterdir()), [])

    @unittest.skipUnless(sys.platform == "darwin", "Maintainer macOS output contract")
    def test_workload_write_outside_private_tmp_is_rejected_before_io(self):
        with mock.patch.object(Path, "mkdir", side_effect=AssertionError("write attempted")):
            with self.assertRaises(ValueError):
                self.generator.write_xm_fixtures(REPO / "forbidden-workload-output", self.manifest(), [NAME])


if __name__ == "__main__":
    unittest.main()
