#!/usr/bin/env python3
"""Analyze one local PCM WAV for likely click/discontinuity evidence."""

from __future__ import annotations

import argparse
import heapq
import json
import math
import sys
import wave
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_TOP = 50
DEFAULT_THRESHOLD_PCM16 = 12000
DEFAULT_CORRELATION_FRAMES = 128
FLOAT_DIGITS = 9


class AnalysisError(Exception):
    """A user-facing analyzer input or validation error."""


@dataclass(frozen=True)
class WavInfo:
    path: Path
    sample_rate: int
    channel_count: int
    sample_width: int
    frame_count: int

    @property
    def duration_seconds(self) -> float:
        if self.sample_rate <= 0:
            return 0.0
        return self.frame_count / self.sample_rate

    @property
    def sample_width_bits(self) -> int:
        return self.sample_width * 8

    def to_json(self) -> dict[str, Any]:
        return {
            "path_name": self.path.name,
            "sample_rate": self.sample_rate,
            "channel_count": self.channel_count,
            "sample_width_bits": self.sample_width_bits,
            "frame_count": self.frame_count,
            "duration_seconds": rounded(self.duration_seconds),
        }


@dataclass(frozen=True)
class Jump:
    frame: int
    channel_index: int
    magnitude_pcm16: int
    magnitude_normalized: float
    before_pcm16: int
    after_pcm16: int
    before_normalized: float
    after_normalized: float

    def sort_key(self) -> tuple[int, int, int]:
        return (-self.magnitude_pcm16, self.frame, self.channel_index)

    def to_json(self, rank: int, sample_rate: int) -> dict[str, Any]:
        return {
            "rank": rank,
            "frame": self.frame,
            "time_seconds": rounded(self.frame / sample_rate if sample_rate > 0 else 0.0),
            "channel_index": self.channel_index,
            "before_frame": max(0, self.frame - 1),
            "after_frame": self.frame,
            "jump_magnitude": self.magnitude_pcm16,
            "jump_magnitude_pcm16": self.magnitude_pcm16,
            "jump_magnitude_normalized": rounded(self.magnitude_normalized),
            "before_sample_pcm16": self.before_pcm16,
            "after_sample_pcm16": self.after_pcm16,
            "before_sample_normalized": rounded(self.before_normalized),
            "after_sample_normalized": rounded(self.after_normalized),
            "nearby_event_categories": [],
            "nearby_events": [],
        }


@dataclass(frozen=True)
class DiagnosticEvent:
    category: str
    label: str
    frame: int
    source: dict[str, Any]
    channel_index: Any
    status: str | None
    details: dict[str, Any]

    def to_json(self, jump_frame: int, sample_rate: int) -> dict[str, Any]:
        distance_frames = self.frame - jump_frame
        return {
            "category": self.category,
            "label": self.label,
            "event_frame": self.frame,
            "event_time_seconds": rounded(self.frame / sample_rate if sample_rate > 0 else 0.0),
            "distance_frames": distance_frames,
            "distance_seconds": rounded(distance_frames / sample_rate if sample_rate > 0 else 0.0),
            "source": self.source,
            "channel_index": self.channel_index,
            "status": self.status,
            "details": self.details,
        }


def rounded(value: float) -> float:
    return round(float(value), FLOAT_DIGITS)


def rounded_optional(value: float | None) -> float | None:
    if value is None:
        return None
    return rounded(value)


def amplitude_to_dbfs(value: float) -> float | None:
    if value <= 0.0:
        return None
    return 20.0 * math.log10(value)


def load_diagnostics_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise AnalysisError(f"missing diagnostics JSON: {path}")
    if not path.is_file():
        raise AnalysisError(f"diagnostics JSON is not a file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise AnalysisError(
            f"malformed diagnostics JSON: {path}: line {error.lineno} column {error.colno}: {error.msg}"
        ) from error
    if not isinstance(value, dict):
        raise AnalysisError(f"diagnostics JSON must contain a top-level object: {path}")
    return value


