#!/usr/bin/env python3
"""Sum local WAV stems and report reconstruction scaling diagnostics."""

from __future__ import annotations

import argparse
import array
import dataclasses
import importlib.util
import json
import math
import struct
import sys
from pathlib import Path
from typing import BinaryIO, Iterable


FLOAT_DIGITS = 9
DEFAULT_SECONDS = 24.0 * 60.0 * 60.0
DEFAULT_NEAR_SILENCE_THRESHOLD = 1.0e-5
DEFAULT_ALIGNMENT_ANALYSIS_FRAMES = 12_000


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


@dataclasses.dataclass(frozen=True)
class FocusWindow:
    start_seconds: float
    end_seconds: float

    def to_json(self, sample_rate: int) -> dict[str, object]:
        start_frame = max(0, int(round(self.start_seconds * sample_rate)))
        end_frame = max(start_frame, int(round(self.end_seconds * sample_rate)))
        return {
            "start_seconds": rounded(self.start_seconds),
            "end_seconds": rounded(self.end_seconds),
            "start_frame": start_frame,
            "end_frame": end_frame,
        }


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


def read_windowed_wav(path: Path, *, start_frame: int, end_frame: int) -> tuple[object, list[float]]:
    if end_frame < start_frame:
        raise StemDiagnosticsError("window end frame must be greater than or equal to start frame")

    with path.open("rb") as wav_file:
        riff = read_exact(wav_file, 12, path)
        if riff[0:4] != b"RIFF" or riff[8:12] != b"WAVE":
            raise StemDiagnosticsError(f"{path}: expected RIFF/WAVE file")

        fmt: dict[str, int | str] | None = None
        data_offset: int | None = None
        data_chunk_size: int | None = None

        while True:
            header = wav_file.read(8)
            if not header:
                break
            if len(header) != 8:
                raise StemDiagnosticsError(f"{path}: truncated WAV chunk header")
            chunk_id, chunk_size = struct.unpack("<4sI", header)
            chunk_data_offset = wav_file.tell()
            if chunk_id == b"fmt ":
                fmt = audio_compare.parse_fmt_chunk(read_exact(wav_file, chunk_size, path), path)
            elif chunk_id == b"data":
                data_offset = chunk_data_offset
                data_chunk_size = chunk_size
                wav_file.seek(chunk_size, 1)
            else:
                wav_file.seek(chunk_size, 1)
            if chunk_size % 2 == 1:
                wav_file.seek(1, 1)

        if fmt is None:
            raise StemDiagnosticsError(f"{path}: missing WAV fmt chunk")
        if data_offset is None or data_chunk_size is None:
            raise StemDiagnosticsError(f"{path}: missing WAV data chunk")

        block_align = int(fmt["block_align"])
        if block_align <= 0:
            raise StemDiagnosticsError(f"{path}: WAV block align must be greater than zero")
        full_frame_count = data_chunk_size // block_align
        safe_start = max(0, min(start_frame, full_frame_count))
        safe_end = max(safe_start, min(end_frame, full_frame_count))
        frame_count = safe_end - safe_start
        byte_count = frame_count * block_align

        wav_file.seek(data_offset + (safe_start * block_align))
        sample_bytes = read_exact(wav_file, byte_count, path) if byte_count > 0 else b""

    info = audio_compare.WavInfo(
        path=path,
        sample_rate=int(fmt["sample_rate"]),
        channels=int(fmt["channels"]),
        sample_width=int(fmt["sample_width"]),
        frame_count=full_frame_count,
        format_code=int(fmt["format_code"]),
        sample_format=str(fmt["sample_format"]),
    )
    audio_compare.validate_wav_info(path, info)
    if info.sample_format == "pcm":
        samples = audio_compare.decode_pcm_samples(sample_bytes, info.sample_width)
    elif info.sample_format == "ieee_float":
        samples = audio_compare.decode_float_samples(sample_bytes, info.sample_width)
    else:
        raise StemDiagnosticsError(f"{path}: unsupported WAV sample format: {info.sample_format}")
    return info, samples


def read_exact(file_object: BinaryIO, byte_count: int, path: Path) -> bytes:
    data = file_object.read(byte_count)
    if len(data) != byte_count:
        raise StemDiagnosticsError(f"{path}: truncated WAV data")
    return data


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


