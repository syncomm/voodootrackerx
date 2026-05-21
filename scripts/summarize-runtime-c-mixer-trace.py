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
POSITION_DIVERGENCE_FRAME_THRESHOLD = 1
PUBLISHED_FOLLOW_POSITION_FRAME_TOLERANCE = 512
PUBLISHED_FOLLOW_POSITION_ROW_TOLERANCE = 1
TRANSIENT_CORRELATION_FRAME_WINDOW = 64
UPDATE_ACTION_PREFIX = "c_mixer_update_"
GAIN_PAN_UPDATE_ACTIONS = {
    "c_mixer_update_gain_pan_applied",
    "c_mixer_update_gain_pan_step_applied",
}
STEP_UPDATE_ACTIONS = {
    "c_mixer_update_step_applied",
    "c_mixer_update_gain_pan_step_applied",
}
EPSILON_UPDATE_FIELDS = (
    ("gain", "gainUpdateStatus", "gainDelta", "gainBefore", "gainRequested"),
    ("pan", "panUpdateStatus", "panDelta", "panBefore", "panRequested"),
    ("step", "sampleStepUpdateStatus", "sampleStepDelta", "sampleStepBefore", "sampleStepRequested"),
)
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


def rounded_optional(value: float | None) -> float | None:
    if value is None:
        return None
    return rounded(value)


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


def first_number(events: list[dict[str, Any]], field: str) -> float | None:
    for event in events:
        value = number(event.get(field))
        if value is not None:
            return value
    return None


def last_number(events: list[dict[str, Any]], field: str) -> float | None:
    for event in reversed(events):
        value = number(event.get(field))
        if value is not None:
            return value
    return None


