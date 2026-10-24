import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original public cells and literal producer values distinguish erased exits from incoming writes.
final class RowExitProvenanceTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias E = PlaybackSongRowExitProvenance
    private let rates = [44_100.0, 48_000]
    private var birth: PlaybackCell { c(note: 49, instrument: 1) }
    private var fineWriters: [PlaybackCell] { [c(14, 0x11), c(14, 0x21), c(33, 0x11), c(33, 0x21)] }

    func testExitOnly400448600UsesExceptionalScalarsAtBothRatesAndDomains() throws {
        for linear in [true, false] { for rate in rates {
            for (effect, parameter): (UInt8, UInt8) in [(4, 0), (4, 0x48), (6, 0)] {
                for writer in fineWriters {
                    let input = song([[c(note: 49, instrument: 1, volume: 0xA4)], [c(volume: 0xB8)],
                        [c(effect, parameter), c(15, 1)], [writer]], linear: linear)
                    let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                    let value = try XCTUnwrap(plan.suppressedRowExit(at: 0))
                    XCTAssertEqual(plan.rowExitProvenance.coverage, .suppressedRowExitsV1)
                    XCTAssertEqual(plan.rowExitProvenance.references.count, 1)
                    XCTAssertEqual(plan.rowExitProvenance.exceptionalScalars.count, 1)
                    XCTAssertEqual(value.cause, .vibratoExitCoalesced)
                    XCTAssertEqual(value.witness, .exceptionalScalar)
                    XCTAssertEqual(value.outgoingDiagnosticIndex, 1)
                    XCTAssertEqual(value.incomingDiagnosticIndex, 0)
                    XCTAssertEqual(value.incomingFamily, incomingFamily(writer))
                    XCTAssertEqual(value.source, .init(orderIndex: 0, patternIndex: 0, rowIndex: 2))
                    XCTAssertEqual(value.syntheticRow, 2); XCTAssertEqual(value.channelIndex, 0)
                    XCTAssertEqual(value.associatedGeneration, 0); XCTAssertEqual(value.syntheticTick, 1)
                    XCTAssertEqual(value.scheduledFrame, rate == 48_000 ? 12_480 : 11_466)
                    XCTAssertEqual(value.domain, linear ? .linear : .amigaVTX4x)
                    XCTAssertEqual(value.nativePeriodBefore, linear ? 4671 : 7100)
                    XCTAssertEqual(value.nativePeriodAfter, linear ? 4608 : 6848)
                    let incoming = try XCTUnwrap(incomingChild(plan, writer))
                    XCTAssertEqual(linear ? incoming.linearPeriodAfter : incoming.amigaPeriodAfter,
                        incomingPeriod(writer, linear: linear))
                    XCTAssertEqual(incoming.scheduledFrame, value.scheduledFrame)
                    XCTAssertTrue(fineExecution(plan, writer)?.coalescedVibratoExit == true)
                    XCTAssertTrue(plan.diagnostics.vibratoEffects[1].stepUpdates.isEmpty)
                    XCTAssertFalse(plan.nativePitchWriterSpans.spans.contains { $0.family == .vibrato && $0.diagnosticIndex == 1 })
                    XCTAssertNil(plan.canonicalTickClock.coordinate(syntheticRow: 2, tick: 1, channel: 0))
                    XCTAssertEqual(plan.canonicalTickClock.coordinate(syntheticRow: 3, tick: 0, channel: 0)?.absoluteFrame, value.scheduledFrame)
                    let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate, preparedPlan: plan)
                    XCTAssertEqual(runtime.events.filter { $0.scheduledFrame == value.scheduledFrame && $0.primaryCategory == "step_update" }.count, 1)
                }
            }
        } }
    }

    func testOrdinaryVibratoUsesOriginalSpanBeyondItsPublicChildPrefix() throws {
        for linear in [true, false] { for rate in rates { for speed in [3, 6] {
            for writer in fineWriters {
                let plan = A.adapt(song([[birth], [c(4, 0x48)], [writer]], linear: linear, speed: speed), orderIndex: 0, sampleRate: rate)
                let value = try XCTUnwrap(plan.suppressedRowExit(at: 0))
                XCTAssertEqual(value.cause, .vibratoExitCoalesced); XCTAssertEqual(value.witness, .nativeWriterSpan)
                XCTAssertEqual(value.outgoingDiagnosticIndex, 0); XCTAssertEqual(value.incomingDiagnosticIndex, 0)
                XCTAssertEqual(value.incomingFamily, incomingFamily(writer)); XCTAssertEqual(value.associatedGeneration, 0)
                XCTAssertEqual(value.syntheticRow, 1); XCTAssertEqual(value.syntheticTick, speed)
                XCTAssertEqual(value.nativePeriodBefore, linear ? (speed == 3 ? 4632 : 4671) : (speed == 3 ? 6944 : 7100))
                XCTAssertEqual(value.nativePeriodAfter, linear ? 4608 : 6848)
                XCTAssertEqual(value.scheduledFrame, (speed == 3 ? 6 : 12) * Int(rate / 50))
                XCTAssertTrue(plan.rowExitProvenance.exceptionalScalars.isEmpty)
                let span = try XCTUnwrap(plan.nativePitchWriterSpans.spans.first)
                XCTAssertEqual(span.family, .vibrato); XCTAssertEqual(span.capturedChildCount, speed - 1)
                XCTAssertEqual(span.originalChildren.count, speed)
                XCTAssertEqual(span.originalChildren.last?.scheduledFrame, value.scheduledFrame)
                XCTAssertEqual(plan.diagnostics.vibratoEffects[0].stepUpdates.count, speed - 1)
                XCTAssertNil(plan.nativePitchWriter(span: 0, child: speed - 1))
            }
        } } }
    }

    func testArpeggio037073ReferencesTheExistingMovedDiagnosticValue() throws {
        for linear in [true, false] { for rate in rates { for outgoing: UInt8 in [0x37, 0x73] {
            for writer in [c(0, outgoing == 0x37 ? 0x73 : 0x37)] + fineWriters {
                let plan = A.adapt(song([[birth], [c(0, outgoing)], [writer]], linear: linear), orderIndex: 0, sampleRate: rate)
                let value = try XCTUnwrap(plan.suppressedRowExit(at: 0))
                let raw = try XCTUnwrap(plan.diagnostics.arpeggioEffects[0].subsumedRowExit)
                XCTAssertEqual(value.cause, .arpeggioExitSubsumed); XCTAssertEqual(value.witness, .arpeggioDiagnostic)
                XCTAssertEqual(value.outgoingDiagnosticIndex, 0)
                XCTAssertEqual(value.incomingDiagnosticIndex, writer.effectType == 0 ? 1 : 0)
                XCTAssertEqual(value.incomingFamily, incomingFamily(writer))
                XCTAssertEqual(value.source, .init(orderIndex: 0, patternIndex: 0, rowIndex: 1))
                XCTAssertEqual(value.associatedGeneration, 0); XCTAssertEqual(value.syntheticRow, 1)
                XCTAssertEqual(value.channelIndex, 0); XCTAssertEqual(value.syntheticTick, 6)
                XCTAssertEqual(value.nativePeriodBefore, linear ? (outgoing == 0x37 ? 4416 : 4160) : (outgoing == 0x37 ? 5760 : 4560))
                XCTAssertEqual(value.nativePeriodAfter, linear ? 4608 : 6848)
                XCTAssertEqual(value.nativePeriodBefore, linear ? raw.linearPeriodBefore : raw.amigaPeriodBefore)
                XCTAssertEqual(value.nativePeriodAfter, linear ? raw.linearPeriodAfter : raw.amigaPeriodAfter)
                XCTAssertEqual(value.scheduledFrame, rate == 48_000 ? 11_520 : 10_584)
                XCTAssertEqual(raw.scheduledFrame, value.scheduledFrame)
                XCTAssertTrue(plan.rowExitProvenance.exceptionalScalars.isEmpty)
                XCTAssertNil(plan.nativePitchWriter(span: 0, child: 6))
                XCTAssertNil(plan.canonicalTickClock.coordinate(syntheticRow: 1, tick: 6, channel: 0))
            }
        } } }
    }

    func testRetainedExitsAndExcludedLifecyclePathsDoNotInventSupersessions() throws {
        for linear in [true, false] { for rate in rates {
            let cases = [
                [[birth], [c(0, 0x37)], [c()]], [[birth], [c(4, 0x48)], [c()]],
                [[birth], [c(4, 0x48)], [c()], [c(4, 0)]],
                [[birth], [c(4, 0x48)], [c(14, 0x44)]],
                [[birth], [c(4, 0)], [c(14, 0x11)]],
                [[birth], [c(4, 0x48)], [c(14, 0x11, note: 53, instrument: 2)]],
                [[birth], [c(4, 0x48)], [c(14, 0xD3, note: 53, instrument: 2)], [c(14, 0x11)]],
                [[birth], [c(4, 0x48)], [c(14, 0x93)], [c(14, 0x11)]],
                [[birth], [c(4, 0x48)], [c(27, 0x02)], [c(14, 0x11)]],
                [[c()], [c(4, 0x48)], [c(14, 0x11)]],
                [[c(note: 49, instrument: 3)], [c(4, 0x48)], [c(14, 0x11)]],
                [[c(note: 49, instrument: 4)], [c(0, 0x37)], [c(14, 0x11)]]
            ]
            for rows in cases {
                let plan = A.adapt(song(rows, linear: linear), orderIndex: 0, sampleRate: rate)
                XCTAssertTrue(plan.rowExitProvenance.references.isEmpty, "\(rows)")
                XCTAssertNil(plan.suppressedRowExit(at: 0))
            }
            let retained = A.adapt(song([[birth], [c(4, 0x48)], [c()]], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(retained.diagnostics.vibratoEffects[0].stepUpdates.last?.syntheticTick, 6)
            let noExit = A.adapt(song([[birth], [c(4, 0x48)], [c(14, 0x11)]], linear: linear, speed: 1), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(noExit.rowExitProvenance.references.isEmpty)
        } }
    }

    func testCompletedPCMRetainsTheActualSemanticSupersessionWithoutPhysicalFinePublication() throws {
        for linear in [true, false] { for rate in rates {
            let input = song([[birth], [c(4, 0x48)], [c(14, 0x11)]], linear: linear, completed: true)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let value = try XCTUnwrap(plan.suppressedRowExit(at: 0))
            XCTAssertEqual(value.associatedGeneration, 0); XCTAssertEqual(value.witness, .nativeWriterSpan)
            XCTAssertEqual(value.nativePeriodBefore, linear ? 4671 : 7100)
            XCTAssertEqual(value.nativePeriodAfter, linear ? 4608 : 6848)
            XCTAssertEqual(value.scheduledFrame, rate == 48_000 ? 11_520 : 10_584)
            let fine = try XCTUnwrap(plan.diagnostics.finePortamentoUpEffects.first)
            XCTAssertTrue(fine.execution.coalescedVibratoExit); XCTAssertFalse(fine.execution.sourceEligible)
            XCTAssertTrue(fine.stepUpdates.isEmpty)
            XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: value.scheduledFrame, plan: plan))
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate, preparedPlan: plan)
            XCTAssertEqual(runtime.events.filter { $0.scheduledFrame == value.scheduledFrame && $0.primaryCategory == "step_update" }.count, 0)
        } }
    }

    func testGenerationOrderCoordinatesReleaseAndFractionalTempoRemainCausal() throws {
        for linear in [true, false] { for rate in rates {
            let mixed = A.adapt(song([[birth, birth], [c(note: 53), c()],
                [c(0, 0x37), c(4, 0x48)], [c(14, 0x11), c(33, 0x21)]], linear: linear, split: 3), orderRange: 0..<2, sampleRate: rate)
            let values = try observations(mixed)
            XCTAssertEqual(values.map(\.associatedGeneration), [2, 1])
            XCTAssertEqual(values.map(\.channelIndex), [0, 1])
            XCTAssertEqual(values.map(\.source), Array(repeating: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2), count: 2))
            XCTAssertEqual(values.map(\.scheduledFrame), Array(repeating: rate == 48_000 ? 17_280 : 15_876, count: 2))
            let released = A.adapt(song([[birth], [c(note: 97)], [c(4, 0x48)], [c(14, 0x11)]], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(try observations(released).map(\.associatedGeneration), [0])
            let fractional = A.adapt(song([[birth], [c(4, 0x48)], [c(14, 0x11)]], linear: linear, bpm: 137), orderIndex: 0, sampleRate: rate)
            let value = try XCTUnwrap(fractional.suppressedRowExit(at: 0))
            XCTAssertEqual(value.scheduledFrame, rate == 48_000 ? 10_510 : 9_656)
            XCTAssertEqual(value.nativePeriodBefore, linear ? 4671 : 7100)
        } }
    }

    func testZeroIsCapturedSeparatelyFromAbsentRowExitAndG23ChildlessCalls() throws {
        for linear in [true, false] { for rate in rates {
            let zero = A.adapt(song([[birth], [c(0, 0x37)]], linear: linear, relative: -49), orderIndex: 0, sampleRate: rate)
            let numeric = try XCTUnwrap(zero.nativePitchWriter(span: 0, child: 0))
            XCTAssertEqual(numeric.nativePeriodBefore, 0); XCTAssertEqual(numeric.nativePeriodAfter, 0)
            XCTAssertNil(zero.suppressedRowExit(at: 0))
            // Independently frozen base producer output includes a real restoration to zero.
            let restored = A.adapt(song([[birth], [c(0, 0x37)], [c(14, 0x11)]], linear: linear, relative: -49), orderIndex: 0, sampleRate: rate)
            let exit = try XCTUnwrap(restored.suppressedRowExit(at: 0))
            XCTAssertEqual(exit.cause, .arpeggioExitSubsumed); XCTAssertEqual(exit.witness, .arpeggioDiagnostic)
            XCTAssertEqual(exit.outgoingDiagnosticIndex, 0); XCTAssertEqual(exit.incomingDiagnosticIndex, 0)
            XCTAssertEqual(exit.associatedGeneration, 0); XCTAssertEqual(exit.syntheticTick, 6)
            XCTAssertEqual(exit.domain, linear ? .linear : .amigaVTX4x)
            XCTAssertEqual(exit.nativePeriodBefore, linear ? 1540 : 428)
            XCTAssertEqual(exit.nativePeriodAfter, 0)
            XCTAssertEqual(exit.scheduledFrame, rate == 48_000 ? 11_520 : 10_584)
            let incoming = try XCTUnwrap(restored.diagnostics.finePortamentoUpEffects.first?.stepUpdates.first)
            XCTAssertEqual(linear ? incoming.linearPeriodAfter : incoming.amigaPeriodAfter, linear ? 1 : 4)
            XCTAssertNil(restored.nativePitchWriter(span: 0, child: 6))
            let g23 = A.adapt(song([[birth], [c(14, 0xD3, instrument: 2, volume: 0xF0)]], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(g23.rowExitProvenance.references.isEmpty)
            let calls = try (0..<5).map { try XCTUnwrap(g23.g23ChildlessPitchInvocation(run: 0, invocation: $0)) }
            XCTAssertEqual(calls.map(\.syntheticTick), [1, 2, 3, 4, 5])
            XCTAssertEqual(calls.map(\.associatedGeneration), [0, 0, 0, 1, 1])
            for writer in fineWriters {
                let folded = A.adapt(song([[c(writer.effectType, writer.effectParam, note: 49, instrument: 1)]], linear: linear), orderIndex: 0, sampleRate: rate)
                XCTAssertTrue(folded.rowExitProvenance.references.isEmpty)
            }
        } }
    }

    func testMismatchedScheduledFrameRetainsTheActualExit() throws {
        let input = song([[c(note: 49, instrument: 1, volume: 0xA4)], [c(volume: 0xB8)],
            [c(4, 0), c(15, 1)], [c(14, 0x11)]])
        let traversal = PlaybackSongTraversalPlanner.plan(input, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(input, traversalPlan: traversal, sampleRate: 48_000)
        var context = A.AdapterRowContext()
        for (index, row) in traversal.rows.enumerated() {
            _ = A.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: input,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: index + 1 < traversal.rows.count ? traversal.rows[index + 1].row : nil, context: &context)
            if index == 2 {
                let raw = try XCTUnwrap(context.vibratoEffects[1].stepUpdates.last)
                // Falsify only the match coordinate; this must not create a causal record.
                context.vibratoEffects[1].stepUpdates = [.init(syntheticTick: raw.syntheticTick,
                    scheduledFrame: raw.scheduledFrame + 1, linearPeriodBefore: raw.linearPeriodBefore,
                    linearPeriodAfter: raw.linearPeriodAfter, playbackStepBefore: raw.playbackStepBefore,
                    playbackStepAfter: raw.playbackStepAfter, reachedTarget: raw.reachedTarget)]
            }
        }
        XCTAssertTrue(context.rowExitObserver.evidence.references.isEmpty)
        XCTAssertEqual(context.vibratoEffects[1].stepUpdates.last?.scheduledFrame, 12_481)
        XCTAssertEqual(context.finePortamentoUpEffects[0].execution.coalescedVibratoExit, false)
    }

    func testSharedDerivationsCachedPlansInvalidationAndStrictLookupBounds() throws {
        let input = song([[c(note: 49, instrument: 1, volume: 0xA4)], [c(volume: 0xB8)],
            [c(4, 0), c(15, 1)], [c(14, 0x11)], [c(0, 0x37), c(15, 6)], [c(14, 0x21)]])
        let plan = A.adapt(input, orderIndex: 0, sampleRate: 48_000)
        XCTAssertEqual(plan.rowExitProvenance.references.count, 2)
        let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: 48_000), rows: 6)
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        var copies = [plan, plan.replacingEventCoverage(plan.diagnostics.eventCoverage),
            PlaybackSongOfflineRenderer.plan(plan, mutingEventsNotIn: []), plan.extendingEnvelopeTail(throughFrame: 100_000),
            renderer.render(request).plan, renderer.renderWindowed(request, windowRows: 1).plan]
        #if DEBUG
        copies.append(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).plan)
        #endif
        for _ in 0..<2 { copies.append(try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000, preparedPlan: plan).plan)) }
        for copy in copies {
            XCTAssertEqual(copy.rowExitProvenance, plan.rowExitProvenance)
            XCTAssertEqual(try observations(copy), try observations(plan))
            plan.rowExitProvenance.references.withUnsafeBufferPointer { original in
                copy.rowExitProvenance.references.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
            }
            plan.rowExitProvenance.exceptionalScalars.withUnsafeBufferPointer { original in
                copy.rowExitProvenance.exceptionalScalars.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
            }
            for index in plan.nativePitchWriterSpans.spans.indices {
                plan.nativePitchWriterSpans.spans[index].originalChildren.withUnsafeBufferPointer { original in
                    copy.nativePitchWriterSpans.spans[index].originalChildren.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
                }
            }
        }
        for index in [-1, 2, Int.max, Int.min] { XCTAssertNil(plan.suppressedRowExit(at: index)) }
        let evidence = plan.rowExitProvenance
        let valid = evidence.references[0]
        for (outgoing, incoming, witness) in [(-1, 0, 0), (Int.max, 0, 0), (1, -1, 0),
            (1, Int.max, 0), (1, 0, -1), (1, 0, Int.max)] {
            var malformed = plan
            malformed.rowExitProvenance = .init(coverage: evidence.coverage, domain: evidence.domain,
                references: [.init(outgoingDiagnosticIndex: outgoing, incomingDiagnosticIndex: incoming,
                    witnessIndex: witness, witness: valid.witness, incomingFamily: valid.incomingFamily)],
                exceptionalScalars: evidence.exceptionalScalars,
                referenceStorageGrowthCount: evidence.referenceStorageGrowthCount,
                scalarStorageGrowthCount: evidence.scalarStorageGrowthCount,
                lookupCapacityHighWatermark: evidence.lookupCapacityHighWatermark,
                lookupStorageGrowthCount: evidence.lookupStorageGrowthCount)
            XCTAssertNil(malformed.suppressedRowExit(at: 0))
        }
        var changed = plan
        changed.diagnostics.vibratoEffects.removeAll()
        XCTAssertEqual(changed.rowExitProvenance.coverage, .notAdapterProduced)
        XCTAssertNil(changed.suppressedRowExit(at: 0))
        XCTAssertEqual(changed.nativePitchWriterSpans.coverage, .notAdapterProduced)
        let manual = PlaybackSongSyntheticPlan(timingConfig: plan.timingConfig, pattern: plan.pattern,
            diagnostics: plan.diagnostics, canonicalTickClock: plan.canonicalTickClock, selectionDispatchFacts: plan.selectionDispatchFacts)
        XCTAssertEqual(manual.rowExitProvenance.coverage, .notAdapterProduced)
        XCTAssertNil(manual.suppressedRowExit(at: 0))
    }

    private func observations(_ plan: PlaybackSongSyntheticPlan) throws -> [E.Observation] {
        try plan.rowExitProvenance.references.indices.map { try XCTUnwrap(plan.suppressedRowExit(at: $0)) }
    }
    private func incomingFamily(_ cell: PlaybackCell) -> E.IncomingFamily {
        if cell.effectType == 0 { return .arpeggio }
        if cell.effectType == 14 { return cell.effectParam >> 4 == 1 ? .finePortamentoUp : .finePortamentoDown }
        return cell.effectParam >> 4 == 1 ? .extraFinePortamentoUp : .extraFinePortamentoDown
    }
    private func incomingPeriod(_ cell: PlaybackCell, linear: Bool) -> Double {
        let amount = cell.effectType == 14 ? (linear ? 4.0 : 16) : (linear ? 1.0 : 4)
        return (linear ? 4608.0 : 6848) + (cell.effectParam >> 4 == 1 ? -amount : amount)
    }
    private func incomingChild(_ plan: PlaybackSongSyntheticPlan, _ cell: PlaybackCell) -> PlaybackSongSyntheticTonePortamentoStepUpdate? {
        if cell.effectType == 33 { return plan.diagnostics.extraFinePortamentoEffects.last?.stepUpdates.first }
        return cell.effectParam >> 4 == 1 ? plan.diagnostics.finePortamentoUpEffects.last?.stepUpdates.first : plan.diagnostics.finePortamentoDownEffects.last?.stepUpdates.first
    }
    private func fineExecution(_ plan: PlaybackSongSyntheticPlan, _ cell: PlaybackCell) -> PlaybackSongSyntheticFinePitchExecution? {
        if cell.effectType == 33 { return plan.diagnostics.extraFinePortamentoEffects.last?.execution }
        return cell.effectParam >> 4 == 1 ? plan.diagnostics.finePortamentoUpEffects.last?.execution : plan.diagnostics.finePortamentoDownEffects.last?.execution
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ rows: [[PlaybackCell]], linear: Bool = true, speed: Int = 6, bpm: Int = 125,
                      relative: Int = 0, completed: Bool = false, split: Int? = nil) -> PlaybackSong {
        let pcm: [Float] = [0.125, -0.375, 0.25, -0.0625, 0.5, -0.25, 0.0625, -0.125]
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: pcm, volume: 0.5, relativeNote: relative,
            finetune: 0, baseSampleRate: 8363, loopLength: completed ? 0 : 8, loopType: completed ? 0 : 1)
        let alternate = PlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: Array(pcm.reversed()), volume: 0.75,
            relativeNote: relative, finetune: 0, baseSampleRate: 8363, loopLength: 8, loopType: 1)
        let empty = PlaybackSample(instrumentIndex: 4, sampleIndex: 1, pcm: [], volume: 0,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        let chunks = split.map { [Array(rows[..<$0]), Array(rows[$0...])] } ?? [rows]
        let patterns = chunks.enumerated().map { index, chunk in
            PlaybackPattern(index: index, rows: chunk.enumerated().map { .init(index: $0.offset,
                cells: $0.element + Array(repeating: c(), count: max(0, 2 - $0.element.count))) })
        }
        return .init(title: "Public suppressed row exit provenance", orders: patterns.map { .init(orderIndex: $0.index, patternIndex: $0.index) },
            patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.map { ($0.index, $0) }),
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96)),
                2: .init(index: 2, samples: [alternate], noteSampleMap: Array(repeating: 0, count: 96)),
                3: .init(index: 3, samples: [], noteSampleMap: Array(repeating: 0, count: 96)),
                4: .init(index: 4, samples: [sample, empty], noteSampleMap: Array(repeating: 1, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: bpm), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [4: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: true, volume: 0, panning: 0, finetune: 0, relativeNote: 0)]])
    }
}