def parse_focus_window(value: str) -> FocusWindow:
    try:
        start_text, end_text = value.split(":", 1)
        start = float(start_text)
        end = float(end_text)
    except ValueError as error:
        raise argparse.ArgumentTypeError("focus windows must use START:END seconds") from error
    if start < 0.0 or end <= start:
        raise argparse.ArgumentTypeError("focus window end must be greater than start and both must be non-negative")
    return FocusWindow(start_seconds=start, end_seconds=end)


def pair_window_metrics(
    reference_samples: list[float],
    candidate_samples: list[float],
    *,
    channels: int,
    sample_rate: int,
    focus_start_frame: int,
    focus_end_frame: int,
    alignment_search_frames: int,
    alignment_analysis_frames: int | None,
) -> dict[str, object]:
    available_frames = min(len(reference_samples), len(candidate_samples)) // channels if channels > 0 else 0
    safe_start = max(0, min(focus_start_frame, available_frames))
    safe_end = max(safe_start, min(focus_end_frame, available_frames))
    frame_count = safe_end - safe_start
    start_sample = safe_start * channels
    end_sample = safe_end * channels
    reference_window = reference_samples[start_sample:end_sample]
    candidate_window = candidate_samples[start_sample:end_sample]
    reference_stats = audio_compare.stats_for(
        reference_window,
        channels,
        sample_rate,
        4,
        DEFAULT_NEAR_SILENCE_THRESHOLD,
        "ieee_float",
    )
    candidate_stats = audio_compare.stats_for(
        candidate_window,
        channels,
        sample_rate,
        4,
        DEFAULT_NEAR_SILENCE_THRESHOLD,
        "ieee_float",
    )
    raw_diff = audio_compare.diff_metrics(reference_window, candidate_window, channels, reference_stats.rms)
    gain_normalized = audio_compare.gain_normalized_metrics(
        reference_window,
        candidate_window,
        channels,
        reference_stats.rms,
        float(raw_diff["overall_rms_difference"]),
    )
    alignment_start = safe_start
    alignment_end = safe_end
    if alignment_analysis_frames is not None and alignment_analysis_frames > 0:
        alignment_end = min(alignment_end, alignment_start + alignment_analysis_frames)

    alignment = audio_compare.local_alignment_search(
        reference_samples,
        candidate_samples,
        channels,
        sample_rate,
        alignment_start,
        alignment_end,
        alignment_search_frames,
    )
    return {
        "overlap_frames": frame_count,
        "reference_stats": reference_stats.to_json(),
        "candidate_stats": candidate_stats.to_json(),
        "normalized_correlation": audio_compare.rounded_optional(
            audio_compare.normalized_correlation(reference_window, candidate_window)
        ),
        "diff": raw_diff,
        "gain_normalized": gain_normalized,
        "local_alignment": alignment,
        "local_alignment_focus": {
            "start_frame": alignment_start,
            "end_frame": alignment_end,
            "frame_count": max(0, alignment_end - alignment_start),
            "truncated": alignment_end < safe_end,
        },
        "mismatch_classification": classify_pair_window(
            reference_stats.rms,
            candidate_stats.rms,
            raw_diff,
            gain_normalized,
            reference_window,
            candidate_window,
            channels,
            alignment,
        ),
    }


