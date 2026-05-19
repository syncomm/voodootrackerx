#!/usr/bin/env python3
"""Correlate local audio comparison mismatch windows with bounded adapter diagnostics."""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any


DEFAULT_PRECEDING_EVENTS = 5
DEFAULT_CONTEXT_ROWS = 8
MAX_EXAMPLES_PER_COMMAND = 3
TRAVERSAL_HAZARD_LABELS = {"Bxx position jump", "Dxx pattern break", "EEx pattern delay"}
PITCH_LABEL_TO_CATEGORY = {
    "0xy arpeggio": "arpeggio",
    "1xx portamento up": "portamento",
    "2xx portamento down": "portamento",
    "3xx tone portamento": "portamento",
    "5xy tone portamento + volume slide": "portamento",
    "tone portamento": "portamento",
    "volume-column tone portamento": "portamento",
    "4xy vibrato": "vibrato",
    "6xy vibrato + volume slide": "vibrato",
    "vibrato speed": "vibrato",
    "vibrato": "vibrato",
    "volume-column vibrato speed": "vibrato",
    "volume-column vibrato": "vibrato",
    "7xy tremolo": "tremolo",
}
PITCH_CATEGORY_DISPLAY = {
    "arpeggio": "Arpeggio",
    "portamento": "Portamento",
    "vibrato": "Vibrato",
    "tremolo": "Tremolo",
}
PITCH_CATEGORY_RECOMMENDATIONS = {
    "arpeggio": "Minimal Arpeggio 0xy for Bounded Offline Renders",
    "portamento": "Minimal Portamento Foundation",
    "vibrato": "Minimal Vibrato Foundation",
    "tremolo": "Minimal Tremolo 7xy",
}


class CorrelationError(Exception):
    """A user-facing correlation input or validation error."""


@dataclass(frozen=True)
class CommandOccurrence:
    domain: str
    label: str
    status: str
    source: dict[str, Any]
    channel: Any
    start_frame: int | None
    end_frame: int | None
    parameter: Any = None
    window_ranks: tuple[int, ...] = ()


def load_json(path: Path, role: str) -> dict[str, Any]:
    if not path.exists():
        raise CorrelationError(f"missing {role} JSON: {path}")
    if not path.is_file():
        raise CorrelationError(f"{role} JSON is not a file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise CorrelationError(
            f"malformed JSON in {role} JSON: {path}: line {error.lineno} column {error.colno}: {error.msg}"
        ) from error
    if not isinstance(value, dict):
        raise CorrelationError(f"{role} JSON must contain a top-level object: {path}")
    return value