def analyze_wav(path: Path, top_count: int, threshold_pcm16: int) -> tuple[WavInfo, dict[str, Any], list[Jump]]:
    if not path.exists():
        raise AnalysisError(f"missing WAV: {path}")
    if not path.is_file():
        raise AnalysisError(f"WAV path is not a file: {path}")

    try:
        wav_file = wave.open(str(path), "rb")
    except wave.Error as error:
        raise AnalysisError(f"{path}: {error}") from error

    with wav_file:
        compression = wav_file.getcomptype()
        info = WavInfo(
            path=path,
            sample_rate=wav_file.getframerate(),
            channel_count=wav_file.getnchannels(),
            sample_width=wav_file.getsampwidth(),
            frame_count=wav_file.getnframes(),
        )
        if compression != "NONE":
            raise AnalysisError(f"{path}: only uncompressed PCM WAV files are supported")
        if info.sample_rate <= 0:
            raise AnalysisError(f"{path}: sample rate must be greater than zero")
        if info.channel_count <= 0:
            raise AnalysisError(f"{path}: channel count must be greater than zero")
        if info.sample_width not in (1, 2, 3, 4):
            raise AnalysisError(f"{path}: unsupported sample width: {info.sample_width} bytes")

        square_sum = 0.0
        peak = 0.0
        sample_count = 0
        per_channel_square = [0.0 for _ in range(info.channel_count)]
        per_channel_peak = [0.0 for _ in range(info.channel_count)]
        previous: list[tuple[int, float] | None] = [None for _ in range(info.channel_count)]
        threshold_by_channel = [0 for _ in range(info.channel_count)]
        threshold_by_second: dict[int, int] = defaultdict(int)
        pcm16_clipping_count: int | None = 0 if info.sample_width == 2 else None
        top_heap: list[tuple[tuple[int, int, int], Jump]] = []

        frame_index = 0
        bytes_per_frame = info.sample_width * info.channel_count
        while frame_index < info.frame_count:
            frames_to_read = min(8192, info.frame_count - frame_index)
            pcm = wav_file.readframes(frames_to_read)
            chunk_frames = len(pcm) // bytes_per_frame if bytes_per_frame > 0 else 0
            for local_frame in range(chunk_frames):
                base_offset = local_frame * bytes_per_frame
                for channel in range(info.channel_count):
                    offset = base_offset + (channel * info.sample_width)
                    raw_value = decode_sample(pcm, offset, info.sample_width)
                    normalized = normalized_sample(raw_value, info.sample_width)
                    pcm16_value = pcm16_equivalent(normalized)
                    abs_normalized = abs(normalized)

                    sample_count += 1
                    square_sum += normalized * normalized
                    peak = max(peak, abs_normalized)
                    per_channel_square[channel] += normalized * normalized
                    per_channel_peak[channel] = max(per_channel_peak[channel], abs_normalized)
                    if pcm16_clipping_count is not None and (raw_value <= -32768 or raw_value >= 32767):
                        pcm16_clipping_count += 1

                    prior = previous[channel]
                    if prior is not None:
                        prior_pcm16, prior_normalized = prior
                        magnitude_pcm16 = abs(pcm16_value - prior_pcm16)
                        magnitude_normalized = abs(normalized - prior_normalized)
                        if magnitude_pcm16 > threshold_pcm16:
                            threshold_by_channel[channel] += 1
                            threshold_by_second[int(frame_index / info.sample_rate)] += 1
                        if top_count > 0:
                            jump = Jump(
                                frame=frame_index,
                                channel_index=channel,
                                magnitude_pcm16=magnitude_pcm16,
                                magnitude_normalized=magnitude_normalized,
                                before_pcm16=prior_pcm16,
                                after_pcm16=pcm16_value,
                                before_normalized=prior_normalized,
                                after_normalized=normalized,
                            )
                            heap_key = (magnitude_pcm16, -frame_index, -channel)
                            if len(top_heap) < top_count:
                                heapq.heappush(top_heap, (heap_key, jump))
                            elif heap_key > top_heap[0][0]:
                                heapq.heapreplace(top_heap, (heap_key, jump))
                    previous[channel] = (pcm16_value, normalized)
                frame_index += 1

    per_channel_rms = [
        math.sqrt(total / info.frame_count) if info.frame_count > 0 else 0.0
        for total in per_channel_square
    ]
    rms = math.sqrt(square_sum / sample_count) if sample_count else 0.0
    threshold_total = sum(threshold_by_channel)
    threshold_counts_by_second = [
        {
            "start_second": second,
            "end_second": second + 1,
            "count": count,
        }
        for second, count in sorted(threshold_by_second.items())
    ]
    metrics = {
        "peak": rounded(peak),
        "peak_dbfs": rounded_optional(amplitude_to_dbfs(peak)),
        "rms": rounded(rms),
        "rms_dbfs": rounded_optional(amplitude_to_dbfs(rms)),
        "per_channel_peak": [rounded(value) for value in per_channel_peak],
        "per_channel_rms": [rounded(value) for value in per_channel_rms],
        "pcm16_clipping_count": pcm16_clipping_count,
        "threshold_pcm16": threshold_pcm16,
        "threshold_jump_count": threshold_total,
        "threshold_jump_count_by_channel": threshold_by_channel,
        "threshold_jumps_per_second": rounded(threshold_total / info.duration_seconds)
        if info.duration_seconds > 0 else 0.0,
        "threshold_jump_counts_by_second": threshold_counts_by_second,
    }
    jumps = [item[1] for item in top_heap]
    jumps.sort(key=Jump.sort_key)
    return info, metrics, jumps


