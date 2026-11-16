import copy
import json
import struct
import tempfile
import unittest
import wave
from pathlib import Path

from tools.vtx_diag import runtime_loop_trace, runtime_trace_correlate_window, runtime_trace_summary


def occurrence(sequence=1, disposition=0):
    scope = dict(documentHigh=2**63 + 3, documentLow=2, sourceGeneration=4, transportEpoch=9,
        sampleRateBits=struct.unpack("<Q", struct.pack("<d", 48_000.0))[0], semanticVersion=1,
        linearFrequencyMode=True, order=0, pattern=0, firstRow=0, lastRow=3)
    birth = dict(sourceGeneration=3, transportEpoch=9, birthSequence=1, birthEventIndex=17)
    return dict(runtimeAction="user_loop_native_occurrence", runtimeAudioBackend="c_mixer",
        runtimeEventSource="offline_adapter_plan", runtimeEventCategory="user_loop_native_occurrence",
        plannedEventID=7, adapterActiveEventIndex=0, eventAppliedFrame=sequence + 3,
        plannedRuntimeFrame=sequence + 3, eventApplicationTiming="exact_frame",
        loopOccurrence=dict(scope=scope, batchSequence=sequence, eventOrdinal=8, eventID=7,
            localSourceIndex=0, opcode=2, disposition=disposition, plannedRuntimeFrame=sequence + 3,
            appliedRuntimeFrame=sequence + 3, targetBirth=birth, sourceBefore=birth, sourceAfter=birth))


def ordinary_occurrence(sequence=1, disposition=0):
    event = occurrence(sequence, disposition)
    event.update(schemaVersion=2, nativeTransportKind="finite_song",
        runtimeAction="ordinary_native_occurrence", runtimeEventCategory="ordinary_native_occurrence")
    event["loopOccurrence"]["scope"]["transportKind"] = "finite_song"
    return event


class RuntimeLoopTraceReaderTests(unittest.TestCase):
    def test_repeated_numeric_ids_keep_exact_scope_and_imported_birth(self):
        events = [occurrence(1), occurrence(2, 2)]
        result = runtime_loop_trace.scoped_loop_summary(events)
        self.assertEqual(result["scoped_occurrence_key_count"], 2)
        self.assertEqual(result["raw_numeric_id_count"], 1)
        self.assertEqual(result["duplicate_scoped_key_count"], 0)
        example = result["examples"][0]
        self.assertEqual(example["key"]["scope"]["documentHigh"], 2**63 + 3)
        self.assertEqual(example["key"]["eventID"], 7)
        self.assertEqual(example["localSourceIndex"], 0)
        self.assertEqual(example["targetBirth"]["sourceGeneration"], 3)
        self.assertEqual(example["targetBirth"]["birthEventIndex"], 17)

    def test_summary_separates_native_attempts_from_legacy_applications_and_reports_drops(self):
        legacy = dict(runtimeAction="c_mixer_add_voice", runtimeAudioBackend="c_mixer",
            plannedEventID=7, eventAppliedFrame=1, plannedRuntimeFrame=1, eventApplicationTiming="exact_frame")
        events = [legacy, occurrence(1), occurrence(2, 2), dict(runtimeAction="user_loop_native_summary",
            loopOccurrenceSummary=dict(attemptedOccurrences=3, appliedOccurrences=1, suppressedOccurrences=2,
                failedOccurrences=0, recordedOccurrences=2, droppedOccurrences=1))]
        result = runtime_trace_summary.build_summary(events)
        self.assertEqual(result["sample_time_alignment"]["applied_planned_event_count"], 1)
        self.assertEqual(result["user_loop_native"]["observed_occurrence_count"], 2)
        self.assertEqual(result["user_loop_native"]["dropped_occurrence_count"], 1)
        self.assertFalse(result["user_loop_native"]["complete_observed_trace"])
        self.assertIn("plan-local", runtime_trace_summary.build_markdown(result))
        self.assertNotIn("user_loop_native", runtime_trace_summary.build_summary([legacy]))

    def test_malformed_or_float_scope_never_falls_back_to_a_numeric_id(self):
        event = occurrence()
        event["loopOccurrence"]["scope"]["documentHigh"] = float(2**63 + 3)
        with self.assertRaises(runtime_trace_summary.TraceSummaryError):
            runtime_trace_summary.build_summary([event])
        with self.assertRaises(runtime_loop_trace.ScopedLoopTraceError):
            runtime_loop_trace.loop_observation(dict(runtimeAction="user_loop_native_occurrence", plannedEventID=7))

    def test_window_rejects_unscoped_offline_oracle_but_keeps_audio_only_scoped_keys(self):
        with tempfile.TemporaryDirectory(prefix="vtx-scoped-trace-", dir="/tmp") as temporary:
            root = Path(temporary)
            wavs = [root / "runtime.wav", root / "offline.wav"]
            for path in wavs:
                with wave.open(str(path), "wb") as output:
                    output.setnchannels(1); output.setsampwidth(2); output.setframerate(48_000)
                    output.writeframes(bytes(32))
            trace = root / "trace.jsonl"
            trace.write_text(json.dumps(occurrence()) + "\n", encoding="utf-8")
            offline = root / "diagnostics.json"
            offline.write_text(json.dumps(dict(events=[dict(event_index=7, scheduled_start_frame=4)])), encoding="utf-8")
            arguments = dict(runtime_wav=wavs[0], offline_wav=wavs[1], runtime_trace=trace,
                windows=[], window_frames=["0:8"], alignment_search_frames=0)
            with self.assertRaisesRegex(runtime_trace_correlate_window.WindowCorrelationError, "plan-local"):
                runtime_trace_correlate_window.build_report(**arguments, offline_diagnostics_json=offline)
            report = runtime_trace_correlate_window.build_report(**arguments)
            sample = report["windows"][0]["runtime_trace_correlation"]["event_order_sample"][0]
            self.assertEqual(sample["loop_occurrence"]["key"]["scope"]["documentHigh"], 2**63 + 3)
            self.assertEqual(sample["loop_occurrence"]["key"]["eventID"], 7)


