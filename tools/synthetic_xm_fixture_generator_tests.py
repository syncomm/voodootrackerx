import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "generate-synthetic-xm-fixtures.py"


def load_module():
    spec = importlib.util.spec_from_file_location("synthetic_xm_fixture_generator", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class SyntheticXMFixtureGeneratorTests(unittest.TestCase):
    def test_manifest_is_deterministic_and_names_first_fixture(self):
        generator = load_module()

        first = generator.deterministic_json(generator.fixture_manifest())
        second = generator.deterministic_json(generator.fixture_manifest())
        manifest = json.loads(first)

        self.assertEqual(first, second)
        self.assertEqual([fixture["name"] for fixture in manifest["fixtures"]], ["basic-instrument-sample.xm"])
        self.assertEqual(manifest["fixtures"][0]["xm_output"], "generated/basic-instrument-sample.xm")
        self.assertEqual(
            manifest["fixtures"][0]["source_manifest"],
            "source/basic-instrument-sample.manifest.json",
        )
        self.assertFalse(manifest["writes_binary_xm_by_default"])
        self.assertFalse(manifest["writes_reference_renders_by_default"])

    def test_manifest_does_not_include_private_or_local_paths(self):
        generator = load_module()

        manifest_text = generator.deterministic_json(generator.fixture_manifest())

        forbidden_fragments = [
            "/" + "Users",
            "Desk" + "top",
            "private-xm-corpus",
            "vtx-private-xm-corpus-label-map",
            "xm-corpus-",
            "/tmp/vtx-",
            ".wav",
            ".jsonl",
        ]
        for fragment in forbidden_fragments:
            self.assertNotIn(fragment, manifest_text)

    def test_write_manifest_stays_inside_output_dir_and_writes_no_audio_or_xm(self):
        generator = load_module()

        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "pack"
            written = generator.write_source_manifest(output_dir)
            files = sorted(path.relative_to(output_dir).as_posix() for path in output_dir.rglob("*") if path.is_file())

            self.assertEqual(
                written.resolve(),
                (output_dir / "source" / "basic-instrument-sample.manifest.json").resolve(),
            )
            self.assertEqual(files, ["source/basic-instrument-sample.manifest.json"])
            self.assertFalse((output_dir / "generated" / "basic-instrument-sample.xm").exists())
            self.assertEqual(list(output_dir.rglob("*.wav")), [])
            self.assertEqual(list(output_dir.rglob("*.jsonl")), [])

    def test_planned_paths_are_confined_to_requested_output_dir(self):
        generator = load_module()

        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "pack"
            paths = generator.planned_paths(output_dir)
            root = output_dir.resolve()
            relative_paths = {
                key: path.resolve().relative_to(root).as_posix()
                for key, path in paths.items()
            }

            self.assertEqual(
                relative_paths,
                {
                    "source_manifest": "source/basic-instrument-sample.manifest.json",
                    "xm_output": "generated/basic-instrument-sample.xm",
                    "reference_render_directory": "reference-renders",
                },
            )

            with self.assertRaises(ValueError):
                generator.resolved_child(output_dir, "../outside.manifest.json")


if __name__ == "__main__":
    unittest.main()