def decode_sample(pcm: bytes, offset: int, sample_width: int) -> int:
    if sample_width == 1:
        return int(pcm[offset]) - 128
    return int.from_bytes(pcm[offset : offset + sample_width], byteorder="little", signed=True)


def normalized_sample(raw_value: int, sample_width: int) -> float:
    return raw_value / float(1 << ((sample_width * 8) - 1))


def pcm16_equivalent(normalized: float) -> int:
    if not math.isfinite(normalized):
        return 0
    return min(32767, max(-32768, int(round(normalized * 32768.0))))


def build_analysis(
    wav_path: Path,
    diagnostics_path: Path | None = None,
    *,
    top_count: int = DEFAULT_TOP,
    threshold_pcm16: int = DEFAULT_THRESHOLD_PCM16,
    correlation_frames: int = DEFAULT_CORRELATION_FRAMES,
) -> dict[str, Any]:
    info, metrics, jumps = analyze_wav(wav_path, top_count, threshold_pcm16)
    diagnostics = load_diagnostics_json(diagnostics_path) if diagnostics_path else None
    diagnostic_events = normalize_diagnostic_events(diagnostics or {}, info.sample_rate) if diagnostics else []
    jump_objects = [jump.to_json(index, info.sample_rate) for index, jump in enumerate(jumps, start=1)]
    attach_correlations(jump_objects, diagnostic_events, info.sample_rate, correlation_frames)

    return {
        "schema_version": 1,
        "tool": "scripts/analyze-audio-discontinuities.py",
        "local_only": True,
        "notes": [
            "Diagnostic evidence only; adjacent-sample jumps do not prove a specific mixer bug.",
            "Generated reports are local artifacts and must not be committed when derived from private modules.",
            "This analyzer does not change playback, rendering, mixer DSP, gain, pan, loop, envelope, or export behavior.",
        ],
        "wav": info.to_json(),
        "analysis": {
            "top_requested": top_count,
            "correlation_window_frames": correlation_frames,
            **metrics,
        },
        "top_adjacent_sample_jumps": jump_objects,
        "diagnostics_correlation": correlation_summary(
            diagnostics_provided=diagnostics is not None,
            diagnostics_path=diagnostics_path,
            diagnostic_event_count=len(diagnostic_events),
            jumps=jump_objects,
        ),
    }


