import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Test-only algebra experiment; neither projection is installed in a product plan.
final class FinalPitchPublicationShadowTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer
    private struct Key: Hashable { let generation: Int; let frame: Int }
    private struct Writer: Equatable {
        let family: Int, generation: Int, frame: Int, tick: Int, ordinal: Int
        let step: Double
        var key: Key { .init(generation: generation, frame: frame) }
    }

    func testSevenFamilyDepthOffProjectionPreservesFinalStepsCursorsAndPitchOnlyPCM() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song([c(note: 49, instrument: 1), c(3, 4, note: 53), c(1, 3), c(2, 2),
                c(14, 0x11), c(14, 0x21), c(33, 0x11), c(0, 0x37), c(4, 0x21),
                c(4, 0x56, volume: 0xB3), c(6, 2), c(14, 0x44), c()], linear: linear)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let raw = writers(plan), final = coalesce(raw)
            XCTAssertEqual(Set(raw.map(\.family)), Set(0..<7))
            XCTAssertLessThan(final.count, raw.count)
            for group in Dictionary(grouping: raw, by: \.key).values {
                XCTAssertEqual(final.first { $0.key == group[0].key }, group.last)
            }
            let mixed = try XCTUnwrap(plan.diagnostics.vibratoEffects.first { $0.syntheticRow == 9 })
            XCTAssertEqual(mixed.stepUpdates.map(\.syntheticTick), [1,1,2,2,3,3,4,4,5,5])
            XCTAssertNotEqual(mixed.stepUpdates[0].playbackStepAfter, mixed.stepUpdates[1].playbackStepAfter)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate, preparedPlan: plan)
            let delivered = runtime.events.compactMap { event -> Key? in
                guard case let .stepUpdate(generation, _) = event.action else { return nil }
                return .init(generation: generation, frame: event.scheduledFrame)
            }
            XCTAssertEqual(delivered, raw.map(\.key))
            XCTAssertEqual(runtime.events.compactMap { event -> Double? in
                guard case let .stepUpdate(_, step) = event.action else { return nil }; return step
            }, raw.map(\.step))
            try checkCursors(plan, raw: raw, final: final)
            // Isolate pitch delivery: this harness intentionally omits volume/release/retirement.
            XCTAssertEqual(try pitchPCM(plan, raw), try pitchPCM(plan, final))
            let before = plan.diagnostics
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 13)
            let renderer = R(preparedPlan: plan), whole = renderer.render(request).block.interleavedPCM
            let window = renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM
            XCTAssertLessThanOrEqual(zip(whole, window).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            XCTAssertEqual(whole.count, window.count)
            XCTAssertEqual(plan.diagnostics, before) // Intermediate writers and their memories survive.
        } }
    }

    func testLifecycleProjectionKeepsGenerationsAndStrictBeforeHistorySeparate() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for completed in [false, true] {
            let input = song([c(14, 0x10), c(note: 49, instrument: 1), c(4, 0x48),
                c(instrument: 1), c(note: 53), c(14, 0xD3, note: 49), c(14, 0x93), c(27, 0x93),
                c(note: 49, instrument: 2), c(note: 50, instrument: 1), c(33, 0x10), c(note: 49)],
                linear: linear, completed: completed)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let raw = writers(plan)
            XCTAssertFalse(plan.pattern.events.isEmpty)
            XCTAssertFalse(plan.pattern.events.contains { $0.row == 0 || $0.row == 8 || $0.row == 9 })
            XCTAssertFalse(plan.xmEmptyRoutes.isEmpty)
            XCTAssertTrue(plan.diagnostics.finePortamentoUpEffects.first?.stepUpdates.isEmpty == true)
            try checkCursors(plan, raw: raw, final: coalesce(raw))
            let history = R.PitchSourceHistory(plan: plan)
            for route in plan.xmEmptyRoutes {
                if let source = route.stoppedEventIndex {
                    XCTAssertFalse(R.hasActiveSource(eventIndex: source, at: route.scheduledFrame,
                        plan: plan, pitchHistory: history))
                }
            }
        } } }
    }

    func testHypotheticalBirthValueMustBeInTriggerAndZeroBirthRetainsExistingHold() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song([c(note: 49, instrument: 1)], linear: linear)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let birth = try XCTUnwrap(runtime.events.first { if case .noteTrigger = $0.action { return true }; return false })
            guard case let .noteTrigger(index, event, mapping) = birth.action else { return XCTFail("Missing trigger") }
            // Arbitrary authored period offset proves folding, without an autovibrato algorithm.
            let step = try XCTUnwrap(linear ? A.playbackStep(linearPeriod: 4616, baseSampleRate: 8363, outputSampleRate: rate)
                : A.playbackStep(amigaPeriod: 6880, baseSampleRate: 8363, outputSampleRate: rate))
            let misplaced = RuntimeCMixerAdapterEvent(id: birth.id + 1, source: birth.source, channelIndex: 0,
                syntheticTick: birth.syntheticTick, scheduledFrame: birth.scheduledFrame,
                action: .stepUpdate(activeEventIndex: index, playbackStep: step), categories: ["step_update"])
            let storage = RuntimeCMixerAdapterEventStorage(events: [birth, misplaced])
            XCTAssertEqual(storage.ordering.first?.eventIndex, 1) // Real priority puts it before creation.
            let folded = SyntheticTrackerEvent(row: event.row, tick: event.tick, scheduledStartFrame: event.scheduledStartFrame,
                sample: event.sample, gain: event.gain, pan: event.pan, playbackStep: step, loop: event.loop)
            let action = RuntimeCMixerAdapterEventAction.noteTrigger(eventIndex: index, event: folded, mapping: mapping)
            guard case let .noteTrigger(_, value, _) = action else { return XCTFail("Missing folded intent") }
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let voice = mixer.addVoice(sample: value.sample, playbackStep: value.playbackStep, loop: value.loop)
            _ = mixer.render(frames: 1)
            XCTAssertEqual(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice)).samplePosition, step)
            let cold = song([c(note: 49, instrument: 1), c(14, 0x11)], linear: linear, relative: -49)
            let held = RuntimeCMixerAdapterEventPlan.make(song: cold, sampleRate: rate)
            let plan = try XCTUnwrap(held.plan)
            XCTAssertEqual(plan.initialHeldPitchEventIndices, [0])
            let triggerSlot = try XCTUnwrap(held.events.firstIndex { if case .noteTrigger = $0.action { return true }; return false })
            let holdSlot = try XCTUnwrap(held.events.firstIndex { $0.categories.contains("initial_pitch_hold") })
            XCTAssertGreaterThan(holdSlot, triggerSlot)
            XCTAssertEqual(SyntheticTrackerEvent(row: 0, sample: event.sample, playbackStep: 0).playbackStep, 1)
            let raw = writers(plan)
            try checkCursors(plan, raw: raw, final: coalesce(raw))
            let resume = try XCTUnwrap(raw.first { $0.generation == 0 && $0.step > 0 })
            let history = R.PitchSourceHistory(plan: plan)
            XCTAssertEqual(history.advancedPosition(for: 0, at: resume.frame), 0)
            XCTAssertEqual(history.advancedPosition(for: 0, at: resume.frame + 1), resume.step)
        } }
    }

    func testZeroStepHoldResumeAndSameFrameGenerationSeparation() throws {
        for rate in [44_100.0, 48_000] {
            let plan = A.adapt(song([c(4, 0x4F, note: 95, instrument: 1), c(4), c(4), c(4)],
                linear: false, fine: 8), orderIndex: 0, sampleRate: rate)
            let raw = writers(plan), history = R.PitchSourceHistory(plan: plan)
            let hold = try XCTUnwrap(raw.first { $0.step == 0 })
            let resume = try XCTUnwrap(raw.first { $0.frame > hold.frame && $0.step > 0 })
            XCTAssertEqual(history.advancedPosition(for: 0, at: hold.frame + 1), history.advancedPosition(for: 0, at: resume.frame))
            try checkCursors(plan, raw: raw, final: coalesce(raw))
            XCTAssertEqual(try pitchPCM(plan, raw), try pitchPCM(plan, coalesce(raw)))
            let pair = [Writer(family: 6, generation: 0, frame: 0, tick: 0, ordinal: 0, step: 0),
                Writer(family: 6, generation: 1, frame: 0, tick: 0, ordinal: 1, step: resume.step)]
            XCTAssertEqual(coalesce(pair), pair) // A channel/frame key alone would lose a generation.
        }
    }

    private func writers(_ plan: PlaybackSongSyntheticPlan) -> [Writer] {
        var result = [Writer]()
        func append(_ family: Int, _ source: Int?, _ applied: Bool, _ steps: [PlaybackSongSyntheticTonePortamentoStepUpdate]) {
            guard applied, let source else { return }
            for step in steps {
                result.append(.init(family: family, generation: source, frame: step.scheduledFrame,
                    tick: step.syntheticTick, ordinal: result.count, step: step.playbackStepAfter))
            }
        }
        let d = plan.diagnostics
        for x in d.tonePortamentoEffects { append(0, x.activeEventIndex, x.applied, x.stepUpdates) }
        for x in d.portamentoSlideEffects { append(1, x.activeEventIndex, x.applied, x.stepUpdates) }
        for x in d.finePortamentoUpEffects { append(2, x.activeEventIndex, x.applied && !x.appliedToInitialPlaybackStep, x.stepUpdates) }
        for x in d.finePortamentoDownEffects { append(3, x.activeEventIndex, x.applied && !x.appliedToInitialPlaybackStep, x.stepUpdates) }
        for x in d.extraFinePortamentoEffects { append(4, x.activeEventIndex, x.applied && !x.appliedToInitialPlaybackStep, x.stepUpdates) }
        for x in d.arpeggioEffects { append(5, x.activeEventIndex, x.applied, x.stepUpdates) }
        for x in d.vibratoEffects { append(6, x.activeEventIndex, x.applied, x.stepUpdates) }
        return result.sorted {
            if $0.frame != $1.frame { return $0.frame < $1.frame }
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            return $0.ordinal < $1.ordinal
        }
    }

    private func coalesce(_ raw: [Writer]) -> [Writer] {
        var last = [Key: Int]()
        for (index, writer) in raw.enumerated() { last[writer.key] = index }
        // Keep every distinct frame, even when steps equal: Double integration retains its boundaries.
        return raw.enumerated().compactMap { last[$0.element.key] == $0.offset ? $0.element : nil }
    }

    private func checkCursors(_ plan: PlaybackSongSyntheticPlan, raw: [Writer], final: [Writer]) throws {
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig), history = R.PitchSourceHistory(plan: plan)
        let frames = Set((raw.map(\.frame) + plan.diagnostics.rowTiming.map(\.rowStartFrame)).flatMap { [max(0, $0 - 1), $0, $0 + 1] })
        for (index, event) in plan.pattern.events.enumerated() {
            let start = scheduler.frame(for: event)
            func position(_ points: [Writer], at frame: Int) -> Double {
                var cursor = start, position = Double(event.initialSourceFrame)
                var step = plan.initialHeldPitchEventIndices.contains(index) ? 0 : event.playbackStep
                for point in points where point.generation == index && point.frame > start && point.frame < frame {
                    position += Double(point.frame - cursor) * step; cursor = point.frame; step = point.step
                }
                return position + Double(max(0, frame - cursor)) * step
            }
            for frame in frames where frame >= start {
                XCTAssertEqual(position(raw, at: frame), position(final, at: frame))
                XCTAssertEqual(position(final, at: frame), try XCTUnwrap(history.advancedPosition(for: index, at: frame)))
                XCTAssertEqual(R.hasActiveSource(eventIndex: index, at: frame, plan: plan),
                    R.hasActiveSource(eventIndex: index, at: frame, plan: plan, pitchHistory: history))
            }
        }
    }

    private func pitchPCM(_ plan: PlaybackSongSyntheticPlan, _ points: [Writer]) throws -> [Float] {
        let mixer = CSoftwareMixer(config: .init(sampleRate: plan.timingConfig.sampleRate, channelCount: 1))
        let scheduler = SyntheticTrackerScheduler(config: plan.timingConfig)
        var voices = [Int: Int]()
        for (index, event) in plan.pattern.events.enumerated() {
            voices[index] = mixer.addScheduledVoice(sample: event.sample, scheduledStartFrame: scheduler.frame(for: event),
                playbackStep: event.playbackStep, loop: event.loop, initialSourceFrame: event.initialSourceFrame)
        }
        for point in points {
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: try XCTUnwrap(voices[point.generation]),
                scheduledFrame: point.frame, playbackStep: point.step).wasAccepted)
        }
        return mixer.render(frames: (points.last?.frame ?? 0) + 64).interleavedPCM
    }

    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ cells: [PlaybackCell], linear: Bool, completed: Bool = false, relative: Int = 0, fine: Int = 0) -> PlaybackSong {
        func sample(_ instrument: Int, _ tuning: Int) -> PlaybackSample {
            .init(instrumentIndex: instrument, sampleIndex: 0, pcm: [0, 0.25, -0.125, -0.5, 0.125, 0.375, -0.25, 0.0625],
                volume: 0.5, relativeNote: tuning, finetune: fine, baseSampleRate: 8363,
                loopLength: completed ? 0 : 8, loopType: completed ? 0 : 1)
        }
        var map = Array(repeating: 0, count: 96); map[49] = 1
        return .init(title: "Public final-pitch shadow", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample(1, relative)],
                autoVibrato: .init(waveformType: 1, sweep: 16, depth: 0, rate: 13), noteSampleMap: map),
                2: .init(index: 2, samples: [sample(2, 96)], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true,
                volume: 0, panning: 0, finetune: 0, relativeNote: 0)]])
    }
}

