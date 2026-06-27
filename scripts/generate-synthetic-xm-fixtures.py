#!/usr/bin/env python3
"""Generate deterministic public-safe synthetic XM fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


GENERATOR_NAME = "scripts/generate-synthetic-xm-fixtures.py"
FIRST_FIXTURE_NAME = "basic-instrument-sample.xm"
FIRST_FIXTURE_SOURCE_MANIFEST = "source/basic-instrument-sample.manifest.json"
FIRST_FIXTURE_XM_OUTPUT = "generated/basic-instrument-sample.xm"
FIRST_FIXTURE_TITLE = "VTX BASIC SAMPLE"
FIRST_FIXTURE_TRACKER_NAME = "VTX SYNTH FIXTURE"
FIRST_FIXTURE_INSTRUMENT_NAME = "BASIC SAMPLE"
FIRST_FIXTURE_SAMPLE_NAME = "SINE64"
FIRST_FIXTURE_CHANNELS = 1
FIRST_FIXTURE_ROWS = 16
FIRST_FIXTURE_SAMPLE_LENGTH = 64
FIRST_FIXTURE_SAMPLE_AMPLITUDE = 48
SECOND_FIXTURE_NAME = "multi-pattern-loop-boundary.xm"
SECOND_FIXTURE_XM_OUTPUT = "generated/multi-pattern-loop-boundary.xm"
SECOND_FIXTURE_TITLE = "VTX LOOP BOUNDARY"
SECOND_FIXTURE_INSTRUMENT_NAME = "BOUNDARY SAMPLE"
SECOND_FIXTURE_SAMPLE_NAME = "BOUNDARY64"
SECOND_FIXTURE_CHANNELS = 1
SECOND_FIXTURE_PATTERNS = 3
SECOND_FIXTURE_ROWS = 4
SECOND_FIXTURE_ORDER_TABLE = [0, 1, 2]
SECOND_FIXTURE_SAMPLE_LENGTH = 64
SECOND_FIXTURE_SAMPLE_AMPLITUDE = 40


def fixture_manifest() -> dict[str, Any]:
    """Return the deterministic public fixture manifest contract."""
    first_fixture_bytes = basic_instrument_sample_xm_bytes()
    second_fixture_bytes = multi_pattern_loop_boundary_xm_bytes()
    return {
        "schema_version": 1,
        "generator": GENERATOR_NAME,
        "writes_binary_xm_by_default": False,
        "writes_reference_renders_by_default": False,
        "artifact_policy": {
            "binary_xm_commits_require_explicit_review": True,
            "generated_wav_json_markdown_logs_stay_under_tmp_by_default": True,
            "private_modules_allowed": False,
            "private_corpus_dependencies_allowed": False,
        },
        "fixture_pack_layout": {
            "source": "source/",
            "generated_xm": "generated/",
            "reference_renders": "reference-renders/",
        },
        "fixtures": [
            {
                "name": FIRST_FIXTURE_NAME,
                "status": "generated",
                "source_manifest": FIRST_FIXTURE_SOURCE_MANIFEST,
                "xm_output": FIRST_FIXTURE_XM_OUTPUT,
                "xm_sha256": hashlib.sha256(first_fixture_bytes).hexdigest(),
                "xm_size_bytes": len(first_fixture_bytes),
                "reference_render_directory": "reference-renders/",
                "purpose": (
                    "One instrument, one sample, simple note events, and real "
                    "synthetic sample payload for parser/editor positive-path tests."
                ),
                "sample_formula": {
                    "format": "signed_8_bit_delta_pcm",
                    "length_frames": 64,
                    "formula": "round(48 * sin(2 * pi * frame / 16))",
                    "loop": None,
                    "normalization": "bounded integer amplitude; no copied sample material",
                },
                "pattern_plan": {
                    "channels": FIRST_FIXTURE_CHANNELS,
                    "rows": FIRST_FIXTURE_ROWS,
                    "events": [
                        {"row": 0, "channel": 0, "note": "C-4", "instrument": 1},
                        {"row": 8, "channel": 0, "note": "key-off"},
                    ],
                },
            },
            {
                "name": SECOND_FIXTURE_NAME,
                "status": "generated",
                "source_manifest": FIRST_FIXTURE_SOURCE_MANIFEST,
                "xm_output": SECOND_FIXTURE_XM_OUTPUT,
                "xm_sha256": hashlib.sha256(second_fixture_bytes).hexdigest(),
                "xm_size_bytes": len(second_fixture_bytes),
                "reference_render_directory": "reference-renders/",
                "purpose": (
                    "Three short patterns and three order positions with simple "
                    "row-0 note triggers for adapter-plan order-boundary traversal "
                    "tests and future adapter-safe pattern-loop design work."
                ),
                "sample_formula": {
                    "format": "signed_8_bit_delta_pcm",
                    "length_frames": 64,
                    "formula": "round(40 * sin(2 * pi * frame / 16))",
                    "loop": None,
                    "normalization": "bounded integer amplitude; no copied sample material",
                },
                "pattern_plan": {
                    "channels": SECOND_FIXTURE_CHANNELS,
                    "pattern_count": SECOND_FIXTURE_PATTERNS,
                    "rows_per_pattern": SECOND_FIXTURE_ROWS,
                    "order_table": SECOND_FIXTURE_ORDER_TABLE,
                    "events": [
                        {"order": 0, "pattern": 0, "row": 0, "channel": 0, "note": "C-4", "instrument": 1},
                        {"order": 1, "pattern": 1, "row": 0, "channel": 0, "note": "E-4", "instrument": 1},
                        {"order": 2, "pattern": 2, "row": 0, "channel": 0, "note": "G-4", "instrument": 1},
                    ],
                },
            }
        ],
    }


def deterministic_json(data: dict[str, Any]) -> str:
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def fixed_ascii(value: str, size: int, padding: int = 0x00) -> bytes:
    encoded = value.encode("ascii")
    if len(encoded) > size:
        encoded = encoded[:size]
    return encoded + bytes([padding]) * (size - len(encoded))


def u16(value: int) -> bytes:
    return int(value).to_bytes(2, "little", signed=False)


def u32(value: int) -> bytes:
    return int(value).to_bytes(4, "little", signed=False)


def generated_sample_values(
    length: int = FIRST_FIXTURE_SAMPLE_LENGTH,
    amplitude: int = FIRST_FIXTURE_SAMPLE_AMPLITUDE,
) -> list[int]:
    return [
        round(amplitude * math.sin(2 * math.pi * frame / 16))
        for frame in range(length)
    ]


def delta_encode_signed_8_bit(values: list[int]) -> bytes:
    encoded = bytearray()
    previous = 0
    for value in values:
        if value < -128 or value > 127:
            raise ValueError(f"sample value out of signed 8-bit range: {value}")
        delta = (value - previous) & 0xFF
        encoded.append(delta)
        previous = value
    return bytes(encoded)


def packed_pattern_data() -> bytes:
    """Return one packed XM pattern with C-4/instrument 1 and a later key-off."""
    rows = []
    for row in range(FIRST_FIXTURE_ROWS):
        if row == 0:
            rows.append(bytes([0x83, 49, 1]))  # note + instrument
        elif row == 8:
            rows.append(bytes([0x81, 97]))  # XM key-off note value
        else:
            rows.append(bytes([0x80]))  # packed cell with no populated fields
    return b"".join(rows)


def packed_multi_pattern_data(pattern_index: int) -> bytes:
    """Return one packed XM pattern for the multi-pattern boundary fixture."""
    note_by_pattern = {
        0: 49,  # C-4
        1: 53,  # E-4
        2: 56,  # G-4
    }
    rows = []
    for row in range(SECOND_FIXTURE_ROWS):
        if row == 0:
            rows.append(bytes([0x83, note_by_pattern[pattern_index], 1]))  # note + instrument
        else:
            rows.append(bytes([0x80]))  # packed cell with no populated fields
    return b"".join(rows)


def basic_instrument_sample_xm_bytes() -> bytes:
    """Build the narrow XM 1.04 subset needed by basic-instrument-sample.xm."""
    data = bytearray()

    data.extend(fixed_ascii("Extended Module: ", 17, padding=0x20))
    data.extend(fixed_ascii(FIRST_FIXTURE_TITLE, 20, padding=0x20))
    data.append(0x1A)
    data.extend(fixed_ascii(FIRST_FIXTURE_TRACKER_NAME, 20, padding=0x20))
    data.extend(u16(0x0104))

    data.extend(u32(276))  # XM song header size, including 256-byte order table.
    data.extend(u16(1))  # song length
    data.extend(u16(0))  # restart position
    data.extend(u16(FIRST_FIXTURE_CHANNELS))
    data.extend(u16(1))  # pattern count
    data.extend(u16(1))  # instrument count
    data.extend(u16(1))  # linear frequency table
    data.extend(u16(6))  # default speed
    data.extend(u16(125))  # default BPM
    data.append(0)  # order table position 0 -> pattern 0
    data.extend(bytes(255))

    pattern = packed_pattern_data()
    data.extend(u32(9))  # pattern header length
    data.append(0)  # packing type
    data.extend(u16(FIRST_FIXTURE_ROWS))
    data.extend(u16(len(pattern)))
    data.extend(pattern)

    instrument = bytearray(263)
    instrument[0:4] = u32(263)
    instrument[4:26] = fixed_ascii(FIRST_FIXTURE_INSTRUMENT_NAME, 22)
    instrument[27:29] = u16(1)
    instrument[29:33] = u32(40)
    data.extend(instrument)

    sample_header = bytearray(40)
    sample_header[0:4] = u32(FIRST_FIXTURE_SAMPLE_LENGTH)
    sample_header[4:8] = u32(0)
    sample_header[8:12] = u32(0)
    sample_header[12] = 64  # volume
    sample_header[13] = 0  # finetune
    sample_header[14] = 0  # one-shot 8-bit sample
    sample_header[15] = 128  # center panning
    sample_header[16] = 0  # relative note
    sample_header[17] = 0
    sample_header[18:40] = fixed_ascii(FIRST_FIXTURE_SAMPLE_NAME, 22)
    data.extend(sample_header)
    data.extend(delta_encode_signed_8_bit(generated_sample_values()))

    return bytes(data)


def multi_pattern_loop_boundary_xm_bytes() -> bytes:
    """Build the small XM 1.04 multi-order traversal fixture."""
    data = bytearray()

    data.extend(fixed_ascii("Extended Module: ", 17, padding=0x20))
    data.extend(fixed_ascii(SECOND_FIXTURE_TITLE, 20, padding=0x20))
    data.append(0x1A)
    data.extend(fixed_ascii(FIRST_FIXTURE_TRACKER_NAME, 20, padding=0x20))
    data.extend(u16(0x0104))

    data.extend(u32(276))  # XM song header size, including 256-byte order table.
    data.extend(u16(len(SECOND_FIXTURE_ORDER_TABLE)))  # song length
    data.extend(u16(0))  # restart position
    data.extend(u16(SECOND_FIXTURE_CHANNELS))
    data.extend(u16(SECOND_FIXTURE_PATTERNS))
    data.extend(u16(1))  # instrument count
    data.extend(u16(1))  # linear frequency table
    data.extend(u16(6))  # default speed
    data.extend(u16(125))  # default BPM
    data.extend(bytes(SECOND_FIXTURE_ORDER_TABLE))
    data.extend(bytes(256 - len(SECOND_FIXTURE_ORDER_TABLE)))

    for pattern_index in range(SECOND_FIXTURE_PATTERNS):
        pattern = packed_multi_pattern_data(pattern_index)
        data.extend(u32(9))  # pattern header length
        data.append(0)  # packing type
        data.extend(u16(SECOND_FIXTURE_ROWS))
        data.extend(u16(len(pattern)))
        data.extend(pattern)

    instrument = bytearray(263)
    instrument[0:4] = u32(263)
    instrument[4:26] = fixed_ascii(SECOND_FIXTURE_INSTRUMENT_NAME, 22)
    instrument[27:29] = u16(1)
    instrument[29:33] = u32(40)
    data.extend(instrument)

    sample_header = bytearray(40)
    sample_header[0:4] = u32(SECOND_FIXTURE_SAMPLE_LENGTH)
    sample_header[4:8] = u32(0)
    sample_header[8:12] = u32(0)
    sample_header[12] = 64  # volume
    sample_header[13] = 0  # finetune
    sample_header[14] = 0  # one-shot 8-bit sample
    sample_header[15] = 128  # center panning
    sample_header[16] = 0  # relative note
    sample_header[17] = 0
    sample_header[18:40] = fixed_ascii(SECOND_FIXTURE_SAMPLE_NAME, 22)
    data.extend(sample_header)
    data.extend(delta_encode_signed_8_bit(generated_sample_values(
        length=SECOND_FIXTURE_SAMPLE_LENGTH,
        amplitude=SECOND_FIXTURE_SAMPLE_AMPLITUDE,
    )))

    return bytes(data)


def resolved_child(output_dir: Path, relative_path: str) -> Path:
    root = output_dir.resolve()
    child = (root / relative_path).resolve()
    try:
        child.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"refusing to write outside output directory: {relative_path}") from exc
    return child


def planned_paths(output_dir: Path) -> dict[str, Path]:
    return {
        "source_manifest": resolved_child(output_dir, FIRST_FIXTURE_SOURCE_MANIFEST),
        "basic_instrument_sample_xm_output": resolved_child(output_dir, FIRST_FIXTURE_XM_OUTPUT),
        "multi_pattern_loop_boundary_xm_output": resolved_child(output_dir, SECOND_FIXTURE_XM_OUTPUT),
        "reference_render_directory": resolved_child(output_dir, "reference-renders"),
    }


def write_source_manifest(output_dir: Path) -> Path:
    path = planned_paths(output_dir)["source_manifest"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(deterministic_json(fixture_manifest()), encoding="utf-8")
    return path


def write_xm_fixture(output_dir: Path) -> list[Path]:
    paths = planned_paths(output_dir)
    fixtures = [
        (paths["basic_instrument_sample_xm_output"], basic_instrument_sample_xm_bytes()),
        (paths["multi_pattern_loop_boundary_xm_output"], multi_pattern_loop_boundary_xm_bytes()),
    ]
    for path, fixture_bytes in fixtures:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(fixture_bytes)
    return [path for path, _ in fixtures]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Print the manifest or explicitly write deterministic synthetic XM fixtures."
    )
    parser.add_argument(
        "--output-dir",
        default="tests/reference-xm",
        type=Path,
        help="Fixture-pack root. Default: tests/reference-xm",
    )
    parser.add_argument(
        "--write-manifest",
        action="store_true",
        help="Write source/basic-instrument-sample.manifest.json under --output-dir.",
    )
    parser.add_argument(
        "--write-xm",
        action="store_true",
        help="Write approved generated XM fixtures under --output-dir.",
    )
    parser.add_argument(
        "--print-paths",
        action="store_true",
        help="Print intended fixture paths relative to the fixture-pack root.",
    )
    args = parser.parse_args(argv)

    paths = planned_paths(args.output_dir)
    if args.print_paths:
        for key in sorted(paths):
            print(f"{key}: {paths[key].relative_to(args.output_dir.resolve())}")
        return 0

    written_paths = []
    if args.write_manifest:
        written_paths.append(write_source_manifest(args.output_dir))
    if args.write_xm:
        written_paths.extend(write_xm_fixture(args.output_dir))
    if written_paths:
        for written in written_paths:
            print(f"Wrote {written.relative_to(args.output_dir.resolve())}")
        return 0

    print(deterministic_json(fixture_manifest()), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