def attach_correlations(
    jumps: list[dict[str, Any]],
    events: list[DiagnosticEvent],
    sample_rate: int,
    correlation_frames: int,
) -> None:
    for jump in jumps:
        jump_frame = int(jump["frame"])
        nearby = [
            event for event in events
            if abs(event.frame - jump_frame) <= correlation_frames
        ]
        nearby.sort(key=lambda event: (
            abs(event.frame - jump_frame),
            event.frame,
            event.category,
            event.label,
            sort_int(event.channel_index),
        ))
        jump["nearby_events"] = [event.to_json(jump_frame, sample_rate) for event in nearby]
        jump["nearby_event_categories"] = sorted({event.category for event in nearby})


def correlation_summary(
    *,
    diagnostics_provided: bool,
    diagnostics_path: Path | None,
    diagnostic_event_count: int,
    jumps: list[dict[str, Any]],
) -> dict[str, Any]:
    category_counts: Counter[str] = Counter()
    category_max: dict[str, int] = defaultdict(int)
    for jump in jumps:
        magnitude = int(jump.get("jump_magnitude_pcm16", 0))
        for category in jump.get("nearby_event_categories", []):
            category_counts[str(category)] += 1
            category_max[str(category)] = max(category_max[str(category)], magnitude)

    categories = [
        {
            "category": category,
            "top_jump_count_near_category": count,
            "max_jump_magnitude_pcm16_near_category": category_max[category],
        }
        for category, count in sorted(category_counts.items(), key=lambda item: (-item[1], item[0]))
    ]
    return {
        "diagnostics_provided": diagnostics_provided,
        "diagnostics_path_name": diagnostics_path.name if diagnostics_path else None,
        "diagnostic_event_count": diagnostic_event_count,
        "top_jump_count": len(jumps),
        "top_jumps_with_nearby_events": sum(1 for jump in jumps if jump.get("nearby_events")),
        "summary_by_category": categories,
        "disclaimer": "Nearby event categories are diagnostic evidence, not proof of root cause.",
    }


