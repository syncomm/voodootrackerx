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


if __name__ == "__main__":
    unittest.main()
