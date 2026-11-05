import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class OrdinaryEDGainTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testMappedHeaderDefaultsAndExplicitSettersAtOrdinaryEDDispatch() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for header in [0, 1, 16, 32, 64] { for delay in [-1, 0, 1, 6] {
                for column: UInt8 in [0, 0xC8, 0x35] {
                    let module = song([note(delay: delay, column: column), c(), c(12, 32), c()],
                        header: header, linear: linear)
                    let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: rate)
                    if delay == 6 {
                        XCTAssertTrue(plan.pattern.events.isEmpty)
                        XCTAssertTrue(plan.diagnostics.noteDelayEffects.first?.outOfRow == true)
                        continue
                    }
                    let event = try XCTUnwrap(plan.pattern.events.first)
                    let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)
                    let expected = column == 0x35 ? 37 : header
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    XCTAssertEqual(event.gain, Float(expected) / 64)
                    XCTAssertEqual(mapping.effectiveVolumeValue, expected)
                    XCTAssertEqual(mapping.sampleIndex, 1) // S01 is a distinct, louder decoy.
                    XCTAssertEqual(mapping.sampleSelectionMethod, .sampleMap)
                    XCTAssertFalse(mapping.firstPlayableSampleFallbackUsed)
                    XCTAssertEqual(event.scheduledStartFrame, max(0, delay) * Int(rate / 50))
                    XCTAssertEqual(event.initialSourceFrame, 0)
                }
            } }
        } }
    }

    func testOnsetC20RevealAndExactWindowStreamContinuation() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for header in [0, 32] { for delay in [0, 1] {
                let module = song([note(delay: delay), c(), c(12, 32), c()],
                    header: header, linear: linear)
                let request = PlaybackSongOfflineRenderRequest(song: module,
                    config: .init(sampleRate: rate, channelCount: 1), rows: 4)
                let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
                let pcm = full.block.interleavedPCM, birth = delay * Int(rate / 50)
                let onset = Int(rate * 0.005), level = Float(header) / 128
                XCTAssertTrue(pcm.prefix(birth + 1).allSatisfy { $0 == 0 })
                XCTAssertEqual(pcm[birth + onset / 2], level / 2)
                XCTAssertEqual(pcm[birth + onset], level)
                XCTAssertEqual(pcm[18 * Int(rate / 50)], 0.25) // C20, independent of header.
                for rows in [1, 2] {
                    XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, pcm)
                }
                var streamed = [Float]()
                let stream = renderer.renderStreaming(request, chunkFrameCount: 997) { _, _, block in
                    streamed += block.interleavedPCM
                }
                XCTAssertEqual(stream.renderedFrameCount, full.block.frameCount)
                XCTAssertEqual(streamed, pcm)
#if DEBUG
                let boundaries = [birth - 1, birth, birth + 1, birth + onset / 2, birth + onset]
                    .filter { $0 > 0 }
                XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request,
                    boundaries: boundaries).block.interleavedPCM, pcm)
#endif
            } }
        } }
    }

    func testNoteOnlyInstrumentOnlyAndHeldDispatchKeepTheirOwnDefaults() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for delay: UInt8 in [0, 1] { for instrumentOnly in [false, true] {
                let target = PlaybackCell(note: instrumentOnly ? 0 : 52, instrument: instrumentOnly ? 1 : 0,
                    volumeColumn: 0, effectType: 14, effectParam: 0xD0 + delay)
                let plan = Adapter.adapt(song([note(delay: -1), c(12, 14), target, c()],
                    header: 32, linear: linear), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.pattern.events.count, instrumentOnly && delay == 0 ? 1 : 2)
                if !instrumentOnly || delay == 1 {
                    let event = try XCTUnwrap(plan.pattern.events.last)
                    XCTAssertEqual(event.gain, instrumentOnly ? 0.5 : 14.0 / 64)
                    XCTAssertEqual(event.scheduledStartFrame, (12 + Int(delay)) * Int(rate / 50))
                }
            } }
            for delay in [0, 1] {
                let plan = Adapter.adapt(song([note(delay: delay), c(), c()], header: 32,
                    linear: linear, held: true), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.pattern.events.map(\.gain), [0.5, 0.5])
                XCTAssertEqual(plan.pattern.events.map(\.scheduledStartFrame),
                    [delay, 6 + delay].map { $0 * Int(rate / 50) })
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [1, 1])
            }
        } }
    }

    func testWarmSourceKeepsItsVolumeUntilTheNewEDSourceStarts() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for delay in [0, 1] {
                let config = MixerRenderConfig(sampleRate: rate, channelCount: 1)
                let candidate = song([note(delay: -1), c(12, 14), note(delay: delay), c()],
                    header: 32, linear: linear)
                let control = song([note(delay: -1), c(12, 14), c(), c()], header: 32, linear: linear)
                let renderer = PlaybackSongOfflineRenderer()
                let actual = renderer.render(.init(song: candidate, config: config, rows: 4))
                let held = renderer.render(.init(song: control, config: config, rows: 4))
                let birth = (12 + delay) * Int(rate / 50), onset = Int(rate * 0.005)
                XCTAssertEqual(actual.plan.pattern.events.map(\.gain), [0.5, 0.5])
                XCTAssertEqual(Array(actual.block.interleavedPCM.prefix(birth)),
                    Array(held.block.interleavedPCM.prefix(birth)))
                XCTAssertEqual(actual.block.interleavedPCM[birth], 14.0 / 128)
                XCTAssertEqual(actual.block.interleavedPCM[birth + onset / 2], 14.0 / 256 + 0.125)
                XCTAssertEqual(actual.block.interleavedPCM[birth + onset], 0.25)
            }
        } }
    }

    func testVolumeColumnTonePortamentoKeepsItsSeparateEDAdmission() {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for delay in [0, 1] {
                let module = song([note(delay: -1), c(12, 14), note(delay: delay, column: 0xF4), c()],
                    header: 32, linear: linear)
                let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.pattern.events.count, 1)
                XCTAssertEqual(plan.xmChannelRows[4].controls.baseChannelVolume, 14)
                XCTAssertEqual(plan.xmChannelRows[4].controls.activeEventIndex, 0)
            }
        } }
    }

    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: 0, instrument: 0, volumeColumn: 0, effectType: effect, effectParam: parameter)
    }

    private func note(delay: Int, column: UInt8 = 0) -> PlaybackCell {
        .init(note: 52, instrument: 1, volumeColumn: column,
            effectType: delay < 0 ? 0 : 14, effectParam: delay < 0 ? 0 : UInt8(0xD0 + delay))
    }

    private func song(_ cells: [PlaybackCell], header: Int, linear: Bool, held: Bool = false) -> PlaybackSong {
        let samples = [PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: Array(repeating: -0.25, count: 128), volume: 1, relativeNote: 0,
            finetune: 0, baseSampleRate: 8363, loopLength: 128, loopType: 1),
            PlaybackSample(instrumentIndex: 1, sampleIndex: 1,
            pcm: Array(repeating: 0.5, count: 128), volume: Float(header) / 64, relativeNote: 0,
            finetune: 0, baseSampleRate: 8363, loopLength: 128, loopType: 1)]
        let rows = cells.enumerated().map { index, cell in
            PlaybackRow(index: index, cells: [cell, held && index == 0 ? c(14, 0xE1) : c()])
        }
        return PlaybackSong(title: "Ordinary ED gain", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows)],
            instrumentsByIndex: [1: .init(index: 1, samples: samples, noteSampleMap: Array(repeating: 1, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125),
            usesLinearFrequencyTable: linear)
    }
}
