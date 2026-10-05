import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class VolumeColumnPanSlideTimingTests: XCTestCase {
    func testObservedTrajectoriesZeroFormsAndClampsAtBothRates() throws {
        // Project-authored controls observed through pinned FT2 87be425 before implementation.
        for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] {
                for header: UInt8 in [0, 1, 64, 128, 224, 254, 255] {
                    for column: UInt8 in [0xD0, 0xD1, 0xDF, 0xE0, 0xE1, 0xEF] {
                        let plan = adapt(song([cell(note: 49, instrument: 1, volume: column), cell()],
                                              speed: speed, pan: header), rate)
                        XCTAssertEqual(plan.pattern.events.first?.pan, PlaybackSamplePanningPolicy.plannedPan(header))
                        XCTAssertEqual(plan.xmChannelRows.first?.controls.panningValue, Double(header))
                        let updates = slides(plan)
                        XCTAssertEqual(updates.map(\.syntheticTick), Array(1..<speed))
                        var value = Int(header)
                        for update in updates {
                            if column == 0xD0 { value = 0 }
                            else if column < 0xE0 { value = max(0, value - Int(column & 15)) }
                            else { value = min(255, value + Int(column & 15)) }
                            XCTAssertEqual(update.channelPanningValueAfter, Double(value))
                            XCTAssertEqual(update.scheduledFrame, update.syntheticTick * Int(rate / 50))
                            XCTAssertEqual(update.behavior, .tickLevelAfterTick0)
                            XCTAssertTrue(update.activeVoiceUpdated)
                            XCTAssertFalse(update.effectMemoryReused)
                            XCTAssertFalse(update.effectMemoryDeferred)
                            XCTAssertEqual(update.effectiveVolumeBefore, update.effectiveVolumeAfter)
                        }
                        XCTAssertEqual(plan.xmChannelRows.last?.controls.panningValue, Double(value))
                        if column == 0xE0 {
                            XCTAssertEqual(plan.xmChannelRows.last?.controls.pan, PlaybackSamplePanningPolicy.plannedPan(header))
                        }
                    }
                }
            }
        }
    }

    func testEffectiveFxxSpeedSameRowNoteAndContinuation() {
        let plan = adapt(song([cell(note: 49, instrument: 1, volume: 0xD1, effect: 15, param: 3),
            cell(volume: 0xE1, effect: 15, param: 1), cell(volume: 0xE1, effect: 15, param: 6),
            cell(note: 49, instrument: 1, volume: 0xD1), cell(note: 49, volume: 0xE1), cell()]))
        XCTAssertEqual(plan.diagnostics.rowTiming.map(\.effectiveSpeed), [3, 1, 6, 6, 6, 6])
        XCTAssertEqual(plan.xmChannelRows.map { $0.controls.panningValue }, [128, 126, 126, 128, 123, 128])
        XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 0 }.map(\.channelPanningValueAfter), [127, 126])
        XCTAssertTrue(slides(plan).allSatisfy { $0.syntheticTick > 0 })
        XCTAssertEqual(plan.pattern.events.count, 3)
        XCTAssertEqual(plan.pattern.events[1].pan, 0) // Explicit instrument refreshes the header.
        XCTAssertEqual(plan.pattern.events[2].pan, PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: 123))
    }

    func testStaticWritersKeepPrecedenceAndZeroFormsHaveNoMemory() {
        let plan = adapt(song([cell(note: 49, instrument: 1, volume: 0xD1, effect: 8, param: 224),
            cell(volume: 0xE1, effect: 8, param: 64), cell(volume: 0xD0, effect: 8, param: 128),
            cell(volume: 0xE0, effect: 8, param: 128), cell(volume: 0xC8), cell(volume: 0xD1),
            cell(volume: 0xC4, effect: 8, param: 224), cell(volume: 0xE1), cell()]))
        XCTAssertEqual(plan.xmChannelRows.map { $0.controls.panningValue }, [224, 64, 128, 128, 128, 128, 224, 224, 229])
        XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 0 }.map(\.channelPanningValueAfter), [223, 222, 221, 220, 219])
        XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 2 }.map(\.channelPanningValueAfter), [0, 0, 0, 0, 0])
        XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 3 }.map(\.channelPanningValueAfter), [128, 128, 128, 128, 128])
        XCTAssertEqual(plan.pattern.events.first?.pan, PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: 224))
        let zero = adapt(song([cell(note: 49, instrument: 1, volume: 0xD3), cell(volume: 0xE0),
            cell(volume: 0xE3), cell(volume: 0xD0), cell()]))
        XCTAssertEqual(zero.xmChannelRows.map { $0.controls.panningValue }, [128, 113, 113, 128, 0])
        XCTAssertTrue(zero.xmChannelRows.allSatisfy { $0.controls.volumeSlideMemory == nil })
        let pxy = adapt(song([cell(note: 49, instrument: 1, volume: 0xD1, effect: 0x19, param: 1)]))
        XCTAssertTrue(pxy.diagnostics.deferredCellFields.contains { $0.field == .effect })
        XCTAssertEqual(slides(pxy).map(\.channelPanningValueAfter), [127, 126, 125, 124, 123])
    }

    func testSilentAndCompletedSourcesCarryPanWithoutFabricatingVoice() {
        for oneShot in [false, true] {
            let plan = adapt(song([cell(note: oneShot ? 49 : 50, instrument: 1),
                cell(volume: 0xD1), cell(note: 49)], empty: !oneShot, oneShot: oneShot))
            XCTAssertEqual(plan.pattern.events.count, oneShot ? 2 : 1)
            XCTAssertEqual(plan.xmChannelRows.last?.controls.panningValue, 123)
            XCTAssertEqual(plan.pattern.events.last?.pan, PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: 123))
            if !oneShot { XCTAssertTrue(slides(plan).allSatisfy { !$0.activeVoiceUpdated }) }
        }
        let cold = adapt(song([cell(instrument: 1, effect: 8, param: 128), cell(volume: 0xD1), cell(note: 49)]))
        XCTAssertTrue(slides(cold).allSatisfy { !$0.activeVoiceUpdated })
        XCTAssertEqual(cold.pattern.events.count, 1)
        XCTAssertEqual(cold.xmChannelRows.last?.controls.panningValue, 123)
        let uninitialized = adapt(song([cell(volume: 0xE1), cell()]))
        XCTAssertEqual(uninitialized.xmChannelRows.last?.controls.panningValue, 132.5) // Retained cold baseline.
        XCTAssertTrue(uninitialized.pattern.events.isEmpty)
    }

    func testPanEnvelopeAndLxxUseCurrentStoredPanAndExistingTargets() throws {
        for rate in [44_100.0, 48_000] {
            let cells = [cell(note: 49, instrument: 1, volume: 0xD1),
                cell(volume: 0xE1, effect: 0x15, param: 8), cell(volume: 0xD0), cell(volume: 0xE0)]
            let plan = adapt(song(cells, panEnvelope: true), rate)
            let baseline = adapt(song(cells.map { cell(note: $0.note, instrument: $0.instrument,
                effect: $0.effectType, param: $0.effectParam) }, panEnvelope: true), rate)
            XCTAssertEqual(plan.xmEnvelopeTimeline?.updates.map(\.state), baseline.xmEnvelopeTimeline?.updates.map(\.state))
            let semantics = try XCTUnwrap(plan.xmEnvelopeTimeline?.updates)
            XCTAssertEqual(semantics.prefix(6).map(\.channelPanningValue), [128, 127, 126, 125, 124, 123])
            XCTAssertEqual(semantics[6].state.panTick, 8)
            let targets = try XCTUnwrap(plan.xmAudibleTimeline?.updates)
            // Byte-domain values observed in the independent integer-slope G06 control.
            for (tick, byte) in [128, 111, 94, 78, 62, 92, 184, 170, 156, 141, 127, 128].enumerated() {
                let staticByte = semantics[tick].channelPanningValue
                let staticPan = tick == 0 ? Float(0) : PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: staticByte)
                let expected = min(1, max(-1, staticPan + PlaybackSamplePanningPolicy.plannedPan(byte)
                    - PlaybackSamplePanningPolicy.plannedPan(Int(staticByte))))
                XCTAssertEqual(targets[tick].pan, expected, accuracy: 1e-7)
                XCTAssertEqual(targets[tick].scheduledFrame, tick * Int(rate / 50))
                XCTAssertEqual(targets[tick].durationFrames, tick == 0 ? 0 : Int(rate / 50))
            }
            XCTAssertEqual(semantics[13].channelPanningValue, 0)
            XCTAssertEqual(targets[13].pan, -1)
            let request = PlaybackSongOfflineRenderRequest(song: song(cells, panEnvelope: true), config: .init(sampleRate: rate), rows: cells.count)
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: request.song, sampleRate: rate).plan, full.plan)
            for rows in [1, 2, 3] { XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block, full.block) }
        }
    }

    func testG08VolumeWritersRemainIndependentOnMixedPanRows() {
        let plan = adapt(song([cell(note: 49, instrument: 1, volume: 0x61), cell(volume: 0xD1, effect: 10, param: 0x10),
            cell(volume: 0x71), cell(volume: 0xE1, effect: 6, param: 0x01), cell(volume: 0x60), cell(volume: 0x70), cell()]))
        XCTAssertEqual(plan.xmChannelRows.map { $0.controls.outputChannelVolume }, [32, 27, 32, 37, 32, 32, 32])
        XCTAssertEqual(plan.xmChannelRows.map { $0.controls.panningValue }, [128, 128, 123, 123, 128, 128, 128])
        let columns = plan.diagnostics.voiceStateUpdates.filter { $0.commandSource == .volumeColumn }
        XCTAssertTrue(columns.allSatisfy { $0.syntheticTick > 0 })
        XCTAssertEqual(columns.count, 30)
    }

    func testPublicFixtureHasExactPanFramesAndWholeWindowRuntimePlans() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/volume-column-pan-slide-timing.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let renderer = PlaybackSongOfflineRenderer(), request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 6)
            let full = renderer.render(request)
            XCTAssertEqual(full.plan.xmChannelRows.filter { $0.channelIndex == 0 }.map { $0.controls.panningValue }, [128, 128, 126, 224, 2, 0])
            XCTAssertEqual(full.plan.xmChannelRows.filter { $0.channelIndex == 1 }.map { $0.controls.panningValue }, [128, 128, 130, 135, 254, 255])
            XCTAssertEqual(slides(full.plan).count, 44)
            XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, full.plan)
            for rows in [1, 2, 3] {
                let window = renderer.renderWindowed(request, windowRows: rows)
                XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
        }
    }

    private func slides(_ plan: PlaybackSongSyntheticPlan) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        plan.diagnostics.voiceStateUpdates.filter { (0xD0...0xEF).contains($0.rawVolumeColumn ?? 0) }
    }

    private func adapt(_ module: PlaybackSong, _ rate: Double = 48_000) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: rate)
    }

    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(_ cells: [PlaybackCell], speed: Int = 6, pan: UInt8 = 128,
                      panEnvelope: Bool = false, empty: Bool = false, oneShot: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 256),
            volume: 0.5, panning: pan, relativeNote: 0, finetune: 0, baseSampleRate: 8_363,
            loopStart: 0, loopLength: oneShot ? 0 : 256, loopType: oneShot ? 0 : 1)
        let volume = PlaybackVolumeEnvelope(enabled: true, points: [.init(tick: 0, value: 64), .init(tick: 100, value: 64)],
            sustainPointIndex: panEnvelope ? 1 : nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: panEnvelope ? 3 : 1, fadeout: 0)
        let envelope = PlaybackPanningEnvelope(enabled: panEnvelope,
            points: panEnvelope ? [.init(tick: 0, value: 32), .init(tick: 4, value: 16), .init(tick: 8, value: 48), .init(tick: 12, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: panEnvelope ? 1 : 0)
        var map = Array(repeating: 0, count: 96)
        if empty { map[49] = 1 }
        return PlaybackSong(title: "Public G09 control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: volume, panningEnvelope: envelope, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true,
            xmSampleSlotProvenanceByInstrument: empty ? [1: [.init(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: false,
                volume: 32, panning: pan, finetune: 0, relativeNote: 0)]] : [:])
    }
}