/// Public R02 controls use distinct, asymmetric sources so restoring the wrong phase is audible.
final class OrdinaryReplacementOfflineParityTests: XCTestCase {
    private typealias R = PlaybackSongOfflineRenderer

    func testOrdinaryReplacementPreservesWholeIndexedScanAndPreparedPCM() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for loop in [1, 2] { for modulation in 0...2 {
                let input = song(linear: linear, loop: loop, modulation: modulation)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
                let plan = try XCTUnwrap(runtime.plan)
                let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 4)
                let renderer = R(preparedPlan: plan), whole = renderer.render(request)
                let replacement = try XCTUnwrap(whole.sameChannelVoiceLifetime.replacementEvents.first)
                let reference = try physicalReference(runtime, config: request.config, frames: whole.block.frameCount)
                assertPCM(whole.block.interleavedPCM, reference)
                XCTAssertEqual(replacement.oldEventIndex, 0)
                XCTAssertEqual(replacement.newEventIndex, 1)
                XCTAssertEqual(replacement.replacementFrame, 12 * Int(rate / 50))
                XCTAssertEqual(replacement.completionFrame, replacement.replacementFrame + 32)
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), [1, 2])
                XCTAssertNotEqual(plan.pattern.events[0].sample, plan.pattern.events[1].sample)
                for rows in [1, 2, 3] {
                    let indexed = renderer.renderWindowed(request, windowRows: rows)
                    let scan = renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: rows)
                    assertPCM(indexed.block.interleavedPCM, reference)
                    XCTAssertEqual(indexed.block.interleavedPCM, scan.block.interleavedPCM)
                }
                // Chunking a live session does not reconstruct voices and is an independent control.
                let session = renderer.prepare(request)
                let cuts = [replacement.replacementFrame, replacement.replacementFrame + 1,
                    replacement.replacementFrame + 15, replacement.replacementFrame + 30,
                    replacement.replacementFrame + 31, replacement.replacementFrame + 32, whole.block.frameCount]
                var previous = 0, prepared = [Float]()
                for cut in cuts {
                    prepared += session.render(frames: cut - previous).interleavedPCM
                    previous = cut
                }
                assertPCM(prepared, reference)
