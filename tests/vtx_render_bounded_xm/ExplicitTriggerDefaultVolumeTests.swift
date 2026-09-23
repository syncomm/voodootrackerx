import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class ExplicitTriggerDefaultVolumeTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testColdAndStaleBaseOutputInitializeFromTheNewMappedSample() throws {
        for prior in [0, 7, 64] {
            for output in [0, 29] {
                for (note, instrument, sample, volume): (UInt8, UInt8, Int, Int) in
                    [(1, 1, 0, 64), (48, 1, 0, 64), (49, 1, 1, 16), (96, 1, 1, 16), (49, 2, 0, 32)] {
                    var state = Adapter.ChannelState()
                    state.baseChannelVolume = prior
                    state.outputChannelVolume = output
                    let (context, states) = inspect(song([cell(note: note, instrument: instrument)]), initial: state)
                    let after = try XCTUnwrap(states.last)
                    XCTAssertEqual(after.baseChannelVolume, volume)
                    XCTAssertEqual(after.outputChannelVolume, volume)
                    XCTAssertEqual(after.activeInstrumentIndex, Int(instrument))
                    XCTAssertEqual(after.activeSampleIndex, sample)
                    XCTAssertEqual(after.activeSampleVolume, Float(volume) / 64)
                    XCTAssertEqual(after.activeEventIndex, 0)
                    XCTAssertEqual(context.events.count, 1)
                    XCTAssertEqual(context.events[0].scheduledStartFrame, 0)
                    XCTAssertEqual(context.events[0].initialSourceFrame, 0)
                    XCTAssertEqual(context.events[0].gain, Float(volume * volume) / 4096)
                    XCTAssertEqual(context.eventMappings[0].sampleVolumeRawEstimate, volume)
                    XCTAssertEqual(context.eventMappings[0].sampleSelectionMethod, .sampleMap)
                    XCTAssertFalse(context.eventMappings[0].firstPlayableSampleFallbackUsed)
                }
            }
        }
    }

    func testColdInstrumentOnlyLikeZeroStateThenExplicitTriggerIsAudible() throws {
        // C00 expresses the stopped candidate's exact zero-volume/no-voice state
        // on current main, without implementing instrument-only reset behavior.
        let module = song([cell(instrument: 1, effect: 12, parameter: 0), cell(note: 49, instrument: 1), cell()])
        let (context, states) = inspect(module)
        XCTAssertEqual(states.map(\.baseChannelVolume), [0, 16, 16])
        XCTAssertEqual(states.map(\.outputChannelVolume), [0, 16, 16])
        XCTAssertNil(states[0].activeEventIndex)
        XCTAssertEqual(context.events.map(\.scheduledStartFrame), [1])
        XCTAssertEqual(context.events.map(\.gain), [0.0625])
        let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: 100, channelCount: 1), rows: 3)
        let rendered = PlaybackSongOfflineRenderer().render(request)
        XCTAssertEqual(rendered.block.interleavedPCM, [0, 0.0625, 0.0625])
        XCTAssertEqual(rendered.diagnostics.eventMappings.first?.sampleIndex, 1)
    }

    func testNewNotesReplaceReducedOrZeroVolumeUsingEachMappedDefault() {
        let module = song([cell(note: 37, instrument: 1), cell(effect: 12, parameter: 7),
                           cell(note: 49, instrument: 1), cell(effect: 12, parameter: 0),
                           cell(note: 50, instrument: 2), cell(note: 38, instrument: 1)])
        let (context, states) = inspect(module)
        XCTAssertEqual(states.map(\.baseChannelVolume), [64, 7, 16, 0, 32, 64])
        XCTAssertEqual(context.eventMappings.map(\.sampleIndex), [0, 1, 0, 0])
        XCTAssertEqual(context.eventMappings.map(\.instrumentIndex), [1, 1, 2, 1])
        XCTAssertEqual(context.eventMappings.map(\.effectiveVolumeValue), [64, 16, 32, 64])
        XCTAssertEqual(context.events.map(\.gain), [1, 0.0625, 0.25, 1])
        XCTAssertEqual(context.events.map(\.scheduledStartFrame), [0, 2, 4, 5])
        XCTAssertEqual(states.map(\.activeEventIndex), [0, 0, 1, 1, 2, 3])
    }

    func testSameCellVolumeWritersOverrideDefaultAndGlobalStaysIndependent() {
        for (volume, effect, parameter, expected): (UInt8, UInt8, UInt8, Int) in
            [(0x30, 0, 0, 32), (0, 12, 7, 7), (0x30, 12, 0, 0), (0, 14, 0xA3, 19)] {
            let module = song([cell(effect: 16, parameter: 32),
                               cell(note: 49, instrument: 1, volume: volume, effect: effect, parameter: parameter)])
            let (context, states) = inspect(module)
            XCTAssertEqual(states.last?.baseChannelVolume, expected)
            XCTAssertEqual(states.last?.outputChannelVolume, expected)
            XCTAssertEqual(states.last?.activeSampleVolume, 0.25)
            XCTAssertEqual(context.events.map(\.gain), [Float(expected) / 512])
            XCTAssertEqual(context.globalVolumeState.volumeValue, 32)
        }
    }

    func testTremoloHeldOutputCannotOverrideNewSampleDefaultOrClearMemory() {
        var state = Adapter.ChannelState()
        state.baseChannelVolume = 32
        state.outputChannelVolume = 63
        state.tremolo = .init(speed: 4, depth: 8, control: 4, phase: 80, activated: true)
        let (context, states) = inspect(song([cell(note: 49, instrument: 1)]), initial: state)
        XCTAssertEqual(states[0].baseChannelVolume, 16)
        XCTAssertEqual(states[0].outputChannelVolume, 16)
        XCTAssertEqual(states[0].tremolo, state.tremolo)
        XCTAssertEqual(context.events[0].gain, 0.0625)
    }

    func testInvalidMapDoesNotFallbackOrInitializeFromFirstSample() {
        let module = song([cell(note: 49, instrument: 1)], map: Array(repeating: 15, count: 96))
        var state = Adapter.ChannelState()
        state.baseChannelVolume = 7
        let (context, states) = inspect(module, initial: state)
        XCTAssertTrue(context.events.isEmpty)
        XCTAssertEqual(states[0].baseChannelVolume, 7)
        XCTAssertFalse(context.ignoredCells[0].firstPlayableSampleFallbackUsed)
    }

    func testInstrumentOnlyAndNoteOnlyRemainDeferred() {
        let (context, states) = inspect(song([cell(effect: 12, parameter: 7), cell(instrument: 1), cell(note: 49)]))
        XCTAssertEqual(states.map(\.baseChannelVolume), [7, 7, 7])
        XCTAssertTrue(context.events.isEmpty)
    }

    func testRuntimePlanAndWindowedPCMMatchOfflineAcrossDefaultChanges() {
        let module = song([cell(instrument: 1, effect: 12), cell(note: 49, instrument: 1), cell(),
                           cell(effect: 12, parameter: 7), cell(note: 37, instrument: 1), cell(),
                           cell(effect: 12), cell(note: 49, instrument: 2), cell()])
        let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: 48_000, channelCount: 1), rows: 9)
        let renderer = PlaybackSongOfflineRenderer()
        let offline = renderer.render(request)
        XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: 48_000).plan, offline.plan)
        for window in [1, 2, 4] {
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: window).block.interleavedPCM, offline.block.interleavedPCM)
        }
        XCTAssertEqual(offline.plan.pattern.events.map(\.scheduledStartFrame), [480, 1920, 3360])
        XCTAssertEqual(offline.plan.pattern.events.map(\.gain), [0.0625, 1, 0.25])
        XCTAssertGreaterThan(offline.block.interleavedPCM[480], 0)
    }

    private func inspect(_ song: PlaybackSong, initial: Adapter.ChannelState = .init()) -> (Adapter.AdapterRowContext, [Adapter.ChannelState]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song, startOrderIndex: 0, orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(song, traversalPlan: traversal, sampleRate: 100)
        var context = Adapter.AdapterRowContext()
        context.channelStates = [initial]
        var states = [Adapter.ChannelState]()
        for row in traversal.rows {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow, tick: 0), context: &context)
            states.append(context.channelStates[0])
        }
        return (context, states)
    }

    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, parameter: UInt8 = 0) -> PlaybackCell {
        PlaybackCell(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ cells: [PlaybackCell], map: [Int]? = nil) -> PlaybackSong {
        func sample(_ instrument: Int, _ index: Int, _ volume: Float) -> PlaybackSample {
            PlaybackSample(instrumentIndex: instrument, sampleIndex: index, pcm: Array(repeating: 1, count: 256),
                volume: volume, relativeNote: 0, finetune: 0, baseSampleRate: 100)
        }
        // Reversed storage order proves the canonical identity, not array order, owns selection.
        let instrument = PlaybackInstrument(index: 1, samples: [sample(1, 1, 0.25), sample(1, 0, 1)],
            noteSampleMap: map ?? Array(repeating: 0, count: 48) + Array(repeating: 1, count: 48))
        return PlaybackSong(title: "Explicit trigger defaults", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: instrument, 2: .init(index: 2, samples: [sample(2, 0, 0.5)], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 1, bpm: 250), usesLinearFrequencyTable: true)
    }
}