def classify_pair_window(
    reference_rms: float,
    candidate_rms: float,
    raw_diff: dict[str, object],
    gain_normalized: dict[str, object],
    reference_samples: list[float],
    candidate_samples: list[float],
    channels: int,
    alignment: dict[str, object],
) -> str:
    silence = 1.0e-7
    if reference_rms <= silence and candidate_rms > silence:
        return "extra_voice_or_reference_silence"
    if candidate_rms <= silence and reference_rms > silence:
        return "missing_voice_or_candidate_silence"

    raw_rms = float(raw_diff.get("overall_rms_difference", 0.0))
    gain_diff = gain_normalized.get("diff")
    reduction = gain_normalized.get("rms_difference_reduction_ratio")
    if isinstance(gain_diff, dict) and isinstance(reduction, (int, float)):
        normalized_rms = float(gain_diff.get("overall_rms_difference", raw_rms))
        if reduction >= 0.75 and (raw_rms == 0.0 or normalized_rms <= raw_rms * 0.35):
            return "amplitude_scalar"

    zero = alignment.get("zero_shift")
    best = alignment.get("best_shift")
    if isinstance(zero, dict) and isinstance(best, dict):
        zero_corr = zero.get("normalized_correlation")
        best_corr = best.get("normalized_correlation")
        zero_rms = zero.get("rms_difference")
        best_rms = best.get("rms_difference")
        best_shift = int(best.get("candidate_shift_frames", 0))
        if (
            best_shift != 0
            and isinstance(zero_corr, (int, float))
            and isinstance(best_corr, (int, float))
            and isinstance(zero_rms, (int, float))
            and isinstance(best_rms, (int, float))
            and (best_corr >= zero_corr + 0.10 or best_rms <= zero_rms * 0.80)
        ):
            return "timing_or_phase_shift"

    correlation = audio_compare.normalized_correlation(reference_samples, candidate_samples)
    if correlation is not None and correlation >= 0.85:
        return "phase_or_small_shape_difference"
    return "timbre_or_content_difference"


def build_channel_pair_diagnostics(
    reference_stem_paths: list[Path],
    candidate_stem_paths: list[Path],
    focus_windows: list[FocusWindow],
    *,
    top_channels: int,
    alignment_search_frames: int,
    alignment_analysis_frames: int | None,
) -> dict[str, object]:
    if len(reference_stem_paths) != len(candidate_stem_paths):
        raise StemDiagnosticsError("--candidate-stem count must match --stem count")
    if not focus_windows:
        raise StemDiagnosticsError("--focus-window is required when --candidate-stem is used")

    windows_json: list[dict[str, object]] = []
    for focus_window in focus_windows:
        window_rows: list[dict[str, object]] = []
        sample_rate: int | None = None
        channels: int | None = None
        start_frame: int | None = None
        end_frame: int | None = None

        for index, (reference_path, candidate_path) in enumerate(zip(reference_stem_paths, candidate_stem_paths)):
            if sample_rate is None:
                info, _ = audio_compare.read_wav(reference_path, 0.001)
                sample_rate = info.sample_rate
                channels = info.channels
                start_frame = max(0, int(round(focus_window.start_seconds * sample_rate)))
                end_frame = max(start_frame, int(round(focus_window.end_seconds * sample_rate)))
            assert sample_rate is not None and channels is not None and start_frame is not None and end_frame is not None
            context_start_frame = max(0, start_frame - alignment_search_frames)
            context_end_frame = end_frame + alignment_search_frames

            reference_info, reference_samples = read_windowed_wav(
                reference_path,
                start_frame=context_start_frame,
                end_frame=context_end_frame,
            )
            candidate_info, candidate_samples = read_windowed_wav(
                candidate_path,
                start_frame=context_start_frame,
                end_frame=context_end_frame,
            )
            if (
                reference_info.sample_rate != candidate_info.sample_rate
                or reference_info.channels != candidate_info.channels
            ):
                raise StemDiagnosticsError("matched stem WAVs must have the same sample rate and channel count")
            if reference_info.sample_rate != sample_rate or reference_info.channels != channels:
                raise StemDiagnosticsError("all reference stems must share sample rate and channel count")

            metrics = pair_window_metrics(
                reference_samples,
                candidate_samples,
                channels=channels,
                sample_rate=sample_rate,
                focus_start_frame=start_frame - context_start_frame,
                focus_end_frame=end_frame - context_start_frame,
                alignment_search_frames=alignment_search_frames,
                alignment_analysis_frames=alignment_analysis_frames,
            )
            raw_diff = metrics.get("diff") if isinstance(metrics.get("diff"), dict) else {}
            gain = metrics.get("gain_normalized") if isinstance(metrics.get("gain_normalized"), dict) else {}
            gain_diff = gain.get("diff") if isinstance(gain.get("diff"), dict) else {}
            alignment = metrics.get("local_alignment") if isinstance(metrics.get("local_alignment"), dict) else {}
            best_shift = alignment.get("best_shift") if isinstance(alignment.get("best_shift"), dict) else {}
            window_rows.append({
                "stem_index": index,
                "tracker_channel": index + 1,
                "vtx_channel_index": index,
                "reference_path_name": reference_path.name,
                "candidate_path_name": candidate_path.name,
                "metrics": metrics,
                "ranking": {
                    "raw_rms_difference": raw_diff.get("overall_rms_difference"),
                    "gain_normalized_rms_difference": gain_diff.get("overall_rms_difference"),
                    "normalized_correlation": metrics.get("normalized_correlation"),
                    "best_shift_frames": best_shift.get("candidate_shift_frames"),
                    "reference_rms": metrics["reference_stats"].get("overall_rms"),
                    "candidate_rms": metrics["candidate_stats"].get("overall_rms"),
                    "classification": metrics.get("mismatch_classification"),
                },
            })

        window_rows.sort(
            key=lambda item: (
                -float(item["ranking"].get("raw_rms_difference") or 0.0),
                int(item["stem_index"]),
            )
        )
        assert sample_rate is not None and start_frame is not None and end_frame is not None
        windows_json.append({
            **focus_window.to_json(sample_rate),
            "top_channels": window_rows[:top_channels],
        })

    return {
        "available": True,
        "reference_stem_count": len(reference_stem_paths),
        "candidate_stem_count": len(candidate_stem_paths),
        "alignment_search_frames": alignment_search_frames,
        "alignment_analysis_frames": alignment_analysis_frames,
        "top_channel_count": top_channels,
        "windows": windows_json,
        "notes": [
            "Ranking is by raw RMS difference inside each explicit focus window.",
            "Local alignment search may use a bounded prefix of long focus windows; raw RMS still covers the full focus window.",
            "Mismatch classification is heuristic diagnostic evidence, not a playback-correctness proof.",
        ],
    }


