import Foundation
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif
import XCTest

/// A test-only fixed native delta probes delivery seams, not an enabled oscillator or planner.
final class InstrumentAutovibratoDeliveryPreflightTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter

    func testBlankTickCanUseExistingGenerationAddressedStepProtocol() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song([cell(note: 49, instrument: 1), cell()], linear: linear)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan)
            let coordinate = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: 1, tick: 3, channel: 0))
            XCTAssertFalse(runtime.events.contains { $0.scheduledFrame == coordinate.absoluteFrame })
            XCTAssertTrue(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: coordinate.absoluteFrame, plan: plan))
            let semantic = try XCTUnwrap(plan.semanticPitch(row: 1, tick: 3, channel: 0))
            guard case let .known(native) = semantic.output else { return XCTFail("Missing native output") }
            let step = try converted(native + 16, linear, rate)
            let birth = plan.pattern.events[0]
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let voice = mixer.addVoice(sample: birth.sample, playbackStep: birth.playbackStep, loop: birth.loop)
            // The causal request carries a real generation; it does not create PCM.
            let request = RuntimeCMixerAdapterEvent(id: runtime.events.count, source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 1),
                channelIndex: 0, syntheticTick: 3, scheduledFrame: coordinate.absoluteFrame,
                action: .stepUpdate(activeEventIndex: 0, playbackStep: step), categories: ["step_update"])
            guard case let .stepUpdate(generation, target) = request.action else { return XCTFail("Missing request") }
            XCTAssertEqual(generation, semantic.associatedGeneration)
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: request.scheduledFrame, playbackStep: target).wasAccepted)
            _ = mixer.render(frames: coordinate.absoluteFrame)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.sampleStep, birth.playbackStep)
            _ = mixer.render(frames: 1)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.sampleStep, step)
        } }
    }

    func testPositiveBirthFoldsBeforeMixingAndZeroBirthHoldsExactlyOnce() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song([cell(note: 49, instrument: 1)], linear: linear), sampleRate: rate)
            let birth = try XCTUnwrap(runtime.events.first { if case .noteTrigger = $0.action { return true }; return false })
            guard case let .noteTrigger(generation, event, mapping) = birth.action else { return XCTFail("Missing birth") }
            for zero in [false, true] {
                let step = zero ? 0 : try converted((linear ? 4608 : 6848) + 16, linear, rate)
                let trigger = replacing(birth, action: .noteTrigger(eventIndex: generation,
                    event: event.withPlaybackStep(step > 0 ? step : event.playbackStep), mapping: mapping))
                let update = RuntimeCMixerAdapterEvent(id: birth.id + 1, source: birth.source, channelIndex: 0,
                    syntheticTick: 0, scheduledFrame: 0, action: .stepUpdate(activeEventIndex: generation, playbackStep: step),
                    categories: zero ? ["step_update", "initial_pitch_hold"] : ["step_update"])
                let storage = RuntimeCMixerAdapterEventStorage(events: zero ? [trigger, update] : [trigger])
                XCTAssertEqual(storage.ordering.map(\.priority), zero ? [2, 3] : [2])
                XCTAssertEqual(storage.events.filter { $0.categories.contains("initial_pitch_hold") }.count, zero ? 1 : 0)
                let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
                var voices = [Int: Int]()
                for ordered in storage.ordering {
                    switch storage.events[ordered.eventIndex].action {
                    case let .noteTrigger(index, value, _):
                        voices[index] = mixer.addVoice(sample: value.sample, playbackStep: value.playbackStep, loop: value.loop)
                    case let .stepUpdate(index, target):
                        let voice = try XCTUnwrap(voices[index])
                        XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: 0, playbackStep: target).wasAccepted)
                    default: XCTFail("Unexpected action")
                    }
                }
                let voice = try XCTUnwrap(voices[generation])
                _ = mixer.render(frames: 1)
                XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, step)
                XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.sampleStep, step)
                if zero {
                    XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: 1, playbackStep: event.playbackStep).wasAccepted)
                    _ = mixer.render(frames: 1)
                    XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, event.playbackStep)
                }
                // An ordinary priority-zero update runs before a future birth and cannot initialize it.
                XCTAssertEqual(RuntimeCMixerAdapterEventStorage(events: [trigger, replacing(update,
                    action: .stepUpdate(activeEventIndex: generation, playbackStep: 0.25), categories: ["step_update"])]).ordering.map(\.priority), [0, 2])
            }
        } }
    }

    func testFixedDeltaPreservesBothOrderedBxThenEffectNativeIntermediates() throws {
        for effect: UInt8 in [4, 6] { for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song([cell(note: 49, instrument: 1, volume: 0xA4),
                cell(effect, effect == 4 ? 0x48 : 0, volume: 0xB8), cell()], linear: linear), sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), frame = 8 * Int(rate / 50)
            let raw = runtime.events.filter { $0.scheduledFrame == frame }
            let children = try XCTUnwrap(plan.diagnostics.vibratoEffects.first).stepUpdates.filter { $0.scheduledFrame == frame }
            XCTAssertEqual(raw.count, 2); XCTAssertEqual(children.count, 2)
            let steps = try children.map { child in
                if linear { return try converted(child.linearPeriodAfter + 16, linear, rate) }
                return try converted(try XCTUnwrap(child.amigaPeriodAfter) + 16, linear, rate)
            }
            XCTAssertNotEqual(steps[0], steps[1])
            let composed = zip(raw, steps).map { replacing($0.0, action: .stepUpdate(activeEventIndex: 0, playbackStep: $0.1)) }
            XCTAssertEqual(composed.map(\.id), raw.map(\.id))
            XCTAssertEqual(composed.map(\.categories), raw.map(\.categories))
            let storage = RuntimeCMixerAdapterEventStorage(events: composed)
            XCTAssertEqual(storage.ordering.map(\.eventID), raw.map(\.id))
            let event = plan.pattern.events[0], mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let voice = mixer.addVoice(sample: event.sample, playbackStep: event.playbackStep, loop: event.loop)
            for step in steps { XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: frame, playbackStep: step).wasAccepted) }
            _ = mixer.render(frames: frame + 1)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.sampleStep, steps.last)
            XCTAssertEqual(plan.diagnostics.vibratoEffects.first?.stepUpdates.filter { $0.scheduledFrame == frame }, children)
        } } }
    }

    private func converted(_ native: Double, _ linear: Bool, _ rate: Double) throws -> Double {
        try XCTUnwrap(linear ? A.playbackStep(linearPeriod: native, baseSampleRate: 8363, outputSampleRate: rate)
            : A.playbackStep(amigaPeriod: native, baseSampleRate: 8363, outputSampleRate: rate))
    }
    private func replacing(_ event: RuntimeCMixerAdapterEvent, action: RuntimeCMixerAdapterEventAction, categories: [String]? = nil) -> RuntimeCMixerAdapterEvent {
        .init(id: event.id, source: event.source, channelIndex: event.channelIndex, syntheticTick: event.syntheticTick,
            scheduledFrame: event.scheduledFrame, action: action, categories: categories ?? event.categories,
            effectType: event.effectType, effectParam: event.effectParam, volumeColumn: event.volumeColumn)
    }
    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ cells: [PlaybackCell], linear: Bool) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.125, -0.375, 0.25, -0.0625, 0.5, -0.25, 0.0625, -0.125],
            volume: 0.5, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopLength: 8, loopType: 1)
        return .init(title: "Public automatic-pitch delivery preflight", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
