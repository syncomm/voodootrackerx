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
MAX_MECHANICS_EXAMPLES = 5
MAX_ENVELOPE_GAIN_EXAMPLES = 5
MAX_PERIOD_SAMPLE_STEP_EXAMPLES = 8
MAX_GAIN_PAN_EXAMPLES = 8
MAX_SAMPLE_INSTRUMENT_EXAMPLES = 8
MAX_LOOP_CROSSING_EXAMPLES = 8
MAX_STEADY_STATE_LOOP_EXAMPLES = 8
FRACTION_EPSILON = 1.0e-9
AUDIBLE_GAIN_EPSILON = 1.0e-6
TRAVERSAL_HAZARD_LABELS = {"Bxx position jump", "Dxx pattern break", "E6x pattern loop", "EEx pattern delay"}
STEP_UPDATE_SECTIONS = (
    ("arpeggio_effects", "0xy arpeggio"),
    ("tone_portamento_effects", "3xx tone portamento"),
    ("portamento_slide_effects", "1xx/2xx portamento slide"),
    ("fine_portamento_up_effects", "E1x fine portamento up"),
    ("fine_portamento_down_effects", "E2x fine portamento down"),
    ("vibrato_effects", "4xy/6xy vibrato"),
)
PITCH_LABEL_TO_CATEGORY = {
    "0xy arpeggio": "arpeggio",
    "1xx portamento up": "portamento",
    "2xx portamento down": "portamento",
    "3xx tone portamento": "portamento",
    "5xy tone portamento + volume slide": "portamento",
    "tone portamento": "portamento",
    "E2x fine portamento down": "portamento",
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
    "arpeggio": "Minimal 0xy Arpeggio Foundation",
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


@dataclass(frozen=True)
class SourcePositionEstimate:
    raw_position: float
    rendered_position: float | None
    fractional_part: float | None
    boundary_crossing_count: int | None


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
    replacement_completion_by_event = replacement_completion_frames_by_event(diagnostics)
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
        event_index = integer(raw_event.get("event_index"))
        replacement_completion_frame = None
        if event_index is not None:
            replacement_completion_frame = replacement_completion_by_event.get(event_index)
            if replacement_completion_frame is not None:
                end_frame = min(end_frame, max(start_frame + 1, replacement_completion_frame))
        event = {
            **raw_event,
            "_start_frame": max(0, start_frame),
            "_end_frame": max(start_frame + 1, end_frame),
        }
        if replacement_completion_frame is not None:
            event["_same_channel_replacement_completion_frame"] = replacement_completion_frame
        events.append(event)
    events.sort(key=lambda item: (item["_start_frame"], item.get("event_index", 0)))
    return events


def replacement_completion_frames_by_event(diagnostics: dict[str, Any]) -> dict[int, int]:
    completions: dict[int, int] = {}
    for replacement in nested_list(nested_dict(diagnostics.get("same_channel_voice_lifetime")).get("replacement_events")):
        if not isinstance(replacement, dict):
            continue
        old_event_index, completion_frame = integer(replacement.get("old_event_index")), integer(replacement.get("completion_frame"))
        if old_event_index is None or completion_frame is None:
            continue
        existing = completions.get(old_event_index)
        if existing is None or completion_frame < existing:
            completions[old_event_index] = completion_frame
    return completions


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
        if subcommand == 0x02:
            return "E2x fine portamento down"
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
    if effect_type == 0x10:
        return "Gxx set global volume"
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


def fine_portamento_down_status(portamento: dict[str, Any]) -> str:
    status = str(portamento.get("status", ""))
    if bool(portamento.get("applied")) or status == "applied":
        return "applied"
    if status == "zero_amount_effect_memory_deferred" or bool(portamento.get("deferred")):
        return "deferred/no-op"
    if status in {"no_active_voice", "out_of_range"} or bool(portamento.get("ignored_as_no_op")):
        return "ignored/no-op"
    return "unknown"


def fine_portamento_up_status(portamento: dict[str, Any]) -> str:
    return fine_portamento_down_status(portamento)


def arpeggio_status(arpeggio: dict[str, Any]) -> str:
    status = str(arpeggio.get("status", ""))
    if bool(arpeggio.get("applied")) or status == "applied":
        return "applied"
    if bool(arpeggio.get("deferred")) or status.startswith("deferred"):
        return "deferred/unsupported"
    if status in {"no_active_voice", "out_of_range"} or bool(arpeggio.get("ignored_as_no_op")):
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

    for arpeggio in nested_list(diagnostics.get("arpeggio_effects")):
        if not isinstance(arpeggio, dict):
            continue
        start_frame, end_frame = frame_range_for_diagnostic(arpeggio, rows_by_source, rows_by_synthetic)
        frames = [
            value for value in (
                integer(update.get("scheduled_frame"))
                for update in nested_list(arpeggio.get("step_updates"))
                if isinstance(update, dict)
            )
            if value is not None
        ]
        if frames:
            start_frame = min(frames)
            end_frame = max(frames) + 1
        occurrences.append(CommandOccurrence(
            domain="effect",
            label=effect_command_label(arpeggio.get("effect_type"), arpeggio.get("effect_param")),
            status=arpeggio_status(arpeggio),
            source=nested_dict(arpeggio.get("source")),
            channel=arpeggio.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=arpeggio.get("effect_param"),
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

    for portamento in nested_list(diagnostics.get("fine_portamento_up_effects")):
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
            status=fine_portamento_up_status(portamento),
            source=nested_dict(portamento.get("source")),
            channel=portamento.get("channel_index"),
            start_frame=start_frame,
            end_frame=end_frame,
            parameter=portamento.get("effect_param"),
        ))

    for portamento in nested_list(diagnostics.get("fine_portamento_down_effects")):
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
            status=fine_portamento_down_status(portamento),
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


def build_rendering_mechanics_summary(
    comparison: dict[str, Any],
    diagnostics: dict[str, Any],
    windows: list[dict[str, Any]],
    events: list[dict[str, Any]],
    rows: list[dict[str, Any]],
) -> dict[str, Any]:
    render = nested_dict(diagnostics.get("render"))
    reference_info = nested_dict(nested_dict(comparison.get("reference")).get("info"))
    candidate_info = nested_dict(nested_dict(comparison.get("candidate")).get("info"))
    render_sample_rate = number(render.get("sample_rate"))
    reference_sample_rate = number(reference_info.get("sample_rate"))
    candidate_sample_rate = number(candidate_info.get("sample_rate"))
    sample_rate_values = [
        value for value in (render_sample_rate, reference_sample_rate, candidate_sample_rate)
        if value is not None
    ]
    sample_rate_mismatch = bool(sample_rate_values) and (
        max(sample_rate_values) - min(sample_rate_values) > FRACTION_EPSILON
    )

    step_updates = normalize_step_update_signals(diagnostics, rows)
    all_event_mechanics = [event_mechanics_for_window(event, None) for event in events]
    window_summaries = []
    for window in windows:
        overlapping_events = [
            event for event in events
            if overlaps(event["_start_frame"], event["_end_frame"], window["_start_frame"], window["_end_frame"])
        ]
        mechanics = [event_mechanics_for_window(event, window) for event in overlapping_events]
        window_step_updates = [
            update for update in step_updates
            if window["_start_frame"] <= update["frame"] < window["_end_frame"]
        ]
        pitch_summary = pitch_mechanics_summary(mechanics)
        window_summaries.append({
            "rank": int(window["_rank"]),
            "start_seconds": window["_start_seconds"],
            "end_seconds": window["_end_seconds"],
            "event_count": len(overlapping_events),
            "fractional_step_event_count": sum(1 for item in mechanics if item["fractional_playback_step"]),
            "fractional_source_phase_event_count": sum(1 for item in mechanics if item["fractional_source_phase"]),
            "looped_event_count": sum(1 for item in mechanics if item["loop_mode"] != "none"),
            "loop_boundary_crossing_event_count": sum(1 for item in mechanics if item["loop_boundary_crossing"]),
            "loop_boundary_crossing_count": sum(int(item["loop_boundary_crossing_count"]) for item in mechanics),
            "forward_loop_wrap_count": sum(int(item["forward_loop_wrap_count"]) for item in mechanics),
            "ping_pong_turnaround_count": sum(int(item["ping_pong_turnaround_count"]) for item in mechanics),
            "sample_offset_event_count": sum(1 for item in mechanics if item["sample_offset_applied"]),
            "step_update_count": len(window_step_updates),
            **pitch_summary,
            "examples": [mechanics_example_label(item) for item in mechanics[:MAX_MECHANICS_EXAMPLES]],
        })

    pitch_status_counts = Counter(
        str(nested_dict(event.get("pitch")).get("frequency_table_status") or "unavailable")
        for event in events
    )
    summary = {
        "interpolation_mode": render.get("sample_interpolation") or "unavailable",
        "render_sample_rate": render_sample_rate,
        "reference_sample_rate": reference_sample_rate,
        "candidate_sample_rate": candidate_sample_rate,
        "sample_rate_mismatch": sample_rate_mismatch,
        "comparison_shape": comparison_shape(comparison),
        "total_event_count": len(events),
        "fractional_step_event_count": sum(1 for item in all_event_mechanics if item["fractional_playback_step"]),
        "integer_step_event_count": sum(1 for item in all_event_mechanics if item["integer_playback_step"]),
        "neutral_step_event_count": sum(1 for item in all_event_mechanics if item["neutral_playback_step"]),
        "fractional_source_phase_event_count": sum(1 for item in all_event_mechanics if item["fractional_source_phase"]),
        "looped_event_count": sum(1 for item in all_event_mechanics if item["loop_mode"] != "none"),
        "loop_boundary_crossing_count": sum(int(item["loop_boundary_crossing_count"]) for item in all_event_mechanics),
        "forward_loop_wrap_count": sum(int(item["forward_loop_wrap_count"]) for item in all_event_mechanics),
        "ping_pong_turnaround_count": sum(int(item["ping_pong_turnaround_count"]) for item in all_event_mechanics),
        "sample_offset_event_count": sum(1 for item in all_event_mechanics if item["sample_offset_applied"]),
        "step_update_count": len(step_updates),
        **pitch_mechanics_summary(all_event_mechanics),
        "pitch_frequency_table_counts": dict(sorted(pitch_status_counts.items())),
        "amiga_deferred_event_count": sum(
            1 for event in events
            if bool(nested_dict(event.get("pitch")).get("amiga_frequency_deferred"))
        ),
        "neutral_step_fallback_event_count": sum(
            1 for event in events
            if bool(nested_dict(event.get("pitch")).get("fallback_neutral_step_used"))
            or bool(nested_dict(event.get("pitch")).get("used_neutral_step"))
        ),
        "window_summaries": window_summaries,
    }
    recommendation, rationale = recommend_rendering_mechanics(summary)
    summary["candidate_signal"] = recommendation
    summary["candidate_signal_rationale"] = rationale
    return summary


def normalize_step_update_signals(
    diagnostics: dict[str, Any],
    rows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    rows_by_source, rows_by_synthetic = row_frame_indexes(rows)
    updates: list[dict[str, Any]] = []
    for section, label in STEP_UPDATE_SECTIONS:
        for diagnostic in nested_list(diagnostics.get(section)):
            if not isinstance(diagnostic, dict):
                continue
            for raw_update in nested_list(diagnostic.get("step_updates")):
                if not isinstance(raw_update, dict):
                    continue
                frame = integer(raw_update.get("scheduled_frame"))
                if frame is None:
                    frame, _ = frame_range_for_diagnostic(diagnostic, rows_by_source, rows_by_synthetic)
                if frame is None:
                    continue
                updates.append({
                    "frame": max(0, frame),
                    "label": label,
                    "status": diagnostic.get("status"),
                    "source": nested_dict(diagnostic.get("source")),
                    "channel_index": diagnostic.get("channel_index"),
                    "active_event_index": diagnostic.get("active_event_index"),
                    "active_event_mapping_index": diagnostic.get("active_event_mapping_index"),
                    "linear_period_before": raw_update.get("linear_period_before"),
                    "linear_period_after": raw_update.get("linear_period_after"),
                    "playback_step_before": raw_update.get("playback_step_before", raw_update.get("current_step_before")),
                    "playback_step_after": raw_update.get("playback_step_after", raw_update.get("current_step_after")),
                    "synthetic_tick": raw_update.get("synthetic_tick"),
                })
    updates.sort(key=lambda item: (item["frame"], item["label"], sort_int(item.get("channel_index"))))
    return updates


def normalize_render_windows(diagnostics: dict[str, Any]) -> list[dict[str, Any]]:
    windowed = nested_dict(diagnostics.get("windowed_render"))
    windows: list[dict[str, Any]] = []
    for raw_window in nested_list(windowed.get("per_window")):
        if not isinstance(raw_window, dict):
            continue
        start_frame = integer(raw_window.get("start_frame"))
        end_frame = integer(raw_window.get("end_frame"))
        if start_frame is None or end_frame is None:
            continue
        windows.append({
            **raw_window,
            "_start_frame": max(0, start_frame),
            "_end_frame": max(start_frame + 1, end_frame),
        })
    windows.sort(key=lambda item: (item["_start_frame"], item.get("window_index", 0)))
    return windows


def render_window_for_frame(render_windows: list[dict[str, Any]], frame: int) -> dict[str, Any] | None:
    for window in render_windows:
        if window["_start_frame"] <= frame < window["_end_frame"]:
            return window
    return None


def active_events_for_window(
    window: dict[str, Any],
    events: list[dict[str, Any]],
    render_windows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    start_frame = int(window["_start_frame"])
    end_frame = int(window["_end_frame"])
    render_window = render_window_for_frame(render_windows, start_frame)
    if render_window is None:
        return [
            {**event, "_effective_start_frame": event["_start_frame"], "_effective_end_frame": event["_end_frame"]}
            for event in events
            if overlaps(event["_start_frame"], event["_end_frame"], start_frame, end_frame)
        ]

    render_start = int(render_window["_start_frame"])
    render_end = int(render_window["_end_frame"])
    latest_prior_by_channel: dict[Any, dict[str, Any]] = {}
    current_window_events: list[dict[str, Any]] = []
    for event in events:
        event_start = int(event["_start_frame"])
        event_end = int(event["_end_frame"])
        if event_start < render_start and event_end > render_start:
            channel = event.get("channel_index")
            existing = latest_prior_by_channel.get(channel)
            if existing is None or (
                event_start,
                sort_int(event.get("event_index")),
            ) > (
                int(existing["_start_frame"]),
                sort_int(existing.get("event_index")),
            ):
                latest_prior_by_channel[channel] = event
        elif render_start <= event_start < render_end:
            current_window_events.append(event)

    candidates = list(latest_prior_by_channel.values()) + current_window_events
    active: list[dict[str, Any]] = []
    for event in candidates:
        effective_start = max(int(event["_start_frame"]), render_start)
        effective_end = min(int(event["_end_frame"]), render_end)
        if overlaps(effective_start, effective_end, start_frame, end_frame):
            active.append({
                **event,
                "_effective_start_frame": effective_start,
                "_effective_end_frame": effective_end,
                "_render_window_index": render_window.get("window_index"),
            })
    active.sort(key=lambda item: (sort_int(item.get("channel_index")), sort_int(item.get("event_index"))))
    return active


def build_period_sample_step_voice_summary(
    diagnostics: dict[str, Any],
    windows: list[dict[str, Any]],
    events: list[dict[str, Any]],
    rows: list[dict[str, Any]],
) -> dict[str, Any]:
    render_windows = normalize_render_windows(diagnostics)
    step_updates = normalize_step_update_signals(diagnostics, rows)
    window_summaries: list[dict[str, Any]] = []
    for window in windows:
        active = active_events_for_window(window, events, render_windows)
        update_count = sum(
            1 for update in step_updates
            if int(window["_start_frame"]) <= update["frame"] < int(window["_end_frame"])
        )
        mechanics = [event_mechanics_for_window(event, window) for event in active]
        pitch_summary = pitch_mechanics_summary(mechanics)
        looped_count = sum(1 for item in mechanics if item["loop_mode"] != "none")
        examples = [
            period_sample_step_voice_label(event, window, step_updates)
            for event in active[:MAX_PERIOD_SAMPLE_STEP_EXAMPLES]
        ]
        window_summaries.append({
            "rank": int(window["_rank"]),
            "start_seconds": window["_start_seconds"],
            "end_seconds": window["_end_seconds"],
            "active_voice_count": len(active),
            "active_channel_count": len({event.get("channel_index") for event in active}),
            "looped_voice_count": looped_count,
            "sample_step_update_count": update_count,
            **pitch_summary,
            "examples": examples,
        })
    return {
        "windowed_render_aware": bool(render_windows),
        "render_window_count": len(render_windows),
        "window_summaries": window_summaries,
    }


def build_gain_pan_voice_summary(
    diagnostics: dict[str, Any],
    windows: list[dict[str, Any]],
    events: list[dict[str, Any]],
) -> dict[str, Any]:
    render_windows = normalize_render_windows(diagnostics)
    all_voice_signals = [gain_pan_voice_signal(event, None) for event in events]
    window_summaries: list[dict[str, Any]] = []
    for window in windows:
        active = active_events_for_window(window, events, render_windows)
        probe_frame = int(window["_start_frame"]) + max(0, (int(window["_end_frame"]) - int(window["_start_frame"])) // 2)
        voice_signals = [gain_pan_voice_signal(event, probe_frame) for event in active]
        window_summaries.append({
            "rank": int(window["_rank"]),
            "start_seconds": window["_start_seconds"],
            "end_seconds": window["_end_seconds"],
            "probe_frame": probe_frame,
            "active_voice_count": len(active),
            "final_gain": numeric_distribution(voice_signals, "final_gain"),
            "base_gain": numeric_distribution(voice_signals, "base_gain"),
            "pan": numeric_distribution(voice_signals, "pan"),
            "left_gain": numeric_distribution(voice_signals, "left_gain"),
            "right_gain": numeric_distribution(voice_signals, "right_gain"),
            "center_pan_voice_count": sum(1 for item in voice_signals if pan_is_centered(item.get("pan"))),
            "hard_left_voice_count": sum(1 for item in voice_signals if pan_is_hard_left(item.get("pan"))),
            "hard_right_voice_count": sum(1 for item in voice_signals if pan_is_hard_right(item.get("pan"))),
            "examples": [gain_pan_voice_label(item) for item in voice_signals[:MAX_GAIN_PAN_EXAMPLES]],
        })
    return {
        "pan_law": "linear_clamped_-1_to_1_full_amplitude_center",
        "pan_law_detail": "left=1 when pan<=0 else 1-pan; right=1 when pan>=0 else 1+pan",
        "event_count": len(events),
        "base_gain": numeric_distribution(all_voice_signals, "base_gain"),
        "pan": numeric_distribution(all_voice_signals, "pan"),
        "windowed_render_aware": bool(render_windows),
        "window_summaries": window_summaries,
    }


def build_sample_instrument_gain_summary(
    comparison: dict[str, Any],
    diagnostics: dict[str, Any],
    windows: list[dict[str, Any]],
    events: list[dict[str, Any]],
) -> dict[str, Any]:
    render_windows = normalize_render_windows(diagnostics)
    all_voice_signals = [sample_instrument_gain_signal(event, None) for event in events]
    voice_counts: list[float] = []
    window_rms_diffs: list[float] = []
    window_summaries: list[dict[str, Any]] = []
    window_scalars: list[float] = []
    for window in windows:
        active = active_events_for_window(window, events, render_windows)
        probe_frame = int(window["_start_frame"]) + max(0, (int(window["_end_frame"]) - int(window["_start_frame"])) // 2)
        voice_signals = [sample_instrument_gain_signal(event, probe_frame) for event in active]
        scalar = window_gain_scalar(window)
        if scalar is not None:
            window_scalars.append(scalar)
        rms_diff = number(window.get("rms_difference"))
        if rms_diff is not None:
            voice_counts.append(float(len(active)))
            window_rms_diffs.append(rms_diff)
        window_summaries.append({
            "rank": int(window["_rank"]),
            "start_seconds": window["_start_seconds"],
            "end_seconds": window["_end_seconds"],
            "probe_frame": probe_frame,
            "active_voice_count": len(active),
            "sample_volume": numeric_distribution(voice_signals, "sample_volume"),
            "sample_volume_raw_estimate": numeric_distribution(voice_signals, "sample_volume_raw_estimate"),
            "channel_volume": numeric_distribution(voice_signals, "channel_volume"),
            "global_volume": numeric_distribution(voice_signals, "global_volume"),
            "base_gain": numeric_distribution(voice_signals, "base_gain"),
            "final_gain": numeric_distribution(voice_signals, "final_gain"),
            "final_gain_histogram": final_gain_histogram(voice_signals),
            "candidate_scalar_to_reference": scalar,
            "dominant": dominant_instrument_sample_groups(voice_signals, window),
        })
    return {
        "gain_construction": "sample_volume * (channel_volume / 64) * (global_volume / 64), then C mixer volume_envelope * fadeout before panning",
        "sample_volume_source": "XM sample header volume raw 0...64 normalized once into PlaybackSample.volume",
        "c_mixer_gain_expectation": "C mixer receives generic finite event gain; bounded adapter event gain is already normalized and clamped to 0...1",
        "active_voice_lifetime": "same-channel replacement completion frames are folded into event end frames when diagnostics are present",
        "global_candidate_scalar_to_reference": comparison_global_gain_scalar(comparison),
        "window_candidate_scalar": numeric_distribution(
            [{"value": value} for value in window_scalars],
            "value",
        ),
        "voice_count_to_window_rms_correlation": pearson_correlation(voice_counts, window_rms_diffs),
        "event_count": len(events),
        "sample_volume": numeric_distribution(all_voice_signals, "sample_volume"),
        "sample_volume_raw_estimate": numeric_distribution(all_voice_signals, "sample_volume_raw_estimate"),
        "channel_volume": numeric_distribution(all_voice_signals, "channel_volume"),
        "global_volume": numeric_distribution(all_voice_signals, "global_volume"),
        "base_gain": numeric_distribution(all_voice_signals, "base_gain"),
        "windowed_render_aware": bool(render_windows),
        "window_summaries": window_summaries,
    }


def build_loop_crossing_timbre_summary(
    diagnostics: dict[str, Any],
    windows: list[dict[str, Any]],
    events: list[dict[str, Any]],
) -> dict[str, Any]:
    render_windows = normalize_render_windows(diagnostics)
    all_mechanics = [event_mechanics_for_window(event, None) for event in events]
    looped_mechanics = [item for item in all_mechanics if item["loop_mode"] != "none"]
    window_summaries: list[dict[str, Any]] = []
    for window in windows:
        active = active_events_for_window(window, events, render_windows)
        probe_frame = int(window["_start_frame"]) + max(0, (int(window["_end_frame"]) - int(window["_start_frame"])) // 2)
        signals = [
            loop_crossing_voice_signal(event, window, probe_frame)
            for event in active
            if str(event.get("loop_mode") or "none") != "none"
        ]
        crossing_count = sum(integer(item.get("loop_boundary_crossing_count")) or 0 for item in signals)
        window_summaries.append({
            "rank": int(window["_rank"]),
            "start_seconds": window["_start_seconds"],
            "end_seconds": window["_end_seconds"],
            "probe_frame": probe_frame,
            "active_voice_count": len(active),
            "looped_voice_count": len(signals),
            "crossing_voice_count": sum(1 for item in signals if (integer(item.get("loop_boundary_crossing_count")) or 0) > 0),
            "loop_boundary_crossing_count": crossing_count,
            "forward_loop_wrap_count": sum(integer(item.get("forward_loop_wrap_count")) or 0 for item in signals),
            "playback_step": numeric_distribution(signals, "playback_step"),
            "final_gain": numeric_distribution(signals, "final_gain"),
            "timbre": loop_timbre_signal(window),
            "dominant": dominant_looped_instrument_sample_groups(signals),
            "examples": [loop_crossing_voice_label(item) for item in signals[:MAX_LOOP_CROSSING_EXAMPLES]],
        })
    return {
        "event_count": len(events),
        "looped_event_count": len(looped_mechanics),
        "loop_crossing_event_count": sum(1 for item in looped_mechanics if int(item["loop_boundary_crossing_count"]) > 0),
        "loop_boundary_crossing_count": sum(int(item["loop_boundary_crossing_count"]) for item in looped_mechanics),
        "windowed_render_aware": bool(render_windows),
        "render_window_count": len(render_windows),
        "timbre_metric_window_count": sum(
            1 for window in windows
            if loop_timbre_signal(window).get("residual_to_reference_rms") is not None
        ),
        "window_count": len(windows),
        "window_summaries": window_summaries,
    }


def build_steady_state_loop_summary(
    diagnostics: dict[str, Any],
    windows: list[dict[str, Any]],
    events: list[dict[str, Any]],
    rows: list[dict[str, Any]],
) -> dict[str, Any]:
    render_windows = normalize_render_windows(diagnostics)
    step_updates = normalize_step_update_signals(diagnostics, rows)
    gain_updates = normalize_gain_pan_updates(diagnostics, rows)
    replacement_ramps = normalize_replacement_ramp_signals(diagnostics)
    window_summaries: list[dict[str, Any]] = []
    for window in windows:
        active = active_events_for_window(window, events, render_windows)
        probe_frame = int(window["_start_frame"]) + max(0, (int(window["_end_frame"]) - int(window["_start_frame"])) // 2)
        signals = [
            steady_state_loop_voice_signal(
                event,
                window,
                probe_frame,
                step_updates,
                gain_updates,
                replacement_ramps,
            )
            for event in active
            if str(event.get("loop_mode") or "none") != "none"
        ]
        window_step_updates = [
            update for update in step_updates
            if int(window["_start_frame"]) <= update["frame"] < int(window["_end_frame"])
        ]
        window_gain_updates = [
            update for update in gain_updates
            if int(window["_start_frame"]) <= update["frame"] < int(window["_end_frame"])
        ]
        window_replacement_ramps = [
            ramp for ramp in replacement_ramps
            if overlaps(
                int(ramp["start_frame"]),
                int(ramp["end_frame"]),
                int(window["_start_frame"]),
                int(window["_end_frame"]),
            )
        ]
        window_summaries.append({
            "rank": int(window["_rank"]),
            "start_seconds": window["_start_seconds"],
            "end_seconds": window["_end_seconds"],
            "probe_frame": probe_frame,
            "active_voice_count": len(active),
            "looped_voice_count": len(signals),
            "steady_state_loop_interior_voice_count": sum(1 for item in signals if bool(item.get("steady_state_loop_interior"))),
            "loop_boundary_crossing_count": sum(integer(item.get("loop_boundary_crossing_count")) or 0 for item in signals),
            "sample_step_update_count": len(window_step_updates),
            "gain_update_count": len(window_gain_updates),
            "replacement_ramp_count": len(window_replacement_ramps),
            "loop_phase_histogram": loop_phase_histogram(signals),
            "timbre": loop_timbre_signal(window),
            "dominant": dominant_steady_state_loop_groups(signals),
            "examples": [steady_state_loop_voice_label(item) for item in signals[:MAX_STEADY_STATE_LOOP_EXAMPLES]],
        })
    return {
        "event_count": len(events),
        "looped_event_count": sum(1 for event in events if str(event.get("loop_mode") or "none") != "none"),
        "windowed_render_aware": bool(render_windows),
        "render_window_count": len(render_windows),
        "window_count": len(windows),
        "classification_policy": "steady_state_loop_interior means looped, no estimated boundary crossing, and start/mid/end source positions remain at least max(1 frame, sample_step) away from loop edges",
        "contribution_policy": "final_gain^2 times active overlap frames; this is a stem proxy, not isolated audio RMS",
        "window_summaries": window_summaries,
    }


def gain_pan_voice_signal(event: dict[str, Any], probe_frame: int | None) -> dict[str, Any]:
    base_gain = number(event.get("gain"))
    pan = number(event.get("pan"))
    if pan is None:
        pan = number(event.get("effective_pan"))
    final_gain = base_gain
    envelope_value = None
    fadeout_value = None
    if probe_frame is not None:
        snapshot = event_envelope_snapshot(event, probe_frame)
        if snapshot is not None:
            final_gain = number(snapshot.get("final_voice_gain"))
            envelope_value = number(snapshot.get("value"))
            fadeout_value = number(snapshot.get("fadeout_value"))
    left_pan = left_pan_gain(pan)
    right_pan = right_pan_gain(pan)
    return {
        "source": nested_dict(event.get("source")),
        "channel_index": event.get("channel_index"),
        "event_index": event.get("event_index"),
        "base_gain": base_gain,
        "final_gain": final_gain,
        "pan": pan,
        "left_pan_gain": left_pan,
        "right_pan_gain": right_pan,
        "left_gain": None if final_gain is None or left_pan is None else final_gain * left_pan,
        "right_gain": None if final_gain is None or right_pan is None else final_gain * right_pan,
        "envelope_value": envelope_value,
        "fadeout_value": fadeout_value,
    }


def left_pan_gain(pan: Any) -> float | None:
    value = clamped_pan(pan)
    if value is None:
        return None
    return 1.0 if value <= 0.0 else 1.0 - value


def right_pan_gain(pan: Any) -> float | None:
    value = clamped_pan(pan)
    if value is None:
        return None
    return 1.0 if value >= 0.0 else 1.0 + value


def clamped_pan(pan: Any) -> float | None:
    value = number(pan)
    if value is None:
        return None
    return min(1.0, max(-1.0, value))


def pan_is_centered(pan: Any) -> bool:
    value = clamped_pan(pan)
    return value is not None and abs(value) <= 0.01


def pan_is_hard_left(pan: Any) -> bool:
    value = clamped_pan(pan)
    return value is not None and value <= -0.99


def pan_is_hard_right(pan: Any) -> bool:
    value = clamped_pan(pan)
    return value is not None and value >= 0.99


def numeric_distribution(items: list[dict[str, Any]], key: str) -> dict[str, Any]:
    values = [value for value in (number(item.get(key)) for item in items) if value is not None]
    return {
        "count": len(values),
        "missing_count": len(items) - len(values),
        "min": min(values) if values else None,
        "max": max(values) if values else None,
        "mean": sum(values) / len(values) if values else None,
    }


def gain_pan_voice_label(item: dict[str, Any]) -> str:
    return (
        f"{source_label(nested_dict(item.get('source')))} "
        f"ch {format_optional(item.get('channel_index'))} "
        f"event {format_optional(item.get('event_index'))} "
        f"gain {format_optional_float(item.get('base_gain'))}->"
        f"{format_optional_float(item.get('final_gain'))} "
        f"pan {format_optional_float(item.get('pan'))} "
        f"L/R {format_optional_float(item.get('left_gain'))}/"
        f"{format_optional_float(item.get('right_gain'))}"
    )


def sample_instrument_gain_signal(event: dict[str, Any], probe_frame: int | None) -> dict[str, Any]:
    construction = nested_dict(event.get("gain_construction"))
    base_gain = number(event.get("gain"))
    channel_volume = integer(event.get("effective_volume_value"))
    if channel_volume is None:
        channel_volume = integer(construction.get("channel_volume_value"))
    global_volume = integer(event.get("effective_global_volume_value"))
    if global_volume is None:
        global_volume = integer(construction.get("global_volume_value"))
    channel_multiplier = number(event.get("effective_volume_multiplier"))
    if channel_multiplier is None:
        channel_multiplier = number(construction.get("channel_volume_multiplier"))
    if channel_multiplier is None and channel_volume is not None:
        channel_multiplier = normalized_xm_volume_multiplier(channel_volume)
    global_multiplier = number(event.get("effective_global_volume_multiplier"))
    if global_multiplier is None:
        global_multiplier = number(construction.get("global_volume_multiplier"))
    if global_multiplier is None and global_volume is not None:
        global_multiplier = normalized_xm_volume_multiplier(global_volume)
    sample_volume = number(event.get("sample_volume"))
    if sample_volume is None:
        sample_volume = number(construction.get("sample_volume_normalized"))
    if sample_volume is None and base_gain is not None and channel_multiplier is not None and global_multiplier is not None:
        denominator = channel_multiplier * global_multiplier
        if abs(denominator) > FRACTION_EPSILON:
            sample_volume = base_gain / denominator
    sample_volume_raw = integer(event.get("sample_volume_raw_estimate"))
    if sample_volume_raw is None:
        sample_volume_raw = integer(construction.get("sample_volume_raw_estimate"))
    if sample_volume_raw is None and sample_volume is not None:
        sample_volume_raw = max(0, min(64, int(round(sample_volume * 64.0))))

    final_gain = base_gain
    envelope_value = None
    fadeout_value = None
    if probe_frame is not None:
        snapshot = event_envelope_snapshot(event, probe_frame)
        if snapshot is not None:
            final_gain = number(snapshot.get("final_voice_gain"))
            envelope_value = number(snapshot.get("value"))
            fadeout_value = number(snapshot.get("fadeout_value"))
    return {
        "source": nested_dict(event.get("source")),
        "channel_index": event.get("channel_index"),
        "event_index": event.get("event_index"),
        "instrument_index": integer(event.get("instrument_index")),
        "sample_index": integer(event.get("sample_index")),
        "sample_volume": sample_volume,
        "sample_volume_raw_estimate": sample_volume_raw,
        "channel_volume": channel_volume,
        "channel_multiplier": channel_multiplier,
        "global_volume": global_volume,
        "global_multiplier": global_multiplier,
        "base_gain": base_gain,
        "final_gain": final_gain,
        "envelope_value": envelope_value,
        "fadeout_value": fadeout_value,
        "effective_start_frame": integer(event.get("_effective_start_frame", event.get("_start_frame"))),
        "effective_end_frame": integer(event.get("_effective_end_frame", event.get("_end_frame"))),
    }


def loop_crossing_voice_signal(
    event: dict[str, Any],
    window: dict[str, Any],
    probe_frame: int,
) -> dict[str, Any]:
    mechanics = event_mechanics_for_window(event, window)
    gain_signal = sample_instrument_gain_signal(event, probe_frame)
    pitch = nested_dict(event.get("pitch"))
    loop_start = integer(event.get("loop_start_frame"))
    loop_end = integer(event.get("loop_end_frame"))
    loop_length = integer(event.get("loop_length_frames"))
    if loop_length is None and loop_start is not None and loop_end is not None:
        loop_length = max(0, loop_end - loop_start)
    start_position = mechanics["start_position"]
    end_position = mechanics["end_position"]
    window_start = int(window["_start_frame"])
    window_end = int(window["_end_frame"])
    event_start = integer(event.get("_effective_start_frame", event.get("_start_frame")))
    event_end = integer(event.get("_effective_end_frame", event.get("_end_frame")))
    overlap_frames = 1
    if event_start is not None and event_end is not None:
        overlap_frames = max(0, min(event_end, window_end) - max(event_start, window_start))
    final_gain = number(gain_signal.get("final_gain"))
    contribution = 0.0 if final_gain is None else final_gain * final_gain * float(overlap_frames)
    return {
        "source": nested_dict(event.get("source")),
        "channel_index": event.get("channel_index"),
        "event_index": event.get("event_index"),
        "note": event.get("note"),
        "instrument_index": integer(event.get("instrument_index")),
        "sample_index": integer(event.get("sample_index")),
        "sample_frame_count": integer(event.get("sample_frame_count")),
        "loop_mode": mechanics["loop_mode"],
        "loop_start_frame": loop_start,
        "loop_end_frame": loop_end,
        "loop_length_frames": loop_length,
        "playback_step": number(pitch.get("playback_step")),
        "final_gain": final_gain,
        "contribution_estimate": contribution,
        "loop_boundary_crossing_count": mechanics["loop_boundary_crossing_count"],
        "forward_loop_wrap_count": mechanics["forward_loop_wrap_count"],
        "start_source_position": start_position.rendered_position,
        "end_source_position": end_position.rendered_position,
        "start_raw_source_position": start_position.raw_position,
        "end_raw_source_position": end_position.raw_position,
        "crossing_examples": loop_crossing_examples(event, window),
    }


def loop_timbre_signal(window: dict[str, Any]) -> dict[str, Any]:
    mono = nested_dict(nested_dict(window.get("timbre_metrics")).get("mono"))
    reference = nested_dict(mono.get("reference"))
    candidate = nested_dict(mono.get("candidate"))
    residual = nested_dict(mono.get("residual"))
    residual_band = nested_dict(residual.get("band_energy_proxy"))
    return {
        "residual_to_reference_rms": number(mono.get("residual_to_reference_rms")),
        "reference_high_frequency_proxy": number(reference.get("high_frequency_proxy_ratio")),
        "candidate_high_frequency_proxy": number(candidate.get("high_frequency_proxy_ratio")),
        "residual_high_frequency_proxy": number(residual.get("high_frequency_proxy_ratio")),
        "residual_derivative_rms": number(residual.get("derivative_rms")),
        "residual_transient_derivative_rms": number(residual.get("first_10ms_derivative_rms")),
        "residual_high_band_ratio": number(residual_band.get("high_ratio")),
    }


def steady_state_loop_voice_signal(
    event: dict[str, Any],
    window: dict[str, Any],
    probe_frame: int,
    step_updates: list[dict[str, Any]],
    gain_updates: list[dict[str, Any]],
    replacement_ramps: list[dict[str, Any]],
) -> dict[str, Any]:
    mechanics = event_mechanics_for_window(event, window)
    gain_signal = sample_instrument_gain_signal(event, probe_frame)
    pitch = nested_dict(event.get("pitch"))
    loop_start = integer(event.get("loop_start_frame"))
    loop_end = integer(event.get("loop_end_frame"))
    loop_length = integer(event.get("loop_length_frames"))
    if loop_length is None and loop_start is not None and loop_end is not None:
        loop_length = max(0, loop_end - loop_start)
    start_position = mechanics["start_position"]
    end_position = mechanics["end_position"]
    midpoint_position = estimate_source_position(event, probe_frame)
    final_gain = number(gain_signal.get("final_gain"))
    window_start = int(window["_start_frame"])
    window_end = int(window["_end_frame"])
    event_start = integer(event.get("_effective_start_frame", event.get("_start_frame")))
    event_end = integer(event.get("_effective_end_frame", event.get("_end_frame")))
    overlap_frames = 1
    if event_start is not None and event_end is not None:
        overlap_frames = max(0, min(event_end, window_end) - max(event_start, window_start))
    contribution = 0.0 if final_gain is None else final_gain * final_gain * float(overlap_frames)
    crossing_count = integer(mechanics.get("loop_boundary_crossing_count")) or 0
    playback_step = number(pitch.get("playback_step"))
    return {
        "source": nested_dict(event.get("source")),
        "channel_index": event.get("channel_index"),
        "event_index": event.get("event_index"),
        "note": event.get("note"),
        "instrument_index": integer(event.get("instrument_index")),
        "sample_index": integer(event.get("sample_index")),
        "sample_frame_count": integer(event.get("sample_frame_count")),
        "sample_volume": gain_signal.get("sample_volume"),
        "sample_volume_raw_estimate": gain_signal.get("sample_volume_raw_estimate"),
        "sample_relative_note": integer(pitch.get("sample_relative_note")),
        "sample_finetune": integer(pitch.get("sample_finetune")),
        "loop_mode": mechanics["loop_mode"],
        "loop_start_frame": loop_start,
        "loop_end_frame": loop_end,
        "loop_length_frames": loop_length,
        "playback_step": playback_step,
        "final_gain": final_gain,
        "contribution_estimate": contribution,
        "overlap_frames": overlap_frames,
        "loop_boundary_crossing_count": crossing_count,
        "start_source_position": start_position.rendered_position,
        "mid_source_position": midpoint_position.rendered_position,
        "end_source_position": end_position.rendered_position,
        "start_loop_phase": loop_phase_for_position(start_position.rendered_position, event),
        "mid_loop_phase": loop_phase_for_position(midpoint_position.rendered_position, event),
        "end_loop_phase": loop_phase_for_position(end_position.rendered_position, event),
        "steady_state_loop_interior": source_positions_are_loop_interior(
            event,
            [start_position.rendered_position, midpoint_position.rendered_position, end_position.rendered_position],
            crossing_count,
            playback_step,
        ),
        "sample_step_update_count": count_updates_for_event(step_updates, event, window),
        "gain_update_count": count_updates_for_event(gain_updates, event, window),
        "replacement_ramp_count": count_replacement_ramps_for_event(replacement_ramps, event, window),
    }


def loop_phase_for_position(position: float | None, event: dict[str, Any]) -> float | None:
    if position is None:
        return None
    loop_start = integer(event.get("loop_start_frame"))
    loop_end = integer(event.get("loop_end_frame"))
    loop_mode = str(event.get("loop_mode") or "none")
    if loop_start is None or loop_end is None or loop_end <= loop_start:
        return None
    if loop_mode == "forward":
        return min(1.0, max(0.0, (position - loop_start) / float(loop_end - loop_start)))
    if loop_mode == "ping_pong":
        span = max(1, loop_end - loop_start - 1)
        return min(1.0, max(0.0, (position - loop_start) / float(span)))
    return None


def source_positions_are_loop_interior(
    event: dict[str, Any],
    positions: list[float | None],
    crossing_count: int,
    playback_step: float | None,
) -> bool:
    if crossing_count > 0 or str(event.get("loop_mode") or "none") == "none":
        return False
    loop_start = integer(event.get("loop_start_frame"))
    loop_end = integer(event.get("loop_end_frame"))
    if loop_start is None or loop_end is None or loop_end <= loop_start:
        return False
    margin = max(1.0, abs(playback_step or 0.0))
    for position in positions:
        if position is None:
            return False
        if position < loop_start + margin or position > loop_end - margin:
            return False
    return True


def count_updates_for_event(
    updates: list[dict[str, Any]],
    event: dict[str, Any],
    window: dict[str, Any],
) -> int:
    event_index = event.get("event_index")
    channel = event.get("channel_index")
    count = 0
    for update in updates:
        frame = integer(update.get("frame"))
        if frame is None or not (int(window["_start_frame"]) <= frame < int(window["_end_frame"])):
            continue
        active_index = update.get("active_event_index")
        if active_index == event_index or (active_index is None and update.get("channel_index") == channel):
            count += 1
    return count


def normalize_replacement_ramp_signals(diagnostics: dict[str, Any]) -> list[dict[str, Any]]:
    ramps: list[dict[str, Any]] = []
    for replacement in nested_list(nested_dict(diagnostics.get("same_channel_voice_lifetime")).get("replacement_events")):
        if not isinstance(replacement, dict):
            continue
        start = integer(replacement.get("replacement_frame"))
        if start is None:
            continue
        duration = max(1, integer(replacement.get("old_voice_ramp_duration_frames")) or 1)
        end = integer(replacement.get("completion_frame"))
        if end is None:
            end = start + duration
        ramps.append({
            **replacement,
            "start_frame": max(0, start),
            "end_frame": max(start + 1, end),
        })
    return ramps


def count_replacement_ramps_for_event(
    ramps: list[dict[str, Any]],
    event: dict[str, Any],
    window: dict[str, Any],
) -> int:
    event_index = event.get("event_index")
    count = 0
    for ramp in ramps:
        if not overlaps(int(ramp["start_frame"]), int(ramp["end_frame"]), int(window["_start_frame"]), int(window["_end_frame"])):
            continue
        if ramp.get("old_event_index") == event_index or ramp.get("new_event_index") == event_index:
            count += 1
    return count


def loop_phase_histogram(signals: list[dict[str, Any]]) -> dict[str, int]:
    histogram = {"0_0.25": 0, "0.25_0.5": 0, "0.5_0.75": 0, "0.75_1.0": 0, "missing": 0}
    for signal in signals:
        for key in ("start_loop_phase", "mid_loop_phase", "end_loop_phase"):
            phase = number(signal.get(key))
            if phase is None:
                histogram["missing"] += 1
            elif phase < 0.25:
                histogram["0_0.25"] += 1
            elif phase < 0.5:
                histogram["0.25_0.5"] += 1
            elif phase < 0.75:
                histogram["0.5_0.75"] += 1
            else:
                histogram["0.75_1.0"] += 1
    return histogram


def dominant_steady_state_loop_groups(signals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, Any, Any, Any, Any], dict[str, Any]] = {}
    for signal in signals:
        key = (
            signal.get("instrument_index"),
            signal.get("sample_index"),
            signal.get("loop_mode"),
            signal.get("loop_start_frame"),
            signal.get("loop_end_frame"),
        )
        group = groups.setdefault(key, {
            "instrument_index": signal.get("instrument_index"),
            "sample_index": signal.get("sample_index"),
            "sample_frame_count": signal.get("sample_frame_count"),
            "loop_mode": signal.get("loop_mode"),
            "loop_start_frame": signal.get("loop_start_frame"),
            "loop_end_frame": signal.get("loop_end_frame"),
            "loop_length_frames": signal.get("loop_length_frames"),
            "voice_count": 0,
            "steady_state_loop_interior_voice_count": 0,
            "loop_boundary_crossing_count": 0,
            "sample_step_update_count": 0,
            "gain_update_count": 0,
            "replacement_ramp_count": 0,
            "contribution_estimate": 0.0,
            "_sample_volume_items": [],
            "_sample_volume_raw_items": [],
            "_relative_note_items": [],
            "_finetune_items": [],
            "_playback_step_items": [],
            "_final_gain_items": [],
            "_source_position_items": [],
            "_phase_signals": [],
        })
        group["voice_count"] += 1
        group["steady_state_loop_interior_voice_count"] += 1 if bool(signal.get("steady_state_loop_interior")) else 0
        group["loop_boundary_crossing_count"] += integer(signal.get("loop_boundary_crossing_count")) or 0
        group["sample_step_update_count"] += integer(signal.get("sample_step_update_count")) or 0
        group["gain_update_count"] += integer(signal.get("gain_update_count")) or 0
        group["replacement_ramp_count"] += integer(signal.get("replacement_ramp_count")) or 0
        group["contribution_estimate"] += number(signal.get("contribution_estimate")) or 0.0
        group["_sample_volume_items"].append({"sample_volume": signal.get("sample_volume")})
        group["_sample_volume_raw_items"].append({"sample_volume_raw_estimate": signal.get("sample_volume_raw_estimate")})
        group["_relative_note_items"].append({"sample_relative_note": signal.get("sample_relative_note")})
        group["_finetune_items"].append({"sample_finetune": signal.get("sample_finetune")})
        group["_playback_step_items"].append({"playback_step": signal.get("playback_step")})
        group["_final_gain_items"].append({"final_gain": signal.get("final_gain")})
        for key_name in ("start_source_position", "mid_source_position", "end_source_position"):
            group["_source_position_items"].append({"source_position": signal.get(key_name)})
        group["_phase_signals"].append(signal)
    total = sum(number(group.get("contribution_estimate")) or 0.0 for group in groups.values())
    result = []
    for group in groups.values():
        contribution = number(group.get("contribution_estimate")) or 0.0
        result.append({
            "instrument_index": group.get("instrument_index"),
            "sample_index": group.get("sample_index"),
            "sample_frame_count": group.get("sample_frame_count"),
            "loop_mode": group.get("loop_mode"),
            "loop_start_frame": group.get("loop_start_frame"),
            "loop_end_frame": group.get("loop_end_frame"),
            "loop_length_frames": group.get("loop_length_frames"),
            "voice_count": group.get("voice_count"),
            "steady_state_loop_interior_voice_count": group.get("steady_state_loop_interior_voice_count"),
            "loop_boundary_crossing_count": group.get("loop_boundary_crossing_count"),
            "sample_step_update_count": group.get("sample_step_update_count"),
            "gain_update_count": group.get("gain_update_count"),
            "replacement_ramp_count": group.get("replacement_ramp_count"),
            "contribution_estimate": contribution,
            "contribution_ratio": contribution / total if total > 0.0 else None,
            "sample_volume": numeric_distribution(nested_list(group.get("_sample_volume_items")), "sample_volume"),
            "sample_volume_raw_estimate": numeric_distribution(nested_list(group.get("_sample_volume_raw_items")), "sample_volume_raw_estimate"),
            "sample_relative_note": numeric_distribution(nested_list(group.get("_relative_note_items")), "sample_relative_note"),
            "sample_finetune": numeric_distribution(nested_list(group.get("_finetune_items")), "sample_finetune"),
            "playback_step": numeric_distribution(nested_list(group.get("_playback_step_items")), "playback_step"),
            "final_gain": numeric_distribution(nested_list(group.get("_final_gain_items")), "final_gain"),
            "source_position": numeric_distribution(nested_list(group.get("_source_position_items")), "source_position"),
            "loop_phase_histogram": loop_phase_histogram(nested_list(group.get("_phase_signals"))),
        })
    result.sort(key=lambda item: (
        -(number(item.get("contribution_estimate")) or 0.0),
        -sort_int(item.get("voice_count")),
        sort_int(item.get("instrument_index")),
        sort_int(item.get("sample_index")),
    ))
    return result[:MAX_STEADY_STATE_LOOP_EXAMPLES]


def dominant_looped_instrument_sample_groups(signals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, Any, Any, Any, Any], dict[str, Any]] = {}
    for signal in signals:
        key = (
            signal.get("instrument_index"),
            signal.get("sample_index"),
            signal.get("loop_mode"),
            signal.get("loop_start_frame"),
            signal.get("loop_end_frame"),
        )
        group = groups.setdefault(key, {
            "instrument_index": signal.get("instrument_index"),
            "sample_index": signal.get("sample_index"),
            "loop_mode": signal.get("loop_mode"),
            "loop_start_frame": signal.get("loop_start_frame"),
            "loop_end_frame": signal.get("loop_end_frame"),
            "loop_length_frames": signal.get("loop_length_frames"),
            "voice_count": 0,
            "loop_boundary_crossing_count": 0,
            "contribution_estimate": 0.0,
            "_playback_step_items": [],
            "_final_gain_items": [],
        })
        group["voice_count"] += 1
        group["loop_boundary_crossing_count"] += integer(signal.get("loop_boundary_crossing_count")) or 0
        group["contribution_estimate"] += number(signal.get("contribution_estimate")) or 0.0
        group["_playback_step_items"].append({"playback_step": signal.get("playback_step")})
        group["_final_gain_items"].append({"final_gain": signal.get("final_gain")})
    total = sum(number(group.get("contribution_estimate")) or 0.0 for group in groups.values())
    result = []
    for group in groups.values():
        contribution = number(group.get("contribution_estimate")) or 0.0
        result.append({
            "instrument_index": group.get("instrument_index"),
            "sample_index": group.get("sample_index"),
            "loop_mode": group.get("loop_mode"),
            "loop_start_frame": group.get("loop_start_frame"),
            "loop_end_frame": group.get("loop_end_frame"),
            "loop_length_frames": group.get("loop_length_frames"),
            "voice_count": group.get("voice_count"),
            "loop_boundary_crossing_count": group.get("loop_boundary_crossing_count"),
            "contribution_estimate": contribution,
            "contribution_ratio": contribution / total if total > 0.0 else None,
            "playback_step": numeric_distribution(nested_list(group.get("_playback_step_items")), "playback_step"),
            "final_gain": numeric_distribution(nested_list(group.get("_final_gain_items")), "final_gain"),
        })
    result.sort(key=lambda item: (
        -(number(item.get("contribution_estimate")) or 0.0),
        -sort_int(item.get("voice_count")),
        sort_int(item.get("instrument_index")),
        sort_int(item.get("sample_index")),
    ))
    return result[:MAX_SAMPLE_INSTRUMENT_EXAMPLES]


def loop_crossing_examples(event: dict[str, Any], window: dict[str, Any]) -> list[dict[str, Any]]:
    if str(event.get("loop_mode") or "none") != "forward":
        return []
    step = number(nested_dict(event.get("pitch")).get("playback_step"))
    loop_start = integer(event.get("loop_start_frame"))
    loop_end = integer(event.get("loop_end_frame"))
    event_start = integer(event.get("_start_frame", event.get("scheduled_start_frame"))) or 0
    if step is None or step <= 0 or loop_start is None or loop_end is None or loop_end <= loop_start:
        return []
    loop_length = loop_end - loop_start
    probe_start = max(event_start, int(window["_start_frame"]))
    probe_end = min(integer(event.get("_end_frame", event.get("estimated_end_frame"))) or probe_start, int(window["_end_frame"]))
    if probe_end <= probe_start:
        return []
    start_raw = estimate_source_position(event, probe_start).raw_position
    end_raw = estimate_source_position(event, probe_end).raw_position
    first_index = max(0, math.ceil((start_raw - loop_end) / loop_length))
    threshold = loop_end + (first_index * loop_length)
    initial_source_frame = number(event.get("initial_source_frame")) or 0.0
    examples = []
    while threshold <= end_raw + FRACTION_EPSILON and len(examples) < 3:
        frame = event_start + int(math.ceil((threshold - initial_source_frame) / step))
        if probe_start < frame <= probe_end:
            before = estimate_source_position(event, frame - 1)
            after = estimate_source_position(event, frame)
            examples.append({
                "frame": frame,
                "raw_threshold": threshold,
                "before_position": before.rendered_position,
                "after_position": after.rendered_position,
            })
        threshold += loop_length
    return examples


def normalized_xm_volume_multiplier(value: int) -> float:
    return float(min(64, max(0, value))) / 64.0


def comparison_global_gain_scalar(comparison: dict[str, Any]) -> float | None:
    sample_comparison = nested_dict(comparison.get("sample_comparison"))
    gain_normalized = nested_dict(sample_comparison.get("gain_normalized"))
    return number(gain_normalized.get("candidate_scalar_to_reference"))


def window_gain_scalar(window: dict[str, Any]) -> float | None:
    gain_normalized = nested_dict(window.get("gain_normalized"))
    return number(gain_normalized.get("candidate_scalar_to_reference"))


def pearson_correlation(xs: list[float], ys: list[float]) -> float | None:
    pairs = [(x, y) for x, y in zip(xs, ys) if math.isfinite(x) and math.isfinite(y)]
    if len(pairs) < 2:
        return None
    mean_x = sum(x for x, _ in pairs) / len(pairs)
    mean_y = sum(y for _, y in pairs) / len(pairs)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in pairs)
    denominator_x = math.sqrt(sum((x - mean_x) * (x - mean_x) for x, _ in pairs))
    denominator_y = math.sqrt(sum((y - mean_y) * (y - mean_y) for _, y in pairs))
    denominator = denominator_x * denominator_y
    if denominator == 0.0:
        return None
    return numerator / denominator


def final_gain_histogram(signals: list[dict[str, Any]]) -> dict[str, int]:
    keys = ("zero", "0_0.125", "0.125_0.25", "0.25_0.5", "0.5_0.75", "0.75_1.0", "gt_1.0", "missing")
    buckets = (
        (AUDIBLE_GAIN_EPSILON, "zero"),
        (0.125, "0_0.125"),
        (0.25, "0.125_0.25"),
        (0.5, "0.25_0.5"),
        (0.75, "0.5_0.75"),
        (1.0, "0.75_1.0"),
    )
    histogram = dict.fromkeys(keys, 0)
    for signal in signals:
        value = number(signal.get("final_gain"))
        if value is None:
            histogram["missing"] += 1
        else:
            bucket = next((label for threshold, label in buckets if value <= threshold), "gt_1.0")
            histogram[bucket] += 1
    return histogram


def dominant_instrument_sample_groups(
    signals: list[dict[str, Any]],
    window: dict[str, Any],
) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, Any], dict[str, Any]] = {}
    window_start = int(window["_start_frame"])
    window_end = int(window["_end_frame"])
    for signal in signals:
        instrument = signal.get("instrument_index")
        sample = signal.get("sample_index")
        key = (instrument, sample)
        start = integer(signal.get("effective_start_frame"))
        end = integer(signal.get("effective_end_frame"))
        overlap_frames = 1
        if start is not None and end is not None:
            overlap_frames = max(0, min(end, window_end) - max(start, window_start))
        final_gain = number(signal.get("final_gain"))
        contribution = 0.0 if final_gain is None else final_gain * final_gain * float(overlap_frames)
        group = groups.setdefault(key, {
            "instrument_index": instrument,
            "sample_index": sample,
            "voice_count": 0,
            "contribution_estimate": 0.0,
            "_sample_volume_items": [],
            "_channel_volume_items": [],
            "_global_volume_items": [],
            "_final_gain_items": [],
        })
        group["voice_count"] += 1
        group["contribution_estimate"] += contribution
        for field in ("sample_volume", "channel_volume", "global_volume", "final_gain"):
            group[f"_{field}_items"].append({field: signal.get(field)})
    result = []
    total = sum(number(group.get("contribution_estimate")) or 0.0 for group in groups.values())
    for group in groups.values():
        contribution = number(group.get("contribution_estimate")) or 0.0
        result.append({
            "instrument_index": group.get("instrument_index"),
            "sample_index": group.get("sample_index"),
            "voice_count": group.get("voice_count"),
            "contribution_estimate": contribution,
            "contribution_ratio": contribution / total if total > 0.0 else None,
            "sample_volume": numeric_distribution(nested_list(group.get("_sample_volume_items")), "sample_volume"),
            "channel_volume": numeric_distribution(nested_list(group.get("_channel_volume_items")), "channel_volume"),
            "global_volume": numeric_distribution(nested_list(group.get("_global_volume_items")), "global_volume"),
            "final_gain": numeric_distribution(nested_list(group.get("_final_gain_items")), "final_gain"),
        })
    result.sort(key=lambda item: (
        -(number(item.get("contribution_estimate")) or 0.0),
        -sort_int(item.get("voice_count")),
        sort_int(item.get("instrument_index")),
        sort_int(item.get("sample_index")),
    ))
    return result[:MAX_SAMPLE_INSTRUMENT_EXAMPLES]


def sample_instrument_group_label(item: dict[str, Any]) -> str:
    return f"inst/sample {format_optional(item.get('instrument_index'))}/{format_optional(item.get('sample_index'))} voices {format_optional(item.get('voice_count'))} score {format_optional_float(item.get('contribution_estimate'))} ratio {format_optional_float(item.get('contribution_ratio'))} sample-vol {format_distribution_range(nested_dict(item.get('sample_volume')))} chan-vol {format_distribution_range(nested_dict(item.get('channel_volume')))} global-vol {format_distribution_range(nested_dict(item.get('global_volume')))} final-gain {format_distribution_range(nested_dict(item.get('final_gain')))}"


def looped_instrument_sample_group_label(item: dict[str, Any]) -> str:
    return (
        f"inst/sample {format_optional(item.get('instrument_index'))}/{format_optional(item.get('sample_index'))} "
        f"voices {format_optional(item.get('voice_count'))} crossings {format_optional(item.get('loop_boundary_crossing_count'))} "
        f"score {format_optional_float(item.get('contribution_estimate'))} ratio {format_optional_float(item.get('contribution_ratio'))} "
        f"loop {format_optional(item.get('loop_mode'))} {format_optional(item.get('loop_start_frame'))}-"
        f"{format_optional(item.get('loop_end_frame'))} len {format_optional(item.get('loop_length_frames'))} "
        f"step {format_distribution_range(nested_dict(item.get('playback_step')))} "
        f"final-gain {format_distribution_range(nested_dict(item.get('final_gain')))}"
    )


def loop_crossing_voice_label(item: dict[str, Any]) -> str:
    examples = ", ".join(
        loop_crossing_position_label(example)
        for example in nested_list(item.get("crossing_examples"))
        if isinstance(example, dict)
    ) or "no crossing frame example"
    return (
        f"{source_label(nested_dict(item.get('source')))} "
        f"ch {format_optional(item.get('channel_index'))} "
        f"event {format_optional(item.get('event_index'))} "
        f"inst/sample {format_optional(item.get('instrument_index'))}/{format_optional(item.get('sample_index'))} "
        f"loop {format_optional(item.get('loop_mode'))} "
        f"{format_optional(item.get('loop_start_frame'))}-{format_optional(item.get('loop_end_frame'))} "
        f"len {format_optional(item.get('loop_length_frames'))} "
        f"step {format_optional_float(item.get('playback_step'))} "
        f"gain {format_optional_float(item.get('final_gain'))} "
        f"crossings {format_optional(item.get('loop_boundary_crossing_count'))} "
        f"source {format_position(number(item.get('start_source_position')))}->"
        f"{format_position(number(item.get('end_source_position')))} "
        f"{examples}"
    )


def steady_state_loop_group_label(item: dict[str, Any]) -> str:
    return (
        f"inst/sample {format_optional(item.get('instrument_index'))}/{format_optional(item.get('sample_index'))} "
        f"voices {format_optional(item.get('voice_count'))} steady {format_optional(item.get('steady_state_loop_interior_voice_count'))} "
        f"crossings {format_optional(item.get('loop_boundary_crossing_count'))} "
        f"updates step/gain/ramp {format_optional(item.get('sample_step_update_count'))}/"
        f"{format_optional(item.get('gain_update_count'))}/{format_optional(item.get('replacement_ramp_count'))} "
        f"score {format_optional_float(item.get('contribution_estimate'))} ratio {format_optional_float(item.get('contribution_ratio'))} "
        f"sample-len {format_optional(item.get('sample_frame_count'))} "
        f"loop {format_optional(item.get('loop_mode'))} {format_optional(item.get('loop_start_frame'))}-"
        f"{format_optional(item.get('loop_end_frame'))} len {format_optional(item.get('loop_length_frames'))} "
        f"sample-vol {format_distribution_range(nested_dict(item.get('sample_volume')))} "
        f"raw-vol {format_distribution_range(nested_dict(item.get('sample_volume_raw_estimate')))} "
        f"rel/fine {format_distribution_range(nested_dict(item.get('sample_relative_note')))}/"
        f"{format_distribution_range(nested_dict(item.get('sample_finetune')))} "
        f"step {format_distribution_range(nested_dict(item.get('playback_step')))} "
        f"source {format_distribution_range(nested_dict(item.get('source_position')))} "
        f"phase {format_phase_histogram(nested_dict(item.get('loop_phase_histogram')))} "
        f"final-gain {format_distribution_range(nested_dict(item.get('final_gain')))}"
    )


def steady_state_loop_voice_label(item: dict[str, Any]) -> str:
    return (
        f"{source_label(nested_dict(item.get('source')))} "
        f"ch {format_optional(item.get('channel_index'))} "
        f"event {format_optional(item.get('event_index'))} "
        f"inst/sample {format_optional(item.get('instrument_index'))}/{format_optional(item.get('sample_index'))} "
        f"loop {format_optional(item.get('loop_mode'))} "
        f"{format_optional(item.get('loop_start_frame'))}-{format_optional(item.get('loop_end_frame'))} "
        f"step {format_optional_float(item.get('playback_step'))} "
        f"source {format_position(number(item.get('start_source_position')))}->"
        f"{format_position(number(item.get('mid_source_position')))}->"
        f"{format_position(number(item.get('end_source_position')))} "
        f"phase {format_optional_float(item.get('start_loop_phase'))}->"
        f"{format_optional_float(item.get('mid_loop_phase'))}->"
        f"{format_optional_float(item.get('end_loop_phase'))} "
        f"steady {str(bool(item.get('steady_state_loop_interior'))).lower()} "
        f"gain {format_optional_float(item.get('final_gain'))} "
        f"score {format_optional_float(item.get('contribution_estimate'))} "
        f"updates step/gain/ramp {format_optional(item.get('sample_step_update_count'))}/"
        f"{format_optional(item.get('gain_update_count'))}/{format_optional(item.get('replacement_ramp_count'))}"
    )


def loop_crossing_position_label(item: dict[str, Any]) -> str:
    return (
        f"frame {format_optional(item.get('frame'))} "
        f"source {format_position(number(item.get('before_position')))}->"
        f"{format_position(number(item.get('after_position')))} "
        f"raw {format_optional_float(item.get('raw_threshold'))}"
    )


def loop_timbre_label(item: dict[str, Any]) -> str:
    return (
        f"rms_ratio {format_optional_float(item.get('residual_to_reference_rms'))}; "
        f"hf ref/cand/resid {format_optional_float(item.get('reference_high_frequency_proxy'))}/"
        f"{format_optional_float(item.get('candidate_high_frequency_proxy'))}/"
        f"{format_optional_float(item.get('residual_high_frequency_proxy'))}; "
        f"resid_delta {format_optional_float(item.get('residual_derivative_rms'))}; "
        f"resid_10ms_delta {format_optional_float(item.get('residual_transient_derivative_rms'))}; "
        f"resid_high_band {format_optional_float(item.get('residual_high_band_ratio'))}"
    )


def period_sample_step_voice_label(
    event: dict[str, Any],
    window: dict[str, Any],
    step_updates: list[dict[str, Any]],
) -> str:
    pitch = nested_dict(event.get("pitch"))
    start_position = estimate_source_position(event, int(window["_start_frame"]))
    end_position = estimate_source_position(event, int(window["_end_frame"]))
    event_index = event.get("event_index")
    event_updates = [
        update for update in step_updates
        if update.get("active_event_index") == event_index
        and int(window["_start_frame"]) <= update["frame"] < int(window["_end_frame"])
    ]
    if not event_updates:
        event_updates = [
            update for update in step_updates
            if update.get("active_event_index") is None
            and update.get("channel_index") == event.get("channel_index")
            and int(window["_start_frame"]) <= update["frame"] < int(window["_end_frame"])
        ]
    update_suffix = ""
    if event_updates:
        first_update = event_updates[0]
        update_suffix = (
            f" updates {len(event_updates)} first {first_update['frame']} "
            f"{format_optional_float(first_update.get('playback_step_before'))}->"
            f"{format_optional_float(first_update.get('playback_step_after'))}"
        )
    return (
        f"{source_label(nested_dict(event.get('source')))} "
        f"ch {format_optional(event.get('channel_index'))} "
        f"note {format_optional(event.get('note'))} "
        f"eff {format_optional(pitch.get('effective_note_value'))} "
        f"rel {format_optional(pitch.get('sample_relative_note'))} "
        f"fine {format_optional(pitch.get('sample_finetune'))}/{format_optional(pitch.get('effective_finetune'))} "
        f"inst/sample {format_optional(event.get('instrument_index'))}/{format_optional(event.get('sample_index'))} "
        f"base {format_optional_float(pitch.get('sample_base_sample_rate'))} Hz "
        f"out {format_optional_float(pitch.get('output_sample_rate'))} Hz "
        f"period {format_optional_float(pitch.get('linear_period'))} "
        f"freq {format_optional_float(pitch.get('linear_frequency'))} "
        f"step {format_optional_float(pitch.get('playback_step'))} "
        f"source {format_position(start_position.rendered_position)}->{format_position(end_position.rendered_position)} "
        f"loop {format_optional(event.get('loop_mode'))}"
        f"{update_suffix}"
    )


def event_mechanics_for_window(event: dict[str, Any], window: dict[str, Any] | None) -> dict[str, Any]:
    pitch = nested_dict(event.get("pitch"))
    playback_step = number(pitch.get("playback_step"))
    start_frame = integer(event.get("_start_frame"))
    end_frame = integer(event.get("_end_frame"))
    if start_frame is None:
        start_frame = integer(event.get("scheduled_start_frame")) or 0
    if end_frame is None:
        end_frame = integer(event.get("estimated_end_frame")) or start_frame + 1
    if window is None:
        probe_start = start_frame
        probe_end = end_frame
    else:
        probe_start = max(start_frame, int(window["_start_frame"]))
        probe_end = min(end_frame, int(window["_end_frame"]))
    probe_end = max(probe_start, probe_end)

    start_position = estimate_source_position(event, probe_start)
    end_position = estimate_source_position(event, probe_end)
    loop_mode = str(event.get("loop_mode") or "none")
    loop_boundary_crossing = (
        loop_mode != "none"
        and start_position.boundary_crossing_count is not None
        and end_position.boundary_crossing_count is not None
        and end_position.boundary_crossing_count > start_position.boundary_crossing_count
    )
    crossing_delta = 0
    if start_position.boundary_crossing_count is not None and end_position.boundary_crossing_count is not None:
        crossing_delta = max(0, end_position.boundary_crossing_count - start_position.boundary_crossing_count)
    return {
        "event": event,
        "playback_step": playback_step,
        "fractional_playback_step": playback_step is not None and is_fractional(playback_step),
        "integer_playback_step": playback_step is not None and not is_fractional(playback_step),
        "neutral_playback_step": playback_step is not None and abs(playback_step - 1.0) <= FRACTION_EPSILON,
        "fractional_source_phase": (
            fractional_part_is_nonzero(start_position.fractional_part)
            or fractional_part_is_nonzero(end_position.fractional_part)
        ),
        "start_position": start_position,
        "end_position": end_position,
        "loop_mode": loop_mode,
        "loop_boundary_crossing": loop_boundary_crossing,
        "loop_boundary_crossing_count": crossing_delta if loop_mode != "none" else 0,
        "forward_loop_wrap_count": crossing_delta if loop_mode == "forward" else 0,
        "ping_pong_turnaround_count": crossing_delta if loop_mode == "ping_pong" else 0,
        "sample_offset_applied": event_sample_offset_applied(event),
    }


def pitch_mechanics_summary(mechanics: list[dict[str, Any]]) -> dict[str, Any]:
    pitch_objects = [nested_dict(nested_dict(item.get("event")).get("pitch")) for item in mechanics]
    playback_steps = [value for value in (number(pitch.get("playback_step")) for pitch in pitch_objects) if value is not None]
    sample_base_rates = [
        value for value in (number(pitch.get("sample_base_sample_rate")) for pitch in pitch_objects)
        if value is not None
    ]
    linear_periods = [value for value in (number(pitch.get("linear_period")) for pitch in pitch_objects) if value is not None]
    linear_frequencies = [
        value for value in (number(pitch.get("linear_frequency")) for pitch in pitch_objects)
        if value is not None
    ]
    return {
        "playback_step_min": min(playback_steps) if playback_steps else None,
        "playback_step_max": max(playback_steps) if playback_steps else None,
        "playback_step_missing_count": len(mechanics) - len(playback_steps),
        "sample_base_rate_min": min(sample_base_rates) if sample_base_rates else None,
        "sample_base_rate_max": max(sample_base_rates) if sample_base_rates else None,
        "sample_base_rate_missing_count": len(mechanics) - len(sample_base_rates),
        "linear_period_min": min(linear_periods) if linear_periods else None,
        "linear_period_max": max(linear_periods) if linear_periods else None,
        "linear_period_missing_count": len(mechanics) - len(linear_periods),
        "linear_frequency_min": min(linear_frequencies) if linear_frequencies else None,
        "linear_frequency_max": max(linear_frequencies) if linear_frequencies else None,
        "linear_frequency_missing_count": len(mechanics) - len(linear_frequencies),
    }


def build_alignment_summary(windows: list[dict[str, Any]]) -> dict[str, Any]:
    window_summaries: list[dict[str, Any]] = []
    for window in windows:
        alignment = nested_dict(window.get("local_alignment"))
        if not alignment:
            continue
        zero = nested_dict(alignment.get("zero_shift"))
        best = nested_dict(alignment.get("best_shift"))
        if not zero and not best:
            continue
        zero_corr = number(zero.get("normalized_correlation"))
        best_corr = number(best.get("normalized_correlation"))
        zero_rms = number(zero.get("rms_difference"))
        best_rms = number(best.get("rms_difference"))
        shift = integer(best.get("candidate_shift_frames"))
        window_summaries.append({
            "rank": int(window["_rank"]),
            "start_seconds": window["_start_seconds"],
            "end_seconds": window["_end_seconds"],
            "search_radius_frames": integer(alignment.get("search_radius_frames")),
            "zero_shift_correlation": zero_corr,
            "best_shift_frames": shift,
            "best_shift_seconds": number(best.get("candidate_shift_seconds")),
            "best_shift_correlation": best_corr,
            "correlation_improvement": None
            if zero_corr is None or best_corr is None else best_corr - zero_corr,
            "zero_shift_rms_difference": zero_rms,
            "best_shift_rms_difference": best_rms,
            "rms_difference_reduction": None
            if zero_rms is None or best_rms is None else zero_rms - best_rms,
        })
    return {
        "enabled": bool(window_summaries),
        "window_count": len(window_summaries),
        "nonzero_best_shift_count": sum(
            1 for item in window_summaries
            if (integer(item.get("best_shift_frames")) or 0) != 0
        ),
        "improved_correlation_count": sum(
            1 for item in window_summaries
            if (number(item.get("correlation_improvement")) or 0.0) > FRACTION_EPSILON
        ),
        "improved_rms_count": sum(
            1 for item in window_summaries
            if (number(item.get("rms_difference_reduction")) or 0.0) > FRACTION_EPSILON
        ),
        "window_summaries": window_summaries,
    }


def build_envelope_gain_summary(
    diagnostics: dict[str, Any],
    windows: list[dict[str, Any]],
    events: list[dict[str, Any]],
    rows: list[dict[str, Any]],
) -> dict[str, Any]:
    updates = normalize_gain_pan_updates(diagnostics, rows)
    key_offs = normalize_key_off_events(diagnostics, rows)
    event_envelopes = [event_envelope_signal(event) for event in events]
    window_summaries: list[dict[str, Any]] = []
    for window in windows:
        overlapping_events = [
            event for event in events
            if overlaps(event["_start_frame"], event["_end_frame"], window["_start_frame"], window["_end_frame"])
        ]
        overlapping_envelopes = [event_envelope_signal(event) for event in overlapping_events]
        window_updates = [
            update for update in updates
            if window["_start_frame"] <= update["frame"] < window["_end_frame"]
        ]
        window_key_offs = [
            item for item in key_offs
            if window["_start_frame"] <= item["frame"] < window["_end_frame"]
        ]
        probe_frame = window["_start_frame"] + max(0, (window["_end_frame"] - window["_start_frame"]) // 2)
        examples = envelope_gain_examples(overlapping_events, window_updates, window_key_offs, probe_frame)
        window_summaries.append({
            "rank": int(window["_rank"]),
            "start_seconds": window["_start_seconds"],
            "end_seconds": window["_end_seconds"],
            "event_count": len(overlapping_events),
            "envelope_enabled_event_count": sum(1 for item in overlapping_envelopes if item["envelope_enabled"]),
            "audible_envelope_event_count": audible_envelope_event_count(overlapping_events, probe_frame),
            "sustain_event_count": sum(1 for item in overlapping_envelopes if item["sustain_applied"] or item["sustain_deferred"]),
            "envelope_loop_event_count": sum(1 for item in overlapping_envelopes if item["loop_applied"] or item["loop_deferred"]),
            "fadeout_event_count": sum(1 for item in overlapping_envelopes if item["fadeout_applied"] or item["fadeout_deferred"]),
            "key_off_event_count": len(window_key_offs),
            "gain_update_count": sum(1 for item in window_updates if item["gain_changed"]),
            "pan_update_count": sum(1 for item in window_updates if item["pan_changed"]),
            "channel_volume_update_count": sum(1 for item in window_updates if item["channel_volume_changed"]),
            "global_volume_update_count": sum(1 for item in window_updates if item["global_volume_changed"]),
            "examples": examples,
        })
    return {
        "event_count": len(events),
        "envelope_enabled_event_count": sum(1 for item in event_envelopes if item["envelope_enabled"]),
        "sustain_event_count": sum(1 for item in event_envelopes if item["sustain_applied"] or item["sustain_deferred"]),
        "envelope_loop_event_count": sum(1 for item in event_envelopes if item["loop_applied"] or item["loop_deferred"]),
        "fadeout_event_count": sum(1 for item in event_envelopes if item["fadeout_applied"] or item["fadeout_deferred"]),
        "key_off_event_count": len(key_offs),
        "gain_update_count": sum(1 for item in updates if item["gain_changed"]),
        "pan_update_count": sum(1 for item in updates if item["pan_changed"]),
        "channel_volume_update_count": sum(1 for item in updates if item["channel_volume_changed"]),
        "global_volume_update_count": sum(1 for item in updates if item["global_volume_changed"]),
        "window_summaries": window_summaries,
    }


def normalize_gain_pan_updates(diagnostics: dict[str, Any], rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows_by_source, rows_by_synthetic = row_frame_indexes(rows)
    updates: list[dict[str, Any]] = []
    for raw_update in nested_list(diagnostics.get("volume_panning_state_updates")):
        if not isinstance(raw_update, dict):
            continue
        frame, _ = frame_range_for_diagnostic(raw_update, rows_by_source, rows_by_synthetic)
        if frame is None:
            continue
        gain_before = number(raw_update.get("gain_before"))
        gain_after = number(raw_update.get("gain_after"))
        pan_before = number(raw_update.get("pan_before"))
        pan_after = number(raw_update.get("pan_after"))
        volume_before = number(raw_update.get("effective_volume_before"))
        volume_after = number(raw_update.get("effective_volume_after"))
        global_before = number(raw_update.get("global_volume_before"))
        global_after = number(raw_update.get("global_volume_after"))
        updates.append({
            "frame": max(0, frame),
            "source": nested_dict(raw_update.get("source")),
            "channel_index": raw_update.get("target_channel_index", raw_update.get("channel_index")),
            "active_event_index": raw_update.get("active_event_index"),
            "command_name": raw_update.get("command_name") or raw_update.get("command_label") or raw_update.get("command"),
            "status": raw_update.get("status"),
            "gain_before": gain_before,
            "gain_after": gain_after,
            "pan_before": pan_before,
            "pan_after": pan_after,
            "gain_changed": values_changed(gain_before, gain_after),
            "pan_changed": values_changed(pan_before, pan_after),
            "channel_volume_changed": values_changed(volume_before, volume_after),
            "global_volume_changed": values_changed(global_before, global_after),
        })
    updates.sort(key=lambda item: (item["frame"], sort_int(item.get("channel_index")), str(item.get("command_name"))))
    return updates


def normalize_key_off_events(diagnostics: dict[str, Any], rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows_by_source, rows_by_synthetic = row_frame_indexes(rows)
    result: list[dict[str, Any]] = []
    for raw_event in nested_list(diagnostics.get("key_off_events")):
        if not isinstance(raw_event, dict):
            continue
        frame, _ = frame_range_for_diagnostic(raw_event, rows_by_source, rows_by_synthetic)
        if frame is None:
            frame = integer(raw_event.get("release_frame"))
        if frame is None:
            continue
        result.append({
            "frame": max(0, frame),
            "source": nested_dict(raw_event.get("source")),
            "channel_index": raw_event.get("channel_index"),
            "applied": bool(raw_event.get("applied")),
            "deferred": bool(raw_event.get("deferred")),
            "reason": raw_event.get("reason"),
        })
    result.sort(key=lambda item: (item["frame"], sort_int(item.get("channel_index"))))
    return result


def event_envelope_signal(event: dict[str, Any]) -> dict[str, Any]:
    envelope = nested_dict(event.get("volume_envelope"))
    return {
        "envelope_enabled": bool(envelope.get("enabled")) or str(envelope.get("status") or "") == "mapped",
        "sustain_applied": bool(envelope.get("sustain_applied")),
        "sustain_deferred": bool(envelope.get("sustain_deferred") or envelope.get("has_deferred_sustain")),
        "loop_applied": bool(envelope.get("loop_applied")),
        "loop_deferred": bool(envelope.get("loop_deferred") or envelope.get("has_deferred_loop")),
        "key_off_applied": bool(envelope.get("key_off_applied")),
        "key_off_deferred": bool(envelope.get("key_off_deferred")),
        "fadeout_applied": bool(envelope.get("fadeout_applied")),
        "fadeout_deferred": bool(envelope.get("fadeout_deferred") or envelope.get("has_deferred_fadeout")),
    }


def envelope_gain_examples(
    events: list[dict[str, Any]],
    updates: list[dict[str, Any]],
    key_offs: list[dict[str, Any]],
    probe_frame: int | None = None,
) -> list[str]:
    examples: list[str] = []
    ordered_events = events
    if probe_frame is not None:
        ordered_events = sorted(
            events,
            key=lambda event: 0 if envelope_event_is_audible(event, probe_frame) else 1,
        )
    for event in ordered_events:
        envelope = nested_dict(event.get("volume_envelope"))
        signal = event_envelope_signal(event)
        if not any(signal.values()):
            continue
        parts = [source_label(nested_dict(event.get("source"))), f"ch {format_optional(event.get('channel_index'))}"]
        if signal["sustain_applied"] or signal["sustain_deferred"]:
            parts.append("sustain")
        if signal["loop_applied"] or signal["loop_deferred"]:
            parts.append("env-loop")
        if signal["key_off_applied"] or signal["key_off_deferred"]:
            parts.append("key-off")
        if signal["fadeout_applied"] or signal["fadeout_deferred"]:
            parts.append(f"fadeout {format_optional(envelope.get('fadeout_value'))}")
        if probe_frame is not None:
            parts.append(envelope_state_label(event, probe_frame))
        examples.append(" ".join(parts))
        if len(examples) >= MAX_ENVELOPE_GAIN_EXAMPLES:
            return examples
    for key_off in key_offs:
        examples.append(
            f"{source_label(nested_dict(key_off.get('source')))} ch {format_optional(key_off.get('channel_index'))} key-off"
        )
        if len(examples) >= MAX_ENVELOPE_GAIN_EXAMPLES:
            return examples
    for update in updates:
        changed = []
        if update["gain_changed"]:
            changed.append("gain")
        if update["pan_changed"]:
            changed.append("pan")
        if update["channel_volume_changed"]:
            changed.append("chan-vol")
        if update["global_volume_changed"]:
            changed.append("global-vol")
        if not changed:
            continue
        examples.append(
            f"{source_label(nested_dict(update.get('source')))} ch {format_optional(update.get('channel_index'))} "
            f"{','.join(changed)} {format_optional(update.get('command_name'))}"
        )
        if len(examples) >= MAX_ENVELOPE_GAIN_EXAMPLES:
            return examples
    return examples


def envelope_event_is_audible(event: dict[str, Any], probe_frame: int) -> bool:
    snapshot = event_envelope_snapshot(event, probe_frame)
    if snapshot is None:
        return False
    return (number(snapshot.get("final_voice_gain")) or 0.0) > AUDIBLE_GAIN_EPSILON


def audible_envelope_event_count(events: list[dict[str, Any]], probe_frame: int) -> int:
    count = 0
    for event in events:
        if not event_envelope_signal(event)["envelope_enabled"]:
            continue
        if envelope_event_is_audible(event, probe_frame):
            count += 1
    return count


def envelope_state_label(event: dict[str, Any], frame: int) -> str:
    snapshot = event_envelope_snapshot(event, frame)
    if snapshot is None:
        return f"env@{frame} unavailable"
    return (
        f"env@{frame} pos {format_optional(snapshot.get('position_frame'))} "
        f"val {format_optional_float(snapshot.get('value'))} "
        f"seg {format_optional(snapshot.get('segment_index'))} "
        f"key-on {snapshot.get('key_on')} "
        f"sustain-held {snapshot.get('sustain_held')} "
        f"loop-active {snapshot.get('loop_active')} "
        f"fadeout {format_optional_float(snapshot.get('fadeout_value'))} "
        f"final-gain {format_optional_float(snapshot.get('final_voice_gain'))}"
    )


def event_envelope_snapshot(event: dict[str, Any], frame: int) -> dict[str, Any] | None:
    envelope = nested_dict(event.get("volume_envelope"))
    points = envelope_points(envelope)
    if not points:
        return None
    start_frame = integer(event.get("_start_frame"))
    if start_frame is None:
        start_frame = integer(event.get("scheduled_start_frame")) or 0
    key_off_frame = integer(envelope.get("key_off_frame"))
    if key_off_frame is None:
        key_off_frame = integer(envelope.get("release_frame"))
    relative_frame = max(0, frame - max(0, start_frame))
    relative_key_off_frame = None if key_off_frame is None else max(0, key_off_frame - max(0, start_frame))
    key_on = relative_key_off_frame is None or relative_frame < relative_key_off_frame
    key_off_basis = relative_key_off_frame if relative_key_off_frame is not None else relative_frame
    keyed_frames = relative_frame if key_on else min(relative_frame, key_off_basis)
    released_frames = 0 if key_on else max(0, relative_frame - key_off_basis)
    position = advance_envelope_position(0, keyed_frames, True, envelope)
    position = advance_envelope_position(position, released_frames, False, envelope)
    value = envelope_value_at(points, position)
    fadeout_decrement = number(envelope.get("fadeout_frame_decrement")) or 0.0
    fadeout_value = 1.0 if key_on else max(0.0, 1.0 - (released_frames * max(0.0, fadeout_decrement)))
    base_gain = number(event.get("gain")) or 0.0
    sustain_frame = integer(envelope.get("sustain_frame"))
    loop_start = integer(envelope.get("loop_start_frame"))
    loop_end = integer(envelope.get("loop_end_frame"))
    return {
        "position_frame": position,
        "value": value,
        "segment_index": envelope_segment_index(points, position),
        "key_on": key_on,
        "sustain_held": key_on and sustain_frame is not None and position == sustain_frame and keyed_frames >= sustain_frame,
        "loop_active": key_on and loop_start is not None and loop_end is not None and loop_start <= position <= loop_end,
        "fadeout_value": fadeout_value,
        "final_voice_gain": base_gain * value * fadeout_value,
    }


def envelope_points(envelope: dict[str, Any]) -> list[dict[str, float]]:
    points: list[dict[str, float]] = []
    for raw_point in nested_list(envelope.get("points")):
        if not isinstance(raw_point, dict):
            continue
        position_frame = integer(raw_point.get("position_frame"))
        value = number(raw_point.get("value"))
        if position_frame is None or value is None:
            continue
        points.append({"position_frame": float(max(0, position_frame)), "value": value})
    points.sort(key=lambda item: item["position_frame"])
    return points


def advance_envelope_position(position: int, frames: int, key_on: bool, envelope: dict[str, Any]) -> int:
    position = max(0, position)
    frames = max(0, frames)
    if frames <= 0:
        return position
    if not key_on:
        return position + frames
    sustain_frame = integer(envelope.get("sustain_frame"))
    if sustain_frame is not None and position >= sustain_frame:
        return sustain_frame
    loop_start = integer(envelope.get("loop_start_frame"))
    loop_end = integer(envelope.get("loop_end_frame"))
    if sustain_frame is not None and can_reach_sustain_before_loop(position, frames, sustain_frame, loop_end):
        return sustain_frame
    if loop_start is None or loop_end is None or loop_end < loop_start:
        return position + frames
    target = position + frames
    if target <= loop_end:
        return target
    loop_length = loop_end - loop_start + 1
    if loop_length <= 0:
        return target
    return loop_start + ((target - loop_end - 1) % loop_length)


def can_reach_sustain_before_loop(position: int, frames: int, sustain_frame: int, loop_end_frame: int | None) -> bool:
    if position >= sustain_frame or position + frames < sustain_frame:
        return False
    return not (loop_end_frame is not None and loop_end_frame < sustain_frame and position + frames > loop_end_frame)


def envelope_value_at(points: list[dict[str, float]], position_frame: int) -> float:
    if not points:
        return 1.0
    first = points[0]
    if position_frame <= first["position_frame"]:
        return first["value"]
    for index in range(1, len(points)):
        previous = points[index - 1]
        current = points[index]
        if position_frame <= current["position_frame"]:
            span = max(1.0, current["position_frame"] - previous["position_frame"])
            progress = (position_frame - previous["position_frame"]) / span
            return previous["value"] + ((current["value"] - previous["value"]) * progress)
    return points[-1]["value"]


def envelope_segment_index(points: list[dict[str, float]], position_frame: int) -> int | None:
    if not points:
        return None
    if position_frame <= points[0]["position_frame"]:
        return 0
    for index in range(1, len(points)):
        if position_frame <= points[index]["position_frame"]:
            return index - 1
    return len(points) - 1


def values_changed(before: float | None, after: float | None) -> bool:
    return before is not None and after is not None and abs(after - before) > FRACTION_EPSILON


def estimate_source_position(event: dict[str, Any], frame: int) -> SourcePositionEstimate:
    start_frame = integer(event.get("_start_frame"))
    if start_frame is None:
        start_frame = integer(event.get("scheduled_start_frame")) or 0
    pitch = nested_dict(event.get("pitch"))
    playback_step = number(pitch.get("playback_step"))
    if playback_step is None or playback_step <= 0:
        return SourcePositionEstimate(0.0, None, None, None)
    initial_source_frame = number(event.get("initial_source_frame")) or 0.0
    raw_position = initial_source_frame + (max(0, frame - start_frame) * playback_step)
    loop_mode = str(event.get("loop_mode") or "none")
    sample_frame_count = integer(event.get("sample_frame_count"))
    loop_start = integer(event.get("loop_start_frame"))
    loop_end = integer(event.get("loop_end_frame"))

    if loop_mode == "forward" and loop_start is not None and loop_end is not None and loop_end > loop_start:
        loop_length = loop_end - loop_start
        if raw_position >= loop_end:
            overflow = raw_position - loop_end
            crossing_count = int(math.floor(overflow / loop_length)) + 1
            rendered = loop_start + math.fmod(overflow, loop_length)
        else:
            crossing_count = 0
            rendered = raw_position
        return SourcePositionEstimate(
            raw_position=raw_position,
            rendered_position=rendered,
            fractional_part=fractional_part(rendered),
            boundary_crossing_count=crossing_count,
        )

    if loop_mode == "ping_pong" and loop_start is not None and loop_end is not None and loop_end > loop_start + 1:
        first_frame = float(loop_start)
        last_frame = float(loop_end - 1)
        span = last_frame - first_frame
        if raw_position <= last_frame:
            rendered = raw_position
            crossing_count = 0
        else:
            excess = raw_position - last_frame
            period = span * 2.0
            phase = math.fmod(excess, period)
            crossing_count = int(math.floor(excess / span)) + 1
            if phase <= span:
                rendered = last_frame - phase
            else:
                rendered = first_frame + (phase - span)
        return SourcePositionEstimate(
            raw_position=raw_position,
            rendered_position=rendered,
            fractional_part=fractional_part(rendered),
            boundary_crossing_count=crossing_count,
        )

    crossing_count = 0
    if sample_frame_count is not None and raw_position >= sample_frame_count:
        crossing_count = 1
    return SourcePositionEstimate(
        raw_position=raw_position,
        rendered_position=raw_position,
        fractional_part=fractional_part(raw_position),
        boundary_crossing_count=crossing_count,
    )


def recommend_rendering_mechanics(summary: dict[str, Any]) -> tuple[str, str]:
    shape = str(summary.get("comparison_shape") or "unknown")
    window_summaries = nested_list(summary.get("window_summaries"))
    window_fractional_steps = sum(integer(item.get("fractional_step_event_count")) or 0 for item in window_summaries if isinstance(item, dict))
    window_loop_crossings = sum(integer(item.get("loop_boundary_crossing_event_count")) or 0 for item in window_summaries if isinstance(item, dict))
    window_sample_offsets = sum(integer(item.get("sample_offset_event_count")) or 0 for item in window_summaries if isinstance(item, dict))
    window_step_updates = sum(integer(item.get("step_update_count")) or 0 for item in window_summaries if isinstance(item, dict))

    if bool(summary.get("sample_rate_mismatch")):
        return (
            "output_sample_rate_difference",
            "render, candidate, and reference sample rates do not all match.",
        )
    if shape == "broad_low_correlation" and window_fractional_steps > 0:
        return (
            "interpolation_or_sample_step_plausible",
            "top windows overlap fractional playback steps and the comparison shape is broad/low-correlation.",
        )
    if window_loop_crossings > 0 and shape == "localized":
        return (
            "loop_endpoint_or_loop_interpolation_plausible",
            "top localized windows include estimated loop-boundary crossings.",
        )
    if window_sample_offsets > 0 and shape == "localized":
        return (
            "sample_offset_rounding_plausible",
            "top localized windows overlap applied sample-offset starts.",
        )
    if window_step_updates > 0:
        return (
            "pitch_or_sample_step_update_timing_possible",
            "top windows include scheduled pitch/sample-step updates.",
        )
    if window_fractional_steps > 0:
        return (
            "interpolation_or_sample_step_possible",
            "top windows overlap fractional playback steps, but the comparison shape is not strongly broad.",
        )
    if window_loop_crossings > 0:
        return (
            "loop_endpoint_possible",
            "top windows include estimated loop-boundary crossings.",
        )
    return (
        "insufficient_rendering_mechanics_evidence",
        "top windows did not expose fractional steps, sample-offset starts, step updates, or loop-boundary crossings.",
    )


def comparison_shape(comparison: dict[str, Any]) -> str:
    sample = comparison.get("sample_comparison")
    if not isinstance(sample, dict):
        return "comparison_unavailable"
    correlation = number(sample.get("normalized_correlation"))
    diff = nested_dict(sample.get("diff"))
    overall = number(diff.get("overall_rms_difference"))
    windows = [item for item in nested_list(sample.get("worst_windows")) if isinstance(item, dict)]
    top = number(windows[0].get("rms_difference")) if windows else None
    if overall is not None and overall <= 0.005 and (correlation is None or correlation >= 0.995):
        return "close"
    if correlation is not None and correlation < 0.90:
        return "broad_low_correlation"
    if overall is not None and top is not None and overall > 0 and top / overall >= 2.5:
        return "localized"
    return "mixed_or_broad"


def event_sample_offset_applied(event: dict[str, Any]) -> bool:
    sample_offset = nested_dict(event.get("sample_offset"))
    if bool(sample_offset.get("applied")):
        return True
    initial = number(event.get("initial_source_frame"))
    return initial is not None and initial > 0


def is_fractional(value: float) -> bool:
    return abs(value - round(value)) > FRACTION_EPSILON


def fractional_part(value: float | None) -> float | None:
    if value is None or not math.isfinite(value):
        return None
    return value - math.floor(value)


def fractional_part_is_nonzero(value: float | None) -> bool:
    if value is None:
        return False
    return value > FRACTION_EPSILON and abs(value - 1.0) > FRACTION_EPSILON


def mechanics_example_label(item: dict[str, Any]) -> str:
    event = nested_dict(item.get("event"))
    pitch = nested_dict(event.get("pitch"))
    start = item["start_position"]
    end = item["end_position"]
    assert isinstance(start, SourcePositionEstimate)
    assert isinstance(end, SourcePositionEstimate)
    loop_mode = str(item.get("loop_mode") or "none")
    loop_range = ""
    if loop_mode != "none":
        loop_range = (
            f" loop {loop_mode} "
            f"{format_optional(event.get('loop_start_frame'))}-{format_optional(event.get('loop_end_frame'))}"
        )
    return (
        f"{source_label(nested_dict(event.get('source')))} "
        f"ch {format_optional(event.get('channel_index'))} "
        f"note {format_optional(event.get('note'))} "
        f"inst/sample {format_optional(event.get('instrument_index'))}/{format_optional(event.get('sample_index'))} "
        f"step {format_optional_float(pitch.get('playback_step'))} "
        f"source {format_position(start.rendered_position)}->{format_position(end.rendered_position)}"
        f"{loop_range}"
    )


def format_position(value: float | None) -> str:
    if value is None:
        return "unavailable"
    return f"{value:.4f}"


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
    alignment_summary = build_alignment_summary(windows)
    rendering_mechanics = build_rendering_mechanics_summary(comparison, diagnostics, windows, events, rows)
    period_sample_step_summary = build_period_sample_step_voice_summary(diagnostics, windows, events, rows)
    loop_crossing_timbre_summary = build_loop_crossing_timbre_summary(diagnostics, windows, events)
    steady_state_loop_summary = build_steady_state_loop_summary(diagnostics, windows, events, rows)
    gain_pan_voice_summary = build_gain_pan_voice_summary(diagnostics, windows, events)
    sample_instrument_gain_summary = build_sample_instrument_gain_summary(comparison, diagnostics, windows, events)
    envelope_gain_summary = build_envelope_gain_summary(diagnostics, windows, events, rows)
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
    append_alignment_summary(lines, alignment_summary)
    append_rendering_mechanics_summary(lines, rendering_mechanics)
    append_period_sample_step_voice_summary(lines, period_sample_step_summary)
    append_loop_crossing_timbre_summary(lines, loop_crossing_timbre_summary)
    append_steady_state_loop_summary(lines, steady_state_loop_summary)
    append_gain_pan_voice_summary(lines, gain_pan_voice_summary)
    append_sample_instrument_gain_summary(lines, sample_instrument_gain_summary)
    append_envelope_gain_summary(lines, envelope_gain_summary)

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


def append_rendering_mechanics_summary(lines: list[str], summary: dict[str, Any]) -> None:
    pitch_counts = nested_dict(summary.get("pitch_frequency_table_counts"))
    pitch_count_label = ", ".join(
        f"{key}={value}" for key, value in sorted(pitch_counts.items())
    ) or "unavailable"
    total_events = integer(summary.get("total_event_count")) or 0
    lines.extend([
        "",
        "## Sample-Step / Interpolation Evidence",
        f"- Interpolation mode: {format_optional(summary.get('interpolation_mode'))}",
        "- Sample rates: "
        f"render {format_optional_float(summary.get('render_sample_rate'))} Hz, "
        f"candidate {format_optional_float(summary.get('candidate_sample_rate'))} Hz, "
        f"reference {format_optional_float(summary.get('reference_sample_rate'))} Hz, "
        f"mismatch {str(bool(summary.get('sample_rate_mismatch'))).lower()}",
        f"- Comparison shape: {format_optional(summary.get('comparison_shape'))}",
        "- Playback-step events: "
        f"{format_optional(summary.get('fractional_step_event_count'))}/{total_events} fractional, "
        f"{format_optional(summary.get('integer_step_event_count'))}/{total_events} integer, "
        f"{format_optional(summary.get('neutral_step_event_count'))}/{total_events} neutral-step",
        "- Source-position phase events: "
        f"{format_optional(summary.get('fractional_source_phase_event_count'))}/{total_events} fractional phase estimates",
        "- Loop/sample-offset events: "
        f"{format_optional(summary.get('looped_event_count'))}/{total_events} looped, "
        f"{format_optional(summary.get('sample_offset_event_count'))}/{total_events} sample-offset starts",
        "- Estimated loop boundary crossings: "
        f"{format_optional(summary.get('loop_boundary_crossing_count'))} total, "
        f"{format_optional(summary.get('forward_loop_wrap_count'))} forward wraps, "
        f"{format_optional(summary.get('ping_pong_turnaround_count'))} ping-pong turnarounds",
        f"- Scheduled sample-step updates: {format_optional(summary.get('step_update_count'))}",
        "- Playback-step range: "
        f"{format_optional_float(summary.get('playback_step_min'))}..."
        f"{format_optional_float(summary.get('playback_step_max'))}; "
        f"missing {format_optional(summary.get('playback_step_missing_count'))}",
        "- Sample base-rate range: "
        f"{format_optional_float(summary.get('sample_base_rate_min'))}..."
        f"{format_optional_float(summary.get('sample_base_rate_max'))} Hz; "
        f"missing {format_optional(summary.get('sample_base_rate_missing_count'))}",
        "- Linear period/frequency ranges: "
        f"period {format_optional_float(summary.get('linear_period_min'))}..."
        f"{format_optional_float(summary.get('linear_period_max'))}, "
        f"frequency {format_optional_float(summary.get('linear_frequency_min'))}..."
        f"{format_optional_float(summary.get('linear_frequency_max'))}; "
        f"missing period/frequency "
        f"{format_optional(summary.get('linear_period_missing_count'))}/"
        f"{format_optional(summary.get('linear_frequency_missing_count'))}",
        f"- Pitch frequency-table statuses: {pitch_count_label}",
        "- Amiga/neutral fallback evidence: "
        f"{format_optional(summary.get('amiga_deferred_event_count'))} Amiga-deferred, "
        f"{format_optional(summary.get('neutral_step_fallback_event_count'))} neutral-fallback",
        f"- Candidate mechanics signal: {format_optional(summary.get('candidate_signal'))}",
        f"- Mechanics rationale: {format_optional(summary.get('candidate_signal_rationale'))}",
    ])
    window_summaries = [
        item for item in nested_list(summary.get("window_summaries"))
        if isinstance(item, dict)
    ]
    if not window_summaries:
        lines.append("- Worst-window mechanics: unavailable")
        return

    lines.extend([
        "",
        "| Window | Events | Fractional Steps | Fractional Source Phase | Loop Crossings | Sample Offsets | Step Updates | Forward Wraps | Ping-Pong Turns | Step Range | Examples |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |",
    ])
    for item in window_summaries:
        examples = "; ".join(str(example) for example in nested_list(item.get("examples"))) or "none"
        step_range = (
            f"{format_optional_float(item.get('playback_step_min'))}..."
            f"{format_optional_float(item.get('playback_step_max'))}"
        )
        lines.append(
            f"| {format_optional(item.get('rank'))} | "
            f"{format_optional(item.get('event_count'))} | "
            f"{format_optional(item.get('fractional_step_event_count'))} | "
            f"{format_optional(item.get('fractional_source_phase_event_count'))} | "
            f"{format_optional(item.get('loop_boundary_crossing_event_count'))} | "
            f"{format_optional(item.get('sample_offset_event_count'))} | "
            f"{format_optional(item.get('step_update_count'))} | "
            f"{format_optional(item.get('forward_loop_wrap_count'))} | "
            f"{format_optional(item.get('ping_pong_turnaround_count'))} | "
            f"{step_range} | "
            f"{examples} |"
        )


def append_period_sample_step_voice_summary(lines: list[str], summary: dict[str, Any]) -> None:
    lines.extend([
        "",
        "## Period / Sample-Step Voice Evidence",
        f"- Windowed render-aware active-voice estimate: {str(bool(summary.get('windowed_render_aware'))).lower()}",
        f"- Render windows: {format_optional(summary.get('render_window_count'))}",
    ])
    window_summaries = [
        item for item in nested_list(summary.get("window_summaries"))
        if isinstance(item, dict)
    ]
    if not window_summaries:
        lines.append("- Worst-window active voice evidence: unavailable")
        return
    lines.extend([
        "",
        "| Window | Active Voices | Channels | Looped Voices | Step Updates | Step Range | Base Rate Range | Period Range | Voice Examples |",
        "| ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |",
    ])
    for item in window_summaries:
        step_range = (
            f"{format_optional_float(item.get('playback_step_min'))}..."
            f"{format_optional_float(item.get('playback_step_max'))}"
        )
        base_range = (
            f"{format_optional_float(item.get('sample_base_rate_min'))}..."
            f"{format_optional_float(item.get('sample_base_rate_max'))}"
        )
        period_range = (
            f"{format_optional_float(item.get('linear_period_min'))}..."
            f"{format_optional_float(item.get('linear_period_max'))}"
        )
        examples = "; ".join(str(example) for example in nested_list(item.get("examples"))) or "none"
        lines.append(
            f"| {format_optional(item.get('rank'))} | "
            f"{format_optional(item.get('active_voice_count'))} | "
            f"{format_optional(item.get('active_channel_count'))} | "
            f"{format_optional(item.get('looped_voice_count'))} | "
            f"{format_optional(item.get('sample_step_update_count'))} | "
            f"{step_range} | "
            f"{base_range} | "
            f"{period_range} | "
            f"{examples} |"
        )


def append_loop_crossing_timbre_summary(lines: list[str], summary: dict[str, Any]) -> None:
    lines.extend([
        "",
        "## Loop-Crossing Timbre Evidence",
        f"- Windowed render-aware active-voice estimate: {str(bool(summary.get('windowed_render_aware'))).lower()}",
        f"- Render windows: {format_optional(summary.get('render_window_count'))}",
        "- Looped events: "
        f"{format_optional(summary.get('looped_event_count'))}/"
        f"{format_optional(summary.get('event_count'))}; "
        f"estimated crossing events {format_optional(summary.get('loop_crossing_event_count'))}; "
        f"crossings {format_optional(summary.get('loop_boundary_crossing_count'))}",
        "- Timbre metrics in comparison windows: "
        f"{format_optional(summary.get('timbre_metric_window_count'))}/"
        f"{format_optional(summary.get('window_count'))}",
        "- Dominant looped voice score: final_gain^2 times active overlap frames; this is a level-weighted estimate, not isolated audio RMS",
    ])
    window_summaries = [
        item for item in nested_list(summary.get("window_summaries"))
        if isinstance(item, dict)
    ]
    if not window_summaries:
        lines.append("- Worst-window loop-crossing evidence: unavailable")
        return
    lines.extend([
        "",
        "| Window | Active Voices | Looped Voices | Crossing Voices | Loop Crossings | Forward Wraps | Step Range | Final Gain Range | Residual Timbre | Dominant Looped Instruments/Samples | Voice Examples |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- |",
    ])
    for item in window_summaries:
        dominant = "; ".join(
            looped_instrument_sample_group_label(group)
            for group in nested_list(item.get("dominant"))
            if isinstance(group, dict)
        ) or "none"
        examples = "; ".join(str(example) for example in nested_list(item.get("examples"))) or "none"
        lines.append(
            f"| {format_optional(item.get('rank'))} | "
            f"{format_optional(item.get('active_voice_count'))} | "
            f"{format_optional(item.get('looped_voice_count'))} | "
            f"{format_optional(item.get('crossing_voice_count'))} | "
            f"{format_optional(item.get('loop_boundary_crossing_count'))} | "
            f"{format_optional(item.get('forward_loop_wrap_count'))} | "
            f"{format_distribution_range(nested_dict(item.get('playback_step')))} | "
            f"{format_distribution_range(nested_dict(item.get('final_gain')))} | "
            f"{loop_timbre_label(nested_dict(item.get('timbre')))} | "
            f"{dominant} | "
            f"{examples} |"
        )


def append_steady_state_loop_summary(lines: list[str], summary: dict[str, Any]) -> None:
    lines.extend([
        "",
        "## Steady-State Looped Sample Evidence",
        f"- Windowed render-aware active-voice estimate: {str(bool(summary.get('windowed_render_aware'))).lower()}",
        f"- Render windows: {format_optional(summary.get('render_window_count'))}",
        f"- Looped events: {format_optional(summary.get('looped_event_count'))}/{format_optional(summary.get('event_count'))}",
        f"- Classification policy: {format_optional(summary.get('classification_policy'))}",
        f"- Contribution policy: {format_optional(summary.get('contribution_policy'))}",
    ])
    window_summaries = [
        item for item in nested_list(summary.get("window_summaries"))
        if isinstance(item, dict)
    ]
    if not window_summaries:
        lines.append("- Worst-window steady-state loop evidence: unavailable")
        return
    lines.extend([
        "",
        "| Window | Active Voices | Looped Voices | Steady Interior Voices | Loop Crossings | Step/Gain/Ramp Updates | Loop Phase Histogram | Residual Timbre | Dominant Looped Instruments/Samples | Voice Examples |",
        "| ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- |",
    ])
    for item in window_summaries:
        dominant = "; ".join(
            steady_state_loop_group_label(group)
            for group in nested_list(item.get("dominant"))
            if isinstance(group, dict)
        ) or "none"
        examples = "; ".join(str(example) for example in nested_list(item.get("examples"))) or "none"
        updates = (
            f"{format_optional(item.get('sample_step_update_count'))}/"
            f"{format_optional(item.get('gain_update_count'))}/"
            f"{format_optional(item.get('replacement_ramp_count'))}"
        )
        lines.append(
            f"| {format_optional(item.get('rank'))} | "
            f"{format_optional(item.get('active_voice_count'))} | "
            f"{format_optional(item.get('looped_voice_count'))} | "
            f"{format_optional(item.get('steady_state_loop_interior_voice_count'))} | "
            f"{format_optional(item.get('loop_boundary_crossing_count'))} | "
            f"{updates} | "
            f"{format_phase_histogram(nested_dict(item.get('loop_phase_histogram')))} | "
            f"{loop_timbre_label(nested_dict(item.get('timbre')))} | "
            f"{dominant} | "
            f"{examples} |"
        )


def append_gain_pan_voice_summary(lines: list[str], summary: dict[str, Any]) -> None:
    base_gain = nested_dict(summary.get("base_gain"))
    pan = nested_dict(summary.get("pan"))
    lines.extend([
        "",
        "## Gain / Pan Voice Evidence",
        f"- Pan law: {format_optional(summary.get('pan_law'))}",
        f"- Pan law detail: {format_optional(summary.get('pan_law_detail'))}",
        f"- Windowed render-aware active-voice estimate: {str(bool(summary.get('windowed_render_aware'))).lower()}",
        "- Event base-gain range: "
        f"{format_distribution_range(base_gain)}; mean {format_optional_float(base_gain.get('mean'))}; "
        f"missing {format_optional(base_gain.get('missing_count'))}",
        "- Event pan range: "
        f"{format_distribution_range(pan)}; mean {format_optional_float(pan.get('mean'))}; "
        f"missing {format_optional(pan.get('missing_count'))}",
    ])
    window_summaries = [
        item for item in nested_list(summary.get("window_summaries"))
        if isinstance(item, dict)
    ]
    if not window_summaries:
        lines.append("- Worst-window gain/pan voice evidence: unavailable")
        return
    lines.extend([
        "",
        "| Window | Active Voices | Probe Frame | Final Gain Range | Pan Range | L Gain Range | R Gain Range | Center/Hard L/Hard R | Voice Examples |",
        "| ---: | ---: | ---: | --- | --- | --- | --- | --- | --- |",
    ])
    for item in window_summaries:
        examples = "; ".join(str(example) for example in nested_list(item.get("examples"))) or "none"
        lines.append(
            f"| {format_optional(item.get('rank'))} | "
            f"{format_optional(item.get('active_voice_count'))} | "
            f"{format_optional(item.get('probe_frame'))} | "
            f"{format_distribution_range(nested_dict(item.get('final_gain')))} | "
            f"{format_distribution_range(nested_dict(item.get('pan')))} | "
            f"{format_distribution_range(nested_dict(item.get('left_gain')))} | "
            f"{format_distribution_range(nested_dict(item.get('right_gain')))} | "
            f"{format_optional(item.get('center_pan_voice_count'))}/"
            f"{format_optional(item.get('hard_left_voice_count'))}/"
            f"{format_optional(item.get('hard_right_voice_count'))} | "
            f"{examples} |"
        )


def append_sample_instrument_gain_summary(lines: list[str], summary: dict[str, Any]) -> None:
    sample_volume = nested_dict(summary.get("sample_volume"))
    raw_sample_volume = nested_dict(summary.get("sample_volume_raw_estimate"))
    channel_volume = nested_dict(summary.get("channel_volume"))
    global_volume = nested_dict(summary.get("global_volume"))
    base_gain = nested_dict(summary.get("base_gain"))
    window_scalar = nested_dict(summary.get("window_candidate_scalar"))
    lines.extend([
        "",
        "## Sample / Instrument Gain Evidence",
        f"- Gain construction: {format_optional(summary.get('gain_construction'))}",
        f"- Sample volume source: {format_optional(summary.get('sample_volume_source'))}",
        f"- C mixer gain expectation: {format_optional(summary.get('c_mixer_gain_expectation'))}",
        f"- Active voice lifetime: {format_optional(summary.get('active_voice_lifetime'))}",
        f"- Whole-song candidate scalar to reference: {format_optional_float(summary.get('global_candidate_scalar_to_reference'))}",
        "- Worst-window candidate scalar range: "
        f"{format_distribution_range(window_scalar)}; mean {format_optional_float(window_scalar.get('mean'))}; "
        f"missing {format_optional(window_scalar.get('missing_count'))}",
        f"- Voice count vs window RMS-diff correlation: {format_optional_float(summary.get('voice_count_to_window_rms_correlation'))}",
        "- Dominant instrument/sample score: final_gain^2 times active overlap frames; this is a level-weighted estimate, not isolated audio RMS",
        "- Event sample-volume range: "
        f"{format_distribution_range(sample_volume)}; raw {format_distribution_range(raw_sample_volume)}; "
        f"missing {format_optional(sample_volume.get('missing_count'))}",
        "- Event channel/global-volume range: "
        f"channel {format_distribution_range(channel_volume)}, "
        f"global {format_distribution_range(global_volume)}",
        "- Event base-gain range: "
        f"{format_distribution_range(base_gain)}; mean {format_optional_float(base_gain.get('mean'))}; "
        f"missing {format_optional(base_gain.get('missing_count'))}",
    ])
    window_summaries = [
        item for item in nested_list(summary.get("window_summaries"))
        if isinstance(item, dict)
    ]
    if not window_summaries:
        lines.append("- Worst-window sample/instrument gain evidence: unavailable")
        return
    lines.extend([
        "",
        "| Window | Active Voices | Scalar | Sample Vol | Raw Sample Vol | Channel Vol | Global Vol | Final Gain Histogram | Dominant Instruments/Samples |",
        "| ---: | ---: | ---: | --- | --- | --- | --- | --- | --- |",
    ])
    for item in window_summaries:
        dominant = "; ".join(
            sample_instrument_group_label(group)
            for group in nested_list(item.get("dominant"))
            if isinstance(group, dict)
        ) or "none"
        lines.append(
            f"| {format_optional(item.get('rank'))} | "
            f"{format_optional(item.get('active_voice_count'))} | "
            f"{format_optional_float(item.get('candidate_scalar_to_reference'))} | "
            f"{format_distribution_range(nested_dict(item.get('sample_volume')))} | "
            f"{format_distribution_range(nested_dict(item.get('sample_volume_raw_estimate')))} | "
            f"{format_distribution_range(nested_dict(item.get('channel_volume')))} | "
            f"{format_distribution_range(nested_dict(item.get('global_volume')))} | "
            f"{format_final_gain_histogram(nested_dict(item.get('final_gain_histogram')))} | "
            f"{dominant} |"
        )


def append_alignment_summary(lines: list[str], summary: dict[str, Any]) -> None:
    lines.extend(["", "## Local Alignment Evidence"])
    if not bool(summary.get("enabled")):
        lines.append("- Worst-window local alignment search: unavailable in comparison JSON.")
        return
    lines.extend([
        "- Worst-window local alignment search: available",
        f"- Windows with nonzero best shift: {format_optional(summary.get('nonzero_best_shift_count'))}/"
        f"{format_optional(summary.get('window_count'))}",
        f"- Windows with improved correlation: {format_optional(summary.get('improved_correlation_count'))}/"
        f"{format_optional(summary.get('window_count'))}",
        f"- Windows with lower RMS difference after shift: {format_optional(summary.get('improved_rms_count'))}/"
        f"{format_optional(summary.get('window_count'))}",
        "",
        "| Window | Search Radius | Zero Corr | Best Shift | Best Corr | Corr Improvement | Zero RMS | Best RMS |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])
    for item in nested_list(summary.get("window_summaries")):
        if not isinstance(item, dict):
            continue
        lines.append(
            f"| {format_optional(item.get('rank'))} | "
            f"{format_optional(item.get('search_radius_frames'))} | "
            f"{format_optional_float(item.get('zero_shift_correlation'))} | "
            f"{format_optional(item.get('best_shift_frames'))} | "
            f"{format_optional_float(item.get('best_shift_correlation'))} | "
            f"{format_optional_float(item.get('correlation_improvement'))} | "
            f"{format_optional_float(item.get('zero_shift_rms_difference'))} | "
            f"{format_optional_float(item.get('best_shift_rms_difference'))} |"
        )


def append_envelope_gain_summary(lines: list[str], summary: dict[str, Any]) -> None:
    total_events = integer(summary.get("event_count")) or 0
    lines.extend([
        "",
        "## Envelope / Gain Timing Evidence",
        "- Envelope-enabled events: "
        f"{format_optional(summary.get('envelope_enabled_event_count'))}/{total_events}",
        "- Sustain/loop/fadeout event evidence: "
        f"sustain {format_optional(summary.get('sustain_event_count'))}, "
        f"loop {format_optional(summary.get('envelope_loop_event_count'))}, "
        f"fadeout {format_optional(summary.get('fadeout_event_count'))}, "
        f"key-off {format_optional(summary.get('key_off_event_count'))}",
        "- Gain/pan/global-volume updates: "
        f"gain {format_optional(summary.get('gain_update_count'))}, "
        f"pan {format_optional(summary.get('pan_update_count'))}, "
        f"channel-volume {format_optional(summary.get('channel_volume_update_count'))}, "
        f"global-volume {format_optional(summary.get('global_volume_update_count'))}",
    ])
    window_summaries = [
        item for item in nested_list(summary.get("window_summaries"))
        if isinstance(item, dict)
    ]
    if not window_summaries:
        lines.append("- Worst-window envelope/gain timing evidence: unavailable")
        return
    lines.extend([
        "",
        "| Window | Events | Env Enabled | Audible Env | Sustain | Env Loop | Fadeout | Key-Off | Gain Updates | Pan Updates | Global Vol | Examples |",
        "| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ])
    for item in window_summaries:
        examples = "; ".join(str(example) for example in nested_list(item.get("examples"))) or "none"
        lines.append(
            f"| {format_optional(item.get('rank'))} | "
            f"{format_optional(item.get('event_count'))} | "
            f"{format_optional(item.get('envelope_enabled_event_count'))} | "
            f"{format_optional(item.get('audible_envelope_event_count'))} | "
            f"{format_optional(item.get('sustain_event_count'))} | "
            f"{format_optional(item.get('envelope_loop_event_count'))} | "
            f"{format_optional(item.get('fadeout_event_count'))} | "
            f"{format_optional(item.get('key_off_event_count'))} | "
            f"{format_optional(item.get('gain_update_count'))} | "
            f"{format_optional(item.get('pan_update_count'))} | "
            f"{format_optional(item.get('global_volume_update_count'))} | "
            f"{examples} |"
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


def format_distribution_range(distribution: dict[str, Any]) -> str:
    if not distribution or integer(distribution.get("count")) == 0:
        return "unavailable...unavailable"
    return (
        f"{format_optional_float(distribution.get('min'))}..."
        f"{format_optional_float(distribution.get('max'))}"
    )


def format_final_gain_histogram(histogram: dict[str, Any]) -> str:
    if not histogram:
        return "unavailable"
    keys = ("zero", "0_0.125", "0.125_0.25", "0.25_0.5", "0.5_0.75", "0.75_1.0", "gt_1.0", "missing")
    return ", ".join(f"{key}={int_or_zero(histogram.get(key))}" for key in keys)


def format_phase_histogram(histogram: dict[str, Any]) -> str:
    if not histogram:
        return "unavailable"
    keys = ("0_0.25", "0.25_0.5", "0.5_0.75", "0.75_1.0", "missing")
    return ", ".join(f"{key}={int_or_zero(histogram.get(key))}" for key in keys)


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
