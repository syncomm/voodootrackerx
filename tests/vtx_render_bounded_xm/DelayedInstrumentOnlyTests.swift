import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class DelayedInstrumentOnlyTests: XCTestCase {
    private typealias Adapter = PlaybackSongSyntheticAdapter

    func testRowEntryOwnerPrecedesDelayedExactRouteDefaultsAndReset() throws {
        for rate in [44_100.0, 48_000] {
            for (note, slot, volume, pan): (UInt8, UInt8, Int, UInt8) in [(49, 1, 40, 224), (53, 0, 24, 64)] {
                let module = song([c(note: note, instrument: 1), c(volume: 0xC3, effect: 12, parameter: 16),
                    c(instrument: 2, effect: 14, parameter: 0xD1), c(note: 61)])
                let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: rate)
                let maps = plan.diagnostics.eventMappings, events = plan.pattern.events
                XCTAssertEqual(maps.map(\.instrumentIndex), [1, 2, 2])
                XCTAssertEqual(maps.map(\.sampleIndex), [0, Int(slot), 0])
                XCTAssertEqual(maps.map(\.note), [note, note, 61])
                XCTAssertTrue(maps.allSatisfy { $0.sampleSelectionMethod == .sampleMap && !$0.firstPlayableSampleFallbackUsed })
                XCTAssertEqual(events[1].scheduledStartFrame, 13 * Int(rate / 50))
                XCTAssertEqual(events[1].gain, Float(volume) / 64)
                XCTAssertEqual(events[1].pan, PlaybackSamplePanningPolicy.plannedPan(pan))
                XCTAssertEqual(events[1].initialSourceFrame, 0)
                let row = try XCTUnwrap(plan.xmEnvelopeTimeline).channelUpdates.filter { $0.source.rowIndex == 2 }
                XCTAssertEqual(row.map(\.carriedInstrumentIndex), Array(repeating: 2, count: 6))
                XCTAssertEqual(row.map(\.sourceEventIndex), [0, 1, 1, 1, 1, 1])
                XCTAssertEqual(row.map(\.cachedDefaultVolume), [64, volume, volume, volume, volume, volume])
                XCTAssertEqual(row.map { $0.state.volumeTick }, [12, 0, 1, 2, 3, 4])
                XCTAssertEqual(row[1].state.fadeoutAccumulator, 32_768)
                XCTAssertTrue(row[1].state.keyOn)
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.channelPanningValue, Double(pan))
                XCTAssertEqual(plan.xmChannelRows[2].controls.activeInstrumentIndex, 1)
                XCTAssertEqual(plan.xmChannelRows[2].controls.baseChannelVolume, 16)
                XCTAssertEqual(MemoryLayout<Adapter.ChannelState>.stride, 1152)
            }
        }
    }

    func testSpeedFxxAndOutOfRowKeepOwnerSelectionWithoutClampingDispatch() throws {
        for rate in [44_100.0, 48_000] {
            for speed in [1, 2, 3, 6] {
                for delay in [1, 2, 3, 5, 15] {
                    for fChannel in [-1, 0, 1] {
                        let module = song([c(note: 49, instrument: 1), c(),
                            c(instrument: 2, effect: 14, parameter: UInt8(0xD0 | delay)), c(note: 61)],
                            speed: fChannel == -1 ? speed : 6, rowSpeed: fChannel == -1 ? nil : speed, fChannel: fChannel)
                        let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: rate)
                        let d = try XCTUnwrap(plan.diagnostics.noteDelayEffects.first)
                        XCTAssertTrue(d.rowEntryInstrumentSelected)
                        XCTAssertEqual(d.rowSpeed, speed)
                        XCTAssertEqual(d.status, delay < speed ? .instrumentOnlyStarted : .instrumentOnlyOutOfRow)
                        XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), delay < speed ? [1, 2, 2] : [1, 2])
                        XCTAssertEqual(plan.pattern.events.count, delay < speed ? 3 : 2)
                        if delay < speed {
                            XCTAssertEqual(d.delayedFrame, (2 * (fChannel == -1 ? speed : 6) + delay) * Int(rate / 50))
                        } else { XCTAssertNil(d.delayedFrame) }
                    }
                }
            }
        }
    }

    func testColumnSettersWaitForDelaySlidesPrecedeResetAndFineCommandsAreSkipped() throws {
        for (column, volume, pan): (UInt8, Float, Double) in [(0x20, 16, 224), (0xC3, 40, 48),
                (0x61, 36, 224), (0x81, 40, 224), (0x91, 40, 224), (0xD1, 40, 220), (0xE1, 40, 228)] {
            let module = song([c(note: 49, instrument: 1), c(volume: 0xC3, effect: 12, parameter: 16),
                c(instrument: 2, volume: column, effect: 14, parameter: 0xD1), c(note: 61)])
            let plan = Adapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
            XCTAssertEqual(plan.xmChannelRows[2].controls.baseChannelVolume, 16)
            XCTAssertEqual(plan.xmChannelRows[2].controls.panningValue, 48)
            XCTAssertEqual(plan.pattern.events[1].gain, column == 0x20 ? 0.25 : 0.625)
            XCTAssertEqual(plan.pattern.events[2].gain, volume / 64)
            XCTAssertEqual(plan.xmChannelRows[3].controls.panningValue, pan)
            XCTAssertTrue(plan.diagnostics.voiceStateUpdates.filter { $0.source.rowIndex == 2 }.allSatisfy { $0.syntheticTick > 0 })
        }
    }

    func testED0ReleaseCompletedColdAndOffsetBoundaries() throws {
        for rate in [44_100.0, 48_000] {
            for instrument: UInt8 in [1, 2] {
                let plan = Adapter.adapt(song([c(note: 49, instrument: 1), c(note: 97),
                    c(instrument: instrument, effect: 14, parameter: 0xD0), c(note: 61)]), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.pattern.events.count, 2)
                XCTAssertEqual(plan.diagnostics.noteDelayEffects.first?.status, .instrumentOnlyImmediate)
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?.first { $0.source.rowIndex == 2 }?.state.volumeTick, 0)
            }
            for completed in [false, true] {
                let plan = Adapter.adapt(song([c(note: 49, instrument: 1), c(note: 97),
                    c(instrument: 2, effect: 14, parameter: 0xD2)], completed: completed), orderIndex: 0, sampleRate: rate)
                let reset = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first)
                XCTAssertEqual(reset.scheduledFrame, 14 * Int(rate / 50))
                XCTAssertTrue(reset.state.keyOn)
                XCTAssertEqual(reset.state.fadeoutAccumulator, 32_768)
                XCTAssertEqual(reset.state.volumeTick, 0)
                XCTAssertEqual(reset.state.panTick, 0)
            }
            let cold = Adapter.adapt(song([c(instrument: 2, effect: 14, parameter: 0xD1), c(note: 61)]), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(cold.diagnostics.noteDelayEffects.first?.status, .instrumentOnlyNoRetainedNote)
            XCTAssertEqual(cold.pattern.events.count, 1)
            XCTAssertEqual(cold.pattern.events.first?.gain, 0)
            let offset = Adapter.adapt(song([c(note: 49, instrument: 1, effect: 9, parameter: 2),
                c(note: 49, effect: 9), c(instrument: 2, effect: 14, parameter: 0xD1)]), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(offset.pattern.events.map(\.initialSourceFrame), [512, 512, 0])
            XCTAssertEqual(offset.xmChannelRows.last?.controls.sampleOffsetMemory?.offsetFrames, 512)
        }
    }

    func testDelayedResetHonorsPriorPhaseControlsAndPreservesEffectMemory() {
        for suppress in [false, true] {
            let plan = Adapter.adapt(song([c(note: 49, instrument: 1),
                c(effect: 14, parameter: suppress ? 0x44 : 0x40), c(effect: 4, parameter: 0x47),
                c(effect: 7, parameter: 0x48), c(instrument: 2, effect: 14, parameter: 0xD1), c()]),
                orderIndex: 0, sampleRate: 48_000)
            let before = plan.xmChannelRows[4].controls, after = plan.xmChannelRows[5].controls
            XCTAssertEqual(before.vibratoPhase, 80)
            XCTAssertEqual(after.vibratoPhase, suppress ? 80 : 0)
            XCTAssertEqual(after.tremolo.phase, 0)
            XCTAssertEqual(after.vibratoSpeed, before.vibratoSpeed)
            XCTAssertEqual(after.vibratoDepth, before.vibratoDepth)
            XCTAssertEqual(after.tremolo.speed, before.tremolo.speed)
            XCTAssertEqual(after.tremolo.depth, before.tremolo.depth)
        }
    }

