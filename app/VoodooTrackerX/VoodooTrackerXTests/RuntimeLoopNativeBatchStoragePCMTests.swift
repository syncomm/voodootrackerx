import Foundation
import XCTest

private final class Generation { let cache = CSoftwareMixerSharedSamplePayloadCache() }
private final class WeakPlan { weak var value: AnyObject?; init(_ value: AnyObject?) { self.value = value } }
private func song(_ visits: [Int], linear: Bool, globalVolume: Bool = false) -> PlaybackSong {
    let cells: [PlaybackCell] = [
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 1, effectParam: 1),
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
        .init(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)]
    let global: [PlaybackCell] = [
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x11, effectParam: 0),
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x10, effectParam: 0x30),
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x11, effectParam: 1),
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x11, effectParam: 0)]
    let pattern = PlaybackPattern(index: 0, rows: visits.enumerated().map {
        .init(index: $0.offset, cells: globalVolume ? [cells[$0.element], global[$0.element]] : [cells[$0.element]])
    })
    let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25, -0.25, 0.125, -0.125],
        volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 4, loopType: 1)
    return .init(title: "Public loop source-continuation regression", orders: [.init(orderIndex: 0, patternIndex: 0)],
        patternsByIndex: [0: pattern], instrumentsByIndex: [1: .init(index: 1, samples: [sample])],
        restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: linear)
}
private func makeCore(_ rate: Double) -> RuntimeCMixerRenderCore {
    .init(config: .init(sampleRate: rate, channelCount: 1), maximumRenderFrames: 1024,
        outputPolicy: .init(outputGain: 1, headroomPolicy: "control", gainPolicySource: "control"))
}
private func render(_ core: RuntimeCMixerRenderCore, count: Int) -> [Float] {
    var result = [Float](repeating: 0, count: count)
    XCTAssertTrue(result.withUnsafeMutableBufferPointer { core.render(into: $0, frameCount: count) }, "C render")
    return result
}
/// Uses the existing normal full-plan Core as PCM oracle; only production continuation
/// chooses/interprets each bounded batch and prepares the native commands.
final class RuntimeLoopNativeBatchStoragePCMTests: XCTestCase {
    func testProductionStorageAndCoreMatchExpandedPCMAtBothRatesModesAndRowCaps() throws {
        for rate in [44_100.0, 48_000] { for linear in [true, false] { for cap in [1, 3, 7] {
            for globalVolume in [false, true] {
                try qualify(rate: rate, linear: linear, cap: cap, globalVolume: globalVolume)
            }
            for kind in LoopTraversalProofFixture.Kind.allCases {
                try qualify(rate: rate, linear: linear, cap: cap, globalVolume: false,
                    traversal: LoopTraversalProofFixture.make(kind, linear: linear))
            }
        } } }
    }
    private func qualify(rate: Double, linear: Bool, cap: Int, globalVolume: Bool,
                         traversal: LoopTraversalProofFixture? = nil) throws {
        let visits = traversal?.visits ?? [2, 3] + (0..<3).flatMap { _ in [0, 1, 2, 3] }
        let oracle = RuntimeCMixerAdapterEventPlan.make(
            song: traversal?.oracle ?? song(visits, linear: linear, globalVolume: globalVolume), sampleRate: rate)
        let expectedPlan = try XCTUnwrap(oracle.plan)
        let total: Int
        if let traversal { total = expectedPlan.diagnostics.rowTiming[traversal.targetRows].rowStartFrame }
        else { total = try XCTUnwrap(oracle.plannedSongEndFrame) }
        let resolver = PlaybackSongSampleTimePositionResolver(plan: expectedPlan)
        let trackerChannels = traversal?.input.pattern(for: 0)?.rows.first?.cells.count ?? (globalVolume ? 2 : 1)
        var comparedGlobalTicks = 0, sourceBoundGlobalTargets = 0
        var warmH00Rows = Set<Int>(), gxxRows = Set<Int>()
        var expectedOccurrences = [OccurrencePoint]()
        let producer = try PlaybackSongUserLoopProducer(
            song: traversal?.input ?? song([0, 1, 2, 3], linear: linear, globalVolume: globalVolume),
            initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2), sampleRate: rate,
            sourceGeneration: 7, transportEpoch: 9)
        let scope = RuntimeLoopNativeScope(documentHigh: 1, documentLow: 2, sourceGeneration: 7,
            transportEpoch: 9, sampleRateBits: rate.bitPattern, semanticVersion: 1,
            linearFrequencyMode: linear, order: 0, pattern: 0, firstRow: 0, lastRow: 3)
        let generation = Generation(), channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
        let actual = makeCore(rate), control = makeCore(rate)
        defer { actual.stopAll(); control.stopAll(); channel.shutdownAfterCallbackQuiescence() }
        @inline(never) func produce() throws -> WeakPlan {
            let reservation = try XCTUnwrap(channel.reserve())
            let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: cap)
            let weak = WeakPlan(batch.adapterPlan.semanticPlanOwnerForTesting)
            if globalVolume {
                let plan = try XCTUnwrap(batch.adapterPlan.plan)
                for timing in plan.diagnostics.rowTiming {
                    for tick in 0..<timing.actualTickCount {
                        let coordinate = try XCTUnwrap(plan.canonicalTickClock.coordinate(
                            syntheticRow: timing.syntheticRow, tick: tick, channel: 0))
                        let frame = coordinate.absoluteFrame
                        guard frame < total else { continue }
                        comparedGlobalTicks += 1
                        XCTAssertEqual(globalPoints(plan, at: frame), globalPoints(expectedPlan, at: frame),
                            "every-tick global writer/held target, frame=\(frame), cap=\(cap), rate=\(rate), linear=\(linear)")
                    }
                }
                for update in plan.diagnostics.voiceStateUpdates where update.scheduledFrame < total {
                    if update.activeEventIndex != nil {
                        switch update.command {
                        case .gxxChannelTarget, .hxyChannelTarget: sourceBoundGlobalTargets += 1
                        default: break
                        }
                    }
                    if update.source.rowIndex == 1, case .gxxSetGlobalVolume = update.command {
                        gxxRows.insert(try XCTUnwrap(plan.diagnostics.rowTiming.first {
                            $0.syntheticRow == update.syntheticRow }).rowStartFrame)
                    }
                    guard update.source.rowIndex == 0 && update.effectType == 0x11 && update.effectParam == 0 &&
                        update.syntheticTick > 0 else { continue }
                    XCTAssertTrue(update.effectMemoryReused && !update.effectMemoryMissing)
                    XCTAssertEqual(update.globalVolumeSlideResolvedParameter, 1)
                    XCTAssertLessThan(try XCTUnwrap(update.globalVolumeBefore), 64,
                        "Warm H00 must consume carried non-default global state")
                    let timing = try XCTUnwrap(plan.diagnostics.rowTiming.first { $0.syntheticRow == update.syntheticRow })
                    warmH00Rows.insert(timing.rowStartFrame)
                }
            }
            let storage = try RuntimeLoopNativeBatchStorage(batch: batch, scope: scope,
                trackerChannelCount: trackerChannels, cache: generation.cache, recordsCategories: true)
            XCTAssertTrue(storage.header.commandCount == batch.adapterPlan.events.count, "every generated command")
            XCTAssertTrue(storage.header.terminalStateToken == batch.sequence && storage.header.predecessorStateToken == batch.predecessorSequence, "state tokens")
            let commands = storage.header.commands?.assumingMemoryBound(to: RuntimeLoopNativeCommandDescriptor.self)
            for (index, entry) in batch.adapterPlan.eventStorage.ordering.enumerated() {
                let event = batch.adapterPlan.events[entry.eventIndex], command = commands![index]
                XCTAssertTrue(command.eventID == event.id && command.eventOrdinal == entry.eventIndex, "original numeric event ID/ordinal")
                XCTAssertTrue(command.localSourceIndex == event.activeEventIndex ?? -1, "original source index")
                if (globalVolume || traversal != nil) && event.scheduledFrame < total {
                    expectedOccurrences.append(.init(sequence: batch.sequence, eventID: event.id,
                        ordinal: entry.eventIndex, source: event.activeEventIndex ?? -1,
                        frame: UInt64(event.scheduledFrame), birth: event.activeEventIndex.flatMap { batch.sourceIdentities[$0] }))
                }
                if command.targetBindingOrdinal >= 0 {
                    let target = try XCTUnwrap(storage.header.bindings)[command.targetBindingOrdinal]
                    XCTAssertTrue(target.birth == batch.sourceIdentities[target.localLookupIndex], "exact original birth scope")
                }
            }
            XCTAssertTrue(storage.header.followRowCount == storage.rowTimings.count, "stable follow count")
            for (index, row) in storage.rowTimings.enumerated() {
                let native = try XCTUnwrap(storage.header.followRows)[index]
                XCTAssertTrue(native.rowStartFrame == row.rowStartFrame && native.rowEndFrame == row.rowStartFrame + row.rowDurationFrames && native.actualTickCount == row.actualTickCount, "stable follow POD")
            }
            XCTAssertTrue(channel.publish(reservation, header: storage.header, retaining: storage), "publication")
            return weak
        }
        let first = try produce(); XCTAssertTrue(first.value == nil, "first semantic plan released after native conversion")
        guard case .admitted = channel.begin(at: 0) else { return XCTFail("claim initial") }
        let next = try produce(); XCTAssertTrue(next.value == nil, "successor semantic plan released after native conversion")
        actual.configureNativeLoopDelivery(channel: channel, scope: scope, trackerChannelCount: trackerChannels, keepingAlive: generation, recordsOccurrences: globalVolume || traversal != nil)
        control.configureAdapterEventSchedule(oracle.eventStorage, runtimeFrameOffset: 0)
        let partitions = [1, 127, 31, 509, 997]
        var frame = 0, ordinal = 0, lastAcknowledged: UInt64 = 0
        var observedWarmEntries = Set<Int>()
        while frame < total {
            let count = min(total - frame, partitions[ordinal % partitions.count])
            let lhs = render(actual, count: count), rhs = render(control, count: count)
            if let mismatch = zip(lhs, rhs).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
                return XCTFail("PCM frame \(frame + mismatch.offset), rate=\(rate), linear=\(linear), cap=\(cap)")
            }
            frame += count; ordinal += 1
            XCTAssertTrue(actual.consumeNativeLoopPlanningFailure() == nil && actual.consumeNativeLoopHostFault() == nil, "no delivery fault")
            if frame < total {
                let follow = try XCTUnwrap(actual.nativeLoopFollowPosition())
                let expected = try XCTUnwrap(resolver.position(atFrame: frame))
                XCTAssertTrue(follow.nativeFrame == UInt64(frame), "follow native clock")
                XCTAssertTrue(follow.rowStartFrame == expected.rowStartFrame && follow.rowEndFrame == expected.rowEndFrame && follow.tickInRow == expected.tickInRow, "follow row/tick")
                XCTAssertTrue(follow.source.rowIndex == visits[expected.syntheticRow], "follow original row")
                if traversal != nil, follow.source.rowIndex == 0 { observedWarmEntries.insert(follow.rowStartFrame) }
            }
            let acknowledged = channel.acknowledgedSequence
            if acknowledged != lastAcknowledged {
                XCTAssertTrue(acknowledged == lastAcknowledged + 1, "at most one horizon per callback")
                channel.reclaimRetired()
                let probe = try produce(); XCTAssertTrue(probe.value == nil, "semantic plan released after each conversion")
                lastAcknowledged = acknowledged
            }
        }
        if globalVolume {
            XCTAssertEqual(comparedGlobalTicks, expectedPlan.canonicalTickClock.totalCanonicalTicks)
            XCTAssertEqual(warmH00Rows.count, 3, "Three complete warm wraps execute H00 from the cold H01 seed")
            XCTAssertEqual(gxxRows.count, 3, "The unplayed cold G30 prefix first executes only after wrap")
            XCTAssertGreaterThan(sourceBoundGlobalTargets, 0)
        }
        if globalVolume || traversal != nil {
            if let traversal {
                XCTAssertEqual(Array(visits.prefix(traversal.targetRows)).filter { $0 == 0 }.count, 3)
                XCTAssertEqual(observedWarmEntries.count, 3, "Actual native follow observes three warm entries")
                XCTAssertGreaterThan(expectedOccurrences.count, 0, "The structural matrix executes actual native commands")
            }
            let native = actual.drainNativeLoopOccurrences()
            XCTAssertEqual(native.failures, 0); XCTAssertEqual(native.drops, 0)
            XCTAssertEqual(native.attempts, UInt64(expectedOccurrences.count))
            XCTAssertTrue(native.events.allSatisfy { $0.scope == scope && $0.plannedFrame == $0.appliedFrame })
            XCTAssertEqual(native.events.map { OccurrencePoint(sequence: $0.sequence, eventID: $0.eventID,
                ordinal: $0.eventOrdinal, source: $0.localSourceIndex, frame: $0.plannedFrame, birth: $0.targetBirth) },
                expectedOccurrences, "Every actual native command retains its planned frame, numeric IDs and full birth binding")
        }
    }

    private struct OccurrencePoint: Equatable {
        let sequence: UInt64, eventID: Int, ordinal: Int, source: Int, frame: UInt64
        let birth: RuntimeLoopNativeSourceIdentity?
    }

    private struct GlobalPoint: Equatable {
        let channel: Int, command: PlaybackSongSyntheticVoiceStateUpdateCommand
        let birthFrame: Int?, globalBefore: Int?, globalAfter: Int?
        let gainBefore: Float?, gainAfter: Float?
        let memoryReused: Bool, memoryMissing: Bool, resolvedParameter: UInt8?
    }

    private func globalPoints(_ plan: PlaybackSongSyntheticPlan, at frame: Int) -> [GlobalPoint] {
        plan.diagnostics.voiceStateUpdates.compactMap { update in
            guard update.scheduledFrame == frame else { return nil }
            switch update.command {
            case .gxxSetGlobalVolume, .gxxChannelTarget, .hxyGlobalVolumeSlide, .hxyChannelTarget: break
            default: return nil
            }
            let birth = update.activeEventIndex.flatMap {
                plan.pattern.events.indices.contains($0) ? plan.pattern.events[$0].scheduledStartFrame : nil
            }
            return .init(channel: update.channelIndex, command: update.command, birthFrame: birth,
                globalBefore: update.globalVolumeBefore, globalAfter: update.globalVolumeAfter,
                gainBefore: update.gainBefore, gainAfter: update.gainAfter,
                memoryReused: update.effectMemoryReused, memoryMissing: update.effectMemoryMissing,
                resolvedParameter: update.globalVolumeSlideResolvedParameter)
        }
    }
}

/// Public in-memory recipe v1. The oracle uses accepted legacy traversal only to
/// select literal executed rows, then ordinary finite interpretation/C rendering.
/// Structural commands live on silent channels and are removed only after their
/// accepted row visits/precedence have been checked; musical cells stay exact.
private struct LoopTraversalProofFixture {
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
