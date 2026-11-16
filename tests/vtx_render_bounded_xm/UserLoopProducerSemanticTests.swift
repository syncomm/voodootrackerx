import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Finite repeated orders are an independent oracle; only the production producer
/// chooses batch boundaries and imports checkpoints. No test reimplements effects.
final class UserLoopProducerSemanticTests: XCTestCase {
    private typealias Producer = PlaybackSongUserLoopProducer
    private typealias Pitch = PlaybackSongSemanticPitchProjection
    private struct BirthBinding {
        let actual: RuntimeLoopNativeSourceIdentity
        let expected: Int
    }
    private struct GlobalPoint: Equatable {
        let command: PlaybackSongSyntheticVoiceStateUpdateCommand
        let source: Int?, globalBefore: Int?, globalAfter: Int?
        let gainBefore: Float?, gainAfter: Float?
        let memoryReused: Bool, memoryMissing: Bool, resolvedParameter: UInt8?
    }
    private struct NativePoint: Equatable {
        enum Payload: Equatable {
            case trigger(SyntheticTrackerEvent, UInt8, Int, Int)
            case gainPan(Float?, Float?), step(Double), envelopePosition(Int)
            case state(MixerPlaybackStateChange), envelope(MixerEnvelopeSemanticState)
            case channel(Int, UInt8?, MixerEnvelopeSemanticState, Int?, Int?, UInt8?, Int)
            case audible(Float, Float, Int, String, MixerAudibleOutputSeed?, Bool, Int, Int)
            case stop(Bool), cut
        }
        let frame: Int, tick: Int, row: Int, channel: Int, source: Int?
        let categories: [String]
        let effect: UInt8?, parameter: UInt8?, volume: UInt8?
        let payload: Payload
    }

    func testProductionArpeggioVibratoHeldRowsAndFractionalFxxMatchExpandedExecution() throws {
        for modulatedInstrument in [false, true] {
            for linear in [true, false] { for rate in [44_100.0, 48_000] { for cap in [1, 3, 7] {
                try assertProductionMatchesExpanded(song(linear: linear, modulatedInstrument: modulatedInstrument),
                    rate: rate, cap: cap, targetRows: 22)
            } } }
        }
        for kind in LoopTraversalProofFixture.Kind.allCases {
            for linear in [true, false] { for rate in [44_100.0, 48_000] { for cap in [1, 3, 7] {
                let fixture = try LoopTraversalProofFixture.make(kind, linear: linear)
                try assertProductionMatchesExpanded(fixture.input, rate: rate, cap: cap,
                    targetRows: fixture.targetRows, oracleInput: fixture.oracle,
                    expectedSourceRows: fixture.visits, minimumBirths: 1)
            } } }
        }
    }