def exact_integer(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and math.isfinite(value):
        return int(value)
    return None


def last_exact_integer(events: list[dict[str, Any]], field: str) -> int | None:
    for event in reversed(events):
        value = exact_integer(event.get(field))
        if value is not None:
            return value
    return None


def first_string(events: list[dict[str, Any]], field: str) -> str | None:
    for event in events:
        value = event.get(field)
        if isinstance(value, str) and value:
            return value
    return None


def last_string(events: list[dict[str, Any]], field: str) -> str | None:
    for event in reversed(events):
        value = event.get(field)
        if isinstance(value, str) and value:
            return value
    return None


def first_bool(events: list[dict[str, Any]], field: str) -> bool | None:
    for event in events:
        value = event.get(field)
        if isinstance(value, bool):
            return value
    return None


def last_bool(events: list[dict[str, Any]], field: str) -> bool | None:
    for event in reversed(events):
        value = event.get(field)
        if isinstance(value, bool):
            return value
    return None


def average(values: list[int]) -> float | None:
    if not values:
        return None
    return rounded(sum(values) / len(values))


def median(values: list[int]) -> float | None:
    if not values:
        return None
    return rounded(statistics.median(values))


def time_delta_ms(frame_delta: int | None, sample_rate: float | None) -> float | None:
    if frame_delta is None or sample_rate is None or sample_rate <= 0:
        return None
    return rounded((frame_delta / sample_rate) * 1000.0)


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


def is_transport_reset_event(event: dict[str, Any]) -> bool:
    action = event.get("runtimeAction")
    reason = str(event.get("reason") or "")
    if reason in TRANSPORT_CLEAR_REASONS:
        return True
    return action in {"backend_reset", "backend_start_failed"}


def is_in_callback_sample_time_event(event: dict[str, Any], frame: int | None = None) -> bool:
    if integer(event.get("inCallbackOffset")) is None:
        return False
    callback_start = integer(event.get("callbackStartFrame"))
    callback_end = integer(event.get("callbackEndFrame"))
    if callback_start is None or callback_end is None:
        return False
    event_frame = frame if frame is not None else c_mixer_rendered_frames(event)
    return event_frame is not None and callback_start <= event_frame <= callback_end


def sample_rate(event: dict[str, Any]) -> float | None:
    value = number(event.get("sampleRate"))
    if value is None or value <= 0:
        return None
    return value


def context_from_event(event: dict[str, Any]) -> dict[str, Any]:
    return {
        "order_index": event.get("orderIndex", event.get("plannedSourceOrderIndex")),
        "pattern_index": event.get("patternIndex", event.get("plannedSourcePatternIndex")),
        "row_index": event.get("rowIndex", event.get("plannedSourceRowIndex")),
        "tick_in_row": event.get("tickInRow", event.get("plannedSourceTickInRow")),
    }


def event_frame_for_correlation(event: dict[str, Any]) -> int | None:
    for field in (
        "eventAppliedFrame",
        "runtimeApplicationFrame",
        "lastOutputDiscontinuityRuntimeFrame",
        "cMixerSampleTimeFrame",
        "currentFrame",
        "cMixerRenderedFrames",
        "runtimeRenderedFrameCount",
    ):
        value = integer(event.get(field))
        if value is not None:
            return value
    return None


def nearest_context_for_frame(events: list[dict[str, Any]], runtime_frame: int | None) -> dict[str, Any] | None:
    if runtime_frame is None:
        return None
    best: tuple[int, int, dict[str, Any]] | None = None
    for index, event in enumerate(events):
        frame = event_frame_for_correlation(event)
        if frame is None:
            continue
        context = context_from_event(event)
        if all(value is None for value in context.values()):
            continue
        delta = abs(frame - runtime_frame)
        candidate = (delta, index, context)
        if best is None or candidate[:2] < best[:2]:
            best = candidate
    if best is None:
        return None
    context = dict(best[2])
    context["context_frame_delta"] = best[0]
    return context


def discontinuity_threshold_counts(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    counts: dict[float, int] = {}
    for event in events:
        raw_counts = event.get("outputDiscontinuityThresholdCounts")
        if not isinstance(raw_counts, list):
            continue
        for item in raw_counts:
            if not isinstance(item, dict):
                continue
            threshold = number(item.get("threshold"))
            count = integer(item.get("count"))
            if threshold is None or count is None:
                continue
            key = rounded(threshold)
            counts[key] = max(counts.get(key, 0), count)
    if not counts:
        threshold = max_numeric(events, "outputDiscontinuityThreshold")
        count = int(max_numeric(events, "outputDiscontinuityCount") or 0)
        if threshold is not None:
            counts[rounded(threshold)] = count
    return [
        {"threshold": threshold, "count": counts[threshold]}
        for threshold in sorted(counts)
    ]


def top_output_sample_jumps(events: list[dict[str, Any]], limit: int = 10) -> list[dict[str, Any]]:
    rows_by_key: dict[tuple[int, int, float], dict[str, Any]] = {}
    for event in events:
        raw_rows = event.get("topOutputAdjacentSampleJumps")
        if not isinstance(raw_rows, list):
            continue
        for item in raw_rows:
            if not isinstance(item, dict):
                continue
            sample_jump = number(item.get("sampleJump"))
            runtime_frame = integer(item.get("runtimeFrame"))
            channel_index = integer(item.get("channelIndex"))
            if sample_jump is None or runtime_frame is None or channel_index is None:
                continue
            key = (runtime_frame, channel_index, rounded(sample_jump))
            rows_by_key.setdefault(key, {
                "sample_jump": rounded(sample_jump),
                "runtime_frame": runtime_frame,
                "callback_index": integer(item.get("callbackIndex")),
                "frame_offset": integer(item.get("frameOffset")),
                "channel_index": channel_index,
            })
    rows = list(rows_by_key.values())
    rows.sort(key=lambda item: (-item["sample_jump"], item["runtime_frame"], item["channel_index"]))
    rows = rows[:limit]
    for row in rows:
        context = nearest_context_for_frame(events, row["runtime_frame"])
        if context is not None:
            row.update(context)
    return rows


def top_output_peaks(events: list[dict[str, Any]], limit: int = 10) -> list[dict[str, Any]]:
    rows_by_key: dict[tuple[int, int, float], dict[str, Any]] = {}
    for event in events:
        raw_rows = event.get("topOutputPeaks")
        if not isinstance(raw_rows, list):
            continue
        for item in raw_rows:
            if not isinstance(item, dict):
                continue
            peak = number(item.get("peak"))
            runtime_frame = integer(item.get("runtimeFrame"))
            channel_index = integer(item.get("channelIndex"))
            if peak is None or runtime_frame is None or channel_index is None:
                continue
            key = (runtime_frame, channel_index, rounded(peak))
            rows_by_key.setdefault(key, {
                "peak": rounded(peak),
                "runtime_frame": runtime_frame,
                "callback_index": integer(item.get("callbackIndex")),
                "frame_offset": integer(item.get("frameOffset")),
                "channel_index": channel_index,
                "above_0_95": peak > 0.95,
                "above_1_0": peak > 1.0,
            })
    rows = list(rows_by_key.values())
    rows.sort(key=lambda item: (-item["peak"], item["runtime_frame"], item["channel_index"]))
    rows = rows[:limit]
    for row in rows:
        context = nearest_context_for_frame(events, row["runtime_frame"])
        if context is not None:
            row.update(context)
    return rows


def nearest_transient(
    runtime_frame: int | None,
    rows: list[dict[str, Any]],
    value_field: str,
    window: int = TRANSIENT_CORRELATION_FRAME_WINDOW,
) -> dict[str, Any] | None:
    if runtime_frame is None:
        return None
    candidates = []
    for row in rows:
        frame = row.get("runtime_frame")
        if not isinstance(frame, int):
            continue
        delta = abs(frame - runtime_frame)
        if delta <= window:
            candidates.append((delta, -float(row.get(value_field) or 0), frame, row))
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[:3])
    result = dict(candidates[0][3])
    result["burst_frame_delta"] = candidates[0][0]
    return result


def attach_nearby_transients_to_bursts(
    bursts: list[dict[str, Any]],
    jumps: list[dict[str, Any]],
    peaks: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    rows = []
    for burst in bursts:
        row = dict(burst)
        frame = integer(row.get("runtime_application_frame"))
        row["nearest_top_jump"] = nearest_transient(frame, jumps, "sample_jump")
        row["nearest_top_peak"] = nearest_transient(frame, peaks, "peak")
        rows.append(row)
    return rows


def epsilon_suppressed_fields(event: dict[str, Any]) -> list[str]:
    return [
        name
        for name, status_field, *_ in EPSILON_UPDATE_FIELDS
        if event.get(status_field) == "suppressed_epsilon"
    ]


def epsilon_applied_fields(event: dict[str, Any]) -> list[str]:
    return [
        name
        for name, status_field, *_ in EPSILON_UPDATE_FIELDS
        if event.get(status_field) == "applied"
    ]


def epsilon_suppressed_update_rows(
    events: list[dict[str, Any]],
    jumps: list[dict[str, Any]],
    peaks: list[dict[str, Any]],
    limit: int = 10,
) -> list[dict[str, Any]]:
    rows = []
    for index, event in enumerate(events):
        suppressed_fields = epsilon_suppressed_fields(event)
        if not suppressed_fields:
            continue
        frame = event_frame_for_correlation(event)
        field_deltas = {}
        signed_deltas = {}
        max_abs_delta = 0.0
        for name, _, delta_field, before_field, requested_field in EPSILON_UPDATE_FIELDS:
            delta = number(event.get(delta_field))
            if delta is not None:
                field_deltas[name] = rounded(delta)
                if name in suppressed_fields:
                    max_abs_delta = max(max_abs_delta, abs(delta))
            before = number(event.get(before_field))
            requested = number(event.get(requested_field))
            if before is not None and requested is not None:
                signed_deltas[name] = rounded(requested - before)
        row = context_from_event(event)
        row.update({
            "trace_index": index,
            "runtime_action": event.get("runtimeAction"),
            "runtime_frame": frame,
            "update_disposition": event.get("updateDisposition"),
            "update_type": event.get("updateType"),
            "update_epsilon": number(event.get("updateEpsilon")),
            "suppressed_fields": suppressed_fields,
            "applied_fields": epsilon_applied_fields(event),
            "field_deltas": field_deltas,
            "signed_deltas": signed_deltas,
            "max_abs_delta": rounded(max_abs_delta),
            "nearest_top_jump": nearest_transient(frame, jumps, "sample_jump"),
            "nearest_top_peak": nearest_transient(frame, peaks, "peak"),
        })
        rows.append(row)
    rows.sort(key=lambda item: (-item["max_abs_delta"], item["trace_index"]))
    return rows[:limit]


def epsilon_suppression_profile(
    events: list[dict[str, Any]],
    jumps: list[dict[str, Any]],
    peaks: list[dict[str, Any]],
) -> dict[str, Any]:
    rows = epsilon_suppressed_update_rows(events, jumps, peaks, limit=len(events))
    field_counts: Counter[str] = Counter()
    field_total_abs_delta: Counter[str] = Counter()
    field_signed_delta: Counter[str] = Counter()
    fully_suppressed_count = 0
    partial_update_count = 0
    near_transient_count = 0
    for row in rows:
        for field in row["suppressed_fields"]:
            field_counts[field] += 1
            field_total_abs_delta[field] += abs(float(row["field_deltas"].get(field) or 0))
            field_signed_delta[field] += float(row["signed_deltas"].get(field) or 0)
        if row["update_disposition"] == "update_suppressed_no_change" and not row["applied_fields"]:
            fully_suppressed_count += 1
        if row["applied_fields"]:
            partial_update_count += 1
        if row["nearest_top_jump"] is not None or row["nearest_top_peak"] is not None:
            near_transient_count += 1

    if not rows:
        assessment = "not_observed"
    elif partial_update_count > 0:
        assessment = "suppressed_fields_held_while_other_fields_applied"
    else:
        assessment = "fully_suppressed_no_runtime_state_motion"

    return {
        "epsilon_values_observed": sorted({
            rounded(value)
            for event in events
            for value in [number(event.get("updateEpsilon")), number(event.get("runtimeUpdateEpsilon"))]
            if value is not None
        }),
        "runtime_update_epsilon_policy_counts": dict(sorted(Counter(
            str(event.get("runtimeUpdateEpsilonPolicy"))
            for event in events
            if event.get("runtimeUpdateEpsilonPolicy") is not None
        ).items())),
        "runtime_update_epsilon_configuration_warnings": dict(sorted(Counter(
            str(event.get("runtimeUpdateEpsilonConfigurationWarning"))
            for event in events
            if event.get("runtimeUpdateEpsilonConfigurationWarning") is not None
        ).items())),
        "suppressed_update_event_count": len(rows),
        "suppressed_field_counts": dict(sorted(field_counts.items())),
        "suppressed_field_total_abs_delta": {
            field: rounded(total)
            for field, total in sorted(field_total_abs_delta.items())
        },
        "suppressed_field_signed_delta_sum": {
            field: rounded(total)
            for field, total in sorted(field_signed_delta.items())
        },
        "fully_suppressed_no_change_event_count": fully_suppressed_count,
        "partial_update_after_epsilon_filter_event_count": partial_update_count,
        "suppressed_update_near_top_transient_count": near_transient_count,
        "motion_assessment": assessment,
        "top_epsilon_suppressed_updates": rows[:10],
    }


def likely_correlation_category(
    clipping_count: int,
    overrange_count: int,
    top_peaks: list[dict[str, Any]],
    top_jumps: list[dict[str, Any]],
    same_frame_bursts: list[dict[str, Any]],
    ramped_replacements: list[dict[str, Any]],
    ramping_out_voice_count: int,
    ramp_down_completion_count: int,
    abrupt_ramp_down_stop_count: int,
) -> str:
    if clipping_count > 0 or overrange_count > 0 or any(row.get("above_1_0") for row in top_peaks):
        return "peak/clip"
    for burst in same_frame_bursts:
        frame = integer(burst.get("runtime_application_frame"))
        if frame is None:
            continue
        near_jump = nearest_transient(frame, top_jumps, "sample_jump")
        if near_jump is None:
            continue
        categories = set(str(key) for key in burst.get("categories", {}).keys())
        categories.update(str(key) for key in burst.get("event_categories", {}).keys())
        categories.update(str(category) for category in burst.get("explicit_event_categories", []))
        if "replacement_stop_ramp" in categories:
            return "replacement ramp burst"
        return "event burst"
    if abrupt_ramp_down_stop_count > 0 or ramping_out_voice_count > 0 or ramp_down_completion_count > 0:
        return "voice cleanup"
    if ramped_replacements:
        return "replacement ramp burst"
    return "unknown"


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


def published_follow_position(event: dict[str, Any]) -> tuple[Any, Any, Any, Any]:
    return (
        event.get("publishedPlaybackFollowOrderIndex"),
        event.get("publishedPlaybackFollowPatternIndex"),
        event.get("publishedPlaybackFollowRowIndex"),
        event.get("publishedPlaybackFollowTickInRow"),
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


def playback_clock_relation(frame_delta: int | None) -> str:
    if frame_delta is None:
        return "unknown"
    if frame_delta > POSITION_DIVERGENCE_FRAME_THRESHOLD:
        return "c_mixer_ahead_of_playback_engine"
    if frame_delta < -POSITION_DIVERGENCE_FRAME_THRESHOLD:
        return "c_mixer_behind_playback_engine"
    return "aligned"


def published_follow_c_mixer_position_delta_row(
    index: int,
    event: dict[str, Any],
) -> dict[str, Any] | None:
    frame_delta = integer(event.get("publishedPlaybackFollowToCMixerFrameDelta"))
    if frame_delta is None:
        c_mixer_frame = integer(event.get("cMixerSampleTimeFrame"))
        published_frame = integer(event.get("publishedPlaybackFollowSampleTimeFrame"))
        if c_mixer_frame is not None and published_frame is not None:
            frame_delta = c_mixer_frame - published_frame
    if frame_delta is None:
        return None
    playback = playback_engine_position(event)
    published = published_follow_position(event)
    c_mixer = c_mixer_position(event)
    rate = sample_rate(event)
    return {
        "trace_index": index,
        "runtime_action": event.get("runtimeAction"),
        "published_position_source": event.get("publishedPlaybackFollowPositionSource"),
        "playback_engine_order_index": playback[0],
        "playback_engine_pattern_index": playback[1],
        "playback_engine_row_index": playback[2],
        "playback_engine_tick_in_row": playback[3],
        "published_order_index": published[0],
        "published_pattern_index": published[1],
        "published_row_index": published[2],
        "published_tick_in_row": published[3],
        "published_sample_time_frame": integer(event.get("publishedPlaybackFollowSampleTimeFrame")),
        "published_position_status": event.get("publishedPlaybackFollowPositionStatus"),
        "published_synthetic_row": integer(event.get("publishedPlaybackFollowSyntheticRow")),
        "c_mixer_order_index": c_mixer[0],
        "c_mixer_pattern_index": c_mixer[1],
        "c_mixer_row_index": c_mixer[2],
        "c_mixer_tick_in_row": c_mixer[3],
        "c_mixer_sample_time_frame": c_mixer_sample_time_frame(event),
        "c_mixer_position_status": event.get("cMixerSampleTimePositionStatus"),
        "sample_rate": rate,
        "frame_delta": frame_delta,
        "abs_frame_delta": abs(frame_delta),
        "row_delta": integer(event.get("publishedPlaybackFollowToCMixerRowDelta")),
        "playback_engine_to_published_frame_delta": integer(event.get("playbackEngineToPublishedPlaybackFollowFrameDelta")),
        "playback_engine_to_published_row_delta": integer(event.get("playbackEngineToPublishedPlaybackFollowRowDelta")),
        "time_delta_ms": time_delta_ms(frame_delta, rate),
        "published_clock_relation": playback_clock_relation(frame_delta),
    }


def published_follow_c_mixer_position_delta_rows(
    events: list[dict[str, Any]],
    limit: int | None = 10,
) -> list[dict[str, Any]]:
    rows = []
    for index, event in enumerate(events):
        if is_transport_reset_event(event):
            continue
        row = published_follow_c_mixer_position_delta_row(index, event)
        if row is not None:
            rows.append(row)
    if limit is None:
        return rows
    return rows[:limit]


def largest_published_follow_c_mixer_position_delta_rows(
    events: list[dict[str, Any]],
    limit: int = 10,
) -> list[dict[str, Any]]:
    rows = published_follow_c_mixer_position_delta_rows(events, limit=None)
    rows.sort(key=lambda item: (-item["abs_frame_delta"], item["trace_index"]))
    return rows[:limit]


def first_published_follow_divergence_above_threshold(
    events: list[dict[str, Any]],
    threshold: int = PUBLISHED_FOLLOW_POSITION_FRAME_TOLERANCE,
) -> dict[str, Any] | None:
    rows = published_follow_c_mixer_position_delta_rows(events, limit=None)
    for row in rows:
        if published_follow_divergent(row, threshold=threshold):
            return row
    return None


def published_follow_divergent(
    row: dict[str, Any],
    threshold: int = PUBLISHED_FOLLOW_POSITION_FRAME_TOLERANCE,
) -> bool:
    row_delta = row.get("row_delta")
    row_mismatch = (
        isinstance(row_delta, int)
        and abs(row_delta) > PUBLISHED_FOLLOW_POSITION_ROW_TOLERANCE
    )
    return row["abs_frame_delta"] > threshold or row_mismatch


def playback_engine_c_mixer_position_delta_row(
    index: int,
    event: dict[str, Any],
) -> dict[str, Any] | None:
    frame_delta = integer(event.get("playbackEngineToCMixerFrameDelta"))
    if frame_delta is None:
        return None
    playback = playback_engine_position(event)
    c_mixer = c_mixer_position(event)
    rate = sample_rate(event)
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
        "sample_rate": rate,
        "frame_delta": frame_delta,
        "abs_frame_delta": abs(frame_delta),
        "time_delta_ms": time_delta_ms(frame_delta, rate),
        "position_mismatch": bool(position_mismatch(event)),
        "playback_clock_relation": playback_clock_relation(frame_delta),
        "row_transition_delta_category": event.get("rowTransitionDeltaCategory"),
    }
    return row


def playback_engine_c_mixer_position_delta_rows(
    events: list[dict[str, Any]],
    include_zero: bool = True,
    include_transport_resets: bool = False,
    row_transitions_only: bool = True,
    limit: int | None = 10,
) -> list[dict[str, Any]]:
    rows = []
    for index, event in enumerate(events):
        if not include_transport_resets and is_transport_reset_event(event):
            continue
        if row_transitions_only and not is_row_transition_event(event):
            continue
        row = playback_engine_c_mixer_position_delta_row(index, event)
        if row is None:
            continue
        if include_zero or row["abs_frame_delta"] > 0 or row["position_mismatch"]:
            rows.append(row)
    if limit is None:
        return rows
    return rows[:limit]


def largest_playback_engine_c_mixer_position_delta_rows(
    events: list[dict[str, Any]],
    limit: int = 10,
) -> list[dict[str, Any]]:
    rows = playback_engine_c_mixer_position_delta_rows(events, include_zero=True, limit=None)
    rows.sort(key=lambda item: (-item["abs_frame_delta"], item["trace_index"]))
    return rows[:limit]


def first_position_divergence_above_threshold(
    events: list[dict[str, Any]],
    threshold: int = POSITION_DIVERGENCE_FRAME_THRESHOLD,
) -> dict[str, Any] | None:
    rows = playback_engine_c_mixer_position_delta_rows(events, include_zero=True, limit=None)
    for row in rows:
        if row["abs_frame_delta"] > threshold or row["position_mismatch"]:
            return row
    return None


def playback_engine_c_mixer_drift_profile(events: list[dict[str, Any]]) -> dict[str, Any]:
    rows = playback_engine_c_mixer_position_delta_rows(events, include_zero=True, limit=None)
    deltas = [
        row["frame_delta"]
        for row in rows
        if isinstance(row.get("frame_delta"), int)
    ]
    nonzero_deltas = [
        delta for delta in deltas
        if abs(delta) > POSITION_DIVERGENCE_FRAME_THRESHOLD
    ]
    if not deltas:
        return {
            "classification": "not_observed",
            "mostly_constant_offset": False,
            "accumulating": False,
            "delta_count": 0,
            "nonzero_delta_count": 0,
            "signed_delta_min": None,
            "signed_delta_max": None,
            "signed_delta_range": None,
            "constant_offset_tolerance_frames": None,
        }
    signed_delta_min = min(deltas)
    signed_delta_max = max(deltas)
    if not nonzero_deltas:
        return {
            "classification": "aligned",
            "mostly_constant_offset": False,
            "accumulating": False,
            "delta_count": len(deltas),
            "nonzero_delta_count": 0,
            "signed_delta_min": signed_delta_min,
            "signed_delta_max": signed_delta_max,
            "signed_delta_range": signed_delta_max - signed_delta_min,
            "constant_offset_tolerance_frames": 0,
        }

    absolute_nonzero = [abs(delta) for delta in nonzero_deltas]
    max_abs_delta = max(absolute_nonzero)
    tolerance = max(4, int(max_abs_delta * 0.05))
    absolute_range = max(absolute_nonzero) - min(absolute_nonzero)
    same_sign = all(delta > 0 for delta in nonzero_deltas) or all(delta < 0 for delta in nonzero_deltas)
    mostly_constant = same_sign and absolute_range <= tolerance
    accumulating = (
        len(absolute_nonzero) >= 2
        and not mostly_constant
        and absolute_nonzero[-1] > absolute_nonzero[0] + tolerance
        and all(
            current + tolerance >= previous
            for previous, current in zip(absolute_nonzero, absolute_nonzero[1:])
        )
    )
    if mostly_constant:
        classification = "mostly_constant_offset"
    elif accumulating:
        classification = "accumulating"
    else:
        classification = "mixed"
    return {
        "classification": classification,
        "mostly_constant_offset": mostly_constant,
        "accumulating": accumulating,
        "delta_count": len(deltas),
        "nonzero_delta_count": len(nonzero_deltas),
        "signed_delta_min": signed_delta_min,
        "signed_delta_max": signed_delta_max,
        "signed_delta_range": signed_delta_max - signed_delta_min,
        "constant_offset_tolerance_frames": tolerance,
    }


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


def event_timing_delta_rows(events: list[dict[str, Any]], limit: int | None = 10) -> list[dict[str, Any]]:
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
    if limit is None:
        return rows
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
            "event_categories": Counter(),
            "contexts": Counter(),
            "active_before": [],
            "active_after": [],
            "loaded_before": [],
            "loaded_after": [],
            "burst_ids": set(),
            "event_ordinals": set(),
            "explicit_categories": set(),
            "affected_channels": set(),
            "note_trigger_counts": [],
            "replacement_ramp_counts": [],
            "gain_pan_update_counts": [],
            "step_update_counts": [],
            "note_cut_counts": [],
            "key_off_counts": [],
            "global_volume_update_counts": [],
            "voices_entering_ramp_down": [],
            "voices_completing_ramp_down": [],
            "new_voices_started": [],
            "sustained_voices_carried": [],
            "at_order_start": False,
            "at_row_transition": False,
        })
        entry["event_count"] += 1
        entry["actions"][action] += 1
        category = event.get("runtimeEventCategory") or event.get("adapterEventCategory") or "unknown"
        entry["categories"][str(category)] += 1
        entry["event_categories"][normalized_burst_category(str(category))] += 1
        explicit_categories = event.get("sameFrameBurstCategories")
        if isinstance(explicit_categories, list):
            for explicit_category in explicit_categories:
                entry["explicit_categories"].add(normalized_burst_category(str(explicit_category)))
        explicit_channels = event.get("sameFrameBurstAffectedChannels")
        if isinstance(explicit_channels, list):
            for channel in explicit_channels:
                channel_index = integer(channel)
                if channel_index is not None:
                    entry["affected_channels"].add(channel_index)
        for field, target in (
            ("sameFrameBurstID", "burst_ids"),
            ("sameFrameBurstEventOrdinal", "event_ordinals"),
        ):
            value = integer(event.get(field))
            if value is not None:
                entry[target].add(value)
        for field, target in (
            ("sameFrameBurstNoteTriggerCount", "note_trigger_counts"),
            ("sameFrameBurstReplacementRampCount", "replacement_ramp_counts"),
            ("sameFrameBurstGainPanUpdateCount", "gain_pan_update_counts"),
            ("sameFrameBurstStepUpdateCount", "step_update_counts"),
            ("sameFrameBurstNoteCutCount", "note_cut_counts"),
            ("sameFrameBurstKeyOffCount", "key_off_counts"),
            ("sameFrameBurstGlobalVolumeUpdateCount", "global_volume_update_counts"),
            ("sameFrameBurstVoicesEnteringRampDown", "voices_entering_ramp_down"),
            ("sameFrameBurstVoicesCompletingRampDown", "voices_completing_ramp_down"),
            ("sameFrameBurstNewVoicesStarted", "new_voices_started"),
            ("sameFrameBurstSustainedVoicesCarried", "sustained_voices_carried"),
        ):
            value = integer(event.get(field))
            if value is not None:
                entry[target].append(value)
        if event.get("sameFrameBurstAtOrderStart") is True:
            entry["at_order_start"] = True
        if event.get("sameFrameBurstAtRowTransition") is True:
            entry["at_row_transition"] = True
        entry["contexts"][context_key(event)] += 1
        for field, target in (
            ("activeVoiceCountBefore", "active_before"),
            ("activeVoiceCountAfter", "active_after"),
            ("activeVoiceCount", "active_after"),
            ("loadedVoiceCountBefore", "loaded_before"),
            ("loadedVoiceCountAfter", "loaded_after"),
            ("loadedVoiceCount", "loaded_after"),
            ("sameFrameBurstActiveVoiceCountBefore", "active_before"),
            ("sameFrameBurstActiveVoiceCountAfter", "active_after"),
            ("sameFrameBurstLoadedVoiceCountBefore", "loaded_before"),
            ("sameFrameBurstLoadedVoiceCountAfter", "loaded_after"),
        ):
            value = integer(event.get(field))
            if value is not None:
                entry[target].append(value)

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
            "event_categories": dict(sorted(entry["event_categories"].items())),
            "explicit_event_categories": sorted(entry["explicit_categories"]),
            "same_frame_burst_id": min(entry["burst_ids"]) if entry["burst_ids"] else None,
            "same_frame_burst_event_ordinals": sorted(entry["event_ordinals"]),
            "affected_channels": sorted(entry["affected_channels"]),
            "note_trigger_count": max(entry["note_trigger_counts"], default=entry["event_categories"].get("note_trigger", 0)),
            "replacement_ramp_count": max(entry["replacement_ramp_counts"], default=entry["event_categories"].get("replacement_stop_ramp", 0)),
            "gain_pan_update_count": max(entry["gain_pan_update_counts"], default=entry["event_categories"].get("gain_pan_update", 0)),
            "step_update_count": max(entry["step_update_counts"], default=entry["event_categories"].get("step_update", 0)),
            "note_cut_count": max(entry["note_cut_counts"], default=entry["event_categories"].get("ecx_edx_e9x", 0)),
            "key_off_count": max(entry["key_off_counts"], default=entry["event_categories"].get("key_off_fadeout", 0)),
            "global_volume_update_count": max(entry["global_volume_update_counts"], default=entry["event_categories"].get("global_volume_update", 0)),
            "active_voice_count_before": min(entry["active_before"]) if entry["active_before"] else None,
            "active_voice_count_after": max(entry["active_after"]) if entry["active_after"] else None,
            "loaded_voice_count_before": min(entry["loaded_before"]) if entry["loaded_before"] else None,
            "loaded_voice_count_after": max(entry["loaded_after"]) if entry["loaded_after"] else None,
            "voices_entering_ramp_down": max(entry["voices_entering_ramp_down"], default=0),
            "voices_completing_ramp_down": max(entry["voices_completing_ramp_down"], default=0),
            "new_voices_started": max(entry["new_voices_started"], default=0),
            "sustained_voices_carried": max(entry["sustained_voices_carried"], default=0),
            "at_order_start": entry["at_order_start"],
            "at_row_transition": entry["at_row_transition"],
            "top_contexts": contexts,
        })
    bursts.sort(key=lambda item: (-item["event_count"], item["runtime_application_frame"]))
    return bursts[:limit]


