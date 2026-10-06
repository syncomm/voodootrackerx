import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class GlobalVolumeSlideTimingTests: XCTestCase {
    func testPinnedNonzeroTickArithmeticSpeedsAndClampsAtBothRates() {
        for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] {
                for (param, delta): (UInt8, Int) in [(1, -1), (0x10, 1), (0x12, 1)] {
                    let plan = adapt(song([[c(note: 49, instrument: 1, effect: 16, param: 32)],
                        [c(effect: 17, param: param)], [c()], [c()]], speed: speed), rate)
                    let mutations = slides(plan)
                    XCTAssertEqual(mutations.map(\.syntheticTick), Array(1..<speed))
                    XCTAssertEqual(mutations.map(\.globalVolumeAfter), (1..<speed).map { 32 + $0 * delta })
                    XCTAssertEqual(mutations.map(\.scheduledFrame), (1..<speed).map { (speed + $0) * Int(rate / 50) })
                    XCTAssertTrue(mutations.allSatisfy { $0.behavior == .tickLevelAfterTick0 && !$0.activeVoiceUpdated })
                    XCTAssertTrue(targets(plan).filter { $0.syntheticRow == 2 }.isEmpty)
                }
            }
            for (seed, param, expected): (UInt8, UInt8, [Int]) in [(2, 1, [1, 0, 0, 0, 0]),
                (62, 0x10, [63, 64, 64, 64, 64]), (0, 1, [0, 0, 0, 0, 0]), (64, 0x12, [64, 64, 64, 64, 64])] {
                let plan = adapt(song([[c(effect: 16, param: seed)], [c(effect: 17, param: param)]]), rate)
                XCTAssertEqual(slides(plan).map(\.globalVolumeAfter), expected)
                XCTAssertTrue(targets(plan).isEmpty)
            }
        }
    }

    func testWriterTurnsCanonicalTransitionsAndDistinctSampleTargets() {
        // Independent public controls observed in pinned FT2 87be425; values include
        // the state before a writer, between writers, and after the final writer.
        for rate in [44_100.0, 48_000] {
            for writer in 0..<3 {
                var row = Array(repeating: c(), count: 3); row[writer] = c(effect: 17, param: 1)
                let plan = adapt(song([initial(3), row, Array(repeating: c(), count: 3)]), rate)
                let first = targets(plan).filter { $0.syntheticRow == 1 && $0.syntheticTick == 1 }
                XCTAssertEqual(first.map(\.channelIndex), [0, 1, 2])
                XCTAssertEqual(first.map(\.globalVolumeAfter), (0..<3).map { $0 < writer ? 32 : 31 })
                XCTAssertEqual(slides(plan).last?.globalVolumeAfter, 27)
                XCTAssertEqual(Set(plan.diagnostics.eventMappings.map(\.instrumentIndex)), [1, 2, 3])
            }
            for (parameters, factors, final): ([UInt8], [Int], Int) in [([1, 0, 0x10], [31, 31, 32], 32),
                ([0x10, 0, 1], [33, 33, 32], 32), ([1, 0, 1], [31, 31, 30], 22),
                ([0x10, 0, 0x10], [33, 33, 34], 42), ([0, 1, 0x10, 1, 0], [32, 31, 32, 31, 31], 27)] {
                let plan = adapt(song([initial(parameters.count), parameters.map { c(effect: $0 == 0 ? 0 : 17, param: $0) },
                    Array(repeating: c(), count: parameters.count)]), rate)
                let first = targets(plan).filter { $0.syntheticRow == 1 && $0.syntheticTick == 1 }
                XCTAssertEqual(first.map(\.globalVolumeAfter), factors)
                XCTAssertEqual(slides(plan).last?.globalVolumeAfter, final)
                let firstTurn = plan.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 1 && $0.syntheticTick == 1 }
                XCTAssertEqual(firstTurn.map(\.channelIndex), firstTurn.map(\.channelIndex).sorted())
                for target in first {
                    XCTAssertEqual(target.gainAfter, Float(factors[target.channelIndex] * [64, 32, 16][target.channelIndex % 3]) / 4096)
                }
                if parameters == [1, 0, 0x10] {
                    XCTAssertEqual(targets(plan).filter { $0.gainBefore != $0.gainAfter }.count, 2)
                    let runtime = RuntimeCMixerAdapterEventPlan.make(song: song([initial(3), parameters.map { c(effect: $0 == 0 ? 0 : 17, param: $0) },
                        Array(repeating: c(), count: 3)]), sampleRate: rate)
                    XCTAssertEqual(runtime.events.filter { $0.categories.contains("hxy_channel_target") }.map(\.channelIndex), [0, 1])
                }
            }
        }
    }

    func testPlainTargetsPersistAndOnlyVolumePublicationsRefreshCanonicalState() {
        let blank = Array(repeating: c(), count: 3)
        for publication in [c(), c(effect: 8, param: 64), c(effect: 12, param: 64), c(volume: 0x50), c(effect: 16, param: 40)] {
            var later = blank; later[publication.effectType == 16 ? 2 : 0] = publication
            let plan = adapt(song([initial(3), [c(), c(effect: 17, param: 1), c()], blank, later, blank]))
            XCTAssertTrue(targets(plan).filter { $0.syntheticRow == 2 }.isEmpty)
            let lastH = targets(plan).last { $0.syntheticRow == 1 && $0.channelIndex == 0 }
            XCTAssertEqual(lastH?.gainAfter, 28 / 64)
            let recovery = targets(plan).filter { $0.syntheticRow == 3 }
            if publication.effectType == 12 || publication.volumeColumn != 0 {
                XCTAssertEqual(recovery.first?.gainBefore, 28 / 64)
                XCTAssertEqual(recovery.first?.gainAfter, 27 / 64) // Same base volume still publishes.
            } else if publication.effectType == 16 {
                XCTAssertEqual(recovery.map(\.globalVolumeAfter), [27, 27, 40])
                XCTAssertTrue(targets(plan).filter { $0.syntheticRow == 4 }.isEmpty)
            } else { XCTAssertTrue(recovery.isEmpty) } // Pan-only writes retain held scalar gain.
        }
        let cold = adapt(song([[c(effect: 16, param: 32), c()], [c(), c(effect: 17, param: 1)],
            [c(note: 49, instrument: 1), c()]]))
        XCTAssertTrue(targets(cold).isEmpty)
        XCTAssertEqual(cold.pattern.events.count, 1)
        XCTAssertEqual(cold.pattern.events[0].gain, 27 / 64)
        let note = adapt(song([initial(3), [c(), c(effect: 17, param: 1), c()], blank,
            [c(note: 49, instrument: 1), c(), c()]]))
        XCTAssertEqual(note.pattern.events.last?.gain, 27 / 64)
    }

    func testSameRowFxxGxxAndLocalWritersUseCurrentTurnWithoutChangingMemory() {
        let fxx = adapt(song([initial(2), [c(effect: 17, param: 1), c(effect: 15, param: 3)],
            [c(effect: 17, param: 0x10), c(effect: 15, param: 1)]]))
        XCTAssertEqual(fxx.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 3, 1])
        XCTAssertEqual(slides(fxx).map(\.globalVolumeAfter), [31, 30])
        for writer in [0, 1] {
            var row = [c(effect: 16, param: 16), c(effect: 16, param: 16)]
            row[writer] = c(effect: 17, param: 1)
            let plan = adapt(song([initial(2), row]))
            XCTAssertEqual(targets(plan).filter { $0.syntheticRow == 1 && $0.syntheticTick == 0 }.map(\.globalVolumeAfter), writer == 0 ? [32, 16] : [16, 16])
            XCTAssertEqual(slides(plan).map(\.globalVolumeAfter), [15, 14, 13, 12, 11])
            XCTAssertEqual(targets(plan).filter { $0.syntheticRow == 1 && $0.syntheticTick == 1 }.map(\.globalVolumeAfter), writer == 0 ? [15, 15] : [16, 15])
        }
        let mixed = adapt(song([initial(3), [c(effect: 10, param: 1), c(effect: 17, param: 1), c(volume: 0x71)],
            Array(repeating: c(), count: 3)]))
        XCTAssertEqual(targets(mixed).filter { $0.syntheticTick == 1 }.map(\.gainAfter), [Float(63 * 32) / 4096, Float(32 * 31) / 4096, Float(17 * 31) / 4096])
        XCTAssertEqual(mixed.xmChannelRows.last { $0.channelIndex == 0 }?.controls.volumeSlideMemory?.parameter, 1)
    }

    func testEnvelopeFadeoutClocksAndForcedPostHRefreshUseExistingTargets() throws {
        for rate in [44_100.0, 48_000] {
            for release in [false, true] {
                let blank = Array(repeating: c(), count: 3)
                let rows = [initial(3), release ? Array(repeating: c(note: 97), count: 3) : blank,
                    [c(), c(effect: 17, param: 1), c()], blank]
                var baseline = rows; baseline[2] = blank
                let plan = adapt(song(rows, envelope: true, fadeout: release ? 512 : 0), rate)
                let control = adapt(song(baseline, envelope: true, fadeout: release ? 512 : 0), rate)
                XCTAssertEqual(plan.xmEnvelopeTimeline?.channelUpdates.map(\.state), control.xmEnvelopeTimeline?.channelUpdates.map(\.state))
                let recovery = try XCTUnwrap(targets(plan).first { $0.syntheticRow == 3 && $0.channelIndex == 0 })
                XCTAssertEqual(recovery.gainBefore, 28 / 64)
                XCTAssertEqual(recovery.gainAfter, 27 / 64)
                let audible = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.channelIndex == 0 && $0.scheduledFrame == recovery.scheduledFrame })
                let semantic = try XCTUnwrap(plan.xmEnvelopeTimeline?.updates.first { $0.channelIndex == 0 && $0.scheduledFrame == recovery.scheduledFrame })
                XCTAssertEqual(audible.amplitude, 27 / 64 * semantic.state.volumeValue * semantic.state.fadeoutValue)
                let request = PlaybackSongOfflineRenderRequest(song: song(rows, envelope: true, fadeout: release ? 512 : 0), config: .init(sampleRate: rate), rows: rows.count)
                let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block, full.block)
                XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: request.song, sampleRate: rate).plan, full.plan)
            }
        }
    }

    func testPublicFixtureRetainsCanonicalTransitionsHeldTargetsAndWindowPCM() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/global-volume-slide-timing.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let plan = adapt(module, rate)
            XCTAssertTrue(targets(plan).allSatisfy { $0.behavior == nil })
            XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 2 }.map(\.globalVolumeAfter), [33, 34])
            XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 3 }.map(\.globalVolumeAfter), [33, 32, 31, 30, 29])
            XCTAssertEqual(plan.diagnostics.eventMappings.filter { $0.syntheticRow == 4 }.map(\.effectiveGlobalVolumeValue), Array(repeating: 29, count: 5))
            XCTAssertEqual(targets(plan).filter { $0.syntheticRow == 6 && $0.syntheticTick == 1 }.map(\.globalVolumeAfter), [31, 31, 32, 32, 32])
            XCTAssertTrue(targets(plan).filter { $0.syntheticRow == 7 }.isEmpty)
            XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 8 }.last?.globalVolumeAfter, 22)
            XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 9 }.last?.globalVolumeAfter, 17)
            XCTAssertEqual(targets(plan).filter { $0.syntheticRow == 10 && $0.syntheticTick == 0 }.map(\.globalVolumeAfter), [17, 17, 17, 17, 32])
            XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 16 }.map(\.globalVolumeAfter), [33, 34, 35, 36, 37])
            XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 17 }.map(\.globalVolumeAfter), [38, 39, 40, 41, 42])
            XCTAssertTrue(slides(plan).filter { $0.syntheticRow == 17 }.allSatisfy(\.effectMemoryReused))
            XCTAssertEqual(plan.diagnostics.eventMappings.last?.effectiveGlobalVolumeValue, 37)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let end = try XCTUnwrap(runtime.plannedSongEndFrame)
            let renderer = PlaybackSongOfflineRenderer()
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), frames: end)
            let full = renderer.render(request)
            XCTAssertEqual(runtime.plan, full.plan)
            for window in [1, 4] {
                let split = renderer.renderWindowed(request, windowRows: window).block
                XCTAssertEqual(split.frameCount, full.block.frameCount)
                let error = zip(split.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0
                XCTAssertLessThanOrEqual(error, 1e-7, "Window \(window), rate \(rate)")
            }
            // Channel 0 has a newer trigger identity than channels 1...4 here.
            let ordered = runtime.events.filter { $0.categories.contains("hxy_channel_target") && $0.source.rowIndex == 19 && $0.syntheticTick == 1 }
            XCTAssertEqual(ordered.map(\.channelIndex), ordered.map(\.channelIndex).sorted())
        }
    }

    private func slides(_ plan: PlaybackSongSyntheticPlan) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        plan.diagnostics.voiceStateUpdates.filter { $0.effectType == 17 && $0.applied }
    }
    private func targets(_ plan: PlaybackSongSyntheticPlan) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        plan.diagnostics.voiceStateUpdates.filter { if case .hxyChannelTarget = $0.command { return true }; return false }
    }
    private func adapt(_ song: PlaybackSong, _ rate: Double = 48_000) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
    }
    private func c(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }
    private func initial(_ channels: Int) -> [PlaybackCell] {
        (0..<channels).map { channel in
            let effect: UInt8 = channel == 0 ? 16 : 0
            let parameter: UInt8 = channel == 0 ? 32 : 0
            return c(note: 49, instrument: UInt8(channel + 1), effect: effect, param: parameter)
        }
    }
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, envelope: Bool = false, fadeout: Int = 0) -> PlaybackSong {
        let channels = rows.map(\.count).max() ?? 1
        let instruments = (1...channels).map { index -> (Int, PlaybackInstrument) in
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0, pcm: Array(repeating: Float(index) / 32, count: 256),
                volume: Float([64, 32, 16][(index - 1) % 3]) / 64, panning: 128, relativeNote: 0, finetune: 0,
                baseSampleRate: 8_363, loopStart: 0, loopLength: 256, loopType: 1)
            let volume = PlaybackVolumeEnvelope(enabled: envelope,
                points: envelope ? [.init(tick: 0, value: 64), .init(tick: 4, value: 32), .init(tick: 100, value: 32)] : [],
                sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: fadeout)
            return (index, .init(index: index, samples: [sample], volumeEnvelope: volume, noteSampleMap: Array(repeating: 0, count: 96)))
        }
        return PlaybackSong(title: "Public G12 control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: Dictionary(uniqueKeysWithValues: instruments), restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true)
    }
}