def normalize_diagnostic_events(diagnostics: dict[str, Any], sample_rate: int) -> list[DiagnosticEvent]:
    rows_by_source, rows_by_synthetic = row_frame_indexes(nested_list(diagnostics.get("row_timing")))
    events: list[DiagnosticEvent] = []

    for raw_event in nested_list(diagnostics.get("events")):
        if not isinstance(raw_event, dict):
            continue
        frame = frame_for(raw_event, sample_rate, rows_by_source, rows_by_synthetic, ["scheduled_start_frame"])
        if frame is None:
            continue
        loop_mode = str(raw_event.get("loop_mode", "none"))
        details = selected_details(raw_event, [
            "event_index", "note", "instrument_index", "sample_index", "sample_selection_method",
            "gain", "pan", "loop_mode", "initial_source_frame",
        ])
        events.append(diagnostic_event("note_trigger", "note trigger", frame, raw_event, details))
        if loop_mode and loop_mode != "none":
            events.append(diagnostic_event("looped_voice_event", f"looped voice ({loop_mode})", frame, raw_event, details))

    for update in nested_list(diagnostics.get("volume_panning_state_updates")):
        if not isinstance(update, dict):
            continue
        frame = frame_for(update, sample_rate, rows_by_source, rows_by_synthetic, ["scheduled_frame", "absolute_frame"])
        if frame is None:
            continue
        label = str(update.get("command_label") or update.get("command_name") or "gain/pan update")
        events.append(diagnostic_event(
            "gain_pan_update",
            label,
            frame,
            update,
            selected_details(update, [
                "command_source", "command_name", "active_voice_updated",
                "gain_before", "gain_after", "pan_before", "pan_after",
            ]),
        ))

    for mapping in nested_list(diagnostics.get("volume_column_mappings")):
        if not isinstance(mapping, dict):
            continue
        frame = frame_for(mapping, sample_rate, rows_by_source, rows_by_synthetic, ["scheduled_frame", "row_start_frame"])
        if frame is None:
            continue
        volume_column = nested_dict(mapping.get("volume_column"))
        command = nested_dict(volume_column.get("command"))
        events.append(diagnostic_event(
            "volume_panning_state_update",
            f"volume column {command.get('name', 'update')}",
            frame,
            mapping,
            {
                "raw_value": volume_column.get("raw_value"),
                "command": command,
                "classification": volume_column.get("classification"),
                "applied": volume_column.get("applied"),
                "deferred": volume_column.get("deferred"),
            },
        ))

    for item in nested_list(diagnostics.get("note_cut_effects")):
        append_effect_event(events, item, "ecx_note_cut", "ECx note cut", sample_rate, rows_by_source, rows_by_synthetic)
    for item in nested_list(diagnostics.get("note_delay_effects")):
        append_effect_event(events, item, "edx_note_delay", "EDx note delay", sample_rate, rows_by_source, rows_by_synthetic)
    for item in nested_list(diagnostics.get("key_off_events")):
        append_effect_event(events, item, "key_off_release", "key-off/release/fadeout", sample_rate, rows_by_source, rows_by_synthetic)
    for item in nested_list(diagnostics.get("sample_offset_effects")):
        append_effect_event(events, item, "sample_offset", "sample offset", sample_rate, rows_by_source, rows_by_synthetic)
    for item in nested_list(diagnostics.get("timing_changes")):
        append_effect_event(events, item, "timing_change", "Fxx timing change", sample_rate, rows_by_source, rows_by_synthetic)
    for item in nested_list(diagnostics.get("loop_boundaries")):
        append_effect_event(events, item, "loop_boundary", "loop boundary", sample_rate, rows_by_source, rows_by_synthetic)
    for item in nested_list(diagnostics.get("envelope_events")):
        append_effect_event(events, item, "envelope_fadeout_change", "envelope/fadeout change", sample_rate, rows_by_source, rows_by_synthetic)

    append_window_boundary_events(events, nested_dict(diagnostics.get("windowed_render")), sample_rate)
    events.sort(key=lambda event: (event.frame, event.category, event.label, sort_int(event.channel_index)))
    return events


def append_effect_event(
    events: list[DiagnosticEvent],
    raw_item: Any,
    category: str,
    label: str,
    sample_rate: int,
    rows_by_source: dict[tuple[Any, Any, Any], tuple[int, int]],
    rows_by_synthetic: dict[Any, tuple[int, int]],
) -> None:
    if not isinstance(raw_item, dict):
        return
    frame = frame_for(
        raw_item,
        sample_rate,
        rows_by_source,
        rows_by_synthetic,
        ["scheduled_frame", "absolute_frame", "delayed_frame", "release_frame", "row_start_frame"],
    )
    if frame is None:
        return
    events.append(diagnostic_event(
        category,
        label,
        frame,
        raw_item,
        selected_details(raw_item, [
            "effect_type", "effect_param", "status", "applied", "deferred",
            "ignored_as_no_op", "out_of_row", "requested_tick",
            "computed_offset_frames", "applied_offset_frames",
        ]),
    ))


