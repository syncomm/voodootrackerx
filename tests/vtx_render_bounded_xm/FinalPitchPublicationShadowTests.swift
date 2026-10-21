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
