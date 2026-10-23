import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Independently specified public controls for partial child-bearing native observations.
final class NativePitchWriterSpanTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias W = PlaybackSongNativePitchWriterSpans
    private let rates = [44_100.0, 48_000]

    func testLiteralSevenFamilyChildrenAcrossDomainsRatesAndSpeeds() throws {
        for linear in [true, false] { for rate in rates { for speed in [1, 3, 6] {
            let base = linear ? 4608.0 : 6848
            let up = linear ? [4604.0, 4600, 4596, 4592, 4588] : [6832, 6816, 6800, 6784, 6768]
            let down = linear ? [4612.0, 4616, 4620, 4624, 4628] : [6864, 6880, 6896, 6912, 6928]
            let modulation = linear ? [4608.0, 4632, 4653, 4666, 4671] : [6848, 6944, 7028, 7080, 7100]
            let arp = speed == 1 ? [base] : speed == 3
                ? (linear ? [4608.0, 4160, 4416] : [6848, 4560, 5760])
                : (linear ? [4608.0, 4160, 4416, 4608, 4160, 4416] : [6848, 4560, 5760, 6848, 4560, 5760])
            let cases: [(PlaybackCell, W.Family, [Double], Int)] = [
                (c(3, 1, note: 61), .tonePortamento, Array(up.prefix(speed - 1)), 1),
                (c(1, 1), .portamentoSlide, Array(up.prefix(speed - 1)), 1),
                (c(2, 1), .portamentoSlide, Array(down.prefix(speed - 1)), 1),
                (c(14, 0x11), .finePortamentoUp, [linear ? 4604 : 6832], 0),
                (c(14, 0x21), .finePortamentoDown, [linear ? 4612 : 6864], 0),
                (c(33, 0x11), .extraFinePortamento, [linear ? 4607 : 6844], 0),
                (c(33, 0x21), .extraFinePortamento, [linear ? 4609 : 6852], 0),
                (c(0, 0x37), .arpeggio, arp, 0),
                (c(4, 0x48), .vibrato, Array(modulation.prefix(speed - 1)), 1),
                (c(6), .vibrato, Array(repeating: base, count: speed - 1), 1),
                (c(volume: 0xB8), .vibrato, Array(modulation.prefix(speed - 1)), 1)
            ]
            for (cell, family, periods, firstTick) in cases {
                let plan = A.adapt(song([birth, cell], linear: linear, speed: speed), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.nativePitchWriterSpans.coverage, .partialChildBearingProducersV1)
                let observed = try observations(plan)
                XCTAssertEqual(observed.map(\.nativePeriodAfter), periods, "\(family), speed \(speed)")
                XCTAssertEqual(observed.map(\.family), Array(repeating: family, count: periods.count))
                XCTAssertEqual(plan.nativePitchWriterSpans.spans.count, periods.isEmpty ? 0 : 1)
                for (ordinal, value) in observed.enumerated() {
                    XCTAssertEqual(value.diagnosticIndex, 0); XCTAssertEqual(value.childIndex, ordinal)
                    XCTAssertEqual(value.producerAppendOrdinal, 0); XCTAssertEqual(value.associatedGeneration, 0)
                    XCTAssertEqual(value.source, .init(orderIndex: 0, patternIndex: 0, rowIndex: 1))
                    XCTAssertEqual(value.syntheticRow, 1); XCTAssertEqual(value.channelIndex, 0)
                    XCTAssertEqual(value.syntheticTick, firstTick + ordinal)
                    XCTAssertEqual(value.scheduledFrame, (speed + firstTick + ordinal) * Int(rate / 50))
                    XCTAssertEqual(value.domain, linear ? .linear : .amigaVTX4x)
                    XCTAssertEqual(value.delivery, .retainedDiagnosticChild)
                }
            }
        } } }
    }

    func testSeededFiveFxAndSixRetainDistinctExistingProducers() throws {
        for linear in [true, false] { for rate in rates { for speed in [3, 6] {
            for (effect, first): (PlaybackCell, Double) in [
                (c(5), linear ? (speed == 3 ? 4596 : 4584) : (speed == 3 ? 6800 : 6752)),
                (c(volume: 0xF1), linear ? (speed == 3 ? 4536 : 4524) : (speed == 3 ? 6560 : 6512))
            ] {
                let plan = A.adapt(song([birth, c(3, 1, note: 61), effect], linear: linear, speed: speed), orderIndex: 0, sampleRate: rate)
                let values = try observations(plan).filter { $0.syntheticRow == 2 }
                XCTAssertEqual(values.count, speed - 1); XCTAssertEqual(values.first?.nativePeriodAfter, first)
                XCTAssertTrue(values.allSatisfy { $0.family == .tonePortamento && $0.diagnosticIndex == 1 && $0.associatedGeneration == 0 })
            }
            let plan = A.adapt(song([birth, c(4, 0x48), c(6)], linear: linear, speed: speed), orderIndex: 0, sampleRate: rate)
            let six = try observations(plan).filter { $0.syntheticRow == 2 }
            XCTAssertEqual(six.first?.nativePeriodAfter, linear ? (speed == 3 ? 4653 : 4666) : (speed == 3 ? 7028 : 7080))
            XCTAssertEqual(six.count, speed - 1); XCTAssertEqual(six.first?.diagnosticIndex, 1)
        } } }
    }

    func testBothSameTickBxAndEffectWritersRemainOrderedAndSyntheticExitIsUncaptured() throws {
        for linear in [true, false] { for rate in rates { for effect: UInt8 in [4, 6] {
            let plan = A.adapt(song([birth, c(effect, effect == 4 ? 0x48 : 0, volume: 0xB8), c()], linear: linear), orderIndex: 0, sampleRate: rate)
            let values = try observations(plan)
            XCTAssertEqual(values.map(\.syntheticTick), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
            XCTAssertEqual(values.map(\.nativePeriodAfter), linear
                ? [4608, 4632, 4653, 4666, 4671, 4666, 4653, 4632, 4608, 4584]
                : [6848, 6944, 7028, 7080, 7100, 7080, 7028, 6944, 6848, 6752])
            XCTAssertEqual(values.map(\.childIndex), Array(0..<10))
            XCTAssertEqual(plan.nativePitchWriterSpans.spans.count, 1)
            XCTAssertEqual(plan.nativePitchWriterSpans.spans[0].capturedChildCount, 10)
            XCTAssertNil(plan.nativePitchWriter(span: 0, child: 10))
            XCTAssertFalse(values.contains { $0.syntheticTick == 6 })
        } } }
    }

    func testNativeZeroAndSameQ16DifferentNativeOutputsAreNotMerged() throws {
        for linear in [true, false] { for rate in rates {
            let zero = A.adapt(song([c(note: 49, instrument: 1), c(0, 0x37)], linear: linear, relative: -49), orderIndex: 0, sampleRate: rate)
            let value = try XCTUnwrap(zero.nativePitchWriter(span: 0, child: 0))
            XCTAssertEqual(value.nativePeriodBefore, 0); XCTAssertEqual(value.nativePeriodAfter, 0)
            XCTAssertEqual(value.associatedGeneration, 0); XCTAssertEqual(value.syntheticTick, 0)
            XCTAssertNotNil(zero.nativePitchWriter(span: 0, child: 0))
            // A 1 Hz PlaybackSong model rate is intentionally coarser than parser-produced tuning.
            let plan = A.adapt(song(chain, linear: linear, baseRate: 1), orderIndex: 0, sampleRate: rate)
            let bx = try XCTUnwrap(plan.nativePitchWriter(span: 0, child: 4))
            let slide = try XCTUnwrap(plan.nativePitchWriter(span: 1, child: 4))
            XCTAssertEqual(bx.nativePeriodAfter, linear ? 4671 : 7100)
            XCTAssertEqual(slide.nativePeriodAfter, linear ? 4588 : 6768)
            XCTAssertEqual(plan.nativePitchWriterSpans.spans[0].child(at: 4)?.playbackStepAfter, 1.0 / 65536)
            XCTAssertEqual(plan.nativePitchWriterSpans.spans[1].child(at: 4)?.playbackStepAfter, 1.0 / 65536)
            XCTAssertNotEqual(bx.nativePeriodAfter, slide.nativePeriodAfter)
        } }
    }

    func testChildlessHoldsBlankRowsAndSourceLessPhaseRemainNegativeCoverage() throws {
        for linear in [true, false] { for rate in rates {
            let plan = A.adapt(song(chain, linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.nativePitchWriterSpans.spans.map(\.family), [.vibrato, .portamentoSlide])
            XCTAssertEqual(try observations(plan).map(\.syntheticRow), Array(repeating: 1, count: 5) + Array(repeating: 3, count: 5))
            let known = plan.heldPitchProvenance.rowHolds.compactMap { hold -> Double? in
                guard case let .known(value) = hold.held else { return nil }; return value.nativePeriod
            }
            XCTAssertEqual(known, linear ? [4671, 4588] : [7100, 6768])
            let blank = A.adapt(song([birth, c(), c(3)], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(blank.nativePitchWriterSpans.spans.isEmpty)
            let cold = A.adapt(song([c(volume: 0xA4), c(volume: 0xB8), c(14, 0x10)], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(cold.nativePitchWriterSpans.spans.isEmpty); XCTAssertTrue(cold.pattern.events.isEmpty)
            XCTAssertTrue(cold.selectionDispatchFacts.facts.allSatisfy { $0.associatedGeneration == nil })
            XCTAssertEqual(cold.diagnostics.vibratoEffects.first?.phaseAfter, 80)
        } }
    }

    func testG23ActualNonzeroInvocationsDoNotAcquireFabricatedChildCoordinates() throws {
        for linear in [true, false] { for rate in rates {
            let plan = A.adapt(song([birth, c(14, 0xD3, instrument: 2, volume: 0xF0)], linear: linear), orderIndex: 0, sampleRate: rate)
            // The existing handler really iterates ticks 1...5, while these no-target
            // diagnostics retain row scope. This observation does not repair that gap.
            let commands = plan.diagnostics.tonePortamentoEffects
            XCTAssertEqual(commands.count, 5)
            XCTAssertEqual(commands.map(\.syntheticTick), [0, 0, 0, 0, 0])
            XCTAssertTrue(commands.allSatisfy { $0.syntheticRow == 1 && $0.stepUpdates.isEmpty })
            XCTAssertTrue(plan.nativePitchWriterSpans.spans.isEmpty)
            XCTAssertNil(plan.nativePitchWriter(span: 0, child: 0))
            XCTAssertEqual(plan.pattern.events.count, 2)
            XCTAssertEqual(plan.pattern.events[1].scheduledStartFrame, 9 * Int(rate / 50))
        } }
    }

    func testFoldedFineBirthsRemainZeroChildrenAndCompletedSourceRawChildrenSurviveAdmission() throws {
        for linear in [true, false] { for rate in rates {
            for command in [c(14, 0x11, note: 49, instrument: 1), c(14, 0x21, note: 49, instrument: 1),
                            c(33, 0x11, note: 49, instrument: 1), c(33, 0x21, note: 49, instrument: 1)] {
                let folded = A.adapt(song([command], linear: linear), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(folded.pattern.events.count, 1); XCTAssertTrue(folded.nativePitchWriterSpans.spans.isEmpty)
                XCTAssertEqual(folded.diagnostics.finePortamentoUpEffects.first?.appliedToInitialPlaybackStep
                    ?? folded.diagnostics.finePortamentoDownEffects.first?.appliedToInitialPlaybackStep
                    ?? folded.diagnostics.extraFinePortamentoEffects.first?.appliedToInitialPlaybackStep, true)
            }
            for (command, family, period): (PlaybackCell, W.Family, Double) in [
                (c(14, 0x11), .finePortamentoUp, linear ? 4604 : 6832),
                (c(14, 0x21), .finePortamentoDown, linear ? 4612 : 6864),
                (c(33, 0x11), .extraFinePortamento, linear ? 4607 : 6844)] {
                let completed = A.adapt(song([birth, command], linear: linear, completed: true), orderIndex: 0, sampleRate: rate)
                let raw = try XCTUnwrap(completed.nativePitchWriter(span: 0, child: 0))
                XCTAssertEqual(raw.family, family); XCTAssertEqual(raw.nativePeriodAfter, period)
                XCTAssertEqual(raw.delivery, .suppressedNoActiveSource); XCTAssertEqual(raw.associatedGeneration, 0)
                XCTAssertEqual(raw.scheduledFrame, 6 * Int(rate / 50))
                XCTAssertEqual(completed.pattern.events.count, 1)
                XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: raw.scheduledFrame, plan: completed))
            }
        } }
    }

    func testImmutableBackingDerivationsPreparedReuseAndDiagnosticInvalidation() throws {
        let input = song(chain), plan = A.adapt(input, orderIndex: 0, sampleRate: 48_000)
        let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: 48_000), rows: chain.count)
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        var copies = [plan.replacingEventCoverage(plan.diagnostics.eventCoverage),
            PlaybackSongOfflineRenderer.plan(plan, mutingEventsNotIn: []), plan.extendingEnvelopeTail(throughFrame: 100_000),
            renderer.render(request).plan, renderer.renderWindowed(request, windowRows: 1).plan]
        #if DEBUG
        copies.append(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).plan)
        #endif
        for _ in 0..<2 { copies.append(try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000, preparedPlan: plan).plan)) }
        for copy in copies {
            XCTAssertEqual(copy.nativePitchWriterSpans, plan.nativePitchWriterSpans)
            XCTAssertEqual(copy.selectionDispatchFacts, plan.selectionDispatchFacts)
            XCTAssertEqual(copy.heldPitchProvenance, plan.heldPitchProvenance)
            for index in plan.nativePitchWriterSpans.spans.indices {
                plan.nativePitchWriterSpans.spans[index].originalChildren.withUnsafeBufferPointer { original in
                    copy.nativePitchWriterSpans.spans[index].originalChildren.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
                }
            }
        }
        let manual = PlaybackSongSyntheticPlan(timingConfig: plan.timingConfig, pattern: plan.pattern,
            diagnostics: plan.diagnostics, canonicalTickClock: plan.canonicalTickClock, selectionDispatchFacts: plan.selectionDispatchFacts)
        XCTAssertEqual(manual.nativePitchWriterSpans.coverage, .notAdapterProduced)
        var changed = plan
        changed.diagnostics.vibratoEffects.removeAll()
        XCTAssertEqual(changed.nativePitchWriterSpans.coverage, .notAdapterProduced)
        XCTAssertNil(changed.nativePitchWriter(span: 0, child: 0))
        XCTAssertEqual(changed.heldPitchProvenance.coverage, .notAdapterProduced)
        XCTAssertEqual(changed.selectionDispatchFacts, plan.selectionDispatchFacts)
        XCTAssertEqual(plan.nativePitchWriterSpans.spans.count, 2)
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride, 1152)
        XCTAssertEqual(MemoryLayout<PlaybackXMChannelRow>.stride, 8)
        XCTAssertEqual(MemoryLayout<PlaybackSongSelectionDispatchFacts.Fact>.stride, 288)
        XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticTonePortamentoStepUpdate>.stride, 144)
        XCTAssertEqual(MemoryLayout<W.Span>.stride, 32)
    }

    func testClampsDeclaredEmptyAndActualProducerAppendOrderKeepIndependentMeaning() throws {
        for linear in [true, false] { for rate in rates {
            let clamped = A.adapt(song([c(note: 96, instrument: 1), c(1, 255)], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(try observations(clamped).map(\.nativePeriodAfter), linear ? [580, 1] : [4])
            XCTAssertEqual(clamped.nativePitchWriterSpans.spans.first?.originalChildren.last?.clamped, true)
            let empty = A.adapt(song([c(note: 49, instrument: 3, volume: 0xA4), c(14, 0x11), c(volume: 0xB8)], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(empty.pattern.events.isEmpty); XCTAssertTrue(empty.nativePitchWriterSpans.spans.isEmpty)
            XCTAssertEqual(empty.selectionDispatchFacts.facts.first?.role, .emptySelection)
            XCTAssertNil(empty.selectionDispatchFacts.facts.first?.associatedGeneration)
            let base = song([birth], linear: linear)
            let input = PlaybackSong(title: base.title, orders: base.orders,
                patternsByIndex: [0: .init(index: 0, rows: [.init(index: 0, cells: [birth, birth]),
                    .init(index: 1, cells: [c(14, 0x11), c(1, 1)])])],
                instrumentsByIndex: base.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: base.initialTiming, usesLinearFrequencyTable: linear)
            let ordered = A.adapt(input, orderIndex: 0, sampleRate: rate)
            // Channel-zero fine arithmetic completes before channel-one's row slide;
            // runtime's seven-family fanout has the opposite family order.
            XCTAssertEqual(ordered.nativePitchWriterSpans.spans.map(\.family), [.finePortamentoUp, .portamentoSlide])
            XCTAssertEqual(ordered.nativePitchWriterSpans.spans.map(\.diagnosticIndex), [0, 0])
            let values = try observations(ordered)
            XCTAssertEqual(values.map(\.associatedGeneration), [0, 1, 1, 1, 1, 1])
            XCTAssertEqual(values.map(\.channelIndex), [0, 1, 1, 1, 1, 1])
            let replaced = A.adapt(song([birth, c(1, 1, note: 49, instrument: 2)], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(try observations(replaced).allSatisfy { $0.associatedGeneration == 1 && $0.syntheticRow == 1 })
            XCTAssertEqual(replaced.selectionDispatchFacts.facts.last?.associatedGeneration, 1)
        } }
    }

    func testRawDelayedBirthCalculationSurvivesAndRowExitRemainsOutsideCoverage() throws {
        for linear in [true, false] { for rate in rates {
            let delayed = A.adapt(song([birth, c(14, 0xD3, note: 49, instrument: 2, volume: 0xB8)], linear: linear), orderIndex: 0, sampleRate: rate)
            let values = try observations(delayed)
            XCTAssertEqual(values.map(\.syntheticTick), [1, 2, 3, 4, 5])
            XCTAssertEqual(values.map(\.associatedGeneration), [0, 0, 0, 1, 1])
            XCTAssertEqual(values.map(\.nativePeriodAfter), linear ? [4608, 4632, 4653, 4608, 4632] : [6848, 6944, 7028, 6848, 6944])
            XCTAssertEqual(values[2].delivery, .supersededDelayedBirth)
            XCTAssertEqual(delayed.diagnostics.vibratoEffects.flatMap(\.stepUpdates).count, 4)
            let exit = A.adapt(song([birth, c(0, 0x37), c(14, 0x11)], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertNotNil(exit.diagnostics.arpeggioEffects.first?.subsumedRowExit)
            XCTAssertEqual(exit.nativePitchWriterSpans.spans.first?.capturedChildCount, 6)
            XCTAssertNil(exit.nativePitchWriter(span: 0, child: 6))
        } }
    }

    private func observations(_ plan: PlaybackSongSyntheticPlan) throws -> [W.Observation] {
        try plan.nativePitchWriterSpans.spans.indices.flatMap { span in
            try (0..<plan.nativePitchWriterSpans.spans[span].capturedChildCount).map { child in
                try XCTUnwrap(plan.nativePitchWriter(span: span, child: child))
            }
        }
    }
    private var birth: PlaybackCell { c(note: 49, instrument: 1, volume: 0xA4) }
    private var chain: [PlaybackCell] { [birth, c(volume: 0xB8), c(3), c(1, 1), c(3)] }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                   instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ cells: [PlaybackCell], linear: Bool = true, speed: Int = 6,
                      baseRate: Double = 8363, relative: Int = 0, completed: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: [0.125, -0.375, 0.25, -0.0625, 0.5, -0.25, 0.0625, -0.125], volume: 0.5,
            relativeNote: relative, finetune: 0, baseSampleRate: baseRate,
            loopLength: completed ? 0 : 8, loopType: completed ? 0 : 1)
        let other = PlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: sample.pcm, volume: 0.5,
            relativeNote: relative, finetune: 0, baseSampleRate: baseRate, loopLength: 8, loopType: 1)
        return .init(title: "Public native numeric writer controls", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96)),
                                 2: .init(index: 2, samples: [other], noteSampleMap: Array(repeating: 0, count: 96)),
                                 3: .init(index: 3, samples: [], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: 32, panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