def append_window_boundary_events(events: list[DiagnosticEvent], windowed: dict[str, Any], sample_rate: int) -> None:
    per_window = [item for item in nested_list(windowed.get("per_window")) if isinstance(item, dict)]
    for index, window in enumerate(per_window):
        window_index = integer(window.get("window_index"))
        start_frame = integer(window.get("start_frame"))
        end_frame = integer(window.get("end_frame"))
        details = selected_details(window, [
            "window_index", "start_row", "end_row_exclusive", "carried_voice_count",
            "boundary_continuation_count", "dropped_at_window_boundary_count",
            "may_contain_boundary_cuts",
        ])
        if start_frame is not None and index > 0:
            events.append(DiagnosticEvent(
                category="window_boundary",
                label="window start",
                frame=max(0, start_frame),
                source={},
                channel_index=None,
                status=None,
                details=details,
            ))
            if any(integer(window.get(key)) for key in (
                "carried_voice_count", "boundary_continuation_count", "dropped_at_window_boundary_count"
            )):
                events.append(DiagnosticEvent(
                    category="carried_voice_boundary",
                    label="carried voice window boundary",
                    frame=max(0, start_frame),
                    source={},
                    channel_index=None,
                    status=None,
                    details=details,
                ))
        if end_frame is not None and (window_index is None or window_index < len(per_window) - 1):
            events.append(DiagnosticEvent(
                category="window_boundary",
                label="window end",
                frame=max(0, end_frame),
                source={},
                channel_index=None,
                status=None,
                details=details,
            ))


def diagnostic_event(
    category: str,
    label: str,
    frame: int,
    item: dict[str, Any],
    details: dict[str, Any],
) -> DiagnosticEvent:
    return DiagnosticEvent(
        category=category,
        label=label,
        frame=max(0, frame),
        source=nested_dict(item.get("source")),
        channel_index=item.get("channel_index"),
        status=str(item.get("status")) if item.get("status") is not None else None,
        details=details,
    )


def frame_for(
    item: dict[str, Any],
    sample_rate: int,
    rows_by_source: dict[tuple[Any, Any, Any], tuple[int, int]],
    rows_by_synthetic: dict[Any, tuple[int, int]],
    preferred_keys: list[str],
) -> int | None:
    for key in preferred_keys + ["scheduled_start_frame", "row_start_frame", "start_frame"]:
        value = integer(item.get(key))
        if value is not None:
            return max(0, value)
    for key in ("scheduled_start_seconds", "time_seconds"):
        seconds = number(item.get(key))
        if seconds is not None and sample_rate > 0:
            return max(0, int(round(seconds * sample_rate)))
    source_range = rows_by_source.get(source_row_key(nested_dict(item.get("source"))))
    if source_range is not None:
        return source_range[0]
    synthetic_range = rows_by_synthetic.get(item.get("synthetic_row"))
    if synthetic_range is not None:
        return synthetic_range[0]
    return None


def row_frame_indexes(rows: list[Any]) -> tuple[dict[tuple[Any, Any, Any], tuple[int, int]], dict[Any, tuple[int, int]]]:
    by_source: dict[tuple[Any, Any, Any], tuple[int, int]] = {}
    by_synthetic: dict[Any, tuple[int, int]] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        start = integer(row.get("row_start_frame"))
        if start is None:
            continue
        end = integer(row.get("row_end_frame"))
        if end is None:
            duration = integer(row.get("row_duration_frames")) or 1
            end = start + max(1, duration)
        frame_range = (max(0, start), max(start + 1, end))
        by_source[source_row_key(nested_dict(row.get("source")))] = frame_range
        if row.get("synthetic_row") is not None:
            by_synthetic[row.get("synthetic_row")] = frame_range
    return by_source, by_synthetic


def selected_details(item: dict[str, Any], keys: list[str]) -> dict[str, Any]:
    return {key: item[key] for key in keys if key in item}


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
    if numeric is None:
        return None
    return int(numeric)


def source_row_key(source: dict[str, Any]) -> tuple[Any, Any, Any]:
    return (source.get("order"), source.get("pattern"), source.get("row"))


def sort_int(value: Any) -> int:
    parsed = integer(value)
    return parsed if parsed is not None else sys.maxsize