    func testSourceFreeAndOwnerOnlyWritersPreserveHonestMissingSourceAcrossCheckpoints() throws {
        for ownerOnly in [false, true] { for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(linear: linear, modulatedInstrument: true, birth: false, ownerOnly: ownerOnly)
            try assertProductionMatchesExpanded(input, rate: rate, cap: 1, targetRows: 14, expectNoBirths: true)
        } } }
    }

    func testCancelledProductionDoesNotAdvanceTheCommittedCheckpointOrBirthScope() throws {
        let input = song(linear: true, modulatedInstrument: true)
        let actual = try producer(input, rate: 48_000), control = try producer(input, rate: 48_000)
        let a = try actual.next(minimumHorizonFrames: Int.max, maximumRows: 3)
        let b = try control.next(minimumHorizonFrames: Int.max, maximumRows: 3)
        XCTAssertEqual(a.adapterPlan, b.adapterPlan)
        var calls = 0
        XCTAssertThrowsError(try actual.next(minimumHorizonFrames: Int.max, maximumRows: 7,
            isCancelled: { calls += 1; return calls >= 8 }))
        XCTAssertGreaterThanOrEqual(calls, 8)
        let resumed = try actual.next(minimumHorizonFrames: Int.max, maximumRows: 7)
        let expected = try control.next(minimumHorizonFrames: Int.max, maximumRows: 7)
        XCTAssertEqual(resumed.sequence, expected.sequence)
        XCTAssertEqual(resumed.predecessorSequence, expected.predecessorSequence)
        XCTAssertEqual(resumed.startFrame, expected.startFrame)
        XCTAssertEqual(resumed.endFrame, expected.endFrame)
        XCTAssertEqual(resumed.sourceIdentities, expected.sourceIdentities)
        XCTAssertEqual(resumed.adapterPlan, expected.adapterPlan)
    }

    func testLoopAssemblyMatchesFullThenFilterWithoutChangingIDsOrCategories() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for cap in [1, 7] {
            let input = song(linear: linear, modulatedInstrument: true)
            let actual = try producer(input, rate: rate)
            for _ in 0..<4 {
                let batch = try actual.next(minimumHorizonFrames: Int.max, maximumRows: cap)
                let prepared = try XCTUnwrap(batch.adapterPlan.plan)
                let full = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate,
                    preparedPlan: prepared, rowCaptureRetention: .runtimeFinalized,
                    lookupOnlySourceCount: batch.importedSourceCount)
                let filtered = full.events.filter { (batch.startFrame..<batch.endFrame).contains($0.scheduledFrame) }
                XCTAssertEqual(batch.adapterPlan.events, filtered)
                XCTAssertEqual(batch.adapterPlan.categories, full.categories)
                XCTAssertEqual(batch.adapterPlan.plannedSongEndFrame, batch.endFrame)
                XCTAssertEqual(batch.adapterPlan.plannedEventCount, filtered.count)
                XCTAssertEqual(batch.adapterPlan.eventStorage, RuntimeCMixerAdapterEventStorage(events: filtered))
            }
        } } }
    }

    func testFiniteSongCrossOrderSemanticEventsMatchFullColdPlan() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for cap in [1, 3] {
            let input = FiniteSongProducerProofFixture.make(linear: linear)
            let oracle = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate,
                initialPosition: FiniteSongProducerProofFixture.origin)
            let expected = try XCTUnwrap(oracle.plan)
            XCTAssertEqual(expected.diagnostics.traversalStopReason, .songEnd)
            let producer = try Producer(song: input, initialPosition: FiniteSongProducerProofFixture.origin,
                sampleRate: rate, sourceGeneration: 11, transportEpoch: 17, mode: .finiteSong)
            var rowOffset = 0, bindings = [BirthBinding](), points = [NativePoint]()
            var firstBirth: RuntimeLoopNativeSourceIdentity?
            while rowOffset < expected.diagnostics.rowTiming.count {
                let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: cap)
                let plan = try XCTUnwrap(batch.adapterPlan.plan)
                XCTAssertEqual(plan.diagnostics.requestedStartOrderIndex, 0)
                XCTAssertEqual(plan.diagnostics.requestedOrderCount, input.orders.count)
                XCTAssertTrue(batch.naturalBoundaries.isEmpty)
                for event in batch.adapterPlan.events {
                    guard case let .noteTrigger(index, _, _) = event.action else { continue }
                    let identity = try XCTUnwrap(batch.sourceIdentities[index])
                    XCTAssertGreaterThanOrEqual(index, batch.importedSourceCount)
                    XCTAssertEqual(identity.birthSequence, batch.sequence)
                    XCTAssertEqual(identity.birthEventIndex, index)
                    let reference = try XCTUnwrap(oracle.events.first {
                        guard case .noteTrigger = $0.action else { return false }
                        return $0.scheduledFrame == event.scheduledFrame && $0.channelIndex == event.channelIndex
                    })
                    let expectedIndex = try XCTUnwrap(reference.activeEventIndex)
                    XCTAssertFalse(bindings.contains { $0.actual == identity }, "No checkpoint pseudo-birth")
                    bindings.append(.init(actual: identity, expected: expectedIndex))
                    if firstBirth == nil { firstBirth = identity }
                }
                for local in plan.diagnostics.rowTiming.indices {
                    let a = plan.diagnostics.rowTiming[local]
                    let b = expected.diagnostics.rowTiming[rowOffset + local]
                    XCTAssertEqual(a.source, b.source)
                    XCTAssertEqual(a.rowStartExactFrame, b.rowStartExactFrame)
                    XCTAssertEqual(a.rowDurationFrames, b.rowDurationFrames)
                    XCTAssertEqual(a.actualTickCount, b.actualTickCount)
                    for tick in 0..<a.actualTickCount { for channel in 0..<3 {
                        let lhs = try XCTUnwrap(plan.semanticPitch(row: local, tick: tick, channel: channel))
                        let rhs = try XCTUnwrap(expected.semanticPitch(row: rowOffset + local,
                            tick: tick, channel: channel))
                        XCTAssertEqual(lhs.base, rhs.base)
                        XCTAssertEqual(lhs.output, rhs.output)
                        XCTAssertEqual(lhs.incoming, rhs.incoming)
                        XCTAssertEqual(lhs.semanticInstrument, rhs.semanticInstrument)
                        XCTAssertEqual(lhs.semanticSample, rhs.semanticSample)
                        XCTAssertEqual(lhs.carriedInstrument, rhs.carriedInstrument)
                        XCTAssertEqual(try resolved(lhs.associatedGeneration, batch: batch, bindings: bindings,
                            file: #filePath, line: #line),
                            rhs.associatedGeneration)
                        let coordinate = try XCTUnwrap(plan.canonicalTickClock.coordinate(
                            syntheticRow: local, tick: tick, channel: channel))
                        let reference = try XCTUnwrap(expected.canonicalTickClock.coordinate(
                            syntheticRow: rowOffset + local, tick: tick, channel: channel))
                        XCTAssertEqual(coordinate.absoluteFrame, reference.absoluteFrame)
                        XCTAssertEqual(coordinate.canonicalTickOrdinal, reference.canonicalTickOrdinal)
                        let actualGlobal = try plan.diagnostics.voiceStateUpdates.filter {
                            $0.channelIndex == channel && $0.scheduledFrame == coordinate.absoluteFrame && isGlobal($0.command)
                        }.map { globalPoint($0, source: try resolved($0.activeEventIndex,
                            batch: batch, bindings: bindings, file: #filePath, line: #line)) }
                        let expectedGlobal = expected.diagnostics.voiceStateUpdates.filter {
                            $0.channelIndex == channel && $0.scheduledFrame == reference.absoluteFrame && isGlobal($0.command)
                        }.map { globalPoint($0, source: $0.activeEventIndex) }
                        XCTAssertEqual(actualGlobal, expectedGlobal)
                    } }
                }
                for entry in batch.adapterPlan.eventStorage.ordering {
                    let event = batch.adapterPlan.events[entry.eventIndex]
                    points.append(point(event, source: try resolved(event.activeEventIndex,
                        batch: batch, bindings: bindings, file: #filePath, line: #line)))
                }
                rowOffset += plan.diagnostics.rowTiming.count
                XCTAssertEqual(batch.terminalStopReason == nil, rowOffset < expected.diagnostics.rowTiming.count)
            }
            let end = try XCTUnwrap(oracle.plannedSongEndFrame)
            let terminalWriters = oracle.events.filter { $0.scheduledFrame == end }
            XCTAssertFalse(terminalWriters.isEmpty,
                "This finite fixture must prove parity for a real end-frame writer")
            let expectedPoints = oracle.eventStorage.ordering.compactMap { entry -> NativePoint? in
                let event = oracle.events[entry.eventIndex]
                return event.scheduledFrame <= end ? point(event, source: event.activeEventIndex) : nil
            }
            for channel in 0..<3 {
                let actual = points.filter { $0.channel == channel }
                let expected = expectedPoints.filter { $0.channel == channel }
                XCTAssertEqual(actual.count, expected.count, "channel \(channel) event count")
                for index in 0..<min(actual.count, expected.count) where actual[index] != expected[index] {
                    XCTFail("channel \(channel) first event mismatch at \(index): actual frame \(actual[index].frame) categories \(actual[index].categories), expected frame \(expected[index].frame) categories \(expected[index].categories)")
                    break
                }
            }
            XCTAssertGreaterThanOrEqual(bindings.count, 3)
            XCTAssertNotNil(firstBirth)
            XCTAssertEqual(producer.exportResumeState().terminalStopReason, .songEnd)
            XCTAssertThrowsError(try producer.next(minimumHorizonFrames: Int.max, maximumRows: cap))
        } } }
    }

    private func assertProductionMatchesExpanded(_ input: PlaybackSong, rate: Double, cap: Int,
        targetRows: Int, expectNoBirths: Bool = false, oracleInput: PlaybackSong? = nil,
        expectedSourceRows: [Int]? = nil, minimumBirths: Int = 5,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let channelCount = try XCTUnwrap(input.patternsByIndex[0]?.rows.first).cells.count
        let orderCount = (targetRows + cap + 5) / 4 + 2
        let expanded = PlaybackSong(title: input.title,
            orders: (0..<orderCount).map { .init(orderIndex: $0, patternIndex: 0) },
            patternsByIndex: input.patternsByIndex, instrumentsByIndex: input.instrumentsByIndex,
            restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: input.initialTiming, usesLinearFrequencyTable: input.usesLinearFrequencyTable)
        let oracle = RuntimeCMixerAdapterEventPlan.make(song: oracleInput ?? expanded, sampleRate: rate,
            initialPosition: oracleInput == nil ? .init(orderIndex: 0, patternIndex: 0, rowIndex: 2) : nil)
        let expectedPlan = try XCTUnwrap(oracle.plan, file: file, line: line)
        let end = expectedPlan.diagnostics.rowTiming[targetRows].rowStartFrame
        let expectedBirths = oracle.events.filter { event in if case .noteTrigger = event.action { return true }; return false }
        let actual = try producer(input, rate: rate)
        var bindings = [BirthBinding](), points = [NativePoint](), rowOffset = 0, sequence: UInt64 = 0, nextFrame = 0
        while rowOffset < targetRows {
            let batch = try actual.next(minimumHorizonFrames: Int.max, maximumRows: cap)
            let plan = try XCTUnwrap(batch.adapterPlan.plan, file: file, line: line)
            XCTAssertEqual(batch.sequence, sequence + 1, file: file, line: line)
            XCTAssertEqual(batch.predecessorSequence, sequence, file: file, line: line)
            XCTAssertEqual(batch.startFrame, nextFrame, file: file, line: line)
            XCTAssertGreaterThan(batch.endFrame, batch.startFrame, file: file, line: line)
            XCTAssertLessThanOrEqual(plan.diagnostics.rowTiming.count, cap, file: file, line: line)
            XCTAssertFalse(plan.$xmChannelRows.isFullCapture, file: file, line: line)
            XCTAssertEqual(Set(batch.adapterPlan.events.map(\.id)).count, batch.adapterPlan.events.count, file: file, line: line)
            XCTAssertTrue(batch.adapterPlan.events.allSatisfy { (batch.startFrame..<batch.endFrame).contains($0.scheduledFrame) }, file: file, line: line)
            for event in batch.adapterPlan.events where event.scheduledFrame < end {
                guard case let .noteTrigger(index, _, _) = event.action else { continue }
                XCTAssertGreaterThanOrEqual(index, batch.importedSourceCount, file: file, line: line)
                let identity = try XCTUnwrap(batch.sourceIdentities[index], file: file, line: line)
                XCTAssertEqual(identity.sourceGeneration, 11, file: file, line: line)
                XCTAssertEqual(identity.transportEpoch, 17, file: file, line: line)
                XCTAssertEqual(identity.birthSequence, batch.sequence, file: file, line: line)
                XCTAssertEqual(identity.birthEventIndex, index, file: file, line: line)
                let expected = try XCTUnwrap(expectedBirths.first {
                    $0.scheduledFrame == event.scheduledFrame && $0.channelIndex == event.channelIndex
                }, file: file, line: line)
                let expectedIndex = try XCTUnwrap(expected.activeEventIndex, file: file, line: line)
                XCTAssertFalse(bindings.contains { $0.actual == identity }, "No pseudo-birth or repeated birth scope", file: file, line: line)
                bindings.append(.init(actual: identity, expected: expectedIndex))
            }
            for local in plan.diagnostics.rowTiming.indices where rowOffset + local < targetRows {
                let timing = plan.diagnostics.rowTiming[local]
                let expectedTiming = expectedPlan.diagnostics.rowTiming[rowOffset + local]
                XCTAssertEqual(timing.source.rowIndex,
                    expectedSourceRows?[rowOffset + local] ?? expectedTiming.source.rowIndex, file: file, line: line)
                XCTAssertEqual(timing.rowStartExactFrame, expectedTiming.rowStartExactFrame, file: file, line: line)
                XCTAssertEqual(timing.rowDurationFrames, expectedTiming.rowDurationFrames, file: file, line: line)
                XCTAssertEqual(timing.effectiveSpeed, expectedTiming.effectiveSpeed, file: file, line: line)
                XCTAssertEqual(timing.effectiveBPM, expectedTiming.effectiveBPM, file: file, line: line)
                XCTAssertEqual(timing.patternDelayCycles, expectedTiming.patternDelayCycles, file: file, line: line)
                for tick in 0..<timing.actualTickCount { for channel in 0..<channelCount {
                    let lhs = try XCTUnwrap(plan.semanticPitch(row: local, tick: tick, channel: channel), file: file, line: line)
                    let rhs = try XCTUnwrap(expectedPlan.semanticPitch(row: rowOffset + local, tick: tick, channel: channel), file: file, line: line)
                    let label = "cap=\(cap) sequence=\(batch.sequence) executedRow=\(rowOffset + local) tick=\(tick) channel=\(channel)"
                    XCTAssertEqual(lhs.base, rhs.base, label + " base", file: file, line: line)
                    XCTAssertEqual(lhs.output, rhs.output, label + " output", file: file, line: line)
                    XCTAssertEqual(lhs.incoming, rhs.incoming, label + " incoming", file: file, line: line)
                    XCTAssertEqual(lhs.semanticInstrument, rhs.semanticInstrument, label + " instrument", file: file, line: line)
                    XCTAssertEqual(lhs.semanticSample, rhs.semanticSample, label + " sample", file: file, line: line)
                    XCTAssertEqual(lhs.carriedInstrument, rhs.carriedInstrument, label + " carried", file: file, line: line)
                    let birth = try resolved(lhs.associatedGeneration, batch: batch, bindings: bindings, file: file, line: line)
                    XCTAssertEqual(birth, rhs.associatedGeneration, label + " birth", file: file, line: line)
                    let coordinate = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: local, tick: tick, channel: channel), file: file, line: line)
                    let expectedCoordinate = try XCTUnwrap(expectedPlan.canonicalTickClock.coordinate(syntheticRow: rowOffset + local, tick: tick, channel: channel), file: file, line: line)
                    XCTAssertEqual(coordinate.absoluteFrame, expectedCoordinate.absoluteFrame, label + " absolute frame", file: file, line: line)
                    XCTAssertEqual(coordinate.canonicalTickOrdinal, expectedCoordinate.canonicalTickOrdinal, label + " ordinal", file: file, line: line)
                    let actualGlobal = try plan.diagnostics.voiceStateUpdates.filter {
                        $0.channelIndex == channel && $0.scheduledFrame == coordinate.absoluteFrame && isGlobal($0.command)
                    }.map { update in
                        globalPoint(update, source: try resolved(update.activeEventIndex,
                            batch: batch, bindings: bindings, file: file, line: line))
                    }
                    let expectedGlobal = expectedPlan.diagnostics.voiceStateUpdates.filter {
                        $0.channelIndex == channel && $0.scheduledFrame == expectedCoordinate.absoluteFrame && isGlobal($0.command)
                    }.map { globalPoint($0, source: $0.activeEventIndex) }
                    XCTAssertEqual(actualGlobal, expectedGlobal, label + " global targets/memory", file: file, line: line)
                    XCTAssertEqual(plan.instrumentAutovibrato(row: local, tick: tick, channel: channel),
                        expectedPlan.instrumentAutovibrato(row: rowOffset + local, tick: tick, channel: channel), label + " automatic", file: file, line: line)
                } }
            }
            // Compare native consumption order within each channel. Independent channels
            // may interleave differently when immutable batch-local numeric IDs restart.
            for entry in batch.adapterPlan.eventStorage.ordering {
                let event = batch.adapterPlan.events[entry.eventIndex]
                guard event.scheduledFrame < end else { continue }
                let source = try resolved(event.activeEventIndex, batch: batch, bindings: bindings, file: file, line: line)
                points.append(point(event, source: source))
            }
            rowOffset += plan.diagnostics.rowTiming.count
            sequence = batch.sequence; nextFrame = batch.endFrame
        }
        let expectedPoints = oracle.eventStorage.ordering.compactMap { entry -> NativePoint? in
            let event = oracle.events[entry.eventIndex]
            guard event.scheduledFrame < end else { return nil }
            if let expectedSourceRows, !expectedSourceRows.indices.contains(event.source.rowIndex) {
                XCTFail("In-range oracle event has no literal source-row projection", file: file, line: line)
                return nil
            }
            return point(event, source: event.activeEventIndex,
                sourceRow: expectedSourceRows?[event.source.rowIndex])
        }
        for channel in 0..<channelCount {
            XCTAssertEqual(points.filter { $0.channel == channel }, expectedPoints.filter { $0.channel == channel },
                "cap=\(cap) rate=\(rate) linear=\(input.usesLinearFrequencyTable) channel=\(channel)", file: file, line: line)
        }
        let warmH00 = expectedPlan.diagnostics.voiceStateUpdates.filter { update in
            // Ordinary full planning also emits a terminal-tail diagnostic one
            // synthetic row past its finite input. It is outside this comparison.
            guard update.scheduledFrame < end else { return false }
            if let expectedSourceRows, !expectedSourceRows.indices.contains(update.syntheticRow) {
                XCTFail("In-range global diagnostic has no literal source-row projection", file: file, line: line)
                return false
            }
            return (expectedSourceRows?[update.syntheticRow] ?? update.source.rowIndex) == 0 &&
                update.effectType == 0x11 && update.effectParam == 0 && update.syntheticTick > 0 &&
                update.effectMemoryReused && update.globalVolumeSlideResolvedParameter == 1
        }
        XCTAssertGreaterThanOrEqual(Set(warmH00.map(\.syntheticRow)).count, 3,
            "The oracle must execute admitted H00 memory after three real wraps", file: file, line: line)
        XCTAssertTrue(warmH00.allSatisfy { ($0.globalVolumeBefore ?? 64) < 64 },
            "Warm H00 must observe carried global state rather than a cold default", file: file, line: line)
        if !expectNoBirths {
            XCTAssertTrue(expectedPlan.diagnostics.voiceStateUpdates.contains {
                guard $0.scheduledFrame < end, $0.activeEventIndex != nil else { return false }
                switch $0.command { case .gxxChannelTarget, .hxyChannelTarget: return true; default: return false }
            }, "The matrix must actually publish source-bound global targets", file: file, line: line)
        }
        if expectNoBirths { XCTAssertTrue(bindings.isEmpty, file: file, line: line) }
        else { XCTAssertGreaterThanOrEqual(bindings.count, minimumBirths, file: file, line: line) }
    }

    private func resolved(_ local: Int?, batch: Producer.Batch, bindings: [BirthBinding],
        file: StaticString, line: UInt) throws -> Int? {
        guard let local else { return nil }
        let identity = try XCTUnwrap(batch.sourceIdentities[local], "Unbound actual source index \(local)", file: file, line: line)
        return try XCTUnwrap(bindings.first { $0.actual == identity }?.expected,
            "Source does not name a real observed birth: \(identity)", file: file, line: line)
    }

    private func isGlobal(_ command: PlaybackSongSyntheticVoiceStateUpdateCommand) -> Bool {
        switch command {
        case .gxxSetGlobalVolume, .gxxChannelTarget, .hxyGlobalVolumeSlide, .hxyChannelTarget: return true
        default: return false
        }
    }

    private func globalPoint(_ update: PlaybackSongSyntheticVoiceStateUpdateDiagnostic, source: Int?) -> GlobalPoint {
        .init(command: update.command, source: source, globalBefore: update.globalVolumeBefore,
            globalAfter: update.globalVolumeAfter, gainBefore: update.gainBefore, gainAfter: update.gainAfter,
            memoryReused: update.effectMemoryReused, memoryMissing: update.effectMemoryMissing,
            resolvedParameter: update.globalVolumeSlideResolvedParameter)
    }

    private func point(_ event: RuntimeCMixerAdapterEvent, source: Int?, sourceRow: Int? = nil) -> NativePoint {
        let payload: NativePoint.Payload
        switch event.action {
        case let .noteTrigger(_, e, m):
            let value = SyntheticTrackerEvent(row: 0, tick: e.tick, scheduledStartFrame: e.scheduledStartFrame,
                sample: e.sample, gain: e.gain, pan: e.pan, playbackStep: e.playbackStep, loop: e.loop,
                initialSourceFrame: e.initialSourceFrame, volumeEnvelope: e.volumeEnvelope, panEnvelope: e.panEnvelope,
                keyOffFrame: e.keyOffFrame, fadeoutFrameDecrement: e.fadeoutFrameDecrement)
            payload = .trigger(value, m.note, m.instrumentIndex, m.sampleIndex)
        case let .gainPanUpdate(_, gain, pan): payload = .gainPan(gain, pan)
        case let .stepUpdate(_, value): payload = .step(value)
        case let .envelopePositionUpdate(_, value): payload = .envelopePosition(value)
        case let .playbackStateChange(_, value): payload = .state(value)
        case let .envelopeSemanticUpdate(_, value): payload = .envelope(value)
        case let .channelSemanticUpdate(u): payload = .channel(u.instrumentIndex, u.sampleIndex, u.state,
            u.carriedInstrumentIndex, u.cachedDefaultVolume, u.cachedDefaultPan, u.selectionFrame)
        case let .audibleTargetUpdate(u): payload = .audible(u.amplitude, u.pan, u.durationFrames,
            u.intent, u.activation, u.rebaseFromCurrent, u.bpm, u.speed)
        case let .sourceStop(_, retire): payload = .stop(retire)
        case .noteCut: payload = .cut
        }
        return .init(frame: event.scheduledFrame, tick: event.syntheticTick, row: sourceRow ?? event.source.rowIndex,
            channel: event.channelIndex, source: source, categories: event.categories,
            effect: event.effectType, parameter: event.effectParam, volume: event.volumeColumn, payload: payload)
    }

    private func producer(_ song: PlaybackSong, rate: Double) throws -> Producer {
        try .init(song: song, initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2),
            sampleRate: rate, sourceGeneration: 11, transportEpoch: 17)
    }

    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0,
                      note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(linear: Bool, modulatedInstrument: Bool, birth: Bool = true, ownerOnly: Bool = false) -> PlaybackSong {
        let pattern = PlaybackPattern(index: 0, rows: [
            // The original four channels stay intact. The fifth admits H01 at
            // cold row 2; row-0 H00 must retain that executed memory across wrap.
            .init(index: 0, cells: [cell(0, 0x37), cell(4, 0x48), cell(15, 3), cell(15, 127), cell(17, 0)]),
            .init(index: 1, cells: [cell(14, 0x11), cell(33, 0x21), cell(14, 0xE1), cell(), cell(16, 0x30)]),
            .init(index: 2, cells: [cell(note: birth ? 49 : 0, instrument: birth || ownerOnly ? 1 : 0, volume: 0xA4),
                cell(note: birth ? 53 : 0, instrument: birth || ownerOnly ? 2 : 0, volume: 0xB8), cell(), cell(), cell(17, 1)]),
            .init(index: 3, cells: [cell(4, 0x48), cell(0, 0x73), cell(15, 5), cell(15, 143), cell(17, 0)])
        ])
        let volume = PlaybackVolumeEnvelope(enabled: modulatedInstrument,
            points: [.init(tick: 0, value: 48), .init(tick: 2, value: 13), .init(tick: 5, value: 61)],
            sustainPointIndex: nil, loopStartPointIndex: 0, loopEndPointIndex: 2,
            typeFlags: modulatedInstrument ? 5 : 0, fadeout: 257)
        let pan = PlaybackPanningEnvelope(enabled: modulatedInstrument,
            points: [.init(tick: 0, value: 7), .init(tick: 3, value: 57), .init(tick: 6, value: 23)],
            sustainPointIndex: nil, loopStartPointIndex: 0, loopEndPointIndex: 2,
            typeFlags: modulatedInstrument ? 5 : 0)
        var instruments = [Int: PlaybackInstrument]()
        for index in 1...2 {
            let pcm: [Float] = (0..<64).map { Float(($0 * (index == 1 ? 37 : 19) + 11) % 127 - 63) / 128 }
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0, pcm: pcm,
                volume: index == 1 ? 0.75 : 0.5, panning: index == 1 ? 79 : 183,
                relativeNote: index - 1, finetune: index == 1 ? -32 : 16,
                baseSampleRate: 8363, loopStart: 0, loopLength: pcm.count, loopType: index)
            instruments[index] = .init(index: index, samples: [sample], volumeEnvelope: volume,
                panningEnvelope: pan, autoVibrato: modulatedInstrument
                    ? .init(waveformType: UInt8(index - 1), sweep: 19, depth: 7, rate: UInt8(index * 9)) : .disabled,
                noteSampleMap: Array(repeating: 0, count: 96))
        }
        return .init(title: "Public production continuation mix", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: pattern], instrumentsByIndex: instruments, restartOrderIndex: 0,
            endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: linear)
    }
}

