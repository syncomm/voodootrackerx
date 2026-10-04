import contextlib
import hashlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.private_xm_corpus_label_map_tests import make_xm
from tools.vtx_diag import corpus_inventory as inventory, corpus_map, residual_scan
from tools.vtx_diag.cli import main


def synthetic_xm(*, flags=1, patterns=None, orders=(0, 0), volumes=(16, 64, 0, 32), channels=2):
    """Generate local test bytes, including an empty quiet slot and rich raw headers."""
    data = bytearray(make_xm("PRIVATE TRACKER", flags=flags, channels=channels, sample_counts=[]))[:336]
    data[17:37] = b"PRIVATE MODULE TITLE"
    patterns = [(2, bytes((49, 1, 0xA4, 14, 0x10, 0, 1, 0xD0, 14, 0xE1,
                           50, 0, 0xB0, 27, 0, 97, 0, 0, 33, 0x10)))] if patterns is None else patterns
    for offset, value in ((64, len(orders)), (66, 1), (70, len(patterns)), (72, 1), (76, 0), (78, 31)):
        data[offset:offset + 2] = value.to_bytes(2, "little")
    data[80:336] = bytes(orders).ljust(256, b"\0")
    for rows, payload in patterns:
        data.extend((9).to_bytes(4, "little") + b"\0" + rows.to_bytes(2, "little") + len(payload).to_bytes(2, "little") + payload)
    header = bytearray(263)
    header[0:4] = (263).to_bytes(4, "little")
    header[4:26] = b"PRIVATE INSTRUMENT".ljust(22, b"\0")
    header[27:29] = len(volumes).to_bytes(2, "little")
    header[29:33] = (40).to_bytes(4, "little")
    for offset, values in ((129, (0, 64, 3, 40)), (177, (0, 32, 4, 48))):
        header[offset:offset + 8] = b"".join(value.to_bytes(2, "little") for value in values)
    header[225:227] = b"\2\2"
    header[233:239] = bytes((7, 7, 2, 3, 4, 5))
    header[239:241] = (256).to_bytes(2, "little")
    data.extend(header)
    payloads = bytearray()
    for index, volume in enumerate(volumes):
        sample = bytearray(40)
        length = 0 if index == 3 else 8
        sample[0:4] = length.to_bytes(4, "little")
        sample[4:8] = (0 if index == 1 else 2).to_bytes(4, "little")
        sample[8:12] = (length if index == 1 else 2).to_bytes(4, "little")
        sample[12:17] = bytes((volume, 255 if index == 0 else 0, (18, 1, 0, 0)[index % 4], (64, 128, 255, 128)[index % 4], 1 if index == 0 else 0))
        sample[18:40] = b"PRIVATE SAMPLE".ljust(22, b"\0")
        data.extend(sample)
        payloads.extend(bytes(length))
    return bytes(data + payloads)


class CorpusInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.map = self.directory / "map.json"
        self.output = self.directory / "inventory.json"

    def sources(self, modules):
        entries = []
        for label, data in modules:
            source = self.directory / f"PRIVATE-SOURCE-{label}.xm"
            source.write_bytes(data)
            entries.append({"label": label, "path": str(source), "frequency_table": "linear", "private_extra": "PRIVATE EXTRA"})
        self.map.write_text(json.dumps({"entries": entries}), encoding="utf-8")
        return entries

    def invoke(self, *arguments):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = main(["corpus_map", *map(str, arguments)])
        return code, stdout.getvalue(), stderr.getvalue()

    def enrich(self):
        result = self.invoke("enrich", "--label-map", self.map, "--output", self.output)
        self.assertEqual(result[0], 0, result[2])
        return json.loads(self.output.read_text())

    def select(self, *filters):
        result = self.invoke("select", "--inventory", self.output, "--json", *filters)
        self.assertEqual(result[0], 0, result[2])
        return json.loads(result[1])["entries"]

    def test_deterministic_labels_hash_duplicates_redaction_and_unchanged_inputs(self):
        data = synthetic_xm()
        sources = self.sources([("xm-corpus-010", data), ("xm-corpus-002", data), ("xm-corpus-003", synthetic_xm(flags=0))])
        before = {path: path.read_bytes() for path in (self.map, *(Path(item["path"]) for item in sources))}
        first = self.enrich()
        serialized = self.output.read_bytes()
        self.assertEqual(first, self.enrich())
        self.assertEqual(serialized, self.output.read_bytes())
        self.assertEqual([entry["label"] for entry in first["entries"]], ["xm-corpus-002", "xm-corpus-003", "xm-corpus-010"])
        entry = first["entries"][0]
        self.assertEqual((entry["sha256"], entry["file_size_bytes"]), (hashlib.sha256(data).hexdigest(), len(data)))
        self.assertEqual(first["duplicate_groups"], [{"sha256": entry["sha256"], "labels": ["xm-corpus-002", "xm-corpus-010"]}])
        self.assertFalse(first["entries"][1]["frequency_table_matches_map"])
        self.assertEqual(first["entries"][1]["frequency_table"], "amiga")
        output = serialized.decode() + self.invoke("select", "--inventory", self.output)[1]
        for secret in ("PRIVATE", str(self.directory), "path", "filename", "title", "tracker_name", "generated_at", "G01", "implemented", "deferred"):
            self.assertNotIn(secret, output)
        for path, value in before.items():
            self.assertEqual(path.read_bytes(), value)
        self.assertEqual({path.name for path in self.directory.iterdir()}, {self.map.name, self.output.name, *(Path(item["path"]).name for item in sources)})

    def test_structure_represented_quiet_headers_pan_loops_and_instruments(self):
        self.sources([("xm-corpus-001", synthetic_xm())])
        entry = self.enrich()["entries"][0]
        for key, value in {"channel_count": 2, "instrument_count": 1, "declared_sample_count": 4,
                           "represented_sample_count": 3, "pattern_count": 1, "order_count": 2, "restart_position": 1,
                           "initial_speed": 0, "initial_bpm": 31, "allocated_row_count": 2, "listed_order_row_count": 4}.items():
            self.assertEqual(entry[key], value, key)
        declared, represented = entry["declared_samples"], entry["represented_samples"]
        self.assertEqual(declared["positive_quiet_header_count"], 2)
        for key, value in {"positive_quiet_header_count": 1, "zero_volume_header_count": 1, "full_volume_header_count": 1,
                           "noncenter_sample_pan_count": 2, "sixteen_bit_count": 1, "eight_bit_count": 2,
                           "ping_pong_loop_count": 1, "forward_loop_count": 1, "one_shot_count": 1,
                           "nonzero_relative_note_count": 1, "nonzero_finetune_count": 1}.items():
            self.assertEqual(represented[key], value, key)
        self.assertEqual(represented["sample_header_volume_histogram"], {"0": 1, "16": 1, "64": 1})
        self.assertEqual(declared["zero_length_slot_count"], 1)
        self.assertEqual(represented["zero_length_slot_count"], 0)
        self.assertEqual(represented["loop_start_bytes_range"], {"min": 0, "max": 2})
        instruments = entry["instruments"]
        for key in ("instruments_with_volume_envelope", "instruments_with_panning_envelope", "nonneutral_volume_envelope_count",
                    "nonneutral_panning_envelope_count", "volume_sustain_flag_count", "volume_loop_flag_count",
                    "panning_sustain_flag_count", "panning_loop_flag_count", "nonzero_fadeout_count", "nonzero_autovibrato_count"):
            self.assertEqual(instruments[key], 1, key)
        self.assertEqual(instruments["waveform_histogram"], {"2": 1})
        self.assertEqual(entry["cell_shapes"]["normal_note_cells"], 2)
        self.assertEqual(entry["cell_shapes"]["note_only_cells"], 1)
        self.assertEqual(entry["cell_shapes"]["instrument_only_cells"], 1)
        self.assertEqual(entry["cell_shapes"]["key_off_cells"], 1)
        self.assertEqual(entry["vtx_parse_status"], "not_checked")
        self.assertIsNone(entry["vtx_admitted"])

    def test_effect_families_exact_forms_zero_nibbles_coordinates_and_order_weights(self):
        commands = [(code, 0) for code in (*range(14), 16, 17, 20, 21, 25, 27, 29)]
        commands += [(14, value) for value in range(256)]
        commands += [(15, value) for value in (0, 1, 31, 32, 255)]
        commands += [(33, value) for value in (16, 17, 32, 33, 144)]
        commands += [(code, value) for code in (4, 7, 27) for value in (1, 16)] + [(254, 42)]
        payload = b"".join(bytes((0, 0, 0, code, value)) for code, value in commands)
        self.sources([("xm-corpus-001", synthetic_xm(patterns=[(len(commands), payload)], channels=1))])
        # Split the >256 cells across channels to retain valid 1.04 dimensions.
        source = Path(json.loads(self.map.read_text())["entries"][0]["path"])
        padded = payload + bytes(5 * (len(commands) % 2))
        source.write_bytes(synthetic_xm(patterns=[((len(commands) + 1) // 2, padded)], channels=2))
        effects = self.enrich()["entries"][0]["effects"]
        for form in ("000", "100", "200", "300", "400", "500", "600", "700", "800", "900", "A00", "B00", "C00", "D00",
                     "G00", "H00", "K00", "L00", "P00", "R00", "T00", "E10", "E20", "E90", "EA0", "EB0", "X10", "X20"):
            self.assertGreater(effects["exact_forms"][form]["stored_cell_count"], 0, form)
        for family in ("F00", "F01...F1F", "F20...FFF", *(f"E{i:X}x" for i in range(16)), "X1x", "X2x"):
            self.assertIn(family, effects["families"])
        self.assertEqual(effects["families"]["F01...F1F"]["parameter_histogram"], {"01": 1, "1F": 1})
        self.assertEqual(effects["families"]["E1x"]["stored_cell_count"], 16)
        self.assertEqual(effects["families"]["E1x"]["listed_order_cell_count"], 32)
        self.assertEqual(len(effects["families"]["E1x"]["first_stored_coordinates"]), 3)
        self.assertEqual(effects["families"]["E1x"]["first_stored_coordinates"][0], {"pattern": 0, "row": 18, "channel": 1})
        for form in ("40y", "4x0", "70y", "7x0", "R0y", "Rx0"):
            self.assertEqual(effects["nibble_forms"][form]["stored_cell_count"], 1)
        self.assertEqual(self.select("--effect", "EEx", "--effect-form", "X10", "--effect", "byte-FE")[0]["label"], "xm-corpus-001")
        self.assertEqual(self.select("--effect-form", "byte-FE:2A")[0]["label"], "xm-corpus-001")
        self.assertEqual(self.select("--effect-form", "R0y", "--effect-form", "Rx0")[0]["label"], "xm-corpus-001")

    def test_volume_ranges_histograms_and_zero_forms(self):
        values = [*range(16, 81), *range(96, 256), 0, 1, 95]
        payload = b"".join(bytes((0x84, value)) for value in values)
        self.sources([("xm-corpus-001", synthetic_xm(patterns=[(len(values), payload)], channels=1))])
        volume = self.enrich()["entries"][0]["volume_column"]
        self.assertEqual(volume["families"]["10...50"]["stored_cell_count"], 65)
        for nibble in range(6, 16):
            family = volume["families"][f"{nibble:X}x"]
            self.assertEqual(family["stored_cell_count"], 16)
            self.assertEqual(family["zero_low_nibble_count"], 1)
            for amount in range(16):
                self.assertEqual(volume["exact_forms"][f"{nibble:X}{amount:X}"]["listed_order_cell_count"], 2)
        self.assertEqual(self.select("--volume-command", "Ax", "--volume-command", "10...50")[0]["label"], "xm-corpus-001")

    def test_empty_packed_explicit_zero_and_zero_row_patterns(self):
        self.sources([("xm-corpus-001", synthetic_xm(patterns=[(2, b""), (1, bytes((0x80, 0x98, 0, 0))), (0, b"")], orders=(0, 1, 1, 2)))])
        entry = self.enrich()["entries"][0]
        self.assertEqual(entry["zero_row_pattern_count"], 1)
        self.assertEqual(entry["cell_shapes"]["empty_cells"], 6)
        self.assertEqual(entry["cell_shapes"]["explicit_effect_column_cells"], 1)
        self.assertEqual(entry["effects"]["exact_forms"]["000"], {"stored_cell_count": 1, "listed_order_cell_count": 2})

    def test_per_module_failures_isolate_truncated_cells_instruments_payload_and_old_layout(self):
        truncated = synthetic_xm(patterns=[(1, b"\x81")], channels=1)
        old_layout = bytearray(synthetic_xm())
        old_layout[58:60] = b"\2\1"
        self.sources([("xm-corpus-001", b"not XM"), ("xm-corpus-002", truncated), ("xm-corpus-003", synthetic_xm()[:-1]),
                      ("xm-corpus-004", bytes(old_layout)), ("xm-corpus-005", synthetic_xm())])
        result = self.enrich()
        self.assertEqual([entry["static_failure_code"] for entry in result["entries"]],
                         ["invalid_xm_header", "truncated_pattern_cells", "truncated_xm_structure", "unsupported_xm_layout", None])
        self.assertEqual([entry["label"] for entry in self.select()], ["xm-corpus-005"])
        sources = json.loads(self.map.read_text())["entries"]
        Path(sources[-1]["path"]).unlink()
        self.assertEqual(self.enrich()["entries"][-1]["static_failure_code"], "source_unreadable")

    def test_invalid_orders_leave_listed_counts_unavailable_and_stored_facts_intact(self):
        self.sources([("xm-corpus-001", synthetic_xm(orders=(9,)))])
        entry = self.enrich()["entries"][0]
        self.assertIsNone(entry["listed_order_row_count"])
        self.assertEqual(entry["listed_order_status"], "invalid_pattern_reference")
        self.assertEqual(entry["effects"]["families"]["E1x"]["stored_cell_count"], 1)
        self.assertIsNone(entry["effects"]["families"]["E1x"]["listed_order_cell_count"])

    def test_empty_inventory_and_zero_row_only_module_select_safely(self):
        self.sources([])
        self.assertEqual(self.enrich(), {"schema_version": 1, "entries": [], "duplicate_groups": []})
        self.assertEqual(self.select(), [])
        self.sources([("xm-corpus-001", synthetic_xm(patterns=[(0, b"")]))])
        self.enrich()
        self.assertEqual(self.select()[0]["normal_note_cells"], 0)

    def test_unreadable_symlink_source_is_isolated_and_neutral_traits_are_absent(self):
        sources = self.sources([("xm-corpus-001", synthetic_xm()), ("xm-corpus-002", synthetic_xm(volumes=(64,)))])
        loop = Path(sources[0]["path"])
        loop.unlink()
        loop.symlink_to(loop.name)
        data = bytearray(Path(sources[1]["path"]).read_bytes())
        instrument_at = 336 + 9 + 20
        data[instrument_at + 233:instrument_at + 239] = bytes(6)
        data[instrument_at + 263 + 14] = 0
        data[instrument_at + 263 + 15] = 128
        Path(sources[1]["path"]).write_bytes(data)
        entries = self.enrich()["entries"]
        self.assertEqual(entries[0]["static_failure_code"], "source_unreadable")
        self.assertEqual(entries[1]["instruments"]["nonneutral_volume_envelope_count"], 0)
        for trait in inventory.TRAITS:
            self.assertEqual(self.select("--has-" + trait), [], trait)

    def test_select_traits_mode_conjunction_limits_and_absence(self):
        self.sources([("xm-corpus-001", synthetic_xm()), ("xm-corpus-002", synthetic_xm(flags=0, volumes=(64,)))])
        self.enrich()
        for trait in inventory.TRAITS:
            expected = ["xm-corpus-001"] if trait in ("positive-quiet-header", "forward-loop") else ["xm-corpus-001", "xm-corpus-002"]
            self.assertEqual([entry["label"] for entry in self.select("--has-" + trait)], expected, trait)
        self.assertEqual([entry["label"] for entry in self.select("--frequency-table", "amiga")], ["xm-corpus-002"])
        self.assertEqual(self.select("--frequency-table", "amiga", "--has-positive-quiet-header"), [])
        self.assertEqual(self.select("--min-channels", "3"), [])
        self.assertEqual(self.select("--effect-form", "E20"), [])
        self.assertEqual(len(self.select("--limit", "1")), 1)
        self.assertEqual(self.select("--limit", "0"), [])
        result = self.invoke("select", "--inventory", self.output, "--effect", "PRIVATE INVALID")
        self.assertEqual(result, (1, "", "vtx_diag: invalid_effect_family\n"))

    def test_output_confinement_aliases_inputs_and_atomic_failure(self):
        sources = self.sources([("xm-corpus-001", synthetic_xm())])
        hardlink = self.directory / "alias.json"
        os.link(self.map, hardlink)
        repository_alias = self.directory / "repository-alias"
        repository_alias.symlink_to(inventory.REPO_ROOT, target_is_directory=True)
        for output in (self.map, hardlink, Path(sources[0]["path"]), inventory.REPO_ROOT / "build" / "forbidden-inventory.json", repository_alias / "forbidden.json"):
            with self.subTest(output=output.name):
                result = self.invoke("enrich", "--label-map", self.map, "--output", output)
                self.assertEqual(result[0], 1)
                self.assertEqual(result[1], "")
                self.assertNotIn(str(self.directory), result[2])
        self.output.write_text("previous inventory")
        with mock.patch.object(inventory, "build_inventory", side_effect=inventory.InventoryError("internal_invariant_failure")):
            self.assertEqual(self.invoke("enrich", "--label-map", self.map, "--output", self.output)[0], 1)
        self.assertEqual(self.output.read_text(), "previous inventory")
        blocked = self.directory / "blocked"
        blocked.mkdir()
        result = self.invoke("enrich", "--label-map", self.map, "--output", blocked)
        self.assertEqual(result, (1, "", "vtx_diag: inventory_io_or_json_failure\n"))
        self.assertEqual(set(self.directory.glob("tmp*")), set())

    def test_invalid_map_inventory_and_private_fields_cannot_leak(self):
        for payload in ("{PRIVATE INVALID", "{}", '[{"label":"PRIVATE","path":"PRIVATE"}]',
                        '[{"label":"xm-corpus-001","path":"x"},{"label":"xm-corpus-001","path":"y"}]'):
            self.map.write_text(payload)
            result = self.invoke("enrich", "--label-map", self.map, "--output", self.output)
            self.assertEqual(result[0], 1)
            self.assertNotIn("PRIVATE", result[1] + result[2])
            self.assertFalse(self.output.exists())
        self.sources([("xm-corpus-001", synthetic_xm())])
        data = self.enrich()
        data["entries"][0]["path"] = "PRIVATE"
        data["entries"][0]["title"] = "PRIVATE"
        self.output.write_text(json.dumps(data))
        self.assertNotIn("PRIVATE", self.invoke("select", "--inventory", self.output, "--json")[1])
        data["schema_version"] = 99
        self.output.write_text(json.dumps(data))
        self.assertEqual(self.invoke("select", "--inventory", self.output)[0], 1)

    def test_existing_walkers_return_identical_results_with_observers(self):
        sources = self.sources([("xm-corpus-001", synthetic_xm())])
        path = Path(sources[0]["path"])
        patterns, instruments = [], []
        self.assertEqual(corpus_map.parse_xm(path), corpus_map.parse_xm(path, pattern_observer=lambda *args: patterns.append(args),
                         instrument_observer=lambda *args: instruments.append(args)))
        self.assertEqual(len(patterns), 1)
        self.assertEqual(len(instruments), 1)
        for payload in (b"", b"\x81", b"\0", b"\x98\0\0", bytes((49, 1, 16, 14, 16))):
            observed = []
            self.assertEqual(residual_scan.decode_pattern_cells(payload, 2, 2), residual_scan.decode_pattern_cells(
                payload, 2, 2, observer=lambda *args: observed.append(args)))
            self.assertEqual(len(observed), 4)


if __name__ == "__main__":
    unittest.main()
