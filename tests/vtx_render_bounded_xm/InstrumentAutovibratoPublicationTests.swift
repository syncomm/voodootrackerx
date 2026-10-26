import Foundation
#if canImport(VoodooTrackerXPlaybackSupport)
@testable import VoodooTrackerXPlaybackSupport
#endif
import XCTest

/// Enabled controls exercise actual adapter publication, not a substituted event stream.
final class InstrumentAutovibratoPublicationTests: XCTestCase {
    private typealias K = PlaybackSongInstrumentAutovibratoComposition
    private let rates = [44_100.0, 48_000]
    private func metadata(_ type: UInt8 = 0, depth: UInt8 = 8, rate: UInt8 = 16, sweep: UInt8 = 0) -> PlaybackInstrumentAutoVibrato {
        .init(waveformType: type, sweep: sweep, depth: depth, rate: rate)
    }

    func testAutomaticClockAndCausalRequestRemainCompact() {
        XCTAssertEqual(MemoryLayout<PlaybackSongInstrumentAutovibratoClock.Run>.stride, 48)
        XCTAssertEqual(MemoryLayout<PlaybackSongInstrumentAutovibratoPublication.Request>.stride, 32)
        XCTAssertEqual(MemoryLayout<K.Bounds>.stride, 32)
        XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticAdapter.ChannelState>.stride, 1152)
    }

    func testEnabledBirthFoldsAndBlankTicksPublishIncludingNeutralPhaseRestoration() throws {
        let firstDeltas = [-3, -8, 1, -1]
        for linear in [true, false] { for rate in rates { for type in UInt8(0)...3 {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song([[c(note: 49, instrument: 1)], [c()], [c()]],
                linear: linear, auto: metadata(type)), sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), base = linear ? 4608.0 : 6848
            let bounds = K.Bounds(linear: linear, baseSampleRate: 8363, outputSampleRate: rate)
            let birth = try XCTUnwrap(plan.pattern.events.first)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(birth.playbackStep, bounds.step(period: base, delta: firstDeltas[Int(type)]))
            XCTAssertEqual(plan.diagnostics.eventMappings.first?.linearPeriod, linear ? base : nil)
            XCTAssertEqual(plan.diagnostics.eventMappings.first?.amigaPeriod, linear ? nil : base)
            let trigger = try XCTUnwrap(runtime.events.first { if case .noteTrigger = $0.action { return true }; return false })
            guard case let .noteTrigger(index, event, _) = trigger.action else { return XCTFail("Missing trigger") }
            XCTAssertEqual(index, 0); XCTAssertEqual(event.playbackStep, birth.playbackStep)
            XCTAssertFalse(runtime.events.contains { $0.categories.contains("initial_pitch_hold") })
            if type == 0 {
                // Phase128 restores unmodulated output; phase160 is a new blank-row value.
                for (tick, delta) in [(1, 0), (3, 6)] {
                    let coordinate = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: 1, tick: tick, channel: 0))
                    let updates = steps(runtime.events.filter { $0.scheduledFrame == coordinate.absoluteFrame })
                    XCTAssertEqual(updates.map(\.0), [0])
                    XCTAssertEqual(updates.map(\.1), [try XCTUnwrap(bounds.step(period: base, delta: delta))])
                }
            }
        } } }
    }

    func testOrderedBxThenFourOrSixComposeEachNativeIntermediateWithoutFinalOnlyReplacement() throws {
        for effect: UInt8 in [4, 6] { for linear in [true, false] { for rate in rates {
            let rows = [[c(note: 49, instrument: 1, volume: 0xa4)], [c(effect, effect == 4 ? 0x48 : 0, volume: 0xb8)], [c()]]
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear, auto: metadata()), sampleRate: rate)
            let neutral = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear, auto: .disabled), sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), frame = 8 * Int(rate / 50)
            let children = try XCTUnwrap(plan.diagnostics.vibratoEffects.first).stepUpdates.filter { $0.scheduledFrame == frame }
            let originals = neutral.events.filter { $0.scheduledFrame == frame }
            let requests = runtime.events.filter { $0.scheduledFrame == frame }
            XCTAssertEqual(children.count, 2); XCTAssertEqual(requests.count, 2)
            XCTAssertEqual(requests.map(\.id), originals.map(\.id)); XCTAssertEqual(requests.map(\.categories), originals.map(\.categories))
            let rawChildren = try XCTUnwrap(neutral.plan?.diagnostics.vibratoEffects.first).stepUpdates
                .filter { $0.scheduledFrame == frame }
            XCTAssertEqual(children.map(\.syntheticTick), rawChildren.map(\.syntheticTick))
            XCTAssertEqual(children.map(\.linearPeriodAfter), rawChildren.map(\.linearPeriodAfter))
            XCTAssertEqual(children.map(\.amigaPeriodAfter), rawChildren.map(\.amigaPeriodAfter))
            XCTAssertEqual(children.map(\.vibrato), rawChildren.map(\.vibrato))
            XCTAssertEqual(plan.nativePitchWriterSpans, neutral.plan?.nativePitchWriterSpans)
            let bounds = K.Bounds(linear: linear, baseSampleRate: 8363, outputSampleRate: rate)
            let expected = try children.map { child in
                let period = linear ? child.linearPeriodAfter : try XCTUnwrap(child.amigaPeriodAfter)
                return try XCTUnwrap(bounds.step(period: period, delta: 3))
            }
            XCTAssertNotEqual(expected[0], expected[1]); XCTAssertEqual(steps(requests).map(\.1), expected)
            if linear && rate == 48000 {
                XCTAssertEqual(originals.map(\.id), [3, 4])
                XCTAssertEqual(steps(originals).map(\.1), [10963.0 / 65536, 10835.0 / 65536])
            }
        } } }
    }

    func testDepthAndRateZeroKeepExistingPhysicalEventsExactly() throws {
        for linear in [true, false] { for rate in rates { for effect: UInt8 in [4, 6] {
            for retrigger in [c(14, 0x93), c(27, 2), c(14, 0x93, volume: 0xb8), c(27, 2, volume: 0xb8)] {
            let rows = [[c(note: 49, instrument: 1, volume: 0xa4)],
                [c(effect, effect == 4 ? 0x48 : 0, volume: 0xb8)], [retrigger], [c()]]
            let neutral = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear,
                auto: .disabled, allAutomaticOff: true), sampleRate: rate)
            for raw in [PlaybackInstrumentAutoVibrato.disabled, metadata(1, depth: 0), metadata(1, rate: 0)] {
                // Unused I02 enables the global helper. It grants no pitch changes on I01.
                let actual = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear, auto: raw), sampleRate: rate)
                XCTAssertEqual(actual.events, neutral.events)
                XCTAssertEqual(actual.plan?.pattern.events, neutral.plan?.pattern.events)
            }
        } } } }
    }

    func testRetriggerBirthAndFollowingBlankTicksComposeAroundItsOwnOrdinaryNativePitch() throws {
        for linear in [true, false] { for rate in rates { for effect: UInt8 in [4, 6] {
            for retrigger in [c(14, 0x93), c(27, 2), c(14, 0x93, volume: 0xb8), c(27, 2, volume: 0xb8)] {
            let rows = [[c(note: 49, instrument: 1, volume: 0xa4)],
                [c(effect, effect == 4 ? 0x48 : 0, volume: 0xb8)], [retrigger], [c()], [c(4, 0x48)], [c()]]
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear, auto: metadata()), sampleRate: rate)
            let baseline = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear,
                auto: .disabled, allAutomaticOff: true), sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), neutral = try XCTUnwrap(baseline.plan)
            let bounds = K.Bounds(linear: linear, baseSampleRate: 8363, outputSampleRate: rate)
            let ordered = runtime.eventStorage.ordering.map { runtime.events[$0.eventIndex] }
            // Test-only physical-native oracle: ordinary priority-zero writers can
            // affect an existing generation; every priority-two birth installs its own native pitch.
            var changes = [(frame: Int, priority: Int, generation: Int, native: Double)]()
            for mapping in neutral.diagnostics.eventMappings {
                changes.append((neutral.pattern.events[mapping.eventIndex].scheduledStartFrame ?? 0, 2, mapping.eventIndex,
                    try XCTUnwrap(linear ? mapping.linearPeriod : mapping.amigaPeriod)))
            }
            for command in neutral.diagnostics.vibratoEffects where command.applied {
                guard let generation = command.activeEventIndex else { continue }
                for child in command.stepUpdates {
                    changes.append((child.scheduledFrame, 0, generation,
                        linear ? child.linearPeriodAfter : try XCTUnwrap(child.amigaPeriodAfter)))
                }
            }
            changes.sort { $0.frame != $1.frame ? $0.frame < $1.frame : $0.priority < $1.priority }
            for row in 2...5 { for tick in 0..<6 {
                let coordinate = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: row, tick: tick, channel: 0))
                guard let generation = neutral.pattern.events.indices.last(where: {
                    (neutral.pattern.events[$0].scheduledStartFrame ?? 0) <= coordinate.absoluteFrame
                }), generation > 0 else { continue }
                var bases = [Int: Double]()
                for change in changes where change.frame <= coordinate.absoluteFrame {
                    if change.priority == 2 || bases[change.generation] != nil { bases[change.generation] = change.native }
                }
                let native = try XCTUnwrap(bases[generation])
                let clock = try XCTUnwrap(plan.instrumentAutovibrato(row: row, tick: tick, channel: 0))
                let expected = bounds.step(period: native, delta: K.delta(clock: clock))
                var held: Double?
                for event in ordered where event.scheduledFrame <= coordinate.absoluteFrame {
                    if case let .noteTrigger(index, source, _) = event.action, index == generation { held = source.playbackStep }
                    if case let .stepUpdate(index, step) = event.action, index == generation, held != nil { held = step }
                }
                XCTAssertEqual(held, expected, "birth-native Linear=\(linear) rate=\(rate) effect=\(effect) retrigger=\(retrigger) row=\(row) tick=\(tick)")
                if neutral.pattern.events[generation].scheduledStartFrame == coordinate.absoluteFrame {
                    XCTAssertEqual(plan.pattern.events[generation].playbackStep, expected)
                }
            } }
            let request = PlaybackSongOfflineRenderRequest(song: song(rows, linear: linear, auto: metadata()),
                config: .init(sampleRate: rate, channelCount: 1), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan), whole = renderer.render(request).block.interleavedPCM
            assertPCM(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole)
