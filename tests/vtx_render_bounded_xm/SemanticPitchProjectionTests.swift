import Foundation
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif
import XCTest

/// Integrated public controls distinguish native semantic output from physical pitch delivery.
final class SemanticPitchProjectionTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias P = PlaybackSongSemanticPitchProjection
    private let rates = [44_100.0, 48_000]
    private var birth: PlaybackCell { c(note: 49, instrument: 1, volume: 0xA4) }

    func testHeldOutputSurvivesBlankTargetlessRowsAndCoarseConversion() throws {
        for linear in [true, false] { for rate in rates { for baseRate in [8363.0, 1] {
            let plan = adapt([[birth], [c(volume: 0xB8)], [c()], [c(3)], [c(1, 1)], [c(3)]], linear, rate, baseRate: baseRate)
            XCTAssertEqual(plan.semanticPitchProjection.coverage, .nativeDepthOffV1)
            for row in [2, 3] {
                let held = try value(plan, row, 5)
                XCTAssertEqual(held.base, .known(linear ? 4608 : 6848)); XCTAssertEqual(held.output, .known(linear ? 4671 : 7100))
                XCTAssertEqual(held.producer, .nativeWriter(span: 0, child: 4))
            }
            let held = try value(plan, 5, 0)
            XCTAssertEqual(held.base, .known(linear ? 4588 : 6768)); XCTAssertEqual(held.output, held.base)
            XCTAssertEqual(held.producer, .nativeWriter(span: 1, child: 4)); XCTAssertEqual(held.associatedGeneration, 0)
            let controls = try XCTUnwrap(plan.xmChannelRows.first { $0.syntheticRow == 5 }).controls
            XCTAssertEqual(linear ? controls.vibratoOutputLinearPeriod : controls.vibratoOutputAmigaPeriod, linear ? 4671 : 7100)
            if baseRate == 1 {
                XCTAssertEqual(plan.nativePitchWriterSpans.spans[0].originalChildren.last?.playbackStepAfter,
                    plan.nativePitchWriterSpans.spans[1].originalChildren.last?.playbackStepAfter)
            }
        } } }
    }

    func testChildlessFineNativeOutputNeverInventsSourceOrCoverage() throws {
        for linear in [true, false] { for rate in rates {
            let plan = adapt([[c(note: 49, instrument: 3, volume: 0xA4)], [c(14, 0x11)], [c(volume: 0xB8)]], linear, rate)
            XCTAssertTrue(plan.pattern.events.isEmpty); XCTAssertTrue(plan.nativePitchWriterSpans.spans.isEmpty)
            XCTAssertTrue(plan.diagnostics.finePortamentoUpEffects[0].stepUpdates.isEmpty)
            for row in [1, 2] { for tick in [0, 5] {
                let result = try value(plan, row, tick)
                XCTAssertEqual(result.base, .known(linear ? 4604 : 6832)); XCTAssertEqual(result.output, result.base)
                XCTAssertEqual(result.producer, .diagnosticScalar(family: .finePortamentoUp, index: 0))
                XCTAssertEqual(result.semanticInstrument, 3); XCTAssertEqual(result.semanticSample, 0); XCTAssertNil(result.associatedGeneration)
            } }
            let cold = adapt([[c()], [c(3)], [c(volume: 0xB8)]], linear, rate)
            XCTAssertEqual(try value(cold, 2, 5).output, .notEstablished); XCTAssertNil(try value(cold, 2, 5).semanticInstrument)
            let zero = adapt([[c(note: 49, instrument: 4)], [c(3)]], linear, rate)
            XCTAssertEqual(try value(zero, 1, 5).output, .known(0)); XCTAssertEqual(try value(zero, 1, 5).associatedGeneration, 0)
        } }
    }

    func testSevenFamiliesAndFoldedBirthsPublishNativeResults() throws {
        for linear in [true, false] { for rate in rates {
            let cases: [(PlaybackCell, Double, Int)] = [(c(3, 1, note: 61), linear ? 4588 : 6768, 5),
                (c(1, 1), linear ? 4588 : 6768, 5), (c(2, 1), linear ? 4628 : 6928, 5),
                (c(14, 0x11), linear ? 4604 : 6832, 0), (c(14, 0x21), linear ? 4612 : 6864, 0),
                (c(33, 0x11), linear ? 4607 : 6844, 0), (c(0, 0x37), linear ? 4416 : 5760, 5),
                (c(4, 0x48), linear ? 4671 : 7100, 5)]
            for (cell, period, tick) in cases {
                let plan = adapt([[birth], [cell]], linear, rate)
                XCTAssertEqual(try value(plan, 1, tick).output, .known(period), "\(cell)")
            }
            let equalTarget = adapt([[birth], [c(3, 255, note: 50)], [c(volume: 0xB8)], [c(3)]], linear, rate)
            XCTAssertTrue(equalTarget.diagnostics.tonePortamentoEffects[1].stepUpdates.isEmpty)
            XCTAssertEqual(try value(equalTarget, 3, 0).output, .known(linear ? 4607 : 6716))
            XCTAssertEqual(try value(equalTarget, 3, 1).output, .known(linear ? 4544 : 6464))
            XCTAssertEqual(try value(equalTarget, 3, 1).producer, .diagnosticScalar(family: .tonePortamento, index: 1))
            let restarted = adapt([[birth], [c(3, 255, note: 50)], [c(volume: 0xB8)], [c(27, 3, volume: 0xF0)]], linear, rate)
            XCTAssertEqual(try value(restarted, 3, 1).incoming, .known(linear ? 4607 : 6716))
            XCTAssertEqual(try value(restarted, 3, 1).output, .known(linear ? 4544 : 6464))
            XCTAssertEqual(try value(restarted, 3, 1).incomingProducer, .nativeWriter(span: 1, child: 4))
            XCTAssertFalse(restarted.diagnostics.eventMappings.contains { $0.syntheticRow == 3 && $0.syntheticTick == 1 })
            let folded = adapt([[c(14, 0x11, note: 49, instrument: 1)]], linear, rate)
            XCTAssertEqual(try value(folded, 0, 0).output, .known(linear ? 4604 : 6832))
            XCTAssertTrue(folded.nativePitchWriterSpans.spans.isEmpty)
            for effect: UInt8 in [4, 6] {
                let plan = adapt([[birth], [c(effect, effect == 4 ? 0x48 : 0, volume: 0xB8)], [c()]], linear, rate)
                XCTAssertEqual(try value(plan, 1, 2).output, .known(linear ? 4666 : 7080))
                XCTAssertEqual(try value(plan, 1, 2).incoming, .known(linear ? 4653 : 7028))
                XCTAssertEqual(try value(plan, 1, 2).incomingProducer, .nativeWriter(span: 0, child: 2))
                XCTAssertEqual(try value(plan, 1, 2).producer, .nativeWriter(span: 0, child: 3))
                XCTAssertEqual(plan.nativePitchWriterSpans.spans[0].capturedChildCount, 10)
                if linear && rate == 48_000 {
                    let runtime = RuntimeCMixerAdapterEventPlan.make(song: input([[birth], [c(effect, effect == 4 ? 0x48 : 0, volume: 0xB8)], [c()]]), sampleRate: rate, preparedPlan: plan)
                    let requests = runtime.events.filter { $0.scheduledFrame == 7680 }
                    XCTAssertEqual(requests.map(\.id), [3, 4]); XCTAssertEqual(requests.map(\.activeEventIndex), [0, 0])
                    XCTAssertEqual(requests.compactMap { if case let .stepUpdate(_, step) = $0.action { return step }; return nil }, [10963.0 / 65536, 10835.0 / 65536])
                }
            }
        } }
    }

    func testPendingExitsRespectCanonicalTicksSpeedOneAndFxxChannelOrder() throws {
        for linear in [true, false] { for rate in rates {
            let plan = adapt([[birth], [c(4, 0x48)], [c(14, 0x11)]], linear, rate)
            XCTAssertEqual(try value(plan, 1, 5).output, .known(linear ? 4671 : 7100))
            XCTAssertEqual(try value(plan, 2, 0).output, .known(linear ? 4604 : 6832))
            XCTAssertEqual(try value(plan, 2, 0).incoming, .known(linear ? 4608 : 6848))
            XCTAssertEqual(try value(plan, 2, 0).incomingProducer, .rowExit(family: .vibrato, index: 0))
            XCTAssertNil(plan.semanticPitch(row: 1, tick: 6, channel: 0)); XCTAssertEqual(plan.canonicalTickClock.totalCanonicalTicks, 18)
            for incoming in [c(), c(0, 0x73), c(14, 0x11)] {
                let arp = adapt([[birth], [c(0, 0x37)], [incoming]], linear, rate)
                XCTAssertEqual(try value(arp, 1, 5).output, .known(linear ? 4416 : 5760))
                XCTAssertEqual(try value(arp, 2, 0).output, .known(incoming.effectType == 14 ? (linear ? 4604 : 6832) : (linear ? 4608 : 6848)))
            }
            let sparse = adapt([[birth, birth], [c(), c(0, 0x37)], [c()], [c(), c()]], linear, rate)
            XCTAssertEqual(try value(sparse, 1, 5, 1).output, .known(linear ? 4416 : 5760))
            XCTAssertNil(sparse.semanticPitch(row: 2, tick: 0, channel: 1))
            XCTAssertEqual(try value(sparse, 3, 0, 1).output, .known(linear ? 4608 : 6848))
            let ordinals = sparse.semanticPitchProjection.channels[1].map(\.ordinal); XCTAssertEqual(ordinals, ordinals.sorted())
            for channel in [0, 1] {
                var row = [c(4, 0x48), c(15, 1)]; row.swapAt(0, channel)
                let speedOne = adapt([[birth, birth], [c(volume: 0xB8), c(volume: 0xB8)], row, [c(14, 0x11), c(14, 0x11)]], linear, rate)
                XCTAssertEqual(try value(speedOne, 2, 0, channel).output, .known(linear ? 4671 : 7100))
                XCTAssertEqual(try value(speedOne, 3, 0, channel).output, .known(linear ? 4604 : 6832))
                XCTAssertNil(speedOne.semanticPitch(row: 2, tick: 1, channel: channel))
            }
        } }
    }

    func testOwnersDelayedResetsAndSourceGenerationsRemainSeparate() throws {
        for linear in [true, false] { for rate in rates {
            let releaseControl = adapt([[birth], [c(note: 97, instrument: 2)]], linear, rate)
            XCTAssertEqual(try value(releaseControl, 1, 0).semanticInstrument, 1); XCTAssertEqual(try value(releaseControl, 1, 0).carriedInstrument, 2)
            let coldControl = adapt([[c(3, 1, note: 49, instrument: 2)]], linear, rate)
            XCTAssertEqual(try value(coldControl, 0, 0).carriedInstrument, 2); XCTAssertNil(try value(coldControl, 0, 0).semanticInstrument)
            let delayed = adapt([[birth], [c(14, 0xD3, instrument: 2)]], linear, rate)
            let before = try value(delayed, 1, 2), after = try value(delayed, 1, 3)
            XCTAssertEqual(before.semanticInstrument, 1); XCTAssertEqual(before.carriedInstrument, 2); XCTAssertEqual(before.associatedGeneration, 0)
            XCTAssertNil(before.delayedResetIndex); XCTAssertEqual(after.semanticInstrument, 2)
            let childless = adapt([[birth], [c(14, 0xD3, instrument: 2, volume: 0xF0)]], linear, rate)
            XCTAssertEqual(try value(childless, 1, 2).associatedGeneration, 0); XCTAssertEqual(try value(childless, 1, 3).associatedGeneration, 1)
            XCTAssertEqual(try value(childless, 1, 3).delayedResetIndex, 0)
            let split = adapt([[birth], [c(14, 0xD3, note: 49, instrument: 2, volume: 0xB8)]], linear, rate)
            XCTAssertEqual(try value(split, 1, 2).output, .known(linear ? 4632 : 6944))
            XCTAssertEqual(try value(split, 1, 3).output, .known(linear ? 4608 : 6848)); XCTAssertEqual(try value(split, 1, 3).associatedGeneration, 1)
            XCTAssertEqual(after.associatedGeneration, 1); XCTAssertEqual(after.delayedResetIndex, 0)
            let unavailable = adapt([[birth], [c(instrument: 6)], [c(14, 0xD3, note: 49)]], linear, rate)
            XCTAssertEqual(try value(unavailable, 2, 2).semanticInstrument, 1); XCTAssertEqual(try value(unavailable, 2, 2).associatedGeneration, 0)
            XCTAssertEqual(try value(unavailable, 2, 3).semanticInstrument, 6); XCTAssertEqual(try value(unavailable, 2, 3).semanticSample, 9)
            XCTAssertNil(try value(unavailable, 2, 3).associatedGeneration); XCTAssertNil(try value(unavailable, 2, 3).selectionFactIndex)
            XCTAssertEqual(try value(unavailable, 2, 3).emptyRouteIndex, 0)
            XCTAssertEqual(unavailable.selectionDispatchFacts.facts.map(\.role), [.trigger, .carriedInstrument])
            let outside = adapt([[birth], [c(14, 0xD6, instrument: 2)]], linear, rate)
            XCTAssertEqual(try value(outside, 1, 5).semanticInstrument, 1); XCTAssertNil(try value(outside, 1, 5).delayedResetIndex)
            for cell in [c(note: 53), c(instrument: 2), c(14, 0xD0, instrument: 2), c(note: 49, instrument: 5), c(note: 49, instrument: 6), c(note: 97), c(20, 3)] {
                let plan = adapt([[birth], [cell]], linear, rate), result = try value(plan, 1, 5)
                XCTAssertNotEqual(result.base, .notCaptured); XCTAssertNotEqual(result.output, .notCaptured)
                for (index, fact) in plan.rowEntryTriggerResetFacts.facts.enumerated() {
                    XCTAssertEqual(try value(plan, fact.syntheticRow, 0, fact.channelIndex).rowEntryResetIndex, index)
                }
                if let fact = plan.selectionDispatchFacts.facts.last {
                    XCTAssertEqual(result.semanticInstrument, fact.semanticInstrument); XCTAssertEqual(result.carriedInstrument, fact.carriedInstrument)
                }
            }
            let mapped = adapt([[birth], [c(note: 53)]], linear, rate)
            XCTAssertEqual(try value(mapped, 1, 0).semanticSample, 1); XCTAssertEqual(try value(mapped, 1, 0).associatedGeneration, 1)
            for cell in [c(14, 0x93), c(14, 0x90), c(27, 2)] {
                let plan = adapt([[birth], [cell]], linear, rate)
                for mapping in plan.diagnostics.eventMappings where mapping.syntheticRow == 1 {
                    XCTAssertEqual(try value(plan, 1, mapping.syntheticTick).associatedGeneration, mapping.eventIndex)
                }
            }
            let completed = adapt([[birth], [c(14, 0x11)]], linear, rate, completed: true)
            XCTAssertEqual(try value(completed, 1, 0).output, .known(linear ? 4604 : 6832))
            XCTAssertEqual(try value(completed, 1, 0).associatedGeneration, 0)
            XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: Int(rate * 0.12), plan: completed))
        } }
    }

    func testSparseResetRunsKeepActualCoordinatesAndShareStorage() throws {
        XCTAssertEqual(MemoryLayout<P.Record>.stride, 48); XCTAssertEqual(MemoryLayout<P.ResetRun>.stride, 24)
        var wide = P.Record(); wide.ordinal = Int(Int32.max) + 7; wide.generation = Int(Int32.max) + 9
        XCTAssertEqual(wide.ordinal, Int(Int32.max) + 7); XCTAssertEqual(wide.generation, Int(Int32.max) + 9)
        let reset = P.ResetRun(ordinal: Int(Int32.max) + 7, rowReset: Int(Int32.max) + 8, delayedReset: Int(Int32.max) + 9)
        XCTAssertEqual(reset.rowReset, Int(Int32.max) + 8); XCTAssertEqual(reset.delayedReset, Int(Int32.max) + 9)
        for linear in [true, false] { for rate in rates {
            let song = input([[birth], [c(3, note: 49, instrument: 1)], [c()], [c(14, 0xD3, instrument: 1)], [c()]], linear: linear)
            let plan = A.adapt(song, orderIndex: 0, sampleRate: rate), projection = plan.semanticPitchProjection
            XCTAssertEqual(projection.resetRuns[0].map(\.ordinal), [0, 6, 21])
            XCTAssertFalse(projection.channels[0].contains { $0.ordinal == 6 || $0.ordinal == 12 })
            for (row, tick, ordinary, delayed): (Int, Int, Int, Int?) in [(0, 0, 0, nil), (1, 0, 1, nil), (2, 5, 1, nil), (3, 2, 1, nil), (3, 3, 1, 0), (4, 5, 1, 0)] {
                let result = try value(plan, row, tick)
                XCTAssertEqual(result.rowEntryResetIndex, ordinary); XCTAssertEqual(result.delayedResetIndex, delayed)
                XCTAssertEqual(result.output, .known(linear ? 4608 : 6848))
            }
            for copy in [plan.replacingEventCoverage(plan.diagnostics.eventCoverage), try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, preparedPlan: plan).plan)] {
                XCTAssertEqual(try value(copy, 4, 5), try value(plan, 4, 5))
                projection.resetRuns.withUnsafeBufferPointer { original in
                    copy.semanticPitchProjection.resetRuns.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
                }
                projection.resetRuns[0].withUnsafeBufferPointer { original in
                    copy.semanticPitchProjection.resetRuns[0].withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
                }
            }
        } }
    }

    func testImmutableCopiesWindowsPreparedReuseInvalidationAndManualPlans() throws {
        let song = input([[birth], [c(volume: 0xB8)], [c(3)]]), plan = A.adapt(song, orderIndex: 0, sampleRate: 48_000)
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan), request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: 48_000), rows: 3)
        var copies = [plan.replacingEventCoverage(plan.diagnostics.eventCoverage), PlaybackSongOfflineRenderer.plan(plan, mutingEventsNotIn: []),
            plan.extendingEnvelopeTail(throughFrame: 100_000), renderer.render(request).plan, renderer.renderWindowed(request, windowRows: 1).plan]
        #if DEBUG
        copies.append(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).plan)
        #endif
        for _ in 0..<2 { copies.append(try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 48_000, preparedPlan: plan).plan)) }
        for copy in copies {
            XCTAssertEqual(copy.semanticPitchProjection, plan.semanticPitchProjection)
            XCTAssertEqual(try value(copy, 2, 5), try value(plan, 2, 5))
        }
        var changed = plan; changed.diagnostics.vibratoEffects.removeAll()
        XCTAssertEqual(changed.semanticPitchProjection.coverage, .notAdapterProduced); XCTAssertNil(changed.semanticPitch(row: 2, tick: 5, channel: 0))
        let manual = PlaybackSongSyntheticPlan(timingConfig: plan.timingConfig, pattern: plan.pattern, diagnostics: plan.diagnostics,
            canonicalTickClock: plan.canonicalTickClock, selectionDispatchFacts: plan.selectionDispatchFacts)
        XCTAssertEqual(manual.semanticPitchProjection.coverage, .notAdapterProduced)
        for coordinate in [(-1, 0, 0), (0, -1, 0), (0, 0, -1), (3, 0, 0), (0, 0, 2), (Int.max, 0, 0)] {
            XCTAssertNil(plan.semanticPitch(row: coordinate.0, tick: coordinate.1, channel: coordinate.2))
        }
    }

    private func value(_ plan: PlaybackSongSyntheticPlan, _ row: Int, _ tick: Int, _ channel: Int = 0) throws -> P.Result {
        try XCTUnwrap(plan.semanticPitch(row: row, tick: tick, channel: channel), "Missing semantic coverage at \(row)/\(tick)/\(channel)")
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func adapt(_ rows: [[PlaybackCell]], _ linear: Bool, _ rate: Double, baseRate: Double = 8363, completed: Bool = false) -> PlaybackSongSyntheticPlan {
        let plan = A.adapt(input(rows, linear: linear, baseRate: baseRate, completed: completed), orderIndex: 0, sampleRate: rate)
        XCTAssertEqual(plan.semanticPitchProjection.captureFailureCount, 0)
        return plan
    }
    private func input(_ rows: [[PlaybackCell]], linear: Bool = true, baseRate: Double = 8363, completed: Bool = false) -> PlaybackSong {
        func sample(_ instrument: Int, _ slot: Int = 0, relative: Int = 0) -> PlaybackSample {
            .init(instrumentIndex: instrument, sampleIndex: slot, pcm: [0.125, -0.375, 0.25, -0.0625, 0.5, -0.25, 0.0625, -0.125], volume: 0.5,
                relativeNote: relative, finetune: 0, baseSampleRate: baseRate, loopLength: completed ? 0 : 8, loopType: completed ? 0 : 1)
        }
        var map = Array(repeating: 0, count: 96); map[52] = 1
        return .init(title: "Public integrated native semantic pitch", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample(1), sample(1, 1)], noteSampleMap: map),
                2: .init(index: 2, samples: [sample(2)], noteSampleMap: Array(repeating: 0, count: 96)),
                3: .init(index: 3, samples: [], noteSampleMap: Array(repeating: 0, count: 96)),
                4: .init(index: 4, samples: [sample(4, relative: -49)], noteSampleMap: Array(repeating: 0, count: 96)),
                5: .init(index: 5, samples: [sample(5, relative: 96)], noteSampleMap: Array(repeating: 0, count: 96)),
                6: .init(index: 6, samples: [sample(6)], noteSampleMap: Array(repeating: 9, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: false,
                volume: 32, panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