def normalized_burst_category(category: str) -> str:
    aliases = {
        "step_pitch_update": "step_update",
        "hxy_global_volume": "global_volume_update",
        "hxy_global_volume_update": "global_volume_update",
        "key_off": "key_off_fadeout",
        "replacement": "replacement_stop_ramp",
    }
    return aliases.get(category, category)


def sustained_voice_transition_summary(events: list[dict[str, Any]], limit: int = 10) -> dict[str, Any]:
    non_update_actions = {
        "c_mixer_add_voice",
        "note_trigger",
        "c_mixer_stop_channel",
        "c_mixer_stop_channel_ramped",
        "channel_stop",
    }
    update_events = [
        event for event in events
        if (
            is_update_action(event)
            or event.get("adapterSustainedVoiceUpdate") is True
            or event.get("adapterEventCategory") in {"gain_pan_update", "step_update", "key_off_fadeout", "ecx_edx_e9x"}
        )
        and event.get("runtimeAction") not in non_update_actions
    ]
    order_start_updates = [
        event for event in update_events
        if event.get("sameFrameBurstAtOrderStart") is True
        or (
            integer(event.get("rowIndex")) == 0
            and integer(event.get("tickInRow")) == 0
        )
    ]
    sustained_updates = [
        event for event in update_events
        if event.get("adapterSustainedVoiceUpdate") is True
    ]
    retained_updates = [
        event for event in sustained_updates
        if event.get("adapterChannelAssociationRetained") is True
    ]
    lost_updates = [
        event for event in sustained_updates
        if event.get("adapterChannelAssociationRetained") is False
    ]
    missed_updates = [
        event for event in update_events
        if event.get("updateDisposition") in {
            "update_deferred_no_active_voice",
            "update_deferred_stale_after_stop",
            "update_stored_channel_state",
        }
        or (
            event.get("adapterActiveEventIndex") is not None
            and event.get("adapterCurrentEventIndexBefore") is None
        )
    ]

    order_start_channel_rows = []
    for event in order_start_updates[:limit]:
        row = event_context_dict(event)
        row.update({
            "runtime_action": event.get("runtimeAction"),
            "adapter_event_category": event.get("adapterEventCategory"),
            "runtime_event_category": event.get("runtimeEventCategory"),
            "channel_index": integer(event.get("channelIndex")),
            "event_applied_frame": integer(event.get("eventAppliedFrame")),
            "same_frame_burst_id": integer(event.get("sameFrameBurstID")),
            "same_frame_burst_event_ordinal": integer(event.get("sameFrameBurstEventOrdinal")),
            "same_frame_burst_size": integer(event.get("sameFrameBurstSize")),
            "adapter_active_event_index": integer(event.get("adapterActiveEventIndex")),
            "adapter_current_event_index_before": integer(event.get("adapterCurrentEventIndexBefore")),
            "adapter_current_event_index_after": integer(event.get("adapterCurrentEventIndexAfter")),
            "adapter_channel_association_retained": event.get("adapterChannelAssociationRetained"),
            "adapter_sustained_voice_update": event.get("adapterSustainedVoiceUpdate"),
            "update_disposition": event.get("updateDisposition"),
        })
        order_start_channel_rows.append(row)

    return {
        "update_event_count": len(update_events),
        "order_start_update_event_count": len(order_start_updates),
        "sustained_update_event_count": len(sustained_updates),
        "association_retained_count": len(retained_updates),
        "association_lost_count": len(lost_updates),
        "missed_or_stored_update_count": len(missed_updates),
        "update_without_note_applied_count": count_if(
            update_events,
            lambda event: event.get("updateDisposition") == "update_applied"
            and event.get("adapterActiveEventIndex") is not None,
        ),
        "active_event_index_observed_count": count_if(
            update_events,
            lambda event: event.get("adapterActiveEventIndex") is not None,
        ),
        "current_association_before_observed_count": count_if(
            update_events,
            lambda event: event.get("adapterCurrentEventIndexBefore") is not None,
        ),
        "current_association_after_observed_count": count_if(
            update_events,
            lambda event: event.get("adapterCurrentEventIndexAfter") is not None,
        ),
        "top_order_start_updates": order_start_channel_rows,
    }


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


