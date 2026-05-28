#!/usr/bin/env python3
"""Compare two local WAV renders and emit deterministic diagnostic metrics."""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_SECONDS = 30.0
DEFAULT_DIFF_THRESHOLD = 1.0e-4
DEFAULT_NEAR_SILENCE_THRESHOLD = 1.0e-5
DEFAULT_WINDOW_MS = 100.0
DEFAULT_TOP_WINDOWS = 5
DEFAULT_ALIGNMENT_SEARCH_FRAMES = 0
FLOAT_DIGITS = 9
WAVE_FORMAT_PCM = 1
WAVE_FORMAT_IEEE_FLOAT = 3
WAVE_FORMAT_EXTENSIBLE = 0xFFFE


@dataclass(frozen=True)
class WavInfo:
    path: Path
    sample_rate: int
    channels: int
    sample_width: int
    frame_count: int
    format_code: int
    sample_format: str

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
            "wav_format_code": self.format_code,
            "sample_format": self.sample_format,
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
    info, sample_bytes = read_wav_sample_bytes(path, seconds)
    if info.sample_format == "pcm":
        samples = decode_pcm_samples(sample_bytes, info.sample_width)
    elif info.sample_format == "ieee_float":
        samples = decode_float_samples(sample_bytes, info.sample_width)
    else:
        raise ValueError(f"{path}: unsupported WAV sample format: {info.sample_format}")
    return info, samples


def read_wav_sample_bytes(path: Path, seconds: float) -> tuple[WavInfo, bytes]:
    with path.open("rb") as wav_file:
        riff = read_exact(wav_file, 12, path)
        if riff[0:4] != b"RIFF" or riff[8:12] != b"WAVE":
            raise ValueError(f"{path}: expected RIFF/WAVE file")

        fmt: dict[str, int | str] | None = None
        data_bytes: bytes | None = None
        data_chunk_size: int | None = None

        while True:
            header = wav_file.read(8)
            if not header:
                break
            if len(header) != 8:
                raise ValueError(f"{path}: truncated WAV chunk header")
            chunk_id, chunk_size = struct.unpack("<4sI", header)
            if chunk_id == b"fmt ":
                fmt = parse_fmt_chunk(read_exact(wav_file, chunk_size, path), path)
            elif chunk_id == b"data":
                data_chunk_size = chunk_size
                if fmt is None:
                    data_bytes = read_exact(wav_file, chunk_size, path)
                else:
                    data_bytes = read_data_chunk(wav_file, chunk_size, fmt, seconds, path)
            else:
                wav_file.seek(chunk_size, 1)
            if chunk_size % 2 == 1:
                wav_file.seek(1, 1)

        if fmt is None:
            raise ValueError(f"{path}: missing WAV fmt chunk")
        if data_chunk_size is None or data_bytes is None:
            raise ValueError(f"{path}: missing WAV data chunk")

        block_align = int(fmt["block_align"])
        frame_count = data_chunk_size // block_align if block_align > 0 else 0
        info = WavInfo(
            path=path,
            sample_rate=int(fmt["sample_rate"]),
            channels=int(fmt["channels"]),
            sample_width=int(fmt["sample_width"]),
            frame_count=frame_count,
            format_code=int(fmt["format_code"]),
            sample_format=str(fmt["sample_format"]),
        )
        validate_wav_info(path, info)
        return info, data_bytes


def read_exact(file_object, byte_count: int, path: Path) -> bytes:
    data = file_object.read(byte_count)
    if len(data) != byte_count:
        raise ValueError(f"{path}: truncated WAV data")
    return data


def parse_fmt_chunk(chunk: bytes, path: Path) -> dict[str, int | str]:
    if len(chunk) < 16:
        raise ValueError(f"{path}: truncated WAV fmt chunk")
    format_code, channels, sample_rate, byte_rate, block_align, bits_per_sample = struct.unpack(
        "<HHIIHH",
        chunk[:16],
    )
    if format_code == WAVE_FORMAT_EXTENSIBLE:
        format_code = extensible_subformat_code(chunk, path)
    if bits_per_sample % 8 != 0:
        raise ValueError(f"{path}: unsupported non-byte-aligned WAV sample width: {bits_per_sample} bits")
    sample_width = bits_per_sample // 8
    sample_format = sample_format_name(format_code)
    return {
        "format_code": format_code,
        "channels": channels,
        "sample_rate": sample_rate,
        "byte_rate": byte_rate,
        "block_align": block_align,
        "bits_per_sample": bits_per_sample,
        "sample_width": sample_width,
        "sample_format": sample_format,
    }


def extensible_subformat_code(chunk: bytes, path: Path) -> int:
    if len(chunk) < 40:
        raise ValueError(f"{path}: truncated WAVE_FORMAT_EXTENSIBLE fmt chunk")
    return struct.unpack_from("<I", chunk, 24)[0]