#if !canImport(VoodooTrackerXPlaybackSupport)
            try assertRuntimePCM(runtime, request: request, expected: whole,
                label: "birth basis Linear=\(linear) rate=\(rate) ordinary=\(effect) retrigger=\(retrigger)", depthOffWitness: {
                    self.song(rows, linear: linear, auto: .disabled, allAutomaticOff: true)
                })
#endif
        } } } }
    }

    func testConvergedFineAndExtraFineNativeAssignmentsStillFeedAutomaticPitch() throws {
        for rate in rates { for effect: UInt8 in [14, 33] {
            let native = effect == 14 || rate == 44100 ? 68 : 80
            let amount = effect == 14 ? 4 : 1, fine = (128 - native) * 2
            let input = song([[c(note: 96, instrument: 1)], [c(effect, 0x11)], [c()]], linear: true,
                auto: metadata(1, rate: 1), speed: 1, firstRelative: 23, firstFinetune: fine, firstBaseRate: 1)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate), plan = try XCTUnwrap(runtime.plan)
            let bounds = K.Bounds(linear: true, baseSampleRate: 1, outputSampleRate: rate)
            XCTAssertEqual(PlaybackSongSyntheticAdapter.playbackStep(linearPeriod: Double(native), baseSampleRate: 1, outputSampleRate: rate),
                PlaybackSongSyntheticAdapter.playbackStep(linearPeriod: Double(native - amount), baseSampleRate: 1, outputSampleRate: rate))
            XCTAssertNotEqual(bounds.step(period: Double(native), delta: -8), bounds.step(period: Double(native - amount), delta: -8))
            XCTAssertTrue(effect == 14 ? plan.diagnostics.finePortamentoUpEffects[0].stepUpdates.isEmpty
                : plan.diagnostics.extraFinePortamentoEffects[0].stepUpdates.isEmpty)
            let frame = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: 1, tick: 0, channel: 0)).absoluteFrame
            XCTAssertEqual(steps(runtime.events.filter { $0.scheduledFrame == frame }).map(\.1),
                [try XCTUnwrap(bounds.step(period: Double(native - amount), delta: -8))])
            try assertTickIntents(runtime, rows: 0..<3, rate: rate, linear: true)
        } }
    }

    func testInactiveAutomaticMetadataPreservesLegacyZeroBirthRetriggerHolds() throws {
        let rows = [[c(note: 1, instrument: 1)], [c(14, 0x93)], [c()]]
        for linear in [true, false] { for rate in rates {
            let baseline = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear,
                auto: .disabled, allAutomaticOff: true, firstRelative: -1), sampleRate: rate)
            XCTAssertEqual(baseline.plan?.initialHeldPitchEventIndices, [0])
            XCTAssertEqual(baseline.plan?.pattern.events.count, 2)
            for raw in [PlaybackInstrumentAutoVibrato.disabled, metadata(1, depth: 0), metadata(1, rate: 0)] {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear,
                    auto: raw, firstRelative: -1), sampleRate: rate)
                XCTAssertEqual(runtime.plan?.initialHeldPitchEventIndices, baseline.plan?.initialHeldPitchEventIndices)
                XCTAssertEqual(runtime.events, baseline.events)
                XCTAssertEqual(runtime.eventStorage.ordering, baseline.eventStorage.ordering)
                XCTAssertEqual(runtime.plan?.pattern.events, baseline.plan?.pattern.events)
            }
        } }
    }

    func testChildlessEqualTargetToneInvocationRestoresNativeBasisAcrossCoarseConversion() throws {
        for rate in rates {
            let native = rate == 44100 ? 144 : 164, fine = (128 - (native - 64)) * 2
            let input = song([[c(note: 96, instrument: 1, volume: 0xa2)], [c(3, 255, note: 95)],
                [c(volume: 0xb1)], [c(3)], [c()]], linear: true, auto: metadata(1, rate: 1), speed: 3,
                firstRelative: 23, firstFinetune: fine, firstBaseRate: 1)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate), plan = try XCTUnwrap(runtime.plan)
            let bounds = K.Bounds(linear: true, baseSampleRate: 1, outputSampleRate: rate)
            XCTAssertTrue(try XCTUnwrap(plan.diagnostics.tonePortamentoEffects.last).stepUpdates.isEmpty)
            XCTAssertEqual(plan.semanticPitch(row: 3, tick: 0, channel: 0)?.output, .known(Double(native + 1)))
            XCTAssertEqual(plan.semanticPitch(row: 3, tick: 1, channel: 0)?.output, .known(Double(native)))
            XCTAssertEqual(PlaybackSongSyntheticAdapter.playbackStep(linearPeriod: Double(native), baseSampleRate: 1, outputSampleRate: rate),
                PlaybackSongSyntheticAdapter.playbackStep(linearPeriod: Double(native + 1), baseSampleRate: 1, outputSampleRate: rate))
            XCTAssertNotEqual(bounds.step(period: Double(native), delta: -8), bounds.step(period: Double(native + 1), delta: -8))
            let frame = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: 3, tick: 1, channel: 0)).absoluteFrame
            XCTAssertEqual(steps(runtime.events.filter { $0.scheduledFrame == frame }).map(\.1),
                [try XCTUnwrap(bounds.step(period: Double(native), delta: -8))])
            try assertTickIntents(runtime, rows: 0..<5, rate: rate, linear: true)
        }
    }

    func testSparseChannelArpeggioExitCarriesItsPhysicalRestorationAcrossAbsentTicks() throws {
        for linear in [true, false] { for rate in rates {
            let rows = [[c(note: 49, instrument: 1), c(note: 49, instrument: 1)],
                [c(), c(0, 0x37)], [c()], [c(), c()]]
            let input = song(rows, linear: linear, auto: metadata())
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate), plan = try XCTUnwrap(runtime.plan)
            XCTAssertNil(plan.canonicalTickClock.coordinate(syntheticRow: 2, tick: 0, channel: 1))
            XCTAssertNil(plan.instrumentAutovibrato(row: 2, tick: 0, channel: 1))
            XCTAssertFalse(plan.instrumentAutovibratoRequests.contains { $0.syntheticRow == 2 && $0.channelIndex == 1 })
            let prior = try XCTUnwrap(plan.instrumentAutovibrato(row: 1, tick: 5, channel: 1))
            let returned = try XCTUnwrap(plan.instrumentAutovibrato(row: 3, tick: 0, channel: 1))
            XCTAssertEqual(K.delta(clock: prior), 8); XCTAssertEqual(K.delta(clock: returned), -7)
            let base = linear ? 4608.0 : 6848
            let bounds = K.Bounds(linear: linear, baseSampleRate: 8363, outputSampleRate: rate)
            let exit = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first?.stepUpdates.last)
            XCTAssertEqual(exit.syntheticTick, 6)
            XCTAssertEqual(linear ? exit.linearPeriodAfter : exit.amigaPeriodAfter, base)
            XCTAssertEqual(exit.playbackStepAfter, bounds.step(period: base, delta: 8))
            let frame = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: 3, tick: 0, channel: 1)).absoluteFrame
            let updates = steps(runtime.events.filter { $0.channelIndex == 1 && $0.scheduledFrame == frame })
            XCTAssertEqual(updates.map(\.0), [1])
            XCTAssertEqual(updates.map(\.1), [try XCTUnwrap(bounds.step(period: base, delta: -7))])
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate, channelCount: 1),
                frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan), whole = renderer.render(request).block.interleavedPCM
            assertPCM(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole)
