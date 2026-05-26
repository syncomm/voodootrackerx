#!/usr/bin/env python3
"""Summarize local XM effect coverage from offline diagnostics or runtime traces."""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


FLOAT_DIGITS = 9
MAX_FIRST_COORDINATES = 5
EFFECT_MEMORY_STATUS_MARKERS = {
    "effect_memory",
    "ignored_900_no_op",
    "ignored_e90_no_effect_memory",
    "zero_param_effect_memory_deferred",
    "zero_amount_effect_memory_deferred",
}
NO_OP_STATUS_MARKERS = EFFECT_MEMORY_STATUS_MARKERS | {
    "no_note_deferred",
    "out_of_row_no_op",
}

PITCH_RECOMMENDATIONS = {
    "0xy arpeggio": "Minimal 0xy Arpeggio Foundation",
    "E1x fine portamento up": "Minimal E1x Fine Portamento Up",
    "5xy tone portamento + volume slide": "Minimal 5xy Tone Portamento + Volume Slide",
    "6xy vibrato + volume slide": "Minimal 6xy Vibrato + Volume Slide",
    "4xy vibrato": "Minimal Vibrato Foundation",
    "7xy tremolo": "Minimal 7xy Tremolo",
    "volume-column vibrato speed": "Volume-Column Vibrato / Vibrato Speed Split",
    "volume-column vibrato": "Volume-Column Vibrato / Vibrato Speed Split",
    "volume-column tone portamento": "Volume-Column Tone Portamento",
    "E2x fine portamento down": "Minimal E2x Fine Portamento Down",
    "E5x set finetune": "Minimal E5x Set Finetune",
    "EAx fine volume slide up": "Minimal EAx/EBx Fine Volume Slide",
    "EBx fine volume slide down": "Minimal EAx/EBx Fine Volume Slide",
}

PORTAMENTO_MEMORY_COMMANDS = {
    "1xx portamento up",
    "2xx portamento down",
}

PORTAMENTO_MEMORY_RECOMMENDATION = "1xx/2xx Portamento Effect Memory Expansion"

LIMITED_USEFULNESS_COMMANDS = {
    "E0x filter toggle",
}

NON_IMPLEMENTATION_PRIORITIES = {
    "covered/low",
    "deferred/limited",
    "observed no-op/low",
}

EFFECT_FAMILY_ORDER = (
    "arpeggio",
    "portamento_up_down_tone",
    "vibrato",
    "tremolo",
    "tone_portamento_volume_slide",
    "vibrato_volume_slide",
    "panning_slide",
    "global_volume_global_slide",
    "note_cut_delay_retrigger",
    "pattern_break_jump_delay",
    "sample_offset",
    "volume_column_effects",
    "panning_envelope",
    "unknown_or_unsupported",
)


class EffectCoverageError(Exception):
    """A user-facing effect coverage input or validation error."""


@dataclass(frozen=True)
class SourceCoordinate:
    order: Any = None
    pattern: Any = None
    row: Any = None
    channel: Any = None
    tick: Any = None

    def key(self) -> tuple[Any, Any, Any, Any, Any]:
        return (self.order, self.pattern, self.row, self.channel, self.tick)

    def label(self) -> str:
        parts = []
        if self.order is not None:
            parts.append(f"order {self.order}")
        if self.pattern is not None:
            parts.append(f"pattern {self.pattern}")
        if self.row is not None:
            parts.append(f"row {self.row}")
        if self.channel is not None:
            parts.append(f"ch {self.channel}")
        if self.tick is not None:
            parts.append(f"tick {self.tick}")
        return " ".join(parts) if parts else "unknown"

    def to_json(self) -> dict[str, Any]:
        return {
            "order": self.order,
            "pattern": self.pattern,
            "row": self.row,
            "channel": self.channel,
            "tick": self.tick,
            "label": self.label(),
        }


@dataclass(frozen=True)
class CoverageOccurrence:
    command: str
    command_source: str
    category: str
    status: str
    reason: str
    source: SourceCoordinate
    effect_type: Any = None
    effect_param: Any = None
    raw_volume_column: Any = None
    input_name: str = ""

    def grouping_key(self) -> tuple[str, str, str]:
        return (self.command, self.command_source, self.category)


def rounded(value: float) -> float:
    return round(float(value), FLOAT_DIGITS)


def byte_hex(value: Any) -> str | None:
    parsed = parse_byte(value)
    return f"{parsed:02X}" if parsed is not None else None


