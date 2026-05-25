#!/usr/bin/env python3
"""Build a focused row/channel playback diagnostics summary from local XM artifacts.

Inputs are intentionally artifact paths produced outside git:
- mc_dump --json --pattern N
- vtx_render_bounded_xm --diagnostics-json PATH

The script does not read module files directly and does not echo input paths in
its report, so it is safe to use with anonymized local corpus labels.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


NOTE_NAMES = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
NEAR_ZERO_GAIN_THRESHOLD = 1.0 / 64.0


def load_json(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except OSError as error:
        raise SystemExit(f"error: could not read {path.name}: {error}") from error
    except json.JSONDecodeError as error:
        raise SystemExit(f"error: malformed JSON in {path.name}: {error}") from error
    if not isinstance(payload, dict):
        raise SystemExit(f"error: {path.name} must contain a JSON object")
    return payload


def note_text(note: int | None) -> str | None:
    if note is None:
        return None
    if note == 0:
        return "..."
    if note == 97:
        return "==="
    if note < 0 or note > 96:
        return "???"
    value = note - 1
    return f"{NOTE_NAMES[value % 12]}{value // 12}"


def effect_field(effect_type: int, effect_param: int) -> str:
    if effect_type == 0 and effect_param == 0:
        return "..."
    if 0 <= effect_type <= 0x0F:
        command = f"{effect_type:X}"
    elif effect_type == 0x10:
        command = "G"
    elif effect_type == 0x11:
        command = "H"
    else:
        command = "?"
    return f"{command}{effect_param:02X}"


def volume_column_text(raw_value: int) -> str:
    return ".." if raw_value == 0 else f"{raw_value:02X}"


def volume_column_category(raw_value: int) -> str | None:
    if raw_value == 0:
        return None
    if 0x10 <= raw_value <= 0x50:
        return f"volume-column set volume {raw_value - 0x10}"
    if 0x60 <= raw_value <= 0x6F:
        return f"volume-column slide down {raw_value & 0x0F}"
    if 0x70 <= raw_value <= 0x7F:
        return f"volume-column slide up {raw_value & 0x0F}"
    if 0x80 <= raw_value <= 0x8F:
        return f"volume-column fine slide down {raw_value & 0x0F}"
    if 0x90 <= raw_value <= 0x9F:
        return f"volume-column fine slide up {raw_value & 0x0F}"
    if 0xA0 <= raw_value <= 0xAF:
        return f"volume-column vibrato speed {raw_value & 0x0F}"
    if 0xB0 <= raw_value <= 0xBF:
        return f"volume-column vibrato {raw_value & 0x0F}"
    if 0xC0 <= raw_value <= 0xCF:
        return f"volume-column set panning {(raw_value & 0x0F) * 17}"
    if 0xD0 <= raw_value <= 0xDF:
        return f"volume-column panning slide left {raw_value & 0x0F}"
    if 0xE0 <= raw_value <= 0xEF:
        return f"volume-column panning slide right {raw_value & 0x0F}"
    if 0xF0 <= raw_value <= 0xFF:
        return f"volume-column tone portamento {raw_value & 0x0F}"
    return f"volume-column unsupported {raw_value:02X}"


def effect_category(effect_type: int, effect_param: int) -> str | None:
    if effect_type == 0x00:
        return None if effect_param == 0 else "0xy arpeggio"
    labels = {
        0x01: "1xx portamento up",
        0x02: "2xx portamento down",
        0x03: "3xx tone portamento",
        0x04: "4xy vibrato",
        0x05: "5xy tone portamento + volume slide",
        0x06: "6xy vibrato + volume slide",
        0x07: "7xy tremolo",
        0x08: "8xx set panning",
        0x09: "9xx sample offset",
        0x0A: "Axy volume slide",
        0x0B: "Bxx position jump",
        0x0C: "Cxx set volume",
        0x0D: "Dxx pattern break",
        0x0F: "Fxx speed/BPM",
        0x11: "Hxy global volume slide",
    }
    if effect_type == 0x0E:
        subcommand = (effect_param >> 4) & 0x0F
        return {
            0x01: "E1x fine portamento up",
            0x02: "E2x fine portamento down",
            0x05: "E5x set finetune",
            0x06: "E6x pattern loop",
            0x09: "E9x retrigger",
            0x0A: "EAx fine volume slide up",
            0x0B: "EBx fine volume slide down",
            0x0C: "ECx note cut",
            0x0D: "EDx note delay",
            0x0E: "EEx pattern delay",
        }.get(subcommand, "Exx extended")
    return labels.get(effect_type, f"unknown effect {effect_type:02X}")


def interpreted_category(cell: dict[str, Any]) -> str:
    parts = []
    volume = volume_column_category(int(cell["volume_column"]))
    effect = effect_category(int(cell["effect_type"]), int(cell["effect_param"]))
    if volume:
        parts.append(volume)
    if effect:
        parts.append(effect)
    return "; ".join(parts) if parts else "none"


def source_key(item: dict[str, Any]) -> tuple[int, int, int, int] | None:
    source = item.get("source")
    if not isinstance(source, dict):
        return None
    channel = item.get("channel_index")
    if not isinstance(channel, int):
        return None
    return (
        int(source.get("order", -1)),
        int(source.get("pattern", -1)),
        int(source.get("row", -1)),
        channel,
    )


def items_by_key(items: list[Any]) -> dict[tuple[int, int, int, int], list[dict[str, Any]]]:
    result: dict[tuple[int, int, int, int], list[dict[str, Any]]] = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        key = source_key(item)
        if key is None:
            continue
        result.setdefault(key, []).append(item)
    return result


def timing_source_key(item: dict[str, Any]) -> tuple[int, int, int] | None:
    source = item.get("source")
    if not isinstance(source, dict):
        return None
    return (
        int(source.get("order", -1)),
        int(source.get("pattern", -1)),
        int(source.get("row", -1)),
    )


def row_timing_by_key(items: list[Any]) -> dict[tuple[int, int, int], dict[str, Any]]:
    result: dict[tuple[int, int, int], dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        key = timing_source_key(item)
        if key is not None:
            result[key] = item
    return result


def cell_from_mc_dump(
    mc_dump: dict[str, Any],
    pattern: int,
    row: int,
    channel_index: int,
) -> dict[str, Any]:
    for event in mc_dump.get("xm_events", []):
        if not isinstance(event, dict):
            continue
        if (
            int(event.get("pattern", -1)) == pattern
            and int(event.get("row", -1)) == row
            and int(event.get("channel", -1)) == channel_index
        ):
            return {
                "note": int(event.get("note", 0)),
                "note_text": note_text(int(event.get("note", 0))),
                "instrument": int(event.get("instrument", 0)),
                "volume_column": int(event.get("volume", 0)),
                "volume_column_text": volume_column_text(int(event.get("volume", 0))),
                "effect_type": int(event.get("effect_type", 0)),
                "effect_param": int(event.get("effect_param", 0)),
                "effect": effect_field(int(event.get("effect_type", 0)), int(event.get("effect_param", 0))),
            }
    return {
        "note": 0,
        "note_text": "...",
        "instrument": 0,
        "volume_column": 0,
        "volume_column_text": "..",
        "effect_type": 0,
        "effect_param": 0,
        "effect": "...",
    }


def first_number(items: list[dict[str, Any]], key: str) -> int | float | None:
    for item in items:
        value = item.get(key)
        if isinstance(value, (int, float)):
            return value
    return None


def last_number(items: list[dict[str, Any]], key: str) -> int | float | None:
    return first_number(list(reversed(items)), key)


def is_near_zero_gain(value: Any) -> bool:
    return isinstance(value, (int, float)) and abs(float(value)) <= NEAR_ZERO_GAIN_THRESHOLD


def volume_column_set_volume_value(mappings: list[dict[str, Any]]) -> int | None:
    for mapping in mappings:
        volume_column = mapping.get("volume_column")
        if not isinstance(volume_column, dict):
            continue
        command = volume_column.get("command")
        if not isinstance(command, dict):
            continue
        if command.get("name") != "setVolume":
            continue
        value = command.get("value")
        if isinstance(value, int):
            return value
    return None


def gain_update_scheduled(update: dict[str, Any]) -> bool:
    if update.get("active_voice_updated") is not True:
        return False
    gain_after = update.get("gain_after")
    if not isinstance(gain_after, (int, float)):
        return False
    gain_before = update.get("gain_before")
    return not isinstance(gain_before, (int, float)) or float(gain_before) != float(gain_after)


def active_voice_gain_update_scheduled(updates: list[dict[str, Any]]) -> bool:
    return any(gain_update_scheduled(update) for update in updates)


def effective_gain_scheduled_to_c_mixer(
    event: dict[str, Any] | None,
    updates: list[dict[str, Any]],
) -> float | None:
    scheduled_update_gains = [
        float(update["gain_after"])
        for update in updates
        if gain_update_scheduled(update)
    ]
    if scheduled_update_gains:
        return scheduled_update_gains[-1]
    if event and isinstance(event.get("gain"), (int, float)):
        return float(event["gain"])
    return None


def tick_frame_count(row_timing: dict[str, Any] | None) -> int | None:
    if not row_timing:
        return None
    speed = row_timing.get("effective_speed")
    duration = row_timing.get("row_duration_frames")
    if not isinstance(speed, int) or speed <= 0 or not isinstance(duration, int):
        return None
    return max(1, round(duration / speed))


def maximum_synthetic_tick(
    row_timing: dict[str, Any] | None,
    updates: list[dict[str, Any]],
    tone_updates: list[dict[str, Any]],
) -> int:
    if row_timing and isinstance(row_timing.get("effective_speed"), int) and row_timing["effective_speed"] > 0:
        return int(row_timing["effective_speed"]) - 1
    max_tick = 0
    for update in updates:
        tick = update.get("synthetic_tick")
        if isinstance(tick, int):
            max_tick = max(max_tick, tick)
    for tone in tone_updates:
        for step in tone.get("step_updates", []):
            if not isinstance(step, dict):
                continue
            tick = step.get("synthetic_tick")
            if isinstance(tick, int):
                max_tick = max(max_tick, tick)
    return max_tick


def build_tick_timeline(
    *,
    row_timing: dict[str, Any] | None,
    event: dict[str, Any] | None,
    updates: list[dict[str, Any]],
    tone_updates: list[dict[str, Any]],
    channel_volume_before: int | float | None,
    channel_volume_after: int | float | None,
    gain_before: int | float | None,
    gain_after: int | float | None,
) -> list[dict[str, Any]]:
    updates_by_tick: dict[int, list[dict[str, Any]]] = {}
    for update in updates:
        tick = update.get("synthetic_tick")
        updates_by_tick.setdefault(tick if isinstance(tick, int) else 0, []).append(update)

    step_updates_by_tick: dict[int, list[dict[str, Any]]] = {}
    for tone in tone_updates:
        for step_update in tone.get("step_updates", []):
            if not isinstance(step_update, dict):
                continue
            tick = step_update.get("synthetic_tick")
            step_updates_by_tick.setdefault(tick if isinstance(tick, int) else 0, []).append(step_update)

    tick_frames = tick_frame_count(row_timing)
    row_start_frame = row_timing.get("row_start_frame") if row_timing else None
    if not isinstance(row_start_frame, int):
        row_start_frame = None

    current_volume = channel_volume_before
    current_gain = gain_before
    timeline = []
    max_tick = maximum_synthetic_tick(row_timing, updates, tone_updates)
    for tick in range(max_tick + 1):
        tick_updates = updates_by_tick.get(tick, [])
        step_updates = step_updates_by_tick.get(tick, [])
        volume_before_tick = current_volume
        gain_before_tick = current_gain

        volume_after_tick = last_number(tick_updates, "effective_volume_after")
        gain_after_tick = last_number(tick_updates, "gain_after")
        if volume_after_tick is not None:
            current_volume = volume_after_tick
        elif tick == 0 and event:
            event_volume = event.get("effective_volume_value")
            if isinstance(event_volume, (int, float)):
                current_volume = event_volume
        if gain_after_tick is not None:
            current_gain = gain_after_tick
        elif tick == 0 and event:
            event_gain = event.get("gain")
            if isinstance(event_gain, (int, float)):
                current_gain = event_gain

        scheduled_frame = None
        if row_start_frame is not None and tick_frames is not None:
            scheduled_frame = row_start_frame + tick * tick_frames
        if step_updates:
            step_frame = step_updates[-1].get("scheduled_frame")
            if isinstance(step_frame, int):
                scheduled_frame = step_frame
        update_frame = last_number(tick_updates, "scheduled_frame")
        if isinstance(update_frame, int):
            scheduled_frame = update_frame

        scheduled_gain = effective_gain_scheduled_to_c_mixer(
            event if tick == 0 else None,
            tick_updates,
        )
        timeline.append({
            "tick": tick,
            "scheduled_frame": scheduled_frame,
            "channel_volume_before_tick": volume_before_tick,
            "channel_volume_after_tick": current_volume,
            "gain_before_tick": gain_before_tick,
            "gain_after_tick": current_gain,
            "gain_reached_zero_or_near_zero": is_near_zero_gain(current_gain),
            "active_voice_gain_update_scheduled": active_voice_gain_update_scheduled(tick_updates),
            "effective_gain_scheduled_to_c_mixer": scheduled_gain,
            "tone_portamento_sample_step_update_count": len(step_updates),
            "tone_portamento_sample_step_after": last_number(step_updates, "current_step_after"),
        })
    return timeline


def event_sample_offset(event: dict[str, Any] | None) -> int | None:
    if event is None:
        return None
    value = event.get("initial_source_frame")
    if isinstance(value, int):
        return value
    sample_offset = event.get("sample_offset")
    if isinstance(sample_offset, dict):
        applied = sample_offset.get("applied_offset_frames")
        if isinstance(applied, int):
            return applied
    return None


def volume_slide_summary(updates: list[dict[str, Any]], mappings: list[dict[str, Any]]) -> dict[str, Any] | None:
    for update in updates:
        if update.get("command_name") in {"axyVolumeSlide", "effect6xyVolumeSlide"}:
            return {
                "source": update.get("command_label"),
                "direction": update.get("volume_slide_direction"),
                "amount": update.get("volume_slide_amount"),
                "up": update.get("volume_slide_up"),
                "down": update.get("volume_slide_down"),
                "raw_up_nibble": update.get("volume_slide_raw_up_nibble"),
                "raw_down_nibble": update.get("volume_slide_raw_down_nibble"),
                "both_nibbles_nonzero": update.get("volume_slide_both_nibbles_nonzero", False),
                "policy": update.get("volume_slide_policy"),
            }
    for mapping in mappings:
        volume_column = mapping.get("volume_column")
        if not isinstance(volume_column, dict):
            continue
        command = volume_column.get("command")
        if not isinstance(command, dict):
            continue
        name = command.get("name")
        if name in {
            "volumeSlideDown",
            "volumeSlideUp",
            "fineVolumeSlideDown",
            "fineVolumeSlideUp",
        }:
            return {
                "source": f"volume-column {name}",
                "direction": volume_column.get("slide_direction"),
                "amount": volume_column.get("slide_amount"),
                "up": command.get("amount") if name.endswith("Up") else 0,
                "down": command.get("amount") if name.endswith("Down") else 0,
                "raw_up_nibble": None,
                "raw_down_nibble": None,
                "both_nibbles_nonzero": False,
                "policy": volume_column.get("behavior"),
            }
    return None


def build_summary(
    mc_dump: dict[str, Any],
    diagnostics: dict[str, Any],
    *,
    label: str,
    order: int,
    pattern: int,
    channel_index: int,
    row_start: int,
    row_end: int,
) -> dict[str, Any]:
    events_by_key = items_by_key(list(diagnostics.get("events", [])))
    updates_by_key = items_by_key(list(diagnostics.get("volume_panning_state_updates", [])))
    mappings_by_key = items_by_key(list(diagnostics.get("volume_column_mappings", [])))
    tone_by_key = items_by_key(list(diagnostics.get("tone_portamento_effects", [])))
    ignored_by_key = items_by_key(list(diagnostics.get("ignored_cells", [])))
    offsets_by_key = items_by_key(list(diagnostics.get("sample_offset_effects", [])))
    timing_by_key = row_timing_by_key(list(diagnostics.get("row_timing", [])))

    order_table = mc_dump.get("order_table", [])
    order_maps_to_pattern = isinstance(order_table, list) and order < len(order_table) and order_table[order] == pattern

    active = False
    active_sample_index: int | None = None
    active_event_index: int | None = None
    current_channel_volume = 64
    current_gain: float | None = None
    rows = []

    for row in range(row_start, row_end + 1):
        key = (order, pattern, row, channel_index)
        cell = cell_from_mc_dump(mc_dump, pattern, row, channel_index)
        row_events = events_by_key.get(key, [])
        row_updates = updates_by_key.get(key, [])
        row_mappings = mappings_by_key.get(key, [])
        row_tone = tone_by_key.get(key, [])
        row_ignored = ignored_by_key.get(key, [])
        row_offsets = offsets_by_key.get(key, [])
        row_timing = timing_by_key.get((order, pattern, row))
        event = row_events[0] if row_events else None
        active_before = active
        active_sample_before = active_sample_index
        active_event_before = active_event_index

        channel_volume_before = first_number(row_updates, "effective_volume_before")
        channel_volume_after = first_number(list(reversed(row_updates)), "effective_volume_after")
        gain_before = first_number(row_updates, "gain_before")
        gain_after = first_number(list(reversed(row_updates)), "gain_after")

        if channel_volume_before is None:
            channel_volume_before = current_channel_volume
        if channel_volume_after is None:
            channel_volume_after = event.get("effective_volume_value") if event else current_channel_volume
        if isinstance(channel_volume_after, int):
            current_channel_volume = channel_volume_after

        if gain_before is None:
            gain_before = current_gain
        if gain_after is None:
            gain_after = event.get("gain") if event else current_gain

        note_trigger_event_created = bool(row_events)
        voice_replacement_happened = note_trigger_event_created and active_before
        if event:
            active = True
            active_sample_index = event.get("sample_index") if isinstance(event.get("sample_index"), int) else None
            active_event_index = event.get("event_index") if isinstance(event.get("event_index"), int) else None
            current_gain = event.get("gain") if isinstance(event.get("gain"), (int, float)) else current_gain
        if isinstance(gain_after, (int, float)):
            current_gain = float(gain_after)

        sample_offset = event_sample_offset(event)
        if sample_offset is None and row_offsets:
            value = row_offsets[0].get("applied_offset_frames")
            if isinstance(value, int):
                sample_offset = value

        tone_target_set = any(item.get("target_exists_after") is True for item in row_tone)
        tone_suppressed = (
            1 <= int(cell["note"]) <= 96
            and int(cell["effect_type"]) == 0x03
            and bool(row_tone)
            and not note_trigger_event_created
        )
        set_volume_value = volume_column_set_volume_value(row_mappings)
        scheduled_gain = effective_gain_scheduled_to_c_mixer(event, row_updates)
        tick_timeline = build_tick_timeline(
            row_timing=row_timing,
            event=event,
            updates=row_updates,
            tone_updates=row_tone,
            channel_volume_before=channel_volume_before,
            channel_volume_after=channel_volume_after,
            gain_before=gain_before,
            gain_after=gain_after,
        )
        channel_volume_after_nonzero_ticks = [
            {
                "tick": item["tick"],
                "channel_volume": item["channel_volume_after_tick"],
                "gain": item["gain_after_tick"],
            }
            for item in tick_timeline
            if item["tick"] > 0
        ]

        rows.append({
            "row": row,
            "row_hex": f"{row:02X}",
            "decoded_cell": cell,
            "interpreted_effect_category": interpreted_category(cell),
            "note_trigger_event_created": note_trigger_event_created,
            "voice_replacement_happened": voice_replacement_happened,
            "tone_portamento_target_set": tone_target_set,
            "tone_portamento_suppressed_retrigger": tone_suppressed,
            "channel_volume_before": channel_volume_before,
            "channel_volume_after": channel_volume_after,
            "channel_volume_after_tick0": tick_timeline[0]["channel_volume_after_tick"] if tick_timeline else channel_volume_after,
            "channel_volume_after_nonzero_ticks": channel_volume_after_nonzero_ticks,
            "gain_before": gain_before,
            "gain_after": gain_after,
            "gain_reached_zero_or_near_zero": is_near_zero_gain(gain_after),
            "effective_gain_scheduled_to_c_mixer": scheduled_gain,
            "active_voice_gain_update_scheduled": active_voice_gain_update_scheduled(row_updates),
            "volume_column_set_volume_value": set_volume_value,
            "volume_slide": volume_slide_summary(row_updates, row_mappings),
            "sample_selected": event.get("sample_index") if event else None,
            "sample_selection_method": event.get("sample_selection_method") if event else None,
            "sample_offset": sample_offset,
            "active_voice_present_before": active_before,
            "active_voice_present_after": active,
            "active_sample_before": active_sample_before,
            "active_sample_after": active_sample_index,
            "active_event_index_before": active_event_before,
            "active_event_index_after": active_event_index,
            "ignored_reasons": [item.get("reason") or item.get("skip_reason") for item in row_ignored],
            "tone_portamento_diagnostics": row_tone,
            "events": row_events,
            "voice_state_updates": row_updates,
            "volume_column_mappings": row_mappings,
            "tick_timeline": tick_timeline,
        })

    note_text_mismatches = []
    for event in diagnostics.get("events", []):
        if not isinstance(event, dict) or not isinstance(event.get("note"), int):
            continue
        expected = note_text(event["note"])
        actual = event.get("note_text")
        if actual is not None and actual != expected:
            note_text_mismatches.append({"kind": "event", "note": event["note"], "expected": expected, "actual": actual})
    for tone in diagnostics.get("tone_portamento_effects", []):
        if not isinstance(tone, dict) or not isinstance(tone.get("target_note"), int):
            continue
        expected = note_text(tone["target_note"])
        actual = tone.get("target_note_text")
        if actual is not None and actual != expected:
            note_text_mismatches.append({
                "kind": "tone_portamento_target",
                "note": tone["target_note"],
                "expected": expected,
                "actual": actual,
            })

    focused_note_rows = [
        {"row": item["row"], "row_hex": item["row_hex"], "note": item["decoded_cell"]["note"], "note_text": item["decoded_cell"]["note_text"]}
        for item in rows
        if item["decoded_cell"]["note"] not in (0, 97)
    ]
    normal_trigger_rows = [
        item["row_hex"]
        for item in rows
        if 1 <= item["decoded_cell"]["note"] <= 96
        and item["decoded_cell"]["effect_type"] != 0x03
        and item["note_trigger_event_created"]
    ]
    suppressed_3xx_rows = [item["row_hex"] for item in rows if item["tone_portamento_suppressed_retrigger"]]
    mixed_axy_rows = [
        item["row_hex"]
        for item in rows
        if item["volume_slide"] and item["volume_slide"].get("both_nibbles_nonzero") is True
    ]
    zero_or_near_zero_gain_rows = [
        item["row_hex"] for item in rows if item["gain_reached_zero_or_near_zero"]
    ]
    set_volume_without_active_update_rows = [
        item["row_hex"]
        for item in rows
        if item["volume_column_set_volume_value"] is not None
        and not item["active_voice_gain_update_scheduled"]
    ]
    set_volume_with_active_update_rows = [
        item["row_hex"]
        for item in rows
        if item["volume_column_set_volume_value"] is not None
        and item["active_voice_gain_update_scheduled"]
    ]

    return {
        "schema_version": 2,
        "tool": "scripts/focused-xm-channel-diagnostics.py",
        "local_only": True,
        "label": label,
        "focus": {
            "order": order,
            "pattern": pattern,
            "order_maps_to_pattern": order_maps_to_pattern,
            "channel_index": channel_index,
            "channel_one_based": channel_index + 1,
            "row_start": row_start,
            "row_end": row_end,
        },
        "note_display_verification": {
            "policy": "XM note value 1 maps to C-0; note values advance chromatically.",
            "examples": [
                {"note": 1, "note_text": note_text(1)},
                {"note": 54, "note_text": note_text(54)},
                {"note": 56, "note_text": note_text(56)},
                {"note": 97, "note_text": note_text(97)},
            ],
            "focused_note_rows": focused_note_rows,
            "diagnostics_note_text_mismatch_count": len(note_text_mismatches),
            "diagnostics_note_text_mismatches": note_text_mismatches,
        },
        "summary": {
            "normal_note_trigger_rows": normal_trigger_rows,
            "tone_portamento_suppressed_retrigger_rows": suppressed_3xx_rows,
            "mixed_nibble_axy_rows": mixed_axy_rows,
            "zero_or_near_zero_gain_rows": zero_or_near_zero_gain_rows,
            "volume_column_set_volume_with_active_voice_update_rows": set_volume_with_active_update_rows,
            "volume_column_set_volume_without_active_voice_update_rows": set_volume_without_active_update_rows,
            "rows_with_note_triggers": [item["row_hex"] for item in rows if item["note_trigger_event_created"]],
            "rows_with_voice_replacement": [item["row_hex"] for item in rows if item["voice_replacement_happened"]],
            "rows_with_no_active_tone_portamento": [
                item["row_hex"]
                for item in rows
                if any(diagnostic.get("active_voice_found") is False for diagnostic in item["tone_portamento_diagnostics"])
            ],
            "candidate_interpretation": (
                "same-cell 3xx note rows set tone-portamento targets without retriggering; "
                "non-3xx note rows remain normal trigger/replacement rows."
            ),
        },
        "rows": rows,
    }


def format_bool(value: Any) -> str:
    if value is True:
        return "yes"
    if value is False:
        return "no"
    return "n/a"


def compact_value(value: Any) -> str:
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.6g}"
    if isinstance(value, bool):
        return format_bool(value)
    return str(value)


def render_markdown(summary: dict[str, Any]) -> str:
    focus = summary["focus"]
    note_check = summary["note_display_verification"]
    lines = [
        f"# Focused XM Channel Diagnostics: {summary['label']}",
        "",
        f"- Order/pattern: {focus['order']} -> {focus['pattern']} (verified: {format_bool(focus['order_maps_to_pattern'])})",
        f"- Channel: {focus['channel_one_based']} one-based / {focus['channel_index']} zero-based",
        f"- Rows: 0x{focus['row_start']:02X} through 0x{focus['row_end']:02X}",
        f"- Note mapping policy: {note_check['policy']}",
        f"- Note-text mismatches in diagnostics JSON: {note_check['diagnostics_note_text_mismatch_count']}",
        "",
        "## Summary",
        "",
        f"- Normal trigger rows: {', '.join(summary['summary']['normal_note_trigger_rows']) or 'none'}",
        f"- Same-cell 3xx suppressed-retrigger rows: {', '.join(summary['summary']['tone_portamento_suppressed_retrigger_rows']) or 'none'}",
        f"- Mixed-nibble Axy rows: {', '.join(summary['summary']['mixed_nibble_axy_rows']) or 'none'}",
        f"- Zero/near-zero gain rows: {', '.join(summary['summary']['zero_or_near_zero_gain_rows']) or 'none'}",
        (
            "- Volume-column set-volume rows with active voice gain updates: "
            f"{', '.join(summary['summary']['volume_column_set_volume_with_active_voice_update_rows']) or 'none'}"
        ),
        (
            "- Volume-column set-volume rows without active voice gain updates: "
            f"{', '.join(summary['summary']['volume_column_set_volume_without_active_voice_update_rows']) or 'none'}"
        ),
        f"- Voice replacement rows: {', '.join(summary['summary']['rows_with_voice_replacement']) or 'none'}",
        f"- Interpretation: {summary['summary']['candidate_interpretation']}",
        "",
        "## Rows",
        "",
        "| Row | Cell | Category | Trigger | Replace | 3xx target/suppress | Volume | Gain | SetVol | Slide | C mix gain | Near0 | Sample | Offset | Active |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in summary["rows"]:
        cell = row["decoded_cell"]
        cell_text = (
            f"{cell['note_text']} "
            f"{cell['instrument']:02X} "
            f"{cell['volume_column_text']} "
            f"{cell['effect']}"
        )
        tone = (
            f"{format_bool(row['tone_portamento_target_set'])}/"
            f"{format_bool(row['tone_portamento_suppressed_retrigger'])}"
        )
        volume = f"{compact_value(row['channel_volume_before'])}->{compact_value(row['channel_volume_after'])}"
        gain = f"{compact_value(row['gain_before'])}->{compact_value(row['gain_after'])}"
        slide = row.get("volume_slide")
        if slide:
            slide_text = (
                f"{slide.get('direction')} {slide.get('amount')}"
                + (f" ({slide.get('policy')})" if slide.get("policy") else "")
            )
        else:
            slide_text = "-"
        c_mixer_gain = compact_value(row.get("effective_gain_scheduled_to_c_mixer"))
        active = f"{format_bool(row['active_voice_present_before'])}->{format_bool(row['active_voice_present_after'])}"
        lines.append(
            "| "
            + " | ".join([
                row["row_hex"],
                cell_text,
                row["interpreted_effect_category"],
                format_bool(row["note_trigger_event_created"]),
                format_bool(row["voice_replacement_happened"]),
                tone,
                volume,
                gain,
                compact_value(row.get("volume_column_set_volume_value")),
                slide_text,
                c_mixer_gain,
                format_bool(row.get("gain_reached_zero_or_near_zero")),
                compact_value(row["sample_selected"]),
                compact_value(row["sample_offset"]),
                active,
            ])
            + " |"
        )
    lines.extend([
        "",
        "## Tick Timeline",
        "",
        "| Row | Tick | Frame | Volume | Gain | Active gain update | C mix gain | Tone step updates | Near0 |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ])
    for row in summary["rows"]:
        for tick in row["tick_timeline"]:
            volume = (
                f"{compact_value(tick['channel_volume_before_tick'])}"
                f"->{compact_value(tick['channel_volume_after_tick'])}"
            )
            gain = (
                f"{compact_value(tick['gain_before_tick'])}"
                f"->{compact_value(tick['gain_after_tick'])}"
            )
            lines.append(
                "| "
                + " | ".join([
                    row["row_hex"],
                    str(tick["tick"]),
                    compact_value(tick.get("scheduled_frame")),
                    volume,
                    gain,
                    format_bool(tick.get("active_voice_gain_update_scheduled")),
                    compact_value(tick.get("effective_gain_scheduled_to_c_mixer")),
                    compact_value(tick.get("tone_portamento_sample_step_update_count")),
                    format_bool(tick.get("gain_reached_zero_or_near_zero")),
                ])
                + " |"
            )
    lines.append("")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mc-dump-json", type=Path, required=True)
    parser.add_argument("--diagnostics-json", type=Path, required=True)
    parser.add_argument("--label", default="local-xm")
    parser.add_argument("--order", type=int, required=True)
    parser.add_argument("--pattern", type=int, required=True)
    parser.add_argument("--channel-index", type=int)
    parser.add_argument("--channel-one-based", type=int)
    parser.add_argument("--row-start", type=lambda value: int(value, 0), default=0)
    parser.add_argument("--row-end", type=lambda value: int(value, 0), default=0x3F)
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.channel_index is None and args.channel_one_based is None:
        raise SystemExit("error: pass --channel-index or --channel-one-based")
    channel_index = args.channel_index if args.channel_index is not None else args.channel_one_based - 1
    if channel_index < 0:
        raise SystemExit("error: channel must be positive")
    if args.row_end < args.row_start:
        raise SystemExit("error: --row-end must be >= --row-start")

    summary = build_summary(
        load_json(args.mc_dump_json),
        load_json(args.diagnostics_json),
        label=args.label,
        order=args.order,
        pattern=args.pattern,
        channel_index=channel_index,
        row_start=args.row_start,
        row_end=args.row_end,
    )
    if args.format == "json":
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print(render_markdown(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