def sample_format_name(format_code: int) -> str:
    if format_code == WAVE_FORMAT_PCM:
        return "pcm"
    if format_code == WAVE_FORMAT_IEEE_FLOAT:
        return "ieee_float"
    raise ValueError(f"unsupported WAV format code: {format_code}")


def validate_wav_info(path: Path, info: WavInfo) -> None:
    if info.channels <= 0:
        raise ValueError(f"{path}: channel count must be greater than zero")
    if info.sample_rate <= 0:
        raise ValueError(f"{path}: sample rate must be greater than zero")
    if info.sample_format == "pcm" and info.sample_width not in (1, 2, 3, 4):
        raise ValueError(f"{path}: unsupported PCM sample width: {info.sample_width} bytes")
    if info.sample_format == "ieee_float" and info.sample_width not in (4, 8):
        raise ValueError(f"{path}: unsupported IEEE float sample width: {info.sample_width} bytes")


def read_data_chunk(file_object, chunk_size: int, fmt: dict[str, int | str], seconds: float, path: Path) -> bytes:
    block_align = int(fmt["block_align"])
    sample_rate = int(fmt["sample_rate"])
    if block_align <= 0:
        raise ValueError(f"{path}: WAV block align must be greater than zero")
    frame_count = chunk_size // block_align
    frames_to_read = min(frame_count, max(0, int(seconds * sample_rate)))
    bytes_to_read = min(chunk_size, frames_to_read * block_align)
    data = read_exact(file_object, bytes_to_read, path)
    remaining = chunk_size - bytes_to_read
    if remaining > 0:
        file_object.seek(remaining, 1)
    return data


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


def decode_float_samples(sample_bytes: bytes, sample_width: int) -> list[float]:
    if sample_width == 4:
        return [float(value[0]) for value in struct.iter_unpack("<f", sample_bytes)]
    if sample_width == 8:
        return [float(value[0]) for value in struct.iter_unpack("<d", sample_bytes)]
    raise ValueError(f"unsupported IEEE float sample width: {sample_width} bytes")


def stats_for(
    samples: Iterable[float],
    channels: int,
    sample_rate: int,
    sample_width: int,
    near_silence_threshold: float,
    sample_format: str = "pcm",
) -> AudioStats:
    sample_list = list(samples)
    count = len(sample_list)
    frames = count // channels if channels > 0 else 0
    duration = frames / sample_rate if sample_rate > 0 else 0.0
    if sample_format == "ieee_float":
        clipping_threshold = 1.0
    else:
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


def signal_rms(samples: list[float]) -> float:
    if not samples:
        return 0.0
    return math.sqrt(sum(sample * sample for sample in samples) / len(samples))


def channel_signal(samples: list[float], channels: int, channel: int) -> list[float]:
    if channels <= 0 or channel < 0 or channel >= channels:
        return []
    return samples[channel::channels]


def mono_sum_signal(samples: list[float], channels: int) -> list[float]:
    if channels <= 0:
        return []
    frames = len(samples) // channels
    result: list[float] = []
    for frame in range(frames):
        start = frame * channels
        result.append(sum(samples[start : start + channels]) / channels)
    return result


def stereo_side_signal(samples: list[float], channels: int) -> list[float]:
    if channels < 2:
        return []
    frames = len(samples) // channels
    result: list[float] = []
    for frame in range(frames):
        start = frame * channels
        result.append((samples[start] - samples[start + 1]) * 0.5)
    return result


def signal_comparison_metrics(
    reference: list[float],
    candidate: list[float],
    *,
    description: str,
) -> dict[str, object]:
    reference_rms = signal_rms(reference)
    raw_diff = diff_metrics(reference, candidate, 1, reference_rms)
    return {
        "description": description,
        "overlap_frames": min(len(reference), len(candidate)),
        "reference_rms": rounded(reference_rms),
        "candidate_rms": rounded(signal_rms(candidate)),
        "normalized_correlation": rounded_optional(normalized_correlation(reference, candidate)),
        "diff": raw_diff,
        "gain_normalized": gain_normalized_metrics(
            reference,
            candidate,
            1,
            reference_rms,
            float(raw_diff["overall_rms_difference"]),
        ),
    }