def build_markdown_report(analysis: dict[str, Any]) -> str:
    wav_info = nested_dict(analysis.get("wav"))
    metrics = nested_dict(analysis.get("analysis"))
    jumps = nested_list(analysis.get("top_adjacent_sample_jumps"))
    correlation = nested_dict(analysis.get("diagnostics_correlation"))

    lines = [
        "# Audio Discontinuity Report",
        "",
        "Diagnostic evidence only; adjacent-sample jumps and nearby events do not prove a specific root cause.",
        "",
        "## Inputs",
        f"- WAV: {wav_info.get('path_name', 'unavailable')}",
        f"- Diagnostics JSON: {correlation.get('diagnostics_path_name') or 'not provided'}",
        f"- Top jumps requested: {metrics.get('top_requested')}",
        f"- Jump threshold: {metrics.get('threshold_pcm16')} PCM16-equivalent units",
        f"- Correlation window: +/-{metrics.get('correlation_window_frames')} frames",
        "",
        "## Overall Clipping And Headroom Recap",
        f"- Format: {wav_info.get('sample_rate')} Hz, {wav_info.get('channel_count')} channel(s), {wav_info.get('sample_width_bits')}-bit PCM",
        f"- Frames/duration: {wav_info.get('frame_count')} / {float(wav_info.get('duration_seconds', 0.0)):.6f} s",
        f"- Peak: {float(metrics.get('peak', 0.0)):.8f} ({format_db(metrics.get('peak_dbfs'))})",
        f"- RMS: {float(metrics.get('rms', 0.0)):.8f} ({format_db(metrics.get('rms_dbfs'))})",
        f"- Per-channel peak: {format_float_list(metrics.get('per_channel_peak'))}",
        f"- Per-channel RMS: {format_float_list(metrics.get('per_channel_rms'))}",
        f"- PCM16 clipping samples: {format_optional(metrics.get('pcm16_clipping_count'))}",
        f"- Jumps above threshold: {metrics.get('threshold_jump_count')} ({float(metrics.get('threshold_jumps_per_second', 0.0)):.6f} / second)",
        "",
        "## Top Adjacent-Sample Jumps",
    ]
    if not jumps:
        lines.append("- None reported.")
    else:
        lines.extend([
            "| Rank | Frame | Time (s) | Channel | Magnitude | Before -> After | Nearby Categories |",
            "| ---: | ---: | ---: | ---: | ---: | --- | --- |",
        ])
        for jump in jumps:
            categories = ", ".join(jump.get("nearby_event_categories", [])) or "none"
            lines.append(
                f"| {jump.get('rank')} | {jump.get('frame')} | {float(jump.get('time_seconds', 0.0)):.6f} | "
                f"{jump.get('channel_index')} | {jump.get('jump_magnitude_pcm16')} | "
                f"{jump.get('before_sample_pcm16')} -> {jump.get('after_sample_pcm16')} | {escape_table(categories)} |"
            )

    lines.extend(["", "## Likely Nearby Event Categories"])
    summary = nested_list(correlation.get("summary_by_category"))
    if not correlation.get("diagnostics_provided"):
        lines.append("- Diagnostics JSON was not provided, so event correlation was skipped.")
    elif not summary:
        lines.append("- No diagnostic events were found near the reported top jumps.")
    else:
        lines.extend([
            "| Category | Top Jumps Near Category | Max Nearby Jump Magnitude |",
            "| --- | ---: | ---: |",
        ])
        for item in summary:
            if not isinstance(item, dict):
                continue
            lines.append(
                f"| {escape_table(str(item.get('category')))} | "
                f"{item.get('top_jump_count_near_category')} | "
                f"{item.get('max_jump_magnitude_pcm16_near_category')} |"
            )

    lines.extend([
        "",
        "## Clustering Summary",
        category_line(correlation, "gain_pan_update", "Gain/pan updates"),
        category_line(correlation, "volume_panning_state_update", "Volume/panning state updates"),
        category_line(correlation, "ecx_note_cut", "ECx note cuts"),
        category_line(correlation, "edx_note_delay", "EDx note delays"),
        category_line(correlation, "loop_boundary", "Loop boundaries"),
        category_line(correlation, "looped_voice_event", "Looped voice events"),
        category_line(correlation, "window_boundary", "Window boundaries"),
        category_line(correlation, "carried_voice_boundary", "Carried voice boundaries"),
        category_line(correlation, "key_off_release", "Key-off/release/fadeout events"),
        "",
        "## Notes",
        "- Nearby events identify where to inspect next; they are not proof that the event caused the jump.",
        "- This tool does not smooth, ramp, resample, time-align, or modify audio output.",
        "- Keep generated WAVs, JSON reports, Markdown reports, traces, logs, and private-module-derived findings outside git.",
    ])
    return "\n".join(lines) + "\n"


