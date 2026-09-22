import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class VibratoFoundationTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testIntegerTrajectorySamplesBeforeAdvanceAcrossBothHalvesAndWrap() {
        // Executed against unchanged ft2-clone 87be42543dac82cf802b5bddad917bda62ace131.
        let phases = [0, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 240, 0]
        let magnitudes = [0, 97, 180, 235, 255, 235, 180, 97, 0, 97, 180, 235, 255, 235, 180, 97, 0]
        let deltas = [0, 24, 45, 58, 63, 58, 45, 24, 0, -24, -45, -58, -63, -58, -45, -24, 0]
        var phase = 0
        for index in phases.indices {
            let tick = Adapter.vibratoTick(phase: phase, speed: 4, depth: 8, control: 0)
            XCTAssertEqual(tick.phaseBefore, phases[index])
            XCTAssertEqual(tick.waveformMagnitude, magnitudes[index])
            XCTAssertEqual(tick.waveformSign, phases[index] < 128 ? 1 : -1)
            XCTAssertEqual(tick.depth, 8)
            XCTAssertEqual(tick.signedReferenceDelta, deltas[index])
            XCTAssertEqual(tick.phaseAfter, (phases[index] + 16) & 255)
            phase = tick.phaseAfter
        }
        XCTAssertEqual(Adapter.vibratoTick(phase: 64, speed: 15, depth: 15, control: 2).signedReferenceDelta, 119)
    }

    func testEveryE4AliasUsesExactWaveformAndResetSuppression() throws {
        let phases = [0, 32, 64, 96, 128, 160, 192, 224]
        let magnitudes = [[0, 180, 255, 180, 0, 180, 255, 180],
                          [0, 64, 128, 192, 255, 191, 127, 63],
                          Array(repeating: 255, count: 8)]
        let deltas = [[0, 45, 63, 45, 0, -45, -63, -45],
                      [0, 16, 32, 48, -63, -47, -31, -15],
                      [63, 63, 63, 63, -63, -63, -63, -63]]
        for control in 0...15 {
            let waveform = min(control & 3, 2)
            XCTAssertEqual(phases.map { Adapter.vibratoTick(phase: $0, speed: 4, depth: 8, control: control).waveformMagnitude },
                           magnitudes[waveform])
            XCTAssertEqual(phases.map { Adapter.vibratoTick(phase: $0, speed: 4, depth: 8, control: control).signedReferenceDelta },
                           deltas[waveform])
            let plan = adapt([cell(0xE, 0x40 | UInt8(control)), cell(4, 0x48, note: 49, instrument: 1),
                              cell(4, 0, note: 49, instrument: 1), cell(4, 0, note: 49), cell(4, 0)])
            let effects = plan.diagnostics.vibratoEffects
            XCTAssertEqual(plan.diagnostics.vibratoControlEffects.first?.controlValue, control)
            XCTAssertEqual(plan.diagnostics.vibratoControlEffects.first?.retriggerSuppressed, control & 4 != 0)
            XCTAssertEqual(effects.map(\.phaseBefore), control & 4 == 0 ? [0, 0, 80, 160] : [0, 80, 160, 240])
            XCTAssertEqual(effects.map(\.vibratoWaveform), Array(repeating: ["sine", "ramp_down", "square"][waveform], count: 4))
            XCTAssertEqual(plan.pattern.events.count, 2) // Existing note-only trigger boundary is retained.
        }
    }

    func testInstrumentOnlyAndSameCellControlUsePreviousResetPolicy() {
        for suppressed in [false, true] {
            let plan = adapt([cell(0xE, suppressed ? 0x44 : 0x40), cell(4, 0x48, note: 49, instrument: 1),
                              cell(0xE, suppressed ? 0x40 : 0x44, instrument: 1), cell(4, 0)])
            XCTAssertEqual(plan.diagnostics.vibratoEffects.last?.phaseBefore, suppressed ? 80 : 0)
        }
        let keyOff = adapt([cell(4, 0x48, note: 49, instrument: 1), cell(note: 97, instrument: 1),
                            cell(4, 0, note: 49, instrument: 1)])
        XCTAssertEqual(keyOff.diagnostics.vibratoEffects.last?.phaseBefore, 0)
    }

    func testMemoryAndLinearMappingPreserveOutputAcrossConsecutiveRows() throws {
        let plan = adapt([cell(4, 0x48, note: 49, instrument: 1), cell(4, 0), cell(4, 3), cell(4, 0x80), cell()])
        let effects = plan.diagnostics.vibratoEffects
        XCTAssertEqual(effects.map(\.vibratoSpeed), [4, 4, 4, 8])
        XCTAssertEqual(effects.map(\.vibratoDepth), [8, 8, 3, 3])
        XCTAssertEqual(effects.map(\.phaseBefore), [0, 80, 160, 240])
        XCTAssertEqual(effects.map(\.phaseAfter), [80, 160, 240, 144])
        XCTAssertEqual(effects.map(\.effectMemoryReused), [false, true, true, true])
        XCTAssertEqual(effects[0].stepUpdates.map(\.linearPeriodAfter), [4608, 4632, 4653, 4666, 4671])
        XCTAssertEqual(effects[1].stepUpdates.map(\.linearPeriodAfter), [4666, 4653, 4632, 4608, 4584])
        XCTAssertEqual(effects[1].stepUpdates.first?.linearPeriodBefore, 4671)
        XCTAssertEqual(effects[0].stepUpdates.count, 5) // No tick-zero reset between 4xy rows.
        XCTAssertEqual(effects.last?.stepUpdates.last?.syntheticTick, 6)
        XCTAssertEqual(effects.last?.stepUpdates.last?.linearPeriodAfter, 4608)
        for effect in effects {
            for update in effect.stepUpdates {
                XCTAssertEqual(update.playbackStepBefore, step(update.linearPeriodBefore), accuracy: 1e-12)
                XCTAssertEqual(update.playbackStepAfter, step(update.linearPeriodAfter), accuracy: 1e-12)
                XCTAssertEqual(update.scheduledFrame, effect.source.rowIndex * 5760 + update.syntheticTick * 960)
            }
        }
    }

    func testInitialZeroMemorySpeedOneAndNoVoiceStateAreDefined() throws {
        let zero = adapt([cell(4, 0, note: 49, instrument: 1), cell(4, 0x40), cell(4, 8)])
        XCTAssertTrue(zero.diagnostics.vibratoEffects.allSatisfy { $0.applied && !$0.effectMemoryMissing })
        XCTAssertEqual(zero.diagnostics.vibratoEffects.map(\.phaseAfter), [0, 80, 160])
        XCTAssertTrue(zero.diagnostics.vibratoEffects[1].stepUpdates.allSatisfy { $0.vibrato?.signedReferenceDelta == 0 })
        let held = adapt([cell(0xE, 0x42), cell(4, 8, note: 49, instrument: 1)])
        XCTAssertEqual(held.diagnostics.vibratoEffects[0].stepUpdates.map(\.linearPeriodAfter), Array(repeating: 4671, count: 5))
        let single = adapt([cell(4, 0x48, note: 49, instrument: 1), cell(4, 0)], speed: 1)
        XCTAssertEqual(single.diagnostics.vibratoEffects.map(\.vibratoSpeed), [0, 0])
        XCTAssertEqual(single.diagnostics.vibratoEffects.map(\.vibratoDepth), [0, 0])
        XCTAssertTrue(single.diagnostics.vibratoEffects.allSatisfy { $0.stepUpdates.isEmpty })
        let silent = adapt([cell(4, 0x48), cell(4, 0)])
        XCTAssertEqual(silent.diagnostics.vibratoEffects.map(\.phaseAfter), [80, 160])
        XCTAssertTrue(silent.pattern.events.isEmpty)
    }

    func testSeeded6xyPreservesPitchWhile600ReplaysOnNonzeroTicks() {
        let plan = adapt([cell(4, 0x48, note: 49, instrument: 1, volume: 0x30), cell(6, 2), cell(6, 0), cell(6, 0x12)])
        let pure = adapt([cell(4, 0x48, note: 49, instrument: 1, volume: 0x30), cell(4, 0), cell(4, 0), cell(4, 0)])
        XCTAssertEqual(plan.diagnostics.vibratoEffects.map(\.stepUpdates), pure.diagnostics.vibratoEffects.map(\.stepUpdates))
        let volume = plan.diagnostics.voiceStateUpdates.filter { $0.effectType == 6 }
        XCTAssertEqual(volume.map(\.syntheticTick), Array(repeating: [1, 2, 3, 4, 5], count: 3).flatMap { $0 })
        XCTAssertEqual(volume.map(\.effectiveVolumeAfter), [30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 13, 14, 15, 16, 17])
        XCTAssertEqual(volume.map(\.effectParam), [UInt8(2), 0, 0x12].flatMap { Array(repeating: $0, count: 5) })
        XCTAssertTrue(volume[5].applied)
        XCTAssertTrue(volume[5].effectMemoryReused)
    }

    func testPortamentoDoesNotRetainStaleOutputPeriod() {
        let linear = adapt([cell(4, 0x48, note: 49, instrument: 1), cell(1, 0x10), cell(4, 0)])
        XCTAssertEqual(linear.diagnostics.vibratoEffects.last?.stepUpdates.first?.linearPeriodBefore, 4288)
        XCTAssertEqual(linear.diagnostics.vibratoEffects.last?.stepUpdates.first?.playbackStepBefore, step(4288))
    }

    func testPublicFixtureRendersIdenticallyAcrossWindows() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/vibrato-semantics.xm")
        let song = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        XCTAssertTrue(song.usesLinearFrequencyTable)
        let request = PlaybackSongOfflineRenderRequest(song: song, config: MixerRenderConfig(sampleRate: 48000, channelCount: 2), rows: 46)
        let renderer = PlaybackSongOfflineRenderer()
        let bounded = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 3)
        XCTAssertEqual(bounded.block.frameCount, 264960)
        XCTAssertEqual(bounded.block.interleavedPCM.count, windowed.block.interleavedPCM.count)
        let maxDifference = zip(bounded.block.interleavedPCM, windowed.block.interleavedPCM)
            .map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThanOrEqual(maxDifference, 1e-6)
        XCTAssertTrue(bounded.diagnostics.vibratoEffects.allSatisfy(\.applied))
        XCTAssertEqual(bounded.diagnostics.vibratoControlEffects.map(\.controlValue), Array(0...15) + [0])
    }

    private func step(_ period: Double) -> Double { 8363 * pow(2, (4608 - period) / 768) / 48000 }

    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                      instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        PlaybackCell(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func adapt(_ cells: [PlaybackCell], linear: Bool = true, speed: Int = 6) -> PlaybackSongSyntheticPlan {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0, 0.5, 0, -0.5], volume: 1,
                                    relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopLength: 4, loopType: 1)
        let song = PlaybackSong(title: "Vibrato semantics", orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: cells.enumerated().map { PlaybackRow(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: PlaybackTiming(speed: speed, bpm: 125),
            usesLinearFrequencyTable: linear)
        return Adapter.adapt(song, orderIndex: 0, sampleRate: 48000)
    }
}
