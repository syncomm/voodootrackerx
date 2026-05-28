#!/usr/bin/env python3
"""Sum local WAV stems and report reconstruction scaling diagnostics."""

from __future__ import annotations

import argparse
import array
import importlib.util
import json
import math
import struct
import sys
from pathlib import Path
from typing import Iterable


FLOAT_DIGITS = 9
DEFAULT_SECONDS = 24.0 * 60.0 * 60.0
DEFAULT_NEAR_SILENCE_THRESHOLD = 1.0e-5


def load_audio_compare_module():
    script_path = Path(__file__).resolve().with_name("audio-compare.py")
    spec = importlib.util.spec_from_file_location("audio_compare_for_stems", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


audio_compare = load_audio_compare_module()


class StemDiagnosticsError(Exception):
    """User-facing stem diagnostic input error."""


def rounded(value: float) -> float:
    return round(float(value), FLOAT_DIGITS)


def rounded_optional(value: float | None) -> float | None:
    return None if value is None else rounded(value)


def stats_json(
    samples: Iterable[float],
    *,
    channels: int,
    sample_rate: int,
    near_silence_threshold: float,
) -> dict[str, object]:
    per_channel_square = [0.0 for _ in range(channels)]
    per_channel_count = [0 for _ in range(channels)]
    per_channel_peak = [0.0 for _ in range(channels)]
    sample_count = 0
    square_sum = 0.0
    peak = 0.0
    overrange_count = 0
    full_scale_count = 0
    near_silence_count = 0

    for index, sample_value in enumerate(samples):
        sample = float(sample_value)
        absolute = abs(sample)
        channel = index % channels if channels > 0 else 0
        sample_count += 1
        square_sum += sample * sample
        peak = max(peak, absolute)
        overrange_count += 1 if absolute > 1.0 else 0
        full_scale_count += 1 if absolute >= 1.0 else 0
        near_silence_count += 1 if absolute <= near_silence_threshold else 0
        if channel < channels:
            per_channel_square[channel] += sample * sample
            per_channel_count[channel] += 1
            per_channel_peak[channel] = max(per_channel_peak[channel], absolute)

    frames = sample_count // channels if channels > 0 else 0
    rms = math.sqrt(square_sum / sample_count) if sample_count else 0.0
    per_channel_rms = [
        math.sqrt(square / count) if count else 0.0
        for square, count in zip(per_channel_square, per_channel_count)
    ]
    return {
        "frames_analyzed": frames,
        "duration_analyzed_seconds": rounded(frames / sample_rate if sample_rate > 0 else 0.0),
        "overall_rms": rounded(rms),
        "overall_peak": rounded(peak),
        "overall_rms_dbfs": rounded_optional(audio_compare.amplitude_to_dbfs(rms)),
        "overall_peak_dbfs": rounded_optional(audio_compare.amplitude_to_dbfs(peak)),
        "per_channel_rms": [rounded(value) for value in per_channel_rms],
        "per_channel_peak": [rounded(value) for value in per_channel_peak],
        "overrange_sample_count": overrange_count,
        "full_scale_sample_count": full_scale_count,
        "near_silence_count": near_silence_count,
        "near_silence_ratio": rounded(near_silence_count / sample_count if sample_count else 0.0),
    }


def write_float32_wav(path: Path, *, samples: array.array, sample_rate: int, channels: int) -> None:
    frame_count = len(samples) // channels if channels > 0 else 0
    data_size = len(samples) * 4
    riff_size = 4 + (8 + 16) + (8 + data_size)
    if data_size > 0xFFFFFFFF or riff_size > 0xFFFFFFFF:
        raise StemDiagnosticsError("summed WAV is too large for the simple RIFF writer")

    path.parent.mkdir(parents=True, exist_ok=True)
    output_samples = samples
    if sys.byteorder != "little":
        output_samples = array.array("f", samples)
        output_samples.byteswap()

    with path.open("wb") as handle:
        handle.write(b"RIFF")
        handle.write(struct.pack("<I", riff_size))
        handle.write(b"WAVE")
        handle.write(b"fmt ")
        handle.write(struct.pack(
            "<IHHIIHH",
            16,
            audio_compare.WAVE_FORMAT_IEEE_FLOAT,
            channels,
            sample_rate,
            sample_rate * channels * 4,
            channels * 4,
            32,
        ))
        handle.write(b"data")
        handle.write(struct.pack("<I", data_size))
        handle.write(output_samples.tobytes())


def extend_with_zeros(samples: array.array, additional_count: int) -> None:
    if additional_count > 0:
        samples.extend(array.array("f", [0.0]) * additional_count)


def sum_stems(
    stem_paths: list[Path],
    output_path: Path,
    *,
    seconds: float | None,
    near_silence_threshold: float,
) -> dict[str, object]:
    if not stem_paths:
        raise StemDiagnosticsError("at least one stem is required")

    read_seconds = seconds if seconds is not None else DEFAULT_SECONDS
    sample_rate: int | None = None
    channels: int | None = None
    summed = array.array("f")
    stem_inputs = []

    for path in stem_paths:
        info, samples = audio_compare.read_wav(path, read_seconds)
        if sample_rate is None:
            sample_rate = info.sample_rate
            channels = info.channels
        elif info.sample_rate != sample_rate:
            raise StemDiagnosticsError("all stems must have the same sample rate")
        elif info.channels != channels:
            raise StemDiagnosticsError("all stems must have the same channel count")

        extend_with_zeros(summed, len(samples) - len(summed))
        for index, sample in enumerate(samples):
            summed[index] += sample
        stem_inputs.append({
            "info": info.to_json(),
            "stats": stats_json(
                samples,
                channels=info.channels,
                sample_rate=info.sample_rate,
                near_silence_threshold=near_silence_threshold,
            ),
        })

    assert sample_rate is not None and channels is not None
    if not summed:
        raise StemDiagnosticsError("requested stem sum contains no samples")

    write_float32_wav(output_path, samples=summed, sample_rate=sample_rate, channels=channels)
    frame_count = len(summed) // channels
    return {
        "schema_version": 1,
        "tool": "scripts/stem-scaling-diagnostics.py",
        "local_only": True,
        "notes": [
            "Diagnostic metrics only; they do not prove tracker semantic correctness.",
            "Summed stems are written as 32-bit IEEE float WAV without normalization or attenuation.",
            "Generated WAVs and JSON reports are local artifacts and must not be committed.",
        ],
        "stem_count": len(stem_inputs),
        "stem_inputs": stem_inputs,
        "summed_mix": {
            "path_name": output_path.name,
            "sample_rate": sample_rate,
            "channel_count": channels,
            "sample_width_bits": 32,
            "sample_format": "ieee_float",
            "frame_count": frame_count,
            "duration_seconds": rounded(frame_count / sample_rate),
            "stats": stats_json(
                summed,
                channels=channels,
                sample_rate=sample_rate,
                near_silence_threshold=near_silence_threshold,
            ),
        },
    }


def reconstruction_summary(comparison: dict[str, object]) -> dict[str, object]:
    sample_comparison = comparison.get("sample_comparison")
    reference = comparison.get("reference")
    candidate = comparison.get("candidate")
    if not isinstance(sample_comparison, dict) or not isinstance(reference, dict) or not isinstance(candidate, dict):
        return {"available": False, "classification": "sample_comparison_unavailable"}

    reference_stats = reference.get("stats") if isinstance(reference.get("stats"), dict) else {}
    candidate_stats = candidate.get("stats") if isinstance(candidate.get("stats"), dict) else {}
    reference_rms = float(reference_stats.get("overall_rms", 0.0))
    candidate_rms = float(candidate_stats.get("overall_rms", 0.0))
    rms_ratio = candidate_rms / reference_rms if reference_rms > 0 else None
    gain_normalized = sample_comparison.get("gain_normalized")
    scalar = gain_normalized.get("candidate_scalar_to_reference") if isinstance(gain_normalized, dict) else None
    correlation = sample_comparison.get("normalized_correlation")
    diff = sample_comparison.get("diff") if isinstance(sample_comparison.get("diff"), dict) else {}
    normalized_diff = diff.get("normalized_rms_difference") if isinstance(diff, dict) else None

    if isinstance(correlation, (int, float)) and isinstance(rms_ratio, float):
        if correlation >= 0.99999 and abs(rms_ratio - 1.0) <= 0.001:
            classification = "reconstructs_full_render"
        elif correlation >= 0.999 and abs(rms_ratio - 1.0) > 0.001:
            classification = "matches_full_render_after_scalar_only"
        else:
            classification = "does_not_reconstruct_full_render"
    else:
        classification = "sample_comparison_unavailable"

    return {
        "available": True,
        "classification": classification,
        "overlap_frames": sample_comparison.get("overlap_frames"),
        "normalized_correlation": correlation,
        "normalized_rms_difference": normalized_diff,
        "summed_to_full_rms_ratio": rounded_optional(rms_ratio),
        "full_rms": reference_stats.get("overall_rms"),
        "summed_rms": candidate_stats.get("overall_rms"),
        "full_peak": reference_stats.get("overall_peak"),
        "summed_peak": candidate_stats.get("overall_peak"),
        "candidate_scalar_to_reference": scalar,
    }


def build_diagnostics(
    stem_paths: list[Path],
    output_path: Path,
    *,
    full_render_path: Path | None = None,
    seconds: float | None = None,
    chunk_frames: int | None = None,
    near_silence_threshold: float = DEFAULT_NEAR_SILENCE_THRESHOLD,
    window_ms: float = audio_compare.DEFAULT_WINDOW_MS,
    top_windows: int = audio_compare.DEFAULT_TOP_WINDOWS,
    alignment_search_frames: int = audio_compare.DEFAULT_ALIGNMENT_SEARCH_FRAMES,
) -> dict[str, object]:
    _ = chunk_frames
    diagnostics = sum_stems(
        stem_paths,
        output_path,
        seconds=seconds,
        near_silence_threshold=near_silence_threshold,
    )
    if full_render_path is None:
        diagnostics["full_render_reconstruction"] = {
            "available": False,
            "classification": "not_requested",
        }
        return diagnostics

    comparison = audio_compare.build_comparison(
        full_render_path,
        output_path,
        seconds if seconds is not None else DEFAULT_SECONDS,
        audio_compare.DEFAULT_DIFF_THRESHOLD,
        near_silence_threshold,
        window_ms,
        top_windows,
        alignment_search_frames,
    )
    diagnostics["full_render"] = {"path_name": full_render_path.name}
    diagnostics["full_render_reconstruction"] = reconstruction_summary(comparison)
    diagnostics["comparison"] = comparison
    return diagnostics


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sum local WAV stems and compare them to an optional full render.")
    parser.add_argument("--stem", action="append", required=True, type=Path, help="Stem WAV path; pass once per stem")
    parser.add_argument("--sum-output", required=True, type=Path, help="Output 32-bit float WAV path for the summed stems")
    parser.add_argument("--full-render", type=Path, help="Optional full-render WAV path for reconstruction comparison")
    parser.add_argument("--json", dest="json_output", type=Path, help="Optional JSON diagnostics output path")
    parser.add_argument("--seconds", type=float, help="Optional duration cap in seconds")
    parser.add_argument("--near-silence-threshold", type=float, default=DEFAULT_NEAR_SILENCE_THRESHOLD)
    parser.add_argument("--window-ms", type=float, default=audio_compare.DEFAULT_WINDOW_MS)
    parser.add_argument("--top-windows", type=int, default=audio_compare.DEFAULT_TOP_WINDOWS)
    parser.add_argument("--alignment-search-frames", type=int, default=audio_compare.DEFAULT_ALIGNMENT_SEARCH_FRAMES)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.seconds is not None and args.seconds <= 0:
        print("--seconds must be greater than zero", file=sys.stderr)
        return 2
    if args.near_silence_threshold < 0:
        print("--near-silence-threshold must be zero or greater", file=sys.stderr)
        return 2
    if args.window_ms <= 0:
        print("--window-ms must be greater than zero", file=sys.stderr)
        return 2
    if args.top_windows < 0:
        print("--top-windows must be zero or greater", file=sys.stderr)
        return 2
    if args.alignment_search_frames < 0:
        print("--alignment-search-frames must be zero or greater", file=sys.stderr)
        return 2

    try:
        diagnostics = build_diagnostics(
            args.stem,
            args.sum_output,
            full_render_path=args.full_render,
            seconds=args.seconds,
            near_silence_threshold=args.near_silence_threshold,
            window_ms=args.window_ms,
            top_windows=args.top_windows,
            alignment_search_frames=args.alignment_search_frames,
        )
    except (OSError, ValueError, StemDiagnosticsError) as error:
        print(f"stem-scaling-diagnostics: {error}", file=sys.stderr)
        return 1

    text = json.dumps(diagnostics, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
