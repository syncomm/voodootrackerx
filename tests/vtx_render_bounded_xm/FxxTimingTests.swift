import Foundation
import CryptoKit
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class FxxTimingTests: XCTestCase {
    func testTimingContinuationKeepsExecutedFxxDelayAndFractionalFramesAcrossPartitions() {
        for rate in [44_100.0, 48_000.0] {
            let commands = [[cc(15, 3)], [cc(15, 151)], [cc(14, 0xE2), cc(15, 5)], [cc(15, 7), cc(15, 143)]]
            let rows = (0..<4000).map { PlaybackRow(index: $0, cells: commands[$0 % commands.count]) }
            let pattern = PlaybackPattern(index: 0, rows: rows)
            let song = PlaybackSong(title: "Public continuation clock", orders: [.init(orderIndex: 0, patternIndex: 0)],
                patternsByIndex: [0: pattern], instrumentsByIndex: [:], restartOrderIndex: 0,
                endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125))
            let whole = PlaybackSongFxxTimingPlanner.plan(song, startOrderIndex: 0, orderCount: 1, sampleRate: rate)
            for partition in [1, 3, 7, 64] {
                var state = PlaybackSongFxxTimingPlanner.State(speed: 6, bpm: 125, nextExactFrame: 0)
                for start in stride(from: 0, to: rows.count, by: partition) {
                    let end = min(rows.count, start + partition)
                    let visits = (start..<end).enumerated().map { local, global in
                        PlaybackSongTraversalRow(source: .init(orderIndex: 0, patternIndex: 0, rowIndex: global),
                            orderIndex: 0, pattern: pattern, row: rows[global], rowArrayIndex: global, syntheticRow: local)
                    }
                    let traversal = PlaybackSongTraversalPlan(rows: visits, adaptedOrders: [], traversalDiagnostics: [],
                        pathLength: visits.count, stopReason: .selectedRangeEnd, guardHit: false)
                    let batch = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: rate, initialState: state)
                    for local in batch.rowTimings.indices {
                        let actual = batch.rowTimings[local], expected = whole.rowTimings[start + local]
                        XCTAssertEqual(actual.rowStartExactFrame, expected.rowStartExactFrame)
                        XCTAssertEqual(actual.rowEndExactFrame, expected.rowEndExactFrame)
                        XCTAssertEqual(actual.effectiveSpeed, expected.effectiveSpeed)
                        XCTAssertEqual(actual.effectiveBPM, expected.effectiveBPM)
                        XCTAssertEqual(actual.patternDelayCycles, expected.patternDelayCycles)
                        for tick in 0..<expected.actualTickCount {
                            XCTAssertEqual(batch.frameFor(row: local, tick: tick), whole.frameFor(row: start + local, tick: tick))
                        }
                    }
                    state = batch.terminalState
                }
                XCTAssertEqual(state, whole.terminalState)
            }
            XCTAssertEqual(whole.rowTimings[2].patternDelayCycles, 2)
            XCTAssertNotEqual(whole.endExactFrame, whole.endExactFrame.rounded(.down))
        }
    }

    func testNativeSelectionLiteralPeriodsAndIndependentThreeSampleRouting() throws {
        typealias F = PlaybackSongSelectionDispatchFacts
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let song = selectionSong(selectionSentinels[0], linear: linear)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
            let facts = plan.selectionDispatchFacts.facts
            XCTAssertEqual(plan.selectionDispatchFacts.coverage, .nativeSelectionProducersV1)
            XCTAssertEqual(facts.count, 5)
            let periods: [Double] = linear ? [4608, 3768, 2928, 4608, 4608] : [6848, 3208, 1504, 6848, 6848]
            for (i, fact) in facts.enumerated() {
                let slot = [0, 1, 2, 0, 0][i]
                XCTAssertEqual(fact.role, .trigger); XCTAssertEqual(fact.channel, 0)
                XCTAssertEqual(fact.noteOnly, (1...3).contains(i))
                XCTAssertEqual(fact.syntheticRow, i); XCTAssertEqual(fact.tick, 0)
                XCTAssertEqual(fact.source, .init(orderIndex: 0, patternIndex: 0, rowIndex: i))
                XCTAssertEqual(fact.absoluteFrame, i * 6 * Int(rate / 50))
                XCTAssertEqual(fact.pitch, .known(linear ? .linear : .amigaVTX4x, nativePeriod: periods[i]))
                XCTAssertEqual(fact.semanticInstrument, 1); XCTAssertEqual(fact.semanticSample, slot)
                XCTAssertEqual(fact.carriedInstrument, 1); XCTAssertEqual(fact.carriedNote, [49, 50, 51, 49, 49][i])
                XCTAssertEqual(fact.routedInstrument, 1); XCTAssertEqual(fact.mappedSample, slot)
                XCTAssertEqual(fact.selectionMethod, .sampleMap); XCTAssertEqual(fact.associatedGeneration, i)
                XCTAssertEqual(fact.baseRate, [8363.0, 16726, 25089][slot])
                XCTAssertEqual(fact.relativeNote, slot * 12); XCTAssertEqual(fact.finetune, slot * 16)
                XCTAssertEqual(fact.baseRateOrigin, .representedHeader)
                XCTAssertEqual(fact.relativeNoteOrigin, .representedHeader); XCTAssertEqual(fact.finetuneOrigin, .representedHeader)
                XCTAssertEqual(plan.pattern.events[i].initialSourceFrame, 0)
            }
            XCTAssertNotEqual(plan.pattern.events[0].sample, plan.pattern.events[1].sample)
            XCTAssertNotEqual(plan.pattern.events[1].sample, plan.pattern.events[2].sample)
            XCTAssertEqual(song.instrumentsByIndex[1]?.noteSampleMap?.count, 96)
            XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticAdapter.ChannelState>.stride, 1152)
            XCTAssertEqual(MemoryLayout<PlaybackXMChannelRow>.stride, 8)
            XCTAssertEqual(MemoryLayout<F.TuningProducers>.stride, 24)
            let laterSong = PlaybackSong(title: song.title, orders: [0, 1].map { .init(orderIndex: $0, patternIndex: 0) },
                patternsByIndex: song.patternsByIndex, instrumentsByIndex: song.instrumentsByIndex,
                restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: song.initialTiming, usesLinearFrequencyTable: linear)
            let later = PlaybackSongSyntheticAdapter.adapt(laterSong, startOrderIndex: 1, orderCount: 1, sampleRate: rate)
            XCTAssertEqual(later.selectionDispatchFacts.facts.first?.source.orderIndex, 1)
            XCTAssertEqual(later.selectionDispatchFacts.facts.first?.absoluteFrame, 0)
            XCTAssertEqual(later.selectionDispatchFacts.facts.first?.associatedGeneration, 0)
        } }
    }

    func testNativeSelectionEmptyRefusedAndActualDelayDispatch() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for delay in [0, 3, 6] {
            let unit = Int(rate / 50)
            for instrument: UInt8 in [2, 3, 4] {
                let song = selectionSong([cc(note: 50, instrument: 1),
                    cc(14, UInt8(0xD0 + delay), note: 49, instrument: instrument, volume: 0xB8), cc(note: 50, instrument: 1)], linear: linear)
                let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
                let selected = plan.selectionDispatchFacts.facts.filter { $0.syntheticRow == 1 && $0.role != .carriedInstrument }
                XCTAssertEqual(selected.count, delay < 6 ? 1 : 0)
                guard delay < 6 else { continue }
                let fact = try XCTUnwrap(selected.first)
                XCTAssertEqual(fact.tick, delay); XCTAssertEqual(fact.absoluteFrame, (6 + delay) * unit)
                XCTAssertEqual(fact.semanticInstrument, Int(instrument)); XCTAssertEqual(fact.semanticSample, 0)
                if instrument == 3 {
                    XCTAssertEqual(fact.role, .emptySelection); XCTAssertNil(fact.associatedGeneration)
                    XCTAssertEqual(fact.pitch, .known(linear ? .linear : .amigaVTX4x, nativePeriod: linear ? 3828 : 3388))
                    XCTAssertEqual(fact.relativeNote, 12); XCTAssertEqual(fact.finetune, 24); XCTAssertEqual(fact.baseRate, 8363)
                    XCTAssertEqual(fact.baseRateOrigin, .neutralDefault); XCTAssertEqual(fact.finetuneOrigin, .declaredEmptyHeader)
                    XCTAssertEqual(fact.cachedDefaultVolume, 40); XCTAssertEqual(fact.cachedDefaultPan, 128)
                    XCTAssertEqual(plan.xmEmptyRoutes.first?.scheduledFrame, (6 + delay) * unit)
                    XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: fact.absoluteFrame, plan: plan))
                    XCTAssertTrue(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: fact.absoluteFrame - 1, plan: plan))
                } else if instrument == 4 {
                    XCTAssertEqual(fact.role, .refusedDispatch); XCTAssertEqual(fact.associatedGeneration, 0)
                    XCTAssertEqual(fact.pitch, .known(linear ? .linear : .amigaVTX4x, nativePeriod: linear ? 3768 : 3208))
                    XCTAssertEqual(fact.baseRate, 16726); XCTAssertEqual(fact.relativeNote, 96); XCTAssertEqual(fact.finetune, 16)
                    XCTAssertEqual(fact.baseRateOrigin, .selectionFact(0)); XCTAssertEqual(fact.finetuneOrigin, .selectionFact(0))
                    XCTAssertEqual(fact.relativeNoteOrigin, .refusedRoute)
                } else {
                    XCTAssertEqual(fact.role, .trigger); XCTAssertEqual(fact.associatedGeneration, 1)
                    XCTAssertEqual(fact.pitch, .known(linear ? .linear : .amigaVTX4x, nativePeriod: linear ? 4608 : 6848))
                }
                XCTAssertEqual(plan.pattern.events.last?.scheduledStartFrame, 12 * unit)
                XCTAssertEqual(plan.pattern.events.last?.initialSourceFrame, 0)
                XCTAssertEqual(plan.pattern.events.count, instrument == 2 ? 3 : 2)
            }
            for note: UInt8 in [0, 49] {
                let song = selectionSong([cc(note: 49, instrument: 1, volume: 0xA4),
                    cc(14, UInt8(0xD0 + delay), note: note, instrument: 2, volume: 0xB8), cc()], linear: linear)
                let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
                let dispatch = plan.selectionDispatchFacts.facts.filter { $0.syntheticRow == 1 && $0.role != .carriedInstrument }
                XCTAssertEqual(dispatch.count, delay < 6 && (note != 0 || delay != 0) ? 1 : 0)
                if let fact = dispatch.first {
                    XCTAssertEqual(fact.tick, delay); XCTAssertEqual(fact.associatedGeneration, 1)
                    XCTAssertEqual(fact.role, note == 0 ? .retainedNoteRestart : .trigger)
                }
                if note == 0 {
                    let carried = try XCTUnwrap(plan.selectionDispatchFacts.facts.first { $0.syntheticRow == 1 && $0.role == .carriedInstrument })
                    XCTAssertEqual(carried.tick, 0); XCTAssertEqual(carried.carriedInstrument, 2)
                    XCTAssertEqual(carried.semanticInstrument, 1); XCTAssertEqual(carried.associatedGeneration, 0)
                }
                if delay == 3 {
                    let oldBirthWrites = plan.diagnostics.vibratoEffects.filter { $0.syntheticRow == 1 && $0.activeEventIndex == 0 }
                        .flatMap(\.stepUpdates).filter { $0.syntheticTick == 3 }
                    XCTAssertEqual(oldBirthWrites.count, note == 0 ? 1 : 0)
                    XCTAssertEqual(plan.diagnostics.vibratoEffects.contains { $0.syntheticRow == 1 && $0.supersededDelayedBirth != nil }, note != 0)
                }
            }
        } } }
    }

    func testNativeSelectionColdUnavailableQuietZeroAndTuningCarry() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            func facts(_ cells: [PlaybackCell]) -> [PlaybackSongSelectionDispatchFacts.Fact] {
                PlaybackSongSyntheticAdapter.adapt(selectionSong(cells, linear: linear), orderIndex: 0, sampleRate: rate).selectionDispatchFacts.facts
            }
            let cold = facts([cc(instrument: 1), cc(14, 0xD3, instrument: 2)])
            XCTAssertEqual(cold.map(\.role), [.carriedInstrument, .carriedInstrument, .coldDispatch])
            XCTAssertTrue(cold.allSatisfy { $0.pitch == .unavailable && $0.associatedGeneration == nil && $0.semanticInstrument == nil })
            XCTAssertEqual(cold.last?.absoluteFrame, 9 * Int(rate / 50)); XCTAssertNil(cold.last?.mappedSample)
            let absent = facts([cc(instrument: 5), cc(note: 50)])
            XCTAssertEqual(absent.last?.role, .unavailableRoute); XCTAssertEqual(absent.last?.pitch, .unavailable)
            XCTAssertNil(absent.last?.mappedSample); XCTAssertNil(absent.last?.associatedGeneration)
            let unavailable = facts([cc(note: 49, instrument: 5), cc(note: 50)])
            XCTAssertEqual(unavailable.first?.selectionMethod, .skippedNoValidSample)
            XCTAssertEqual(unavailable.first?.role, .unavailableRoute)
            XCTAssertNil(unavailable.first?.mappedSample)
            XCTAssertEqual(unavailable.last?.role, .unavailableRoute); XCTAssertNil(unavailable.last?.associatedGeneration)
            let missing = facts([cc(note: 49, instrument: 8)])
            XCTAssertEqual(missing.last?.mappedSample, 7); XCTAssertEqual(missing.last?.role, .unavailableRoute)
            XCTAssertEqual(missing.last?.pitch, .unavailable)
            let quiet = facts([cc(note: 49, instrument: 6)])
            XCTAssertEqual(quiet.first?.role, .trigger); XCTAssertEqual(quiet.first?.associatedGeneration, 0)
            XCTAssertEqual(quiet.first?.cachedDefaultVolume, 0)
            XCTAssertEqual(quiet.first?.pitch, .known(linear ? .linear : .amigaVTX4x, nativePeriod: linear ? 4608 : 6848))
            let zero = facts([cc(note: 49, instrument: 7)])
            XCTAssertEqual(zero.first?.pitch, .known(linear ? .linear : .amigaVTX4x, nativePeriod: 0))
            let tuned = facts([cc(14, 0x5C, note: 49, instrument: 1), cc(note: 49, instrument: 4), cc(note: 49)])
            XCTAssertEqual(tuned.first?.finetune, 64); XCTAssertEqual(tuned.first?.finetuneOrigin, .finetuneCommand)
            XCTAssertEqual(tuned.last?.finetune, 64); XCTAssertEqual(tuned.last?.finetuneOrigin, .selectionFact(0))
            XCTAssertEqual(tuned.last?.noteOnly, true); XCTAssertEqual(tuned.last?.associatedGeneration, 0)
            let refusedCold = facts([cc(note: 49, instrument: 4)])
            XCTAssertEqual(refusedCold.first?.pitch, .unavailable); XCTAssertEqual(refusedCold.first?.semanticInstrument, 4)
            XCTAssertEqual(refusedCold.first?.baseRateOrigin, .neutralDefault); XCTAssertEqual(refusedCold.first?.finetuneOrigin, .neutralDefault)
        } }
    }

    func testNativeSelectionSparseWorkDoesNotGrowWithVirtualBlankTicks() throws {
        for speed: UInt8 in [1, 6, 31] { for padding in [1, 64] {
            let sink = ClockProfileSink(), session = AdapterPlanProfileRecorder(isEnabled: true, sink: sink).beginLifecycle("selection_work")
            let song = clockSong([cc(note: 49, instrument: 1), cc(15, speed)] + Array(repeating: cc(), count: padding), linear: true)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100, profileSession: session)
            let facts = plan.selectionDispatchFacts.facts
            XCTAssertEqual(facts.count, 1); XCTAssertEqual(plan.canonicalTickClock.totalCanonicalTicks, 6 + (padding + 1) * Int(speed))
            XCTAssertTrue(sink.lines.contains { $0.contains("selection_fact_count=1") && $0.contains("selection_fact_storage_growth_count=1") &&
                $0.contains("empty_cell_bypass_count=\(padding)") && $0.contains("full_cell_dispatch_count=2") })
            print("SELECTION_LAYOUT facts=\(facts.count) stride=\(MemoryLayout<PlaybackSongSelectionDispatchFacts.Fact>.stride) logical_bytes=\(facts.count * MemoryLayout<PlaybackSongSelectionDispatchFacts.Fact>.stride) capacity=\(facts.capacity) growth_allocations=1 provenance_stride=24 extra_song_passes=0 extra_cell_dispatches=0 per_tick_objects=0")
            let blank = PlaybackSongSyntheticAdapter.adapt(clockSong(Array(repeating: cc(), count: padding), linear: true), orderIndex: 0, sampleRate: 100)
            XCTAssertTrue(blank.selectionDispatchFacts.facts.isEmpty)
        } }
    }

    func testNativeSelectionPhysicalBaseline() throws {
        // Policy B removes only the nil-map sentinel's legacy source. The other
        // mapped routes retain exact frozen event, PCM, timing and lifetime guards.
        // Ordinary ED admission restores the represented zero-volume header in the ED3 sentinel.
        // Pin its corrected gain/PCM; source, pitch, cursor and clock evidence stays exact.
        // Pin full output and the projection without retriggers independently.
        // The physical projection also contains gain; its corrected scalar is intentional.
        // Output interpolation contracts multiply-add on arm64; keep separate full-PCM
        // hashes and exact shared source/pitch/clock guards.
        #if arch(arm64)
        let expected = ["false-44100": "0c953b5e80cf419c1804de7675065a6ab50cd0a1549560d9e2e998ba21d9da1e",
            "false-48000": "e565423670c6073434e813aa3c5921899e8e2c236ef0b74fd0d57efc53e28f6e",
            "true-44100": "d7c47439054433a4c3da9ede30cc7bca2bed1897d219a7183268a8a94c451876",
            "true-48000": "5c0bce3e6e625fff3537fad56892b4bf50e544a3925b9fea568b10ab102a58a0"]
        #else
        let expected = ["false-44100": "b798183fbd78ae5a7d88b643544ca9cec2cc526d98286763806e2d8d39cf989e",
            "false-48000": "0f7097ff5f09be8ed75fb2ce4f74ea256ce915d5849ad15dc66096c837129f07",
            "true-44100": "3732e405c08797e1e9d8bc253a3354cbe3e8c81f4f3d5a094eaf5e419d433b18",
            "true-48000": "977f7b53f4cf60068bcbd7801746ccf550169bebc76b880084454f61d3027414"]
        #endif
        let expectedWithoutRetriggers = ["false-44100": "d0a7fdb5598025fac10219b905e0f3f139c48c75397859530dadeded791dd0c6",
            "false-48000": "ea7c2ea11cb7704b19cda2e047b8d805891e39d15a788bc54b67e2019ae8dbfb",
            "true-44100": "425730dc60c53faa0e3d7a6b5c7f681237247ef81d20624a377fcbe2f539fb07",
            "true-48000": "9f3989c0a016cfaefb53c43387026dc1e7bf6b04dd1919f71a44eaa4e3fdaba4"]
        let expectedPhysical = ["false-44100": "399c33cb362880aa581c2529ef2e78043bbfb7c0ee0168db3638542ce24a5ba6",
            "false-48000": "9ee749ce2bc6a164fb2e768c058ba39656c5735752b3c31c4eeb535bd6a4c896",
            "true-44100": "9466d31448cfe84f3e0e6f353ca30cd5c5b47bcc7710a2a5dd2c08dbb09e08dc",
            "true-48000": "bd0fe2bc0e03788ad4321830209615bdb2e67e625c7fbbaf95a4e94a9dad0635"]
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            var evidence = Data(), physical = Data(), unchanged = SHA256()
            for cells in clockSentinels + selectionSentinels {
                let evidenceStart = evidence.count
                let song = selectionSong(cells, linear: linear)
                let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, preparedPlan: plan)
                physical.append(protectedClockEvidence(plan, runtime: runtime))
                for value: Any in [runtime.events, runtime.eventStorage.ordering, plan.pattern, plan.diagnostics,
                    plan.xmChannelRows, plan.xmEmptyRoutes, plan.xmInstrumentSelections, plan.playbackStateEvents,
                    plan.noteOnlyEventIndices, plan.coldReleasedEventIndices, plan.initialHeldPitchEventIndices] {
                    evidence.append(Data(clockSnapshot(value).utf8))
                }
                let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), rows: cells.count)
                let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
                for pcm in [renderer.render(request).block.interleavedPCM,
                            renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM] {
                    pcm.withUnsafeBytes { evidence.append(contentsOf: $0) }
                }
                let windows = renderer.makeWindowedRenderScheduleIndex(for: plan, totalFrames: request.requestedFrameCount,
                    windowRows: 1, includedEventIndices: nil, config: request.config).windows
                evidence.append(Data(clockSnapshot(windows).utf8))
                let history = PlaybackSongOfflineRenderer.PitchSourceHistory(plan: plan)
                for i in plan.pattern.events.indices { for row in cells.indices { for delta in [-1, 0, 1] {
                    let frame = row * 6 * Int(rate / 50) + delta
                    let source = Data(clockSnapshot([history.advancedPosition(for: i, at: frame) as Any,
                        history.cutFrame(for: i) as Any,
                        PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: i, at: frame, plan: plan),
                        PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: i, at: frame, plan: plan, pitchHistory: history)]).utf8)
                    evidence.append(source); physical.append(source)
                } } }
                #if DEBUG
                XCTAssertEqual(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).block.interleavedPCM,
                    renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM)
                #endif
                if !plan.diagnostics.retriggerEffects.contains(where: { $0.applied && !$0.replacedEventIndices.isEmpty }) {
                    unchanged.update(data: evidence.subdata(in: evidenceStart..<evidence.count))
                }
            }
            let key = "\(linear)-\(Int(rate))"
            let digest = SHA256.hash(data: evidence).map { String(format: "%02x", $0) }.joined()
            print("NATIVE_SELECTION_BASELINE \(key) \(digest) bytes=\(evidence.count)")
            if let directory = ProcessInfo.processInfo.environment["VTX_SELECTION_EVIDENCE_DIR"] {
                try evidence.write(to: URL(fileURLWithPath: directory).appendingPathComponent("physical-\(key).bin"))
            }
            XCTAssertEqual(digest, expected[key])
            XCTAssertEqual(unchanged.finalize().map { String(format: "%02x", $0) }.joined(),
                expectedWithoutRetriggers[key])
            XCTAssertEqual(SHA256.hash(data: physical).map { String(format: "%02x", $0) }.joined(), expectedPhysical[key])
        } }
    }

    private var selectionSentinels: [[PlaybackCell]] {
        let birth = cc(note: 49, instrument: 1)
        return [[birth, cc(note: 50), cc(note: 51), cc(note: 49), cc(note: 49, instrument: 1)],
            [cc(instrument: 1), cc(14, 0xD3, instrument: 2), cc(note: 49, instrument: 3), cc(instrument: 2), cc(note: 49)],
            [cc(note: 49, instrument: 5), cc(note: 50), cc(note: 49, instrument: 6), cc(12, 64)],
            [birth, cc(note: 49, instrument: 8), cc(14, 0xD3, note: 49, instrument: 8), cc(note: 50)],
            [cc(note: 49, instrument: 7), cc(note: 49, instrument: 4)],
            [birth, cc(note: 49, instrument: 3), cc(note: 50, instrument: 1)]]
            + [0xD0, 0xD3, 0xD6].flatMap { delay in
                [2, 3, 4].map { [birth, cc(14, UInt8(delay), note: 49, instrument: UInt8($0), volume: 0xB8), cc(note: 50, instrument: 1)] }
            }
    }

    private func selectionSong(_ cells: [PlaybackCell], linear: Bool) -> PlaybackSong {
        let seed = clockSong(cells, linear: linear)
        var instruments = seed.instrumentsByIndex
        let samples = (0..<3).map { slot in
            PlaybackSample(instrumentIndex: 1, sampleIndex: slot,
                pcm: (0..<32_768).map { Float(($0 * (137 + slot * 26) + 731) % 16_384 - 8_192) / 32_768 },
                volume: 0.5, relativeNote: slot * 12, finetune: slot * 16, baseSampleRate: 8363 * Double(slot + 1))
        }
        var map = Array(repeating: 0, count: 96); map[49] = 1; map[50] = 2
        instruments[1] = .init(index: 1, samples: samples, noteSampleMap: map)
        instruments[8] = .init(index: 8, samples: [], noteSampleMap: Array(repeating: 7, count: 96))
        return .init(title: "Public selection controls", orders: seed.orders, patternsByIndex: seed.patternsByIndex,
            instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: seed.initialTiming, usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: seed.xmSampleSlotProvenanceByInstrument)
    }

    func testCanonicalClockPhysicalBaseline() throws {
        // Policy B removes only the nil-map sentinel's legacy source. The other
        // mapped routes retain exact frozen event, PCM, timing and lifetime guards.
        // Ordinary ED admission restores the represented zero-volume header in the ED3 sentinel.
        // Pin its corrected gain/PCM; source, pitch, cursor and clock evidence stays exact.
        // Full output, the projection without retriggers and the physical projection
        // independently pin the corrected gain and unchanged source/pitch/clock state.
        // Keep the same architecture-specific interpolation hashes as the selection guard.
        #if arch(arm64)
        let expected = ["false44100": "c5a8e56aec5381d657fd9fc521683830ab646dab88b23723332249934c1683e6",
            "false48000": "c5b3e03dede71edfbe9d2f04b5c82d416cd3e77beb692fce9f04125b75ab641d",
            "true44100": "21136ef6fb6ac08f8e53d2d7ea6176058842d1a8c3adc962d0090698d3267eed",
            "true48000": "d3012314d47565e54321b13fd58b869f45f6e29dfdc7e25a95345233f1f18cc6"]
        #else
        let expected = ["false44100": "e2edce54500dec7b04a9f67b133a9fe42137ad3d4a2ab36f1d0021d7a69c21ad",
            "false48000": "ea2db6efccb14f5793ef7404f4afa70a168cdcf3d83f48f01975dd9812369bec",
            "true44100": "0cd538a402246882a49884e3137509284332cd5d4cecd4c730a13f49422b9b40",
            "true48000": "e156d85d79d8e345b4a8434eab49c1065f1334f8f159c653935a0355d1296c9b"]
        #endif
        let expectedWithoutRetriggers = ["false44100": "bed40b1a6233215ce28decf3084c0ff54880ca81ff53449befaf88682659a810",
            "false48000": "2210d7586cf29bdeb8a9de10d54d6ce3a361758438966bbb60021c48c69526a0",
            "true44100": "455cb52abe4cedfe174ff9d695ffb1aeccd9d5161a4f0fe7d4a45e8e6c242a2a",
            "true48000": "982a5dab7401718ab19e595b6ab1783789c8b50180430a982f49d3b83be79b82"]
        let expectedPhysical = ["false44100": "70f3b04fafa8464f72bc5f77db27798a7f84ce233f5c834d8b562b0dea2bb48a",
            "false48000": "c05cc415d1c9384dd345fbd871050868881d250b49ed6cf60b2313e05fc37c61",
            "true44100": "26347da711e953dd22279063427f8dae52e3e8971169a63d32e416ba30218da8",
            "true48000": "d37f821a73f191fd4027f137cd210afbfd3487d1e60efabcbac84c40c2cea58e"]
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            var evidence = Data(), physical = Data(), unchanged = SHA256()
            for cells in clockSentinels {
                let evidenceStart = evidence.count
                let song = clockSong(cells, linear: linear)
                let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, preparedPlan: plan)
                physical.append(protectedClockEvidence(plan, runtime: runtime))
                let clock = plan.canonicalTickClock
                XCTAssertEqual(clock.runs.count, cells.count)
                XCTAssertEqual(clock.totalCanonicalTicks, cells.count * 6)
                for row in cells.indices { for tick in 0..<6 {
                    let coordinate = try XCTUnwrap(clock.coordinate(syntheticRow: row, tick: tick, channel: 0))
                    XCTAssertEqual(coordinate.canonicalTickOrdinal, row * 6 + tick)
                    XCTAssertEqual(coordinate.absoluteFrame, (row * 6 + tick) * (rate == 48_000 ? 960 : 882))
                } }
                // Freeze all ordered payloads, IDs, categories, sources and diagnostics, independently of clock data.
                evidence.append(Data(clockSnapshot(runtime.events).utf8))
                evidence.append(Data(clockSnapshot(runtime.eventStorage.ordering).utf8))
                evidence.append(Data(clockSnapshot(plan.diagnostics).utf8))
                let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), rows: cells.count)
                let pcm = PlaybackSongOfflineRenderer(preparedPlan: plan).render(request).block.interleavedPCM
                pcm.withUnsafeBytes { evidence.append(contentsOf: $0) }
                if !plan.diagnostics.retriggerEffects.contains(where: { $0.applied && !$0.replacedEventIndices.isEmpty }) {
                    unchanged.update(data: evidence.subdata(in: evidenceStart..<evidence.count))
                }
            }
            XCTAssertEqual(SHA256.hash(data: evidence).map { String(format: "%02x", $0) }.joined(), expected["\(linear)\(Int(rate))"])
            XCTAssertEqual(unchanged.finalize().map { String(format: "%02x", $0) }.joined(),
                expectedWithoutRetriggers["\(linear)\(Int(rate))"])
            XCTAssertEqual(SHA256.hash(data: physical).map { String(format: "%02x", $0) }.joined(), expectedPhysical["\(linear)\(Int(rate))"])
        } }
    }

    func testCanonicalClockFxxFramesAndNoWriterRows() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let rows = [[cc(), cc()], [cc(15, 3), cc(15, 1)], [cc(15, 1), cc(15, 3)],
                [cc(15, 6), cc(15, 150)], [cc(15, 125), cc(15, 255)], [cc(15, 125), cc(15, 0)], []]
            let song = PlaybackSong(title: "Public Fxx clock", orders: [.init(orderIndex: 0, patternIndex: 0)],
                patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
                instrumentsByIndex: [:], restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate), clock = plan.canonicalTickClock
            let frames = rate == 48_000
                ? [[0,960,1920,2880,3840,4800], [5760], [6720,7680,8640], [9600,10400,11200,12000,12800,13600],
                   [14400,14870,15341,15811,16282,16752], [17223,18183,19143,20103,21063,22023]]
                : [[0,882,1764,2646,3528,4410], [5292], [6174,7056,7938], [8820,9555,10290,11025,11760,12495],
                   [13230,13662,14094,14527,14959,15391], [15824,16706,17588,18470,19352,20234]]
            XCTAssertEqual(clock.runs.map(\.firstCanonicalTickOrdinal), [0,6,7,10,16,22,28])
            XCTAssertEqual(clock.runs.map(\.timingRowIndex), Array(0..<7))
            XCTAssertEqual(clock.totalCanonicalTicks, 34)
            XCTAssertEqual(clock.rowTiming.map(\.effectiveSpeed), [6,1,3,6,6,6,6])
            let timing = PlaybackSongFxxTimingPlanner.plan(song, startOrderIndex: 0, orderCount: 1, sampleRate: rate)
            for (row, ticks) in frames.enumerated() { for (tick, frame) in ticks.enumerated() { for channel in 0..<2 {
                let value = try XCTUnwrap(clock.coordinate(syntheticRow: row, tick: tick, channel: channel))
                XCTAssertEqual(value, clock.coordinate(syntheticRow: row, tick: tick, channel: channel))
                XCTAssertEqual(value.absoluteFrame, frame)
                XCTAssertEqual(value.absoluteFrame, timing.frameFor(row: row, tick: tick))
                XCTAssertEqual(value.syntheticRow, row); XCTAssertEqual(value.tick, tick); XCTAssertEqual(value.channel, channel)
            } } }
            for (row, tick, channel) in [(-1,0,0), (7,0,0), (0,-1,0), (1,1,0), (0,6,0), (0,0,-1), (0,0,2), (6,0,0), (Int.max,0,0)] {
                XCTAssertNil(clock.coordinate(syntheticRow: row, tick: tick, channel: channel))
            }
            XCTAssertTrue(plan.pattern.events.isEmpty)
            XCTAssertTrue(RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, preparedPlan: plan).events.isEmpty)
            let sink = ClockProfileSink(), session = AdapterPlanProfileRecorder(isEnabled: true, sink: sink).beginLifecycle("test")
            let blank = PlaybackSongSyntheticAdapter.adapt(clockSong([cc(), cc(), cc()], linear: linear),
                orderIndex: 0, sampleRate: rate, profileSession: session)
            XCTAssertEqual(blank.canonicalTickClock.totalCanonicalTicks, 18)
            XCTAssertTrue(sink.lines.contains { $0.contains("empty_cell_bypass_count=3") && $0.contains("full_cell_dispatch_count=0") })
        } }
    }

    func testCanonicalClockNonzeroStartLoopsAndJumpsHaveNoPrerollOrExitTick() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let patterns = [[cc(15,1)], [cc(14,0x60), cc(14,0x61), cc(15,3)], [cc(11,4)]]
            let song = PlaybackSong(title: "Public traversal clock",
                orders: [0,1,1,2].enumerated().map { .init(orderIndex: $0.offset, patternIndex: $0.element) },
                patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.enumerated().map { i, cells in
                    (i, .init(index: i, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })) }),
                instrumentsByIndex: [:], restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 1, orderCount: 3, sampleRate: rate)
            let clock = plan.canonicalTickClock
            XCTAssertEqual(plan.diagnostics.rowMappings.map { $0.source.rowIndex }, [0,1,0,1,2,0,1,0,1,2,0])
            XCTAssertEqual(plan.diagnostics.rowMappings.map { $0.source.orderIndex }, [1,1,1,1,1,2,2,2,2,2,3])
            XCTAssertEqual(clock.runs.map(\.firstCanonicalTickOrdinal), [0,6,12,18,24,27,30,33,36,39,42])
            XCTAssertEqual(clock.totalCanonicalTicks, 45)
            for (row, run) in clock.runs.enumerated() {
                XCTAssertEqual(clock.coordinate(syntheticRow: row, tick: 0, channel: 0)?.absoluteFrame,
                    run.firstCanonicalTickOrdinal * (rate == 48_000 ? 960 : 882))
                XCTAssertNil(clock.coordinate(syntheticRow: row, tick: clock.rowTiming[row].effectiveSpeed, channel: 0))
            }
            XCTAssertNil(clock.coordinate(syntheticRow: 11, tick: 0, channel: 0))
        } }
    }

    private final class ClockProfileSink: AdapterPlanProfileSinking {
        var lines = [String]()
        func writeAdapterPlanProfileLine(_ line: String) { lines.append(line) }
    }

    func testCanonicalClockMissingMappedDestinationRetainsSourceIdentity() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let seed = clockSong([cc(note: 49, instrument: 1), cc(14, 0xD3, note: 49, instrument: 8), cc()], linear: linear)
            var instruments = seed.instrumentsByIndex
            instruments[8] = .init(index: 8, samples: [], noteSampleMap: Array(repeating: 1, count: 96))
            let song = PlaybackSong(title: seed.title, orders: seed.orders, patternsByIndex: seed.patternsByIndex,
                instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: seed.initialTiming, usesLinearFrequencyTable: linear)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.count, 1); XCTAssertEqual(plan.pattern.events.first?.row, 0)
            XCTAssertTrue(plan.xmEmptyRoutes.isEmpty) // Missing metadata is distinct from the represented empty header sentinel.
            XCTAssertEqual(plan.canonicalTickClock.totalCanonicalTicks, 18)
            XCTAssertEqual(plan.canonicalTickClock.coordinate(syntheticRow: 1, tick: 3, channel: 0)?.absoluteFrame,
                rate == 48_000 ? 8640 : 7938)
        } }
    }

    /// Pins existing payloads/IDs and source state separately from newly admitted output targets.
    private func protectedClockEvidence(_ plan: PlaybackSongSyntheticPlan,
                                        runtime: RuntimeCMixerAdapterEventPlan) -> Data {
        let physical = runtime.events.filter { if case .audibleTargetUpdate = $0.action { return false }; return true }
        let ordering = runtime.eventStorage.ordering.compactMap { entry -> [Int]? in
            if case .audibleTargetUpdate = runtime.events[entry.eventIndex].action { return nil }
            // New targets shift array offsets; the original ID/frame/priority remains authority.
            return [entry.eventID, entry.scheduledFrame, entry.priority]
        }
        var result = Data()
        for value: Any in [physical, ordering, plan.diagnostics, plan.pattern, plan.xmChannelRows,
            plan.xmEmptyRoutes, plan.xmInstrumentSelections, plan.playbackStateEvents,
            plan.noteOnlyEventIndices, plan.coldReleasedEventIndices, plan.initialHeldPitchEventIndices] {
            result.append(Data(clockSnapshot(value).utf8))
        }
        return result
    }

    private func clockSnapshot(_ value: Any) -> String {
        if let action = value as? RuntimeCMixerAdapterEventAction,
           case let .sourceStop(index, retireSong) = action {
            XCTAssertFalse(retireSong) // These historical sentinels contain no 9xx attempt.
            return "sourceStop:activeEventIndex:\(clockSnapshot(index))"
        }
        let mirror = Mirror(reflecting: value)
        if mirror.children.isEmpty { return String(describing: value) }
        // Keep the historical field stream/hashes exact; pin added neutral effect state separately.
        if let controls = value as? PlaybackSongSyntheticAdapter.ChannelState {
            XCTAssertEqual(controls.panningSlideMemory, 0)
            XCTAssertEqual(controls.tremorMemory, 0)
            XCTAssertEqual(controls.tremorPhase, 0)
            XCTAssertFalse(controls.glissandoEnabled)
        }
        if let step = value as? PlaybackSongSyntheticTonePortamentoStepUpdate {
            XCTAssertNil(step.glissandoFinetune)
        }
        if let timing = value as? PlaybackSongSyntheticRowTimingDiagnostic {
            XCTAssertEqual(timing.patternDelayCycles, 0)
        }
        if let route = value as? PlaybackXMEmptyRoute { XCTAssertFalse(route.retiresSource) }
        let fields = mirror.children.filter { !(value is PlaybackSongSyntheticAdapter.ChannelState &&
            ($0.label == "panningSlideMemory" || $0.label == "tremorMemory" || $0.label == "tremorPhase" || $0.label == "glissandoEnabled")) &&
            !(value is PlaybackSongSyntheticTonePortamentoStepUpdate && $0.label == "glissandoFinetune") &&
            !(value is PlaybackSongSyntheticRowTimingDiagnostic && $0.label == "patternDelayCycles") &&
            !(value is PlaybackXMEmptyRoute && $0.label == "retiresSource") }
            .map { "\($0.label ?? "_"):\(clockSnapshot($0.value))" }
        // Coverage diagnostics contain dictionaries; iteration order is deliberately not evidence.
        return (mirror.displayStyle == .dictionary || mirror.displayStyle == .set ? fields.sorted() : fields).joined(separator: "|")
    }

    private func cc(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                    instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private var clockSentinels: [[PlaybackCell]] {
        let birth = cc(note: 49, instrument: 1, volume: 0xA4)
        return [[birth, cc(4, 0x48, volume: 0xB8), cc()],
            [birth, cc(3, 4, note: 53), cc(1, 3), cc(2, 2), cc(14, 0x11), cc(14, 0x21),
             cc(33, 0x11), cc(0, 0x37), cc(4, 0x21), cc(4, 0x56, volume: 0xB3), cc(6, 2), cc(14, 0x44), cc()],
            [birth, cc(14, 0xD3, instrument: 2, volume: 0xB8), cc()],
            [birth, cc(14, 0x44), cc(14, 0x93), cc(14, 0x90), cc(27, 0x93), cc()],
            [cc(14, 0x11, note: 49, instrument: 1), cc(33, 0x11, note: 53, instrument: 1)],
            [cc(note: 49, instrument: 7), cc(14, 0x11), cc()],
            [birth, cc(0, 0x37), cc(4, 0x48, volume: 0xB8), cc()],
            [cc(4, 0x48, note: 49, instrument: 1), cc(note: 49, instrument: 2), cc()]]
            + [0xD0, 0xD3, 0xD6].map { [birth, cc(14, UInt8($0), note: 49, instrument: 2, volume: 0xB8), cc()] }
            + [3, 4, 5, 6, 99].map { [birth, cc(14, 0xD3, note: 49, instrument: UInt8($0), volume: 0xB8), cc()] }
    }

    private func clockSong(_ cells: [PlaybackCell], linear: Bool) -> PlaybackSong {
        // Instruments 3...7 distinguish empty, refused, nil-map unavailable, quiet PCM and zero pitch.
        var instruments = [Int: PlaybackInstrument]()
        for i in 1...7 where i != 3 {
            let sample = PlaybackSample(instrumentIndex: i, sampleIndex: 0,
                pcm: (0..<32_768).map { Float(($0 * 137 + 731) % 16_384 - 8_192) / 32_768 },
                volume: i == 6 ? 0 : 0.5, relativeNote: i == 4 ? 96 : i == 7 ? -49 : 0,
                finetune: 0, baseSampleRate: 8363)
            instruments[i] = .init(index: i, samples: [sample], noteSampleMap: i == 5 ? nil : Array(repeating: 0, count: 96))
        }
        instruments[3] = .init(index: 3, samples: [], noteSampleMap: Array(repeating: 0, count: 96))
        return .init(title: "Public clock sentinels", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: 40, panning: 128, finetune: 24, relativeNote: 12)]])
    }

    func testParsedFixtureMixedTimingControlsBoundedAndWindowedRenders() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("reference-xm/generated/fxx-timing.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixture.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixture.path)
        let rows = try XCTUnwrap(song.patternsByIndex[0]).rows
        XCTAssertEqual(rows.map { $0.cells[0].effectParam },
                       [0, 3, 0, 150, 0, 6, 125, 31, 32, 255, 3, 32, 3, 0, 6, 0])
        XCTAssertEqual(rows.map { $0.cells[1].effectParam },
                       [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 125, 150, 0, 0, 0])
        XCTAssertTrue(rows.flatMap(\.cells).allSatisfy { $0.effectType == 0 || $0.effectType == 0x0F })
        let plan = PlaybackSongFxxTimingPlanner.plan(song, startOrderIndex: 0, orderCount: 1, sampleRate: 48_000)
        let starts = [0, 5_760, 8_640, 11_520, 13_920, 16_320, 21_120, 26_880,
                      56_640, 172_890, 187_478, 190_301, 196_061, 198_461, 200_861, 205_661]
        XCTAssertEqual(plan.rowTimings.map(\.rowStartFrame), starts)
        XCTAssertEqual(plan.rowTimings.map(\.effectiveSpeed), [6, 3, 3, 3, 3, 6, 6, 31, 31, 31, 6, 6, 3, 3, 6, 6])
        XCTAssertEqual(plan.rowTimings.map(\.effectiveBPM), [125, 125, 125, 150, 150, 150, 125, 125, 32, 255, 255, 125, 150, 150, 150, 150])
        let conflicts = plan.timingChanges.filter { (10...12).contains($0.source.rowIndex) }
        XCTAssertEqual(conflicts.map(\.channelIndex), [0, 1, 0, 1, 0, 1])
        XCTAssertEqual(conflicts.map(\.appliesToSyntheticRowAfter), [10, 10, 11, 11, 12, 12])
        let request = PlaybackSongOfflineRenderRequest(
            song: song, config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2), rows: 16
        )
        XCTAssertEqual(request.requestedFrameCount, 210_461)
        let renderer = PlaybackSongOfflineRenderer()
        let bounded = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 3)
        XCTAssertEqual(bounded.diagnostics.rowTiming, plan.rowTimingDiagnostics)
        XCTAssertEqual(bounded.plan.pattern.events.map(\.scheduledStartFrame), starts.map(Optional.some))
        XCTAssertEqual(bounded.block.interleavedPCM.count, 210_461 * 2)
        XCTAssertTrue(bounded.block.interleavedPCM.contains { $0 != 0 })
        XCTAssertEqual(windowed.block.interleavedPCM, bounded.block.interleavedPCM)
    }

    func testSpeedAppliesToCommandRowAndFollowingRows() {
        for speed in [3, 6, 31] {
            let plan = timingPlan(parameter: UInt8(speed), initialSpeed: 4, initialBPM: 125)
            XCTAssertEqual(plan.rowTimings.map(\.effectiveSpeed), [4, speed, speed, speed, speed])
            XCTAssertEqual(plan.rowTimings.map(\.effectiveBPM), [125, 125, 125, 125, 125])
            XCTAssertEqual(plan.rowTimings.map(\.rowStartFrame),
                           [0, 3_840, 3_840 + speed * 960, 3_840 + speed * 1_920, 3_840 + speed * 2_880])
            XCTAssertEqual(plan.rowTimings[1].rowDurationFrames, speed * 960)
            XCTAssertEqual(plan.frameFor(row: 1, tick: 1), 4_800)
            XCTAssertEqual(plan.frameFor(row: 1, tick: speed - 1), 3_840 + (speed - 1) * 960)
            XCTAssertEqual(plan.frameFor(row: 1, tick: speed), plan.frameFor(row: 1, tick: speed - 1))
            XCTAssertEqual(plan.timingChanges.first?.appliesToSyntheticRowAfter, 1)
        }
    }

    func testBPMStartsAtTickZeroOfCommandRowWithoutAccumulatedBoundaryDrift() {
        let cases: [(UInt8, [Int], Int, Int)] = [
            (0x20, [0, 1_440, 12_690, 23_940, 35_190], 5_190, 46_440),
            (0x7D, [0, 1_440, 4_320, 7_200, 10_080], 2_400, 12_960),
            (0x96, [0, 1_440, 3_840, 6_240, 8_640], 2_240, 11_040),
            (0xFF, [0, 1_440, 2_851, 4_263, 5_675], 1_910, 7_087),
        ]
        for (bpm, starts, firstTick, end) in cases {
            let plan = timingPlan(parameter: bpm, initialSpeed: 3, initialBPM: 250)
            XCTAssertEqual(plan.frameFor(row: 0, tick: 1), 480)
            XCTAssertEqual(plan.rowTimings.map(\.rowStartFrame), starts)
            XCTAssertEqual(plan.rowTimings.map(\.effectiveSpeed), [3, 3, 3, 3, 3])
            XCTAssertEqual(plan.rowTimings.map(\.effectiveBPM), [250] + Array(repeating: Int(bpm), count: 4))
            XCTAssertEqual(plan.frameFor(row: 1, tick: 1), firstTick)
            XCTAssertEqual(plan.frameFor(row: 5), end)
            XCTAssertEqual(plan.rowTimings[1].rowEndExactFrame - plan.rowTimings[1].rowStartExactFrame,
                           3 * 120_000 / Double(bpm), accuracy: 1e-9)
        }
    }

    private func timingPlan(parameter: UInt8, initialSpeed: Int, initialBPM: Int) -> PlaybackSongFxxTimingPlan {
        let rows = (0..<5).map { row in
            PlaybackRow(index: row, cells: [PlaybackCell(
                note: 0, instrument: 0, volumeColumn: 0,
                effectType: row == 1 ? 0x0F : 0, effectParam: row == 1 ? parameter : 0
            )])
        }
        let song = PlaybackSong(
            title: "Fxx boundaries", orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: rows)], instrumentsByIndex: [:],
            restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: PlaybackTiming(speed: initialSpeed, bpm: initialBPM)
        )
        return PlaybackSongFxxTimingPlanner.plan(song, startOrderIndex: 0, orderCount: 1, sampleRate: 48_000)
    }
}
