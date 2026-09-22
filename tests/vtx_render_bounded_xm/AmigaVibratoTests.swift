import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class AmigaVibratoTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testExactUnsignedPeriodArithmeticBeforeFourTimesMapping() throws {
        // Executed against unchanged ft2-clone 87be42543dac82cf802b5bddad917bda62ace131.
        for (base, delta, result) in [(1712, 0, 1712), (1712, 63, 1775), (1712, -63, 1649),
                                     (120, -119, 1), (119, -119, 0), (118, -119, 65535),
                                     (22, -119, 65439), (65535, 119, 118), (65417, 119, 0)] {
            let period = Adapter.vibratoAmigaPeriod(basePeriod: Double(base * 4), signedReferenceDelta: delta)
            XCTAssertEqual(period, Double(result * 4))
            XCTAssertEqual(try XCTUnwrap(Adapter.playbackStep(amigaPeriod: period, baseSampleRate: 8363,
                                                             outputSampleRate: 48000)), step(result), accuracy: 1e-12)
        }
        XCTAssertEqual(Adapter.amigaPeriodFromLookup(effectiveNoteValue: 49, finetune: 0), 1712 * 4)
        XCTAssertEqual(Adapter.amigaPeriodFromLookup(effectiveNoteValue: 95, finetune: 8), 119 * 4)
        for invalid in [-1.0, .nan, .infinity] {
            XCTAssertNil(Adapter.playbackStep(amigaPeriod: invalid, baseSampleRate: 8363, outputSampleRate: 48000))
        }
    }

    func testBothWaveformHalvesPhaseWrapMemoryAndUnchangedBase() throws {
        let plan = adapt([cell(4, 0x48, note: 49, instrument: 1), cell(4), cell(4), cell(4),
                          cell(4, 3), cell(4, 0x80), cell()])
        let effects = plan.diagnostics.vibratoEffects
        XCTAssertTrue(effects.allSatisfy(\.applied))
        XCTAssertEqual(effects.map(\.vibratoSpeed), [4, 4, 4, 4, 4, 8])
        XCTAssertEqual(effects.map(\.vibratoDepth), [8, 8, 8, 8, 3, 3])
        XCTAssertEqual(effects.map(\.phaseBefore), [0, 80, 160, 240, 64, 144])
        XCTAssertEqual(effects.map(\.effectMemoryReused), [false, true, true, true, true, true])
        let trajectory = [1712, 1736, 1757, 1770, 1775, 1770, 1757, 1736, 1712,
                          1688, 1667, 1654, 1649, 1654, 1667, 1688, 1712]
        let updates = effects.flatMap(\.stepUpdates)
        XCTAssertEqual(Array(updates.prefix(17)).map(\.amigaPeriodAfter), trajectory.map { Double($0 * 4) })
        XCTAssertEqual(effects[1].stepUpdates.first?.amigaPeriodBefore, 1775 * 4)
        XCTAssertEqual(effects.last?.stepUpdates.last?.amigaPeriodAfter, 1712 * 4)
        for effect in effects {
            XCTAssertNil(effect.currentLinearPeriodAfter)
            for update in effect.stepUpdates {
                let result = try XCTUnwrap(update.amigaPeriodAfter)
                if let modulation = update.vibrato {
                    XCTAssertEqual(result, Double((1712 + modulation.signedReferenceDelta) * 4))
                }
                XCTAssertEqual(update.playbackStepAfter, step(Int(result / 4)), accuracy: 1e-12)
                XCTAssertEqual(update.scheduledFrame, effect.source.rowIndex * 5760 + update.syntheticTick * 960)
            }
        }
        let slides = adapt([cell(4, 0x48, note: 49, instrument: 1), cell(2, 0x10), cell(4)])
        XCTAssertEqual(slides.diagnostics.vibratoEffects.last?.stepUpdates.first?.amigaPeriodBefore, 8128)
    }

    func testEveryE4ControlReusesSharedTriggerAndNoteOnlyRules() throws {
        for control in 0...15 {
            let effects = adapt([cell(14, 0x40 | UInt8(control)), cell(4, 0x48, note: 49, instrument: 1),
                                 cell(4, instrument: 1), cell(4, note: 49), cell(4)]).diagnostics.vibratoEffects
            XCTAssertEqual(effects.map(\.phaseBefore), control & 4 == 0 ? [0, 0, 80, 160] : [0, 80, 160, 240])
            for update in effects.flatMap(\.stepUpdates) {
                let tick = try XCTUnwrap(update.vibrato)
                XCTAssertEqual(tick, Adapter.vibratoTick(phase: tick.phaseBefore, speed: 4, depth: 8, control: control))
                XCTAssertEqual(update.amigaPeriodAfter, Double((1712 + tick.signedReferenceDelta) * 4))
            }
        }
        for suppressed in [false, true] {
            let effects = adapt([cell(14, suppressed ? 0x44 : 0x40), cell(4, 0x48, note: 49, instrument: 1),
                                 cell(14, suppressed ? 0x40 : 0x44, instrument: 1), cell(4)]).diagnostics.vibratoEffects
            XCTAssertEqual(effects.last?.phaseBefore, suppressed ? 80 : 0)
        }
    }

    func testSeeded6xyPreservesPitchWhile600ReplaysOnNonzeroTicks() {
        let mixed = adapt([cell(4, 0x48, note: 49, instrument: 1, volume: 0x30), cell(6, 2), cell(6), cell(6, 0x12)])
        let pure = adapt([cell(4, 0x48, note: 49, instrument: 1, volume: 0x30), cell(4), cell(4), cell(4)])
        XCTAssertEqual(mixed.diagnostics.vibratoEffects.map(\.stepUpdates), pure.diagnostics.vibratoEffects.map(\.stepUpdates))
        let volume = mixed.diagnostics.voiceStateUpdates.filter { $0.effectType == 6 }
        XCTAssertEqual(volume.map(\.syntheticTick), Array(repeating: [1, 2, 3, 4, 5], count: 3).flatMap { $0 })
        XCTAssertEqual(volume.map(\.effectiveVolumeAfter), [30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 13, 14, 15, 16, 17])
        XCTAssertTrue(volume[5].applied)
        XCTAssertTrue(volume[5].effectMemoryReused)
    }

    func testValidNoteReachesZeroAndUnderflowWithoutClampingOrRetrigger() throws {
        for (finetune, base, result) in [(8, 119, 0), (24, 118, 65535)] {
            let plan = adapt([cell(4, 0x4F, note: 95, instrument: 1), cell(4), cell(4), cell(4)], finetune: finetune)
            XCTAssertEqual(plan.pattern.events.count, 1)
            let update = plan.diagnostics.vibratoEffects[2].stepUpdates[2]
            XCTAssertEqual(update.vibrato?.signedReferenceDelta, -119)
            XCTAssertEqual(update.amigaPeriodAfter, Double(result * 4))
            XCTAssertEqual(update.playbackStepAfter, step(result), accuracy: 1e-12)
            XCTAssertEqual(update.scheduledFrame, 14400)
            XCTAssertEqual(plan.diagnostics.eventMappings.first?.amigaPeriod, Double(base * 4))
            let resume = plan.diagnostics.vibratoEffects[2].stepUpdates[3]
            XCTAssertEqual(resume.amigaPeriodBefore, Double(result * 4))
            XCTAssertEqual(resume.amigaPeriodAfter, Double((base - 110) * 4))
            XCTAssertGreaterThan(resume.playbackStepAfter, 0)
        }
    }

    func testPublicFixtureRendersAcrossWindowBoundariesIncludingZeroHold() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/amiga-vibrato.xm")
        let song = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        XCTAssertFalse(song.usesLinearFrequencyTable)
        let request = PlaybackSongOfflineRenderRequest(song: song, config: MixerRenderConfig(sampleRate: 48000, channelCount: 1), rows: 30)
        let renderer = PlaybackSongOfflineRenderer()
        let bounded = renderer.render(request), windowed = renderer.renderWindowed(request, windowRows: 1)
        XCTAssertEqual(bounded.block.frameCount, 172800)
        XCTAssertEqual(bounded.block.interleavedPCM.count, windowed.block.interleavedPCM.count)
        XCTAssertLessThanOrEqual(zip(bounded.block.interleavedPCM, windowed.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-6)
        XCTAssertTrue(bounded.diagnostics.vibratoEffects.allSatisfy(\.applied))
        let zero = try XCTUnwrap(bounded.diagnostics.vibratoEffects.flatMap(\.stepUpdates).first { $0.playbackStepAfter == 0 })
        XCTAssertEqual(zero.scheduledFrame, 158400)
        let pcm = bounded.block.interleavedPCM
        XCTAssertTrue(pcm[158400..<159360].allSatisfy { $0 == pcm[158400] })
        XCTAssertNotEqual(pcm[159361], pcm[159360])
    }

    private func step(_ period: Int) -> Double { period == 0 ? 0 : 8363 * 1712 / Double(period) / 48000 }

    private func cell(_ effect: UInt8 = 0, _ param: UInt8 = 0, note: UInt8 = 0,
                      instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        PlaybackCell(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func adapt(_ cells: [PlaybackCell], finetune: Int = 0) -> PlaybackSongSyntheticPlan {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0, 0.5, 0, -0.5], volume: 1,
            relativeNote: 0, finetune: finetune, baseSampleRate: 8363, loopLength: 4, loopType: 1)
        let song = PlaybackSong(title: "Amiga vibrato", orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: cells.enumerated().map { PlaybackRow(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: PlaybackTiming(speed: 6, bpm: 125), usesLinearFrequencyTable: false)
        return Adapter.adapt(song, orderIndex: 0, sampleRate: 48000)
    }
}