#if DEBUG
    func testOfflineContinuationImmediatelyBeforeAtAndAfterDelayedDispatch() throws {
        for rate in [44_100.0, 48_000] {
            let module = song([c(note: 49, instrument: 1), c(note: 97),
                c(instrument: 2, effect: 14, parameter: 0xD2), c(note: 61), c()])
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 5)
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            let boundary = 14 * Int(rate / 50)
            for splits in [[boundary - 1], [boundary], [boundary + 1], [boundary - 1, boundary, boundary + 1]] {
                let window = renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: splits)
                XCTAssertEqual(window.plan, full.plan)
                XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
        }
    }
#endif

    func testPublicFixtureEmptyRoutesDiagnosticsAndWholeWindowParity() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/delayed-instrument-only-edx.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 18)
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            XCTAssertTrue(full.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
            XCTAssertTrue(full.diagnostics.noteDelayEffects.contains { $0.status == .instrumentOnlyUnavailable })
            XCTAssertTrue(full.diagnostics.noteDelayEffects.contains { $0.status == .instrumentOnlyNoRetainedNote })
            XCTAssertTrue(full.plan.xmEmptyRoutes.contains { $0.instrumentIndex == 4 && $0.sampleIndex == 1 && $0.tick == 1 })
            XCTAssertTrue(full.plan.xmEmptyRoutes.contains { $0.instrumentIndex == 5 })
            for rows in [1, 2, 3, 5] {
                let window = renderer.renderWindowed(request, windowRows: rows)
                XCTAssertEqual(window.plan, full.plan)
                XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
            XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, full.plan)
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: full)
            let delays = try XCTUnwrap(json["note_delay_effects"] as? [[String: Any]])
            XCTAssertFalse(delays.contains { $0["status"] as? String == "no_note_deferred" })
            XCTAssertTrue(delays.contains { $0["status"] as? String == "instrument_only_delayed_source_started" && $0["retained_note"] as? Int == 49 })
        }
    }

    private func c(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0,
                   effect: UInt8 = 0, parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ cells: [PlaybackCell], speed: Int = 6, rowSpeed: Int? = nil,
                      fChannel: Int = -1, completed: Bool = false) -> PlaybackSong {
        func sample(_ owner: Int, _ slot: Int, _ volume: Float, _ pan: UInt8, _ value: Float) -> PlaybackSample {
            .init(instrumentIndex: owner, sampleIndex: slot, pcm: Array(repeating: value, count: completed && owner == 1 ? 64 : 1024),
                volume: volume, panning: pan, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: completed && owner == 1 ? 0 : 1024, loopType: completed && owner == 1 ? 0 : 1)
        }
        let envelope = PlaybackVolumeEnvelope(enabled: true, points: [.init(tick: 0, value: 64), .init(tick: 24, value: 16)],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 256)
        let pan = PlaybackPanningEnvelope(enabled: true, points: [.init(tick: 0, value: 16), .init(tick: 24, value: 48)],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1)
        let first = PlaybackInstrument(index: 1, samples: [sample(1, 0, 1, 192, 0.125)], volumeEnvelope: envelope,
            panningEnvelope: pan, noteSampleMap: Array(repeating: 0, count: 96))
        let second = PlaybackInstrument(index: 2, samples: [sample(2, 0, 0.375, 64, -0.125), sample(2, 1, 0.625, 224, 0.0625)],
            volumeEnvelope: envelope, panningEnvelope: pan, noteSampleMap: (0..<96).map { $0 < 49 ? 1 : 0 })
        let rows = cells.enumerated().map { row, cell -> PlaybackRow in
            var columns = [cell]
            if let rowSpeed, row == 2 {
                let f = c(effect: 15, parameter: UInt8(rowSpeed)); columns = fChannel == 0 ? [f, cell] : [cell, f]
            } else if fChannel == 0 { columns = [c(), cell] }
            return .init(index: row, cells: columns)
        }
        return .init(title: "Public G23", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows)], instrumentsByIndex: [1: first, 2: second],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true)
    }
}
