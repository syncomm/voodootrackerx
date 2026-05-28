import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "summarize-xm-residual-effect-scan.py"


def load_module():
    spec = importlib.util.spec_from_file_location("xm_residual_effect_scan", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


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
        self.assertEqual(buckets["unknown"].count("vxx_count"), 1)
        self.assertEqual(buckets["unknown"].count("wxx_count"), 1)
        self.assertEqual(scan.recommend_next_pr(group), "Minimal Xxy Extra Fine Portamento")

    def test_recommendation_treats_axy_memory_as_completed_foundation(self):
        scan = load_module()
        group = scan.ScanGroup("linear")
        group.bucket("axy").add(
            "xm-corpus-001",
            scan.Coordinate("xm-corpus-001", 0, 0, 0, 0, "linear"),
            metric="a00_reuse_if_implemented_count",
            amount=1000,
        )
        group.bucket("xxy").add(
            "xm-corpus-002",
            scan.Coordinate("xm-corpus-002", 0, 0, 0, 0, "linear"),
        )

        self.assertEqual(scan.recommend_next_pr(group), "Minimal Xxy Extra Fine Portamento")
        self.assertIn("A00 replay", scan.status_note("axy", {}))

    def test_amiga_scan_keeps_pitch_residuals_in_foundation_bucket(self):
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
                    [cell(scan, effect_type=0x03, effect_param=0x04)],
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
        self.assertEqual(group.bucket("3xx").count("unsupported_frequency_table_count"), 1)


def cell(module, note=0, instrument=0, volume=0, effect_type=0, effect_param=0):
    return module.Cell(note=note, instrument=instrument, volume=volume, effect_type=effect_type, effect_param=effect_param)


if __name__ == "__main__":
    unittest.main()
