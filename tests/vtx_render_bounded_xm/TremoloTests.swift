import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class TremoloTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testOrdinaryTremoloPinsEveryTrackerDomainTickBeforeSampleScaling() {
        for sample: Float in [1, 0.25] {
            let (context, states) = inspect(song([cell(7, 0x48, note: 49, instrument: 1, volume: 0x30)], sample: sample))
            let updates = tremolo(context)
            XCTAssertEqual(updates.map { $0.0.syntheticTick }, [1, 2, 3, 4, 5])
            XCTAssertEqual(updates.map { $0.0.scheduledFrame }, [1, 2, 3, 4, 5])
            XCTAssertEqual(updates.map { $0.1.phaseBefore }, [0, 16, 32, 48, 64])
            XCTAssertEqual(updates.map { $0.1.phaseAfter }, [16, 32, 48, 64, 80])
            XCTAssertEqual(updates.map { $0.1.delta }, [0, 12, 22, 29, 31])
            XCTAssertEqual(updates.map { $0.1.outputVolume }, [32, 44, 54, 61, 63])
            XCTAssertTrue(updates.allSatisfy { $0.1.baseVolume == 32 && $0.1.sampleVolume == sample && !$0.1.clamped })
            XCTAssertEqual(updates.map { $0.0.gainAfter }, [32, 44, 54, 61, 63].map { Optional(Float($0) / 64 * sample) })
            XCTAssertEqual(context.events.map(\.gain), [0.5 * sample]) // Tick 0 is the unmodulated trigger.
            XCTAssertEqual(states[0].baseChannelVolume, 32)
            XCTAssertEqual(states[0].outputChannelVolume, 63)
            XCTAssertEqual(states[0].tremolo.speed, 4)
            XCTAssertEqual(states[0].tremolo.depth, 8)
        }
    }

    func testEmptyRowHoldsOutputAndIndependentZeroNibblesKeepMemory() {
        let (context, states) = inspect(song([
            cell(7, 0x48, note: 49, instrument: 1, volume: 0x30), cell(),
            cell(7, 0), cell(7, 4), cell(7, 0x80),
        ]))
        // Executed against unchanged ft2-clone 87be42543dac82cf802b5bddad917bda62ace131.
        for (row, outputs, phases) in [
            (2, [61, 54, 44, 32, 20], [80, 96, 112, 128, 144]),
            (3, [21, 18, 17, 18, 21], [160, 176, 192, 208, 224]),
            (4, [26, 38, 46, 46, 38], [240, 16, 48, 80, 112]),
        ] {
            XCTAssertEqual(tremolo(context, row: row).map { $0.1.outputVolume }, outputs)
            XCTAssertEqual(tremolo(context, row: row).map { $0.1.phaseBefore }, phases)
        }
        XCTAssertEqual(states.map(\.baseChannelVolume), [32, 32, 32, 32, 32])
        XCTAssertEqual(states.map(\.outputChannelVolume), [63, 63, 20, 21, 38])
        XCTAssertEqual(states.map { $0.tremolo.phase }, [80, 80, 160, 240, 144])
        XCTAssertEqual(states.map { $0.tremolo.speed }, [4, 4, 4, 4, 8])
        XCTAssertEqual(states.map { $0.tremolo.depth }, [8, 8, 8, 4, 4])
        XCTAssertFalse(context.voiceStateUpdates.contains { $0.source.rowIndex == 1 })
    }

    func testTickZeroDoesNotSetMemoryAndInitialZeroMemoryRemainsDeterministic() {
        let (_, singleTick) = inspect(song([cell(7, 0x48, note: 49, instrument: 1, volume: 0x30)], speed: 1))
        XCTAssertEqual(singleTick[0].tremolo.speed, 0)
        XCTAssertEqual(singleTick[0].tremolo.depth, 0)
        XCTAssertEqual(singleTick[0].tremolo.phase, 0)
        XCTAssertEqual(singleTick[0].outputChannelVolume, 32)
        let (context, _) = inspect(song([cell(7, 0, note: 49, instrument: 1, volume: 0x30)]))
        XCTAssertEqual(tremolo(context).map { $0.1.outputVolume }, [32, 32, 32, 32, 32])
        XCTAssertEqual(tremolo(context).map { $0.1.phaseAfter }, [0, 0, 0, 0, 0])
        let (silent, memory) = inspect(song([cell(7, 0x48), cell(7, 0)]))
        XCTAssertTrue(silent.events.isEmpty)
        XCTAssertEqual(memory[1].tremolo.phase, 160)
        XCTAssertEqual(memory[1].tremolo.speed, 4)
        XCTAssertEqual(memory[1].tremolo.depth, 8)
        XCTAssertTrue(tremolo(silent).allSatisfy { $0.1.sampleVolume == nil && !$0.0.activeVoiceUpdated })
    }

    func testEveryControlHasEvidencedWaveformAndPhaseResetPolicy() {
        let phases = [0, 32, 64, 96, 128, 160, 192, 224]
        let deltas = [[0, 22, 31, 22, 0, -22, -31, -22],
                      [0, 8, 16, 24, 0, -8, -16, -24],
                      [31, 31, 31, 31, -31, -31, -31, -31]]
        for control in 0...15 {
            XCTAssertEqual(phases.map { Adapter.tremoloDelta(phase: $0, depth: 8, control: control, vibratoPhase: 0) },
                           deltas[min(control & 3, 2)])
            let (context, states) = inspect(song([
                cell(0x0E, 0x70 | UInt8(control)),
                cell(7, 0x48, note: 49, instrument: 1, volume: 0x30),
                cell(7, 0, note: 49, instrument: 1, volume: 0x30),
                cell(7, 0, note: 49), // Note-only continuation must not reset phase.
            ]))
            let resetSuppressed = control & 4 != 0
            XCTAssertEqual(states[3].tremolo.control, control)
            XCTAssertEqual(tremolo(context, row: 2).first?.1.phaseBefore, resetSuppressed ? 80 : 0)
            XCTAssertEqual(tremolo(context, row: 3).first?.1.phaseBefore, resetSuppressed ? 160 : 80)
            // The existing adapter skips instrument-less note retriggers; tremolo still
            // continues on the active voice. That separate trigger boundary is unchanged.
            XCTAssertEqual(context.events.count, 2)
            XCTAssertFalse(Adapter.hasDeferredEffect(cell(0x0E, 0x70 | UInt8(control))))
        }
    }

    func testSameCellControlUsesPriorResetPolicyAndInstrumentRestoresBaseOutput() {
        for (old, new, expected) in [(0, 4, 0), (4, 0, 80)] {
            let (_, states) = inspect(song([
                cell(0x0E, 0x70 | UInt8(old)),
                cell(7, 0x48, note: 49, instrument: 1, volume: 0x30),
                cell(0x0E, 0x70 | UInt8(new), note: 49, instrument: 1),
            ]))
            XCTAssertEqual(states[2].tremolo.phase, expected)
            XCTAssertEqual(states[2].tremolo.control, new)
            XCTAssertEqual(states[2].baseChannelVolume, 64)
            XCTAssertEqual(states[2].outputChannelVolume, 64)
        }
    }

    func testTremoloControlIsIndependentAndRampUsesFT2VibratoSignQuirk() {
        XCTAssertEqual(Adapter.tremoloDelta(phase: 0, depth: 8, control: 1, vibratoPhase: 0), 0)
        XCTAssertEqual(Adapter.tremoloDelta(phase: 0, depth: 8, control: 1, vibratoPhase: 128), 31)
        XCTAssertEqual(Adapter.tremoloDelta(phase: 128, depth: 8, control: 1, vibratoPhase: 128), -31)
        for vibrato: UInt8 in [0x81, 0x80] {
            let (context, states) = inspect(song([
                cell(4, vibrato, note: 49, instrument: 1, volume: 0x30),
                cell(0x0E, 0x42), cell(0x0E, 0x71), cell(7, 0x48), cell(0x0E, 0x40),
            ]))
            // FT2 advances phase even with zero depth; this observer does not alter pitch.
            XCTAssertEqual(states[0].tremoloVibratoPhase, 160)
            XCTAssertEqual(states[2].vibratoControl?.controlValue, 2)
            XCTAssertEqual(states[4].tremolo.control, 1)
            XCTAssertEqual(tremolo(context).first?.1.vibratoPhase, 160)
            XCTAssertEqual(tremolo(context).first?.1.outputVolume, 63)
            if vibrato == 0x80 {
                XCTAssertTrue(context.vibratoEffects[0].applied)
                XCTAssertTrue(context.vibratoEffects[0].stepUpdates.allSatisfy { $0.vibrato?.signedReferenceDelta == 0 })
            }
        }
    }

    func testInstrumentOnlyRestoresVolumeAndRespectsPhaseControl() {
        for control: UInt8 in [0, 4] {
            let (context, states) = inspect(song([
                cell(0x0E, 0x70 | control),
                cell(7, 0x48, note: 49, instrument: 1, volume: 0x30), cell(instrument: 1),
            ], sample: 0.25))
            XCTAssertEqual(states[2].baseChannelVolume, 64)
            XCTAssertEqual(states[2].outputChannelVolume, 64)
            XCTAssertEqual(states[2].activeSampleVolume, 0.25)
            XCTAssertEqual(states[2].tremolo.phase, control == 0 ? 0 : 80)
            XCTAssertEqual(context.events.count, 1)
            let update = context.voiceStateUpdates.first { $0.source.rowIndex == 2 && $0.activeVoiceUpdated }
            XCTAssertEqual(update?.gainBefore, 63 / 256)
            XCTAssertEqual(update?.gainAfter, 0.25)
        }
    }

    func testE9RetriggerKeepsHeldOutputWhileRxyReplacesOutputFromBase() {
        for control: UInt8 in [0, 4] {
            for retrigger in [cell(0x0E, 0x93), cell(0x1B, 0x03)] {
                let (context, states) = inspect(song([
                    cell(0x0E, 0x70 | control),
                    cell(7, 0x48, note: 49, instrument: 1, volume: 0x30), retrigger,
                ]))
                let isE9 = retrigger.effectType == 0x0E
                XCTAssertEqual(states[2].baseChannelVolume, 32)
                XCTAssertEqual(states[2].outputChannelVolume, isE9 ? 63 : 32)
                XCTAssertEqual(states[2].tremolo.phase, isE9 && control == 0 ? 0 : 80)
                XCTAssertEqual(context.events.map(\.gain), [0.5, isE9 ? 63 / 64 : 0.5])
                XCTAssertEqual(context.retriggerEffects.flatMap(\.retriggerTicks), [3])
            }
        }
    }

    func testKeyOffAndDelayedTriggersUseEvidencedPhaseResetTiming() {
        for control: UInt8 in [0, 4] {
            for (command, resets) in [
                (cell(0x14, 0, instrument: 1), false), (cell(note: 97, instrument: 1), false),
                (cell(0x0E, 0xD0, note: 49, instrument: 1), true),
                (cell(0x0E, 0xD1, note: 49, instrument: 1), true),
                (cell(0x0E, 0xD6, note: 49, instrument: 1), false),
            ] {
                let (context, states) = inspect(song([
                    cell(0x0E, 0x70 | control),
                    cell(7, 0x48, note: 49, instrument: 1, volume: 0x30), command,
                ]))
                XCTAssertEqual(states[2].tremolo.phase, resets && control == 0 ? 0 : 80)
                if resets {
                    XCTAssertEqual(context.events.count, 2)
                    XCTAssertEqual(context.events.last?.tick, command.effectParam == 0xD1 ? 1 : 0)
                    XCTAssertEqual(context.events.last?.gain, 1)
                    XCTAssertEqual(states[2].baseChannelVolume, 64)
                    XCTAssertEqual(states[2].outputChannelVolume, 64)
                } else if command.effectType == 0x0E {
                    XCTAssertEqual(context.events.count, 1)
                    XCTAssertEqual(states[2].outputChannelVolume, 63)
                }
            }
        }
    }

    func testLaterVolumeWritersReplaceHeldOutputUsingPersistentBase() {
        for (command, outputs, ticks) in [
            (cell(0x0C, 32), [32], [0]), (cell(volume: 0x30), [32], [0]),
            (cell(0x0E, 0xA1), [33], [0]), (cell(0x0E, 0xB1), [31], [0]),
            (cell(0x0A, 1), [31, 30, 29, 28, 27], [1, 2, 3, 4, 5]),
        ] {
            let (context, states) = inspect(song([
                cell(7, 0x48, note: 49, instrument: 1, volume: 0x30), command, cell(),
            ], sample: 0.25))
            let updates = context.voiceStateUpdates.filter { $0.source.rowIndex == 1 && $0.applied }
            XCTAssertEqual(updates.map(\.effectiveVolumeAfter), outputs.map(Optional.some))
            XCTAssertEqual(updates.map(\.syntheticTick), ticks)
            XCTAssertEqual(updates.first?.effectiveVolumeBefore, 63)
            XCTAssertEqual(updates.map(\.gainAfter), outputs.map { Optional(Float($0) / 256) })
            XCTAssertEqual(states[1].baseChannelVolume, outputs.last)
            XCTAssertEqual(states[2].outputChannelVolume, outputs.last)
            XCTAssertTrue(states.allSatisfy { $0.activeSampleVolume == 0.25 })
        }
    }

    func testDelayedInstrumentRestoresVolumeWithoutReplayingColumnSlides() {
        for (volume, expected): (UInt8, Int) in [(0x30, 32), (0x81, 64), (0x61, 64)] {
            let (context, states) = inspect(song([
                cell(7, 0x48, note: 49, instrument: 1, volume: 0x30),
                cell(0x0E, 0xD1, note: 49, instrument: 1, volume: volume),
            ]))
            XCTAssertEqual(context.events.last?.tick, 1)
            XCTAssertEqual(context.events.last?.gain, Float(expected) / 64)
            XCTAssertEqual(states[1].baseChannelVolume, expected)
            XCTAssertEqual(states[1].outputChannelVolume, expected)
            XCTAssertEqual(states[1].tremolo.phase, 0)
        }
    }

    func testQuietSamplesClampTrackerOutputBeforeApplyingSampleVolume() {
        for sample: Float in [1, 0.25] {
            let (context, states) = inspect(song([
                cell(0x0E, 0x72), cell(7, 0xFF, note: 49, instrument: 1, volume: 0x20),
            ], sample: sample))
            let updates = tremolo(context)
            XCTAssertEqual(updates.map { $0.1.delta }, [59, 59, 59, -59, -59])
            XCTAssertEqual(updates.map { $0.1.outputVolume }, [64, 64, 64, 0, 0])
            XCTAssertTrue(updates.allSatisfy { $0.1.clamped && $0.1.baseVolume == 16 })
            XCTAssertEqual(updates.map { $0.0.gainAfter }, [sample, sample, sample, 0, 0].map(Optional.some))
            XCTAssertEqual(states[1].baseChannelVolume, 16)
            XCTAssertEqual(states[1].activeSampleVolume, sample)
        }
    }

    func testLaterChannelGlobalUpdatesUseHeldOutputAndTremoloUsesCurrentRowGlobalVolume() {
        let (context, states) = inspect(song([
            cell(note: 49, instrument: 1, volume: 0x30), cell(7, 0x48), cell(),
        ], secondary: [cell(), cell(0x10, 32), cell(0x10, 16)]))
        XCTAssertEqual(tremolo(context).map { $0.0.gainAfter }, [32, 44, 54, 61, 63].map { Optional(Float($0) / 128) })
        let globals = context.voiceStateUpdates.filter { $0.effectType == 0x10 && $0.activeVoiceUpdated }
        XCTAssertEqual(globals.map(\.effectiveVolumeAfter), [32, 63])
        XCTAssertEqual(globals.map(\.gainAfter), [0.25, 63 / 256])
        XCTAssertEqual(states.map(\.baseChannelVolume), [32, 32, 32])
        XCTAssertEqual(states.map(\.outputChannelVolume), [32, 63, 63])
    }

    func testTremoloMemoryAndControlRemainChannelLocal() {
        let (context, _) = inspect(song([
            cell(0x0E, 0x71), cell(7, 0x48, note: 49, instrument: 1, volume: 0x30),
        ], secondary: [cell(0x0E, 0x76), cell(7, 0x23, note: 49, instrument: 1, volume: 0x30)]))
        XCTAssertEqual(context.channelStates.map { $0.tremolo.control }, [1, 6])
        XCTAssertEqual(context.channelStates.map { $0.tremolo.speed }, [4, 2])
        XCTAssertEqual(context.channelStates.map { $0.tremolo.depth }, [8, 3])
        XCTAssertEqual(context.channelStates.map { $0.tremolo.phase }, [80, 40])
        XCTAssertEqual(context.channelStates.map(\.outputChannelVolume), [48, 43])
    }

    func testPublicFixtureUsesSameBoundedAndWindowedPCM() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/tremolo-effects.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixture.path)
        let module = try PlaybackSongBuilder.build(from: metadata, modulePath: fixture.path)
        let request = PlaybackSongOfflineRenderRequest(song: module, config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2), rows: 56)
        let renderer = PlaybackSongOfflineRenderer()
        let bounded = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 3)
        XCTAssertEqual(bounded.block.interleavedPCM.count, windowed.block.interleavedPCM.count)
        // Window carryover can round the same ramp by one Float32 unit.
        let maxError = zip(bounded.block.interleavedPCM, windowed.block.interleavedPCM)
            .reduce(Float(0)) { max($0, abs($1.0 - $1.1)) }
        XCTAssertLessThanOrEqual(maxError, 1e-6)
        XCTAssertTrue(bounded.block.interleavedPCM.contains { abs($0) > 0.01 })
        XCTAssertEqual(bounded.block.frameCount, 56 * 5_760)
        XCTAssertFalse(bounded.diagnostics.deferredCellFields.contains { $0.field == .effect })
    }

    private func tremolo(_ context: Adapter.AdapterRowContext, row: Int? = nil)
        -> [(PlaybackSongSyntheticVoiceStateUpdateDiagnostic, PlaybackSongSyntheticTremoloTick)] {
        context.voiceStateUpdates.compactMap { update in
            guard row == nil || update.source.rowIndex == row, case let .tremolo(tick) = update.command else { return nil }
            return (update, tick)
        }
    }

    private func inspect(_ song: PlaybackSong) -> (Adapter.AdapterRowContext, [Adapter.ChannelState]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: 100)
        var context = Adapter.AdapterRowContext()
        var states = [Adapter.ChannelState]()
        for row in traversal.rows {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow,
                song: song, timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow, tick: 0), context: &context)
            states.append(context.channelStates[0])
        }
        return (context, states)
    }

    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                      instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        PlaybackCell(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ cells: [PlaybackCell], sample volume: Float = 1, speed: Int = 6,
                      secondary: [PlaybackCell]? = nil) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1, count: 256),
            volume: volume, relativeNote: 0, finetune: 0, baseSampleRate: 100, loopLength: 256, loopType: 1)
        return PlaybackSong(title: "Tremolo", orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: cells.enumerated().map { entry in
                PlaybackRow(index: entry.offset, cells: [entry.element] + (secondary.map { [$0[entry.offset]] } ?? []))
            })],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: PlaybackTiming(speed: speed, bpm: 250), usesLinearFrequencyTable: true)
    }
}
