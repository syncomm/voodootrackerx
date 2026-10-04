import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class VolumeColumnSlideTimingTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testOrdinarySlideTrajectoriesClampsAndNoMemoryAtBothRates() throws {
        // Project-authored stimuli observed through pinned FT2 87be425 before implementation.
        for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] {
                for (column, header, delta): (UInt8, Int, Int) in [(0x61, 32, -1), (0x71, 32, 1),
                    (0x6F, 2, -15), (0x7F, 62, 15), (0x60, 32, 0), (0x70, 32, 0)] {
                    let module = song([cell(note: 49, instrument: 1, volume: column), cell(volume: 0x60), cell(volume: 0x70)],
                                      speed: speed, header: header)
                    let plan = adapt(module, rate)
                    XCTAssertEqual(plan.pattern.events.first?.gain, Float(header) / 64)
                    let updates = slides(plan).filter { $0.syntheticRow == 0 }
                    XCTAssertEqual(updates.map(\.syntheticTick), Array(1..<speed))
                    var value = header
                    for update in updates {
                        let raw = value + delta
                        XCTAssertEqual(update.effectiveVolumeBefore, value)
                        value = min(64, max(0, raw))
                        XCTAssertEqual(update.effectiveVolumeAfter, value)
                        XCTAssertEqual(update.gainAfter, Float(value) / 64)
                        XCTAssertEqual(update.scheduledFrame, update.syntheticTick * Int(rate / 50))
                        XCTAssertEqual(update.volumeSlideClamped, raw != value)
                        XCTAssertEqual(update.behavior, .tickLevelAfterTick0)
                        XCTAssertEqual(update.volumeSlideTick0Suppressed, true)
                        XCTAssertTrue(update.activeVoiceUpdated)
                        XCTAssertFalse(update.effectMemoryReused)
                        XCTAssertFalse(update.effectMemoryDeferred)
                    }
                    XCTAssertEqual(plan.xmChannelRows.last?.controls.baseChannelVolume, value)
                    XCTAssertTrue(plan.xmChannelRows.allSatisfy { $0.controls.volumeSlideMemory == nil })
                }
            }
        }
    }

    func testTickZeroPrecedenceFxxAndActiveContinuation() {
        let module = song([cell(note: 49, instrument: 1, volume: 0x61, effect: 12, param: 40),
            cell(volume: 0x71, effect: 15, param: 3), cell(volume: 0x61, effect: 15, param: 1),
            cell(volume: 0x71, effect: 15, param: 6)])
        let plan = adapt(module)
        XCTAssertEqual(plan.pattern.events.count, 1)
        XCTAssertEqual(plan.pattern.events.first?.gain, 40 / 64)
        XCTAssertEqual(slides(plan).map(\.effectiveVolumeAfter), [39, 38, 37, 36, 35, 36, 37, 38, 39, 40, 41, 42])
        XCTAssertEqual(plan.xmChannelRows.map { $0.controls.outputChannelVolume }, [40, 35, 37, 37])
        XCTAssertEqual(plan.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 3, 1, 6])
        let set = adapt(song([cell(note: 49, instrument: 1, volume: 0x30, effect: 12, param: 40)]))
        XCTAssertEqual(set.pattern.events.first?.gain, 40 / 64)
    }

    func testZeroAmountsRestoreTremoloOnlyAtTickOneAndFineSlidesStayAtTickZero() {
        for column: UInt8 in [0x60, 0x70, 0x80, 0x81, 0x90, 0x91] {
            let plan = adapt(song([cell(note: 49, instrument: 1, effect: 7, param: 0x48), cell(volume: column), cell()]))
            let ordinary = column < 0x80
            let expected = column == 0x81 ? 31 : (column == 0x91 ? 33 : 32)
            XCTAssertEqual(plan.xmChannelRows[1].controls.outputChannelVolume, ordinary ? 63 : expected)
            XCTAssertEqual(plan.xmChannelRows[2].controls.outputChannelVolume, expected)
            let updates = plan.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 1 }
            XCTAssertEqual(updates.map(\.syntheticTick), ordinary ? [1, 2, 3, 4, 5] : [0])
            XCTAssertEqual(updates.first?.effectiveVolumeBefore, 63)
            XCTAssertEqual(updates.first?.effectiveVolumeAfter, expected)
            XCTAssertNil(plan.xmChannelRows[2].controls.volumeSlideMemory)
        }
    }

    func testEffectColumnWritersRemainIndependentAndFollowColumnEachTick() {
        for family: UInt8 in [5, 6, 10] {
            let plan = adapt(song([cell(note: 49, instrument: 1), cell(volume: 0x6F, effect: family, param: 0x10),
                cell(volume: 0x70), cell(effect: family)], header: 2))
            let mixed = plan.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 1 }
            XCTAssertEqual(mixed.map(\.effectiveVolumeAfter), [0, 1, 0, 1, 0, 1, 0, 1, 0, 1])
            XCTAssertEqual(mixed.map(\.syntheticTick), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
            XCTAssertEqual(plan.xmChannelRows[2].controls.volumeSlideMemory?.parameter, 0x10)
            let replay = plan.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 3 }
            XCTAssertEqual(replay.map(\.effectiveVolumeAfter), [2, 3, 4, 5, 6])
            XCTAssertTrue(replay.allSatisfy(\.effectMemoryReused))
            let pure = adapt(song([cell(note: 49, instrument: 1), cell(effect: family, param: 0x10)], header: 2))
            XCTAssertEqual(pure.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 1 }.map(\.effectiveVolumeAfter), [3, 4, 5, 6, 7])
        }
        let tremolo = adapt(song([cell(note: 49, instrument: 1, volume: 0x61, effect: 7, param: 0x48)]))
        XCTAssertEqual(tremolo.diagnostics.voiceStateUpdates.map(\.effectiveVolumeAfter), [31, 31, 30, 42, 29, 51, 28, 57, 27, 58])
        for family: UInt8 in [5, 10] {
            let cold = adapt(song([cell(note: 49, instrument: 1), cell(volume: 0x61, effect: family)]))
            XCTAssertEqual(slides(cold).map(\.effectiveVolumeAfter), [31, 30, 29, 28, 27])
            XCTAssertNil(cold.xmChannelRows.first?.controls.volumeSlideMemory)
        }
    }

    func testSilentAndCompletedSourcesCarryVolumeIntoLaterNoteWithoutFabricatingVoice() {
        for oneShot in [false, true] {
            let first = cell(note: oneShot ? 49 : 50, instrument: 1, volume: oneShot ? 0 : 0x61)
            let plan = adapt(song([first, cell(volume: oneShot ? 0x61 : 0), cell(note: 49)], empty: !oneShot, oneShot: oneShot))
            XCTAssertEqual(plan.pattern.events.count, oneShot ? 2 : 1)
            XCTAssertEqual(plan.pattern.events.last?.gain, 27 / 64)
            XCTAssertEqual(plan.xmChannelRows.last?.controls.outputChannelVolume, 27)
            if !oneShot { XCTAssertTrue(slides(plan).allSatisfy { !$0.activeVoiceUpdated }) }
        }
        let cold = adapt(song([cell(volume: 0x61), cell(note: 49, instrument: 1)]))
        XCTAssertTrue(slides(cold).allSatisfy { !$0.activeVoiceUpdated })
        XCTAssertEqual(cold.xmChannelRows[1].controls.outputChannelVolume, 32) // Explicit header refresh.
    }

    func testEnvelopeUsesExistingOutputTargetsAndBothRateWindowParity() throws {
        for rate in [44_100.0, 48_000] {
            let module = song([cell(note: 49, instrument: 1, volume: 0x61), cell(volume: 0x71), cell()], envelope: true)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 3)
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            let targets = try XCTUnwrap(full.plan.xmAudibleTimeline?.updates)
            for tick in 0..<6 {
                let target = try XCTUnwrap(targets.first { $0.scheduledFrame == tick * Int(rate / 50) })
                XCTAssertEqual(target.amplitude, Float(32 - tick) / 64 * Float(64 - tick * 4) / 64)
                XCTAssertEqual(target.durationFrames, tick == 0 ? 0 : Int(rate / 50))
            }
            XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, full.plan)
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block, full.block)
        }
    }

    func testPublicFixtureHasExactTickValuesAndWindowRuntimePlansAtBothRates() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/volume-column-slide-timing.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let renderer = PlaybackSongOfflineRenderer(), request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 8)
            let full = renderer.render(request)
            XCTAssertEqual(full.plan.xmChannelRows.filter { $0.channelIndex == 0 }.map { $0.controls.outputChannelVolume }, [32, 32, 30, 2, 0, 32, 31, 31])
            XCTAssertEqual(full.plan.xmChannelRows.filter { $0.channelIndex == 1 }.map { $0.controls.outputChannelVolume }, [32, 32, 34, 62, 64, 32, 33, 33])
            XCTAssertEqual(slides(full.plan).count, 44)
            XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, full.plan)
            for rows in [1, 2, 3] {
                let window = renderer.renderWindowed(request, windowRows: rows)
                XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
        }
    }

    private func slides(_ plan: PlaybackSongSyntheticPlan) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        plan.diagnostics.voiceStateUpdates.filter { $0.commandSource == .volumeColumn && $0.behavior == .tickLevelAfterTick0 }
    }

    private func adapt(_ module: PlaybackSong, _ rate: Double = 48_000) -> PlaybackSongSyntheticPlan {
        Adapter.adapt(module, orderIndex: 0, sampleRate: rate)
    }

    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(_ cells: [PlaybackCell], speed: Int = 6, header: Int = 32, envelope: Bool = false,
                      empty: Bool = false, oneShot: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 256),
            volume: Float(header) / 64, relativeNote: 0, finetune: 0, baseSampleRate: 8_363,
            loopStart: 0, loopLength: oneShot ? 0 : 256, loopType: oneShot ? 0 : 1)
        let volume = PlaybackVolumeEnvelope(enabled: envelope,
            points: envelope ? [.init(tick: 0, value: 64), .init(tick: 8, value: 32), .init(tick: 20, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: 0)
        var map = Array(repeating: 0, count: 96)
        if empty { map[49] = 1 }
        return PlaybackSong(title: "Public G08 control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: volume, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true,
            xmSampleSlotProvenanceByInstrument: empty ? [1: [.init(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: false,
                volume: UInt8(header), panning: 128, finetune: 0, relativeNote: 0)]] : [:])
    }
}