def sample_time_position_mismatches(
    events: list[dict[str, Any]],
    include_transport_resets: bool = False,
    row_transitions_only: bool = True,
    limit: int = 10,
) -> list[dict[str, Any]]:
    rows = []
    for index, event in enumerate(events):
        if not include_transport_resets and is_transport_reset_event(event):
            continue
        if row_transitions_only and not is_row_transition_event(event):
            continue
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
            "sample_rate": sample_rate(event),
            "frame_delta": frame_delta,
            "abs_frame_delta": abs(frame_delta) if frame_delta is not None else None,
            "time_delta_ms": time_delta_ms(frame_delta, sample_rate(event)),
            "position_mismatch": bool(mismatch),
            "playback_clock_relation": playback_clock_relation(frame_delta),
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
    return c_mixer_sample_time_monotonic_analysis(events)["unexpected_backward_count"] == 0


def c_mixer_sample_time_monotonic_analysis(events: list[dict[str, Any]]) -> dict[str, Any]:
    previous: int | None = None
    observed = False
    reset_events = []
    in_callback_ordering_events = []
    unexpected_backward_events = []
    for index, event in enumerate(events):
        frame = c_mixer_rendered_frames(event)
        if frame is None:
            continue
        observed = True
        if previous is not None and frame < previous:
            row = event_context_dict(event)
            row.update({
                "trace_index": index,
                "runtime_action": event.get("runtimeAction"),
                "reason": event.get("reason"),
                "previous_frame": previous,
                "current_frame": frame,
            })
            if is_transport_reset_event(event):
                reset_events.append(row)
            elif is_in_callback_sample_time_event(event, frame):
                row.update({
                    "callback_start_frame": integer(event.get("callbackStartFrame")),
                    "callback_end_frame": integer(event.get("callbackEndFrame")),
                    "in_callback_offset": integer(event.get("inCallbackOffset")),
                    "event_application_timing": event.get("eventApplicationTiming"),
                })
                in_callback_ordering_events.append(row)
            else:
                unexpected_backward_events.append(row)
        previous = frame
    return {
        "observed": observed,
        "monotonic_excluding_transport_resets": not unexpected_backward_events,
        "monotonic_excluding_transport_resets_and_in_callback_applications": not unexpected_backward_events,
        "reset_count": len(reset_events),
        "reset_events": reset_events[:10],
        "in_callback_ordering_count": len(in_callback_ordering_events),
        "in_callback_ordering_events": in_callback_ordering_events[:10],
        "unexpected_backward_count": len(unexpected_backward_events),
        "unexpected_backward_events": unexpected_backward_events[:10],
    }


def c_mixer_sample_time_frame_observed(events: list[dict[str, Any]]) -> bool:
    return any(c_mixer_rendered_frames(event) is not None for event in events)


def position_diverges_over_time(events: list[dict[str, Any]]) -> bool:
    return bool(playback_engine_c_mixer_drift_profile(events)["accumulating"])


