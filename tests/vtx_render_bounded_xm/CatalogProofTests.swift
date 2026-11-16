import XCTest
@testable import VoodooTrackerXPlaybackSupport

final class CatalogProofTests: XCTestCase {
    private typealias P = PlaybackSongUserLoopProducer
    private func song(_ pcm: [Float], note: UInt8 = 49) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: pcm, volume: 1,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: pcm.count, loopType: 1)
        return .init(title: "Public catalog proof", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: [
                .init(index: 0, cells: [.init(note: note, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)]),
                .init(index: 1, cells: [.init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)])])],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: true)
    }
    private func producer(_ song: PlaybackSong, generation: UInt64 = 3, epoch: UInt64 = 9) throws -> P {
        try .init(song: song, initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            sampleRate: 48_000, sourceGeneration: generation, transportEpoch: epoch)
    }
    private func address(_ pcm: [Float]) -> UInt { pcm.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) } }

    func testPrevalidatedProofConsumesSameLeasePrefixAndReusesSanitizedPCMWithFreshRawStorage() throws {
        let pcm: [Float] = [0.25, -0.25, 0.125, -0.125]
        let old = song(pcm), fresh = song(pcm.map { $0 }, note: 52)
        XCTAssertNotEqual(address(old.instrumentsByIndex[1]!.samples[0].pcm), address(fresh.instrumentsByIndex[1]!.samples[0].pcm))
        let original = try producer(old), start = original.exportResumeState()
        let batch = try original.next(minimumHorizonFrames: Int.max, maximumRows: 4)
        let boundary = try XCTUnwrap(batch.naturalBoundaries.first)
        let proof = try P.prevalidateRefresh(song: fresh, resuming: start, sourceGeneration: 4)
        XCTAssertThrowsError(try P(resuming: start, validatedRefresh: proof)) // Not a natural boundary.
        let replay = try P(song: old, resuming: start, sourceGeneration: 3)
        _ = try replay.next(minimumHorizonFrames: 1, maximumRows: boundary.rowCount, untilFrame: boundary.frame,
            nextRowOverride: fresh.pattern(for: 0)!.rows[0])
        let prefix = replay.exportResumeState()
        XCTAssertTrue(prefix.isNaturalBoundary)
        let edited = try P(resuming: prefix, validatedRefresh: proof)
        XCTAssertEqual(edited.resources.cachedSampleBuffers, replay.resources.cachedSampleBuffers)
        let next = try edited.next(minimumHorizonFrames: 1, maximumRows: 1)
        let birth = try XCTUnwrap(next.adapterPlan.events.first { if case .noteTrigger = $0.action { return true }; return false }?.activeEventIndex)
        let oldPCM = try XCTUnwrap(batch.adapterPlan.plan).pattern.events[0].sample.monoPCM
        let newPCM = try XCTUnwrap(next.adapterPlan.plan).pattern.events[birth].sample.monoPCM
        XCTAssertEqual(address(newPCM), address(oldPCM)) // Selected immutable sanitized buffer, not process memory.
        XCTAssertEqual(next.sourceIdentities[birth]?.sourceGeneration, 4)
    }

    func testChangedBytesStaleGenerationOtherLeaseAndEpochCannotUseProof() throws {
        let old = song([0.25, -0.25, 0.125, -0.125]), original = try producer(old)
        let start = original.exportResumeState()
        let proof = try P.prevalidateRefresh(song: old, resuming: start, sourceGeneration: 4)
        for input in [song([0.5, -0.25, 0.125, -0.125])] {
            XCTAssertThrowsError(try P.prevalidateRefresh(song: input, resuming: start, sourceGeneration: 4)) {
                guard case .incompatibleRefresh? = $0 as? P.Failure else { return XCTFail("Expected catalog refusal") }
            }
        }
        XCTAssertThrowsError(try P.prevalidateRefresh(song: old, resuming: start, sourceGeneration: 3))
        for (generation, epoch) in [(UInt64(3), UInt64(9)), (3, 10), (2, 9)] {
            let other = try producer(old, generation: generation, epoch: epoch)
            _ = try other.next(minimumHorizonFrames: 1, maximumRows: 2,
                untilFrame: Int(48_000 * 2.5 / 125) * 6)
            XCTAssertThrowsError(try P(resuming: other.exportResumeState(), validatedRefresh: proof))
        }
    }
}
