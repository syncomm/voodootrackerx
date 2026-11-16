import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Proposed tests for bounded physical pending writers; root integrates the file.
final class PendingRowPitchContinuationTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testPendingExitKeepsOnlyBoundaryChildrenAndExactMetadata() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for effect: UInt8 in [0, 4] { for delay: UInt8 in [0, 1] {
                let fixture = control(effect: effect, delay: delay, linear: linear)
                let plan = Adapter.adapt(fixture.song, startOrderIndex: 0, orderCount: 1, sampleRate: rate)
                let frame = plan.diagnostics.rowTiming[0].rowStartFrame + plan.diagnostics.rowTiming[0].rowDurationFrames
                let pending = PlaybackSongPendingRowPitch.capture(plan: plan, lastSyntheticRow: 0, boundaryFrame: frame)
                if effect == 0 {
                    let captured = try XCTUnwrap(pending.arpeggios.first)
                    let original = plan.diagnostics.arpeggioEffects[captured.originalDiagnosticIndex]
                    XCTAssertEqual(captured.command.stepUpdates, original.stepUpdates.filter { $0.scheduledFrame == frame })
                    XCTAssertEqual(captured.command.source, original.source)
                    XCTAssertEqual(captured.command.rowSpeed, original.rowSpeed)
                    XCTAssertEqual(captured.command.effectParam, original.effectParam)
                } else {
                    let captured = try XCTUnwrap(pending.vibratos.first)
                    let original = plan.diagnostics.vibratoEffects[captured.originalDiagnosticIndex]
                    XCTAssertEqual(captured.command.stepUpdates, original.stepUpdates.filter { $0.scheduledFrame == frame })
                    XCTAssertEqual(captured.command.phaseBefore, original.phaseBefore)
                    XCTAssertEqual(captured.command.phaseAfter, original.phaseAfter)
                    XCTAssertEqual(captured.command.vibratoSpeedMemorySource, original.vibratoSpeedMemorySource)
                }
                XCTAssertEqual(pending.childCount, 1)
                let ticks = 6 * (Int(delay) + 1)
                let child = effect == 0 ? pending.arpeggios[0].command.stepUpdates[0]
                    : pending.vibratos[0].command.stepUpdates[0]
                XCTAssertEqual(child.scheduledFrame, frame)
                XCTAssertEqual(child.syntheticTick, ticks)
            } }
        } }
    }

    func testImportedExitCoalescesAtRealLocalRowZeroIncludingHeldRows() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for effect: UInt8 in [0, 4] { for delay: UInt8 in [0, 1] {
                let fixture = control(effect: effect, delay: delay, linear: linear)
                let plan = Adapter.adapt(fixture.song, startOrderIndex: 0, orderCount: 1, sampleRate: rate)
                let firstTiming = plan.diagnostics.rowTiming[0]
                let frame = firstTiming.rowStartFrame + firstTiming.rowDurationFrames
                let pending = PlaybackSongPendingRowPitch.capture(plan: plan, lastSyntheticRow: 0, boundaryFrame: frame)
                var context = Adapter.AdapterRowContext()
                context.events = plan.pattern.events
                context.eventMappings = plan.diagnostics.eventMappings
                context.importedSourceCount = context.events.count
                context.channelStates = [try XCTUnwrap(plan.xmChannelRows.first { $0.channelIndex == 0 }).controls]
                let imported = try XCTUnwrap(pending.restore(into: &context, sourceMap: [0: 0], mappingMap: [0: 0]))
                XCTAssertEqual(context.events.count, 1)
                let fine = PlaybackRow(index: 1, cells: [.init(note: 0, instrument: 0,
                    volumeColumn: 0, effectType: 14, effectParam: 0x11)])
                let source = PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1)
                let timing = PlaybackSongFxxTimingPlan(sampleRate: rate, initialSpeed: 6, initialBPM: 125,
                    rowTimings: [.init(source: source, syntheticRow: 0,
                        rowStartExactFrame: Double(frame), rowEndExactFrame: Double(frame) + rate * 0.12,
                        effectiveSpeed: 6, effectiveBPM: 125)], timingChanges: [],
                    finalSpeed: 6, finalBPM: 125, endExactFrame: Double(frame) + rate * 0.12)
                context.semanticPitchBuilder.begin(states: context.channelStates, count: 1,
                    firstOrdinal: firstTiming.actualTickCount, speed: 6, linear: linear,
                    retriggers: 0, rowResets: 0, delayedResets: 0, exits: 0, rows: 0)
                _ = Adapter.appendEvents(from: fine, source: source, syntheticRow: 0, song: fixture.song,
                    timingConfig: .init(speed: 6, bpm: 125, sampleRate: rate), timingPlan: timing,
                    scheduledStartFrame: frame, context: &context)
                if effect == 0 {
                    let index = try XCTUnwrap(imported.arpeggioIndices[0])
                    XCTAssertEqual(context.arpeggioEffects[index].syntheticRow, -1)
                    XCTAssertTrue(context.arpeggioEffects[index].stepUpdates.isEmpty)
                    XCTAssertEqual(context.arpeggioEffects[index].subsumedRowExit?.scheduledFrame, frame)
                } else {
                    let index = try XCTUnwrap(imported.vibratoIndices[0])
                    XCTAssertEqual(context.vibratoEffects[index].syntheticRow, -1)
                    XCTAssertTrue(context.vibratoEffects[index].stepUpdates.isEmpty)
                    XCTAssertEqual(context.finePortamentoUpEffects.first?.execution.coalescedVibratoExit, true)
                    XCTAssertEqual(context.rowExitObserver.exceptionalScalars.count, 1)
                }
                XCTAssertEqual(context.events.count, 1, "Import and fine writers must not create a birth")
                XCTAssertEqual(context.rowExitObserver.references.count, 1)
            } }
        } }
    }

    func testDelayedVibratoEligibilityUsesImportedIndexAndMissingBindingIsTransactional() throws {
        let fixture = control(effect: 4, delay: 0, linear: true)
        var plan = Adapter.adapt(fixture.song, startOrderIndex: 0, orderCount: 1, sampleRate: 48_000)
        var diagnostic = try XCTUnwrap(plan.diagnostics.vibratoEffects.first)
        diagnostic.ordinaryDelayedExecution = true
        plan.diagnostics.vibratoEffects = [diagnostic]
        let pending = PlaybackSongPendingRowPitch.capture(plan: plan, lastSyntheticRow: 0,
            boundaryFrame: 5_760, ordinaryDelayedVibratoIndices: [0])
        var context = Adapter.AdapterRowContext()
        context.events = plan.pattern.events
        context.eventMappings = plan.diagnostics.eventMappings
        XCTAssertNil(pending.restore(into: &context, sourceMap: [:], mappingMap: [0: 0]))
        XCTAssertTrue(context.vibratoEffects.isEmpty)
        XCTAssertTrue(context.ordinaryDelayedVibratoIndices.isEmpty)
        let imported = try XCTUnwrap(pending.restore(into: &context, sourceMap: [0: 0], mappingMap: [0: 0]))
        XCTAssertEqual(context.ordinaryDelayedVibratoIndices, [try XCTUnwrap(imported.vibratoIndices[0])])
        XCTAssertTrue(context.vibratoEffects[0].ordinaryDelayedExecution)
    }

    private func control(effect: UInt8, delay: UInt8, linear: Bool) -> (song: PlaybackSong, first: PlaybackRow) {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: [0.25, -0.25, 0.125, -0.125], volume: 0.5,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363,
            loopStart: 0, loopLength: 4, loopType: 1)
        let first = PlaybackRow(index: 0, cells: [
            .init(note: 49, instrument: 1, volumeColumn: 0, effectType: effect, effectParam: effect == 0 ? 0x37 : 0x48),
            .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 14, effectParam: 0xE0 | delay)])
        let blank = PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0)
        let pattern = PlaybackPattern(index: 0, rows: [first,
            PlaybackRow(index: 1, cells: [blank, blank])])
        let instrument = PlaybackInstrument(index: 1, samples: [sample],
            noteSampleMap: Array(repeating: 0, count: 96))
        let input = PlaybackSong(title: "Public bounded pending row pitch",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: pattern], instrumentsByIndex: [1: instrument],
            restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
        return (input, first)
    }
}
