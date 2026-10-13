import json
import tempfile
import unittest
from pathlib import Path

from tools.vtx_diag import residual_scan


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_module():
    return residual_scan


class XMResidualEffectScanTests(unittest.TestCase):
    def test_linear_scan_classifies_requested_focus_buckets(self):
        scan = load_module()
        module = scan.ModuleData(
            label="xm-corpus-001",
            frequency_table="linear",
            channels=2,
            song_length=1,
            default_speed=6,
            default_bpm=125,
            order_table=[0],
            patterns=[
                scan.Pattern(rows=[
                    [cell(scan, note=48, instrument=1), cell(scan, effect_type=0x0A, effect_param=0x00)],
                    [cell(scan, note=50, effect_type=0x03, effect_param=0x04), cell(scan)],
                    [cell(scan, effect_type=0x03, effect_param=0x00), cell(scan, note=48, instrument=1)],
                    [cell(scan, effect_type=0x0A, effect_param=0x0F), cell(scan, effect_type=0x0A, effect_param=0x00)],
                    [cell(scan, effect_type=0x0A, effect_param=0x00), cell(scan, effect_type=0x15, effect_param=0x04)],
                    [cell(scan, effect_type=0x21, effect_param=0x11), cell(scan, volume=0xB4)],
                    [cell(scan, effect_type=0x07, effect_param=0x04), cell(scan, effect_type=0x0E, effect_param=0x72)],
                    [cell(scan, volume=0xA2), cell(scan, volume=0xF3)],
                    [cell(scan, effect_type=0x1B, effect_param=0x22), cell(scan, effect_type=0x14, effect_param=0x01)],
                    [cell(scan, effect_type=0x1B, effect_param=0x00), cell(scan, effect_type=0x14, effect_param=0x09)],
                    [cell(scan, effect_type=0x05, effect_param=0x0F), cell(scan, effect_type=0x05, effect_param=0x00)],
                    [cell(scan, effect_type=0x1F, effect_param=0x44), cell(scan, effect_type=0x20, effect_param=0x55)],
                    [cell(scan, effect_type=0x19, effect_param=0x12), cell(scan, effect_type=0x11, effect_param=0x00)],
                    [cell(scan, effect_type=0x11, effect_param=0x12), cell(scan, effect_type=0x0E, effect_param=0x31)],
                    [cell(scan, effect_type=0x0E, effect_param=0xE2), cell(scan, effect_type=0x1D, effect_param=0x34)],
                    [cell(scan, effect_type=0x0E, effect_param=0x08), cell(scan)],
                ])
            ],
            instruments=[scan.InstrumentEnvelope(), scan.InstrumentEnvelope(volume_enabled=True)],
        )
        group = scan.ScanGroup("linear")

        scan.scan_module(module, [group])
        buckets = group.buckets

        self.assertEqual(buckets["xxy"].count(), 1)
        self.assertEqual(buckets["lxx"].count(), 1)
        self.assertEqual(buckets["lxx"].count("active_channel_envelope_enabled_count"), 1)
        self.assertEqual(buckets["3xx"].count("nonzero_3xx_count"), 1)
        self.assertEqual(buckets["3xx"].count("zero_300_count"), 1)
        self.assertEqual(buckets["3xx"].count("zero_300_memory_reuse_count"), 1)
        self.assertEqual(buckets["axy"].count("a00_count"), 3)
        self.assertEqual(buckets["axy"].count("a00_reuse_if_implemented_count"), 1)
        self.assertEqual(buckets["axy"].count("mixed_nibble_count"), 0)
        self.assertEqual(buckets["7xy"].count("7xy_count"), 1)
        self.assertEqual(buckets["7xy"].count("700_count"), 0)
        self.assertEqual(buckets["7xy"].count("zero_nibble_memory_case_count"), 1)
        self.assertEqual(buckets["7xy"].count("e7x_control_count"), 1)
        self.assertEqual(buckets["vol_a"].count(), 1)
        self.assertEqual(buckets["vol_b"].count(), 1)
        self.assertEqual(buckets["vol_f"].count(), 1)
        self.assertEqual(buckets["rxy"].count("applied_count"), 0)
        self.assertEqual(buckets["rxy"].count("counter_execution_count"), 6)
        self.assertEqual(buckets["rxy"].count("memory_replay_count"), 1)
        self.assertEqual(buckets["rxy"].count("no_op_effect_memory_deferred_count"), 0)
        self.assertEqual(buckets["kxx"].count("applied_count"), 1)
        self.assertEqual(buckets["kxx"].count("out_of_row_no_op_count"), 1)
        self.assertEqual(buckets["5xy"].count("applied_count"), 1)
        self.assertEqual(buckets["5xy"].count("no_target_count"), 1)
        self.assertEqual(buckets["pxy"].count("detected_count"), 1)
        self.assertEqual(buckets["hxy"].count("detected_count"), 2)
        self.assertEqual(buckets["hxy"].count("h00_no_op_count"), 1)
        self.assertEqual(buckets["hxy"].count("both_nibbles_nonzero_count"), 1)
        self.assertEqual(buckets["e3x"].count("detected_count"), 1)
        self.assertEqual(buckets["eex"].count("detected_count"), 1)
        self.assertEqual(buckets["txy"].count("detected_count"), 1)
        self.assertEqual(buckets["e0x"].count("detected_count"), 1)
        self.assertEqual(buckets["unknown"].count("vxx_count"), 1)
        self.assertEqual(buckets["unknown"].count("wxx_count"), 1)
        self.assertEqual(
            scan.recommend_next_pr(group),
            " ".join((
                scan.BACKEND_FREEZE_NEXT_PR_RECOMMENDATION,
                scan.BACKEND_FREEZE_PRIORITIZATION_NOTE,
                scan.BACKEND_FREEZE_PROMOTION_NOTE,
            )),
        )

    def test_recommendation_treats_completed_foundations_as_low_priority(self):
        scan = load_module()
        group = scan.ScanGroup("linear")
        group.bucket("axy").add(
            "xm-corpus-001",
            scan.Coordinate("xm-corpus-001", "linear", 0, 0, 0, 0),
            metric="a00_reuse_if_implemented_count",
            amount=1000,
        )
        group.bucket("xxy").add(
            "xm-corpus-002",
            scan.Coordinate("xm-corpus-002", "linear", 0, 0, 0, 0),
        )

        freeze_recommendation = " ".join((
            scan.BACKEND_FREEZE_NEXT_PR_RECOMMENDATION,
            scan.BACKEND_FREEZE_PRIORITIZATION_NOTE,
            scan.BACKEND_FREEZE_PROMOTION_NOTE,
        ))
        self.assertEqual(scan.recommend_next_pr(group), freeze_recommendation)
        self.assertIn("A00 memory is supported", scan.status_note("axy", {}))

        group.bucket("vol_f").add(
            "xm-corpus-003",
            scan.Coordinate("xm-corpus-003", "linear", 0, 0, 0, 0),
        )
        self.assertEqual(scan.recommend_next_pr(group), freeze_recommendation)
        self.assertIn("Implemented, parity-watch", scan.status_note("vol_f", {}))

    def test_recommendation_freezes_completed_and_parity_watch_buckets(self):
        scan = load_module()
        group = scan.ScanGroup("linear")
        for key in ("lxx", "kxx", "5xy", "rxy", "vol_f"):
            group.bucket(key).add(
                "xm-corpus-001",
                scan.Coordinate("xm-corpus-001", "linear", 0, 0, 0, 0),
            )

        recommendation = scan.recommend_next_pr(group)

        self.assertIn("No behavior-changing XM effect PR is recommended", recommendation)
        self.assertIn("docs/xm-effect-support.md", recommendation)
        self.assertIn("freeze-exit criterion", recommendation)
        self.assertNotIn("Minimal Lxx", recommendation)
        self.assertNotIn("Tone Portamento Foundation", recommendation)
        self.assertIn("G20–G22 closed", scan.status_note("rxy", {}))

    def test_amiga_scan_keeps_pitch_residuals_in_parity_watch_bucket(self):
        scan = load_module()
        module = scan.ModuleData(
            label="xm-corpus-036",
            frequency_table="amiga",
            channels=1,
            song_length=1,
            default_speed=6,
            default_bpm=125,
            order_table=[0],
            patterns=[
                scan.Pattern(rows=[
                    [cell(scan, note=48, instrument=1)],
                    [cell(scan, effect_type=0x02, effect_param=0x04)],
                    [cell(scan, note=50, effect_type=0x03, effect_param=0x04)],
                    [cell(scan, note=52, effect_type=0x05, effect_param=0x01)],
                    [cell(scan, effect_type=0x21, effect_param=0x21)],
                    [cell(scan, volume=0xF4)],
                ])
            ],
            instruments=[scan.InstrumentEnvelope(), scan.InstrumentEnvelope()],
        )
        group = scan.ScanGroup("amiga")

        scan.scan_module(module, [group])
        bucket = group.bucket("amiga")

        self.assertEqual(bucket.count("amiga_2xx_count"), 1)
        self.assertEqual(bucket.count("amiga_3xx_count"), 1)
        self.assertEqual(bucket.count("amiga_xxy_count"), 1)
        self.assertEqual(bucket.count("amiga_volume_column_fxx_count"), 1)
        self.assertEqual(group.bucket("3xx").count("unsupported_frequency_table_count"), 0)
        self.assertEqual(group.bucket("3xx").count("applied_or_applyable_count"), 1)
        self.assertEqual(bucket.count("amiga_5xy_count"), 1)
        self.assertEqual(group.bucket("5xy").count("unsupported_frequency_table_count"), 1)

    def test_public_tremolo_fixture_reports_implemented_parent_and_controls(self):
        scan = load_module()
        module = scan.parse_xm_module(
            REPO_ROOT / "tests/reference-xm/generated/tremolo-effects.xm",
            "xm-corpus-001",
            "linear",
        )
        group = scan.ScanGroup("linear")
        scan.scan_module(module, [group])

        bucket = group.bucket("7xy")
        self.assertEqual(bucket.count("7xy_count"), 37)
        self.assertEqual(bucket.count("e7x_control_count"), 8)
        self.assertEqual(bucket.count("700_count"), 26)
        self.assertEqual(bucket.count("zero_nibble_memory_case_count"), 28)
        self.assertEqual(set(bucket.family_counts), {f"E7{x:X}" for x in range(8)})
        note = scan.status_note("7xy", dict(bucket.counts))
        self.assertIn("Implemented, parity-watch", note)
        self.assertIn("memory", note)
        self.assertNotIn("deferred", note.lower())

    def test_all_tremolo_controls_and_cold_zero_memory_remain_occurrence_counts(self):
        scan = load_module()
        rows = [[cell(scan, effect_type=0x07, effect_param=0)]]
        for control in range(16):
            rows.extend([
                [cell(scan, effect_type=0x0E, effect_param=0x70 | control)],
                [cell(scan, effect_type=0x07, effect_param=0x48)],
            ])
        group = scan.ScanGroup("linear")
        scan.scan_module(module_with_rows(scan, rows), [group])

        counts = group.bucket("7xy").counts
        self.assertEqual(counts["7xy_count"], 17)
        self.assertEqual(counts["e7x_control_count"], 16)
        self.assertEqual(counts["700_count"], 1)
        self.assertEqual(counts["zero_nibble_memory_case_count"], 1)
        self.assertNotIn("applied_count", counts)

    def test_public_amiga_3xx_fixture_keeps_300_memory_without_unsupported_gate(self):
        scan = load_module()
        module = scan.parse_xm_module(
            REPO_ROOT / "tests/reference-xm/generated/portamento-scaling-amiga.xm",
            "xm-corpus-001",
            "amiga",
        )
        group = scan.ScanGroup("amiga")
        scan.scan_module(module, [group])

        bucket = group.bucket("3xx")
        self.assertEqual(bucket.count("nonzero_3xx_count"), 1)
        self.assertEqual(bucket.count("zero_300_count"), 1)
        self.assertEqual(bucket.count("applied_or_applyable_count"), 2)
        self.assertEqual(bucket.count("zero_300_memory_reuse_count"), 1)
        self.assertEqual(bucket.count("unsupported_frequency_table_count"), 0)
        self.assertEqual(group.bucket("amiga").count("amiga_3xx_count"), 2)

    def test_3xx_residual_states_are_preserved_in_both_supported_frequency_modes(self):
        scan = load_module()
        rows = [
            [cell(scan, effect_type=0x03)],
            [cell(scan, note=48, instrument=1)],
            [cell(scan, effect_type=0x03)],
            [cell(scan, note=50, effect_type=0x03)],
            [cell(scan, note=52, effect_type=0x03, effect_param=0x04)],
            [cell(scan, effect_type=0x03)],
        ]
        for frequency_table in ("linear", "amiga"):
            with self.subTest(frequency_table=frequency_table):
                group = scan.ScanGroup(frequency_table)
                scan.scan_module(module_with_rows(scan, rows, frequency_table), [group])
                bucket = group.bucket("3xx")
                self.assertEqual(bucket.count("no_active_count"), 1)
                self.assertEqual(bucket.count("no_target_count"), 1)
                self.assertEqual(bucket.count("missing_memory_count"), 1)
                self.assertEqual(bucket.count("applied_or_applyable_count"), 2)
                self.assertEqual(bucket.count("zero_300_memory_reuse_count"), 1)
                self.assertEqual(bucket.count("unsupported_frequency_table_count"), 0)

        group = scan.ScanGroup("unknown")
        scan.scan_module(module_with_rows(scan, rows, "unknown"), [group])
        self.assertEqual(group.bucket("3xx").count("unsupported_frequency_table_count"), 4)

    def test_gap_triage_recognizes_tremolo_without_promoting_other_parents(self):
        scan = load_module()
        with tempfile.TemporaryDirectory() as directory:
            label_map = Path(directory) / "public-map.json"
            label_map.write_text(json.dumps({"entries": [{
                "label": "xm-corpus-001",
                "path": str(REPO_ROOT / "tests/reference-xm/generated/tremolo-effects.xm"),
            }]}), encoding="utf-8")
            report = scan.build_scan(label_map)
        triage = scan.build_gap_triage(report, REPO_ROOT / "docs/xm-effect-support.md")
        targets = {target["key"]: target for target in triage["targets"]}

        for key in ("7xy", "e7x"):
            with self.subTest(key=key):
                self.assertEqual(targets[key]["c_mixer_adapter_implementation_exists"], "yes")
                self.assertEqual(targets[key]["recommended_priority"], "implemented/parity-watch")
                self.assertEqual(targets[key]["current_adapter_summary"], "coverage not provided")
        for key in ("pxy", "vol_a", "vol_b", "eex", "txy"):
            self.assertEqual(targets[key]["c_mixer_adapter_implementation_exists"], "no")
        self.assertEqual(triage["schema_version"], 1)
        self.assertNotIn("7xy/E7x,", triage["answers"]["surgical_legacy_ports"])
        self.assertIn("Amiga", triage["answers"]["three_xx_memory_gap"])
        self.assertIn("implemented", triage["answers"]["seven_xy_before_amiga"])