#if DEBUG
                for boundaries in [Array(cuts.dropLast()), [replacement.replacementFrame + 1],
                    [replacement.replacementFrame + 15], [replacement.replacementFrame + 30],
                    [replacement.replacementFrame + 31], [replacement.replacementFrame + 32]] {
                    let split = renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries)
                    assertPCM(split.block.interleavedPCM, reference)
                }
#endif
            } }
        } }
    }

    func testReplacementBoundaryCarriesPhysicalOldGenerationStepAndCursor() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for loop in [1, 2] { for modulation in 0...2 {
                let input = song(linear: linear, loop: loop, modulation: modulation)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
                let plan = try XCTUnwrap(runtime.plan), old = plan.pattern.events[0]
                let boundary = 12 * Int(rate / 50)
                let mixer = CSoftwareMixer(config: .init(sampleRate: rate))
                let voice = mixer.addVoice(sample: old.sample, gain: old.gain, pan: old.pan,
                    playbackStep: old.playbackStep, loop: old.loop)
                // Deliver real physical requests in runtime order, retaining every writer.
                var finalStep = old.playbackStep
                for ordered in runtime.eventStorage.ordering {
                    let event = runtime.events[ordered.eventIndex]
                    guard event.scheduledFrame < boundary,
                          case let .stepUpdate(generation, step) = event.action, generation == 0 else { continue }
                    XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice,
                        scheduledFrame: event.scheduledFrame, playbackStep: step).wasAccepted)
                    finalStep = step
                }
                _ = mixer.render(frames: boundary)
                let physical = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                XCTAssertEqual(physical.sampleStep, finalStep)
                if modulation != 0 { XCTAssertNotEqual(finalStep, old.playbackStep) }
                let renderer = R(preparedPlan: plan)
                let index = renderer.makeWindowedRenderScheduleIndex(for: plan,
                    totalFrames: boundary + Int(rate / 50) * 12, windowRows: 1,
                    includedEventIndices: nil, config: .init(sampleRate: rate))
                let bucket = try XCTUnwrap(index.windows.first { $0.startFrame == boundary })
                let carry = try XCTUnwrap(bucket.continuations.first { $0.eventIndex == 0 })
                XCTAssertEqual(bucket.scheduledEvents.map(\.eventIndex), [1])
                XCTAssertEqual(carry.event.sample, old.sample)
                XCTAssertEqual(carry.playbackStep, physical.sampleStep)
                XCTAssertEqual(carry.runtimeState.samplePosition, physical.samplePosition, accuracy: 1e-8)
                XCTAssertEqual(carry.runtimeState.pingPongDirection, physical.pingPongDirection)
                XCTAssertEqual(carry.runtimeState.keyOn, physical.keyOn)
                XCTAssertEqual(carry.runtimeState.fadeoutValue, physical.fadeoutValue)
                XCTAssertNil(carry.runtimeState.gainRamp) // The N publication remains queued locally at zero.
            } }
        } }
    }

    func testCompletedOldSourceIsNeverRestoredDuringReplacementTail() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(linear: linear, loop: 0, modulation: 1)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 4)
            let renderer = R(), whole = renderer.render(request)
            let boundary = 12 * Int(rate / 50)
            let index = renderer.makeWindowedRenderScheduleIndex(for: whole.plan,
                totalFrames: whole.block.frameCount, windowRows: 1, includedEventIndices: nil, config: request.config)
            for bucket in index.windows where bucket.startFrame >= boundary {
                XCTAssertFalse(bucket.continuations.contains { $0.eventIndex == 0 })
            }
            assertPCM(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole.block.interleavedPCM)
