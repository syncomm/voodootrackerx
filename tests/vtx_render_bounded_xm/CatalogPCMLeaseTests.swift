import XCTest
@testable import VoodooTrackerXPlaybackSupport

final class CatalogPCMLeaseTests: XCTestCase {
    private typealias P = PlaybackSongUserLoopProducer

    private func song(note: UInt8) -> PlaybackSong {
        // Fresh raw Array storage on every revision; the second sample is absent
        // from every executed and speculative row of the old active batch.
        let pcm: [[Float]] = [[0.25, -0.25, 0.125, -0.125], [0.5, -0.5, 0.375, -0.375]]
        let samples = pcm.enumerated().map { index, values in
            PlaybackSample(instrumentIndex: 1, sampleIndex: index, pcm: values.map { $0 }, volume: 1,
                relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 4, loopType: 1)
        }
        var map = [Int](repeating: 0, count: 96)
        map[51] = 1 // XM note 52.
        return .init(title: "Public revoked-candidate PCM lease", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: [
                .init(index: 0, cells: [.init(note: note, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)]),
                .init(index: 1, cells: [.init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)])])],
            instrumentsByIndex: [1: .init(index: 1, samples: samples, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: true)
    }

    private func firstBirth(_ batch: P.Batch) throws -> MixerSampleBuffer {
        let index = try XCTUnwrap(batch.adapterPlan.events.first {
            if case .noteTrigger = $0.action { return true }; return false
        }?.activeEventIndex)
        return try XCTUnwrap(batch.adapterPlan.plan).pattern.events[index].sample
    }

    func testRevokedCandidatesReuseOnePayloadForPreviouslyUnplayedCatalogSample() throws {
        let old = song(note: 49), cache = CSoftwareMixerSharedSamplePayloadCache()
        let original = try P(song: old, initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            sampleRate: 48_000, sourceGeneration: 3, transportEpoch: 9)
        let initialStart = original.exportResumeState() // The captured per-state cache is empty.
        XCTAssertEqual(original.resources.cachedSampleBuffers, 0)
        let active = try original.next(minimumHorizonFrames: Int.max, maximumRows: 4)
        let boundary = try XCTUnwrap(active.naturalBoundaries.first)
        let oldBirth = try XCTUnwrap(CSoftwareMixerPreparedLoopBirthStorage(cache: cache, sample: firstBirth(active)))
        let originalPayload = UInt(bitPattern: oldBirth.birth.payload)
        var payloads = Set([originalPayload]), candidatePayload: UInt?
        for generation in UInt64(4)..<132 { // 128 prepared candidates, all revoked before native admission.
            let fresh = song(note: 52)
            let oldAddress = old.instrumentsByIndex[1]!.samples[1].pcm.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
            let nextAddress = fresh.instrumentsByIndex[1]!.samples[1].pcm.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
            XCTAssertNotEqual(oldAddress, nextAddress)
            let proof = try P.prevalidateRefresh(song: fresh, resuming: initialStart, sourceGeneration: generation)
            let replay = try P(song: old, resuming: initialStart, sourceGeneration: 3)
            _ = try replay.next(minimumHorizonFrames: 1, maximumRows: boundary.rowCount, untilFrame: boundary.frame,
                nextRowOverride: fresh.pattern(for: 0)!.rows[0])
            let prefix = replay.exportResumeState()
            XCTAssertEqual(prefix.sequence, active.sequence)
            XCTAssertEqual(prefix.startFrame, boundary.frame)
            let candidate = try P(resuming: prefix, validatedRefresh: proof)
            let batch = try candidate.next(minimumHorizonFrames: 1, maximumRows: 1)
            let birth = try XCTUnwrap(CSoftwareMixerPreparedLoopBirthStorage(cache: cache, sample: firstBirth(batch)))
            let payload = UInt(bitPattern: birth.birth.payload)
            XCTAssertNotEqual(payload, originalPayload)
            if let candidatePayload { XCTAssertEqual(payload, candidatePayload) } else { candidatePayload = payload }
            payloads.insert(payload)
            XCTAssertEqual(payloads.count, 2) // One C payload per referenced canonical sample, no revision growth.
            XCTAssertEqual(batch.sequence, active.sequence + 1)
            XCTAssertTrue(batch.sourceIdentities.values.contains { $0.sourceGeneration == generation })
            // No publish: candidate plans/envelopes die here; only the generation cache keeps PCM alive.
        }
        XCTAssertEqual(payloads.count, 2)
    }
}