def number(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return float(value)
    if isinstance(value, str):
        try:
            parsed = float(value)
        except ValueError:
            return None
        if math.isfinite(parsed):
            return parsed
    return None


def integer(value: Any) -> int | None:
    value_number = number(value)
    if value_number is None:
        return None
    return int(value_number)


def parse_byte(value: Any) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value & 0xFF
    if isinstance(value, float) and math.isfinite(value):
        return int(value) & 0xFF
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            if text.lower().startswith("0x"):
                return int(text, 16) & 0xFF
            if len(text) <= 2 or any(ch in "abcdefABCDEF" for ch in text):
                return int(text, 16) & 0xFF
            return int(text, 10) & 0xFF
        except ValueError:
            return None
    return None


def nested_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def nested_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise EffectCoverageError(
            f"malformed JSON input: {path}: line {error.lineno} column {error.colno}: {error.msg}"
        ) from error


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise EffectCoverageError(
                f"malformed JSONL input: {path}: line {line_number}: {error.msg}"
            ) from error
        if not isinstance(value, dict):
            raise EffectCoverageError(f"malformed JSONL input: {path}: line {line_number}: expected object")
        events.append(value)
    return events


def load_input(path: Path) -> tuple[str, Any]:
    if not path.exists():
        raise EffectCoverageError(f"missing input: {path}")
    if not path.is_file():
        raise EffectCoverageError(f"input is not a file: {path}")
    if path.suffix.lower() == ".jsonl":
        return ("runtime_trace", load_jsonl(path))
    payload = load_json(path)
    if isinstance(payload, list):
        return ("runtime_trace", payload)
    if isinstance(payload, dict):
        return ("offline_diagnostics", payload)
    raise EffectCoverageError(f"input must be a JSON object or JSONL trace: {path}")


def input_label(input_name: str) -> str:
    name = Path(input_name).name
    for suffix in (".effect-coverage.json", ".diagnostics.json", ".jsonl", ".json"):
        if name.endswith(suffix):
            return name[:-len(suffix)]
    return name


def source_coordinate(
    source: dict[str, Any] | None = None,
    *,
    channel: Any = None,
    tick: Any = None,
    fallback: dict[str, Any] | None = None,
) -> SourceCoordinate:
    source = nested_dict(source)
    fallback = nested_dict(fallback)
    return SourceCoordinate(
        order=first_present(
            source.get("order"),
            source.get("order_index"),
            fallback.get("orderIndex"),
            fallback.get("order_index"),
            fallback.get("plannedSourceOrderIndex"),
        ),
        pattern=first_present(
            source.get("pattern"),
            source.get("pattern_index"),
            fallback.get("patternIndex"),
            fallback.get("pattern_index"),
            fallback.get("plannedSourcePatternIndex"),
        ),
        row=first_present(
            source.get("row"),
            source.get("row_index"),
            fallback.get("rowIndex"),
            fallback.get("row_index"),
            fallback.get("plannedSourceRowIndex"),
        ),
        channel=first_present(
            channel,
            source.get("channel"),
            source.get("channel_index"),
            fallback.get("channelIndex"),
            fallback.get("channel_index"),
            fallback.get("plannedSourceChannelIndex"),
        ),
        tick=first_present(
            tick,
            source.get("tick"),
            source.get("tick_in_row"),
            fallback.get("tickInRow"),
            fallback.get("tick_in_row"),
            fallback.get("plannedSourceTickInRow"),
        ),
    )


def first_present(*values: Any) -> Any:
    for value in values:
        if value is not None:
            return value
    return None


def effect_command_label(effect_type_value: Any, effect_param_value: Any) -> str:
    effect_type = parse_byte(effect_type_value)
    effect_param = parse_byte(effect_param_value) or 0
    if effect_type is None:
        return "unknown/unsupported"
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
    if effect_type == 0x08:
        return "8xx set panning"
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
        return extended_effect_command_label(effect_param)
    if effect_type == 0x0F:
        return "Fxx speed/BPM"
    if effect_type == 0x10:
        return "Gxx set global volume"
    if effect_type == 0x11:
        return "Hxy global volume slide"
    if effect_type == 0x19:
        return "Pxy panning slide"
    if effect_type == 0x21:
        return "Xxy extra fine portamento"
    return f"{effect_type:02X}xx unknown/unsupported"


def extended_effect_command_label(effect_param: int) -> str:
    subcommand = (effect_param >> 4) & 0x0F
    if subcommand == 0x00:
        return "E0x filter toggle"
    if subcommand == 0x01:
        return "E1x fine portamento up"
    if subcommand == 0x02:
        return "E2x fine portamento down"
    if subcommand == 0x03:
        return "E3x glissando control"
    if subcommand == 0x04:
        return "E4x vibrato control"
    if subcommand == 0x05:
        return "E5x set finetune"
    if subcommand == 0x06:
        return "E6x pattern loop"
    if subcommand == 0x07:
        return "E7x tremolo control"
    if subcommand == 0x08:
        return "E8x set panning"
    if subcommand == 0x09:
        return "E9x retrigger"
    if subcommand == 0x0A:
        return "EAx fine volume slide up"
    if subcommand == 0x0B:
        return "EBx fine volume slide down"
    if subcommand == 0x0C:
        return "ECx note cut"
    if subcommand == 0x0D:
        return "EDx note delay"
    if subcommand == 0x0E:
        return "EEx pattern delay"
    if subcommand == 0x0F:
        return "EFx invert loop"
    return "unknown/unsupported"


def volume_command_label(volume_column: dict[str, Any], raw_value: Any = None) -> str:
    command = nested_dict(volume_column.get("command"))
    name = str(command.get("name") or volume_column.get("command_name") or "")
    if name == "setVolume":
        return "volume-column set volume"
    if name == "volumeSlideDown":
        return "volume-column volume slide down"
    if name == "volumeSlideUp":
        return "volume-column volume slide up"
    if name == "fineVolumeSlideDown":
        return "volume-column fine volume slide down"
    if name == "fineVolumeSlideUp":
        return "volume-column fine volume slide up"
    if name == "setVibratoSpeed":
        return "volume-column vibrato speed"
    if name == "vibrato":
        return "volume-column vibrato"
    if name == "setPanning":
        return "volume-column set panning"
    if name == "panningSlideLeft":
        return "volume-column panning slide left"
    if name == "panningSlideRight":
        return "volume-column panning slide right"
    if name == "tonePortamento":
        return "volume-column tone portamento"
    if name == "none":
        return "volume-column none"
    parsed = parse_byte(raw_value if raw_value is not None else volume_column.get("raw_value"))
    if parsed is not None:
        return f"volume-column {parsed:02X} unknown/unsupported"
    return "volume-column unknown/unsupported"


def volume_status(volume_column: dict[str, Any]) -> str:
    classification = str(volume_column.get("classification", "")).lower()
    if bool(volume_column.get("applied")) or classification == "supported":
        return "applied"
    if bool(volume_column.get("deferred")) or classification == "deferred":
        return "deferred/unsupported"
    if bool(volume_column.get("ignored_as_empty_or_no_op")) or classification == "ignored_no_op":
        return "ignored/no-op"
    return "unknown"


def diagnostic_status(item: dict[str, Any], default: str = "unknown") -> str:
    raw_status = str(item.get("current_status") or item.get("status") or default)
    if bool(item.get("applied")) or raw_status == "applied":
        return "applied"
    if raw_status in {"ignored/no-op", "ignored_no_op", "out_of_row_no_op"} or bool(item.get("ignored_as_no_op")):
        return "ignored/no-op"
    if raw_status in {
        "ignored_900_no_op",
        "ignored_e90_no_effect_memory",
        "zero_param_effect_memory_deferred",
        "zero_amount_effect_memory_deferred",
    }:
        return "deferred/no-op"
    if raw_status == "no_active_voice":
        return "ignored/no-op"
    if raw_status == "no_note_deferred":
        return "deferred/no-op"
    if raw_status.startswith("deferred") or bool(item.get("deferred")):
        return raw_status.replace("_", "/") if raw_status == "deferred_unsupported" else raw_status
    return raw_status or default


def diagnostic_reason(item: dict[str, Any], status: str) -> str:
    if bool(item.get("effect_memory_reused")) and status == "applied":
        return "effect_memory_reused"
    if bool(item.get("effect_memory_missing")):
        return str(item.get("memory_unavailable_reason") or "effect_memory_missing")
    return str(item.get("status") or status)


def runtime_status(event: dict[str, Any]) -> str:
    decision = str(event.get("decision") or "")
    if decision in {"triggered", "delayed", "cut", "retriggered", "updated"}:
        return "applied"
    if decision == "ignored":
        return "ignored/no-op"
    action = str(event.get("runtimeAction") or "")
    disposition = str(event.get("updateDisposition") or "")
    if action.endswith("_applied") or action in {"c_mixer_add_voice", "c_mixer_stop_channel", "c_mixer_stop_channel_ramped"}:
        return "applied"
    if "suppressed" in action or "no_change" in disposition:
        return "ignored/no-op"
    if "deferred_no_active_voice" in action or disposition == "no_active_voice":
        return "ignored/no-op"
    if "deferred" in action or "unsupported" in action or disposition in {"missing_data", "unsupported", "stale_after_stop"}:
        return "deferred/unsupported"
    if decision == "observed":
        return "observed"
    return "unknown"


def effect_status_key(
    item: dict[str, Any],
    *,
    effect_type: Any = None,
    effect_param: Any = None,
    channel: Any = None,
) -> tuple[Any, Any, Any, Any, Any, int | None, int | None]:
    source = source_coordinate(
        nested_dict(item.get("source")),
        channel=first_present(channel, item.get("channel_index")),
        tick=item.get("synthetic_tick"),
        fallback=item,
    )
    return (*source.key()[:4], parse_byte(effect_type if effect_type is not None else item.get("effect_type")),
            parse_byte(effect_param if effect_param is not None else item.get("effect_param")))


def offline_occurrences(payload: dict[str, Any], input_name: str) -> list[CoverageOccurrence]:
    occurrences: list[CoverageOccurrence] = []
    specialized: dict[tuple[Any, ...], tuple[str, str]] = {}
    specialized_used: set[tuple[Any, ...]] = set()

    for field_name in (
        "sample_offset_effects",
        "set_finetune_effects",
        "note_cut_effects",
        "note_delay_effects",
        "retrigger_effects",
        "arpeggio_effects",
        "tone_portamento_effects",
        "portamento_slide_effects",
        "fine_portamento_up_effects",
        "fine_portamento_down_effects",
        "vibrato_control_effects",
        "vibrato_effects",
    ):
        for item in nested_list(payload.get(field_name)):
            if not isinstance(item, dict):
                continue
            key = effect_status_key(item)
            status = diagnostic_status(item)
            reason = diagnostic_reason(item, status)
            specialized[key] = (status, reason)

    for item in nested_list(payload.get("pattern_traversal_timing_effects")):
        if not isinstance(item, dict):
            continue
        effect_type = parse_byte(item.get("effect_type"))
        effect_param = parse_byte(item.get("effect_param")) or 0
        label = str(item.get("effect_label") or item.get("decoded_label") or effect_command_label(effect_type, effect_param))
        if label == "none":
            continue
        key = effect_status_key(item, effect_type=effect_type, effect_param=effect_param)
        status, reason = specialized.get(key, (diagnostic_status(item), str(item.get("status") or "")))
        if key in specialized:
            specialized_used.add(key)
        occurrences.append(CoverageOccurrence(
            command=label,
            command_source="effect_column",
            category="offline_bounded_render",
            status=status,
            reason=reason or status,
            source=source_coordinate(nested_dict(item.get("source")), channel=item.get("channel_index"), fallback=item),
            effect_type=effect_type,
            effect_param=effect_param,
            input_name=input_name,
        ))

    for field_name in (
        "sample_offset_effects",
        "set_finetune_effects",
        "note_cut_effects",
        "note_delay_effects",
        "retrigger_effects",
        "arpeggio_effects",
        "tone_portamento_effects",
        "portamento_slide_effects",
        "fine_portamento_up_effects",
        "fine_portamento_down_effects",
        "vibrato_control_effects",
        "vibrato_effects",
    ):
        for item in nested_list(payload.get(field_name)):
            if not isinstance(item, dict):
                continue
            effect_type = parse_byte(item.get("effect_type"))
            effect_param = parse_byte(item.get("effect_param")) or 0
            key = effect_status_key(item, effect_type=effect_type, effect_param=effect_param)
            if key in specialized_used:
                continue
            label = effect_command_label(effect_type, effect_param)
            if label == "none":
                continue
            occurrences.append(CoverageOccurrence(
                command=label,
                command_source="effect_column",
                category="offline_bounded_render",
                status=diagnostic_status(item),
                reason=diagnostic_reason(item, diagnostic_status(item)),
                source=source_coordinate(nested_dict(item.get("source")), channel=item.get("channel_index"), tick=item.get("synthetic_tick"), fallback=item),
                effect_type=effect_type,
                effect_param=effect_param,
                input_name=input_name,
            ))

    for mapping in nested_list(payload.get("volume_column_mappings")):
        if not isinstance(mapping, dict):
            continue
        volume_column = nested_dict(mapping.get("volume_column"))
        raw = parse_byte(volume_column.get("raw_value"))
        label = volume_command_label(volume_column, raw)
        if label == "volume-column none":
            continue
        occurrences.append(CoverageOccurrence(
            command=label,
            command_source="volume_column",
            category="offline_bounded_render",
            status=volume_status(volume_column),
            reason=str(volume_column.get("classification") or volume_status(volume_column)),
            source=source_coordinate(nested_dict(mapping.get("source")), channel=mapping.get("channel_index"), tick=mapping.get("synthetic_tick"), fallback=mapping),
            raw_volume_column=raw,
            input_name=input_name,
        ))

    volume_mapping_keys = {
        source_coordinate(
            nested_dict(mapping.get("source")),
            channel=mapping.get("channel_index"),
            fallback=mapping,
        ).key()
        for mapping in nested_list(payload.get("volume_column_mappings"))
        if isinstance(mapping, dict)
    }
    for field in nested_list(payload.get("deferred_fields")):
        if not isinstance(field, dict):
            continue
        if field.get("field") == "volume_column":
            coord = source_coordinate(nested_dict(field.get("source")), channel=field.get("channel_index"), fallback=field)
            if coord.key() in volume_mapping_keys:
                continue
            volume_column = nested_dict(field.get("volume_column"))
            occurrences.append(CoverageOccurrence(
                command=volume_command_label(volume_column, field.get("volume_column_raw")),
                command_source="volume_column",
                category="offline_bounded_render",
                status=volume_status(volume_column),
                reason=str(volume_column.get("classification") or "deferred"),
                source=coord,
                raw_volume_column=parse_byte(field.get("volume_column_raw")),
                input_name=input_name,
            ))

    for key_off in nested_list(payload.get("key_off_events")):
        if not isinstance(key_off, dict):
            continue
        occurrences.append(CoverageOccurrence(
            command="note off / key off",
            command_source="note",
            category="offline_bounded_render",
            status="applied" if bool(key_off.get("applied")) else "ignored/no-op",
            reason=str(key_off.get("reason") or "key_off"),
            source=source_coordinate(nested_dict(key_off.get("source")), channel=key_off.get("channel_index"), tick=key_off.get("synthetic_tick"), fallback=key_off),
            input_name=input_name,
        ))

    return occurrences


def runtime_occurrences(events: list[Any], input_name: str) -> list[CoverageOccurrence]:
    occurrences: list[CoverageOccurrence] = []
    for raw_event in events:
        if not isinstance(raw_event, dict):
            continue
        effect_type = parse_byte(first_present(raw_event.get("effectType"), raw_event.get("effect_type"), raw_event.get("effectCommand")))
        effect_param = parse_byte(first_present(raw_event.get("effectParam"), raw_event.get("effect_param"), raw_event.get("effectParameter")))
        if effect_type is not None and (effect_type != 0 or (effect_param or 0) != 0):
            occurrences.append(CoverageOccurrence(
                command=effect_command_label(effect_type, effect_param),
                command_source="effect_column",
                category="runtime_c_mixer_trace",
                status=runtime_status(raw_event),
                reason=str(raw_event.get("decisionReason") or raw_event.get("runtimeAction") or raw_event.get("updateDisposition") or runtime_status(raw_event)),
                source=source_coordinate(None, fallback=raw_event),
                effect_type=effect_type,
                effect_param=effect_param or 0,
                input_name=input_name,
            ))
        raw_volume = first_present(raw_event.get("volumeColumn"), raw_event.get("rawVolumeColumn"), raw_event.get("raw_volume_column"))
        volume_value = parse_byte(raw_volume)
        decoded = raw_event.get("decodedVolumeColumnCommand")
        if volume_value is not None and volume_value != 0:
            volume_column = {
                "raw_value": volume_value,
                "command": {"name": decoded or "unsupported"},
                "applied": raw_event.get("volumeColumnApplied"),
                "classification": "supported" if raw_event.get("volumeColumnApplied") is True else "",
            }
            occurrences.append(CoverageOccurrence(
                command=volume_command_label(volume_column, volume_value),
                command_source="volume_column",
                category="runtime_c_mixer_trace",
                status="applied" if raw_event.get("volumeColumnApplied") is True else "deferred/unsupported",
                reason=str(decoded or raw_event.get("runtimeAction") or "volume_column"),
                source=source_coordinate(None, fallback=raw_event),
                raw_volume_column=volume_value,
                input_name=input_name,
            ))
    return occurrences


def status_flags(occurrence: CoverageOccurrence) -> dict[str, bool]:
    status = occurrence.status.lower()
    reason = occurrence.reason.lower()
    effect_memory_reused = "effect_memory_reused" in reason
    effect_memory_missing = (
        "effect_memory_missing" in reason
        or ("missing_" in reason and "memory" in reason)
    )
    no_op = (
        "ignored" in status
        or "no-op" in status
        or "no_op" in status
        or "no_active_voice" in status
        or "no_active_voice" in reason
        or any(marker in status or marker in reason for marker in NO_OP_STATUS_MARKERS)
    ) and not effect_memory_reused
    unsupported = "unsupported" in status or "unknown/unsupported" in occurrence.command or "unknown" == status
    deferred = "deferred" in status or unsupported
    return {
        "applied": status == "applied",
        "deferred": deferred,
        "unsupported": unsupported,
        "no_op_effect_memory_deferred": no_op,
        "effect_memory_reused": effect_memory_reused,
        "effect_memory_missing": effect_memory_missing,
        "unknown": status == "unknown" or occurrence.command.endswith("unknown/unsupported"),
    }


def effect_family(command: str, command_source: str) -> str:
    if command_source == "volume_column":
        return "volume_column_effects"
    if "arpeggio" in command:
        return "arpeggio"
    if command.startswith(("1xx", "2xx", "3xx")) or "fine portamento" in command or "extra fine portamento" in command:
        return "portamento_up_down_tone"
    if command.startswith("5xy"):
        return "tone_portamento_volume_slide"
    if command.startswith("4xy") or "vibrato control" in command:
        return "vibrato"
    if command.startswith("6xy"):
        return "vibrato_volume_slide"
    if command.startswith("7xy") or "tremolo" in command:
        return "tremolo"
    if "panning slide" in command or command.startswith("Pxy"):
        return "panning_slide"
    if command.startswith(("Gxx", "Hxy")):
        return "global_volume_global_slide"
    if command.startswith(("E9x", "ECx", "EDx")):
        return "note_cut_delay_retrigger"
    if command.startswith(("Bxx", "Dxx", "EEx")) or "pattern loop" in command:
        return "pattern_break_jump_delay"
    if "sample offset" in command:
        return "sample_offset"
    if "panning envelope" in command:
        return "panning_envelope"
    if "unknown/unsupported" in command:
        return "unknown_or_unsupported"
    return "other"


def has_effect_memory_gap(command: str, reason_counts: Counter | dict[str, Any] | None) -> bool:
    filtered_reasons = {
        reason: count for reason, count in dict(reason_counts or {}).items()
        if "effect_memory_reused" not in str(reason).lower()
    }
    reason_text = json.dumps(filtered_reasons, sort_keys=True).lower()
    command_text = command.lower()
    return "effect memory" in command_text or "effect_memory" in reason_text or "ignored_900" in reason_text


def explicit_effect_memory_count(row: dict[str, Any]) -> int:
    reason_counts = nested_dict(row.get("reason_counts"))
    total = 0
    for reason, count in reason_counts.items():
        reason_text = str(reason).lower()
        if "effect_memory_reused" in reason_text:
            continue
        if "effect_memory" in reason_text or "ignored_900" in reason_text or "ignored_e90" in reason_text:
            total += int(count or 0)
    return total


def effect_memory_priority_for_command(command: str) -> str:
    if command in PORTAMENTO_MEMORY_COMMANDS:
        return PORTAMENTO_MEMORY_RECOMMENDATION
    return "Effect Memory Foundation"


def priority_for_command(command: str, counters: Counter, reason_counts: Counter | dict[str, Any] | None = None) -> str:
    unresolved = counters["unsupported_count"] + counters["no_op_effect_memory_deferred_count"]
    if unresolved <= 0:
        return "covered/low"
    if command in LIMITED_USEFULNESS_COMMANDS:
        return "deferred/limited"
    if command in PITCH_RECOMMENDATIONS:
        return PITCH_RECOMMENDATIONS[command]
    if command.startswith("Pxy"):
        return "Minimal Pxy Panning Slide"
    if command.startswith("Gxx"):
        return "Minimal Gxx Global Volume"
    if command.startswith(("Bxx", "Dxx", "EEx")):
        return "Pattern Delay / Break / Jump Runtime Parity Follow-Up"
    if command == "note off / key off":
        return "Key-Off / Fadeout Edge Case Follow-Up"
    if has_effect_memory_gap(command, reason_counts):
        return effect_memory_priority_for_command(command)
    if counters["unsupported_count"] == 0 and counters["no_op_effect_memory_deferred_count"] > 0:
        return "observed no-op/low"
    if command.endswith("unknown/unsupported"):
        return "Classify Unknown XM Effect Command"
    return f"{command} Follow-Up"


def summarize_occurrences(occurrences: list[CoverageOccurrence], input_names: list[str]) -> dict[str, Any]:
    grouped: dict[tuple[str, str, str], list[CoverageOccurrence]] = defaultdict(list)
    for occurrence in occurrences:
        grouped[occurrence.grouping_key()].append(occurrence)

    rows = []
    totals = Counter()
    family_counts: dict[str, Counter] = defaultdict(Counter)
    reason_counts = Counter()
    no_active = Counter()
    unsupported_deferred = Counter()
    key_off = Counter()
    first_no_active: dict[str, SourceCoordinate] = {}
    first_unsupported: dict[str, SourceCoordinate] = {}
    first_key_off: dict[str, SourceCoordinate] = {}

    for occurrence in occurrences:
        flags = status_flags(occurrence)
        totals["detected_count"] += 1
        family = effect_family(occurrence.command, occurrence.command_source)
        family_counts[family]["detected_count"] += 1
        reason_counts[occurrence.reason or occurrence.status] += 1
        for flag, enabled in flags.items():
            if enabled and flag.endswith("_count"):
                totals[flag] += 1
            elif enabled:
                totals[f"{flag}_count"] += 1
                family_counts[family][f"{flag}_count"] += 1
        if "no_active_voice" in occurrence.reason or "no_active_voice" in occurrence.status:
            no_active[occurrence.command] += 1
            first_no_active.setdefault(occurrence.command, occurrence.source)
        if flags["unsupported"]:
            unsupported_deferred[occurrence.command] += 1
            first_unsupported.setdefault(occurrence.command, occurrence.source)
        if occurrence.command == "note off / key off":
            key_off[occurrence.reason] += 1
            first_key_off.setdefault(occurrence.reason, occurrence.source)

    for key, values in grouped.items():
        command, command_source, category = key
        counters = Counter()
        status_counter = Counter()
        reason_counter = Counter()
        first_coordinates = []
        first_effect_type = None
        first_effect_param = None
        first_volume_column = None
        first_input_label = None
        input_labels = []
        seen_inputs = set()
        seen_coordinates = set()
        for occurrence in values:
            counters["detected_count"] += 1
            status_counter[occurrence.status] += 1
            reason_counter[occurrence.reason] += 1
            occurrence_input_label = input_label(occurrence.input_name)
            if first_input_label is None:
                first_input_label = occurrence_input_label
            if occurrence_input_label not in seen_inputs:
                input_labels.append(occurrence_input_label)
                seen_inputs.add(occurrence_input_label)
            if first_effect_type is None and occurrence.effect_type is not None:
                first_effect_type = occurrence.effect_type
            if first_effect_param is None and occurrence.effect_param is not None:
                first_effect_param = occurrence.effect_param
            if first_volume_column is None and occurrence.raw_volume_column is not None:
                first_volume_column = occurrence.raw_volume_column
            flags = status_flags(occurrence)
            for name, enabled in flags.items():
                if enabled:
                    counters[f"{name}_count"] += 1
            coord_key = occurrence.source.key()
            if coord_key not in seen_coordinates and len(first_coordinates) < MAX_FIRST_COORDINATES:
                first_coordinates.append(occurrence.source)
                seen_coordinates.add(coord_key)
        rows.append({
            "command": command,
            "command_source": command_source,
            "runtime_offline_category": category,
            "detected_count": counters["detected_count"],
            "applied_count": counters["applied_count"],
            "deferred_count": counters["deferred_count"],
            "unsupported_count": counters["unsupported_count"],
            "no_op_effect_memory_deferred_count": counters["no_op_effect_memory_deferred_count"],
            "effect_memory_reused_count": counters["effect_memory_reused_count"],
            "effect_memory_missing_count": counters["effect_memory_missing_count"],
            "unknown_count": counters["unknown_count"],
            "first_effect_type": first_effect_type,
            "first_effect_param": first_effect_param,
            "first_effect_type_hex": byte_hex(first_effect_type),
            "first_effect_param_hex": byte_hex(first_effect_param),
            "first_volume_column": first_volume_column,
            "first_volume_column_hex": byte_hex(first_volume_column),
            "first_input_label": first_input_label or "none",
            "input_labels": input_labels,
            "input_count": len(input_labels),
            "first_coordinates": [coord.to_json() for coord in first_coordinates],
            "first_coordinate": first_coordinates[0].label() if first_coordinates else "none",
            "status_counts": dict(sorted(status_counter.items())),
            "reason_counts": dict(sorted(reason_counter.items())),
            "recommended_implementation_priority": priority_for_command(command, counters, reason_counter),
        })

    rows.sort(key=lambda row: (
        -int(row["unsupported_count"]),
        -int(row["deferred_count"]),
        -int(row["no_op_effect_memory_deferred_count"]),
        -int(row["detected_count"]),
        str(row["command"]),
        str(row["command_source"]),
    ))

    family_rows = []
    for family in EFFECT_FAMILY_ORDER + tuple(sorted(set(family_counts) - set(EFFECT_FAMILY_ORDER))):
        counts = family_counts.get(family)
        if not counts:
            continue
        family_rows.append({
            "family": family,
            "detected_count": counts["detected_count"],
            "applied_count": counts["applied_count"],
            "deferred_count": counts["deferred_count"],
            "unsupported_count": counts["unsupported_count"],
            "no_op_effect_memory_deferred_count": counts["no_op_effect_memory_deferred_count"],
            "effect_memory_reused_count": counts["effect_memory_reused_count"],
            "effect_memory_missing_count": counts["effect_memory_missing_count"],
        })

    recommended_next_pr = recommend_next_pr(rows, unsupported_deferred, no_active, key_off)
    return {
        "schema_version": 1,
        "tool": "scripts/summarize-xm-effect-coverage.py",
        "local_only": True,
        "input_count": len(input_names),
        "inputs": [{"path_name": name} for name in input_names],
        "summary": {
            "detected_count": totals["detected_count"],
            "applied_count": totals["applied_count"],
            "deferred_count": totals["deferred_count"],
            "unsupported_count": totals["unsupported_count"],
            "no_op_effect_memory_deferred_count": totals["no_op_effect_memory_deferred_count"],
            "effect_memory_reused_count": totals["effect_memory_reused_count"],
            "effect_memory_missing_count": totals["effect_memory_missing_count"],
            "unknown_count": totals["unknown_count"],
            "recommended_next_pr": recommended_next_pr,
        },
        "effect_coverage": rows,
        "effect_family_counts": family_rows,
        "unresolved_breakdown": {
            "unsupported_deferred_effect_interaction": [
                {
                    "command": command,
                    "count": count,
                    "first_coordinate": first_unsupported[command].to_json(),
                }
                for command, count in unsupported_deferred.most_common()
            ],
            "note_off_key_off": [
                {
                    "reason": reason,
                    "count": count,
                    "first_coordinate": first_key_off[reason].to_json(),
                }
                for reason, count in key_off.most_common()
            ],
            "no_active_voice": [
                {
                    "command": command,
                    "count": count,
                    "first_coordinate": first_no_active[command].to_json(),
                }
                for command, count in no_active.most_common()
            ],
        },
        "reason_counts": dict(sorted(reason_counts.items(), key=lambda item: (-item[1], item[0]))),
    }


def recommend_next_pr(
    rows: list[dict[str, Any]],
    unsupported_deferred: Counter,
    no_active: Counter,
    key_off: Counter,
) -> str:
    unresolved_rows = [
        row for row in rows
        if int(row["unsupported_count"]) > 0
        or (
            int(row["no_op_effect_memory_deferred_count"]) > 0
            and has_effect_memory_gap(str(row.get("command") or ""), nested_dict(row.get("reason_counts")))
        )
    ]
    if not unresolved_rows:
        return "No clear missing-effect implementation target"

    effect_memory_rows = [
        row for row in unresolved_rows
        if int(row["no_op_effect_memory_deferred_count"]) > 0
        and int(row["unsupported_count"]) == 0
        and "no_active_voice" not in json.dumps(row.get("reason_counts", {}))
    ]
    unsupported_rows = [row for row in unresolved_rows if int(row["unsupported_count"]) > 0]
    effect_memory_marker_rows = [
        row for row in unresolved_rows
        if explicit_effect_memory_count(row) > 0
    ]
    effect_memory_marker_total = sum(explicit_effect_memory_count(row) for row in effect_memory_marker_rows)
    top_unsupported_count = max((int(row["unsupported_count"]) for row in unsupported_rows), default=0)
    if len(effect_memory_marker_rows) >= 2 and effect_memory_marker_total > top_unsupported_count:
        portamento_memory_total = sum(
            explicit_effect_memory_count(row)
            for row in effect_memory_marker_rows
            if str(row.get("command") or "") in PORTAMENTO_MEMORY_COMMANDS
        )
        if portamento_memory_total > top_unsupported_count and portamento_memory_total * 2 >= effect_memory_marker_total:
            return PORTAMENTO_MEMORY_RECOMMENDATION
        return "Effect Memory Foundation"

    useful_unsupported_rows = [
        row for row in unsupported_rows
        if str(row.get("recommended_implementation_priority")) not in NON_IMPLEMENTATION_PRIORITIES
    ]
    if unsupported_rows and not useful_unsupported_rows:
        unsupported_commands = {str(row.get("command") or "") for row in unsupported_rows}
        if unsupported_commands <= LIMITED_USEFULNESS_COMMANDS:
            return "Document E0x Filter Toggle Deferral"
    candidate_rows = useful_unsupported_rows or unsupported_rows or effect_memory_rows or unresolved_rows
    candidate_rows.sort(key=lambda row: (
        -int(row["unsupported_count"]),
        -int(row["no_op_effect_memory_deferred_count"]),
        -int(row["detected_count"]),
        str(row["command"]),
    ))
    priority = str(candidate_rows[0]["recommended_implementation_priority"])
    if priority not in NON_IMPLEMENTATION_PRIORITIES:
        return priority
    if key_off and not unsupported_deferred:
        return "Key-Off / Fadeout Edge Case Follow-Up"
    if no_active and not unsupported_deferred:
        return "No-Active Voice Classification Follow-Up"
    return f"{candidate_rows[0]['command']} Follow-Up"


def build_summary_from_payloads(payloads: list[tuple[str, str, Any]]) -> dict[str, Any]:
    occurrences: list[CoverageOccurrence] = []
    input_names: list[str] = []
    for kind, input_name, payload in payloads:
        input_names.append(input_name)
        if kind == "runtime_trace":
            occurrences.extend(runtime_occurrences(nested_list(payload), input_name))
        elif isinstance(payload, dict):
            occurrences.extend(offline_occurrences(payload, input_name))
    return summarize_occurrences(occurrences, input_names)


def build_summary(paths: list[Path]) -> dict[str, Any]:
    payloads: list[tuple[str, str, Any]] = []
    for path in paths:
        kind, payload = load_input(path)
        payloads.append((kind, path.name, payload))
    return build_summary_from_payloads(payloads)


def build_markdown_report(summary: dict[str, Any], *, top: int | None = None) -> str:
    totals = nested_dict(summary.get("summary"))
    lines = [
        "# XM Effect Coverage Summary",
        "",
        "Local diagnostics only; generated reports derived from private modules must stay out of git.",
        "",
        "## Totals",
        f"- Inputs: {summary.get('input_count', 0)}",
        f"- Detected commands: {totals.get('detected_count', 0)}",
        f"- Applied: {totals.get('applied_count', 0)}",
        f"- Deferred: {totals.get('deferred_count', 0)}",
        f"- Unsupported: {totals.get('unsupported_count', 0)}",
        f"- No-op/effect-memory deferred: {totals.get('no_op_effect_memory_deferred_count', 0)}",
        f"- Effect memory reused: {totals.get('effect_memory_reused_count', 0)}",
        f"- Effect memory missing: {totals.get('effect_memory_missing_count', 0)}",
        f"- Recommended next PR: {totals.get('recommended_next_pr', 'No clear missing-effect implementation target')}",
        "",
        "## Coverage Table",
        "| Command | Source | Runtime/offline | Detected | Applied | Deferred | Unsupported | No-op/effect-memory | Memory reused | Memory missing | First input | First coordinates | Recommended priority |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |",
    ]
    rows = nested_list(summary.get("effect_coverage"))
    if top is not None and top > 0:
        rows = rows[:top]
    if not rows:
        lines.append("| none | n/a | n/a | 0 | 0 | 0 | 0 | 0 | 0 | 0 | none | none | No clear missing-effect implementation target |")
    for row in rows:
        lines.append(
            f"| {row.get('command')} | {row.get('command_source')} | {row.get('runtime_offline_category')} | "
            f"{row.get('detected_count', 0)} | {row.get('applied_count', 0)} | {row.get('deferred_count', 0)} | "
            f"{row.get('unsupported_count', 0)} | {row.get('no_op_effect_memory_deferred_count', 0)} | "
            f"{row.get('effect_memory_reused_count', 0)} | {row.get('effect_memory_missing_count', 0)} | "
            f"{row.get('first_input_label', 'none')} | {row.get('first_coordinate', 'none')} | "
            f"{row.get('recommended_implementation_priority')} |"
        )

    lines.extend([
        "",
        "## Effect Family Counts",
        "| Family | Detected | Applied | Deferred | Unsupported | No-op/effect-memory | Memory reused | Memory missing |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])
    family_rows = nested_list(summary.get("effect_family_counts"))
    if not family_rows:
        lines.append("| none | 0 | 0 | 0 | 0 | 0 | 0 | 0 |")
    for row in family_rows:
        lines.append(
            f"| {row.get('family')} | {row.get('detected_count', 0)} | {row.get('applied_count', 0)} | "
            f"{row.get('deferred_count', 0)} | {row.get('unsupported_count', 0)} | "
            f"{row.get('no_op_effect_memory_deferred_count', 0)} | "
            f"{row.get('effect_memory_reused_count', 0)} | {row.get('effect_memory_missing_count', 0)} |"
        )

    unresolved = nested_dict(summary.get("unresolved_breakdown"))
    append_breakdown(lines, "unsupported_deferred_effect_interaction", nested_list(unresolved.get("unsupported_deferred_effect_interaction")))
    append_breakdown(lines, "note_off_key_off", nested_list(unresolved.get("note_off_key_off")))
    append_breakdown(lines, "no_active_voice", nested_list(unresolved.get("no_active_voice")))
    return "\n".join(lines) + "\n"


def append_breakdown(lines: list[str], title: str, rows: list[Any]) -> None:
    lines.extend(["", f"## {title}"])
    if not rows:
        lines.append("- none")
        return
    for row in rows[:10]:
        if not isinstance(row, dict):
            continue
        label = row.get("command") or row.get("reason") or "unknown"
        coord = nested_dict(row.get("first_coordinate")).get("label", "unknown")
        lines.append(f"- {label}: {row.get('count', 0)} (first {coord})")


def write_json(summary: dict[str, Any], path: Path) -> None:
    data = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    path.write_text(data, encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path, help="Diagnostics JSON or runtime JSONL trace path")
    parser.add_argument("--json", type=Path, help="Write machine-readable summary JSON")
    parser.add_argument("--markdown", type=Path, help="Write Markdown summary")
    parser.add_argument("--top", type=int, default=0, help="Limit Markdown coverage table rows; 0 means all")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        summary = build_summary(args.inputs)
        if args.json:
            write_json(summary, args.json)
        markdown = build_markdown_report(summary, top=args.top if args.top > 0 else None)
        if args.markdown:
            args.markdown.write_text(markdown, encoding="utf-8")
        if not args.json and not args.markdown:
            print(markdown, end="")
        return 0
    except EffectCoverageError as error:
        print(f"summarize-xm-effect-coverage: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