def comparison_mode_metrics(
    reference: list[float],
    candidate: list[float],
    channels: int,
    reference_rms: float,
    raw_diff: dict[str, object],
) -> dict[str, object]:
    modes: dict[str, object] = {
        "stereo": {
            "description": "interleaved samples as-is",
            "overlap_frames": min(len(reference), len(candidate)) // channels if channels > 0 else 0,
            "reference_rms": rounded(reference_rms),
            "candidate_rms": rounded(signal_rms(candidate)),
            "normalized_correlation": rounded_optional(normalized_correlation(reference, candidate)),
            "diff": raw_diff,
            "gain_normalized": gain_normalized_metrics(
                reference,
                candidate,
                channels,
                reference_rms,
                float(raw_diff["overall_rms_difference"]),
            ),
        },
        "mono_sum": signal_comparison_metrics(
            mono_sum_signal(reference, channels),
            mono_sum_signal(candidate, channels),
            description="per-frame channel average for mono-summed comparison",
        ),
    }
    if channels >= 1:
        modes["left"] = signal_comparison_metrics(
            channel_signal(reference, channels, 0),
            channel_signal(candidate, channels, 0),
            description="channel 0 only",
        )
    if channels >= 2:
        modes["right"] = signal_comparison_metrics(
            channel_signal(reference, channels, 1),
            channel_signal(candidate, channels, 1),
            description="channel 1 only",
        )
        modes["side"] = signal_comparison_metrics(
            stereo_side_signal(reference, channels),
            stereo_side_signal(candidate, channels),
            description="(left - right) / 2 side-channel comparison",
        )
    return modes


def frame_slice(samples: list[float], channels: int, start_frame: int, end_frame: int) -> list[float]:
    if channels <= 0:
        return []
    return samples[start_frame * channels : end_frame * channels]


def window_signal_metrics(reference: list[float], candidate: list[float]) -> dict[str, object]:
    reference_rms = signal_rms(reference)
    candidate_rms = signal_rms(candidate)
    diff = diff_metrics(reference, candidate, 1, reference_rms)
    result = {
        "reference_rms": rounded(reference_rms),
        "candidate_rms": rounded(candidate_rms),
        "rms_difference": diff["overall_rms_difference"],
        "normalized_correlation": rounded_optional(normalized_correlation(reference, candidate)),
        "gain_normalized": gain_normalized_metrics(
            reference,
            candidate,
            1,
            reference_rms,
            float(diff["overall_rms_difference"]),
        ),
    }
    if reference_rms > 0.0 or candidate_rms > 0.0:
        result["reference_energy"] = rounded(reference_rms * reference_rms)
        result["candidate_energy"] = rounded(candidate_rms * candidate_rms)
        result["candidate_minus_reference_energy"] = rounded((candidate_rms * candidate_rms) - (reference_rms * reference_rms))
    return result


def window_stereo_mono_metrics(
    reference: list[float],
    candidate: list[float],
    channels: int,
    start_frame: int,
    end_frame: int,
) -> dict[str, object]:
    reference_window = frame_slice(reference, channels, start_frame, end_frame)
    candidate_window = frame_slice(candidate, channels, start_frame, end_frame)
    metrics: dict[str, object] = {
        "mono_sum": window_signal_metrics(
            mono_sum_signal(reference_window, channels),
            mono_sum_signal(candidate_window, channels),
        ),
    }
    if channels >= 1:
        metrics["left"] = window_signal_metrics(
            channel_signal(reference_window, channels, 0),
            channel_signal(candidate_window, channels, 0),
        )
    if channels >= 2:
        metrics["right"] = window_signal_metrics(
            channel_signal(reference_window, channels, 1),
            channel_signal(candidate_window, channels, 1),
        )
        metrics["side"] = window_signal_metrics(
            stereo_side_signal(reference_window, channels),
            stereo_side_signal(candidate_window, channels),
        )
    return metrics


def timbre_profile(samples: list[float], sample_rate: int) -> dict[str, object]:
    if not samples:
        return {
            "first_10ms_rms": 0.0,
            "derivative_rms": 0.0,
            "first_10ms_derivative_rms": 0.0,
            "transient_derivative_to_sustain_ratio": None,
            "max_abs_delta": 0.0,
            "high_frequency_proxy_ratio": None,
            "spectral_centroid_proxy_hz": None,
            "band_energy_proxy": band_energy_proxy([]),
            "zero_crossing_rate": None,
        }
    first_10ms_frames = max(1, min(len(samples), int(sample_rate * 0.010))) if sample_rate > 0 else len(samples)
    deltas = [samples[index] - samples[index - 1] for index in range(1, len(samples))]
    rms = signal_rms(samples)
    derivative_rms = signal_rms(deltas)
    first_10ms_delta_count = max(0, first_10ms_frames - 1)
    first_10ms_derivative_rms = signal_rms(deltas[:first_10ms_delta_count])
    sustain_derivative_rms = signal_rms(deltas[first_10ms_delta_count:])
    zero_crossings = sum(
        1
        for index in range(1, len(samples))
        if (samples[index - 1] < 0.0 <= samples[index]) or (samples[index - 1] > 0.0 >= samples[index])
    )
    high_frequency_proxy_ratio = derivative_rms / rms if rms > 0.0 else None
    return {
        "first_10ms_rms": rounded(signal_rms(samples[:first_10ms_frames])),
        "derivative_rms": rounded(derivative_rms),
        "first_10ms_derivative_rms": rounded(first_10ms_derivative_rms),
        "transient_derivative_to_sustain_ratio": rounded_optional(
            first_10ms_derivative_rms / sustain_derivative_rms if sustain_derivative_rms > 0.0 else None
        ),
        "max_abs_delta": rounded(max((abs(delta) for delta in deltas), default=0.0)),
        "high_frequency_proxy_ratio": rounded_optional(high_frequency_proxy_ratio),
        "spectral_centroid_proxy_hz": rounded_optional(
            spectral_centroid_proxy_hz(high_frequency_proxy_ratio, sample_rate)
        ),
        "band_energy_proxy": band_energy_proxy(samples),
        "zero_crossing_rate": rounded_optional(zero_crossings / (len(samples) - 1) if len(samples) > 1 else None),
    }


