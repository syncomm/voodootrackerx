import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class GlobalVolumeSlideMemoryTests: XCTestCase {
    func testColdH00HasNoPublicationOrPCMChangeIncludingHeldCounterexample() {
        for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] {
                for sounding in [false, true] {
                    let rows = [initial(sounding), [c(effect: 17)], []]
                    assertColdMatchesBlank(rows, coldRow: 1, speed: speed, rate: rate)
                    XCTAssertTrue(adapt(song(rows, speed: speed), rate).xmChannelRows.allSatisfy { $0.controls.globalVolumeSlideMemory == nil })
                }
            }
            for channel in [0, 2] {
                var cold = Array(repeating: c(), count: 3); cold[channel] = c(effect: 17)
                let rows = [initial(), [c(), c(effect: 17, param: 1)], [], cold, []]
                assertColdMatchesBlank(rows, coldRow: 3, rate: rate)
                let plan = adapt(song(rows), rate)
                XCTAssertEqual(slides(plan).last?.globalVolumeAfter, 27)
                XCTAssertEqual(targets(plan).last { $0.channelIndex == 0 }?.gainAfter, 28 / 64)
                XCTAssertTrue(targets(plan).filter { $0.syntheticRow >= 2 }.isEmpty)
            }
        }
    }

    func testWholeByteReplayAndProvenanceAtBothRates() throws {
        for rate in [44_100.0, 48_000] {
            for (parameter, delta): (UInt8, Int) in [(1, -1), (0x10, 1), (0x12, 1), (0x21, 2)] {
                let plan = adapt(song([initial(), [c(effect: 17, param: parameter)], [c(effect: 17)], [], [c(effect: 17)]]), rate)
                let replay = slides(plan).filter { $0.effectParam == 0 }
                XCTAssertEqual(replay.count, 10)
                XCTAssertEqual(replay.map(\.globalVolumeAfter), (6...15).map { 32 + $0 * delta })
                XCTAssertTrue(replay.allSatisfy { $0.globalVolumeSlideResolvedParameter == parameter && $0.effectMemoryReused && !$0.effectMemoryMissing })
                XCTAssertTrue(replay.allSatisfy { $0.memorySource?.effectParam == parameter && $0.memorySource?.source.rowIndex == 1 && $0.memorySource?.channelIndex == 0 })
                XCTAssertTrue(replay.allSatisfy { $0.syntheticTick > 0 && $0.behavior == .tickLevelAfterTick0 && !$0.activeVoiceUpdated })
                XCTAssertEqual(plan.xmChannelRows.last { $0.channelIndex == 0 }?.controls.globalVolumeSlideMemory?.parameter, parameter)
                XCTAssertTrue(plan.xmChannelRows.allSatisfy { $0.controls.volumeSlideMemory == nil })
                let frame = Int(rate / 50)
                XCTAssertEqual(replay.map(\.scheduledFrame), (1...5).map { (12 + $0) * frame } + (1...5).map { (24 + $0) * frame })
            }
        }
    }

    func testIndependentMemoriesAndMixedColdSeededWriterTurns() {
        for rate in [44_100.0, 48_000] {
            let independent = adapt(song([initial(), [c(effect: 17, param: 1), c(effect: 17, param: 0x10), c(effect: 17, param: 0x12)],
                Array(repeating: c(effect: 17), count: 3)]), rate)
            XCTAssertEqual(firstTargets(independent, row: 2), [36, 37, 38])
            XCTAssertEqual(slides(independent).last?.globalVolumeAfter, 42)
            XCTAssertEqual(slides(independent).filter { $0.syntheticRow == 2 && $0.syntheticTick == 1 }.map(\.globalVolumeSlideResolvedParameter), [1, 0x10, 0x12])
            let mixed = adapt(song([initial(), [c(effect: 17, param: 1), c(), c(effect: 17, param: 0x10)],
                Array(repeating: c(effect: 17), count: 3)]), rate)
            XCTAssertEqual(firstTargets(mixed, row: 2), [31, 31, 32])
            XCTAssertEqual(slides(mixed).filter { $0.syntheticRow == 2 }.map(\.channelIndex), Array(repeating: [0, 2], count: 5).flatMap { $0 })
            XCTAssertNil(mixed.xmChannelRows.last { $0.channelIndex == 1 }?.controls.globalVolumeSlideMemory)
            for earlierSeed in [false, true] {
                let seed = earlierSeed ? [c(effect: 17, param: 1)] : [c(), c(), c(effect: 17, param: 0x10)]
                let writers = earlierSeed ? [c(effect: 17), c(), c(effect: 17, param: 0x10)] : [c(effect: 17, param: 1), c(), c(effect: 17)]
                let plan = adapt(song([initial(), seed, writers]), rate)
                XCTAssertEqual(firstTargets(plan, row: 2), earlierSeed ? [26, 26, 27] : [36, 36, 37])
                let turn = plan.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 2 && $0.syntheticTick == 1 }
                XCTAssertEqual(turn.map(\.channelIndex), turn.map(\.channelIndex).sorted())
            }
        }
    }

    func testFxxReplayAndSpeedOneNeitherSeedsNorReplacesMemory() {
        let plan = adapt(song([initial(), [c(effect: 17, param: 1)],
            [c(effect: 17), c(), c(effect: 15, param: 1)], [c(effect: 17), c(), c(effect: 15, param: 3)],
            [c(effect: 17), c(), c(effect: 15, param: 6)]]))
        XCTAssertEqual(plan.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 6, 1, 3, 6])
        XCTAssertEqual((2...4).map { row in slides(plan).filter { $0.syntheticRow == row }.count }, [0, 2, 5])
        XCTAssertEqual(slides(plan).last?.globalVolumeAfter, 20)
        for seeded in [false, true] {
            let gate = adapt(song([initial(), seeded ? [c(effect: 17, param: 1)] : [],
                [c(effect: 17, param: 0x12), c(), c(effect: 15, param: 1)],
                [c(effect: 17), c(), c(effect: 15, param: 6)]]))
            XCTAssertEqual(gate.xmChannelRows.last { $0.channelIndex == 0 }?.controls.globalVolumeSlideMemory?.parameter, seeded ? 1 : nil)
            XCTAssertEqual(slides(gate).filter { $0.syntheticRow == 3 }.map(\.globalVolumeAfter), seeded ? [26, 25, 24, 23, 22] : [])
        }
    }

    func testMemorySurvivesNotesInstrumentsReleaseBlanksAndOrdersButFreshPlanClearsIt() {
        for change in [c(note: 51, instrument: 2), c(note: 51), c(instrument: 2), c(note: 97), c(effect: 20), c(instrument: 2, effect: 20), c()] {
            let module = song([initial(), [c(effect: 17, param: 1)], [change], [], [c(effect: 17)]], split: 3)
            let plan = adapt(module)
            XCTAssertEqual(slides(plan).last?.globalVolumeAfter, 22)
            XCTAssertEqual(slides(plan).last?.memorySource?.source.orderIndex, 0)
            XCTAssertEqual(slides(plan).last?.source.orderIndex, 1)
            XCTAssertEqual(plan.xmChannelRows.last { $0.channelIndex == 0 }?.controls.globalVolumeSlideMemory?.parameter, 1)
        }
        let fresh = adapt(song([initial(), [c(effect: 17)]]))
        XCTAssertTrue(slides(fresh).isEmpty)
        XCTAssertTrue(fresh.xmChannelRows.allSatisfy { $0.controls.globalVolumeSlideMemory == nil })
    }

    func testSourceLessAndCompletedRoutesRetainReplayAndLaterNoteInheritance() {
        for completed in [false, true] {
            let module = song([initial(completed), [c(effect: 17, param: 1)], [], [c(effect: 17)], [c(note: 49, instrument: 1)]], completed: completed)
            let plan = adapt(module)
            XCTAssertEqual(slides(plan).last?.globalVolumeAfter, 22)
            XCTAssertEqual(plan.pattern.events.last?.gain, 22 / 64)
            XCTAssertTrue(slides(plan).allSatisfy { !$0.activeVoiceUpdated })
            if !completed { XCTAssertEqual(plan.pattern.events.count, 1); XCTAssertTrue(targets(plan).isEmpty) }
        }
    }

    func testSeededClampReplayPublishesAndGxxUsesExistingChannelTurns() {
        for (volume, parameter): (UInt8, UInt8) in [(0, 1), (64, 0x10)] {
            var start = initial(); start[0] = c(note: 49, instrument: 1, effect: 16, param: volume)
            let plan = adapt(song([start, [c(), c(effect: 17, param: parameter)], [c(), c(effect: 17)]]))
            let replay = slides(plan).filter { $0.syntheticRow == 2 }
            XCTAssertEqual(replay.count, 5)
            XCTAssertTrue(replay.allSatisfy { $0.effectMemoryReused && $0.globalVolumeBefore == Int(volume) && $0.globalVolumeAfter == Int(volume) && $0.globalVolumeSlideClamped == true })
            XCTAssertEqual(targets(plan).filter { $0.syntheticRow == 2 && $0.syntheticTick > 0 }.count, 15)
        }
        for writer in [0, 2] {
            var seed = Array(repeating: c(), count: 3); seed[writer] = c(effect: 17, param: 1)
            var replay = Array(repeating: c(), count: 3); replay[2 - writer] = c(effect: 16, param: 16); replay[writer] = c(effect: 17)
            let plan = adapt(song([initial(), seed, replay]))
            XCTAssertEqual(slides(plan).last?.globalVolumeAfter, 11)
            XCTAssertEqual(firstTargets(plan, row: 2), writer == 0 ? [15, 15, 15] : [16, 16, 15])
        }
    }

    func testHMemoryIsIndependentOfAxy5xy6xyAndReplayPreservesEnvelopeClocks() {
        for family: UInt8 in [10, 5, 6] {
            let other = adapt(song([initial(), [c(effect: family, param: 2)], [c(effect: 17)]]))
            XCTAssertTrue(slides(other).isEmpty)
            XCTAssertNil(other.xmChannelRows.last { $0.channelIndex == 0 }?.controls.globalVolumeSlideMemory)
            let h = adapt(song([initial(), [c(effect: 17, param: 1)], [c(effect: family)]]))
            XCTAssertNil(h.xmChannelRows.last { $0.channelIndex == 0 }?.controls.volumeSlideMemory)
            XCTAssertEqual(h.xmChannelRows.last { $0.channelIndex == 0 }?.controls.globalVolumeSlideMemory?.parameter, 1)
        }
        for rate in [44_100.0, 48_000] {
            for released in [false, true] {
                let rows = [initial(), [c(effect: 17, param: 1)], released ? [c(note: 97)] : [], [c(effect: 17)], []]
                var explicit = rows; explicit[3] = [c(effect: 17, param: 1)]
                let renderer = PlaybackSongOfflineRenderer()
                let a = renderer.render(.init(song: song(rows, envelope: true), config: .init(sampleRate: rate), rows: 5))
                let b = renderer.render(.init(song: song(explicit, envelope: true), config: .init(sampleRate: rate), rows: 5))
                XCTAssertEqual(a.plan.xmEnvelopeTimeline?.channelUpdates.map(\.state), b.plan.xmEnvelopeTimeline?.channelUpdates.map(\.state))
                XCTAssertEqual(a.block, b.block)
            }
        }
    }

    func testPublicFixtureWholeWindowAndRuntimePlansCarryMemoryAcrossOrderBoundary() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/global-volume-slide-memory.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let end = try XCTUnwrap(runtime.plannedSongEndFrame)
            let renderer = PlaybackSongOfflineRenderer(), request = PlaybackSongOfflineRenderRequest(song: module, orderCount: 2, config: .init(sampleRate: rate), frames: end)
            let full = renderer.render(request)
            XCTAssertEqual(runtime.plan, full.plan)
            XCTAssertTrue(slides(full.plan).contains { $0.effectMemoryReused && $0.source.orderIndex == 1 && $0.memorySource?.source.orderIndex == 0 })
            XCTAssertFalse(full.plan.xmEmptyRoutes.isEmpty)
            for window in [1, 4] {
                let split = renderer.renderWindowed(request, windowRows: window)
                XCTAssertEqual(split.block.frameCount, full.block.frameCount)
                XCTAssertLessThanOrEqual(zip(split.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
        }
    }

    private func assertColdMatchesBlank(_ rows: [[PlaybackCell]], coldRow: Int, speed: Int = 6, rate: Double) {
        var blank = rows; blank[coldRow] = []
        let a = song(rows, speed: speed), b = song(blank, speed: speed)
        let plan = adapt(a, rate)
        XCTAssertTrue(targets(plan).filter { $0.syntheticRow == coldRow }.isEmpty)
        XCTAssertTrue(plan.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == coldRow && $0.effectType == 17 }.allSatisfy { $0.ignoredAsNoOp && !$0.activeVoiceUpdated && $0.effectMemoryMissing })
        XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: a, sampleRate: rate).events, RuntimeCMixerAdapterEventPlan.make(song: b, sampleRate: rate).events)
        let renderer = PlaybackSongOfflineRenderer()
        let request = PlaybackSongOfflineRenderRequest(song: a, config: .init(sampleRate: rate), rows: rows.count)
        let full = renderer.render(request)
        XCTAssertEqual(full.block, renderer.render(.init(song: b, config: .init(sampleRate: rate), rows: rows.count)).block)
        XCTAssertEqual(full.block, renderer.renderWindowed(request, windowRows: 1).block)
    }
    private func adapt(_ module: PlaybackSong, _ rate: Double = 48_000) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(module, startOrderIndex: 0, orderCount: module.orders.count, sampleRate: rate)
    }
    private func slides(_ plan: PlaybackSongSyntheticPlan) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        plan.diagnostics.voiceStateUpdates.filter { $0.effectType == 17 && $0.applied }
    }
    private func targets(_ plan: PlaybackSongSyntheticPlan) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        plan.diagnostics.voiceStateUpdates.filter { if case .hxyChannelTarget = $0.command { return true }; return false }
    }
    private func firstTargets(_ plan: PlaybackSongSyntheticPlan, row: Int) -> [Int?] {
        targets(plan).filter { $0.syntheticRow == row && $0.syntheticTick == 1 }.map(\.globalVolumeAfter)
    }
    private func c(note: UInt8 = 0, instrument: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: param)
    }
    private func initial(_ sounding: Bool = true) -> [PlaybackCell] {
        (0..<3).map { channel -> PlaybackCell in
            let note: UInt8 = sounding ? 49 : 0
            let instrument: UInt8 = sounding ? UInt8(channel + 1) : 0
            let effect: UInt8 = channel == 0 ? 16 : 0
            let parameter: UInt8 = channel == 0 ? 32 : 0
            return c(note: note, instrument: instrument, effect: effect, param: parameter)
        }
    }
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, split: Int? = nil, completed: Bool = false, envelope: Bool = false) -> PlaybackSong {
        let instruments = (1...3).map { index -> (Int, PlaybackInstrument) in
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0, pcm: Array(repeating: Float(index) / 32, count: completed ? 32 : 256),
                volume: Float([64, 32, 16][index - 1]) / 64, panning: 128, relativeNote: 0, finetune: 0,
                baseSampleRate: 8_363, loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
            let volume = PlaybackVolumeEnvelope(enabled: envelope, points: envelope ? [.init(tick: 0, value: 64), .init(tick: 4, value: 32), .init(tick: 100, value: 32)] : [],
                sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: envelope ? 512 : 0)
            return (index, .init(index: index, samples: [sample], volumeEnvelope: volume, noteSampleMap: Array(repeating: 0, count: 96)))
        }
        let cells = rows.map { $0 + Array(repeating: c(), count: 3 - $0.count) }
        let groups = split.map { [Array(cells[..<$0]), Array(cells[$0...])] } ?? [cells]
        return .init(title: "Public G13 control", orders: groups.indices.map { .init(orderIndex: $0, patternIndex: $0) },
            patternsByIndex: Dictionary(uniqueKeysWithValues: groups.enumerated().map { index, group in
                (index, .init(index: index, rows: group.enumerated().map { .init(index: $0.offset, cells: $0.element) }))
            }), instrumentsByIndex: Dictionary(uniqueKeysWithValues: instruments), restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true)
    }
}