class RxyResidualContractTests(unittest.TestCase):
    def trace(self, cells, speed=6):
        module = module_with_rows(residual_scan, [[c] for c in cells])
        state, group, decisions = residual_scan.ChannelState(), residual_scan.ScanGroup("all"), []
        for row, c in enumerate(cells):
            residual_scan.update_rxy_reset_state(module, c, state, speed)
            if c.effect_type == 27:
                decisions.append(residual_scan.scan_rxy(module, c,
                    residual_scan.Coordinate(module.label, "linear", 0, 0, row, 0), state, speed, [group]))
        return decisions, state, group.bucket("rxy")

    def r(self, parameter=0, **fields):
        return residual_scan.Cell(effect_type=27, effect_param=parameter, **fields)

    def test_seeded_r00_resolves_both_nibbles_and_executes_ticks_two_five(self):
        decisions, state, bucket = self.trace([self.r(0x93), self.r()])
        self.assertEqual([(d.mode, d.interval, d.execution_ticks) for d in decisions], [(9, 3, (2, 5))] * 2)
        self.assertTrue(decisions[1].mode_reused and decisions[1].speed_reused)
        self.assertEqual(state.r_counter, 0)
        self.assertEqual(bucket.count("counter_execution_count"), 4)
        self.assertEqual(bucket.count("memory_replay_count"), 1)
        # The static inputs cannot prove a represented route or audible application.
        self.assertEqual(bucket.count("applied_count"), 0)
        self.assertEqual(bucket.count("source_eligibility_unknown_count"), 2)
        for key in ("applied_count", "detected_count", "no_op_effect_memory_deferred_count", "out_of_row_no_op_count"):
            self.assertIsInstance(bucket.to_json()["counts"][key], int)
        self.assertEqual(bucket.count("no_op_effect_memory_deferred_count"), 0)

    def test_speed_one_carries_counter_and_fires_third_row(self):
        decisions, _, bucket = self.trace([self.r(0x93)] * 4, speed=1)
        self.assertEqual([d.execution_ticks for d in decisions], [(), (), (0,), ()])
        self.assertEqual([d.counter_after for d in decisions], [1, 2, 0, 1])
        self.assertEqual(bucket.count("counter_carry_execution_count"), 1)
        self.assertEqual(bucket.count("out_of_row_no_op_count"), 0)
        module = module_with_rows(residual_scan, [[self.r(0x93)]] * 4)
        module = residual_scan.ModuleData(**{**vars(module), "default_speed": 1})
        group = residual_scan.ScanGroup("all")
        residual_scan.scan_module(module, [group])
        self.assertEqual(group.bucket("rxy").count("counter_execution_count"), 1)

    def test_mixed_zero_nibbles_reuse_only_their_own_memory(self):
        for parameter, reused in [(0x03, (True, False)), (0x90, (False, True))]:
            with self.subTest(parameter=parameter):
                decisions, _, _ = self.trace([self.r(0x93), self.r(parameter)])
                replay = decisions[1]
                self.assertEqual((replay.mode, replay.interval, replay.execution_ticks), (9, 3, (2, 5)))
                self.assertEqual((replay.mode_reused, replay.speed_reused), reused)

    def test_cold_r00_and_r90_execute_literal_zero_interval(self):
        for parameter, mode in [(0, 0), (0x90, 9)]:
            with self.subTest(parameter=parameter):
                decisions, _, bucket = self.trace([self.r(parameter)])
                self.assertEqual((decisions[0].mode, decisions[0].interval), (mode, 0))
                self.assertEqual(decisions[0].execution_ticks, tuple(range(6)))
                self.assertEqual(bucket.count("interval_zero_execution_count"), 6)
                self.assertEqual(bucket.count("no_op_effect_memory_deferred_count"), 0)

    def test_two_channels_keep_distinct_memory_and_counter_histories(self):
        states = [residual_scan.ChannelState(), residual_scan.ChannelState()]
        module = module_with_rows(residual_scan, [])
        histories = []
        for row in range(3):
            history = []
            for channel, seed in enumerate([0x94, 0x13]):
                decision = residual_scan.scan_rxy(module, self.r(seed if row == 0 else 0),
                    residual_scan.Coordinate(module.label, "linear", 0, 0, row, channel), states[channel], 1, [])
                history.append(decision.execution_ticks)
            histories.append(history)
        self.assertEqual(histories, [[(), ()], [(), ()], [(), (0,)]])
        self.assertEqual([(s.r_mode_memory, s.r_speed_memory, s.r_counter) for s in states], [(9, 4, 3), (1, 3, 0)])
        rows = [[self.r(0x94), self.r(0x13)]] + [[self.r(), self.r()]] * 2
        module = residual_scan.ModuleData(**{**vars(module), "channels": 2, "default_speed": 1,
            "patterns": [residual_scan.Pattern(rows)]})
        group = residual_scan.ScanGroup("all")
        residual_scan.scan_module(module, [group])
        self.assertEqual(group.bucket("rxy").count("counter_execution_count"), 1)

    def test_reset_boundaries_preserve_nibble_memory(self):
        for transition in [residual_scan.Cell(instrument=1), residual_scan.Cell(note=53, instrument=1),
                           residual_scan.Cell(instrument=1, effect_type=20, volume=0xF1),
                           residual_scan.Cell(effect_type=14, effect_param=0x93)]:
            with self.subTest(transition=transition):
                decisions, state, _ = self.trace([self.r(0x94), transition, self.r()])
                self.assertEqual(decisions[-1].execution_ticks, (3,))
                self.assertEqual((state.r_mode_memory, state.r_speed_memory), (9, 4))
                module = module_with_rows(residual_scan, [[self.r(0x94)], [transition], [self.r()]])
                group = residual_scan.ScanGroup("all")
                residual_scan.scan_module(module, [group])
                self.assertEqual(group.bucket("rxy").count("counter_execution_count"), 2)

    def test_note_release_e90_and_undispatched_e9_preserve_counter(self):
        for transition in [residual_scan.Cell(note=53), residual_scan.Cell(note=97),
                           residual_scan.Cell(instrument=1, effect_type=20),
                           residual_scan.Cell(effect_type=20), residual_scan.Cell(effect_type=14, effect_param=0x90),
                           residual_scan.Cell(effect_type=14, effect_param=0x97)]:
            with self.subTest(transition=transition):
                decisions, _, _ = self.trace([self.r(0x94), transition, self.r()])
                self.assertEqual(decisions[-1].counter_before, 2)
                self.assertEqual(decisions[-1].execution_ticks, (1, 5))
                module = module_with_rows(residual_scan, [[self.r(0x94)], [transition], [self.r()]])
                group = residual_scan.ScanGroup("all")
                residual_scan.scan_module(module, [group])
                self.assertEqual(group.bucket("rxy").count("counter_execution_count"), 3)

    def test_tick_zero_admitted_and_gated_rows_always_resolve_memory(self):
        for volume, gated in [(0, False), (0x10, False), (0xA0, False), (0xC0, False),
                              (0x20, True), (0x61, True), (0x91, True), (0xB1, True), (0xF1, True)]:
            with self.subTest(volume=volume):
                decisions, state, bucket = self.trace([self.r(0x90, volume=volume)], speed=1)
                self.assertEqual(decisions[0].tick_zero_gated, gated)
                self.assertEqual(decisions[0].execution_ticks, () if gated else (0,))
                self.assertEqual((state.r_mode_memory, state.r_speed_memory), (9, 0))
                self.assertEqual(bucket.count("tick_zero_gated_count"), int(gated))
                self.assertEqual(bucket.count("counter_pending_count"), 0)

    def test_unknown_fine_volume_gate_and_delayed_route_do_not_invent_noop(self):
        for volume in [0x80, 0x8F, 0x90]:
            decisions, state, bucket = self.trace([self.r(0x93, volume=volume)])
            self.assertIsNone(decisions[0].tick_zero_gated)
            self.assertTrue(decisions[0].uncertain)
            self.assertIsNone(state.r_counter)
            self.assertEqual(bucket.count("no_op_effect_memory_deferred_count"), 0)
        decisions, _, _ = self.trace([self.r(0x93, volume=0x80), residual_scan.Cell(instrument=1), self.r()])
        self.assertFalse(decisions[-1].uncertain)
        self.assertEqual((decisions[-1].mode, decisions[-1].interval, decisions[-1].execution_ticks), (9, 3, (2, 5)))
        decisions, _, _ = self.trace([self.r(0x94),
            residual_scan.Cell(note=49, instrument=1, effect_type=14, effect_param=0xD1), self.r()])
        self.assertTrue(decisions[-1].uncertain)

    def test_order_and_e60_carry_but_unexpanded_loop_is_uncertain(self):
        for effect in [None, 0x60, 0x61]:
            rows = [[self.r(0x94)]] + ([] if effect is None else [[residual_scan.Cell(effect_type=14, effect_param=effect)]])
            module = module_with_rows(residual_scan, rows)
            module = residual_scan.ModuleData(**{**vars(module), "song_length": 2, "order_table": [0, 1],
                "patterns": [residual_scan.Pattern(rows), residual_scan.Pattern([[self.r()]])]})
            group = residual_scan.ScanGroup("all")
            residual_scan.scan_module(module, [group])
            bucket = group.bucket("rxy")
            self.assertEqual(bucket.count("counter_execution_count"), 1 if effect == 0x61 else 3)
            self.assertEqual(bucket.count("scheduler_unknown_count"), int(effect == 0x61))
            self.assertEqual(bucket.count("memory_replay_count"), 1)

    def test_same_row_fxx_last_writer_changes_only_rxy_classification(self):
        for cells in [[self.r(0x93), residual_scan.Cell(effect_type=15, effect_param=6)],
                      [residual_scan.Cell(effect_type=15, effect_param=6), self.r(0x93)]]:
            module = module_with_rows(residual_scan, [cells])
            module = residual_scan.ModuleData(**{**vars(module), "channels": 2, "default_speed": 1})
            group = residual_scan.ScanGroup("all")
            residual_scan.scan_module(module, [group])
            self.assertEqual(group.bucket("rxy").count("counter_execution_count"), 2)
        for first, last, executions in [(1, 6, 2), (6, 1, 0)]:
            module = module_with_rows(residual_scan, [[residual_scan.Cell(effect_type=15, effect_param=first),
                self.r(0x93), residual_scan.Cell(effect_type=15, effect_param=last)]])
            module = residual_scan.ModuleData(**{**vars(module), "channels": 3, "default_speed": 1})
            group = residual_scan.ScanGroup("all")
            residual_scan.scan_module(module, [group])
            self.assertEqual(group.bucket("rxy").count("counter_execution_count"), executions)
        module = module_with_rows(residual_scan, [[residual_scan.Cell(effect_type=20, effect_param=3),
                                                  residual_scan.Cell(effect_type=15, effect_param=6)]])
        module = residual_scan.ModuleData(**{**vars(module), "channels": 2, "default_speed": 1})
        group = residual_scan.ScanGroup("all")
        residual_scan.scan_module(module, [group])
        self.assertEqual(group.bucket("kxx").count("out_of_row_no_op_count"), 1)


def cell(module, note=0, instrument=0, volume=0, effect_type=0, effect_param=0):
    return module.Cell(note=note, instrument=instrument, volume=volume, effect_type=effect_type, effect_param=effect_param)


def module_with_rows(scan, rows, frequency_table="linear"):
    return scan.ModuleData(
        label="xm-corpus-001", frequency_table=frequency_table, channels=1,
        song_length=1, default_speed=6, default_bpm=125, order_table=[0],
        patterns=[scan.Pattern(rows=rows)],
        instruments=[scan.InstrumentEnvelope(), scan.InstrumentEnvelope()],
    )


if __name__ == "__main__":
    unittest.main()
