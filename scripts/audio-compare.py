#!/usr/bin/env python3
"""Compare two PCM WAV renders and emit a concise audio metrics report."""

from __future__ import annotations

import argparse
import math
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_SECONDS = 30.0
DEFAULT_DIFF_THRESHOLD = 1.0e-4


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


@dataclass(frozen=True)
class AudioStats:
    frames_analyzed: int
    duration_analyzed: float
    rms: float
    peak: float

    @property
    def rms_dbfs(self) -> float | None:
        return amplitude_to_dbfs(self.rms)

    @property
    def peak_dbfs(self) -> float | None:
        return amplitude_to_dbfs(self.peak)


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


def stats_for(samples: Iterable[float], channels: int, sample_rate: int) -> AudioStats:
    count = 0
    square_sum = 0.0
    peak = 0.0

    for sample in samples:
        count += 1
        square_sum += sample * sample
        peak = max(peak, abs(sample))

    frames = count // channels if channels > 0 else 0
    rms = math.sqrt(square_sum / count) if count else 0.0
    duration = frames / sample_rate if sample_rate > 0 else 0.0
    return AudioStats(frames_analyzed=frames, duration_analyzed=duration, rms=rms, peak=peak)


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


def build_report(
    reference_path: Path,
    candidate_path: Path,
    seconds: float,
    diff_threshold: float,
) -> str:
    reference_info, reference_samples = read_wav(reference_path, seconds)
    candidate_info, candidate_samples = read_wav(candidate_path, seconds)

    reference_stats = stats_for(
        reference_samples,
        reference_info.channels,
        reference_info.sample_rate,
    )
    candidate_stats = stats_for(
        candidate_samples,
        candidate_info.channels,
        candidate_info.sample_rate,
    )

    lines = [
        "Audio Comparison Report",
        "=======================",
        "",
        f"Reference: {reference_info.path}",
        format_info(reference_info),
        f"Candidate: {candidate_info.path}",
        format_info(candidate_info),
        "",
        f"Requested window: {seconds:.3f} s",
        f"Reference analyzed: {reference_stats.duration_analyzed:.6f} s ({reference_stats.frames_analyzed} frames)",
        f"Candidate analyzed: {candidate_stats.duration_analyzed:.6f} s ({candidate_stats.frames_analyzed} frames)",
        "",
        "Format checks:",
        f"- Sample rate: {format_match(reference_info.sample_rate, candidate_info.sample_rate, 'Hz')}",
        f"- Channels: {format_match(reference_info.channels, candidate_info.channels, '')}",
        f"- Sample width: {format_match(reference_info.sample_width * 8, candidate_info.sample_width * 8, 'bit')}",
        f"- Full duration difference: {candidate_info.duration_seconds - reference_info.duration_seconds:+.6f} s",
        "",
        "Level metrics over analyzed window:",
        f"- Reference RMS: {reference_stats.rms:.8f} ({format_db(reference_stats.rms_dbfs)})",
        f"- Candidate RMS: {candidate_stats.rms:.8f} ({format_db(candidate_stats.rms_dbfs)})",
        f"- RMS level difference: {db_difference(candidate_stats.rms, reference_stats.rms)}",
        f"- Reference peak: {reference_stats.peak:.8f} ({format_db(reference_stats.peak_dbfs)})",
        f"- Candidate peak: {candidate_stats.peak:.8f} ({format_db(candidate_stats.peak_dbfs)})",
        f"- Peak level difference: {db_difference(candidate_stats.peak, reference_stats.peak)}",
        "",
    ]

    if (
        reference_info.sample_rate == candidate_info.sample_rate
        and reference_info.channels == candidate_info.channels
    ):
        correlation = normalized_correlation(reference_samples, candidate_samples)
        first_difference = first_difference_timestamp(
            reference_samples,
            candidate_samples,
            reference_info.channels,
            reference_info.sample_rate,
            diff_threshold,
        )
        lines.extend(
            [
                "Sample comparison:",
                f"- Normalized correlation: {format_optional_float(correlation)}",
                f"- First difference > {diff_threshold:g}: {format_timestamp(first_difference)}",
            ]
        )
    else:
        lines.extend(
            [
                "Sample comparison:",
                "- Skipped because sample rate or channel count differs.",
            ]
        )

    lines.extend(
        [
            "",
            "Notes:",
            "- This tool does not resample, time-align, or compensate for renderer latency.",
            "- Correlation is a rough level-independent check over interleaved PCM samples.",
        ]
    )
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


def format_timestamp(value: float | None) -> str:
    if value is None:
        return "none within analyzed window"
    return f"{value:.6f} s"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare a reference WAV render with a VoodooTracker X WAV capture.",
    )
    parser.add_argument("--reference", required=True, type=Path, help="Reference WAV path")
    parser.add_argument("--candidate", required=True, type=Path, help="Candidate WAV path")
    parser.add_argument(
        "--seconds",
        type=float,
        default=DEFAULT_SECONDS,
        help=f"Seconds to compare from the start of each file (default: {DEFAULT_SECONDS:g})",
    )
    parser.add_argument("--report", type=Path, help="Optional text report output path")
    parser.add_argument(
        "--diff-threshold",
        type=float,
        default=DEFAULT_DIFF_THRESHOLD,
        help=f"Absolute sample threshold for first-difference reporting (default: {DEFAULT_DIFF_THRESHOLD:g})",
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

    try:
        report = build_report(args.reference, args.candidate, args.seconds, args.diff_threshold)
    except (FileNotFoundError, wave.Error, ValueError) as error:
        print(f"audio-compare: {error}", file=sys.stderr)
        return 1

    if args.report:
        args.report.write_text(report, encoding="utf-8")
    else:
        print(report, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