#if DEBUG
            assertPCM(renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [boundary, boundary + 1, boundary + 15, boundary + 30, boundary + 31, boundary + 32])
                .block.interleavedPCM, whole.block.interleavedPCM)
#endif
        } }
    }

    func testAmigaZeroHoldResumeRetainsRetiringPitchAcrossExactSplits() throws {
        for rate in [44_100.0, 48_000] { for loop in [1, 2] {
            let input = song(linear: false, loop: loop, modulation: 3)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let n = 24 * Int(rate / 50)
            let steps = runtime.eventStorage.ordering.compactMap { ordered -> Double? in
                let event = runtime.events[ordered.eventIndex]
                guard event.scheduledFrame < n,
                      case let .stepUpdate(generation, step) = event.action, generation == 0 else { return nil }
                return step
            }
            let held = try XCTUnwrap(steps.firstIndex(of: 0))
            XCTAssertTrue(steps.dropFirst(held + 1).contains { $0 > 0 })
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), frames: n + 64)
            let renderer = R(preparedPlan: try XCTUnwrap(runtime.plan))
            let reference = try physicalReference(runtime, config: request.config, frames: request.boundedFrameCount)
            assertPCM(renderer.render(request).block.interleavedPCM, reference)
#if DEBUG
            assertPCM(renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [n, n + 1, n + 15, n + 30, n + 31, n + 32]).block.interleavedPCM, reference)
