#!/usr/bin/env python3
"""Summarize local reference-render parity comparisons across anonymized cases."""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter
from pathlib import Path
from typing import Any


FLOAT_DIGITS = 9
MAX_WINDOWS_PER_REFERENCE = 5

BUCKET_RECOMMENDATIONS = {
    "envelope/key-off/fadeout": "Envelope/key-off/fadeout parity investigation",
    "interpolation/sample stepping": "Interpolation/sample-step parity investigation",
    "resampling": "Interpolation/sample-step parity investigation",
    "sample/instrument selection": "Sample/instrument selection parity investigation",
    "loop/sample offset": "Loop/sample-offset parity investigation",
    "panning/gain math": "Panning/gain math parity investigation",
    "same-cell portamento/retrigger": "Tone-portamento/retrigger semantics parity PR",
    "tone-portamento semantics": "Tone-portamento/retrigger semantics parity PR",
    "residual effect semantics": "Residual effect semantics cleanup",
    "render-gain policy": "Render-gain policy comparison",
}


class TriageError(Exception):
    """A user-facing triage input or validation error."""


def rounded(value: float) -> float:
    return round(float(value), FLOAT_DIGITS)


def rounded_optional(value: Any) -> float | None:
    numeric = number(value)
    if numeric is None:
        return None
    return rounded(numeric)


