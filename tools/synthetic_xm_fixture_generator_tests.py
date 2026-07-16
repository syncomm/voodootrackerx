import copy
import importlib.util
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "generate-synthetic-xm-fixtures.py"
PACK_ROOT = SCRIPT_PATH.parents[1] / "tests" / "reference-xm"
ALL_FIXTURES = [
    "basic-instrument-sample.xm",
    "multi-pattern-loop-boundary.xm",
    "instrument-sustained-defaults.xm",
    "instrument-metadata-matrix.xm",
]


def load_module():
    spec = importlib.util.spec_from_file_location("synthetic_xm_fixture_generator", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class SyntheticXMFixtureGeneratorTests(unittest.TestCase):
    def test_manifest_is_deterministic_and_names_generated_fixtures(self):
        generator = load_module()

        first = generator.deterministic_json(generator.fixture_manifest())
        second = generator.deterministic_json(generator.fixture_manifest())
        manifest = json.loads(first)
        fixtures = {fixture["name"]: fixture for fixture in manifest["fixtures"]}

        self.assertEqual(first, second)
        self.assertEqual(
            [fixture["name"] for fixture in manifest["fixtures"]],
            ALL_FIXTURES,
        )
        self.assertEqual(fixtures["basic-instrument-sample.xm"]["xm_output"], "generated/basic-instrument-sample.xm")
        self.assertEqual(fixtures["basic-instrument-sample.xm"]["id"], "basic-instrument-sample")
        self.assertEqual(
            fixtures["basic-instrument-sample.xm"]["xm_sha256"],
            hashlib.sha256(generator.basic_instrument_sample_xm_bytes()).hexdigest(),
        )
        self.assertEqual(
            fixtures["basic-instrument-sample.xm"]["xm_size_bytes"],
            len(generator.basic_instrument_sample_xm_bytes()),
        )
        self.assertEqual(
            fixtures["multi-pattern-loop-boundary.xm"]["xm_output"],
            "generated/multi-pattern-loop-boundary.xm",
        )
        self.assertEqual(fixtures["multi-pattern-loop-boundary.xm"]["id"], "multi-pattern-loop-boundary")
        self.assertEqual(
            fixtures["multi-pattern-loop-boundary.xm"]["xm_sha256"],
            hashlib.sha256(generator.multi_pattern_loop_boundary_xm_bytes()).hexdigest(),
        )
        self.assertEqual(
            fixtures["multi-pattern-loop-boundary.xm"]["xm_size_bytes"],
            len(generator.multi_pattern_loop_boundary_xm_bytes()),
        )
        self.assertEqual(
            fixtures["basic-instrument-sample.xm"]["source_manifest"],
            "source/basic-instrument-sample.manifest.json",
        )
        self.assertEqual(
            fixtures["multi-pattern-loop-boundary.xm"]["source_manifest"],
            "source/basic-instrument-sample.manifest.json",
        )
        sustained = fixtures["instrument-sustained-defaults.xm"]
        sustained_bytes = generator.fixture_xm_bytes(manifest, sustained["name"])
        self.assertEqual(sustained["xm_output"], "generated/instrument-sustained-defaults.xm")
        self.assertEqual(sustained["xm_size_bytes"], 33_486)
        self.assertEqual(sustained["xm_sha256"], hashlib.sha256(sustained_bytes).hexdigest())
        matrix = fixtures["instrument-metadata-matrix.xm"]
        matrix_bytes = generator.fixture_xm_bytes(manifest, matrix["name"])
        self.assertEqual(matrix["xm_output"], "generated/instrument-metadata-matrix.xm")
        self.assertEqual(matrix["xm_size_bytes"], 5_635)
        self.assertEqual(matrix["xm_sha256"], hashlib.sha256(matrix_bytes).hexdigest())
        self.assertEqual(manifest["schema_version"], 2)
        generator.validate_manifest(manifest)

    def test_manifest_does_not_include_private_or_local_paths(self):
        generator = load_module()

        manifest_text = generator.deterministic_json(generator.fixture_manifest())

        forbidden_fragments = [
            "/" + "Users",
            "Desk" + "top",
            "private-xm-corpus",
            "vtx-" + "private-xm-corpus-label-map",
            "xm-corpus-",
            "/tmp/vtx-",
            ".wav",
            ".jsonl",
        ]
        for fragment in forbidden_fragments:
            self.assertNotIn(fragment, manifest_text)

    def test_basic_instrument_sample_xm_bytes_are_deterministic_and_public_safe(self):
        generator = load_module()

        first = generator.basic_instrument_sample_xm_bytes()
        second = generator.basic_instrument_sample_xm_bytes()

        self.assertEqual(first, second)
        self.assertLess(len(first), 1024)
        self.assertIn(b"Extended Module: ", first)
        self.assertIn(b"VTX BASIC SAMPLE", first)
        self.assertIn(b"BASIC SAMPLE", first)
        self.assertIn(b"SINE64", first)

        forbidden_fragments = [
            b"/" + b"Users",
            b"Desk" + b"top",
            b"private-xm-corpus",
            b"xm-corpus-",
            b".wav",
            b".jsonl",
            b".trace",
        ]
        for fragment in forbidden_fragments:
            self.assertNotIn(fragment, first)

    def test_multi_pattern_loop_boundary_xm_bytes_are_deterministic_and_public_safe(self):
        generator = load_module()

        first = generator.multi_pattern_loop_boundary_xm_bytes()
        second = generator.multi_pattern_loop_boundary_xm_bytes()

        self.assertEqual(first, second)
        self.assertLess(len(first), 1024)
        self.assertIn(b"Extended Module: ", first)
        self.assertIn(b"VTX LOOP BOUNDARY", first)
        self.assertIn(b"BOUNDARY SAMPLE", first)
        self.assertIn(b"BOUNDARY64", first)

        forbidden_fragments = [
            b"/" + b"Users",
            b"Desk" + b"top",
            b"private-xm-corpus",
            b"xm-corpus-",
            b".wav",
            b".jsonl",
            b".trace",
        ]
        for fragment in forbidden_fragments:
            self.assertNotIn(fragment, first)

    def test_sustained_fixture_has_pinned_pcm_metadata_and_nontrivial_duration(self):
        generator = load_module()
        manifest = generator.fixture_manifest()
        fixture = next(item for item in manifest["fixtures"] if item["name"] == "instrument-sustained-defaults.xm")
        instrument = fixture["module"]["instruments"][0]
        sample = instrument["samples"][0]
        payload = generator.fixture_xm_bytes(manifest, fixture["name"])

        self.assertEqual(payload, generator.fixture_xm_bytes(manifest, fixture["name"]))
        self.assertEqual(len(payload), 33_486)
        self.assertEqual(hashlib.sha256(payload).hexdigest(), "babedfc9bd79f7e1ac79dbec6493e2182182700a8855c42cd15405f4eb6f0fde")
        self.assertEqual(sample["pcm_recipe"]["frame_count"], 16_384)
        self.assertGreater(sample["pcm_recipe"]["frame_count"], 8_363)
        self.assertEqual(sample["encoding"], "signed_16_bit_delta_pcm")
        self.assertEqual(sample["loop"], {"length_frames": 8_192, "mode": "forward", "start_frame": 4_096})
        self.assertEqual(hashlib.sha256(generator.sample_pcm_bytes(sample)).hexdigest(), sample["pcm_sha256"])
        self.assertEqual(instrument["volume_envelope"]["points"], [[0, 64], [24, 56], [48, 64]])

    def test_metadata_matrix_has_pinned_pairwise_sample_header_coverage(self):
        generator = load_module()
        manifest = generator.fixture_manifest()
        fixture = next(item for item in manifest["fixtures"] if item["name"] == "instrument-metadata-matrix.xm")
        samples = [instrument["samples"][0] for instrument in fixture["module"]["instruments"]]
        payload = generator.fixture_xm_bytes(manifest, fixture["name"])

        self.assertEqual(len(payload), 5_635)
        self.assertEqual(hashlib.sha256(payload).hexdigest(), "590e4aaafc71c41130cb1a9a4e768220c38c6e8dcdd3529d9be6e35ec400aef3")
        self.assertEqual([sample["panning"] for sample in samples], [0, 64, 128, 192, 255])
        self.assertEqual([sample["volume"] for sample in samples], [0, 16, 32, 48, 64])
        self.assertEqual([sample["finetune"] for sample in samples], [-96, -32, 0, 48, 96])
        self.assertEqual([sample["relative_note"] for sample in samples], [-12, 5, -5, 12, 0])
        self.assertEqual([sample["encoding"] for sample in samples], [
            "signed_8_bit_delta_pcm",
            "signed_16_bit_delta_pcm",
            "signed_8_bit_delta_pcm",
            "signed_16_bit_delta_pcm",
            "signed_8_bit_delta_pcm",
        ])
        self.assertEqual([sample["loop"]["mode"] for sample in samples], [
            "none", "forward", "ping_pong", "none", "forward",
        ])
        for sample in samples:
            self.assertEqual(hashlib.sha256(generator.sample_pcm_bytes(sample)).hexdigest(), sample["pcm_sha256"])

    def test_manifest_validation_rejects_invalid_ranges_events_and_duplicate_ids(self):
        generator = load_module()
        manifest = generator.fixture_manifest()
        sustained = 2
        sample_path = ["fixtures", sustained, "module", "instruments", 0, "samples", 0]
        cases = [
            ("volume", sample_path + ["volume"], 65),
            ("panning", sample_path + ["panning"], 256),
            ("finetune", sample_path + ["finetune"], -129),
            ("relative_note", sample_path + ["relative_note"], 128),
            ("loop", sample_path + ["loop", "length_frames"], 99_999),
            ("envelope ordering", ["fixtures", sustained, "module", "instruments", 0, "volume_envelope", "points"], [[8, 64], [4, 32]]),
        ]
        for label, path, replacement in cases:
            with self.subTest(label=label):
                invalid = copy.deepcopy(manifest)
                target = invalid
                for component in path[:-1]:
                    target = target[component]
                target[path[-1]] = replacement
                with self.assertRaisesRegex(ValueError, label):
                    generator.validate_manifest(invalid, verify_derived=False)

        unsupported_event = copy.deepcopy(manifest)
        unsupported_event["fixtures"][sustained]["module"]["patterns"][0]["events"][0]["ignored"] = 1
        with self.assertRaisesRegex(ValueError, "unsupported event fields"):
            generator.validate_manifest(unsupported_event, verify_derived=False)
        duplicate_id = copy.deepcopy(manifest)
        duplicate_id["fixtures"][1]["id"] = duplicate_id["fixtures"][0]["id"]
        with self.assertRaisesRegex(ValueError, "fixture id"):
            generator.validate_manifest(duplicate_id, verify_derived=False)

    def test_generation_order_scoping_and_committed_verification_are_deterministic(self):
        generator = load_module()
        manifest = generator.fixture_manifest()
        first = {name: generator.fixture_xm_bytes(manifest, name) for name in ALL_FIXTURES}
        reordered = copy.deepcopy(manifest)
        reordered["fixtures"].reverse()

        for name in ALL_FIXTURES:
            self.assertEqual(first[name], generator.fixture_xm_bytes(reordered, name))
        self.assertEqual([item["name"] for item in generator.verify_xm_fixtures(PACK_ROOT, manifest)], ALL_FIXTURES)

        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "pack"
            selected = "instrument-sustained-defaults.xm"
            generator.write_xm_fixtures(output_dir, manifest, [selected])
            self.assertEqual([path.name for path in (output_dir / "generated").iterdir()], [selected])
            self.assertEqual(
                [item["name"] for item in generator.verify_xm_fixtures(output_dir, manifest, [selected])],
                [selected],
            )

    def test_write_xm_stays_inside_output_dir_and_writes_no_renders(self):
        generator = load_module()

        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "pack"
            written = generator.write_xm_fixture(output_dir)
            files = sorted(path.relative_to(output_dir).as_posix() for path in output_dir.rglob("*") if path.is_file())

            self.assertEqual(
                [path.resolve() for path in written],
                [
                    (output_dir / "generated" / "basic-instrument-sample.xm").resolve(),
                    (output_dir / "generated" / "multi-pattern-loop-boundary.xm").resolve(),
                    (output_dir / "generated" / "instrument-sustained-defaults.xm").resolve(),
                    (output_dir / "generated" / "instrument-metadata-matrix.xm").resolve(),
                ],
            )
            self.assertEqual(
                files,
                [
                    "generated/basic-instrument-sample.xm",
                    "generated/instrument-metadata-matrix.xm",
                    "generated/instrument-sustained-defaults.xm",
                    "generated/multi-pattern-loop-boundary.xm",
                ],
            )
            self.assertEqual(
                (output_dir / "generated" / "basic-instrument-sample.xm").read_bytes(),
                generator.basic_instrument_sample_xm_bytes(),
            )
            self.assertEqual(
                (output_dir / "generated" / "multi-pattern-loop-boundary.xm").read_bytes(),
                generator.multi_pattern_loop_boundary_xm_bytes(),
            )
            self.assertEqual(
                (output_dir / "generated" / "instrument-sustained-defaults.xm").read_bytes(),
                generator.fixture_xm_bytes(generator.fixture_manifest(), "instrument-sustained-defaults.xm"),
            )
            self.assertEqual(list(output_dir.rglob("*.wav")), [])
            self.assertEqual(list(output_dir.rglob("*.jsonl")), [])
            self.assertEqual(list(output_dir.rglob("*.trace")), [])

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
            self.assertFalse((output_dir / "generated" / "multi-pattern-loop-boundary.xm").exists())
            self.assertFalse((output_dir / "generated" / "instrument-sustained-defaults.xm").exists())
            self.assertFalse((output_dir / "generated" / "instrument-metadata-matrix.xm").exists())
            self.assertEqual(list(output_dir.rglob("*.wav")), [])
            self.assertEqual(list(output_dir.rglob("*.jsonl")), [])

    def test_write_manifest_and_xm_to_temporary_output_dir(self):
        generator = load_module()

        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "pack"
            manifest_path = generator.write_source_manifest(output_dir)
            generator.write_xm_fixture(output_dir)
            files = sorted(path.relative_to(output_dir).as_posix() for path in output_dir.rglob("*") if path.is_file())

            self.assertEqual(
                files,
                [
                    "generated/basic-instrument-sample.xm",
                    "generated/instrument-metadata-matrix.xm",
                    "generated/instrument-sustained-defaults.xm",
                    "generated/multi-pattern-loop-boundary.xm",
                    "source/basic-instrument-sample.manifest.json",
                ],
            )
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            fixtures = {fixture["name"]: fixture for fixture in manifest["fixtures"]}
            self.assertEqual(fixtures["basic-instrument-sample.xm"]["xm_output"], "generated/basic-instrument-sample.xm")
            self.assertEqual(
                fixtures["basic-instrument-sample.xm"]["xm_sha256"],
                hashlib.sha256((output_dir / "generated" / "basic-instrument-sample.xm").read_bytes()).hexdigest(),
            )
            self.assertEqual(
                fixtures["multi-pattern-loop-boundary.xm"]["xm_output"],
                "generated/multi-pattern-loop-boundary.xm",
            )
            self.assertEqual(
                fixtures["multi-pattern-loop-boundary.xm"]["xm_sha256"],
                hashlib.sha256((output_dir / "generated" / "multi-pattern-loop-boundary.xm").read_bytes()).hexdigest(),
            )
            self.assertEqual(
                fixtures["instrument-sustained-defaults.xm"]["xm_sha256"],
                hashlib.sha256((output_dir / "generated" / "instrument-sustained-defaults.xm").read_bytes()).hexdigest(),
            )
            self.assertEqual(
                fixtures["instrument-metadata-matrix.xm"]["xm_sha256"],
                hashlib.sha256((output_dir / "generated" / "instrument-metadata-matrix.xm").read_bytes()).hexdigest(),
            )
            self.assertEqual(list(output_dir.rglob("*.wav")), [])
            self.assertEqual(list(output_dir.rglob("*.log")), [])

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
                    "xm:basic-instrument-sample.xm": "generated/basic-instrument-sample.xm",
                    "xm:multi-pattern-loop-boundary.xm": "generated/multi-pattern-loop-boundary.xm",
                    "xm:instrument-sustained-defaults.xm": "generated/instrument-sustained-defaults.xm",
                    "xm:instrument-metadata-matrix.xm": "generated/instrument-metadata-matrix.xm",
                },
            )

            with self.assertRaises(ValueError):
                generator.resolved_child(output_dir, "../outside.manifest.json")


if __name__ == "__main__":
    unittest.main()