def moving_average(samples: list[float], width: int) -> list[float]:
    if not samples:
        return []
    window_width = max(1, width)
    if window_width == 1:
        return list(samples)

    half_width = window_width // 2
    prefix_sum = [0.0]
    for sample in samples:
        prefix_sum.append(prefix_sum[-1] + sample)

    averaged: list[float] = []
    for index in range(len(samples)):
        start = max(0, index - half_width)
        end = min(len(samples), index + half_width + 1)
        averaged.append((prefix_sum[end] - prefix_sum[start]) / float(end - start))
    return averaged


def band_energy_proxy(samples: list[float]) -> dict[str, object]:
    if not samples:
        return {
            "low_rms": 0.0,
            "mid_rms": 0.0,
            "high_rms": 0.0,
            "low_ratio": None,
            "mid_ratio": None,
            "high_ratio": None,
        }

    low = moving_average(samples, 16)
    mid_smooth = moving_average(samples, 4)
    mid = [mid_smooth[index] - low[index] for index in range(len(samples))]
    high = [samples[index] - mid_smooth[index] for index in range(len(samples))]
    low_rms = signal_rms(low)
    mid_rms = signal_rms(mid)
    high_rms = signal_rms(high)
    total_energy = (low_rms * low_rms) + (mid_rms * mid_rms) + (high_rms * high_rms)
    return {
        "low_rms": rounded(low_rms),
        "mid_rms": rounded(mid_rms),
        "high_rms": rounded(high_rms),
        "low_ratio": rounded_optional((low_rms * low_rms) / total_energy if total_energy > 0.0 else None),
        "mid_ratio": rounded_optional((mid_rms * mid_rms) / total_energy if total_energy > 0.0 else None),
        "high_ratio": rounded_optional((high_rms * high_rms) / total_energy if total_energy > 0.0 else None),
    }


def spectral_centroid_proxy_hz(high_frequency_proxy_ratio: float | None, sample_rate: int) -> float | None:
    if high_frequency_proxy_ratio is None or sample_rate <= 0:
        return None
    # For a sine wave, derivative_rms/rms is 2*sin(pi*f/sample_rate). Invert it
    # as a rough single-number brightness proxy for mixed tracker audio.
    normalized = max(0.0, min(1.0, high_frequency_proxy_ratio / 2.0))
    return math.asin(normalized) * float(sample_rate) / math.pi


def residual_signal(reference: list[float], candidate: list[float]) -> list[float]:
    sample_count = min(len(reference), len(candidate))
    return [candidate[index] - reference[index] for index in range(sample_count)]


def window_timbre_metrics(
    reference: list[float],
    candidate: list[float],
    channels: int,
    sample_rate: int,
    start_frame: int,
    end_frame: int,
) -> dict[str, object]:
    reference_window = frame_slice(reference, channels, start_frame, end_frame)
    candidate_window = frame_slice(candidate, channels, start_frame, end_frame)
    reference_mono = mono_sum_signal(reference_window, channels)
    candidate_mono = mono_sum_signal(candidate_window, channels)
    residual_mono = residual_signal(reference_mono, candidate_mono)
    reference_mono_rms = signal_rms(reference_mono)
    residual_rms = signal_rms(residual_mono)

    result: dict[str, object] = {
        "mono": {
            "reference": timbre_profile(reference_mono, sample_rate),
            "candidate": timbre_profile(candidate_mono, sample_rate),
            "residual": timbre_profile(residual_mono, sample_rate),
            "residual_rms": rounded(residual_rms),
            "residual_peak": rounded(max((abs(sample) for sample in residual_mono), default=0.0)),
            "residual_mean": rounded(sum(residual_mono) / len(residual_mono) if residual_mono else 0.0),
            "residual_to_reference_rms": rounded_optional(
                residual_rms / reference_mono_rms if reference_mono_rms > 0.0 else None
            ),
        },
    }
    return result


