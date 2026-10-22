import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Literal public controls for the partial Bx/1xx/targetless-300 causal invariant.
final class NativeHeldPitchProvenanceTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias H = PlaybackSongHeldPitchProvenance
    private let rates = [44_100.0, 48_000]

    func testLiteralChainRetainsNativeProducerRatherThanCanonicalOrStaleVibratoPitch() throws {
        for linear in [true, false] { for rate in rates {
            let input = song(chain, linear: linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.heldPitchProvenance.coverage, .partialBxUpSlideTargetlessRows)
            XCTAssertEqual(plan.heldPitchProvenance.rowHolds.map(\.toneDiagnosticIndex), [0, 1])
            let first = try known(plan, at: 0), second = try known(plan, at: 1)
            XCTAssertEqual(first.nativePeriod, linear ? 4671 : 7100)
            XCTAssertEqual(second.nativePeriod, linear ? 4588 : 6768)
            XCTAssertEqual(first.domain, linear ? .linear : .amigaVTX4x)
            XCTAssertEqual(second.domain, first.domain)
            XCTAssertEqual(first.producer, .volumeColumnVibrato(diagnostic: 0, child: 4))
            XCTAssertEqual(second.producer, .portamentoUp(diagnostic: 0, child: 4))
            XCTAssertEqual(first.selectionFactIndex, 0); XCTAssertEqual(second.selectionFactIndex, 0)
            let owner = plan.selectionDispatchFacts.facts[first.selectionFactIndex]
            XCTAssertEqual(owner.semanticInstrument, 1); XCTAssertEqual(owner.semanticSample, 0)
            XCTAssertEqual(owner.associatedGeneration, 0)
            XCTAssertEqual(plan.diagnostics.tonePortamentoEffects.map(\.syntheticRow), [2, 4])
            XCTAssertTrue(plan.diagnostics.tonePortamentoEffects.allSatisfy { $0.status == .noTarget && $0.stepUpdates.isEmpty })
            let generic = plan.diagnostics.tonePortamentoEffects[0]
            XCTAssertEqual(linear ? generic.currentLinearPeriodAfter : generic.currentAmigaPeriodAfter, linear ? 4608 : 6848)
            let originalBx = try XCTUnwrap(plan.diagnostics.vibratoEffects[0].stepUpdates.last)
            XCTAssertEqual(linear ? originalBx.linearPeriodAfter : originalBx.amigaPeriodAfter, first.nativePeriod)
            XCTAssertNotEqual(first.nativePeriod, second.nativePeriod)
            XCTAssertEqual(plan.pattern.events.count, 1)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate, preparedPlan: plan)
            XCTAssertFalse(runtime.events.contains { [2, 4].contains($0.source.rowIndex) })
            let controls = try XCTUnwrap(plan.xmChannelRows.first { $0.syntheticRow == 4 }).controls
            XCTAssertEqual(linear ? controls.vibratoOutputLinearPeriod : controls.vibratoOutputAmigaPeriod, linear ? 4671 : 7100)
            XCTAssertEqual(linear ? controls.activeLinearPeriod : controls.activeAmigaPeriod, linear ? 4588 : 6768)
            let bxQ16 = rate == 48_000 ? (linear ? 10787 : 11013) : (linear ? 11741 : 11986)
            let slideQ16 = rate == 48_000 ? (linear ? 11626 : 11553) : (linear ? 12654 : 12574)
            XCTAssertEqual(originalBx.playbackStepAfter, Double(bxQ16) / 65536)
            XCTAssertEqual(plan.diagnostics.portamentoSlideEffects[0].stepUpdates.last?.playbackStepAfter, Double(slideQ16) / 65536)
        } }
    }

    func testDistinctNativeOutputsRemainDistinctWhenTheirQ16StepsAreIdentical() throws {
        // A positive 1 Hz synthetic source rate deliberately makes the conversion coarse.
        // This is a PlaybackSong model control, not a claim about parser-produced XM tuning.
        for linear in [true, false] { for rate in rates {
            let plan = A.adapt(song(chain, linear: linear, baseRate: 1), orderIndex: 0, sampleRate: rate)
            let first = try known(plan, at: 0), second = try known(plan, at: 1)
            XCTAssertEqual(first.nativePeriod, linear ? 4671 : 7100)
            XCTAssertEqual(second.nativePeriod, linear ? 4588 : 6768)
            let bx = try XCTUnwrap(plan.diagnostics.vibratoEffects[0].stepUpdates.last)
            let slide = try XCTUnwrap(plan.diagnostics.portamentoSlideEffects[0].stepUpdates.last)
            XCTAssertEqual(bx.playbackStepAfter, 1.0 / 65536)
            XCTAssertEqual(slide.playbackStepAfter, 1.0 / 65536)
            XCTAssertNotEqual(first.producer, second.producer)
        } }
    }

    func testBlankRowsPreserveHeldOutputWithoutCreatingNewProducers() throws {
        for linear in [true, false] { for rate in rates {
            let input = song([birth, c(volume: 0xB8), c(), c(), c(3)], linear: linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let held = try known(plan, at: 0)
            XCTAssertEqual(held.nativePeriod, linear ? 4671 : 7100)
            XCTAssertEqual(held.producer, .volumeColumnVibrato(diagnostic: 0, child: 4))
            XCTAssertEqual(plan.heldPitchProvenance.rowHolds.count, 1)
            XCTAssertEqual(plan.diagnostics.tonePortamentoEffects[0].syntheticRow, 4)
        } }
    }

    func testSelectedKnownZeroUnknownAndUnmodeledPitchHaveDifferentCoverageStates() throws {
        for linear in [true, false] { for rate in rates {
            let zero = A.adapt(song([c(note: 49, instrument: 2), c(3)], linear: linear), orderIndex: 0, sampleRate: rate)
            let value = try known(zero, at: 0)
            XCTAssertEqual(value.nativePeriod, 0); XCTAssertEqual(value.producer, .selectionFact(0))
            XCTAssertEqual(zero.selectionDispatchFacts.facts[value.selectionFactIndex].associatedGeneration, 0)
            let cold = A.adapt(song([c(3), c(), c(3)], linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(cold.heldPitchProvenance.rowHolds.map(\.held), [.notEstablished, .notEstablished])
            let unsupported = A.adapt(song([birth, c(volume: 0xB8), c(0, 0x37), c(3)], linear: linear),
                orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(unsupported.heldPitchProvenance.rowHolds.map(\.held), [.notCaptured])
        } }
    }

    func testPlainNewBirthAndSupportedNoteOnlyBirthSeedTheActualNewSelection() throws {
        for linear in [true, false] { for rate in rates { for instrument: UInt8 in [0, 1] {
            let plan = A.adapt(song([birth, c(volume: 0xB8), c(note: 49, instrument: instrument), c(3)], linear: linear),
                orderIndex: 0, sampleRate: rate)
            let value = try known(plan, at: 0)
            XCTAssertEqual(value.nativePeriod, linear ? 4608 : 6848)
            XCTAssertEqual(value.producer, .selectionFact(1)); XCTAssertEqual(value.selectionFactIndex, 1)
            let fact = plan.selectionDispatchFacts.facts[value.selectionFactIndex]
            XCTAssertEqual(fact.role, .trigger); XCTAssertEqual(fact.noteOnly, instrument == 0)
            XCTAssertEqual(fact.associatedGeneration, 1); XCTAssertEqual(fact.source.rowIndex, 2)
            XCTAssertEqual(fact.semanticInstrument, 1); XCTAssertEqual(fact.semanticSample, 0)
        } } }
    }

    func testDeclaredEmptySelectionCanEstablishNativePitchWithoutSourceGeneration() throws {
        for linear in [true, false] { for rate in rates {
            let plan = A.adapt(song([c(note: 49, instrument: 3), c(3)], linear: linear), orderIndex: 0, sampleRate: rate)
            let value = try known(plan, at: 0)
            XCTAssertEqual(value.nativePeriod, linear ? 4608 : 6848)
            XCTAssertEqual(value.producer, .selectionFact(0))
            let fact = plan.selectionDispatchFacts.facts[value.selectionFactIndex]
            XCTAssertEqual(fact.role, .emptySelection); XCTAssertNil(fact.associatedGeneration)
            XCTAssertEqual(fact.semanticInstrument, 3); XCTAssertEqual(fact.semanticSample, 0)
            XCTAssertTrue(plan.pattern.events.isEmpty)
        } }
    }

    func testChildlessSourceLessBxCarriesSelectionWithoutInventingANewNativeProducer() throws {
        for linear in [true, false] { for rate in rates {
            let plan = A.adapt(song([c(note: 49, instrument: 3, volume: 0xA4), c(volume: 0xB8), c(3)], linear: linear),
                orderIndex: 0, sampleRate: rate)
            let value = try known(plan, at: 0)
            XCTAssertEqual(value.nativePeriod, linear ? 4608 : 6848)
            XCTAssertEqual(value.producer, .selectionFact(0))
            XCTAssertNil(plan.selectionDispatchFacts.facts[value.selectionFactIndex].associatedGeneration)
            XCTAssertEqual(plan.diagnostics.vibratoEffects[0].status, .noActiveVoice)
            XCTAssertTrue(plan.diagnostics.vibratoEffects[0].stepUpdates.isEmpty)
        } }
    }

    func testUnmodeledWritersAndComplexDispatchFailClosedUntilProvenReselection() throws {
        let unmodeled = [c(4, 0x48, volume: 0xB8), c(4, 0x48), c(0, 0x37), c(2, 1),
            c(14, 0x11), c(14, 0x21), c(33, 0x11), c(33, 0x21),
            c(14, 0x93), c(27, 0x93), c(14, 0xD3, instrument: 1, volume: 0xB8),
            c(14, 0xD3, note: 49, instrument: 1, volume: 0xB8), c(instrument: 1)]
        for linear in [true, false] { for effect in unmodeled {
            let plan = A.adapt(song([birth, c(volume: 0xB8), effect, c(3), c(note: 49, instrument: 1), c(3)], linear: linear),
                orderIndex: 0, sampleRate: 48_000)
            XCTAssertEqual(plan.heldPitchProvenance.rowHolds.first?.held, .notCaptured)
            let recovered = try known(plan, at: plan.heldPitchProvenance.rowHolds.count - 1)
            XCTAssertEqual(recovered.nativePeriod, linear ? 4608 : 6848)
            XCTAssertEqual(plan.selectionDispatchFacts.facts[recovered.selectionFactIndex].source.rowIndex, 4)
        } }
    }

    func testToneTargetDoesNotMasqueradeAsTargetlessRowEvidence() {
        let plan = A.adapt(song([birth, c(volume: 0xB8), c(3, 1, note: 61), c(3)]),
            orderIndex: 0, sampleRate: 48_000)
        XCTAssertTrue(plan.heldPitchProvenance.rowHolds.isEmpty)
        XCTAssertTrue(plan.diagnostics.tonePortamentoEffects.allSatisfy(\.targetExistsAfter))
    }

    func testNilMapMissingAndRefusedSelectionsNeverSeedAFalseKnownOutput() throws {
        for instrument: UInt8 in [4, 5, 6] {
            let plan = A.adapt(song([birth, c(volume: 0xB8), c(note: 49, instrument: instrument), c(3)]),
                orderIndex: 0, sampleRate: 48_000)
            XCTAssertEqual(plan.heldPitchProvenance.rowHolds.first?.held, .notCaptured)
        }
    }

    func testShiftedChannelsKeepIndependentNativeProducersAndDistinctSourceGenerations() throws {
        for linear in [true, false] { for rate in rates {
            let base = song(chain, linear: linear)
            let rows = [[c(), birth], [birth, c(volume: 0xB8)], [c(volume: 0xB8), c(3)],
                [c(3), c(1, 1)], [c(1, 1), c(3)], [c(3), c()]]
            let input = PlaybackSong(title: base.title, orders: base.orders,
                patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
                instrumentsByIndex: base.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: base.initialTiming, usesLinearFrequencyTable: linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let held = try (0..<4).map { try known(plan, at: $0) }
            XCTAssertEqual(held.map(\.nativePeriod), linear ? [4671, 4671, 4588, 4588] : [7100, 7100, 6768, 6768])
            XCTAssertEqual(held.map(\.producer), [.volumeColumnVibrato(diagnostic: 0, child: 4),
                .volumeColumnVibrato(diagnostic: 1, child: 4), .portamentoUp(diagnostic: 0, child: 4),
                .portamentoUp(diagnostic: 1, child: 4)])
            XCTAssertEqual(plan.heldPitchProvenance.rowHolds.map { plan.diagnostics.tonePortamentoEffects[$0.toneDiagnosticIndex].channelIndex }, [1, 0, 1, 0])
            XCTAssertEqual(held.map { plan.selectionDispatchFacts.facts[$0.selectionFactIndex].associatedGeneration }, [0, 1, 0, 1])
            XCTAssertEqual(held.map { plan.selectionDispatchFacts.facts[$0.selectionFactIndex].channel }, [1, 0, 1, 0])
        } }
    }

    func testNaturallyCompletedPCMDoesNotEraseSemanticHeldPitchOrGrantSourceEligibility() throws {
        for linear in [true, false] { for rate in rates {
            let plan = A.adapt(song(chain, linear: linear, completed: true), orderIndex: 0, sampleRate: rate)
            let first = try known(plan, at: 0), second = try known(plan, at: 1)
            XCTAssertEqual(first.nativePeriod, linear ? 4671 : 7100)
            XCTAssertEqual(second.nativePeriod, linear ? 4588 : 6768)
            XCTAssertEqual(plan.selectionDispatchFacts.facts[first.selectionFactIndex].associatedGeneration, 0)
            XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: 12 * Int(rate / 50), plan: plan))
            XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: 24 * Int(rate / 50), plan: plan))
        } }
    }

    func testWitnessesShareBackingAcrossDerivedPreparedAndRepeatedPlans() throws {
        let input = song(chain), plan = A.adapt(input, orderIndex: 0, sampleRate: 48_000)
        let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: 48_000), rows: chain.count)
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        let copies = [plan.replacingEventCoverage(plan.diagnostics.eventCoverage),
            PlaybackSongOfflineRenderer.plan(plan, mutingEventsNotIn: []), plan.extendingEnvelopeTail(throughFrame: 100_000),
            renderer.render(request).plan, renderer.renderWindowed(request, windowRows: 1).plan,
            renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).plan]
        for copy in copies {
            XCTAssertEqual(copy.heldPitchProvenance, plan.heldPitchProvenance)
            plan.heldPitchProvenance.rowHolds.withUnsafeBufferPointer { original in
                copy.heldPitchProvenance.rowHolds.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
            }
        }
        for _ in 0..<2 {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000, preparedPlan: plan)
            XCTAssertEqual(runtime.plan?.heldPitchProvenance, plan.heldPitchProvenance)
        }
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride, 1152)
        XCTAssertEqual(MemoryLayout<PlaybackXMChannelRow>.stride, 8)
        XCTAssertEqual(MemoryLayout<PlaybackSongSelectionDispatchFacts.Fact>.stride, 288)
    }

    func testManualAndMutatedPlansDoNotInheritIncompatibleProducerReferences() {
        let plan = A.adapt(song(chain), orderIndex: 0, sampleRate: 48_000)
        let manual = PlaybackSongSyntheticPlan(timingConfig: plan.timingConfig, pattern: plan.pattern,
            diagnostics: plan.diagnostics, canonicalTickClock: plan.canonicalTickClock,
            selectionDispatchFacts: plan.selectionDispatchFacts)
        XCTAssertEqual(manual.heldPitchProvenance.coverage, .notAdapterProduced)
        XCTAssertTrue(manual.heldPitchProvenance.rowHolds.isEmpty)
        var mutated = plan
        mutated.diagnostics.vibratoEffects.removeAll()
        XCTAssertEqual(mutated.heldPitchProvenance.coverage, .notAdapterProduced)
        XCTAssertTrue(mutated.heldPitchProvenance.rowHolds.isEmpty)
        XCTAssertEqual(plan.heldPitchProvenance.rowHolds.count, 2)
        XCTAssertEqual(plan.diagnostics.vibratoEffects.count, 1)
    }

    private func known(_ plan: PlaybackSongSyntheticPlan, at index: Int) throws -> H.Known {
        let witness = try XCTUnwrap(plan.heldPitchProvenance.rowHolds.indices.contains(index)
            ? plan.heldPitchProvenance.rowHolds[index] : nil)
        guard case let .known(value) = witness.held else {
            XCTFail("Expected independently specified known native pitch, got \(witness.held)")
            throw NSError(domain: "NativeHeldPitchProvenanceTests", code: 1)
        }
        return value
    }
    private var birth: PlaybackCell { c(note: 49, instrument: 1, volume: 0xA4) }
    private var chain: [PlaybackCell] { [birth, c(volume: 0xB8), c(3), c(1, 1), c(3)] }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                   instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ cells: [PlaybackCell], linear: Bool = true, baseRate: Double = 8363, completed: Bool = false) -> PlaybackSong {
        var instruments = [Int: PlaybackInstrument]()
        for index in [1, 2, 4, 5] {
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0,
                pcm: [0.125, -0.375, 0.25, -0.0625, 0.5, -0.25, 0.0625, -0.125], volume: 0.5,
                relativeNote: index == 2 ? -49 : index == 4 ? 96 : 0, finetune: 0, baseSampleRate: baseRate,
                loopLength: completed ? 0 : 8, loopType: completed ? 0 : 1)
            instruments[index] = .init(index: index, samples: [sample],
                noteSampleMap: index == 5 ? nil : Array(repeating: 0, count: 96))
        }
        instruments[3] = .init(index: 3, samples: [], noteSampleMap: Array(repeating: 0, count: 96))
        instruments[6] = .init(index: 6, samples: [], noteSampleMap: Array(repeating: 7, count: 96))
        return .init(title: "Public native held-pitch provenance", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: 32, panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
