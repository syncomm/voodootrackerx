import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class NewSourceOnsetTests: XCTestCase {
    private typealias Renderer = PlaybackSongOfflineRenderer

    func testConstantPCMHasZeroFirstFrameLinearInteriorAndExactEndpoint() throws {
        // Independent mathematical controls: no interpolation, envelopes or moving targets.
        for rate in [44_100.0, 48_000] { for profile in MixerMixProfile.allCases {
            for sign: Float in [-1, 1] { for gain: Float in [0.25, 1] { for pan: Float in [0, -0.5] {
                for managed in [false, true] {
                    let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
                    let mixer = CSoftwareMixer(config: config), plain = CSoftwareMixer(config: config)
                    let sample = MixerSampleBuffer(monoPCM: Array(repeating: sign, count: 4096))
                    let start = 17, duration = Int(rate * 0.005)
                    let voice = try XCTUnwrap(mixer.addScheduledVoice(sample: sample, scheduledStartFrame: start,
                        gain: gain, pan: pan, sourceOnsetElapsedFrames: 0))
                    _ = plain.addScheduledVoice(sample: sample, scheduledStartFrame: start, gain: gain, pan: pan)
                    XCTAssertTrue(mixer.render(frames: start).interleavedPCM.allSatisfy { $0 == 0 })
                    _ = plain.render(frames: start)
                    if managed {
                        XCTAssertTrue(mixer.publishAudibleOutput(target(gain, pan: pan), forVoiceAt: voice))
                    }
                    let before = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                    XCTAssertEqual(before.samplePosition, 0)
                    XCTAssertEqual(before.sourceOnsetDurationFrames, rate == 48_000 ? 240 : 220)
                    XCTAssertEqual(before.sourceOnsetElapsedFrames, 0)
                    let pcm = mixer.render(frames: duration + 65).interleavedPCM
                    let control = plain.render(frames: duration + 65).interleavedPCM
                    for k in [0, 1, duration / 4, duration / 2, duration - 1, duration, duration + 1] {
                        for channel in 0..<2 {
                            let expected = control[k * 2 + channel] * min(1, Float(k) / Float(duration))
                            XCTAssertEqual(pcm[k * 2 + channel], expected, accuracy: 1e-7,
                                "rate=\(rate), frame=\(k), managed=\(managed)")
                        }
                    }
                    XCTAssertEqual(Array(pcm[(duration * 2)...]), Array(control[(duration * 2)...]))
                    let after = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                    XCTAssertEqual(after.samplePosition, Double(duration + 65))
                    XCTAssertEqual(after.sourceOnsetElapsedFrames, duration)
                    XCTAssertNil(after.gainRamp)
                    XCTAssertNil(after.panRamp)
                }
            } } }
        } }
    }

    func testHighFirstSampleAdvancesImmediatelyAndChunkPartitionsAreExact() throws {
        for rate in [44_100.0, 48_000] {
            let sample = MixerSampleBuffer(monoPCM: [0.9375] + Array(repeating: -0.25, count: 4095))
            func make() -> (CSoftwareMixer, Int) {
                let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
                let slot = mixer.addVoice(sample: sample, sourceOnsetElapsedFrames: 0)
                return (mixer, slot)
            }
            let (whole, _) = make(), expected = whole.render(frames: 2048).interleavedPCM
            XCTAssertEqual(expected[0], 0)
            XCTAssertEqual(expected[1], -0.25 / Float(Int(rate * 0.005)))
            for chunk in [1, 17, 256, 997] {
                let (mixer, slot) = make()
                var pcm = [Float]()
                while pcm.count < expected.count {
                    pcm += mixer.render(frames: min(chunk, expected.count - pcm.count)).interleavedPCM
                    XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: slot)?.samplePosition, Double(pcm.count))
                }
                XCTAssertEqual(pcm, expected)
                mixer.reset()
                XCTAssertEqual(mixer.render(frames: 2048).interleavedPCM, expected)
            }
        }
    }

    func testSilentAndZeroStepBirthsContinueWithoutAnotherOnset() throws {
        for rate in [44_100.0, 48_000] {
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let voice = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 0.75, count: 4096)),
                gain: 0, initialSourceFrame: 256, sourceOnsetElapsedFrames: 0)
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: 0, playbackStep: 0).wasAccepted)
            let duration = Int(rate * 0.005)
            XCTAssertTrue(mixer.render(frames: duration + 1).interleavedPCM.allSatisfy { $0 == 0 })
            let held = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertTrue(held.active)
            XCTAssertEqual(held.samplePosition, 256)
            XCTAssertEqual(held.sampleStep, 0)
            XCTAssertEqual(held.sourceOnsetElapsedFrames, duration)
            XCTAssertFalse(mixer.setSourceOnset(elapsedFrames: 0, forVoiceAt: voice))
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: duration + 1, playbackStep: 1).wasAccepted)
            XCTAssertTrue(mixer.scheduleVoiceGainPanImmediateUpdate(voiceIndex: voice, scheduledFrame: duration + 1, gain: 1).wasAccepted)
            XCTAssertEqual(mixer.render(frames: 1).interleavedPCM, [0.75])
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, 257)
        }
    }

    func testCompletedStoppedAndEmptySourcesCannotBeRevivedAndNewGenerationStartsAtZero() throws {
        let mixer = CSoftwareMixer(config: .init(sampleRate: 48_000, channelCount: 1))
        let empty = mixer.addVoice(sample: .init(monoPCM: []), sourceOnsetElapsedFrames: 0)
        XCTAssertFalse(mixer.setSourceOnset(elapsedFrames: 0, forVoiceAt: empty))
        XCTAssertEqual(mixer.activeVoiceCount, 0)
        let source = MixerSampleBuffer(monoPCM: [1, -1])
        let voice = mixer.addVoice(sample: source, sourceOnsetElapsedFrames: 0)
        XCTAssertEqual(mixer.render(frames: 3).interleavedPCM, [0, -1.0 / 240, 0])
        XCTAssertFalse(mixer.setSourceOnset(elapsedFrames: 0, forVoiceAt: voice))
        let next = mixer.addVoice(sample: source, sourceOnsetElapsedFrames: 0)
        XCTAssertEqual(mixer.render(frames: 1).interleavedPCM, [0])
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: next)?.samplePosition, 1)
        XCTAssertTrue(mixer.stopVoice(at: next))
        XCTAssertFalse(mixer.setSourceOnset(elapsedFrames: 0, forVoiceAt: next))
        XCTAssertTrue(mixer.render(frames: 256).interleavedPCM.allSatisfy { $0 == 0 })
    }

    func testSilentMovingSourceCanReceiveManagedOutputDuringAttackWithoutAnotherBirth() throws {
        for rate in [44_100.0, 48_000] {
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let voice = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 0.75, count: 4096)),
                gain: 0, sourceOnsetElapsedFrames: 0)
            XCTAssertTrue(mixer.publishAudibleOutput(target(0), forVoiceAt: voice))
            let duration = Int(rate * 0.005), half = duration / 2
            XCTAssertTrue(mixer.render(frames: half).interleavedPCM.allSatisfy { $0 == 0 })
            let silent = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertTrue(silent.active)
            XCTAssertEqual(silent.samplePosition, Double(half))
            XCTAssertEqual(silent.sourceOnsetElapsedFrames, half)
            let output = PlaybackXMAudibleUpdate(eventIndex: 0, channelIndex: 0,
                source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), tick: 0,
                scheduledFrame: half, bpm: 125, speed: 6, amplitude: 1, pan: 0,
                durationFrames: duration, intent: "early-volume-recovery", rebaseFromCurrent: true)
            XCTAssertTrue(mixer.publishAudibleOutput(output, forVoiceAt: voice))
            let pcm = mixer.render(frames: duration + 1).interleavedPCM
            for k in [0, 1, half, duration - 1, duration] {
                let onset = min(1, Float(half + k) / Float(duration))
                let finalTarget = Float(k) / Float(duration)
                XCTAssertEqual(pcm[k], 0.75 * onset * finalTarget, accuracy: 1e-7)
            }
            let restored = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertEqual(restored.samplePosition, Double(half + duration + 1))
            XCTAssertEqual(restored.sourceOnsetElapsedFrames, duration)
            XCTAssertNil(restored.gainRamp)
            XCTAssertEqual(mixer.loadedVoiceCount, 1)
        }
    }

    func testManagedReplacementKeepsOld32FrameTailIndependentOfNewOnset() throws {
        for rate in [44_100.0, 48_000] {
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let old = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 0.5, count: 4096)), sourceOnsetElapsedFrames: 0)
            mixer.setChannelTag(0, forVoiceAt: old)
            XCTAssertTrue(mixer.publishAudibleOutput(target(0.5), forVoiceAt: old))
            let duration = Int(rate * 0.005)
            _ = mixer.render(frames: duration + 17)
            XCTAssertEqual(mixer.rampDownVoices(channel: 0), 1)
            let new = mixer.addVoice(sample: .init(monoPCM: Array(repeating: -0.5, count: 4096)), sourceOnsetElapsedFrames: 0)
            XCTAssertTrue(mixer.publishAudibleOutput(target(1), forVoiceAt: new))
            let pcm = mixer.render(frames: 31).interleavedPCM
            for k in 0..<31 {
                XCTAssertEqual(pcm[k], 0.25 * (1 - Float(k + 1) / 32) - 0.5 * Float(k) / Float(duration), accuracy: 1e-7)
            }
            XCTAssertTrue(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: old)).active)
            XCTAssertEqual(mixer.render(frames: 1).interleavedPCM[0], -0.5 * 31 / Float(duration))
            XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: old)).active)
            XCTAssertEqual(mixer.rampDownCompletionCount, 1)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: new)?.sourceOnsetElapsedFrames, 32)
        }
    }

    func testWholePreparedIndexedScanAndArbitraryWindowsPreserveBirthAge() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for delayed in [false, true] {
            let module = song(linear: linear, delayed: delayed)
            let config = MixerRenderConfig(sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 4)
            let renderer = Renderer(), full = renderer.render(request)
            let plan = full.plan, start = delayed ? Int(rate / 50) : 0, duration = Int(rate * 0.005)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.pattern.events[0].scheduledStartFrame, start)
            XCTAssertEqual(plan.pattern.events[0].initialSourceFrame, delayed ? 0 : 256)
            XCTAssertEqual(Renderer(preparedPlan: plan).render(request).block.interleavedPCM, full.block.interleavedPCM)
            for rows in [1, 2, 3] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, full.block.interleavedPCM)
                XCTAssertEqual(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: rows).block.interleavedPCM,
                    full.block.interleavedPCM)
            }
            #if DEBUG
            let boundaries = Set([1, max(1, start - 1), max(1, start), start + 1,
                start + duration / 2, start + duration - 1, start + duration, start + duration + 1]).sorted()
            XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries).block.interleavedPCM,
                full.block.interleavedPCM)
            for age in [1, duration / 2, duration, duration + 1] {
                let carry = try XCTUnwrap(renderer.continuationsForTesting(plan, at: start + age, config: config).first)
                XCTAssertEqual(carry.runtimeState.sourceOnsetElapsedFrames, age)
                let mixer = CSoftwareMixer(config: config)
                let slot = try XCTUnwrap(Renderer.scheduleContinuation(carry, on: mixer).voiceIndex)
                XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: slot)?.sourceOnsetElapsedFrames, min(age, duration))
                XCTAssertEqual(mixer.render(frames: 32).interleavedPCM,
                    Array(full.block.interleavedPCM[((start + age) * 2)..<((start + age + 32) * 2)]))
            }
            #endif
        } } }
    }

    func testPublicPhraseKeepsExactSampleIdentityDispatchAndGenerationFrames() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/new-source-onset.xm")
        let loaded = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let song = PlaybackSong(title: loaded.title, orders: loaded.orders, patternsByIndex: loaded.patternsByIndex,
                instrumentsByIndex: loaded.instrumentsByIndex, restartOrderIndex: loaded.restartOrderIndex,
                endBehavior: loaded.endBehavior, initialTiming: loaded.initialTiming, usesLinearFrequencyTable: linear)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), tick = Int(rate / 50)
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 1, 1, 0, 0, 1])
            XCTAssertEqual(plan.pattern.events.map(\.scheduledStartFrame), [0, 24, 48, 73, 96, 120].map { $0 * tick })
            XCTAssertTrue(plan.pattern.events.allSatisfy { $0.initialSourceFrame == 0 })
            let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), rows: 24)
            let renderer = Renderer(preparedPlan: plan), whole = renderer.render(request)
            for rows in [1, 5, 7] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, whole.block.interleavedPCM)
            }
            let session = renderer.prepare(request)
            var pcm = [Float]()
            for chunk in [1, 17, 256, 997] {
                pcm += session.render(frames: chunk).interleavedPCM
            }
            pcm += session.render(frames: whole.block.frameCount - pcm.count / 2).interleavedPCM
            XCTAssertEqual(pcm, whole.block.interleavedPCM)
        } }
    }

    private func target(_ amplitude: Float, pan: Float = 0) -> PlaybackXMAudibleUpdate {
        .init(eventIndex: 0, channelIndex: 0, source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            tick: 0, scheduledFrame: 0, bpm: 125, speed: 6, amplitude: amplitude, pan: pan,
            durationFrames: 0, intent: "new-source-control")
    }

    private func song(linear: Bool, delayed: Bool) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.75, count: 4096),
            volume: 0.25, panning: 64, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
            loopStart: 0, loopLength: 4096, loopType: 1)
        let cells = [PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: delayed ? 14 : 9,
            effectParam: delayed ? 0xD1 : 1)] + Array(repeating: PlaybackCell(note: 0, instrument: 0,
                volumeColumn: 0, effectType: 0, effectParam: 0), count: 3)
        return .init(title: "Original new-source control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
