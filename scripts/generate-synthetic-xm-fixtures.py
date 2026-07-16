#!/usr/bin/env python3
"""Validate and generate deterministic public-safe synthetic XM fixtures."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


GENERATOR_NAME = "scripts/generate-synthetic-xm-fixtures.py"
SOURCE_MANIFEST = "source/basic-instrument-sample.manifest.json"
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PACK_ROOT = REPO_ROOT / "tests/reference-xm"
DEFAULT_MANIFEST_PATH = DEFAULT_PACK_ROOT / SOURCE_MANIFEST
EVENT_FIELDS = {
    "row", "channel", "note", "instrument", "volume_column", "effect_type", "effect_parameter"
}
ENCODING_BITS = {
    "signed_8_bit_delta_pcm": 8,
    "signed_16_bit_delta_pcm": 16,
}
LOOP_TYPES = {"none": 0, "forward": 1}
NOTE_NAMES = {name: index for index, name in enumerate(("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"))}
WAVEFORM_TABLES = {
    "sine": [0, 12539, 23170, 30273, 32767, 30273, 23170, 12539, 0, -12539, -23170, -30273, -32767, -30273, -23170, -12539],
}


def deterministic_json(data: dict[str, Any]) -> str:
    """Return stable, sorted, newline-terminated JSON."""
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def load_source_manifest(path: Path | None = None) -> dict[str, Any]:
    """Load the reviewable fixture-pack source manifest."""
    source = path or DEFAULT_MANIFEST_PATH
    return json.loads(source.read_text(encoding="utf-8"))


def fixture_names(manifest: dict[str, Any]) -> list[str]:
    """Return approved fixture filenames in manifest order."""
    return [fixture["name"] for fixture in manifest["fixtures"]]


def _require_int(value: Any, minimum: int, maximum: int, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or not minimum <= value <= maximum:
        raise ValueError(f"{label} must be in {minimum}...{maximum}")
    return value


def _require_ascii(value: Any, maximum_bytes: int, label: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{label} must be text")
    try:
        encoded = value.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ValueError(f"{label} must use deterministic ASCII") from exc
    if len(encoded) > maximum_bytes:
        raise ValueError(f"{label} exceeds {maximum_bytes} bytes")
    return value


def _note_byte(note: Any) -> int:
    if isinstance(note, int) and not isinstance(note, bool):
        return _require_int(note, 1, 97, "event note")
    if note == "key-off":
        return 97
    if isinstance(note, str):
        match = re.fullmatch(r"(C#?|D#?|E|F#?|G#?|A#?|B)-([0-7])", note)
        if match:
            value = (int(match.group(2)) * 12) + NOTE_NAMES[match.group(1)] + 1
            return _require_int(value, 1, 96, "event note")
    raise ValueError(f"event note is unsupported: {note!r}")


def _validate_envelope(envelope: dict[str, Any], label: str) -> None:
    expected = {"enabled", "points", "type_flags"}
    if set(envelope) != expected:
        raise ValueError(f"{label} fields must be exactly {sorted(expected)}")
    points = envelope["points"]
    if not isinstance(points, list) or len(points) > 12:
        raise ValueError(f"{label} point count must be in 0...12")
    previous_tick = -1
    for index, point in enumerate(points):
        if not isinstance(point, list) or len(point) != 2:
            raise ValueError(f"{label} point {index} must be [tick, value]")
        tick = _require_int(point[0], 0, 65_535, f"{label} point tick")
        _require_int(point[1], 0, 64, f"{label} point value")
        if tick <= previous_tick:
            raise ValueError(f"{label} ordering must use strictly increasing ticks")
        previous_tick = tick
    flags = _require_int(envelope["type_flags"], 0, 1, f"{label} type flags")
    if not isinstance(envelope["enabled"], bool):
        raise ValueError(f"{label} enabled must be boolean")
    if envelope["enabled"] != bool(flags & 0x01):
        raise ValueError(f"{label} enabled must match type flags")


def _validate_sample(sample: dict[str, Any], expected_slot: int, label: str) -> None:
    expected = {"slot", "name", "encoding", "pcm_recipe", "pcm_sha256", "volume", "panning", "finetune", "relative_note", "loop"}
    if set(sample) != expected:
        raise ValueError(f"{label} fields must be exactly {sorted(expected)}")
    if sample["slot"] != expected_slot:
        raise ValueError(f"{label} slot must be contiguous and equal {expected_slot}")
    _require_ascii(sample["name"], 22, f"{label} name")
    if sample["encoding"] not in ENCODING_BITS:
        raise ValueError(f"{label} encoding is unsupported")
    bits = ENCODING_BITS[sample["encoding"]]
    _require_int(sample["volume"], 0, 64, f"{label} volume")
    _require_int(sample["panning"], 0, 255, f"{label} panning")
    _require_int(sample["finetune"], -128, 127, f"{label} finetune")
    _require_int(sample["relative_note"], -128, 127, f"{label} relative_note")
    recipe = sample["pcm_recipe"]
    if set(recipe) != {"amplitude", "frame_count", "period_frames", "waveform"}:
        raise ValueError(f"{label} PCM recipe fields are unsupported")
    if recipe["waveform"] not in WAVEFORM_TABLES:
        raise ValueError(f"{label} PCM waveform is unsupported")
    if recipe["period_frames"] != 16:
        raise ValueError(f"{label} PCM period_frames must be 16")
    frames = _require_int(recipe["frame_count"], 1, 1_000_000, f"{label} PCM frame count")
    _require_int(recipe["amplitude"], 1, 127 if bits == 8 else 32_767, f"{label} PCM amplitude")
    loop = sample["loop"]
    if set(loop) != {"length_frames", "mode", "start_frame"} or loop["mode"] not in LOOP_TYPES:
        raise ValueError(f"{label} loop fields or mode are unsupported")
    start = _require_int(loop["start_frame"], 0, frames, f"{label} loop start")
    length = _require_int(loop["length_frames"], 0, frames, f"{label} loop length")
    if loop["mode"] == "none" and (start != 0 or length != 0):
        raise ValueError(f"{label} loop must be zeroed when mode is none")
    if loop["mode"] != "none" and (length == 0 or start + length > frames):
        raise ValueError(f"{label} loop range exceeds PCM frames")


def _validate_manifest_structure(manifest: dict[str, Any]) -> None:
    if manifest.get("schema_version") != 2:
        raise ValueError("schema_version must be 2")
    if manifest.get("generator") != GENERATOR_NAME:
        raise ValueError(f"generator must be {GENERATOR_NAME}")
    fixtures = manifest.get("fixtures")
    if not isinstance(fixtures, list) or not fixtures:
        raise ValueError("fixtures must be a nonempty list")
    ids: set[str] = set()
    names: set[str] = set()
    for fixture_index, fixture in enumerate(fixtures):
        label = f"fixture {fixture_index}"
        required = {"id", "name", "purpose", "source_manifest", "xm_output", "xm_sha256", "xm_size_bytes", "significant_rows", "intended_tests", "unsupported_semantics", "module"}
        if set(fixture) != required:
            raise ValueError(f"{label} fields must be exactly {sorted(required)}")
        identifier = fixture["id"]
        name = fixture["name"]
        if not isinstance(identifier, str) or not re.fullmatch(r"[a-z0-9-]+", identifier) or identifier in ids:
            raise ValueError(f"fixture id is invalid or duplicated: {identifier!r}")
        if not isinstance(name, str) or Path(name).name != name or not name.endswith(".xm") or name in names:
            raise ValueError(f"fixture name is invalid or duplicated: {name!r}")
        ids.add(identifier)
        names.add(name)
        if fixture["source_manifest"] != SOURCE_MANIFEST or fixture["xm_output"] != f"generated/{name}":
            raise ValueError(f"{label} provenance paths are not canonical")
        module = fixture["module"]
        module_fields = {"title", "tracker_name", "channels", "orders", "patterns", "instruments", "restart_position", "speed", "bpm", "flags"}
        if set(module) != module_fields:
            raise ValueError(f"{label} module fields must be exactly {sorted(module_fields)}")
        _require_ascii(module["title"], 20, f"{label} module title")
        _require_ascii(module["tracker_name"], 20, f"{label} tracker name")
        channels = _require_int(module["channels"], 1, 32, f"{label} channels")
        _require_int(module["restart_position"], 0, max(0, len(module["orders"]) - 1), f"{label} restart position")
        _require_int(module["speed"], 1, 65_535, f"{label} speed")
        _require_int(module["bpm"], 1, 65_535, f"{label} bpm")
        _require_int(module["flags"], 0, 65_535, f"{label} flags")
        patterns = module["patterns"]
        orders = module["orders"]
        if not isinstance(patterns, list) or not patterns or len(patterns) > 256:
            raise ValueError(f"{label} patterns must contain 1...256 entries")
        if not isinstance(orders, list) or not orders or len(orders) > 256:
            raise ValueError(f"{label} orders must contain 1...256 entries")
        for order in orders:
            _require_int(order, 0, len(patterns) - 1, f"{label} order pattern")
        instrument_count = len(module["instruments"])
        for pattern_index, pattern in enumerate(patterns):
            if set(pattern) != {"rows", "events"}:
                raise ValueError(f"{label} pattern fields are unsupported")
            rows = _require_int(pattern["rows"], 1, 256, f"{label} pattern rows")
            occupied: set[tuple[int, int]] = set()
            for event in pattern["events"]:
                extras = set(event) - EVENT_FIELDS
                if extras:
                    raise ValueError(f"{label} unsupported event fields: {sorted(extras)}")
                if not {"row", "channel", "note"} <= set(event):
                    raise ValueError(f"{label} event requires row, channel, and note")
                row = _require_int(event["row"], 0, rows - 1, f"{label} event row")
                channel = _require_int(event["channel"], 0, channels - 1, f"{label} event channel")
                if (row, channel) in occupied:
                    raise ValueError(f"{label} duplicate event at row {row}, channel {channel}")
                occupied.add((row, channel))
                _note_byte(event["note"])
                _require_int(event.get("instrument", 0), 0, instrument_count, f"{label} event instrument")
                for field in ("volume_column", "effect_type", "effect_parameter"):
                    _require_int(event.get(field, 0), 0, 255, f"{label} event {field}")
        if instrument_count > 255:
            raise ValueError(f"{label} instrument count exceeds 255")
        for instrument_index, instrument in enumerate(module["instruments"]):
            instrument_label = f"{label} instrument {instrument_index}"
            required_instrument = {"name", "samples", "volume_envelope"}
            if set(instrument) != required_instrument:
                raise ValueError(f"{instrument_label} fields are unsupported")
            _require_ascii(instrument["name"], 22, f"{instrument_label} name")
            samples = instrument["samples"]
            if not isinstance(samples, list) or len(samples) > 16:
                raise ValueError(f"{instrument_label} sample count must be in 0...16")
            for sample_index, sample in enumerate(samples):
                _validate_sample(sample, sample_index, f"{instrument_label} sample {sample_index}")
            _validate_envelope(instrument["volume_envelope"], f"{instrument_label} volume envelope")


def validate_manifest(manifest: dict[str, Any], verify_derived: bool = True) -> None:
    """Validate schema, representable ranges, and optionally pinned hashes/sizes."""
    _validate_manifest_structure(manifest)
    if not verify_derived:
        return
    canonical = canonical_manifest(manifest)
    for actual, expected in zip(manifest["fixtures"], canonical["fixtures"]):
        if actual.get("xm_sha256") != expected["xm_sha256"] or actual.get("xm_size_bytes") != expected["xm_size_bytes"]:
            raise ValueError(f"{actual['name']} derived XM hash or byte count is stale")
        for actual_instrument, expected_instrument in zip(actual["module"]["instruments"], expected["module"]["instruments"]):
            for actual_sample, expected_sample in zip(actual_instrument["samples"], expected_instrument["samples"]):
                if actual_sample.get("pcm_sha256") != expected_sample["pcm_sha256"]:
                    raise ValueError(f"{actual['name']} sample PCM hash is stale")


def _scaled_waveform_values(sample: dict[str, Any]) -> list[int]:
    recipe = sample["pcm_recipe"]
    table = WAVEFORM_TABLES[recipe["waveform"]]
    amplitude = recipe["amplitude"]
    values = []
    for frame in range(recipe["frame_count"]):
        unit = table[frame % 16]
        magnitude = ((abs(unit) * amplitude) + 16_383) // 32_767
        values.append(-magnitude if unit < 0 else magnitude)
    return values


def sample_pcm_bytes(sample: dict[str, Any]) -> bytes:
    """Return canonical absolute signed PCM bytes for a sample recipe."""
    values = _scaled_waveform_values(sample)
    if ENCODING_BITS[sample["encoding"]] == 8:
        return bytes(value & 0xFF for value in values)
    data = bytearray()
    for value in values:
        data.extend((value & 0xFFFF).to_bytes(2, "little"))
    return bytes(data)


def _delta_encoded_pcm(sample: dict[str, Any]) -> bytes:
    values = _scaled_waveform_values(sample)
    bits = ENCODING_BITS[sample["encoding"]]
    mask = (1 << bits) - 1
    data = bytearray()
    previous = 0
    for value in values:
        delta = (value - previous) & mask
        data.extend(delta.to_bytes(bits // 8, "little"))
        previous = value
    return bytes(data)


def _fixed_ascii(value: str, size: int, padding: int = 0) -> bytes:
    encoded = value.encode("ascii")
    return encoded + bytes([padding]) * (size - len(encoded))


def _u16(value: int) -> bytes:
    return int(value).to_bytes(2, "little", signed=False)


def _u32(value: int) -> bytes:
    return int(value).to_bytes(4, "little", signed=False)


def _packed_pattern(pattern: dict[str, Any], channels: int) -> bytes:
    events = {(event["row"], event["channel"]): event for event in pattern["events"]}
    data = bytearray()
    for row in range(pattern["rows"]):
        for channel in range(channels):
            event = events.get((row, channel))
            if event is None:
                data.append(0x80)
                continue
            fields = []
            marker = 0x80
            values = (
                (0x01, _note_byte(event["note"])),
                (0x02, event.get("instrument", 0)),
                (0x04, event.get("volume_column", 0)),
                (0x08, event.get("effect_type", 0)),
                (0x10, event.get("effect_parameter", 0)),
            )
            for bit, value in values:
                if value:
                    marker |= bit
                    fields.append(value)
            data.extend([marker, *fields])
    return bytes(data)


def _append_envelope(instrument: bytearray, offset: int, envelope: dict[str, Any]) -> None:
    for index, point in enumerate(envelope["points"]):
        point_offset = offset + (index * 4)
        instrument[point_offset:point_offset + 2] = _u16(point[0])
        instrument[point_offset + 2:point_offset + 4] = _u16(point[1])


def _instrument_bytes(instrument_spec: dict[str, Any]) -> bytes:
    samples = instrument_spec["samples"]
    if not samples:
        header = bytearray(29)
        header[0:4] = _u32(29)
        header[4:26] = _fixed_ascii(instrument_spec["name"], 22)
        return bytes(header)
    header = bytearray(263)
    header[0:4] = _u32(263)
    header[4:26] = _fixed_ascii(instrument_spec["name"], 22)
    header[27:29] = _u16(len(samples))
    header[29:33] = _u32(40)
    header[33:129] = bytes(96)
    volume = instrument_spec["volume_envelope"]
    _append_envelope(header, 129, volume)
    header[225] = len(volume["points"])
    header[233] = volume["type_flags"]
    sample_headers = bytearray()
    payloads = bytearray()
    for sample in samples:
        payload = _delta_encoded_pcm(sample)
        bits = ENCODING_BITS[sample["encoding"]]
        bytes_per_frame = bits // 8
        loop = sample["loop"]
        sample_type = LOOP_TYPES[loop["mode"]] | (0x10 if bits == 16 else 0)
        sample_header = bytearray(40)
        sample_header[0:4] = _u32(len(payload))
        sample_header[4:8] = _u32(loop["start_frame"] * bytes_per_frame)
        sample_header[8:12] = _u32(loop["length_frames"] * bytes_per_frame)
        sample_header[12] = sample["volume"]
        sample_header[13] = sample["finetune"] & 0xFF
        sample_header[14] = sample_type
        sample_header[15] = sample["panning"]
        sample_header[16] = sample["relative_note"] & 0xFF
        sample_header[18:40] = _fixed_ascii(sample["name"], 22)
        sample_headers.extend(sample_header)
        payloads.extend(payload)
    return bytes(header + sample_headers + payloads)


def _fixture_by_name(manifest: dict[str, Any], name: str) -> dict[str, Any]:
    for fixture in manifest["fixtures"]:
        if fixture["name"] == name:
            return fixture
    raise ValueError(f"unknown fixture: {name}")


def fixture_xm_bytes(manifest: dict[str, Any], name: str) -> bytes:
    """Generate one deterministic XM 1.04 fixture from the manifest."""
    module = _fixture_by_name(manifest, name)["module"]
    data = bytearray()
    data.extend(_fixed_ascii("Extended Module: ", 17, padding=0x20))
    data.extend(_fixed_ascii(module["title"], 20, padding=0x20))
    data.append(0x1A)
    data.extend(_fixed_ascii(module["tracker_name"], 20, padding=0x20))
    data.extend(_u16(0x0104))
    data.extend(_u32(276))
    data.extend(_u16(len(module["orders"])))
    data.extend(_u16(module["restart_position"]))
    data.extend(_u16(module["channels"]))
    data.extend(_u16(len(module["patterns"])))
    data.extend(_u16(len(module["instruments"])))
    data.extend(_u16(module["flags"]))
    data.extend(_u16(module["speed"]))
    data.extend(_u16(module["bpm"]))
    data.extend(bytes(module["orders"]))
    data.extend(bytes(256 - len(module["orders"])))
    for pattern in module["patterns"]:
        packed = _packed_pattern(pattern, module["channels"])
        data.extend(_u32(9))
        data.append(0)
        data.extend(_u16(pattern["rows"]))
        data.extend(_u16(len(packed)))
        data.extend(packed)
    for instrument in module["instruments"]:
        data.extend(_instrument_bytes(instrument))
    return bytes(data)


def fixture_manifest() -> dict[str, Any]:
    """Compatibility name for the canonical committed manifest contract."""
    return canonical_manifest(load_source_manifest())


def basic_instrument_sample_xm_bytes() -> bytes:
    """Return the unchanged original basic fixture bytes."""
    manifest = load_source_manifest()
    return fixture_xm_bytes(manifest, "basic-instrument-sample.xm")


def multi_pattern_loop_boundary_xm_bytes() -> bytes:
    """Return the unchanged original traversal fixture bytes."""
    manifest = load_source_manifest()
    return fixture_xm_bytes(manifest, "multi-pattern-loop-boundary.xm")


def canonical_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    """Return a deep copy with derived XM and PCM expectations refreshed."""
    _validate_manifest_structure(manifest)
    canonical = copy.deepcopy(manifest)
    for fixture in canonical["fixtures"]:
        for instrument in fixture["module"]["instruments"]:
            for sample in instrument["samples"]:
                sample["pcm_sha256"] = hashlib.sha256(sample_pcm_bytes(sample)).hexdigest()
        payload = fixture_xm_bytes(canonical, fixture["name"])
        fixture["xm_sha256"] = hashlib.sha256(payload).hexdigest()
        fixture["xm_size_bytes"] = len(payload)
    return canonical


def fixture_summary(manifest: dict[str, Any], name: str) -> dict[str, Any]:
    """Return stable generation diagnostics for one fixture."""
    fixture = _fixture_by_name(manifest, name)
    payload = fixture_xm_bytes(manifest, name)
    instruments = fixture["module"]["instruments"]
    return {
        "name": name,
        "bytes": len(payload),
        "instruments": len(instruments),
        "samples": sum(len(instrument["samples"]) for instrument in instruments),
        "sha256": hashlib.sha256(payload).hexdigest(),
    }


def resolved_child(output_dir: Path, relative_path: str) -> Path:
    """Resolve a planned output while rejecting traversal outside its root."""
    root = output_dir.resolve()
    child = (root / relative_path).resolve()
    try:
        child.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"refusing to write outside output directory: {relative_path}") from exc
    return child


def planned_paths(output_dir: Path, manifest: dict[str, Any] | None = None) -> dict[str, Path]:
    """Return the confined source-manifest and approved generated-XM paths."""
    source = manifest or load_source_manifest()
    paths = {"source_manifest": resolved_child(output_dir, SOURCE_MANIFEST)}
    for name in fixture_names(source):
        paths[f"xm:{name}"] = resolved_child(output_dir, f"generated/{name}")
    return paths


def _selected_names(manifest: dict[str, Any], selected: list[str] | None) -> list[str]:
    names = fixture_names(manifest)
    if selected is None:
        return names
    unknown = [name for name in selected if name not in names]
    if unknown:
        raise ValueError(f"unknown fixture selection: {', '.join(unknown)}")
    return selected


def write_source_manifest(output_dir: Path, manifest: dict[str, Any] | None = None) -> Path:
    """Write the canonical reviewable source manifest under source/."""
    source = canonical_manifest(manifest or load_source_manifest())
    path = resolved_child(output_dir, SOURCE_MANIFEST)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(deterministic_json(source), encoding="utf-8")
    return path


def write_xm_fixtures(
    output_dir: Path,
    manifest: dict[str, Any] | None = None,
    selected: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Write approved fixtures under generated/ and return stable summaries."""
    source = manifest or load_source_manifest()
    validate_manifest(source)
    summaries = []
    for name in _selected_names(source, selected):
        path = resolved_child(output_dir, f"generated/{name}")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(fixture_xm_bytes(source, name))
        summaries.append(fixture_summary(source, name))
    return summaries


