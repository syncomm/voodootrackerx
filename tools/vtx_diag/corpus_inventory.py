"""Disposable, path-free XM facts observed through the existing diagnostic walkers."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any

from . import corpus_map, residual_scan

SCHEMA_VERSION = 1
REPO_ROOT = Path(__file__).resolve().parents[2]
COORDINATE_LIMIT = 3
NIBBLE_FORMS = ("40y", "4x0", "70y", "7x0", "R0y", "Rx0")
EFFECTS = {i: f"{i:X}{'xy' if i in (0, 4, 5, 6, 7, 10) else 'xx'}" for i in range(14)}
EFFECTS.update({16: "Gxx", 17: "Hxy", 20: "Kxx", 21: "Lxx", 25: "Pxy", 27: "Rxy", 29: "Txy"})
TRAITS = {
    "positive-quiet-header": ("represented_samples", "positive_quiet_header_count"),
    "noncenter-sample-pan": ("represented_samples", "noncenter_sample_pan_count"),
    "forward-loop": ("represented_samples", "forward_loop_count"),
    "ping-pong-loop": ("represented_samples", "ping_pong_loop_count"),
    "volume-envelope": ("instruments", "instruments_with_volume_envelope"),
    "panning-envelope": ("instruments", "instruments_with_panning_envelope"),
    "autovibrato": ("instruments", "nonzero_autovibrato_count"),
}


class InventoryError(ValueError):
    """A fixed, redacted failure category; never carries private input text."""


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise InventoryError(code)


def _load_entries(path: Path, *, inventory: bool = False) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if inventory:
        _require(isinstance(payload, dict) and type(payload.get("schema_version")) is int
                 and payload["schema_version"] == SCHEMA_VERSION, "invalid_inventory_schema")
    entries = payload if isinstance(payload, list) else payload.get("entries") if isinstance(payload, dict) else None
    _require(isinstance(entries, list), "invalid_entries_schema")
    labels = set()
    for entry in entries:
        _require(isinstance(entry, dict), "invalid_entry_schema")
        label = entry.get("label")
        _require(isinstance(label, str) and corpus_map.LABEL_RE.fullmatch(label) is not None
                 and label not in labels, "invalid_or_duplicate_label")
        labels.add(label)
        _require(entry.get("frequency_table", "unknown") in (None, "unknown", "linear", "amiga"), "invalid_frequency_table")
        if not inventory:
            _require(isinstance(entry.get("path"), str) and bool(entry["path"])
                     and "\x00" not in entry["path"], "invalid_source_location")
    return sorted(entries, key=lambda item: (residual_scan.label_number(item["label"]), item["label"]))


def _histogram(values: list[int]) -> dict[str, int]:
    return {str(key): count for key, count in sorted(Counter(values).items())}


def _sample_facts(headers: list[bytes]) -> dict[str, Any]:
    volumes, pans = [header[12] for header in headers], [header[15] for header in headers]
    lengths = [corpus_map.u32(header, 0) for header in headers]
    starts = [corpus_map.u32(header, 4) for header in headers]
    loops = [corpus_map.u32(header, 8) for header in headers]
    modes = [header[14] & 3 for header in headers]
    loop_indices = [i for i, mode in enumerate(modes) if mode in (1, 2)]
    facts = {
        "sample_count": len(headers), "sample_header_volume_histogram": _histogram(volumes),
        "positive_quiet_header_count": sum(0 < value < 64 for value in volumes),
        "zero_volume_header_count": volumes.count(0), "full_volume_header_count": volumes.count(64),
        "out_of_range_volume_header_count": sum(value > 64 for value in volumes),
        "sample_pan_histogram": _histogram(pans), "noncenter_sample_pan_count": sum(value != 128 for value in pans),
        "eight_bit_count": sum(not header[14] & 16 for header in headers),
        "sixteen_bit_count": sum(bool(header[14] & 16) for header in headers),
        "zero_length_slot_count": lengths.count(0), "forward_loop_count": modes.count(1),
        "ping_pong_loop_count": modes.count(2), "one_shot_count": modes.count(0),
        "unknown_loop_type_count": modes.count(3), "type_flags_histogram": _histogram([h[14] for h in headers]),
        "nonzero_relative_note_count": sum(header[16] != 0 for header in headers),
        "nonzero_finetune_count": sum(header[13] != 0 for header in headers),
        "odd_sixteen_bit_length_count": sum(bool(h[14] & 16) and length % 2 != 0 for h, length in zip(headers, lengths)),
        "loop_zero_length_count": sum(loops[i] == 0 for i in loop_indices),
        "loop_start_at_or_past_end_count": sum(starts[i] >= lengths[i] for i in loop_indices),
        "loop_end_past_sample_count": sum(starts[i] + loops[i] > lengths[i] for i in loop_indices),
        "loop_one_frame_count": sum(loops[i] == (2 if headers[i][14] & 16 else 1) for i in loop_indices),
        "unaligned_sixteen_bit_loop_count": sum(bool(headers[i][14] & 16) and bool((starts[i] | loops[i]) & 1) for i in loop_indices),
    }
    for name, values in (("start_bytes", starts), ("length_bytes", loops)):
        selected = [values[i] for i in loop_indices]
        facts[f"loop_{name}_range"] = {"min": min(selected, default=None), "max": max(selected, default=None)}
    return facts


def _instrument_facts(headers: list[bytes]) -> dict[str, Any]:
    counts: Counter = Counter()
    histograms: dict[str, list[int]] = {key: [] for key in ("waveform", "sweep", "depth", "rate", "fadeout")}
    for header in headers:
        if len(header) < 241:
            counts["headers_without_envelope_metadata"] += 1
            continue
        for name, point_at, count_at, flags_at, neutral in (("volume", 129, 225, 233, 64), ("panning", 177, 226, 234, 32)):
            points, flags = header[count_at], header[flags_at]
            _require(points <= 12, "invalid_envelope_point_count")
            counts[f"instruments_with_{name}_envelope"] += bool(flags & 1) and points > 0
            counts[f"{name}_enable_flag_count"] += bool(flags & 1)
            counts[f"{name}_sustain_flag_count"] += bool(flags & 2)
            counts[f"{name}_loop_flag_count"] += bool(flags & 4)
            counts[f"nonneutral_{name}_envelope_count"] += bool(flags & 1) and any(
                corpus_map.u16(header, point_at + i * 4 + 2) != neutral for i in range(points))
        auto = list(header[235:239])
        counts["nonzero_autovibrato_count"] += any(auto)
        for name, value in zip(("waveform", "sweep", "depth", "rate"), auto):
            histograms[name].append(value)
        fadeout = corpus_map.u16(header, 239)
        histograms["fadeout"].append(fadeout)
        counts["nonzero_fadeout_count"] += fadeout != 0
    names = ["headers_without_envelope_metadata", "nonzero_autovibrato_count", "nonzero_fadeout_count"]
    for name in ("volume", "panning"):
        names.extend((f"instruments_with_{name}_envelope", f"nonneutral_{name}_envelope_count"))
        names.extend(f"{name}_{flag}_flag_count" for flag in ("enable", "sustain", "loop"))
    return {**{name: counts[name] for name in names}, **{f"{key}_histogram": _histogram(values) for key, values in histograms.items()}}


def _effect_keys(command: int, parameter: int) -> tuple[str, str]:
    if command == 14:
        return f"E{parameter >> 4:X}x", f"E{parameter:02X}"
    if command == 33:
        return f"X{parameter >> 4:X}x", f"X{parameter:02X}"
    if command == 15:
        return "F00" if parameter == 0 else "F01...F1F" if parameter < 32 else "F20...FFF", f"F{parameter:02X}"
    family = EFFECTS.get(command, f"byte-{command:02X}")
    return family, f"{family[0]}{parameter:02X}" if command in EFFECTS else f"byte-{command:02X}:{parameter:02X}"


def _occurrence(records: dict, key: str, parameter: int, coordinate: dict, listed: int | None, *, family: bool = False) -> None:
    record = records.setdefault(key, {"stored_cell_count": 0, "listed_order_cell_count": 0 if listed is not None else None})
    record["stored_cell_count"] += 1
    if listed is not None:
        record["listed_order_cell_count"] += listed
    if family:
        histogram = record.setdefault("parameter_histogram", {})
        raw = f"{parameter:02X}"
        histogram[raw] = histogram.get(raw, 0) + 1
        for name, condition in (("zero_parameter_count", parameter == 0), ("zero_low_nibble_count", parameter & 15 == 0),
                                ("zero_high_nibble_count", parameter >> 4 == 0)):
            record[name] = record.get(name, 0) + int(condition)
        coordinates = record.setdefault("first_stored_coordinates", [])
        if len(coordinates) < COORDINATE_LIMIT:
            coordinates.append(coordinate)


def _derive(path: Path, data: bytes) -> dict[str, Any]:
    _require(len(data) >= 80 and data[:17] == corpus_map.SIG and data[37] == 0x1A, "invalid_xm_header")
    _require(corpus_map.u16(data, 58) == 0x0104, "unsupported_xm_layout")
    header_end = 60 + corpus_map.u32(data, 60)
    channels, song_length = corpus_map.u16(data, 68), corpus_map.u16(data, 64)
    _require(1 <= channels <= 256 and corpus_map.u16(data, 70) <= 256
             and corpus_map.u16(data, 72) <= 256, "invalid_dimensions")
    _require(song_length <= 256 and 80 + song_length <= header_end <= len(data), "invalid_xm_header_bounds")
    row_counts, encoded_patterns, instrument_headers, sample_headers = [], [], [], []

    def pattern_observer(index: int, header: bytes, payload: bytes) -> None:
        _require(header[4] == 0 and corpus_map.u16(header, 5) <= 256, "invalid_pattern_header")
        row_counts.append(corpus_map.u16(header, 5))
        encoded_patterns.append(payload)

    def instrument_observer(header: bytes, samples: list[bytes]) -> None:
        _require(not samples or (len(header) >= 241 and all(len(sample) >= 40 for sample in samples)), "incomplete_sample_metadata")
        instrument_headers.append(header)
        sample_headers.extend(samples)

    metadata = corpus_map.parse_xm(path, data=data, pattern_observer=pattern_observer, instrument_observer=instrument_observer)
    _require(not metadata["parse_warnings"] and metadata["sample_count_status"] == "complete", "truncated_xm_structure")
    orders = list(data[80:80 + song_length])
    listed_complete = all(pattern < len(row_counts) for pattern in orders)
    order_weights = Counter(orders)
    shapes: Counter = Counter({name: 0 for name in (
        "normal_note_cells", "note_only_cells", "instrument_only_cells", "key_off_cells", "empty_cells",
        "explicit_volume_column_cells", "explicit_effect_column_cells", "invalid_note_cells",
    )})
    effects, volume = {"families": {}, "exact_forms": {}, "nibble_forms": {}}, {"families": {}, "exact_forms": {}}
    unknown: Counter = Counter()
    for pattern, payload in enumerate(encoded_patterns):
        byte_count = 0

        def cell_observer(row: int, channel: int, cell: residual_scan.Cell, mask: int, consumed: int, complete: bool) -> None:
            nonlocal byte_count
            _require(complete, "truncated_pattern_cells")
            byte_count += consumed
            normal = residual_scan.is_normal_note(cell.note)
            for key, condition in (("normal_note_cells", normal), ("note_only_cells", normal and cell.instrument == 0),
                                   ("instrument_only_cells", cell.note == 0 and cell.instrument != 0),
                                   ("key_off_cells", cell.note == 97), ("empty_cells", cell == residual_scan.Cell()),
                                   ("explicit_volume_column_cells", bool(mask & 4)), ("explicit_effect_column_cells", bool(mask & 24)),
                                   ("invalid_note_cells", cell.note > 97)):
                shapes[key] += bool(condition)
            coordinate = {"pattern": pattern, "row": row, "channel": channel}
            listed = order_weights[pattern] if listed_complete else None
            if mask & 24:
                family, form = _effect_keys(cell.effect_type, cell.effect_param)
                _occurrence(effects["families"], family, cell.effect_param, coordinate, listed, family=True)
                _occurrence(effects["exact_forms"], form, cell.effect_param, coordinate, listed)
                if cell.effect_type in (4, 7, 27) and cell.effect_param != 0:
                    if cell.effect_param >> 4 == 0 or cell.effect_param & 15 == 0:
                        nibble = f"{form[0]}0y" if cell.effect_param >> 4 == 0 else f"{form[0]}x0"
                        _occurrence(effects["nibble_forms"], nibble, cell.effect_param, coordinate, listed)
                if cell.effect_type not in EFFECTS and cell.effect_type not in (14, 15, 33):
                    unknown[f"{cell.effect_type:02X}"] += 1
            if mask & 4:
                value = cell.volume
                family = "10...50" if 16 <= value <= 80 else f"{value >> 4:X}x" if value >= 96 else "empty" if value == 0 else "unknown"
                _occurrence(volume["families"], family, value, coordinate, listed, family=True)
                _occurrence(volume["exact_forms"], f"{value:02X}", value, coordinate, listed)

        residual_scan.decode_pattern_cells(payload, row_counts[pattern], channels, observer=cell_observer)
        _require(byte_count == len(payload), "trailing_pattern_bytes")
    represented = [header for header in sample_headers if corpus_map.u32(header, 0) // (2 if header[14] & 16 else 1) > 0]
    return {
        "frequency_table": metadata["frequency_table"], "xm_version": metadata["xm_version"],
        "channel_count": channels, "instrument_count": metadata["instrument_count"],
        "declared_sample_count": len(sample_headers), "represented_sample_count": len(represented),
        "represented_sample_count_status": "static_nonempty_pcm_frames",
        "pattern_count": len(row_counts), "order_count": song_length,
        "restart_position": corpus_map.u16(data, 66), "initial_speed": corpus_map.u16(data, 76), "initial_bpm": corpus_map.u16(data, 78),
        "pattern_row_counts": row_counts, "order_table": orders, "allocated_row_count": sum(row_counts),
        "listed_order_row_count": sum(row_counts[p] for p in orders) if listed_complete else None,
        "listed_order_status": "complete" if listed_complete else "invalid_pattern_reference",
        "zero_row_pattern_count": row_counts.count(0), "stored_cell_count": sum(row_counts) * channels,
        "listed_order_cell_count": sum(row_counts[p] for p in orders) * channels if listed_complete else None,
        "declared_samples": _sample_facts(sample_headers), "represented_samples": _sample_facts(represented),
        "instruments": _instrument_facts(instrument_headers), "cell_shapes": dict(shapes),
        "effects": effects, "volume_column": volume, "unknown_effect_type_histogram": dict(unknown),
    }


def build_inventory(label_map: Path) -> dict[str, Any]:
    """Generate deterministic, label-only facts; individual failures remain entries."""
    entries = []
    for source in _load_entries(label_map):
        entry = {"label": source["label"], "frequency_table": source.get("frequency_table") or "unknown",
                 "file_size_bytes": None, "sha256": None, "static_parse_status": "failed", "static_failure_code": None,
                 "vtx_parse_status": "not_checked", "vtx_admitted": None}
        try:
            path = Path(source["path"]).expanduser()
            data = path.read_bytes()
            entry.update(file_size_bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
            facts = _derive(path, data)
            entry.update(facts, static_parse_status="ok")
            entry["frequency_table_matches_map"] = source.get("frequency_table") not in ("linear", "amiga") or source["frequency_table"] == facts["frequency_table"]
        except OSError:
            entry["static_failure_code"] = "source_unreadable"
        except InventoryError as error:
            entry["static_failure_code"] = str(error)
        entries.append(entry)
    hashes: dict[str, list[str]] = {}
    for entry in entries:
        if entry["sha256"] is not None:
            hashes.setdefault(entry["sha256"], []).append(entry["label"])
    return {"schema_version": SCHEMA_VERSION, "entries": entries,
            "duplicate_groups": [{"sha256": digest, "labels": labels} for digest, labels in sorted(hashes.items()) if len(labels) > 1]}


def _confine_output(output: Path, label_map: Path, sources: list[dict]) -> None:
    output = output.expanduser()
    resolved = output.resolve()
    _require(not resolved.is_relative_to(REPO_ROOT), "output_inside_repository")
    for protected in [label_map, *(Path(entry["path"]).expanduser() for entry in sources)]:
        try:
            target = protected.resolve()
        except (OSError, RuntimeError):
            # Unreadable/looping sources still become individual failure entries.
            target = protected.absolute()
        _require(resolved != target and not (output.exists() and protected.exists()
                 and os.path.samefile(output, protected)), "output_overwrites_input")


def run_enrich(args: argparse.Namespace) -> int:
    """Write one external inventory atomically without modifying map or modules."""
    temporary = None
    try:
        _confine_output(args.output, args.label_map, _load_entries(args.label_map))
        inventory = build_inventory(args.label_map)
        output = args.output.expanduser()
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(json.dumps(inventory, indent=2, sort_keys=True) + "\n")
        temporary.replace(output)
        failures = sum(entry["static_parse_status"] != "ok" for entry in inventory["entries"])
        print(f"Inventory generated: {len(inventory['entries'])} entries; {failures} static failures; VTX admission not checked.")
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        print(f"vtx_diag: {error if isinstance(error, InventoryError) else 'inventory_io_or_json_failure'}", file=sys.stderr)
        return 1
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _family_argument(value: str) -> str:
    candidates = [*EFFECTS.values(), *(f"E{i:X}x" for i in range(16)), *(f"X{i:X}x" for i in range(16)), "F00", "F01...F1F", "F20...FFF"]
    candidates.extend(f"byte-{i:02X}" for i in range(256))
    aliases = {candidate.upper(): candidate for candidate in candidates}
    _require(value.upper() in aliases, "invalid_effect_family")
    return aliases[value.upper()]


def _count(value: Any) -> int:
    _require(type(value) is int and value >= 0, "invalid_inventory_fact")
    return value


def _selection_summary(entry: dict) -> dict:
    samples = entry["represented_samples"]
    histogram = samples["sample_header_volume_histogram"]
    _require(isinstance(histogram, dict) and all(re.fullmatch(r"\d{1,3}", key) and int(key) <= 255
             and _count(value) >= 0 for key, value in histogram.items()), "invalid_inventory_histogram")
    return {"label": entry["label"], "frequency_table": entry["frequency_table"],
            "channel_count": _count(entry["channel_count"]), "represented_sample_count": _count(entry["represented_sample_count"]),
            "positive_quiet_header_count": _count(samples["positive_quiet_header_count"]),
            "header_volume_values": sorted(int(key) for key in histogram),
            "normal_note_cells": _count(entry["cell_shapes"]["normal_note_cells"]),
            **{key: _count(entry[group][key]) for group, key in TRAITS.values()}}


def run_select(args: argparse.Namespace) -> int:
    """Select structural candidates with conjunctive factual filters and safe output."""
    try:
        _require(args.limit >= 0 and args.min_channels >= 0, "invalid_selection_limit")
        families = [_family_argument(value) for value in args.effect]
        forms = [value.upper().replace("BYTE-", "byte-") for value in args.effect_form]
        nibble_aliases = {form.upper(): form for form in NIBBLE_FORMS}
        forms = [nibble_aliases.get(form, form) for form in forms]
        _require(all(form in NIBBLE_FORMS or re.fullmatch(r"[0-9A-Z][0-9A-F]{2}|byte-[0-9A-F]{2}:[0-9A-F]{2}", form, re.I) for form in forms), "invalid_effect_form")
        volume_commands = [value[0].upper() + "x" if re.fullmatch(r"[6-9A-F]x", value, re.I) else value for value in args.volume_command]
        _require(all(value in ("10...50", *(f"{i:X}x" for i in range(6, 16))) for value in volume_commands), "invalid_volume_command")
        selected = []
        for entry in _load_entries(args.inventory, inventory=True):
            if entry.get("static_parse_status") != "ok":
                continue
            summary = _selection_summary(entry)
            if args.frequency_table and summary["frequency_table"] != args.frequency_table:
                continue
            if summary["channel_count"] < args.min_channels or any(getattr(args, "has_" + trait.replace("-", "_")) and summary[key] == 0 for trait, (_, key) in TRAITS.items()):
                continue
            if any(_count(entry["effects"]["families"].get(key, {}).get("stored_cell_count", 0)) == 0 for key in families):
                continue
            if any(_count(entry["effects"]["nibble_forms" if key in NIBBLE_FORMS else "exact_forms"].get(key, {}).get("stored_cell_count", 0)) == 0 for key in forms):
                continue
            if any(_count(entry["volume_column"]["families"].get(key, {}).get("stored_cell_count", 0)) == 0 for key in volume_commands):
                continue
            selected.append(summary)
        selected = selected[:args.limit]
        if args.json:
            print(json.dumps({"schema_version": SCHEMA_VERSION, "entries": selected}, indent=2, sort_keys=True))
        else:
            for entry in selected:
                print(f"{entry['label']} {entry['frequency_table']} represented={entry['represented_sample_count']} quiet={entry['positive_quiet_header_count']} volumes={','.join(map(str, entry['header_volume_values']))}")
        return 0
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f"vtx_diag: {error if isinstance(error, InventoryError) else 'invalid_or_unreadable_inventory'}", file=sys.stderr)
        return 1


def add_enrich_arguments(parser: argparse.ArgumentParser) -> None:
    """Register explicit local inputs and output for inventory generation."""
    parser.add_argument("--label-map", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)


def add_select_arguments(parser: argparse.ArgumentParser) -> None:
    """Register a bounded set of factual candidate filters, combined with AND."""
    parser.add_argument("--inventory", required=True, type=Path)
    parser.add_argument("--frequency-table", choices=("linear", "amiga"))
    for trait in TRAITS:
        parser.add_argument("--has-" + trait, action="store_true")
    parser.add_argument("--min-channels", type=int, default=0)
    parser.add_argument("--effect", action="append", default=[], help="Exact family, e.g. EEx, Pxy, F01...F1F; repeat for AND.")
    parser.add_argument("--effect-form", action="append", default=[], help="Stored form, e.g. E10, H00, 400, R0y, Rx0.")
    parser.add_argument("--volume-command", action="append", default=[], help="Volume family, e.g. Ax or 10...50.")
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--json", action="store_true")