def number(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return float(value)
    return None


def integer(value: Any) -> int | None:
    numeric = number(value)
    if numeric is None:
        return None
    return int(numeric)


def nested_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def nested_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def extract_sample_rate(comparison: dict[str, Any], diagnostics: dict[str, Any]) -> int:
    render = nested_dict(diagnostics.get("render"))
    for value in (
        render.get("sample_rate"),
        nested_dict(nested_dict(comparison.get("candidate")).get("info")).get("sample_rate"),
        nested_dict(nested_dict(comparison.get("reference")).get("info")).get("sample_rate"),
    ):
        numeric = number(value)
        if numeric is not None and numeric > 0:
            return int(numeric)
    raise CorrelationError("cannot determine sample rate from diagnostics or comparison JSON")


def extract_windows(comparison: dict[str, Any], sample_rate: int) -> list[dict[str, Any]]:
    sample_comparison = comparison.get("sample_comparison")
    if not isinstance(sample_comparison, dict):
        raise CorrelationError(
            "comparison JSON does not contain sample_comparison.worst_windows; "
            "sample comparison may have been skipped because formats differ"
        )
    windows = sample_comparison.get("worst_windows")
    if not isinstance(windows, list):
        raise CorrelationError("comparison JSON does not contain sample_comparison.worst_windows list")

    normalized: list[dict[str, Any]] = []
    for index, window in enumerate(windows, start=1):
        if not isinstance(window, dict):
            raise CorrelationError(f"worst mismatch window {index} is not an object")
        start_frame = integer(window.get("start_frame"))
        end_frame = integer(window.get("end_frame"))
        if start_frame is None or end_frame is None:
            start_seconds = number(window.get("start_seconds"))
            end_seconds = number(window.get("end_seconds"))
            if start_seconds is None or end_seconds is None:
                raise CorrelationError(
                    f"worst mismatch window {index} needs start/end frames or start/end seconds"
                )
            start_frame = int(math.floor(start_seconds * sample_rate))
            end_frame = int(math.ceil(end_seconds * sample_rate))
        start_frame = max(0, start_frame)
        end_frame = max(start_frame + 1, end_frame)
        normalized.append({
            **window,
            "_rank": index,
            "_start_frame": start_frame,
            "_end_frame": end_frame,
            "_start_seconds": start_frame / sample_rate,
            "_end_seconds": end_frame / sample_rate,
        })
    return normalized


def normalize_events(diagnostics: dict[str, Any], sample_rate: int) -> list[dict[str, Any]]:
    events = []
    for raw_event in nested_list(diagnostics.get("events")):
        if not isinstance(raw_event, dict):
            continue
        start_frame = integer(raw_event.get("scheduled_start_frame"))
        if start_frame is None:
            start_seconds = number(raw_event.get("scheduled_start_seconds"))
            if start_seconds is not None:
                start_frame = int(math.floor(start_seconds * sample_rate))
        if start_frame is None:
            continue
        end_frame = integer(raw_event.get("estimated_end_frame"))
        if end_frame is None:
            duration = integer(raw_event.get("estimated_duration_frames"))
            if duration is not None:
                end_frame = start_frame + max(1, duration)
        if end_frame is None:
            end_seconds = number(raw_event.get("estimated_end_seconds"))
            if end_seconds is not None:
                end_frame = int(math.ceil(end_seconds * sample_rate))
        if end_frame is None:
            end_frame = start_frame + 1
        event = {
            **raw_event,
            "_start_frame": max(0, start_frame),
            "_end_frame": max(start_frame + 1, end_frame),
        }
        events.append(event)
    events.sort(key=lambda item: (item["_start_frame"], item.get("event_index", 0)))
    return events


def normalize_row_timing(diagnostics: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    for raw_row in nested_list(diagnostics.get("row_timing")):
        if not isinstance(raw_row, dict):
            continue
        start_frame = integer(raw_row.get("row_start_frame"))
        end_frame = integer(raw_row.get("row_end_frame"))
        if start_frame is None:
            continue
        if end_frame is None:
            duration = integer(raw_row.get("row_duration_frames")) or 1
            end_frame = start_frame + max(1, duration)
        rows.append({
            **raw_row,
            "_start_frame": max(0, start_frame),
            "_end_frame": max(start_frame + 1, end_frame),
        })
    rows.sort(key=lambda item: (item["_start_frame"], item.get("synthetic_row", 0)))
    return rows


def normalize_timing_changes(diagnostics: dict[str, Any]) -> list[dict[str, Any]]:
    changes = []
    for raw_change in nested_list(diagnostics.get("timing_changes")):
        if isinstance(raw_change, dict):
            changes.append(raw_change)
    changes.sort(key=lambda item: (integer(item.get("row_start_frame")) or 0, item.get("channel_index", 0)))
    return changes


def overlaps(start_a: int, end_a: int, start_b: int, end_b: int) -> bool:
    return start_a < end_b and end_a > start_b


def source_key(source: dict[str, Any], channel: Any) -> tuple[Any, Any, Any, Any]:
    return (
        source.get("order"),
        source.get("pattern"),
        source.get("row"),
        channel,
    )


def timing_change_index(changes: list[dict[str, Any]]) -> dict[tuple[Any, Any, Any, Any], list[dict[str, Any]]]:
    indexed: dict[tuple[Any, Any, Any, Any], list[dict[str, Any]]] = {}
    for change in changes:
        key = source_key(nested_dict(change.get("source")), change.get("channel_index"))
        indexed.setdefault(key, []).append(change)
    return indexed


def source_row_key(source: dict[str, Any]) -> tuple[Any, Any, Any]:
    return (
        source.get("order"),
        source.get("pattern"),
        source.get("row"),
    )


def row_frame_indexes(
    rows: list[dict[str, Any]],
) -> tuple[dict[tuple[Any, Any, Any], tuple[int, int]], dict[Any, tuple[int, int]]]:
    by_source: dict[tuple[Any, Any, Any], tuple[int, int]] = {}
    by_synthetic_row: dict[Any, tuple[int, int]] = {}
    for row in rows:
        frame_range = (row["_start_frame"], row["_end_frame"])
        by_source[source_row_key(nested_dict(row.get("source")))] = frame_range
        synthetic_row = row.get("synthetic_row")
        if synthetic_row is not None:
            by_synthetic_row[synthetic_row] = frame_range
    return by_source, by_synthetic_row


def frame_range_for_diagnostic(
    diagnostic: dict[str, Any],
    rows_by_source: dict[tuple[Any, Any, Any], tuple[int, int]],
    rows_by_synthetic: dict[Any, tuple[int, int]],
) -> tuple[int | None, int | None]:
    scheduled_frame = integer(diagnostic.get("scheduled_frame"))
    if scheduled_frame is not None:
        return max(0, scheduled_frame), scheduled_frame + 1
    source = nested_dict(diagnostic.get("source"))
    source_range = rows_by_source.get(source_row_key(source))
    if source_range is not None:
        return source_range
    synthetic_row = diagnostic.get("synthetic_row")
    synthetic_range = rows_by_synthetic.get(synthetic_row)
    if synthetic_range is not None:
        return synthetic_range
    start_frame = integer(diagnostic.get("scheduled_start_frame"))
    end_frame = integer(diagnostic.get("estimated_end_frame"))
    if start_frame is None:
        start_frame = integer(diagnostic.get("row_start_frame"))
    if start_frame is None:
        return None, None
    if end_frame is None:
        end_frame = start_frame + 1
    return max(0, start_frame), max(start_frame + 1, end_frame)


def effect_command_label(effect_type_value: Any, effect_param_value: Any) -> str:
    effect_type = int_or_none(effect_type_value)
    effect_param = int_or_none(effect_param_value) or 0
    if effect_type is None:
        return "unknown/unsupported"
    effect_type &= 0xFF
    effect_param &= 0xFF
    if effect_type == 0x00:
        return "0xy arpeggio" if effect_param != 0 else "none"
    if effect_type == 0x01:
        return "1xx portamento up"
    if effect_type == 0x02:
        return "2xx portamento down"
    if effect_type == 0x03:
        return "3xx tone portamento"
    if effect_type == 0x04:
        return "4xy vibrato"
    if effect_type == 0x05:
        return "5xy tone portamento + volume slide"
    if effect_type == 0x06:
        return "6xy vibrato + volume slide"
    if effect_type == 0x07:
        return "7xy tremolo"
    if effect_type == 0x09:
        return "900 sample offset / effect memory" if effect_param == 0 else "9xx sample offset"
    if effect_type == 0x0A:
        return "Axy volume slide"
    if effect_type == 0x0B:
        return "Bxx position jump"
    if effect_type == 0x0C:
        return "Cxx set volume"
    if effect_type == 0x0D:
        return "Dxx pattern break"
    if effect_type == 0x0E:
        subcommand = (effect_param >> 4) & 0x0F
        if subcommand == 0x09:
            return "E9x retrigger"
        if subcommand == 0x0C:
            return "ECx note cut"
        if subcommand == 0x0D:
            return "EDx note delay"
        if subcommand == 0x0E:
            return "EEx pattern delay"
        return "unknown/unsupported"
    if effect_type == 0x0F:
        return "Fxx speed/BPM"
    if effect_type == 0x11:
        return "Hxy global volume slide"
    return "unknown/unsupported"


def volume_command_label(volume_column: dict[str, Any]) -> str:
    command = nested_dict(volume_column.get("command"))
    name = command.get("name")
    if name == "setVolume":
        return "set volume"
    if name == "volumeSlideDown":
        return "volume slide down"
    if name == "volumeSlideUp":
        return "volume slide up"
    if name == "fineVolumeSlideDown":
        return "fine volume slide down"
    if name == "fineVolumeSlideUp":
        return "fine volume slide up"
    if name == "setPanning":
        return "set panning"
    if name == "panningSlideLeft":
        return "pan slide left"
    if name == "panningSlideRight":
        return "pan slide right"
    if name == "setVibratoSpeed":
        return "vibrato speed"
    if name == "vibrato":
        return "vibrato"
    if name == "tonePortamento":
        return "tone portamento"
    if name == "none":
        return "none"
    return "unsupported/unknown"


def volume_status(volume_column: dict[str, Any]) -> str:
    classification = str(volume_column.get("classification", "")).lower()
    if bool(volume_column.get("applied")) or classification == "supported":
        return "applied"
    if bool(volume_column.get("deferred")) or classification == "deferred":
        return "deferred/unsupported"
    if bool(volume_column.get("ignored_as_empty_or_no_op")) or classification == "ignored_no_op":
        return "ignored/no-op"
    return "unknown"


def sample_offset_status(sample_offset: dict[str, Any]) -> str:
    status = str(sample_offset.get("status", ""))
    if bool(sample_offset.get("applied")) or status == "applied":
        return "applied"
    if status == "ignored_900_no_op" or bool(sample_offset.get("deferred")):
        return "deferred/no-op"
    if bool(sample_offset.get("skipped")) or status == "out_of_range_skipped":
        return "ignored/no-op"
    if status == "not_present":
        return "ignored/no-op"
    return "unknown"


def note_cut_status(note_cut: dict[str, Any]) -> str:
    status = str(note_cut.get("status", ""))
    if bool(note_cut.get("applied")) or status == "applied":
        return "applied"
    if status in {"no_active_voice", "out_of_row_no_op"} or bool(note_cut.get("ignored_as_no_op")):
        return "ignored/no-op"
    if bool(note_cut.get("deferred")):
        return "deferred/unsupported"
    return "unknown"


def note_delay_status(note_delay: dict[str, Any]) -> str:
    status = str(note_delay.get("status", ""))
    if bool(note_delay.get("applied")) or status == "applied":
        return "applied"
    if status == "out_of_row_no_op" or bool(note_delay.get("ignored_as_no_op")):
        return "ignored/no-op"
    if status == "no_note_deferred" or bool(note_delay.get("deferred")):
        return "deferred/unsupported"
    return "unknown"


def retrigger_status(retrigger: dict[str, Any]) -> str:
    status = str(retrigger.get("status", ""))
    if bool(retrigger.get("applied")) or status == "applied":
        return "applied"
    if status == "ignored_e90_no_effect_memory" or bool(retrigger.get("deferred")):
        return "deferred/no-op"
    if status in {"no_active_voice", "out_of_row_no_op"} or bool(retrigger.get("ignored_as_no_op")):
        return "ignored/no-op"
    return "unknown"


def tone_portamento_status(tone_portamento: dict[str, Any]) -> str:
    status = str(tone_portamento.get("status", ""))
    if bool(tone_portamento.get("applied")) or status == "applied":
        return "applied"
    if bool(tone_portamento.get("deferred")) or status.startswith("deferred"):
        return "deferred/unsupported"
    if status in {"no_active_voice", "no_target", "no_speed", "out_of_range"} or bool(tone_portamento.get("ignored_as_no_op")):
        return "ignored/no-op"
    return "unknown"


def portamento_slide_status(portamento: dict[str, Any]) -> str:
    status = str(portamento.get("status", ""))
    if bool(portamento.get("applied")) or status == "applied":
        return "applied"
    if status == "zero_param_effect_memory_deferred" or bool(portamento.get("deferred")):
        return "deferred/no-op"
    if status in {"no_active_voice", "out_of_range"} or bool(portamento.get("ignored_as_no_op")):
        return "ignored/no-op"
    return "unknown"


def timing_change_status(change: dict[str, Any]) -> str:
    if bool(change.get("applied")):
        return "applied"
    if change.get("kind") == "ignored_f00":
        return "ignored/no-op"
    return "unknown"


def extract_command_occurrences(
    diagnostics: dict[str, Any],
    events: list[dict[str, Any]],
    rows: list[dict[str, Any]],
    changes: list[dict[str, Any]],
) -> list[CommandOccurrence]:
    rows_by_source, rows_by_synthetic = row_frame_indexes(rows)
    occurrences: list[CommandOccurrence] = []

    sample_offset_keys = {
        (
            source_key(nested_dict(item.get("source")), item.get("channel_index")),
            int_or_none(item.get("effect_type")),
            int_or_none(item.get("effect_param")),
        )
        for item in nested_list(diagnostics.get("sample_offset_effects"))
        if isinstance(item, dict)
    }

    retrigger_keys = {
        (
            source_key(nested_dict(item.get("source")), item.get("channel_index")),
            int_or_none(item.get("effect_type")),
            int_or_none(item.get("effect_param")),
        )
        for item in nested_list(diagnostics.get("retrigger_effects"))
        if isinstance(item, dict)
    }

    volume_mapping_keys = {
        source_key(nested_dict(item.get("source")), item.get("channel_index"))
        for item in nested_list(diagnostics.get("volume_column_mappings"))
        if isinstance(item, dict)
    }

    for field in nested_list(diagnostics.get("deferred_fields")):
        if not isinstance(field, dict):
            continue
        domain = field.get("field")
        source = nested_dict(field.get("source"))
        channel = field.get("channel_index")
        if domain == "effect":
            effect_type = int_or_none(field.get("effect_type"))
            effect_param = int_or_none(field.get("effect_param"))
            if (source_key(source, channel), effect_type, effect_param) in sample_offset_keys:
                continue
            if (source_key(source, channel), effect_type, effect_param) in retrigger_keys:
                continue
            start_frame, end_frame = frame_range_for_diagnostic(field, rows_by_source, rows_by_synthetic)
            occurrences.append(CommandOccurrence(
                domain="effect",
                label=effect_command_label(effect_type, effect_param),
                status="deferred/unsupported",
                source=source,
                channel=channel,
                start_frame=start_frame,
                end_frame=end_frame,
                parameter=effect_param,
            ))
        elif domain == "volume_column" and source_key(source, channel) not in volume_mapping_keys:
            volume_column = nested_dict(field.get("volume_column"))
            start_frame, end_frame = frame_range_for_diagnostic(field, rows_by_source, rows_by_synthetic)
            occurrences.append(CommandOccurrence(
                domain="volume",
                label=volume_command_label(volume_column),
                status=volume_status(volume_column),
                source=source,
                channel=channel,
                start_frame=start_frame,
                end_frame=end_frame,
                parameter=volume_column.get("raw_value", field.get("volume_column_raw")),
            ))

    for sample_offset in nested_list(diagnostics.get("sample_offset_effects")):
        if not isinstance(sample_offset, dict):
            continue
        start_frame, end_frame = frame_range_for_diagnostic(sample_offset, rows_by_source, rows_by_synthetic)
        occurrences.append(CommandOccurrence(
            domain="effect",
            label=effect_command_label(sample_offset.get("effect_type"), sample_offset.get("effect_param")),
            status=sample_offset_status(sample_offset),
            source=nested_dict(sample_offset.get("source")),
            channel=sample_offset.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=sample_offset.get("effect_param"),
        ))

    for note_cut in nested_list(diagnostics.get("note_cut_effects")):
        if not isinstance(note_cut, dict):
            continue
        start_frame, end_frame = frame_range_for_diagnostic(note_cut, rows_by_source, rows_by_synthetic)
        occurrences.append(CommandOccurrence(
            domain="effect",
            label=effect_command_label(note_cut.get("effect_type"), note_cut.get("effect_param")),
            status=note_cut_status(note_cut),
            source=nested_dict(note_cut.get("source")),
            channel=note_cut.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=note_cut.get("effect_param"),
        ))

    for note_delay in nested_list(diagnostics.get("note_delay_effects")):
        if not isinstance(note_delay, dict):
            continue
        start_frame, end_frame = frame_range_for_diagnostic(note_delay, rows_by_source, rows_by_synthetic)
        occurrences.append(CommandOccurrence(
            domain="effect",
            label=effect_command_label(note_delay.get("effect_type"), note_delay.get("effect_param")),
            status=note_delay_status(note_delay),
            source=nested_dict(note_delay.get("source")),
            channel=note_delay.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=note_delay.get("effect_param"),
        ))

    for retrigger in nested_list(diagnostics.get("retrigger_effects")):
        if not isinstance(retrigger, dict):
            continue
        start_frame, end_frame = frame_range_for_diagnostic(retrigger, rows_by_source, rows_by_synthetic)
        frames = [
            value for value in (integer(frame) for frame in nested_list(retrigger.get("retrigger_frames")))
            if value is not None
        ]
        if frames:
            start_frame = min(frames)
            end_frame = max(frames) + 1
        occurrences.append(CommandOccurrence(
            domain="effect",
            label=effect_command_label(retrigger.get("effect_type"), retrigger.get("effect_param")),
            status=retrigger_status(retrigger),
            source=nested_dict(retrigger.get("source")),
            channel=retrigger.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=retrigger.get("effect_param"),
        ))

    for tone_portamento in nested_list(diagnostics.get("tone_portamento_effects")):
        if not isinstance(tone_portamento, dict):
            continue
        start_frame, end_frame = frame_range_for_diagnostic(tone_portamento, rows_by_source, rows_by_synthetic)
        frames = [
            value for value in (
                integer(update.get("scheduled_frame"))
                for update in nested_list(tone_portamento.get("step_updates"))
                if isinstance(update, dict)
            )
            if value is not None
        ]
        if frames:
            start_frame = min(frames)
            end_frame = max(frames) + 1
        occurrences.append(CommandOccurrence(
            domain="effect",
            label=effect_command_label(tone_portamento.get("effect_type"), tone_portamento.get("effect_param")),
            status=tone_portamento_status(tone_portamento),
            source=nested_dict(tone_portamento.get("source")),
            channel=tone_portamento.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=tone_portamento.get("effect_param"),
        ))

    for portamento in nested_list(diagnostics.get("portamento_slide_effects")):
        if not isinstance(portamento, dict):
            continue
        start_frame, end_frame = frame_range_for_diagnostic(portamento, rows_by_source, rows_by_synthetic)
        frames = [
            value for value in (
                integer(update.get("scheduled_frame"))
                for update in nested_list(portamento.get("step_updates"))
                if isinstance(update, dict)
            )
            if value is not None
        ]
        if frames:
            start_frame = min(frames)
            end_frame = max(frames) + 1
        occurrences.append(CommandOccurrence(
            domain="effect",
            label=effect_command_label(portamento.get("effect_type"), portamento.get("effect_param")),
            status=portamento_slide_status(portamento),
            source=nested_dict(portamento.get("source")),
            channel=portamento.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=portamento.get("effect_param"),
        ))

    if not nested_list(diagnostics.get("sample_offset_effects")):
        for event in events:
            sample_offset = nested_dict(event.get("sample_offset"))
            if not sample_offset or not sample_offset.get("detected"):
                continue
            occurrences.append(CommandOccurrence(
                domain="effect",
                label=effect_command_label(sample_offset.get("effect_type"), sample_offset.get("effect_param")),
                status=sample_offset_status(sample_offset),
                source=nested_dict(event.get("source")),
                channel=event.get("channel_index"),
                start_frame=event.get("_start_frame"),
                end_frame=event.get("_end_frame"),
                parameter=sample_offset.get("effect_param"),
            ))

    for change in changes:
        start_frame, end_frame = frame_range_for_diagnostic(change, rows_by_source, rows_by_synthetic)
        occurrences.append(CommandOccurrence(
            domain="effect",
            label=effect_command_label(change.get("effect_type"), change.get("effect_param")),
            status=timing_change_status(change),
            source=nested_dict(change.get("source")),
            channel=change.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=change.get("effect_param"),
        ))

    for mapping in nested_list(diagnostics.get("volume_column_mappings")):
        if not isinstance(mapping, dict):
            continue
        volume_column = nested_dict(mapping.get("volume_column"))
        start_frame, end_frame = frame_range_for_diagnostic(mapping, rows_by_source, rows_by_synthetic)
        occurrences.append(CommandOccurrence(
            domain="volume",
            label=volume_command_label(volume_column),
            status=volume_status(volume_column),
            source=nested_dict(mapping.get("source")),
            channel=mapping.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=volume_column.get("raw_value"),
        ))

    for update in nested_list(diagnostics.get("volume_panning_state_updates")):
        if not isinstance(update, dict):
            continue
        start_frame, end_frame = frame_range_for_diagnostic(update, rows_by_source, rows_by_synthetic)
        command_source = update.get("command_source")
        command_name = str(update.get("command_name", ""))
        label = str(update.get("command_label") or command_name or "volume/pan state update")
        if command_source == "volume_column":
            domain = "volume"
            if update.get("cell_note") == 0 and command_name == "setVolume":
                label = "empty-note volume-column set volume state update"
            elif update.get("cell_note") == 0 and command_name == "setPanning":
                label = "empty-note volume-column set panning state update"
            else:
                volume_column = nested_dict(nested_dict(update.get("command")).get("volume_column"))
                label = f"volume-column {volume_command_label(volume_column)} state update"
        else:
            domain = "effect"
        occurrences.append(CommandOccurrence(
            domain=domain,
            label=label,
            status=str(update.get("status", "unknown")),
            source=nested_dict(update.get("source")),
            channel=update.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=update.get("effect_param", update.get("raw_volume_column")),
        ))

    return occurrences


def tag_occurrences_with_windows(
    occurrences: list[CommandOccurrence],
    windows: list[dict[str, Any]],
) -> list[CommandOccurrence]:
    tagged = []
    for occurrence in occurrences:
        ranks: list[int] = []
        if occurrence.start_frame is not None and occurrence.end_frame is not None:
            for window in windows:
                if overlaps(occurrence.start_frame, occurrence.end_frame, window["_start_frame"], window["_end_frame"]):
                    ranks.append(int(window["_rank"]))
        tagged.append(replace(occurrence, window_ranks=tuple(ranks)))
    return tagged


def normalize_traversal_effects(
    diagnostics: dict[str, Any],
    rows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    rows_by_source, rows_by_synthetic = row_frame_indexes(rows)
    effects: list[dict[str, Any]] = []
    for raw_effect in nested_list(diagnostics.get("pattern_traversal_timing_effects")):
        if not isinstance(raw_effect, dict):
            continue
        start_frame, end_frame = frame_range_for_diagnostic(raw_effect, rows_by_source, rows_by_synthetic)
        effects.append({
            **raw_effect,
            "_start_frame": start_frame,
            "_end_frame": end_frame,
            "_window_relations": [],
        })
    effects.sort(key=lambda item: (
        sort_int(item.get("_start_frame")),
        sort_int(nested_dict(item.get("source")).get("order")),
        sort_int(nested_dict(item.get("source")).get("row")),
        sort_int(item.get("channel_index")),
    ))
    return effects


def tag_traversal_effects_with_windows(
    effects: list[dict[str, Any]],
    windows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    tagged = []
    for effect in effects:
        start_frame = integer(effect.get("_start_frame"))
        end_frame = integer(effect.get("_end_frame"))
        relations = []
        if start_frame is not None and end_frame is not None:
            for window in windows:
                rank = int(window["_rank"])
                if overlaps(start_frame, end_frame, window["_start_frame"], window["_end_frame"]):
                    relations.append(f"{rank} overlaps")
                elif start_frame <= window["_end_frame"]:
                    relations.append(f"{rank} before")
        tagged.append({**effect, "_window_relations": relations})
    return tagged


def int_or_none(value: Any) -> int | None:
    parsed = integer(value)
    return parsed if parsed is not None else None


def sort_int(value: Any) -> int:
    parsed = integer(value)
    return parsed if parsed is not None else sys.maxsize


def correlated_windows(
    windows: list[dict[str, Any]],
    events: list[dict[str, Any]],
    rows: list[dict[str, Any]],
    changes: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    correlated = []
    for window in windows:
        start_frame = window["_start_frame"]
        end_frame = window["_end_frame"]
        overlapping_events = [
            event for event in events
            if overlaps(event["_start_frame"], event["_end_frame"], start_frame, end_frame)
        ]
        preceding_events = [
            event for event in events
            if event["_start_frame"] <= start_frame and event not in overlapping_events
        ][-DEFAULT_PRECEDING_EVENTS:]
        overlapping_rows = [
            row for row in rows
            if overlaps(row["_start_frame"], row["_end_frame"], start_frame, end_frame)
        ][:DEFAULT_CONTEXT_ROWS]
        relevant_changes = [
            change for change in changes
            if relevant_timing_change(change, start_frame, end_frame, overlapping_rows, preceding_events, overlapping_events)
        ]
        correlated.append({
            "window": window,
            "overlapping_events": overlapping_events,
            "preceding_events": preceding_events,
            "overlapping_rows": overlapping_rows,
            "timing_changes": relevant_changes,
        })
    return correlated


def relevant_timing_change(
    change: dict[str, Any],
    start_frame: int,
    end_frame: int,
    rows: list[dict[str, Any]],
    preceding_events: list[dict[str, Any]],
    overlapping_events: list[dict[str, Any]],
) -> bool:
    row_start = integer(change.get("row_start_frame"))
    if row_start is not None and start_frame <= row_start < end_frame:
        return True
    change_source = nested_dict(change.get("source"))
    change_key = source_key(change_source, change.get("channel_index"))
    event_keys = {
        source_key(nested_dict(event.get("source")), event.get("channel_index"))
        for event in overlapping_events + preceding_events
    }
    row_keys = {
        (
            nested_dict(row.get("source")).get("order"),
            nested_dict(row.get("source")).get("pattern"),
            nested_dict(row.get("source")).get("row"),
            change.get("channel_index"),
        )
        for row in rows
    }
    return change_key in event_keys or change_key in row_keys


def build_correlation_report(
    comparison: dict[str, Any],
    diagnostics: dict[str, Any],
    *,
    label: str | None = None,
    metadata: str | None = None,
) -> str:
    sample_rate = extract_sample_rate(comparison, diagnostics)
    windows = extract_windows(comparison, sample_rate)
    events = normalize_events(diagnostics, sample_rate)
    rows = normalize_row_timing(diagnostics)
    changes = normalize_timing_changes(diagnostics)
    change_index = timing_change_index(changes)
    command_occurrences = tag_occurrences_with_windows(
        extract_command_occurrences(diagnostics, events, rows, changes),
        windows,
    )
    traversal_effects = tag_traversal_effects_with_windows(
        normalize_traversal_effects(diagnostics, rows),
        windows,
    )
    render = nested_dict(diagnostics.get("render"))
    correlated = correlated_windows(windows, events, rows, changes)

    lines = [
        "# Local Audio Correlation Report",
        "",
        "Approximate diagnostic evidence only; this report does not prove tracker semantic correctness.",
        "",
        "## Inputs",
    ]
    if label:
        lines.append(f"- Label: {label}")
    if metadata:
        lines.append(f"- Metadata: {metadata}")
    lines.extend([
        f"- Sample rate used for frame mapping: {sample_rate} Hz",
        f"- Worst mismatch windows: {len(windows)}",
        f"- Candidate diagnostic events: {len(events)}",
        f"- Row timing entries: {len(rows)}",
        f"- Fxx timing changes: {len(changes)}",
    ])
    if render:
        lines.extend([
            f"- Rendered frames: {format_optional(render.get('rendered_frame_count'))}",
            f"- Requested order range: {format_optional(render.get('requested_start_order_index'))}..<"
            f"{format_order_end(render)}",
            f"- Initial timing: speed {format_optional(render.get('initial_speed'))}, "
            f"BPM {format_optional(render.get('initial_bpm'))}",
        ])
        interpolation = render.get("sample_interpolation")
        if interpolation:
            lines.append(f"- Sample interpolation: {interpolation}")
    append_event_coverage_summary(lines, nested_dict(diagnostics.get("event_coverage")))
    append_traversal_hazard_summary(
        lines,
        nested_dict(diagnostics.get("traversal_hazard_summary")),
        traversal_effects,
    )
    append_pitch_modulation_summary(lines, command_occurrences)

    lines.extend([
        "",
        "## Correlated Windows",
    ])
    if not correlated:
        lines.append("- No worst mismatch windows were present in the comparison JSON.")

    for item in correlated:
        window = item["window"]
        lines.extend([
            "",
            f"### Window {window['_rank']}: {window['_start_seconds']:.6f}-{window['_end_seconds']:.6f} s "
            f"(frames {window['_start_frame']}-{window['_end_frame']})",
            "",
            f"- RMS difference: {format_optional_float(window.get('rms_difference'))}",
            f"- Max absolute difference: {format_optional_float(window.get('max_abs_sample_difference'))}",
            "",
            "#### Row Timing Context",
        ])
        append_row_table(lines, item["overlapping_rows"])
        lines.extend(["", "#### Overlapping Candidate Events"])
        append_event_table(lines, item["overlapping_events"], change_index)
        if not item["overlapping_events"]:
            lines.append(
                "- No candidate event frame range overlapped this mismatch window; review row context and preceding events."
            )
        lines.extend(["", "#### Recent Preceding Candidate Events"])
        append_event_table(lines, item["preceding_events"], change_index)
        lines.extend(["", "#### Relevant Fxx Timing Changes"])
        append_timing_change_table(lines, item["timing_changes"])

    append_command_frequency_summary(lines, command_occurrences, traversal_effects)

    lines.extend([
        "",
        "## Notes",
        "- Event overlap is approximate because looped events are bounded to the rendered segment and one-shot duration uses available sample-step diagnostics.",
        "- Missing diagnostics fields are reported as unavailable rather than inferred.",
        "- Use this report to choose a focused follow-up PR; do not treat it as an automatic audio fix.",
    ])
    return "\n".join(lines) + "\n"


def append_event_coverage_summary(lines: list[str], coverage: dict[str, Any]) -> None:
    if not coverage:
        return
    capacity = nested_dict(coverage.get("capacity"))
    skip_reasons = [
        item for item in nested_list(coverage.get("skip_reason_counts"))
        if isinstance(item, dict)
    ]
    top_reasons = ", ".join(
        f"{format_optional(item.get('reason'))}={format_optional(item.get('count'))}"
        for item in skip_reasons[:5]
    )
    skipped = [
        item for item in nested_list(coverage.get("first_skipped_note_coordinates"))
        if isinstance(item, dict)
    ]
    lines.extend([
        "",
        "## Event Coverage",
        f"- Normal note cells: {format_optional(coverage.get('normal_note_cells'))}",
        f"- Note-off cells: {format_optional(coverage.get('note_off_cells'))}",
        f"- Scheduled note events: {format_optional(coverage.get('scheduled_note_events'))}",
        f"- Skipped note events: {format_optional(coverage.get('skipped_note_events'))}",
        f"- Sample-map selection events: {format_optional(coverage.get('sample_map_selection_events'))}",
        f"- First-playable-sample fallback events: {format_optional(coverage.get('first_playable_sample_fallback_events'))}",
        f"- Fallback-after-invalid-map events: {format_optional(coverage.get('fallback_after_invalid_sample_map_events'))}",
        f"- Skipped-no-valid-sample events: {format_optional(coverage.get('skipped_no_valid_sample_events'))}",
        f"- Sample-map/keymap missing or deferred events: {format_optional(coverage.get('sample_map_keymap_missing_or_deferred_events', coverage.get('sample_map_keymap_deferred_events')))}",
        f"- Top skip reasons: {top_reasons if top_reasons else 'none'}",
    ])
    if capacity:
        scheduled_capacity = capacity.get(
            "scheduled_voice_capacity",
            capacity.get("c_mixer_scheduled_voice_capacity", capacity.get("c_mixer_voice_capacity"))
        )
        active_capacity = capacity.get(
            "active_voice_capacity",
            capacity.get("c_mixer_active_voice_capacity", capacity.get("c_mixer_voice_capacity"))
        )
        lines.append(
            "- C mixer scheduling: "
            f"{format_optional(capacity.get('scheduled_voice_accepted_count'))}/"
            f"{format_optional(capacity.get('scheduled_voice_attempt_count'))} accepted, "
            f"{format_optional(capacity.get('scheduled_voice_rejected_count'))} rejected, "
            f"scheduled capacity {format_optional(scheduled_capacity)}, "
            f"active capacity {format_optional(active_capacity)}"
        )
    if skipped:
        lines.append(
            "- First skipped note coordinates: "
            + "; ".join(skipped_note_label(item) for item in skipped[:5])
        )
    else:
        lines.append("- First skipped note coordinates: none")


def append_traversal_hazard_summary(
    lines: list[str],
    summary: dict[str, Any],
    traversal_effects: list[dict[str, Any]],
) -> None:
    derived_counts = traversal_counts(traversal_effects)
    bxx_count = integer(summary.get("total_bxx_position_jump"))
    dxx_count = integer(summary.get("total_dxx_pattern_break"))
    eex_count = integer(summary.get("total_eex_pattern_delay"))
    fxx_count = integer(summary.get("total_fxx_speed_bpm"))
    e9x_count = integer(summary.get("total_e9x_retrigger"))
    ecx_count = integer(summary.get("total_ecx_note_cut"))
    edx_count = integer(summary.get("total_edx_note_delay"))
    other_e_count = integer(summary.get("total_other_e_commands"))
    total_hazards = integer(summary.get("total_traversal_hazards"))
    if bxx_count is None:
        bxx_count = derived_counts["Bxx position jump"]
    if dxx_count is None:
        dxx_count = derived_counts["Dxx pattern break"]
    if eex_count is None:
        eex_count = derived_counts["EEx pattern delay"]
    if fxx_count is None:
        fxx_count = sum(1 for effect in traversal_effects if effect.get("effect_label") == "Fxx speed/BPM")
    if e9x_count is None:
        e9x_count = sum(1 for effect in traversal_effects if effect.get("effect_label") == "E9x retrigger")
    if ecx_count is None:
        ecx_count = sum(1 for effect in traversal_effects if effect.get("effect_label") == "ECx note cut")
    if edx_count is None:
        edx_count = sum(1 for effect in traversal_effects if effect.get("effect_label") == "EDx note delay")
    if other_e_count is None:
        other_e_count = sum(
            1 for effect in traversal_effects
            if int_or_none(effect.get("effect_type")) == 0x0E
            and effect.get("effect_label") not in {"E9x retrigger", "EEx pattern delay", "ECx note cut", "EDx note delay"}
        )
    if total_hazards is None:
        total_hazards = bxx_count + dxx_count + eex_count
    likely_ignores = summary.get("likely_ignores_structure_changing_behavior")
    if not isinstance(likely_ignores, bool):
        likely_ignores = total_hazards > 0

    lines.extend([
        "",
        "## Pattern Traversal / Timing Hazards",
        f"- Bxx position jumps: {bxx_count}",
        f"- Dxx pattern breaks: {dxx_count}",
        f"- EEx pattern delays: {eex_count}",
        f"- Fxx speed/BPM timing changes: {fxx_count}",
        f"- E9x retriggers: {e9x_count}",
        f"- ECx note cuts: {ecx_count}",
        f"- EDx note delays: {edx_count}",
        f"- Other E-command diagnostics: {other_e_count}",
        f"- Total traversal hazards: {total_hazards}",
        f"- Bounded render likely ignores structure-changing behavior: {str(likely_ignores).lower()}",
    ])

    e_counts = [
        item for item in nested_list(summary.get("e_command_subtype_counts"))
        if isinstance(item, dict)
    ]
    if e_counts:
        lines.append(
            "- E-command subtype counts: "
            + ", ".join(
                f"{format_optional(item.get('label'))}={format_optional(item.get('count'))}"
                for item in e_counts
            )
        )

    hazards_near_windows = [
        effect for effect in traversal_effects
        if is_traversal_hazard_effect(effect) and effect.get("_window_relations")
    ]
    if not hazards_near_windows:
        lines.append("- Traversal hazards in or before top mismatch windows: none")
        return

    lines.extend([
        "",
        "| Effect | Status | Source | Channel | Param | Window Relation |",
        "| --- | --- | --- | ---: | ---: | --- |",
    ])
    for effect in hazards_near_windows[:10]:
        lines.append(
            f"| {format_optional(effect.get('effect_label', effect.get('decoded_label')))} | "
            f"{format_optional(effect.get('current_status', effect.get('status')))} | "
            f"{source_label(nested_dict(effect.get('source')))} | "
            f"{format_optional(effect.get('channel_index'))} | "
            f"{format_optional(effect.get('effect_param'))} | "
            f"{'; '.join(effect.get('_window_relations', []))} |"
        )


def append_pitch_modulation_summary(
    lines: list[str],
    occurrences: list[CommandOccurrence],
) -> None:
    pitch_occurrences = pitch_modulation_occurrences(occurrences)
    overall_counts = pitch_category_counts(pitch_occurrences)
    near_window_occurrences = [occurrence for occurrence in pitch_occurrences if occurrence.window_ranks]
    near_counts = pitch_category_counts(near_window_occurrences)
    recommendation, rationale, ranking = recommend_pitch_effect_pr(pitch_occurrences)

    lines.extend([
        "",
        "## Pitch Modulation / Deferred Effect Diagnostics",
        f"- Arpeggio: {overall_counts['arpeggio']} overall, {near_counts['arpeggio']} near top mismatch windows",
        f"- Portamento: {overall_counts['portamento']} overall, {near_counts['portamento']} near top mismatch windows",
        f"- Vibrato: {overall_counts['vibrato']} overall, {near_counts['vibrato']} near top mismatch windows",
        f"- Tremolo: {overall_counts['tremolo']} overall, {near_counts['tremolo']} near top mismatch windows",
        f"- Recommended next pitch-effect PR: {recommendation}",
        f"- Pitch-effect rationale: {rationale}",
    ])

    if not pitch_occurrences:
        lines.append("- Deferred pitch-modulation effect coordinates: none")
        return

    dominant_category = ranking[0][0] if ranking else dominant_pitch_category(overall_counts)
    if dominant_category is None:
        lines.append("- First dominant deferred pitch-modulation coordinates: none")
        return
    dominant_near = [
        occurrence for occurrence in near_window_occurrences
        if PITCH_LABEL_TO_CATEGORY.get(occurrence.label) == dominant_category
    ]
    dominant_all = [
        occurrence for occurrence in pitch_occurrences
        if PITCH_LABEL_TO_CATEGORY.get(occurrence.label) == dominant_category
    ]
    examples = dominant_near or dominant_all
    if not examples:
        lines.append("- First dominant deferred pitch-modulation coordinates: none")
        return

    lines.extend([
        "",
        "### First dominant deferred pitch-modulation coordinates",
        "| Category | Effect | Status | Source | Channel | Param | Worst Windows |",
        "| --- | --- | --- | --- | ---: | ---: | --- |",
    ])
    for occurrence in examples[:MAX_EXAMPLES_PER_COMMAND]:
        windows = ", ".join(str(rank) for rank in occurrence.window_ranks) if occurrence.window_ranks else "not in top windows"
        category = PITCH_CATEGORY_DISPLAY.get(
            PITCH_LABEL_TO_CATEGORY.get(occurrence.label, ""),
            "Pitch modulation",
        )
        lines.append(
            f"| {category} | {occurrence.label} | {occurrence.status} | "
            f"{source_label(occurrence.source)} | {format_optional(occurrence.channel)} | "
            f"{format_optional(occurrence.parameter)} | {windows} |"
        )


def pitch_modulation_occurrences(
    occurrences: list[CommandOccurrence],
) -> list[CommandOccurrence]:
    return [
        occurrence for occurrence in occurrences
        if occurrence.status.startswith("deferred")
        and occurrence.label in PITCH_LABEL_TO_CATEGORY
    ]


def pitch_category_counts(
    occurrences: list[CommandOccurrence],
) -> Counter:
    counts: Counter = Counter()
    for occurrence in occurrences:
        category = PITCH_LABEL_TO_CATEGORY.get(occurrence.label)
        if category is not None:
            counts[category] += 1
    return counts


def dominant_pitch_category(counts: Counter) -> str | None:
    ranked = sorted(
        ((category, counts[category]) for category in PITCH_CATEGORY_DISPLAY if counts[category] > 0),
        key=lambda item: (-item[1], item[0]),
    )
    return ranked[0][0] if ranked else None


def recommend_pitch_effect_pr(
    occurrences: list[CommandOccurrence],
) -> tuple[str, str, list[tuple[str, int]]]:
    near = [occurrence for occurrence in occurrences if occurrence.window_ranks]
    evidence = near if near else occurrences
    counts = pitch_category_counts(evidence)
    ranking = sorted(
        [(category, counts[category]) for category in PITCH_CATEGORY_DISPLAY if counts[category] > 0],
        key=lambda item: (-item[1], item[0]),
    )
    if not ranking:
        return (
            "No clear pitch-effect target",
            "No deferred arpeggio, portamento, vibrato, or tremolo diagnostics were present.",
            [],
        )

    top_category, top_score = ranking[0]
    total = sum(score for _, score in ranking)
    tied = len(ranking) > 1 and ranking[1][1] == top_score
    minimum_score = max(2, math.ceil(total * 0.4))
    if tied or top_score < minimum_score:
        return (
            "No clear pitch-effect target",
            "Deferred pitch-modulation counts are sparse or split across categories.",
            ranking,
        )

    return (
        PITCH_CATEGORY_RECOMMENDATIONS[top_category],
        "This heuristic ranks deferred pitch-modulation diagnostics in the top mismatch windows when present, otherwise overall bounded diagnostics.",
        ranking,
    )


def traversal_counts(traversal_effects: list[dict[str, Any]]) -> Counter:
    return Counter(
        effect.get("effect_label", effect.get("decoded_label"))
        for effect in traversal_effects
        if is_traversal_hazard_effect(effect)
    )


def is_traversal_hazard_effect(effect: dict[str, Any]) -> bool:
    if bool(effect.get("is_traversal_hazard")):
        return True
    label = effect.get("effect_label", effect.get("decoded_label"))
    return label in TRAVERSAL_HAZARD_LABELS


def skipped_note_label(item: dict[str, Any]) -> str:
    source = source_label(nested_dict(item.get("source")))
    return (
        f"{source} ch {format_optional(item.get('channel_index'))} "
        f"note {format_optional(item.get('note'))} "
        f"reason {format_optional(item.get('reason'))}"
    )


def append_command_frequency_summary(
    lines: list[str],
    occurrences: list[CommandOccurrence],
    traversal_effects: list[dict[str, Any]],
) -> None:
    lines.extend([
        "",
        "## Effect And Volume Command Frequency",
        "",
        "Counts below are local diagnostic evidence from bounded adapter diagnostics. "
        "They distinguish applied, ignored/no-op, deferred/unsupported, and unknown command handling.",
    ])

    worst_occurrences = [occurrence for occurrence in occurrences if occurrence.window_ranks]
    append_frequency_section(
        lines,
        "Deferred effect commands in worst windows",
        filtered_occurrences(worst_occurrences, domain="effect", status_prefix="deferred"),
    )
    append_frequency_section(
        lines,
        "Applied effect commands in worst windows",
        filtered_occurrences(worst_occurrences, domain="effect", status_prefix="applied"),
    )
    append_frequency_section(
        lines,
        "Ignored/no-op effect commands in worst windows",
        filtered_occurrences(worst_occurrences, domain="effect", status_prefix="ignored"),
    )
    append_frequency_section(
        lines,
        "Unknown effect commands in worst windows",
        filtered_occurrences(worst_occurrences, domain="effect", status_prefix="unknown"),
    )
    append_frequency_section(
        lines,
        "Deferred volume-column commands in worst windows",
        filtered_occurrences(worst_occurrences, domain="volume", status_prefix="deferred"),
    )
    append_frequency_section(
        lines,
        "Applied volume-column commands in worst windows",
        filtered_occurrences(worst_occurrences, domain="volume", status_prefix="applied"),
    )
    append_frequency_section(
        lines,
        "Ignored/no-op volume-column commands in worst windows",
        filtered_occurrences(worst_occurrences, domain="volume", status_prefix="ignored"),
    )
    append_frequency_section(
        lines,
        "Unknown volume-column commands in worst windows",
        filtered_occurrences(worst_occurrences, domain="volume", status_prefix="unknown"),
    )
    append_frequency_section(lines, "Overall command frequency in bounded render", occurrences)
    append_frequency_section(
        lines,
        "Overall deferred command frequency in bounded render",
        [occurrence for occurrence in occurrences if occurrence.status.startswith("deferred")],
    )
    append_recommendation(lines, occurrences, traversal_effects)


def filtered_occurrences(
    occurrences: list[CommandOccurrence],
    *,
    domain: str,
    status_prefix: str,
) -> list[CommandOccurrence]:
    return [
        occurrence for occurrence in occurrences
        if occurrence.domain == domain and occurrence.status.startswith(status_prefix)
    ]


def append_frequency_section(
    lines: list[str],
    title: str,
    occurrences: list[CommandOccurrence],
) -> None:
    lines.extend(["", f"### {title}"])
    if not occurrences:
        lines.append("- None.")
        return

    lines.extend([
        "| Command | Status | Count | Worst Windows | Example Sources |",
        "| --- | --- | ---: | --- | --- |",
    ])
    for item in grouped_occurrences(occurrences):
        lines.append(
            f"| {item['label']} | {item['status']} | {item['count']} | "
            f"{item['windows']} | {item['examples']} |"
        )


def grouped_occurrences(
    occurrences: list[CommandOccurrence],
) -> list[dict[str, Any]]:
    groups: dict[tuple[str, str], list[CommandOccurrence]] = defaultdict(list)
    for occurrence in occurrences:
        groups[(occurrence.label, occurrence.status)].append(occurrence)

    rows = []
    for (label, status), items in groups.items():
        window_ranks = sorted({rank for item in items for rank in item.window_ranks})
        examples = unique_preserving_order(occurrence_source_label(item) for item in items)
        rows.append({
            "label": label,
            "status": status,
            "count": len(items),
            "windows": ", ".join(str(rank) for rank in window_ranks) if window_ranks else "not in top windows",
            "examples": "; ".join(examples[:MAX_EXAMPLES_PER_COMMAND]),
        })
    rows.sort(key=lambda row: (-row["count"], row["label"], row["status"]))
    return rows


def unique_preserving_order(values: Any) -> list[str]:
    seen = set()
    unique = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        unique.append(value)
    return unique


def occurrence_source_label(occurrence: CommandOccurrence) -> str:
    source = source_label(occurrence.source)
    channel = format_optional(occurrence.channel)
    return f"{source} ch {channel}"


def append_recommendation(
    lines: list[str],
    occurrences: list[CommandOccurrence],
    traversal_effects: list[dict[str, Any]],
) -> None:
    recommendation, rationale, ranking = recommend_next_pr(occurrences, traversal_effects)
    lines.extend([
        "",
        "### Candidate next PR ranking",
        f"- Recommended next PR: {recommendation}",
        f"- Rationale: {rationale}",
    ])
    if not ranking:
        lines.append("- Ranking signals: none from deferred commands in top mismatch windows.")
        return
    lines.append("- Ranking signals:")
    for label, score in ranking:
        lines.append(f"  - {label}: {score}")


def recommend_next_pr(
    occurrences: list[CommandOccurrence],
    traversal_effects: list[dict[str, Any]] | None = None,
) -> tuple[str, str, list[tuple[str, int]]]:
    deferred_worst = [
        occurrence for occurrence in occurrences
        if occurrence.status.startswith("deferred")
        and occurrence.window_ranks
    ]
    traversal_effects = traversal_effects or []
    traversal_signals = traversal_signal_counts(traversal_effects)
    if not deferred_worst and not traversal_signals:
        return (
            "No clear single target; review local listening/correlation evidence or improve diagnostics.",
            "No deferred command or traversal hazard appears in or before the top mismatch windows.",
            [],
        )

    label_counts = Counter(occurrence.label for occurrence in deferred_worst)
    traversal_break_jump_score = max(
        label_counts["Dxx pattern break"] + label_counts["Bxx position jump"],
        traversal_signals["Dxx pattern break"] + traversal_signals["Bxx position jump"],
    )
    traversal_delay_score = max(
        label_counts["EEx pattern delay"],
        traversal_signals["EEx pattern delay"],
    )
    scores = {
        "Minimal Note Cut ECx / Note Delay EDx for Bounded Offline Renders":
            label_counts["ECx note cut"] + label_counts["EDx note delay"],
        "Minimal Retrigger E9x for Bounded Offline Renders":
            label_counts["E9x retrigger"],
        "Sample Offset 900 Effect Memory Follow-Up":
            label_counts["900 sample offset / effect memory"],
        "Minimal Pattern Break Dxx / Position Jump Bxx for Bounded Offline Traversal":
            traversal_break_jump_score,
        "Minimal Pattern Delay EEx for Bounded Offline Renders":
            traversal_delay_score,
    }
    pitch_recommendation, _, pitch_ranking = recommend_pitch_effect_pr(
        [occurrence for occurrence in deferred_worst if occurrence.label in PITCH_LABEL_TO_CATEGORY]
    )
    if pitch_ranking and pitch_recommendation != "No clear pitch-effect target":
        scores[pitch_recommendation] = pitch_ranking[0][1]
    ranking = sorted(
        [(label, score) for label, score in scores.items() if score > 0],
        key=lambda item: (-item[1], item[0]),
    )
    if not ranking:
        return (
            "No clear single target; review local listening/correlation evidence or improve diagnostics.",
            "Deferred effect commands are present, but they do not match a focused heuristic bucket.",
            [],
        )

    top_label, top_score = ranking[0]
    total = max(sum(label_counts.values()), sum(traversal_signals.values()))
    tied = len(ranking) > 1 and ranking[1][1] == top_score
    minimum_score = 1 if total == 1 else max(2, math.ceil(total * 0.4))
    if tied or top_score < minimum_score:
        return (
            "No clear single target; review local listening/correlation evidence or improve diagnostics.",
            "The top deferred command bucket does not dominate the mismatch-window evidence.",
            ranking,
        )
    return (
        top_label,
        "This heuristic only ranks deferred effect commands and traversal hazards in or before the top mismatch windows; it is not an automatic correctness decision.",
        ranking,
    )


def traversal_signal_counts(traversal_effects: list[dict[str, Any]]) -> Counter:
    counts: Counter = Counter()
    seen = set()
    for effect in traversal_effects:
        if not is_traversal_hazard_effect(effect) or not effect.get("_window_relations"):
            continue
        label = effect.get("effect_label", effect.get("decoded_label"))
        if label not in TRAVERSAL_HAZARD_LABELS:
            continue
        identity = (
            source_key(nested_dict(effect.get("source")), effect.get("channel_index")),
            int_or_none(effect.get("effect_type")),
            int_or_none(effect.get("effect_param")),
        )
        if identity in seen:
            continue
        seen.add(identity)
        counts[label] += 1
    return counts


def append_row_table(lines: list[str], rows: list[dict[str, Any]]) -> None:
    if not rows:
        lines.append("- No row timing diagnostics overlap this mismatch window.")
        return
    lines.extend([
        "| Source | Synthetic Row | Frame Range | Timing |",
        "| --- | ---: | --- | --- |",
    ])
    for row in rows:
        lines.append(
            f"| {source_label(nested_dict(row.get('source')))} | "
            f"{format_optional(row.get('synthetic_row'))} | "
            f"{row['_start_frame']}-{row['_end_frame']} | "
            f"speed {format_optional(row.get('effective_speed'))}, BPM {format_optional(row.get('effective_bpm'))} |"
        )


def append_event_table(
    lines: list[str],
    events: list[dict[str, Any]],
    change_index: dict[tuple[Any, Any, Any, Any], list[dict[str, Any]]],
) -> None:
    if not events:
        lines.append("- None.")
        return
    lines.extend([
        "| Source | Channel | Note | Instrument/Sample | Sample Selection | Frames | Pitch | Gain/Pan | Volume Column | Sample Offset | Fxx | Envelope | Loop |",
        "| --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ])
    for event in events:
        source = nested_dict(event.get("source"))
        channel = event.get("channel_index")
        key = source_key(source, channel)
        lines.append(
            f"| {source_label(source)} | "
            f"{format_optional(channel)} | "
            f"{format_optional(event.get('note'))} | "
            f"{format_optional(event.get('instrument_index'))}/{format_optional(event.get('sample_index'))} | "
            f"{sample_selection_label(event)} | "
            f"{event['_start_frame']}-{event['_end_frame']} | "
            f"{pitch_label(nested_dict(event.get('pitch')))} | "
            f"{format_optional_float(event.get('gain'))}/{format_optional_float(event.get('pan'))} | "
            f"{volume_column_label(nested_dict(event.get('volume_column')))} | "
            f"{sample_offset_label(nested_dict(event.get('sample_offset')))} | "
            f"{fxx_label(change_index.get(key, []))} | "
            f"{envelope_label(nested_dict(event.get('volume_envelope')))} | "
            f"{format_optional(event.get('loop_mode'))} |"
        )


def append_timing_change_table(lines: list[str], changes: list[dict[str, Any]]) -> None:
    if not changes:
        lines.append("- None tied to overlapping rows/events.")
        return
    lines.extend([
        "| Source | Channel | Row Frame | Kind | Param | Applied | Timing Before | Timing After |",
        "| --- | ---: | ---: | --- | ---: | --- | --- | --- |",
    ])
    for change in changes:
        lines.append(
            f"| {source_label(nested_dict(change.get('source')))} | "
            f"{format_optional(change.get('channel_index'))} | "
            f"{format_optional(change.get('row_start_frame'))} | "
            f"{format_optional(change.get('kind'))} | "
            f"{format_optional(change.get('effect_param'))} | "
            f"{format_optional(change.get('applied'))} | "
            f"speed {format_optional(change.get('speed_before'))}, BPM {format_optional(change.get('bpm_before'))} | "
            f"speed {format_optional(change.get('speed_after'))}, BPM {format_optional(change.get('bpm_after'))} |"
        )


def source_label(source: dict[str, Any]) -> str:
    if not source:
        return "source unavailable"
    return (
        f"order {format_optional(source.get('order'))} "
        f"pattern {format_optional(source.get('pattern'))} "
        f"row {format_optional(source.get('row'))}"
    )


def pitch_label(pitch: dict[str, Any]) -> str:
    if not pitch:
        return "unavailable"
    parts = [f"step {format_optional_float(pitch.get('playback_step'))}"]
    period = number(pitch.get("linear_period"))
    frequency = number(pitch.get("linear_frequency"))
    if period is not None:
        parts.append(f"period {period:.4f}")
    if frequency is not None:
        parts.append(f"freq {frequency:.4f}")
    status = pitch.get("frequency_table_status")
    if status is not None:
        parts.append(str(status))
    if pitch.get("amiga_frequency_deferred"):
        parts.append("amiga deferred")
    if pitch.get("fallback_neutral_step_used") or pitch.get("used_neutral_step"):
        parts.append("neutral fallback")
    return "; ".join(parts)


def volume_column_label(volume_column: dict[str, Any]) -> str:
    if not volume_column:
        return "unavailable"
    command = nested_dict(volume_column.get("command"))
    command_name = command.get("name", "unknown")
    detail = command.get("value", command.get("amount", command.get("raw_value")))
    if detail is not None:
        command_name = f"{command_name}({detail})"
    return (
        f"raw {format_optional(volume_column.get('raw_value'))} "
        f"{command_name} / {format_optional(volume_column.get('classification'))}"
    )


def sample_offset_label(sample_offset: dict[str, Any]) -> str:
    if not sample_offset:
        return "unavailable"
    status = str(sample_offset.get("status", "unavailable"))
    computed = integer(sample_offset.get("computed_offset_frames"))
    applied = integer(sample_offset.get("applied_offset_frames"))
    selected_length = integer(sample_offset.get("selected_sample_length"))
    if status == "not_present":
        return "none"
    if status == "applied":
        return f"9xx applied offset {format_optional(applied)}"
    if status == "ignored_900_no_op":
        return "900 ignored no-op"
    if status == "out_of_range_skipped":
        return (
            f"9xx skipped offset {format_optional(computed)} "
            f"len {format_optional(selected_length)}"
        )
    return status


def sample_selection_label(event: dict[str, Any]) -> str:
    method = event.get("sample_selection_method") or event.get("selected_sample_selection_method")
    if method is None:
        method = event.get("sample_selection_strategy")
    if method is None:
        return "unavailable"
    mapped = event.get("mapped_sample_index")
    valid = event.get("mapped_sample_valid")
    present = event.get("sample_map_keymap_present")
    parts = [str(method)]
    if mapped is not None:
        parts.append(f"mapped {format_optional(mapped)}")
    if valid is not None:
        parts.append(f"valid {format_optional(valid)}")
    if present is not None:
        parts.append(f"map {format_optional(present)}")
    if event.get("first_playable_sample_fallback_used"):
        parts.append("fallback")
    return "; ".join(parts)


def fxx_label(changes: list[dict[str, Any]]) -> str:
    if not changes:
        return "none"
    formatted = []
    for change in changes:
        formatted.append(
            f"{format_optional(change.get('kind'))} F{int_or_zero(change.get('effect_param')):02X} "
            f"{format_optional(change.get('speed_before'))}/{format_optional(change.get('bpm_before'))}"
            f"->{format_optional(change.get('speed_after'))}/{format_optional(change.get('bpm_after'))}"
        )
    return "; ".join(formatted)


def envelope_label(envelope: dict[str, Any]) -> str:
    if not envelope:
        return "unavailable"
    applied = []
    if envelope.get("sustain_applied"):
        applied.append("sustain")
    if envelope.get("loop_applied"):
        applied.append("loop")
    if envelope.get("key_off_applied"):
        applied.append("key-off")
    if envelope.get("fadeout_applied"):
        applied.append("fadeout")
    deferred = []
    if envelope.get("has_deferred_sustain"):
        deferred.append("sustain")
    if envelope.get("has_deferred_loop"):
        deferred.append("loop")
    if envelope.get("has_deferred_fadeout"):
        deferred.append("fadeout")
    if envelope.get("key_off_deferred"):
        deferred.append("key-off")
    applied_suffix = f"; applied {','.join(applied)}" if applied else ""
    suffix = f"; deferred {','.join(deferred)}" if deferred else ""
    return (
        f"{format_optional(envelope.get('status'))} "
        f"{format_optional(envelope.get('mapped_point_count'))}/{format_optional(envelope.get('source_point_count'))}"
        f"{applied_suffix}{suffix}"
    )


def format_order_end(render: dict[str, Any]) -> str:
    start = integer(render.get("requested_start_order_index"))
    count = integer(render.get("requested_order_count"))
    if start is None or count is None:
        return "unavailable"
    return str(start + count)


def format_optional(value: Any) -> str:
    if value is None:
        return "unavailable"
    return str(value)


def format_optional_float(value: Any) -> str:
    numeric = number(value)
    if numeric is None:
        return "unavailable"
    return f"{numeric:.8f}"


def int_or_zero(value: Any) -> int:
    parsed = integer(value)
    return parsed if parsed is not None else 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Correlate scripts/audio-compare.py worst mismatch windows with "
            "local bounded PlaybackSong adapter diagnostics."
        )
    )
    parser.add_argument("--comparison-json", required=True, type=Path, help="JSON from scripts/audio-compare.py")
    parser.add_argument("--diagnostics-json", required=True, type=Path, help="Bounded candidate diagnostics JSON")
    parser.add_argument("--output-markdown", required=True, type=Path, help="Local correlation Markdown report path")
    parser.add_argument("--label", help="Optional local run label")
    parser.add_argument("--metadata", help="Optional local render/reference notes")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        comparison = load_json(args.comparison_json, "comparison")
        diagnostics = load_json(args.diagnostics_json, "diagnostics")
        report = build_correlation_report(
            comparison,
            diagnostics,
            label=args.label,
            metadata=args.metadata,
        )
    except CorrelationError as error:
        print(f"audio-correlation: {error}", file=sys.stderr)
        return 1

    args.output_markdown.parent.mkdir(parents=True, exist_ok=True)
    args.output_markdown.write_text(report, encoding="utf-8")
    print(f"Correlation report: {args.output_markdown}")
    print("Approximate local diagnostic evidence only; no audio fixes were applied.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