def write_xm_fixture(output_dir: Path) -> list[Path]:
    """Compatibility wrapper for the original all-fixtures writer API."""
    manifest = load_source_manifest()
    write_xm_fixtures(output_dir, manifest)
    return [resolved_child(output_dir, f"generated/{name}") for name in fixture_names(manifest)]


def verify_xm_fixtures(
    output_dir: Path,
    manifest: dict[str, Any] | None = None,
    selected: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Fail if any selected committed XM differs from regenerated bytes."""
    source = manifest or load_source_manifest()
    validate_manifest(source)
    summaries = []
    for name in _selected_names(source, selected):
        path = resolved_child(output_dir, f"generated/{name}")
        if not path.is_file() or path.read_bytes() != fixture_xm_bytes(source, name):
            raise ValueError(f"{path} differs from regenerated bytes")
        summaries.append(fixture_summary(source, name))
    return summaries


def _print_summary(prefix: str, summary: dict[str, Any]) -> None:
    print(
        f"{prefix} {summary['name']}: {summary['bytes']} bytes; "
        f"{summary['instruments']} instruments; {summary['samples']} samples; sha256 {summary['sha256']}"
    )


def main(argv: list[str] | None = None) -> int:
    """Run manifest validation, generation, or committed-output verification."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST_PATH, help="Source pack manifest.")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_PACK_ROOT, help="Fixture-pack root.")
    parser.add_argument("--fixture", action="append", help="Generate or verify one named fixture; repeatable.")
    parser.add_argument("--validate", action="store_true", help="Validate the source manifest and pinned expectations.")
    parser.add_argument("--write-manifest", action="store_true", help="Canonicalize the manifest under --output-dir/source.")
    parser.add_argument("--write-xm", action="store_true", help="Write selected approved fixtures under --output-dir/generated.")
    parser.add_argument("--verify", action="store_true", help="Verify selected committed outputs without rewriting them.")
    parser.add_argument("--print-paths", action="store_true", help="Print confined approved output paths.")
    args = parser.parse_args(argv)
    try:
        manifest = load_source_manifest(args.manifest)
        acted = False
        if args.write_manifest:
            path = write_source_manifest(args.output_dir, manifest)
            manifest = canonical_manifest(manifest)
            print(f"Wrote {path.relative_to(args.output_dir.resolve())}")
            acted = True
        if args.validate:
            validate_manifest(manifest)
            print(f"Validated {len(manifest['fixtures'])} fixtures.")
            acted = True
        if args.print_paths:
            for key, path in sorted(planned_paths(args.output_dir, manifest).items()):
                print(f"{key}: {path.relative_to(args.output_dir.resolve())}")
            acted = True
        if args.write_xm:
            for summary in write_xm_fixtures(args.output_dir, manifest, args.fixture):
                _print_summary("Wrote", summary)
            acted = True
        if args.verify:
            for summary in verify_xm_fixtures(args.output_dir, manifest, args.fixture):
                _print_summary("Verified", summary)
            acted = True
        if not acted:
            print(deterministic_json(canonical_manifest(manifest)), end="")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
