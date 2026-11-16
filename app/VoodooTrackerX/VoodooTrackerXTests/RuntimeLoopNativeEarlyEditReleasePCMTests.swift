import Foundation
import XCTest

private func demand(_ value: Bool, _ reason: String,
                    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value, reason, file: file, line: line)
}
private final class GenerationCache { let cache = CSoftwareMixerSharedSamplePayloadCache() }
private func inputSong(linear: Bool, edited: Bool, expanded: Bool = false,
                       envelope: Bool, recipe: Int) -> PlaybackSong {
    let original: [PlaybackCell] = [
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
        .init(note: recipe == 2 ? 97 : 0, instrument: 0, volumeColumn: 0,
            effectType: recipe == 0 || recipe == 3 ? 20 : 0, effectParam: recipe == 0 || recipe == 3 ? 1 : 0),
        .init(note: 49, instrument: 1, volumeColumn: 0, effectType: recipe == 1 ? 20 : 0, effectParam: 0),
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)]
    var replacement = original
    if recipe != 3 { replacement[1] = .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0) }
    let cells = expanded ? [original[2], original[3]] + (0..<3).flatMap { _ in replacement } : (edited ? replacement : original)
    let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25, -0.25, 0.125, -0.125],
        volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 4, loopType: 1)
    let volume = PlaybackVolumeEnvelope(enabled: envelope,
        points: envelope ? [.init(tick: 0, value: 64), .init(tick: 3, value: 40), .init(tick: 8, value: 0)] : [],
        sustainPointIndex: envelope ? 1 : nil, loopStartPointIndex: nil, loopEndPointIndex: nil,
        typeFlags: envelope ? 3 : 0, fadeout: 1024)
    return .init(title: "Public obsolete-release edit control", orders: [.init(orderIndex: 0, patternIndex: 0)],
        patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
        instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: volume, noteSampleMap: Array(repeating: 0, count: 96))],
        restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: linear)
}
private func scope(_ rate: Double, _ linear: Bool, generation: UInt64) -> RuntimeLoopNativeScope {
    .init(documentHigh: 1, documentLow: 2, sourceGeneration: generation, transportEpoch: 9,
        sampleRateBits: rate.bitPattern, semanticVersion: 1, linearFrequencyMode: linear,
        order: 0, pattern: 0, firstRow: 0, lastRow: 3)
}
private func core(_ rate: Double) -> RuntimeCMixerRenderCore {
    .init(config: .init(sampleRate: rate, channelCount: 1), maximumRenderFrames: 1024,
        outputPolicy: .init(outputGain: 1, headroomPolicy: "control", gainPolicySource: "control"))
}
private func render(_ core: RuntimeCMixerRenderCore, _ count: Int) -> [Float] {
    var output = [Float](repeating: 0, count: count)
    demand(output.withUnsafeMutableBufferPointer { core.render(into: $0, frameCount: count) }, "render")
    return output
}
final class RuntimeLoopNativeEarlyEditReleasePCMTests: XCTestCase {
    func testReleaseEditsMatchExpandedPCMWithoutSpeculativeNativeKeyOff() throws {
        var maximumCacheKeys = 0
        for rate in [44_100.0, 48_000] { for linear in [true, false] { for envelope in [true, false] {
            for recipe in 0..<4 { maximumCacheKeys = max(maximumCacheKeys, try qualify(rate: rate, linear: linear, envelope: envelope, recipe: recipe)) }
        } } }
        XCTAssertLessThanOrEqual(maximumCacheKeys, 1)
    }
    private func qualify(rate: Double, linear: Bool, envelope: Bool, recipe: Int) throws -> Int {
        let oldSong = inputSong(linear: linear, edited: false, envelope: envelope, recipe: recipe)
        let newSong = inputSong(linear: linear, edited: true, envelope: envelope, recipe: recipe)
        let oldScope = scope(rate, linear, generation: 3), newScope = scope(rate, linear, generation: 4)
        let producer = try PlaybackSongUserLoopProducer(song: oldSong,
            initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2), sampleRate: rate,
            sourceGeneration: 3, transportEpoch: 9)
        let activeStart = producer.exportResumeState(), generation = GenerationCache()
        let active = try producer.next(minimumHorizonFrames: Int(rate / 2), maximumRows: 128)
        let boundary = try XCTUnwrap(active.naturalBoundaries.first)
        demand(boundary.frame < active.endFrame && boundary.frame > 1, "edit is inside multiiteration batch")
        let channel = RuntimeLoopNativeTwoSlotChannel(scope: oldScope)
        var initial: RuntimeLoopNativeBatchStorage? = try .init(batch: active, scope: oldScope, trackerChannelCount: 1, cache: generation.cache)
        weak let initialWeak = initial
        let initialCommands = initial!.header.commands?.assumingMemoryBound(to: RuntimeLoopNativeCommandDescriptor.self)
        for ordinal in 0..<initial!.header.commandCount {
            let value = initialCommands![ordinal].payload!.assumingMemoryBound(to: RuntimeLoopPreparedCommandPayload.self).pointee
            if case let .birth(birth) = value.action { demand(birth.absoluteKeyOffFrame == nil, "no future keyoff preinstallation") }
        }
        demand(channel.publish(try XCTUnwrap(channel.reserve()), header: initial!.header, retaining: initial!), "active publish")
        initial = nil
        guard case .admitted = channel.begin(at: 0) else { XCTFail("initial claim"); return 0 }
        let oldSuccessor = try producer.next(minimumHorizonFrames: Int(rate / 2), maximumRows: 128)
        var safety: RuntimeLoopNativeBatchStorage? = try .init(batch: oldSuccessor, scope: oldScope, trackerChannelCount: 1, cache: generation.cache)
        weak let safetyWeak = safety
        demand(channel.publish(try XCTUnwrap(channel.reserve()), header: safety!.header, retaining: safety!), "safety publish")
        safety = nil
        let actual = core(rate), control = core(rate)
        defer { actual.stopAll(); control.stopAll(); channel.shutdownAfterCallbackQuiescence() }
        actual.configureNativeLoopDelivery(channel: channel, scope: oldScope, trackerChannelCount: 1, keepingAlive: generation, recordsOccurrences: true)
        let oracle = RuntimeCMixerAdapterEventPlan.make(song: inputSong(linear: linear, edited: true, expanded: true, envelope: envelope, recipe: recipe), sampleRate: rate)
        control.configureAdapterEventSchedule(oracle.eventStorage, runtimeFrameOffset: 0)
        demand(render(actual, 1) == render(control, 1), "old prefix before edit request")
        let proof = try PlaybackSongUserLoopProducer.prevalidateRefresh(song: newSong,
            resuming: activeStart, sourceGeneration: 4)
        channel.authorizeRefreshRequest(5)
        let reservation = try XCTUnwrap(channel.retractReady())
        demand(safetyWeak == nil, "old ready releases before new preparation")
        @inline(never) func reconstructPrefix() throws -> PlaybackSongUserLoopProducer.ResumeState {
            let replay = try PlaybackSongUserLoopProducer(song: oldSong, resuming: activeStart, sourceGeneration: 3)
            let prefix = try replay.next(minimumHorizonFrames: 1, maximumRows: boundary.rowCount,
                untilFrame: boundary.frame, nextRowOverride: try XCTUnwrap(newSong.pattern(for: 0)).rows[0])
            demand(prefix.sequence == active.sequence && prefix.endFrame == boundary.frame, "literal old prefix birth scope")
            return replay.exportResumeState()
        }
        let prefixState = try reconstructPrefix() // Prefix graph dies before new semantic/native construction.
        let editedProducer = try PlaybackSongUserLoopProducer(resuming: prefixState, validatedRefresh: proof)
        let edited = try editedProducer.next(minimumHorizonFrames: Int(rate / 2), maximumRows: 128)
        let cutover = RuntimeLoopNativeEarlyCutover(previousScope: oldScope, predecessorSequence: active.sequence,
            boundaryFrame: UInt64(boundary.frame), boundaryStateToken: boundary.stateToken, requestSerial: 5)
        let native = try RuntimeLoopNativeBatchStorage(batch: edited, scope: newScope,
            trackerChannelCount: 1, cache: generation.cache, earlyCutover: cutover)
        demand(channel.publish(reservation, header: native.header, retaining: native), "edit publication")
        let end = try XCTUnwrap(oracle.plannedSongEndFrame), partitions = [1, 127, 31, 509, 997]
        var frame = 1, ordinal = 0, sawCutover = false, lastRetired: UInt64 = 0
        while frame < end {
            let count = min(end - frame, partitions[ordinal % partitions.count])
            let lhs = render(actual, count), rhs = render(control, count)
            if let first = zip(lhs, rhs).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
                XCTFail("edit PCM mismatch frame \(frame + first.offset), rate \(rate), linear \(linear), env \(envelope), recipe \(recipe)")
                return editedProducer.resources.cachedSampleBuffers
            }
            frame += count; ordinal += 1
            demand(actual.consumeNativeLoopPlanningFailure() == nil && actual.consumeNativeLoopHostFault() == nil, "no edit delivery failure")
            if let frontier = channel.latestExecutionFrontier, frontier.sequence != lastRetired {
                if !sawCutover {
                    demand(frontier.sourceGeneration == 3 && frontier.sequence == active.sequence,
                        "retired original scope")
                    demand(frontier.frame == UInt64(boundary.frame) && frontier.stateToken == boundary.stateToken && !frontier.wholeBatch,
                        "acknowledge real prefix, never discarded old tail")
                    demand(frontier.admittedSourceGeneration == 4 && frontier.admittedSequence == edited.sequence,
                        "new generation admission receipt at actual B")
                    demand(initialWeak != nil, "callback does not dispose active owner")
                    sawCutover = true
                }
                channel.reclaimRetired()
                if sawCutover { demand(initialWeak == nil, "old active graph retires off audio after prefix ACK") }
                let next = try editedProducer.next(minimumHorizonFrames: Int(rate / 2), maximumRows: 128)
                let owner = try RuntimeLoopNativeBatchStorage(batch: next, scope: newScope,
                    trackerChannelCount: 1, cache: generation.cache)
                demand(channel.publish(try XCTUnwrap(channel.reserve()), header: owner.header, retaining: owner), "normal following new generation")
                lastRetired = frontier.sequence
            }
        }
        demand(sawCutover, "actual natural-boundary cutover observed")
        let diagnostics = actual.drainNativeLoopOccurrences()
        demand(!diagnostics.events.contains { $0.opcode == 0 && $0.appliedFrame == UInt64(boundary.frame) }, "edit boundary does not fabricate a new birth")
        demand(diagnostics.events.allSatisfy { $0.plannedFrame == $0.appliedFrame }, "exact executed frames")
        return editedProducer.resources.cachedSampleBuffers
    }
}
