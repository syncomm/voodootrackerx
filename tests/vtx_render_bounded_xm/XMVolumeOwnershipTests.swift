import CryptoKit
import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMVolumeOwnershipTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testQuietSampleAndChannelDomainsRemainDistinguishable() throws {
        for (sample, channel, gain): (Float, Int, Float) in [(1, 64, 1), (1, 16, 0.25), (0.25, 64, 0.25), (0.25, 16, 0.0625)] {
            let module = song([cell(note: 49, volume: UInt8(0x10 + channel)), cell()], sample: sample)
            let (context, states) = inspect(module)
            XCTAssertEqual(states.map(\.baseChannelVolume), [channel, channel])
            XCTAssertEqual(states.map(\.activeSampleVolume), [sample, sample])
            XCTAssertEqual(context.events.map(\.gain), [gain])
            XCTAssertEqual(context.eventMappings.map(\.effectiveVolumeValue), [channel])
            XCTAssertEqual(render(module).block.interleavedPCM, Array(repeating: gain, count: 8))
        }
    }

    func testExistingVolumeWritersPreserveSampleScalingAndFrozenTrajectories() throws {
        let cases: [(PlaybackCell, [Int], [Int])] = [
            (cell(0x0C, 16), [16], [0]), (cell(volume: 0x20), [16], [0]),
            (cell(volume: 0x63), [29], [0]), (cell(volume: 0x73), [35], [0]),
            (cell(volume: 0x83), [29], [0]), (cell(volume: 0x93), [35], [0]),
            (cell(0x0A, 2), [30, 28, 26], [1, 2, 3]),
            (cell(0x0E, 0xA3), [35], [0]), (cell(0x0E, 0xB3), [29], [0]),
            (cell(0x05, 2), [30, 28, 26], [1, 2, 3]),
            (cell(0x06, 2), [30], [0]),
        ]
        for (command, volumes, ticks) in cases {
            let module = song([cell(note: 49, volume: 0x30), command, cell()], sample: 0.25)
            let (context, states) = inspect(module)
            let updates = context.voiceStateUpdates.filter { $0.source.rowIndex == 1 && $0.applied }
            XCTAssertEqual(updates.map(\.effectiveVolumeAfter), volumes.map(Optional.some))
            XCTAssertEqual(updates.map(\.syntheticTick), ticks)
            XCTAssertEqual(updates.map(\.scheduledFrame), ticks.map { 4 + $0 })
            XCTAssertEqual(updates.map(\.gainAfter), volumes.map { Optional(Float($0) / 256) })
            XCTAssertEqual(states.map(\.baseChannelVolume), [32, volumes.last!, volumes.last!])
            XCTAssertTrue(states.allSatisfy { $0.activeSampleVolume == 0.25 })
            XCTAssertEqual(context.events.map(\.gain), [0.125])
        }
    }

    func testEveryRetriggerVolumeModeKeepsSampleIndependent() {
        let expected = [32, 31, 30, 28, 24, 16, 21, 16, 32, 33, 34, 36, 40, 48, 48, 64]
        for mode in 0...15 {
            let module = song([cell(note: 49, volume: 0x30), cell(0x1B, UInt8(mode << 4 | 3)), cell()], sample: 0.25)
            let (context, states) = inspect(module)
            XCTAssertEqual(states.map(\.baseChannelVolume), [32, expected[mode], expected[mode]])
            XCTAssertTrue(states.allSatisfy { $0.activeSampleVolume == 0.25 })
            XCTAssertEqual(context.events.map(\.gain), [0.125, Float(expected[mode]) / 256])
            XCTAssertEqual(context.retriggerEffects.flatMap(\.volumeValuesAfter), [expected[mode]])
            XCTAssertEqual(context.retriggerEffects.flatMap(\.retriggerTicks), [3])
        }
    }

    func testVolumeWritersUseBaseArithmeticAndReplaceDistinctOutput() {
        for (command, expected) in [(cell(0x0C, 32), 32), (cell(0x0E, 0xA3), 35)] {
            var state = Adapter.ChannelState()
            state.baseChannelVolume = 32
            state.outputChannelVolume = 16
            state.activeSampleVolume = 0.25
            state.activeEventIndex = 0
            let update = Adapter.applyEffectColumnState(from: command,
                source: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0), channelIndex: 0,
                syntheticRow: 0, scheduledFrame: 0, rowSpeed: 6, channelState: &state, globalVolumeValue: 64)
            XCTAssertEqual(update?.gainBefore, 0.0625)
            XCTAssertEqual(update?.gainAfter, Float(expected) / 256)
            XCTAssertEqual(update?.effectiveVolumeBefore, 16)
            XCTAssertEqual(update?.effectiveVolumeAfter, expected)
            XCTAssertEqual(state.baseChannelVolume, expected)
            XCTAssertEqual(state.outputChannelVolume, expected)
            XCTAssertEqual(state.activeSampleVolume, 0.25)
        }
    }

    func testTriggerAndActiveUpdateAgreeAndGlobalVolumeRemainsDownstream() {
        for volume: UInt8 in [0x10, 0x20, 0x50] {
            let trigger = inspect(song([cell(note: 49, volume: volume)], sample: 0.25)).0
            let update = inspect(song([cell(note: 49), cell(volume: volume)], sample: 0.25)).0
            XCTAssertEqual(trigger.events[0].gain, update.voiceStateUpdates.last?.gainAfter)
        }
        let module = song([cell(note: 49, volume: 0x30), cell(0x10, 32), cell(0x11, 4), cell()], sample: 0.25)
        let (context, states) = inspect(module)
        XCTAssertEqual(states.map(\.baseChannelVolume), [32, 32, 32, 32])
        XCTAssertTrue(states.allSatisfy { $0.activeSampleVolume == 0.25 })
        XCTAssertEqual(context.globalVolumeState.volumeValue, 28)
        let updates = context.voiceStateUpdates.filter { $0.effectType == 0x10 || $0.effectType == 0x11 }
        XCTAssertEqual(updates.map(\.globalVolumeAfter), [32, 28])
        XCTAssertEqual(updates.map(\.gainAfter), [0.0625, 0.0546875])
    }

    func testEnvelopeAndFadeoutRemainDownstreamWithExactPCM() {
        let envelope = PlaybackVolumeEnvelope(enabled: true, points: [PlaybackEnvelopePoint(tick: 0, value: 32)],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 65_536)
        let module = song([cell(note: 49, volume: 0x30), cell(note: 97), cell(), cell()], sample: 0.25, speed: 1, envelope: envelope)
        let (context, states) = inspect(module)
        XCTAssertEqual(states.map(\.baseChannelVolume), [32, 32, 32, 32])
        XCTAssertEqual(context.events.map(\.gain), [0.125])
        let result = render(module)
        XCTAssertEqual(result.block.interleavedPCM, [0.0625, 0.0625, 0.03125, 0])
        XCTAssertEqual(result.diagnostics.eventMappings.first?.volumeEnvelopeSemantics.fadeoutApplied, true)
    }

    func testRepresentativePreFoundationPCMAndWindowedRenderingRemainIdentical() {
        let commands = [cell(note: 49, volume: 0x30), cell(0x0C, 16), cell(volume: 0x30),
            cell(0x0A, 2), cell(0x0E, 0xA3), cell(0x0E, 0xB3), cell(0x05, 2), cell(0x06, 2),
            cell(0x1B, 0x63), cell(0x10, 32), cell(0x11, 4), cell(), cell(note: 49), cell()]
        let module = song(commands, sample: 0.25)
        let request = PlaybackSongOfflineRenderRequest(song: module, config: MixerRenderConfig(sampleRate: 100, channelCount: 1), rows: commands.count)
        let renderer = PlaybackSongOfflineRenderer()
        let bounded = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 2)
        XCTAssertEqual(bounded.block.interleavedPCM, windowed.block.interleavedPCM)
        let bytes = bounded.block.interleavedPCM.flatMap { value -> [UInt8] in
            let bits = value.bitPattern
            return [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: bits >> $0) }
        }
        let hash = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        // Captured on the unchanged pre-foundation adapter; preserve exact Float32 output.
        XCTAssertEqual(hash, "dd747eebec7253a8bff57cbb97517fa0b455a230c65ffd7eb9bc76f38f7932de")
        XCTAssertEqual(bounded.block.frameCount, 56)
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
            let state = context.channelStates[0]
            XCTAssertEqual(state.outputChannelVolume, state.baseChannelVolume)
            states.append(state)
        }
        return (context, states)
    }

    private func render(_ song: PlaybackSong) -> PlaybackSongOfflineRenderResult {
        PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(song: song,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1), rows: song.patternsByIndex[0]!.rows.count))
    }

    private func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        PlaybackCell(note: note, instrument: note == 49 ? 1 : 0, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ cells: [PlaybackCell], sample volume: Float, speed: Int = 4,
                      envelope: PlaybackVolumeEnvelope = .disabled) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1, count: 256),
            volume: volume, relativeNote: 0, finetune: 0, baseSampleRate: 100)
        return PlaybackSong(title: "Volume ownership", orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: PlaybackPattern(index: 0, rows: cells.enumerated().map { PlaybackRow(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: PlaybackTiming(speed: speed, bpm: 250), usesLinearFrequencyTable: true)
    }
}
