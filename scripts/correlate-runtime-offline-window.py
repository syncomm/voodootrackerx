#!/usr/bin/env python3
"""Correlate runtime/offline C mixer mismatch windows with traces."""

from __future__ import annotations

import argparse
import json
import math
import sys
import wave
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


FLOAT_DIGITS = 9
DEFAULT_ALIGNMENT_SEARCH_FRAMES = 1024
DEFAULT_TRACE_PADDING_FRAMES = 2048
DEFAULT_EVENT_LIMIT = 20

RECOMMENDATIONS = {
    "amplitude": "Runtime C Mixer Gain/Headroom Normalization Follow-Up",
    "timing": "Runtime C Mixer Alignment/Timing Follow-Up",
    "burst": "Runtime C Mixer Event Burst Mitigation Follow-Up",
    "voice": "Runtime C Mixer Voice State / Cleanup Fix",
    "capture": "Runtime C Mixer Live Capture Follow-Up",
    "offline": "No runtime fix; continue offline effect work",
}


class WindowCorrelationError(Exception):
    """A user-facing input or validation error."""


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
    return None if value_number is None else int(value_number)


def nested_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def nested_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def load_json(path: Path, role: str) -> dict[str, Any]:
    if not path.exists():
        raise WindowCorrelationError(f"missing {role}: {path}")
    if not path.is_file():
        raise WindowCorrelationError(f"{role} is not a file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise WindowCorrelationError(
            f"malformed {role}: {path}: line {error.lineno} column {error.colno}: {error.msg}"
        ) from error
    if not isinstance(value, dict):
        raise WindowCorrelationError(f"{role} must contain a top-level object: {path}")
    return value


