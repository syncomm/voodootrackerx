import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Public constructions specify actual G23 calls independently of row-scoped diagnostics.
final class G23ChildlessPitchInvocationTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias E = PlaybackSongG23ChildlessPitchInvocations
    private let rates = [44_100.0, 48_000]
    private var birth: PlaybackCell { c(note: 49, instrument: 1) }
    private var g23: PlaybackCell { c(14, 0xD3, instrument: 2, volume: 0xF0) }

    func testLiteralCanonicalCallsKeepDiagnosticScopeAndDelayedGeneration() throws {
        for linear in [true, false] { for rate in rates {
            let input = song([[birth], [g23]], linear: linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let calls = try observations(plan)
            assertTimingFrames(calls, input: input, rate: rate)
            XCTAssertEqual(plan.g23ChildlessPitchInvocations.coverage, .partialG23F0InvocationsV1)
            XCTAssertEqual(plan.g23ChildlessPitchInvocations.runs.count, 1)
            XCTAssertEqual(calls.map(\.syntheticTick), [1, 2, 3, 4, 5])
            XCTAssertEqual(calls.map(\.scheduledFrame), rate == 48_000
                ? [6720, 7680, 8640, 9600, 10560] : [6174, 7056, 7938, 8820, 9702])
            XCTAssertEqual(calls.map(\.diagnosticIndex), [0, 1, 2, 3, 4])
            XCTAssertEqual(calls.map(\.associatedGeneration), [0, 0, 0, 1, 1])
            for call in calls {
                XCTAssertEqual(call.classification, .executedNoNumericPitchChild)
                XCTAssertEqual(call.source, .init(orderIndex: 0, patternIndex: 0, rowIndex: 1))
                XCTAssertEqual(call.syntheticRow, 1); XCTAssertEqual(call.channelIndex, 0)
                XCTAssertEqual(call.rowCell, g23)
                XCTAssertEqual(call.status, .noTarget)
                XCTAssertEqual(call.policy, "volume_column_tone_portamento_no_existing_target")
                XCTAssertEqual(plan.canonicalTickClock.coordinate(syntheticRow: 1,
                    tick: call.syntheticTick, channel: 0)?.absoluteFrame, call.scheduledFrame)
            }
            let commands = plan.diagnostics.tonePortamentoEffects
            XCTAssertEqual(commands.map(\.syntheticTick), [0, 0, 0, 0, 0])
            XCTAssertTrue(commands.allSatisfy { $0.stepUpdates.isEmpty })
            XCTAssertTrue(plan.nativePitchWriterSpans.spans.isEmpty)
            let delay = try XCTUnwrap(plan.diagnostics.noteDelayEffects.first)
            XCTAssertEqual(delay.status, .instrumentOnlyStarted)
            XCTAssertEqual(delay.requestedTick, 3); XCTAssertEqual(delay.eventIndex, 1)
            XCTAssertEqual(delay.delayedFrame, rate == 48_000 ? 8640 : 7938)
            let facts = plan.selectionDispatchFacts.facts
            XCTAssertEqual(facts.map(\.role), [.trigger, .carriedInstrument, .retainedNoteRestart])
            XCTAssertEqual(facts.map(\.tick), [0, 0, 3])
            XCTAssertEqual(facts.map(\.associatedGeneration), [0, 0, 1])
            XCTAssertEqual(facts.last?.mappedSample, 0)
            XCTAssertEqual(plan.pattern.events.count, 2)
        } }
    }

    func testEffectiveSpeedAndDelayedBirthEligibilityAreSeparateGates() throws {
        for linear in [true, false] { for rate in rates { for speed in [1, 3, 6] {
            for fBefore in [false, true] {
                let initial = fBefore ? [c(), birth] : [birth, c()]
                let row = fBefore ? [c(15, UInt8(speed)), g23] : [g23, c(15, UInt8(speed))]
                let input = song([initial, row], linear: linear)
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                let calls = try observations(plan)
                assertTimingFrames(calls, input: input, rate: rate)
                let ticks = speed == 1 ? [] : speed == 3 ? [1, 2] : [1, 2, 3, 4, 5]
                let frames = rate == 48_000 ? [6720, 7680, 8640, 9600, 10560] : [6174, 7056, 7938, 8820, 9702]
                XCTAssertEqual(calls.map(\.syntheticTick), ticks)
                XCTAssertEqual(calls.map(\.scheduledFrame), Array(frames.prefix(ticks.count)))
                XCTAssertEqual(calls.map(\.channelIndex), Array(repeating: fBefore ? 1 : 0, count: ticks.count))
                XCTAssertEqual(plan.diagnostics.noteDelayEffects.first?.rowSpeed, speed)
                XCTAssertEqual(plan.diagnostics.noteDelayEffects.first?.status,
                    speed == 6 ? .instrumentOnlyStarted : .instrumentOnlyOutOfRow)
                XCTAssertEqual(plan.pattern.events.count, speed == 6 ? 2 : 1)
            }
            let initialPlan = A.adapt(song([[birth], [g23]], linear: linear, speed: speed), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(try observations(initialPlan).map(\.syntheticTick), speed == 1 ? [] : speed == 3 ? [1, 2] : [1, 2, 3, 4, 5])
            if speed == 3 {
                XCTAssertEqual(try observations(initialPlan).map(\.scheduledFrame), rate == 48_000 ? [3840, 4800] : [3528, 4410])
                XCTAssertEqual(try observations(initialPlan).map(\.associatedGeneration), [0, 0])
            }
        } } }
    }

    func testLastFxxChannelWinsAndFractionalBPMFramesAreLiteral() throws {
        for linear in [true, false] { for rate in rates {
            for lastSpeed: UInt8 in [3, 6] {
                let row = [c(15, lastSpeed == 3 ? 6 : 3), g23, c(15, lastSpeed)]
                let plan = A.adapt(song([[c(), birth, c()], row], linear: linear), orderIndex: 0, sampleRate: rate)
                let calls = try observations(plan)
                XCTAssertEqual(calls.map(\.syntheticTick), lastSpeed == 3 ? [1, 2] : [1, 2, 3, 4, 5])
                let frames = rate == 48_000 ? [6720, 7680, 8640, 9600, 10560] : [6174, 7056, 7938, 8820, 9702]
                XCTAssertEqual(calls.map(\.scheduledFrame), Array(frames.prefix(lastSpeed == 3 ? 2 : 5)))
            }
            for tempoBefore in [false, true] {
                let initial = tempoBefore ? [c(), birth] : [birth, c()]
                let row = tempoBefore ? [c(15, 127), g23] : [g23, c(15, 127)]
                let input = song([initial, row], linear: linear)
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                let calls = try observations(plan)
                assertTimingFrames(calls, input: input, rate: rate)
                // Exact row start is 6 ticks at BPM125; subsequent ticks use BPM127.
                XCTAssertEqual(calls.map(\.scheduledFrame), rate == 48_000
                    ? [6704, 7649, 8594, 9539, 10484] : [6160, 7028, 7896, 8764, 9632])
                for call in calls {
                    XCTAssertEqual(plan.canonicalTickClock.coordinate(syntheticRow: 1, tick: call.syntheticTick,
                        channel: tempoBefore ? 1 : 0)?.absoluteFrame, call.scheduledFrame)
                }
            }
        } }
    }

    func testNegativeSourcesRetainOnlyTheirActuallyReportedAssociations() throws {
        for linear in [true, false] { for rate in rates {
            let cases: [(PlaybackCell, PlaybackCell, Bool, [Int?], PlaybackSongSyntheticNoteDelayDiagnostic.Status)] = [
                (birth, c(14, 0xD3, instrument: 9, volume: 0xF0), false, [0, 0, 0, 0, 0], .instrumentOnlyInvalidInstrument),
                (c(), g23, false, [nil, nil, nil, nil, nil], .instrumentOnlyNoRetainedNote),
                (birth, c(14, 0xD3, instrument: 3, volume: 0xF0), false, [0, 0, 0, nil, nil], .instrumentOnlyUnavailable),
                (birth, c(14, 0xD3, instrument: 4, volume: 0xF0), false, [0, 0, 0, nil, nil], .instrumentOnlyUnavailable),
                (birth, g23, true, [0, 0, 0, 1, 1], .instrumentOnlyStarted)
            ]
            for (initial, command, completed, generations, status) in cases {
                let plan = A.adapt(song([[initial], [command]], linear: linear, completed: completed), orderIndex: 0, sampleRate: rate)
                let calls = try observations(plan)
                XCTAssertEqual(calls.map(\.syntheticTick), [1, 2, 3, 4, 5])
                XCTAssertEqual(calls.map(\.associatedGeneration), generations)
                XCTAssertTrue(calls.allSatisfy { $0.classification == .executedNoNumericPitchChild })
                XCTAssertEqual(plan.diagnostics.noteDelayEffects.first?.status, status)
                for call in calls {
                    let diagnostic = plan.diagnostics.tonePortamentoEffects[call.diagnosticIndex]
                    XCTAssertEqual(call.status, diagnostic.status); XCTAssertEqual(call.policy, diagnostic.policy)
                    XCTAssertEqual(call.associatedGeneration, diagnostic.activeEventIndex)
                }
                if initial == c() {
                    XCTAssertTrue(plan.pattern.events.isEmpty)
                    XCTAssertTrue(calls.allSatisfy { $0.status == .noActiveVoice })
                    XCTAssertTrue(plan.selectionDispatchFacts.facts.allSatisfy { $0.associatedGeneration == nil })
                }
                if command.instrument == 3 || command.instrument == 4 {
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    XCTAssertEqual(plan.selectionDispatchFacts.facts.last?.mappedSample, 0)
                    XCTAssertEqual(plan.selectionDispatchFacts.facts.last?.role, command.instrument == 3 ? .emptySelection : .unavailableRoute)
                    XCTAssertNil(plan.selectionDispatchFacts.facts.last?.associatedGeneration)
                }
                if completed {
                    XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: calls[0].scheduledFrame, plan: plan))
                    // Diagnostic association survives natural completion; it is not source eligibility.
                    XCTAssertEqual(calls[0].associatedGeneration, 0)
                }
            }
        } }
    }

    func testMixedNumericCallsDoNotInventChildlessCoverageAndNativeZeroStaysNumeric() throws {
        for linear in [true, false] { for rate in rates {
            // Five earlier steps leave exactly one step to the target. Reaching
            // it latches the higher-period direction. Restart restores note49;
            // tick4 clamps the already-crossed target, then tick5 is childless.
            let seed = c(3, linear ? 3 : 4, note: 50)
            let plan = A.adapt(song([[birth], [seed], [g23]], linear: linear), orderIndex: 0, sampleRate: rate)
            let calls = try observations(plan)
            XCTAssertEqual(calls.map(\.syntheticTick), [2, 3, 5])
            XCTAssertEqual(calls.map(\.diagnosticIndex), [2, 3, 5])
            XCTAssertEqual(calls.map(\.associatedGeneration), [0, 0, 1])
            XCTAssertTrue(calls.allSatisfy { $0.status == .applied })
            XCTAssertEqual(plan.g23ChildlessPitchInvocations.runs.count, 2)
            XCTAssertEqual(plan.g23ChildlessPitchInvocations.runs.map(\.firstTick), [2, 5])
            XCTAssertEqual(plan.g23ChildlessPitchInvocations.runs.map(\.invocationCount), [2, 1])
            XCTAssertEqual(plan.diagnostics.tonePortamentoEffects.dropFirst().map { $0.stepUpdates.count }, [1, 0, 0, 1, 0])
            let numeric = plan.nativePitchWriterSpans.spans.flatMap(\.originalChildren)
            XCTAssertEqual(numeric.compactMap { linear ? $0.linearPeriodAfter : $0.amigaPeriodAfter }, linear
                ? [4596, 4584, 4572, 4560, 4548, 4544, 4544]
                : [6784, 6720, 6656, 6592, 6528, 6464, 6464])
            let zero = A.adapt(song([[birth], [c(0, 0x37)]], linear: linear, relative: -49), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(zero.g23ChildlessPitchInvocations.runs.isEmpty)
            let child = try XCTUnwrap(zero.nativePitchWriter(span: 0, child: 0))
            XCTAssertEqual(child.nativePeriodAfter, 0)
            XCTAssertEqual(child.delivery, .retainedDiagnosticChild)
        } }
    }

    func testOtherDispatchAndEffectDomainsRemainUnclaimed() throws {
        let controls: [[PlaybackCell]] = [
            [birth, c(volume: 0xB8), c(3), c(1, 1), c(3)],
            [birth, c(14, 0xD0, instrument: 2, volume: 0xF0)],
            [birth, c(14, 0xD3, note: 53, instrument: 2, volume: 0xF0)],
            [birth, c(14, 0xD3, instrument: 2, volume: 0xB8)],
            [birth, c(14, 0xD3, instrument: 2, volume: 0xF1)],
            [birth, c(4, 0x48, volume: 0xB8), c(6, volume: 0xB8), c()],
            [birth, c(0, 0x37), c(), c(14, 0x93), c(27, 0x93)],
            [birth, c(note: 53, instrument: 2), c(14, 0xC0), c(14, 0xC3)],
            [birth, c(1, 1), c(14, 0x11), c(14, 0x21), c(33, 0x11), c(4, 0x48)]
        ]
        for linear in [true, false] { for rate in rates { for cells in controls {
            let plan = A.adapt(song(cells.map { [$0] }, linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.g23ChildlessPitchInvocations.coverage, .partialG23F0InvocationsV1)
            XCTAssertTrue(plan.g23ChildlessPitchInvocations.runs.isEmpty)
            XCTAssertNil(plan.g23ChildlessPitchInvocation(run: 0, invocation: 0))
        } } }
    }

    func testObserverMergesOnlyIndividuallyRecordedAdjacentCalls() throws {
        let plan = A.adapt(song([[birth, birth], [g23, g23], [g23, c()]]), orderIndex: 0, sampleRate: 48_000)
        let diagnostics = plan.diagnostics.tonePortamentoEffects
        var skippedTick = E.Observer()
        skippedTick.record(rowCell: g23, tick: 1, diagnosticIndex: 0, diagnostics: diagnostics)
        skippedTick.record(rowCell: g23, tick: 3, diagnosticIndex: 2, diagnostics: diagnostics)
        skippedTick.record(rowCell: g23, tick: 4, diagnosticIndex: 3, diagnostics: diagnostics)
        XCTAssertEqual(skippedTick.runs.map(\.firstTick), [1, 3])
        XCTAssertEqual(skippedTick.runs.map(\.invocationCount), [1, 2])

        // Insert an independently produced command into test storage between two
        // real calls. Index discontinuity must also split an otherwise adjacent tick pair.
        let inserted = [diagnostics[0], diagnostics[5], diagnostics[1]]
        var skippedIndex = E.Observer()
        skippedIndex.record(rowCell: g23, tick: 1, diagnosticIndex: 0, diagnostics: inserted)
        skippedIndex.record(rowCell: g23, tick: 2, diagnosticIndex: 2, diagnostics: inserted)
        XCTAssertEqual(skippedIndex.runs.map(\.invocationCount), [1, 1])

        var complete = E.Observer()
        for call in try observations(plan) {
            complete.record(rowCell: call.rowCell, tick: call.syntheticTick,
                diagnosticIndex: call.diagnosticIndex, diagnostics: diagnostics)
        }
        XCTAssertEqual(complete.evidence, plan.g23ChildlessPitchInvocations)
        let before = complete.evidence
        for (tick, index) in [(0, 0), (6, 0), (1, -1), (1, Int.max)] {
            complete.record(rowCell: g23, tick: tick, diagnosticIndex: index, diagnostics: diagnostics)
        }
        complete.record(rowCell: c(14, 0xD3, instrument: 2, volume: 0xF1), tick: 1,
            diagnosticIndex: 0, diagnostics: diagnostics)
        XCTAssertEqual(complete.evidence, before)

        let mixed = A.adapt(song([[birth], [c(3, 3, note: 50)], [g23]]), orderIndex: 0, sampleRate: 48_000)
        var childBoundary = E.Observer()
        for tick in 1...5 {
            childBoundary.record(rowCell: g23, tick: tick, diagnosticIndex: tick,
                diagnostics: mixed.diagnostics.tonePortamentoEffects)
        }
        XCTAssertEqual(childBoundary.runs.map(\.firstTick), [2, 5])
        XCTAssertEqual(childBoundary.runs.map(\.invocationCount), [2, 1])
    }

    func testRunBoundariesStrictBoundsImmutableCopiesAndDiagnosticInvalidation() throws {
        let input = song([[birth, birth], [g23, g23], [g23, c()]])
        let plan = A.adapt(input, orderIndex: 0, sampleRate: 48_000)
        XCTAssertEqual(plan.g23ChildlessPitchInvocations.runs.count, 3)
        XCTAssertEqual(plan.g23ChildlessPitchInvocations.runs.map(\.invocationCount), [5, 5, 5])
        XCTAssertEqual(plan.g23ChildlessPitchInvocations.runs.map(\.firstToneDiagnosticIndex), [0, 5, 10])
        XCTAssertEqual(try observations(plan).map(\.channelIndex), Array(repeating: 0, count: 5) + Array(repeating: 1, count: 5) + Array(repeating: 0, count: 5))
        for (run, invocation) in [(-1, 0), (3, 0), (0, -1), (0, 5), (Int.max, Int.max)] {
            XCTAssertNil(plan.g23ChildlessPitchInvocation(run: run, invocation: invocation))
        }
        let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: 48_000), rows: 3)
        let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
        var copies = [plan.replacingEventCoverage(plan.diagnostics.eventCoverage),
            PlaybackSongOfflineRenderer.plan(plan, mutingEventsNotIn: []), plan.extendingEnvelopeTail(throughFrame: 100_000),
            renderer.render(request).plan, renderer.renderWindowed(request, windowRows: 1).plan]
        #if DEBUG
        copies.append(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).plan)
        #endif
        for _ in 0..<2 {
            copies.append(try XCTUnwrap(RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000, preparedPlan: plan).plan))
        }
        for copy in copies {
            XCTAssertEqual(copy.g23ChildlessPitchInvocations, plan.g23ChildlessPitchInvocations)
            XCTAssertEqual(try observations(copy), try observations(plan))
            XCTAssertEqual(copy.selectionDispatchFacts, plan.selectionDispatchFacts)
            XCTAssertEqual(copy.heldPitchProvenance, plan.heldPitchProvenance)
            XCTAssertEqual(copy.nativePitchWriterSpans, plan.nativePitchWriterSpans)
            plan.g23ChildlessPitchInvocations.runs.withUnsafeBufferPointer { original in
                copy.g23ChildlessPitchInvocations.runs.withUnsafeBufferPointer { XCTAssertEqual(original.baseAddress, $0.baseAddress) }
            }
        }
        let manual = PlaybackSongSyntheticPlan(timingConfig: plan.timingConfig, pattern: plan.pattern,
            diagnostics: plan.diagnostics, canonicalTickClock: plan.canonicalTickClock, selectionDispatchFacts: plan.selectionDispatchFacts)
        XCTAssertEqual(manual.g23ChildlessPitchInvocations.coverage, .notAdapterProduced)
        var changed = plan
        changed.diagnostics.vibratoEffects.removeAll()
        XCTAssertEqual(changed.g23ChildlessPitchInvocations.coverage, .notAdapterProduced)
        XCTAssertEqual(changed.heldPitchProvenance.coverage, .notAdapterProduced)
        XCTAssertEqual(changed.nativePitchWriterSpans.coverage, .notAdapterProduced)
        XCTAssertNil(changed.g23ChildlessPitchInvocation(run: 0, invocation: 0))
        XCTAssertEqual(plan.g23ChildlessPitchInvocations.runs.count, 3)
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride, 1152)
        XCTAssertEqual(MemoryLayout<PlaybackSongSelectionDispatchFacts.Fact>.stride, 288)
        XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticTonePortamentoStepUpdate>.stride, 144)
        XCTAssertEqual(MemoryLayout<PlaybackXMChannelRow>.stride, 8)
        XCTAssertEqual(MemoryLayout<E.Run>.stride, 32)
        // Each partial reset companion adds 24 inline bytes; G23 runs stay 32 bytes.
        // Sparse reset storage makes the native semantic companion 56 inline bytes.
        XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticPlan>.stride, 1048)
    }

    private func observations(_ plan: PlaybackSongSyntheticPlan) throws -> [E.Observation] {
        try plan.g23ChildlessPitchInvocations.runs.indices.flatMap { run in
            try (0..<plan.g23ChildlessPitchInvocations.runs[run].invocationCount).map {
                try XCTUnwrap(plan.g23ChildlessPitchInvocation(run: run, invocation: $0))
            }
        }
    }

    private func assertTimingFrames(_ calls: [E.Observation], input: PlaybackSong, rate: Double,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let traversal = PlaybackSongTraversalPlanner.plan(input, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(input, traversalPlan: traversal, sampleRate: rate)
        for call in calls {
            XCTAssertEqual(call.scheduledFrame, timing.frameFor(row: call.syntheticRow, tick: call.syntheticTick), file: file, line: line)
        }
    }

    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                   instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ rows: [[PlaybackCell]], linear: Bool = true, speed: Int = 6,
                      completed: Bool = false, relative: Int = 0) -> PlaybackSong {
        let pcm: [Float] = [0.125, -0.375, 0.25, -0.0625, 0.5, -0.25, 0.0625, -0.125]
        let first = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: pcm, volume: 0.5,
            relativeNote: relative, finetune: 0, baseSampleRate: 8363,
            loopLength: completed ? 0 : 8, loopType: completed ? 0 : 1)
        let second = PlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: pcm, volume: 0.5,
            relativeNote: relative, finetune: 0, baseSampleRate: 8363, loopLength: 8, loopType: 1)
        let map = Array(repeating: 0, count: 96)
        return .init(title: "Public G23 childless invocation controls", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [first], noteSampleMap: map),
                2: .init(index: 2, samples: [second], noteSampleMap: map),
                3: .init(index: 3, samples: [], noteSampleMap: map),
                4: .init(index: 4, samples: [], noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125),
            usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: 32, panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
