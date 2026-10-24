import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Public cells pin real delayed reset calls independently of trigger admission and PCM lifetime.
final class DelayedInstrumentResetFactsTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias E = PlaybackSongDelayedInstrumentResetFacts
    private let rates = [44_100.0, 48_000]
    private var birth: PlaybackCell { c(note: 49, instrument: 1) }
    private var delayed: PlaybackCell { c(14, 0xD3, instrument: 2) }

    func testLiteralInvocationsSeparatePriorNewEmptyCompletedReleasedAndColdSources() throws {
        for linear in [true, false] { for rate in rates {
            let cases: [([PlaybackCell], PlaybackCell, Bool, Int?, Int?, Int)] = [
                ([birth], delayed, false, 0, 1, 2), ([c()], delayed, false, nil, nil, 0),
                ([birth], c(14, 0xD3, instrument: 3), false, 0, nil, 1),
                ([birth], c(14, 0xD3, instrument: 4), false, 0, nil, 1),
                ([birth], delayed, true, 0, 1, 2), ([birth, c(note: 97)], delayed, false, 0, 1, 2),
                ([c(note: 49, instrument: 3)], delayed, false, nil, 0, 1)]
            for (initial, target, completed, prior, next, eventCount) in cases {
                let input = song((initial + [target]).map { [$0] }, linear: linear, completed: completed)
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate), calls = try observations(plan)
                XCTAssertEqual(plan.delayedInstrumentResetFacts.coverage, .partialInRowInstrumentOnlyEDxV1)
                XCTAssertEqual(calls.count, 1)
                let call = try XCTUnwrap(calls.first)
                XCTAssertEqual(call.source, .init(orderIndex: 0, patternIndex: 0, rowIndex: initial.count))
                XCTAssertEqual(call.syntheticRow, initial.count); XCTAssertEqual(call.syntheticTick, 3)
                XCTAssertEqual(call.channelIndex, 0); XCTAssertEqual(call.requestedInstrumentIndex, Int(target.instrument))
                XCTAssertEqual(call.scheduledFrame, (initial.count * 6 + 3) * Int(rate / 50))
                XCTAssertEqual(call.priorSourceEventIndex, prior); XCTAssertEqual(call.newSourceEventIndex, next)
                XCTAssertEqual(call.cause, .existingInRowInstrumentOnlyEDxEffectPhaseResetGate)
                XCTAssertEqual(call.before, call.after) // Already-zero is an actual invocation.
                XCTAssertEqual(plan.pattern.events.count, eventCount)
                if let next {
                    XCTAssertEqual(plan.pattern.events[next].scheduledStartFrame, call.scheduledFrame)
                    XCTAssertEqual(plan.pattern.events[next].sample.monoPCM, [-0.5, 0.25, 0.125, -0.25])
                    XCTAssertEqual(plan.diagnostics.eventMappings.last?.instrumentIndex, 2)
                }
                if completed { XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: call.scheduledFrame, plan: plan)) }
                if target.instrument == 3 || target.instrument == 4 {
                    XCTAssertEqual(plan.xmEmptyRoutes.last?.stoppedEventIndex, 0)
                    XCTAssertNil(plan.selectionDispatchFacts.facts.last?.associatedGeneration)
                }
                XCTAssertEqual(plan.delayedInstrumentResetFacts, A.adapt(input, orderIndex: 0, sampleRate: rate).delayedInstrumentResetFacts)
            }
        } }
    }

    func testNegativeDispatchesNeverSynthesizeAResetFact() throws {
        let negatives = [c(14, 0xD0, instrument: 2), c(14, 0xD6, instrument: 2), c(14, 0xDF, instrument: 2),
            c(14, 0xD3, instrument: 99), c(14, 0xD3, note: 53, instrument: 2), c(14, 0xD3, note: 53),
            c(note: 53), c(), c(14, 0x93, instrument: 2), c(14, 0x90, instrument: 2), c(27, 0x02, instrument: 2),
            c(20, instrument: 2), c(20, 3, instrument: 2), c(note: 97, instrument: 2), c(instrument: 2),
            c(note: 49, instrument: 5), c(14, 0xD3, note: 49, instrument: 5)]
        for linear in [true, false] { for rate in rates { for cell in negatives {
            let plan = A.adapt(song([[birth], [cell]], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.delayedInstrumentResetFacts.coverage, .partialInRowInstrumentOnlyEDxV1)
            XCTAssertTrue(plan.delayedInstrumentResetFacts.facts.isEmpty, "\(cell)")
            XCTAssertNil(plan.delayedInstrumentReset(at: 0))
        } } }
    }

    func testEffectiveFxxSpeedChannelOrderingAndFractionalBPMUseActualDelayedClock() throws {
        for linear in [true, false] { for rate in rates { for speed in [1, 3, 6] { for targetTick in [1, 3, 15] {
            for fChannel in [0, 1] {
                var first = [birth, birth], row = [c(14, UInt8(0xD0 + targetTick), instrument: 2), c()]
                row.swapAt(0, 1 - fChannel); row[fChannel] = c(15, UInt8(speed)); first[fChannel] = c()
                let plan = A.adapt(song([first, row], linear: linear), orderIndex: 0, sampleRate: rate)
                let calls = try observations(plan)
                XCTAssertEqual(calls.count, targetTick < speed ? 1 : 0)
                if let call = calls.first {
                    XCTAssertEqual(call.syntheticTick, targetTick); XCTAssertEqual(call.channelIndex, 1 - fChannel)
                    XCTAssertEqual(call.scheduledFrame, (6 + targetTick) * Int(rate / 50))
                }
                let initial = A.adapt(song([[birth], [row[1 - fChannel]]], linear: linear, speed: speed), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(initial.delayedInstrumentResetFacts.facts.map(\.scheduledFrame), targetTick < speed ? [(speed + targetTick) * Int(rate / 50)] : [])
            }
        } } } }
        for linear in [true, false] { for rate in rates { for fChannel in [0, 1] {
            var row = [delayed, delayed]; row[fChannel] = c(15, 127)
            let plan = A.adapt(song([[birth, birth], row], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(try observations(plan).map(\.scheduledFrame), [rate == 48_000 ? 8594 : 7896])
        } } }
        for linear in [true, false] { for rate in rates { for tick in 1...15 {
            let plan = A.adapt(song([[birth], [c(14, UInt8(0xD0 + tick), instrument: 2)]], linear: linear, speed: 31), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(try observations(plan).map(\.syntheticTick), [tick])
            XCTAssertEqual(try observations(plan).map(\.scheduledFrame), [(31 + tick) * Int(rate / 50)])
        } } }
        let ordered = A.adapt(song([[birth, birth], [delayed, delayed]]), orderIndex: 0, sampleRate: 48_000)
        XCTAssertEqual(try observations(ordered).map(\.channelIndex), [0, 1])
        XCTAssertEqual(try observations(ordered).map(\.priorSourceEventIndex), [0, 1])
        XCTAssertEqual(try observations(ordered).map(\.newSourceEventIndex), [2, 3])
    }

    func testIncomingBxAndColumnSlidesRunBeforeResetAndG23ChildlessFactsRemainExact() throws {
        for linear in [true, false] { for rate in rates {
            let bx = A.adapt(song([[birth], [c(4, 0x48)], [c(14, 0xD3, instrument: 2, volume: 0xB8)]], linear: linear), orderIndex: 0, sampleRate: rate)
            let reset = try XCTUnwrap(bx.delayedInstrumentReset(at: 0))
            XCTAssertEqual(reset.before.vibratoPhase, 128); XCTAssertEqual(reset.after.vibratoPhase, 0)
            let writers = bx.diagnostics.vibratoEffects.filter { $0.syntheticRow == 2 }
            XCTAssertEqual(writers.map(\.phaseBefore), [80, 96, 112, 0, 16])
            XCTAssertEqual(writers.map(\.phaseAfter), [96, 112, 128, 16, 32])
            XCTAssertEqual(writers.map(\.activeEventIndex), [0, 0, 0, 1, 1])
            let volume = A.adapt(song([[birth], [c(14, 0xD3, instrument: 2, volume: 0x61)]], linear: linear), orderIndex: 0, sampleRate: rate)
            let slides = volume.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 1 && $0.commandSource == .volumeColumn }
            XCTAssertEqual(slides.map(\.syntheticTick), [1, 2, 3, 4, 5])
            XCTAssertEqual(slides.map(\.effectiveVolumeAfter), [31, 30, 29, 47, 46])
            XCTAssertEqual(volume.diagnostics.eventMappings.last?.effectiveVolumeValue, 48)
            let childless = A.adapt(song([[birth], [c(14, 0xD3, instrument: 2, volume: 0xF0)]], linear: linear), orderIndex: 0, sampleRate: rate)
            let calls = try (0..<5).map { try XCTUnwrap(childless.g23ChildlessPitchInvocation(run: 0, invocation: $0)) }
            XCTAssertEqual(calls.map(\.syntheticTick), [1, 2, 3, 4, 5])
            XCTAssertEqual(calls.map(\.associatedGeneration), [0, 0, 0, 1, 1])
            XCTAssertEqual(calls.map(\.scheduledFrame), rate == 48_000 ? [6720, 7680, 8640, 9600, 10560] : [6174, 7056, 7938, 8820, 9702])
            XCTAssertEqual(childless.diagnostics.tonePortamentoEffects.map(\.syntheticTick), [0, 0, 0, 0, 0])
            XCTAssertTrue(childless.diagnostics.tonePortamentoEffects.allSatisfy { $0.stepUpdates.isEmpty })
            XCTAssertEqual(childless.rowEntryTriggerResetFacts.facts.map(\.syntheticRow), [0])
        } }
    }

    func testE4E7SuppressionAndPersistentRCounterAreObservedLiterally() throws {
        for linear in [true, false] { for rate in rates { for suppressed in [false, true] {
            let rows = [[birth], [c(14, suppressed ? 0x44 : 0x40)], [c(4, 0x48)],
                [c(14, suppressed ? 0x74 : 0x70)], [c(7, 0x48)], [c(27, 0x0F)], [delayed]]
            let plan = A.adapt(song(rows, linear: linear), orderIndex: 0, sampleRate: rate)
            let call = try XCTUnwrap(plan.delayedInstrumentReset(at: 0))
            XCTAssertEqual([call.before.vibratoPhase, call.before.tremoloPhase, call.before.tremoloVibratoPhase], [80, 80, 80])
            XCTAssertEqual([call.after.vibratoPhase, call.after.tremoloPhase, call.after.tremoloVibratoPhase], suppressed ? [80, 80, 80] : [0, 0, 0])
            XCTAssertEqual(call.before.vibratoRetriggerSuppressed, suppressed)
            XCTAssertEqual(call.before.tremoloRetriggerSuppressed, suppressed)
            XCTAssertEqual(call.before.tremoloVibratoRetriggerSuppressed, suppressed)
            XCTAssertEqual(call.before.rRetriggerCounter, 6); XCTAssertEqual(call.after.rRetriggerCounter, 0)
        } } }
    }

    func testProducerHookBracketsIndependentSuppressionAndRCounterExactlyOnce() throws {
        for vibrato: Bool? in [nil, false, true] { for tremolo in [false, true] { for linked in [false, true] {
            var state = A.ChannelState(), calls = [(PlaybackSongRowEntryTriggerResetFacts.Scalars, PlaybackSongRowEntryTriggerResetFacts.Scalars)]()
            state.vibratoPhase = 76; state.tremolo.phase = 84; state.tremoloVibratoPhase = 92; state.rRetriggerCounter = 7
            state.vibratoControl = vibrato.map { .init(controlValue: $0 ? 4 : 0, waveform: .sine, retriggerSuppressed: $0, source: nil) }
            state.tremolo.control = tremolo ? 4 : 0; state.tremoloVibratoControl = linked ? 4 : 0
            A.resetDelayedInstrument(cell: delayed, state: &state, didResetEffectPhases: { calls.append(($0, $1)) })
            XCTAssertEqual(calls.count, 1)
            let (before, after) = try XCTUnwrap(calls.first)
            XCTAssertEqual([before.vibratoPhase, before.tremoloPhase, before.tremoloVibratoPhase], [76, 84, 92])
            XCTAssertEqual([after.vibratoPhase, after.tremoloPhase, after.tremoloVibratoPhase], [vibrato == true ? 76 : 0, tremolo ? 84 : 0, linked ? 92 : 0])
            XCTAssertEqual(before.vibratoRetriggerSuppressed, vibrato); XCTAssertEqual(after.vibratoRetriggerSuppressed, vibrato)
            XCTAssertEqual(before.tremoloRetriggerSuppressed, tremolo); XCTAssertEqual(after.tremoloRetriggerSuppressed, tremolo)
            XCTAssertEqual(before.tremoloVibratoRetriggerSuppressed, linked); XCTAssertEqual(after.tremoloVibratoRetriggerSuppressed, linked)
            XCTAssertEqual(before.rRetriggerCounter, 7); XCTAssertEqual(after.rRetriggerCounter, 0)
        } } }
    }

    func testRepeatedOrdersAndTraversedLoopsRetainEachActualOccurrence() throws {
        for linear in [true, false] { for rate in rates {
            let repeated = A.adapt(song([[birth], [delayed]], linear: linear, repeated: true), orderRange: 0..<2, sampleRate: rate)
            let calls = try observations(repeated)
            XCTAssertEqual(calls.map(\.syntheticRow), [1, 3]); XCTAssertEqual(calls.map { $0.source.orderIndex }, [0, 1])
            XCTAssertEqual(calls.map(\.priorSourceEventIndex), [0, 2]); XCTAssertEqual(calls.map(\.newSourceEventIndex), [1, 3])
            XCTAssertEqual(calls.map(\.scheduledFrame), [9, 21].map { $0 * Int(rate / 50) })
            let loop = A.adapt(song([[birth], [c(14, 0x60)], [delayed], [c(14, 0x61)]], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(try observations(loop).map(\.syntheticRow), [2, 5])
            XCTAssertEqual(try observations(loop).map { $0.source.rowIndex }, [2, 2])
            XCTAssertEqual(try observations(loop).map(\.scheduledFrame), [15, 33].map { $0 * Int(rate / 50) })
        } }
    }

    func testPlanSharingInvalidationAndBoundsDoNotExtendPartialCoverage() throws {
        let input = song([[birth], [delayed]]), plan = A.adapt(input, orderIndex: 0, sampleRate: 48_000)
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: 48_000), rows: 2)
        var copies = [plan.replacingEventCoverage(plan.diagnostics.eventCoverage), PlaybackSongOfflineRenderer.plan(plan, mutingEventsNotIn: []),
            plan.extendingEnvelopeTail(throughFrame: 50_000), renderer.render(request).plan, renderer.renderWindowed(request, windowRows: 1).plan]
        #if DEBUG
        copies.append(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).plan)
        #endif
        for _ in 0..<2 { copies.append(try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000, preparedPlan: plan).plan)) }
        for copy in copies {
            XCTAssertEqual(copy.delayedInstrumentResetFacts, plan.delayedInstrumentResetFacts)
            XCTAssertEqual(try observations(copy), try observations(plan))
            plan.delayedInstrumentResetFacts.facts.withUnsafeBufferPointer { original in
                copy.delayedInstrumentResetFacts.facts.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
            }
        }
        for index in [-1, Int.min, Int.max, 1] { XCTAssertNil(plan.delayedInstrumentReset(at: index)) }
        var changed = plan; changed.diagnostics.vibratoEffects.removeAll()
        XCTAssertEqual(changed.delayedInstrumentResetFacts.coverage, .notAdapterProduced)
        XCTAssertNil(changed.delayedInstrumentReset(at: 0))
        let manual = PlaybackSongSyntheticPlan(timingConfig: plan.timingConfig, pattern: plan.pattern, diagnostics: plan.diagnostics,
            canonicalTickClock: plan.canonicalTickClock, selectionDispatchFacts: plan.selectionDispatchFacts)
        XCTAssertEqual(manual.delayedInstrumentResetFacts.coverage, .notAdapterProduced)
        let first = try XCTUnwrap(plan.delayedInstrumentReset(at: 0))
        var malformed = plan
        malformed.delayedInstrumentResetFacts = .init(coverage: .partialInRowInstrumentOnlyEDxV1,
            facts: [.init(source: first.source, syntheticRow: first.syntheticRow, syntheticTick: first.syntheticTick,
                channelIndex: first.channelIndex, scheduledFrame: first.scheduledFrame + 1, requestedInstrumentIndex: first.requestedInstrumentIndex,
                priorSourceEventIndex: first.priorSourceEventIndex, newSourceEventIndex: first.newSourceEventIndex,
                before: first.before, after: first.after)], storageGrowthCount: 1)
        XCTAssertNil(malformed.delayedInstrumentReset(at: 0))
    }

    private func observations(_ plan: PlaybackSongSyntheticPlan) throws -> [E.Fact] {
        try plan.delayedInstrumentResetFacts.facts.indices.map { try XCTUnwrap(plan.delayedInstrumentReset(at: $0)) }
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ rows: [[PlaybackCell]], linear: Bool = true, speed: Int = 6, completed: Bool = false, repeated: Bool = false) -> PlaybackSong {
        func sample(_ instrument: Int, relative: Int = 0) -> PlaybackSample {
            .init(instrumentIndex: instrument, sampleIndex: 0, pcm: instrument == 1 ? [0.125, -0.375, 0.25, -0.0625] : [-0.5, 0.25, 0.125, -0.25],
                volume: instrument == 1 ? 0.5 : 0.75, relativeNote: relative, finetune: 0, baseSampleRate: 8363,
                loopLength: completed ? 0 : 4, loopType: completed ? 0 : 1)
        }
        let map = Array(repeating: 0, count: 96)
        return .init(title: "Public delayed reset controls", orders: (0..<(repeated ? 2 : 1)).map { .init(orderIndex: $0, patternIndex: 0) },
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset,
                cells: $0.element + Array(repeating: c(), count: max(0, 2 - $0.element.count))) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample(1)], noteSampleMap: map), 2: .init(index: 2, samples: [sample(2)], noteSampleMap: map),
                3: .init(index: 3, samples: [], noteSampleMap: map), 4: .init(index: 4, samples: [], noteSampleMap: map),
                5: .init(index: 5, samples: [sample(5, relative: 96)], noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: 32, panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