def load_trace(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        raise WindowCorrelationError(f"missing runtime trace: {path}")
    events = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as error:
            raise WindowCorrelationError(f"malformed runtime trace: {path}: line {line_number}: {error.msg}") from error
        if not isinstance(event, dict):
            raise WindowCorrelationError(f"malformed runtime trace: {path}: line {line_number}: expected JSON object")
        events.append(event)
    return events


def wav_info(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise WindowCorrelationError(f"missing WAV: {path}")
    if not path.is_file():
        raise WindowCorrelationError(f"WAV path is not a file: {path}")
    try:
        wav_file = wave.open(str(path), "rb")
    except wave.Error as error:
        raise WindowCorrelationError(f"{path}: {error}") from error
    with wav_file:
        if wav_file.getcomptype() != "NONE":
            raise WindowCorrelationError(f"{path}: only uncompressed PCM WAV files are supported")
        info = {
            "path": path,
            "path_name": path.name,
            "sample_rate": wav_file.getframerate(),
            "channel_count": wav_file.getnchannels(),
            "sample_width": wav_file.getsampwidth(),
            "frame_count": wav_file.getnframes(),
        }
    if info["sample_rate"] <= 0:
        raise WindowCorrelationError(f"{path}: sample rate must be greater than zero")
    if info["channel_count"] <= 0:
        raise WindowCorrelationError(f"{path}: channel count must be greater than zero")
    if info["sample_width"] not in (1, 2, 3, 4):
        raise WindowCorrelationError(f"{path}: unsupported sample width: {info['sample_width']} bytes")
    info["duration_seconds"] = info["frame_count"] / info["sample_rate"]
    return info


def public_wav_info(info: dict[str, Any]) -> dict[str, Any]:
    return {
        "path_name": info["path_name"],
        "sample_rate": info["sample_rate"],
        "channel_count": info["channel_count"],
        "sample_width_bits": info["sample_width"] * 8,
        "frame_count": info["frame_count"],
        "duration_seconds": rounded(info["duration_seconds"]),
    }


def read_wav_window(path: Path, start_frame: int, frame_count: int, info: dict[str, Any]) -> list[float]:
    safe_start = min(max(0, start_frame), info["frame_count"])
    safe_count = min(max(0, frame_count), max(0, info["frame_count"] - safe_start))
    with wave.open(str(path), "rb") as wav_file:
        wav_file.setpos(safe_start)
        return decode_pcm(wav_file.readframes(safe_count), info["sample_width"])


def decode_pcm(pcm: bytes, sample_width: int) -> list[float]:
    if sample_width == 1:
        return [(sample - 128) / 128.0 for sample in pcm]
    scale = float(1 << ((sample_width * 8) - 1))
    result = []
    for offset in range(0, len(pcm), sample_width):
        chunk = pcm[offset:offset + sample_width]
        if len(chunk) == sample_width:
            result.append(int.from_bytes(chunk, "little", signed=True) / scale)
    return result


def audio_stats(samples: list[float], channels: int) -> dict[str, Any]:
    if not samples:
        return {"peak": 0.0, "rms": 0.0, "per_channel_peak": [0.0] * channels, "per_channel_rms": [0.0] * channels}
    return {
        "peak": rounded(max(abs(sample) for sample in samples)),
        "rms": rounded(math.sqrt(sum(sample * sample for sample in samples) / len(samples))),
        "per_channel_peak": [
            rounded(max((abs(sample) for sample in samples[channel::channels]), default=0.0))
            for channel in range(channels)
        ],
        "per_channel_rms": [
            rounded(channel_rms(samples[channel::channels]))
            for channel in range(channels)
        ],
    }


def channel_rms(samples: list[float]) -> float:
    return math.sqrt(sum(sample * sample for sample in samples) / len(samples)) if samples else 0.0


def diff_metrics(offline: list[float], runtime: list[float], scalar: float = 1.0) -> dict[str, Any]:
    count = min(len(offline), len(runtime))
    if count == 0:
        return {"normalized_correlation": None, "rms_difference": 0.0, "max_abs_difference": 0.0}
    dot = offline_square = runtime_square = diff_square = max_abs = 0.0
    for index in range(count):
        ref = offline[index]
        run = runtime[index] * scalar
        dot += ref * run
        offline_square += ref * ref
        runtime_square += run * run
        diff = run - ref
        diff_square += diff * diff
        max_abs = max(max_abs, abs(diff))
    denominator = math.sqrt(offline_square * runtime_square)
    return {
        "normalized_correlation": None if denominator == 0 else rounded(dot / denominator),
        "rms_difference": rounded(math.sqrt(diff_square / count)),
        "max_abs_difference": rounded(max_abs),
    }


def best_scalar(offline: list[float], runtime: list[float]) -> float | None:
    count = min(len(offline), len(runtime))
    denominator = sum(runtime[index] * runtime[index] for index in range(count))
    if count == 0 or denominator == 0:
        return None
    numerator = sum(offline[index] * runtime[index] for index in range(count))
    return numerator / denominator


def alignment_metrics(
    offline_wav: Path,
    runtime_wav: Path,
    offline_info: dict[str, Any],
    runtime_info: dict[str, Any],
    start_frame: int,
    end_frame: int,
    search_frames: int,
) -> dict[str, Any]:
    channels = offline_info["channel_count"]
    radius = max(0, search_frames)
    end_frame = max(start_frame, min(end_frame, offline_info["frame_count"], runtime_info["frame_count"]))
    frames = max(0, end_frame - start_frame)
    offline = read_wav_window(offline_wav, start_frame, frames, offline_info)
    runtime_base_start = max(0, start_frame - radius)
    runtime_base_end = min(runtime_info["frame_count"], end_frame + radius)
    runtime_base = read_wav_window(runtime_wav, runtime_base_start, runtime_base_end - runtime_base_start, runtime_info)

    zero_sample = (start_frame - runtime_base_start) * channels
    zero_runtime = runtime_base[zero_sample:zero_sample + len(offline)]
    scalar = best_scalar(offline, zero_runtime)
    best = None
    for shift in range(-radius, radius + 1):
        shifted_start = start_frame + shift
        if shifted_start < runtime_base_start or shifted_start + frames > runtime_base_end:
            continue
        sample_start = (shifted_start - runtime_base_start) * channels
        metrics = diff_metrics(offline, runtime_base[sample_start:sample_start + len(offline)])
        key = (
            -(metrics["normalized_correlation"] if metrics["normalized_correlation"] is not None else -2.0),
            metrics["rms_difference"],
            abs(shift),
            shift,
        )
        if best is None or key < best["_key"]:
            best = {"runtime_shift_frames": shift, **metrics, "_key": key}
    if best is not None:
        del best["_key"]
    return {
        "search_radius_frames": radius,
        "zero_shift": diff_metrics(offline, zero_runtime),
        "best_shift": best,
        "runtime_to_offline_scalar": None if scalar is None else rounded(scalar),
        "scalar_normalized_zero_shift": diff_metrics(offline, zero_runtime, scalar or 1.0),
    }


def event_frame(event: dict[str, Any]) -> int | None:
    for field in (
        "eventAppliedFrame", "runtimeApplicationFrame", "plannedRuntimeFrame", "transitionRuntimeFrame",
        "lastOutputDiscontinuityRuntimeFrame", "cMixerSampleTimeFrame", "currentFrame",
        "cMixerRenderedFrames", "runtimeRenderedFrameCount", "callbackStartFrame",
    ):
        value = integer(event.get(field))
        if value is not None:
            return value
    return None


def event_category(event: dict[str, Any]) -> str:
    raw = event.get("adapterEventCategory") or event.get("runtimeEventCategory")
    if isinstance(raw, str) and raw:
        return {
            "replacement_stop_ramp": "replacement_ramp",
            "hxy_global_volume": "global_volume_update",
            "hxy_global_volume_update": "global_volume_update",
            "key_off": "key_off_fadeout",
            "ecx_edx_e9x": "voice_timing_effect",
        }.get(raw, raw)
    action = str(event.get("runtimeAction") or "")
    return {
        "c_mixer_add_voice": "note_trigger",
        "note_trigger": "note_trigger",
        "c_mixer_stop_channel_ramped": "replacement_ramp",
        "c_mixer_stop_channel": "channel_stop",
        "key_off": "key_off_fadeout",
        "c_mixer_update_gain_pan_applied": "gain_pan_update",
        "c_mixer_update_gain_pan_step_applied": "gain_pan_update",
        "c_mixer_update_step_applied": "step_update",
        "c_mixer_clear_all": "clear_all",
    }.get(action, "row_transition" if action.startswith("row_transition") else action or "unknown")


def trace_context(event: dict[str, Any]) -> dict[str, Any]:
    return {
        "order_index": event.get("orderIndex", event.get("plannedSourceOrderIndex")),
        "pattern_index": event.get("patternIndex", event.get("plannedSourcePatternIndex")),
        "row_index": event.get("rowIndex", event.get("plannedSourceRowIndex")),
        "tick_in_row": event.get("tickInRow", event.get("plannedSourceTickInRow")),
        "channel_index": event.get("channelIndex", event.get("plannedSourceChannelIndex")),
    }


def trace_correlation(events: list[dict[str, Any]], start_frame: int, end_frame: int, padding: int, limit: int) -> dict[str, Any]:
    padded_start = max(0, start_frame - padding)
    padded_end = end_frame + padding
    nearby = []
    for index, event in enumerate(events):
        frame = event_frame(event)
        if frame is not None and padded_start <= frame <= padded_end:
            nearby.append({"index": index, "frame": frame, "event": event, "category": event_category(event)})
    nearby.sort(key=lambda item: (
        item["frame"],
        integer(item["event"].get("sameFrameBurstEventOrdinal")) or 0,
        item["index"],
    ))
    active_values = event_values(nearby, "activeVoiceCount", "activeVoiceCountBefore", "activeVoiceCountAfter",
                                 "sameFrameBurstActiveVoiceCountBefore", "sameFrameBurstActiveVoiceCountAfter")
    loaded_values = event_values(nearby, "loadedVoiceCount", "loadedVoiceCountBefore", "loadedVoiceCountAfter",
                                 "sameFrameBurstLoadedVoiceCountBefore", "sameFrameBurstLoadedVoiceCountAfter")
    return {
        "padding_frames": padding,
        "event_count": len(nearby),
        "category_counts": dict(sorted(Counter(row["category"] for row in nearby).items())),
        "action_counts": dict(sorted(Counter(str(row["event"].get("runtimeAction")) for row in nearby if row["event"].get("runtimeAction")).items())),
        "active_voice_range": range_dict(active_values),
        "loaded_voice_range": range_dict(loaded_values),
        "same_frame_bursts": same_frame_bursts(nearby),
        "sustained_voice_transitions": sustained_summary(nearby),
        "voice_cleanup": cleanup_summary(nearby),
        "source_positions": unique_contexts(nearby)[:limit],
        "event_order_sample": event_order_sample(nearby, start_frame, limit),
    }


def event_values(rows: list[dict[str, Any]], *fields: str) -> list[int]:
    values = []
    for row in rows:
        for field in fields:
            value = integer(row["event"].get(field))
            if value is not None:
                values.append(value)
    return values


def range_dict(values: list[int]) -> dict[str, int | None]:
    return {"min": min(values) if values else None, "max": max(values) if values else None}


def same_frame_bursts(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped = defaultdict(list)
    for row in rows:
        size = integer(row["event"].get("sameFrameBurstSize")) or 0
        burst_id = integer(row["event"].get("sameFrameBurstID"))
        if size > 1 or burst_id is not None:
            grouped[(row["frame"], burst_id)].append(row)
    result = []
    for (frame, burst_id), burst_rows in grouped.items():
        first = burst_rows[0]["event"]
        channels = set()
        for row in burst_rows:
            raw_channels = nested_list(row["event"].get("sameFrameBurstAffectedChannels"))
            if raw_channels:
                channels.update(channel for channel in raw_channels if isinstance(channel, int))
            else:
                channel = row["event"].get("channelIndex", row["event"].get("plannedSourceChannelIndex"))
                if isinstance(channel, int):
                    channels.add(channel)
        result.append({
            "runtime_frame": frame,
            "same_frame_burst_id": burst_id,
            "event_count": len(burst_rows),
            "declared_burst_size": max(integer(row["event"].get("sameFrameBurstSize")) or 0 for row in burst_rows),
            "event_ordinals": sorted(value for value in (integer(row["event"].get("sameFrameBurstEventOrdinal")) for row in burst_rows) if value is not None),
            "categories": dict(sorted(Counter(row["category"] for row in burst_rows).items())),
            "actions": dict(sorted(Counter(str(row["event"].get("runtimeAction")) for row in burst_rows if row["event"].get("runtimeAction")).items())),
            "affected_channels": sorted(channels),
            "active_voice_count_before": first_value(burst_rows, "sameFrameBurstActiveVoiceCountBefore", "activeVoiceCountBefore", fn=min),
            "active_voice_count_after": first_value(burst_rows, "sameFrameBurstActiveVoiceCountAfter", "activeVoiceCountAfter", fn=max),
            "loaded_voice_count_before": first_value(burst_rows, "sameFrameBurstLoadedVoiceCountBefore", "loadedVoiceCountBefore", fn=min),
            "loaded_voice_count_after": first_value(burst_rows, "sameFrameBurstLoadedVoiceCountAfter", "loadedVoiceCountAfter", fn=max),
            "replacement_ramp_count": first_value(burst_rows, "sameFrameBurstReplacementRampCount", fn=max),
            "gain_pan_update_count": first_value(burst_rows, "sameFrameBurstGainPanUpdateCount", fn=max),
            "step_update_count": first_value(burst_rows, "sameFrameBurstStepUpdateCount", fn=max),
            "global_volume_update_count": first_value(burst_rows, "sameFrameBurstGlobalVolumeUpdateCount", fn=max),
            "new_voices_started": first_value(burst_rows, "sameFrameBurstNewVoicesStarted", fn=max),
            "sustained_voices_carried": first_value(burst_rows, "sameFrameBurstSustainedVoicesCarried", fn=max),
            "at_order_start": bool(first.get("sameFrameBurstAtOrderStart")),
            "at_row_transition": bool(first.get("sameFrameBurstAtRowTransition")),
            "context": trace_context(first),
        })
    result.sort(key=lambda item: (-item["event_count"], item["runtime_frame"], item["same_frame_burst_id"] or -1))
    return result


def first_value(rows: list[dict[str, Any]], *fields: str, fn=max) -> int | None:
    values = event_values(rows, *fields)
    return fn(values) if values else None


def sustained_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    retained = lost = updates = 0
    examples = []
    for row in rows:
        event = row["event"]
        retained_flag = event.get("adapterChannelAssociationRetained")
        sustained_flag = event.get("adapterSustainedVoiceUpdate")
        updates += 1 if sustained_flag is True else 0
        if sustained_flag is True:
            retained += 1 if retained_flag is True else 0
            lost += 1 if retained_flag is False else 0
        if retained_flag is not None or sustained_flag is not None:
            examples.append({
                "runtime_frame": row["frame"],
                "category": row["category"],
                "adapter_channel_association_retained": retained_flag,
                "adapter_sustained_voice_update": sustained_flag,
                "adapter_active_event_index": integer(event.get("adapterActiveEventIndex")),
                "context": trace_context(event),
            })
    return {
        "sustained_update_count": updates,
        "retained_association_count": retained,
        "lost_association_count": lost,
        "rows": examples[:DEFAULT_EVENT_LIMIT],
    }


def cleanup_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    actions = Counter(str(row["event"].get("runtimeAction")) for row in rows)
    return {
        "channel_stop_count": actions["c_mixer_stop_channel"],
        "replacement_ramp_count": actions["c_mixer_stop_channel_ramped"],
        "clear_all_count": actions["c_mixer_clear_all"],
        "ramp_down_start_count": max(event_values(rows, "rampDownStartCount") or [0]),
        "ramp_down_completion_count": max(event_values(rows, "rampDownCompletionCount") or [0]),
        "abrupt_ramp_down_stop_count": max(event_values(rows, "abruptRampDownStopCount") or [0]),
        "ramping_out_voice_count": max(event_values(rows, "rampingOutVoiceCount") or [0]),
    }


def unique_contexts(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen = set()
    result = []
    for row in rows:
        context = trace_context(row["event"])
        key = tuple(context.values())
        if all(value is None for value in key) or key in seen:
            continue
        seen.add(key)
        result.append({"runtime_frame": row["frame"], **context})
    return result


def event_order_sample(rows: list[dict[str, Any]], start_frame: int, limit: int) -> list[dict[str, Any]]:
    return [
        {
            "trace_index": row["index"],
            "runtime_frame": row["frame"],
            "distance_from_window_start_frames": row["frame"] - start_frame,
            "runtime_action": row["event"].get("runtimeAction"),
            "category": row["category"],
            "planned_event_id": integer(row["event"].get("plannedEventID")),
            "same_frame_burst_id": integer(row["event"].get("sameFrameBurstID")),
            "same_frame_burst_ordinal": integer(row["event"].get("sameFrameBurstEventOrdinal")),
            "active_voice_count_before": integer(row["event"].get("activeVoiceCountBefore")),
            "active_voice_count_after": integer(row["event"].get("activeVoiceCountAfter")),
            "loaded_voice_count_before": integer(row["event"].get("loadedVoiceCountBefore")),
            "loaded_voice_count_after": integer(row["event"].get("loadedVoiceCountAfter")),
            "context": trace_context(row["event"]),
        }
        for row in rows[:limit]
    ]


def offline_events(diagnostics: dict[str, Any]) -> list[dict[str, Any]]:
    result = []

    def add(category: str, item: Any, frame: int | None = None) -> None:
        if not isinstance(item, dict):
            return
        event_frame = frame if frame is not None else first_int(item, "scheduled_frame", "absolute_frame", "scheduled_start_frame", "delayed_frame", "row_start_frame", "release_frame")
        if event_frame is None:
            return
        source = nested_dict(item.get("source"))
        result.append({
            "frame": event_frame,
            "category": category,
            "status": item.get("status"),
            "order_index": source.get("order"),
            "pattern_index": source.get("pattern"),
            "row_index": source.get("row"),
            "channel_index": item.get("channel_index"),
        })

    for item in nested_list(diagnostics.get("events")):
        add("note_trigger", item)
    for item in nested_list(diagnostics.get("volume_panning_state_updates")):
        add("global_volume_update" if item.get("global_volume_before") is not None else "gain_pan_update", item)
    for item in nested_list(diagnostics.get("volume_column_mappings")):
        add("gain_pan_update", item)
    for key, category in (
        ("sample_offset_effects", "sample_offset"), ("note_cut_effects", "note_cut"),
        ("note_delay_effects", "note_delay"), ("key_off_events", "key_off_fadeout"),
        ("timing_changes", "timing_change"),
    ):
        for item in nested_list(diagnostics.get(key)):
            add(category, item)
    for item in nested_list(diagnostics.get("retrigger_effects")):
        frames = [integer(frame) for frame in nested_list(item.get("retrigger_frames"))]
        emitted = False
        for frame in frames:
            if frame is not None:
                add("retrigger", item, frame)
                emitted = True
        if not emitted:
            add("retrigger", item)
    for key in ("tone_portamento_effects", "portamento_slide_effects"):
        for item in nested_list(diagnostics.get(key)):
            add("step_update", item)
            for update in nested_list(item.get("step_updates")):
                if isinstance(update, dict):
                    add("step_update", {**item, **update})
    result.sort(key=lambda row: (row["frame"], row["category"], str(row["channel_index"])))
    return result


def first_int(item: dict[str, Any], *fields: str) -> int | None:
    for field in fields:
        value = integer(item.get(field))
        if value is not None:
            return value
    return None


def offline_correlation(diagnostics: dict[str, Any], start_frame: int, end_frame: int, padding: int) -> dict[str, Any]:
    rows = [
        row for row in offline_events(diagnostics)
        if max(0, start_frame - padding) <= row["frame"] <= end_frame + padding
    ]
    categories = Counter(row["category"] for row in rows)
    statuses = Counter(f"{row['category']}:{row['status']}" for row in rows if row.get("status") is not None)
    source_positions = []
    seen = set()
    for row in rows:
        key = (row["order_index"], row["pattern_index"], row["row_index"], row["channel_index"])
        if key not in seen:
            seen.add(key)
            source_positions.append({key: row[key] for key in ("frame", "order_index", "pattern_index", "row_index", "channel_index")})
    return {
        "provided": True,
        "event_count": len(rows),
        "category_counts": dict(sorted(categories.items())),
        "status_counts": dict(sorted(statuses.items())),
        "source_positions": source_positions[:DEFAULT_EVENT_LIMIT],
    }


def category_comparison(runtime: dict[str, Any], offline: dict[str, Any] | None) -> dict[str, Any]:
    if offline is None:
        return {"offline_diagnostics_provided": False, "rows": []}
    runtime_counts = Counter(runtime["category_counts"])
    offline_counts = Counter(offline["category_counts"])
    return {
        "offline_diagnostics_provided": True,
        "rows": [
            {
                "category": category,
                "runtime_count": runtime_counts.get(category, 0),
                "offline_count": offline_counts.get(category, 0),
                "runtime_minus_offline": runtime_counts.get(category, 0) - offline_counts.get(category, 0),
            }
            for category in sorted(set(runtime_counts) | set(offline_counts))
        ],
    }


def classify(audio: dict[str, Any], trace: dict[str, Any], offline: dict[str, Any] | None, complete: bool) -> dict[str, Any]:
    if not complete:
        return assessment("capture_or_window_incomplete", "live capture/window coverage issue", RECOMMENDATIONS["capture"],
                          "requested window extends beyond runtime or offline WAV coverage")
    zero = audio["alignment"]["zero_shift"]
    normalized = audio["alignment"]["scalar_normalized_zero_shift"]
    best = audio["alignment"]["best_shift"] or {}
    zero_rms = float(zero["rms_difference"])
    normalized_reduction = reduction(zero_rms, float(normalized["rms_difference"]))
    best_reduction = reduction(zero_rms, float(best.get("rms_difference", zero_rms)))
    shift = int(best.get("runtime_shift_frames") or 0)
    corr = zero.get("normalized_correlation")
    if normalized_reduction >= 0.75 and (corr is None or corr >= 0.98):
        return assessment("amplitude_difference", "amplitude difference", RECOMMENDATIONS["amplitude"],
                          f"scalar normalization reduced RMS diff by {rounded(normalized_reduction)}")
    if abs(shift) > 0 and best_reduction >= 0.45:
        return assessment("timing_shift", "timing shift or sample-position offset", RECOMMENDATIONS["timing"],
                          f"best local runtime shift {shift} frames reduced RMS diff by {rounded(best_reduction)}")
    cleanup = trace["voice_cleanup"]
    sustained = trace["sustained_voice_transitions"]
    if cleanup["abrupt_ramp_down_stop_count"] > 0 or sustained["lost_association_count"] > 0:
        return assessment("voice_state_difference", "event/voice-state difference", RECOMMENDATIONS["voice"],
                          "runtime trace shows voice cleanup or sustained-association loss near the window")
    if trace["same_frame_bursts"] or burst_event_count(trace) >= 16:
        return assessment("event_burst_difference", "event/voice-state difference", RECOMMENDATIONS["burst"],
                          "runtime trace shows dense same-frame or nearby event burst activity")
    if offline and any("deferred" in key or "unsupported" in key for key in offline["status_counts"]):
        return assessment("offline_effect_gap", "offline effect/parity difference", RECOMMENDATIONS["offline"],
                          "offline diagnostics show deferred/unsupported adapter evidence")
    if best.get("normalized_correlation") is not None and corr is not None and best["normalized_correlation"] > corr and abs(shift) > 0:
        return assessment("phase_or_sample_position_difference", "phase/sample-position difference", RECOMMENDATIONS["timing"],
                          "local alignment improved correlation but not enough to classify as a pure timing shift")
    return assessment("unknown", "unknown", RECOMMENDATIONS["burst"],
                      "audio metrics and nearby trace events do not isolate one dominant cause")


def assessment(classification: str, looks_like: str, recommendation: str, evidence: str) -> dict[str, Any]:
    return {
        "classification": classification,
        "mismatch_looks_like": looks_like,
        "evidence": [evidence],
        "recommended_next_pr": recommendation,
    }


def reduction(before: float, after: float) -> float:
    return 0.0 if before <= 0 else max(0.0, (before - after) / before)


def burst_event_count(trace: dict[str, Any]) -> int:
    counts = Counter(trace["category_counts"])
    return sum(counts.get(category, 0) for category in (
        "note_trigger", "replacement_ramp", "gain_pan_update", "step_update",
        "global_volume_update", "note_cut", "key_off_fadeout",
    ))


def parse_window(value: str, sample_rate: int, frame_mode: bool) -> tuple[int, int]:
    if ":" not in value:
        raise WindowCorrelationError(f"window must be START:END: {value}")
    start_text, end_text = value.split(":", 1)
    try:
        start = int(start_text) if frame_mode else int(math.floor(float(start_text) * sample_rate))
        end = int(end_text) if frame_mode else int(math.ceil(float(end_text) * sample_rate))
    except ValueError as error:
        raise WindowCorrelationError(f"invalid window value: {value}") from error
    if start < 0 or end <= start:
        raise WindowCorrelationError(f"window must have non-negative start and end greater than start: {value}")
    return start, end


def comparison_windows(path: Path, sample_rate: int, limit: int) -> list[tuple[int, int]]:
    comparison = load_json(path, "audio comparison JSON")
    sample_comparison = comparison.get("sample_comparison")
    if not isinstance(sample_comparison, dict) or not isinstance(sample_comparison.get("worst_windows"), list):
        raise WindowCorrelationError("audio comparison JSON does not contain sample_comparison.worst_windows")
    result = []
    for index, window in enumerate(sample_comparison["worst_windows"][:max(0, limit)], start=1):
        if not isinstance(window, dict):
            raise WindowCorrelationError(f"audio comparison worst window {index} is not an object")
        start = integer(window.get("start_frame"))
        end = integer(window.get("end_frame"))
        if start is None or end is None:
            start_seconds = number(window.get("start_seconds"))
            end_seconds = number(window.get("end_seconds"))
            if start_seconds is None or end_seconds is None:
                raise WindowCorrelationError(f"audio comparison worst window {index} needs start/end frames or seconds")
            start = int(math.floor(start_seconds * sample_rate))
            end = int(math.ceil(end_seconds * sample_rate))
        if start < 0 or end <= start:
            raise WindowCorrelationError(f"audio comparison worst window {index} has invalid bounds")
        result.append((start, end))
    return result


def dedupe_windows(windows: list[tuple[int, int]]) -> list[tuple[int, int]]:
    seen = set()
    result = []
    for window in windows:
        if window not in seen:
            seen.add(window)
            result.append(window)
    return result


def build_report(
    runtime_wav: Path,
    offline_wav: Path,
    runtime_trace: Path,
    windows: list[str],
    window_frames: list[str],
    comparison_json: Path | None = None,
    comparison_window_limit: int = 5,
    offline_diagnostics_json: Path | None = None,
    alignment_search_frames: int = DEFAULT_ALIGNMENT_SEARCH_FRAMES,
    trace_padding_frames: int = DEFAULT_TRACE_PADDING_FRAMES,
    trace_event_limit: int = DEFAULT_EVENT_LIMIT,
) -> dict[str, Any]:
    runtime_info = wav_info(runtime_wav)
    offline_info = wav_info(offline_wav)
    if runtime_info["sample_rate"] != offline_info["sample_rate"]:
        raise WindowCorrelationError("runtime and offline WAV sample rates must match")
    if runtime_info["channel_count"] != offline_info["channel_count"]:
        raise WindowCorrelationError("runtime and offline WAV channel counts must match")
    trace = load_trace(runtime_trace)
    offline_diagnostics = load_json(offline_diagnostics_json, "offline diagnostics JSON") if offline_diagnostics_json else None
    parsed_windows = [parse_window(window, runtime_info["sample_rate"], False) for window in windows]
    parsed_windows += [parse_window(window, runtime_info["sample_rate"], True) for window in window_frames]
    if comparison_json:
        parsed_windows += comparison_windows(comparison_json, runtime_info["sample_rate"], comparison_window_limit)
    parsed_windows = dedupe_windows(parsed_windows)
    if not parsed_windows:
        raise WindowCorrelationError("at least one --window, --window-frames, or --comparison-json window is required")

    window_reports = []
    for rank, (start, end) in enumerate(parsed_windows, start=1):
        frames = end - start
        complete = end <= runtime_info["frame_count"] and end <= offline_info["frame_count"]
        runtime_samples = read_wav_window(runtime_wav, start, frames, runtime_info)
        offline_samples = read_wav_window(offline_wav, start, frames, offline_info)
        audio = {
            "runtime": audio_stats(runtime_samples, runtime_info["channel_count"]),
            "offline": audio_stats(offline_samples, offline_info["channel_count"]),
            "alignment": alignment_metrics(
                offline_wav, runtime_wav, offline_info, runtime_info, start, end, alignment_search_frames,
            ),
        }
        runtime_corr = trace_correlation(trace, start, end, max(0, trace_padding_frames), trace_event_limit)
        offline_corr = offline_correlation(offline_diagnostics, start, end, max(0, trace_padding_frames)) if offline_diagnostics else None
        window_reports.append({
            "rank": rank,
            "start_frame": start,
            "end_frame": end,
            "start_seconds": rounded(start / runtime_info["sample_rate"]),
            "end_seconds": rounded(end / runtime_info["sample_rate"]),
            "duration_seconds": rounded(frames / runtime_info["sample_rate"]),
            "frame_complete": complete,
            "audio": audio,
            "runtime_trace_correlation": runtime_corr,
            "offline_diagnostics_correlation": offline_corr or {"provided": False},
            "runtime_vs_offline_event_category_comparison": category_comparison(runtime_corr, offline_corr),
            "assessment": classify(audio, runtime_corr, offline_corr, complete),
        })

    return {
        "schema_version": 1,
        "tool": "scripts/correlate-runtime-offline-window.py",
        "local_only": True,
        "notes": [
            "Diagnostic evidence only; this tool does not change playback, rendering, gain, timing, or mixer DSP.",
            "Generated reports from private/local modules must stay outside git.",
            "Positive runtime_shift_frames means the runtime comparison slice starts later than the offline window.",
        ],
        "inputs": {
            "runtime_wav": public_wav_info(runtime_info),
            "offline_wav": public_wav_info(offline_info),
            "runtime_trace_path_name": runtime_trace.name,
            "offline_diagnostics_path_name": offline_diagnostics_json.name if offline_diagnostics_json else None,
            "audio_comparison_path_name": comparison_json.name if comparison_json else None,
        },
        "configuration": {
            "alignment_search_frames": max(0, alignment_search_frames),
            "trace_padding_frames": max(0, trace_padding_frames),
            "trace_event_limit": trace_event_limit,
        },
        "windows": window_reports,
        "recommendation_counts": dict(sorted(Counter(row["assessment"]["recommended_next_pr"] for row in window_reports).items())),
        "recommended_next_pr": choose_recommendation(window_reports),
    }


def choose_recommendation(windows: list[dict[str, Any]]) -> str:
    seen = {window["assessment"]["recommended_next_pr"] for window in windows}
    for key in ("capture", "voice", "burst", "amplitude", "timing", "offline"):
        if RECOMMENDATIONS[key] in seen:
            return RECOMMENDATIONS[key]
    return RECOMMENDATIONS["burst"]


def build_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Runtime / Offline Window Correlation",
        "",
        "Diagnostic evidence only; generated reports from private/local modules must stay outside git.",
        "",
        "## Inputs",
        f"- Runtime WAV: {report['inputs']['runtime_wav']['path_name']}",
        f"- Offline WAV: {report['inputs']['offline_wav']['path_name']}",
        f"- Runtime trace: {report['inputs']['runtime_trace_path_name']}",
        f"- Audio comparison: {report['inputs']['audio_comparison_path_name'] or 'not provided'}",
        f"- Offline diagnostics: {report['inputs']['offline_diagnostics_path_name'] or 'not provided'}",
        "",
        "## Recommendation",
        f"- Recommended next PR: {report['recommended_next_pr']}",
        "",
        "## Windows",
    ]
    for window in report["windows"]:
        audio = window["audio"]
        zero = audio["alignment"]["zero_shift"]
        best = audio["alignment"]["best_shift"] or {}
        normalized = audio["alignment"]["scalar_normalized_zero_shift"]
        trace = window["runtime_trace_correlation"]
        assessment_row = window["assessment"]
        lines.extend([
            "",
            f"### Window {window['rank']}: {window['start_seconds']:.6f}-{window['end_seconds']:.6f} s",
            f"- Runtime peak/RMS: {audio['runtime']['peak']:.8f} / {audio['runtime']['rms']:.8f}",
            f"- Offline peak/RMS: {audio['offline']['peak']:.8f} / {audio['offline']['rms']:.8f}",
            f"- Correlation/RMS diff/max diff: {optional_float(zero['normalized_correlation'])} / "
            f"{zero['rms_difference']:.8f} / {zero['max_abs_difference']:.8f}",
            f"- Best runtime shift: {best.get('runtime_shift_frames')} frames, "
            f"correlation={optional_float(best.get('normalized_correlation'))}, "
            f"rms_diff={optional_float(best.get('rms_difference'))}",
            f"- Scalar runtime-to-offline: {optional_float(audio['alignment']['runtime_to_offline_scalar'])}; "
            f"normalized RMS diff={normalized['rms_difference']:.8f}",
            f"- Assessment: {assessment_row['mismatch_looks_like']} ({assessment_row['classification']})",
            f"- Recommended next PR: {assessment_row['recommended_next_pr']}",
            f"- Runtime trace events nearby: {trace['event_count']} {trace['category_counts']}",
            f"- Active voices: {trace['active_voice_range']['min']}...{trace['active_voice_range']['max']}; "
            f"loaded voices: {trace['loaded_voice_range']['min']}...{trace['loaded_voice_range']['max']}",
        ])
        if trace["same_frame_bursts"]:
            burst = trace["same_frame_bursts"][0]
            lines.append(
                f"- Largest same-frame burst: frame={burst['runtime_frame']} count={burst['event_count']} "
                f"categories={burst['categories']} voices={burst['active_voice_count_before']}->{burst['active_voice_count_after']}"
            )
        if window["offline_diagnostics_correlation"].get("provided"):
            offline = window["offline_diagnostics_correlation"]
            lines.append(f"- Offline diagnostics nearby: {offline['event_count']} {offline['category_counts']}")
        lines.append(f"- Evidence: {'; '.join(assessment_row['evidence'])}")
    return "\n".join(lines) + "\n"


def optional_float(value: Any) -> str:
    value_number = number(value)
    return "unavailable" if value_number is None else f"{value_number:.8f}"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Correlate runtime/offline C mixer mismatch windows.")
    parser.add_argument("--runtime-wav", required=True, type=Path)
    parser.add_argument("--offline-wav", required=True, type=Path)
    parser.add_argument("--runtime-trace", required=True, type=Path)
    parser.add_argument("--offline-diagnostics-json", type=Path)
    parser.add_argument("--comparison-json", type=Path)
    parser.add_argument("--comparison-window-limit", type=int, default=5)
    parser.add_argument("--window", action="append", default=[], help="Seconds window START:END, repeatable")
    parser.add_argument("--window-frames", action="append", default=[], help="Frame window START:END, repeatable")
    parser.add_argument("--alignment-search-frames", type=int, default=DEFAULT_ALIGNMENT_SEARCH_FRAMES)
    parser.add_argument("--trace-padding-frames", type=int, default=DEFAULT_TRACE_PADDING_FRAMES)
    parser.add_argument("--trace-event-limit", type=int, default=DEFAULT_EVENT_LIMIT)
    parser.add_argument("--json", dest="json_report", type=Path)
    parser.add_argument("--markdown", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    for name in ("alignment_search_frames", "trace_padding_frames", "trace_event_limit", "comparison_window_limit"):
        if getattr(args, name) < 0:
            print(f"--{name.replace('_', '-')} must be zero or greater", file=sys.stderr)
            return 2
    try:
        report = build_report(
            runtime_wav=args.runtime_wav,
            offline_wav=args.offline_wav,
            runtime_trace=args.runtime_trace,
            windows=args.window,
            window_frames=args.window_frames,
            comparison_json=args.comparison_json,
            comparison_window_limit=args.comparison_window_limit,
            offline_diagnostics_json=args.offline_diagnostics_json,
            alignment_search_frames=args.alignment_search_frames,
            trace_padding_frames=args.trace_padding_frames,
            trace_event_limit=args.trace_event_limit,
        )
    except (WindowCorrelationError, OSError, wave.Error) as error:
        print(f"correlate-runtime-offline-window: {error}", file=sys.stderr)
        return 1
    markdown = build_markdown(report)
    if args.json_report:
        args.json_report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.markdown:
        args.markdown.write_text(markdown, encoding="utf-8")
    if not args.json_report and not args.markdown:
        print(markdown, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
