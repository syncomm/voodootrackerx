#!/usr/bin/env python3
"""Summarize local runtime C mixer JSONL traces for A/B diagnostics."""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


FLOAT_DIGITS = 9
UPDATE_ACTION_PREFIX = "c_mixer_update_"
GAIN_PAN_UPDATE_ACTIONS = {
    "c_mixer_update_gain_pan_applied",
    "c_mixer_update_gain_pan_step_applied",
}
STEP_UPDATE_ACTIONS = {
    "c_mixer_update_step_applied",
    "c_mixer_update_gain_pan_step_applied",
}
TRANSPORT_CLEAR_REASONS = {
    "transport_stop",
    "transport_pause",
    "transport_stop_all",
    "debug_seek",
    "runtime_c_mixer_backend_reset",
    "runtime_c_mixer_engine_start_failed",
}


class TraceSummaryError(Exception):
    """A user-facing runtime trace summary error."""


def rounded(value: float) -> float:
    return round(float(value), FLOAT_DIGITS)


def number(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return float(value)
    return None


def integer(value: Any) -> int | None:
    value_number = number(value)
    if value_number is None:
        return None
    return int(value_number)


def load_trace(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        raise TraceSummaryError(f"missing runtime C mixer trace: {path}")
    if not path.is_file():
        raise TraceSummaryError(f"runtime C mixer trace is not a file: {path}")

    events: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as error:
            raise TraceSummaryError(
                f"malformed runtime C mixer trace: {path}: line {line_number}: {error.msg}"
            ) from error
        if not isinstance(event, dict):
            raise TraceSummaryError(
                f"malformed runtime C mixer trace: {path}: line {line_number}: expected JSON object"
            )
        events.append(event)
    return events


def max_numeric(events: list[dict[str, Any]], *fields: str) -> float | None:
    values = []
    for event in events:
        for field in fields:
            value = number(event.get(field))
            if value is not None:
                values.append(value)
    return max(values) if values else None


def numeric_range(events: list[dict[str, Any]], *fields: str) -> dict[str, int | None]:
    values: list[int] = []
    for event in events:
        for field in fields:
            value = integer(event.get(field))
            if value is not None:
                values.append(value)
    return {
        "min": min(values) if values else None,
        "max": max(values) if values else None,
    }


def average(values: list[int]) -> float | None:
    if not values:
        return None
    return rounded(sum(values) / len(values))


def median(values: list[int]) -> float | None:
    if not values:
        return None
    return rounded(statistics.median(values))


def effect_type(event: dict[str, Any]) -> str | None:
    value = event.get("effectType")
    if isinstance(value, str):
        return value.upper()
    return None


def effect_param(event: dict[str, Any]) -> str | None:
    value = event.get("effectParam")
    if isinstance(value, str):
        return value.upper()
    return None


def is_extended_effect(event: dict[str, Any], high_nibble: str) -> bool:
    parameter = effect_param(event)
    return effect_type(event) == "0E" and parameter is not None and parameter.startswith(high_nibble)


def is_update_action(event: dict[str, Any]) -> bool:
    action = event.get("runtimeAction")
    return isinstance(action, str) and action.startswith(UPDATE_ACTION_PREFIX)


def is_row_transition_event(event: dict[str, Any]) -> bool:
    action = event.get("runtimeAction")
    return (
        isinstance(action, str)
        and action.startswith("row_transition")
    ) or event.get("runtimeEventCategory") == "row_transition"


def is_planned_adapter_event_application(event: dict[str, Any]) -> bool:
    if is_row_transition_event(event):
        return False
    if integer(event.get("plannedEventID")) is not None:
        return True
    if event.get("adapterEventCategory") is not None and integer(event.get("eventAppliedFrame")) is not None:
        return True
    return (
        event.get("runtimeEventSource") == "offline_adapter_plan"
        and integer(event.get("eventAppliedFrame")) is not None
        and (
            integer(event.get("plannedRuntimeFrame")) is not None
            or integer(event.get("plannedEventFrame")) is not None
        )
    )


def count_if(events: list[dict[str, Any]], predicate: Any) -> int:
    return sum(1 for event in events if predicate(event))


def context_key(event: dict[str, Any]) -> tuple[Any, Any, Any, Any]:
    return (
        event.get("orderIndex"),
        event.get("patternIndex"),
        event.get("rowIndex"),
        event.get("tickInRow"),
    )


def context_dict_from_key(key: tuple[Any, Any, Any, Any]) -> dict[str, Any]:
    return {
        "order_index": key[0],
        "pattern_index": key[1],
        "row_index": key[2],
        "tick_in_row": key[3],
    }


def event_context_dict(event: dict[str, Any]) -> dict[str, Any]:
    return context_dict_from_key(context_key(event))


def c_mixer_sample_time_frame(event: dict[str, Any]) -> int | None:
    frame = integer(event.get("cMixerSampleTimeFrame"))
    if frame is not None:
        return frame
    return integer(event.get("currentFrame"))


def c_mixer_rendered_frames(event: dict[str, Any]) -> int | None:
    frame = integer(event.get("cMixerRenderedFrames"))
    if frame is not None:
        return frame
    frame = integer(event.get("currentFrame"))
    if frame is not None:
        return frame
    return integer(event.get("runtimeRenderedFrameCount"))


def playback_engine_position(event: dict[str, Any]) -> tuple[Any, Any, Any, Any]:
    return (
        event.get("playbackEngineOrderIndex", event.get("orderIndex")),
        event.get("playbackEnginePatternIndex", event.get("patternIndex")),
        event.get("playbackEngineRowIndex", event.get("rowIndex")),
        event.get("playbackEngineTickInRow", event.get("tickInRow")),
    )


def c_mixer_position(event: dict[str, Any]) -> tuple[Any, Any, Any, Any]:
    return (
        event.get("cMixerSampleTimeOrderIndex"),
        event.get("cMixerSampleTimePatternIndex"),
        event.get("cMixerSampleTimeRowIndex"),
        event.get("cMixerSampleTimeTickInRow"),
    )


def positions_are_known(event: dict[str, Any]) -> bool:
    playback = playback_engine_position(event)
    c_mixer = c_mixer_position(event)
    return all(item is not None for item in playback[:3]) and all(item is not None for item in c_mixer[:3])


def position_mismatch(event: dict[str, Any]) -> bool | None:
    explicit = event.get("playbackEngineToCMixerPositionMismatch")
    if isinstance(explicit, bool):
        return explicit
    if not positions_are_known(event):
        return None
    playback = playback_engine_position(event)
    c_mixer = c_mixer_position(event)
    playback_tick = playback[3] if playback[3] is not None else 0
    c_mixer_tick = c_mixer[3] if c_mixer[3] is not None else 0
    return playback[:3] != c_mixer[:3] or playback_tick != c_mixer_tick


def top_event_bursts(events: list[dict[str, Any]], limit: int = 5) -> list[dict[str, Any]]:
    grouped: dict[tuple[Any, Any, Any, Any], Counter[str]] = defaultdict(Counter)
    interesting_prefixes = ("c_mixer_",)
    interesting_actions = {"note_trigger", "channel_stop", "key_off", "row_transition"}
    for event in events:
        action = event.get("runtimeAction")
        if not isinstance(action, str):
            continue
        if not (action.startswith(interesting_prefixes) or action in interesting_actions):
            continue
        grouped[context_key(event)][action] += 1

    bursts = []
    for key, actions in grouped.items():
        total = sum(actions.values())
        bursts.append({
            "order_index": key[0],
            "pattern_index": key[1],
            "row_index": key[2],
            "tick_in_row": key[3],
            "event_count": total,
            "actions": dict(sorted(actions.items())),
        })
    bursts.sort(key=lambda item: (-item["event_count"], item["order_index"] or -1, item["row_index"] or -1, item["tick_in_row"] or -1))
    return bursts[:limit]


def event_timing_delta_rows(events: list[dict[str, Any]], limit: int = 10) -> list[dict[str, Any]]:
    rows = []
    for event in events:
        delta_value = integer(event.get("plannedVsAppliedDelta"))
        if delta_value is None:
            delta_value = integer(event.get("eventFrameDelta"))
        if delta_value is None:
            continue
        row = event_context_dict(event)
        row.update({
            "runtime_action": event.get("runtimeAction"),
            "runtime_event_category": event.get("runtimeEventCategory"),
            "adapter_event_category": event.get("adapterEventCategory"),
            "planned_event_id": integer(event.get("plannedEventID")),
            "planned_event_frame": integer(event.get("plannedEventFrame")),
            "planned_runtime_frame": integer(event.get("plannedRuntimeFrame")),
            "runtime_application_frame": integer(event.get("runtimeApplicationFrame")),
            "event_applied_frame": integer(event.get("eventAppliedFrame")),
            "in_callback_offset": integer(event.get("inCallbackOffset")),
            "event_frame_delta": delta_value,
            "planned_vs_applied_delta": delta_value,
            "event_application_timing": event.get("eventApplicationTiming"),
            "same_frame_burst_size": integer(event.get("sameFrameBurstSize")),
            "callback_index": integer(event.get("callbackIndex")),
            "callback_start_frame": integer(event.get("callbackStartFrame")),
            "callback_end_frame": integer(event.get("callbackEndFrame")),
        })
        rows.append(row)
    rows.sort(
        key=lambda item: (
            -abs(item["event_frame_delta"]),
            item["order_index"] or -1,
            item["row_index"] or -1,
            item["tick_in_row"] or -1,
            item["planned_event_id"] or -1,
        )
    )
    return rows[:limit]


def callback_boundary_events(events: list[dict[str, Any]], limit: int = 10) -> list[dict[str, Any]]:
    rows = [
        event for event in events
        if event.get("eventApplicationTiming") == "callback_start"
        and (
            integer(event.get("plannedVsAppliedDelta"))
            if integer(event.get("plannedVsAppliedDelta")) is not None
            else integer(event.get("eventFrameDelta"))
        ) not in (None, 0)
    ]
    return event_timing_delta_rows(rows, limit=limit)


def top_same_frame_event_bursts(events: list[dict[str, Any]], limit: int = 10) -> list[dict[str, Any]]:
    grouped: dict[int, dict[str, Any]] = {}
    for event in events:
        runtime_frame = integer(event.get("eventAppliedFrame"))
        if runtime_frame is None:
            runtime_frame = integer(event.get("runtimeApplicationFrame"))
        action = event.get("runtimeAction")
        if runtime_frame is None or not isinstance(action, str):
            continue
        if not (action.startswith("c_mixer_") or action.startswith("row_transition")):
            continue
        entry = grouped.setdefault(runtime_frame, {
            "runtime_application_frame": runtime_frame,
            "event_count": 0,
            "actions": Counter(),
            "categories": Counter(),
            "contexts": Counter(),
        })
        entry["event_count"] += 1
        entry["actions"][action] += 1
        category = event.get("runtimeEventCategory") or event.get("adapterEventCategory") or "unknown"
        entry["categories"][str(category)] += 1
        entry["contexts"][context_key(event)] += 1

    bursts = []
    for entry in grouped.values():
        contexts = [
            {
                **context_dict_from_key(key),
                "event_count": count,
            }
            for key, count in entry["contexts"].most_common(3)
        ]
        bursts.append({
            "runtime_application_frame": entry["runtime_application_frame"],
            "event_count": entry["event_count"],
            "actions": dict(sorted(entry["actions"].items())),
            "categories": dict(sorted(entry["categories"].items())),
            "top_contexts": contexts,
        })
    bursts.sort(key=lambda item: (-item["event_count"], item["runtime_application_frame"]))
    return bursts[:limit]


def top_transition_bursts(events: list[dict[str, Any]], limit: int = 10) -> list[dict[str, Any]]:
    counts_by_context: dict[tuple[Any, Any, Any, Any], Counter[str]] = defaultdict(Counter)
    for event in events:
        action = event.get("runtimeAction")
        if not isinstance(action, str):
            continue
        if action.startswith("row_transition"):
            continue
        if not (action.startswith("c_mixer_") or action in {"note_trigger", "channel_stop", "key_off"}):
            continue
        counts_by_context[context_key(event)][action] += 1

    bursts = []
    for event in events:
        if event.get("runtimeAction") != "row_transition_after_events":
            continue
        key = context_key(event)
        actions = counts_by_context.get(key, Counter())
        event_count = sum(actions.values())
        burst = event_context_dict(event)
        burst.update({
            "event_count": event_count,
            "actions": dict(sorted(actions.items())),
            "transition_runtime_frame": integer(event.get("transitionRuntimeFrame")),
            "planned_runtime_frame": integer(event.get("plannedRuntimeFrame")),
            "event_frame_delta": integer(event.get("eventFrameDelta")),
            "active_voice_count_before": integer(event.get("activeVoiceCountBefore")),
            "active_voice_count_after": integer(event.get("activeVoiceCountAfter")),
            "loaded_voice_count_before": integer(event.get("loadedVoiceCountBefore")),
            "loaded_voice_count_after": integer(event.get("loadedVoiceCountAfter")),
            "replacement_ramp_count": integer(event.get("transitionReplacementRampCount")),
            "update_count": integer(event.get("transitionUpdateCount")),
        })
        bursts.append(burst)
    bursts.sort(
        key=lambda item: (
            -item["event_count"],
            -(item["replacement_ramp_count"] or 0),
            -(item["update_count"] or 0),
            item["order_index"] or -1,
            item["row_index"] or -1,
        )
    )
    return bursts[:limit]


def sample_time_position_mismatches(events: list[dict[str, Any]], limit: int = 10) -> list[dict[str, Any]]:
    rows = []
    for index, event in enumerate(events):
        mismatch = position_mismatch(event)
        frame_delta = integer(event.get("playbackEngineToCMixerFrameDelta"))
        if frame_delta is None:
            frame_delta = integer(event.get("eventFrameDelta"))
        if mismatch is not True and (frame_delta is None or frame_delta == 0):
            continue
        playback = playback_engine_position(event)
        c_mixer = c_mixer_position(event)
        row = {
            "trace_index": index,
            "runtime_action": event.get("runtimeAction"),
            "playback_engine_order_index": playback[0],
            "playback_engine_pattern_index": playback[1],
            "playback_engine_row_index": playback[2],
            "playback_engine_tick_in_row": playback[3],
            "c_mixer_order_index": c_mixer[0],
            "c_mixer_pattern_index": c_mixer[1],
            "c_mixer_row_index": c_mixer[2],
            "c_mixer_tick_in_row": c_mixer[3],
            "c_mixer_sample_time_frame": c_mixer_sample_time_frame(event),
            "c_mixer_rendered_frames": c_mixer_rendered_frames(event),
            "c_mixer_position_status": event.get("cMixerSampleTimePositionStatus"),
            "frame_delta": frame_delta,
            "abs_frame_delta": abs(frame_delta) if frame_delta is not None else None,
            "position_mismatch": bool(mismatch),
            "row_transition_delta_category": event.get("rowTransitionDeltaCategory"),
        }
        rows.append(row)
    rows.sort(
        key=lambda item: (
            -(item["abs_frame_delta"] if item["abs_frame_delta"] is not None else -1),
            item["trace_index"],
        )
    )
    return rows[:limit]


def first_suspicious_position_mismatch(events: list[dict[str, Any]]) -> dict[str, Any] | None:
    rows = sample_time_position_mismatches(events, limit=len(events))
    if not rows:
        return None
    return sorted(rows, key=lambda item: item["trace_index"])[0]


def c_mixer_sample_time_is_monotonic(events: list[dict[str, Any]]) -> bool:
    previous: int | None = None
    observed = False
    for event in events:
        frame = c_mixer_rendered_frames(event)
        if frame is None:
            continue
        observed = True
        if previous is not None and frame < previous:
            return False
        previous = frame
    return True


def c_mixer_sample_time_frame_observed(events: list[dict[str, Any]]) -> bool:
    return any(c_mixer_rendered_frames(event) is not None for event in events)


def position_diverges_over_time(events: list[dict[str, Any]]) -> bool:
    rows = sorted(sample_time_position_mismatches(events, limit=len(events)), key=lambda item: item["trace_index"])
    deltas = [
        row["abs_frame_delta"]
        for row in rows
        if isinstance(row.get("abs_frame_delta"), int)
    ]
    if len(deltas) < 2:
        return False
    return deltas[-1] > deltas[0] and max(deltas) > 0


def largest_mismatch_order_row_ranges(
    mismatch_rows: list[dict[str, Any]],
    limit: int = 5,
) -> list[dict[str, Any]]:
    grouped: dict[Any, dict[str, Any]] = {}
    for row in mismatch_rows:
        order_index = row.get("playback_engine_order_index")
        if order_index is None:
            order_index = row.get("c_mixer_order_index")
        entry = grouped.setdefault(order_index, {
            "playback_engine_order_index": order_index,
            "playback_engine_min_row_index": None,
            "playback_engine_max_row_index": None,
            "c_mixer_min_row_index": None,
            "c_mixer_max_row_index": None,
            "max_abs_frame_delta": 0,
            "mismatch_count": 0,
        })
        for key, field in (
            ("playback_engine_min_row_index", "playback_engine_row_index"),
            ("playback_engine_max_row_index", "playback_engine_row_index"),
            ("c_mixer_min_row_index", "c_mixer_row_index"),
            ("c_mixer_max_row_index", "c_mixer_row_index"),
        ):
            value = row.get(field)
            if not isinstance(value, int):
                continue
            if entry[key] is None:
                entry[key] = value
            elif key.endswith("min_row_index"):
                entry[key] = min(entry[key], value)
            else:
                entry[key] = max(entry[key], value)
        entry["max_abs_frame_delta"] = max(entry["max_abs_frame_delta"], row.get("abs_frame_delta") or 0)
        entry["mismatch_count"] += 1
    rows = list(grouped.values())
    rows.sort(key=lambda item: (-item["max_abs_frame_delta"], item["playback_engine_order_index"] or -1))
    return rows[:limit]


def top_suspicious_positions(
    timing_deltas: list[dict[str, Any]],
    same_frame_bursts: list[dict[str, Any]],
    transition_bursts: list[dict[str, Any]],
    limit: int = 10,
) -> list[dict[str, Any]]:
    by_context: dict[tuple[Any, Any, Any, Any], dict[str, Any]] = {}

    def entry_for(context: dict[str, Any]) -> dict[str, Any]:
        key = (
            context.get("order_index"),
            context.get("pattern_index"),
            context.get("row_index"),
            context.get("tick_in_row"),
        )
        return by_context.setdefault(key, {
            **context_dict_from_key(key),
            "max_abs_event_frame_delta": 0,
            "same_frame_event_count": 0,
            "transition_event_count": 0,
            "replacement_ramp_count": 0,
            "update_count": 0,
            "reasons": set(),
        })

    for row in timing_deltas:
        entry = entry_for(row)
        delta_abs = abs(row["event_frame_delta"])
        entry["max_abs_event_frame_delta"] = max(entry["max_abs_event_frame_delta"], delta_abs)
        if delta_abs > 0:
            entry["reasons"].add("event_frame_delta")
        if row.get("event_application_timing") == "callback_start":
            entry["reasons"].add("callback_boundary")

    for burst in same_frame_bursts:
        for context in burst.get("top_contexts", []):
            entry = entry_for(context)
            entry["same_frame_event_count"] = max(entry["same_frame_event_count"], burst["event_count"])
            if burst["event_count"] > 1:
                entry["reasons"].add("same_frame_burst")

    for burst in transition_bursts:
        entry = entry_for(burst)
        entry["transition_event_count"] = max(entry["transition_event_count"], burst["event_count"])
        entry["replacement_ramp_count"] = max(entry["replacement_ramp_count"], burst["replacement_ramp_count"] or 0)
        entry["update_count"] = max(entry["update_count"], burst["update_count"] or 0)
        if burst["event_count"] > 0:
            entry["reasons"].add("transition_burst")

    rows = []
    for entry in by_context.values():
        score = (
            entry["max_abs_event_frame_delta"] * 10
            + entry["same_frame_event_count"]
            + entry["transition_event_count"]
            + entry["replacement_ramp_count"]
            + entry["update_count"]
        )
        if score <= 0:
            continue
        row = dict(entry)
        row["score"] = score
        row["reasons"] = sorted(row["reasons"])
        rows.append(row)
    rows.sort(key=lambda item: (-item["score"], item["order_index"] or -1, item["row_index"] or -1, item["tick_in_row"] or -1))
    return rows[:limit]


def summarize_update_parity(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    categories = [
        (
            "gain_pan_state_updates",
            lambda event: event.get("runtimeAction") in GAIN_PAN_UPDATE_ACTIONS
            or event.get("runtimeAction") == "c_mixer_update_stored_channel_state",
        ),
        (
            "step_pitch_updates",
            lambda event: event.get("runtimeAction") in STEP_UPDATE_ACTIONS
            or event.get("updateType") in {"step", "combined"},
        ),
        (
            "hxy_global_volume_updates",
            lambda event: is_update_action(event) and effect_type(event) == "11",
        ),
        (
            "ecx_note_cut",
            lambda event: is_extended_effect(event, "C")
            and event.get("runtimeAction") in {"channel_stop", "c_mixer_stop_channel"},
        ),
        (
            "edx_note_delay",
            lambda event: is_extended_effect(event, "D")
            and event.get("runtimeAction") in {"note_trigger", "c_mixer_add_voice"},
        ),
        (
            "e9x_retrigger",
            lambda event: is_extended_effect(event, "9")
            and event.get("runtimeAction") in {"note_trigger", "c_mixer_add_voice"},
        ),
        (
            "portamento_1xx_2xx_3xx_updates",
            lambda event: is_update_action(event)
            and effect_type(event) in {"01", "02", "03"}
            and event.get("updateType") in {"step", "combined"},
        ),
    ]
    return [
        {
            "category": name,
            "runtime_event_count": count_if(events, predicate),
            "observed_in_runtime_trace": count_if(events, predicate) > 0,
        }
        for name, predicate in categories
    ]


def build_summary(events: list[dict[str, Any]], trace_path: Path | None = None) -> dict[str, Any]:
    action_counts = Counter(
        event.get("runtimeAction") for event in events if isinstance(event.get("runtimeAction"), str)
    )
    update_disposition_counts = Counter(
        event.get("updateDisposition") for event in events if isinstance(event.get("updateDisposition"), str)
    )
    update_type_counts = Counter(
        event.get("updateType") for event in events if isinstance(event.get("updateType"), str)
    )
    hard_stop_reasons = Counter(
        str(event.get("reason") or "unknown")
        for event in events
        if event.get("runtimeAction") == "c_mixer_stop_channel"
    )
    deferred_updates = [
        event for event in events
        if isinstance(event.get("updateDisposition"), str)
        and event["updateDisposition"].startswith("update_deferred")
    ]
    deferred_categories = Counter(
        f"{event.get('updateDisposition')}:{event.get('updateType') or 'none'}:{event.get('reason') or 'unknown'}"
        for event in deferred_updates
    )

    clear_all_normal = [
        event for event in events
        if event.get("runtimeAction") == "c_mixer_clear_all"
        and str(event.get("reason") or "unknown") not in TRANSPORT_CLEAR_REASONS
    ]
    hard_replacement_stops = [
        event for event in events
        if event.get("runtimeAction") == "c_mixer_stop_channel"
        and "replacement" in str(event.get("reason") or "")
    ]
    ramped_replacements = [
        event for event in events
        if event.get("runtimeAction") == "c_mixer_stop_channel_ramped"
    ]
    ramped_coverage = "not_observed"
    if ramped_replacements or hard_replacement_stops:
        ramped_coverage = "yes" if ramped_replacements and not hard_replacement_stops else "no"

    output_peak = max_numeric(events, "outputPeak", "lastOutputPeak") or 0.0
    clipping_count = int(max_numeric(events, "clippingSampleCount") or 0)
    underrun_count = int(max_numeric(events, "underrunCount") or 0)
    zero_fill_count = int(max_numeric(events, "zeroFillCount") or 0)
    failed_render_count = int(max_numeric(events, "failedRenderCount") or 0)
    bursts = top_event_bursts(events)
    planned_adapter_event_applications = [
        event for event in events if is_planned_adapter_event_application(event)
    ]
    row_transition_events = [event for event in events if is_row_transition_event(event)]
    timing_deltas = event_timing_delta_rows(planned_adapter_event_applications)
    row_transition_timing_deltas = event_timing_delta_rows(row_transition_events)
    callback_events = callback_boundary_events(planned_adapter_event_applications)
    same_frame_bursts = top_same_frame_event_bursts(events)
    transition_bursts = top_transition_bursts(events)
    suspicious_positions = top_suspicious_positions(timing_deltas, same_frame_bursts, transition_bursts)
    position_mismatches = sample_time_position_mismatches(events)
    first_position_mismatch = first_suspicious_position_mismatch(events)
    row_transition_delta_values = [
        abs(row["event_frame_delta"])
        for row in row_transition_timing_deltas
        if isinstance(row.get("event_frame_delta"), int)
    ]
    row_transition_delta_categories = Counter(
        str(event.get("rowTransitionDeltaCategory"))
        for event in row_transition_events
        if event.get("rowTransitionDeltaCategory") is not None
    )
    parity_categories = summarize_update_parity(events)
    max_abs_event_frame_delta = max((abs(row["event_frame_delta"]) for row in timing_deltas), default=0)
    max_row_transition_frame_delta = max(
        (abs(row["event_frame_delta"]) for row in row_transition_timing_deltas),
        default=0,
    )
    max_planned_vs_applied_delta = int(
        max_numeric(events, "maxPlannedVsAppliedDelta")
        or max_abs_event_frame_delta
    )
    applied_planned_event_counter = int(max_numeric(events, "appliedPlannedEventCount") or 0)
    exact_frame_applied_event_counter = int(max_numeric(events, "exactFrameAppliedEventCount") or 0)
    callback_boundary_applied_event_counter = int(max_numeric(events, "callbackBoundaryAppliedEventCount") or 0)
    late_planned_event_counter = int(max_numeric(events, "latePlannedEventCount") or 0)
    applied_planned_event_count = (
        applied_planned_event_counter
        if applied_planned_event_counter > 0
        else len(planned_adapter_event_applications)
    )
    exact_frame_applied_event_count = (
        exact_frame_applied_event_counter
        if exact_frame_applied_event_counter > 0
        else count_if(
            planned_adapter_event_applications,
            lambda event: event.get("eventApplicationTiming") == "exact_frame",
        )
    )
    callback_boundary_applied_event_count = max(
        callback_boundary_applied_event_counter,
        len(callback_events),
    )
    late_planned_event_count = (
        late_planned_event_counter
        if late_planned_event_counter > 0
        else count_if(
            planned_adapter_event_applications,
            lambda event: event.get("eventApplicationTiming") == "late",
        )
    )
    observed_adapter_plan = any(event.get("runtimeEventSource") == "offline_adapter_plan" for event in events)
    observed_sample_time_queue = any(
        event.get("inCallbackOffset") is not None
        or event.get("sameFrameBurstSize") is not None
        or event.get("appliedPlannedEventCount") is not None
        for event in events
    )

    suspicious_findings: list[str] = []
    if clipping_count > 0:
        suspicious_findings.append("runtime clipping/overrange remains after runtime gain")
    if underrun_count > 0 or zero_fill_count > 0 or failed_render_count > 0:
        suspicious_findings.append("runtime render underrun, zero-fill, or failure counters are nonzero")
    if hard_replacement_stops:
        suspicious_findings.append("at least one note replacement used c_mixer_stop_channel instead of c_mixer_stop_channel_ramped")
    if action_counts["c_mixer_stop_channel"] > 0:
        suspicious_findings.append("immediate c_mixer_stop_channel hard-stop events remain during playback")
    if clear_all_normal:
        suspicious_findings.append("c_mixer_clear_all appeared outside known transport/reset reasons")
    if deferred_updates:
        suspicious_findings.append("runtime update deferrals remain")
    if bursts and bursts[0]["event_count"] >= 24:
        suspicious_findings.append("large same-row/tick runtime event burst observed")
    if max_planned_vs_applied_delta > 0:
        suspicious_findings.append("planned-vs-applied event frame deltas observed")
    if callback_boundary_applied_event_count > 0:
        suspicious_findings.append("events applied at callback boundaries instead of planned frames")
    if late_planned_event_count > 0:
        suspicious_findings.append("late planned events observed")
    if same_frame_bursts and same_frame_bursts[0]["event_count"] >= 24:
        suspicious_findings.append("large same-frame runtime event burst observed")
    if transition_bursts and transition_bursts[0]["event_count"] >= 24:
        suspicious_findings.append("large order/row transition runtime event burst observed")
    if not c_mixer_sample_time_is_monotonic(events):
        suspicious_findings.append("C mixer sample-time frame counter moved backward")
    if position_mismatches:
        suspicious_findings.append("PlaybackEngine position and C mixer sample-time position mismatch observed")
    if position_diverges_over_time(events):
        suspicious_findings.append("PlaybackEngine position and C mixer sample-time position diverge over time")

    large_event_burst = bool(bursts and bursts[0]["event_count"] >= 24)
    large_same_frame_burst = bool(same_frame_bursts and same_frame_bursts[0]["event_count"] >= 24)
    has_sample_time_delta = (
        max_planned_vs_applied_delta > 0
        or callback_boundary_applied_event_count > 0
        or late_planned_event_count > 0
    )

    if hard_replacement_stops:
        recommended_next_pr = "Runtime C Mixer Hard Stop / Replacement Follow-Up"
    elif has_sample_time_delta:
        recommended_next_pr = "Runtime C Mixer Remaining Sample-Time Timing Gap Investigation"
    elif position_diverges_over_time(events):
        recommended_next_pr = "Runtime C Mixer Playback Follow Position Drift Investigation"
    elif position_mismatches:
        recommended_next_pr = "Runtime C Mixer Tracker-Follow Sample-Time Integration"
    elif large_same_frame_burst:
        recommended_next_pr = "Runtime C Mixer Same-Frame Event Burst Stabilization"
    elif deferred_updates or action_counts["c_mixer_stop_channel"] > 0 or large_event_burst:
        recommended_next_pr = "Runtime C Mixer Offline Adapter Event Stream Bridge"
    elif underrun_count > 0 or zero_fill_count > 0 or failed_render_count > 0:
        recommended_next_pr = "Runtime C Mixer Backend Stabilization / Stop-Start Robustness"
    elif clipping_count > 0:
        recommended_next_pr = "Runtime C Mixer Remaining Update Parity Fix"
    else:
        recommended_next_pr = "Runtime C Mixer Playback Follow / Sample-Time Position Bridge"

    return {
        "schema_version": 1,
        "tool": "scripts/summarize-runtime-c-mixer-trace.py",
        "trace": {"path_name": trace_path.name if trace_path else None},
        "event_count": len(events),
        "actions": dict(sorted(action_counts.items())),
        "health": {
            "peak": rounded(output_peak),
            "clipping_sample_count": clipping_count,
            "clipping_detected": clipping_count > 0 or any(event.get("clippingDetected") is True for event in events),
            "underrun_count": underrun_count,
            "zero_fill_count": zero_fill_count,
            "failed_render_count": failed_render_count,
        },
        "voices": {
            "active_voice_range": numeric_range(events, "activeVoiceCount", "activeVoiceCountBefore", "activeVoiceCountAfter"),
            "loaded_voice_range": numeric_range(events, "loadedVoiceCount", "loadedVoiceCountBefore", "loadedVoiceCountAfter"),
        },
        "stops": {
            "add_voice_events": action_counts["c_mixer_add_voice"],
            "ramped_replacement_stop_events": len(ramped_replacements),
            "ramped_replacement_voice_count": sum(integer(event.get("rampedVoiceCount")) or 0 for event in ramped_replacements),
            "immediate_hard_replacement_stop_events": len(hard_replacement_stops),
            "immediate_hard_stop_events": action_counts["c_mixer_stop_channel"],
            "immediate_hard_stop_reasons": dict(sorted(hard_stop_reasons.items())),
            "clear_all_events": action_counts["c_mixer_clear_all"],
            "clear_all_normal_playback_events": len(clear_all_normal),
            "ramped_replacement_covers_all_observed_replacement_stops": ramped_coverage,
        },
        "updates": {
            "applied_gain_pan_update_events": count_if(
                events,
                lambda event: event.get("runtimeAction") in GAIN_PAN_UPDATE_ACTIONS
                or (
                    event.get("updateDisposition") == "update_applied"
                    and event.get("updateType") in {"gain", "pan", "combined"}
                ),
            ),
            "applied_step_update_events": count_if(
                events,
                lambda event: event.get("runtimeAction") in STEP_UPDATE_ACTIONS
                or (
                    event.get("updateDisposition") == "update_applied"
                    and event.get("updateType") in {"step", "combined"}
                ),
            ),
            "suppressed_no_change_update_events": action_counts["c_mixer_update_suppressed_no_change"],
            "stored_channel_state_update_events": action_counts["c_mixer_update_stored_channel_state"],
            "update_dispositions": dict(sorted(update_disposition_counts.items())),
            "update_types": dict(sorted(update_type_counts.items())),
            "remaining_deferred_update_categories": dict(sorted(deferred_categories.items())),
        },
        "runtime_vs_offline_adapter_categories": parity_categories,
        "event_stream": {
            "runtime_driver": (
                "offline adapter plan applied by runtime sample-time render queue"
                if observed_adapter_plan and observed_sample_time_queue
                else "offline adapter plan consumed by PlaybackEngine tick clock"
                if observed_adapter_plan
                else "PlaybackEngine timer/control events"
            ),
            "offline_adapter_event_stream_observed": observed_adapter_plan,
            "sample_time_render_queue_observed": observed_sample_time_queue,
            "assessment": (
                "runtime trace applied planned offline-adapter events with callback-range and in-callback offset diagnostics"
                if observed_adapter_plan and observed_sample_time_queue
                else "runtime trace consumed planned offline-adapter events; inspect sample-time alignment fields for callback-boundary drift"
                if observed_adapter_plan
                else "runtime trace is driven by PlaybackEngine actions, not the richer bounded offline adapter event stream"
            ),
        },
        "event_bursts": bursts,
        "sample_time_alignment": {
            "max_abs_event_frame_delta": max_abs_event_frame_delta,
            "max_planned_vs_applied_delta": max_planned_vs_applied_delta,
            "max_row_transition_frame_delta": max_row_transition_frame_delta,
            "average_row_transition_frame_delta": average(row_transition_delta_values),
            "median_row_transition_frame_delta": median(row_transition_delta_values),
            "row_transition_delta_categories": dict(sorted(row_transition_delta_categories.items())),
            "applied_planned_event_count": applied_planned_event_count,
            "exact_frame_applied_event_count": exact_frame_applied_event_count,
            "callback_boundary_applied_event_count": callback_boundary_applied_event_count,
            "delayed_to_callback_boundary_count": callback_boundary_applied_event_count,
            "late_planned_event_count": late_planned_event_count,
            "c_mixer_sample_time_frame_observed": c_mixer_sample_time_frame_observed(events),
            "c_mixer_sample_time_monotonic": c_mixer_sample_time_is_monotonic(events),
            "playback_engine_c_mixer_position_diverges_over_time": position_diverges_over_time(events),
            "largest_playback_engine_vs_c_mixer_mismatch": position_mismatches[0] if position_mismatches else None,
            "largest_playback_engine_vs_c_mixer_mismatches": position_mismatches,
            "first_suspicious_position_mismatch": first_position_mismatch,
            "largest_mismatch_order_row_ranges": largest_mismatch_order_row_ranges(position_mismatches),
            "largest_event_timing_deltas": timing_deltas,
            "row_transition_timing_deltas": row_transition_timing_deltas,
            "callback_boundary_event_count": len(callback_events),
            "callback_boundary_events": callback_events,
            "same_frame_event_bursts": same_frame_bursts,
            "order_row_transition_event_bursts": transition_bursts,
            "top_suspicious_positions": suspicious_positions,
        },
        "suspicious_findings": suspicious_findings,
        "recommended_next_pr": recommended_next_pr,
    }


def build_markdown(summary: dict[str, Any]) -> str:
    health = summary["health"]
    stops = summary["stops"]
    updates = summary["updates"]
    voices = summary["voices"]
    alignment = summary["sample_time_alignment"]
    lines = [
        "# Runtime C Mixer Trace Summary",
        "",
        f"- Events: {summary['event_count']}",
        f"- Peak: {health['peak']}",
        f"- Clipping samples: {health['clipping_sample_count']}",
        f"- Underruns / zero-fill / failed renders: {health['underrun_count']} / {health['zero_fill_count']} / {health['failed_render_count']}",
        f"- Add voice events: {stops['add_voice_events']}",
        f"- Ramped replacement stops: {stops['ramped_replacement_stop_events']} events, {stops['ramped_replacement_voice_count']} voices",
        f"- Immediate hard replacement stops: {stops['immediate_hard_replacement_stop_events']}",
        f"- Immediate hard channel stops: {stops['immediate_hard_stop_events']}",
        f"- Clear-all events outside transport/reset: {stops['clear_all_normal_playback_events']}",
        f"- Active voice range: {voices['active_voice_range']['min']}...{voices['active_voice_range']['max']}",
        f"- Loaded voice range: {voices['loaded_voice_range']['min']}...{voices['loaded_voice_range']['max']}",
        f"- Applied gain/pan updates: {updates['applied_gain_pan_update_events']}",
        f"- Applied step updates: {updates['applied_step_update_events']}",
        f"- Suppressed no-change updates: {updates['suppressed_no_change_update_events']}",
        f"- Stored channel-state updates: {updates['stored_channel_state_update_events']}",
        f"- Max planned event frame delta: {alignment['max_abs_event_frame_delta']}",
        f"- Max planned-vs-applied frame delta: {alignment['max_planned_vs_applied_delta']}",
        f"- Max row-transition frame delta: {alignment['max_row_transition_frame_delta']}",
        f"- Average row-transition frame delta: {alignment['average_row_transition_frame_delta']}",
        f"- Median row-transition frame delta: {alignment['median_row_transition_frame_delta']}",
        f"- C mixer sample-time position monotonic: {alignment['c_mixer_sample_time_monotonic']}",
        f"- PlaybackEngine/C mixer position diverges over time: {alignment['playback_engine_c_mixer_position_diverges_over_time']}",
        f"- Planned events applied at exact frames: {alignment['exact_frame_applied_event_count']}",
        f"- Planned events delayed to callback boundaries: {alignment['callback_boundary_applied_event_count']}",
        f"- Late planned events: {alignment['late_planned_event_count']}",
        "",
        "## Stop Paths",
        "",
        f"- Ramped replacements cover all observed replacement stops: {stops['ramped_replacement_covers_all_observed_replacement_stops']}",
    ]
    for reason, count in stops["immediate_hard_stop_reasons"].items():
        lines.append(f"- Hard stop reason `{reason}`: {count}")
    if not stops["immediate_hard_stop_reasons"]:
        lines.append("- Hard stop reasons: none")

    lines.extend(["", "## Runtime Update Categories", ""])
    for category in summary["runtime_vs_offline_adapter_categories"]:
        observed = "yes" if category["observed_in_runtime_trace"] else "no"
        lines.append(f"- {category['category']}: {category['runtime_event_count']} observed={observed}")

    lines.extend(["", "## Deferred Updates", ""])
    if updates["remaining_deferred_update_categories"]:
        for category, count in updates["remaining_deferred_update_categories"].items():
            lines.append(f"- `{category}`: {count}")
    else:
        lines.append("- None")

    lines.extend(["", "## Event Stream", ""])
    lines.append(f"- Runtime driver: {summary['event_stream']['runtime_driver']}")
    lines.append(f"- Offline adapter event stream observed: {summary['event_stream']['offline_adapter_event_stream_observed']}")
    lines.append(f"- Sample-time render queue observed: {summary['event_stream']['sample_time_render_queue_observed']}")
    lines.append(f"- Assessment: {summary['event_stream']['assessment']}")

    lines.extend(["", "## Event Bursts", ""])
    if summary["event_bursts"]:
        for burst in summary["event_bursts"]:
            context = f"order={burst['order_index']} pattern={burst['pattern_index']} row={burst['row_index']} tick={burst['tick_in_row']}"
            lines.append(f"- {context}: {burst['event_count']} events {burst['actions']}")
    else:
        lines.append("- None")

    lines.extend(["", "## Sample-Time Alignment", ""])
    if alignment["largest_event_timing_deltas"]:
        lines.append("- Largest planned event frame deltas:")
        for row in alignment["largest_event_timing_deltas"][:5]:
            context = f"order={row['order_index']} pattern={row['pattern_index']} row={row['row_index']} tick={row['tick_in_row']}"
            lines.append(
                f"- {context} action={row['runtime_action']} category={row['runtime_event_category']} "
                f"planned_runtime_frame={row['planned_runtime_frame']} event_applied_frame={row['event_applied_frame']} "
                f"in_callback_offset={row['in_callback_offset']} delta={row['planned_vs_applied_delta']} "
                f"timing={row['event_application_timing']} burst={row['same_frame_burst_size']}"
            )
    else:
        lines.append("- Largest planned event frame deltas: none")
    if alignment["row_transition_timing_deltas"]:
        lines.append("- Row-transition frame deltas:")
        for row in alignment["row_transition_timing_deltas"][:5]:
            context = f"order={row['order_index']} pattern={row['pattern_index']} row={row['row_index']} tick={row['tick_in_row']}"
            lines.append(
                f"- {context} action={row['runtime_action']} "
                f"planned_runtime_frame={row['planned_runtime_frame']} "
                f"runtime_application_frame={row['runtime_application_frame']} delta={row['event_frame_delta']}"
            )
    else:
        lines.append("- Row-transition frame deltas: none")
    if alignment["largest_playback_engine_vs_c_mixer_mismatches"]:
        lines.append("- PlaybackEngine vs C mixer sample-time mismatches:")
        for row in alignment["largest_playback_engine_vs_c_mixer_mismatches"][:5]:
            playback = (
                f"playback=order={row['playback_engine_order_index']} "
                f"pattern={row['playback_engine_pattern_index']} row={row['playback_engine_row_index']} "
                f"tick={row['playback_engine_tick_in_row']}"
            )
            c_mixer = (
                f"c_mixer=order={row['c_mixer_order_index']} pattern={row['c_mixer_pattern_index']} "
                f"row={row['c_mixer_row_index']} tick={row['c_mixer_tick_in_row']}"
            )
            lines.append(
                f"- {playback} {c_mixer} frame={row['c_mixer_sample_time_frame']} "
                f"delta={row['frame_delta']} category={row['row_transition_delta_category']}"
            )
    else:
        lines.append("- PlaybackEngine vs C mixer sample-time mismatches: none")
    if alignment["same_frame_event_bursts"]:
        lines.append("- Same-frame event bursts:")
        for burst in alignment["same_frame_event_bursts"][:5]:
            lines.append(
                f"- frame={burst['runtime_application_frame']}: {burst['event_count']} events "
                f"actions={burst['actions']} categories={burst['categories']}"
            )
    else:
        lines.append("- Same-frame event bursts: none")
    if alignment["order_row_transition_event_bursts"]:
        lines.append("- Order/row transition event bursts:")
        for burst in alignment["order_row_transition_event_bursts"][:5]:
            context = f"order={burst['order_index']} pattern={burst['pattern_index']} row={burst['row_index']} tick={burst['tick_in_row']}"
            lines.append(
                f"- {context}: {burst['event_count']} events replacement_ramps={burst['replacement_ramp_count']} "
                f"updates={burst['update_count']} voices={burst['active_voice_count_before']}->{burst['active_voice_count_after']}"
            )
    else:
        lines.append("- Order/row transition event bursts: none")
    if alignment["top_suspicious_positions"]:
        lines.append("- Top suspicious positions:")
        for row in alignment["top_suspicious_positions"][:5]:
            context = f"order={row['order_index']} pattern={row['pattern_index']} row={row['row_index']} tick={row['tick_in_row']}"
            lines.append(
                f"- {context}: score={row['score']} reasons={row['reasons']} "
                f"max_delta={row['max_abs_event_frame_delta']} same_frame_events={row['same_frame_event_count']} "
                f"transition_events={row['transition_event_count']}"
            )
    else:
        lines.append("- Top suspicious positions: none")

    lines.extend(["", "## Suspicious Findings", ""])
    if summary["suspicious_findings"]:
        lines.extend(f"- {finding}" for finding in summary["suspicious_findings"])
    else:
        lines.append("- None")
    lines.extend(["", f"Recommended next PR: {summary['recommended_next_pr']}", ""])
    return "\n".join(lines)


def write_json(path: Path, summary: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="Runtime C mixer JSONL trace path")
    parser.add_argument("--json", dest="json_report", type=Path, help="Optional JSON summary output path")
    parser.add_argument("--markdown", type=Path, help="Optional Markdown summary output path")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        events = load_trace(args.trace)
        summary = build_summary(events, trace_path=args.trace)
    except TraceSummaryError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    markdown = build_markdown(summary)
    if args.json_report:
        write_json(args.json_report, summary)
    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text(markdown, encoding="utf-8")
    if not args.json_report and not args.markdown:
        print(markdown, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
