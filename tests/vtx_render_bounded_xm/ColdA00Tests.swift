import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class ColdA00Tests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testColdRestorationAtNativeAndSameRowFxxSpeeds() throws {
        // Original controls measured against pinned FT2 87be425; no reference code/tables.
        for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] {
                for fxx in [false, true] {
                    let module = song([[c(note: 49, instrument: 1)], [c(7, 0x48)],
                                       [c(10), fxx ? c(15, UInt8(speed)) : c()]], speed: fxx ? 6 : speed)
                    let (context, states) = inspect(module, rate)
                    let held = fxx || speed == 6 ? 63 : speed == 3 ? 44 : 32
                    let updates = context.voiceStateUpdates.filter { $0.effectType == 10 }
                    XCTAssertEqual(updates.filter(\.applied).map(\.syntheticTick), Array(1..<speed))
                    XCTAssertEqual(updates.filter(\.applied).map(\.effectiveVolumeBefore),
                                   speed > 1 ? [held] + Array(repeating: 32, count: speed - 2) : [])
                    XCTAssertEqual(updates.filter(\.applied).map(\.effectiveVolumeAfter), Array(repeating: 32, count: speed - 1))
                    XCTAssertEqual(states[2][0].baseChannelVolume, 32)
                    XCTAssertEqual(states[2][0].outputChannelVolume, speed > 1 ? 32 : held)
                    XCTAssertTrue(states.allSatisfy { $0[0].volumeSlideMemory == nil })
                    XCTAssertTrue(updates.allSatisfy { !$0.effectMemoryReused && !$0.effectMemoryDeferred })
                    let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                    let gains = gainEvents(runtime, row: 2)
                    XCTAssertEqual(gains.count, speed > 1 ? 1 : 0)
                    if let event = gains.first {
                        XCTAssertEqual(event.syntheticTick, 1)
                        XCTAssertEqual(event.scheduledFrame, ((fxx ? 12 : 2 * speed) + 1) * Int(rate / 50))
                        if case let .gainPanUpdate(index, gain, _) = event.action {
                            XCTAssertEqual(index, 0); XCTAssertEqual(gain, 0.5)
                        }
                    }
                }
            }
        }
    }

    func testCanonicalBaseSourcesAndResetBoundaries() {
        let sources: [(PlaybackCell, Int)] = [(c(), 32), (c(12, 24), 24), (c(volume: 0x28), 24)]
        for (writer, base) in sources {
            let (_, states) = inspect(song([[c(note: 49, instrument: 1)], [writer], [c(7, 0x48)], [c(10)]]))
            XCTAssertEqual(states[3][0].baseChannelVolume, base)
            XCTAssertEqual(states[3][0].outputChannelVolume, base)
        }
        for reset in [c(note: 49, instrument: 1), c(instrument: 1), c(note: 49)] {
            let module = song([[c(note: 49, instrument: 1)], [c(7, 0x48)], [reset], [c(10)]])
            let (context, states) = inspect(module)
            XCTAssertEqual(states[2][0].outputChannelVolume, reset.instrument == 0 ? 63 : 32)
            XCTAssertEqual(states[3][0].outputChannelVolume, 32)
            XCTAssertEqual(states[3][0].tremolo, states[2][0].tremolo)
            let gains = gainEvents(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: 48000), row: 3)
            XCTAssertEqual(gains.count, reset.instrument == 0 ? 1 : 0)
            if reset.instrument == 0 { XCTAssertEqual(gains.first?.activeEventIndex, context.events.count - 1) }
        }
        let (_, plain) = inspect(song([[c(note: 49, instrument: 1)], [c(10)], [c(10)]]))
        XCTAssertEqual(plain.map { $0[0].outputChannelVolume }, [32, 32, 32])
    }

    func testEnvelopeClockAndFinalAmplitudeUseExistingComposition() throws {
        for rate in [44_100.0, 48_000] {
            let module = song([[c(note: 49, instrument: 1)], [c(7, 0x48)], [c(10)]], envelope: true)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), frame = 13 * Int(rate / 50)
            let held = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == frame - Int(rate / 50) })
            let restored = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == frame })
            XCTAssertEqual(held.amplitude, 0.4921875)
            XCTAssertEqual(restored.amplitude, 0.25)
            XCTAssertEqual(plan.xmEnvelopeTimeline?.updates.first { $0.scheduledFrame == frame }?.state.volumeTick, 13)
            let rendered = PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate, channelCount: 1), rows: 3))
            XCTAssertEqual(rendered.block.interleavedPCM[frame + Int(rate / 50)], 0.25 / 32, accuracy: 1e-6)
        }
    }

    func testColdExecutionDoesNotSeedAndRealSeedsKeepTheirOrigins() {
        for family: UInt8 in [10, 5, 6] {
            let rows = [[c(note: 49, instrument: 1)], [c(10)], [c(family, 4, volume: 0x50)],
                        [c(7, 0x48)], [c(10)]]
            let (context, states) = inspect(song(rows))
            XCTAssertNil(states[1][0].volumeSlideMemory)
            XCTAssertEqual(states[2][0].volumeSlideMemory?.parameter, 4)
            XCTAssertEqual(states[4][0].volumeSlideMemory?.source.effectType, family)
            XCTAssertEqual(states[4][0].volumeSlideMemory?.source.source.rowIndex, 2)
            let replay = context.voiceStateUpdates.filter { $0.syntheticRow == 4 && $0.effectType == 10 }
            XCTAssertEqual(replay.map(\.effectiveVolumeBefore), [64, 40, 36, 32, 28])
            XCTAssertEqual(replay.map(\.effectiveVolumeAfter), [40, 36, 32, 28, 24])
            XCTAssertTrue(replay.allSatisfy { $0.effectMemoryReused && $0.memorySource?.effectType == family })
        }
        let (_, independent) = inspect(song([[c(10, 4, note: 49, instrument: 1), c(note: 49, instrument: 1)],
                                             [c(10), c(10)]]))
        XCTAssertEqual(independent[1][0].volumeSlideMemory?.parameter, 4)
        XCTAssertNil(independent[1][1].volumeSlideMemory)
    }

    func testTremoloStateAndLaterReplaySurviveColdRestoration() {
        for control: UInt8 in [0, 6] {
            let (context, states) = inspect(song([[c(14, 0x70 | control, note: 49, instrument: 1)],
                [c(7, 0x48)], [c(10)], [c(7)], [c(10)], [c(10)]]))
            XCTAssertEqual(states[2][0].tremolo, states[1][0].tremolo)
            XCTAssertEqual(states[2][0].tremolo.phase, 80)
            XCTAssertEqual(states[2][0].tremolo.control, Int(control))
            XCTAssertEqual(states[3][0].tremolo.phase, 160)
            XCTAssertEqual(states[5][0].tremolo, states[3][0].tremolo)
            if control == 0 {
                let later = context.voiceStateUpdates.filter { $0.syntheticRow == 3 && $0.effectType == 7 }
                XCTAssertEqual(later.map(\.effectiveVolumeAfter), [61, 54, 44, 32, 20])
            }
        }
    }

    func testPublicationUsesHeldGenerationWhileColdH00StaysUnchanged() throws {
        for rate in [44_100.0, 48_000] {
            for family: UInt8 in [10, 17, 6, 5] {
                let module = song([[c(note: 49, instrument: 1), c(16, 16)], [], [c(family)], [c(family)]], base: 64)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                let gains = gainEvents(runtime, row: 2)
                XCTAssertEqual(gains.count, family == 17 ? 0 : 1)
                XCTAssertTrue(gainEvents(runtime, row: 3).isEmpty) // Identical held targets deduplicate.
                if family != 17 {
                    let target = try XCTUnwrap(runtime.plan?.diagnostics.voiceStateUpdates.first {
                        if case .gxxChannelTarget = $0.command { return $0.syntheticRow == 2 }; return false
                    })
                    XCTAssertEqual(target.gainBefore, 1); XCTAssertEqual(target.gainAfter, 0.25)
                    XCTAssertEqual(target.activeEventIndex, 0)
                }
            }
            for (family, output): (UInt8, Int) in [(17, 63), (6, 32), (5, 32)] {
                let (_, states) = inspect(song([[c(note: 49, instrument: 1)], [c(7, 0x48)], [c(family)]]), rate)
                XCTAssertEqual(states[2][0].outputChannelVolume, output)
                XCTAssertNil(states[2][0].volumeSlideMemory)
            }
        }
    }

    func testSilentAndCompletedRoutesRestoreInheritanceWithoutCreatingSources() {
        for rate in [44_100.0, 48_000] {
            let (cold, _) = inspect(song([[c(10)]]), rate)
            XCTAssertTrue(cold.events.isEmpty)
            XCTAssertTrue(cold.voiceStateUpdates.allSatisfy { $0.applied && !$0.activeVoiceUpdated })
            for completed in [false, true] {
                let module = song([[c(note: completed ? 49 : 50, instrument: 1)], [c(7, 0x48)],
                                   [c(10)], [c(note: 49)]], completed: completed)
                let (context, states) = inspect(module, rate)
                XCTAssertEqual(states[2][0].baseChannelVolume, 32)
                XCTAssertEqual(states[2][0].outputChannelVolume, 32)
                XCTAssertEqual(context.events.count, completed ? 2 : 1)
                XCTAssertEqual(context.events.last?.gain, 0.5)
                let full = PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate, channelCount: 1), rows: 4))
                let tick = Int(rate / 50)
                XCTAssertTrue(full.block.interleavedPCM[(12 * tick)..<(18 * tick)].allSatisfy { $0 == 0 })
                XCTAssertEqual(full.block.interleavedPCM[18 * tick + 100], 0.5 / 32, accuracy: 1e-7)
            }
        }
    }

    func testSameCellNotePublishesOnlyAfterNewBirthAndWindowsKeepPCM() throws {
        for rate in [44_100.0, 48_000] {
            let module = song([[c(note: 49, instrument: 1)], [c(7, 0x48)], [c(10, note: 49)], []])
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            XCTAssertEqual(runtime.plan?.pattern.events.map(\.gain), [0.5, 0.984375])
            let event = try XCTUnwrap(gainEvents(runtime, row: 2).first)
            XCTAssertEqual(event.activeEventIndex, 1); XCTAssertEqual(event.syntheticTick, 1)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate, channelCount: 2), rows: 4)
            let full = PlaybackSongOfflineRenderer().render(request)
            XCTAssertEqual(full.plan, runtime.plan)
            for window in [1, 2, 3] {
                assertPCMEqual(full.block.interleavedPCM, PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: window).block.interleavedPCM)
            }
        }
    }

    func testPublicFixturePinsColdDiagnosticsAndSourceIdentity() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/cold-a00-output-restoration.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let (context, states) = inspect(module, rate)
            XCTAssertEqual(states[2][0].outputChannelVolume, 63)
            XCTAssertEqual(states[3].map(\.outputChannelVolume), [32, 32])
            XCTAssertTrue(states.allSatisfy { $0.allSatisfy { $0.volumeSlideMemory == nil } })
            XCTAssertEqual(context.events.last?.gain, 0.5)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate, channelCount: 2), rows: 7)
            let full = PlaybackSongOfflineRenderer().render(request)
            for window in [1, 3, 4] {
                assertPCMEqual(full.block.interleavedPCM, PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: window).block.interleavedPCM)
            }
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let updates = try XCTUnwrap(json["volume_panning_state_updates"] as? [[String: Any]])
            let cold = updates.filter { $0["volume_slide_policy"] as? String == "a00_cold_zero_slide_output_restoration" }
            XCTAssertFalse(cold.isEmpty)
            XCTAssertTrue(cold.allSatisfy { $0["applied"] as? Bool == true && $0["effect_memory_deferred"] as? Bool == false })
            XCTAssertTrue(cold.allSatisfy { $0["effect_memory_reused"] as? Bool == false && $0["memory_source"] is NSNull })
        }
    }

    private func assertPCMEqual(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0, 1e-7, file: file, line: line)
    }
    private func gainEvents(_ runtime: RuntimeCMixerAdapterEventPlan, row: Int) -> [RuntimeCMixerAdapterEvent] {
        runtime.events.filter { if case .gainPanUpdate = $0.action { return $0.source.rowIndex == row }; return false }
    }
    private func inspect(_ song: PlaybackSong, _ rate: Double = 48000) -> (Adapter.AdapterRowContext, [[Adapter.ChannelState]]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: rate)
        var context = Adapter.AdapterRowContext(), states = [[Adapter.ChannelState]]()
        for row in traversal.rows {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow), context: &context)
            states.append(context.channelStates)
        }
        return (context, states)
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, base: Int = 32, envelope: Bool = false, completed: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1 / 32, count: completed ? 32 : 256),
            volume: Float(base) / 64, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
            loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
        let empty = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [], volume: Float(base) / 64, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        let env = PlaybackVolumeEnvelope(enabled: envelope, points: envelope ? [.init(tick: 0, value: 32), .init(tick: 64, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: 0)
        var map = Array(repeating: 0, count: 96); map[49] = 1
        return .init(title: "Public cold A00", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 2 - $0.element.count)) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample, empty], volumeEnvelope: env, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: UInt8(base), panning: 128, finetune: 0, relativeNote: 0)]])
    }
}