def build_diagnostics(
    stem_paths: list[Path],
    output_path: Path,
    *,
    full_render_path: Path | None = None,
    candidate_stem_paths: list[Path] | None = None,
    focus_windows: list[FocusWindow] | None = None,
    top_channels: int = 8,
    alignment_analysis_frames: int | None = DEFAULT_ALIGNMENT_ANALYSIS_FRAMES,
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
    else:
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

    if candidate_stem_paths:
        diagnostics["matched_stem_windows"] = build_channel_pair_diagnostics(
            stem_paths,
            candidate_stem_paths,
            focus_windows or [],
            top_channels=top_channels,
            alignment_search_frames=alignment_search_frames,
            alignment_analysis_frames=alignment_analysis_frames,
        )
    else:
        diagnostics["matched_stem_windows"] = {"available": False, "classification": "not_requested"}
    return diagnostics


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sum local WAV stems and compare them to an optional full render.")
    parser.add_argument("--stem", action="append", required=True, type=Path, help="Stem WAV path; pass once per stem")
    parser.add_argument("--candidate-stem", action="append", type=Path, help="Matching candidate/VTX stem WAV path; pass once per stem")
    parser.add_argument("--sum-output", required=True, type=Path, help="Output 32-bit float WAV path for the summed stems")
    parser.add_argument("--full-render", type=Path, help="Optional full-render WAV path for reconstruction comparison")
    parser.add_argument("--json", dest="json_output", type=Path, help="Optional JSON diagnostics output path")
    parser.add_argument("--focus-window", action="append", type=parse_focus_window, help="Focused START:END seconds for matched-stem ranking")
    parser.add_argument("--top-channels", type=int, default=8)
    parser.add_argument(
        "--alignment-analysis-frames",
        type=int,
        default=DEFAULT_ALIGNMENT_ANALYSIS_FRAMES,
        help="Maximum frames from each focus window used for local shift search; use 0 for full-window alignment",
    )
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
    if args.top_channels <= 0:
        print("--top-channels must be greater than zero", file=sys.stderr)
        return 2
    if args.alignment_search_frames < 0:
        print("--alignment-search-frames must be zero or greater", file=sys.stderr)
        return 2
    if args.alignment_analysis_frames < 0:
        print("--alignment-analysis-frames must be zero or greater", file=sys.stderr)
        return 2

    try:
        diagnostics = build_diagnostics(
            args.stem,
            args.sum_output,
            full_render_path=args.full_render,
            candidate_stem_paths=args.candidate_stem,
            focus_windows=args.focus_window,
            top_channels=args.top_channels,
            alignment_analysis_frames=args.alignment_analysis_frames if args.alignment_analysis_frames > 0 else None,
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
