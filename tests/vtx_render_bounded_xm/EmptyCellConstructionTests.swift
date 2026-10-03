import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class EmptyCellConstructionTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter
    private let empty = PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)

    func testEmptyCellsPreserveCompleteCarriedControlsAndOccurrenceDiagnostics() {
        let module = song(patterns: [0: Array(repeating: [empty, empty], count: 3)], orders: [0, 0])
        let origin = PlaybackPosition(orderIndex: 3, patternIndex: 7, rowIndex: 12)
        let memory = Adapter.effectMemorySource(source: origin, channelIndex: 0,
            cell: PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 10, effectParam: 2))
        var carried = Adapter.ChannelState()
        carried.carriedInstrumentIndex = 2
        carried.semanticInstrumentIndex = 1
        carried.semanticSampleIndex = 4
        carried.semanticVolumeEnvelopeEnabled = true
        carried.baseChannelVolume = 32
        carried.outputChannelVolume = 19
        carried.initializePanning(fromSampleHeader: 224)
        carried.triggeredSampleDefaultVolume = 40
        carried.triggeredSampleDefaultPan = 64
        carried.keyOffWithoutVoice = true
        carried.volumeSlideMemory = .init(parameter: 2, source: memory)
        carried.sampleOffsetMemory = .init(offsetFrames: 256, source: memory)
        carried.portamentoUpMemory = .init(amount: 4, source: memory)
        carried.activeLinearPeriod = 4608
        carried.tonePortamentoTargetNote = 53
        carried.tonePortamentoSpeed = 8
        carried.vibratoSpeed = 4
        carried.vibratoDepth = 8
        carried.vibratoPhase = 128
        carried.tremolo = .init(speed: 3, depth: 7, control: 1, phase: 64, activated: true)
        carried.tremoloVibratoPhase = 128
        var sounding = carried
        sounding.activeEventIndex = 9
        sounding.activeEventMappingIndex = 9
        sounding.activeInstrumentIndex = 1
        sounding.activeSampleIndex = 0
        sounding.activeSampleVolume = 0.625
        sounding.activePlaybackStep = 1.25
        let context = inspect(module, states: [carried, sounding])

        XCTAssertEqual(context.channelStates, [carried, sounding])
        XCTAssertEqual(context.emptyCellFastPathCount, 12)
        XCTAssertEqual(context.fullCellDispatchCount, 0)
        XCTAssertEqual(context.xmChannelRows.count, 12)
        XCTAssertEqual(context.xmChannelRows.map(\.controls), Array(repeating: [carried, sounding], count: 6).flatMap { $0 })
        XCTAssertTrue(context.xmChannelRows.allSatisfy { $0.instrumentOnlyReset == nil })
        XCTAssertEqual(context.xmChannelRows.map(\.source.orderIndex), Array(repeating: 0, count: 6) + Array(repeating: 1, count: 6))
        XCTAssertEqual(context.xmChannelRows.map(\.syntheticRow), (0..<6).flatMap { [$0, $0] })
        XCTAssertEqual(context.xmChannelRows.map(\.scheduledFrame), (0..<6).flatMap { [$0 * 5760, $0 * 5760] })
        XCTAssertEqual(context.ignoredCells.map(\.source), context.xmChannelRows.map(\.source))
        XCTAssertEqual(context.ignoredCells.map(\.channelIndex), context.xmChannelRows.map(\.channelIndex))
        XCTAssertTrue(context.ignoredCells.allSatisfy {
            $0.reason == .emptyNote && $0.skipReason == .emptyCell && $0.volumeColumn == PlaybackSongVolumeColumnDecoder.decode(0) &&
                !$0.hasIgnoredEffect && !$0.hasIgnoredVolumeColumn && $0.selectedSampleIndex == nil
        })
        XCTAssertEqual(context.eventCoverage.summary.totalCellsVisited, 12)
        XCTAssertEqual(context.eventCoverage.summary.emptyCells, 12)
        XCTAssertEqual(context.eventCoverage.summary.ignoredOrDeferredCells, 12)
        XCTAssertTrue(context.events.isEmpty)
        XCTAssertTrue(context.voiceStateUpdates.isEmpty)
        XCTAssertTrue(context.playbackStateEvents.isEmpty)
        XCTAssertTrue(context.effectCommandDiagnostics.isEmpty)
        XCTAssertTrue(context.deferredCellFields.isEmpty)
    }

    func testEveryNonzeroFieldRetainsFullDispatchIncludingArpeggioParameter() {
        let cells = [
            empty,
            PlaybackCell(note: 1, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 0, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 1, effectType: 0, effectParam: 0),
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 1, effectParam: 0),
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 1),
        ]
        let context = inspect(song(patterns: [0: [cells]]))
        XCTAssertEqual(context.emptyCellFastPathCount, 1)
        XCTAssertEqual(context.fullCellDispatchCount, 5)
        XCTAssertEqual(context.eventCoverage.summary.emptyCells, 1)
        XCTAssertEqual(context.eventCoverage.summary.normalNoteCells, 1)
        XCTAssertEqual(context.eventCoverage.summary.instrumentOnlyCells, 1)
        XCTAssertEqual(context.arpeggioEffects.count, 1)
        XCTAssertEqual(context.portamentoSlideEffects.count, 1)
        XCTAssertEqual(context.xmChannelRows.count, cells.count)
        XCTAssertEqual(context.volumeColumnMappings.count, 1)
    }

    func testRepeatedPatternStillUsesEachOrdersCarriedInstrument() throws {
        let noteOnly = PlaybackCell(note: 49, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)
        let instrumentOnly = PlaybackCell(note: 0, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        let module = song(patterns: [0: [[noteOnly], [empty]], 1: [[instrumentOnly], [empty]]], orders: [0, 1, 0])
        let plan = Adapter.adapt(module, startOrderIndex: 0, orderCount: 3, sampleRate: 48000)
        let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)
        XCTAssertEqual(plan.pattern.events.count, 1)
        XCTAssertEqual(mapping.source, PlaybackPosition(orderIndex: 2, patternIndex: 0, rowIndex: 0))
        XCTAssertEqual(mapping.instrumentIndex, 1)
        XCTAssertEqual(mapping.syntheticRow, 4)
        XCTAssertEqual(plan.xmChannelRows.map(\.syntheticRow), Array(0..<6))
        XCTAssertEqual(plan.diagnostics.ignoredCells.filter { $0.reason == .emptyNote }.map(\.source.orderIndex), [0, 1, 2])
    }

    func testSparseConstructionDispatchWorkScalesWithNonemptyOccurrences() {
        var rows = Array(repeating: Array(repeating: empty, count: 16), count: 128)
        rows[0][0] = PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        let context = inspect(song(patterns: [0: rows], orders: [0, 0, 0, 0]))
        XCTAssertEqual(context.emptyCellFastPathCount, 8188)
        XCTAssertEqual(context.fullCellDispatchCount, 4)
        XCTAssertEqual(context.events.count, 4)
        XCTAssertEqual(context.xmChannelRows.count, 8192)
        XCTAssertEqual(context.ignoredCells.count, 8188)
        XCTAssertEqual(context.eventCoverage.summary.totalCellsVisited, 8192)
    }

    func testConstructionProfileKeepsNumericBypassAndDispatchCounts() throws {
        let sink = ProfileSink()
        let recorder = AdapterPlanProfileRecorder(isEnabled: true, sink: sink)
        let session = try XCTUnwrap(recorder.beginLifecycle("test"))
        let parameterOnly = PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 1)
        _ = Adapter.adapt(song(patterns: [0: [[empty, parameterOnly]]]), orderIndex: 0, sampleRate: 48000,
            profileSession: session)
        let line = try XCTUnwrap(sink.lines.first { $0.contains("phase=event_generation ") })
        XCTAssertTrue(line.contains("empty_cell_bypass_count=1"))
        XCTAssertTrue(line.contains("full_cell_dispatch_count=1"))
        XCTAssertFalse(line.contains("redacted"))
    }

    private final class ProfileSink: AdapterPlanProfileSinking {
        var lines = [String]()
        func writeAdapterPlanProfileLine(_ line: String) { lines.append(line) }
    }

    private func inspect(_ module: PlaybackSong, states: [Adapter.ChannelState] = []) -> Adapter.AdapterRowContext {
        let traversal = PlaybackSongTraversalPlanner.plan(module, startOrderIndex: 0, orderCount: module.orders.count)
        let timing = PlaybackSongFxxTimingPlanner.plan(module, traversalPlan: traversal, sampleRate: 48000)
        var context = Adapter.AdapterRowContext()
        context.channelStates = states
        for (index, row) in traversal.rows.enumerated() {
            _ = Adapter.appendEvents(from: row.row, source: row.source, syntheticRow: row.syntheticRow, song: module,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow), timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow, tick: 0),
                nextRow: traversal.rows.indices.contains(index + 1) ? traversal.rows[index + 1].row : nil, context: &context)
        }
        return context
    }

    private func song(patterns: [Int: [[PlaybackCell]]], orders: [Int] = [0]) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25, -0.25], volume: 1,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopLength: 2, loopType: 1)
        return PlaybackSong(title: "Empty-cell construction", orders: orders.enumerated().map {
            PlaybackOrderEntry(orderIndex: $0.offset, patternIndex: $0.element)
        }, patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.map { index, rows in
            (index, PlaybackPattern(index: index, rows: rows.enumerated().map { PlaybackRow(index: $0.offset, cells: $0.element) }))
        }), instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: PlaybackTiming(speed: 6, bpm: 125), usesLinearFrequencyTable: true)
    }
}
