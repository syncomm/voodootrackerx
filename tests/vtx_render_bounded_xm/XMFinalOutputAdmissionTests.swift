import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Public, authored controls distinguish moving sample identity from final-output interpolation.
final class XMFinalOutputAdmissionTests: XCTestCase {
    private typealias R = PlaybackSongOfflineRenderer

    func testPlainAndFlatUnityEnvelopeHaveIdenticalMusicalGainAndPanOutput() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for bpm in [125, 250] {
            for profile in MixerMixProfile.allCases {
                let rows = [[c(note: 49, instrument: 1)], [c(effect: 16, param: 32)],
                    [c(effect: 8, param: 0)], [c(volume: 0x40, effect: 8, param: 192)],
                    [c(volume: 0x20, effect: 12, param: 48)], [c()]]
                let plain = song(rows, linear: linear, bpm: bpm)
                let flat = song(rows, linear: linear, bpm: bpm, envelope: true)
                let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
                let a = R().render(.init(song: plain, config: config, rows: rows.count))
                let b = R().render(.init(song: flat, config: config, rows: rows.count))
                XCTAssertEqual(a.block.interleavedPCM, b.block.interleavedPCM,
                    "linear=\(linear), rate=\(rate), bpm=\(bpm), profile=\(profile)")
                let updates = try XCTUnwrap(a.plan.xmAudibleTimeline?.updatesByEvent[0])
                XCTAssertEqual(updates.map(\.source.rowIndex), [0, 1, 2, 3])
                XCTAssertEqual(updates.map(\.amplitude), [1, 0.5, 0.5, 0.375])
                XCTAssertEqual(updates.map(\.durationFrames),
                    [0, Int(rate * 2.5 / Double(bpm)), Int(rate * 2.5 / Double(bpm)), Int(rate * 0.005)])
                XCTAssertEqual(Set(updates.map(\.scheduledFrame)).count, updates.count)
                XCTAssertTrue(updates.allSatisfy { $0.activation == nil })
            }
        } } }
    }

    func testGainPanAndCoalescedTargetsHaveOldValueAtZeroAndExactEndpoints() throws {
        // The 0.5/right -> 0.75/left case increases both amplitude and left gain;
        // interpolation must occur once on their final product.
        let commands = [c(effect: 16, param: 32), c(effect: 8, param: 0),
            c(volume: 0x40, effect: 8, param: 192), c(volume: 0x20, effect: 12, param: 48)]
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for bpm in [125, 250] {
            for command in commands {
                let rows = [[c(note: 49, instrument: 1)], [command], [c()]]
                let input = song(rows, linear: linear, bpm: bpm)
                let plan = adapt(input, rate)
                let updates = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
                XCTAssertEqual(updates.count, 2)
                let next = updates[1], start = updates[0]
                let quick = command.volumeColumn != 0 || command.effectType == 12
                let d = Int(rate * (quick ? 0.005 : 2.5 / Double(bpm)))
                XCTAssertEqual(next.durationFrames, d)
                XCTAssertEqual(next.amplitude, command.effectType == 8 && command.volumeColumn == 0 ? 1 :
                    command.effectType == 16 ? 0.5 : 0.75)
                for profile in MixerMixProfile.allCases {
                    let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
                    let actual = R(preparedPlan: plan).render(.init(song: input, config: config, rows: 3)).block.interleavedPCM
                    let neutral = song([[c(note: 49, instrument: 1)], [c()], [c()]], linear: linear, bpm: bpm)
                    let source = R().render(.init(song: neutral,
                        config: .init(sampleRate: rate, channelCount: 1), rows: 3)).block.interleavedPCM
                    for k in [0, 1, 8, 32, d / 2, d - 1, d, d + 1] {
                        let fraction = min(1, Float(k) / Float(d))
                        for channel in 0..<2 {
                            let law = channel == 0 ? config.panLaw.leftGain : config.panLaw.rightGain
                            let old = start.amplitude * law(start.pan), new = next.amplitude * law(next.pan)
                            let factor = old + (new - old) * fraction
                            XCTAssertEqual(actual[2 * (next.scheduledFrame + k) + channel],
                                source[next.scheduledFrame + k] * factor * config.outputScale, accuracy: 1e-7)
                        }
                    }
                }
            }
        } } }
    }

    func testNeutralTicksAndRepeatedTargetsStaySparseWithoutRestartingTransitions() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let rows = [[c(note: 49, instrument: 1)], [c(effect: 12, param: 32)],
                [c(effect: 12, param: 32)], [c(volume: 0x30)], [c(instrument: 1, volume: 0x30)]] +
                Array(repeating: [c()], count: 59)
            let plan = adapt(song(rows, linear: linear), rate)
            let updates = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertEqual(updates.map(\.amplitude), [1, 0.5])
            XCTAssertEqual(updates.map(\.source.rowIndex), [0, 1])
            XCTAssertEqual(updates.first?.durationFrames, 0)
            XCTAssertEqual(plan.pattern.events.count, 1)
            var state = MixerAudibleOutputState()
            let config = MixerRenderConfig(sampleRate: rate)
            state.publish(updates[0], config: config)
            state.publish(updates[1], config: config)
            state.advance(8)
            let before = state
            state.publish(updates[1], config: config)
            XCTAssertEqual(state, before)
        } }
    }

    func testEightFrameInterruptionKeepsOrdinaryAndResetRebasingDistinct() throws {
        for rate in [44_100.0, 48_000] { for bpm in [125, 250] {
            let config = MixerRenderConfig(sampleRate: rate), d = Int(rate * 2.5 / Double(bpm))
            var ordinary = MixerAudibleOutputState()
            ordinary.publish(target(0.25, pan: -0.5), config: config)
            ordinary.publish(target(1, pan: 0.5, duration: d), config: config)
            ordinary.advance(8)
            let current = ordinary.current
            var reset = ordinary
            ordinary.publish(target(0.5, pan: -0.25, duration: d), config: config)
            XCTAssertEqual(ordinary.current, [1, 0.5, 1])
            var quick = target(0.5, pan: -0.25, duration: Int(rate * 0.005))
            quick.rebaseFromCurrent = true
            reset.publish(quick, config: config)
            XCTAssertEqual(reset.current, current)
            XCTAssertNotEqual(reset.start, ordinary.start)
            let saved = reset
            reset.publish(quick, config: config)
            XCTAssertEqual(reset, saved)
            ordinary.advance(d)
            reset.advance(Int(rate * 0.005))
            XCTAssertEqual(ordinary.current, [0.5, 0.5, 0.375])
            XCTAssertEqual(reset.current, ordinary.current)
        } }
    }

    func testSilentPanSlidesStaySparseAndRecoveryUsesRetainedPanAndMovingCursor() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            var rows = [[c(note: 49, instrument: 1)]]
            for row in 1...12 { rows.append([c(volume: row % 2 == 1 ? 0xD1 : 0xE2)]) }
            rows += [[c(effect: 12, param: 32)], [c()]]
            let input = song(rows, linear: linear, headerVolume: 0)
            let plan = adapt(input, rate), config = MixerRenderConfig(sampleRate: rate)
            let updates = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertEqual(updates.map(\.amplitude), [0, 0.5])
            XCTAssertEqual(updates.map(\.source.rowIndex), [0, 13])
            // Six left rows subtract 5 each; six right rows add 10 each: byte 158.
            // Column-pan conversion remains its existing symmetric byte law.
            XCTAssertEqual(updates.last?.pan ?? 0, Float(61) / 255, accuracy: 1e-7)
            let mixer = CSoftwareMixer(config: config)
            let slot = try XCTUnwrap(SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)[0])
            R.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: slot], on: mixer)
            let restore = 13 * 6 * Int(rate / 50)
            XCTAssertTrue(mixer.render(frames: restore).interleavedPCM.allSatisfy { $0 == 0 })
            let silent = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slot))
            XCTAssertTrue(silent.active)
            XCTAssertEqual(silent.samplePosition, (Double(restore) * silent.sampleStep).truncatingRemainder(dividingBy: 257), accuracy: 1e-8)
            XCTAssertEqual(silent.audibleOutputState?.target, [0, 0, 0])
            _ = mixer.render(frames: Int(rate * 0.005) + 1)
            let recovered = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slot))
            XCTAssertEqual(recovered.audibleOutputState?.target[1] ?? 0, 0.5 * (1 - Float(61) / 255), accuracy: 1e-7)
            XCTAssertEqual(recovered.audibleOutputState?.target[2], 0.5)
            XCTAssertNil(recovered.gainRamp)
            XCTAssertNil(recovered.panRamp)
            XCTAssertEqual(mixer.loadedVoiceCount, 1)
        } }
    }

    func testPanEnvelopeLongNeutralHoldAddsOnlyGenuineMotionWithoutVolumeEnvelope() throws {
        let pan = PlaybackPanningEnvelope(enabled: true,
            points: [(0, 32), (32, 32), (36, 48), (40, 48)].map { .init(tick: $0.0, value: $0.1) },
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1)
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let rows = [[c(note: 49, instrument: 1)]] + Array(repeating: [c()], count: 8)
            let sparse = adapt(song(rows, linear: linear, panEnvelope: pan), rate)
            let updates = try XCTUnwrap(sparse.xmAudibleTimeline?.updatesByEvent[0])
            let tick = Int(rate / 50)
            XCTAssertEqual(updates.map(\.scheduledFrame), [0, 33 * tick, 34 * tick, 35 * tick, 36 * tick])
            XCTAssertEqual(updates.map(\.pan), [0, Float(16) / 127, Float(32) / 127, Float(48) / 127, Float(64) / 127])
            XCTAssertTrue(updates.allSatisfy { $0.amplitude == 1 })
            XCTAssertEqual(updates.map(\.durationFrames), [0, tick, tick, tick, tick])
            let dense = adapt(song(rows, linear: linear, envelope: true, panEnvelope: pan), rate)
            XCTAssertEqual(dense.xmAudibleTimeline?.updates.count, dense.xmEnvelopeTimeline?.updates.count)
            XCTAssertGreaterThan(dense.xmAudibleTimeline?.updates.count ?? 0, 32)
        } }
    }

    func testZeroHeaderBirthPublishesZeroAndMovesBeforeQuickRecovery() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song([[c(note: 49, instrument: 1)], [c()], [c(effect: 12, param: 32)], [c()]],
                linear: linear, headerVolume: 0)
            let plan = adapt(input, rate), config = MixerRenderConfig(sampleRate: rate)
            let updates = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertEqual(updates.map(\.amplitude), [0, 0.5])
            XCTAssertEqual(updates.first?.scheduledFrame, 0)
            XCTAssertEqual(updates.first?.durationFrames, 0)
            XCTAssertEqual(plan.pattern.events.count, 1)
            let mixer = CSoftwareMixer(config: config)
            let voice = try XCTUnwrap(SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)[0])
            R.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: voice], on: mixer)
            let restore = 12 * Int(rate / 50)
            XCTAssertTrue(mixer.render(frames: restore).interleavedPCM.allSatisfy { $0 == 0 })
            let silent = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertTrue(silent.active)
            XCTAssertEqual(silent.audibleOutputState?.target, [0, 0, 0])
            XCTAssertEqual(silent.sourceOnsetElapsedFrames, Int(rate * 0.005))
            XCTAssertEqual(silent.samplePosition,
                (Double(restore) * silent.sampleStep).truncatingRemainder(dividingBy: 257), accuracy: 1e-8)
            XCTAssertNil(silent.gainRamp)
            XCTAssertNil(silent.panRamp)
            let pcm = mixer.render(frames: Int(rate * 0.005) + 2).interleavedPCM
            XCTAssertEqual(Array(pcm.prefix(2)), [0, 0])
            XCTAssertTrue(pcm.dropFirst(2).contains { $0 != 0 })
            XCTAssertEqual(mixer.loadedVoiceCount, 1)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.sourceOnsetElapsedFrames, Int(rate * 0.005))
        } }
    }

    func testGlobalBirthVisibilityAndBlankHoldRemainChannelTurnCausal() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for first in [false, true] {
            let note = c(note: 49, instrument: 1), global = c(effect: 16, param: 32)
            let input = song([first ? [global, note] : [note, global], [c(), c()],
                first ? [c(), c(effect: 12, param: 64)] : [c(effect: 12, param: 64), c()], [c(), c()]], linear: linear)
            let plan = adapt(input, rate)
            let updates = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertEqual(updates.first?.amplitude, first ? 0.5 : 1)
            XCTAssertFalse(updates.contains { $0.source.rowIndex == 1 })
            XCTAssertEqual(updates.last?.amplitude, 0.5)
            XCTAssertEqual(updates.count, first ? 1 : 2)
            XCTAssertEqual(updates.first?.durationFrames, 0)
        } } }
    }

    func testExactSampleOwnershipAcrossNoteOnlyAndInstrumentOnlyReset() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song([[c(note: 49, instrument: 1)], [c(effect: 12, param: 16)],
                [c(instrument: 1)], [c(note: 50)], [c(instrument: 1)], [c()]], linear: linear)
            let plan = adapt(input, rate)
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 1])
            XCTAssertEqual(plan.pattern.events.count, 2)
            XCTAssertEqual(plan.pattern.events[0].sample.monoPCM, pcm(0))
            XCTAssertEqual(plan.pattern.events[1].sample.monoPCM, pcm(1))
            XCTAssertEqual(plan.pattern.events[1].gain, 1)
            let second = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[1]?.first)
            XCTAssertEqual(second.scheduledFrame, 18 * Int(rate / 50))
            XCTAssertEqual(second.durationFrames, 0)
            XCTAssertEqual(second.amplitude, 1)
            let reset = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0]?.first { $0.source.rowIndex == 2 })
            XCTAssertTrue(reset.rebaseFromCurrent)
            XCTAssertEqual(reset.durationFrames, Int(rate * 0.005))
            XCTAssertEqual(reset.amplitude, 1)
        } }
    }

    func testEmptyMissingRefusedColdAndCompletedSourcesCannotBeCreatedByOutputUpdates() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for kind in ["empty", "missing", "absent", "refused", "cold"] {
                let rows = [[kind == "cold" ? c() : c(note: 49, instrument: 1)],
                    [c(effect: 12, param: 64)], [c(effect: 8, param: 0)], [c(instrument: 1)]]
                let input = song(rows, linear: linear, sourceKind: kind)
                let result = R().render(.init(song: input, config: .init(sampleRate: rate), rows: rows.count))
                XCTAssertTrue(result.plan.pattern.events.isEmpty, kind)
                XCTAssertTrue(result.plan.xmAudibleTimeline?.updates.isEmpty ?? true, kind)
                XCTAssertTrue(result.block.interleavedPCM.allSatisfy { $0 == 0 }, kind)
            }
            let finite = song([[c(note: 49, instrument: 1)], [c(effect: 12, param: 32)],
                [c(effect: 8, param: 0)], [c(instrument: 1)]], linear: linear, sourceKind: "finite")
            let result = R().render(.init(song: finite, config: .init(sampleRate: rate), rows: 4))
            XCTAssertEqual(result.plan.pattern.events.count, 1)
            let row = 6 * Int(rate / 50)
            XCTAssertTrue(result.block.interleavedPCM[(row * 2)...].allSatisfy { $0 == 0 })
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate)), plan = result.plan
            let slot = try XCTUnwrap(SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)[0])
            R.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: slot], on: mixer)
            _ = mixer.render(frames: row)
            XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slot)).active)
            XCTAssertFalse(mixer.publishAudibleOutput(target(1), forVoiceAt: slot))
            XCTAssertTrue(mixer.render(frames: row * 3).interleavedPCM.allSatisfy { $0 == 0 })
            XCTAssertEqual(mixer.activeVoiceCount, 0)
            XCTAssertEqual(mixer.loadedVoiceCount, 1)
        } }
    }

    func testAllZeroRepresentedPCMRemainsAnActiveManagedMovingSource() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song([[c(note: 49, instrument: 1)], [c(effect: 12, param: 32)], [c()]],
                linear: linear, sourceKind: "silent")
            let plan = adapt(input, rate), config = MixerRenderConfig(sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.count, 1)
            let mixer = CSoftwareMixer(config: config)
            let slot = try XCTUnwrap(SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)[0])
            R.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: slot], on: mixer)
            let frames = 8 * Int(rate / 50)
            XCTAssertTrue(mixer.render(frames: frames).interleavedPCM.allSatisfy { $0 == 0 })
            let voice = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slot))
            XCTAssertTrue(voice.active)
            XCTAssertEqual(voice.audibleOutputState?.target, [0.5, 0.5, 0.5])
            XCTAssertEqual(voice.samplePosition, (Double(frames) * voice.sampleStep).truncatingRemainder(dividingBy: 257), accuracy: 1e-8)
            XCTAssertNil(voice.gainRamp)
            XCTAssertEqual(mixer.loadedVoiceCount, 1)
        } }
    }

    func testStaticQuietNoncenterPanRetainsLawWithinFloatAssociationAndPCM16Precision() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for profile in MixerMixProfile.allCases {
            let input = song([[c(note: 49, instrument: 1)], [c()], [c()]], linear: linear,
                headerVolume: 13.0 / 64, panning: 73)
            let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
            let actual = R().render(.init(song: input, config: config, rows: 3))
            let event = try XCTUnwrap(actual.plan.pattern.events.first)
            let generic = CSoftwareMixer(config: config)
            let voice = generic.addVoice(sample: event.sample, gain: event.gain, pan: event.pan,
                playbackStep: event.playbackStep, loop: event.loop, sourceOnsetElapsedFrames: 0)
            let previous = generic.render(frames: actual.block.frameCount).interleavedPCM
            let settled = Int(rate * 0.005) * 2
            XCTAssertEqual(actual.plan.xmAudibleTimeline?.updates.count, 1)
            XCTAssertNil(generic.voiceDiagnostic(forVoiceAt: voice)?.audibleOutputState)
            // Admission associates the same static factors into final L/R once. Tiny
            // Float32 rounding is observable; it must not alter the law or PCM16 level.
            for index in settled..<previous.count {
                XCTAssertEqual(actual.block.interleavedPCM[index], previous[index], accuracy: 1e-7)
                let old = Int(MixerWAVExporter.pcm16Sample(from: previous[index]))
                let new = Int(MixerWAVExporter.pcm16Sample(from: actual.block.interleavedPCM[index]))
                XCTAssertLessThanOrEqual(abs(old - new), 1)
            }
        } } }
    }

    func testWholePreparedIndexedScanAndArbitraryWindowsImportExactSparseState() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for bpm in [125, 250] {
            let rows = [[c(note: 49, instrument: 1)], [c(effect: 16, param: 32)],
                [c(effect: 8, param: 0)], [c(volume: 0x40, effect: 8, param: 192)], [c()], [c()]]
            let input = song(rows, linear: linear, bpm: bpm)
            let config = MixerRenderConfig(sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: config, rows: rows.count)
            let renderer = R(), whole = renderer.render(request), plan = whole.plan
            XCTAssertEqual(R(preparedPlan: plan).render(request).block.interleavedPCM, whole.block.interleavedPCM)
            for window in [1, 2, 3] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: window).block.interleavedPCM, whole.block.interleavedPCM)
                XCTAssertEqual(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: window).block.interleavedPCM,
                    whole.block.interleavedPCM)
            }
            let updates = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertNil(plan.xmAudibleTimeline?.state(eventIndex: 0, before: 0, config: config))
            var candidates = Set<Int>()
            for update in updates {
                let frame = update.scheduledFrame, duration = update.durationFrames
                for offset in [0, 1, 8, duration / 2, duration, duration + 1] {
                    if frame + offset > 0 { candidates.insert(frame + offset) }
                }
            }
            let boundaries = candidates.sorted()
            #if DEBUG
            XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries).block.interleavedPCM,
                whole.block.interleavedPCM)
            for boundary in boundaries {
                let carry = try XCTUnwrap(renderer.continuationsForTesting(plan, at: boundary, config: config).first)
                let expected = try XCTUnwrap(plan.xmAudibleTimeline?.state(eventIndex: 0, before: boundary, config: config))
                XCTAssertEqual(carry.audibleOutputState, expected)
                let mixer = CSoftwareMixer(config: config)
                let slot = try XCTUnwrap(R.scheduleContinuation(carry, on: mixer).voiceIndex)
                R.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: slot], on: mixer, windowStartFrame: boundary)
                XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: slot)?.samplePosition, carry.runtimeState.samplePosition)
                XCTAssertEqual(mixer.render(frames: 64).interleavedPCM,
                    Array(whole.block.interleavedPCM[(boundary * 2)..<((boundary + 64) * 2)]))
            }
            #endif
        } } }
    }

    private func target(_ amplitude: Float, pan: Float = 0, duration: Int = 0) -> PlaybackXMAudibleUpdate {
        .init(eventIndex: 0, channelIndex: 0, source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            tick: 0, scheduledFrame: 0, bpm: 125, speed: 6, amplitude: amplitude, pan: pan,
            durationFrames: duration, intent: "authored-control")
    }

    private func adapt(_ input: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
    }

    private func c(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0,
                   effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func pcm(_ identity: Int) -> [Float] {
        (0..<257).map { Float(($0 * (identity == 0 ? 73 : 41) + identity * 37) % 251 - 125) / 256 }
    }

    private func song(_ rows: [[PlaybackCell]], linear: Bool = true, bpm: Int = 125,
                      envelope: Bool = false, headerVolume: Float = 1, panning: UInt8 = 128,
                      sourceKind: String = "loop", panEnvelope: PlaybackPanningEnvelope = .disabled) -> PlaybackSong {
        let loops = sourceKind == "loop" || sourceKind == "silent"
        let samples = (0...1).map { index in
            PlaybackSample(instrumentIndex: 1, sampleIndex: index,
                pcm: sourceKind == "empty" ? [] : sourceKind == "silent" ? Array(repeating: 0, count: 257) :
                    sourceKind == "finite" ? Array(pcm(index).prefix(32)) : pcm(index),
                volume: headerVolume, panning: panning, relativeNote: sourceKind == "refused" ? 127 : 0,
                finetune: 0, baseSampleRate: 8_363,
                loopStart: 0, loopLength: loops ? 257 : 0, loopType: loops ? 1 : 0)
        }
        let volume = PlaybackVolumeEnvelope(enabled: envelope,
            points: envelope ? [.init(tick: 0, value: 64), .init(tick: 64, value: 64)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: 0)
        var map = Array(repeating: sourceKind == "missing" ? 7 : 0, count: 96)
        if sourceKind != "missing" { map[49] = 1 }
        return .init(title: "Original G05 final-output admission controls", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: [1: .init(index: 1, samples: sourceKind == "absent" ? [] : samples,
                volumeEnvelope: volume, panningEnvelope: panEnvelope, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: bpm), usesLinearFrequencyTable: linear)
    }
}
