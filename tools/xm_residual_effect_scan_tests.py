import json
import tempfile
import unittest
from pathlib import Path

from tools.vtx_diag import residual_scan


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_module():
    return residual_scan


class XMResidualEffectScanTests(unittest.TestCase):
    def test_linear_scan_classifies_requested_focus_buckets(self):
        scan = load_module()
        module = scan.ModuleData(
            label="xm-corpus-001",
            frequency_table="linear",
            channels=2,
            song_length=1,
            default_speed=6,
            default_bpm=125,
            order_table=[0],
            patterns=[
                scan.Pattern(rows=[
                    [cell(scan, note=48, instrument=1), cell(scan, effect_type=0x0A, effect_param=0x00)],
                    [cell(scan, note=50, effect_type=0x03, effect_param=0x04), cell(scan)],
                    [cell(scan, effect_type=0x03, effect_param=0x00), cell(scan, note=48, instrument=1)],
                    [cell(scan, effect_type=0x0A, effect_param=0x0F), cell(scan, effect_type=0x0A, effect_param=0x00)],
                    [cell(scan, effect_type=0x0A, effect_param=0x00), cell(scan, effect_type=0x15, effect_param=0x04)],
                    [cell(scan, effect_type=0x21, effect_param=0x11), cell(scan, volume=0xB4)],
                    [cell(scan, effect_type=0x07, effect_param=0x04), cell(scan, effect_type=0x0E, effect_param=0x72)],
                    [cell(scan, volume=0xA2), cell(scan, volume=0xF3)],
                    [cell(scan, effect_type=0x1B, effect_param=0x22), cell(scan, effect_type=0x14, effect_param=0x01)],
                    [cell(scan, effect_type=0x1B, effect_param=0x00), cell(scan, effect_type=0x14, effect_param=0x09)],
                    [cell(scan, effect_type=0x05, effect_param=0x0F), cell(scan, effect_type=0x05, effect_param=0x00)],
                    [cell(scan, effect_type=0x1F, effect_param=0x44), cell(scan, effect_type=0x20, effect_param=0x55)],
                    [cell(scan, effect_type=0x19, effect_param=0x12), cell(scan, effect_type=0x11, effect_param=0x00)],
                    [cell(scan, effect_type=0x11, effect_param=0x12), cell(scan, effect_type=0x0E, effect_param=0x31)],
                    [cell(scan, effect_type=0x0E, effect_param=0xE2), cell(scan, effect_type=0x1D, effect_param=0x34)],
                    [cell(scan, effect_type=0x0E, effect_param=0x08), cell(scan)],
                ])
            ],
            instruments=[scan.InstrumentEnvelope(), scan.InstrumentEnvelope(volume_enabled=True)],
        )
        group = scan.ScanGroup("linear")

        scan.scan_module(module, [group])
        buckets = group.buckets

        self.assertEqual(buckets["xxy"].count(), 1)
        self.assertEqual(buckets["lxx"].count(), 1)
        self.assertEqual(buckets["lxx"].count("active_channel_envelope_enabled_count"), 1)
        self.assertEqual(buckets["3xx"].count("nonzero_3xx_count"), 1)
        self.assertEqual(buckets["3xx"].count("zero_300_count"), 1)
        self.assertEqual(buckets["3xx"].count("zero_300_memory_reuse_count"), 1)
        self.assertEqual(buckets["axy"].count("a00_count"), 3)
        self.assertEqual(buckets["axy"].count("a00_reuse_if_implemented_count"), 1)
        self.assertEqual(buckets["axy"].count("mixed_nibble_count"), 0)
        self.assertEqual(buckets["7xy"].count("7xy_count"), 1)
        self.assertEqual(buckets["7xy"].count("700_count"), 0)
        self.assertEqual(buckets["7xy"].count("zero_nibble_memory_case_count"), 1)
        self.assertEqual(buckets["7xy"].count("e7x_control_count"), 1)
        self.assertEqual(buckets["vol_a"].count(), 1)
        self.assertEqual(buckets["vol_b"].count(), 1)
        self.assertEqual(buckets["vol_f"].count(), 1)
        self.assertEqual(buckets["rxy"].count("applied_count"), 1)
        self.assertEqual(buckets["rxy"].count("no_op_effect_memory_deferred_count"), 1)
        self.assertEqual(buckets["kxx"].count("applied_count"), 1)
        self.assertEqual(buckets["kxx"].count("out_of_row_no_op_count"), 1)
        self.assertEqual(buckets["5xy"].count("applied_count"), 1)
        self.assertEqual(buckets["5xy"].count("no_target_count"), 1)
        self.assertEqual(buckets["pxy"].count("detected_count"), 1)
        self.assertEqual(buckets["hxy"].count("detected_count"), 2)
        self.assertEqual(buckets["hxy"].count("h00_no_op_count"), 1)
        self.assertEqual(buckets["hxy"].count("both_nibbles_nonzero_count"), 1)
        self.assertEqual(buckets["e3x"].count("detected_count"), 1)
        self.assertEqual(buckets["eex"].count("detected_count"), 1)
        self.assertEqual(buckets["txy"].count("detected_count"), 1)
        self.assertEqual(buckets["e0x"].count("detected_count"), 1)
        self.assertEqual(buckets["unknown"].count("vxx_count"), 1)
        self.assertEqual(buckets["unknown"].count("wxx_count"), 1)
        self.assertEqual(
            scan.recommend_next_pr(group),
            " ".join((
                scan.BACKEND_FREEZE_NEXT_PR_RECOMMENDATION,
                scan.BACKEND_FREEZE_PRIORITIZATION_NOTE,
                scan.BACKEND_FREEZE_PROMOTION_NOTE,
            )),
        )

    def test_recommendation_treats_completed_foundations_as_low_priority(self):
        scan = load_module()
        group = scan.ScanGroup("linear")
        group.bucket("axy").add(
            "xm-corpus-001",
            scan.Coordinate("xm-corpus-001", "linear", 0, 0, 0, 0),
            metric="a00_reuse_if_implemented_count",
            amount=1000,
        )
        group.bucket("xxy").add(
            "xm-corpus-002",
            scan.Coordinate("xm-corpus-002", "linear", 0, 0, 0, 0),
        )

        freeze_recommendation = " ".join((
            scan.BACKEND_FREEZE_NEXT_PR_RECOMMENDATION,
            scan.BACKEND_FREEZE_PRIORITIZATION_NOTE,
            scan.BACKEND_FREEZE_PROMOTION_NOTE,
        ))
        self.assertEqual(scan.recommend_next_pr(group), freeze_recommendation)
        self.assertIn("A00 memory is supported", scan.status_note("axy", {}))

        group.bucket("vol_f").add(
            "xm-corpus-003",
            scan.Coordinate("xm-corpus-003", "linear", 0, 0, 0, 0),
        )
        self.assertEqual(scan.recommend_next_pr(group), freeze_recommendation)
        self.assertIn("Implemented, parity-watch", scan.status_note("vol_f", {}))

    def test_recommendation_freezes_completed_and_parity_watch_buckets(self):
        scan = load_module()
        group = scan.ScanGroup("linear")
        for key in ("lxx", "kxx", "5xy", "rxy", "vol_f"):
            group.bucket(key).add(
                "xm-corpus-001",
                scan.Coordinate("xm-corpus-001", "linear", 0, 0, 0, 0),
            )

        recommendation = scan.recommend_next_pr(group)

        self.assertIn("No behavior-changing XM effect PR is recommended", recommendation)
        self.assertIn("docs/xm-effect-support.md", recommendation)
        self.assertIn("freeze-exit criterion", recommendation)
        self.assertNotIn("Minimal Lxx", recommendation)
        self.assertNotIn("Tone Portamento Foundation", recommendation)
        self.assertIn("R00 memory refinement is parked", scan.status_note("rxy", {}))

    def test_amiga_scan_keeps_pitch_residuals_in_parity_watch_bucket(self):
        scan = load_module()
        module = scan.ModuleData(
            label="xm-corpus-036",
            frequency_table="amiga",
            channels=1,
            song_length=1,
            default_speed=6,
            default_bpm=125,
            order_table=[0],
            patterns=[
                scan.Pattern(rows=[
                    [cell(scan, note=48, instrument=1)],
                    [cell(scan, effect_type=0x02, effect_param=0x04)],
                    [cell(scan, note=50, effect_type=0x03, effect_param=0x04)],
                    [cell(scan, note=52, effect_type=0x05, effect_param=0x01)],
                    [cell(scan, effect_type=0x21, effect_param=0x21)],
                    [cell(scan, volume=0xF4)],
                ])
            ],
            instruments=[scan.InstrumentEnvelope(), scan.InstrumentEnvelope()],
        )
        group = scan.ScanGroup("amiga")

        scan.scan_module(module, [group])
        bucket = group.bucket("amiga")

        self.assertEqual(bucket.count("amiga_2xx_count"), 1)
        self.assertEqual(bucket.count("amiga_3xx_count"), 1)
        self.assertEqual(bucket.count("amiga_xxy_count"), 1)
        self.assertEqual(bucket.count("amiga_volume_column_fxx_count"), 1)
        self.assertEqual(group.bucket("3xx").count("unsupported_frequency_table_count"), 0)
        self.assertEqual(group.bucket("3xx").count("applied_or_applyable_count"), 1)
        self.assertEqual(bucket.count("amiga_5xy_count"), 1)
        self.assertEqual(group.bucket("5xy").count("unsupported_frequency_table_count"), 1)

    def test_public_tremolo_fixture_reports_implemented_parent_and_controls(self):
        scan = load_module()
        module = scan.parse_xm_module(
            REPO_ROOT / "tests/reference-xm/generated/tremolo-effects.xm",
            "xm-corpus-001",
            "linear",
        )
        group = scan.ScanGroup("linear")
        scan.scan_module(module, [group])

        bucket = group.bucket("7xy")
        self.assertEqual(bucket.count("7xy_count"), 37)
        self.assertEqual(bucket.count("e7x_control_count"), 8)
        self.assertEqual(bucket.count("700_count"), 26)
        self.assertEqual(bucket.count("zero_nibble_memory_case_count"), 28)
        self.assertEqual(set(bucket.family_counts), {f"E7{x:X}" for x in range(8)})
        note = scan.status_note("7xy", dict(bucket.counts))
        self.assertIn("Implemented, parity-watch", note)
        self.assertIn("memory", note)
        self.assertNotIn("deferred", note.lower())

    def test_all_tremolo_controls_and_cold_zero_memory_remain_occurrence_counts(self):
        scan = load_module()
        rows = [[cell(scan, effect_type=0x07, effect_param=0)]]
        for control in range(16):
            rows.extend([
                [cell(scan, effect_type=0x0E, effect_param=0x70 | control)],
                [cell(scan, effect_type=0x07, effect_param=0x48)],
            ])
        group = scan.ScanGroup("linear")
        scan.scan_module(module_with_rows(scan, rows), [group])

        counts = group.bucket("7xy").counts
        self.assertEqual(counts["7xy_count"], 17)
        self.assertEqual(counts["e7x_control_count"], 16)
        self.assertEqual(counts["700_count"], 1)
        self.assertEqual(counts["zero_nibble_memory_case_count"], 1)
        self.assertNotIn("applied_count", counts)

    def test_public_amiga_3xx_fixture_keeps_300_memory_without_unsupported_gate(self):
        scan = load_module()
        module = scan.parse_xm_module(
            REPO_ROOT / "tests/reference-xm/generated/portamento-scaling-amiga.xm",
            "xm-corpus-001",
            "amiga",
        )
        group = scan.ScanGroup("amiga")
        scan.scan_module(module, [group])

        bucket = group.bucket("3xx")
        self.assertEqual(bucket.count("nonzero_3xx_count"), 1)
        self.assertEqual(bucket.count("zero_300_count"), 1)
        self.assertEqual(bucket.count("applied_or_applyable_count"), 2)
        self.assertEqual(bucket.count("zero_300_memory_reuse_count"), 1)
        self.assertEqual(bucket.count("unsupported_frequency_table_count"), 0)
        self.assertEqual(group.bucket("amiga").count("amiga_3xx_count"), 2)

    def test_3xx_residual_states_are_preserved_in_both_supported_frequency_modes(self):
        scan = load_module()
        rows = [
            [cell(scan, effect_type=0x03)],
            [cell(scan, note=48, instrument=1)],
            [cell(scan, effect_type=0x03)],
            [cell(scan, note=50, effect_type=0x03)],
            [cell(scan, note=52, effect_type=0x03, effect_param=0x04)],
            [cell(scan, effect_type=0x03)],
        ]
        for frequency_table in ("linear", "amiga"):
            with self.subTest(frequency_table=frequency_table):
                group = scan.ScanGroup(frequency_table)
                scan.scan_module(module_with_rows(scan, rows, frequency_table), [group])
                bucket = group.bucket("3xx")
                self.assertEqual(bucket.count("no_active_count"), 1)
                self.assertEqual(bucket.count("no_target_count"), 1)
                self.assertEqual(bucket.count("missing_memory_count"), 1)
                self.assertEqual(bucket.count("applied_or_applyable_count"), 2)
                self.assertEqual(bucket.count("zero_300_memory_reuse_count"), 1)
                self.assertEqual(bucket.count("unsupported_frequency_table_count"), 0)

        group = scan.ScanGroup("unknown")
        scan.scan_module(module_with_rows(scan, rows, "unknown"), [group])
        self.assertEqual(group.bucket("3xx").count("unsupported_frequency_table_count"), 4)

    def test_gap_triage_recognizes_tremolo_without_promoting_other_parents(self):
        scan = load_module()
        with tempfile.TemporaryDirectory() as directory:
            label_map = Path(directory) / "public-map.json"
            label_map.write_text(json.dumps({"entries": [{
                "label": "xm-corpus-001",
                "path": str(REPO_ROOT / "tests/reference-xm/generated/tremolo-effects.xm"),
            }]}), encoding="utf-8")
            report = scan.build_scan(label_map)
        triage = scan.build_gap_triage(report, REPO_ROOT / "docs/xm-effect-support.md")
        targets = {target["key"]: target for target in triage["targets"]}

        for key in ("7xy", "e7x"):
            with self.subTest(key=key):
                self.assertEqual(targets[key]["c_mixer_adapter_implementation_exists"], "yes")
                self.assertEqual(targets[key]["recommended_priority"], "implemented/parity-watch")
                self.assertEqual(targets[key]["current_adapter_summary"], "coverage not provided")
        for key in ("pxy", "vol_a", "vol_b", "eex", "txy"):
            self.assertEqual(targets[key]["c_mixer_adapter_implementation_exists"], "no")
        self.assertEqual(triage["schema_version"], 1)
        self.assertNotIn("7xy/E7x,", triage["answers"]["surgical_legacy_ports"])
        self.assertIn("Amiga", triage["answers"]["three_xx_memory_gap"])
        self.assertIn("implemented", triage["answers"]["seven_xy_before_amiga"])


def cell(module, note=0, instrument=0, volume=0, effect_type=0, effect_param=0):
    return module.Cell(note=note, instrument=instrument, volume=volume, effect_type=effect_type, effect_param=effect_param)


def module_with_rows(scan, rows, frequency_table="linear"):
    return scan.ModuleData(
        label="xm-corpus-001", frequency_table=frequency_table, channels=1,
        song_length=1, default_speed=6, default_bpm=125, order_table=[0],
        patterns=[scan.Pattern(rows=rows)],
        instruments=[scan.InstrumentEnvelope(), scan.InstrumentEnvelope()],
    )


if __name__ == "__main__":
    unittest.main()
