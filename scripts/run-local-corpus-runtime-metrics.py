#!/usr/bin/env python3
"""Run local-only runtime metrics diagnostics for anonymized XM corpus labels."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_APP_PATH = REPO_ROOT / "build" / "Build" / "Products" / "Debug" / "VoodooTrackerX.app" / "Contents" / "MacOS" / "VoodooTrackerX"
LABEL_RE = re.compile(r"^xm-corpus-\d{3,}$")
PRIVATE_LABEL_MAP_ENV = "VTX_PRIVATE_XM_CORPUS_LABEL_MAP"
DEFAULT_SECONDS = 10.0
DEFAULT_TIMEOUT_PAD_SECONDS = 8.0


class MetricsRunError(Exception):
    """A user-facing local metrics run error."""


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run disabled-by-default local runtime diagnostics for anonymized private XM corpus labels."
    )
    parser.add_argument(
        "--label-map",
        type=Path,
        default=env_path(PRIVATE_LABEL_MAP_ENV),
        help=f"Local private corpus label map path. Defaults to ${PRIVATE_LABEL_MAP_ENV} when set.",
    )
    parser.add_argument("--labels", help="Comma-separated labels such as xm-corpus-001,xm-corpus-002")
    parser.add_argument("--limit", type=int, help="Run the first N labels from the map when --labels is omitted")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=default_output_dir(),
        help="Output directory for local-only artifacts. Defaults to a timestamped /tmp directory.",
    )
    parser.add_argument("--app-path", type=Path, default=DEFAULT_APP_PATH, help="Debug app executable path")
    parser.add_argument(
        "--seconds",
        "--stop-after-seconds",
        dest="seconds",
        type=float,
        default=DEFAULT_SECONDS,
        help=f"Playback duration before each debug stop (default: {DEFAULT_SECONDS:g})",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        help="Process timeout. Defaults to --seconds plus a short shutdown pad.",
    )
    parser.add_argument(
        "--single-play",
        action="store_true",
        help="Run only the initial autoplay/stop cycle instead of the default Stop/Play cache-reuse cycle.",
    )
    parser.add_argument(
        "--pre-play-delay-seconds",
        type=float,
        default=0.0,
        help="Debug-only delay before the initial autoplay request, giving async prewarm a fixed window (default: 0).",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print planned anonymized labels only")
    parser.add_argument(
        "--allow-repo-output",
        action="store_true",
        help="Allow writing output inside the repository. Intended only for synthetic tests.",
    )
    return parser.parse_args(argv)


def env_path(name: str) -> Path | None:
    value = os.environ.get(name, "").strip()
    return Path(value) if value else None


def default_output_dir() -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%SZ")
    return Path("/tmp") / f"vtx-runtime-metrics-{stamp}"


def load_label_map(path: Path | None) -> list[dict[str, Any]]:
    if path is None:
        raise MetricsRunError(f"missing --label-map or ${PRIVATE_LABEL_MAP_ENV}")
    if not path.exists():
        raise MetricsRunError("label map does not exist")
    loaded = json.loads(path.read_text(encoding="utf-8"))
    entries = loaded if isinstance(loaded, list) else loaded.get("entries") if isinstance(loaded, dict) else None
    if not isinstance(entries, list):
        raise MetricsRunError("label map must be a JSON array or an object with an entries array")
    normalized = [normalize_entry(entry) for entry in entries if isinstance(entry, dict)]
    return [entry for entry in normalized if entry is not None]


def normalize_entry(entry: dict[str, Any]) -> dict[str, Any] | None:
    label = entry.get("stable_anonymized_label") or entry.get("label")
    source_path = entry.get("path")
    if not isinstance(label, str) or not LABEL_RE.fullmatch(label):
        return None
    if not isinstance(source_path, str) or not source_path:
        return None
    return {"label": label, "path": Path(source_path)}


def select_entries(entries: list[dict[str, Any]], labels: str | None, limit: int | None) -> list[dict[str, Any]]:
    if labels and limit is not None:
        raise MetricsRunError("use --labels or --limit, not both")
    if labels:
        requested = [label.strip() for label in labels.split(",") if label.strip()]
        invalid = [label for label in requested if not LABEL_RE.fullmatch(label)]
        if invalid:
            raise MetricsRunError(f"invalid anonymized label: {invalid[0]}")
        by_label = {entry["label"]: entry for entry in entries}
        missing = [label for label in requested if label not in by_label]
        if missing:
            raise MetricsRunError(f"label not found in map: {missing[0]}")
        return [by_label[label] for label in requested]
    if limit is None:
        raise MetricsRunError("provide --labels or --limit")
    if limit <= 0:
        raise MetricsRunError("--limit must be positive")
    return entries[:limit]


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(parent.resolve(strict=False))
        return True
    except ValueError:
        return False


def validate_output_dir(path: Path, allow_repo_output: bool) -> None:
    if is_relative_to(path, REPO_ROOT) and not allow_repo_output:
        raise MetricsRunError("refusing to write diagnostics inside the repository; use /tmp or --allow-repo-output")
    if path.exists() and not path.is_dir():
        raise MetricsRunError("output path exists and is not a directory")


def validate_app(path: Path) -> None:
    if not path.exists():
        raise MetricsRunError("app executable does not exist; build the Debug app or pass --app-path")
    if not path.is_file():
        raise MetricsRunError("app path is not a file")


def run_entry(
    entry: dict[str, Any],
    app_path: Path,
    output_dir: Path,
    seconds: float,
    timeout_seconds: float,
    replay_after_stop: bool,
    pre_play_delay_seconds: float,
) -> dict[str, Any]:
    label = entry["label"]
    source_path = entry["path"]
    label_dir = output_dir / label
    label_dir.mkdir(parents=True, exist_ok=True)

    stdout_path = label_dir / f"{label}.stdout.txt"
    stderr_path = label_dir / f"{label}.stderr.txt"
    runtime_trace_path = label_dir / f"{label}.runtime-c-mixer-trace.jsonl"
    metrics_path = label_dir / f"{label}.metrics.json"

    diagnostic_env = {
        "VTX_OPEN_PATH": str(source_path),
        "VTX_AUDIO_BACKEND": "c_mixer",
        "VTX_DEBUG_AUTOPLAY": "1",
        "VTX_DEBUG_STOP_AFTER_SECONDS": format_seconds(seconds),
        "VTX_DEBUG_REPLAY_AFTER_STOP": "1" if replay_after_stop else "0",
        "VTX_DEBUG_PRE_PLAY_DELAY_SECONDS": format_nonnegative_seconds(pre_play_delay_seconds),
        "VTX_PLAYBACK_TIMING_TRACE": "1",
        "VTX_ADAPTER_PLAN_PROFILE": "1",
        "VTX_RUNTIME_MIXER_METRICS_TRACE": "1",
        "VTX_C_MIXER_RUNTIME_TRACE_PATH": str(runtime_trace_path),
    }
    env = os.environ.copy()
    env.update(diagnostic_env)

    started = time.monotonic()
    process = subprocess.Popen(
        [str(app_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    timed_out = False
    terminated_after_window = False
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        terminated_after_window = True
        process.terminate()
        try:
            stdout, stderr = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate()
    return_code = process.returncode
    elapsed = time.monotonic() - started

    redactions = [
        source_path,
        source_path.expanduser(),
        source_path.resolve(strict=False),
        app_path,
        app_path.expanduser(),
        app_path.resolve(strict=False),
    ]
    stdout_path.write_text(redact(stdout, redactions), encoding="utf-8")
    stderr_path.write_text(redact(stderr, redactions), encoding="utf-8")

    timing_records = parse_prefixed_records(stderr, "vtx_playback_timing")
    adapter_plan_profile_records = parse_prefixed_records(stderr, "vtx_adapter_plan_profile")
    metrics_records = parse_prefixed_records(stderr, "vtx_runtime_mixer_metrics")
    timings = summarize_timings(timing_records)
    adapter_plan_profile = summarize_adapter_plan_profile(adapter_plan_profile_records)
    metrics = summarize_runtime_metrics(metrics_records)
    outcome = process_outcome(return_code, timed_out, terminated_after_window)
    summary = {
        "schema": 1,
        "label": label,
        "process_outcome": outcome,
        "return_code": return_code,
        "elapsed_wall_seconds": round(elapsed, 3),
        "seconds": seconds,
        "timeout_seconds": timeout_seconds,
        "replay_after_stop": replay_after_stop,
        "pre_play_delay_seconds": pre_play_delay_seconds,
        "playback_timing_line_count": len(timing_records),
        "adapter_plan_profile_line_count": len(adapter_plan_profile_records),
        "runtime_mixer_metrics_line_count": len(metrics_records),
        "runtime_trace_written": runtime_trace_path.exists(),
        "runtime_trace_bytes": runtime_trace_path.stat().st_size if runtime_trace_path.exists() else 0,
        "stdout_log": stdout_path.name,
        "stderr_log": stderr_path.name,
        "runtime_trace": runtime_trace_path.name,
        "metadata": timings["metadata"],
        "timings_ms": timings["timings_ms"],
        "adapter_plan_profile": adapter_plan_profile,
        "runtime_metrics": metrics,
    }
    metrics_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return summary


def redact(text: str, source_paths: list[Path]) -> str:
    redacted = text
    tokens: set[str] = set()
    for path in source_paths:
        text_path = str(path)
        if text_path:
            tokens.add(text_path)
        if path.name:
            tokens.add(path.name)
        if path.stem:
            tokens.add(path.stem)
    for token in sorted(tokens, key=len, reverse=True):
        redacted = redacted.replace(token, "[redacted]")
    return redacted


def parse_prefixed_records(text: str, prefix: str) -> list[dict[str, str]]:
    records = []
    for line in text.splitlines():
        if not line.startswith(prefix + " "):
            continue
        fields: dict[str, str] = {}
        for part in line.split()[1:]:
            key, separator, value = part.partition("=")
            if separator:
                fields[key] = value
        records.append(fields)
    return records


def summarize_timings(records: list[dict[str, str]]) -> dict[str, Any]:
    load_records = records_for_lifecycle_occurrence(records, "load", 0)
    prewarm_records = records_for_lifecycle_occurrence(records, "prewarm", 0)
    first_play_records = records_for_lifecycle_occurrence(records, "play", 0)
    second_play_records = records_for_lifecycle_occurrence(records, "play", 1)
    prewarm_make = elapsed_ms_in_records(prewarm_records, "runtime_adapter_event_plan_prewarm_make")
    prewarm_configure = elapsed_ms_in_records(prewarm_records, "runtime_adapter_event_plan_prewarm_configure")
    first_play_make = elapsed_ms_in_records(first_play_records, "runtime_adapter_event_plan_make")
    first_play_configure = elapsed_ms_in_records(first_play_records, "runtime_adapter_event_plan_configure")
    second_play_make = elapsed_ms_in_records(second_play_records, "runtime_adapter_event_plan_make")
    second_play_configure = elapsed_ms_in_records(second_play_records, "runtime_adapter_event_plan_configure")
    first_play_mode = adapter_plan_mode(first_play_records)
    second_play_mode = adapter_plan_mode(second_play_records)
    prewarm_total_record = record_for_phase(prewarm_records, "total") or {}
    timings: dict[str, Any] = {
        "load_total": elapsed_ms_in_records(load_records, "total"),
        "module_metadata_loader_load": elapsed_ms_in_records(load_records, "module_metadata_loader_load"),
        "playback_song_builder_build": elapsed_ms_in_records(load_records, "playback_song_builder_build"),
        "playback_engine_load": elapsed_ms_in_records(load_records, "playback_engine_load"),
        "runtime_adapter_event_plan_make": elapsed_ms_in_records(load_records, "runtime_adapter_event_plan_make"),
        "runtime_adapter_event_plan_configure": elapsed_ms_in_records(load_records, "runtime_adapter_event_plan_configure"),
        "prewarm_total": elapsed_ms_in_records(prewarm_records, "total"),
        "prewarm_outcome": prewarm_total_record.get("prewarm_outcome"),
        "prewarm_runtime_adapter_event_plan_make": prewarm_make,
        "prewarm_runtime_adapter_event_plan_configure": prewarm_configure,
        "first_play_total": elapsed_ms_in_records(first_play_records, "total"),
        "first_play_runtime_adapter_plan_mode": first_play_mode,
        "first_play_runtime_adapter_event_plan_make": first_play_make,
        "first_play_runtime_adapter_event_plan_configure": first_play_configure,
        "second_play_total": elapsed_ms_in_records(second_play_records, "total"),
        "second_play_runtime_adapter_plan_mode": second_play_mode,
        "second_play_runtime_adapter_event_plan_make": second_play_make,
        "second_play_runtime_adapter_event_plan_configure": second_play_configure,
        "playback_engine_start_position_resolution": elapsed_ms_in_records(
            first_play_records, "playback_engine_start_position_resolution"
        ),
        "playback_engine_transient_runtime_state_reset": elapsed_ms_in_records(
            first_play_records, "playback_engine_transient_runtime_state_reset"
        ),
        "runtime_adapter_event_consumption_schedule_setup": elapsed_ms_in_records(
            first_play_records, "runtime_adapter_event_consumption_schedule_setup"
        ),
        "coreaudio_output_prepare": elapsed_ms_in_records(first_play_records, "coreaudio_output_prepare"),
        "coreaudio_output_start": elapsed_ms_in_records(first_play_records, "coreaudio_output_start"),
    }
    make_ms = timings["runtime_adapter_event_plan_make"] or 0.0
    configure_ms = timings["runtime_adapter_event_plan_configure"] or 0.0
    timings["runtime_adapter_plan_total"] = round(make_ms + configure_ms, 3) if make_ms or configure_ms else None
    prewarm_plan_ms = (prewarm_make or 0.0) + (prewarm_configure or 0.0)
    timings["prewarm_runtime_adapter_plan_total"] = round(prewarm_plan_ms, 3) if prewarm_plan_ms else None
    timings["prewarm_completed_before_first_play"] = first_play_mode == "prewarmed"
    first_play_plan_ms = (first_play_make or 0.0) + (first_play_configure or 0.0)
    second_play_plan_ms = (second_play_make or 0.0) + (second_play_configure or 0.0)
    timings["first_play_runtime_adapter_plan_total"] = round(first_play_plan_ms, 3) if first_play_plan_ms else None
    timings["second_play_runtime_adapter_plan_total"] = round(second_play_plan_ms, 3) if second_play_plan_ms else None
    timings["play_total"] = timings["first_play_total"]
    timings["second_play_reused_runtime_adapter_plan"] = (
        bool(second_play_records)
        and (
            second_play_mode == "cached_reuse"
            or timings["second_play_runtime_adapter_plan_total"] is None
        )
    )

    load_total = record_for_phase(load_records, "total") or {}
    metadata = {
        "module_type": load_total.get("module_type"),
        "channel_count": int_value(load_total.get("channel_count")),
        "order_count": int_value(load_total.get("order_count")),
        "pattern_count": int_value(load_total.get("pattern_count")),
        "instrument_count": int_value(load_total.get("instrument_count")),
    }
    return {"metadata": metadata, "timings_ms": timings}


def adapter_plan_mode(records: list[dict[str, str]]) -> str | None:
    ready = record_for_phase(records, "runtime_adapter_event_plan_ready_for_play")
    if ready and ready.get("play_adapter_plan_mode"):
        return ready["play_adapter_plan_mode"]
    if elapsed_ms_in_records(records, "runtime_adapter_event_plan_make") is not None:
        return "sync_fallback"
    return None


def summarize_adapter_plan_profile(records: list[dict[str, str]]) -> dict[str, Any]:
    lifecycles: dict[str, Any] = {}
    for lifecycle in sorted({record.get("lifecycle") for record in records if record.get("lifecycle")}):
        lifecycle_records = [record for record in records if record.get("lifecycle") == lifecycle]
        lifecycles[lifecycle] = summarize_adapter_plan_profile_lifecycle(lifecycle_records)
    primary_lifecycle = "prewarm" if "prewarm" in lifecycles else "play" if "play" in lifecycles else None
    primary = lifecycles.get(primary_lifecycle, {}) if primary_lifecycle else {}
    return {
        "available": bool(records),
        "line_count": len(records),
        "primary_lifecycle": primary_lifecycle,
        "adapter_plan_total_ms": primary.get("runtime_c_mixer_adapter_event_plan_make_total"),
        "adapt_total_ms": primary.get("playback_song_synthetic_adapter_adapt_total"),
        "backend_configure_ms": primary.get("backend_plan_configuration"),
        "top_phases": primary.get("top_phases", []),
        "planned_event_count": primary.get("planned_event_count"),
        "order_count": primary.get("order_count"),
        "pattern_count": primary.get("pattern_count"),
        "row_count": primary.get("row_count"),
        "category_count": primary.get("category_count"),
        "planned_song_end_frame": primary.get("planned_song_end_frame"),
        "lifecycles": lifecycles,
    }


def summarize_adapter_plan_profile_lifecycle(records: list[dict[str, str]]) -> dict[str, Any]:
    phase_timings: dict[str, float] = {}
    for record in records:
        phase = record.get("phase")
        elapsed = float_value(record.get("elapsed_ms"))
        if phase and elapsed is not None:
            phase_timings[phase] = elapsed
    total_record = record_for_phase(records, "runtime_c_mixer_adapter_event_plan_make_total") or {}
    adapt_record = record_for_phase(records, "playback_song_synthetic_adapter_adapt_total") or {}
    sorting_record = record_for_phase(records, "event_sorting_grouping") or {}
    count_source = total_record or sorting_record or adapt_record
    return {
        **phase_timings,
        "top_phases": top_adapter_plan_profile_phases(phase_timings),
        "planned_event_count": int_value(count_source.get("planned_event_count")),
        "order_count": int_value(count_source.get("order_count")),
        "pattern_count": int_value(count_source.get("pattern_count")),
        "row_count": int_value(count_source.get("row_count")),
        "category_count": int_value(count_source.get("category_count")),
        "planned_song_end_frame": int_value(count_source.get("planned_song_end_frame")),
    }


def top_adapter_plan_profile_phases(phase_timings: dict[str, float]) -> list[dict[str, Any]]:
    excluded = {
        "runtime_c_mixer_adapter_event_plan_make_total",
        "playback_song_synthetic_adapter_adapt_total",
    }
    candidates = [
        {"phase": phase, "elapsed_ms": elapsed}
        for phase, elapsed in phase_timings.items()
        if phase not in excluded
    ]
    candidates.sort(key=lambda item: item["elapsed_ms"], reverse=True)
    return candidates[:3]


def summarize_runtime_metrics(records: list[dict[str, str]]) -> dict[str, Any]:
    stop_summary = next((record for record in reversed(records) if record.get("phase") == "stop_summary"), None)
    if stop_summary is None:
        return {"available": False}
    return {
        "available": True,
        "rendered_frame_count": int_value(stop_summary.get("rendered_frame_count")),
        "output_peak": float_value(stop_summary.get("output_peak")),
        "output_rms": float_value(stop_summary.get("output_rms")),
        "overrange_sample_count": int_value(stop_summary.get("overrange_sample_count")),
        "clipping_sample_count": int_value(stop_summary.get("clipping_sample_count")),
        "clipping_detected": bool_value(stop_summary.get("clipping_detected")),
        "output_discontinuity_count": int_value(stop_summary.get("output_discontinuity_count")),
        "adjacent_jump_count_gt_0_25": int_value(stop_summary.get("adjacent_jump_count_gt_0_25")),
        "adjacent_jump_count_gt_0_35": int_value(stop_summary.get("adjacent_jump_count_gt_0_35")),
        "adjacent_jump_count_gt_0_50": int_value(stop_summary.get("adjacent_jump_count_gt_0_50")),
        "max_output_adjacent_sample_jump": float_value(stop_summary.get("max_output_adjacent_sample_jump")),
        "runtime_output_gain": float_value(stop_summary.get("runtime_output_gain")),
        "runtime_headroom_policy": stop_summary.get("runtime_headroom_policy"),
        "runtime_default_headroom_db": float_value(stop_summary.get("runtime_default_headroom_db")),
        "runtime_gain_policy_source": stop_summary.get("runtime_gain_policy_source"),
        "runtime_auto_headroom_enabled": bool_value(stop_summary.get("runtime_auto_headroom_enabled")),
    }


def records_for_lifecycle_occurrence(records: list[dict[str, str]], lifecycle: str, occurrence_index: int) -> list[dict[str, str]]:
    occurrences: list[list[dict[str, str]]] = []
    current: list[dict[str, str]] = []
    for record in records:
        if record.get("lifecycle") != lifecycle:
            continue
        current.append(record)
        if record.get("phase") == "total":
            occurrences.append(current)
            current = []
    if current:
        occurrences.append(current)
    return occurrences[occurrence_index] if occurrence_index < len(occurrences) else []


def elapsed_ms_in_records(records: list[dict[str, str]], phase: str) -> float | None:
    record = record_for_phase(records, phase)
    return float_value(record.get("elapsed_ms")) if record else None


def record_for_phase(records: list[dict[str, str]], phase: str) -> dict[str, str] | None:
    for record in reversed(records):
        if record.get("phase") == phase:
            return record
    return None


def process_outcome(return_code: int | None, timed_out: bool, terminated_after_window: bool) -> str:
    if timed_out and terminated_after_window:
        return "terminated_after_window"
    if return_code == 0:
        return "exited_zero"
    return "exited_nonzero"


def float_value(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        return round(float(value), 3)
    except ValueError:
        return None


def int_value(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


def bool_value(value: str | None) -> bool | None:
    if value is None:
        return None
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    return None


def format_seconds(value: float) -> str:
    return f"{max(0.1, value):.3f}".rstrip("0").rstrip(".")


def format_nonnegative_seconds(value: float) -> str:
    return f"{max(0.0, value):.3f}".rstrip("0").rstrip(".") or "0"


def write_run_summary(output_dir: Path, summaries: list[dict[str, Any]]) -> Path:
    path = output_dir / "summary.json"
    payload = {
        "schema": 1,
        "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "labels": [summary["label"] for summary in summaries],
        "module_count": len(summaries),
        "process_outcomes": {summary["label"]: summary["process_outcome"] for summary in summaries},
        "playback_timing_line_counts": {summary["label"]: summary["playback_timing_line_count"] for summary in summaries},
        "adapter_plan_profile_line_counts": {
            summary["label"]: summary["adapter_plan_profile_line_count"] for summary in summaries
        },
        "runtime_mixer_metrics_line_counts": {
            summary["label"]: summary["runtime_mixer_metrics_line_count"] for summary in summaries
        },
        "runtime_trace_written": {summary["label"]: summary["runtime_trace_written"] for summary in summaries},
        "results": summaries,
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown_summary(output_dir / "summary.md", summaries)
    return path


def write_markdown_summary(path: Path, summaries: list[dict[str, Any]]) -> None:
    lines = [
        "# Local Corpus Runtime Metrics Summary",
        "",
        "Public-safe anonymized local diagnostics summary. Private filenames, paths, and titles are omitted.",
        "",
        "| Label | Load total ms | Metadata ms | Song build ms | Adapter profile total ms | Top adapter profile phases | Adapt ms | Backend configure ms | Planned events | Orders | Patterns | Rows | Categories | Song-end frame | Prewarm status | First Play ms | First Play mode | First Play adapter plan ms | Second Play ms | Second Play mode | Reused plan | Peak | RMS | Clip samples | Overrange samples | Clipping | Jump indicator |",
        "| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | --- | ---: |",
    ]
    for summary in summaries:
        timings = summary["timings_ms"]
        metrics = summary["runtime_metrics"]
        profile = summary["adapter_plan_profile"]
        lines.append(
            "| {label} | {load} | {metadata} | {build} | {profile_total} | {top_profile} | {adapt_total} | {backend_configure} | {planned_events} | {orders} | {patterns} | {rows} | {categories} | {song_end_frame} | {prewarm_status} | {first_play} | {first_mode} | {first_play_adapter} | {second_play} | {second_mode} | {reused} | {peak} | {rms} | {clips} | {overrange} | {clipping} | {jump} |".format(
                label=summary["label"],
                load=cell(timings.get("load_total")),
                metadata=cell(timings.get("module_metadata_loader_load")),
                build=cell(timings.get("playback_song_builder_build")),
                profile_total=cell(profile.get("adapter_plan_total_ms")),
                top_profile=profile_phase_cell(profile.get("top_phases", [])),
                adapt_total=cell(profile.get("adapt_total_ms")),
                backend_configure=cell(profile.get("backend_configure_ms")),
                planned_events=cell(profile.get("planned_event_count")),
                orders=cell(profile.get("order_count")),
                patterns=cell(profile.get("pattern_count")),
                rows=cell(profile.get("row_count")),
                categories=cell(profile.get("category_count")),
                song_end_frame=cell(profile.get("planned_song_end_frame")),
                prewarm_status=cell(timings.get("prewarm_outcome")),
                first_play=cell(timings.get("first_play_total")),
                first_mode=cell(timings.get("first_play_runtime_adapter_plan_mode")),
                first_play_adapter=cell(timings.get("first_play_runtime_adapter_plan_total")),
                second_play=cell(timings.get("second_play_total")),
                second_mode=cell(timings.get("second_play_runtime_adapter_plan_mode")),
                reused=str(timings.get("second_play_reused_runtime_adapter_plan")).lower()
                if timings.get("second_play_total") is not None
                else "n/a",
                peak=cell(metrics.get("output_peak")),
                rms=cell(metrics.get("output_rms")),
                clips=cell(metrics.get("clipping_sample_count")),
                overrange=cell(metrics.get("overrange_sample_count")),
                clipping=str(metrics.get("clipping_detected")).lower() if metrics.get("available") else "missing",
                jump=cell(metrics.get("max_output_adjacent_sample_jump")),
            )
        )
    lines.extend(
        [
            "",
            "These outputs are local-only diagnostics. Do not commit this report or raw logs unless a future task explicitly approves a public-safe excerpt.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cell(value: Any) -> str:
    return "n/a" if value is None else str(value)


def profile_phase_cell(phases: list[dict[str, Any]]) -> str:
    if not phases:
        return "n/a"
    return ", ".join(f"{phase['phase']}={phase['elapsed_ms']}ms" for phase in phases)


def main(argv: list[str]) -> int:
    try:
        args = parse_args(argv)
        entries = load_label_map(args.label_map)
        selected = select_entries(entries, args.labels, args.limit)
        if args.dry_run:
            for entry in selected:
                print(entry["label"])
            return 0

        validate_output_dir(args.output_dir, args.allow_repo_output)
        validate_app(args.app_path)
        if args.pre_play_delay_seconds < 0:
            raise MetricsRunError("--pre-play-delay-seconds must be non-negative")
        args.output_dir.mkdir(parents=True, exist_ok=True)
        play_count = 1 if args.single_play else 2
        timeout_seconds = args.timeout_seconds or (
            max(0.1, args.seconds) * play_count
            + max(0.0, args.pre_play_delay_seconds)
            + DEFAULT_TIMEOUT_PAD_SECONDS
        )

        summaries = []
        for entry in selected:
            summary = run_entry(
                entry,
                args.app_path,
                args.output_dir,
                args.seconds,
                timeout_seconds,
                replay_after_stop=not args.single_play,
                pre_play_delay_seconds=max(0.0, args.pre_play_delay_seconds),
            )
            summaries.append(summary)
            print(
                f"{summary['label']}: {summary['process_outcome']} "
                f"timing_lines={summary['playback_timing_line_count']} "
                f"adapter_profile_lines={summary['adapter_plan_profile_line_count']} "
                f"metrics_lines={summary['runtime_mixer_metrics_line_count']} "
                f"runtime_trace_written={str(summary['runtime_trace_written']).lower()}"
            )
        run_summary = write_run_summary(args.output_dir, summaries)
        print(f"summary: {run_summary}")
        return 0
    except (MetricsRunError, OSError, json.JSONDecodeError) as error:
        print(f"run-local-corpus-runtime-metrics: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