/// Public in-memory recipe v1. The oracle uses accepted legacy traversal only to
/// select literal executed rows, then ordinary finite interpretation/C rendering.
/// Structural commands live on silent channels and are removed only after their
/// accepted row visits/precedence have been checked; musical cells stay exact.
struct LoopTraversalProofFixture {
    enum Kind: CaseIterable, Equatable { case e6DelayFxx, sameOrderJump, outgoingJump }
    let input: PlaybackSong, oracle: PlaybackSong
    let visits: [Int]
    let targetRows: Int

    static func make(_ kind: Kind, linear: Bool) throws -> Self {
        func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0,
               note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
            .init(note: note, instrument: instrument, volumeColumn: volume,
                effectType: effect, effectParam: parameter)
        }
        var rows: [[PlaybackCell]] = [
            [c(0, 0x37), c(17, 0), c(15, 3), c(15, 127), c(), c()],
            [c(4, 0x48), c(16, 0x30), c(14, 0xE1), c(), c(), c()],
            [c(note: 49, instrument: 1, volume: 0xB8), c(17, 1), c(), c(), c(), c()],
            [c(1, 1), c(17, 0), c(15, 5), c(15, 143), c(), c()]
        ]
        let cold: [Int], warm: [Int]
        switch kind {
        case .e6DelayFxx:
            rows[1][4] = c(14, 0x60); rows[3][4] = c(14, 0x61)
            cold = [2, 3, 1, 2, 3]; warm = [0, 1, 2, 3, 1, 2, 3]
        case .sameOrderJump:
            // G38A: row-1 EE1 consumes the jump flag, then advances the D02
            // pending row once before the next cell read, reaching row 3.
            rows[1][4] = c(11, 0); rows[1][5] = c(13, 2)
            cold = [2, 3]; warm = [0, 1, 3]
        case .outgoingJump:
            rows[1][4] = c(11, 1); rows[1][5] = c(13, 2)
            cold = [2, 3]; warm = [0, 1]
        }
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: (0..<64).map { Float(($0 * 37 + 11) % 127 - 63) / 128 }, volume: 0.75,
            panning: 79, relativeNote: 0, finetune: -32, baseSampleRate: 8363,
            loopStart: 0, loopLength: 64, loopType: 1)
        let envelope = PlaybackVolumeEnvelope(enabled: true,
            points: [.init(tick: 0, value: 48), .init(tick: 2, value: 13), .init(tick: 5, value: 61)],
            sustainPointIndex: nil, loopStartPointIndex: 0, loopEndPointIndex: 2, typeFlags: 5, fadeout: 257)
        let pan = PlaybackPanningEnvelope(enabled: true,
            points: [.init(tick: 0, value: 7), .init(tick: 3, value: 57), .init(tick: 6, value: 23)],
            sustainPointIndex: nil, loopStartPointIndex: 0, loopEndPointIndex: 2, typeFlags: 5)
        let instrument = PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope,
            panningEnvelope: pan, autoVibrato: .init(waveformType: 0, sweep: 19, depth: 7, rate: 9),
            noteSampleMap: Array(repeating: 0, count: 96))
        func song(_ patterns: [Int: PlaybackPattern], _ orders: [Int]) -> PlaybackSong {
            .init(title: "Public traversal/native continuation recipe v1",
                orders: orders.enumerated().map { .init(orderIndex: $0.offset, patternIndex: $0.element) },
                patternsByIndex: patterns, instrumentsByIndex: [1: instrument], restartOrderIndex: 0,
                endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: linear)
        }
        let input = song([0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) }),
            1: .init(index: 1, rows: (0..<4).map { .init(index: $0, cells: Array(repeating: c(), count: 6)) })], [0, 1])
        func accepted(_ start: Int) -> PlaybackSongTraversalPlan {
            PlaybackSongTraversalPlanner.plan(input, startOrderIndex: 0, orderCount: 2,
                initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: start))
        }
        let acceptedCold = accepted(2), acceptedWarm = accepted(0)
        XCTAssertFalse(acceptedCold.guardHit); XCTAssertFalse(acceptedWarm.guardHit)
        XCTAssertEqual(acceptedCold.rows.prefix { $0.orderIndex == 0 }.map(\.rowArrayIndex), cold)
        XCTAssertEqual(acceptedWarm.rows.prefix { $0.orderIndex == 0 }.map(\.rowArrayIndex), warm)
        if kind == .e6DelayFxx {
            XCTAssertTrue(acceptedCold.traversalDiagnostics.contains(where: \.loopTaken))
            XCTAssertTrue(acceptedWarm.traversalDiagnostics.contains(where: \.loopTaken))
        } else {
            XCTAssertTrue(acceptedWarm.traversalDiagnostics.contains { $0.kind == .bxxPositionJump && $0.applied && $0.combinedWithDxx })
            XCTAssertTrue(acceptedWarm.traversalDiagnostics.contains { $0.kind == .dxxPatternBreak && $0.applied && $0.combinedWithBxx })
            XCTAssertFalse(warm.contains(2), "Every warm pass skips the later birth")
            if kind == .outgoingJump { XCTAssertFalse(warm.contains(3), "Outgoing B/D ends the selected scope before row 3") }
        }
        let visits = cold + (0..<7).flatMap { _ in warm }
        let targetRows = cold.count + 3 * warm.count
        // Extra finite rows provide the exact next-row peek beyond the compared interval.
        let flat = visits.enumerated().map { index, source -> PlaybackRow in
            var cells = rows[source]
            cells[4] = c(); cells[5] = c()
            return .init(index: index, cells: cells)
        }
        let oracle = song([0: .init(index: 0, rows: flat)], [0])
        return .init(input: input, oracle: oracle, visits: visits, targetRows: targetRows)
    }
}