def aligned_window_metrics(
    reference: list[float],
    candidate: list[float],
    channels: int,
    start_frame: int,
    end_frame: int,
    candidate_shift_frames: int = 0,
) -> dict[str, object] | None:
    if channels <= 0:
        return None
    safe_start = max(0, start_frame)
    safe_end = max(safe_start, end_frame)
    frame_count = safe_end - safe_start
    if frame_count <= 0:
        return None

    candidate_start = safe_start + candidate_shift_frames
    candidate_end = candidate_start + frame_count
    if candidate_start < 0:
        return None
    if safe_end * channels > len(reference):
        return None
    if candidate_end * channels > len(candidate):
        return None

    reference_start_sample = safe_start * channels
    reference_end_sample = safe_end * channels
    candidate_start_sample = candidate_start * channels
    candidate_end_sample = candidate_end * channels
    reference_slice = reference[reference_start_sample:reference_end_sample]
    candidate_slice = candidate[candidate_start_sample:candidate_end_sample]
    if not reference_slice or len(reference_slice) != len(candidate_slice):
        return None

    dot = 0.0
    ref_square_sum = 0.0
    candidate_square_sum = 0.0
    diff_square_sum = 0.0
    max_abs = 0.0
    for index, ref in enumerate(reference_slice):
        cand = candidate_slice[index]
        dot += ref * cand
        ref_square_sum += ref * ref
        candidate_square_sum += cand * cand
        diff = cand - ref
        diff_square_sum += diff * diff
        max_abs = max(max_abs, abs(diff))

    denominator = math.sqrt(ref_square_sum * candidate_square_sum)
    correlation = None if denominator == 0.0 else dot / denominator
    sample_count = len(reference_slice)
    return {
        "candidate_shift_frames": candidate_shift_frames,
        "normalized_correlation": rounded_optional(correlation),
        "rms_difference": rounded(math.sqrt(diff_square_sum / sample_count)),
        "max_abs_sample_difference": rounded(max_abs),
        "compared_frames": frame_count,
    }


def local_alignment_search(
    reference: list[float],
    candidate: list[float],
    channels: int,
    sample_rate: int,
    start_frame: int,
    end_frame: int,
    search_radius_frames: int,
) -> dict[str, object]:
    radius = max(0, search_radius_frames)
    zero_shift = aligned_window_metrics(reference, candidate, channels, start_frame, end_frame, 0)
    best_shift: dict[str, object] | None = None
    for shift in range(-radius, radius + 1):
        metrics = aligned_window_metrics(reference, candidate, channels, start_frame, end_frame, shift)
        if metrics is None:
            continue
        correlation = metrics.get("normalized_correlation")
        correlation_value = float(correlation) if correlation is not None else -2.0
        key = (
            -correlation_value,
            float(metrics["rms_difference"]),
            float(metrics["max_abs_sample_difference"]),
            abs(shift),
            shift,
        )
        if best_shift is None or key < best_shift["_sort_key"]:
            best_shift = {**metrics, "_sort_key": key}
    if best_shift is not None:
        del best_shift["_sort_key"]
        best_shift["candidate_shift_seconds"] = rounded(
            float(best_shift["candidate_shift_frames"]) / sample_rate if sample_rate > 0 else 0.0
        )
    if zero_shift is not None:
        zero_shift["candidate_shift_seconds"] = 0.0
    return {
        "search_radius_frames": radius,
        "search_radius_seconds": rounded(radius / sample_rate if sample_rate > 0 else 0.0),
        "zero_shift": zero_shift,
        "best_shift": best_shift,
    }


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
    candidate_gain: float = 1.0,
) -> dict[str, object]:
    sample_count = min(len(reference), len(candidate))
    if sample_count == 0:
        per_channel = [0.0 for _ in range(channels)]
        overall = 0.0
        max_abs = 0.0
    else:
        diffs = [(candidate[index] * candidate_gain) - reference[index] for index in range(sample_count)]
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


def best_fit_candidate_gain(reference: list[float], candidate: list[float]) -> float | None:
    sample_count = min(len(reference), len(candidate))
    if sample_count == 0:
        return None

    candidate_square_sum = 0.0
    dot = 0.0
    for index in range(sample_count):
        ref = reference[index]
        cand = candidate[index]
        candidate_square_sum += cand * cand
        dot += ref * cand

    if candidate_square_sum == 0.0:
        return None
    return dot / candidate_square_sum


