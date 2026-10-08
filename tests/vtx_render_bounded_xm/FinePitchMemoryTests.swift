import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class FinePitchMemoryTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testReferenceVectorsAndIndependentDirectionalChannelProvenance() {
        for (parameters, periods): ([UInt8], [Double]) in [
            ([0x11, 0x10], [4608, 4604, 4600]), ([0x21, 0x20], [4608, 4612, 4616]),
            ([0x13, 0x24, 0x10, 0x20], [4608, 4596, 4612, 4600, 4616])
        ] {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1), c(note: 49, instrument: 1)]] +
                parameters.map { [c(14, $0), c(14, $0 & 0xF0)] }))
            XCTAssertEqual(states.map { $0[0].activeLinearPeriod }, periods.map(Optional.some))
            XCTAssertEqual(states.map { $0[1].activeLinearPeriod }, Array(repeating: 4608, count: periods.count))
            XCTAssertTrue(states.allSatisfy { $0[1].finePitchUpMemory == nil && $0[1].finePitchDownMemory == nil })
            for execution in executions(context).filter(\.effectMemoryReused) {
                XCTAssertEqual(execution.memoryOrigin?.channelIndex, 0)
                XCTAssertEqual(execution.memoryValue, Int(execution.memoryOrigin!.effectParam & 15))
            }
            XCTAssertEqual(context.finePortamentoUpEffects.filter { $0.fineAmountNibble == 0 && $0.channelIndex == 0 }.first?.execution.memoryOrigin?.source.rowIndex, parameters.first! >> 4 == 1 ? 1 : nil)
        }
    }

    func testTickZeroAtAllSpeedsWithEarlierLaterSameRowFxxAndBPM() {
        for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] {
                for fxxChannel in [-1, 0, 1] {
                    for (seed, zero, delta): (UInt8, UInt8, Double) in [(0x13, 0x10, -12), (0x24, 0x20, 16)] {
                        let channel = fxxChannel == 0 ? 1 : 0
                        var rows = Array(repeating: [c(), c()], count: 3)
                        rows[0][channel] = c(note: 49, instrument: 1)
                        rows[1][channel] = c(14, seed); rows[2][channel] = c(14, zero)
                        if fxxChannel >= 0 { rows[1][fxxChannel] = c(15, UInt8(speed)) }
                        let (context, states) = inspect(song(rows, speed: fxxChannel < 0 ? speed : 6), rate)
                        let updates = steps(context).sorted { $0.scheduledFrame < $1.scheduledFrame }
                        XCTAssertEqual(updates.map(\.syntheticTick), [0, 0])
                        let first = fxxChannel < 0 ? speed : 6
                        XCTAssertEqual(updates.map(\.scheduledFrame), [first, first + speed].map { $0 * Int(rate / 50) })
                        XCTAssertEqual(states.map { $0[channel].activeLinearPeriod }, [4608, 4608 + delta, 4608 + 2 * delta])
                    }
                }
            }
            for channel in [0, 1] {
                var rows = Array(repeating: [c(), c()], count: 3)
                rows[0][channel] = c(note: 49, instrument: 1)
                rows[1][channel] = c(14, 0x13); rows[1][1 - channel] = c(15, 250)
                rows[2][channel] = c(14, 0x10)
                XCTAssertEqual(steps(inspect(song(rows), rate).0).map(\.scheduledFrame), [6, 9].map { $0 * Int(rate / 50) })
            }
        }
    }

    func testColdRestoresHeldColumnVibratoWithoutChangingMemoryPhaseOrControl() throws {
        for rate in [44_100.0, 48_000] {
            for zero: UInt8 in [0x10, 0x20] {
                for control: UInt8 in [0, 6] {
                    let module = song([[c(14, 0x40 | control, note: 49, instrument: 1, volume: 0xA4)],
                        [c(volume: 0xB8)], [c(14, zero)], [c(volume: 0xB0)], [c(14, zero)]])
                    let (context, states) = inspect(module, rate)
                    for row in [2, 4] {
                        let before = states[row - 1][0], after = states[row][0]
                        XCTAssertEqual(after.activeLinearPeriod, before.activeLinearPeriod)
                        XCTAssertEqual(after.activePlaybackStep, step(4608, rate))
                        XCTAssertNil(after.vibratoOutputLinearPeriod)
                        XCTAssertEqual(after.vibratoSpeed, before.vibratoSpeed); XCTAssertEqual(after.vibratoDepth, before.vibratoDepth)
                        XCTAssertEqual(after.vibratoPhase, before.vibratoPhase); XCTAssertEqual(after.vibratoControl, before.vibratoControl)
                        XCTAssertEqual(after.vibratoSpeedMemorySource, before.vibratoSpeedMemorySource)
                        XCTAssertEqual(after.vibratoDepthMemorySource, before.vibratoDepthMemorySource)
                    }
                    XCTAssertEqual(states[2][0].vibratoPhase, 80); XCTAssertEqual(states[3][0].vibratoPhase, 160)
                    XCTAssertTrue(executions(context).allSatisfy { $0.cold && $0.memoryOrigin == nil && $0.memoryValue == nil && !$0.effectMemoryReused })
                    if control == 0 {
                        XCTAssertEqual(states[1][0].vibratoOutputLinearPeriod, 4671)
                        XCTAssertEqual(context.vibratoEffects.last?.stepUpdates.map(\.linearPeriodAfter), [4666, 4653, 4632, 4608, 4584])
                    }
                    let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: rate)
                    let fine = plan.diagnostics.finePortamentoUpEffects.map(\.execution) + plan.diagnostics.finePortamentoDownEffects.map(\.execution)
                    XCTAssertTrue(fine.allSatisfy { $0.canonicalPitchValid && $0.sourceEligible && $0.publicationRequested && $0.publicationSuppressionReason == nil })
                }
            }
        }
    }

    func testColdRestoresCurrentRegularPortamentoBaseAndConvergedTargetsDeduplicate() {
        for zero: UInt8 in [0x10, 0x20] {
            let (context, states) = inspect(song([[c(note: 49, instrument: 1, volume: 0xA4)], [c(1, 4)],
                [c(volume: 0xB8)], [], [c(14, zero)], [c(14, zero)]]))
            XCTAssertEqual(states[3][0].activeLinearPeriod, 4528)
            XCTAssertEqual(states[3][0].vibratoOutputLinearPeriod, 4591)
            XCTAssertEqual(states[4][0].activeLinearPeriod, 4528)
            XCTAssertEqual(states[4][0].activePlaybackStep, step(4528, 48000))
            XCTAssertEqual(steps(context).count, 1)
            XCTAssertEqual(executions(context).last?.publicationSuppressionReason, "held_pitch_converged")
            for writer in [c(), c(4, 0x48), c(6)] {
                let (current, _) = inspect(song([[c(note: 49, instrument: 1)], [writer], [c(14, zero)], [c(14, zero)]]))
                XCTAssertTrue(steps(current).isEmpty)
                XCTAssertTrue(executions(current).allSatisfy { $0.publicationRequested && $0.publicationSuppressionReason == "held_pitch_converged" })
            }
        }
    }

    func testLaterFineWriteCoalescesOnlyThePriorRowsVibratoExit() {
        for (seed, zero, expected): (UInt8, UInt8, Double) in [(0x13, 0x10, 4584), (0x24, 0x20, 4640)] {
            for writer in [c(4, 0x48), c(6, volume: 0xB8)] {
                for parameter in [seed, zero] {
                    let module = song([[c(14, seed, note: 49, instrument: 1, volume: 0xA4)], [writer], [c(14, parameter)]])
                    let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: 48000)
                    let fine = plan.diagnostics.finePortamentoUpEffects.map(\.execution) + plan.diagnostics.finePortamentoDownEffects.map(\.execution)
                    XCTAssertTrue(fine.last!.coalescedVibratoExit)
                    XCTAssertEqual(fine.last?.outputLinearPeriodAfter, expected)
                    XCTAssertFalse(plan.diagnostics.vibratoEffects.flatMap(\.stepUpdates).contains { $0.scheduledFrame == 11520 })
                }
            }
        }
    }

    func testRegularToneExtraFineAndModulationMemoriesDoNotCrossSeed() {
        for other in [c(1, 5), c(2, 6), c(3, 7, note: 53), c(4, 0x48), c(6), c(volume: 0xB8), c(33, 0x13), c(33, 0x24)] {
            let (_, states) = inspect(song([[c(note: 49, instrument: 1)], [c(14, 0x13)], [c(14, 0x24)], [other], [c(14, 0x10)], [c(14, 0x20)]]))
            XCTAssertEqual(states[4][0].activeLinearPeriod, states[3][0].activeLinearPeriod! - 12)
            XCTAssertEqual(states[5][0].activeLinearPeriod, states[4][0].activeLinearPeriod! + 16)
            for state in states.dropFirst(3).map({ $0[0] }) {
                XCTAssertEqual(state.finePitchUpMemory?.amount, 3); XCTAssertEqual(state.finePitchDownMemory?.amount, 4)
                XCTAssertEqual(state.finePitchUpMemory?.source.source.rowIndex, 1)
                XCTAssertEqual(state.finePitchDownMemory?.source.source.rowIndex, 2)
            }
            XCTAssertEqual(states[5][0].portamentoUpMemory, states[3][0].portamentoUpMemory)
            XCTAssertEqual(states[5][0].portamentoDownMemory, states[3][0].portamentoDownMemory)
            XCTAssertEqual(states[5][0].tonePortamentoSpeed, states[3][0].tonePortamentoSpeed)
            let (_, cold) = inspect(song([[c(note: 49, instrument: 1)], [other], [c(14, 0x10)], [c(14, 0x20)]]))
            XCTAssertTrue(cold.allSatisfy { $0[0].finePitchUpMemory == nil && $0[0].finePitchDownMemory == nil })
        }
        for (seed, zero): (UInt8, UInt8) in [(0x13, 0x10), (0x24, 0x20)] {
            let (context, _) = inspect(song([[c(note: 49, instrument: 1)], [c(14, seed)], [c(33, zero)]]))
            XCTAssertEqual(context.extraFinePortamentoEffects.first?.status, .zeroAmountEffectMemoryDeferred)
        }
    }

    func testMemoryCarriesAcrossNotesInstrumentsKeyOffOrdersAndFreshPlannerResets() {
        for (seed, zero): (UInt8, UInt8) in [(0x13, 0x10), (0x24, 0x20)] {
            for seeded in [false, true] {
                for boundary in [c(note: 51, instrument: 2), c(note: 51), c(instrument: 2), c(note: 97), c()] {
                    func module(_ parameter: UInt8) -> PlaybackSong {
                        song([[c(note: 49, instrument: 1)], [seeded ? c(14, seed) : c()],
                            [c(14, parameter, note: boundary.note, instrument: boundary.instrument)], [], [c(14, zero)]], split: 2)
                    }
                    let (context, states) = inspect(module(zero)), explicit = inspect(module(seeded ? seed : zero)).1
                    XCTAssertEqual(states[2][0].activeLinearPeriod, explicit[2][0].activeLinearPeriod)
                    XCTAssertEqual(context.events.count, (1...96).contains(boundary.note) ? 2 : 1)
                    for state in states.dropFirst(2).map({ $0[0] }) {
                        XCTAssertEqual(state.finePitchUpMemory, states[1][0].finePitchUpMemory)
                        XCTAssertEqual(state.finePitchDownMemory, states[1][0].finePitchDownMemory)
                    }
                    XCTAssertEqual(executions(context).last?.effectMemoryReused, seeded)
                }
            }
            let (fresh, _) = inspect(song([[c(14, zero, note: 49, instrument: 1)]]))
            XCTAssertEqual(fresh.events.count, 1); XCTAssertEqual(fresh.events[0].playbackStep, step(4608, 48000))
            XCTAssertTrue(steps(fresh).isEmpty); XCTAssertTrue(executions(fresh).allSatisfy { $0.cold && $0.memoryOrigin == nil })
        }
    }

    func testSameCellInitialPitchFoldsNonzeroReplayAndColdExactlyOnce() {
        for (seed, zero, delta): (UInt8, UInt8, Double) in [(0x11, 0x10, -4), (0x21, 0x20, 4)] {
            for parameter in [seed, zero] {
                for seeded in [false, true] {
                    let (context, _) = inspect(song([[seeded ? c(14, seed) : c()], [c(14, parameter, note: 49, instrument: 1)]]))
                    XCTAssertEqual(context.events.count, 1); XCTAssertTrue(steps(context).isEmpty)
                    XCTAssertEqual(context.events[0].playbackStep, step(4608 + (parameter == seed || seeded ? delta : 0), 48000))
                    let execution = executions(context).last!
                    XCTAssertEqual(execution.publicationSuppressionReason, "folded_into_trigger")
                    XCTAssertEqual(execution.effectMemoryReused, parameter == zero && seeded)
                }
            }
        }
    }

    func testColdUninitializedAndCompletedOrCanonicalEmptyRoutesNeverInventSources() throws {
        for rate in [44_100.0, 48_000] {
            for zero: UInt8 in [0x10, 0x20] {
                let (cold, states) = inspect(song([[c(14, zero)], [c(14, zero)]]), rate)
                XCTAssertTrue(cold.events.isEmpty); XCTAssertTrue(steps(cold).isEmpty)
                XCTAssertTrue(states.allSatisfy { $0[0].activeLinearPeriod == nil && $0[0].activePlaybackStep == nil && $0[0].finePitchUpMemory == nil && $0[0].finePitchDownMemory == nil })
                XCTAssertTrue(executions(cold).allSatisfy { !$0.canonicalPitchValid && !$0.publicationRequested && !$0.sourceEligible && $0.memoryOrigin == nil })
                for route in [1, 2] {
                    let module = song([[c(note: route == 1 ? 49 : 50, instrument: 1, volume: 0xA4)],
                        [c(volume: 0xB8)], [c(14, zero)], [c(note: 49, instrument: 1)]], completed: route == 1, canonicalEmpty: true)
                    let result = PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate, channelCount: 1), rows: 4))
                    let executions = result.diagnostics.finePortamentoUpEffects.map(\.execution) + result.diagnostics.finePortamentoDownEffects.map(\.execution)
                    XCTAssertTrue(executions.allSatisfy { $0.canonicalPitchValid && $0.publicationRequested && !$0.sourceEligible && $0.publicationSuppressionReason == "no_active_source" && $0.memoryOrigin == nil })
                    XCTAssertTrue(result.diagnostics.finePortamentoUpEffects.flatMap(\.stepUpdates).isEmpty)
                    XCTAssertTrue(result.diagnostics.finePortamentoDownEffects.flatMap(\.stepUpdates).isEmpty)
                    let rowFrames = 6 * Int(rate / 50)
                    XCTAssertTrue(result.block.interleavedPCM[rowFrames..<(3 * rowFrames)].allSatisfy { $0 == 0 })
                    XCTAssertEqual(result.plan.pattern.events.last?.playbackStep, step(4608, rate))
                }
            }
        }
    }

    func testParentClampsReplayAndColdZeroNeverClampsValidOrUninitializedPeriods() {
        for (seed, zero, period, boundary): (UInt8, UInt8, Double, Double) in [
            (0x1F, 0x10, Adapter.xmLinearMinimumSafePeriod + 2, Adapter.xmLinearMinimumSafePeriod),
            (0x2F, 0x20, Adapter.xmLinearMaximumSafePeriod - 2, Adapter.xmLinearMaximumSafePeriod)
        ] {
            let (context, states) = inspect(song([[c(14, seed)], [c(14, zero)], [c(14, zero)]]), initial: represented(period))
            XCTAssertEqual(states.map { $0[0].activeLinearPeriod }, Array(repeating: boundary, count: 3))
            XCTAssertEqual(steps(context).count, 1)
            XCTAssertEqual(executions(context).last?.publicationSuppressionReason, "held_pitch_converged")
        }
        for zero: UInt8 in [0x10, 0x20] {
            for period in [0.0, 1, 31999] {
                let (context, states) = inspect(song([[c(14, zero)]]), initial: represented(period))
                XCTAssertEqual(states[0][0].activeLinearPeriod, period)
                XCTAssertTrue(steps(context).isEmpty)
                XCTAssertTrue(executions(context).allSatisfy { $0.memoryOrigin == nil })
                XCTAssertTrue(context.finePortamentoUpEffects.allSatisfy { !$0.clamped })
                XCTAssertTrue(context.finePortamentoDownEffects.allSatisfy { !$0.clamped })
            }
        }
    }

    func testAmigaFinePitchGuardAndG29RemainUnchanged() {
        for parameter: UInt8 in [0x13, 0x10, 0x24, 0x20] {
            for sameCell in [false, true] {
                let (context, states) = inspect(song([[c(note: 49, instrument: 1)],
                    [c(14, parameter, note: sameCell ? 49 : 0, instrument: sameCell ? 1 : 0)]], linear: false))
                XCTAssertTrue(steps(context).isEmpty)
                XCTAssertTrue(states.allSatisfy { $0[0].finePitchUpMemory == nil && $0[0].finePitchDownMemory == nil })
                XCTAssertTrue(context.finePortamentoUpEffects.allSatisfy { $0.status == .unsupportedFrequencyTable })
                XCTAssertTrue(context.finePortamentoDownEffects.allSatisfy { $0.status == .unsupportedFrequencyTable })
                XCTAssertTrue(executions(context).allSatisfy { !$0.usesLinearFrequencyTable && !$0.publicationRequested })
            }
        }
    }

    func testPublicFixtureDiagnosticsAndWholeWindowRuntimePlanParity() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/fine-pitch-directional-memory.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module, orderCount: 2, config: .init(sampleRate: rate, channelCount: 2), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let full = PlaybackSongOfflineRenderer().render(request)
            XCTAssertEqual(runtime.plan, full.plan)
            for window in [1, 3, 12] { assertPCM(full.block.interleavedPCM, PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: window).block.interleavedPCM) }
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let fine = try XCTUnwrap(json["fine_portamento_up_effects"] as? [[String: Any]]) + XCTUnwrap(json["fine_portamento_down_effects"] as? [[String: Any]])
            XCTAssertTrue(fine.contains { $0["cold"] as? Bool == true && $0["source_eligible"] as? Bool == true && $0["step_update_count"] as? Int == 1 })
            XCTAssertTrue(fine.contains { $0["effect_memory_reused"] as? Bool == true && $0["fine_amount_nibble"] as? Int == 0 && $0["fine_amount"] as? Int == 3 })
            XCTAssertTrue(fine.filter { $0["cold"] as? Bool == true }.allSatisfy { $0["fine_memory_origin"] is NSNull && $0["memory_source"] is NSNull })
        }
    }

    private func executions(_ context: Adapter.AdapterRowContext) -> [PlaybackSongSyntheticFinePitchExecution] {
        context.finePortamentoUpEffects.map(\.execution) + context.finePortamentoDownEffects.map(\.execution)
    }
    private func steps(_ context: Adapter.AdapterRowContext) -> [PlaybackSongSyntheticTonePortamentoStepUpdate] {
        context.finePortamentoUpEffects.flatMap(\.stepUpdates) + context.finePortamentoDownEffects.flatMap(\.stepUpdates)
    }
    private func step(_ period: Double, _ rate: Double) -> Double { Adapter.playbackStep(linearPeriod: period, baseSampleRate: 8363, outputSampleRate: rate)! }
    private func represented(_ period: Double) -> Adapter.ChannelState {
        var state = Adapter.ChannelState()
        state.activeEventIndex = 0; state.semanticInstrumentIndex = 1; state.semanticSampleIndex = 0
        state.activeLinearPeriod = period; state.activePlaybackStep = step(period, 48000)
        state.activeSampleBaseSampleRate = 8363; state.activeUsesLinearFrequencyTable = true
        return state
    }
    private func assertPCM(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0, 1e-7, file: file, line: line)
    }
    private func inspect(_ song: PlaybackSong, _ rate: Double = 48000, initial: Adapter.ChannelState? = nil) -> (Adapter.AdapterRowContext, [[Adapter.ChannelState]]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: song.orders.count)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: rate)
        var context = Adapter.AdapterRowContext(), states = [[Adapter.ChannelState]]()
        if let initial { context.channelStates = [initial, Adapter.ChannelState()] }
        for (index, row) in traversal.rows.enumerated() {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: index + 1 < traversal.rows.count ? traversal.rows[index + 1].row : nil, context: &context)
            states.append(context.channelStates)
        }
        return (context, states)
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, base: Int = 32, linear: Bool = true, envelope: Bool = false, completed: Bool = false, canonicalEmpty: Bool = false, split: Int? = nil) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1 / 32, count: completed ? 32 : 256),
            volume: Float(base) / 64, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
            loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
        let empty = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [], volume: 0, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        let alternate = PlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: sample.pcm, volume: 0.75,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: sample.pcm.count, loopType: 1)
        let env = PlaybackVolumeEnvelope(enabled: envelope, points: envelope ? [.init(tick: 0, value: 32), .init(tick: 64, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: envelope ? 1024 : 0)
        var map = Array(repeating: 0, count: 96); map[49] = 1
        let chunks = split.map { [Array(rows[..<$0]), Array(rows[$0...])] } ?? [rows]
        let patterns = chunks.enumerated().map { index, chunk in
            PlaybackPattern(index: index, rows: chunk.enumerated().map { .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 2 - $0.element.count)) })
        }
        return .init(title: "Public fine pitch memory", orders: patterns.map { .init(orderIndex: $0.index, patternIndex: $0.index) },
            patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.map { ($0.index, $0) }),
            instrumentsByIndex: [1: .init(index: 1, samples: [sample, empty], volumeEnvelope: env, noteSampleMap: map),
                                 2: .init(index: 2, samples: [alternate], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: canonicalEmpty, volume: 0, panning: 0, finetune: 0, relativeNote: 0)]])
    }
}
