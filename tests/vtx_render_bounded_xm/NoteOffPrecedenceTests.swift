import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class NoteOffPrecedenceTests: XCTestCase {
    private let rates = [44_100.0, 48_000.0]
    private let prefix: [PlaybackCell] = [c(note: 49, instrument: 1), c(effect: 4, parameter: 0x47),
        c(volume: 0x30, effect: 7, parameter: 0x48), c(volume: 0xC3, effect: 12, parameter: 16)]

    func testReleaseRestorationCarriesSoundingOwnershipClocksAndPhases() throws {
        for rate in rates {
            for enabled in [false, true] {
                for instrument: UInt8 in [0, 1, 2] {
                    for target in [Self.c(note: 97, instrument: instrument), Self.c(instrument: instrument, effect: 20),
                                   Self.c(note: 97, instrument: instrument, effect: 20)] {
                        let plan = adapt(prefix + [target, Self.c(note: 53), Self.c()], rate, enabled: enabled)
                        let row = plan.xmChannelRows.first { $0.syntheticRow == 4 && $0.channelIndex == 0 }!.controls
                        XCTAssertEqual(row.baseChannelVolume, instrument == 0 ? (enabled ? 16 : 0) : 24)
                        XCTAssertEqual(row.outputChannelVolume, row.baseChannelVolume)
                        XCTAssertEqual(row.panningValue, instrument == 0 ? 48 : 192)
                        XCTAssertEqual(row.triggeredSampleDefaultVolume, 24)
                        XCTAssertEqual(row.carriedInstrumentIndex, instrument == 0 ? 1 : Int(instrument))
                        XCTAssertEqual(row.activeInstrumentIndex, 1)
                        XCTAssertEqual(row.carriedNote, 49)
                        XCTAssertEqual(row.vibratoPhase, 80)
                        XCTAssertEqual(row.tremolo.phase, 80)
                        XCTAssertEqual(plan.pattern.events.map(\.row), [0, 5])
                        XCTAssertEqual(plan.diagnostics.eventMappings.last?.instrumentIndex, instrument == 2 ? 2 : 1)
                        XCTAssertEqual(plan.diagnostics.keyOffEvents.filter { $0.syntheticRow == 4 }.count, 1)
                        let state = try state(plan, row: 4)
                        XCTAssertFalse(state.keyOn)
                        XCTAssertEqual(state.fadeoutAccumulator, 32_512)
                        XCTAssertEqual(state.volumeTick, enabled ? 4 : 0)
                    }
                }
            }
        }
    }

    func testRawK00SuppressesOrdinaryNoteAndInstrumentStarts() {
        for rate in rates {
            for instrument: UInt8 in [0, 2] {
                let plan = adapt(prefix + [Self.c(note: 53, instrument: instrument, effect: 20), Self.c()], rate)
                XCTAssertEqual(plan.pattern.events.count, 1)
                XCTAssertEqual(plan.xmChannelRows[8].controls.carriedNote, 49)
                XCTAssertEqual(plan.xmChannelRows[8].controls.triggeredSampleDefaultVolume, 24)
                XCTAssertEqual(plan.diagnostics.keyOffEvents.count, 1)
            }
        }
    }

    func testRowEntryVolumeFineAndPanWritersFollowReleaseAndCachedDefaults() {
        let cases: [(PlaybackCell, Int, Double)] = [
            (Self.c(note: 97, volume: 0x30), 32, 48), (Self.c(volume: 0x30, effect: 20), 32, 48),
            (Self.c(note: 97, instrument: 2, volume: 0x30), 32, 192),
            (Self.c(note: 97, instrument: 2, effect: 12, parameter: 32), 32, 192),
            (Self.c(note: 97, instrument: 2, volume: 0xC3), 24, 48),
            (Self.c(note: 97, instrument: 2, effect: 8, parameter: 32), 24, 32),
            (Self.c(volume: 0x91, effect: 20), 1, 48), (Self.c(instrument: 2, volume: 0x91, effect: 20), 25, 192)]
        for rate in rates {
            for (cell, volume, pan) in cases {
                let plan = adapt(prefix + [cell, Self.c()], rate)
                let controls = plan.xmChannelRows[8].controls
                XCTAssertEqual(controls.baseChannelVolume, volume)
                XCTAssertEqual(controls.outputChannelVolume, volume)
                XCTAssertEqual(controls.panningValue, pan)
                XCTAssertEqual(plan.pattern.events.count, 1)
            }
        }
    }

    func testMaskedNonzeroTicksAndEffectiveSpeedKeepRowEntryReset() throws {
        for rate in rates {
            for speed in [1, 2, 3, 6] {
                for parameter: UInt8 in [1, 5, 6, 0x20, 0x21] {
                    let plan = adapt(prefix + [Self.c(instrument: 2, effect: 20, parameter: parameter), Self.c()],
                        rate, enabled: true, speed: speed)
                    let tick = Int(parameter & 31), valid = tick > 0 && tick < speed
                    let release = try XCTUnwrap(plan.diagnostics.keyOffEvents.first)
                    XCTAssertEqual(release.applied, valid)
                    if tick == 0 { XCTAssertEqual(release.reason, .maskedZeroNoOp) }
                    else if !valid { XCTAssertEqual(release.reason, .outOfRowNoOp) }
                    XCTAssertEqual(release.scheduledFrame, valid ? (4 * speed + tick) * Int(rate / 50) : nil)
                    let initial = try state(plan, row: 4)
                    XCTAssertTrue(initial.keyOn)
                    XCTAssertEqual(initial.volumeTick, 0)
                    XCTAssertEqual(initial.fadeoutAccumulator, 32_768)
                    let end = try state(plan, row: 4, tick: speed - 1)
                    XCTAssertEqual(end.keyOn, !valid)
                    XCTAssertEqual(end.fadeoutAccumulator, valid ? 32_768 - (speed - tick) * 256 : 32_768)
                }
                for channel in [0, 1] {
                    let plan = adapt(prefix + [Self.c(instrument: 2, effect: 20, parameter: 0x21), Self.c()],
                        rate, enabled: true, fxx: UInt8(speed), channel: channel)
                    XCTAssertEqual(plan.diagnostics.keyOffEvents.first?.rowSpeed, speed)
                    XCTAssertEqual(plan.diagnostics.keyOffEvents.first?.scheduledFrame,
                        speed > 1 ? 25 * Int(rate / 50) : nil)
                }
            }
        }
    }

    func testNonzeroColumnWriterPrecedesK01AndLaterNoteOnlyCarriesFour() {
        for rate in rates {
            let plan = adapt(prefix + [Self.c(note: 97, volume: 0x71, effect: 20, parameter: 1), Self.c(note: 53)], rate)
            let writes = plan.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 4 && $0.syntheticTick == 1 }
            XCTAssertEqual(writes.map(\.effectiveVolumeAfter), [1, 0])
            XCTAssertEqual(plan.xmChannelRows.last { $0.channelIndex == 0 }?.controls.baseChannelVolume, 4)
            XCTAssertEqual(plan.pattern.events.last?.gain, 4.0 / 64)
            XCTAssertEqual(plan.diagnostics.keyOffEvents.map(\.syntheticTick), [0, 1])
        }
    }

    func testColdReleaseAndScheduledReleaseCarryIntoEnabledAndDisabledConsumers() throws {
        for rate in rates {
            for enabled in [false, true] {
                for target in [Self.c(note: 97, instrument: 2), Self.c(instrument: 2, effect: 20),
                               Self.c(instrument: 2, effect: 20, parameter: 1), Self.c(instrument: 2)] {
                    let plan = adapt([target, Self.c(effect: 12, parameter: 64), Self.c(note: 49), Self.c()], rate, enabled: enabled)
                    XCTAssertEqual(plan.pattern.events.map(\.row), [2])
                    let first = try state(plan, row: 2)
                    XCTAssertEqual(first.keyOn, target.note == 0 && target.effectType == 0)
                    XCTAssertEqual(first.fadeoutAccumulator, target.note == 97 || target.effectType == 20 && target.effectParam == 0 ? 0 : 32_768)
                    XCTAssertEqual(first.volumeValue, enabled ? 0 : 1)
                    let releases = plan.diagnostics.keyOffEvents.filter(\.applied)
                    XCTAssertTrue(releases.allSatisfy { $0.activeEventIndex == nil && !$0.activeVoiceFound })
                    if target.effectParam == 1 { XCTAssertEqual(releases.first?.scheduledFrame, Int(rate / 50)) }
                }
            }
        }
    }

    func testColdReleaseDoesNotOverrideSubsequentG23DelayedReset() throws {
        for rate in rates {
            for enabled in [false, true] {
                let plan = adapt([Self.c(note: 97, instrument: 2), Self.c(instrument: 2, effect: 14, parameter: 0xD1),
                    Self.c(effect: 12, parameter: 64), Self.c(note: 49), Self.c()], rate, enabled: enabled)
                XCTAssertEqual(plan.diagnostics.noteDelayEffects.first?.status, .instrumentOnlyNoRetainedNote)
                XCTAssertEqual(plan.pattern.events.map(\.row), [3])
                let first = try state(plan, row: 3)
                XCTAssertTrue(first.keyOn)
                XCTAssertEqual(first.fadeoutAccumulator, 32_768)
                XCTAssertEqual(first.volumeValue, enabled ? 0 : 1)
            }
        }
    }

    func testFxPriorityAndBxObserverCarryPreserveEstablishedBoundaries() throws {
        for rate in rates {
            for note: UInt8 in [0, 53, 97] {
                let plan = adapt(prefix + [Self.c(note: note, instrument: 2, volume: 0xF1, effect: 20), Self.c()], rate, enabled: true)
                XCTAssertEqual(plan.pattern.events.count, 1)
                XCTAssertEqual(plan.diagnostics.keyOffEvents.filter(\.applied).count, note == 97 ? 1 : 0)
                XCTAssertEqual(try state(plan, row: 4).keyOn, note != 97)
            }
            let plan = adapt(prefix + [Self.c(volume: 0xB3, effect: 20, parameter: 1),
                Self.c(effect: 14, parameter: 0x71), Self.c(effect: 7, parameter: 0x48)], rate)
            let controls = plan.xmChannelRows.filter { $0.channelIndex == 0 }.map(\.controls)
            XCTAssertEqual(controls[4].tremoloVibratoPhase, controls[3].tremoloVibratoPhase)
            XCTAssertEqual(controls[5].tremoloVibratoPhase, controls[4].tremoloVibratoPhase)
            XCTAssertEqual(controls[5].vibratoPhase, 160)
        }
    }

    func testAlreadyReleasedAndCompletedChannelsDoNotResetOrRevive() throws {
        for rate in rates {
            let module = song(prefix + [Self.c(note: 97), Self.c(note: 97, instrument: 2, effect: 20), Self.c()], enabled: true)
            let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: rate)
            let carried = try state(plan, row: 5)
            XCTAssertEqual(carried.volumeTick, 10)
            XCTAssertEqual(carried.fadeoutAccumulator, 30_976)
            let complete = adapt(prefix + [Self.c(note: 97, instrument: 2), Self.c()], rate, completed: true)
            XCTAssertEqual(complete.pattern.events.count, 1)
            XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0, at: 24 * Int(rate / 50), plan: complete))
            XCTAssertEqual(try state(complete, row: 4).fadeoutAccumulator, 32_512)
        }
    }

    func testPublicFixtureWholeWindowRuntimePlanAndReleaseBoundaries() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/noteoff-kxx-precedence.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in rates {
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 34)
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            XCTAssertTrue(full.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
            XCTAssertFalse(full.diagnostics.eventMappings.contains { $0.source.rowIndex == 11 && $0.channelIndex == 0 })
            XCTAssertTrue(full.plan.xmEmptyRoutes.contains { $0.instrumentIndex == 5 })
            XCTAssertEqual(full.diagnostics.keyOffEvents.first { $0.source.rowIndex == 21 && $0.channelIndex == 0 }?.reason, .maskedZeroNoOp)
            for rows in [1, 2, 3, 5] {
                let window = renderer.renderWindowed(request, windowRows: rows)
                XCTAssertEqual(window.plan, full.plan)
                XCTAssertEqual(window.block.interleavedPCM.count, full.block.interleavedPCM.count)
                XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
            XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, full.plan)
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let releases = try XCTUnwrap(json["key_off_events"] as? [[String: Any]])
            XCTAssertTrue(releases.contains { $0["reason"] as? String == "masked_zero_no_op" })
#if DEBUG
            let boundaries = Set(full.diagnostics.keyOffEvents.compactMap(\.scheduledFrame)).filter { $0 > 1 && $0 + 1 < request.boundedFrameCount }.sorted()
            for offset in [-1, 0, 1] {
                let window = renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries.map { $0 + offset })
                XCTAssertEqual(window.plan, full.plan)
                XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
#endif
        }
    }

    private func state(_ plan: PlaybackSongSyntheticPlan, row: Int, tick: Int = 0) throws -> MixerEnvelopeSemanticState {
        try XCTUnwrap(plan.xmEnvelopeTimeline?.channelUpdates.first { $0.channelIndex == 0 && $0.source.rowIndex == row && $0.tick == tick }?.state)
    }
    private func adapt(_ cells: [PlaybackCell], _ rate: Double, enabled: Bool = false, speed: Int = 6,
                       fxx: UInt8? = nil, channel: Int = 0, completed: Bool = false) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(song(cells, enabled: enabled, speed: speed, fxx: fxx,
            channel: channel, completed: completed), orderIndex: 0, sampleRate: rate)
    }
    private static func c(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0,
                          effect: UInt8 = 0, parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ cells: [PlaybackCell], enabled: Bool = false, speed: Int = 6,
                      fxx: UInt8? = nil, channel: Int = 0, completed: Bool = false) -> PlaybackSong {
        func instrument(_ index: Int, _ volume: Float, _ pan: UInt8) -> PlaybackInstrument {
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0,
                pcm: Array(repeating: 0.25, count: completed && index == 1 ? 2 : 256), volume: volume,
                panning: pan, relativeNote: 0, finetune: 0, baseSampleRate: 100,
                loopStart: 0, loopLength: completed && index == 1 ? 0 : 256, loopType: completed && index == 1 ? 0 : 1)
            let envelope = PlaybackVolumeEnvelope(enabled: enabled,
                points: [(0,64),(4,48),(8,32),(24,0)].map { .init(tick: $0.0, value: $0.1) },
                sustainPointIndex: 1, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: enabled ? 3 : 0, fadeout: 256)
            return .init(index: index, samples: [sample], volumeEnvelope: envelope, noteSampleMap: Array(repeating: 0, count: 96))
        }
        let rows = cells.enumerated().map { row, cell -> PlaybackRow in
            var columns = channel == 0 ? [cell, Self.c()] : [Self.c(), cell]
            if row == 4, let fxx { columns[1-channel] = Self.c(effect: 15, parameter: fxx) }
            return .init(index: row, cells: columns)
        }
        return .init(title: "Public G24", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows)],
            instrumentsByIndex: [1: instrument(1, 0.375, 192), 2: instrument(2, 0.625, 64)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true)
    }
}
