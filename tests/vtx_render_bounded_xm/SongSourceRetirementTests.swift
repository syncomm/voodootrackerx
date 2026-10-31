import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class SongSourceRetirementTests: XCTestCase {
    private typealias R = PlaybackSongOfflineRenderer

    func testSignedIsolatedAndSummedTailsUseCurrentFirstFrameAndFiveMillisecondEndpoint() throws {
        for rate in [44_100.0, 48_000] { for managed in [false, true] {
            let n = Int(rate * 0.005)
            for age in [n / 2, n + 17] { for gain: Float in [0, 0.25, 1] { for kind in 0..<3 {
                let mixer = CSoftwareMixer(config: .init(sampleRate: rate))
                let oldGain: Float = kind == 1 ? 0 : gain, newGain: Float = kind == 0 ? 0 : 0.25
                let old = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 0.5, count: 4096)),
                    gain: oldGain, pan: -0.5, playbackStep: 0.5, sourceOnsetElapsedFrames: 0)
                mixer.setChannelTag(0, forVoiceAt: old)
                if managed { XCTAssertTrue(mixer.publishAudibleOutput(target(oldGain, pan: -0.5), forVoiceAt: old)) }
                _ = mixer.render(frames: age)
                XCTAssertEqual(mixer.retireSongVoices(channel: 0), 1)
                let new = mixer.addVoice(sample: .init(monoPCM: Array(repeating: -0.25, count: 4096)),
                    gain: newGain, pan: 0.5, playbackStep: 0.25, sourceOnsetElapsedFrames: 0)
                if managed { XCTAssertTrue(mixer.publishAudibleOutput(target(newGain, pan: 0.5), forVoiceAt: new)) }
                let pcm = mixer.render(frames: n + 2).interleavedPCM
                for k in [0, 1, n / 2, n - 1, n, n + 1] {
                    let outgoing = 0.5 * oldGain * min(1, Float(age) / Float(n)) * max(0, 1 - Float(k) / Float(n))
                    let incoming = -0.25 * newGain * min(1, Float(k) / Float(n))
                    XCTAssertEqual(pcm[k * 2], outgoing + incoming * 0.5, accuracy: 1e-7)
                    XCTAssertEqual(pcm[k * 2 + 1], outgoing * 0.5 + incoming, accuracy: 1e-7)
                }
                let retired = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: old))
                XCTAssertFalse(retired.active)
                XCTAssertEqual(retired.samplePosition, Double(age + n) * 0.5)
                XCTAssertEqual(retired.sourceOnsetElapsedFrames, min(age, n))
                XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: new)?.samplePosition, Double(n + 2) * 0.25)
                XCTAssertEqual(mixer.rampDownCompletionCount, 1)
                XCTAssertFalse(mixer.setSourceOnset(elapsedFrames: 0, forVoiceAt: old))
                XCTAssertFalse(mixer.publishAudibleOutput(target(1), forVoiceAt: old))
            } } }
        } }
    }

    func testInterruptedFinalOutputAndZeroStepAreSampledWithoutAnotherGainMultiplier() throws {
        for rate in [44_100.0, 48_000] {
            let n = Int(rate * 0.005), mixer = CSoftwareMixer(config: .init(sampleRate: rate))
            let old = mixer.addVoice(sample: .init(monoPCM: Array(repeating: -0.5, count: 4096)),
                gain: 0.25, sourceOnsetElapsedFrames: n)
            mixer.setChannelTag(0, forVoiceAt: old)
            XCTAssertTrue(mixer.publishAudibleOutput(target(0.25, pan: -0.5), forVoiceAt: old))
            XCTAssertTrue(mixer.publishAudibleOutput(target(0.75, pan: 0.5, duration: n), forVoiceAt: old))
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: old, scheduledFrame: 0, playbackStep: 0).wasAccepted)
            _ = mixer.render(frames: n / 3)
            let before = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: old)?.audibleOutputState)
            XCTAssertEqual(mixer.retireSongVoices(channel: 0), 1)
            XCTAssertTrue(mixer.scheduleSongVoiceRetirement(voiceIndex: old, scheduledFrame: n / 3 + 17).wasAccepted)
            XCTAssertTrue(mixer.scheduleVoiceGainPanUpdate(voiceIndex: old, scheduledFrame: n / 3 + 18, gain: 1).wasAccepted)
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: old, scheduledFrame: n / 3 + 19, playbackStep: 1).wasAccepted)
            let pcm = mixer.render(frames: n + 1).interleavedPCM
            for k in [0, 1, n / 2, n - 1, n] { for channel in 0..<2 {
                XCTAssertEqual(pcm[k * 2 + channel], -0.5 * before.current[channel + 1] * max(0, 1 - Float(k) / Float(n)), accuracy: 1e-7)
            } }
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: old)?.samplePosition, 0)
            XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: old)).active)
        }
    }

    func testRapidRetirementNeverRestartsOrExtendsAnOlderGeneration() throws {
        for rate in [44_100.0, 48_000] {
            let n = Int(rate * 0.005), mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            var slots = [Int]()
            for generation in 0..<4 {
                if generation > 0 {
                    _ = mixer.render(frames: 17)
                    XCTAssertEqual(mixer.retireSongVoices(channel: 0), 1)
                    for previous in slots.indices {
                        let state = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slots[previous]))
                        XCTAssertEqual(state.gainRamp?.positionFrame, (generation - previous - 1) * 17)
                        XCTAssertEqual(state.gainRamp?.totalFrames, n)
                        XCTAssertEqual(state.gainRamp?.songRetirement, true)
                        XCTAssertEqual(state.sourceOnsetElapsedFrames, 17)
                    }
                }
                let slot = mixer.addVoice(sample: .init(monoPCM: Array(repeating: generation % 2 == 0 ? 0.5 : -0.25, count: 4096)),
                    sourceOnsetElapsedFrames: 0)
                mixer.setChannelTag(0, forVoiceAt: slot); slots.append(slot)
            }
            XCTAssertEqual(mixer.rampDownStartCount, 3)
            _ = mixer.render(frames: n - 34)
            XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slots[0])).active)
            XCTAssertTrue(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slots[1])).active)
            _ = mixer.render(frames: 17)
            XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slots[1])).active)
            _ = mixer.render(frames: 17)
            XCTAssertEqual(mixer.rampDownCompletionCount, 3)
            XCTAssertEqual(mixer.activeVoiceCount, 1)
            XCTAssertEqual(mixer.abruptRampDownStopCount, 0)
        }
    }

    func testActualNoteOnlyDelayedEmptyRefusedAndInstrumentOnlyRoutesKeepDispatchOwnership() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(linear: linear, cells: [cell(49, 1), cell(50), cell(49, 1), cell(50, 1, 14, 0xD1),
                cell(0, 1), cell(49, 2), cell(49, 3), cell(49, 1)])
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), tick = Int(rate / 50)
            XCTAssertEqual(plan.pattern.events.map(\.scheduledStartFrame), [0, 3, 6, 10, 21].map { $0 * tick })
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 1, 0, 1, 0])
            XCTAssertEqual(plan.noteOnlyEventIndices, [1])
            XCTAssertEqual(plan.xmEmptyRoutes.first?.scheduledFrame, 15 * tick)
            try assertPaths(input, plan: plan, rate: rate)
        } }
    }

    func testRepeatedOneFrameReplacementsReuseTheFixedPoolAndDrainEveryTail() {
        for rate in [44_100.0, 48_000] {
            let n = Int(rate * 0.005), mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            for generation in 0..<2048 {
                if generation > 0 { XCTAssertEqual(mixer.retireSongVoices(channel: 0), 1) }
                let slot = mixer.addVoice(sample: .init(monoPCM: [0.5, -0.25]),
                    playbackStep: 0.25, loop: .init(mode: .forward, startFrame: 0, endFrame: 2), sourceOnsetElapsedFrames: 0)
                mixer.setChannelTag(0, forVoiceAt: slot)
                _ = mixer.render(frames: 1)
                XCTAssertLessThanOrEqual(mixer.activeVoiceCount, n + 1)
                XCTAssertLessThanOrEqual(mixer.loadedVoiceCount, CSoftwareMixer.maximumVoiceCount)
            }
            _ = mixer.render(frames: n)
            XCTAssertEqual(mixer.activeVoiceCount, 1)
            XCTAssertEqual(mixer.rampDownStartCount, 2047)
            XCTAssertEqual(mixer.rampDownCompletionCount, 2047)
            XCTAssertEqual(mixer.abruptRampDownStopCount, 0)
        }
    }

    func testRapidSyntheticGenerationsHaveExactPCMContinuationAndPartitionIndependentLifetimes() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let n = Int(rate * 0.005), starts = [0, n / 2, n / 2 + 17, n / 2 + 34]
            let input = song(linear: linear, cells: [cell(49, 1), cell(50, 1), cell(49, 1), cell(50, 1)])
            let seed = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
            let events = zip(seed.pattern.events, starts).map { old, start in
                SyntheticTrackerEvent(row: 0, scheduledStartFrame: start, sample: old.sample,
                    gain: old.gain, pan: old.pan, playbackStep: old.playbackStep, loop: old.loop)
            }
            let plan = PlaybackSongSyntheticPlan(timingConfig: seed.timingConfig,
                pattern: .init(rowCount: 4, events: events), diagnostics: seed.diagnostics,
                canonicalTickClock: seed.canonicalTickClock, selectionDispatchFacts: .notAdapterProduced)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate, channelCount: 1), frames: starts.last! + n + 2)
            let renderer = R(preparedPlan: plan), result = renderer.render(request)
            XCTAssertEqual(result.sameChannelVoiceLifetime.replacementEvents.map(\.oldEventIndex), [0, 1, 2])
            XCTAssertEqual(result.sameChannelVoiceLifetime.replacementEvents.map(\.completionFrame), starts.dropFirst().map { $0 + n })
            XCTAssertEqual(result.sameChannelVoiceLifetime.maxVoicesPerSourceChannel[0], 4)
            for frame in 0..<result.block.frameCount {
                var expected: Float = 0
                for generation in starts.indices where frame >= starts[generation] {
                    let replaced = generation < 3 ? starts[generation + 1] : Int.max
                    let attack = min(n, min(frame, replaced) - starts[generation])
                    let tail = frame < replaced ? Float(1) : max(0, 1 - Float(frame - replaced) / Float(n))
                    expected += (generation % 2 == 0 ? 0.5 : -0.25) * 0.25 * Float(attack) / Float(n) * tail
                }
                XCTAssertEqual(result.block.interleavedPCM[frame], expected, accuracy: 1e-7)
            }
            try assertPaths(input, plan: plan, rate: rate, request: request)
        } }
    }

    func testColdZeroStepSourceRemainsHeldThroughImportedRetirement() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let instruments = Dictionary(uniqueKeysWithValues: (1...2).map { i in
                (i, PlaybackInstrument(index: i, samples: [.init(instrumentIndex: i, sampleIndex: 0,
                    pcm: (0..<257).map { Float(($0 * 79 + i * 17) % 251 - 125) / 512 }, volume: 0.25,
                    relativeNote: i == 1 ? -1 : 0, finetune: 0, baseSampleRate: 8363,
                    loopStart: 0, loopLength: 257, loopType: 1)], noteSampleMap: Array(repeating: 0, count: 96)))
            })
            let input = PlaybackSong(title: "Original cold held-source retirement",
                orders: [.init(orderIndex: 0, patternIndex: 0)],
                patternsByIndex: [0: .init(index: 0, rows: [
                    .init(index: 0, cells: [cell(1, 1)]), .init(index: 1, cells: [cell(49, 2)])])],
                instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: linear)
            let plan = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.initialHeldPitchEventIndices, [0])
            try assertPaths(input, plan: plan, rate: rate,
                request: .init(song: input, config: .init(sampleRate: rate), rows: 2))
        } }
    }

    func testContinuationStepImportCannotRetuneRenderedRetiringStoppedOrCompletedSources() throws {
        let mixer = CSoftwareMixer(config: .init(sampleRate: 48_000, channelCount: 1))
        let held = mixer.addVoice(sample: .init(monoPCM: [0.5, -0.25]), sourceOnsetElapsedFrames: 0)
        mixer.setChannelTag(0, forVoiceAt: held)
        XCTAssertTrue(mixer.setContinuationPlaybackStep(0, forVoiceAt: held))
        XCTAssertEqual(mixer.retireSongVoices(channel: 0), 1)
        XCTAssertFalse(mixer.setContinuationPlaybackStep(1, forVoiceAt: held))
        let stopped = mixer.addVoice(sample: .init(monoPCM: [0.5]))
        XCTAssertTrue(mixer.stopVoice(at: stopped))
        XCTAssertFalse(mixer.setContinuationPlaybackStep(0, forVoiceAt: stopped))
        let completed = mixer.addVoice(sample: .init(monoPCM: [0.5]))
        _ = mixer.render(frames: 1)
        XCTAssertFalse(mixer.setContinuationPlaybackStep(0, forVoiceAt: completed))
        XCTAssertFalse(mixer.setContinuationPlaybackStep(0, forVoiceAt: held))
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: held)?.sampleStep, 0)
        _ = mixer.render(frames: 240)
        XCTAssertEqual(mixer.activeVoiceCount, 0)
        XCTAssertEqual(mixer.rampDownCompletionCount, 1)
    }

    func testE92HeldAndOrdinaryRowsKeepExactRetirementEndpointsAndCursor() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for delay in [0, 2] {
            let input = retriggerSong(linear: linear, command: 14, parameter: 0x92, delay: delay)
            let plan = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
            let tick = Int(rate / 50), n = Int(rate * 0.005)
            let frames = (stride(from: 2, to: 6 * (delay + 1), by: 2)).map { (6 + $0) * tick }
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 4)
            let renderer = R(preparedPlan: plan), full = renderer.render(request), session = renderer.prepare(request)
            XCTAssertEqual(plan.diagnostics.retriggerEffects.first?.retriggerFrames, frames)
            XCTAssertEqual(plan.pattern.events.count, frames.count + 1)
            XCTAssertEqual(full.sameChannelVoiceLifetime.replacementEvents.map(\.replacementFrame), frames)
            XCTAssertEqual(full.sameChannelVoiceLifetime.replacementEvents.map(\.completionFrame), frames.map { $0 + n })
            #if DEBUG
            var rendered = 0
            for (old, frame) in frames.enumerated() {
                _ = session.render(frames: frame - rendered)
                let before = try XCTUnwrap(session.sourceVoiceForTesting(old))
                XCTAssertTrue(before.active)
                _ = session.render(frames: 1)
                let started = try XCTUnwrap(session.sourceVoiceForTesting(old))
                XCTAssertEqual(started.gainRamp?.songRetirement, true)
                XCTAssertEqual(started.gainRamp?.positionFrame, 1)
                XCTAssertEqual(started.gainRamp?.totalFrames, n)
                XCTAssertEqual(started.sampleStep, before.sampleStep)
                XCTAssertEqual(started.samplePosition, (before.samplePosition + before.sampleStep).truncatingRemainder(dividingBy: 4096), accuracy: 1e-8)
                _ = session.render(frames: n - 1)
                rendered = frame + n
                XCTAssertFalse(try XCTUnwrap(session.sourceVoiceForTesting(old)).active)
            }
            #endif
            try assertPaths(input, plan: plan, rate: rate, request: request)
            var streamed: [Float] = []
            let stream = renderer.renderStreaming(request, chunkFrameCount: 257) { _, _, block in streamed += block.interleavedPCM }
            try stream.controlAdmission.requireSuccess()
            assertSourcePCM(streamed, full.block.interleavedPCM)
            streamed.removeAll(keepingCapacity: true)
            let windows = renderer.renderWindowedStreaming(request, windowRows: 1) { _, _, _, block in streamed += block.interleavedPCM }
            try windows.controlAdmission.requireSuccess()
            assertSourcePCM(streamed, full.block.interleavedPCM)
        } } }
    }

    func testRapidR00CarriesOverlappingOnsetsReleaseAndHeldPitchThroughCheckpoints() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for releasedHeld in [false, true] {
            // Synthetic high-BPM scheduling overlaps genuine 5ms tails; no FT2 header-policy claim.
            let input = retriggerSong(linear: linear, command: 27, parameter: 0, delay: 2,
                bpm: 1000, releasedHeld: releasedHeld)
            let plan = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 5)
            let renderer = R(preparedPlan: plan), full = renderer.render(request)
            XCTAssertGreaterThan(full.sameChannelVoiceLifetime.maxVoicesPerSourceChannel[0] ?? 0, 2)
            #if DEBUG
            let cuts = try XCTUnwrap(plan.diagnostics.retriggerEffects.first?.retriggerFrames)
            let session = renderer.prepare(request), n = Int(rate * 0.005)
            _ = session.render(frames: cuts[1] + 1)
            let oldest = try XCTUnwrap(session.sourceVoiceForTesting(0))
            let previous = try XCTUnwrap(session.sourceVoiceForTesting(1))
            XCTAssertTrue(oldest.active && previous.active)
            XCTAssertEqual(oldest.gainRamp?.positionFrame, cuts[1] + 1 - cuts[0])
            XCTAssertEqual(previous.gainRamp?.positionFrame, 1)
            XCTAssertEqual(previous.sourceOnsetElapsedFrames, cuts[1] - cuts[0])
            XCTAssertEqual(oldest.gainRamp?.songRetirement, true)
            if releasedHeld {
                XCTAssertFalse(oldest.keyOn)
                XCTAssertLessThan(oldest.fadeoutValue, 1)
                XCTAssertEqual(oldest.samplePosition, 0)
                XCTAssertEqual(oldest.sampleStep, 0)
            }
            _ = session.render(frames: cuts[0] + n - cuts[1] - 1)
            XCTAssertFalse(try XCTUnwrap(session.sourceVoiceForTesting(0)).active)
            #endif
            try assertPaths(input, plan: plan, rate: rate, request: request)
        } } }
        let cold = retriggerSong(linear: true, command: 27, parameter: 0, delay: 2, cold: true)
        let result = R().render(.init(song: cold, config: .init(sampleRate: 48_000), rows: 4))
        XCTAssertTrue(result.plan.pattern.events.isEmpty)
        XCTAssertTrue(result.sameChannelVoiceLifetime.replacementEvents.isEmpty)
        XCTAssertTrue(result.block.interleavedPCM.allSatisfy { $0 == 0 })
    }

    private func retriggerSong(linear: Bool, command: UInt8, parameter: UInt8, delay: Int,
                               bpm: Int = 125, releasedHeld: Bool = false, cold: Bool = false) -> PlaybackSong {
        let seed = song(linear: linear, cells: [])
        var instruments = seed.instrumentsByIndex
        if releasedHeld {
            let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.5, count: 4096),
                volume: 0.25, relativeNote: -49, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: 4096, loopType: 1)
            let envelope = PlaybackVolumeEnvelope(enabled: true, points: [.init(tick: 0, value: 64), .init(tick: 64, value: 32)],
                sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 256)
            instruments[1] = .init(index: 1, samples: [sample], volumeEnvelope: envelope, noteSampleMap: Array(repeating: 0, count: 96))
        }
        var rows = [[cold ? cell() : cell(49, 1), cell()]]
        if releasedHeld { rows.append([cell(97), cell()]) }
        rows += [[cell(0, 0, command, parameter), cell(0, 0, 14, UInt8(0xE0 + delay))], [cell(), cell()], [cell(97), cell()]]
        return .init(title: "Original retrigger retirement parity", orders: seed.orders,
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: 6, bpm: bpm), usesLinearFrequencyTable: linear)
    }

    private func assertPaths(_ input: PlaybackSong, plan: PlaybackSongSyntheticPlan, rate: Double,
                             request supplied: PlaybackSongOfflineRenderRequest? = nil) throws {
        let request = supplied ?? .init(song: input, config: .init(sampleRate: rate), rows: 8)
        let renderer = R(preparedPlan: plan), full = renderer.render(request), n = Int(rate * 0.005)
        for rows in [1, 3] {
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, full.block.interleavedPCM)
            XCTAssertEqual(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: rows).block.interleavedPCM,
                full.block.interleavedPCM)
        }
        for chunk in [1, 17, 256, 997] {
            let session = renderer.prepare(request)
            var pcm = [Float](), frame = 0
            while frame < full.block.frameCount {
                let count = min(chunk, full.block.frameCount - frame)
                pcm += session.render(frames: count).interleavedPCM; frame += count
            }
            XCTAssertEqual(pcm, full.block.interleavedPCM)
        }
        #if DEBUG
        let boundaries = Set(plan.pattern.events.flatMap { event in
            [0, 1, n / 2, n - 1, n, n + 1].map { (event.scheduledStartFrame ?? 0) + $0 }
        }).filter { $0 > 0 && $0 < full.block.frameCount }.sorted()
        XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries).block.interleavedPCM,
            full.block.interleavedPCM)
        for replacement in full.sameChannelVoiceLifetime.replacementEvents {
            for age in [1, n / 2, n - 1, n, n + 1] {
                let carries = renderer.continuationsForTesting(plan, at: replacement.replacementFrame + age, config: request.config)
                let carry = carries.first { $0.eventIndex == replacement.oldEventIndex }
                XCTAssertEqual(carry != nil, age < n)
                if let carry {
                    XCTAssertEqual(carry.runtimeState.gainRamp?.positionFrame, age)
                    XCTAssertEqual(carry.runtimeState.gainRamp?.songRetirement, true)
                    let mixer = CSoftwareMixer(config: request.config)
                    let slot = try XCTUnwrap(R.scheduleContinuation(carry, on: mixer).voiceIndex)
                    let state = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slot))
                    XCTAssertEqual(state.gainRamp, carry.runtimeState.gainRamp)
                    XCTAssertEqual(state.sampleStep, carry.playbackStep)
                    XCTAssertEqual(state.samplePosition, carry.runtimeState.samplePosition)
                    _ = mixer.render(frames: n - age)
                    XCTAssertFalse(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slot)).active)
                }
            }
        }
        #endif
    }

    private func target(_ gain: Float, pan: Float = 0, duration: Int = 0) -> PlaybackXMAudibleUpdate {
        .init(eventIndex: 0, channelIndex: 0, source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), tick: 0,
            scheduledFrame: 0, bpm: 125, speed: 3, amplitude: gain, pan: pan, durationFrames: duration,
            intent: "original-retirement-control", rebaseFromCurrent: true)
    }

    private func cell(_ note: UInt8 = 0, _ instrument: UInt8 = 0, _ effect: UInt8 = 0, _ param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: param)
    }

    private func song(linear: Bool, cells: [PlaybackCell]) -> PlaybackSong {
        let samples = (0..<2).map { slot in
            PlaybackSample(instrumentIndex: 1, sampleIndex: slot,
                pcm: Array(repeating: slot == 0 ? 0.5 : -0.25, count: 4096), volume: 0.25,
                relativeNote: 0, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: 4096, loopType: 1)
        }
        var map = Array(repeating: 0, count: 96); map[49] = 1
        let refused = PlaybackSample(instrumentIndex: 3, sampleIndex: 0, pcm: [0.75], volume: 1,
            relativeNote: 127, finetune: 0, baseSampleRate: 8363)
        return .init(title: "Original signed retirement controls", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: samples, noteSampleMap: map),
                2: .init(index: 2, samples: [], noteSampleMap: Array(repeating: 0, count: 96)),
                3: .init(index: 3, samples: [refused], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [2: [.init(sampleIndex: 0, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: true)]])
    }
}