#if !canImport(VoodooTrackerXPlaybackSupport)
            try assertRuntimePCM(runtime, request: request, expected: whole, label: "sparse exit Linear=\(linear) rate=\(rate)")
#endif
        } }
    }

    func testMalformedPlaybackUsesCappedRateWhileRawClockMetadataRemainsExact() throws {
        let raw = metadata(250, depth: 255, rate: 255)
        for linear in [true, false] { for rate in rates {
            let input = song([[c(note: 49, instrument: 1)], [c()]], linear: linear, auto: raw)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), clock = try XCTUnwrap(plan.instrumentAutovibrato(row: 0, tick: 0, channel: 0))
            XCTAssertEqual(clock.raw, raw); XCTAssertNil(clock.phaseAfter); XCTAssertEqual(clock.status, .policyPending)
            XCTAssertEqual(input.instrumentsByIndex[1]?.autoVibrato, raw)
            let expected = K.Bounds(linear: linear, baseSampleRate: 8363, outputSampleRate: rate)
                .step(period: linear ? 4608 : 6848, delta: -15) // Sanitized rate63 advances before sample.
            XCTAssertEqual(plan.pattern.events.first?.playbackStep, expected)
        } }
    }

    func testMalformedToValidOwnerCarryUsesOnePhaseWhileLegacyAvailabilityWaitsForReset() throws {
        let input = song([[c()]], linear: true, auto: metadata(250, depth: 255, rate: 255))
        var builder = PlaybackSongInstrumentAutovibratoClock.Builder()
        builder.ensureChannels(1); builder.resets[0] = .rowEntry
        builder.publish(channel: 0, ordinal: 0, instrument: 1, song: input)
        let first = try XCTUnwrap(builder.channels[0].last)
        XCTAssertNil(first.result(at: 0).phaseAfter)
        XCTAssertEqual(first.result(at: 0, interpreted: true).phaseAfter, 63)
        builder.publish(channel: 0, ordinal: 3, instrument: 2, song: input)
        let carried = try XCTUnwrap(builder.channels[0].last)
        XCTAssertNil(carried.result(at: 3).phaseAfter)
        XCTAssertEqual(carried.result(at: 3, interpreted: true).phaseBefore, 189)
        XCTAssertEqual(carried.result(at: 3, interpreted: true).phaseAfter, 200)
        builder.resets[0] = .rowEntry; builder.publish(channel: 0, ordinal: 4, instrument: 2, song: input)
        XCTAssertEqual(builder.channels[0].last?.result(at: 4).phaseAfter, 11)
    }

    func testCarriedSelectionRefusedOwnerAndEmptyCompletedSourcesKeepTheirSeparateAuthority() throws {
        for linear in [true, false] { for rate in rates {
            let input = song([[c(note: 49, instrument: 1)], [c(instrument: 2)], [c(note: 53)],
                [c(note: 49, instrument: 4)], [c()], [c(note: 49, instrument: 3)], [c()]], linear: linear, auto: metadata())
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate), plan = try XCTUnwrap(runtime.plan)
            XCTAssertEqual(plan.pattern.events.count, 2)
            let carried = try XCTUnwrap(plan.semanticPitch(row: 1, tick: 0, channel: 0))
            XCTAssertEqual(carried.semanticInstrument, 1); XCTAssertEqual(carried.carriedInstrument, 2)
            XCTAssertEqual(plan.instrumentAutovibrato(row: 1, tick: 0, channel: 0)?.raw, metadata())
            let refused = try XCTUnwrap(plan.semanticPitch(row: 3, tick: 0, channel: 0))
            XCTAssertEqual(refused.associatedGeneration, 1)
            XCTAssertEqual(plan.instrumentAutovibrato(row: 3, tick: 0, channel: 0)?.raw, metadata(1, rate: 11))
            // I04's different rate/relative note is refused; modulation converts the retained I02 PCM at12000.
            let sourceMapping = try XCTUnwrap(plan.diagnostics.eventMappings.first { $0.eventIndex == 1 })
            XCTAssertEqual(sourceMapping.sampleBaseSampleRate, 12000)
            try assertTickIntents(runtime, rows: 0..<5, rate: rate, linear: linear)
            let cut = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: 5, tick: 0, channel: 0))
            XCTAssertNil(plan.semanticPitch(row: 5, tick: 0, channel: 0)?.associatedGeneration)
            XCTAssertTrue(steps(runtime.events.filter { $0.scheduledFrame >= cut.absoluteFrame }).isEmpty)
            for rows in [[[c()], [c()]], [[c(note: 49, instrument: 3)], [c()]]] {
                let silent = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear, auto: metadata()), sampleRate: rate)
                XCTAssertTrue(silent.plan?.pattern.events.isEmpty == true); XCTAssertTrue(steps(silent.events).isEmpty)
            }
            let completed = RuntimeCMixerAdapterEventPlan.make(song: song([[c(note: 49, instrument: 1)], [c()]],
                linear: linear, auto: metadata(), sampleCount: 1), sampleRate: rate)
            XCTAssertEqual(completed.plan?.pattern.events.count, 1)
            XCTAssertTrue(steps(completed.events).isEmpty)
        } }
    }

    func testComposedZeroBirthUsesOneAfterTriggerHoldThenResumesThatGeneration() throws {
        for linear in [true, false] { for rate in rates {
            let rows = [[c(note: 96, instrument: 1)], [c(1, 255)], [c(note: 1, instrument: 2)], [c(2, 1)]]
            let input = song(rows,
                linear: linear, auto: .disabled, speed: 3, secondAuto: metadata(3, rate: 63), secondRelative: -1)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate), plan = try XCTUnwrap(runtime.plan)
            let baseline = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear, auto: .disabled,
                speed: 3, secondRelative: -1, allAutomaticOff: true), sampleRate: rate)
            let frame = 6 * Int(rate / 50), source = try XCTUnwrap(plan.pattern.events.last)
            XCTAssertEqual(plan.pattern.events.count, 2); XCTAssertGreaterThan(source.playbackStep, 0)
            XCTAssertEqual(plan.semanticPitch(row: 2, tick: 0, channel: 0)?.output, .known(linear ? 1 : 4))
            let holds = runtime.events.filter { $0.categories.contains("initial_pitch_hold") }
            XCTAssertEqual(holds.count, 1); XCTAssertEqual(holds.first?.scheduledFrame, frame)
            XCTAssertEqual(steps(holds).map(\.0), [1]); XCTAssertEqual(steps(holds).map(\.1), [0])
            let ordinary: (RuntimeCMixerAdapterEvent) -> Bool = { event in
                guard case .stepUpdate = event.action else { return false }
                return !event.categories.contains("initial_pitch_hold") && !event.categories.contains("instrument_auto_pitch")
            }
            XCTAssertEqual(runtime.events.filter(ordinary).map(\.id), baseline.events.filter(ordinary).map(\.id))
            XCTAssertEqual(runtime.events.filter(ordinary).map(\.categories), baseline.events.filter(ordinary).map(\.categories))
            XCTAssertGreaterThan(try XCTUnwrap(holds.first).id, try XCTUnwrap(baseline.events.map(\.id).max()))
            let ordered = runtime.eventStorage.ordering.filter { slot in
                let event = runtime.events[slot.eventIndex]
                return event.scheduledFrame == frame && (event.categories.contains("note_trigger") || event.categories.contains("initial_pitch_hold"))
            }
            XCTAssertEqual(ordered.map(\.priority), [2, 3])
            let resumeFrame = frame + 2 * Int(rate / 50)
            let expected = try XCTUnwrap(K.Bounds(linear: linear, baseSampleRate: 12000, outputSampleRate: rate)
                .step(period: linear ? 1 : 4, delta: 4))
            XCTAssertEqual(steps(runtime.events.filter { $0.scheduledFrame == resumeFrame }).map(\.1), [expected])
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let voice = mixer.addVoice(sample: source.sample, playbackStep: source.playbackStep, loop: source.loop)
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: 0, playbackStep: 0).wasAccepted)
            XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice, scheduledFrame: resumeFrame - frame, playbackStep: expected).wasAccepted)
            _ = mixer.render(frames: resumeFrame - frame)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, 0)
            _ = mixer.render(frames: 1)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, expected)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate, channelCount: 1),
                frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan), whole = renderer.render(request).block.interleavedPCM
            assertPCM(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole)