#endif
        } }
    }

    private func physicalReference(_ runtime: RuntimeCMixerAdapterEventPlan, config: MixerRenderConfig,
                                   frames: Int) throws -> [Float] {
        let plan = try XCTUnwrap(runtime.plan), old = plan.pattern.events[0], new = plan.pattern.events[1]
        let n = try XCTUnwrap(new.scheduledStartFrame), mixer = CSoftwareMixer(config: config)
        let voice = mixer.addVoice(sample: old.sample, gain: old.gain, pan: old.pan,
            playbackStep: old.playbackStep, loop: old.loop, sourceOnsetElapsedFrames: 0)
        mixer.setChannelTag(0, forVoiceAt: voice)
        // Runtime enqueues the same-frame old writer before channel retirement cancels it.
        for ordered in runtime.eventStorage.ordering {
            let event = runtime.events[ordered.eventIndex]
            guard event.scheduledFrame <= n,
                  case let .stepUpdate(generation, step) = event.action, generation == 0 else { continue }
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice,
                scheduledFrame: event.scheduledFrame, playbackStep: step).wasAccepted)
        }
        var pcm = mixer.render(frames: n).interleavedPCM
        let frozen = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
        XCTAssertEqual(mixer.rampDownVoices(channel: 0, rampFrames: 32), 1)
        _ = mixer.addVoice(sample: new.sample, gain: new.gain, pan: new.pan,
            playbackStep: new.playbackStep, loop: new.loop, sourceOnsetElapsedFrames: 0)
        var elapsed = 0
        for offset in [0, 1, 15, 30, 31, 32, frames - n] {
            pcm += mixer.render(frames: offset - elapsed).interleavedPCM
            elapsed = offset
            let state = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertEqual(state.sampleStep, frozen.sampleStep)
            XCTAssertEqual(state.active, offset < 32)
#if DEBUG
            let carry = R().continuationsForTesting(plan, at: n + offset, config: config)
                .first { $0.eventIndex == 0 }
            XCTAssertEqual(carry != nil, offset < 32)
            if let carry {
                XCTAssertEqual(carry.playbackStep, state.sampleStep)
                XCTAssertEqual(carry.runtimeState.samplePosition, state.samplePosition, accuracy: 1e-8)
                XCTAssertEqual(carry.runtimeState.pingPongDirection, state.pingPongDirection)
                XCTAssertEqual(carry.runtimeState.keyOn, state.keyOn)
                XCTAssertEqual(carry.runtimeState.fadeoutValue, state.fadeoutValue)
                if offset > 0 { XCTAssertEqual(carry.runtimeState.gainRamp, state.gainRamp) }
                let restored = CSoftwareMixer(config: config)
                let result = R.scheduleContinuation(carry, on: restored)
                let diagnostic = try XCTUnwrap(restored.voiceDiagnostic(forVoiceAt: try XCTUnwrap(result.voiceIndex)))
                XCTAssertEqual(diagnostic.samplePosition, state.samplePosition, accuracy: 1e-8)
                XCTAssertEqual(diagnostic.pingPongDirection, state.pingPongDirection)
            }
#endif
            if offset < 32 {
                let ramp = try XCTUnwrap(state.gainRamp)
                XCTAssertEqual(ramp.totalFrames, 32)
                XCTAssertEqual(ramp.positionFrame, offset)
                XCTAssertEqual(ramp.target, 0)
                XCTAssertTrue(ramp.deactivateAfterRamp)
            }
        }
        return pcm
    }

    private func assertPCM(_ actual: [Float], _ expected: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        let first = zip(actual, expected).enumerated().first { abs($0.element.0 - $0.element.1) > 1e-7 }
        let maximum = zip(actual, expected).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThanOrEqual(maximum, 1e-7, "first differing interleaved sample: \(String(describing: first?.offset))", file: file, line: line)
    }

    private func song(linear: Bool, loop: Int, modulation: Int) -> PlaybackSong {
        func cell(_ note: UInt8 = 0, _ instrument: UInt8 = 0, effect: UInt8 = 0,
                  parameter: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
            .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
        }
        func instrument(_ index: Int, count: Int, multiplier: Int, pan: UInt8) -> PlaybackInstrument {
            let pcm = (0..<count).map { Float((($0 * multiplier + $0 * $0 * 13) % 49_157) - 24_578) / 32_768 }
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0, pcm: pcm, volume: 0.5,
                panning: pan, relativeNote: 0, finetune: modulation == 3 && index == 1 ? 8 : 0, baseSampleRate: 8363,
                loopStart: 7, loopLength: count - 14, loopType: loop)
            return .init(index: index, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))
        }
        // Bx uses remembered 4xy speed; both modulation controls precede the distinct replacement.
        let rows = [cell(modulation == 3 ? 95 : 49, 1, effect: modulation >= 2 ? 4 : 0,
            parameter: modulation == 3 ? 0x4F : modulation == 2 ? 0x48 : 0),
            cell(effect: modulation == 1 || modulation == 3 ? 4 : 0, parameter: modulation == 1 ? 0x48 : 0,
                volume: modulation == 2 ? 0xB3 : 0)]
            + (modulation == 3 ? [cell(effect: 4), cell(effect: 4)] : []) + [cell(61, 2), cell()]
        return .init(title: "Public R02 ordinary replacement", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: instrument(1, count: 257, multiplier: 149, pan: 112),
                2: instrument(2, count: 347, multiplier: 311, pan: 160)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125),
            usesLinearFrequencyTable: linear)
    }
}
