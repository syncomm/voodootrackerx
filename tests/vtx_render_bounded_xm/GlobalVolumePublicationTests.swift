import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class GlobalVolumePublicationTests: XCTestCase {
    func testChannelOrderBirthSnapshotsAndBlankHoldsAtBothRates() {
        // Project-authored controls measured against pinned FT2 87be425.
        let cases: [([PlaybackCell], [Int], [Float], [Int])] = [
            ([note(0), g(16)], [0], [1], [16]),
            ([g(16), note(1)], [1], [0.25], [16]),
            ([note(0), c(), g(16), note(3)], [0, 3], [1, 0.25], [16]),
            ([c(note: 49, instrument: 1, effect: 16, param: 16)], [0], [0.25], [16]),
            ([note(0), g(32), note(2), g(16), note(4)], [0, 2, 4], [1, 0.5, 0.25], [32, 16]),
            ([note(0), g(32), c(), g(16)], [0], [1], [32, 16]),
            ([c(), g(32), note(2), g(16)], [2], [0.5], [32, 16]),
            ([c(), g(32), c(), g(16), note(4)], [4], [0.25], [32, 16])]
        for rate in [44_100.0, 48_000] {
            for (interaction, channels, gains, globals) in cases {
                var later = Array(repeating: c(), count: 6)
                for channel in channels { later[channel] = c(effect: 12, param: 64) }
                let module = song([[g(64)], interaction, [], later, []])
                let plan = adapt(module, rate)
                XCTAssertEqual(plan.pattern.events.map(\.gain), gains)
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.channelIndex), channels)
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), channels.map { $0 + 1 })
                XCTAssertEqual(mutations(plan, row: 1).map(\.globalVolumeAfter), globals.map(Optional.some))
                XCTAssertEqual(targets(plan, row: 1).map(\.gainAfter), gains.map(Optional.some))
                XCTAssertTrue(targets(plan, row: 2).isEmpty)
                XCTAssertEqual(targets(plan, row: 3).map(\.gainBefore), gains.map(Optional.some))
                XCTAssertEqual(targets(plan, row: 3).map(\.gainAfter), Array(repeating: 0.25, count: gains.count))
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                assertCausalGainEvents(runtime)
                XCTAssertFalse(runtime.events.contains { $0.source.rowIndex == 1 && $0.categories.contains("gain_pan_update") })
            }
        }
    }

    func testExplicitPublicationComparesHeldTargetIncludingRepeatedAndZeroValues() {
        let publications: [(PlaybackCell, Int, UInt8, Float, Int)] = [
            (c(effect: 12, param: 32), 0, 16, 0.125, 16),
            (c(effect: 12, param: 64), 0, 16, 0.25, 16),
            (c(volume: 0x50), 0, 16, 0.25, 16),
            (g(16), 1, 16, 0.25, 16),
            (g(32), 1, 16, 0.25, 32),
            (g(32), 0, 16, 0.5, 32),
            (c(effect: 12, param: 32), 0, 0, 0, 0)]
        for rate in [44_100.0, 48_000] {
            for (publication, writer, firstG, expected, finalGlobal) in publications {
                var later = Array(repeating: c(), count: 6); later[writer] = publication
                let module = song([[g(64)], [note(0), g(firstG)], [], later, [note(0)]])
                let plan = adapt(module, rate)
                let target = targets(plan, row: 3).first
                XCTAssertEqual(target?.gainBefore, 1)
                XCTAssertEqual(target?.gainAfter, expected)
                XCTAssertEqual(plan.pattern.events.last?.gain, Float(finalGlobal) / 64)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                let refresh = runtime.events.filter { $0.source.rowIndex == 3 && $0.categories.contains("gxx_channel_target") }
                XCTAssertEqual(refresh.count, 1)
                if case let .gainPanUpdate(index, gain, _) = refresh.first?.action {
                    XCTAssertEqual(index, 0); XCTAssertEqual(gain, expected)
                } else { XCTFail("Missing held-target refresh") }
                assertCausalGainEvents(runtime)
                let config = MixerRenderConfig(sampleRate: rate, channelCount: 1)
                let full = PlaybackSongOfflineRenderer().render(.init(song: module, config: config, rows: 5))
                // The constant sample makes a wrong held target audible independently
                // of the diagnostics. Check settled PCM after the existing 32-frame ramp.
                let tick = Int(rate / 50)
                XCTAssertEqual(full.block.interleavedPCM[12 * tick + 100], 1 / 32, accuracy: 1e-7)
                XCTAssertEqual(full.block.interleavedPCM[18 * tick + 100], expected / 32, accuracy: 1e-7)
                for window in [1, 2] {
                    let split = PlaybackSongOfflineRenderer().renderWindowed(.init(song: module, config: config, rows: 5), windowRows: window)
                    XCTAssertLessThanOrEqual(maxError(full.block.interleavedPCM, split.block.interleavedPCM), 1e-7)
                }
            }
        }
    }

    func testEnvelopeRefreshesNextTickWhilePanAndColdH00DoNotPublishScalarGain() {
        for rate in [44_100.0, 48_000] {
            let envelope = adapt(song([[g(64)], [note(0), g(16)], []], envelope: true), rate)
            let output = envelope.xmAudibleTimeline?.updates.filter { $0.eventIndex == 0 } ?? []
            XCTAssertEqual(output.first?.amplitude, 1)
            XCTAssertEqual(output.dropFirst().first?.amplitude, 0.25)
            XCTAssertEqual(output.dropFirst().first?.scheduledFrame, 7 * Int(rate / 50))
            XCTAssertEqual(targets(envelope, row: 1).first?.gainBefore, 1)
            for nonwriter in [c(), c(effect: 8, param: 64), c(volume: 0xC8), c(effect: 17)] {
                let plan = adapt(song([[g(64)], [note(0), g(16)], [], [nonwriter], []]), rate)
                XCTAssertTrue(targets(plan, row: 3).isEmpty)
                XCTAssertNil(plan.pattern.events[0].volumeEnvelope)
                XCTAssertTrue(plan.xmAudibleTimeline?.updates.isEmpty ?? true)
            }
        }
    }

    func testSourceLessAndCompletedSourcesDoNotChangeLaterNoteInheritance() {
        for rate in [44_100.0, 48_000] {
            for completed in [false, true] {
                let module = song([completed ? [note(0)] : [], [c(), g(16)], [], [note(0)]], completed: completed)
                let plan = adapt(module, rate)
                XCTAssertEqual(mutations(plan, row: 1).last?.globalVolumeAfter, 16)
                XCTAssertEqual(plan.pattern.events.last?.gain, 0.25)
                if !completed { XCTAssertEqual(plan.pattern.events.count, 1); XCTAssertTrue(targets(plan, row: 1).isEmpty) }
                assertCausalGainEvents(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate))
            }
        }
    }

    func testPublicFixturePinsGenerationsDiagnosticsAndWindowCarry() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/global-volume-publication.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan)
            let before = try XCTUnwrap(plan.diagnostics.eventMappings.first { $0.source.rowIndex == 1 })
            XCTAssertEqual(plan.pattern.events[before.eventIndex].gain, 1)
            XCTAssertEqual(targets(plan, row: 3).first { $0.channelIndex == 0 }?.gainBefore, 1)
            XCTAssertEqual(targets(plan, row: 3).first { $0.channelIndex == 0 }?.gainAfter, 0.25)
            XCTAssertEqual(plan.diagnostics.eventMappings.filter { $0.source.rowIndex == 16 }.map { plan.pattern.events[$0.eventIndex].gain }, [1, 0.5, 0.25])
            XCTAssertFalse(plan.xmEmptyRoutes.isEmpty)
            XCTAssertTrue(plan.diagnostics.voiceStateUpdates.contains { $0.effectType == 17 && $0.effectMemoryReused })
            XCTAssertTrue(plan.diagnostics.voiceStateUpdates.filter { $0.source.rowIndex == 36 && $0.effectType == 17 }.allSatisfy { $0.ignoredAsNoOp && !$0.activeVoiceUpdated })
            let replacement = try XCTUnwrap(plan.diagnostics.eventMappings.first { $0.source.rowIndex == 34 })
            XCTAssertEqual(targets(plan, row: 33).first { $0.channelIndex == 0 }?.activeEventIndex,
                plan.diagnostics.eventMappings.first { $0.source.rowIndex == 32 }?.eventIndex)
            XCTAssertEqual(plan.diagnostics.voiceStateUpdates.first {
                $0.syntheticRow == 35 && $0.channelIndex == 0 && $0.gainAfter != nil
            }?.activeEventIndex, replacement.eventIndex)
            assertCausalGainEvents(runtime)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate, channelCount: 2), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            XCTAssertEqual(full.plan, runtime.plan)
            for window in [1, 2, 7] {
                XCTAssertLessThanOrEqual(maxError(full.block.interleavedPCM, renderer.renderWindowed(request, windowRows: window).block.interleavedPCM), 1e-7)
            }
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let updates = try XCTUnwrap(json["volume_panning_state_updates"] as? [[String: Any]])
            let target = try XCTUnwrap(updates.first { ($0["source"] as? [String: Int])?["row"] == 3 && $0["command_name"] as? String == "gxxChannelTarget" })
            XCTAssertEqual(target["gain_before"] as? Double, 1)
            XCTAssertEqual(target["gain_after"] as? Double, 0.25)
            XCTAssertEqual((target["command"] as? [String: Any])?["publication_reason"] as? String, "local_volume_writer")
        }
    }

    private func assertCausalGainEvents(_ runtime: RuntimeCMixerAdapterEventPlan, file: StaticString = #filePath, line: UInt = #line) {
        var active = [Int: Int]()
        for entry in runtime.eventStorage.ordering {
            let event = runtime.events[entry.eventIndex]
            switch event.action {
            case let .noteTrigger(index, _, _): active[event.channelIndex] = index
            case let .sourceStop(index): if active[event.channelIndex] == index { active[event.channelIndex] = nil }
            case let .gainPanUpdate(index, _, _):
                XCTAssertEqual(active[event.channelIndex], index, "Publication must follow birth and precede retirement", file: file, line: line)
            default: break
            }
        }
    }
    private func targets(_ plan: PlaybackSongSyntheticPlan, row: Int) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        plan.diagnostics.voiceStateUpdates.filter { if case .gxxChannelTarget = $0.command { return $0.syntheticRow == row }; return false }
    }
    private func mutations(_ plan: PlaybackSongSyntheticPlan, row: Int) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        plan.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == row && $0.effectType == 16 }
    }
    private func adapt(_ module: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: rate)
    }
    private func maxError(_ a: [Float], _ b: [Float]) -> Float { zip(a,b).map { abs($0-$1) }.max() ?? 0 }
    private func c(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }
    private func note(_ channel: Int) -> PlaybackCell { c(note: 49, instrument: UInt8(channel + 1)) }
    private func g(_ volume: UInt8) -> PlaybackCell { c(effect: 16, param: volume) }
    private func song(_ rows: [[PlaybackCell]], envelope: Bool = false, completed: Bool = false) -> PlaybackSong {
        let instruments = (1...6).map { index -> (Int, PlaybackInstrument) in
            let sample = PlaybackSample(instrumentIndex: index, sampleIndex: 0, pcm: Array(repeating: Float(index) / 32, count: completed ? 32 : 256),
                volume: 1, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8_363,
                loopStart: 0, loopLength: completed ? 0 : 256, loopType: completed ? 0 : 1)
            let volume = PlaybackVolumeEnvelope(enabled: envelope, points: envelope ? [.init(tick: 0, value: 64), .init(tick: 64, value: 64)] : [],
                sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: 0)
            return (index, .init(index: index, samples: [sample], volumeEnvelope: volume, noteSampleMap: Array(repeating: 0, count: 96)))
        }
        return .init(title: "Public Gxx publication control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: 6 - $0.element.count)) })],
            instrumentsByIndex: Dictionary(uniqueKeysWithValues: instruments), restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: true)
    }
}
