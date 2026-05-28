#!/usr/bin/env python3
"""Summarize focused bounded-render voice timelines for local XM parity windows."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


STEP_UPDATE_SECTIONS = (
    ("arpeggio_effects", "0xy arpeggio"),
    ("tone_portamento_effects", "3xx tone portamento"),
    ("portamento_slide_effects", "1xx/2xx portamento slide"),
    ("fine_portamento_up_effects", "E1x fine portamento up"),
    ("fine_portamento_down_effects", "E2x fine portamento down"),
    ("vibrato_effects", "4xy/6xy vibrato"),
    ("vibrato_volume_slide_6xy_effects", "6xy vibrato + volume slide"),
)
FRACTION_EPSILON = 1.0e-9


class TimelineError(Exception):
    """A user-facing diagnostics input error."""


def load_json(path: Path, role: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise TimelineError(f"could not read {role} JSON: {path}") from error
    except json.JSONDecodeError as error:
        raise TimelineError(f"malformed {role} JSON: {path}: {error}") from error
    if not isinstance(payload, dict):
        raise TimelineError(f"{role} JSON must contain a top-level object: {path}")
    return payload


def nested_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def nested_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def number(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return float(value)
    return None


def integer(value: Any) -> int | None:
    numeric = number(value)
    return int(numeric) if numeric is not None else None


def first_present(*values: Any) -> Any:
    for value in values:
        if value is not None:
            return value
    return None


def value_from(mapping: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in mapping and mapping[key] is not None:
            return mapping[key]
    return None


def sample_rate_from(diagnostics: dict[str, Any], comparison: dict[str, Any] | None = None) -> int:
    candidates = [nested_dict(diagnostics.get("render")).get("sample_rate")]
    if comparison:
        candidates.extend([
            nested_dict(nested_dict(comparison.get("candidate")).get("info")).get("sample_rate"),
            nested_dict(nested_dict(comparison.get("reference")).get("info")).get("sample_rate"),
        ])
    for candidate in candidates:
        parsed = number(candidate)
        if parsed is not None and parsed > 0:
            return int(parsed)
    raise TimelineError("could not determine sample rate from diagnostics or comparison JSON")


def parse_window(value: str, sample_rate: int, rank: int) -> dict[str, Any]:
    separator = ":" if ":" in value else "-"
    parts = value.split(separator, 1)
    if len(parts) != 2:
        raise TimelineError(f"window must be START:END seconds: {value}")
    try:
        start_seconds = float(parts[0])
        end_seconds = float(parts[1])
    except ValueError as error:
        raise TimelineError(f"window must use numeric START:END seconds: {value}") from error
    if not math.isfinite(start_seconds) or not math.isfinite(end_seconds) or end_seconds <= start_seconds:
        raise TimelineError(f"window end must be greater than start: {value}")
    return {
        "rank": rank,
        "label": value,
        "start_seconds": start_seconds,
        "end_seconds": end_seconds,
        "start_frame": max(0, int(math.floor(start_seconds * sample_rate))),
        "end_frame": max(1, int(math.ceil(end_seconds * sample_rate))),
    }


def windows_from_comparison(comparison: dict[str, Any], sample_rate: int) -> list[dict[str, Any]]:
    sample = nested_dict(comparison.get("sample_comparison"))
    windows = nested_list(sample.get("worst_windows"))
    result: list[dict[str, Any]] = []
    for index, window in enumerate(windows, start=1):
        if not isinstance(window, dict):
            continue
        start_frame = integer(window.get("start_frame"))
        end_frame = integer(window.get("end_frame"))
        start_seconds = number(window.get("start_seconds"))
        end_seconds = number(window.get("end_seconds"))
        if start_frame is None and start_seconds is not None:
            start_frame = int(math.floor(start_seconds * sample_rate))
        if end_frame is None and end_seconds is not None:
            end_frame = int(math.ceil(end_seconds * sample_rate))
        if start_frame is None or end_frame is None:
            continue
        result.append({
            "rank": index,
            "label": f"worst-{index}",
            "start_seconds": start_frame / sample_rate,
            "end_seconds": end_frame / sample_rate,
            "start_frame": max(0, start_frame),
            "end_frame": max(start_frame + 1, end_frame),
            "rms_difference": window.get("rms_difference"),
            "max_abs_sample_difference": window.get("max_abs_sample_difference"),
        })
    return result


def overlaps(start_a: int, end_a: int, start_b: int, end_b: int) -> bool:
    return start_a < end_b and end_a > start_b


def source_key(source: dict[str, Any]) -> tuple[Any, Any, Any]:
    return (source.get("order"), source.get("pattern"), source.get("row"))


def normalize_rows(diagnostics: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    for row in nested_list(diagnostics.get("row_timing")):
        if not isinstance(row, dict):
            continue
        start = integer(row.get("row_start_frame"))
        end = integer(row.get("row_end_frame"))
        if start is None:
            continue
        if end is None:
            end = start + max(1, integer(row.get("row_duration_frames")) or 1)
        rows.append({**row, "_start_frame": max(0, start), "_end_frame": max(start + 1, end)})
    rows.sort(key=lambda item: (item["_start_frame"], item.get("synthetic_row", 0)))
    return rows


def normalize_events(diagnostics: dict[str, Any], sample_rate: int) -> list[dict[str, Any]]:
    events = []
    for event in nested_list(diagnostics.get("events")):
        if not isinstance(event, dict):
            continue
        start = integer(event.get("scheduled_start_frame"))
        if start is None:
            seconds = number(event.get("scheduled_start_seconds"))
            start = int(math.floor(seconds * sample_rate)) if seconds is not None else None
        if start is None:
            continue
        end = integer(event.get("estimated_end_frame"))
        if end is None:
            end = start + max(1, integer(event.get("estimated_duration_frames")) or 1)
        events.append({
            **event,
            "_start_frame": max(0, start),
            "_end_frame": max(start + 1, end),
            "_active_end_frame": max(start + 1, end),
        })
    events.sort(key=lambda item: (item["_start_frame"], item.get("event_index", 0)))
    apply_replacement_lifetimes(events, diagnostics)
    return events


def apply_replacement_lifetimes(events: list[dict[str, Any]], diagnostics: dict[str, Any]) -> None:
    events_by_index = {
        event.get("event_index"): event
        for event in events
        if event.get("event_index") is not None
    }
    for replacement in nested_list(nested_dict(diagnostics.get("same_channel_voice_lifetime")).get("replacement_events")):
        if not isinstance(replacement, dict):
            continue
        old_index = replacement.get("old_event_index")
        old_event = events_by_index.get(old_index)
        if old_event is None:
            continue
        completion = integer(replacement.get("completion_frame"))
        replacement_frame = integer(replacement.get("replacement_frame"))
        ramp = integer(replacement.get("old_voice_ramp_duration_frames")) or 0
        if completion is None and replacement_frame is not None:
            completion = replacement_frame + max(1, ramp)
        if completion is None:
            continue
        old_event["_active_end_frame"] = min(int(old_event["_active_end_frame"]), max(int(old_event["_start_frame"]) + 1, completion))


def row_tick_range(row: dict[str, Any], start_frame: int, end_frame: int) -> dict[str, Any]:
    speed = integer(row.get("effective_speed")) or 0
    duration = max(1, int(row["_end_frame"]) - int(row["_start_frame"]))
    tick_frames = duration / speed if speed > 0 else None
    if tick_frames is None:
        return {"tick_start": None, "tick_end": None, "tick_frames": None}
    local_start = max(0, start_frame - int(row["_start_frame"]))
    local_end = max(local_start, min(int(row["_end_frame"]), end_frame) - int(row["_start_frame"]))
    tick_start = min(speed - 1, max(0, int(math.floor(local_start / tick_frames))))
    tick_end = min(speed - 1, max(tick_start, int(math.ceil(local_end / tick_frames)) - 1))
    return {"tick_start": tick_start, "tick_end": tick_end, "tick_frames": tick_frames}


def collect_step_updates(diagnostics: dict[str, Any]) -> list[dict[str, Any]]:
    updates: list[dict[str, Any]] = []
    for section, label in STEP_UPDATE_SECTIONS:
        for diagnostic in nested_list(diagnostics.get(section)):
            if not isinstance(diagnostic, dict):
                continue
            for update in nested_list(diagnostic.get("step_updates")):
                if not isinstance(update, dict):
                    continue
                annotated = annotate_step_update(update, diagnostic, label)
                frame = integer(first_present(
                    value_from(annotated, "scheduled_frame"),
                    value_from(annotated, "absolute_frame"),
                ))
                if frame is None:
                    continue
                updates.append({
                    **annotated,
                    "_frame": max(0, frame),
                })
    updates.sort(key=lambda item: (item["_frame"], str(item["label"]), integer(item.get("channel_index")) or -1))
    return updates


def annotate_step_update(
    update: dict[str, Any],
    parent: dict[str, Any],
    label: str,
) -> dict[str, Any]:
    result = dict(update)
    result["label"] = label
    result["source"] = nested_dict(parent.get("source"))
    result["channel_index"] = first_present(update.get("channel_index"), parent.get("channel_index"))
    result["active_event_index"] = first_present(update.get("active_event_index"), parent.get("active_event_index"))
    result["active_event_mapping_index"] = first_present(
        update.get("active_event_mapping_index"),
        parent.get("active_event_mapping_index"),
    )
    result["status"] = first_present(
        update.get("status"),
        update.get("current_status"),
        parent.get("status"),
        parent.get("current_status"),
    )
    result["linear_period_before"] = value_from(
        update,
        "linear_period_before",
        "current_linear_period_before",
        "current_period_before",
    )
    result["linear_period_after"] = value_from(
        update,
        "linear_period_after",
        "current_linear_period_after",
        "current_period_after",
    )
    result["playback_step_before"] = value_from(
        update,
        "playback_step_before",
        "current_playback_step_before",
        "current_step_before",
    )
    result["playback_step_after"] = value_from(
        update,
        "playback_step_after",
        "current_playback_step_after",
        "current_step_after",
    )
    result["target_linear_period"] = first_present(
        value_from(update, "target_linear_period", "target_period"),
        value_from(parent, "target_linear_period", "target_period"),
    )
    result["target_playback_step"] = first_present(
        value_from(update, "target_playback_step", "target_step"),
        value_from(parent, "target_playback_step", "target_step"),
    )
    return result


def annotate_effect_diagnostic(diagnostic: dict[str, Any], label: str) -> dict[str, Any]:
    result = dict(diagnostic)
    result["label"] = label
    result["step_updates"] = [
        annotate_step_update(update, diagnostic, label)
        for update in nested_list(diagnostic.get("step_updates"))
        if isinstance(update, dict)
    ]
    return result


def advance_position(
    position: float,
    frames: int,
    step: float,
    event: dict[str, Any],
) -> tuple[float, int]:
    if frames <= 0 or step <= 0:
        return position, 0
    raw = position + frames * step
    loop_mode = str(event.get("loop_mode") or "none")
    loop_start = integer(event.get("loop_start_frame"))
    loop_end = integer(event.get("loop_end_frame"))
    if loop_mode == "forward" and loop_start is not None and loop_end is not None and loop_end > loop_start:
        length = loop_end - loop_start
        if raw >= loop_end:
            crossing = int(math.floor((raw - loop_end) / length)) + 1
            return loop_start + math.fmod(raw - loop_end, length), crossing
        return raw, 0
    if loop_mode == "ping_pong" and loop_start is not None and loop_end is not None and loop_end > loop_start + 1:
        first = float(loop_start)
        last = float(loop_end - 1)
        span = last - first
        if raw <= last:
            return raw, 0
        excess = raw - last
        phase = math.fmod(excess, span * 2.0)
        crossing = int(math.floor(excess / span)) + 1
        if phase <= span:
            return last - phase, crossing
        return first + (phase - span), crossing
    sample_count = integer(event.get("sample_frame_count"))
    crossed = 1 if sample_count is not None and position < sample_count <= raw else 0
    return raw, crossed


def source_position_at(event: dict[str, Any], frame: int, step_updates: list[dict[str, Any]]) -> dict[str, Any]:
    event_start = integer(event.get("_start_frame")) or integer(event.get("scheduled_start_frame")) or 0
    target = max(event_start, frame)
    pitch = nested_dict(event.get("pitch"))
    step = number(pitch.get("playback_step")) or number(event.get("playback_step")) or 0.0
    position = number(event.get("initial_source_frame")) or 0.0
    current_frame = event_start
    crossings = 0
    event_index = event.get("event_index")
    channel = event.get("channel_index")
    relevant = [
        update for update in step_updates
        if current_frame <= int(update["_frame"]) <= target
        and (
            update.get("active_event_index") == event_index
            or (update.get("active_event_index") is None and update.get("channel_index") == channel)
        )
    ]
    for update in relevant:
        update_frame = int(update["_frame"])
        position, delta = advance_position(position, update_frame - current_frame, step, event)
        crossings += delta
        step = (
            number(update.get("playback_step_after"))
            or number(update.get("current_step_after"))
            or step
        )
        current_frame = update_frame
    position, delta = advance_position(position, target - current_frame, step, event)
    crossings += delta
    return {
        "frame": frame,
        "position": position,
        "fractional": abs(position - math.floor(position)) > FRACTION_EPSILON,
        "sample_step": step,
        "loop_crossing_count": crossings,
        "approximation": "piecewise_sample_step_with_forward_loop_and_ping_pong_estimates",
    }


def loop_phase(position: Any, event: dict[str, Any]) -> float | None:
    value = number(position)
    loop_start = integer(event.get("loop_start_frame"))
    loop_end = integer(event.get("loop_end_frame"))
    if value is None or loop_start is None or loop_end is None or loop_end <= loop_start:
        return None
    loop_mode = str(event.get("loop_mode") or "none")
    if loop_mode == "forward":
        return min(1.0, max(0.0, (value - loop_start) / (loop_end - loop_start)))
    if loop_mode == "ping_pong":
        span = max(1, loop_end - loop_start - 1)
        return min(1.0, max(0.0, (value - loop_start) / span))
    return None


def steady_state_loop_interior(event: dict[str, Any], start: dict[str, Any], end: dict[str, Any]) -> bool:
    loop_mode = str(event.get("loop_mode") or "none")
    if loop_mode == "none":
        return False
    loop_start = integer(event.get("loop_start_frame"))
    loop_end = integer(event.get("loop_end_frame"))
    step = number(end.get("sample_step")) or number(start.get("sample_step")) or 0.0
    start_position = number(start.get("position"))
    end_position = number(end.get("position"))
    if loop_start is None or loop_end is None or loop_end <= loop_start:
        return False
    if start_position is None or end_position is None:
        return False
    if int(end.get("loop_crossing_count") or 0) > int(start.get("loop_crossing_count") or 0):
        return False
    margin = max(1.0, abs(step))
    return (
        start_position >= loop_start + margin
        and start_position <= loop_end - margin
        and end_position >= loop_start + margin
        and end_position <= loop_end - margin
    )


def voice_update_count(
    updates: list[dict[str, Any]],
    event: dict[str, Any],
    window: dict[str, Any],
) -> int:
    start = int(window["start_frame"])
    end = int(window["end_frame"])
    event_index = event.get("event_index")
    channel = event.get("channel_index")
    count = 0
    for update in updates:
        frame = integer(update.get("_frame", update.get("scheduled_frame")))
        if frame is None or not (start <= frame < end):
            continue
        active_index = update.get("active_event_index")
        if active_index == event_index or (active_index is None and update.get("channel_index") == channel):
            count += 1
    return count


def replacement_ramp_count(
    replacements: list[dict[str, Any]],
    event: dict[str, Any],
    window: dict[str, Any],
) -> int:
    start = int(window["start_frame"])
    end = int(window["end_frame"])
    event_index = event.get("event_index")
    count = 0
    for replacement in replacements:
        replacement_frame = integer(replacement.get("replacement_frame"))
        completion = integer(replacement.get("completion_frame"))
        if replacement_frame is None:
            continue
        ramp_start = replacement_frame
        ramp_end = max(ramp_start + 1, completion or replacement_frame + max(1, integer(replacement.get("old_voice_ramp_duration_frames")) or 1))
        if not overlaps(ramp_start, ramp_end, start, end):
            continue
        if replacement.get("old_event_index") == event_index or replacement.get("new_event_index") == event_index:
            count += 1
    return count


def contribution_estimate(event: dict[str, Any], window: dict[str, Any]) -> float:
    gain = number(event.get("gain"))
    if gain is None:
        return 0.0
    start = max(int(window["start_frame"]), integer(event.get("_start_frame")) or 0)
    end = min(
        int(window["end_frame"]),
        integer(event.get("_active_end_frame", event.get("_end_frame"))) or int(window["end_frame"]),
    )
    overlap_frames = max(0, end - start)
    return gain * gain * overlap_frames


def summarize_voice(
    event: dict[str, Any],
    window: dict[str, Any],
    step_updates: list[dict[str, Any]],
    gain_pan_updates: list[dict[str, Any]],
    replacements: list[dict[str, Any]],
) -> dict[str, Any]:
    start = source_position_at(event, int(window["start_frame"]), step_updates)
    effective_end_frame = min(int(window["end_frame"]), int(event.get("_active_end_frame", event["_end_frame"])))
    end = source_position_at(event, effective_end_frame, step_updates)
    pitch = nested_dict(event.get("pitch"))
    crossing_delta = max(0, int(end["loop_crossing_count"]) - int(start["loop_crossing_count"]))
    loop_mode = str(event.get("loop_mode") or "none")
    loop_boundary_crossings = crossing_delta if loop_mode != "none" else 0
    source_end_crossings = crossing_delta if loop_mode == "none" else 0
    return {
        "event_index": event.get("event_index"),
        "channel_index": event.get("channel_index"),
        "source": nested_dict(event.get("source")),
        "note": event.get("note"),
        "note_text": event.get("note_text"),
        "instrument_index": event.get("instrument_index"),
        "sample_index": event.get("sample_index"),
        "sample_frame_count": event.get("sample_frame_count"),
        "sample_selection_method": event.get("sample_selection_method", event.get("selected_sample_selection_method")),
        "loop_mode": event.get("loop_mode", "none"),
        "loop_start_frame": event.get("loop_start_frame"),
        "loop_end_frame": event.get("loop_end_frame"),
        "loop_length_frames": event.get("loop_length_frames"),
        "initial_source_frame": event.get("initial_source_frame"),
        "playback_step": pitch.get("playback_step", event.get("playback_step")),
        "linear_period": pitch.get("linear_period"),
        "linear_frequency": pitch.get("linear_frequency"),
        "gain": event.get("gain"),
        "pan": event.get("pan", event.get("effective_pan")),
        "active_frame_range": [event["_start_frame"], event.get("_active_end_frame", event["_end_frame"])],
        "source_position_start": start,
        "source_position_end": end,
        "loop_phase_start": loop_phase(start.get("position"), event),
        "loop_phase_end": loop_phase(end.get("position"), event),
        "steady_state_loop_interior": steady_state_loop_interior(event, start, end),
        "loop_crossings_in_window": loop_boundary_crossings,
        "source_end_crossings_in_window": source_end_crossings,
        "contribution_estimate": contribution_estimate(event, window),
        "sample_step_update_count": voice_update_count(step_updates, event, window),
        "gain_pan_update_count": voice_update_count(gain_pan_updates, event, window),
        "replacement_ramp_count": replacement_ramp_count(replacements, event, window),
    }


def dominant_sample_groups(voices: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, Any, Any, Any, Any], dict[str, Any]] = {}
    for voice in voices:
        key = (
            voice.get("instrument_index"),
            voice.get("sample_index"),
            voice.get("loop_mode"),
            voice.get("loop_start_frame"),
            voice.get("loop_end_frame"),
        )
        group = groups.setdefault(key, {
            "instrument_index": voice.get("instrument_index"),
            "sample_index": voice.get("sample_index"),
            "loop_mode": voice.get("loop_mode"),
            "loop_start_frame": voice.get("loop_start_frame"),
            "loop_end_frame": voice.get("loop_end_frame"),
            "loop_length_frames": voice.get("loop_length_frames"),
            "voice_count": 0,
            "steady_state_voice_count": 0,
            "loop_crossing_count": 0,
            "source_end_crossing_count": 0,
            "contribution_estimate": 0.0,
        })
        group["voice_count"] += 1
        if voice.get("steady_state_loop_interior"):
            group["steady_state_voice_count"] += 1
        group["loop_crossing_count"] += integer(voice.get("loop_crossings_in_window")) or 0
        group["source_end_crossing_count"] += integer(voice.get("source_end_crossings_in_window")) or 0
        group["contribution_estimate"] += number(voice.get("contribution_estimate")) or 0.0
    total = sum(number(group.get("contribution_estimate")) or 0.0 for group in groups.values())
    result = []
    for group in groups.values():
        contribution = number(group.get("contribution_estimate")) or 0.0
        result.append({
            **group,
            "contribution_ratio": contribution / total if total > 0 else None,
        })
    result.sort(key=lambda item: (
        -(number(item.get("contribution_estimate")) or 0.0),
        -(integer(item.get("voice_count")) or 0),
        integer(item.get("instrument_index")) or 0,
        integer(item.get("sample_index")) or 0,
    ))
    return result[:8]


def frame_for_diagnostic(item: dict[str, Any], rows_by_source: dict[tuple[Any, Any, Any], dict[str, Any]]) -> int | None:
    frame = integer(item.get("scheduled_frame", item.get("absolute_frame")))
    if frame is not None:
        return frame
    row = rows_by_source.get(source_key(nested_dict(item.get("source"))))
    return int(row["_start_frame"]) if row else None


def same_frame_groups(
    window: dict[str, Any],
    events: list[dict[str, Any]],
    diagnostics: dict[str, Any],
    step_updates: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    start = int(window["start_frame"])
    end = int(window["end_frame"])
    by_frame: dict[int, list[dict[str, Any]]] = {}
    events_by_index = {
        event.get("event_index"): event
        for event in events
        if event.get("event_index") is not None
    }

    def add(frame: int | None, category: str, item: dict[str, Any]) -> None:
        if frame is None or not (start <= frame < end):
            return
        by_frame.setdefault(frame, []).append({
            "category": category,
            "channel_index": item.get("channel_index", item.get("source_channel_index")),
            "event_index": item.get("event_index", item.get("new_event_index", item.get("active_event_index"))),
            "source": nested_dict(item.get("source")),
        })

    for event in events:
        add(integer(event.get("_start_frame")), "note_trigger", event)
    for update in nested_list(diagnostics.get("volume_panning_state_updates")):
        if isinstance(update, dict):
            add(integer(update.get("scheduled_frame")), "gain_pan_update", update)
    for update in step_updates:
        add(integer(update.get("_frame")), "sample_step_update", update)
    for replacement in nested_list(nested_dict(diagnostics.get("same_channel_voice_lifetime")).get("replacement_events")):
        if isinstance(replacement, dict):
            source_event = events_by_index.get(replacement.get("new_event_index"))
            add(
                integer(replacement.get("replacement_frame")),
                "same_channel_replacement",
                {**replacement, "source": nested_dict(source_event.get("source")) if source_event else {}},
            )
    for retrigger in nested_list(diagnostics.get("retrigger_effects")):
        if isinstance(retrigger, dict):
            for frame in nested_list(retrigger.get("retrigger_frames")):
                add(integer(frame), "retrigger", retrigger)

    result = []
    for frame, items in sorted(by_frame.items()):
        if len(items) > 1:
            result.append({"frame": frame, "events": items})
    return result


def build_summary(
    diagnostics: dict[str, Any],
    windows: list[dict[str, Any]],
    *,
    label: str,
    sample_rate: int,
) -> dict[str, Any]:
    rows = normalize_rows(diagnostics)
    events = normalize_events(diagnostics, sample_rate)
    rows_by_source = {source_key(nested_dict(row.get("source"))): row for row in rows}
    step_updates = collect_step_updates(diagnostics)
    replacements = [
        item for item in nested_list(nested_dict(diagnostics.get("same_channel_voice_lifetime")).get("replacement_events"))
        if isinstance(item, dict)
    ]

    window_summaries = []
    for window in windows:
        start = int(window["start_frame"])
        end = int(window["end_frame"])
        overlapping_rows = [row for row in rows if overlaps(row["_start_frame"], row["_end_frame"], start, end)]
        overlapping_source_keys = {source_key(nested_dict(row.get("source"))) for row in overlapping_rows}
        active_events = [
            event for event in events
            if overlaps(event["_start_frame"], event.get("_active_end_frame", event["_end_frame"]), start, end)
        ]
        window_step_updates = [update for update in step_updates if start <= int(update["_frame"]) < end]

        def diagnostic_frame_in_window(item: dict[str, Any]) -> bool:
            frame = integer(item.get("scheduled_frame", item.get("absolute_frame")))
            return frame is not None and start <= frame < end

        tone = [
            annotate_effect_diagnostic(item, "3xx tone portamento")
            for item in nested_list(diagnostics.get("tone_portamento_effects"))
            if isinstance(item, dict)
            and (
                source_key(nested_dict(item.get("source"))) in overlapping_source_keys
                or any(diagnostic_frame_in_window(update) for update in nested_list(item.get("step_updates")) if isinstance(update, dict))
            )
        ]
        offsets = [
            item for item in nested_list(diagnostics.get("sample_offset_effects"))
            if isinstance(item, dict) and source_key(nested_dict(item.get("source"))) in overlapping_source_keys
        ]
        gain_pan = [
            item for item in nested_list(diagnostics.get("volume_panning_state_updates"))
            if isinstance(item, dict) and diagnostic_frame_in_window(item)
        ]
        traversal = [
            item for item in nested_list(diagnostics.get("pattern_traversal_timing_effects", diagnostics.get("traversal_effects")))
            if isinstance(item, dict) and source_key(nested_dict(item.get("source"))) in overlapping_source_keys
        ]
        window_replacements = [
            item for item in replacements
            if start <= (integer(item.get("replacement_frame")) or -1) < end
        ]
        active_voice_summaries = [
            summarize_voice(event, window, step_updates, gain_pan, replacements)
            for event in active_events
        ]
        window_summaries.append({
            **window,
            "row_tick_ranges": [
                {
                    "source": nested_dict(row.get("source")),
                    "synthetic_row": row.get("synthetic_row"),
                    "frame_range": [row["_start_frame"], row["_end_frame"]],
                    "effective_speed": row.get("effective_speed"),
                    "effective_bpm": row.get("effective_bpm"),
                    **row_tick_range(row, start, end),
                }
                for row in overlapping_rows
            ],
            "active_voice_count": len(active_events),
            "active_voices": active_voice_summaries,
            "dominant_sample_groups": dominant_sample_groups(active_voice_summaries),
            "loop_crossing_count": sum(
                voice["loop_crossings_in_window"]
                for voice in active_voice_summaries
            ),
            "source_end_crossing_count": sum(
                voice["source_end_crossings_in_window"]
                for voice in active_voice_summaries
            ),
            "steady_state_loop_interior_voice_count": sum(
                1 for voice in active_voice_summaries
                if voice.get("steady_state_loop_interior")
            ),
            "sample_step_update_count": len(window_step_updates),
            "sample_step_updates": window_step_updates,
            "tone_portamento": tone,
            "sample_offsets": offsets,
            "note_replacements": window_replacements,
            "replacement_ramp_count": sum(
                1 for replacement in replacements
                if overlaps(
                    integer(replacement.get("replacement_frame")) or -1,
                    integer(replacement.get("completion_frame")) or (integer(replacement.get("replacement_frame")) or -1) + 1,
                    start,
                    end,
                )
            ),
            "gain_pan_update_count": len(gain_pan),
            "gain_pan_updates": gain_pan[:16],
            "traversal_events": traversal,
            "same_frame_event_groups": same_frame_groups(window, active_events, diagnostics, step_updates),
        })

    return {
        "schema_version": 2,
        "tool": "scripts/focused-window-voice-timeline.py",
        "local_only": True,
        "label": label,
        "sample_rate": sample_rate,
        "window_count": len(window_summaries),
        "windows": window_summaries,
    }


def source_label(source: dict[str, Any]) -> str:
    if not source:
        return "source unavailable"
    return f"order {source.get('order')} pattern {source.get('pattern')} row {source.get('row')}"


def format_float(value: Any) -> str:
    parsed = number(value)
    return "unavailable" if parsed is None else f"{parsed:.6f}"


def format_compact_float(value: Any) -> str:
    parsed = number(value)
    return "unavailable" if parsed is None else f"{parsed:.6f}".rstrip("0").rstrip(".")


def format_transition(before: Any, after: Any) -> str:
    return f"{format_compact_float(before)}->{format_compact_float(after)}"


def format_target(period: Any, step: Any) -> str:
    return f"{format_compact_float(period)}/{format_compact_float(step)}"


def format_bool(value: Any) -> str:
    if isinstance(value, bool):
        return "yes" if value else "no"
    return "unavailable"


def format_percent(value: Any) -> str:
    parsed = number(value)
    return "unavailable" if parsed is None else f"{parsed * 100.0:.1f}%"


def render_sample_step_updates_markdown(lines: list[str], updates: list[dict[str, Any]]) -> None:
    if not updates:
        return
    lines.extend([
        "",
        "### Sample-Step Updates",
        "",
        "| Effect | Source | Channel | Tick | Frame | Period | Step | Target | Reached |",
        "| --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |",
    ])
    for update in updates:
        lines.append(
            f"| {update.get('label', 'sample-step update')} | {source_label(nested_dict(update.get('source')))} | "
            f"{update.get('channel_index')} | {update.get('synthetic_tick')} | {update.get('_frame', update.get('scheduled_frame'))} | "
            f"{format_transition(update.get('linear_period_before'), update.get('linear_period_after'))} | "
            f"{format_transition(update.get('playback_step_before'), update.get('playback_step_after'))} | "
            f"{format_target(update.get('target_linear_period'), update.get('target_playback_step'))} | "
            f"{format_bool(update.get('reached_target'))} |"
        )


def render_tone_portamento_markdown(lines: list[str], rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    lines.extend([
        "",
        "### Tone-Portamento Rows",
        "",
        "| Source | Channel | Status | Target Note | Target Period | Target Step | Step Frames |",
        "| --- | ---: | --- | --- | ---: | ---: | --- |",
    ])
    for row in rows:
        step_frames = [
            str(integer(first_present(value_from(update, "scheduled_frame"), value_from(update, "absolute_frame"))))
            for update in nested_list(row.get("step_updates"))
            if isinstance(update, dict)
            and integer(first_present(value_from(update, "scheduled_frame"), value_from(update, "absolute_frame"))) is not None
        ]
        lines.append(
            f"| {source_label(nested_dict(row.get('source')))} | {row.get('channel_index')} | "
            f"{row.get('status', row.get('current_status', 'unavailable'))} | "
            f"{row.get('target_note_text', row.get('target_note', 'unavailable'))} | "
            f"{format_compact_float(row.get('target_linear_period'))} | "
            f"{format_compact_float(row.get('target_playback_step', row.get('target_step')))} | "
            f"{', '.join(step_frames) if step_frames else 'none'} |"
        )


def render_markdown(summary: dict[str, Any]) -> str:
    lines = [
        f"# Focused Window Voice Timeline: {summary['label']}",
        "",
        f"- Sample rate: {summary['sample_rate']} Hz",
        f"- Windows: {summary['window_count']}",
    ]
    for window in summary["windows"]:
        lines.extend([
            "",
            f"## Window {window['rank']}: {window['start_seconds']:.6f}-{window['end_seconds']:.6f} s",
            "",
            f"- Frames: {window['start_frame']}-{window['end_frame']}",
            f"- Rows overlapped: {len(window['row_tick_ranges'])}",
            f"- Active voices: {window['active_voice_count']}",
            f"- Loop-boundary crossings: {window['loop_crossing_count']}",
            f"- Source-end crossings: {window['source_end_crossing_count']}",
            f"- Steady-state loop-interior voices: {window['steady_state_loop_interior_voice_count']}",
            f"- Sample-step updates: {window['sample_step_update_count']}",
            f"- Tone-portamento rows: {len(window['tone_portamento'])}",
            f"- Sample-offset rows: {len(window['sample_offsets'])}",
            f"- Note replacements: {len(window['note_replacements'])}",
            f"- Replacement ramps: {window['replacement_ramp_count']}",
            f"- Gain/pan updates: {window['gain_pan_update_count']}",
            f"- Same-frame groups: {len(window['same_frame_event_groups'])}",
            "",
            "| Row | Frames | Ticks | Timing |",
            "| --- | --- | --- | --- |",
        ])
        for row in window["row_tick_ranges"]:
            ticks = f"{row.get('tick_start')}..{row.get('tick_end')}"
            lines.append(
                f"| {source_label(row['source'])} | {row['frame_range'][0]}-{row['frame_range'][1]} | "
                f"{ticks} | speed {row.get('effective_speed')} BPM {row.get('effective_bpm')} |"
            )
        lines.extend(["", "| Channel | Note | Instrument/Sample | Loop | Step | Source Position | Loop Phase | Steady | Gain/Pan | Contribution | Updates |"])
        lines.append("| ---: | --- | --- | --- | ---: | --- | --- | --- | --- | ---: | --- |")
        for voice in window["active_voices"]:
            loop = (
                f"{voice.get('loop_mode')} "
                f"{voice.get('loop_start_frame')}-{voice.get('loop_end_frame')}"
            )
            source = (
                f"{format_float(voice['source_position_start'].get('position'))}->"
                f"{format_float(voice['source_position_end'].get('position'))}"
            )
            phase = f"{format_percent(voice.get('loop_phase_start'))}->{format_percent(voice.get('loop_phase_end'))}"
            updates = (
                f"step {voice.get('sample_step_update_count')}, "
                f"gain {voice.get('gain_pan_update_count')}, "
                f"ramp {voice.get('replacement_ramp_count')}"
            )
            lines.append(
                f"| {voice.get('channel_index')} | {voice.get('note_text', voice.get('note'))} | "
                f"{voice.get('instrument_index')}/{voice.get('sample_index')} | {loop} | "
                f"{format_float(voice.get('playback_step'))} | {source} | "
                f"{phase} | {format_bool(voice.get('steady_state_loop_interior'))} | "
                f"{format_float(voice.get('gain'))}/{format_float(voice.get('pan'))} | "
                f"{format_float(voice.get('contribution_estimate'))} | {updates} |"
            )
        if window["dominant_sample_groups"]:
            lines.extend(["", "### Dominant Sample Groups", ""])
            for group in window["dominant_sample_groups"]:
                lines.append(
                    "- "
                    f"inst/sample {group.get('instrument_index')}/{group.get('sample_index')} "
                    f"voices {group.get('voice_count')} steady {group.get('steady_state_voice_count')} "
                    f"loop-boundary crossings {group.get('loop_crossing_count')} "
                    f"source-end crossings {group.get('source_end_crossing_count')} "
                    f"score {format_float(group.get('contribution_estimate'))} "
                    f"ratio {format_percent(group.get('contribution_ratio'))} "
                    f"loop {group.get('loop_mode')} {group.get('loop_start_frame')}-{group.get('loop_end_frame')}"
                )
        render_sample_step_updates_markdown(lines, window["sample_step_updates"])
        render_tone_portamento_markdown(lines, window["tone_portamento"])
    return "\n".join(lines) + "\n"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diagnostics-json", required=True, type=Path)
    parser.add_argument("--comparison-json", type=Path)
    parser.add_argument("--window", action="append", default=[], help="Focused START:END seconds; repeatable.")
    parser.add_argument("--label", default="local-xm")
    parser.add_argument("--format", choices=("json", "markdown"), default="markdown")
    parser.add_argument("--output", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        diagnostics = load_json(args.diagnostics_json, "diagnostics")
        comparison = load_json(args.comparison_json, "comparison") if args.comparison_json else None
        sample_rate = sample_rate_from(diagnostics, comparison)
        windows = [parse_window(value, sample_rate, index) for index, value in enumerate(args.window, start=1)]
        if not windows and comparison is not None:
            windows = windows_from_comparison(comparison, sample_rate)
        if not windows:
            raise TimelineError("pass at least one --window or --comparison-json with worst windows")
        summary = build_summary(diagnostics, windows, label=args.label, sample_rate=sample_rate)
    except TimelineError as error:
        print(f"focused-window-voice-timeline: {error}", file=sys.stderr)
        return 1

    output = json.dumps(summary, indent=2, sort_keys=True) if args.format == "json" else render_markdown(summary)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
        print(f"Focused timeline report: {args.output}")
    else:
        print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
