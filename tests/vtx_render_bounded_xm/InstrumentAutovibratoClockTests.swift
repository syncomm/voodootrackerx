import Foundation
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif
import XCTest

/// Public synthetic cells exercise the real traversal and native reset gates at depth off.
final class InstrumentAutovibratoClockTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias C = PlaybackSongInstrumentAutovibratoClock
    private let rates = [44_100.0, 48_000]
    private var birth: PlaybackCell { c(note: 49, instrument: 1) }
    private var ordinary: PlaybackInstrumentAutoVibrato { .init(waveformType: 0, sweep: 16, depth: 8, rate: 7) }

    func testDelayedNoteOnlyResetIsActualDispatchAndImmediateNoteOnlyCarries() throws {
        for linear in [true, false] { for rate in rates {
            let immediate = adapt([[birth], [c(note: 53)]], linear, rate)
            XCTAssertEqual(try value(immediate, 1, 0).phaseBefore, 42)
            XCTAssertEqual(try value(immediate, 1, 0).lastResetOrdinal, 0)
            let delayed = adapt([[birth], [c(14, 0xD3, note: 53)]], linear, rate)
            XCTAssertEqual(try value(delayed, 1, 2).phaseBefore, 56)
            let reset = try value(delayed, 1, 3)
            XCTAssertEqual(reset.phaseBefore, 0); XCTAssertEqual(reset.phaseAfter, 7)
            XCTAssertEqual(reset.lastResetOrdinal, 9); XCTAssertEqual(reset.resetCause, .delayedNote)
            XCTAssertEqual(reset.elapsedTicks, 1)
            // #504 observes instrument-only EDx, so its absence cannot imply no reset here.
            XCTAssertTrue(delayed.delayedInstrumentResetFacts.facts.isEmpty)
            XCTAssertEqual(delayed.diagnostics.eventMappings.map(\.syntheticTick), [0, 3])
            for target in [c(14, 0xD6, note: 53), c(14, 0xD0, note: 53)] {
                let carry = adapt([[birth], [target]], linear, rate)
                XCTAssertEqual(try value(carry, 1, 5).phaseAfter, 84)
                XCTAssertEqual(try value(carry, 1, 5).lastResetOrdinal, 0)
            }
            let ed0 = adapt([[birth], [c(14, 0xD0, note: 53, instrument: 2)]], linear, rate)
            XCTAssertEqual(try value(ed0, 1, 0).lastResetOrdinal, 6)
            XCTAssertEqual(try value(ed0, 1, 0).resetCause, .rowEntry)
        } }
    }

    func testOwnershipUsesSelectedSemanticInstrumentRatherThanCarriedOwnerOrGeneration() throws {
        for linear in [true, false] { for rate in rates {
            let retained = adapt([[birth], [c(instrument: 2)]], linear, rate)
            let controls = try XCTUnwrap(retained.semanticPitch(row: 1, tick: 0, channel: 0))
            XCTAssertEqual(controls.semanticInstrument, 1); XCTAssertEqual(controls.carriedInstrument, 2)
            XCTAssertEqual(controls.associatedGeneration, 0)
            let reset = try value(retained, 1, 0)
            XCTAssertEqual(reset.raw, ordinary); XCTAssertEqual(reset.phaseBefore, 0)
            XCTAssertEqual(reset.resetCause, .rowEntry); XCTAssertEqual(reset.lastResetOrdinal, 6)
            XCTAssertEqual(retained.rowEntryTriggerResetFacts.facts.last?.requestedInstrumentIndex, 2)
            let changed = adapt([[birth], [c(note: 53, instrument: 2)]], linear, rate)
            XCTAssertEqual(try value(changed, 1, 0).raw?.rate, 11)
            XCTAssertEqual(try value(changed, 1, 0).waveform, .square)
            XCTAssertEqual(try value(changed, 1, 1).phaseAfter, 22)
            let delayed = adapt([[birth], [c(14, 0xD3, instrument: 2)]], linear, rate)
            XCTAssertEqual(try value(delayed, 1, 2).raw, ordinary)
            XCTAssertEqual(try value(delayed, 1, 2).phaseBefore, 56)
            XCTAssertEqual(try value(delayed, 1, 3).raw?.rate, 11)
            XCTAssertEqual(try value(delayed, 1, 3).phaseAfter, 11)
            XCTAssertEqual(try value(delayed, 1, 3).resetCause, .delayedInstrument)
            XCTAssertEqual(delayed.delayedInstrumentReset(at: 0)?.syntheticTick, 3)
            let outside = adapt([[birth], [c(14, 0xD6, instrument: 2)]], linear, rate)
            XCTAssertEqual(try value(outside, 1, 5).raw, ordinary)
            XCTAssertEqual(try value(outside, 1, 5).lastResetOrdinal, 0)
            for first in [birth, c(note: 49, instrument: 3)] {
                let next = adapt([[first], [c(instrument: 2)], [c(note: 53)]], linear, rate)
                XCTAssertEqual(try value(next, 2, 0).raw?.rate, 11)
                XCTAssertEqual(try value(next, 2, 0).lastResetOrdinal, 6)
                XCTAssertEqual(try value(next, 2, 0).phaseBefore, 42)
                XCTAssertEqual(try value(next, 2, 0).phaseAfter, 53)
                XCTAssertEqual(next.selectionDispatchFacts.facts.last?.baseRate, 12_000)
            }
        } }
    }

    func testClockIsIndependentOfOrdinaryVibratoAndWaveformIdentity() throws {
        for linear in [true, false] { for rate in rates {
            for waveform in UInt8(0)...3 {
                let metadata = PlaybackInstrumentAutoVibrato(waveformType: waveform, sweep: 16, depth: 8, rate: 7)
                let plan = adapt([[birth], [c(4, 0x48, volume: 0xB8)], [c(6, 1)], [c(volume: 0xB8)],
                    [c(14, 0x44)], [c()]], linear, rate, metadata: metadata)
                for row in 0..<6 { for tick in 0..<6 {
                    let state = try value(plan, row, tick), count = row * 6 + tick
                    XCTAssertEqual(state.waveform?.rawValue, waveform)
                    XCTAssertEqual(state.phaseBefore, UInt8((count * 7) & 255))
                    XCTAssertEqual(state.phaseAfter, UInt8(((count + 1) * 7) & 255))
                    XCTAssertEqual(state.elapsedTicks, count + 1)
                    XCTAssertEqual(state.lastResetOrdinal, 0)
                } }
                XCTAssertEqual(plan.diagnostics.vibratoEffects.first?.stepUpdates.count, 10)
                XCTAssertEqual(try value(plan, 2, 3).sweepReached, true)
                XCTAssertEqual(try value(plan, 0, 5).sweepReached, false)
                XCTAssertEqual(try value(plan, 0, 5).sweepElapsed, 6)
            }
        } }
    }

    func testE9ResetsWhileE90RxyAndOrdinaryReplacementCarry() throws {
        for linear in [true, false] { for rate in rates {
            let repeated = adapt([[birth], [c(14, 0x93)]], linear, rate)
            XCTAssertEqual(repeated.diagnostics.retriggerEffects.last?.retriggerTicks, [3])
            XCTAssertEqual(try value(repeated, 1, 2).phaseAfter, 63)
            XCTAssertEqual(try value(repeated, 1, 3).phaseBefore, 0)
            XCTAssertEqual(try value(repeated, 1, 3).resetCause, .retrigger)
            XCTAssertEqual(try value(repeated, 1, 5).elapsedTicks, 3)
            for cell in [c(14, 0x90), c(27, 2), c(note: 53)] {
                let carry = adapt([[birth], [cell]], linear, rate)
                XCTAssertGreaterThan(carry.pattern.events.count, 1)
                XCTAssertEqual(try value(carry, 1, 5).phaseAfter, 84)
                XCTAssertEqual(try value(carry, 1, 5).lastResetOrdinal, 0)
            }
            let explicit = adapt([[birth], [c(14, 0x90, instrument: 2)]], linear, rate)
            XCTAssertEqual(try value(explicit, 1, 0).lastResetOrdinal, 6)
            XCTAssertEqual(try value(explicit, 1, 0).resetCause, .rowEntry)
            let empty = adapt([[c(note: 49, instrument: 3)], [c(14, 0x93, note: 49)]], linear, rate)
            XCTAssertTrue(empty.pattern.events.isEmpty)
            XCTAssertEqual(try value(empty, 1, 3).lastResetOrdinal, 9)
            XCTAssertEqual(try value(empty, 1, 3).resetCause, .retrigger)
            let emptyNoDispatch = adapt([[c(note: 49, instrument: 3)], [c(14, 0x93)]], linear, rate)
            XCTAssertEqual(try value(emptyNoDispatch, 1, 5).lastResetOrdinal, 0)
            let cold = adapt([[c(14, 0x93)]], linear, rate)
            XCTAssertNil(try value(cold, 0, 5).lastResetOrdinal)
            XCTAssertEqual(try value(cold, 0, 5).status, .unowned)
        } }
    }

    func testColdCompletedDeclaredEmptyUnavailableAndRefusedRoutesDoNotInventSources() throws {
        for linear in [true, false] { for rate in rates {
            let cold = adapt([[c(instrument: 1)], [c()], [c(14, 0xD3, instrument: 2)]], linear, rate)
            XCTAssertTrue(cold.pattern.events.isEmpty)
            XCTAssertEqual(try value(cold, 1, 5).status, .unowned)
            XCTAssertNil(try value(cold, 1, 5).raw)
            for instrument: UInt8 in [3, 5] {
                let plan = adapt([[birth], [c(note: 49, instrument: instrument)], [c()]], linear, rate)
                XCTAssertEqual(plan.pattern.events.count, 1)
                // A declared header cuts; an undeclared explicit route retains the old association.
                let selected = try XCTUnwrap(plan.semanticPitch(row: 2, tick: 5, channel: 0))
                XCTAssertEqual(selected.associatedGeneration, instrument == 3 ? nil : 0)
                XCTAssertEqual(selected.semanticInstrument, instrument == 3 ? 3 : 1)
                XCTAssertEqual(try value(plan, 2, 5).lastResetOrdinal, 6)
                XCTAssertEqual(try value(plan, 2, 5).elapsedTicks, 12)
            }
            let unavailable = adapt([[birth], [c(instrument: 5)], [c(14, 0xD3, note: 53)]], linear, rate)
            XCTAssertEqual(unavailable.semanticPitch(row: 2, tick: 2, channel: 0)?.associatedGeneration, 0)
            XCTAssertEqual(try value(unavailable, 2, 2).raw, ordinary)
            XCTAssertNil(unavailable.semanticPitch(row: 2, tick: 3, channel: 0)?.associatedGeneration)
            XCTAssertEqual(unavailable.semanticPitch(row: 2, tick: 3, channel: 0)?.semanticInstrument, 5)
            XCTAssertEqual(try value(unavailable, 2, 3).raw?.rate, 11)
            XCTAssertEqual(try value(unavailable, 2, 3).lastResetOrdinal, 15)
            XCTAssertEqual(try value(unavailable, 2, 3).resetCause, .delayedNote)
            XCTAssertEqual(unavailable.pattern.events.count, 1)
            let completed = adapt([[birth], [c()], [c(instrument: 2)]], linear, rate, completed: true)
            XCTAssertEqual(completed.pattern.events.count, 1)
            XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: Int(rate * 0.12), plan: completed))
            XCTAssertEqual(try value(completed, 1, 5).phaseAfter, 84)
            XCTAssertEqual(try value(completed, 2, 0).resetCause, .rowEntry)
            let refused = adapt([[birth], [c(note: 49, instrument: 4)]], linear, rate)
            XCTAssertEqual(refused.pattern.events.count, 1)
            XCTAssertEqual(refused.semanticPitch(row: 1, tick: 0, channel: 0)?.associatedGeneration, 0)
            XCTAssertEqual(try value(refused, 1, 0).resetCause, .refused)
            XCTAssertEqual(try value(refused, 1, 0).phaseBefore, 0)
            XCTAssertEqual(refused.selectionDispatchFacts.facts.last?.baseRate, 8363)
            XCTAssertEqual(try value(refused, 1, 0).raw?.rate, 11)
            let carried = adapt([[birth], [c(instrument: 4)], [c(note: 49)]], linear, rate)
            XCTAssertEqual(try value(carried, 2, 0).raw?.rate, 11)
            XCTAssertEqual(try value(carried, 2, 0).lastResetOrdinal, 6)
            XCTAssertEqual(try value(carried, 2, 0).phaseBefore, 42)
            XCTAssertEqual(try value(carried, 2, 0).phaseAfter, 53)
            let delayed = adapt([[birth], [c(instrument: 4)], [c(14, 0xD3, note: 49)]], linear, rate)
            XCTAssertEqual(try value(delayed, 2, 2).raw, ordinary)
            XCTAssertEqual(try value(delayed, 2, 3).raw?.rate, 11)
            XCTAssertEqual(try value(delayed, 2, 3).lastResetOrdinal, 15)
            XCTAssertEqual(try value(delayed, 2, 3).resetCause, .refused)
        } }
    }

    func testReleaseRetainsSweepFactsAndContinuesPhaseWithoutChoosingAmplitude() throws {
        for linear in [true, false] { for rate in rates {
            for cell in [c(note: 97), c(20, 2)] {
                let plan = adapt([[birth], [cell], [c()]], linear, rate)
                let release = try XCTUnwrap(plan.diagnostics.keyOffEvents.first { $0.applied })
                let state = try value(plan, release.syntheticRow, release.syntheticTick)
                XCTAssertTrue(state.released)
                XCTAssertEqual(state.sweepElapsed, 6 + release.syntheticTick)
                XCTAssertEqual(try value(plan, 2, 5).sweepElapsed, state.sweepElapsed)
                XCTAssertEqual(try value(plan, 2, 5).sweepReached, false)
                XCTAssertEqual(try value(plan, 2, 5).phaseAfter, 126)
                XCTAssertEqual(try value(plan, 2, 5).lastResetOrdinal, 0)
            }
        } }
    }

    func testRawPolicyPendingBytesArePreservedWithoutAudibleExpectations() throws {
        let cases: [PlaybackInstrumentAutoVibrato] = [.init(waveformType: 250, sweep: 12, depth: 8, rate: 7),
            .init(waveformType: 0, sweep: 12, depth: 16, rate: 7), .init(waveformType: 0, sweep: 12, depth: 8, rate: 64),
            .init(waveformType: 0, sweep: 255, depth: 8, rate: 7), .init(waveformType: 1, sweep: 12, depth: 8, rate: 0)]
        for (index, raw) in cases.enumerated() {
            let plan = adapt([[birth], [c()]], true, 48_000, metadata: raw)
            let state = try value(plan, 1, 5)
            XCTAssertEqual(state.raw, raw); XCTAssertEqual(state.status, .policyPending)
            if index < 4 { XCTAssertNil(state.sweepReached) }
            if index < 3 { XCTAssertNil(state.phaseBefore); XCTAssertNil(state.phaseAfter) }
        }
        let disabled = PlaybackInstrumentAutoVibrato(waveformType: 0, sweep: 12, depth: 0, rate: 7)
        let depthOff = try value(adapt([[birth]], true, 48_000, metadata: disabled), 0, 5)
        XCTAssertEqual(depthOff.raw, disabled); XCTAssertEqual(depthOff.phaseAfter, 42)
    }

    func testCanonicalTicksFollowEmptyRowsFxxAndOrderTransitionsWithoutExitTicks() throws {
        for linear in [true, false] { for rate in rates { for speed in [1, 2, 3, 6] {
            let rows = [[birth, c()], [c(), c(15, UInt8(speed))], [c(), c(15, 137)], [c(), c()]]
            let source = song(rows, linear: linear, repeated: true)
            let plan = A.adapt(source, orderRange: 0..<2, sampleRate: rate)
            var ordinal = 0
            for row in 0..<8 {
                let effectiveSpeed = row == 0 ? 6 : speed
                for tick in 0..<effectiveSpeed {
                    let state = try value(plan, row, tick), local = row < 4 ? ordinal : ordinal - (6 + 3 * speed)
                    XCTAssertEqual(state.phaseBefore, UInt8((local * 7) & 255))
                    XCTAssertEqual(state.elapsedTicks, local + 1)
                    ordinal += 1
                }
                XCTAssertNil(plan.instrumentAutovibrato(row: row, tick: effectiveSpeed, channel: 0))
            }
            XCTAssertEqual(plan.canonicalTickClock.totalCanonicalTicks, 6 + 7 * speed)
        } } }
    }

    func testImmutablePlansWindowQueriesAndInvalidationNeverAdvanceAgain() throws {
        let source = song([[birth], [c(14, 0xD3, instrument: 2)], [c()]])
        let plan = A.adapt(source, orderIndex: 0, sampleRate: 48_000)
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        let request = PlaybackSongOfflineRenderRequest(song: source, config: .init(sampleRate: 48_000), rows: 3)
        var copies = [plan.replacingEventCoverage(plan.diagnostics.eventCoverage), PlaybackSongOfflineRenderer.plan(plan, mutingEventsNotIn: []),
            plan.extendingEnvelopeTail(throughFrame: 100_000), renderer.render(request).plan, renderer.renderWindowed(request, windowRows: 1).plan]
        let partial = PlaybackSongOfflineRenderRequest(song: source, config: .init(sampleRate: 48_000), rows: 2)
        copies.append(renderer.renderWindowed(partial, windowRows: 1).plan)
        #if DEBUG
        copies.append(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).plan)
        #endif
        for _ in 0..<2 { copies.append(try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: source, sampleRate: 48_000, preparedPlan: plan).plan)) }
        for copy in copies {
            XCTAssertEqual(copy.instrumentAutovibratoClock, plan.instrumentAutovibratoClock)
            XCTAssertEqual(try value(copy, 2, 5), try value(plan, 2, 5))
            plan.instrumentAutovibratoClock.channels.withUnsafeBufferPointer { original in
                copy.instrumentAutovibratoClock.channels.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
            }
            plan.instrumentAutovibratoClock.channels[0].withUnsafeBufferPointer { original in
                copy.instrumentAutovibratoClock.channels[0].withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
            }
        }
        var invalidated = plan; invalidated.diagnostics.vibratoEffects.removeAll()
        XCTAssertEqual(invalidated.instrumentAutovibratoClock.coverage, .notAdapterProduced)
        XCTAssertNil(invalidated.instrumentAutovibrato(row: 0, tick: 0, channel: 0))
        let manual = PlaybackSongSyntheticPlan(timingConfig: plan.timingConfig, pattern: plan.pattern, diagnostics: plan.diagnostics,
            canonicalTickClock: plan.canonicalTickClock, selectionDispatchFacts: plan.selectionDispatchFacts)
        XCTAssertEqual(manual.instrumentAutovibratoClock.coverage, .notAdapterProduced)
        XCTAssertNil(manual.instrumentAutovibrato(row: 0, tick: 0, channel: 0))
        let rebuilt = adapt([[birth], [c()]], true, 48_000,
            metadata: .init(waveformType: 2, sweep: 12, depth: 8, rate: 17))
        XCTAssertEqual(try value(rebuilt, 1, 5).phaseAfter, 204)
        XCTAssertEqual(try value(rebuilt, 1, 5).waveform, .rampDown)
        for (row, tick, channel) in [(-1, 0, 0), (0, -1, 0), (0, 0, -1), (3, 0, 0), (0, 0, 2), (Int.max, 0, 0)] {
            XCTAssertNil(plan.instrumentAutovibrato(row: row, tick: tick, channel: channel))
        }
    }

    func testCaptureGapInvalidatesClockWithoutRewindingPublishedResets() {
        var builder = PlaybackSongSemanticPitchProjection.Builder()
        builder.begin(states: [], count: 1, firstOrdinal: 0, speed: 6, linear: true,
            retriggers: 0, rowResets: 0, delayedResets: 0, exits: 0, rows: 0)
        builder.add(tick: 0, channel: 0, action: .automaticReset(.rowEntry))
        builder.add(tick: 3, channel: 0, action: .automaticReset(.delayedNote))
        builder.add(tick: 4, channel: 0, action: .automaticReset(.delayedNote))
        var context = A.AdapterRowContext(), uncaptured = A.ChannelState()
        uncaptured.activeLinearPeriod = 42; context.channelStates = [uncaptured]
        builder.finish(context: context, song: song([[birth]]))
        XCTAssertEqual(builder.failures, 1)
        XCTAssertEqual(builder.automatic.evidence.coverage, .notAdapterProduced)

        // A real valid prefix must survive a later capture gap. Ordinary writers
        // in that row keep their raw requests instead of using stale automatic phase.
        let input = song([[birth], [c(4, 0x48)]])
        let traversal = PlaybackSongTraversalPlanner.plan(input, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(input, traversalPlan: traversal, sampleRate: 48000)
        var live = A.AdapterRowContext()
        var automatic = PlaybackSongInstrumentAutovibratoPublication.Builder()
        automatic.enabled = true
        var prefix = [PlaybackSongInstrumentAutovibratoPublication.Request]()
        for (index, row) in traversal.rows.enumerated() {
            live.semanticPitchBuilder.begin(states: live.channelStates, count: row.row.cells.count,
                firstOrdinal: index * 6, speed: 6, linear: true, retriggers: live.retriggerEffects.count,
                rowResets: live.rowEntryTriggerResetObserver.facts.count,
                delayedResets: live.delayedInstrumentResetObserver.facts.count,
                exits: live.rowExitObserver.references.count, rows: live.xmChannelRows.count)
            _ = A.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: input,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: index == 0 ? traversal.rows[1].row : nil, context: &live)
            if index == 1 { live.channelStates[0].activeLinearPeriod = 42 }
            A.finishSemanticPitchRow(context: &live, song: input)
            let ordinary = live.vibratoEffects.last?.stepUpdates
            A.materializeInstrumentAutovibratoRow(context: &live, builder: &automatic, source: row.source, row: row.syntheticRow,
                channelCount: row.row.cells.count, timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing)
            if index == 0 { prefix = automatic.requests; XCTAssertFalse(prefix.isEmpty) }
            else {
                XCTAssertEqual(live.semanticPitchBuilder.failures, 1)
                XCTAssertFalse(live.semanticPitchBuilder.automatic.valid)
                XCTAssertEqual(live.vibratoEffects.last?.stepUpdates, ordinary)
                XCTAssertEqual(automatic.requests, prefix)
            }
        }
    }

    func testSparseStorageDoesNotRetainOneStatePerEmptyTick() throws {
        XCTAssertLessThanOrEqual(MemoryLayout<C.Run>.stride, 64)
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride, 1152)
        let plan = adapt([[birth]] + Array(repeating: [c()], count: 100), true, 48_000)
        XCTAssertEqual(plan.canonicalTickClock.totalCanonicalTicks, 606)
        XCTAssertEqual(plan.instrumentAutovibratoClock.channels[0].count, 1)
        XCTAssertEqual(plan.instrumentAutovibratoClock.runCount, 1)
        XCTAssertEqual(try value(plan, 100, 5).elapsedTicks, 606)
        XCTAssertEqual(try value(plan, 100, 5).phaseAfter, UInt8(606 * 7 & 255))
    }

    private func value(_ plan: PlaybackSongSyntheticPlan, _ row: Int, _ tick: Int, _ channel: Int = 0) throws -> C.Result {
        try XCTUnwrap(plan.instrumentAutovibrato(row: row, tick: tick, channel: channel))
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func adapt(_ rows: [[PlaybackCell]], _ linear: Bool, _ rate: Double,
        metadata: PlaybackInstrumentAutoVibrato? = nil, completed: Bool = false) -> PlaybackSongSyntheticPlan {
        A.adapt(song(rows, linear: linear, metadata: metadata, completed: completed), orderIndex: 0, sampleRate: rate)
    }
    private func song(_ rows: [[PlaybackCell]], linear: Bool = true, metadata: PlaybackInstrumentAutoVibrato? = nil,
        completed: Bool = false, repeated: Bool = false) -> PlaybackSong {
        func sample(_ instrument: Int, _ slot: Int = 0, relative: Int = 0) -> PlaybackSample {
            .init(instrumentIndex: instrument, sampleIndex: slot, pcm: [0.125, -0.375, 0.25, -0.0625], volume: 0.5,
                relativeNote: relative, finetune: 0, baseSampleRate: instrument == 2 ? 12_000 : instrument == 4 ? 16_000 : 8363,
                loopLength: completed ? 0 : 4, loopType: completed ? 0 : 1)
        }
        var map = Array(repeating: 0, count: 96); map[52] = 1
        let second = PlaybackInstrumentAutoVibrato(waveformType: 1, sweep: 9, depth: 6, rate: 11)
        return .init(title: "Public inert instrument clock", orders: (0..<(repeated ? 2 : 1)).map { .init(orderIndex: $0, patternIndex: 0) },
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset,
                cells: $0.element + Array(repeating: c(), count: max(0, 2 - $0.element.count))) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample(1), sample(1, 1)], autoVibrato: metadata ?? ordinary, noteSampleMap: map),
                2: .init(index: 2, samples: [sample(2)], autoVibrato: second, noteSampleMap: Array(repeating: 0, count: 96)),
                3: .init(index: 3, samples: [], autoVibrato: metadata ?? ordinary, noteSampleMap: Array(repeating: 0, count: 96)),
                4: .init(index: 4, samples: [sample(4, relative: 96)], autoVibrato: second, noteSampleMap: Array(repeating: 0, count: 96)),
                5: .init(index: 5, samples: [sample(5)], autoVibrato: second, noteSampleMap: Array(repeating: 9, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true,
                volume: 0, panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