#if !canImport(VoodooTrackerXPlaybackSupport)
            try assertRuntimePCM(runtime, request: request, expected: whole, label: "zero birth Linear=\(linear) rate=\(rate)")
#endif
        } }
    }

    func testDisabledRefusedOwnerRestoresRetainedSourceOnceThenBlankTicksStayQuiet() throws {
        for linear in [true, false] { for rate in rates { for off in [metadata(1, depth: 0, rate: 11), metadata(1, rate: 0)] {
            let input = song([[c(note: 49, instrument: 1)], [c(note: 53, instrument: 2)],
                [c(note: 49, instrument: 4)], [c()], [c()]], linear: linear, auto: metadata(), fourthAuto: off)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate), plan = try XCTUnwrap(runtime.plan)
            let coordinate = try XCTUnwrap(plan.canonicalTickClock.coordinate(syntheticRow: 2, tick: 0, channel: 0))
            let pitch = try XCTUnwrap(plan.semanticPitch(row: 2, tick: 0, channel: 0))
            guard case let .known(period) = pitch.output else { return XCTFail("Missing retained native output") }
            XCTAssertEqual(pitch.associatedGeneration, 1); XCTAssertEqual(plan.pattern.events.count, 2)
            let restoration = steps(runtime.events.filter { $0.scheduledFrame == coordinate.absoluteFrame })
            XCTAssertEqual(restoration.map(\.0), [1])
            XCTAssertEqual(restoration.map(\.1), [try XCTUnwrap(K.Bounds(linear: linear, baseSampleRate: 12000, outputSampleRate: rate)
                .step(period: period, delta: 0))])
            XCTAssertTrue(steps(runtime.events.filter { $0.scheduledFrame > coordinate.absoluteFrame }).isEmpty)
        } } }
    }

    func testEnabledLifecycleWholeWindowIndexedScanPreparedAndCachedParity() throws {
        let variants = [c(note: 53), c(instrument: 2), c(14, 0xd0, note: 53, instrument: 2),
            c(14, 0xd3, note: 53, instrument: 2), c(14, 0xd6, note: 53, instrument: 2),
            c(14, 0xd3, instrument: 2), c(14, 0x93), c(14, 0x90), c(27, 2), c(note: 97), c(20, 2)]
        for linear in [true, false] { for rate in rates { for speed in [1, 2, 3, 6] { for target in variants {
            let input = song([[c(note: 49, instrument: 1)], [target], [c()]], linear: linear, auto: metadata(sweep: 16), speed: speed)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate), plan = try XCTUnwrap(runtime.plan)
            try assertTickIntents(runtime, rows: 0..<3, rate: rate, linear: linear)
            let cached = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate, preparedPlan: plan)
            XCTAssertEqual(cached.events, runtime.events); XCTAssertEqual(cached.plan, plan)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate, channelCount: 1), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan), whole = renderer.render(request).block.interleavedPCM
            for size in [1, 2] {
                let indexed = renderer.renderWindowed(request, windowRows: size).block.interleavedPCM
                XCTAssertEqual(indexed, renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: size).block.interleavedPCM)
                assertPCM(indexed, whole)
            }
            let session = renderer.prepare(request), split = min(request.boundedFrameCount / 2, 7 * Int(rate / 50) + 1)
            assertPCM(session.render(frames: split).interleavedPCM + session.render(frames: request.boundedFrameCount - split).interleavedPCM, whole)