class RuntimeOrdinaryTraceReaderTests(unittest.TestCase):
    def test_versioned_batch_local_ids_keep_exact_carried_birth_and_integer_scope(self):
        events = [ordinary_occurrence(1), ordinary_occurrence(2, 2)]
        result = runtime_loop_trace.scoped_finite_song_summary(events)
        self.assertEqual(result["identity_policy"], "scoped_ordinary_occurrence_v2")
        self.assertEqual(result["scoped_occurrence_key_count"], 2)
        self.assertEqual(result["raw_numeric_id_count"], 1)
        self.assertEqual(result["duplicate_scoped_key_count"], 0)
        example = result["examples"][1]
        self.assertEqual(example["key"]["nativeTransportKind"], "finite_song")
        self.assertEqual(example["key"]["scope"]["documentHigh"], 2**63 + 3)
        self.assertEqual(example["key"]["scope"]["transportKind"], "finite_song")
        self.assertEqual(example["targetBirth"]["sourceGeneration"], 3)
        self.assertEqual(example["targetBirth"]["birthEventIndex"], 17)
        self.assertEqual(example["sourceBefore"], example["sourceAfter"])

    def test_identical_raw_scope_row_and_ids_are_separate_across_transport_modes(self):
        loop, song = occurrence(), ordinary_occurrence()
        loop_key = runtime_loop_trace.loop_observation(loop)["key"]
        song_key = runtime_loop_trace.loop_observation(song)["key"]
        self.assertEqual(loop_key["nativeTransportKind"], "explicit_loop")
        self.assertEqual(song_key["nativeTransportKind"], "finite_song")
        self.assertNotEqual(loop_key, song_key)
        self.assertEqual({key: value for key, value in song_key["scope"].items() if key != "transportKind"}, loop_key["scope"])
        summary = runtime_trace_summary.build_summary([loop, song])
        self.assertEqual(summary["user_loop_native"]["scoped_occurrence_key_count"], 1)
        self.assertEqual(summary["ordinary_native"]["scoped_occurrence_key_count"], 1)
        self.assertEqual(summary["sample_time_alignment"]["applied_planned_event_count"], 0)
        markdown = runtime_trace_summary.build_markdown(summary)
        self.assertIn("Scoped Ordinary Song Observations", markdown)
        self.assertIn("Scoped User Loop Observations", markdown)

    def test_missing_unknown_conflicting_version_kind_and_float_scope_fail_closed(self):
        good = ordinary_occurrence()
        invalid = []
        for field, value in [("nativeTransportKind", None), ("nativeTransportKind", "unknown"),
                             ("schemaVersion", 1), ("schemaVersion", 3), ("schemaVersion", "2")]:
            event = copy.deepcopy(good); event[field] = value; invalid.append(event)
        event = copy.deepcopy(good); del event["nativeTransportKind"]; invalid.append(event)
        event = copy.deepcopy(good); del event["loopOccurrence"]["scope"]["transportKind"]; invalid.append(event)
        event = copy.deepcopy(good); event["loopOccurrence"]["scope"]["transportKind"] = "explicit_loop"; invalid.append(event)
        event = copy.deepcopy(good); event["loopOccurrence"]["scope"]["documentHigh"] = float(2**63 + 3); invalid.append(event)
        event = copy.deepcopy(good); event["plannedEventID"] = 8; invalid.append(event)
        event = copy.deepcopy(good); del event["loopOccurrence"]; invalid.append(event)
        for event in invalid:
            with self.subTest(event=event), self.assertRaises(runtime_trace_summary.TraceSummaryError):
                runtime_trace_summary.build_summary([event])
            self.assertFalse(runtime_trace_summary.is_planned_adapter_event_application(event))

    def test_summary_preserves_legacy_counts_and_separates_finite_drops_and_raw_ids(self):
        legacy = dict(runtimeAction="c_mixer_add_voice", plannedEventID=7,
            eventAppliedFrame=1, plannedRuntimeFrame=1, eventApplicationTiming="exact_frame")
        totals = dict(schemaVersion=2, nativeTransportKind="finite_song", runtimeAction="ordinary_native_summary",
            loopOccurrenceSummary=dict(attemptedOccurrences=3, appliedOccurrences=1, suppressedOccurrences=2,
                failedOccurrences=0, recordedOccurrences=2, droppedOccurrences=1))
        result = runtime_trace_summary.build_summary([legacy, ordinary_occurrence(1), ordinary_occurrence(2, 2), totals])
        self.assertEqual(result["sample_time_alignment"]["applied_planned_event_count"], 1)
        self.assertNotIn("user_loop_native", result)
        self.assertEqual(result["ordinary_native"]["observed_occurrence_count"], 2)
        self.assertEqual(result["ordinary_native"]["raw_numeric_id_count"], 1)
        self.assertEqual(result["ordinary_native"]["dropped_occurrence_count"], 1)
        self.assertFalse(result["ordinary_native"]["complete_observed_trace"])
        bad = copy.deepcopy(totals); del bad["nativeTransportKind"]
        with self.assertRaises(runtime_trace_summary.TraceSummaryError):
            runtime_trace_summary.build_summary([bad])

    def test_window_rejects_unscoped_oracle_and_preserves_finite_audio_only_keys(self):
        event = ordinary_occurrence()
        self.assertTrue(runtime_loop_trace.has_scoped_loop_data(event))
        with self.assertRaisesRegex(runtime_loop_trace.ScopedLoopTraceError, "plan-local"):
            runtime_loop_trace.require_unscoped_offline_correlation([event], True)
        with tempfile.TemporaryDirectory(prefix="vtx-finite-trace-", dir="/private/tmp") as temporary:
            root = Path(temporary)
            for name in ["runtime.wav", "offline.wav"]:
                with wave.open(str(root / name), "wb") as output:
                    output.setnchannels(1); output.setsampwidth(2); output.setframerate(48_000)
                    output.writeframes(bytes(32))
            trace = root / "trace.jsonl"; trace.write_text(json.dumps(event) + "\n", encoding="utf-8")
            report = runtime_trace_correlate_window.build_report(runtime_wav=root / "runtime.wav",
                offline_wav=root / "offline.wav", runtime_trace=trace, windows=[],
                window_frames=["0:8"], alignment_search_frames=0)
            correlation = report["windows"][0]["runtime_trace_correlation"]
            self.assertNotIn("user_loop_native", correlation)
            self.assertEqual(correlation["ordinary_native"]["scoped_occurrence_key_count"], 1)
            sample = correlation["event_order_sample"][0]
            self.assertNotIn("loop_occurrence", sample)
            self.assertEqual(sample["ordinary_occurrence"]["key"]["nativeTransportKind"], "finite_song")


if __name__ == "__main__":
    unittest.main()