def order_transition_position_samples(
    events: list[dict[str, Any]],
    limit: int = 20,
) -> list[dict[str, Any]]:
    rows = []
    seen: set[tuple[Any, Any, Any, Any]] = set()
    for index, event in enumerate(events):
        if not is_row_transition_event(event):
            continue
        row = playback_engine_c_mixer_position_delta_row(index, event)
        if row is None:
            continue
        playback_order = row["playback_engine_order_index"]
        playback_row = row["playback_engine_row_index"]
        c_mixer_order = row["c_mixer_order_index"]
        c_mixer_row = row["c_mixer_row_index"]
        if playback_row != 0 and c_mixer_row != 0:
            continue
        key = (playback_order, playback_row, c_mixer_order, c_mixer_row)
        if key in seen:
            continue
        seen.add(key)
        rows.append(row)
        if len(rows) >= limit:
            break
    return rows


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
    unexpected_silent_output_count = int(max_numeric(events, "unexpectedSilentOutputCount") or 0)
    silent_output_callback_count = int(max_numeric(events, "silentOutputCallbackCount") or 0)
    render_callback_count = int(max_numeric(events, "renderCallbackCount") or 0)
    output_discontinuity_count = int(max_numeric(events, "outputDiscontinuityCount") or 0)
    max_output_adjacent_sample_jump = max_numeric(events, "maxOutputAdjacentSampleJump") or 0.0
    output_discontinuity_threshold = max_numeric(events, "outputDiscontinuityThreshold")
    lower_threshold_counts = discontinuity_threshold_counts(events)
    top_transient_jumps = top_output_sample_jumps(events)
    top_transient_peaks = top_output_peaks(events)
    epsilon_profile = epsilon_suppression_profile(events, top_transient_jumps, top_transient_peaks)
    output_peak_warning_threshold = max_numeric(events, "outputPeakWarningThreshold") or 0.95
    output_peak_warning_sample_count = int(max_numeric(events, "outputPeakWarningSampleCount") or 0)
    overrange_sample_count = int(max_numeric(events, "overrangeSampleCount") or 0)
    runtime_policy_warning_counts = Counter(
        str(event.get("runtimeGainConfigurationWarning"))
        for event in events
        if event.get("runtimeGainConfigurationWarning") is not None
    )
    runtime_output_gain = first_number(events, "runtimeOutputGain")
    runtime_default_headroom_db = first_number(events, "runtimeDefaultHeadroomDB")
    runtime_fixed_headroom_db = first_number(events, "runtimeFixedHeadroomDB")
    runtime_policy = {
        "output_gain": rounded(runtime_output_gain) if runtime_output_gain is not None else None,
        "headroom_policy": first_string(events, "runtimeHeadroomPolicy"),
        "gain_policy_label": first_string(events, "runtimeGainPolicyLabel"),
        "gain_policy_source": first_string(events, "runtimeGainPolicySource"),
        "gain_policy_is_environment_override": first_bool(events, "runtimeGainPolicyIsEnvironmentOverride"),
        "default_headroom_db": rounded(runtime_default_headroom_db) if runtime_default_headroom_db is not None else None,
        "fixed_headroom_db": rounded(runtime_fixed_headroom_db) if runtime_fixed_headroom_db is not None else None,
        "auto_headroom_enabled": any(event.get("runtimeAutoHeadroomEnabled") is True for event in events),
        "configuration_warning_counts": dict(sorted(runtime_policy_warning_counts.items())),
    }
    capture_enabled = any(event.get("runtimeCaptureEnabled") is True for event in events)
    capture_sample_rate = first_number(events, "runtimeCaptureSampleRate")
    capture_duration = max_numeric(events, "runtimeCaptureDurationSeconds")
    capture = {
        "enabled": capture_enabled,
        "path_name": first_string(events, "runtimeCapturePathName"),
        "sample_rate": rounded(capture_sample_rate) if capture_sample_rate is not None else None,
        "channel_count": int(first_number(events, "runtimeCaptureChannelCount") or 0) if capture_enabled else None,
        "seconds": rounded(first_number(events, "runtimeCaptureSeconds")) if first_number(events, "runtimeCaptureSeconds") is not None else None,
        "frame_limit": int(max_numeric(events, "runtimeCaptureFrameLimit") or 0) if capture_enabled else None,
        "captured_frame_count": int(max_numeric(events, "runtimeCapturedFrameCount") or 0),
        "duration_seconds": rounded(capture_duration) if capture_duration is not None else None,
        "truncated": any(event.get("runtimeCaptureTruncated") is True for event in events),
        "output_peak": rounded(max_numeric(events, "runtimeCaptureOutputPeak") or 0.0),
        "output_rms": rounded(max_numeric(events, "runtimeCaptureOutputRMS") or 0.0),
        "overrange_sample_count": int(max_numeric(events, "runtimeCaptureOverrangeSampleCount") or 0),
        "clipping_sample_count": int(max_numeric(events, "runtimeCaptureClippingSampleCount") or 0),
        "write_succeeded": any(event.get("runtimeCaptureWriteSucceeded") is True for event in events),
        "write_failed": any(event.get("runtimeCaptureWriteSucceeded") is False for event in events),
        "write_error": first_string(events, "runtimeCaptureWriteError"),
        "configuration_warning": first_string(events, "runtimeCaptureConfigurationWarning"),
    }
    callback_duration_warning_count = int(max_numeric(events, "callbackDurationWarningCount") or 0)
    callback_over_budget_count = int(max_numeric(events, "callbackOverRenderQuantumBudgetCount") or 0)
    callback_timing = {
        "minimal_callback_mode": last_bool(events, "runtimeMinimalCallbackMode"),
        "callback_count": render_callback_count,
        "requested_frame_count_range": numeric_range(events, "callbackRequestedFrameCount", "requestedFrameCount"),
        "duration_warning_threshold_ms": rounded_optional(last_number(events, "callbackDurationWarningThresholdMS")),
        "duration_min_ms": rounded_optional(last_number(events, "callbackDurationMinMS")),
        "duration_max_ms": rounded_optional(max_numeric(events, "callbackDurationMaxMS")),
        "duration_average_ms": rounded_optional(last_number(events, "callbackDurationAverageMS")),
        "duration_warning_count": callback_duration_warning_count,
        "render_quantum_duration_ms": rounded_optional(last_number(events, "callbackRenderQuantumDurationMS")),
        "render_quantum_min_ms": rounded_optional(last_number(events, "callbackRenderQuantumMinMS")),
        "render_quantum_max_ms": rounded_optional(max_numeric(events, "callbackRenderQuantumMaxMS")),
        "over_render_quantum_budget_count": callback_over_budget_count,
        "interval_min_ms": rounded_optional(last_number(events, "callbackIntervalMinMS")),
        "interval_max_ms": rounded_optional(max_numeric(events, "callbackIntervalMaxMS")),
        "interval_last_ms": rounded_optional(last_number(events, "callbackIntervalLastMS")),
    }
    callback_isolation = {
        "callback_thread_is_main": last_bool(events, "callbackThreadIsMain"),
        "callback_thread_id": last_exact_integer(events, "callbackThreadID"),
        "main_thread_dependency_detected": any(event.get("callbackMainThreadDependencyDetected") is True for event in events),
        "allocation_warning": any(event.get("callbackAllocationWarning") is True for event in events),
        "realtime_safe_diagnostics": last_bool(events, "callbackRealtimeSafeDiagnostics"),
        "diagnostic_drop_count": int(max_numeric(events, "callbackDiagnosticDropCount") or 0),
        "ring_buffer_capacity": integer(last_number(events, "callbackRingBufferCapacity")),
        "lock_wait_count": int(max_numeric(events, "callbackLockWaitCount") or 0),
        "lock_wait_duration_ms": rounded_optional(max_numeric(events, "callbackLockWaitDurationMS")),
        "lock_failure_count": int(max_numeric(events, "callbackLockFailureCount") or 0),
        "event_queue_producer_thread_id": last_exact_integer(events, "eventQueueProducerThreadID"),
        "event_queue_producer_thread_is_main": last_bool(events, "eventQueueProducerThreadIsMain"),
        "event_queue_consumer_thread_id": last_exact_integer(events, "eventQueueConsumerThreadID"),
        "event_queue_consumer_thread_is_main": last_bool(events, "eventQueueConsumerThreadIsMain"),
        "follow_publication_disabled": any(event.get("playbackFollowPublicationDisabled") is True for event in events),
        "follow_publication_count": int(max_numeric(events, "playbackFollowPublicationCount") or 0),
        "follow_publication_suppressed_count": int(max_numeric(events, "playbackFollowPublicationSuppressedCount") or 0),
    }
    output_copy_failure_count = int(max_numeric(events, "outputBufferCopyFailureCount") or 0)
    output_copy_last_succeeded = last_bool(events, "outputBufferCopyLastSucceeded")
    output_copy_filled_requested_frames = last_bool(events, "outputBufferCopyFilledRequestedFrames")
    output_copy_channel_count_matches = last_bool(events, "outputBufferCopyChannelCountMatches")
    output_copy_partial_copy = last_bool(events, "outputBufferCopyPartialCopy")
    output_copy_scratch_capture_matches = last_bool(events, "outputBufferCopyScratchCaptureHashMatches")
    output_copy_scratch_output_matches = last_bool(events, "outputBufferCopyScratchOutputHashMatches")
    output_buffer_copy = {
        "attempt_count": int(max_numeric(events, "outputBufferCopyAttemptCount") or 0),
        "failure_count": output_copy_failure_count,
        "last_succeeded": output_copy_last_succeeded,
        "layout": last_string(events, "outputBufferCopyLayout"),
        "requested_frame_count": integer(last_number(events, "outputBufferCopyRequestedFrameCount")),
        "source_channel_count": integer(last_number(events, "outputBufferCopySourceChannelCount")),
        "output_buffer_count": integer(last_number(events, "outputBufferCopyOutputBufferCount")),
        "output_channel_count": integer(last_number(events, "outputBufferCopyOutputChannelCount")),
        "copied_frame_count": integer(last_number(events, "outputBufferCopyCopiedFrameCount")),
        "copied_sample_count": integer(last_number(events, "outputBufferCopyCopiedSampleCount")),
        "expected_sample_count": integer(last_number(events, "outputBufferCopyExpectedSampleCount")),
        "filled_requested_frames": output_copy_filled_requested_frames,
        "channel_count_matches": output_copy_channel_count_matches,
        "partial_copy": output_copy_partial_copy,
        "scratch_hash": last_exact_integer(events, "outputBufferCopyScratchHash"),
        "capture_hash": last_exact_integer(events, "outputBufferCopyCaptureHash"),
        "output_hash": last_exact_integer(events, "outputBufferCopyOutputHash"),
        "scratch_capture_hash_matches": output_copy_scratch_capture_matches,
        "scratch_output_hash_matches": output_copy_scratch_output_matches,
    }
    last_output_discontinuity_events = [
        event for event in events
        if event.get("lastOutputDiscontinuityRuntimeFrame") is not None
    ]
    bursts = top_event_bursts(events)
    planned_adapter_event_applications = [
        event for event in events if is_planned_adapter_event_application(event)
    ]
    row_transition_events = [event for event in events if is_row_transition_event(event)]
    all_timing_deltas = event_timing_delta_rows(planned_adapter_event_applications, limit=None)
    timing_deltas = all_timing_deltas[:10]
    all_row_transition_timing_deltas = event_timing_delta_rows(row_transition_events, limit=None)
    row_transition_timing_deltas = all_row_transition_timing_deltas[:10]
    callback_events = callback_boundary_events(planned_adapter_event_applications)
    same_frame_bursts = attach_nearby_transients_to_bursts(
        top_same_frame_event_bursts(events),
        top_transient_jumps,
        top_transient_peaks,
    )
    transition_bursts = top_transition_bursts(events)
    suspicious_positions = top_suspicious_positions(timing_deltas, same_frame_bursts, transition_bursts)
    position_delta_rows = playback_engine_c_mixer_position_delta_rows(events, include_zero=True, limit=None)
    largest_position_delta_rows = largest_playback_engine_c_mixer_position_delta_rows(events)
    published_position_delta_rows = published_follow_c_mixer_position_delta_rows(events, limit=None)
    largest_published_position_delta_rows = largest_published_follow_c_mixer_position_delta_rows(events)
    first_published_position_divergence = first_published_follow_divergence_above_threshold(events)
    position_mismatches = sample_time_position_mismatches(events)
    first_position_mismatch = first_suspicious_position_mismatch(events)
    first_position_divergence = first_position_divergence_above_threshold(events)
    position_drift_profile = playback_engine_c_mixer_drift_profile(events)
    sample_time_monotonic = c_mixer_sample_time_monotonic_analysis(events)
    position_delta_values = [
        row["abs_frame_delta"]
        for row in position_delta_rows
        if isinstance(row.get("abs_frame_delta"), int)
    ]
    published_position_delta_values = [
        row["abs_frame_delta"]
        for row in published_position_delta_rows
        if isinstance(row.get("abs_frame_delta"), int)
    ]
    row_transition_delta_values = [
        abs(row["event_frame_delta"])
        for row in all_row_transition_timing_deltas
        if isinstance(row.get("event_frame_delta"), int)
    ]
    row_transition_delta_categories = Counter(
        str(event.get("rowTransitionDeltaCategory"))
        for event in row_transition_events
        if event.get("rowTransitionDeltaCategory") is not None
    )
    published_follow_source_counts = Counter(
        str(event.get("publishedPlaybackFollowPositionSource"))
        for event in events
        if event.get("publishedPlaybackFollowPositionSource") is not None
    )
    parity_categories = summarize_update_parity(events)
    sustained_transitions = sustained_voice_transition_summary(events)
    max_abs_event_frame_delta = max((abs(row["event_frame_delta"]) for row in all_timing_deltas), default=0)
    max_row_transition_frame_delta = max(
        (abs(row["event_frame_delta"]) for row in all_row_transition_timing_deltas),
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
    ramping_out_voice_count = int(max_numeric(events, "rampingOutVoiceCount") or 0)
    ramp_down_start_count = int(max_numeric(events, "rampDownStartCount") or 0)
    ramp_down_completion_count = int(max_numeric(events, "rampDownCompletionCount") or 0)
    abrupt_ramp_down_stop_count = int(max_numeric(events, "abruptRampDownStopCount") or 0)
    replacement_overlap_count = count_if(
        ramped_replacements,
        lambda event: event.get("replacementVoicesOverlap") is True,
    )
    likely_transient_correlation = likely_correlation_category(
        clipping_count=clipping_count,
        overrange_count=overrange_sample_count,
        top_peaks=top_transient_peaks,
        top_jumps=top_transient_jumps,
        same_frame_bursts=same_frame_bursts,
        ramped_replacements=ramped_replacements,
        ramping_out_voice_count=ramping_out_voice_count,
        ramp_down_completion_count=ramp_down_completion_count,
        abrupt_ramp_down_stop_count=abrupt_ramp_down_stop_count,
    )

    suspicious_findings: list[str] = []
    if clipping_count > 0:
        suspicious_findings.append("runtime clipping/overrange remains after runtime gain")
    if underrun_count > 0 or zero_fill_count > 0 or failed_render_count > 0:
        suspicious_findings.append("runtime render underrun, zero-fill, or failure counters are nonzero")
    if callback_duration_warning_count > 0 or callback_over_budget_count > 0:
        suspicious_findings.append("AVAudioSourceNode callback duration warnings or over-budget callbacks observed")
    if callback_isolation["main_thread_dependency_detected"]:
        suspicious_findings.append("AVAudioSourceNode callback ran on or depended on the main thread")
    if callback_isolation["lock_wait_count"] > 0:
        suspicious_findings.append("AVAudioSourceNode callback lock waits observed")
    if callback_isolation["lock_failure_count"] > 0:
        suspicious_findings.append("AVAudioSourceNode callback try-lock failures observed")
    if callback_isolation["allocation_warning"]:
        suspicious_findings.append("AVAudioSourceNode callback still contains diagnostic allocation risk")
    if callback_isolation["diagnostic_drop_count"] > 0:
        suspicious_findings.append("runtime C mixer callback diagnostic ring dropped events")
    if (
        output_copy_failure_count > 0
        or output_copy_last_succeeded is False
        or output_copy_filled_requested_frames is False
        or output_copy_channel_count_matches is False
        or output_copy_partial_copy is True
    ):
        suspicious_findings.append("AVAudioSourceNode output buffer copy verification failed")
    if output_copy_scratch_capture_matches is False or output_copy_scratch_output_matches is False:
        suspicious_findings.append("runtime scratch/capture/output buffer hashes diverged")
    if unexpected_silent_output_count > 0:
        suspicious_findings.append("unexpected silent output callbacks observed while voices were active or loaded")
    if output_discontinuity_count > 0:
        suspicious_findings.append("runtime output adjacent-sample discontinuity threshold crossings observed")
    if any(row["count"] > 0 and row["threshold"] < (output_discontinuity_threshold or 0.75) for row in lower_threshold_counts):
        suspicious_findings.append("runtime output adjacent-sample lower-threshold jumps observed")
    if output_peak_warning_sample_count > 0:
        suspicious_findings.append("runtime output peaks above warning threshold observed")
    if epsilon_profile["suppressed_update_near_top_transient_count"] > 0:
        suspicious_findings.append("epsilon-suppressed runtime updates observed near top transient frames")
    if hard_replacement_stops:
        suspicious_findings.append("at least one note replacement used c_mixer_stop_channel instead of c_mixer_stop_channel_ramped")
    if action_counts["c_mixer_stop_channel"] > 0:
        suspicious_findings.append("immediate c_mixer_stop_channel hard-stop events remain during playback")
    if clear_all_normal:
        suspicious_findings.append("c_mixer_clear_all appeared outside known transport/reset reasons")
    if deferred_updates:
        suspicious_findings.append("runtime update deferrals remain")
    if sustained_transitions["association_lost_count"] > 0:
        suspicious_findings.append("sustained carried voice association was lost during runtime updates")
    if sustained_transitions["missed_or_stored_update_count"] > 0:
        suspicious_findings.append("update-without-note events were missed or stored during sustained voice transitions")
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
    if sample_time_monotonic["unexpected_backward_count"] > 0:
        suspicious_findings.append("C mixer sample-time frame counter moved backward")
    if position_mismatches:
        suspicious_findings.append("PlaybackEngine position and C mixer sample-time position mismatch observed")
    if position_diverges_over_time(events):
        suspicious_findings.append("PlaybackEngine position and C mixer sample-time position diverge over time")
    if any(published_follow_divergent(row) for row in published_position_delta_rows):
        suspicious_findings.append("Published playback-follow position and C mixer sample-time position mismatch observed")
    if any(event.get("audioEngineConfigurationChangeCount") for event in events):
        suspicious_findings.append("AVAudioEngine configuration changes observed during playback")
    if any(event.get("audioGraphFormatChanged") is True for event in events):
        suspicious_findings.append("AVAudio graph format changes observed during playback")
    if any(event.get("audioOutputRouteChanged") is True for event in events):
        suspicious_findings.append("output route/device changes observed during playback")

    large_event_burst = bool(bursts and bursts[0]["event_count"] >= 24)
    large_same_frame_burst = bool(same_frame_bursts and same_frame_bursts[0]["event_count"] >= 24)
    has_sample_time_delta = (
        max_planned_vs_applied_delta > 0
        or callback_boundary_applied_event_count > 0
        or late_planned_event_count > 0
    )
    published_follow_has_material_drift = any(
        published_follow_divergent(row)
        for row in published_position_delta_rows
    )
    published_follow_aligned = bool(published_position_delta_rows) and not published_follow_has_material_drift

    if callback_isolation["main_thread_dependency_detected"] or callback_isolation["lock_wait_count"] > 0:
        recommended_next_pr = "Runtime C Mixer Render Callback Isolation"
    elif hard_replacement_stops:
        recommended_next_pr = "Runtime C Mixer Hard Stop / Replacement Follow-Up"
    elif has_sample_time_delta:
        recommended_next_pr = "Runtime C Mixer Remaining Sample-Time Timing Gap Investigation"
    elif output_discontinuity_count > 0:
        recommended_next_pr = "Runtime C Mixer Output Discontinuity Diagnostics / Fix"
    elif (
        callback_duration_warning_count > 0
        or callback_over_budget_count > 0
        or output_copy_failure_count > 0
        or output_copy_last_succeeded is False
        or output_copy_scratch_output_matches is False
    ):
        recommended_next_pr = "Runtime C Mixer AVAudio Callback Deadline / Output Delivery Follow-Up"
    elif any(event.get("audioEngineConfigurationChangeCount") for event in events) or any(event.get("audioOutputRouteChanged") is True for event in events):
        recommended_next_pr = "Runtime C Mixer AVAudio Output Device / Route Follow-Up"
    elif published_follow_has_material_drift:
        recommended_next_pr = "Runtime C Mixer Published Follow Position Bridge Follow-Up"
    elif position_diverges_over_time(events) and not published_follow_aligned:
        recommended_next_pr = "Runtime C Mixer Playback Follow Position Drift Investigation"
    elif position_mismatches and not published_follow_aligned:
        recommended_next_pr = "Runtime C Mixer Tracker-Follow Sample-Time Integration"
    elif large_same_frame_burst:
        recommended_next_pr = "Runtime C Mixer Same-Frame Event Burst Stabilization"
    elif likely_transient_correlation == "peak/clip" or output_peak_warning_sample_count > 0:
        recommended_next_pr = "Runtime C Mixer Transient Peak / Headroom Investigation"
    elif epsilon_profile["suppressed_update_near_top_transient_count"] > 0:
        recommended_next_pr = "Runtime C Mixer Update Epsilon Correlation Follow-Up"
    elif any(row["count"] > 0 and row["threshold"] < (output_discontinuity_threshold or 0.75) for row in lower_threshold_counts):
        recommended_next_pr = "Runtime C Mixer Low-Threshold Transient Diagnostics Follow-Up"
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
            "overrange_sample_count": overrange_sample_count,
            "underrun_count": underrun_count,
            "zero_fill_count": zero_fill_count,
            "unexpected_silent_output_count": unexpected_silent_output_count,
            "failed_render_count": failed_render_count,
            "render_callback_count": render_callback_count,
            "callback_requested_frame_count_range": numeric_range(events, "callbackRequestedFrameCount", "requestedFrameCount"),
            "silent_output_callback_count": silent_output_callback_count,
            "output_discontinuity_threshold": rounded(output_discontinuity_threshold) if output_discontinuity_threshold is not None else None,
            "output_discontinuity_count": output_discontinuity_count,
            "output_discontinuity_threshold_counts": lower_threshold_counts,
            "max_output_adjacent_sample_jump": rounded(max_output_adjacent_sample_jump),
            "top_output_adjacent_sample_jumps": top_transient_jumps,
            "output_peak_warning_threshold": rounded(output_peak_warning_threshold),
            "output_peak_warning_sample_count": output_peak_warning_sample_count,
            "top_output_peaks": top_transient_peaks,
            "likely_correlation_category": likely_transient_correlation,
            "last_output_discontinuity": {
                "runtime_frame": integer(last_output_discontinuity_events[-1].get("lastOutputDiscontinuityRuntimeFrame")) if last_output_discontinuity_events else None,
                "callback_index": integer(last_output_discontinuity_events[-1].get("lastOutputDiscontinuityCallbackIndex")) if last_output_discontinuity_events else None,
                "frame_offset": integer(last_output_discontinuity_events[-1].get("lastOutputDiscontinuityFrameOffset")) if last_output_discontinuity_events else None,
                "channel_index": integer(last_output_discontinuity_events[-1].get("lastOutputDiscontinuityChannelIndex")) if last_output_discontinuity_events else None,
                "sample_jump": rounded(number(last_output_discontinuity_events[-1].get("lastOutputDiscontinuitySampleJump")) or 0.0) if last_output_discontinuity_events else None,
            },
        },
        "capture": capture,
        "callback_timing": callback_timing,
        "callback_isolation": callback_isolation,
        "output_buffer_copy": output_buffer_copy,
        "runtime_policy": runtime_policy,
        "audio_graph": {
            "selected_runtime_sample_rate": rounded(last_number(events, "selectedRuntimeSampleRate") or 0.0),
            "c_mixer_runtime_sample_rate": rounded(last_number(events, "cMixerRuntimeSampleRate") or 0.0),
            "runtime_sample_rate_policy": first_string(events, "runtimeSampleRatePolicy"),
            "runtime_sample_rate_source": first_string(events, "runtimeSampleRateSource"),
            "runtime_sample_rate_configuration_warning": first_string(events, "runtimeSampleRateConfigurationWarning"),
            "c_mixer_render_sample_rate": rounded(last_number(events, "cMixerRenderSampleRate") or 0.0),
            "c_mixer_render_channel_count": integer(last_number(events, "cMixerRenderChannelCount")),
            "source_node_render_sample_rate": rounded(last_number(events, "audioSourceNodeRenderSampleRate") or 0.0),
            "source_node_channel_count": integer(last_number(events, "audioSourceNodeChannelCount")),
            "main_mixer_output_sample_rate": rounded(last_number(events, "audioEngineMainMixerOutputSampleRate") or 0.0),
            "main_mixer_output_channel_count": integer(last_number(events, "audioEngineMainMixerOutputChannelCount")),
            "main_mixer_input_sample_rate": rounded(last_number(events, "audioEngineMainMixerInputSampleRate") or 0.0),
            "main_mixer_input_channel_count": integer(last_number(events, "audioEngineMainMixerInputChannelCount")),
            "main_mixer_latency_seconds": rounded_optional(last_number(events, "audioEngineMainMixerLatency")),
            "main_mixer_output_presentation_latency_seconds": rounded_optional(last_number(events, "audioEngineMainMixerOutputPresentationLatency")),
            "output_node_sample_rate": rounded(last_number(events, "audioEngineOutputNodeSampleRate") or 0.0),
            "output_node_channel_count": integer(last_number(events, "audioEngineOutputNodeChannelCount")),
            "output_node_latency_seconds": rounded_optional(last_number(events, "audioEngineOutputNodeLatency")),
            "output_node_output_presentation_latency_seconds": rounded_optional(last_number(events, "audioEngineOutputNodeOutputPresentationLatency")),
            "hardware_nominal_sample_rate": rounded_optional(last_number(events, "audioHardwareNominalSampleRate")),
            "hardware_device_id": last_exact_integer(events, "audioHardwareDeviceID"),
            "hardware_device_uid_hash": last_string(events, "audioHardwareDeviceUIDHash"),
            "hardware_io_buffer_frame_size": integer(last_number(events, "audioHardwareIOBufferFrameSize")),
            "hardware_io_buffer_duration_seconds": rounded_optional(last_number(events, "audioHardwareIOBufferDuration")),
            "hardware_latency_frames": integer(last_number(events, "audioHardwareLatencyFrames")),
            "hardware_latency_duration_seconds": rounded_optional(last_number(events, "audioHardwareLatencyDuration")),
            "hardware_safety_offset_frames": integer(last_number(events, "audioHardwareSafetyOffsetFrames")),
            "hardware_safety_offset_duration_seconds": rounded_optional(last_number(events, "audioHardwareSafetyOffsetDuration")),
            "hardware_transport_type": last_exact_integer(events, "audioHardwareTransportType"),
            "engine_running": last_bool(events, "audioEngineRunning"),
            "source_node_attached": last_bool(events, "audioEngineSourceNodeAttached"),
            "source_node_connected": last_bool(events, "audioEngineSourceNodeConnected"),
            "main_mixer_connected_to_output": last_bool(events, "audioEngineMainMixerConnectedToOutput"),
            "engine_configuration_change_count": int(max_numeric(events, "audioEngineConfigurationChangeCount") or 0),
            "graph_format_change_count": int(max_numeric(events, "audioGraphFormatChangeCount") or 0),
            "output_route_change_count": int(max_numeric(events, "audioOutputRouteChangeCount") or 0),
            "graph_format_changed": any(event.get("audioGraphFormatChanged") is True for event in events),
            "output_route_changed": any(event.get("audioOutputRouteChanged") is True for event in events),
            "format_conversion_likely": last_bool(events, "audioFormatConversionLikely"),
            "runtime_capture_matches_source_node_format": last_bool(events, "runtimeCaptureMatchesSourceNodeFormat"),
            "runtime_capture_matches_engine_output_format": last_bool(events, "runtimeCaptureMatchesEngineOutputFormat"),
            "runtime_capture_matches_hardware_sample_rate": last_bool(events, "runtimeCaptureMatchesHardwareSampleRate"),
            "callback_requested_frame_count_range": numeric_range(events, "callbackRequestedFrameCount", "requestedFrameCount"),
        },
        "voices": {
            "active_voice_range": numeric_range(events, "activeVoiceCount", "activeVoiceCountBefore", "activeVoiceCountAfter"),
            "loaded_voice_range": numeric_range(events, "loadedVoiceCount", "loadedVoiceCountBefore", "loadedVoiceCountAfter"),
        },
        "stops": {
            "add_voice_events": action_counts["c_mixer_add_voice"],
            "ramped_replacement_stop_events": len(ramped_replacements),
            "ramped_replacement_voice_count": sum(integer(event.get("rampedVoiceCount")) or 0 for event in ramped_replacements),
            "ramped_replacement_overlap_events": replacement_overlap_count,
            "replacement_gain_pan_applied_before_ramp_events": count_if(
                ramped_replacements,
                lambda event: event.get("replacementGainPanAppliedBeforeRamp") is True,
            ),
            "replacement_gain_pan_missing_before_ramp_events": count_if(
                ramped_replacements,
                lambda event: event.get("replacementGainPanAppliedBeforeRamp") is False,
            ),
            "replacement_step_applied_before_ramp_events": count_if(
                ramped_replacements,
                lambda event: event.get("replacementStepAppliedBeforeRamp") is True,
            ),
            "replacement_step_missing_before_ramp_events": count_if(
                ramped_replacements,
                lambda event: event.get("replacementStepAppliedBeforeRamp") is False,
            ),
            "replacement_key_off_applied_before_ramp_events": count_if(
                ramped_replacements,
                lambda event: event.get("replacementKeyOffAppliedBeforeRamp") is True,
            ),
            "replacement_fadeout_applied_before_ramp_events": count_if(
                ramped_replacements,
                lambda event: event.get("replacementFadeoutAppliedBeforeRamp") is True,
            ),
            "immediate_hard_replacement_stop_events": len(hard_replacement_stops),
            "immediate_hard_stop_events": action_counts["c_mixer_stop_channel"],
            "immediate_hard_stop_reasons": dict(sorted(hard_stop_reasons.items())),
            "clear_all_events": action_counts["c_mixer_clear_all"],
            "clear_all_normal_playback_events": len(clear_all_normal),
            "ramped_replacement_covers_all_observed_replacement_stops": ramped_coverage,
            "ramping_out_voice_count": ramping_out_voice_count,
            "ramp_down_start_count": ramp_down_start_count,
            "ramp_down_completion_count": ramp_down_completion_count,
            "abrupt_ramp_down_stop_count": abrupt_ramp_down_stop_count,
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
            "suppressed_epsilon_gain_update_events": max(
                int(max_numeric(events, "updateSuppressedEpsilonGainCount") or 0),
                count_if(events, lambda event: event.get("gainUpdateStatus") == "suppressed_epsilon"),
            ),
            "suppressed_epsilon_pan_update_events": max(
                int(max_numeric(events, "updateSuppressedEpsilonPanCount") or 0),
                count_if(events, lambda event: event.get("panUpdateStatus") == "suppressed_epsilon"),
            ),
            "suppressed_epsilon_step_update_events": max(
                int(max_numeric(events, "updateSuppressedEpsilonStepCount") or 0),
                count_if(events, lambda event: event.get("sampleStepUpdateStatus") == "suppressed_epsilon"),
            ),
            "applied_after_epsilon_filter_update_events": max(
                int(max_numeric(events, "updateAppliedAfterEpsilonFilterCount") or 0),
                count_if(
                    events,
                    lambda event: event.get("updateDisposition") == "update_applied"
                    and bool(epsilon_suppressed_fields(event)),
                ),
            ),
            "stored_channel_state_update_events": action_counts["c_mixer_update_stored_channel_state"],
            "update_dispositions": dict(sorted(update_disposition_counts.items())),
            "update_types": dict(sorted(update_type_counts.items())),
            "remaining_deferred_update_categories": dict(sorted(deferred_categories.items())),
            "epsilon_suppression": epsilon_profile,
        },
        "runtime_vs_offline_adapter_categories": parity_categories,
        "sustained_voice_transitions": sustained_transitions,
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
            "c_mixer_sample_time_monotonic": sample_time_monotonic["unexpected_backward_count"] == 0,
            "c_mixer_sample_time_reset_count": sample_time_monotonic["reset_count"],
            "c_mixer_sample_time_reset_events": sample_time_monotonic["reset_events"],
            "c_mixer_sample_time_in_callback_ordering_count": sample_time_monotonic["in_callback_ordering_count"],
            "c_mixer_sample_time_in_callback_ordering_events": sample_time_monotonic["in_callback_ordering_events"],
            "c_mixer_sample_time_unexpected_backward_count": sample_time_monotonic["unexpected_backward_count"],
            "c_mixer_sample_time_unexpected_backward_events": sample_time_monotonic["unexpected_backward_events"],
            "position_delta_threshold_frames": POSITION_DIVERGENCE_FRAME_THRESHOLD,
            "playback_engine_vs_c_mixer_position_delta_count": len(position_delta_values),
            "max_playback_engine_vs_c_mixer_abs_frame_delta": max(position_delta_values, default=0),
            "average_playback_engine_vs_c_mixer_abs_frame_delta": average(position_delta_values),
            "median_playback_engine_vs_c_mixer_abs_frame_delta": median(position_delta_values),
            "playback_engine_vs_c_mixer_signed_frame_delta_range": {
                "min": position_drift_profile["signed_delta_min"],
                "max": position_drift_profile["signed_delta_max"],
                "range": position_drift_profile["signed_delta_range"],
            },
            "playback_engine_vs_c_mixer_position_drift_classification": position_drift_profile["classification"],
            "playback_engine_vs_c_mixer_position_mostly_constant_offset": position_drift_profile["mostly_constant_offset"],
            "playback_engine_vs_c_mixer_position_accumulates": position_drift_profile["accumulating"],
            "playback_engine_vs_c_mixer_constant_offset_tolerance_frames": position_drift_profile["constant_offset_tolerance_frames"],
            "playback_engine_c_mixer_position_diverges_over_time": position_diverges_over_time(events),
            "largest_playback_engine_vs_c_mixer_position_deltas": largest_position_delta_rows,
            "largest_playback_engine_vs_c_mixer_mismatch": position_mismatches[0] if position_mismatches else None,
            "largest_playback_engine_vs_c_mixer_mismatches": position_mismatches,
            "first_suspicious_position_mismatch": first_position_mismatch,
            "first_position_divergence_above_threshold": first_position_divergence,
            "published_playback_follow_position_source_counts": dict(sorted(published_follow_source_counts.items())),
            "published_playback_follow_position_delta_count": len(published_position_delta_values),
            "max_published_playback_follow_vs_c_mixer_abs_frame_delta": max(published_position_delta_values, default=0),
            "average_published_playback_follow_vs_c_mixer_abs_frame_delta": average(published_position_delta_values),
            "median_published_playback_follow_vs_c_mixer_abs_frame_delta": median(published_position_delta_values),
            "largest_published_playback_follow_vs_c_mixer_position_deltas": largest_published_position_delta_rows,
            "first_published_playback_follow_divergence_above_threshold": first_published_position_divergence,
            "largest_mismatch_order_row_ranges": largest_mismatch_order_row_ranges(position_mismatches),
            "order_transition_position_samples": order_transition_position_samples(events),
            "largest_event_timing_deltas": timing_deltas,
            "row_transition_timing_deltas": row_transition_timing_deltas,
            "callback_boundary_event_count": len(callback_events),
            "callback_boundary_events": callback_events,
            "largest_same_frame_event_burst": same_frame_bursts[0] if same_frame_bursts else None,
            "same_frame_event_bursts": same_frame_bursts,
            "order_row_transition_event_bursts": transition_bursts,
            "top_suspicious_positions": suspicious_positions,
        },
        "suspicious_findings": suspicious_findings,
        "recommended_next_pr": recommended_next_pr,
    }


