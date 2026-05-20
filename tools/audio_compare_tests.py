import importlib.util
import json
import math
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "audio-compare.py"
SMOKE_SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "local-reference-compare-smoke.py"
CORRELATION_SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "correlate-audio-comparison.py"
DISCONTINUITY_SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "analyze-audio-discontinuities.py"
RUNTIME_TRACE_SUMMARY_SCRIPT_PATH = (
    Path(__file__).resolve().parents[1] / "scripts" / "summarize-runtime-c-mixer-trace.py"
)


def load_audio_compare_module():
    spec = importlib.util.spec_from_file_location("audio_compare", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_audio_discontinuities_module():
    spec = importlib.util.spec_from_file_location("audio_discontinuities", DISCONTINUITY_SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_runtime_trace_summary_module():
    spec = importlib.util.spec_from_file_location("runtime_trace_summary", RUNTIME_TRACE_SUMMARY_SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


audio_compare = load_audio_compare_module()
audio_discontinuities = load_audio_discontinuities_module()
runtime_trace_summary = load_runtime_trace_summary_module()


def synthetic_comparison_json(start_frame=100, end_frame=150):
    return {
        "schema_version": 1,
        "tool": "scripts/audio-compare.py",
        "candidate": {"info": {"sample_rate": 1000}},
        "reference": {"info": {"sample_rate": 1000}},
        "sample_comparison": {
            "worst_windows": [
                {
                    "start_frame": start_frame,
                    "end_frame": end_frame,
                    "start_seconds": start_frame / 1000,
                    "end_seconds": end_frame / 1000,
                    "rms_difference": 0.25,
                    "max_abs_sample_difference": 0.75,
                }
            ]
        },
    }


def synthetic_diagnostics_json(event_start=110, event_end=145):
    source = {"order": 0, "pattern": 2, "row": 4}
    return {
        "schema_version": 1,
        "tool": "vtx_render_bounded_xm",
        "render": {
            "sample_rate": 1000,
            "rendered_frame_count": 400,
            "requested_start_order_index": 0,
            "requested_order_count": 1,
            "initial_speed": 6,
            "initial_bpm": 125,
        },
        "event_coverage": {
            "total_cells_visited": 8,
            "empty_cells": 2,
            "normal_note_cells": 3,
            "note_off_cells": 1,
            "invalid_note_cells": 0,
            "instrument_only_cells": 0,
            "note_with_instrument_cells": 2,
            "note_with_missing_or_zero_instrument_cells": 1,
            "scheduled_note_events": 1,
            "skipped_note_events": 2,
            "skipped_note_off_events_no_active_voice": 1,
            "ignored_or_deferred_cells": 4,
            "sample_map_selection_events": 1,
            "first_playable_sample_fallback_events": 0,
            "fallback_after_invalid_sample_map_events": 0,
            "skipped_no_valid_sample_events": 0,
            "sample_map_keymap_deferred_events": 0,
            "sample_map_keymap_missing_or_deferred_events": 0,
            "event_outside_bounded_row_range_count": 0,
            "event_capacity_limit_count": 0,
            "c_mixer_voice_capacity_limit_count": 0,
            "skip_reason_counts": [
                {"reason": "missing_instrument", "count": 1},
                {"reason": "sample_pcm_empty", "count": 1},
            ],
            "capacity": {
                "c_mixer_voice_capacity": 256,
                "c_mixer_scheduled_voice_capacity": 256,
                "c_mixer_active_voice_capacity": 256,
                "scheduled_voice_capacity": 256,
                "active_voice_capacity": 256,
                "scheduled_voice_attempt_count": 1,
                "scheduled_voice_accepted_count": 1,
                "scheduled_voice_rejected_count": 0,
                "scheduled_voice_capacity_rejected_count": 0,
                "active_voice_capacity_rejected_count": 0,
                "invalid_scheduled_voice_rejected_count": 0,
                "potentially_unscheduled_event_count": 0,
                "rejected_event_coordinates": [],
            },
            "first_skipped_note_coordinates": [
                {
                    "source": source,
                    "channel_index": 2,
                    "note": 49,
                    "instrument_index": 0,
                    "reason": "missing_instrument",
                }
            ],
        },
        "row_timing": [
            {
                "source": source,
                "synthetic_row": 4,
                "row_start_frame": 100,
                "row_end_frame": 160,
                "row_duration_frames": 60,
                "effective_speed": 6,
                "effective_bpm": 125,
            }
        ],
        "timing_changes": [
            {
                "source": source,
                "channel_index": 1,
                "effect_type": 15,
                "effect_param": 3,
                "row_start_frame": 100,
                "applies_to_synthetic_row_after": 5,
                "kind": "speed",
                "applied": True,
                "speed_before": 6,
                "bpm_before": 125,
                "speed_after": 3,
                "bpm_after": 125,
            }
        ],
        "volume_column_mappings": [
            {
                "source": source,
                "channel_index": 1,
                "synthetic_row": 4,
                "synthetic_tick": 0,
                "volume_column": {
                    "raw_value": 48,
                    "command": {"name": "setVolume", "value": 32},
                    "classification": "supported",
                    "applied": True,
                    "ignored_as_empty_or_no_op": False,
                    "deferred": False,
                },
            }
        ],
        "events": [
            {
                "source": source,
                "channel_index": 1,
                "note": 49,
                "instrument_index": 7,
                "sample_index": 2,
                "sample_map_keymap_present": True,
                "mapped_sample_index": 2,
                "mapped_sample_valid": True,
                "sample_selection_method": "sample_map",
                "selected_sample_selection_method": "sample_map",
                "sample_selection_strategy": "sample_map",
                "first_playable_sample_fallback_used": False,
                "sample_map_keymap_behavior_deferred": False,
                "sample_map_keymap_missing_or_deferred": False,
                "synthetic_row": 4,
                "synthetic_tick": 0,
                "event_index": 0,
                "scheduled_start_frame": event_start,
                "estimated_end_frame": event_end,
                "estimated_duration_frames": event_end - event_start,
                "sample_frame_count": 35,
                "gain": 0.5,
                "pan": -0.25,
                "loop_mode": "forward",
                "volume_column": {
                    "raw_value": 48,
                    "command": {"name": "setVolume", "value": 32},
                    "classification": "supported",
                    "applied": True,
                    "ignored_as_empty_or_no_op": False,
                    "deferred": False,
                },
                "sample_offset": {
                    "status": "applied",
                    "effect_type": 9,
                    "effect_param": 2,
                    "detected": True,
                    "applied": True,
                    "deferred": False,
                    "ignored_as_no_op": False,
                    "skipped": False,
                    "out_of_range": False,
                    "computed_offset_frames": 512,
                    "applied_offset_frames": 512,
                    "selected_sample_length": 2048,
                },
                "volume_envelope": {
                    "status": "mapped",
                    "source_point_count": 2,
                    "mapped_point_count": 2,
                    "has_deferred_sustain": False,
                    "has_deferred_loop": True,
                    "has_deferred_fadeout": False,
                },
                "pitch": {
                    "playback_step": 1.25,
                    "sample_base_sample_rate": 8363,
                    "sample_relative_note": 0,
                    "sample_finetune": 0,
                    "output_sample_rate": 1000,
                    "effective_note_value": 49,
                    "effective_note_index": 48,
                    "effective_finetune": 0,
                    "linear_period": 4608.0,
                    "linear_frequency": 8363.0,
                    "frequency_table_status": "linear_applied",
                    "linear_frequency_applied": True,
                    "amiga_frequency_deferred": False,
                    "fallback_neutral_step_used": False,
                },
            }
        ],
    }


def synthetic_discontinuity_diagnostics(category, frame=10):
    source = {"order": 0, "pattern": 0, "row": 0}
    diagnostics = {
        "schema_version": 1,
        "tool": "vtx_render_bounded_xm",
        "render": {"sample_rate": 1000, "rendered_frame_count": 32},
        "row_timing": [
            {
                "source": source,
                "synthetic_row": 0,
                "row_start_frame": 0,
                "row_end_frame": 32,
                "row_duration_frames": 32,
            }
        ],
    }
    if category == "gain_pan_update":
        diagnostics["volume_panning_state_updates"] = [
            {
                "source": source,
                "channel_index": 0,
                "scheduled_frame": frame,
                "command_label": "Cxx set volume",
                "command_name": "cxxSetVolume",
                "status": "applied",
                "active_voice_updated": True,
                "gain_before": 1.0,
                "gain_after": 0.25,
            }
        ]
    elif category == "ecx_note_cut":
        diagnostics["note_cut_effects"] = [
            {
                "source": source,
                "channel_index": 0,
                "scheduled_frame": frame,
                "effect_type": 0x0E,
                "effect_param": 0xC2,
                "status": "applied",
                "applied": True,
            }
        ]
    elif category == "e9x_retrigger":
        diagnostics["retrigger_effects"] = [
            {
                "source": source,
                "channel_index": 0,
                "synthetic_row": 0,
                "effect_type": 0x0E,
                "effect_param": 0x91,
                "status": "applied",
                "applied": True,
                "retrigger_interval_ticks": 1,
                "retrigger_frames": [frame],
            }
        ]
    elif category == "window_boundary":
        diagnostics["windowed_render"] = {
            "enabled": True,
            "per_window": [
                {
                    "window_index": 0,
                    "start_row": 0,
                    "end_row_exclusive": 1,
                    "start_frame": 0,
                    "end_frame": frame,
                    "carried_voice_count": 0,
                    "boundary_continuation_count": 0,
                    "dropped_at_window_boundary_count": 0,
                },
                {
                    "window_index": 1,
                    "start_row": 1,
                    "end_row_exclusive": 2,
                    "start_frame": frame,
                    "end_frame": frame + 10,
                    "carried_voice_count": 1,
                    "boundary_continuation_count": 1,
                    "dropped_at_window_boundary_count": 0,
                    "may_contain_boundary_cuts": False,
                },
            ],
        }
    return diagnostics


def deferred_effect_field(effect_type, effect_param, row=4, channel=1):
    return {
        "source": {"order": 0, "pattern": 2, "row": row},
        "channel_index": channel,
        "note": 49,
        "instrument_index": 7,
        "volume_column_raw": 0,
        "volume_column": {
            "raw_value": 0,
            "command": {"name": "none"},
            "classification": "ignored_no_op",
            "applied": False,
            "ignored_as_empty_or_no_op": True,
            "deferred": False,
        },
        "effect_type": effect_type,
        "effect_param": effect_param,
        "field": "effect",
    }


def note_cut_effect(status="applied", row=4, channel=1, tick=2, scheduled_frame=112):
    return {
        "source": {"order": 0, "pattern": 2, "row": row},
        "channel_index": channel,
        "synthetic_row": row,
        "synthetic_tick": tick,
        "effect_type": 0x0E,
        "effect_param": 0xC0 | tick,
        "status": status,
        "detected": True,
        "applied": status == "applied",
        "deferred": False,
        "ignored_as_no_op": status != "applied",
        "out_of_row": status == "out_of_row_no_op",
        "requested_tick": tick,
        "row_speed": 6,
        "row_bpm": 125,
        "scheduled_frame": scheduled_frame,
        "absolute_frame": scheduled_frame,
        "active_event_index": 0 if status == "applied" else None,
        "target_voice_indices": [0] if status == "applied" else [],
        "target_voice_index": 0 if status == "applied" else None,
    }


def note_delay_effect(status="applied", row=4, channel=2, tick=2, original_frame=110, delayed_frame=112):
    return {
        "source": {"order": 0, "pattern": 2, "row": row},
        "channel_index": channel,
        "synthetic_row": row,
        "synthetic_tick": tick,
        "effect_type": 0x0E,
        "effect_param": 0xD0 | tick,
        "status": status,
        "detected": True,
        "applied": status == "applied",
        "deferred": status == "no_note_deferred",
        "ignored_as_no_op": status == "out_of_row_no_op",
        "out_of_row": status == "out_of_row_no_op",
        "requested_tick": tick,
        "row_speed": 6,
        "row_bpm": 125,
        "original_frame": original_frame,
        "delayed_frame": delayed_frame if status == "applied" else None,
        "scheduled_frame": delayed_frame if status == "applied" else None,
        "absolute_frame": delayed_frame if status == "applied" else None,
        "event_index": 0 if status == "applied" else None,
    }


def retrigger_effect(status="applied", row=4, channel=1, interval=2, frames=None):
    frames = [112, 114] if frames is None else frames
    return {
        "source": {"order": 0, "pattern": 2, "row": row},
        "channel_index": channel,
        "synthetic_row": row,
        "synthetic_tick": 0,
        "effect_type": 0x0E,
        "effect_param": 0x90 | interval,
        "status": status,
        "detected": True,
        "applied": status == "applied",
        "deferred": status == "ignored_e90_no_effect_memory",
        "ignored_as_no_op": status != "applied",
        "out_of_row": status == "out_of_row_no_op",
        "active_voice_found": status != "no_active_voice",
        "active_sample_found": status != "no_active_voice",
        "retrigger_interval_ticks": interval,
        "row_speed": 6,
        "row_bpm": 125,
        "retrigger_ticks": [interval, interval * 2] if status == "applied" else [],
        "retrigger_frames": frames if status == "applied" else [],
        "generated_retrigger_frames": frames if status == "applied" else [],
        "retrigger_event_indices": [1, 2] if status == "applied" else [],
        "replaced_event_indices": [0, 1] if status == "applied" else [],
        "active_event_index_before": 0 if status != "no_active_voice" else None,
        "selected_sample_index": 0 if status != "no_active_voice" else None,
        "selected_sample_length": 16 if status != "no_active_voice" else None,
        "initial_source_frame": 0 if status != "no_active_voice" else None,
        "playback_step": 1.0 if status != "no_active_voice" else None,
        "gain": 1.0 if status != "no_active_voice" else None,
        "pan": 0.0 if status != "no_active_voice" else None,
        "envelope_policy": "fresh_event_restarts_envelope",
    }


def traversal_effect(effect_type, effect_param, label, row=4, channel=1, status="deferred/unsupported"):
    return {
        "source": {"order": 0, "pattern": 2, "row": row},
        "channel_index": channel,
        "effect_type": effect_type,
        "effect_param": effect_param,
        "effect_label": label,
        "decoded_label": label,
        "status": status,
        "current_status": status,
        "is_traversal_hazard": label in {"Bxx position jump", "Dxx pattern break", "EEx pattern delay"},
    }


def traversal_summary(effects):
    return {
        "total_bxx_position_jump": sum(1 for effect in effects if effect["effect_label"] == "Bxx position jump"),
        "total_dxx_pattern_break": sum(1 for effect in effects if effect["effect_label"] == "Dxx pattern break"),
        "total_eex_pattern_delay": sum(1 for effect in effects if effect["effect_label"] == "EEx pattern delay"),
        "total_fxx_speed_bpm": sum(1 for effect in effects if effect["effect_label"] == "Fxx speed/BPM"),
        "total_e9x_retrigger": sum(1 for effect in effects if effect["effect_label"] == "E9x retrigger"),
        "total_ecx_note_cut": sum(1 for effect in effects if effect["effect_label"] == "ECx note cut"),
        "total_edx_note_delay": sum(1 for effect in effects if effect["effect_label"] == "EDx note delay"),
        "total_other_e_commands": sum(
            1 for effect in effects
            if effect["effect_type"] == 0x0E
            and effect["effect_label"] not in {"E9x retrigger", "EEx pattern delay", "ECx note cut", "EDx note delay"}
        ),
        "total_traversal_hazards": sum(1 for effect in effects if effect["is_traversal_hazard"]),
        "likely_ignores_structure_changing_behavior": any(effect["is_traversal_hazard"] for effect in effects),
        "first_traversal_hazard_coordinates": [
            effect for effect in effects if effect["is_traversal_hazard"]
        ][:10],
        "e_command_subtype_counts": [],
    }


def deferred_volume_mapping(raw_value, command_name, channel=2):
    return {
        "source": {"order": 0, "pattern": 2, "row": 4},
        "channel_index": channel,
        "synthetic_row": 4,
        "synthetic_tick": 0,
        "volume_column": {
            "raw_value": raw_value,
            "command": {"name": command_name, "amount": raw_value & 0x0F},
            "classification": "deferred",
            "applied": False,
            "ignored_as_empty_or_no_op": False,
            "deferred": True,
        },
    }


def volume_pan_state_update(
    command_source,
    command_name,
    command_label,
    *,
    status="applied",
    channel=1,
    effect_type=None,
    effect_param=None,
    raw_volume_column=None,
    cell_note=0,
):
    command = {"name": command_name, "label": command_label}
    if command_source == "volume_column":
        command["volume_column"] = {
            "name": command_name,
            "value": 32 if command_name == "setVolume" else 204,
        }
    return {
        "source": {"order": 0, "pattern": 2, "row": 4},
        "channel_index": channel,
        "synthetic_row": 4,
        "synthetic_tick": 0,
        "scheduled_frame": 110,
        "cell_note": cell_note,
        "instrument_index": 0,
        "command_source": command_source,
        "command_label": command_label,
        "command_name": command_name,
        "command": command,
        "raw_volume_column": raw_volume_column,
        "effect_type": effect_type,
        "effect_param": effect_param,
        "status": status,
        "applied": status == "applied",
        "deferred": status.startswith("deferred"),
        "ignored_as_no_op": status.startswith("ignored"),
        "active_voice_updated": status == "applied",
        "active_event_index": 0 if status == "applied" else None,
        "effective_volume_before": 64,
        "effective_volume_after": 32,
        "effective_pan_before": 0.0,
        "effective_pan_after": 1.0 if command_name in {"effect8xxSetPanning", "setPanning"} else 0.0,
        "gain_before": 1.0,
        "gain_after": 0.5,
        "pan_before": 0.0,
        "pan_after": 1.0 if command_name in {"effect8xxSetPanning", "setPanning"} else 0.0,
    }


def write_pcm16_wav(path, sample_rate=8000, channels=1, frames=None):
    frames = frames if frames is not None else sine_frames(sample_rate, channels)
    pcm = bytearray()
    for frame in frames:
        values = frame if isinstance(frame, tuple) else (frame,)
        if len(values) != channels:
            raise ValueError("frame channel count mismatch")
        for sample in values:
            clamped = max(-1.0, min(1.0, sample))
            value = -32768 if clamped <= -1.0 else int(clamped * 32767)
            pcm.extend(struct.pack("<h", value))

    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(bytes(pcm))


def sine_frames(sample_rate=8000, channels=1, seconds=0.25, amplitude=0.5):
    frame_count = int(sample_rate * seconds)
    frames = []
    for frame in range(frame_count):
        sample = math.sin(2.0 * math.pi * 440.0 * frame / sample_rate) * amplitude
        frames.append(tuple(sample for _ in range(channels)) if channels > 1 else sample)
    return frames


class AudioDiscontinuityTests(unittest.TestCase):
    def test_smooth_ramp_reports_no_large_jumps(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            wav = Path(tmpdir) / "smooth-ramp.wav"
            frames = [-0.1 + (0.2 * index / 63.0) for index in range(64)]
            write_pcm16_wav(wav, sample_rate=1000, frames=frames)

            analysis = audio_discontinuities.build_analysis(wav, top_count=5, threshold_pcm16=12000)

            self.assertEqual(analysis["wav"]["sample_rate"], 1000)
            self.assertEqual(analysis["analysis"]["threshold_jump_count"], 0)
            self.assertLess(analysis["top_adjacent_sample_jumps"][0]["jump_magnitude_pcm16"], 12000)

    def test_synthetic_ramped_gain_update_reduces_adjacent_sample_jump(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            instant_wav = tmpdir_path / "instant-gain-update.wav"
            ramped_wav = tmpdir_path / "ramped-gain-update.wav"
            instant_frames = [0.0] * 4 + [1.0] * 36
            ramped_frames = [0.0] * 4 + [index / 32.0 for index in range(1, 33)] + [1.0] * 4
            write_pcm16_wav(instant_wav, sample_rate=1000, frames=instant_frames)
            write_pcm16_wav(ramped_wav, sample_rate=1000, frames=ramped_frames)

            instant = audio_discontinuities.build_analysis(instant_wav, top_count=1, threshold_pcm16=12000)
            ramped = audio_discontinuities.build_analysis(ramped_wav, top_count=1, threshold_pcm16=12000)

            instant_jump = instant["top_adjacent_sample_jumps"][0]["jump_magnitude_pcm16"]
            ramped_jump = ramped["top_adjacent_sample_jumps"][0]["jump_magnitude_pcm16"]
            self.assertGreater(instant_jump, 30000)
            self.assertLess(ramped_jump, instant_jump / 20)
            self.assertEqual(ramped["analysis"]["threshold_jump_count"], 0)

    def test_detects_known_synthetic_jump_at_expected_frame_time_and_channel(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            wav = Path(tmpdir) / "known-jump.wav"
            frames = [0.0] * 10 + [0.8] + [0.8] * 4
            write_pcm16_wav(wav, sample_rate=1000, frames=frames)

            analysis = audio_discontinuities.build_analysis(wav, top_count=3, threshold_pcm16=12000)
            jump = analysis["top_adjacent_sample_jumps"][0]

            self.assertEqual(jump["frame"], 10)
            self.assertEqual(jump["time_seconds"], 0.01)
            self.assertEqual(jump["channel_index"], 0)
            self.assertGreater(jump["jump_magnitude_pcm16"], 26000)
            self.assertEqual(analysis["analysis"]["threshold_jump_count"], 1)

    def test_top_n_jumps_are_deterministic(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            wav = Path(tmpdir) / "ranked-jumps.wav"
            frames = [0.0, 0.25, -0.25, 0.75, -0.75, 0.1]
            write_pcm16_wav(wav, sample_rate=1000, frames=frames)

            analysis = audio_discontinuities.build_analysis(wav, top_count=3, threshold_pcm16=0)
            jumps = analysis["top_adjacent_sample_jumps"]

            self.assertEqual([jump["frame"] for jump in jumps], [4, 3, 5])
            self.assertEqual([jump["rank"] for jump in jumps], [1, 2, 3])

    def test_reports_pcm16_clipping_count_for_clipped_wav(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            wav = Path(tmpdir) / "clipped.wav"
            write_pcm16_wav(wav, sample_rate=1000, frames=[0.0, 1.0, -1.0, 0.5])

            analysis = audio_discontinuities.build_analysis(wav, top_count=2)

            self.assertEqual(analysis["analysis"]["pcm16_clipping_count"], 2)

    def test_works_without_diagnostics_json(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            wav = Path(tmpdir) / "no-diagnostics.wav"
            write_pcm16_wav(wav, sample_rate=1000, frames=[0.0] * 4 + [0.9])

            analysis = audio_discontinuities.build_analysis(wav, top_count=1)
            jump = analysis["top_adjacent_sample_jumps"][0]

            self.assertFalse(analysis["diagnostics_correlation"]["diagnostics_provided"])
            self.assertEqual(jump["nearby_events"], [])
            self.assertEqual(jump["nearby_event_categories"], [])

    def test_correlates_jump_near_synthetic_gain_pan_update_event(self):
        analysis = self.analysis_with_diagnostics("gain_pan_update")
        jump = analysis["top_adjacent_sample_jumps"][0]

        self.assertIn("gain_pan_update", jump["nearby_event_categories"])
        self.assertIn("gain_pan_update", self.category_names(analysis))

    def test_correlates_jump_near_synthetic_ecx_cut_event(self):
        analysis = self.analysis_with_diagnostics("ecx_note_cut")
        jump = analysis["top_adjacent_sample_jumps"][0]

        self.assertIn("ecx_note_cut", jump["nearby_event_categories"])
        self.assertIn("ecx_note_cut", self.category_names(analysis))

    def test_correlates_jump_near_synthetic_e9x_retrigger_event(self):
        analysis = self.analysis_with_diagnostics("e9x_retrigger")
        jump = analysis["top_adjacent_sample_jumps"][0]

        self.assertIn("e9x_retrigger", jump["nearby_event_categories"])
        self.assertIn("e9x_retrigger", self.category_names(analysis))

    def test_correlates_jump_near_synthetic_window_boundary(self):
        analysis = self.analysis_with_diagnostics("window_boundary")
        jump = analysis["top_adjacent_sample_jumps"][0]

        self.assertIn("window_boundary", jump["nearby_event_categories"])
        self.assertIn("carried_voice_boundary", jump["nearby_event_categories"])

    def test_missing_wav_path_cli_returns_clear_error(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = subprocess.run(
                [
                    sys.executable,
                    str(DISCONTINUITY_SCRIPT_PATH),
                    "--wav",
                    str(Path(tmpdir) / "missing.wav"),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("analyze-audio-discontinuities:", result.stderr)
            self.assertIn("missing WAV", result.stderr)

    def test_malformed_diagnostics_json_cli_returns_clear_error(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            wav = tmpdir_path / "candidate.wav"
            diagnostics = tmpdir_path / "bad-diagnostics.json"
            write_pcm16_wav(wav, sample_rate=1000, frames=[0.0, 0.8])
            diagnostics.write_text("{not json", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(DISCONTINUITY_SCRIPT_PATH),
                    "--wav",
                    str(wav),
                    "--diagnostics-json",
                    str(diagnostics),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("malformed diagnostics JSON", result.stderr)

    def test_json_output_is_valid_and_deterministic(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            wav = tmpdir_path / "candidate.wav"
            json_report = tmpdir_path / "clicks.json"
            write_pcm16_wav(wav, sample_rate=1000, frames=[0.0] * 4 + [0.9])

            result = subprocess.run(
                [
                    sys.executable,
                    str(DISCONTINUITY_SCRIPT_PATH),
                    "--wav",
                    str(wav),
                    "--json",
                    str(json_report),
                    "--top",
                    "3",
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            raw_json = json_report.read_text(encoding="utf-8")
            parsed = json.loads(raw_json)
            self.assertEqual(parsed["schema_version"], 1)
            self.assertEqual(parsed["wav"]["path_name"], "candidate.wav")
            self.assertNotIn(tmpdir, raw_json)
            self.assertEqual(raw_json, json.dumps(parsed, indent=2, sort_keys=True) + "\n")

    def test_markdown_output_contains_expected_sections(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            wav = tmpdir_path / "candidate.wav"
            markdown_report = tmpdir_path / "clicks.md"
            write_pcm16_wav(wav, sample_rate=1000, frames=[0.0] * 4 + [0.9])

            result = subprocess.run(
                [
                    sys.executable,
                    str(DISCONTINUITY_SCRIPT_PATH),
                    "--wav",
                    str(wav),
                    "--markdown",
                    str(markdown_report),
                    "--top",
                    "3",
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            markdown = markdown_report.read_text(encoding="utf-8")
            self.assertIn("# Audio Discontinuity Report", markdown)
            self.assertIn("## Overall Clipping And Headroom Recap", markdown)
            self.assertIn("## Top Adjacent-Sample Jumps", markdown)
            self.assertIn("## Likely Nearby Event Categories", markdown)
            self.assertIn("Diagnostic evidence only", markdown)

    def analysis_with_diagnostics(self, category):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            wav = tmpdir_path / "candidate.wav"
            diagnostics_path = tmpdir_path / "diagnostics.json"
            write_pcm16_wav(wav, sample_rate=1000, frames=[0.0] * 10 + [0.9] + [0.9] * 4)
            diagnostics_path.write_text(
                json.dumps(synthetic_discontinuity_diagnostics(category, frame=10)),
                encoding="utf-8",
            )
            return audio_discontinuities.build_analysis(
                wav,
                diagnostics_path,
                top_count=3,
                threshold_pcm16=12000,
                correlation_frames=2,
            )

    def category_names(self, analysis):
        return {
            item["category"]
            for item in analysis["diagnostics_correlation"]["summary_by_category"]
        }


class AudioCompareTests(unittest.TestCase):
    def test_identical_stereo_files_report_zero_difference(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            frames = sine_frames(channels=2)
            write_pcm16_wav(reference, channels=2, frames=frames)
            write_pcm16_wav(candidate, channels=2, frames=frames)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            sample_comparison = comparison["sample_comparison"]

            self.assertTrue(comparison["format"]["sample_comparison_available"])
            self.assertEqual(sample_comparison["diff"]["overall_rms_difference"], 0.0)
            self.assertEqual(sample_comparison["diff"]["max_abs_sample_difference"], 0.0)
            self.assertEqual(sample_comparison["diff"]["per_channel_rms_difference"], [0.0, 0.0])
            self.assertEqual(sample_comparison["normalized_correlation"], 1.0)
            self.assertIsNone(sample_comparison["first_difference_seconds"])

    def test_amplitude_mismatch_reports_rms_and_max_difference(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, frames=sine_frames(amplitude=0.5))
            write_pcm16_wav(candidate, frames=sine_frames(amplitude=0.25))

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            diff = comparison["sample_comparison"]["diff"]

            self.assertGreater(diff["overall_rms_difference"], 0.17)
            self.assertGreater(diff["max_abs_sample_difference"], 0.24)
            self.assertGreater(diff["normalized_rms_difference"], 0.49)

    def test_localized_mismatch_appears_in_worst_window_output(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            reference_frames = [0.0] * 100
            candidate_frames = [0.0] * 100
            for index in range(50, 60):
                candidate_frames[index] = 0.8
            write_pcm16_wav(reference, sample_rate=1000, frames=reference_frames)
            write_pcm16_wav(candidate, sample_rate=1000, frames=candidate_frames)

            comparison = audio_compare.build_comparison(
                reference,
                candidate,
                seconds=1.0,
                window_ms=10.0,
                top_windows=3,
            )
            windows = comparison["sample_comparison"]["worst_windows"]

            self.assertEqual(windows[0]["start_frame"], 50)
            self.assertEqual(windows[0]["end_frame"], 60)
            self.assertGreater(windows[0]["rms_difference"], 0.79)

    def test_left_right_stereo_balance_mismatch_is_reported(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            reference_frames = [(0.4, 0.4)] * 32
            candidate_frames = [(0.8, 0.1)] * 32
            write_pcm16_wav(reference, channels=2, frames=reference_frames)
            write_pcm16_wav(candidate, channels=2, frames=candidate_frames)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            balance = comparison["candidate"]["stats"]["stereo_balance"]

            self.assertGreater(balance["left_minus_right_rms"], 0.69)
            self.assertGreater(balance["left_right_energy_difference"], 0.62)

    def test_duration_and_frame_count_mismatch_are_reported(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, sample_rate=1000, frames=[0.0] * 100)
            write_pcm16_wav(candidate, sample_rate=1000, frames=[0.0] * 125)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)

            self.assertEqual(comparison["format"]["frame_count_delta"], 25)
            self.assertEqual(comparison["format"]["analyzed_frame_count_delta"], 25)
            self.assertAlmostEqual(comparison["format"]["duration_delta_seconds"], 0.025)

    def test_sample_rate_mismatch_is_reported_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, sample_rate=8000)
            write_pcm16_wav(candidate, sample_rate=11025)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            report = audio_compare.build_markdown_report(comparison)

            self.assertFalse(comparison["format"]["sample_rate_matches"])
            self.assertIsNone(comparison["sample_comparison"])
            self.assertIn("Sample rate: mismatch (reference 8000 Hz, candidate 11025 Hz)", report)
            self.assertIn("Skipped because sample rate or channel count differs.", report)

    def test_channel_count_mismatch_is_reported_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, channels=1)
            write_pcm16_wav(candidate, channels=2)

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)
            report = audio_compare.build_markdown_report(comparison)

            self.assertFalse(comparison["format"]["channel_count_matches"])
            self.assertIsNone(comparison["sample_comparison"])
            self.assertIn("Channels: mismatch (reference 1, candidate 2)", report)

    def test_clipping_count_is_detected(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, frames=[0.0, 1.0, -1.0, 0.5])
            write_pcm16_wav(candidate, frames=[0.0, 0.5, 0.25, 0.125])

            comparison = audio_compare.build_comparison(reference, candidate, seconds=1.0)

            self.assertEqual(comparison["reference"]["stats"]["clipping_count"], 2)
            self.assertEqual(comparison["candidate"]["stats"]["clipping_count"], 0)

    def test_silence_and_near_silence_are_reported(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, frames=[0.0, 0.0, 0.0, 0.0])
            write_pcm16_wav(candidate, frames=[0.0, 0.00001, 0.25, -0.25])

            comparison = audio_compare.build_comparison(
                reference,
                candidate,
                seconds=1.0,
                near_silence_threshold=0.00002,
            )

            self.assertEqual(comparison["reference"]["stats"]["near_silence_count"], 4)
            self.assertEqual(comparison["reference"]["stats"]["near_silence_ratio"], 1.0)
            self.assertEqual(comparison["candidate"]["stats"]["near_silence_count"], 2)

    def test_json_output_is_valid_deterministic_and_sanitizes_paths(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            reference = tmpdir_path / "reference.wav"
            candidate = tmpdir_path / "candidate.wav"
            json_report = tmpdir_path / "report.json"
            frames = sine_frames(seconds=0.05)
            write_pcm16_wav(reference, frames=frames)
            write_pcm16_wav(candidate, frames=frames)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--seconds",
                    "1",
                    "--json",
                    str(json_report),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            raw_json = json_report.read_text(encoding="utf-8")
            parsed = json.loads(raw_json)
            self.assertEqual(parsed["schema_version"], 1)
            self.assertEqual(parsed["reference"]["info"]["path_name"], "reference.wav")
            self.assertEqual(parsed["candidate"]["info"]["path_name"], "candidate.wav")
            self.assertNotIn(tmpdir, raw_json)
            self.assertEqual(raw_json, json.dumps(parsed, indent=2, sort_keys=True) + "\n")

    def test_markdown_cli_output_is_understandable(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(reference, frames=[0.0, 0.0, 0.0, 0.0])
            write_pcm16_wav(candidate, frames=[0.0, 0.5, 0.0, 0.0])

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--seconds",
                    "1",
                    "--window-ms",
                    "1",
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("# Audio Comparison Report", result.stdout)
            self.assertIn("## Worst Mismatch Windows", result.stdout)
            self.assertIn("Diagnostic metrics only", result.stdout)

    def test_missing_file_cli_returns_clear_error(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "missing-reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(candidate)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("audio-compare:", result.stderr)
            self.assertIn("missing-reference.wav", result.stderr)

    def test_invalid_file_cli_returns_clear_error(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            reference.write_text("not a wav", encoding="utf-8")
            write_pcm16_wav(candidate)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("audio-compare:", result.stderr)

    def test_local_reference_smoke_wrapper_writes_requested_reports(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            reference = tmpdir_path / "tiny-reference.wav"
            candidate = tmpdir_path / "tiny-candidate.wav"
            json_report = tmpdir_path / "tiny-audio-compare.json"
            markdown_report = tmpdir_path / "tiny-audio-compare.md"
            frames = sine_frames(seconds=0.05)
            write_pcm16_wav(reference, frames=frames)
            write_pcm16_wav(candidate, frames=frames)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SMOKE_SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--json",
                    str(json_report),
                    "--markdown",
                    str(markdown_report),
                    "--label",
                    "tiny smoke",
                    "--metadata",
                    "order 0 row 0",
                    "--seconds",
                    "1",
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json_report.exists())
            self.assertTrue(markdown_report.exists())
            parsed = json.loads(json_report.read_text(encoding="utf-8"))
            self.assertEqual(parsed["tool"], "scripts/audio-compare.py")
            self.assertIn("# Audio Comparison Report", markdown_report.read_text(encoding="utf-8"))
            self.assertIn("Delegating metric generation to scripts/audio-compare.py", result.stdout)
            self.assertIn("local artifacts and must not be committed", result.stdout)

    def test_local_reference_smoke_wrapper_default_outputs_are_under_tmp(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            reference = tmpdir_path / "reference.wav"
            candidate = tmpdir_path / "candidate.wav"
            output_dir = Path("/tmp/vtx-local-reference-comparison")
            expected_json = output_dir / "unittest-default-audio-compare.json"
            expected_markdown = output_dir / "unittest-default-audio-compare.md"
            expected_json.unlink(missing_ok=True)
            expected_markdown.unlink(missing_ok=True)
            write_pcm16_wav(reference)
            write_pcm16_wav(candidate)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SMOKE_SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--label",
                    "unittest default",
                    "--seconds",
                    "1",
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(expected_json.exists())
            self.assertTrue(expected_markdown.exists())
            self.assertIn(str(expected_json), result.stdout)
            self.assertIn(str(expected_markdown), result.stdout)
            expected_json.unlink(missing_ok=True)
            expected_markdown.unlink(missing_ok=True)

    def test_local_reference_smoke_wrapper_missing_candidate_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "reference.wav"
            candidate = Path(tmpdir) / "missing-candidate.wav"
            write_pcm16_wav(reference)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SMOKE_SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--json",
                    str(Path(tmpdir) / "report.json"),
                    "--markdown",
                    str(Path(tmpdir) / "report.md"),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing candidate WAV", result.stderr)
            self.assertIn("missing-candidate.wav", result.stderr)

    def test_local_reference_smoke_wrapper_missing_reference_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            reference = Path(tmpdir) / "missing-reference.wav"
            candidate = Path(tmpdir) / "candidate.wav"
            write_pcm16_wav(candidate)

            result = subprocess.run(
                [
                    sys.executable,
                    str(SMOKE_SCRIPT_PATH),
                    "--reference",
                    str(reference),
                    "--candidate",
                    str(candidate),
                    "--json",
                    str(Path(tmpdir) / "report.json"),
                    "--markdown",
                    str(Path(tmpdir) / "report.md"),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing reference WAV", result.stderr)
            self.assertIn("missing-reference.wav", result.stderr)


class AudioCorrelationTests(unittest.TestCase):
    def test_correlation_maps_synthetic_window_to_overlapping_adapter_event(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("Window 1: 0.100000-0.150000 s", markdown)
            self.assertIn("order 0 pattern 2 row 4", markdown)
            self.assertIn("| order 0 pattern 2 row 4 | 1 | 49 | 7/2 | sample_map; mapped 2; valid True; map True | 110-145 |", markdown)

    def test_correlation_includes_rich_adapter_diagnostic_fields(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, label="synthetic rich fields", metadata="order 0 rows 4-5")
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("- Label: synthetic rich fields", markdown)
            self.assertIn("- Metadata: order 0 rows 4-5", markdown)
            self.assertIn("1.25000000", markdown)
            self.assertIn("period 4608.0000", markdown)
            self.assertIn("freq 8363.0000", markdown)
            self.assertIn("0.50000000/-0.25000000", markdown)
            self.assertIn("raw 48 setVolume(32) / supported", markdown)
            self.assertIn("9xx applied offset 512", markdown)
            self.assertIn("speed F03 6/125->3/125", markdown)
            self.assertIn("mapped 2/2; deferred loop", markdown)
            self.assertIn("| forward |", markdown)

    def test_correlation_includes_event_coverage_summary_when_present(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("## Event Coverage", markdown)
            self.assertIn("- Normal note cells: 3", markdown)
            self.assertIn("- Scheduled note events: 1", markdown)
            self.assertIn("- Skipped note events: 2", markdown)
            self.assertIn("- Sample-map selection events: 1", markdown)
            self.assertIn("- First-playable-sample fallback events: 0", markdown)
            self.assertIn("- Fallback-after-invalid-map events: 0", markdown)
            self.assertIn("- Skipped-no-valid-sample events: 0", markdown)
            self.assertIn("- Top skip reasons: missing_instrument=1, sample_pcm_empty=1", markdown)
            self.assertIn("- C mixer scheduling: 1/1 accepted, 0 rejected, scheduled capacity 256, active capacity 256", markdown)
            self.assertIn("reason missing_instrument", markdown)

    def test_correlation_markdown_includes_traversal_hazard_section(self):
        effects = [
            traversal_effect(0x0B, 0x02, "Bxx position jump", channel=1),
            traversal_effect(0x0D, 0x10, "Dxx pattern break", channel=2),
            traversal_effect(0x0E, 0xE2, "EEx pattern delay", channel=3),
            traversal_effect(0x0F, 0x06, "Fxx speed/BPM", channel=4, status="applied"),
            traversal_effect(0x0E, 0x94, "E9x retrigger", channel=5, status="applied"),
        ]
        diagnostics = synthetic_diagnostics_json()
        diagnostics["pattern_traversal_timing_effects"] = effects
        diagnostics["traversal_hazard_summary"] = traversal_summary(effects)

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("## Pattern Traversal / Timing Hazards", markdown)
            self.assertIn("- Bxx position jumps: 1", markdown)
            self.assertIn("- Dxx pattern breaks: 1", markdown)
            self.assertIn("- EEx pattern delays: 1", markdown)
            self.assertIn("- Fxx speed/BPM timing changes: 1", markdown)
            self.assertIn("- E9x retriggers: 1", markdown)
            self.assertIn("- Other E-command diagnostics: 0", markdown)
            self.assertIn("| Bxx position jump | deferred/unsupported | order 0 pattern 2 row 4 | 1 | 2 | 1 overlaps |", markdown)

    def test_recommendation_heuristic_suggests_traversal_when_hazards_dominate(self):
        effects = [
            traversal_effect(0x0B, 0x02, "Bxx position jump", channel=1),
            traversal_effect(0x0D, 0x10, "Dxx pattern break", channel=2),
        ]
        diagnostics = synthetic_diagnostics_json()
        diagnostics["deferred_fields"] = [
            deferred_effect_field(0x0B, 0x02, channel=1),
            deferred_effect_field(0x0D, 0x10, channel=2),
        ]
        diagnostics["pattern_traversal_timing_effects"] = effects
        diagnostics["traversal_hazard_summary"] = traversal_summary(effects)

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn(
                "Recommended next PR: Minimal Pattern Break Dxx / Position Jump Bxx for Bounded Offline Traversal",
                markdown,
            )

    def test_recommendation_heuristic_does_not_suggest_traversal_without_hazards(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("Recommended next PR: No clear single target", markdown)
            self.assertNotIn("Recommended next PR: Minimal Pattern Break Dxx / Position Jump Bxx", markdown)

    def test_correlation_markdown_includes_pitch_modulation_section(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["deferred_fields"] = [
            deferred_effect_field(0x00, 0x37, channel=1),
            deferred_effect_field(0x04, 0x48, channel=2),
        ]
        diagnostics["volume_column_mappings"].append(deferred_volume_mapping(0xB4, "vibrato", channel=3))

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("## Pitch Modulation / Deferred Effect Diagnostics", markdown)
            self.assertIn("- Arpeggio: 1 overall, 1 near top mismatch windows", markdown)
            self.assertIn("- Vibrato: 2 overall, 2 near top mismatch windows", markdown)
            self.assertIn("| 0xy arpeggio | deferred/unsupported | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)
            self.assertIn("| vibrato | deferred/unsupported | 1 | 1 | order 0 pattern 2 row 4 ch 3 |", markdown)
            self.assertIn("### First dominant deferred pitch-modulation coordinates", markdown)

    def test_correlation_report_counts_applied_3xx_tone_portamento(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["pattern_traversal_timing_effects"] = [
            traversal_effect(0x03, 0x40, "3xx tone portamento", status="applied")
        ]
        diagnostics["tone_portamento_effects"] = [
            {
                "source": {"order": 0, "pattern": 2, "row": 4},
                "channel_index": 1,
                "synthetic_row": 4,
                "synthetic_tick": 0,
                "effect_type": 0x03,
                "effect_param": 0x40,
                "status": "applied",
                "current_status": "applied",
                "detected": True,
                "applied": True,
                "deferred": False,
                "ignored_as_no_op": False,
                "active_voice_found": True,
                "target_note": 61,
                "target_step": 2.0,
                "current_step_before": 1.0,
                "current_step_after": 1.25,
                "portamento_speed": 0x40,
                "step_updates": [{"scheduled_frame": 110, "current_step_before": 1.0, "current_step_after": 1.25}],
            }
        ]
        diagnostics["traversal_hazard_summary"] = traversal_summary(diagnostics["pattern_traversal_timing_effects"])

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("### Applied effect commands in worst windows", markdown)
            self.assertIn("| 3xx tone portamento | applied | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)
            self.assertIn("### Overall command frequency in bounded render", markdown)

    def test_correlation_report_counts_applied_1xx_2xx_portamento_slides(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["pattern_traversal_timing_effects"] = [
            traversal_effect(0x01, 0x40, "1xx portamento up", status="applied"),
            traversal_effect(0x02, 0x20, "2xx portamento down", row=5, channel=2, status="applied"),
        ]
        diagnostics["portamento_slide_effects"] = [
            {
                "source": {"order": 0, "pattern": 2, "row": 4},
                "channel_index": 1,
                "synthetic_row": 4,
                "synthetic_tick": 0,
                "effect_type": 0x01,
                "effect_param": 0x40,
                "status": "applied",
                "current_status": "applied",
                "detected": True,
                "applied": True,
                "deferred": False,
                "ignored_as_no_op": False,
                "active_voice_found": True,
                "slide_direction": "up",
                "slide_amount": 0x40,
                "current_step_before": 1.0,
                "current_step_after": 1.25,
                "row_speed": 4,
                "row_bpm": 250,
                "step_updates": [{"scheduled_frame": 110, "current_step_before": 1.0, "current_step_after": 1.25}],
            },
            {
                "source": {"order": 0, "pattern": 2, "row": 5},
                "channel_index": 2,
                "synthetic_row": 5,
                "synthetic_tick": 0,
                "effect_type": 0x02,
                "effect_param": 0x20,
                "status": "applied",
                "current_status": "applied",
                "detected": True,
                "applied": True,
                "deferred": False,
                "ignored_as_no_op": False,
                "active_voice_found": True,
                "slide_direction": "down",
                "slide_amount": 0x20,
                "current_step_before": 1.25,
                "current_step_after": 1.1,
                "row_speed": 4,
                "row_bpm": 250,
                "step_updates": [{"scheduled_frame": 115, "current_step_before": 1.25, "current_step_after": 1.1}],
            },
        ]
        diagnostics["traversal_hazard_summary"] = traversal_summary(diagnostics["pattern_traversal_timing_effects"])

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("| 1xx portamento up | applied | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)
            self.assertIn("| 2xx portamento down | applied | 1 | 1 | order 0 pattern 2 row 5 ch 2 |", markdown)

    def test_recommendation_heuristic_selects_dominant_pitch_bucket(self):
        cases = [
            (
                "arpeggio",
                [deferred_effect_field(0x00, 0x37, channel=1),
                 deferred_effect_field(0x00, 0x47, channel=2),
                 deferred_effect_field(0x00, 0x57, channel=3)],
                [],
                "Minimal Arpeggio 0xy for Bounded Offline Renders",
                "- Arpeggio: 3 overall, 3 near top mismatch windows",
            ),
            (
                "portamento",
                [deferred_effect_field(0x01, 0x08, channel=1),
                 deferred_effect_field(0x02, 0x09, channel=2),
                 deferred_effect_field(0x03, 0x10, channel=3),
                 deferred_effect_field(0x05, 0x20, channel=4)],
                [deferred_volume_mapping(0xF4, "tonePortamento", channel=5)],
                "Minimal Portamento Foundation",
                "- Portamento: 5 overall, 5 near top mismatch windows",
            ),
            (
                "vibrato",
                [deferred_effect_field(0x04, 0x48, channel=1),
                 deferred_effect_field(0x06, 0x30, channel=2)],
                [deferred_volume_mapping(0xA4, "setVibratoSpeed", channel=3),
                 deferred_volume_mapping(0xB5, "vibrato", channel=4)],
                "Minimal Vibrato Foundation",
                "- Vibrato: 4 overall, 4 near top mismatch windows",
            ),
            (
                "tremolo",
                [deferred_effect_field(0x07, 0x48, channel=1),
                 deferred_effect_field(0x07, 0x58, channel=2),
                 deferred_effect_field(0x07, 0x68, channel=3)],
                [],
                "Minimal Tremolo 7xy",
                "- Tremolo: 3 overall, 3 near top mismatch windows",
            ),
        ]

        for name, fields, volume_mappings, recommendation, count_line in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmpdir:
                diagnostics = synthetic_diagnostics_json()
                diagnostics["deferred_fields"] = fields
                diagnostics["volume_column_mappings"].extend(volume_mappings)
                report = self.run_correlation(tmpdir, diagnostics=diagnostics)
                markdown = report.read_text(encoding="utf-8")

                self.assertIn(f"Recommended next pitch-effect PR: {recommendation}", markdown)
                self.assertIn(f"Recommended next PR: {recommendation}", markdown)
                self.assertIn(count_line, markdown)

    def test_recommendation_heuristic_reports_no_clear_pitch_target_when_counts_are_sparse(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["deferred_fields"] = [deferred_effect_field(0x00, 0x37, channel=1)]

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("Recommended next pitch-effect PR: No clear pitch-effect target", markdown)
            self.assertIn("Recommended next PR: No clear single target", markdown)

    def test_correlation_report_counts_deferred_ecx_note_cut_in_worst_windows(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["deferred_fields"] = [deferred_effect_field(0x0E, 0xC3)]

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("### Deferred effect commands in worst windows", markdown)
            self.assertIn("| ECx note cut | deferred/unsupported | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)

    def test_correlation_report_counts_deferred_edx_note_delay_in_worst_windows(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["deferred_fields"] = [deferred_effect_field(0x0E, 0xD2)]

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("| EDx note delay | deferred/unsupported | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)

    def test_correlation_report_counts_applied_ecx_edx_from_supported_diagnostics(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["note_cut_effects"] = [note_cut_effect(channel=1, scheduled_frame=112)]
        diagnostics["note_delay_effects"] = [note_delay_effect(channel=2, delayed_frame=113)]
        diagnostics["pattern_traversal_timing_effects"] = [
            traversal_effect(0x0E, 0xC2, "ECx note cut", channel=1, status="applied"),
            traversal_effect(0x0E, 0xD2, "EDx note delay", channel=2, status="applied"),
        ]
        diagnostics["traversal_hazard_summary"] = traversal_summary(diagnostics["pattern_traversal_timing_effects"])

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("- ECx note cuts: 1", markdown)
            self.assertIn("- EDx note delays: 1", markdown)
            self.assertIn("- Other E-command diagnostics: 0", markdown)
            self.assertIn("### Applied effect commands in worst windows", markdown)
            self.assertIn("| ECx note cut | applied | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)
            self.assertIn("| EDx note delay | applied | 1 | 1 | order 0 pattern 2 row 4 ch 2 |", markdown)

    def test_correlation_report_counts_applied_e9x_retrigger_in_worst_windows(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["retrigger_effects"] = [retrigger_effect(channel=1, frames=[112, 114])]
        diagnostics["pattern_traversal_timing_effects"] = [
            traversal_effect(0x0E, 0x92, "E9x retrigger", channel=1, status="applied"),
        ]
        diagnostics["traversal_hazard_summary"] = traversal_summary(diagnostics["pattern_traversal_timing_effects"])

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("- E9x retriggers: 1", markdown)
            self.assertIn("### Applied effect commands in worst windows", markdown)
            self.assertIn("| E9x retrigger | applied | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)

    def test_correlation_report_counts_applied_9xx_separately_from_deferred_900_no_op(self):
        diagnostics = synthetic_diagnostics_json()
        source = {"order": 0, "pattern": 2, "row": 4}
        diagnostics["sample_offset_effects"] = [
            {
                "source": source,
                "channel_index": 1,
                "synthetic_row": 4,
                "synthetic_tick": 0,
                "effect_type": 0x09,
                "effect_param": 0x02,
                "status": "applied",
                "detected": True,
                "applied": True,
                "deferred": False,
                "ignored_as_no_op": False,
                "skipped": False,
                "out_of_range": False,
                "computed_offset_frames": 512,
                "applied_offset_frames": 512,
                "selected_sample_length": 2048,
            },
            {
                "source": source,
                "channel_index": 2,
                "synthetic_row": 4,
                "synthetic_tick": 0,
                "effect_type": 0x09,
                "effect_param": 0x00,
                "status": "ignored_900_no_op",
                "detected": True,
                "applied": False,
                "deferred": True,
                "ignored_as_no_op": True,
                "skipped": False,
                "out_of_range": False,
                "computed_offset_frames": 0,
                "applied_offset_frames": 0,
                "selected_sample_length": 2048,
            },
        ]
        diagnostics["deferred_fields"] = [deferred_effect_field(0x09, 0x00, channel=2)]

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("| 9xx sample offset | applied | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)
            self.assertIn(
                "| 900 sample offset / effect memory | deferred/no-op | 1 | 1 | order 0 pattern 2 row 4 ch 2 |",
                markdown,
            )

    def test_correlation_report_counts_supported_volume_columns_separately_from_deferred(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["volume_column_mappings"].append(deferred_volume_mapping(0xB4, "vibrato", channel=2))

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("### Applied volume-column commands in worst windows", markdown)
            self.assertIn("| set volume | applied | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)
            self.assertIn("### Deferred volume-column commands in worst windows", markdown)
            self.assertIn("| vibrato | deferred/unsupported | 1 | 1 | order 0 pattern 2 row 4 ch 2 |", markdown)

    def test_correlation_report_counts_volume_pan_state_updates(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["volume_panning_state_updates"] = [
            volume_pan_state_update(
                "volume_column",
                "setVolume",
                "setVolume",
                raw_volume_column=0x30,
                channel=1,
            ),
            volume_pan_state_update(
                "volume_column",
                "setPanning",
                "setPanning",
                raw_volume_column=0xCC,
                channel=2,
            ),
            volume_pan_state_update(
                "effect_column",
                "cxxSetVolume",
                "Cxx set volume",
                effect_type=0x0C,
                effect_param=0x20,
                channel=3,
            ),
            volume_pan_state_update(
                "effect_column",
                "effect8xxSetPanning",
                "8xx set panning",
                effect_type=0x08,
                effect_param=0xFF,
                channel=4,
            ),
            volume_pan_state_update(
                "effect_column",
                "axyVolumeSlide",
                "Axy volume slide",
                effect_type=0x0A,
                effect_param=0x04,
                channel=5,
            ),
            volume_pan_state_update(
                "effect_column",
                "hxyGlobalVolumeSlide",
                "Hxy global volume slide",
                status="applied",
                effect_type=0x11,
                effect_param=0x10,
                channel=6,
            ),
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("| empty-note volume-column set volume state update | applied | 1 | 1 | order 0 pattern 2 row 4 ch 1 |", markdown)
            self.assertIn("| empty-note volume-column set panning state update | applied | 1 | 1 | order 0 pattern 2 row 4 ch 2 |", markdown)
            self.assertIn("| Cxx set volume | applied | 1 | 1 | order 0 pattern 2 row 4 ch 3 |", markdown)
            self.assertIn("| 8xx set panning | applied | 1 | 1 | order 0 pattern 2 row 4 ch 4 |", markdown)
            self.assertIn("| Axy volume slide | applied | 1 | 1 | order 0 pattern 2 row 4 ch 5 |", markdown)
            self.assertIn("| Hxy global volume slide | applied | 1 | 1 | order 0 pattern 2 row 4 ch 6 |", markdown)

    def test_correlation_report_includes_source_coordinates_for_top_deferred_commands(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["deferred_fields"] = [deferred_effect_field(0x0E, 0xC3, channel=3)]

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("order 0 pattern 2 row 4 ch 3", markdown)

    def test_recommendation_heuristic_suggests_ecx_edx_when_they_dominate(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["deferred_fields"] = [
            deferred_effect_field(0x0E, 0xC3, channel=1),
            deferred_effect_field(0x0E, 0xD2, channel=2),
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn(
                "Recommended next PR: Minimal Note Cut ECx / Note Delay EDx for Bounded Offline Renders",
                markdown,
            )

    def test_recommendation_heuristic_suggests_e9x_when_retrigger_dominates(self):
        diagnostics = synthetic_diagnostics_json()
        diagnostics["deferred_fields"] = [deferred_effect_field(0x0E, 0x94)]

        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics=diagnostics)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("Recommended next PR: Minimal Retrigger E9x for Bounded Offline Renders", markdown)

    def test_recommendation_heuristic_reports_no_clear_target_without_deferred_dominance(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir)
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("Recommended next PR: No clear single target", markdown)

    def test_correlation_reports_no_overlapping_events_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(
                tmpdir,
                diagnostics=synthetic_diagnostics_json(event_start=10, event_end=20),
            )
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("No candidate event frame range overlapped this mismatch window", markdown)
            self.assertIn("#### Recent Preceding Candidate Events", markdown)
            self.assertIn("| order 0 pattern 2 row 4 | 1 | 49 | 7/2 | sample_map; mapped 2; valid True; map True | 10-20 |", markdown)

    def test_correlation_missing_optional_diagnostics_fields_degrades_gracefully(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            report = self.run_correlation(tmpdir, diagnostics={})
            markdown = report.read_text(encoding="utf-8")

            self.assertIn("- Candidate diagnostic events: 0", markdown)
            self.assertIn("No row timing diagnostics overlap this mismatch window.", markdown)
            self.assertIn("No candidate event frame range overlapped this mismatch window", markdown)

    def test_correlation_missing_comparison_json_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            diagnostics_path = tmpdir_path / "diagnostics.json"
            output_path = tmpdir_path / "correlation.md"
            diagnostics_path.write_text(json.dumps(synthetic_diagnostics_json()), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(CORRELATION_SCRIPT_PATH),
                    "--comparison-json",
                    str(tmpdir_path / "missing-comparison.json"),
                    "--diagnostics-json",
                    str(diagnostics_path),
                    "--output-markdown",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing comparison JSON", result.stderr)

    def test_correlation_missing_diagnostics_json_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            comparison_path = tmpdir_path / "comparison.json"
            output_path = tmpdir_path / "correlation.md"
            comparison_path.write_text(json.dumps(synthetic_comparison_json()), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(CORRELATION_SCRIPT_PATH),
                    "--comparison-json",
                    str(comparison_path),
                    "--diagnostics-json",
                    str(tmpdir_path / "missing-diagnostics.json"),
                    "--output-markdown",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing diagnostics JSON", result.stderr)

    def test_correlation_malformed_json_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            comparison_path = tmpdir_path / "comparison.json"
            diagnostics_path = tmpdir_path / "diagnostics.json"
            output_path = tmpdir_path / "correlation.md"
            comparison_path.write_text("{not valid json", encoding="utf-8")
            diagnostics_path.write_text(json.dumps(synthetic_diagnostics_json()), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(CORRELATION_SCRIPT_PATH),
                    "--comparison-json",
                    str(comparison_path),
                    "--diagnostics-json",
                    str(diagnostics_path),
                    "--output-markdown",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("malformed JSON in comparison JSON", result.stderr)

    def test_correlation_missing_expected_comparison_fields_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            comparison_path = tmpdir_path / "comparison.json"
            diagnostics_path = tmpdir_path / "diagnostics.json"
            output_path = tmpdir_path / "correlation.md"
            comparison_path.write_text(json.dumps({"sample_comparison": None}), encoding="utf-8")
            diagnostics_path.write_text(json.dumps(synthetic_diagnostics_json()), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(CORRELATION_SCRIPT_PATH),
                    "--comparison-json",
                    str(comparison_path),
                    "--diagnostics-json",
                    str(diagnostics_path),
                    "--output-markdown",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("sample_comparison.worst_windows", result.stderr)

    def run_correlation(self, tmpdir, comparison=None, diagnostics=None, label=None, metadata=None):
        tmpdir_path = Path(tmpdir)
        comparison_path = tmpdir_path / "comparison.json"
        diagnostics_path = tmpdir_path / "diagnostics.json"
        output_path = tmpdir_path / "correlation.md"
        comparison_payload = synthetic_comparison_json() if comparison is None else comparison
        diagnostics_payload = synthetic_diagnostics_json() if diagnostics is None else diagnostics
        comparison_path.write_text(json.dumps(comparison_payload), encoding="utf-8")
        diagnostics_path.write_text(json.dumps(diagnostics_payload), encoding="utf-8")

        command = [
            sys.executable,
            str(CORRELATION_SCRIPT_PATH),
            "--comparison-json",
            str(comparison_path),
            "--diagnostics-json",
            str(diagnostics_path),
            "--output-markdown",
            str(output_path),
        ]
        if label is not None:
            command.extend(["--label", label])
        if metadata is not None:
            command.extend(["--metadata", metadata])

        result = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(output_path.exists())
        self.assertTrue(output_path.is_relative_to(tmpdir_path))
        self.assertIn("Correlation report:", result.stdout)
        return output_path


class RuntimeCMixerTraceSummaryTests(unittest.TestCase):
    def test_synthetic_trace_with_no_underruns_or_clipping_is_healthy(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            trace_path = self.write_trace(
                tmpdir,
                [
                    self.event("backend_selected", runtimeAudioBackend="c_mixer"),
                    self.event("row_transition", rowIndex=0, outputPeak=0.25),
                    self.event("note_trigger", rowIndex=0, noteTriggerEventCount=1),
                    self.event("c_mixer_add_voice", rowIndex=0, cMixerAddVoiceCount=1, activeVoiceCount=1, loadedVoiceCount=1),
                ],
            )

            summary = runtime_trace_summary.build_summary(runtime_trace_summary.load_trace(trace_path), trace_path=trace_path)

            self.assertEqual(summary["health"]["clipping_sample_count"], 0)
            self.assertEqual(summary["health"]["underrun_count"], 0)
            self.assertEqual(summary["health"]["zero_fill_count"], 0)
            self.assertEqual(summary["stops"]["add_voice_events"], 1)
            self.assertEqual(summary["stops"]["immediate_hard_stop_events"], 0)
            self.assertEqual(summary["voices"]["active_voice_range"], {"min": 0, "max": 1})
            self.assertEqual(summary["suspicious_findings"], [])

    def test_synthetic_trace_with_clipping_and_underrun_reports_health_counters(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            trace_path = self.write_trace(
                tmpdir,
                [
                    self.event(
                        "row_transition",
                        outputPeak=1.25,
                        clippingSampleCount=3,
                        clippingDetected=True,
                        underrunCount=2,
                        zeroFillCount=1,
                        failedRenderCount=1,
                    )
                ],
            )

            summary = runtime_trace_summary.build_summary(runtime_trace_summary.load_trace(trace_path), trace_path=trace_path)

            self.assertEqual(summary["health"]["peak"], 1.25)
            self.assertEqual(summary["health"]["clipping_sample_count"], 3)
            self.assertTrue(summary["health"]["clipping_detected"])
            self.assertEqual(summary["health"]["underrun_count"], 2)
            self.assertEqual(summary["health"]["zero_fill_count"], 1)
            self.assertEqual(summary["health"]["failed_render_count"], 1)
            self.assertIn("runtime clipping/overrange remains after runtime gain", summary["suspicious_findings"])
            self.assertIn("runtime render underrun, zero-fill, or failure counters are nonzero", summary["suspicious_findings"])

    def test_synthetic_trace_with_ramped_replacement_stops_reports_coverage(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            trace_path = self.write_trace(
                tmpdir,
                [
                    self.event("c_mixer_add_voice", rowIndex=0, activeVoiceCount=1, loadedVoiceCount=1),
                    self.event(
                        "c_mixer_stop_channel_ramped",
                        rowIndex=1,
                        rampedVoiceCount=2,
                        replacementRampFrames=32,
                        replacementVoicesOverlap=True,
                        reason="note_replacement_stop_channel",
                    ),
                    self.event("c_mixer_add_voice", rowIndex=1, activeVoiceCount=3, loadedVoiceCount=3),
                ],
            )

            summary = runtime_trace_summary.build_summary(runtime_trace_summary.load_trace(trace_path), trace_path=trace_path)

            self.assertEqual(summary["stops"]["ramped_replacement_stop_events"], 1)
            self.assertEqual(summary["stops"]["ramped_replacement_voice_count"], 2)
            self.assertEqual(summary["stops"]["immediate_hard_replacement_stop_events"], 0)
            self.assertEqual(summary["stops"]["ramped_replacement_covers_all_observed_replacement_stops"], "yes")

    def test_synthetic_trace_with_hard_replacement_stop_reports_follow_up(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            trace_path = self.write_trace(
                tmpdir,
                [
                    self.event(
                        "c_mixer_stop_channel",
                        rowIndex=8,
                        stoppedVoiceCount=1,
                        reason="note_replacement_stop_channel",
                    )
                ],
            )

            summary = runtime_trace_summary.build_summary(runtime_trace_summary.load_trace(trace_path), trace_path=trace_path)

            self.assertEqual(summary["stops"]["immediate_hard_stop_events"], 1)
            self.assertEqual(summary["stops"]["immediate_hard_replacement_stop_events"], 1)
            self.assertEqual(summary["stops"]["ramped_replacement_covers_all_observed_replacement_stops"], "no")
            self.assertEqual(summary["recommended_next_pr"], "Runtime C Mixer Hard Stop / Replacement Follow-Up")
            self.assertIn(
                "at least one note replacement used c_mixer_stop_channel instead of c_mixer_stop_channel_ramped",
                summary["suspicious_findings"],
            )

    def test_synthetic_trace_with_applied_and_deferred_updates_reports_categories(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            trace_path = self.write_trace(
                tmpdir,
                [
                    self.event("c_mixer_update_gain_pan_applied", updateDisposition="update_applied", updateType="gain"),
                    self.event("c_mixer_update_step_applied", effectType="03", updateDisposition="update_applied", updateType="step"),
                    self.event("c_mixer_update_stored_channel_state", updateDisposition="update_stored_channel_state", updateType="pan"),
                    self.event("c_mixer_update_suppressed_no_change", updateDisposition="update_suppressed_no_change", updateType="none"),
                    self.event(
                        "c_mixer_update_deferred_no_active_voice",
                        effectType="01",
                        updateDisposition="update_deferred_no_active_voice",
                        updateType="step",
                        reason="runtime_c_mixer_update_deferred_no_active_voice_missing_runtime_channel_state",
                    ),
                    self.event("c_mixer_update_gain_pan_applied", effectType="11", updateDisposition="update_applied", updateType="gain"),
                    self.event("channel_stop", effectType="0E", effectParam="C2", reason="note_cut"),
                    self.event("c_mixer_stop_channel", effectType="0E", effectParam="C2", reason="channel_stop"),
                    self.event("note_trigger", effectType="0E", effectParam="D2", reason="delayed_note_triggered"),
                    self.event("c_mixer_add_voice", effectType="0E", effectParam="D2"),
                    self.event("note_trigger", effectType="0E", effectParam="93", reason="retrigger_interval"),
                    self.event("c_mixer_add_voice", effectType="0E", effectParam="93"),
                ],
            )

            summary = runtime_trace_summary.build_summary(runtime_trace_summary.load_trace(trace_path), trace_path=trace_path)
            categories = {
                item["category"]: item["runtime_event_count"]
                for item in summary["runtime_vs_offline_adapter_categories"]
            }

            self.assertEqual(summary["updates"]["applied_gain_pan_update_events"], 2)
            self.assertEqual(summary["updates"]["applied_step_update_events"], 1)
            self.assertEqual(summary["updates"]["suppressed_no_change_update_events"], 1)
            self.assertEqual(summary["updates"]["stored_channel_state_update_events"], 1)
            self.assertEqual(categories["gain_pan_state_updates"], 3)
            self.assertEqual(categories["step_pitch_updates"], 2)
            self.assertEqual(categories["hxy_global_volume_updates"], 1)
            self.assertEqual(categories["ecx_note_cut"], 2)
            self.assertEqual(categories["edx_note_delay"], 2)
            self.assertEqual(categories["e9x_retrigger"], 2)
            self.assertEqual(categories["portamento_1xx_2xx_3xx_updates"], 2)
            self.assertIn(
                "update_deferred_no_active_voice:step:runtime_c_mixer_update_deferred_no_active_voice_missing_runtime_channel_state",
                summary["updates"]["remaining_deferred_update_categories"],
            )
            self.assertEqual(summary["event_stream"]["runtime_driver"], "PlaybackEngine timer/control events")
            self.assertFalse(summary["event_stream"]["offline_adapter_event_stream_observed"])

    def test_synthetic_trace_reports_event_timing_deltas(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            trace_path = self.write_trace(
                tmpdir,
                [
                    self.event(
                        "c_mixer_add_voice",
                        runtimeEventSource="offline_adapter_plan",
                        runtimeEventCategory="note_trigger",
                        plannedEventID=1,
                        plannedEventFrame=1000,
                        plannedRuntimeFrame=256,
                        runtimeApplicationFrame=512,
                        eventFrameDelta=256,
                        eventApplicationTiming="callback_start",
                        callbackIndex=4,
                        callbackStartFrame=256,
                        callbackEndFrame=512,
                    )
                ],
            )

            summary = runtime_trace_summary.build_summary(runtime_trace_summary.load_trace(trace_path), trace_path=trace_path)
            alignment = summary["sample_time_alignment"]

            self.assertEqual(alignment["max_abs_event_frame_delta"], 256)
            self.assertEqual(alignment["callback_boundary_event_count"], 1)
            self.assertEqual(alignment["largest_event_timing_deltas"][0]["event_frame_delta"], 256)
            self.assertEqual(alignment["largest_event_timing_deltas"][0]["event_application_timing"], "callback_start")
            self.assertTrue(summary["event_stream"]["offline_adapter_event_stream_observed"])
            self.assertIn("planned-vs-runtime event frame deltas observed", summary["suspicious_findings"])
            self.assertIn("events applied at callback boundaries instead of planned frames", summary["suspicious_findings"])
            self.assertEqual(summary["recommended_next_pr"], "Runtime C Mixer Sample-Time Event Scheduling Bridge")

    def test_synthetic_trace_reports_same_frame_event_bursts(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            events = [
                self.event(
                    "c_mixer_add_voice",
                    rowIndex=index,
                    runtimeEventCategory="note_trigger",
                    runtimeApplicationFrame=4096,
                )
                for index in range(3)
            ]
            events.extend([
                self.event(
                    "c_mixer_update_gain_pan_applied",
                    rowIndex=1,
                    runtimeEventCategory="gain_pan_update",
                    runtimeApplicationFrame=4096,
                ),
                self.event(
                    "c_mixer_update_step_applied",
                    rowIndex=1,
                    runtimeEventCategory="step_pitch_update",
                    runtimeApplicationFrame=4096,
                ),
            ])
            trace_path = self.write_trace(tmpdir, events)

            summary = runtime_trace_summary.build_summary(runtime_trace_summary.load_trace(trace_path), trace_path=trace_path)
            burst = summary["sample_time_alignment"]["same_frame_event_bursts"][0]

            self.assertEqual(burst["runtime_application_frame"], 4096)
            self.assertEqual(burst["event_count"], 5)
            self.assertEqual(burst["actions"]["c_mixer_add_voice"], 3)
            self.assertEqual(burst["categories"]["note_trigger"], 3)

    def test_synthetic_trace_reports_order_row_transition_event_bursts_deterministically(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            trace_path = self.write_trace(
                tmpdir,
                [
                    self.event(
                        "row_transition",
                        orderIndex=7,
                        patternIndex=9,
                        rowIndex=0,
                        tickInRow=0,
                        runtimeEventCategory="row_transition",
                        plannedRuntimeFrame=8192,
                        runtimeApplicationFrame=8192,
                        eventFrameDelta=0,
                    ),
                    self.event("c_mixer_stop_channel_ramped", orderIndex=7, patternIndex=9, rowIndex=0, tickInRow=0),
                    self.event("c_mixer_add_voice", orderIndex=7, patternIndex=9, rowIndex=0, tickInRow=0),
                    self.event("c_mixer_update_gain_pan_applied", orderIndex=7, patternIndex=9, rowIndex=0, tickInRow=0),
                    self.event(
                        "row_transition_after_events",
                        orderIndex=7,
                        patternIndex=9,
                        rowIndex=0,
                        tickInRow=0,
                        transitionRuntimeFrame=8192,
                        plannedRuntimeFrame=8192,
                        eventFrameDelta=0,
                        activeVoiceCountBefore=2,
                        activeVoiceCountAfter=3,
                        loadedVoiceCountBefore=2,
                        loadedVoiceCountAfter=3,
                        transitionReplacementRampCount=1,
                        transitionUpdateCount=1,
                    ),
                ],
            )

            summary_a = runtime_trace_summary.build_summary(runtime_trace_summary.load_trace(trace_path), trace_path=trace_path)
            summary_b = runtime_trace_summary.build_summary(runtime_trace_summary.load_trace(trace_path), trace_path=trace_path)
            burst = summary_a["sample_time_alignment"]["order_row_transition_event_bursts"][0]

            self.assertEqual(summary_a, summary_b)
            self.assertEqual(burst["order_index"], 7)
            self.assertEqual(burst["row_index"], 0)
            self.assertEqual(burst["event_count"], 3)
            self.assertEqual(burst["replacement_ramp_count"], 1)
            self.assertEqual(burst["update_count"], 1)
            self.assertEqual(burst["active_voice_count_before"], 2)
            self.assertEqual(burst["active_voice_count_after"], 3)
            self.assertIn("transition_burst", summary_a["sample_time_alignment"]["top_suspicious_positions"][0]["reasons"])

    def test_synthetic_trace_json_and_markdown_outputs_are_deterministic(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir_path = Path(tmpdir)
            trace_path = self.write_trace(
                tmpdir,
                [
                    self.event("row_transition", orderIndex=0, patternIndex=2, rowIndex=0, tickInRow=0),
                    self.event("c_mixer_add_voice", orderIndex=0, patternIndex=2, rowIndex=0, tickInRow=0),
                ],
            )
            json_a = tmpdir_path / "summary-a.json"
            json_b = tmpdir_path / "summary-b.json"
            markdown_a = tmpdir_path / "summary-a.md"
            markdown_b = tmpdir_path / "summary-b.md"

            for json_path, markdown_path in ((json_a, markdown_a), (json_b, markdown_b)):
                result = subprocess.run(
                    [
                        sys.executable,
                        str(RUNTIME_TRACE_SUMMARY_SCRIPT_PATH),
                        str(trace_path),
                        "--json",
                        str(json_path),
                        "--markdown",
                        str(markdown_path),
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

            self.assertEqual(json_a.read_text(encoding="utf-8"), json_b.read_text(encoding="utf-8"))
            self.assertEqual(markdown_a.read_text(encoding="utf-8"), markdown_b.read_text(encoding="utf-8"))
            self.assertIn("Runtime C Mixer Trace Summary", markdown_a.read_text(encoding="utf-8"))

    def test_malformed_runtime_trace_fails_clearly(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            trace_path = Path(tmpdir) / "bad-runtime-trace.jsonl"
            trace_path.write_text("{not json\n", encoding="utf-8")

            result = subprocess.run(
                [sys.executable, str(RUNTIME_TRACE_SUMMARY_SCRIPT_PATH), str(trace_path)],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 2)
            self.assertIn("malformed runtime C mixer trace", result.stderr)
            self.assertIn("line 1", result.stderr)

    def test_runtime_trace_summary_tests_clean_up_temp_files(self):
        temp_directory = tempfile.TemporaryDirectory()
        tmpdir_path = Path(temp_directory.name)
        trace_path = self.write_trace(tmpdir_path, [self.event("row_transition")])

        self.assertTrue(trace_path.exists())
        temp_directory.cleanup()
        self.assertFalse(tmpdir_path.exists())

    def event(self, action, **overrides):
        event = {
            "schemaVersion": 1,
            "runtimeAction": action,
            "runtimeAudioBackend": "c_mixer",
            "experimentalCMixerEnabled": True,
            "orderIndex": overrides.pop("orderIndex", 0),
            "patternIndex": overrides.pop("patternIndex", 2),
            "rowIndex": overrides.pop("rowIndex", 0),
            "tickInRow": overrides.pop("tickInRow", 0),
            "channelIndex": overrides.pop("channelIndex", 0),
            "activeVoiceCount": overrides.pop("activeVoiceCount", 0),
            "loadedVoiceCount": overrides.pop("loadedVoiceCount", 0),
            "outputPeak": overrides.pop("outputPeak", 0),
            "clippingSampleCount": overrides.pop("clippingSampleCount", 0),
            "underrunCount": overrides.pop("underrunCount", 0),
            "zeroFillCount": overrides.pop("zeroFillCount", 0),
            "failedRenderCount": overrides.pop("failedRenderCount", 0),
        }
        event.update(overrides)
        return event

    def write_trace(self, tmpdir, events):
        path = Path(tmpdir) / "runtime-trace.jsonl"
        path.write_text("".join(json.dumps(event, sort_keys=True) + "\n" for event in events), encoding="utf-8")
        return path


if __name__ == "__main__":
    unittest.main()