def category_line(correlation: dict[str, Any], category: str, label: str) -> str:
    lookup = {
        item.get("category"): item
        for item in nested_list(correlation.get("summary_by_category"))
        if isinstance(item, dict)
    }
    count = nested_dict(lookup.get(category)).get("top_jump_count_near_category", 0)
    total = correlation.get("top_jump_count", 0)
    return f"- {label}: {count} of {total} top jumps near this category."


def format_db(value: Any) -> str:
    numeric = number(value)
    if numeric is None:
        return "-inf dBFS"
    return f"{numeric:.2f} dBFS"


def format_float_list(values: Any) -> str:
    if not isinstance(values, list):
        return "unavailable"
    return "[" + ", ".join(f"{float(value):.8f}" for value in values) + "]"


def format_optional(value: Any) -> str:
    return "not applicable" if value is None else str(value)


def escape_table(value: str) -> str:
    return value.replace("|", "/")


def write_json_report(path: Path, analysis: dict[str, Any]) -> None:
    path.write_text(json.dumps(analysis, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Analyze a local WAV for likely click/crackle discontinuity evidence.",
    )
    parser.add_argument("--wav", required=True, type=Path, help="Local WAV path to analyze")
    parser.add_argument("--diagnostics-json", type=Path, help="Optional vtx_render_bounded_xm diagnostics JSON")
    parser.add_argument("--json", dest="json_report", type=Path, help="Optional JSON report output path")
    parser.add_argument("--markdown", type=Path, help="Optional Markdown report output path")
    parser.add_argument("--top", type=int, default=DEFAULT_TOP, help=f"Top adjacent jumps to report (default: {DEFAULT_TOP})")
    parser.add_argument(
        "--threshold",
        type=int,
        default=DEFAULT_THRESHOLD_PCM16,
        help=f"PCM16-equivalent jump threshold for counts (default: {DEFAULT_THRESHOLD_PCM16})",
    )
    parser.add_argument(
        "--correlation-frames",
        type=int,
        default=DEFAULT_CORRELATION_FRAMES,
        help=f"Frames on either side of a jump to search for diagnostic events (default: {DEFAULT_CORRELATION_FRAMES})",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.top < 0:
        print("--top must be zero or greater", file=sys.stderr)
        return 2
    if args.threshold < 0:
        print("--threshold must be zero or greater", file=sys.stderr)
        return 2
    if args.correlation_frames < 0:
        print("--correlation-frames must be zero or greater", file=sys.stderr)
        return 2

    try:
        analysis = build_analysis(
            args.wav,
            args.diagnostics_json,
            top_count=args.top,
            threshold_pcm16=args.threshold,
            correlation_frames=args.correlation_frames,
        )
    except (AnalysisError, wave.Error, OSError) as error:
        print(f"analyze-audio-discontinuities: {error}", file=sys.stderr)
        return 1

    markdown = build_markdown_report(analysis)
    if args.json_report:
        write_json_report(args.json_report, analysis)
    if args.markdown:
        args.markdown.write_text(markdown, encoding="utf-8")
    if not args.json_report and not args.markdown:
        print(markdown, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