def build_markdown(summary: dict[str, Any]) -> str:
    health = summary["health"]
    capture = summary["capture"]
    callback_timing = summary["callback_timing"]
    callback_isolation = summary["callback_isolation"]
    output_buffer_copy = summary["output_buffer_copy"]
    runtime_policy = summary["runtime_policy"]
    audio_graph = summary["audio_graph"]
    stops = summary["stops"]
    updates = summary["updates"]
    voices = summary["voices"]
    alignment = summary["sample_time_alignment"]
    sustained = summary["sustained_voice_transitions"]
    lines = [
        "# Runtime C Mixer Trace Summary",
        "",
        f"- Events: {summary['event_count']}",
        f"- Peak: {health['peak']}",
        f"- Clipping samples: {health['clipping_sample_count']}",
        f"- Overrange samples: {health['overrange_sample_count']}",
        f"- Underruns / zero-fill / unexpected silent / failed renders: {health['underrun_count']} / {health['zero_fill_count']} / {health['unexpected_silent_output_count']} / {health['failed_render_count']}",
        f"- Render callbacks: {health['render_callback_count']} frame_count_range={health['callback_requested_frame_count_range']}",
        f"- Callback timing: minimal={callback_timing['minimal_callback_mode']} max_ms={callback_timing['duration_max_ms']} avg_ms={callback_timing['duration_average_ms']} warning_count={callback_timing['duration_warning_count']} quantum_ms={callback_timing['render_quantum_duration_ms']} over_budget={callback_timing['over_render_quantum_budget_count']} interval_min_max_ms={callback_timing['interval_min_ms']}..{callback_timing['interval_max_ms']}",
        f"- Callback isolation: thread_is_main={callback_isolation['callback_thread_is_main']} thread_id={callback_isolation['callback_thread_id']} main_dependency={callback_isolation['main_thread_dependency_detected']} allocation_warning={callback_isolation['allocation_warning']} realtime_safe={callback_isolation['realtime_safe_diagnostics']} diagnostic_drops={callback_isolation['diagnostic_drop_count']} ring_capacity={callback_isolation['ring_buffer_capacity']} lock_waits={callback_isolation['lock_wait_count']} lock_wait_ms={callback_isolation['lock_wait_duration_ms']} lock_failures={callback_isolation['lock_failure_count']} event_queue_threads={callback_isolation['event_queue_producer_thread_id']}->{callback_isolation['event_queue_consumer_thread_id']} producer_main={callback_isolation['event_queue_producer_thread_is_main']} consumer_main={callback_isolation['event_queue_consumer_thread_is_main']} follow_disabled={callback_isolation['follow_publication_disabled']} follow_count={callback_isolation['follow_publication_count']} suppressed={callback_isolation['follow_publication_suppressed_count']}",
        f"- Output buffer copy: attempts={output_buffer_copy['attempt_count']} failures={output_buffer_copy['failure_count']} last_succeeded={output_buffer_copy['last_succeeded']} layout={output_buffer_copy['layout']} frames={output_buffer_copy['copied_frame_count']}/{output_buffer_copy['requested_frame_count']} channels={output_buffer_copy['output_channel_count']} filled={output_buffer_copy['filled_requested_frames']} scratch_capture_hash_match={output_buffer_copy['scratch_capture_hash_matches']} scratch_output_hash_match={output_buffer_copy['scratch_output_hash_matches']}",
        f"- Output discontinuities > {health['output_discontinuity_threshold']}: {health['output_discontinuity_count']} max_jump={health['max_output_adjacent_sample_jump']} last={health['last_output_discontinuity']}",
        f"- Output discontinuity threshold counts: {health['output_discontinuity_threshold_counts']}",
        f"- Peak warning samples > {health['output_peak_warning_threshold']}: {health['output_peak_warning_sample_count']}",
        f"- Likely transient correlation: {health['likely_correlation_category']}",
        f"- Runtime capture: enabled={capture['enabled']} path_name={capture['path_name']} frames={capture['captured_frame_count']} duration={capture['duration_seconds']} truncated={capture['truncated']} peak={capture['output_peak']} clipping={capture['clipping_sample_count']} write_succeeded={capture['write_succeeded']}",
        f"- Runtime gain policy: label={runtime_policy['gain_policy_label']} source={runtime_policy['gain_policy_source']} env_override={runtime_policy['gain_policy_is_environment_override']} output_gain={runtime_policy['output_gain']} fixed_headroom_db={runtime_policy['fixed_headroom_db']} default_headroom_db={runtime_policy['default_headroom_db']} warnings={runtime_policy['configuration_warning_counts']}",
        f"- Runtime sample-rate policy: selected={audio_graph['selected_runtime_sample_rate']}Hz c_mixer_runtime={audio_graph['c_mixer_runtime_sample_rate']}Hz policy={audio_graph['runtime_sample_rate_policy']} source={audio_graph['runtime_sample_rate_source']} warning={audio_graph['runtime_sample_rate_configuration_warning']}",
        f"- Audio graph: running={audio_graph['engine_running']} source_attached={audio_graph['source_node_attached']} source_connected={audio_graph['source_node_connected']} main_connected={audio_graph['main_mixer_connected_to_output']} c_mixer={audio_graph['c_mixer_render_sample_rate']}Hz/{audio_graph['c_mixer_render_channel_count']}ch source={audio_graph['source_node_render_sample_rate']}Hz/{audio_graph['source_node_channel_count']}ch main_in={audio_graph['main_mixer_input_sample_rate']}Hz/{audio_graph['main_mixer_input_channel_count']}ch main_out={audio_graph['main_mixer_output_sample_rate']}Hz/{audio_graph['main_mixer_output_channel_count']}ch output={audio_graph['output_node_sample_rate']}Hz/{audio_graph['output_node_channel_count']}ch hardware={audio_graph['hardware_nominal_sample_rate']}Hz device_id={audio_graph['hardware_device_id']} device_uid_hash={audio_graph['hardware_device_uid_hash']} io_buffer={audio_graph['hardware_io_buffer_frame_size']} frames ({audio_graph['hardware_io_buffer_duration_seconds']}s) output_latency={audio_graph['output_node_latency_seconds']} presentation_latency={audio_graph['output_node_output_presentation_latency_seconds']} hardware_latency={audio_graph['hardware_latency_frames']} frames ({audio_graph['hardware_latency_duration_seconds']}s) safety_offset={audio_graph['hardware_safety_offset_frames']} frames ({audio_graph['hardware_safety_offset_duration_seconds']}s) route_changes={audio_graph['output_route_change_count']} graph_format_changes={audio_graph['graph_format_change_count']} engine_config_changes={audio_graph['engine_configuration_change_count']} conversion_likely={audio_graph['format_conversion_likely']} capture_matches_source={audio_graph['runtime_capture_matches_source_node_format']} capture_matches_output={audio_graph['runtime_capture_matches_engine_output_format']} capture_matches_hardware_rate={audio_graph['runtime_capture_matches_hardware_sample_rate']}",
        f"- Add voice events: {stops['add_voice_events']}",
        f"- Ramped replacement stops: {stops['ramped_replacement_stop_events']} events, {stops['ramped_replacement_voice_count']} voices",
        f"- Ramped replacement overlaps: {stops['ramped_replacement_overlap_events']}",
        f"- Replacement ramp prep gain/pan true/false, step true/false, key-off, fadeout: {stops['replacement_gain_pan_applied_before_ramp_events']} / {stops['replacement_gain_pan_missing_before_ramp_events']}, {stops['replacement_step_applied_before_ramp_events']} / {stops['replacement_step_missing_before_ramp_events']}, {stops['replacement_key_off_applied_before_ramp_events']}, {stops['replacement_fadeout_applied_before_ramp_events']}",
        f"- Ramping-out voices / ramp starts / completions / abrupt ramp stops: {stops['ramping_out_voice_count']} / {stops['ramp_down_start_count']} / {stops['ramp_down_completion_count']} / {stops['abrupt_ramp_down_stop_count']}",
        f"- Immediate hard replacement stops: {stops['immediate_hard_replacement_stop_events']}",
        f"- Immediate hard channel stops: {stops['immediate_hard_stop_events']}",
        f"- Clear-all events outside transport/reset: {stops['clear_all_normal_playback_events']}",
        f"- Active voice range: {voices['active_voice_range']['min']}...{voices['active_voice_range']['max']}",
        f"- Loaded voice range: {voices['loaded_voice_range']['min']}...{voices['loaded_voice_range']['max']}",
        f"- Applied gain/pan updates: {updates['applied_gain_pan_update_events']}",
        f"- Applied step updates: {updates['applied_step_update_events']}",
        f"- Suppressed no-change updates: {updates['suppressed_no_change_update_events']}",
        f"- Epsilon-suppressed gain/pan/step updates: {updates['suppressed_epsilon_gain_update_events']} / {updates['suppressed_epsilon_pan_update_events']} / {updates['suppressed_epsilon_step_update_events']}",
        f"- Applied updates after epsilon filtering: {updates['applied_after_epsilon_filter_update_events']}",
        f"- Stored channel-state updates: {updates['stored_channel_state_update_events']}",
        f"- Max planned event frame delta: {alignment['max_abs_event_frame_delta']}",
        f"- Max planned-vs-applied frame delta: {alignment['max_planned_vs_applied_delta']}",
        f"- Max row-transition frame delta: {alignment['max_row_transition_frame_delta']}",
        f"- Average row-transition frame delta: {alignment['average_row_transition_frame_delta']}",
        f"- Median row-transition frame delta: {alignment['median_row_transition_frame_delta']}",
        f"- Max PlaybackEngine-vs-C mixer position frame delta: {alignment['max_playback_engine_vs_c_mixer_abs_frame_delta']}",
        f"- Average PlaybackEngine-vs-C mixer position frame delta: {alignment['average_playback_engine_vs_c_mixer_abs_frame_delta']}",
        f"- Median PlaybackEngine-vs-C mixer position frame delta: {alignment['median_playback_engine_vs_c_mixer_abs_frame_delta']}",
        f"- PlaybackEngine-vs-C mixer drift classification: {alignment['playback_engine_vs_c_mixer_position_drift_classification']}",
        f"- PlaybackEngine-vs-C mixer mostly constant offset: {alignment['playback_engine_vs_c_mixer_position_mostly_constant_offset']}",
        f"- PlaybackEngine-vs-C mixer accumulating drift: {alignment['playback_engine_vs_c_mixer_position_accumulates']}",
        f"- Published follow position sources: {alignment['published_playback_follow_position_source_counts']}",
        f"- Max published-follow-vs-C mixer position frame delta: {alignment['max_published_playback_follow_vs_c_mixer_abs_frame_delta']}",
        f"- Average published-follow-vs-C mixer position frame delta: {alignment['average_published_playback_follow_vs_c_mixer_abs_frame_delta']}",
        f"- Median published-follow-vs-C mixer position frame delta: {alignment['median_published_playback_follow_vs_c_mixer_abs_frame_delta']}",
        f"- C mixer sample-time position monotonic: {alignment['c_mixer_sample_time_monotonic']}",
        f"- C mixer sample-time transport/reset jumps: {alignment['c_mixer_sample_time_reset_count']}",
        f"- C mixer in-callback sample-time ordering backfills: {alignment['c_mixer_sample_time_in_callback_ordering_count']}",
        f"- C mixer unexpected sample-time backward jumps: {alignment['c_mixer_sample_time_unexpected_backward_count']}",
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

    epsilon = updates["epsilon_suppression"]
    lines.extend(["", "## Update Epsilon", ""])
    lines.append(f"- Observed epsilon values: {epsilon['epsilon_values_observed']}")
    lines.append(f"- Epsilon policy counts: {epsilon['runtime_update_epsilon_policy_counts']}")
    lines.append(f"- Suppressed update events: {epsilon['suppressed_update_event_count']}")
    lines.append(f"- Suppressed field counts: {epsilon['suppressed_field_counts']}")
    lines.append(f"- Suppressed field total absolute deltas: {epsilon['suppressed_field_total_abs_delta']}")
    lines.append(f"- Suppressed updates near top transients: {epsilon['suppressed_update_near_top_transient_count']}")
    lines.append(f"- Motion assessment: {epsilon['motion_assessment']}")
    if epsilon["top_epsilon_suppressed_updates"]:
        lines.append("- Top epsilon-suppressed updates:")
        for row in epsilon["top_epsilon_suppressed_updates"][:5]:
            context = f"order={row.get('order_index')} pattern={row.get('pattern_index')} row={row.get('row_index')} tick={row.get('tick_in_row')}"
            lines.append(
                f"- frame={row['runtime_frame']} action={row['runtime_action']} fields={row['suppressed_fields']} "
                f"applied={row['applied_fields']} max_delta={row['max_abs_delta']} {context} "
                f"near_jump={row['nearest_top_jump']} near_peak={row['nearest_top_peak']}"
            )
    else:
        lines.append("- Top epsilon-suppressed updates: none")

    lines.extend(["", "## Deferred Updates", ""])
    if updates["remaining_deferred_update_categories"]:
        for category, count in updates["remaining_deferred_update_categories"].items():
            lines.append(f"- `{category}`: {count}")
    else:
        lines.append("- None")

    lines.extend(["", "## Sustained Voice Transitions", ""])
    lines.append(f"- Order-start update events: {sustained['order_start_update_event_count']}")
    lines.append(f"- Sustained update events: {sustained['sustained_update_event_count']}")
    lines.append(
        f"- Association retained / lost: {sustained['association_retained_count']} / "
        f"{sustained['association_lost_count']}"
    )
    lines.append(f"- Update-without-note applied events: {sustained['update_without_note_applied_count']}")
    lines.append(f"- Missed or stored update events: {sustained['missed_or_stored_update_count']}")
    if sustained["top_order_start_updates"]:
        lines.append("- Top order-start updates:")
        for row in sustained["top_order_start_updates"][:5]:
            context = f"order={row['order_index']} pattern={row['pattern_index']} row={row['row_index']} tick={row['tick_in_row']}"
            lines.append(
                f"- {context} channel={row['channel_index']} action={row['runtime_action']} "
                f"ordinal={row['same_frame_burst_event_ordinal']} burst={row['same_frame_burst_size']} "
                f"active_event={row['adapter_active_event_index']} "
                f"association={row['adapter_current_event_index_before']}->{row['adapter_current_event_index_after']} "
                f"retained={row['adapter_channel_association_retained']} disposition={row['update_disposition']}"
            )
    else:
        lines.append("- Top order-start updates: none")

    lines.extend(["", "## Event Stream", ""])
    lines.append(f"- Runtime driver: {summary['event_stream']['runtime_driver']}")
    lines.append(f"- Offline adapter event stream observed: {summary['event_stream']['offline_adapter_event_stream_observed']}")
    lines.append(f"- Sample-time render queue observed: {summary['event_stream']['sample_time_render_queue_observed']}")
    lines.append(f"- Assessment: {summary['event_stream']['assessment']}")

    lines.extend(["", "## Runtime Transients", ""])
    if health["top_output_adjacent_sample_jumps"]:
        lines.append("- Top adjacent same-channel jumps:")
        for row in health["top_output_adjacent_sample_jumps"][:5]:
            context = f"order={row.get('order_index')} pattern={row.get('pattern_index')} row={row.get('row_index')} tick={row.get('tick_in_row')}"
            lines.append(
                f"- frame={row['runtime_frame']} channel={row['channel_index']} jump={row['sample_jump']} "
                f"{context} context_delta={row.get('context_frame_delta')}"
            )
    else:
        lines.append("- Top adjacent same-channel jumps: none")
    if health["top_output_peaks"]:
        lines.append("- Top output peaks:")
        for row in health["top_output_peaks"][:5]:
            context = f"order={row.get('order_index')} pattern={row.get('pattern_index')} row={row.get('row_index')} tick={row.get('tick_in_row')}"
            lines.append(
                f"- frame={row['runtime_frame']} channel={row['channel_index']} peak={row['peak']} "
                f"above_0_95={row['above_0_95']} above_1_0={row['above_1_0']} "
                f"{context} context_delta={row.get('context_frame_delta')}"
            )
    else:
        lines.append("- Top output peaks: none")

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
    if alignment["first_position_divergence_above_threshold"]:
        row = alignment["first_position_divergence_above_threshold"]
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
            f"- First position divergence above {alignment['position_delta_threshold_frames']} frame(s): "
            f"{playback} {c_mixer} delta={row['frame_delta']} delta_ms={row['time_delta_ms']}"
        )
    else:
        lines.append(f"- First position divergence above {alignment['position_delta_threshold_frames']} frame(s): none")
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
                f"delta={row['frame_delta']} delta_ms={row['time_delta_ms']} "
                f"relation={row['playback_clock_relation']} category={row['row_transition_delta_category']}"
            )
    else:
        lines.append("- PlaybackEngine vs C mixer sample-time mismatches: none")
    if alignment["largest_published_playback_follow_vs_c_mixer_position_deltas"]:
        lines.append("- Published follow vs C mixer sample-time deltas:")
        for row in alignment["largest_published_playback_follow_vs_c_mixer_position_deltas"][:5]:
            published = (
                f"published=source={row['published_position_source']} order={row['published_order_index']} "
                f"pattern={row['published_pattern_index']} row={row['published_row_index']} "
                f"tick={row['published_tick_in_row']}"
            )
            c_mixer = (
                f"c_mixer=order={row['c_mixer_order_index']} pattern={row['c_mixer_pattern_index']} "
                f"row={row['c_mixer_row_index']} tick={row['c_mixer_tick_in_row']}"
            )
            lines.append(
                f"- {published} {c_mixer} published_frame={row['published_sample_time_frame']} "
                f"c_mixer_frame={row['c_mixer_sample_time_frame']} delta={row['frame_delta']} "
                f"row_delta={row['row_delta']} delta_ms={row['time_delta_ms']}"
            )
    else:
        lines.append("- Published follow vs C mixer sample-time deltas: none")
    if alignment["order_transition_position_samples"]:
        lines.append("- Order transition position samples:")
        for row in alignment["order_transition_position_samples"][:8]:
            playback = (
                f"playback=order={row['playback_engine_order_index']} "
                f"row={row['playback_engine_row_index']} tick={row['playback_engine_tick_in_row']}"
            )
            c_mixer = (
                f"c_mixer=order={row['c_mixer_order_index']} "
                f"row={row['c_mixer_row_index']} tick={row['c_mixer_tick_in_row']}"
            )
            lines.append(
                f"- {playback} {c_mixer} frame={row['c_mixer_sample_time_frame']} "
                f"delta={row['frame_delta']} delta_ms={row['time_delta_ms']}"
            )
    else:
        lines.append("- Order transition position samples: none")
    if alignment["same_frame_event_bursts"]:
        lines.append("- Same-frame event bursts:")
        for burst in alignment["same_frame_event_bursts"][:5]:
            lines.append(
                f"- frame={burst['runtime_application_frame']}: {burst['event_count']} events "
                f"burst_id={burst['same_frame_burst_id']} ordinals={burst['same_frame_burst_event_ordinals']} "
                f"channels={burst['affected_channels']} actions={burst['actions']} "
                f"categories={burst['event_categories']} explicit={burst['explicit_event_categories']} "
                f"voices={burst['active_voice_count_before']}->{burst['active_voice_count_after']} "
                f"ramps={burst['voices_entering_ramp_down']}/{burst['voices_completing_ramp_down']} "
                f"new={burst['new_voices_started']} carried={burst['sustained_voices_carried']} "
                f"order_start={burst['at_order_start']} row_transition={burst['at_row_transition']} "
                f"near_jump={burst['nearest_top_jump']} near_peak={burst['nearest_top_peak']}"
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
