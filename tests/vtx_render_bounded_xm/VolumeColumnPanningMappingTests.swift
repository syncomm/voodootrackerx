import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class VolumeColumnPanningMappingTests: XCTestCase {
    // Project-authored controls observed against pinned FT2 87be425 before implementation.
    private let observed = [0, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240]

    func testAllObservedBytesInitializeTriggersAndContinuingChannelsAtBothRates() throws {
        for rate in [44_100.0, 48_000] {
            for retrigger in [false, true] {
                let cells = columnCells(retrigger: retrigger)
                let plan = adapt(song(cells), rate)
                XCTAssertEqual(plan.xmChannelRows.map { $0.controls.panningValue }, observed.map(Double.init))
                XCTAssertEqual(plan.diagnostics.volumeColumnMappings.map { $0.volumeColumn.appliedPanningValue }, observed)
                XCTAssertEqual(plan.xmChannelRows.map(\.scheduledFrame), (0..<16).map { $0 * 6 * Int(rate / 50) })
                XCTAssertEqual(plan.pattern.events.count, retrigger ? 16 : 1)
                for event in plan.pattern.events {
                    XCTAssertEqual(event.pan, PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: observed[event.row]))
                    XCTAssertEqual(event.gain, 0.5) // G01 consumes the sample default once.
                }
            }
        }
        let right = render(song([cell(note: 49, instrument: 1, volume: 0xCF)]), 48_000)
        XCTAssertGreaterThan(right.block.interleavedPCM[0], 0) // CF is 240, not the 255 endpoint.
        XCTAssertGreaterThan(right.block.interleavedPCM[1], right.block.interleavedPCM[0])
    }

    func testSampleDefaultsThenColumnThen8xxKeepTheirPrecedence() {
        let effectPans: [UInt8] = [0, 1, 16, 37, 64, 85, 127, 128, 129, 160, 192, 224, 240, 254, 255, 64]
        for rate in [44_100.0, 48_000] {
            let cells = effectPans.enumerated().map { cell(note: 49, instrument: 1,
                volume: UInt8(0xC0 + $0.offset), effect: 8, param: $0.element) }
            let plan = adapt(song(cells), rate)
            XCTAssertEqual(plan.xmChannelRows.map { $0.controls.panningValue }, effectPans.map(Double.init))
            XCTAssertEqual(plan.pattern.events.map(\.pan), effectPans.map { PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: Int($0)) })
            XCTAssertEqual(plan.diagnostics.eventMappings.map { $0.volumeColumn.appliedPanningValue }, observed)
            for header: UInt8 in [0, 1, 64, 128, 224, 254, 255] {
                let plain = adapt(song([cell(note: 49, instrument: 1)], header: header), rate)
                XCTAssertEqual(plain.xmChannelRows.first?.controls.panningValue, Double(header))
                XCTAssertEqual(plain.pattern.events.first?.pan, PlaybackSamplePanningPolicy.plannedPan(header))
            }
        }
    }

    func testG09SlidesStartFromC8WithExistingTimingZeroFormsAndClamps() {
        for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] {
                let plan = adapt(song([cell(note: 49, instrument: 1, volume: 0xC8), cell(volume: 0xD1),
                    cell(volume: 0xC8), cell(volume: 0xE1), cell(volume: 0xD0), cell(volume: 0xE0)], speed: speed), rate)
                let slides = plan.diagnostics.voiceStateUpdates.filter { (0xD0...0xEF).contains($0.rawVolumeColumn ?? 0) }
                XCTAssertEqual(slides.filter { $0.syntheticRow == 1 }.map(\.channelPanningValueAfter), (1..<speed).map { Double(128 - $0) })
                XCTAssertEqual(slides.filter { $0.syntheticRow == 3 }.map(\.channelPanningValueAfter), (1..<speed).map { Double(128 + $0) })
                XCTAssertEqual(slides.filter { $0.syntheticRow == 4 }.map(\.channelPanningValueAfter), Array(repeating: 0, count: speed - 1))
                XCTAssertEqual(slides.filter { $0.syntheticRow == 5 }.map(\.channelPanningValueAfter), Array(repeating: 0, count: speed - 1))
                XCTAssertTrue(slides.allSatisfy { $0.syntheticTick > 0 && !$0.effectMemoryReused })
                for update in slides {
                    XCTAssertEqual(update.scheduledFrame, (update.syntheticRow * speed + update.syntheticTick) * Int(rate / 50))
                }
            }
            let edge = adapt(song([cell(note: 49, instrument: 1, volume: 0xCF), cell(volume: 0xEF)]), rate)
            XCTAssertEqual(edge.diagnostics.voiceStateUpdates.filter { $0.rawVolumeColumn == 0xEF }.map(\.channelPanningValueAfter), [255, 255, 255, 255, 255])
        }
    }

    func testSourceLessEmptyAndCompletedChannelsCarryWithoutInventingVoices() {
        for rate in [44_100.0, 48_000] {
            let cold = adapt(song((0..<16).map { cell(instrument: $0 == 0 ? 1 : 0, volume: UInt8(0xC0 + $0)) }
                + [cell(note: 49)]), rate)
            XCTAssertEqual(cold.xmChannelRows.prefix(16).map { $0.controls.panningValue }, observed.map(Double.init))
            XCTAssertEqual(cold.pattern.events.count, 1)
            XCTAssertEqual(cold.pattern.events.first?.pan, PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: 240))
            XCTAssertTrue(cold.diagnostics.voiceStateUpdates.allSatisfy { !$0.activeVoiceUpdated })
            for empty in [false, true] {
                let result = render(song([cell(note: empty ? 50 : 49, instrument: 1, volume: 0xC8),
                    cell(volume: 0xC4), cell(note: 49)], empty: empty, oneShot: !empty), rate)
                XCTAssertEqual(result.plan.pattern.events.count, empty ? 1 : 2)
                XCTAssertEqual(result.plan.xmChannelRows.map { $0.controls.panningValue }, [128, 64, 64])
                XCTAssertEqual(result.plan.pattern.events.last?.pan, PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: 64))
                let rowFrames = 6 * Int(rate / 50)
                XCTAssertTrue(result.block.interleavedPCM[(rowFrames * 2)..<(rowFrames * 4)].allSatisfy { $0 == 0 })
            }
        }
    }

    func testG06AndG07UseCorrectedBaseWithoutChangingTheirClockOrArithmetic() throws {
        for rate in [44_100.0, 48_000] {
            let cells = [cell(note: 49, instrument: 1, volume: 0xC8), cell(volume: 0xC4, effect: 0x15, param: 8),
                cell(volume: 0xCF), cell(volume: 0xC8)]
            let plan = adapt(song(cells, panEnvelope: true), rate)
            let baseline = adapt(song(cells.map { cell(note: $0.note, instrument: $0.instrument,
                effect: $0.effectType, param: $0.effectParam) }, panEnvelope: true), rate)
            XCTAssertEqual(plan.xmEnvelopeTimeline?.updates.map(\.state), baseline.xmEnvelopeTimeline?.updates.map(\.state))
            let states = try XCTUnwrap(plan.xmEnvelopeTimeline?.updates)
            let targets = try XCTUnwrap(plan.xmAudibleTimeline?.updates)
            XCTAssertEqual(states[6].channelPanningValue, 64)
            XCTAssertEqual(states[6].state.panTick, 8)
            XCTAssertEqual(states[6].state.panValue, 0.75)
            // Reference final byte 96 at L08; retain G40's current static conversion.
            XCTAssertEqual(targets[6].pan, PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: 64) + 0.25, accuracy: 1e-7)
            XCTAssertEqual(targets[6].scheduledFrame, 6 * Int(rate / 50))
            XCTAssertEqual(targets[12].pan, PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: 240))
            XCTAssertTrue(targets.allSatisfy { $0.amplitude == 0.5 })
        }
    }

    func testWholeWindowAndRuntimePlansKeepCorrectedTargetsAtBothRates() throws {
        for rate in [44_100.0, 48_000] {
            for envelope in [false, true] {
                let module = song(columnCells(), panEnvelope: envelope)
                for profile in [MixerMixProfile.vtx, .ft2] {
                    let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate, mixProfile: profile), rows: 16)
                    let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
                    XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, full.plan)
                    XCTAssertEqual(full.plan.xmEnvelopeTimeline?.updates.map(\.channelPanningValue), observed.flatMap { Array(repeating: Double($0), count: 6) })
                    for rows in [1, 3, 5] {
                        let window = renderer.renderWindowed(request, windowRows: rows)
                        XCTAssertEqual(window.block.frameCount, full.block.frameCount)
                        XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
                    }
                }
            }
        }
    }

    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func columnCells(retrigger: Bool = false) -> [PlaybackCell] {
        (0..<16).map { index in
            let starts = retrigger || index == 0
            return cell(note: starts ? 49 : 0, instrument: starts ? 1 : 0, volume: UInt8(0xC0 + index))
        }
    }

    private func song(_ cells: [PlaybackCell], speed: Int = 6, header: UInt8 = 37,
                      panEnvelope: Bool = false, empty: Bool = false, oneShot: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 256),
            volume: 0.5, panning: header, relativeNote: 0, finetune: 0, baseSampleRate: 8_363,
            loopStart: 0, loopLength: oneShot ? 0 : 256, loopType: oneShot ? 0 : 1)
        let volume = PlaybackVolumeEnvelope(enabled: true, points: [.init(tick: 0, value: 64), .init(tick: 100, value: 64)],
            sustainPointIndex: panEnvelope ? 1 : nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: panEnvelope ? 3 : 1, fadeout: 0)
        let pan = PlaybackPanningEnvelope(enabled: panEnvelope,
            points: panEnvelope ? [.init(tick: 0, value: 32), .init(tick: 4, value: 16), .init(tick: 8, value: 48), .init(tick: 12, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: panEnvelope ? 1 : 0)
        var map = Array(repeating: 0, count: 96)
        if empty { map[49] = 1 }
        return PlaybackSong(title: "Public G11 control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: volume, panningEnvelope: pan, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true,
            xmSampleSlotProvenanceByInstrument: empty ? [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: 32, panning: header, finetune: 0, relativeNote: 0)]] : [:])
    }

    private func adapt(_ module: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: rate)
    }

    private func render(_ module: PlaybackSong, _ rate: Double) -> PlaybackSongOfflineRenderResult {
        PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate), rows: module.patternsByIndex[0]!.rows.count))
    }
}
