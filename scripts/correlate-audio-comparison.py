#!/usr/bin/env python3
"""Correlate local audio comparison mismatch windows with bounded adapter diagnostics."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


DEFAULT_PRECEDING_EVENTS = 5
DEFAULT_CONTEXT_ROWS = 8


class CorrelationError(Exception):
    """A user-facing correlation input or validation error."""


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

    lines.extend([
        "",
        "## Notes",
        "- Event overlap is approximate because looped events are bounded to the rendered segment and one-shot duration uses available sample-step diagnostics.",
        "- Missing diagnostics fields are reported as unavailable rather than inferred.",
        "- Use this report to choose a focused follow-up PR; do not treat it as an automatic audio fix.",
    ])
    return "\n".join(lines) + "\n"


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
        "| Source | Channel | Note | Instrument/Sample | Frames | Pitch | Gain/Pan | Volume Column | Fxx | Envelope | Loop |",
        "| --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- |",
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
            f"{event['_start_frame']}-{event['_end_frame']} | "
            f"{pitch_label(nested_dict(event.get('pitch')))} | "
            f"{format_optional_float(event.get('gain'))}/{format_optional_float(event.get('pan'))} | "
            f"{volume_column_label(nested_dict(event.get('volume_column')))} | "
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
    deferred = []
    if envelope.get("has_deferred_sustain"):
        deferred.append("sustain")
    if envelope.get("has_deferred_loop"):
        deferred.append("loop")
    if envelope.get("has_deferred_fadeout"):
        deferred.append("fadeout")
    suffix = f"; deferred {','.join(deferred)}" if deferred else ""
    return (
        f"{format_optional(envelope.get('status'))} "
        f"{format_optional(envelope.get('mapped_point_count'))}/{format_optional(envelope.get('source_point_count'))}"
        f"{suffix}"
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
