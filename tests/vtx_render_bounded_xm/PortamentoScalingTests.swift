import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class PortamentoScalingTests: XCTestCase {
    // FT2 replayer at 87be42543dac82cf802b5bddad917bda62ace131:
    // normal/fine = param << 2, extra-fine = param, volume Fx = x << 6.
    // VTX Linear periods equal FT2 units; VTX Amiga periods equal FT2 units * 4.
    func testParsedPublicFixturesPinPeriodsAndBoundedWindowedPCM() throws {
        for linear in [true, false] {
            let name = "portamento-scaling-\(linear ? "linear" : "amiga").xm"
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("reference-xm/generated/\(name)")
            let metadata = try ModuleMetadataLoader().load(fromPath: fixture.path)
            let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixture.path)
            XCTAssertEqual(song.usesLinearFrequencyTable, linear)
            let rows = linear ? 56 : 16
            let request = PlaybackSongOfflineRenderRequest(
                song: song, config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2), rows: rows
            )
            let renderer = PlaybackSongOfflineRenderer()
            let bounded = renderer.render(request)
            let windowed = renderer.renderWindowed(request, windowRows: 3)
            XCTAssertEqual(bounded.block.frameCount, rows * 5_760)
            XCTAssertTrue(bounded.block.interleavedPCM.contains { $0 != 0 })
            for row in stride(from: 0, to: rows, by: 8) {
                let caseStart = row * 5_760 * 2
                let noteWindow = bounded.block.interleavedPCM[caseStart..<(caseStart + 5_760 * 2)]
                XCTAssertTrue(noteWindow.contains { abs($0) > 0.01 }, "Case at row \(row) must reset the previous mute")
            }
            XCTAssertEqual(windowed.block.interleavedPCM.count, bounded.block.interleavedPCM.count)
            XCTAssertTrue(zip(windowed.block.interleavedPCM, bounded.block.interleavedPCM)
                .allSatisfy { abs($0 - $1) <= 1e-6 })
            let diagnostics = bounded.diagnostics
            let slides = diagnostics.portamentoSlideEffects
            XCTAssertEqual(slides.map(\.effectParam), linear ? [16, 0, 16, 0] : [16, 0])
            XCTAssertEqual(slides.map(\.source.rowIndex), linear ? [2, 4, 10, 12] : [2, 4])
            XCTAssertEqual(slides.first?.stepUpdates.map(\.linearPeriodAfter),
                           linear ? [4_544, 4_480, 4_416, 4_352, 4_288] : [7_104, 7_360, 7_616, 7_872, 8_128])
            let tones = diagnostics.tonePortamentoEffects
            XCTAssertEqual(tones.map(\.source.rowIndex), linear ? [18, 20, 26, 28, 34, 36] : [10, 12])
            XCTAssertEqual(tones.first?.stepUpdates.map(\.linearPeriodAfter),
                           linear ? [4_544, 4_480, 4_416, 4_352, 4_288] : [6_592, 6_336, 6_080, 5_824, 5_568])
            XCTAssertEqual(tones[1].stepUpdates.map(\.linearPeriodAfter),
                           linear ? [4_224, 4_160] : [5_312, 5_056, 4_800, 4_560])
            XCTAssertEqual(tones[1].stepUpdates.last?.reachedTarget, true)
            XCTAssertEqual(diagnostics.finePortamentoUpEffects.map(\.currentLinearPeriodAfter), linear ? [4_548] : [])
            XCTAssertEqual(diagnostics.finePortamentoDownEffects.map(\.currentLinearPeriodAfter), linear ? [4_608] : [])
            XCTAssertEqual(diagnostics.extraFinePortamentoEffects.map(\.currentLinearPeriodAfter), linear ? [4_593, 4_608] : [])
        }
    }

    func testNormalSlidesAndZeroParameterMemoryPinEveryTick() throws {
        for linear in [true, false] {
            for command: UInt8 in linear ? [1, 2] : [2] {
                for amount: UInt8 in [1, 16, 128] {
                    let plan = adapt([cell(note: 49), cell(command, amount), cell(command, 0)], linear: linear)
                    let effects = plan.diagnostics.portamentoSlideEffects
                    XCTAssertEqual(effects.map(\.slideAmount), [Int(amount), Int(amount)])
                    XCTAssertEqual(effects.map(\.effectMemoryReused), [false, true])
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    let updates = effects.flatMap(\.stepUpdates)
                    XCTAssertEqual(updates.map(\.scheduledFrame), [4_800, 5_760, 6_720, 8_640, 9_600, 10_560])
                    let start = linear ? 4_608.0 : 6_848.0
                    let delta = Double(amount) * (linear ? 4 : 16) * (command == 1 ? -1 : 1)
                    for (index, update) in updates.enumerated() {
                        assertStep(update, before: start + Double(index) * delta,
                                   after: start + Double(index + 1) * delta, linear: linear)
                    }
                }
            }
        }
    }

    func testFineAndExtraFineRatiosAtRowStartAndSameCellTrigger() throws {
        for amount: UInt8 in [1, 7, 15] {
            for up in [true, false] {
                for fine in [true, false] {
                    let command: UInt8 = fine ? 0x0E : 0x21
                    let parameter = (up ? UInt8(0x10) : 0x20) | amount
                    let delta = Double(amount) * (fine ? 4 : 1) * (up ? -1 : 1)
                    let plan = adapt([cell(command, parameter, note: 49), cell(command, parameter),
                                      cell(command, parameter & 0xF0)])
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    XCTAssertEqual(try XCTUnwrap(plan.pattern.events.first).playbackStep,
                                   step(4_608 + delta, linear: true), accuracy: 1e-12)
                    let diagnostics = plan.diagnostics
                    let updates = fine
                        ? (up ? diagnostics.finePortamentoUpEffects.flatMap(\.stepUpdates)
                              : diagnostics.finePortamentoDownEffects.flatMap(\.stepUpdates))
                        : diagnostics.extraFinePortamentoEffects.flatMap(\.stepUpdates)
                    XCTAssertEqual(updates.count, 1) // Same-cell adjustment is folded into the trigger; zero stays no-op.
                    let update = try XCTUnwrap(updates.first)
                    XCTAssertEqual(update.syntheticTick, 0)
                    XCTAssertEqual(update.scheduledFrame, 3_840)
                    assertStep(update, before: 4_608 + delta, after: 4_608 + 2 * delta, linear: true)
                }
            }
        }
    }

    func testToneTargetsClampWithoutRetriggerAnd300KeepsSpeed() throws {
        for linear in [true, false] {
            for note: UInt8 in [48, 61] {
                for amount: UInt8 in [1, 16, 255] {
                    let plan = adapt([cell(note: 49), cell(3, amount, note: note), cell(3, 0)], linear: linear)
                    let target = linear ? 4_608 - Double(Int(note) - 49) * 64 : (note == 48 ? 7_256 : 3_424)
                    let effects = plan.diagnostics.tonePortamentoEffects
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    XCTAssertEqual(effects.map(\.portamentoSpeed), [Int(amount), Int(amount)])
                    XCTAssertTrue(effects.allSatisfy { !$0.noteTriggerEventCreated && !$0.samplePositionReset })
                    XCTAssertEqual(linear ? effects.first?.targetLinearPeriod : effects.first?.targetAmigaPeriod, target)
                    var period = linear ? 4_608.0 : 6_848.0
                    let delta = Double(amount) * (linear ? 4 : 16)
                    let count = min(6, Int(ceil(abs(period - target) / delta)))
                    let updates = effects.flatMap(\.stepUpdates)
                    XCTAssertEqual(updates.count, count)
                    for (index, update) in updates.enumerated() {
                        let next = target < period ? max(target, period - delta) : min(target, period + delta)
                        assertStep(update, before: period, after: next, linear: linear)
                        XCTAssertEqual(update.syntheticTick, index % 3 + 1)
                        XCTAssertEqual(update.scheduledFrame, (index / 3 + 1) * 3_840 + (index % 3 + 1) * 960)
                        XCTAssertEqual(update.reachedTarget, next == target)
                        period = next
                    }
                }
            }
        }
    }

    func testVolumeColumnUses3xxEquivalentSpeedAndSharesExistingMemory() throws {
        for nibble: UInt8 in [1, 7, 15] {
            let volume = adapt([cell(note: 49), cell(note: 61, volume: 0xF0 | nibble),
                                cell(volume: 0xF0), cell(3, 0)])
            let effect = adapt([cell(note: 49), cell(3, nibble << 4, note: 61), cell(3, 0), cell(3, 0)])
            XCTAssertEqual(volume.pattern.events.count, 1)
            XCTAssertEqual(volume.diagnostics.tonePortamentoEffects.map(\.portamentoSpeed),
                           Array(repeating: Int(nibble) * 16, count: 3))
            XCTAssertEqual(volume.diagnostics.tonePortamentoEffects.flatMap(\.stepUpdates),
                           effect.diagnostics.tonePortamentoEffects.flatMap(\.stepUpdates))
            let first = try XCTUnwrap(volume.diagnostics.tonePortamentoEffects.first?.stepUpdates.first)
            assertStep(first, before: 4_608, after: max(3_840, 4_608 - Double(nibble) * 64), linear: true)
        }
    }

    func testCombined5xyKeepsIndependentVolumeSlideAndMemory() {
        let plan = adapt([cell(note: 49, volume: 0x30), cell(3, 1, note: 61), cell(5, 2), cell(5, 0)])
        XCTAssertEqual(plan.pattern.events.count, 1)
        let tones = plan.diagnostics.tonePortamentoEffects
        XCTAssertEqual(tones.map(\.portamentoSpeed), [1, 1, 1])
        XCTAssertEqual(tones.flatMap(\.stepUpdates).map(\.linearPeriodAfter), (1...9).map { 4_608 - Double($0) * 4 })
        let volumes = plan.diagnostics.voiceStateUpdates.filter { $0.effectType == 5 && $0.applied }
        XCTAssertEqual(volumes.map(\.effectiveVolumeAfter), [30, 28, 26, 24, 22, 20])
        XCTAssertEqual(volumes.map(\.syntheticTick), [1, 2, 3, 1, 2, 3])
        XCTAssertEqual(volumes.map(\.effectMemoryReused), [false, false, false, true, true, true])
    }

    func testLinearSpeedConversionLeavesDeferredAmigaVolumeMemoryUnchanged() {
        // Existing no-note Amiga Fx can touch a prior 3xx target despite being deferred.
        // Preserve that state here; this is not an Amiga Fx compatibility/support claim.
        let plan = adapt([cell(note: 49), cell(3, 1, note: 61), cell(volume: 0xF4), cell(3, 0)], linear: false)
        XCTAssertEqual(plan.diagnostics.tonePortamentoEffects.map(\.portamentoSpeed), [1, 4, 4])
    }

    private func assertStep(_ update: PlaybackSongSyntheticTonePortamentoStepUpdate,
                            before: Double, after: Double, linear: Bool,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(linear ? update.linearPeriodBefore : update.amigaPeriodBefore, before, file: file, line: line)
        XCTAssertEqual(linear ? update.linearPeriodAfter : update.amigaPeriodAfter, after, file: file, line: line)
        XCTAssertEqual(update.playbackStepBefore, step(before, linear: linear), accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(update.playbackStepAfter, step(after, linear: linear), accuracy: 1e-12, file: file, line: line)
    }

    private func step(_ period: Double, linear: Bool) -> Double {
        // Normalize VTX's Amiga period to the FT2 table domain before converting to Hz.
        let frequency = linear ? 8_363 * pow(2, (4_608 - period) / 768) : 8_363 * 1_712 / (period / 4)
        return frequency / 48_000
    }

    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                      volume: UInt8 = 0) -> PlaybackCell {
        PlaybackCell(note: note, instrument: note == 49 ? 1 : 0, volumeColumn: volume,
                     effectType: effect, effectParam: parameter)
    }

    private func adapt(_ cells: [PlaybackCell], linear: Bool = true) -> PlaybackSongSyntheticPlan {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0, 0.5, 0, -0.5],
                                    volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363,
                                    loopLength: 4, loopType: 1)
        let song = PlaybackSong(
            title: "Portamento units", orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: cells.enumerated().map {
                PlaybackRow(index: $0.offset, cells: [$0.element])
            })], instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample],
                                                           noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: PlaybackTiming(speed: 4, bpm: 125),
            usesLinearFrequencyTable: linear
        )
        return PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 48_000)
    }
}
