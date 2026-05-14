#!/usr/bin/env python3
"""Compare two local PCM WAV renders and emit deterministic diagnostic metrics."""

from __future__ import annotations

import argparse
import json
import math
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_SECONDS = 30.0
DEFAULT_DIFF_THRESHOLD = 1.0e-4
DEFAULT_NEAR_SILENCE_THRESHOLD = 1.0e-5
DEFAULT_WINDOW_MS = 100.0
DEFAULT_TOP_WINDOWS = 5
FLOAT_DIGITS = 9


@dataclass(frozen=True)
class WavInfo:
    path: Path
    sample_rate: int
    channels: int
    sample_width: int
    frame_count: int

    @property
    def duration_seconds(self) -> float:
        if self.sample_rate == 0:
            return 0.0
        return self.frame_count / self.sample_rate

    def to_json(self) -> dict[str, object]:
        return {
            "path_name": self.path.name,
            "sample_rate": self.sample_rate,
            "channel_count": self.channels,
            "sample_width_bits": self.sample_width * 8,
            "frame_count": self.frame_count,
            "duration_seconds": rounded(self.duration_seconds),
        }


@dataclass(frozen=True)
class AudioStats:
    frames_analyzed: int
    duration_analyzed: float
    rms: float
    peak: float
    per_channel_rms: list[float]
    per_channel_peak: list[float]
    clipping_count: int
    near_silence_count: int
    near_silence_ratio: float
    stereo_balance: dict[str, float | None]

    @property
    def rms_dbfs(self) -> float | None:
        return amplitude_to_dbfs(self.rms)

    @property
    def peak_dbfs(self) -> float | None:
        return amplitude_to_dbfs(self.peak)

    def to_json(self) -> dict[str, object]:
        return {
            "frames_analyzed": self.frames_analyzed,
            "duration_analyzed_seconds": rounded(self.duration_analyzed),
            "overall_rms": rounded(self.rms),
            "overall_peak": rounded(self.peak),
            "overall_rms_dbfs": rounded_optional(self.rms_dbfs),
            "overall_peak_dbfs": rounded_optional(self.peak_dbfs),
            "per_channel_rms": [rounded(value) for value in self.per_channel_rms],
            "per_channel_peak": [rounded(value) for value in self.per_channel_peak],
            "clipping_count": self.clipping_count,
            "near_silence_count": self.near_silence_count,
            "near_silence_ratio": rounded(self.near_silence_ratio),
            "stereo_balance": {
                key: rounded_optional(value)
                for key, value in self.stereo_balance.items()
            },
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


def format_db(value: float | None) -> str:
    if value is None:
        return "-inf dBFS"
    return f"{value:.2f} dBFS"


def read_wav(path: Path, seconds: float) -> tuple[WavInfo, list[float]]:
    with wave.open(str(path), "rb") as wav_file:
        compression = wav_file.getcomptype()
        info = WavInfo(
            path=path,
            sample_rate=wav_file.getframerate(),
            channels=wav_file.getnchannels(),
            sample_width=wav_file.getsampwidth(),
            frame_count=wav_file.getnframes(),
        )

        if compression != "NONE":
            raise ValueError(f"{path}: only uncompressed PCM WAV files are supported")
        if info.channels <= 0:
            raise ValueError(f"{path}: channel count must be greater than zero")
        if info.sample_rate <= 0:
            raise ValueError(f"{path}: sample rate must be greater than zero")
        if info.sample_width not in (1, 2, 3, 4):
            raise ValueError(f"{path}: unsupported sample width: {info.sample_width} bytes")

        frames_to_read = min(info.frame_count, max(0, int(seconds * info.sample_rate)))
        pcm = wav_file.readframes(frames_to_read)
        samples = decode_pcm_samples(pcm, info.sample_width)
        return info, samples


def decode_pcm_samples(pcm: bytes, sample_width: int) -> list[float]:
    if sample_width == 1:
        return [(sample - 128) / 128.0 for sample in pcm]

    samples: list[float] = []
    max_amplitude = float(1 << ((sample_width * 8) - 1))
    for offset in range(0, len(pcm), sample_width):
        chunk = pcm[offset : offset + sample_width]
        if len(chunk) != sample_width:
            break
        value = int.from_bytes(chunk, byteorder="little", signed=True)
        samples.append(value / max_amplitude)
    return samples


def stats_for(
    samples: Iterable[float],
    channels: int,
    sample_rate: int,
    sample_width: int,
    near_silence_threshold: float,
) -> AudioStats:
    sample_list = list(samples)
    count = len(sample_list)
    frames = count // channels if channels > 0 else 0
    duration = frames / sample_rate if sample_rate > 0 else 0.0
    clipping_threshold = 1.0 - (1.0 / float(1 << ((sample_width * 8) - 1)))

    square_sum = sum(sample * sample for sample in sample_list)
    peak = max((abs(sample) for sample in sample_list), default=0.0)
    near_silence_count = sum(1 for sample in sample_list if abs(sample) <= near_silence_threshold)
    clipping_count = sum(1 for sample in sample_list if abs(sample) >= clipping_threshold)

    per_channel_rms: list[float] = []
    per_channel_peak: list[float] = []
    for channel in range(channels):
        channel_samples = sample_list[channel::channels]
        channel_square_sum = sum(sample * sample for sample in channel_samples)
        per_channel_rms.append(math.sqrt(channel_square_sum / len(channel_samples)) if channel_samples else 0.0)
        per_channel_peak.append(max((abs(sample) for sample in channel_samples), default=0.0))

    return AudioStats(
        frames_analyzed=frames,
        duration_analyzed=duration,
        rms=math.sqrt(square_sum / count) if count else 0.0,
        peak=peak,
        per_channel_rms=per_channel_rms,
        per_channel_peak=per_channel_peak,
        clipping_count=clipping_count,
        near_silence_count=near_silence_count,
        near_silence_ratio=(near_silence_count / count) if count else 0.0,
        stereo_balance=stereo_balance(per_channel_rms),
    )


def stereo_balance(per_channel_rms: list[float]) -> dict[str, float | None]:
    if len(per_channel_rms) < 2:
        return {
            "left_rms": None,
            "right_rms": None,
            "left_minus_right_rms": None,
            "left_right_energy_difference": None,
        }
    left_rms = per_channel_rms[0]
    right_rms = per_channel_rms[1]
    return {
        "left_rms": left_rms,
        "right_rms": right_rms,
        "left_minus_right_rms": left_rms - right_rms,
        "left_right_energy_difference": (left_rms * left_rms) - (right_rms * right_rms),
    }


def normalized_correlation(reference: list[float], candidate: list[float]) -> float | None:
    sample_count = min(len(reference), len(candidate))
    if sample_count == 0:
        return None

    dot = 0.0
    ref_square_sum = 0.0
    candidate_square_sum = 0.0
    for index in range(sample_count):
        ref = reference[index]
        cand = candidate[index]
        dot += ref * cand
        ref_square_sum += ref * ref
        candidate_square_sum += cand * cand

    denominator = math.sqrt(ref_square_sum * candidate_square_sum)
    if denominator == 0.0:
        return None
    return dot / denominator


def first_difference_timestamp(
    reference: list[float],
    candidate: list[float],
    channels: int,
    sample_rate: int,
    threshold: float,
) -> float | None:
    sample_count = min(len(reference), len(candidate))
    if channels <= 0 or sample_rate <= 0:
        return None

    for index in range(sample_count):
        if abs(reference[index] - candidate[index]) > threshold:
            return (index // channels) / sample_rate
    if len(reference) != len(candidate):
        return sample_count // channels / sample_rate
    return None


def diff_metrics(
    reference: list[float],
    candidate: list[float],
    channels: int,
    reference_rms: float,
) -> dict[str, object]:
    sample_count = min(len(reference), len(candidate))
    if sample_count == 0:
        per_channel = [0.0 for _ in range(channels)]
        overall = 0.0
        max_abs = 0.0
    else:
        diffs = [candidate[index] - reference[index] for index in range(sample_count)]
        overall = math.sqrt(sum(diff * diff for diff in diffs) / sample_count)
        max_abs = max((abs(diff) for diff in diffs), default=0.0)
        per_channel = []
        for channel in range(channels):
            channel_diffs = diffs[channel::channels]
            channel_square_sum = sum(diff * diff for diff in channel_diffs)
            per_channel.append(math.sqrt(channel_square_sum / len(channel_diffs)) if channel_diffs else 0.0)

    if reference_rms > 0.0:
        normalized = overall / reference_rms
    else:
        normalized = 0.0 if overall == 0.0 else None

    return {
        "overall_rms_difference": rounded(overall),
        "normalized_rms_difference": rounded_optional(normalized),
        "max_abs_sample_difference": rounded(max_abs),
        "per_channel_rms_difference": [rounded(value) for value in per_channel],
    }


def worst_mismatch_windows(
    reference: list[float],
    candidate: list[float],
    channels: int,
    sample_rate: int,
    window_ms: float,
    top_count: int,
) -> list[dict[str, object]]:
    if channels <= 0 or sample_rate <= 0 or top_count <= 0:
        return []
    overlap_frames = min(len(reference), len(candidate)) // channels
    if overlap_frames == 0:
        return []

    window_frames = max(1, int(sample_rate * window_ms / 1000.0))
    windows: list[dict[str, object]] = []
    for start_frame in range(0, overlap_frames, window_frames):
        end_frame = min(overlap_frames, start_frame + window_frames)
        start_sample = start_frame * channels
        end_sample = end_frame * channels
        sample_count = end_sample - start_sample
        if sample_count <= 0:
            continue

        square_sum = 0.0
        max_abs = 0.0
        for index in range(start_sample, end_sample):
            diff = candidate[index] - reference[index]
            square_sum += diff * diff
            max_abs = max(max_abs, abs(diff))
        rms = math.sqrt(square_sum / sample_count)
        windows.append({
            "start_frame": start_frame,
            "end_frame": end_frame,
            "start_seconds": rounded(start_frame / sample_rate),
            "end_seconds": rounded(end_frame / sample_rate),
            "rms_difference": rounded(rms),
            "max_abs_sample_difference": rounded(max_abs),
        })

    windows.sort(key=lambda item: (-float(item["rms_difference"]), int(item["start_frame"])))
    return windows[:top_count]


def build_comparison(
    reference_path: Path,
    candidate_path: Path,
    seconds: float = DEFAULT_SECONDS,
    diff_threshold: float = DEFAULT_DIFF_THRESHOLD,
    near_silence_threshold: float = DEFAULT_NEAR_SILENCE_THRESHOLD,
    window_ms: float = DEFAULT_WINDOW_MS,
    top_windows: int = DEFAULT_TOP_WINDOWS,
) -> dict[str, object]:
    reference_info, reference_samples = read_wav(reference_path, seconds)
    candidate_info, candidate_samples = read_wav(candidate_path, seconds)

    reference_stats = stats_for(
        reference_samples,
        reference_info.channels,
        reference_info.sample_rate,
        reference_info.sample_width,
        near_silence_threshold,
    )
    candidate_stats = stats_for(
        candidate_samples,
        candidate_info.channels,
        candidate_info.sample_rate,
        candidate_info.sample_width,
        near_silence_threshold,
    )

    sample_rate_matches = reference_info.sample_rate == candidate_info.sample_rate
    channel_count_matches = reference_info.channels == candidate_info.channels
    sample_width_matches = reference_info.sample_width == candidate_info.sample_width
    sample_comparison_available = sample_rate_matches and channel_count_matches

    comparison: dict[str, object] = {
        "schema_version": 1,
        "tool": "scripts/audio-compare.py",
        "requested_seconds": rounded(seconds),
        "diff_threshold": rounded(diff_threshold),
        "near_silence_threshold": rounded(near_silence_threshold),
        "window_ms": rounded(window_ms),
        "top_window_count": top_windows,
        "reference": {
            "info": reference_info.to_json(),
            "stats": reference_stats.to_json(),
        },
        "candidate": {
            "info": candidate_info.to_json(),
            "stats": candidate_stats.to_json(),
        },
        "format": {
            "sample_rate_matches": sample_rate_matches,
            "channel_count_matches": channel_count_matches,
            "sample_width_matches": sample_width_matches,
            "sample_comparison_available": sample_comparison_available,
            "duration_delta_seconds": rounded(candidate_info.duration_seconds - reference_info.duration_seconds),
            "frame_count_delta": candidate_info.frame_count - reference_info.frame_count,
            "analyzed_duration_delta_seconds": rounded(
                candidate_stats.duration_analyzed - reference_stats.duration_analyzed
            ),
            "analyzed_frame_count_delta": candidate_stats.frames_analyzed - reference_stats.frames_analyzed,
        },
        "sample_comparison": None,
        "notes": [
            "Diagnostic metrics only; they do not prove tracker semantic correctness.",
            "No resampling, downmixing, time alignment, or renderer-latency compensation is applied.",
        ],
    }

    if sample_comparison_available:
        comparison["sample_comparison"] = {
            "overlap_frames": min(reference_stats.frames_analyzed, candidate_stats.frames_analyzed),
            "first_difference_seconds": rounded_optional(first_difference_timestamp(
                reference_samples,
                candidate_samples,
                reference_info.channels,
                reference_info.sample_rate,
                diff_threshold,
            )),
            "normalized_correlation": rounded_optional(normalized_correlation(reference_samples, candidate_samples)),
            "diff": diff_metrics(reference_samples, candidate_samples, reference_info.channels, reference_stats.rms),
            "worst_windows": worst_mismatch_windows(
                reference_samples,
                candidate_samples,
                reference_info.channels,
                reference_info.sample_rate,
                window_ms,
                top_windows,
            ),
        }

    return comparison


def build_report(
    reference_path: Path,
    candidate_path: Path,
    seconds: float,
    diff_threshold: float,
) -> str:
    comparison = build_comparison(reference_path, candidate_path, seconds, diff_threshold)
    return build_markdown_report(comparison)


def build_markdown_report(comparison: dict[str, object]) -> str:
    reference = comparison["reference"]
    candidate = comparison["candidate"]
    format_info = comparison["format"]
    sample_comparison = comparison["sample_comparison"]
    assert isinstance(reference, dict)
    assert isinstance(candidate, dict)
    assert isinstance(format_info, dict)

    reference_info = reference["info"]
    candidate_info = candidate["info"]
    reference_stats = reference["stats"]
    candidate_stats = candidate["stats"]
    assert isinstance(reference_info, dict)
    assert isinstance(candidate_info, dict)
    assert isinstance(reference_stats, dict)
    assert isinstance(candidate_stats, dict)

    lines = [
        "# Audio Comparison Report",
        "",
        "Diagnostic metrics only; lower differences do not prove tracker semantic correctness.",
        "",
        "## Inputs",
        f"- Reference: {reference_info['path_name']}",
        f"- Candidate: {candidate_info['path_name']}",
        f"- Requested window: {comparison['requested_seconds']:.3f} s",
        "",
        "## Format",
        f"- Sample rate: {format_match(reference_info['sample_rate'], candidate_info['sample_rate'], 'Hz')}",
        f"- Channels: {format_match(reference_info['channel_count'], candidate_info['channel_count'], '')}",
        f"- Sample width: {format_match(reference_info['sample_width_bits'], candidate_info['sample_width_bits'], 'bit')}",
        f"- Reference frames/duration: {reference_info['frame_count']} / {reference_info['duration_seconds']:.6f} s",
        f"- Candidate frames/duration: {candidate_info['frame_count']} / {candidate_info['duration_seconds']:.6f} s",
        f"- Duration delta: {format_info['duration_delta_seconds']:+.6f} s",
        f"- Frame-count delta: {format_info['frame_count_delta']:+d}",
        "",
        "## Levels",
        "- Reference RMS: "
        f"{reference_stats['overall_rms']:.8f} ({format_db(reference_stats['overall_rms_dbfs'])})",
        "- Candidate RMS: "
        f"{candidate_stats['overall_rms']:.8f} ({format_db(candidate_stats['overall_rms_dbfs'])})",
        f"- Reference peak: {reference_stats['overall_peak']:.8f} ({format_db(reference_stats['overall_peak_dbfs'])})",
        f"- Candidate peak: {candidate_stats['overall_peak']:.8f} ({format_db(candidate_stats['overall_peak_dbfs'])})",
        f"- Reference per-channel RMS: {format_float_list(reference_stats['per_channel_rms'])}",
        f"- Candidate per-channel RMS: {format_float_list(candidate_stats['per_channel_rms'])}",
        f"- Reference per-channel peak: {format_float_list(reference_stats['per_channel_peak'])}",
        f"- Candidate per-channel peak: {format_float_list(candidate_stats['per_channel_peak'])}",
        f"- Reference clipping samples: {reference_stats['clipping_count']}",
        f"- Candidate clipping samples: {candidate_stats['clipping_count']}",
        "- Reference near-silence samples/ratio: "
        f"{reference_stats['near_silence_count']} / {reference_stats['near_silence_ratio']:.6f}",
        "- Candidate near-silence samples/ratio: "
        f"{candidate_stats['near_silence_count']} / {candidate_stats['near_silence_ratio']:.6f}",
        f"- Reference stereo balance: {format_stereo_balance(reference_stats['stereo_balance'])}",
        f"- Candidate stereo balance: {format_stereo_balance(candidate_stats['stereo_balance'])}",
        "",
        "## Sample Difference",
    ]

    if not isinstance(sample_comparison, dict):
        lines.extend([
            "- Skipped because sample rate or channel count differs.",
            "",
        ])
    else:
        diff = sample_comparison["diff"]
        assert isinstance(diff, dict)
        lines.extend([
            f"- Overlap frames: {sample_comparison['overlap_frames']}",
            f"- Overall RMS difference: {diff['overall_rms_difference']:.8f}",
            f"- Normalized RMS difference: {format_optional_float(diff['normalized_rms_difference'])}",
            f"- Max absolute sample difference: {diff['max_abs_sample_difference']:.8f}",
            f"- Per-channel RMS difference: {format_float_list(diff['per_channel_rms_difference'])}",
            f"- Normalized correlation: {format_optional_float(sample_comparison['normalized_correlation'])}",
            "- First difference "
            f"> {comparison['diff_threshold']:g}: {format_timestamp(sample_comparison['first_difference_seconds'])}",
            "",
            "## Worst Mismatch Windows",
        ])
        windows = sample_comparison["worst_windows"]
        assert isinstance(windows, list)
        if not windows:
            lines.append("- None within analyzed overlap.")
        else:
            for index, window in enumerate(windows, start=1):
                assert isinstance(window, dict)
                lines.append(
                    f"{index}. {window['start_seconds']:.6f}-{window['end_seconds']:.6f} s "
                    f"frames {window['start_frame']}-{window['end_frame']}: "
                    f"rms_diff={window['rms_difference']:.8f}, "
                    f"max_abs_diff={window['max_abs_sample_difference']:.8f}"
                )
        lines.append("")

    lines.extend([
        "## Notes",
        "- This tool does not resample, downmix, upmix, time-align, or compensate for renderer latency.",
        "- Use mismatch windows as leads for focused follow-up debugging, not as an automatic pass/fail oracle.",
    ])
    return "\n".join(lines) + "\n"


def format_info(info: WavInfo) -> str:
    return (
        f"  format: {info.sample_rate} Hz, {info.channels} channel(s), "
        f"{info.sample_width * 8}-bit PCM, {info.frame_count} frames, "
        f"{info.duration_seconds:.6f} s"
    )


def format_match(reference: int, candidate: int, unit: str) -> str:
    suffix = f" {unit}" if unit else ""
    if reference == candidate:
        return f"match ({reference}{suffix})"
    return f"mismatch (reference {reference}{suffix}, candidate {candidate}{suffix})"


def db_difference(candidate: float, reference: float) -> str:
    candidate_db = amplitude_to_dbfs(candidate)
    reference_db = amplitude_to_dbfs(reference)
    if candidate_db is None or reference_db is None:
        return "unavailable"
    return f"{candidate_db - reference_db:+.2f} dB"


def format_optional_float(value: float | None) -> str:
    if value is None:
        return "unavailable"
    return f"{value:.8f}"


def format_float_list(values: object) -> str:
    if not isinstance(values, list):
        return "unavailable"
    return "[" + ", ".join(f"{float(value):.8f}" for value in values) + "]"


def format_stereo_balance(balance: object) -> str:
    if not isinstance(balance, dict) or balance.get("left_rms") is None or balance.get("right_rms") is None:
        return "unavailable"
    return (
        f"L-R RMS {float(balance['left_minus_right_rms']):+.8f}, "
        f"L-R energy {float(balance['left_right_energy_difference']):+.8f}"
    )


def format_timestamp(value: float | None) -> str:
    if value is None:
        return "none within analyzed window"
    return f"{value:.6f} s"


def write_json_report(path: Path, comparison: dict[str, object]) -> None:
    path.write_text(json.dumps(comparison, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare a reference WAV render with a VoodooTracker X candidate WAV.",
    )
    parser.add_argument("--reference", required=True, type=Path, help="Reference WAV path")
    parser.add_argument("--candidate", required=True, type=Path, help="Candidate WAV path")
    parser.add_argument(
        "--seconds",
        type=float,
        default=DEFAULT_SECONDS,
        help=f"Seconds to compare from the start of each file (default: {DEFAULT_SECONDS:g})",
    )
    parser.add_argument("--report", type=Path, help="Optional legacy Markdown report output path")
    parser.add_argument("--markdown", type=Path, help="Optional Markdown report output path")
    parser.add_argument("--json", dest="json_report", type=Path, help="Optional JSON report output path")
    parser.add_argument(
        "--diff-threshold",
        type=float,
        default=DEFAULT_DIFF_THRESHOLD,
        help=f"Absolute sample threshold for first-difference reporting (default: {DEFAULT_DIFF_THRESHOLD:g})",
    )
    parser.add_argument(
        "--near-silence-threshold",
        type=float,
        default=DEFAULT_NEAR_SILENCE_THRESHOLD,
        help=(
            "Absolute sample threshold for near-silence counting "
            f"(default: {DEFAULT_NEAR_SILENCE_THRESHOLD:g})"
        ),
    )
    parser.add_argument(
        "--window-ms",
        type=float,
        default=DEFAULT_WINDOW_MS,
        help=f"Window size for worst mismatch windows in milliseconds (default: {DEFAULT_WINDOW_MS:g})",
    )
    parser.add_argument(
        "--top-windows",
        type=int,
        default=DEFAULT_TOP_WINDOWS,
        help=f"Number of worst mismatch windows to report (default: {DEFAULT_TOP_WINDOWS})",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.seconds <= 0:
        print("--seconds must be greater than zero", file=sys.stderr)
        return 2
    if args.diff_threshold < 0:
        print("--diff-threshold must be zero or greater", file=sys.stderr)
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

    try:
        comparison = build_comparison(
            args.reference,
            args.candidate,
            args.seconds,
            args.diff_threshold,
            args.near_silence_threshold,
            args.window_ms,
            args.top_windows,
        )
    except (FileNotFoundError, wave.Error, ValueError) as error:
        print(f"audio-compare: {error}", file=sys.stderr)
        return 1

    markdown_report = build_markdown_report(comparison)
    markdown_paths = [path for path in (args.report, args.markdown) if path is not None]
    for path in markdown_paths:
        path.write_text(markdown_report, encoding="utf-8")
    if args.json_report:
        write_json_report(args.json_report, comparison)
    if not markdown_paths and not args.json_report:
        print(markdown_report, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