def gain_normalized_metrics(
    reference: list[float],
    candidate: list[float],
    channels: int,
    reference_rms: float,
    raw_rms_difference: float,
) -> dict[str, object]:
    gain = best_fit_candidate_gain(reference, candidate)
    if gain is None:
        return {
            "candidate_scalar_to_reference": None,
            "candidate_scalar_db": None,
            "rms_difference_reduction_ratio": None,
            "diff": None,
        }

    normalized_diff = diff_metrics(reference, candidate, channels, reference_rms, candidate_gain=gain)
    normalized_rms = normalized_diff["overall_rms_difference"]
    reduction_ratio = None
    if raw_rms_difference > 0.0:
        reduction_ratio = max(0.0, min(1.0, (raw_rms_difference - float(normalized_rms)) / raw_rms_difference))

    return {
        "candidate_scalar_to_reference": rounded(gain),
        "candidate_scalar_db": rounded_optional(amplitude_to_dbfs(abs(gain))),
        "rms_difference_reduction_ratio": rounded_optional(reduction_ratio),
        "diff": normalized_diff,
    }


def worst_mismatch_windows(
    reference: list[float],
    candidate: list[float],
    channels: int,
    sample_rate: int,
    window_ms: float,
    top_count: int,
    alignment_search_frames: int = DEFAULT_ALIGNMENT_SEARCH_FRAMES,
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
        reference_window = reference[start_sample:end_sample]
        candidate_window = candidate[start_sample:end_sample]
        reference_window_rms = signal_rms(reference_window)
        windows.append({
            "start_frame": start_frame,
            "end_frame": end_frame,
            "start_seconds": rounded(start_frame / sample_rate),
            "end_seconds": rounded(end_frame / sample_rate),
            "rms_difference": rounded(rms),
            "max_abs_sample_difference": rounded(max_abs),
            "gain_normalized": gain_normalized_metrics(
                reference_window,
                candidate_window,
                channels,
                reference_window_rms,
                rms,
            ),
        })

    windows.sort(key=lambda item: (-float(item["rms_difference"]), int(item["start_frame"])))
    selected = windows[:top_count]
    for window in selected:
        start_frame = int(window["start_frame"])
        end_frame = int(window["end_frame"])
        window["local_alignment"] = local_alignment_search(
            reference,
            candidate,
            channels,
            sample_rate,
            start_frame,
            end_frame,
            alignment_search_frames,
        )
        window["stereo_mono_metrics"] = window_stereo_mono_metrics(
            reference,
            candidate,
            channels,
            start_frame,
            end_frame,
        )
        window["timbre_metrics"] = window_timbre_metrics(
            reference,
            candidate,
            channels,
            sample_rate,
            start_frame,
            end_frame,
        )
    return selected


def build_comparison(
    reference_path: Path,
    candidate_path: Path,
    seconds: float = DEFAULT_SECONDS,
    diff_threshold: float = DEFAULT_DIFF_THRESHOLD,
    near_silence_threshold: float = DEFAULT_NEAR_SILENCE_THRESHOLD,
    window_ms: float = DEFAULT_WINDOW_MS,
    top_windows: int = DEFAULT_TOP_WINDOWS,
    alignment_search_frames: int = DEFAULT_ALIGNMENT_SEARCH_FRAMES,
) -> dict[str, object]:
    reference_info, reference_samples = read_wav(reference_path, seconds)
    candidate_info, candidate_samples = read_wav(candidate_path, seconds)

    reference_stats = stats_for(
        reference_samples,
        reference_info.channels,
        reference_info.sample_rate,
        reference_info.sample_width,
        near_silence_threshold,
        reference_info.sample_format,
    )
    candidate_stats = stats_for(
        candidate_samples,
        candidate_info.channels,
        candidate_info.sample_rate,
        candidate_info.sample_width,
        near_silence_threshold,
        candidate_info.sample_format,
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
        "alignment_search_frames": max(0, alignment_search_frames),
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
            "No resampling, downmixing, upmixing, or renderer-latency compensation is applied.",
            "Worst-window local alignment search is diagnostic only and shifts the candidate window when enabled.",
        ],
    }

    if sample_comparison_available:
        raw_diff = diff_metrics(reference_samples, candidate_samples, reference_info.channels, reference_stats.rms)
        gain_normalized = gain_normalized_metrics(
            reference_samples,
            candidate_samples,
            reference_info.channels,
            reference_stats.rms,
            float(raw_diff["overall_rms_difference"]),
        )
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
            "diff": raw_diff,
            "gain_normalized": gain_normalized,
            "comparison_modes": comparison_mode_metrics(
                reference_samples,
                candidate_samples,
                reference_info.channels,
                reference_stats.rms,
                raw_diff,
            ),
            "worst_windows": worst_mismatch_windows(
                reference_samples,
                candidate_samples,
                reference_info.channels,
                reference_info.sample_rate,
                window_ms,
                top_windows,
                alignment_search_frames,
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
        f"- Sample format: {format_text_match(reference_info['sample_format'], candidate_info['sample_format'])}",
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
        gain_normalized = sample_comparison.get("gain_normalized")
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
            "## Gain-Normalized Difference",
        ])
        if isinstance(gain_normalized, dict) and isinstance(gain_normalized.get("diff"), dict):
            normalized_diff = gain_normalized["diff"]
            assert isinstance(normalized_diff, dict)
            lines.extend([
                "- Candidate scalar to reference: "
                f"{format_optional_float(gain_normalized.get('candidate_scalar_to_reference'))} "
                f"({format_db(gain_normalized.get('candidate_scalar_db'))})",
                "- Gain-normalized RMS difference: "
                f"{normalized_diff['overall_rms_difference']:.8f}",
                "- Gain-normalized max absolute sample difference: "
                f"{normalized_diff['max_abs_sample_difference']:.8f}",
                "- RMS difference reduction after scalar normalization: "
                f"{format_optional_float(gain_normalized.get('rms_difference_reduction_ratio'))}",
                "",
            ])
        else:
            lines.extend([
                "- Unavailable because the candidate has no measurable energy in the analyzed overlap.",
                "",
            ])
        comparison_modes = sample_comparison.get("comparison_modes")
        if isinstance(comparison_modes, dict):
            lines.extend([
                "## Stereo / Mono Comparison Modes",
                "",
                "| Mode | Correlation | RMS Diff | Normalized RMS Diff | Candidate Scalar | Gain-Norm RMS Diff | Reduction |",
                "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
            ])
            for key, label in (
                ("stereo", "Stereo as-is"),
                ("mono_sum", "Mono-summed"),
                ("left", "Left only"),
                ("right", "Right only"),
                ("side", "Side channel"),
            ):
                mode = comparison_modes.get(key)
                if not isinstance(mode, dict):
                    continue
                mode_diff = mode.get("diff")
                mode_gain = mode.get("gain_normalized")
                normalized_mode_diff = nested_dict_value(mode_gain, "diff")
                lines.append(
                    f"| {label} | "
                    f"{format_optional_float(mode.get('normalized_correlation'))} | "
                    f"{format_optional_float(nested_value(mode_diff, 'overall_rms_difference'))} | "
                    f"{format_optional_float(nested_value(mode_diff, 'normalized_rms_difference'))} | "
                    f"{format_optional_float(nested_value(mode_gain, 'candidate_scalar_to_reference'))} | "
                    f"{format_optional_float(nested_value(normalized_mode_diff, 'overall_rms_difference'))} | "
                    f"{format_optional_float(nested_value(mode_gain, 'rms_difference_reduction_ratio'))} |"
                )
            lines.append("")
        lines.extend([
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
                window_gain = window.get("gain_normalized")
                if isinstance(window_gain, dict) and isinstance(window_gain.get("diff"), dict):
                    window_gain_diff = window_gain["diff"]
                    assert isinstance(window_gain_diff, dict)
                    lines.append(
                        "   gain_normalized: "
                        f"scalar={format_optional_float(window_gain.get('candidate_scalar_to_reference'))}, "
                        f"rms_diff={format_optional_float(window_gain_diff.get('overall_rms_difference'))}"
                    )
                alignment = window.get("local_alignment")
                if isinstance(alignment, dict):
                    best_shift = alignment.get("best_shift")
                    zero_shift = alignment.get("zero_shift")
                    if isinstance(best_shift, dict) and isinstance(zero_shift, dict):
                        lines.append(
                            "   local_alignment: "
                            f"radius={alignment.get('search_radius_frames')} frames, "
                            f"zero_corr={format_optional_float(zero_shift.get('normalized_correlation'))}, "
                            f"best_shift={best_shift.get('candidate_shift_frames')} frames, "
                            f"best_corr={format_optional_float(best_shift.get('normalized_correlation'))}, "
                            f"best_rms_diff={format_optional_float(best_shift.get('rms_difference'))}"
                        )
                mode_metrics = window.get("stereo_mono_metrics")
                if isinstance(mode_metrics, dict):
                    lines.append(f"   stereo_mono: {format_window_mode_summary(mode_metrics)}")
                timbre_metrics = window.get("timbre_metrics")
                if isinstance(timbre_metrics, dict):
                    lines.append(f"   timbre: {format_window_timbre_summary(timbre_metrics)}")
        lines.append("")

    lines.extend([
        "## Notes",
        "- This tool does not resample, downmix, upmix, or compensate for renderer latency.",
        "- Positive candidate_shift_frames means the candidate comparison slice starts later than the reference window.",
        "- Use mismatch windows as leads for focused follow-up debugging, not as an automatic pass/fail oracle.",
    ])
    return "\n".join(lines) + "\n"


def format_info(info: WavInfo) -> str:
    return (
        f"  format: {info.sample_rate} Hz, {info.channels} channel(s), "
        f"{info.sample_width * 8}-bit {info.sample_format}, {info.frame_count} frames, "
        f"{info.duration_seconds:.6f} s"
    )


def format_match(reference: int, candidate: int, unit: str) -> str:
    suffix = f" {unit}" if unit else ""
    if reference == candidate:
        return f"match ({reference}{suffix})"
    return f"mismatch (reference {reference}{suffix}, candidate {candidate}{suffix})"


def format_text_match(reference: object, candidate: object) -> str:
    if reference == candidate:
        return f"match ({reference})"
    return f"mismatch (reference {reference}, candidate {candidate})"


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


def nested_value(value: object, key: str) -> object:
    if not isinstance(value, dict):
        return None
    return value.get(key)


def nested_dict_value(value: object, key: str) -> dict[str, object]:
    nested = nested_value(value, key)
    return nested if isinstance(nested, dict) else {}


def format_window_mode_summary(metrics: dict[str, object]) -> str:
    parts: list[str] = []
    for key, label in (
        ("left", "L"),
        ("right", "R"),
        ("mono_sum", "mono"),
        ("side", "side"),
    ):
        mode = metrics.get(key)
        if not isinstance(mode, dict):
            continue
        parts.append(
            f"{label}_rms ref/cand/diff "
            f"{format_optional_float(mode.get('reference_rms'))}/"
            f"{format_optional_float(mode.get('candidate_rms'))}/"
            f"{format_optional_float(mode.get('rms_difference'))}"
        )
    return "; ".join(parts) if parts else "unavailable"


def format_window_timbre_summary(metrics: dict[str, object]) -> str:
    mono = nested_dict_value(metrics, "mono")
    reference = nested_dict_value(mono, "reference")
    candidate = nested_dict_value(mono, "candidate")
    residual = nested_dict_value(mono, "residual")
    reference_band = nested_dict_value(reference, "band_energy_proxy")
    candidate_band = nested_dict_value(candidate, "band_energy_proxy")
    residual_band = nested_dict_value(residual, "band_energy_proxy")
    parts = [
        "hf_proxy ref/cand/resid "
        f"{format_optional_float(reference.get('high_frequency_proxy_ratio'))}/"
        f"{format_optional_float(candidate.get('high_frequency_proxy_ratio'))}/"
        f"{format_optional_float(residual.get('high_frequency_proxy_ratio'))}",
        "centroid_proxy_hz ref/cand/resid "
        f"{format_optional_float(reference.get('spectral_centroid_proxy_hz'))}/"
        f"{format_optional_float(candidate.get('spectral_centroid_proxy_hz'))}/"
        f"{format_optional_float(residual.get('spectral_centroid_proxy_hz'))}",
        "band_high ref/cand/resid "
        f"{format_optional_float(reference_band.get('high_ratio'))}/"
        f"{format_optional_float(candidate_band.get('high_ratio'))}/"
        f"{format_optional_float(residual_band.get('high_ratio'))}",
        "delta_rms ref/cand/resid "
        f"{format_optional_float(reference.get('derivative_rms'))}/"
        f"{format_optional_float(candidate.get('derivative_rms'))}/"
        f"{format_optional_float(residual.get('derivative_rms'))}",
        "transient_delta_rms ref/cand/resid "
        f"{format_optional_float(reference.get('first_10ms_derivative_rms'))}/"
        f"{format_optional_float(candidate.get('first_10ms_derivative_rms'))}/"
        f"{format_optional_float(residual.get('first_10ms_derivative_rms'))}",
        "zero_cross ref/cand "
        f"{format_optional_float(reference.get('zero_crossing_rate'))}/"
        f"{format_optional_float(candidate.get('zero_crossing_rate'))}",
        f"residual_rms_ratio={format_optional_float(mono.get('residual_to_reference_rms'))}",
    ]
    return "; ".join(parts)


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
    parser.add_argument(
        "--alignment-search-frames",
        type=int,
        default=DEFAULT_ALIGNMENT_SEARCH_FRAMES,
        help=(
            "Search +/- this many frames around each worst window for local candidate/reference alignment "
            f"(default: {DEFAULT_ALIGNMENT_SEARCH_FRAMES})"
        ),
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
    if args.alignment_search_frames < 0:
        print("--alignment-search-frames must be zero or greater", file=sys.stderr)
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
            args.alignment_search_frames,
        )
    except (FileNotFoundError, ValueError) as error:
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