def number(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return float(value)
    return None


def nested_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def nested_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def text_list(value: Any) -> list[str]:
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return []


def amplitude_to_db(value: float | None) -> float | None:
    if value is None or value <= 0:
        return None
    return 20.0 * math.log10(value)


def db_delta(candidate: float | None, reference: float | None) -> float | None:
    candidate_db = amplitude_to_db(candidate)
    reference_db = amplitude_to_db(reference)
    if candidate_db is None or reference_db is None:
        return None
    return candidate_db - reference_db


def format_float(value: Any, digits: int = 6) -> str:
    numeric = number(value)
    if numeric is None:
        return "n/a"
    return f"{numeric:.{digits}f}"


def format_signed_db(value: Any) -> str:
    numeric = number(value)
    if numeric is None:
        return "n/a"
    return f"{numeric:+.2f} dB"


def format_bool(value: bool | None) -> str:
    if value is None:
        return "unknown"
    return "yes" if value else "no"


def load_json(path: Path, role: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise TriageError(f"missing {role}: {path}") from error
    except json.JSONDecodeError as error:
        raise TriageError(
            f"malformed JSON in {role}: {path}: line {error.lineno} column {error.colno}: {error.msg}"
        ) from error


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = load_json(path, "manifest JSON")
    if not isinstance(manifest, dict):
        raise TriageError(f"manifest JSON must contain a top-level object: {path}")
    if not isinstance(manifest.get("cases"), list):
        raise TriageError("manifest JSON must contain a cases list")
    return manifest


def comparison_metrics(comparison: dict[str, Any]) -> dict[str, Any]:
    reference = nested_dict(comparison.get("reference"))
    candidate = nested_dict(comparison.get("candidate"))
    reference_info = nested_dict(reference.get("info"))
    candidate_info = nested_dict(candidate.get("info"))
    reference_stats = nested_dict(reference.get("stats"))
    candidate_stats = nested_dict(candidate.get("stats"))
    format_info = nested_dict(comparison.get("format"))
    sample_comparison = comparison.get("sample_comparison")
    sample_available = isinstance(sample_comparison, dict)

    diff = nested_dict(sample_comparison.get("diff")) if sample_available else {}
    gain_normalized = nested_dict(sample_comparison.get("gain_normalized")) if sample_available else {}
    gain_diff = nested_dict(gain_normalized.get("diff"))
    windows = nested_list(sample_comparison.get("worst_windows")) if sample_available else []

    reference_rms = rounded_optional(reference_stats.get("overall_rms"))
    candidate_rms = rounded_optional(candidate_stats.get("overall_rms"))
    reference_peak = rounded_optional(reference_stats.get("overall_peak"))
    candidate_peak = rounded_optional(candidate_stats.get("overall_peak"))
    rms_delta_db = rounded_optional(db_delta(candidate_rms, reference_rms))
    peak_delta_db = rounded_optional(db_delta(candidate_peak, reference_peak))
    gain_reduction = rounded_optional(gain_normalized.get("rms_difference_reduction_ratio"))
    correlation = rounded_optional(sample_comparison.get("normalized_correlation")) if sample_available else None
    overall_rms_diff = rounded_optional(diff.get("overall_rms_difference"))
    max_abs_diff = rounded_optional(diff.get("max_abs_sample_difference"))
    gain_normalized_rms_diff = rounded_optional(gain_diff.get("overall_rms_difference"))
    gain_normalized_max_abs_diff = rounded_optional(gain_diff.get("max_abs_sample_difference"))

    top_window_rms = None
    top_window_max_abs = None
    if windows and isinstance(windows[0], dict):
        top_window_rms = rounded_optional(windows[0].get("rms_difference"))
        top_window_max_abs = rounded_optional(windows[0].get("max_abs_sample_difference"))

    return {
        "reference_info": {
            "sample_rate": reference_info.get("sample_rate"),
            "channel_count": reference_info.get("channel_count"),
            "sample_width_bits": reference_info.get("sample_width_bits"),
            "frame_count": reference_info.get("frame_count"),
            "duration_seconds": reference_info.get("duration_seconds"),
        },
        "candidate_info": {
            "sample_rate": candidate_info.get("sample_rate"),
            "channel_count": candidate_info.get("channel_count"),
            "sample_width_bits": candidate_info.get("sample_width_bits"),
            "frame_count": candidate_info.get("frame_count"),
            "duration_seconds": candidate_info.get("duration_seconds"),
        },
        "format": {
            "sample_rate_matches": format_info.get("sample_rate_matches"),
            "channel_count_matches": format_info.get("channel_count_matches"),
            "sample_width_matches": format_info.get("sample_width_matches"),
            "sample_comparison_available": format_info.get("sample_comparison_available"),
            "duration_delta_seconds": format_info.get("duration_delta_seconds"),
            "frame_count_delta": format_info.get("frame_count_delta"),
        },
        "levels": {
            "reference_rms": reference_rms,
            "candidate_rms": candidate_rms,
            "reference_peak": reference_peak,
            "candidate_peak": candidate_peak,
            "candidate_minus_reference_rms_db": rms_delta_db,
            "candidate_minus_reference_peak_db": peak_delta_db,
            "reference_clipping_count": reference_stats.get("clipping_count"),
            "candidate_clipping_count": candidate_stats.get("clipping_count"),
        },
        "sample_difference": {
            "available": sample_available,
            "overlap_frames": sample_comparison.get("overlap_frames") if sample_available else None,
            "normalized_correlation": correlation,
            "overall_rms_difference": overall_rms_diff,
            "normalized_rms_difference": rounded_optional(diff.get("normalized_rms_difference")),
            "max_abs_sample_difference": max_abs_diff,
            "first_difference_seconds": rounded_optional(sample_comparison.get("first_difference_seconds"))
            if sample_available else None,
            "gain_normalized_candidate_scalar_to_reference": rounded_optional(
                gain_normalized.get("candidate_scalar_to_reference")
            ),
            "gain_normalized_candidate_scalar_db": rounded_optional(gain_normalized.get("candidate_scalar_db")),
            "gain_normalized_rms_difference": gain_normalized_rms_diff,
            "gain_normalized_max_abs_sample_difference": gain_normalized_max_abs_diff,
            "gain_normalized_rms_reduction_ratio": gain_reduction,
            "top_window_rms_difference": top_window_rms,
            "top_window_max_abs_sample_difference": top_window_max_abs,
        },
        "worst_windows": [
            sanitize_window(window)
            for window in windows[:MAX_WINDOWS_PER_REFERENCE]
            if isinstance(window, dict)
        ],
    }


def sanitize_window(window: dict[str, Any]) -> dict[str, Any]:
    return {
        "start_seconds": rounded_optional(window.get("start_seconds")),
        "end_seconds": rounded_optional(window.get("end_seconds")),
        "start_frame": window.get("start_frame"),
        "end_frame": window.get("end_frame"),
        "rms_difference": rounded_optional(window.get("rms_difference")),
        "max_abs_sample_difference": rounded_optional(window.get("max_abs_sample_difference")),
    }


def classify_metrics(metrics: dict[str, Any]) -> dict[str, Any]:
    sample = nested_dict(metrics.get("sample_difference"))
    fmt = nested_dict(metrics.get("format"))
    levels = nested_dict(metrics.get("levels"))
    if not sample.get("available"):
        return {
            "scope": "format_mismatch" if fmt else "comparison_unavailable",
            "candidate_quieter_due_to_headroom": None,
            "candidate_missing_transient_evidence": None,
            "reason": "direct sample comparison was unavailable",
        }

    overall = number(sample.get("overall_rms_difference"))
    top = number(sample.get("top_window_rms_difference"))
    correlation = number(sample.get("normalized_correlation"))
    gain_reduction = number(sample.get("gain_normalized_rms_reduction_ratio"))
    rms_delta_db = number(levels.get("candidate_minus_reference_rms_db"))
    peak_delta_db = number(levels.get("candidate_minus_reference_peak_db"))

    candidate_quieter = (
        rms_delta_db is not None
        and rms_delta_db <= -3.0
        and gain_reduction is not None
        and gain_reduction >= 0.5
    )
    missing_transient = (
        rms_delta_db is not None
        and peak_delta_db is not None
        and peak_delta_db <= -3.0
        and (gain_reduction is None or gain_reduction < 0.5)
    )

    if overall is not None and overall <= 0.005 and (correlation is None or correlation >= 0.995):
        scope = "close"
        reason = "sample-level difference is low in the analyzed window"
    elif gain_reduction is not None and gain_reduction >= 0.75 and (correlation is None or correlation >= 0.95):
        scope = "gain_or_headroom"
        reason = "scalar normalization removes most RMS difference"
    elif overall is not None and top is not None and overall > 0 and top / overall >= 2.5:
        scope = "localized"
        reason = "worst-window RMS difference is much higher than the overall RMS difference"
    elif correlation is not None and correlation < 0.90:
        scope = "global_or_phase"
        reason = "low normalized correlation suggests broad phase, timing, or resampling difference"
    else:
        scope = "mixed_or_broad"
        reason = "no single metric dominated the comparison"

    return {
        "scope": scope,
        "candidate_quieter_due_to_headroom": candidate_quieter,
        "candidate_missing_transient_evidence": missing_transient,
        "reason": reason,
    }


def summarize_reference(raw_reference: dict[str, Any]) -> dict[str, Any]:
    renderer = str(raw_reference.get("renderer") or raw_reference.get("label") or "reference")
    comparison_path_value = raw_reference.get("comparison_json")
    available = raw_reference.get("available")
    if available is None:
        available = comparison_path_value is not None

    summary = {
        "renderer": renderer,
        "available": bool(available),
        "status": str(raw_reference.get("status") or ("available" if available else "missing_reference")),
        "gain_mode": raw_reference.get("gain_mode") or raw_reference.get("mode") or "unspecified",
        "comparison_artifact_label": raw_reference.get("comparison_artifact_label"),
        "notes": text_list(raw_reference.get("notes") or raw_reference.get("note")),
        "metrics": None,
        "classification": None,
    }

    if comparison_path_value is None:
        return summary

    comparison_path = Path(str(comparison_path_value))
    comparison = load_json(comparison_path, f"{renderer} comparison JSON")
    if not isinstance(comparison, dict):
        raise TriageError(f"{renderer} comparison JSON must contain a top-level object: {comparison_path}")
    metrics = comparison_metrics(comparison)
    summary["metrics"] = metrics
    summary["classification"] = classify_metrics(metrics)
    summary["available"] = True
    summary["status"] = str(raw_reference.get("status") or "compared")
    return summary


def summarize_case(raw_case: dict[str, Any], index: int) -> dict[str, Any]:
    label = str(raw_case.get("label") or f"case-{index:03d}")
    references = raw_case.get("references")
    if references is None:
        references = []
    if not isinstance(references, list):
        raise TriageError(f"case {label}: references must be a list")

    reference_summaries = []
    for raw_reference in references:
        if not isinstance(raw_reference, dict):
            raise TriageError(f"case {label}: each reference must be an object")
        reference_summaries.append(summarize_reference(raw_reference))

    compared = [ref for ref in reference_summaries if ref.get("metrics")]
    scopes = Counter(
        nested_dict(ref.get("classification")).get("scope")
        for ref in compared
        if nested_dict(ref.get("classification")).get("scope")
    )
    auto_scope = scopes.most_common(1)[0][0] if scopes else "reference_unavailable"
    manual_classification = raw_case.get("classification")
    suspected_buckets = text_list(raw_case.get("suspected_buckets") or raw_case.get("suspected_bucket"))

    return {
        "label": label,
        "role": raw_case.get("role") or raw_case.get("description") or "",
        "bounds": raw_case.get("bounds") or raw_case.get("target") or "",
        "priority": raw_case.get("priority") or "",
        "reference_count": len(reference_summaries),
        "compared_reference_count": len(compared),
        "reference_availability": {
            "available": sum(1 for ref in reference_summaries if ref.get("available")),
            "missing": sum(1 for ref in reference_summaries if not ref.get("available")),
        },
        "auto_scope": auto_scope,
        "classification": str(manual_classification) if manual_classification else auto_scope,
        "suspected_buckets": suspected_buckets,
        "notes": text_list(raw_case.get("notes") or raw_case.get("note")),
        "references": reference_summaries,
    }


def choose_recommendation(cases: list[dict[str, Any]]) -> dict[str, Any]:
    compared_cases = [case for case in cases if case["compared_reference_count"] > 0]
    if not compared_cases:
        return {
            "recommended_next_pr": "Reference renderer workflow improvements",
            "rationale": "No selected triage case had an available reference comparison.",
        }

    for case in compared_cases:
        if str(case.get("priority")).lower() in {"highest", "target", "recommended"}:
            for bucket in case.get("suspected_buckets", []):
                recommendation = BUCKET_RECOMMENDATIONS.get(bucket.lower())
                if recommendation:
                    return {
                        "recommended_next_pr": recommendation,
                        "rationale": f"{case['label']} was marked {case['priority']} and classified as {bucket}.",
                    }

    bucket_counts = Counter()
    for case in compared_cases:
        for bucket in case.get("suspected_buckets", []):
            normalized = bucket.lower()
            if normalized != "unknown":
                bucket_counts[normalized] += 1
    for bucket, _ in bucket_counts.most_common():
        recommendation = BUCKET_RECOMMENDATIONS.get(bucket)
        if recommendation:
            return {
                "recommended_next_pr": recommendation,
                "rationale": f"The most common suspected bucket was {bucket}.",
            }

    scope_counts = Counter(case["auto_scope"] for case in compared_cases)
    if scope_counts.get("gain_or_headroom", 0) == len(compared_cases):
        return {
            "recommended_next_pr": "Render-gain policy comparison",
            "rationale": "All available comparisons were dominated by scalar gain/headroom evidence.",
        }
    if scope_counts.get("global_or_phase", 0) >= max(2, math.ceil(len(compared_cases) / 2)):
        return {
            "recommended_next_pr": "Interpolation/sample-step parity investigation",
            "rationale": "Broad low-correlation differences dominated the available comparisons.",
        }
    if scope_counts.get("localized", 0) > 0:
        return {
            "recommended_next_pr": "Focused localized mismatch investigation",
            "rationale": "At least one available comparison has localized worst-window evidence but no concrete bucket.",
        }
    return {
        "recommended_next_pr": "Final residual cleanup or reference renderer workflow improvements",
        "rationale": "No single actionable backend parity bucket dominated the triage evidence.",
    }


def build_report(manifest: dict[str, Any], manifest_path: Path | None = None) -> dict[str, Any]:
    cases = [
        summarize_case(raw_case, index)
        for index, raw_case in enumerate(nested_list(manifest.get("cases")), start=1)
        if isinstance(raw_case, dict)
    ]
    if len(cases) != len(nested_list(manifest.get("cases"))):
        raise TriageError("each manifest case must be an object")
    recommendation = choose_recommendation(cases)
    compared_count = sum(case["compared_reference_count"] for case in cases)
    missing_reference_count = sum(case["reference_availability"]["missing"] for case in cases)
    return {
        "schema_version": 1,
        "tool": "scripts/summarize-reference-render-triage.py",
        "manifest_path_name": manifest_path.name if manifest_path else None,
        "title": manifest.get("title") or "Reference Render Parity Triage",
        "metadata": text_list(manifest.get("metadata")),
        "summary": {
            "case_count": len(cases),
            "compared_reference_count": compared_count,
            "missing_reference_count": missing_reference_count,
            **recommendation,
        },
        "cases": cases,
        "notes": [
            "Diagnostic metrics only; lower differences do not prove tracker semantic correctness.",
            "Generated reports from private/local modules must remain outside git.",
            "Comparison JSON path values are reduced to basenames in this report.",
        ],
    }


def build_markdown(report: dict[str, Any]) -> str:
    summary = nested_dict(report.get("summary"))
    lines = [
        f"# {report.get('title') or 'Reference Render Parity Triage'}",
        "",
        "Diagnostic metrics only; use this report to choose a focused follow-up, not as a parity claim.",
        "",
        "## Recommendation",
        f"- Recommended next PR: {summary.get('recommended_next_pr')}",
        f"- Rationale: {summary.get('rationale')}",
        "",
        "## Summary",
        f"- Cases: {summary.get('case_count')}",
        f"- Available reference comparisons: {summary.get('compared_reference_count')}",
        f"- Missing references recorded: {summary.get('missing_reference_count')}",
    ]
    for item in nested_list(report.get("metadata")):
        lines.append(f"- Metadata: {item}")
    lines.extend([
        "",
        "## Triage Set",
        "| Label | Role | Compared refs | Missing refs | Classification | Suspected bucket |",
        "| --- | --- | ---: | ---: | --- | --- |",
    ])
    for case in nested_list(report.get("cases")):
        buckets = ", ".join(case.get("suspected_buckets") or []) or "n/a"
        lines.append(
            f"| {case['label']} | {case.get('role') or 'n/a'} | "
            f"{case['compared_reference_count']} | {case['reference_availability']['missing']} | "
            f"{case['classification']} | {buckets} |"
        )

    for case in nested_list(report.get("cases")):
        lines.extend(["", f"## {case['label']}"])
        if case.get("role"):
            lines.append(f"- Role: {case['role']}")
        if case.get("bounds"):
            lines.append(f"- Bounds: {case['bounds']}")
        lines.append(f"- Classification: {case['classification']}")
        if case.get("suspected_buckets"):
            lines.append(f"- Suspected bucket: {', '.join(case['suspected_buckets'])}")
        for note in case.get("notes", []):
            lines.append(f"- Note: {note}")

        for reference in case.get("references", []):
            lines.extend(["", f"### {reference['renderer']}"])
            lines.append(f"- Status: {reference['status']}")
            lines.append(f"- Gain mode: {reference.get('gain_mode') or 'unspecified'}")
            if reference.get("comparison_artifact_label"):
                lines.append(f"- Comparison artifact: {reference['comparison_artifact_label']}")
            for note in reference.get("notes", []):
                lines.append(f"- Note: {note}")
            metrics = reference.get("metrics")
            if not isinstance(metrics, dict):
                lines.append("- Reference comparison unavailable.")
                continue
            append_metrics_markdown(lines, metrics, nested_dict(reference.get("classification")))

    lines.extend(["", "## Notes"])
    for note in report.get("notes", []):
        lines.append(f"- {note}")
    return "\n".join(lines) + "\n"


def append_metrics_markdown(lines: list[str], metrics: dict[str, Any], classification: dict[str, Any]) -> None:
    reference_info = nested_dict(metrics.get("reference_info"))
    candidate_info = nested_dict(metrics.get("candidate_info"))
    levels = nested_dict(metrics.get("levels"))
    sample = nested_dict(metrics.get("sample_difference"))
    fmt = nested_dict(metrics.get("format"))
    lines.extend([
        "- Duration: "
        f"reference {format_float(reference_info.get('duration_seconds'))} s, "
        f"candidate {format_float(candidate_info.get('duration_seconds'))} s, "
        f"delta {format_float(fmt.get('duration_delta_seconds'))} s",
        "- Sample rate/channels: "
        f"{reference_info.get('sample_rate')} Hz/{reference_info.get('channel_count')} ch reference, "
        f"{candidate_info.get('sample_rate')} Hz/{candidate_info.get('channel_count')} ch candidate",
        "- RMS: "
        f"reference {format_float(levels.get('reference_rms'), 8)}, "
        f"candidate {format_float(levels.get('candidate_rms'), 8)}, "
        f"delta {format_signed_db(levels.get('candidate_minus_reference_rms_db'))}",
        "- Peak: "
        f"reference {format_float(levels.get('reference_peak'), 8)}, "
        f"candidate {format_float(levels.get('candidate_peak'), 8)}, "
        f"delta {format_signed_db(levels.get('candidate_minus_reference_peak_db'))}",
        "- Correlation/RMS diff/max abs diff: "
        f"{format_float(sample.get('normalized_correlation'), 8)} / "
        f"{format_float(sample.get('overall_rms_difference'), 8)} / "
        f"{format_float(sample.get('max_abs_sample_difference'), 8)}",
        "- Gain-normalized scalar/RMS diff/reduction: "
        f"{format_float(sample.get('gain_normalized_candidate_scalar_to_reference'), 8)} / "
        f"{format_float(sample.get('gain_normalized_rms_difference'), 8)} / "
        f"{format_float(sample.get('gain_normalized_rms_reduction_ratio'), 8)}",
        f"- Mismatch scope: {classification.get('scope')} ({classification.get('reason')})",
        "- Candidate quieter due to headroom/gain: "
        f"{format_bool(classification.get('candidate_quieter_due_to_headroom'))}",
        "- Candidate missing transient evidence: "
        f"{format_bool(classification.get('candidate_missing_transient_evidence'))}",
    ])
    windows = metrics.get("worst_windows")
    if isinstance(windows, list) and windows:
        lines.append("- Worst windows:")
        for index, window in enumerate(windows, start=1):
            if not isinstance(window, dict):
                continue
            lines.append(
                f"  {index}. {format_float(window.get('start_seconds'))}-"
                f"{format_float(window.get('end_seconds'))} s, "
                f"rms {format_float(window.get('rms_difference'), 8)}, "
                f"max {format_float(window.get('max_abs_sample_difference'), 8)}"
            )
    else:
        lines.append("- Worst windows: unavailable")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize anonymized local reference-render triage comparison JSONs.",
    )
    parser.add_argument("--manifest", required=True, type=Path, help="Local triage manifest JSON path")
    parser.add_argument("--markdown", type=Path, help="Markdown report output path")
    parser.add_argument("--json", dest="json_report", type=Path, help="JSON summary output path")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        manifest = load_manifest(args.manifest)
        report = build_report(manifest, manifest_path=args.manifest)
        markdown = build_markdown(report)
        if args.markdown:
            args.markdown.parent.mkdir(parents=True, exist_ok=True)
            args.markdown.write_text(markdown, encoding="utf-8")
        if args.json_report:
            args.json_report.parent.mkdir(parents=True, exist_ok=True)
            args.json_report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        if not args.markdown and not args.json_report:
            print(markdown, end="")
    except TriageError as error:
        print(f"reference-render-triage: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
