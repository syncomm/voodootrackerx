import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class InstrumentOnlyVolumeTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testCachedMappedDefaultsAndSourceIdentitySurviveEveryPriorVolumeWriter() {
        let priors = [cell(effect: 12, param: 8), cell(volume: 0x20), cell(effect: 10, param: 2),
            cell(effect: 5, param: 2), cell(effect: 6, param: 2), cell(volume: 0x30, effect: 7, param: 0x48),
            cell(effect: 8, param: 224)]
        for (note, slot, volume, pan): (UInt8, Int, Int, UInt8) in [(37, 0, 64, 64), (49, 1, 24, 192)] {
            for instrument: UInt8 in [1, 2] {
                for prior in priors {
                    let (context, states) = inspect(song([cell(note: note, instrument: 1), prior, cell(instrument: instrument)]))
                    let state = states[2]
                    XCTAssertEqual(state.carriedInstrumentIndex, Int(instrument))
                    XCTAssertEqual(state.activeInstrumentIndex, 1)
                    XCTAssertEqual(state.activeSampleIndex, slot)
                    XCTAssertEqual(state.triggeredSampleDefaultVolume, volume)
                    XCTAssertEqual(state.triggeredSampleDefaultPan, pan)
                    XCTAssertEqual(state.baseChannelVolume, volume)
                    XCTAssertEqual(state.outputChannelVolume, volume)
                    XCTAssertEqual(state.activeSampleVolume, Float(volume) / 64)
                    XCTAssertEqual(state.panningValue, Double(pan))
                    XCTAssertEqual(state.activeEventIndex, 0)
                    XCTAssertEqual(state.volumeSlideMemory, states[1].volumeSlideMemory)
                    XCTAssertEqual(context.events.count, 1)
                    XCTAssertEqual(context.playbackStateEvents.map(\.scheduledFrame), [11_520])
                    XCTAssertEqual(context.playbackStateEvents.map(\.activeEventIndex), [0])
                    XCTAssertEqual(context.voiceStateUpdates.last?.gainAfter, Float(volume * volume) / 4096)
                }
            }
        }
    }

    func testColdAndCompletedVoicesAndLaterExplicitTriggerKeepSeparateMemory() {
        let module = song([cell(instrument: 1), cell(note: 49), cell(note: 49, instrument: 2),
            cell(effect: 12, param: 8), cell(instrument: 1), cell(note: 37, instrument: 1)])
        let (context, states) = inspect(module)
        XCTAssertEqual(states.map(\.baseChannelVolume), [0, 0, 48, 8, 48, 64])
        XCTAssertEqual(states.map(\.carriedInstrumentIndex), [1, 1, 2, 2, 1, 1])
        XCTAssertEqual(states.map(\.activeInstrumentIndex), [nil, 1, 2, 2, 2, 1])
        XCTAssertEqual(context.events.map(\.scheduledStartFrame), [5760, 11_520, 28_800])
        XCTAssertEqual(context.playbackStateEvents.map(\.scheduledFrame), [23_040])
        let pcm = PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: 48_000), rows: 6)).block.interleavedPCM
        XCTAssertTrue(pcm[..<(11_520 * 2)].allSatisfy { $0 == 0 })
        XCTAssertGreaterThan(pcm[(11_520 * 2)..<(12_480 * 2)].map(abs).max() ?? 0, 0)
        // Instrument 2 is a two-frame one-shot. The later instrument-only cell
        // retains its cache but cannot reactivate its completed source.
        XCTAssertTrue(pcm[(12_480 * 2)..<(28_800 * 2)].allSatisfy { $0 == 0 })
    }

    func testSameCellWritersOverrideCachedVolumeAndPan() {
        for (volume, effect, param, expected, pan): (UInt8, UInt8, UInt8, Int, Double) in [
            (0x30, 0, 0, 32, 192), (0, 12, 8, 8, 192), (0, 14, 0xA3, 27, 192),
            (0, 14, 0xB3, 21, 192), (0x93, 0, 0, 27, 192), (0x83, 0, 0, 21, 192),
            (0xC2, 0, 0, 24, 34), (0x30, 8, 224, 32, 224)] {
            let (_, states) = inspect(song([cell(note: 49, instrument: 1), cell(effect: 12, param: 1),
                cell(instrument: 2, volume: volume, effect: effect, param: param)]))
            XCTAssertEqual(states[2].baseChannelVolume, expected)
            XCTAssertEqual(states[2].outputChannelVolume, expected)
            XCTAssertEqual(states[2].panningValue, pan)
            XCTAssertEqual(states[2].triggeredSampleDefaultVolume, 24)
            XCTAssertEqual(states[2].triggeredSampleDefaultPan, 192)
        }
    }

    func testK00RestoresVolumeButReleasesWithoutResetAndK01ResetsBeforeRelease() throws {
        for enabled in [false, true] {
            for volume: UInt8 in [0, 0x30] {
                let module = song([cell(note: 37, instrument: 1), cell(effect: 12, param: 8),
                    cell(instrument: 2, volume: volume, effect: 20), cell(), cell(instrument: 1, effect: 20, param: 1)], envelope: enabled)
                let (context, states) = inspect(module)
                XCTAssertEqual(states[2].baseChannelVolume, volume == 0 ? 64 : 32)
                XCTAssertEqual(context.playbackStateEvents.map(\.scheduledFrame), [23_040])
                let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
                let history = try XCTUnwrap(plan.xmEnvelopeTimeline?.updates)
                let release = try XCTUnwrap(history.first { $0.scheduledFrame == 11_520 })
                XCTAssertFalse(release.state.keyOn)
                XCTAssertEqual(release.state.volumeTick, enabled ? 12 : 0)
                XCTAssertEqual(release.state.panTick, 0) // Existing four-tick loop continues.
                XCTAssertEqual(release.state.fadeoutAccumulator, 31_744)
                let reset = try XCTUnwrap(history.first { $0.scheduledFrame == 23_040 })
                XCTAssertTrue(reset.state.keyOn)
                XCTAssertEqual(reset.state.volumeTick, 0)
                XCTAssertEqual(reset.state.fadeoutAccumulator, 32_768)
                XCTAssertFalse(try XCTUnwrap(history.first { $0.scheduledFrame == 24_000 }).state.keyOn)
                let audible = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == 11_520 })
                XCTAssertEqual(audible.intent, "quick_volume")
                XCTAssertEqual(audible.durationFrames, 240)
            }
        }
        let priority = song([cell(note: 37, instrument: 1), cell(instrument: 2, volume: 0xF0, effect: 20)])
        let plan = Adapter.adapt(priority, orderIndex: 0, sampleRate: 48_000)
        XCTAssertEqual(plan.playbackStateEvents.count, 1)
        XCTAssertTrue(plan.diagnostics.keyOffEvents.isEmpty)
    }

    func testPhaseResetUsesPriorControlsAndRetainsEffectMemory() throws {
        for control: UInt8 in [0, 4] {
            for effect: UInt8 in [4, 7] {
                for suffix in [cell(instrument: 2), cell(instrument: 2, effect: 14, param: effect == 4 ? 0x44 : 0x74),
                               cell(instrument: 2, effect: 20)] {
                    let prefix = [cell(note: 37, instrument: 1, effect: 14, param: (effect << 4) | control),
                        cell(effect: 9, param: 1), cell(effect: 3, param: 2), cell(effect: 10, param: 2),
                        cell(volume: 0x30, effect: effect, param: 0x48)]
                    let (_, states) = inspect(song(prefix + [suffix]))
                    let before = states[4], after = states[5]
                    let phase = effect == 4 ? after.vibratoPhase : after.tremolo.phase
                    let previous = effect == 4 ? before.vibratoPhase : before.tremolo.phase
                    XCTAssertGreaterThan(previous, 0)
                    XCTAssertEqual(phase, control == 4 || suffix.effectType == 20 ? previous : 0)
                    XCTAssertEqual(after.tremolo.speed, before.tremolo.speed)
                    XCTAssertEqual(after.tremolo.depth, before.tremolo.depth)
                    XCTAssertEqual(after.vibratoSpeed, before.vibratoSpeed)
                    XCTAssertEqual(after.vibratoDepth, before.vibratoDepth)
                    XCTAssertEqual(after.volumeSlideMemory, before.volumeSlideMemory)
                    XCTAssertEqual(after.sampleOffsetMemory, before.sampleOffsetMemory)
                    XCTAssertEqual(after.tonePortamentoSpeed, before.tonePortamentoSpeed)
                }
            }
        }
    }

    func testProductionResetFramesTargetsCompletionHoldAndWindowContinuation() throws {
        let cells = [cell(note: 37, instrument: 1), cell(effect: 12, param: 8), cell(note: 97),
            cell(instrument: 2, volume: 0x30, effect: 8, param: 224), cell(), cell(note: 97), cell(instrument: 1), cell()]
        for rate in [44_100.0, 48_000] {
            for profile in MixerMixProfile.allCases {
                let module = song(cells), plan = Adapter.adapt(module, orderIndex: 0, sampleRate: rate)
                let tick = Int(rate / 50), n = tick * 18, d = Int(rate * 0.005)
                XCTAssertEqual(plan.pattern.events.count, 1)
                XCTAssertEqual(plan.playbackStateEvents.map(\.scheduledFrame), [n, tick * 36])
                XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, plan)
                let reset = try XCTUnwrap(plan.xmEnvelopeTimeline?.updates.first { $0.scheduledFrame == n })
                XCTAssertEqual(reset.state, .init())
                let target = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == n })
                XCTAssertEqual(target.amplitude, 0.5)
                XCTAssertEqual(target.durationFrames, d)
                XCTAssertTrue(target.rebaseFromCurrent)
                let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
                let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: cells.count)
                let renderer = PlaybackSongOfflineRenderer(preparedPlan: plan)
                let full = renderer.render(request).block.interleavedPCM
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, full)
                let before = try XCTUnwrap(plan.xmAudibleTimeline?.state(eventIndex: 0, before: n, config: config))
                for (channel, gain) in [config.panLaw.leftGain(for: target.pan), config.panLaw.rightGain(for: target.pan)].enumerated() {
                    let start = before.current[channel + 1], end = target.amplitude * gain
                    for k in [0, 1, d / 2, d, d + 1, tick - 1] {
                        XCTAssertEqual(full[(n + k) * 2 + channel], 0.25 * config.outputScale * (start + (end - start) * min(1, Float(k) / Float(d))), accuracy: 1e-7)
                    }
                }
                let next = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == n + tick })
                XCTAssertEqual(next.durationFrames, tick)
                XCTAssertEqual(next.intent, "ordinary_tick")
                for boundary in [n - 1, n, n + d / 2, n + d, n + d + 1, n + tick, tick * 36 + 1] {
                    let mixer = CSoftwareMixer(config: config)
                    let voice = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 0.25, count: 128)))
                    XCTAssertTrue(mixer.setAudibleOutputState(try XCTUnwrap(plan.xmAudibleTimeline?.state(eventIndex: 0, before: boundary, config: config)), forVoiceAt: voice))
                    PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: voice], on: mixer, windowStartFrame: boundary)
                    XCTAssertEqual(mixer.render(frames: 64).interleavedPCM, Array(full[(boundary * 2)..<((boundary + 64) * 2)]))
                }
                let inert = PlaybackSongOfflineRenderer().render(.init(song: song(cells, panEnvelope: false), config: config, rows: cells.count))
                XCTAssertEqual(inert.block.interleavedPCM, full)
            }
        }
    }

    private func inspect(_ song: PlaybackSong) -> (Adapter.AdapterRowContext, [Adapter.ChannelState]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: 48_000)
        var context = Adapter.AdapterRowContext(), states = [Adapter.ChannelState]()
        for row in traversal.rows {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow), context: &context)
            states.append(context.channelStates[0])
        }
        return (context, states)
    }

    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(_ cells: [PlaybackCell], envelope: Bool = true, panEnvelope: Bool = true) -> PlaybackSong {
        func sample(_ instrument: Int, _ slot: Int, _ volume: Float, _ pan: UInt8, loop: Bool = true) -> PlaybackSample {
            .init(instrumentIndex: instrument, sampleIndex: slot, pcm: Array(repeating: 0.25, count: loop ? 256 : 2),
                volume: volume, panning: pan, relativeNote: 0, finetune: 0, baseSampleRate: 100,
                loopStart: 0, loopLength: loop ? 256 : 0, loopType: loop ? 2 : 0)
        }
        let volume = PlaybackVolumeEnvelope(enabled: envelope,
            points: [(0, 64), (3, 16), (40, 16)].map { .init(tick: $0.0, value: $0.1) },
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: 1024)
        let pan = PlaybackPanningEnvelope(enabled: panEnvelope, points: [.init(tick: 0, value: 0), .init(tick: 4, value: 64)],
            sustainPointIndex: nil, loopStartPointIndex: 0, loopEndPointIndex: 1, typeFlags: panEnvelope ? 5 : 0)
        return .init(title: "Instrument defaults", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample(1, 1, 0.375, 192), sample(1, 0, 1, 64)],
                volumeEnvelope: volume, panningEnvelope: pan,
                noteSampleMap: Array(repeating: 0, count: 48) + Array(repeating: 1, count: 48)),
                2: .init(index: 2, samples: [sample(2, 0, 0.75, 224, loop: false)])],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: true)
    }
}
