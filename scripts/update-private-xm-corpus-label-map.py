#!/usr/bin/env python3
"""Refresh the local private XM corpus label map and redacted summary."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_MAP = Path("/tmp/vtx-private-xm-corpus-label-map.json")
DEFAULT_SUMMARY_JSON = Path("/tmp/vtx-private-xm-corpus-label-map-summary.json")
DEFAULT_SUMMARY_MD = Path("/tmp/vtx-private-xm-corpus-label-map-summary.md")
SIG = b"Extended Module: "
LABEL_RE = re.compile(r"^xm-corpus-(\d{3,})$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Append private XM corpus labels, enrich local metadata, and write a redacted summary."
    )
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--map", default=DEFAULT_MAP, type=Path)
    parser.add_argument("--summary-json", default=DEFAULT_SUMMARY_JSON, type=Path)
    parser.add_argument("--summary-markdown", default=DEFAULT_SUMMARY_MD, type=Path)
    return parser.parse_args()


def u16(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "little")


def u32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "little")


def fixed_text(data: bytes) -> str | None:
    value = data.split(b"\x00", 1)[0].decode("latin-1", errors="replace").strip()
    return value or None


def version_label(raw: int) -> str:
    return f"{raw >> 8}.{raw & 0xFF:02x}"


def parse_xm(path: Path) -> dict[str, Any]:
    warnings: list[str] = []
    metadata: dict[str, Any] = {
        "format": "unknown",
        "tracker_name": None,
        "xm_version": None,
        "xm_version_raw": None,
        "xm_flags": None,
        "frequency_table": "unknown",
        "channel_count": None,
        "song_length": None,
        "order_count": None,
        "playable_order_count": None,
        "pattern_count": None,
        "instrument_count": None,
        "sample_count": None,
        "sample_count_status": "unknown",
        "file_size_bytes": path.stat().st_size,
        "parse_warnings": warnings,
    }
    data = path.read_bytes()
    if len(data) < 80 or data[: len(SIG)] != SIG:
        warnings.append("missing or truncated XM header")
        return metadata

    raw_version = u16(data, 58)
    flags = u16(data, 74)
    song_length = u16(data, 64)
    pattern_count = u16(data, 70)
    order_table = list(data[80 : 80 + min(song_length, 256, max(0, len(data) - 80))])
    metadata.update(
        {
            "format": "XM",
            "tracker_name": fixed_text(data[38:58]),
            "xm_version": version_label(raw_version),
            "xm_version_raw": raw_version,
            "xm_flags": flags,
            "frequency_table": "linear" if flags & 0x01 else "amiga",
            "channel_count": u16(data, 68),
            "song_length": song_length,
            "order_count": song_length,
            "playable_order_count": sum(1 for pattern in order_table if pattern < pattern_count),
            "pattern_count": pattern_count,
            "instrument_count": u16(data, 72),
        }
    )

    offset = 60 + u32(data, 60)
    if offset > len(data):
        warnings.append("XM header extends past file")
        return metadata
    offset = skip_patterns(data, offset, pattern_count, warnings)
    sample_count, status = sample_count_from_instruments(data, offset, metadata["instrument_count"], warnings)
    metadata["sample_count"] = sample_count
    metadata["sample_count_status"] = status
    return metadata


def skip_patterns(data: bytes, offset: int, count: int, warnings: list[str]) -> int:
    current = offset
    for index in range(count):
        if current + 9 > len(data):
            warnings.append(f"pattern {index} header truncated")
            return len(data)
        header_size = u32(data, current)
        if header_size < 9 or current + header_size > len(data):
            warnings.append(f"pattern {index} header invalid")
            return len(data)
        current += header_size + u16(data, current + 7)
        if current > len(data):
            warnings.append(f"pattern {index} packed data extends past file")
            return len(data)
    return current


def sample_count_from_instruments(data: bytes, offset: int, count: int, warnings: list[str]) -> tuple[int | None, str]:
    current = offset
    total = 0
    for index in range(count):
        if current + 29 > len(data):
            warnings.append(f"instrument {index + 1} header truncated")
            return (total or None, "partial")
        header_size = u32(data, current)
        if header_size < 29 or current + header_size > len(data):
            warnings.append(f"instrument {index + 1} header invalid")
            return (total or None, "partial")
        samples = u16(data, current + 27)
        total += samples
        if samples == 0:
            current += header_size
            continue
        sample_header_size = u32(data, current + 29) if header_size >= 33 else 40
        if sample_header_size < 4:
            warnings.append(f"instrument {index + 1} sample header size invalid")
            return (total, "partial")
        headers_at = current + header_size
        headers_size = samples * sample_header_size
        if headers_at + headers_size > len(data):
            warnings.append(f"instrument {index + 1} sample headers truncated")
            return (total, "partial")
        data_size = sum(u32(data, headers_at + sample_header_size * sample) for sample in range(samples))
        current = headers_at + headers_size + data_size
        if current > len(data):
            warnings.append(f"instrument {index + 1} sample data extends past file")
            return (total, "partial")
    return (total, "complete")


def load_map(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"entries": []}
    loaded = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(loaded, list):
        return {"entries": loaded}
    if not isinstance(loaded, dict) or not isinstance(loaded.get("entries"), list):
        raise ValueError("Label map must be an object with an entries array")
    return loaded


def key(path: Path | str) -> str:
    return str(Path(path).expanduser().resolve(strict=False))


def discover(source_dir: Path) -> list[Path]:
    return sorted(
        (path for path in source_dir.iterdir() if path.is_file() and path.suffix.lower() == ".xm"),
        key=lambda path: path.name.casefold(),
    )


def next_number(entries: list[dict[str, Any]]) -> int:
    values = [int(match.group(1)) for entry in entries if (match := LABEL_RE.match(str(entry.get("label", ""))))]
    return max(values, default=0) + 1


def unique_filename_entries(entries: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for entry in entries:
        if isinstance(entry.get("filename"), str):
            grouped.setdefault(entry["filename"].casefold(), []).append(entry)
    return {filename: matches[0] for filename, matches in grouped.items() if len(matches) == 1}


def update_label_map(source_dir: Path, map_path: Path) -> tuple[dict[str, Any], list[str]]:
    label_map = load_map(map_path)
    entries = list(label_map["entries"])
    by_path = {key(entry["path"]): entry for entry in entries if isinstance(entry.get("path"), str)}
    by_filename = unique_filename_entries(entries)
    new_labels: list[str] = []
    number = next_number(entries)

    files = discover(source_dir)
    for xm_file in files:
        entry = by_path.get(key(xm_file)) or by_filename.get(xm_file.name.casefold())
        if entry is None:
            entry = {"label": f"xm-corpus-{number:03d}"}
            number += 1
            entries.append(entry)
            new_labels.append(entry["label"])
        entry.update(
            {
                "stable_anonymized_label": entry["label"],
                "filename": xm_file.name,
                "path": str(xm_file.resolve(strict=False)),
                **parse_xm(xm_file),
            }
        )

    label_map.update(
        {
            "entries": entries,
            "generated_at_utc": utc_now(),
            "source_directory": str(source_dir.resolve(strict=False)),
            "total_xm_files_discovered": len(files),
            "total_mapped_modules": len(entries),
            "newly_added_labels": new_labels,
        }
    )
    return label_map, new_labels


def build_summary(label_map: dict[str, Any], new_labels: list[str]) -> dict[str, Any]:
    entries = [entry for entry in label_map.get("entries", []) if isinstance(entry, dict)]
    channels = [entry["channel_count"] for entry in entries if isinstance(entry.get("channel_count"), int)]
    return {
        "generated_at_utc": utc_now(),
        "total_mapped_modules": len(entries),
        "newly_added_labels": new_labels,
        "frequency_table_counts": dict(sorted(Counter(entry.get("frequency_table") or "unknown" for entry in entries).items())),
        "tracker_version_counts": dict(sorted(Counter(tracker_version(entry) for entry in entries).items())),
        "channel_count_range": {"min": min(channels) if channels else None, "max": max(channels) if channels else None},
        "amiga_frequency_table_labels": labels_where(entries, lambda entry: entry.get("frequency_table") == "amiga"),
        "unusual_metadata": unusual_metadata(entries),
    }


def tracker_version(entry: dict[str, Any]) -> str:
    return f"{entry.get('tracker_name') or 'unknown'} / XM {entry.get('xm_version') or 'unknown'}"


def labels_where(entries: list[dict[str, Any]], predicate: Any) -> list[str]:
    return [entry["label"] for entry in entries if isinstance(entry.get("label"), str) and predicate(entry)]


def unusual_metadata(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    items = []
    for entry in entries:
        notes = []
        if entry.get("format") != "XM":
            notes.append("format not parsed as XM")
        if entry.get("frequency_table") == "amiga":
            notes.append("Amiga frequency table")
        if isinstance(entry.get("xm_flags"), int) and entry["xm_flags"] not in (0, 1):
            notes.append(f"XM flags {entry['xm_flags']}")
        if entry.get("xm_version") not in (None, "1.04"):
            notes.append(f"XM version {entry['xm_version']}")
        channels = entry.get("channel_count")
        if isinstance(channels, int) and (channels <= 0 or channels > 32 or channels % 2 != 0):
            notes.append(f"channel count {channels}")
        if entry.get("playable_order_count") != entry.get("order_count"):
            notes.append(f"playable orders {entry.get('playable_order_count')} of {entry.get('order_count')}")
        if entry.get("sample_count_status") not in (None, "complete"):
            notes.append(f"sample count {entry.get('sample_count_status')}")
        if entry.get("parse_warnings"):
            notes.append("parse warnings present")
        if notes and isinstance(entry.get("label"), str):
            items.append({"label": entry["label"], "notes": notes})
    return items


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_markdown(path: Path, summary: dict[str, Any]) -> None:
    lines = [
        "# Private XM Corpus Label Map Summary",
        "",
        "Public-safe local diagnostics summary. Private filenames and paths are omitted.",
        "",
        f"- Total mapped modules: {summary['total_mapped_modules']}",
        f"- Newly added labels: {label_list(summary['newly_added_labels'])}",
        f"- Frequency table counts: {counts(summary['frequency_table_counts'])}",
        f"- Channel count range: {range_text(summary['channel_count_range'])}",
        "",
        "## Tracker / Version Counts",
        "",
        *count_lines(summary["tracker_version_counts"]),
        "",
        "## Amiga Frequency Table Modules",
        "",
        label_list(summary["amiga_frequency_table_labels"]),
        "",
        "## Unusual Metadata",
        "",
    ]
    lines.extend(
        [f"- `{item['label']}`: {'; '.join(item['notes'])}" for item in summary["unusual_metadata"]]
        or ["None."]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def label_list(labels: list[str]) -> str:
    return ", ".join(f"`{label}`" for label in labels) if labels else "None."


def counts(values: dict[str, int]) -> str:
    return ", ".join(f"{key}={value}" for key, value in values.items()) if values else "None."


def count_lines(values: dict[str, int]) -> list[str]:
    return [f"- {key}: {value}" for key, value in values.items()] if values else ["None."]


def range_text(value: dict[str, int | None]) -> str:
    return "unknown" if value.get("min") is None or value.get("max") is None else f"{value['min']}...{value['max']}"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main() -> int:
    args = parse_args()
    label_map, new_labels = update_label_map(args.source_dir, args.map)
    write_json(args.map, label_map)
    summary = build_summary(label_map, new_labels)
    write_json(args.summary_json, summary)
    write_markdown(args.summary_markdown, summary)
    print(f"Updated private XM corpus label map: {summary['total_mapped_modules']} mapped modules, {len(new_labels)} new labels.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
