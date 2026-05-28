import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "update-private-xm-corpus-label-map.py"


def load_module():
    spec = importlib.util.spec_from_file_location("private_xm_corpus_label_map", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class PrivateXMCorpusLabelMapTests(unittest.TestCase):
    def test_update_preserves_labels_enriches_metadata_and_redacts_summary(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            existing = directory / "existing.xm"
            new = directory / "new.xm"
            existing.write_bytes(make_xm(tracker_name="Tracker A", flags=1, channels=4, sample_counts=[0]))
            new.write_bytes(make_xm(tracker_name="Tracker B", version=0x0102, flags=0, channels=3, sample_counts=[1, 2]))
            map_path = directory / "label-map.json"
            map_path.write_text(
                json.dumps({"entries": [{"label": "xm-corpus-001", "filename": existing.name, "path": str(existing)}]}),
                encoding="utf-8",
            )

            label_map, new_labels = module.update_label_map(directory, map_path)
            summary = module.build_summary(label_map, new_labels)
            markdown_path = directory / "summary.md"
            module.write_markdown(markdown_path, summary)
            markdown = markdown_path.read_text(encoding="utf-8")

            self.assertEqual(new_labels, ["xm-corpus-002"])
            self.assertEqual([entry["label"] for entry in label_map["entries"]], ["xm-corpus-001", "xm-corpus-002"])
            self.assertEqual(label_map["entries"][0]["stable_anonymized_label"], "xm-corpus-001")
            self.assertEqual(label_map["entries"][0]["frequency_table"], "linear")
            self.assertEqual(label_map["entries"][1]["frequency_table"], "amiga")
            self.assertEqual(label_map["entries"][1]["sample_count"], 3)
            self.assertEqual(summary["frequency_table_counts"], {"amiga": 1, "linear": 1})
            self.assertEqual(summary["amiga_frequency_table_labels"], ["xm-corpus-002"])
            self.assertIn("XM version 1.02", markdown)
            self.assertIn("channel count 3", markdown)
            self.assertNotIn(str(new), markdown)
            self.assertNotIn(new.name, markdown)


def make_xm(tracker_name, version=0x0104, flags=1, channels=4, sample_counts=None):
    sample_counts = [0] if sample_counts is None else sample_counts
    data = bytearray()
    data.extend(b"Extended Module: ")
    data.extend(fixed("synthetic", 20))
    data.append(0x1A)
    data.extend(fixed(tracker_name, 20))
    put16(data, version)
    put32(data, 276)
    for value in (1, 0, channels, 1, len(sample_counts), flags, 6, 125):
        put16(data, value)
    data.extend(bytes([0] * 256))
    put32(data, 9)
    data.append(0)
    put16(data, 64)
    put16(data, 0)
    for sample_count in sample_counts:
        append_instrument(data, sample_count)
    return bytes(data)


def append_instrument(data, sample_count):
    if sample_count == 0:
        put32(data, 29)
        data.extend(fixed("instrument", 22))
        data.append(0)
        put16(data, 0)
        return
    put32(data, 263)
    data.extend(fixed("instrument", 22))
    data.append(0)
    put16(data, sample_count)
    put32(data, 40)
    data.extend(bytes(230))
    for _ in range(sample_count):
        data.extend(bytes(18))
        data.extend(fixed("sample", 22))


def fixed(value, length):
    return value.encode("ascii")[:length].ljust(length, b"\x00")


def put16(data, value):
    data.extend(int(value).to_bytes(2, "little"))


def put32(data, value):
    data.extend(int(value).to_bytes(4, "little"))


if __name__ == "__main__":
    unittest.main()
