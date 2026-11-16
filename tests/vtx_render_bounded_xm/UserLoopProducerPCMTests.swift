import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class UserLoopProducerPCMTests: XCTestCase {
    func testAuthoredBxxWindowsMatchFiniteExpandedPCMThroughTwelvePasses() throws {
        for rate in [44_100.0, 48_000] { for linear in [true, false] { for origin in [0, 1] { for cap in [1, 3, 5] {
            let song = try AuthoredBxxProofFixture.make(linear: linear)
            let start = PlaybackPosition(orderIndex: origin, patternIndex: origin, rowIndex: 0)
            let oracle = RuntimeCMixerAdapterEventPlan.make(song: try AuthoredBxxProofFixture.make(linear: linear, passes: 12),
                sampleRate: rate, initialPosition: start)
            let end = try XCTUnwrap(oracle.plannedSongEndFrame)
            let producer = try PlaybackSongUserLoopProducer(song: song, initialPosition: start,
                sampleRate: rate, sourceGeneration: 7, transportEpoch: 9, mode: .finiteSong,
                terminalTailFrames: Int(rate * 3))
            var batches = [(RuntimeCMixerAdapterEventPlan, Int)]()
            let totalRows = (origin == 0 ? 1 : 0) + 48
            var rows = 0
            while rows < totalRows {
                let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: min(cap, totalRows - rows))
                XCTAssertNil(batch.terminalStopReason)
                XCTAssertEqual(batch.runtimeEndFrame, batch.endFrame)
                batches.append((batch.adapterPlan, batch.endFrame))
                rows += try XCTUnwrap(batch.adapterPlan.plan).diagnostics.rowTiming.count
            }
            let expected = try Consumer(rate: rate).render([(oracle, end)], partitions: [1, 127, 31, 509])
            let actual = try Consumer(rate: rate).render(batches, partitions: [1, 127, 31, 509])
            XCTAssertTrue(actual.prefix(Int(rate / 10)).contains { $0 != 0 })
            XCTAssertTrue(actual.suffix(Int(rate / 5)).allSatisfy { $0 == 0 })
            XCTAssertEqual(actual, expected, "Authored Bxx PCM, rate=\(rate), linear=\(linear), origin=\(origin), cap=\(cap)")
        } } } }
    }

    func testFiniteZeroTailRetainsFullPlanEndFrameWriter() throws {
        let rate = 48_000.0, input = FiniteSongProducerProofFixture.make(linear: true)
        let oracle = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate,
            initialPosition: FiniteSongProducerProofFixture.origin)
        let end = try XCTUnwrap(oracle.plannedSongEndFrame)
        let endEvents = oracle.events.filter { $0.scheduledFrame == end }
        XCTAssertFalse(endEvents.isEmpty, "This fixture must exercise a real end-frame writer")
        let producer = try PlaybackSongUserLoopProducer(song: input,
            initialPosition: FiniteSongProducerProofFixture.origin, sampleRate: rate,
            sourceGeneration: 7, transportEpoch: 9, mode: .finiteSong, terminalTailFrames: 0)
        let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: 128)
        XCTAssertEqual(batch.terminalStopReason, .songEnd)
        XCTAssertEqual(batch.endFrame, end)
        XCTAssertEqual(batch.runtimeEndFrame, end)
        XCTAssertEqual(batch.adapterPlan.events.filter { $0.scheduledFrame == end }.map(\.action),
            endEvents.map(\.action))
        XCTAssertEqual(writers(batch.adapterPlan), writers(oracle))
    }

    func testFiniteSongCrossOrderPCMMatchesFullColdPlan() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for cap in [1, 3] {
            let input = FiniteSongProducerProofFixture.make(linear: linear)
            let oracle = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate,
                initialPosition: FiniteSongProducerProofFixture.origin)
            let end = try XCTUnwrap(oracle.plannedSongEndFrame)
            let tailFrames = Int(rate * 3) // App's default runtime song-end tail.
            let stopFrame = end + tailFrames
            XCTAssertTrue(oracle.events.contains { $0.scheduledFrame == end },
                "Fixture must exercise a terminal-frame writer")
            let producer = try PlaybackSongUserLoopProducer(song: input,
                initialPosition: FiniteSongProducerProofFixture.origin,
                sampleRate: rate, sourceGeneration: 7, transportEpoch: 9, mode: .finiteSong,
                terminalTailFrames: tailFrames)
            var batches = [PlaybackSongUserLoopProducer.Batch]()
            for _ in 0..<16 {
                let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: cap)
                batches.append(batch)
                if batch.terminalStopReason != nil { break }
            }
            XCTAssertEqual(batches.last?.terminalStopReason, .songEnd)
            XCTAssertEqual(batches.last?.endFrame, end)
            XCTAssertEqual(batches.last?.runtimeEndFrame, stopFrame)
            XCTAssertTrue(batches.dropLast().allSatisfy { $0.runtimeEndFrame == $0.endFrame })
            XCTAssertTrue(batches.last?.adapterPlan.events.contains { $0.scheduledFrame == end } == true)
            XCTAssertEqual(batches.flatMap { writers($0.adapterPlan) }, writers(oracle))
            let expected = try Consumer(rate: rate).render([(oracle, stopFrame)], partitions: [1, 127, 31, 509])
            let actual = try Consumer(rate: rate).render(batches.map { ($0.adapterPlan, $0.runtimeEndFrame) },
                partitions: [1, 127, 31, 509])
            XCTAssertTrue(expected.contains { $0 != 0 }, "Fixture must actually sound")
            XCTAssertEqual(actual, expected, "finite cold PCM, rate=\(rate), linear=\(linear), cap=\(cap)")
        } } }
    }

    func testExecutedContinuationFixesFrozenFrame18241CounterexampleAgainstExpandedPCM() throws {
        let visits = [2, 3] + (0..<3).flatMap { _ in [0, 1, 2, 3] }
        for rate in [44_100.0, 48_000] { for linear in [true, false] { for cap in [1, 3, 7] {
            let input = song(visits: [0, 1, 2, 3], linear: linear)
            let oracle = RuntimeCMixerAdapterEventPlan.make(song: song(visits: visits, linear: linear), sampleRate: rate)
            let producer = try PlaybackSongUserLoopProducer(song: input,
                initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2),
                sampleRate: rate, sourceGeneration: 7, transportEpoch: 9)
            var batches = [PlaybackSongUserLoopProducer.Batch](), offset = 0
            while offset < visits.count {
                let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: min(cap, visits.count - offset))
                let plan = try XCTUnwrap(batch.adapterPlan.plan)
                XCTAssertFalse(plan.$xmChannelRows.isFullCapture)
                XCTAssertTrue(batch.adapterPlan.events.allSatisfy { (batch.startFrame..<batch.endFrame).contains($0.scheduledFrame) })
                XCTAssertEqual(Set(batch.adapterPlan.events.map(\.id)).count, batch.adapterPlan.events.count)
                for event in batch.adapterPlan.events {
                    if case let .noteTrigger(index, _, _) = event.action {
                        XCTAssertGreaterThanOrEqual(index, batch.importedSourceCount)
                        let birth = try XCTUnwrap(batch.sourceIdentities[index])
                        XCTAssertEqual(birth.birthSequence, batch.sequence)
                        XCTAssertEqual(birth.birthEventIndex, index)
                    }
                }
                for row in plan.diagnostics.rowTiming.indices { for tick in 0..<3 {
                    let actual = try XCTUnwrap(plan.semanticPitch(row: row, tick: tick, channel: 0))
                    let expected = try XCTUnwrap(oracle.plan?.semanticPitch(row: offset + row, tick: tick, channel: 0))
                    XCTAssertEqual(actual.base, expected.base)
                    XCTAssertEqual(actual.output, expected.output)
                    XCTAssertEqual(actual.incoming, expected.incoming)
                    XCTAssertEqual(actual.semanticInstrument, expected.semanticInstrument)
                    XCTAssertEqual(actual.semanticSample, expected.semanticSample)
                } }
                batches.append(batch); offset += plan.diagnostics.rowTiming.count
            }
            let actualWriters = batches.flatMap { writers($0.adapterPlan) }
            XCTAssertEqual(actualWriters, writers(oracle))
            let frames = try XCTUnwrap(oracle.plannedSongEndFrame)
            let expected = try Consumer(rate: rate).render([(oracle, frames)], partitions: [1, 127, 31, 509])
            let actual = try Consumer(rate: rate).render(batches.map { ($0.adapterPlan, $0.endFrame) }, partitions: [1, 127, 31, 509])
            XCTAssertEqual(actual.count, expected.count)
            if let mismatch = zip(actual, expected).enumerated().first(where: { $0.element.0 != $0.element.1 }) {
                XCTFail("PCM mismatch frame \(mismatch.offset), rate=\(rate), linear=\(linear), cap=\(cap)")
            }
        } } }
        for kind in LoopTraversalProofFixture.Kind.allCases {
            for rate in [44_100.0, 48_000] { for linear in [true, false] { for cap in [1, 3, 7] {
                try assertTraversalPCM(LoopTraversalProofFixture.make(kind, linear: linear), rate: rate, linear: linear, cap: cap)
            } } }
        }
    }

    private func assertTraversalPCM(_ fixture: LoopTraversalProofFixture, rate: Double,
                                    linear: Bool, cap: Int) throws {
        let oracle = RuntimeCMixerAdapterEventPlan.make(song: fixture.oracle, sampleRate: rate)
        let expectedPlan = try XCTUnwrap(oracle.plan)
        let end = expectedPlan.diagnostics.rowTiming[fixture.targetRows].rowStartFrame
        let producer = try PlaybackSongUserLoopProducer(song: fixture.input,
            initialPosition: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2),
            sampleRate: rate, sourceGeneration: 7, transportEpoch: 9)
        var batches = [PlaybackSongUserLoopProducer.Batch](), rows = [Int](), offset = 0
        var births = [RuntimeLoopNativeSourceIdentity: Int]()
        while offset < fixture.targetRows {
            let batch = try producer.next(minimumHorizonFrames: Int.max,
                maximumRows: min(cap, fixture.targetRows - offset))
            let plan = try XCTUnwrap(batch.adapterPlan.plan)
            XCTAssertFalse(plan.$xmChannelRows.isFullCapture)
            XCTAssertEqual(Set(batch.adapterPlan.events.map(\.id)).count, batch.adapterPlan.events.count)
            XCTAssertTrue(batch.adapterPlan.events.allSatisfy { (batch.startFrame..<batch.endFrame).contains($0.scheduledFrame) })
            for event in batch.adapterPlan.events {
                guard case let .noteTrigger(index, _, _) = event.action else { continue }
                let identity = try XCTUnwrap(batch.sourceIdentities[index])
                XCTAssertGreaterThanOrEqual(index, batch.importedSourceCount)
                XCTAssertEqual(identity.sourceGeneration, 7); XCTAssertEqual(identity.transportEpoch, 9)
                XCTAssertEqual(identity.birthSequence, batch.sequence); XCTAssertEqual(identity.birthEventIndex, index)
                XCTAssertNil(births[identity], "No boundary pseudo-birth")
                let expected = try XCTUnwrap(oracle.events.first {
                    if case .noteTrigger = $0.action {
                        return $0.scheduledFrame == event.scheduledFrame && $0.channelIndex == event.channelIndex
                    }
                    return false
                })
                births[identity] = try XCTUnwrap(expected.activeEventIndex)
            }
            for local in plan.diagnostics.rowTiming.indices {
                let timing = plan.diagnostics.rowTiming[local]
                let expectedTiming = expectedPlan.diagnostics.rowTiming[offset + local]
                rows.append(timing.source.rowIndex)
                XCTAssertEqual(timing.source.rowIndex, fixture.visits[offset + local])
                XCTAssertEqual(timing.rowStartExactFrame, expectedTiming.rowStartExactFrame)
                XCTAssertEqual(timing.rowDurationFrames, expectedTiming.rowDurationFrames)
                XCTAssertEqual(timing.actualTickCount, expectedTiming.actualTickCount)
                XCTAssertEqual(timing.effectiveSpeed, expectedTiming.effectiveSpeed)
                XCTAssertEqual(timing.effectiveBPM, expectedTiming.effectiveBPM)
                for tick in 0..<timing.actualTickCount { for channel in 0..<6 {
                    let actual = try XCTUnwrap(plan.semanticPitch(row: local, tick: tick, channel: channel))
                    let expected = try XCTUnwrap(expectedPlan.semanticPitch(row: offset + local, tick: tick, channel: channel))
                    XCTAssertEqual(actual.base, expected.base); XCTAssertEqual(actual.output, expected.output)
                    XCTAssertEqual(actual.incoming, expected.incoming)
                    XCTAssertEqual(actual.semanticInstrument, expected.semanticInstrument)
                    XCTAssertEqual(actual.semanticSample, expected.semanticSample)
                    XCTAssertEqual(actual.carriedInstrument, expected.carriedInstrument)
                    let identity = try actual.associatedGeneration.map { try XCTUnwrap(batch.sourceIdentities[$0]) }
                    let source = try identity.map { try XCTUnwrap(births[$0]) }
                    XCTAssertEqual(source, expected.associatedGeneration)
                    let clock = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: local, tick: tick, channel: channel))
                    let reference = try XCTUnwrap(expectedPlan.canonicalTickClock.coordinate(syntheticRow: offset + local, tick: tick, channel: channel))
                    XCTAssertEqual(clock.absoluteFrame, reference.absoluteFrame)
                    XCTAssertEqual(clock.canonicalTickOrdinal, reference.canonicalTickOrdinal)
                    XCTAssertEqual(plan.instrumentAutovibrato(row: local, tick: tick, channel: channel),
                        expectedPlan.instrumentAutovibrato(row: offset + local, tick: tick, channel: channel))
                } }
            }
            batches.append(batch); offset += plan.diagnostics.rowTiming.count
        }
        XCTAssertEqual(rows, Array(fixture.visits.prefix(fixture.targetRows)))
        XCTAssertEqual(rows.filter { $0 == 0 }.count, 3, "Three actual warm entries execute")
        XCTAssertEqual(batches.flatMap { writers($0.adapterPlan) }, writers(oracle).filter { $0.frame < end })
        let expected = try Consumer(rate: rate).render([(oracle, end)], partitions: [1, 127, 31, 509])
        let actual = try Consumer(rate: rate).render(batches.map { ($0.adapterPlan, $0.endFrame) }, partitions: [1, 127, 31, 509])
        XCTAssertEqual(actual, expected, "Integrated accepted-row PCM, cap=\(cap), rate=\(rate), linear=\(linear)")
    }

    private struct Writer: Equatable {
        let frame: Int, channel: Int, birthFrame: Int
        let isBirth: Bool
        let step: Double
    }
    private func writers(_ plan: RuntimeCMixerAdapterEventPlan) -> [Writer] {
        guard let semantic = plan.plan else { return [] }
        return plan.eventStorage.ordering.compactMap { entry in
            let event = plan.events[entry.eventIndex]
            guard let index = event.activeEventIndex, semantic.pattern.events.indices.contains(index) else { return nil }
            let birth = semantic.pattern.events[index].scheduledStartFrame ?? 0
            switch event.action {
            case let .noteTrigger(_, value, _):
                return .init(frame: event.scheduledFrame, channel: event.channelIndex,
                    birthFrame: birth, isBirth: true, step: value.playbackStep)
            case let .stepUpdate(_, step):
                return .init(frame: event.scheduledFrame, channel: event.channelIndex,
                    birthFrame: birth, isBirth: false, step: step)
            default: return nil
            }
        }
    }

    /// Applies already generated runtime commands through the existing C boundary.
    /// This test consumer performs no row/effect interpretation or voice reconstruction.
    private final class Consumer {
        let mixer: CSoftwareMixer
        var current = [Int: Int](), voices = [Int: Int]()
        var heldSteps = [Int: Double]()
        init(rate: Double) { mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1)) }
        func render(_ batches: [(RuntimeCMixerAdapterEventPlan, Int)], partitions: [Int]) throws -> [Float] {
            var pcm = [Float](), partition = 0
            for (batch, end) in batches {
                let plan = try XCTUnwrap(batch.plan)
                let events = batch.eventStorage.ordering.map { batch.events[$0.eventIndex] }
                var index = 0
                while Int(mixer.currentFrame) < end {
                    let frame = Int(mixer.currentFrame)
                    while index < events.count && events[index].scheduledFrame == frame {
                        try apply(events[index], plan: plan); index += 1
                    }
                    let next = min(end, index < events.count ? events[index].scheduledFrame : end)
                    let count = min(next - frame, partitions[partition % partitions.count])
                    XCTAssertGreaterThan(count, 0)
                    guard count > 0 else { return pcm }
                    pcm.append(contentsOf: mixer.render(frames: count).interleavedPCM)
                    partition += 1
                }
            }
            return pcm
        }
        private func apply(_ event: RuntimeCMixerAdapterEvent, plan: PlaybackSongSyntheticPlan) throws {
            let frame = Int(mixer.currentFrame), channel = event.channelIndex
            let source = event.activeEventIndex.flatMap { plan.pattern.events.indices.contains($0)
                ? plan.pattern.events[$0].scheduledStartFrame : nil }
            let voice = source.flatMap { current[channel] == $0 ? voices[$0] : nil }
            switch event.action {
            case let .noteTrigger(_, value, _):
                _ = mixer.retireSongVoices(channel: channel)
                let index = try XCTUnwrap(mixer.addVoice(sample: value.sample, gain: value.gain, pan: value.pan,
                    playbackStep: value.playbackStep, loop: value.loop, initialSourceFrame: value.initialSourceFrame,
                    volumeEnvelope: value.volumeEnvelope, panEnvelope: value.panEnvelope, keyOffFrame: value.keyOffFrame,
                    fadeoutFrameDecrement: value.fadeoutFrameDecrement, sourceOnsetElapsedFrames: 0))
                mixer.setChannelTag(channel, forVoiceAt: index)
                current[channel] = frame; voices[frame] = index; heldSteps[frame] = value.playbackStep
            case let .stepUpdate(_, step):
                if let voice, let source {
                    let before = heldSteps[source] ?? 0
                    if abs(step - before) > 0.0001 || (before == 0) != (step == 0) {
                        if mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: frame,
                            playbackStep: step).wasAccepted { heldSteps[source] = step }
                    }
                }
            case let .gainPanUpdate(_, gain, pan):
                if let voice { _ = mixer.scheduleVoiceGainPanUpdate(voiceIndex: voice, scheduledFrame: frame, gain: gain, pan: pan) }
            case let .envelopePositionUpdate(_, position):
                if let voice { _ = mixer.scheduleVoiceVolumeEnvelopePositionUpdate(voiceIndex: voice, scheduledFrame: frame, positionFrame: position) }
            case let .playbackStateChange(_, change):
                if let voice { _ = mixer.schedulePlaybackStateChange(change, voiceIndex: voice, scheduledFrame: frame) }
            case let .envelopeSemanticUpdate(_, state):
                if let voice { _ = mixer.setEnvelopeSemanticState(state, forVoiceAt: voice) }
            case let .audibleTargetUpdate(target):
                if let voice { _ = mixer.publishAudibleOutput(target, forVoiceAt: voice) }
            case let .sourceStop(_, retire):
                if let voice {
                    if retire { _ = mixer.retireSongVoices(channel: channel) } else { _ = mixer.stopVoice(at: voice) }
                    current[channel] = nil
                }
            case .channelSemanticUpdate, .noteCut: break
            }
        }
    }

    private func song(visits: [Int], linear: Bool) -> PlaybackSong {
        let cells: [PlaybackCell] = [
            .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 1, effectParam: 1),
            .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
            .init(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)
        ]
        let pattern = PlaybackPattern(index: 0, rows: visits.enumerated().map { .init(index: $0.offset, cells: [cells[$0.element]]) })
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: [0.25, -0.25, 0.125, -0.125], volume: 1, relativeNote: 0, finetune: 0,
            baseSampleRate: 8363, loopStart: 0, loopLength: 4, loopType: 1)
        return .init(title: "Public loop source-continuation regression", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: pattern], instrumentsByIndex: [1: .init(index: 1, samples: [sample])],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125),
            usesLinearFrequencyTable: linear)
    }
}