#if !canImport(VoodooTrackerXPlaybackSupport)
            try assertRuntimePCM(runtime, request: request, expected: whole,
                label: "Linear=\(linear) rate=\(rate) speed=\(speed) cell=\(target)", depthOffWitness: {
                    self.song([[self.c(note: 49, instrument: 1)], [target], [self.c()]], linear: linear,
                        auto: .disabled, speed: speed, allAutomaticOff: true)
                })
#endif
#if DEBUG
            let scanned = PlaybackSongSyntheticAdapter.adaptUsingScanEligibility(input, orderCount: input.orders.count, sampleRate: rate)
            XCTAssertEqual(scanned, plan)
            let boundary = 2 * speed * Int(rate / 50)
            assertPCM(renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: [boundary - 1, boundary, boundary + 1]).block.interleavedPCM, whole)
#endif
        } } } }
    }

    func testEnabledTicksFollowFxxSpeedBPMAndOrderChanges() throws {
        for linear in [true, false] { for rate in rates { for speed: UInt8 in [1, 2, 3, 6] {
            let rows = [[c(note: 49, instrument: 1), c(15, speed)], [c(), c(15, 137)], [c(), c(15, 3)]]
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear, auto: metadata(), repeated: true), sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan)
            try assertTickIntents(runtime, rows: 0..<6, rate: rate, linear: linear)
            let tickFrames = Set((0..<6).flatMap { row in (0..<6).compactMap { tick in
                plan.canonicalTickClock.coordinate(syntheticRow: row, tick: tick, channel: 0)?.absoluteFrame
            } })
            XCTAssertTrue(runtime.events.filter { if case .stepUpdate = $0.action { return true }; return false }
                .allSatisfy { tickFrames.contains($0.scheduledFrame) })
        } } }
    }

    func testReleasedUnfinishedSweep255KeepsReachedAudibleAmplitudeAndPhase() throws {
        for linear in [true, false] { for rate in rates {
            let input = song([[c(note: 49, instrument: 1)], [c()], [c()], [c(note: 97)], [c()]],
                linear: linear, auto: metadata(1, depth: 15, sweep: 255), sustainedEnvelope: true)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate), plan = try XCTUnwrap(runtime.plan)
            let release = try XCTUnwrap(plan.instrumentAutovibrato(row: 3, tick: 0, channel: 0))
            let later = try XCTUnwrap(plan.instrumentAutovibrato(row: 4, tick: 3, channel: 0))
            XCTAssertTrue(release.released && later.released)
            XCTAssertEqual(release.sweepElapsed, 18); XCTAssertEqual(later.sweepElapsed, 18)
            XCTAssertEqual(K.delta(clock: release), -1); XCTAssertEqual(K.delta(clock: later), 1)
            XCTAssertNotEqual(release.phaseAfter, later.phaseAfter)
            try assertTickIntents(runtime, rows: 0..<5, rate: rate, linear: linear)
        } }
    }

    func testOrdinaryPitchFamiliesPreserveNativeAncestryAndComposeTheirOrderedIntents() throws {
        let cells = [c(3, 1, note: 61), c(1, 1), c(2, 1), c(14, 0x11), c(14, 0x21),
            c(33, 0x11), c(0, 0x37), c(4, 0x48), c(6, 1), c(volume: 0xb8)]
        for linear in [true, false] { for rate in rates { for cell in cells {
            let rows = [[c(note: 49, instrument: 1, volume: 0xa4)], [cell], [c()]]
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear, auto: metadata()), sampleRate: rate)
            let baseline = RuntimeCMixerAdapterEventPlan.make(song: song(rows, linear: linear, auto: .disabled), sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), neutral = try XCTUnwrap(baseline.plan)
            for row in 0..<3 { for tick in 0..<6 {
                XCTAssertEqual(plan.semanticPitch(row: row, tick: tick, channel: 0), neutral.semanticPitch(row: row, tick: tick, channel: 0))
            } }
            try assertTickIntents(runtime, rows: 0..<3, rate: rate, linear: linear)
        } } }
    }

