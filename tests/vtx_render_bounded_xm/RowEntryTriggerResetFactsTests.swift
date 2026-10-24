import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original public cells pin actual calls, prior source identities and scalar reset ordering.
final class RowEntryTriggerResetFactsTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias E = PlaybackSongRowEntryTriggerResetFacts
    private let rates = [44_100.0, 48_000]
    private var birth: PlaybackCell { c(note: 49, instrument: 1) }

    func testLiteralGateSeparatesBirthReleaseDelayAndInstrumentControl() throws {
        let cases: [(PlaybackCell, Bool)] = [(c(note: 53), false), (c(), false),
            (c(note: 53, instrument: 99), false), (c(14, 0xD3, note: 53, instrument: 2), false),
            (c(14, 0xD3, instrument: 2), false), (c(20, instrument: 2), false),
            (c(20, instrument: 2, volume: 0xF1), true), (c(note: 97, instrument: 2), false),
            (c(20, note: 97, instrument: 2), false), (c(20, 0x21, instrument: 2), true),
            (c(instrument: 2), true), (c(14, 0xD0, note: 53, instrument: 2), true)]
        for linear in [true, false] { for rate in rates { for (cell, admitted) in cases {
            let input = song([[birth], [c(4, 0x48)], [c(7, 0x48)], [cell]], linear: linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let calls = try observations(plan)
            XCTAssertEqual(plan.rowEntryTriggerResetFacts.coverage, .partialOrdinaryRowEntryV1)
            XCTAssertEqual(calls.map(\.syntheticRow), admitted ? [0, 3] : [0], "\(cell)")
            XCTAssertNil(calls[0].priorSourceEventIndex)
            XCTAssertEqual(calls[0].before, calls[0].after) // A real already-zero invocation.
            if admitted {
                let call = calls[1]
                XCTAssertEqual(call.rowCell, cell); XCTAssertEqual(call.requestedInstrumentIndex, 2)
                XCTAssertEqual(call.priorSourceEventIndex, 0); XCTAssertEqual(call.syntheticTick, 0)
                XCTAssertEqual(call.before.vibratoPhase, 80); XCTAssertEqual(call.after.vibratoPhase, 0)
                XCTAssertEqual(call.before.tremoloPhase, 80); XCTAssertEqual(call.after.tremoloPhase, 0)
                XCTAssertEqual(call.scheduledFrame, rate == 48_000 ? 17_280 : 15_876)
                XCTAssertEqual(call.cause, .existingOrdinaryRowEntryInstrumentTriggerEffectPhaseGate)
            }
        } } }
    }

    func testMappedBirthsLateUnavailableAndEarlyRefusalKeepCausalGenerations() throws {
        for linear in [true, false] { for rate in rates {
            let input = song([[birth], [c(note: 53)], [c(note: 53, instrument: 2)], [c(instrument: 1)],
                [c(note: 49, instrument: 4)], [c(note: 49, instrument: 5)],
                [c(note: 49, instrument: 3)], [c(instrument: 1)]], linear: linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate), calls = try observations(plan)
            XCTAssertEqual(calls.map(\.syntheticRow), [0, 2, 3, 4, 6, 7])
            XCTAssertEqual(calls.map(\.requestedInstrumentIndex), [1, 2, 1, 4, 3, 1])
            XCTAssertEqual(calls.map(\.priorSourceEventIndex), [nil, 1, 2, 2, nil, nil])
            XCTAssertEqual(plan.pattern.events.count, 3)
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 1, 0])
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), [1, 1, 2])
            let retained = try XCTUnwrap(plan.xmChannelRows.first { $0.syntheticRow == 3 && $0.channelIndex == 0 })
            XCTAssertEqual(retained.controls.carriedInstrumentIndex, 1)
            XCTAssertEqual(retained.controls.activeInstrumentIndex, 2)
            XCTAssertEqual(retained.controls.activeEventIndex, 2)
            XCTAssertTrue(plan.selectionDispatchFacts.facts.contains { $0.syntheticRow == 5 && $0.role == .refusedDispatch })
            // Empty dispatch clears association before this hook; that absence is literal.
            XCTAssertTrue(plan.xmEmptyRoutes.contains { $0.source.rowIndex == 6 && $0.stoppedEventIndex == 2 })
        } }
    }

    func testColdEmptyAndCompletedSourcesDoNotInventPCMOrEraseRealInvocations() throws {
        for linear in [true, false] { for rate in rates {
            for rows in [[[c(instrument: 1)]], [[c(note: 49, instrument: 3)], [c(instrument: 1)]]] {
                let plan = A.adapt(song(rows, linear: linear), orderIndex: 0, sampleRate: rate)
                XCTAssertTrue(plan.pattern.events.isEmpty)
                XCTAssertTrue(try observations(plan).allSatisfy { $0.priorSourceEventIndex == nil })
                XCTAssertEqual(plan.rowEntryTriggerResetFacts.facts.count, rows.count)
            }
            let plan = A.adapt(song([[birth], [c(instrument: 2)]], linear: linear, completed: true), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(try observations(plan).map(\.priorSourceEventIndex), [nil, 0])
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: 6 * Int(rate / 50), plan: plan))
        } }
    }

    func testScalarSuppressionUsesPriorControlsAndRecordsRCountEvenWithoutNumericChange() throws {
        let input = song([[birth]])
        for flag: Bool? in [nil, false, true] { for tremolo in [false, true] { for linked in [false, true] {
            for control: UInt8 in [0x44, 0x74] {
                var state = A.ChannelState(), observer = E.Observer()
                var updates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
                state.activeEventIndex = 23; state.vibratoPhase = 76; state.tremolo.phase = 84
                state.tremoloVibratoPhase = 92; state.rRetriggerCounter = 7
                state.vibratoControl = flag.map { .init(controlValue: $0 ? 4 : 0, waveform: .sine, retriggerSuppressed: $0, source: nil) }
                state.tremolo.control = tremolo ? 4 : 0; state.tremoloVibratoControl = linked ? 4 : 0
                A.prepareTremoloRow(cell: c(14, control, instrument: 2), song: input,
                    source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), channelIndex: 0,
                    syntheticRow: 0, scheduledFrame: 0, globalVolume: 64, initializesInstrumentVolume: true,
                    channelState: &state, updates: &updates, observer: &observer)
                let call = try XCTUnwrap(observer.evidence.facts.first)
                XCTAssertEqual(observer.evidence.facts.count, 1); XCTAssertEqual(call.priorSourceEventIndex, 23)
                XCTAssertEqual(call.before.vibratoPhase, 76); XCTAssertEqual(call.after.vibratoPhase, flag == true ? 76 : 0)
                XCTAssertEqual(call.before.vibratoRetriggerSuppressed, flag)
                XCTAssertEqual(call.after.vibratoRetriggerSuppressed, flag)
                XCTAssertEqual(call.before.tremoloPhase, 84); XCTAssertEqual(call.after.tremoloPhase, tremolo ? 84 : 0)
                XCTAssertEqual(call.before.tremoloRetriggerSuppressed, tremolo)
                XCTAssertEqual(call.after.tremoloRetriggerSuppressed, tremolo)
                XCTAssertEqual(call.before.tremoloVibratoPhase, 92); XCTAssertEqual(call.after.tremoloVibratoPhase, linked ? 92 : 0)
                XCTAssertEqual(call.before.tremoloVibratoRetriggerSuppressed, linked)
                XCTAssertEqual(call.after.tremoloVibratoRetriggerSuppressed, linked)
                XCTAssertEqual(call.before.rRetriggerCounter, 7); XCTAssertEqual(call.after.rRetriggerCounter, 0)
                if control == 0x44 { XCTAssertEqual(state.tremoloVibratoControl, 4) }
                else { XCTAssertEqual(state.tremolo.control, 4) }
            }
        } } }
    }

    func testE90E9AndRxyCaptureOnlyTheirOrdinaryEntryCall() throws {
        for linear in [true, false] { for rate in rates {
            for effect in [c(14, 0x90), c(14, 0x93), c(27, 0x02)] { for instrument: UInt8 in [0, 2] {
                let cell = c(effect.effectType, effect.effectParam, instrument: instrument)
                let plan = A.adapt(song([[birth], [cell]], linear: linear), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(try observations(plan).map(\.syntheticRow), instrument == 0 ? [0] : [0, 1])
                XCTAssertGreaterThan(plan.pattern.events.count, 1)
                XCTAssertTrue(try observations(plan).allSatisfy { $0.syntheticTick == 0 })
            } }
        } }
    }

    func testActualPriorAndSameCellE4E7ControlWritesRemainDistinct() throws {
        for linear in [true, false] { for rate in rates {
            let retained = A.adapt(song([[birth], [c(14, 0x44)], [c(4, 0x47)], [c(14, 0x74)],
                [c(7, 0x48)], [c(instrument: 2)]], linear: linear), orderIndex: 0, sampleRate: rate)
            let prior = try XCTUnwrap(try observations(retained).last)
            XCTAssertEqual([prior.before.vibratoPhase, prior.before.tremoloPhase, prior.before.tremoloVibratoPhase], [80, 80, 80])
            XCTAssertEqual(prior.before, prior.after)
            XCTAssertEqual(prior.before.vibratoRetriggerSuppressed, true)
            XCTAssertTrue(prior.before.tremoloRetriggerSuppressed && prior.before.tremoloVibratoRetriggerSuppressed)
            for (writer, setter) in [(c(4, 0x47), c(14, 0x44, instrument: 2)), (c(7, 0x48), c(14, 0x74, instrument: 2))] {
                let plan = A.adapt(song([[birth], [writer], [setter]], linear: linear), orderIndex: 0, sampleRate: rate)
                let call = try XCTUnwrap(try observations(plan).last)
                let controls = try XCTUnwrap(plan.xmChannelRows.first { $0.syntheticRow == 2 && $0.channelIndex == 0 }).controls
                if setter.effectParam == 0x44 {
                    XCTAssertEqual(call.before.vibratoPhase, 80); XCTAssertEqual(call.before.tremoloVibratoPhase, 80)
                    XCTAssertNil(call.before.vibratoRetriggerSuppressed); XCTAssertFalse(call.before.tremoloVibratoRetriggerSuppressed)
                    XCTAssertEqual(call.after.vibratoPhase, 0); XCTAssertEqual(call.after.tremoloVibratoPhase, 0)
                    XCTAssertEqual(controls.vibratoControl?.retriggerSuppressed, true)
                } else {
                    XCTAssertEqual(call.before.tremoloPhase, 80); XCTAssertFalse(call.before.tremoloRetriggerSuppressed)
                    XCTAssertEqual(call.after.tremoloPhase, 0); XCTAssertEqual(controls.tremolo.control, 4)
                }
            }
        } }
    }

    func testFxxInEitherChannelAndRepeatedOrdersUseRealTickZeroFrames() throws {
        for linear in [true, false] { for rate in rates { for fChannel in [0, 1] {
            var speed = [c(instrument: 2), c(instrument: 2)], tempo = [c(instrument: 1), c(instrument: 1)]
            speed[fChannel] = c(15, 3, instrument: 2); tempo[1 - fChannel] = c(15, 137, instrument: 1)
            let input = song([[birth, birth], speed, tempo, [c(instrument: 2), c(instrument: 2)]], linear: linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate), calls = try observations(plan)
            let frames = [0, 6 * Int(rate / 50), 9 * Int(rate / 50), Int((rate * (9.0 / 50 + 7.5 / 137)).rounded(.down))]
            XCTAssertEqual(calls.map(\.scheduledFrame), frames.flatMap { [$0, $0] })
            XCTAssertEqual(calls.map(\.channelIndex), [0, 1, 0, 1, 0, 1, 0, 1])
            XCTAssertEqual(calls.map(\.priorSourceEventIndex), [nil, nil, 0, 1, 0, 1, 0, 1])
            XCTAssertEqual(plan.rowEntryTriggerResetFacts, A.adapt(input, orderIndex: 0, sampleRate: rate).rowEntryTriggerResetFacts)
            let repeated = A.adapt(song([[birth]], linear: linear, repeated: true), orderRange: 0..<2, sampleRate: rate)
            let repetitions = try observations(repeated)
            XCTAssertEqual(repetitions.map(\.source), [.init(orderIndex: 0, patternIndex: 0, rowIndex: 0), .init(orderIndex: 1, patternIndex: 0, rowIndex: 0)])
            XCTAssertEqual(repetitions.map(\.syntheticRow), [0, 1]); XCTAssertEqual(repetitions.map(\.priorSourceEventIndex), [nil, 0])
            XCTAssertEqual(repetitions.map(\.scheduledFrame), [0, 6 * Int(rate / 50)])
            let loop = A.adapt(song([[c(14, 0x60)], [birth], [c(14, 0x61)]], linear: linear), orderIndex: 0, sampleRate: rate)
            let occurrences = try observations(loop)
            XCTAssertEqual(occurrences.map(\.source), Array(repeating: .init(orderIndex: 0, patternIndex: 0, rowIndex: 1), count: 2))
            XCTAssertEqual(occurrences.map(\.syntheticRow), [1, 4])
            XCTAssertEqual(occurrences.map(\.priorSourceEventIndex), [nil, 0])
            XCTAssertEqual(occurrences.map(\.scheduledFrame), [6, 24].map { $0 * Int(rate / 50) })
        } } }
    }

    func testSharedPreparedCopiesInvalidationAndBounds() throws {
        let input = song([[birth], [c(4, 0x48)], [c(instrument: 2)]])
        let plan = A.adapt(input, orderIndex: 0, sampleRate: 48_000)
        let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: 48_000), rows: 3)
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        var copies = [plan, plan.replacingEventCoverage(plan.diagnostics.eventCoverage),
            PlaybackSongOfflineRenderer.plan(plan, mutingEventsNotIn: []), plan.extendingEnvelopeTail(throughFrame: 50_000),
            renderer.render(request).plan, renderer.renderWindowed(request, windowRows: 1).plan]
        #if DEBUG
        copies.append(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).plan)
        #endif
        for _ in 0..<2 { copies.append(try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000, preparedPlan: plan).plan)) }
        for copy in copies {
            XCTAssertEqual(copy.rowEntryTriggerResetFacts, plan.rowEntryTriggerResetFacts)
            XCTAssertEqual(try observations(copy), try observations(plan))
            plan.rowEntryTriggerResetFacts.facts.withUnsafeBufferPointer { original in
                copy.rowEntryTriggerResetFacts.facts.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
            }
        }
        for index in [-1, Int.min, Int.max, plan.rowEntryTriggerResetFacts.facts.count] { XCTAssertNil(plan.rowEntryTriggerReset(at: index)) }
        let first = try XCTUnwrap(plan.rowEntryTriggerReset(at: 0))
        var malformed = plan
        malformed.rowEntryTriggerResetFacts = .init(coverage: .partialOrdinaryRowEntryV1,
            facts: [.init(source: first.source, syntheticRow: first.syntheticRow, channelIndex: first.channelIndex,
                scheduledFrame: first.scheduledFrame + 1, priorSourceEventIndex: first.priorSourceEventIndex,
                before: first.before, after: first.after, rowCell: first.rowCell)], storageGrowthCount: 1)
        XCTAssertNil(malformed.rowEntryTriggerReset(at: 0))
        var changed = plan
        changed.diagnostics.vibratoEffects.removeAll()
        XCTAssertEqual(changed.rowEntryTriggerResetFacts.coverage, .notAdapterProduced)
        XCTAssertEqual(changed.heldPitchProvenance.coverage, .notAdapterProduced)
        XCTAssertEqual(changed.nativePitchWriterSpans.coverage, .notAdapterProduced)
        XCTAssertEqual(changed.g23ChildlessPitchInvocations.coverage, .notAdapterProduced)
        XCTAssertEqual(changed.rowExitProvenance.coverage, .notAdapterProduced)
        XCTAssertNil(changed.rowEntryTriggerReset(at: 0))
        let manual = PlaybackSongSyntheticPlan(timingConfig: plan.timingConfig, pattern: plan.pattern,
            diagnostics: plan.diagnostics, canonicalTickClock: plan.canonicalTickClock, selectionDispatchFacts: plan.selectionDispatchFacts)
        XCTAssertEqual(manual.rowEntryTriggerResetFacts.coverage, .notAdapterProduced)
        XCTAssertNil(manual.rowEntryTriggerReset(at: 0))
    }

    private func observations(_ plan: PlaybackSongSyntheticPlan) throws -> [E.Fact] {
        try plan.rowEntryTriggerResetFacts.facts.indices.map { try XCTUnwrap(plan.rowEntryTriggerReset(at: $0)) }
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ rows: [[PlaybackCell]], linear: Bool = true, completed: Bool = false, repeated: Bool = false) -> PlaybackSong {
        func sample(_ instrument: Int, _ slot: Int = 0, relative: Int = 0) -> PlaybackSample {
            .init(instrumentIndex: instrument, sampleIndex: slot, pcm: slot == 0 ? [0.125, -0.375, 0.25, -0.0625] : [-0.5, 0.25, 0.125, -0.25],
                volume: 0.5, relativeNote: relative, finetune: 0, baseSampleRate: 8363,
                loopLength: completed ? 0 : 4, loopType: completed ? 0 : 1)
        }
        var map = Array(repeating: 0, count: 96); map[52] = 1
        let pattern = PlaybackPattern(index: 0, rows: rows.enumerated().map { .init(index: $0.offset,
            cells: $0.element + Array(repeating: c(), count: max(0, 2 - $0.element.count))) })
        return .init(title: "Public row-entry reset provenance", orders: (0..<(repeated ? 2 : 1)).map { .init(orderIndex: $0, patternIndex: 0) },
            patternsByIndex: [0: pattern], instrumentsByIndex: [1: .init(index: 1, samples: [sample(1), sample(1, 1)], noteSampleMap: map),
                2: .init(index: 2, samples: [sample(2)], noteSampleMap: Array(repeating: 0, count: 96)),
                3: .init(index: 3, samples: [], noteSampleMap: Array(repeating: 0, count: 96)),
                4: .init(index: 4, samples: [sample(4)], noteSampleMap: Array(repeating: 9, count: 96)),
                5: .init(index: 5, samples: [sample(5, relative: 96)], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: true, volume: 0, panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
