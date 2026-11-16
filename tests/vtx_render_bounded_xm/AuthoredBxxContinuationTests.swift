import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original public XM plus finite, explicitly expanded execution as the oracle.
enum AuthoredBxxProofFixture {
    static func make(linear: Bool = true, speed: Int = 2, passes: Int? = nil) throws -> PlaybackSong {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/authored-bxx-fade-v1.xm").path
        let source = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: path), modulePath: path)
        var patterns = source.patternsByIndex
        if passes != nil {
            let loop = try XCTUnwrap(patterns[1])
            patterns[1] = .init(index: 1, rows: loop.rows.map { row in
                .init(index: row.index, cells: row.cells.map { cell in
                    cell.effectType == 11 ? .init(note: cell.note, instrument: cell.instrument,
                        volumeColumn: cell.volumeColumn, effectType: 0, effectParam: 0) : cell
                })
            })
        }
        let orders = passes.map { [0] + Array(repeating: 1, count: $0) } ?? [0, 1]
        return .init(title: source.title, orders: orders.enumerated().map { .init(orderIndex: $0.offset, patternIndex: $0.element) },
            patternsByIndex: patterns, instrumentsByIndex: source.instrumentsByIndex,
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125),
            usesLinearFrequencyTable: linear)
    }
}

final class AuthoredBxxContinuationTests: XCTestCase {
    func testBoundedLiveBxxCarriesEveryHxyTickAcrossAdversarialSplitsAndColdOrigins() throws {
        for rate in [44_100.0, 48_000] { for linear in [true, false] { for speed in [1, 2, 3, 6] {
            for origin in [0, 1] { for cap in [1, 3, 4, 5] {
                let input = try AuthoredBxxProofFixture.make(linear: linear, speed: speed)
                let producer = try PlaybackSongUserLoopProducer(song: input,
                    initialPosition: .init(orderIndex: origin, patternIndex: origin, rowIndex: 0),
                    sampleRate: rate, sourceGeneration: 7, transportEpoch: 9,
                    mode: .finiteSong, terminalTailFrames: Int(rate * 3))
                let target = (origin == 0 ? 1 : 0) + 4 * 12
                var rows = 0, global = 64, frame = 0, slideCount = 0, births = 0
                while rows < target {
                    let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: min(cap, target - rows))
                    let plan = try XCTUnwrap(batch.adapterPlan.plan)
                    XCTAssertNil(batch.terminalStopReason)
                    XCTAssertEqual(batch.runtimeEndFrame, batch.endFrame, "No natural-end tail at Bxx")
                    XCTAssertEqual(batch.startFrame, frame)
                    XCTAssertLessThanOrEqual(plan.diagnostics.rowTiming.count, cap)
                    for timing in plan.diagnostics.rowTiming {
                        let absoluteRow = rows + timing.syntheticRow
                        let intro = origin == 0 && absoluteRow == 0
                        let loopRow = (absoluteRow - (origin == 0 ? 1 : 0)) % 4
                        XCTAssertEqual(timing.source.orderIndex, intro ? 0 : 1)
                        XCTAssertEqual(timing.source.rowIndex, intro ? 0 : loopRow)
                        let slides = plan.diagnostics.voiceStateUpdates.filter {
                            guard $0.syntheticRow == timing.syntheticRow && $0.applied else { return false }
                            if case .hxyGlobalVolumeSlide = $0.command { return true }; return false
                        }
                        XCTAssertEqual(slides.count, intro ? 0 : speed - 1)
                        for (index, slide) in slides.enumerated() {
                            let delta = loopRow < 2 ? 4 : 8
                            XCTAssertEqual(slide.syntheticTick, index + 1)
                            XCTAssertEqual(slide.globalVolumeBefore, global)
                            global = max(0, global - delta)
                            XCTAssertEqual(slide.globalVolumeAfter, global)
                            XCTAssertEqual(slide.globalVolumeSlideResolvedParameter, UInt8(delta))
                            XCTAssertEqual(slide.effectMemoryReused, loopRow == 1 || loopRow == 3)
                            slideCount += 1
                        }
                    }
                    births += batch.adapterPlan.events.filter { if case .noteTrigger = $0.action { return true }; return false }.count
                    XCTAssertFalse(plan.diagnostics.traversalGuardHit)
                    rows += plan.diagnostics.rowTiming.count; frame = batch.endFrame
                }
                XCTAssertEqual(slideCount, 48 * (speed - 1))
                XCTAssertEqual(global, speed == 1 ? 64 : 0)
                XCTAssertEqual(births, 12 + (origin == 0 ? 1 : 0), "Only authored notes create sources")
            } }
        } } }
    }

    func testLongSilentCyclesRemainBoundedAndCancellationDoesNotAdvanceCheckpoint() throws {
        let song = try AuthoredBxxProofFixture.make()
        let producer = try PlaybackSongUserLoopProducer(song: song,
            initialPosition: .init(orderIndex: 1, patternIndex: 1, rowIndex: 0), sampleRate: 48_000,
            sourceGeneration: 7, transportEpoch: 9, mode: .finiteSong)
        var plateau: PlaybackSongUserLoopProducer.Resources?
        // Exceeds the old lifetime row guard as well as ten complete cycles.
        for pass in 0..<400 {
            let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: 4)
            XCTAssertNil(batch.terminalStopReason)
            if pass == 12 { plateau = producer.resources }
            if pass > 12 { XCTAssertEqual(producer.resources, plateau) }
        }
        let before = producer.exportResumeState()
        XCTAssertThrowsError(try producer.next(minimumHorizonFrames: Int.max, maximumRows: 4, isCancelled: { true }))
        XCTAssertEqual(producer.exportResumeState().startFrame, before.startFrame)
        XCTAssertEqual(producer.exportResumeState().sequence, before.sequence)
        let resumed = try PlaybackSongUserLoopProducer(song: song, resuming: before, sourceGeneration: 7)
        XCTAssertEqual(try producer.next(minimumHorizonFrames: 1).adapterPlan,
            try resumed.next(minimumHorizonFrames: 1).adapterPlan)
    }

    func testFullAnalysisStillTerminatesAtKnownCycleAndFiniteControlKeepsExactEnd() throws {
        let input = try AuthoredBxxProofFixture.make()
        XCTAssertNil(PlaybackSongDuration.seconds(for: input))
        let full = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000)
        XCTAssertTrue(full.requiresAuthoredCycleContinuation)
        XCTAssertEqual(full.plan?.diagnostics.rowTiming.count, 5)
        XCTAssertEqual(full.plan?.diagnostics.traversalStopReason, .traversalGuardHit)
        let finite = RuntimeCMixerAdapterEventPlan.make(song: try AuthoredBxxProofFixture.make(passes: 3), sampleRate: 48_000)
        XCTAssertFalse(finite.requiresAuthoredCycleContinuation)
        XCTAssertEqual(finite.plannedSongEndFrame, 13 * 1920)
        XCTAssertEqual(finite.plan?.diagnostics.traversalStopReason, .songEnd)
        XCTAssertEqual(PlaybackSongDuration.seconds(for: try AuthoredBxxProofFixture.make(passes: 3)), 0.52)
    }

    func testBxxReturnStartsFreshPatternLocalE6ButRetainsActualFxxH00State() throws {
        let source = try AuthoredBxxProofFixture.make()
        func cell(_ effect: UInt8, _ parameter: UInt8) -> PlaybackCell {
            .init(note: 0, instrument: 0, volumeColumn: 0, effectType: effect, effectParam: parameter)
        }
        for timingCase in [false, true] {
            var pattern = try XCTUnwrap(source.patternsByIndex[1])
            var rows = pattern.rows
            rows[0] = .init(index: 0, cells: [rows[0].cells[0], cell(timingCase ? 15 : 14, timingCase ? 1 : 0x61)])
            rows[1] = .init(index: 1, cells: [rows[1].cells[0], cell(timingCase ? 15 : 14, timingCase ? 3 : 0x60)])
            pattern = .init(index: 1, rows: rows)
            let input = PlaybackSong(title: source.title, orders: source.orders, patternsByIndex: [0: source.patternsByIndex[0]!, 1: pattern],
                instrumentsByIndex: source.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: source.initialTiming, usesLinearFrequencyTable: true)
            for cap in [1, 3] {
                let producer = try PlaybackSongUserLoopProducer(song: input,
                    initialPosition: .init(orderIndex: 1, patternIndex: 1, rowIndex: 0), sampleRate: 48_000,
                    sourceGeneration: 7, transportEpoch: 9, mode: .finiteSong)
                let count = timingCase ? 8 : 20
                var visits = [Int](), globals = [Int]()
                while visits.count < count {
                    let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: min(cap, count - visits.count))
                    let plan = try XCTUnwrap(batch.adapterPlan.plan)
                    visits += plan.diagnostics.rowTiming.map { $0.source.rowIndex }
                    globals += plan.diagnostics.voiceStateUpdates.compactMap {
                        if case .hxyGlobalVolumeSlide = $0.command, $0.applied { return $0.globalVolumeAfter }; return nil
                    }
                }
                if timingCase { XCTAssertEqual(globals, [56, 48, 40, 32, 24, 16, 8, 0, 0, 0]) }
                else { XCTAssertEqual(visits, Array(repeating: [0, 0, 1, 2, 3], count: 4).flatMap { $0 }) }
            }
        }
    }
}