#if !canImport(VoodooTrackerXPlaybackSupport)
    private func assertRuntimePCM(_ runtime: RuntimeCMixerAdapterEventPlan, request: PlaybackSongOfflineRenderRequest,
                                  expected: [Float], label: String, depthOffWitness: (() -> PlaybackSong)? = nil,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = actualRuntimePCM(runtime, request: request, label: label, file: file, line: line)
        let error = zip(actual, expected).map { abs($0 - $1) }.max() ?? 0
        let plan = try XCTUnwrap(runtime.plan), commands = plan.diagnostics.retriggerEffects.filter(\.applied)
        let retirementFrames = Set(commands.flatMap { command in
            Array((command.replacementFrames ?? command.retriggerFrames).prefix(command.replacedEventIndices.count))
        })
        if error > 1e-7, !retirementFrames.isEmpty, let off = depthOffWitness?() {
            // G21 debt is precisely a runtime song-retirement voice (G03's 5 ms)
            // versus offline immediate retrigger cut. Keep every other sample exact.
            XCTAssertTrue(commands.allSatisfy { $0.effectType == 27 || ($0.effectType == 14 && $0.effectParam >> 4 == 9) })
            let baseline = RuntimeCMixerAdapterEventPlan.make(song: off, sampleRate: request.config.sampleRate)
            let baselineRequest = PlaybackSongOfflineRenderRequest(song: off, config: request.config, frames: request.boundedFrameCount)
            let baselinePCM = PlaybackSongOfflineRenderer(preparedPlan: baseline.plan).render(baselineRequest).block.interleavedPCM
            let baselineCore = actualRuntimePCM(baseline, request: baselineRequest, label: label, file: file, line: line)
            let baselineFrames = Set(try XCTUnwrap(baseline.plan).diagnostics.retriggerEffects.filter(\.applied).flatMap {
                Array(($0.replacementFrames ?? $0.retriggerFrames).prefix($0.replacedEventIndices.count))
            })
            XCTAssertEqual(retirementFrames, baselineFrames, label, file: file, line: line)
            var baselineInside: Float = 0, baselineOutside: Float = 0, candidateOutside: Float = 0
            for frame in expected.indices {
                let duration = CSoftwareMixer.songReplacementRampFrameCount(sampleRate: request.config.sampleRate)
                let knownTail = (0..<duration).contains { retirementFrames.contains(frame - $0) }
                let baselineDifference = abs(baselinePCM[frame] - baselineCore[frame])
                if knownTail { baselineInside = max(baselineInside, baselineDifference) }
                else {
                    baselineOutside = max(baselineOutside, baselineDifference)
                    candidateOutside = max(candidateOutside, abs(actual[frame] - expected[frame]))
                }
            }
            XCTAssertGreaterThan(baselineInside, 1e-7, "Depth-off must independently witness existing tail: \(label)", file: file, line: line)
            XCTAssertLessThanOrEqual(baselineOutside, 1e-7, label, file: file, line: line)
            XCTAssertLessThanOrEqual(candidateOutside, 1e-7, label, file: file, line: line)
            try assertRetriggerBirthCursors(runtime, request: request, retirementFrames: retirementFrames, label: label, file: file, line: line)
        } else {
            XCTAssertLessThanOrEqual(error, 1e-7, label, file: file, line: line)
        }
        XCTAssertEqual(actual.count, expected.count, label, file: file, line: line)
    }

    private func assertRetriggerBirthCursors(_ runtime: RuntimeCMixerAdapterEventPlan, request: PlaybackSongOfflineRenderRequest,
        retirementFrames: Set<Int>, label: String, file: StaticString, line: UInt) throws {
        let plan = try XCTUnwrap(runtime.plan), history = PlaybackSongOfflineRenderer.PitchSourceHistory(plan: plan)
        let births = plan.diagnostics.retriggerEffects.filter(\.applied).flatMap {
            Array(zip($0.retriggerEventIndices, $0.retriggerFrames)).filter { retirementFrames.contains($0.1) }
        }
        XCTAssertFalse(births.isEmpty, label, file: file, line: line)
        let core = RuntimeCMixerRenderCore(config: request.config, maximumRenderFrames: 1024,
            outputPolicy: .resolve(environment: [RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"]))
        core.configureAdapterEventScheduleForTesting(runtime.events, runtimeFrameOffset: 0)
        var rendered = 0
        let duration = CSoftwareMixer.songReplacementRampFrameCount(sampleRate: request.config.sampleRate)
        for (generation, start) in births.sorted(by: { $0.1 < $1.1 }) { for offset in [1, 15, duration / 2, duration - 1, duration, duration + 1] {
            let boundary = start + offset
            while rendered < boundary {
                let count = min(997, boundary - rendered); _ = renderRuntimePCM(core, frames: count); rendered += count
            }
            let voice = try XCTUnwrap(core.adapterVoiceDiagnosticForTesting(eventIndex: generation))
            let source = plan.pattern.events[generation]
            XCTAssertEqual(voice.sampleStep, source.playbackStep, label, file: file, line: line)
            XCTAssertEqual(voice.samplePosition, Double(source.initialSourceFrame) + Double(offset) * source.playbackStep,
                accuracy: 1e-9, label, file: file, line: line)
            XCTAssertEqual(voice.samplePosition, try XCTUnwrap(history.advancedPosition(for: generation, at: boundary)),
                accuracy: 1e-9, label, file: file, line: line)
        } }
        XCTAssertTrue(core.drainAppliedAdapterEventDiagnostics().allSatisfy { $0.eventFrameDelta == 0 }, label, file: file, line: line)
    }

    private func actualRuntimePCM(_ runtime: RuntimeCMixerAdapterEventPlan, request: PlaybackSongOfflineRenderRequest,
                                  label: String, file: StaticString, line: UInt) -> [Float] {
        let core = RuntimeCMixerRenderCore(config: request.config, maximumRenderFrames: 1024,
            outputPolicy: .resolve(environment: [RuntimeCMixerOutputPolicy.gainEnvironmentKey: "1"]))
        core.configureAdapterEventScheduleForTesting(runtime.events, runtimeFrameOffset: 0)
        var actual = [Float]()
        while actual.count < request.boundedFrameCount {
            actual += renderRuntimePCM(core, frames: min(997, request.boundedFrameCount - actual.count))
        }
        XCTAssertTrue(core.drainAppliedAdapterEventDiagnostics().allSatisfy { $0.eventFrameDelta == 0 }, label, file: file, line: line)
        return actual
    }
#endif

    private func assertTickIntents(_ runtime: RuntimeCMixerAdapterEventPlan, rows: Range<Int>, rate: Double, linear: Bool,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let plan = try XCTUnwrap(runtime.plan), ordered = runtime.eventStorage.ordering.map { runtime.events[$0.eventIndex] }
        for row in rows { for tick in 0..<6 {
            guard let coordinate = plan.canonicalTickClock.coordinate(syntheticRow: row, tick: tick, channel: 0),
                  let pitch = plan.semanticPitch(row: row, tick: tick, channel: 0), case let .known(period) = pitch.output,
                  let generation = pitch.associatedGeneration,
                  PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: generation, at: coordinate.absoluteFrame, plan: plan),
                  let clock = plan.instrumentAutovibrato(row: row, tick: tick, channel: 0),
                  let mapping = plan.diagnostics.eventMappings.first(where: { $0.eventIndex == generation }) else { continue }
            var held: Double?
            for event in ordered where event.scheduledFrame <= coordinate.absoluteFrame {
                if case let .noteTrigger(index, source, _) = event.action, index == generation { held = source.playbackStep }
                if case let .stepUpdate(index, step) = event.action, index == generation, held != nil { held = step }
            }
            XCTAssertEqual(held, K.Bounds(linear: linear, baseSampleRate: mapping.sampleBaseSampleRate, outputSampleRate: rate)
                .step(period: period, delta: K.delta(clock: clock)), "row\(row) tick\(tick)", file: file, line: line)
        } }
    }

    private func assertPCM(_ actual: [Float], _ expected: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(actual, expected).map { abs($0 - $1) }.max() ?? 0, 1e-7, file: file, line: line)
    }

    private func steps(_ events: [RuntimeCMixerAdapterEvent]) -> [(Int, Double)] {
        events.compactMap { if case let .stepUpdate(index, step) = $0.action { return (index, step) }; return nil }
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ rows: [[PlaybackCell]], linear: Bool, auto: PlaybackInstrumentAutoVibrato,
                      speed: Int = 6, sampleCount: Int = 256, secondAuto: PlaybackInstrumentAutoVibrato? = nil,
                      secondRelative: Int = 0, repeated: Bool = false, sustainedEnvelope: Bool = false,
                      fourthAuto: PlaybackInstrumentAutoVibrato? = nil, allAutomaticOff: Bool = false,
                      firstRelative: Int = 0, firstFinetune: Int = 0, firstBaseRate: Double = 8363) -> PlaybackSong {
        func instrument(_ index: Int, _ count: Int, _ relative: Int, _ base: Double, _ raw: PlaybackInstrumentAutoVibrato) -> PlaybackInstrument {
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0,
                pcm: (0..<count).map { Float(sin(Double($0) * .pi / 8) / 16) }, volume: count == 0 ? 0 : 0.5,
                relativeNote: relative, finetune: index == 1 ? firstFinetune : 0, baseSampleRate: base,
                loopLength: count, loopType: count > 1 ? 1 : 0)
            var samples = [sample], map = Array(repeating: 0, count: 96)
            if index == 1 {
                samples.append(.init(instrumentIndex: 1, sampleIndex: 1, pcm: sample.pcm, volume: 0.5,
                    relativeNote: 0, finetune: 0, baseSampleRate: 16726, loopLength: count, loopType: count > 1 ? 1 : 0))
                map[52] = 1 // Note-only 53 resolves this exact destination and its distinct rate.
            }
            let envelope = sustainedEnvelope ? PlaybackVolumeEnvelope(enabled: true, points: [.init(tick: 0, value: 64)],
                sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 0) : .disabled
            return .init(index: index, samples: samples, volumeEnvelope: envelope,
                autoVibrato: allAutomaticOff ? .disabled : raw, noteSampleMap: map)
        }
        return .init(title: "Public enabled instrument automatic pitch", orders: (0..<(repeated ? 2 : 1)).map { .init(orderIndex: $0, patternIndex: 0) },
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: [1: instrument(1, sampleCount, firstRelative, firstBaseRate, auto),
                2: instrument(2, 256, secondRelative, 12000, secondAuto ?? metadata(1, rate: 11)),
                3: instrument(3, 0, 0, 48000, metadata(1)), 4: instrument(4, 256, 80, 48000, fourthAuto ?? metadata(1, rate: 11))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [3: [.init(sampleIndex: 0, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true,
                volume: 0, panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
