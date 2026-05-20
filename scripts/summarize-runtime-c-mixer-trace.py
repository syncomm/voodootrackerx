#!/usr/bin/env python3
"""Summarize local runtime C mixer JSONL traces for A/B diagnostics."""

from __future__ import annotations

import argparse
import json
import math
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


def count_if(events: list[dict[str, Any]], predicate: Any) -> int:
    return sum(1 for event in events if predicate(event))


def context_key(event: dict[str, Any]) -> tuple[Any, Any, Any, Any]:
    return (
        event.get("orderIndex"),
        event.get("patternIndex"),
        event.get("rowIndex"),
        event.get("tickInRow"),
    )


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
    parity_categories = summarize_update_parity(events)

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

    large_event_burst = bool(bursts and bursts[0]["event_count"] >= 24)

    if hard_replacement_stops:
        recommended_next_pr = "Runtime C Mixer Hard Stop / Replacement Follow-Up"
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
            "runtime_driver": "PlaybackEngine timer/control events",
            "offline_adapter_event_stream_observed": False,
            "assessment": (
                "runtime trace is driven by PlaybackEngine actions, not the richer bounded offline adapter event stream"
            ),
        },
        "event_bursts": bursts,
        "suspicious_findings": suspicious_findings,
        "recommended_next_pr": recommended_next_pr,
    }


def build_markdown(summary: dict[str, Any]) -> str:
    health = summary["health"]
    stops = summary["stops"]
    updates = summary["updates"]
    voices = summary["voices"]
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
    lines.append(f"- Assessment: {summary['event_stream']['assessment']}")

    lines.extend(["", "## Event Bursts", ""])
    if summary["event_bursts"]:
        for burst in summary["event_bursts"]:
            context = f"order={burst['order_index']} pattern={burst['pattern_index']} row={burst['row_index']} tick={burst['tick_in_row']}"
            lines.append(f"- {context}: {burst['event_count']} events {burst['actions']}")
    else:
        lines.append("- None")

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
