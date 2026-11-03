import Foundation
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif
import XCTest

/// Release-row phases, periods and Q16 values were independently observed in pinned FT2.
final class KeyOffVibratoTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer
    private let rates = [44_100.0, 48_000]
    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, _ volume: UInt8 = 0,
                   _ effect: UInt8 = 0, _ parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private var original: [PlaybackCell] { [c(49, 1, 0xA8), c(97, 0, 0xB8)] }

    func testReleasedAudibleSourceRunsFiveInvocationsAndReceivesExactNativePitch() throws {
        for linear in [true, false] { for rate in rates {
            let input = song(original, linear), runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), tick = Int(rate / 50), frame = 8 * tick
            let diagnostic = try XCTUnwrap(plan.diagnostics.vibratoEffects.first { $0.syntheticRow == 1 })
            XCTAssertEqual(diagnostic.stepUpdates.map(\.syntheticTick), [1, 2, 3, 4, 5])
            XCTAssertEqual(diagnostic.stepUpdates.compactMap(\.vibrato).map(\.phaseBefore), [0, 32, 64, 96, 128])
            XCTAssertEqual(diagnostic.stepUpdates.compactMap(\.vibrato).map(\.phaseAfter), [32, 64, 96, 128, 160])
            XCTAssertEqual(diagnostic.vibratoSpeed, 8)
            XCTAssertEqual(diagnostic.vibratoDepth, 8)
            XCTAssertEqual(diagnostic.activeEventIndex, 0)
            XCTAssertEqual(diagnostic.stepUpdates.first { $0.syntheticTick == 2 }?.audibleNativePeriod(linear: linear), linear ? 4653 : 7028)
            XCTAssertEqual(plan.semanticPitch(row: 1, tick: 2, channel: 0)?.associatedGeneration, 0)
            XCTAssertEqual(plan.semanticPitch(row: 1, tick: 2, channel: 0)?.output, .known(linear ? 4653 : 7028))
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.pattern.events[0].scheduledStartFrame, 0)
            XCTAssertEqual(plan.diagnostics.keyOffEvents.filter(\.applied).map(\.releaseFrame), [6 * tick])
            let events = runtime.eventStorage.ordering.map { runtime.events[$0.eventIndex] }
            let request = try XCTUnwrap(events.first { $0.scheduledFrame == frame && $0.categories.contains("vibrato_update") })
            let expected = rate == 48_000 ? (linear ? 10963 : 11125) : (linear ? 11933 : 12109)
            if case let .stepUpdate(generation, step) = request.action {
                XCTAssertEqual(generation, 0)
                XCTAssertEqual(step * 65536, Double(expected))
            } else { XCTFail("Missing physical release-row pitch request") }
            let session = R(preparedPlan: plan).prepare(renderRequest(input, rate))
            let controlSong = song([original[0], c(97)], linear)
            let control = R().prepare(renderRequest(controlSong, rate))
            _ = session.render(frames: frame)
            _ = control.render(frames: frame)
#if DEBUG
            let before = try XCTUnwrap(session.sourceVoiceForTesting(0))
            XCTAssertEqual(before.samplePosition, control.sourceVoiceForTesting(0)?.samplePosition)
            XCTAssertEqual(before.sampleStep * 65536, rate == 48_000 ? 11418 : 12428)
#endif
            _ = session.render(frames: 1)
#if DEBUG
            let after = try XCTUnwrap(session.sourceVoiceForTesting(0))
            XCTAssertTrue(after.active)
            XCTAssertFalse(after.keyOn)
            XCTAssertEqual(after.sampleStep * 65536, Double(expected))
            XCTAssertEqual(after.samplePosition, before.samplePosition + after.sampleStep)
            XCTAssertEqual(after.envelopeSemanticState?.volumeTick, 7)
            XCTAssertEqual(after.envelopeSemanticState?.volumeValue, 0.971435546875)
            XCTAssertEqual(after.envelopeSemanticState?.fadeoutAccumulator, 32768)
            XCTAssertEqual(after.audibleOutputState?.target, [0.4857177734375, 0.4857177734375, 0.4857177734375])
            XCTAssertNil(session.sourceVoiceForTesting(1))
#endif
            try session.controlAdmission.requireSuccess()
        } }
    }

    func testB0MemoryNoColumnAndUnreleasedControlKeepTheirDistinctSemantics() throws {
        for linear in [true, false] { for rate in rates {
            let noColumn = A.adapt(song([original[0], c(97)], linear), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(noColumn.diagnostics.vibratoEffects.isEmpty)
            XCTAssertEqual(noColumn.xmChannelRows.last { $0.channelIndex == 0 }?.controls.vibratoPhase, 0)
            let cold = A.adapt(song([original[0], c(97, 0, 0xB0)], linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(cold.diagnostics.vibratoEffects.last?.vibratoDepth, 0)
            XCTAssertEqual(cold.diagnostics.vibratoEffects.last?.phaseAfter, 160)
            let active = A.adapt(song([original[0], c(0, 0, 0xB8)], linear), orderIndex: 0, sampleRate: rate)
            let released = A.adapt(song(original, linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(active.diagnostics.vibratoEffects.last?.stepUpdates, released.diagnostics.vibratoEffects.last?.stepUpdates)
            XCTAssertTrue(active.diagnostics.keyOffEvents.isEmpty)
            let seeded = [original[0], c(0, 0, 0xB5), c(97, 0, 0xB0), c()]
            let seededSong = song(seeded, linear), seededPlan = A.adapt(seededSong, orderIndex: 0, sampleRate: rate)
            let replay = try XCTUnwrap(seededPlan.diagnostics.vibratoEffects.last)
            XCTAssertEqual(replay.phaseBefore, 160)
            XCTAssertEqual(replay.phaseAfter, 64)
            XCTAssertEqual(replay.vibratoDepth, 5)
            XCTAssertEqual(replay.stepUpdates.compactMap(\.vibrato).map(\.phaseBefore), [160, 192, 224, 0, 32])
            var explicit = seeded; explicit[2] = c(97, 0, 0xB5)
            XCTAssertEqual(R().render(renderRequest(seededSong, rate)).block.interleavedPCM,
                           R().render(renderRequest(song(explicit, linear), rate)).block.interleavedPCM)
            XCTAssertEqual(seededPlan.pattern.events.count, 1)
        } }
    }

    func testSilentCompletedDisabledEnvelopeAndRapidFadeNeverCreateOrRestartASource() throws {
        for linear in [true, false] { for rate in rates {
            for kind in ["silent", "completed", "disabled", "rapid"] {
                let input = song(original + [c()], linear, kind: kind)
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.pattern.events.count, 1)
                XCTAssertEqual(plan.diagnostics.vibratoEffects.last?.phaseAfter, 160)
                XCTAssertEqual(plan.diagnostics.keyOffEvents.filter(\.applied).count, 1)
                let request = renderRequest(input, rate), session = R(preparedPlan: plan).prepare(request)
                let pcm = session.render(frames: request.boundedFrameCount).interleavedPCM
                if kind == "silent" { XCTAssertTrue(pcm.allSatisfy { $0 == 0 }) }
#if DEBUG
                XCTAssertNil(session.sourceVoiceForTesting(1))
                if kind == "completed" { XCTAssertFalse(try XCTUnwrap(session.sourceVoiceForTesting(0)).active) }
                if kind == "rapid" { XCTAssertEqual(session.sourceVoiceForTesting(0)?.envelopeSemanticState?.fadeoutAccumulator, 0) }
                if kind == "disabled" { XCTAssertEqual(session.sourceVoiceForTesting(0)?.audibleOutputState?.target.first, 0) }
#endif
                try session.controlAdmission.requireSuccess()
            }
            let cold = A.adapt(song([c(), c(97, 0, 0xB8)], linear), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(cold.pattern.events.isEmpty)
            XCTAssertEqual(cold.xmChannelRows.last { $0.channelIndex == 0 }?.controls.vibratoPhase, 0)
        } }
    }

    func testReleaseAdmitsOnlyColumnVibratoAndKeepsEffectColumnBoundaries() throws {
        for linear in [true, false] { for rate in rates {
            for effect: UInt8 in [3, 4, 5, 6, 7] {
                let input = song([original[0], c(97, 0, 0xB8, effect, effect == 4 ? 0xF1 : 1)], linear)
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                let diagnostic = try XCTUnwrap(plan.diagnostics.vibratoEffects.last)
                XCTAssertEqual(diagnostic.stepUpdates.map(\.syntheticTick), [1, 2, 3, 4, 5])
                XCTAssertEqual(diagnostic.vibratoSpeed, 8)
                XCTAssertEqual(diagnostic.vibratoDepth, 8)
                XCTAssertEqual(diagnostic.phaseAfter, 160)
                XCTAssertEqual(diagnostic.effectType, effect)
                XCTAssertTrue(plan.diagnostics.tonePortamentoEffects.isEmpty)
                XCTAssertEqual(plan.pattern.events.count, 1)
            }
            for volume: UInt8 in [0, 0xA4, 0xF1] {
                let plan = A.adapt(song([original[0], c(97, 0, volume)], linear), orderIndex: 0, sampleRate: rate)
                XCTAssertTrue(plan.diagnostics.vibratoEffects.isEmpty)
                XCTAssertEqual(plan.xmChannelRows.last { $0.channelIndex == 0 }?.controls.vibratoPhase, 0)
            }
            let singleTick = A.adapt(song(original, linear, speed: 1), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(singleTick.diagnostics.vibratoEffects.flatMap(\.stepUpdates).isEmpty)
            XCTAssertEqual(singleTick.xmChannelRows.last { $0.channelIndex == 0 }?.controls.vibratoDepth, 0)
        } }
    }

    func testReleasedRampTremoloConsumesEachBxInvocation() {
        // Pinned FT2 consumes the current Bx phase before each ramp-tremolo call.
        // This exposes the existing projection's assumption that note97 skips Bx.
        for linear in [true, false] { for rate in rates {
            let input = song([c(49, 1, 0xA8, 14, 0x71), c(97, 0, 0xB8, 7, 0x48)], linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let ticks = plan.diagnostics.voiceStateUpdates.compactMap { diagnostic -> PlaybackSongSyntheticTremoloTick? in
                guard diagnostic.syntheticRow == 1, case let .tremolo(tick) = diagnostic.command else { return nil }
                return tick
            }
            XCTAssertEqual(ticks.map(\.vibratoPhase), [32, 64, 96, 128, 160])
            XCTAssertEqual(ticks.map(\.outputVolume), [32, 36, 40, 51, 47])
            XCTAssertEqual(plan.pattern.events.count, 1)
        } }
    }

    func testReleaseRampNeighborsKeepColumnAdmissionSeparateFromSourceLifetime() {
        for linear in [true, false] { for rate in rates {
            let first = c(49, 1, 0xA8, 14, 0x71)
            for kind in ["normal", "silent", "completed"] {
                let plan = A.adapt(song([first, c(97, 0, 0xB8, 7, 0x48)], linear, kind: kind), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(rampTicks(plan).map { $0.tick.vibratoPhase }, [32, 64, 96, 128, 160])
                XCTAssertEqual(plan.pattern.events.count, 1)
                XCTAssertEqual(plan.diagnostics.keyOffEvents.filter(\.applied).count, 1)
            }
            let noBx = A.adapt(song([first, c(97, 0, 0, 7, 0x48)], linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(rampTicks(noBx).map { $0.tick.vibratoPhase }, [0, 0, 0, 0, 0])
            XCTAssertEqual(rampTicks(noBx).map { $0.tick.outputVolume }, [32, 36, 40, 44, 48])
            let ordinary = A.adapt(song([first, c(0, 0, 0xB8, 7, 0x48)], linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(rampTicks(ordinary).map { $0.tick.vibratoPhase }, [32, 64, 96, 128, 160])
            XCTAssertEqual(rampTicks(ordinary).map { $0.tick.outputVolume }, [32, 36, 40, 51, 47])
            let one = A.adapt(song([first, c(97, 0, 0xB8, 7, 0x48)], linear, speed: 1), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(rampTicks(one).isEmpty)
            XCTAssertTrue(one.diagnostics.vibratoEffects.flatMap(\.stepUpdates).isEmpty)
        } }
    }

    func testHeldReleaseRampUsesElapsedInvocationsAcrossDeliveryBoundaries() {
        for linear in [true, false] { for rate in rates {
            let input = song([c(49, 1, 0xA8, 14, 0x71), c(97, 0, 0xB8, 7, 0x48)], linear,
                             secondary: [c(), c(0, 0, 0, 14, 0xE1)])
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate), tick = Int(rate / 50)
            let invocations = rampTicks(plan)
            XCTAssertEqual(invocations.map { $0.tick.vibratoPhase }, [32, 64, 96, 128, 160, 192, 224, 0, 32, 64, 96])
            XCTAssertEqual(invocations.map { $0.tick.outputVolume }, [32, 36, 40, 51, 47, 43, 39, 60, 32, 28, 24])
            XCTAssertEqual(invocations.map(\.frame), (7...17).map { $0 * tick })
            XCTAssertEqual(plan.pattern.events.count, 1)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), frames: 18 * tick)
            let renderer = R(preparedPlan: plan), whole = renderer.render(request).block.interleavedPCM, frame = 7 * tick
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole)
            XCTAssertEqual(renderer.render(request, splitFrameCounts: [frame, 1, request.boundedFrameCount - frame - 1]).block.interleavedPCM, whole)
            for chunk in [511, 512, 513] {
                var streamed = [Float]()
                _ = renderer.renderStreaming(request, chunkFrameCount: chunk) { _, _, block in streamed += block.interleavedPCM }
                XCTAssertEqual(streamed, whole)
            }
        } }
    }

    private func rampTicks(_ plan: PlaybackSongSyntheticPlan) -> [(frame: Int, tick: PlaybackSongSyntheticTremoloTick)] {
        plan.diagnostics.voiceStateUpdates.compactMap {
            guard $0.syntheticRow == 1, case let .tremolo(tick) = $0.command else { return nil }
            return ($0.scheduledFrame, tick)
        }
    }

    func testHeldReleasedOutputAndAutomaticOnlyTicksKeepTheRetainedGeneration() throws {
        for linear in [true, false] { for rate in rates { for automatic in [false, true] {
            // A4 makes the fifth release-row invocation nonneutral, exposing a wrong held basis.
            let input = song([c(49, 1, 0xA4), c(97, 0, 0xB8), c()], linear, automatic: automatic)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), frame = 12 * Int(rate / 50)
            XCTAssertEqual(plan.diagnostics.vibratoEffects.last?.stepUpdates.last?.audibleNativePeriod(linear: linear), linear ? 4671 : 7100)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.semanticPitch(row: 2, tick: 0, channel: 0)?.associatedGeneration, 0)
            if automatic {
                let clock = try XCTUnwrap(plan.instrumentAutovibrato(row: 2, tick: 0, channel: 0))
                let bounds = PlaybackSongInstrumentAutovibratoComposition.Bounds(linear: linear, baseSampleRate: 8363, outputSampleRate: rate)
                let expected = try XCTUnwrap(bounds.step(period: linear ? 4671 : 7100,
                    delta: PlaybackSongInstrumentAutovibratoComposition.delta(clock: clock)))
                let session = R(preparedPlan: plan).prepare(renderRequest(input, rate))
                _ = session.render(frames: frame + 1)
#if DEBUG
                XCTAssertEqual(session.sourceVoiceForTesting(0)?.sampleStep, expected)
                XCTAssertFalse(try XCTUnwrap(session.sourceVoiceForTesting(0)).keyOn)
#endif
                try session.controlAdmission.requireSuccess()
            } else {
                XCTAssertTrue(runtime.events.filter { $0.scheduledFrame == frame }.allSatisfy { !$0.categories.contains("vibrato_update") })
            }
            let request = renderRequest(input, rate), renderer = R(preparedPlan: plan)
            let whole = renderer.render(request).block.interleavedPCM
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole)
            XCTAssertEqual(renderer.render(request, splitFrameCounts: [frame, 1, request.boundedFrameCount - frame - 1]).block.interleavedPCM, whole)
            for chunk in [511, 512, 513] {
                var streamed = [Float]()
                _ = renderer.renderStreaming(request, chunkFrameCount: chunk) { _, _, block in streamed += block.interleavedPCM }
                XCTAssertEqual(streamed, whole)
            }
        } } }
    }

    private func renderRequest(_ input: PlaybackSong, _ rate: Double) -> PlaybackSongOfflineRenderRequest {
        .init(song: input, config: .init(sampleRate: rate), frames: input.patternsByIndex[0]!.rows.count * 6 * Int(rate / 50))
    }
    private func song(_ cells: [PlaybackCell], _ linear: Bool, kind: String = "normal", automatic: Bool = false, speed: Int = 6,
                      secondary: [PlaybackCell]? = nil) -> PlaybackSong {
        let count = kind == "completed" ? 16 : 256
        let pcm = (0..<count).map { Float((8192 * sin(Double($0) * .pi / 8)).rounded()) / 32768 }
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: pcm, volume: kind == "silent" ? 0 : 0.5,
            panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0,
            loopLength: kind == "completed" ? 0 : count, loopType: kind == "completed" ? 0 : 1)
        let envelope = kind == "disabled" ? PlaybackVolumeEnvelope.disabled : PlaybackVolumeEnvelope(enabled: true,
            points: [.init(tick: 0, value: 64), .init(tick: 5, value: 64), .init(tick: 40, value: 32)],
            sustainPointIndex: 1, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 3, fadeout: kind == "rapid" ? 32768 : 0)
        let rows = cells.enumerated().map { PlaybackRow(index: $0.offset, cells: [$0.element, secondary?[$0.offset] ?? c()]) }
        return .init(title: "Public release-row Bx", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows)], instrumentsByIndex: [1: .init(index: 1, samples: [sample],
                volumeEnvelope: envelope, autoVibrato: automatic ? .init(waveformType: 0, sweep: 0, depth: 8, rate: 16) : .disabled,
                noteSampleMap: Array(repeating: 0, count: 96))], restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
