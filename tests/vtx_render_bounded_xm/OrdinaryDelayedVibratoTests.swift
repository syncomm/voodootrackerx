import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class OrdinaryDelayedVibratoTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer

    func testED3BxUsesOldGenerationThenResetNewbornPitch() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let plan = A.adapt(song(linear), orderIndex: 0, sampleRate: rate)
            let writes = rowWrites(plan)
            XCTAssertEqual(writes.map { $0.0 }, [0, 0, 1, 1])
            XCTAssertEqual(writes.map { $0.1.syntheticTick }, [1, 2, 4, 5])
            // Actual pinned FT2 replay observations, independently authored exact-map XM.
            let base = linear ? 4608.0 : 1712
            XCTAssertEqual(writes.map { native($0.1, linear) }, [base, base + 24, base, base + 24])
            XCTAssertEqual(writes.map { $0.1.vibrato?.phaseBefore }, [0, 16, 0, 16])
            let step = Double(rate == 48_000 ? 11418 : 12428) / 65536
            let modulated = Double(linear ? (rate == 48_000 ? 11173 : 12161) : (rate == 48_000 ? 11260 : 12256)) / 65536
            XCTAssertEqual(writes.map { $0.1.playbackStepAfter }, [step, modulated, step, modulated])
            try assertBirthCursor(song(linear), rate, oldStep: modulated, newbornStep: step)
        } }
    }

    func testAlternateED3BxKeepsOldPCMAndTuningUntilBirth() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(linear, alternate: true)
            let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
            let writes = rowWrites(plan)
            XCTAssertEqual(writes.map { $0.0 }, [0, 0, 1, 1])
            XCTAssertEqual(writes.map { native($0.1, linear) }, linear ? [4608, 4632, 3636, 3660] : [1712, 1736, 712, 736])
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), [1, 2])
            let old = Double(linear ? (rate == 48_000 ? 11173 : 12161) : (rate == 48_000 ? 11260 : 12256)) / 65536
            let newborn = Double(linear ? (rate == 48_000 ? 27453 : 29880) : (rate == 48_000 ? 27455 : 29883)) / 65536
            XCTAssertEqual(plan.pattern.events[1].playbackStep, newborn)
            try assertBirthCursor(input, rate, oldStep: old, newbornStep: newborn)
        } }
    }

    func testOutOfRowED6StillExecutesBxWithoutTriggerOrReset() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let plan = A.adapt(song(linear, delay: 6), orderIndex: 0, sampleRate: rate)
            let writes = rowWrites(plan), base = linear ? 4608.0 : 1712
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(writes.map { $0.0 }, [0, 0, 0, 0, 0])
            XCTAssertEqual(writes.map { $0.1.syntheticTick }, [1, 2, 3, 4, 5])
            XCTAssertEqual(writes.map { native($0.1, linear) }, [0, 24, 45, 58, 63].map { base + $0 })
            XCTAssertEqual(plan.xmChannelRows.last { $0.channelIndex == 0 }?.controls.vibratoPhase, 80)
        } }
    }

    func testDelaysEffectiveFxxSpeedsAndExplicitVersusCarriedInstrument() throws {
        let deltas = [0.0, 24, 45, 58, 63] // independently observed B8 trajectory
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] { for delay in [0, 1, 3, 5, 6] { for explicit in [false, true] {
                let input = song(linear, delay: delay, cells: [c(49, 1, 0xA4),
                    c(49, explicit ? 1 : 0, 0xB8, 14, UInt8(0xD0 + delay)), c()], rowSpeed: speed, rowBPM: 150)
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.pattern.events.count, delay < speed ? 2 : 1)
                let writes = rowWrites(plan), base = linear ? 4608.0 : 1712
                let ticks = Array(1..<speed).filter { delay == 0 || delay >= speed || $0 != delay }
                XCTAssertEqual(writes.map { $0.1.syntheticTick }, ticks)
                XCTAssertEqual(writes.map { native($0.1, linear) }, ticks.map { base + deltas[delay > 0 && delay < $0 ? $0 - delay - 1 : $0 - 1] })
                XCTAssertEqual(writes.map { $0.0 }, ticks.map { delay < speed && $0 > delay ? 1 : 0 })
                XCTAssertEqual(writes.map { $0.1.scheduledFrame }, ticks.map { 6 * Int(rate / 50) + $0 * Int(rate / 60) })
                if delay < speed { XCTAssertEqual(plan.pattern.events[1].scheduledStartFrame, 6 * Int(rate / 50) + delay * Int(rate / 60)) }
                XCTAssertEqual(plan.xmChannelRows.last { $0.channelIndex == 0 }?.controls.vibratoPhase,
                    (delay > 0 && delay < speed ? speed - delay - 1 : speed - 1) * 16)
            } } }
            for control: UInt8 in [0x40, 0x44] {
                let input = song(linear, cells: [c(49, 1, 0xA4), c(0, 0, 0xB8, 14, control), c(49, 0, 0xB0, 14, 0xD3), c()])
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                let ds = plan.diagnostics.vibratoEffects.filter { $0.syntheticRow == 2 }
                let raw = try XCTUnwrap(ds.first?.supersededDelayedBirth)
                XCTAssertEqual(raw.vibrato?.phaseBefore, 112)
                XCTAssertEqual(raw.vibrato?.phaseAfter, 128)
                XCTAssertEqual(ds.last?.phaseAfter, control == 0x44 ? 160 : 32)
                XCTAssertEqual(rowWrites(plan, row: 2).map { native($0.1, linear) },
                    (control == 0x44 ? [58.0, 45, 0, -24] : [58.0, 45, 0, 24]).map { (linear ? 4608.0 : 1712) + $0 })
                XCTAssertEqual(ds.last?.vibratoSpeed, 4)
                XCTAssertEqual(ds.last?.vibratoDepth, 8)
                XCTAssertEqual(ds.last?.vibratoSpeedMemorySource?.source.rowIndex, 0)
                XCTAssertEqual(ds.last?.vibratoDepthMemorySource?.source.rowIndex, 1)
            }
        } }
    }

    func testRawSupersededBirthAndSourceLessRoutesRemainObservable() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for kind in ["normal", "cold", "completed", "released", "empty", "missing", "absent", "refused", "quiet"] {
                let cells = kind == "released" ? [c(49, 1, 0xA4), c(97), c(61, 2, 0xB8, 14, 0xD3), c()]
                    : [kind == "cold" ? c(0, 1, 0xA4) : c(49, 1, 0xA4), c(61, 2, 0xB8, 14, 0xD3), c()]
                let input = song(linear, cells: cells, oldFrames: kind == "completed" ? 24 : 32768,
                    oldVolume: kind == "quiet" ? 0 : 0.5, destination: kind == "absent" ? nil : kind == "empty" ? 1 : kind == "missing" ? 3 : 0,
                    empty: kind == "empty", refused: kind == "refused")
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
                let plan = try XCTUnwrap(runtime.plan), row = kind == "released" ? 2 : 1
                let ds = plan.diagnostics.vibratoEffects.filter { $0.syntheticRow == row }
                let prefix = try XCTUnwrap(ds.first)
                let n = (row * 6 + 3) * Int(rate / 50)
                if kind == "completed" {
                    XCTAssertTrue(prefix.stepUpdates.isEmpty)
                    XCTAssertEqual(prefix.inactiveSourceStepUpdates.map(\.syntheticTick), [1, 2])
                    XCTAssertFalse(R.hasActiveSource(eventIndex: 0, at: n - 1, plan: plan))
                } else if kind != "cold" {
                    XCTAssertEqual(prefix.stepUpdates.map(\.syntheticTick), kind == "refused" ? [1] : kind == "missing" ? [1, 2, 3] : [1, 2])
                }
                if ["normal", "completed", "released", "empty", "quiet", "absent"].contains(kind) {
                    XCTAssertEqual(prefix.supersededDelayedBirth?.vibrato?.phaseBefore, 32)
                    XCTAssertEqual(prefix.supersededDelayedBirth?.vibrato?.phaseAfter, 48)
                }
                if kind == "empty" {
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    XCTAssertEqual(plan.xmEmptyRoutes.first?.scheduledFrame, n)
                    XCTAssertEqual(plan.xmEmptyRoutes.first?.sampleIndex, 1)
                    XCTAssertTrue(ds.last!.stepUpdates.isEmpty)
                    XCTAssertEqual(ds.last?.inactiveSourceStepUpdates.map { native($0, linear) }, linear ? [3060, 3084] : [423, 447])
                    XCTAssertFalse(R.hasActiveSource(eventIndex: 0, at: n, plan: plan))
                }
                if kind == "missing" || kind == "refused" { XCTAssertEqual(plan.pattern.events.count, 1) }
                if kind == "absent" {
                    // Retained implementation debt; this does not approve a Policy B exception.
                    XCTAssertEqual(plan.diagnostics.eventMappings.last?.firstPlayableSampleFallbackUsed, true)
                }
                XCTAssertFalse(runtime.events.contains { e in
                    guard e.source.rowIndex == row, case let .stepUpdate(event, _) = e.action else { return false }
                    return kind == "completed" && event == 0 || kind == "cold" && e.scheduledFrame <= n
                })
            }
        } }
    }

    func testWholeIndexedScanSplitAndHistoryWithNeighboringWriters() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for alternate in [false, true] {
            let input = song(linear, alternate: alternate, cells: [c(49, 1, 0xA4),
                c(alternate ? 61 : 49, alternate ? 2 : 0, 0xB8, 14, 0xD3), c(0, 0, 0xB8, 4, 0x48),
                c(0, 0, 0, 6, 1), c(0, 0, 0, 0, 0x37), c()])
            let renderer = R(), request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 6)
            let whole = renderer.render(request), n = 9 * Int(rate / 50)
            for size in [1, 2, 3] {
                let indexed = renderer.renderWindowed(request, windowRows: size).block.interleavedPCM
                XCTAssertLessThanOrEqual(zip(whole.block.interleavedPCM, indexed).map { abs($0 - $1) }.max() ?? 0, 1e-7)
                #if DEBUG
                XCTAssertEqual(indexed, renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: size).block.interleavedPCM)
                #endif
            }
            #if DEBUG
            let split = renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: [n - 1, n, n + 1, n + Int(rate / 50), 18 * Int(rate / 50)]).block.interleavedPCM
            XCTAssertLessThanOrEqual(zip(whole.block.interleavedPCM, split).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            #endif
            let history = R.PitchSourceHistory(plan: whole.plan)
            XCTAssertTrue(R.hasActiveSource(eventIndex: 0, at: n - 1, plan: whole.plan, pitchHistory: history))
            XCTAssertTrue(R.hasActiveSource(eventIndex: 0, at: n, plan: whole.plan, pitchHistory: history))
            XCTAssertTrue(R.hasActiveSource(eventIndex: 1, at: n, plan: whole.plan, pitchHistory: history))
            XCTAssertEqual(history.advancedPosition(for: 1, at: n), 0)
            XCTAssertEqual(history.advancedPosition(for: 1, at: n + 1), whole.plan.pattern.events[1].playbackStep)
            let mixed = whole.plan.diagnostics.vibratoEffects.first { $0.syntheticRow == 2 }
            XCTAssertEqual(mixed?.stepUpdates.filter { $0.syntheticTick == 1 }.count, 2)
            XCTAssertEqual(mixed?.vibratoDepth, 8)
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: whole)
            let diagnostics = try XCTUnwrap(json["vibrato_effects"] as? [[String: Any]])
            XCTAssertEqual((diagnostics[0]["superseded_delayed_birth"] as? [String: Any])?["scheduled_frame"] as? Int, n)
        } } }
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride, 1152)
        XCTAssertEqual(MemoryLayout<PlaybackXMChannelRow>.stride, 8)
    }

    func testIndependentChannelGenerationsContinueAcrossLaterOrderWindows() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let seed = song(linear), pattern = seed.patternsByIndex[0]!
            let rows = pattern.rows.map { row -> PlaybackRow in
                var cells = row.cells
                cells[1] = row.index == 0 ? c(61, 2, 0xA3) : row.index == 1 ? c(49, 1, 0xB3, 14, 0xD1) : c()
                return .init(index: row.index, cells: cells)
            }
            let input = PlaybackSong(title: seed.title, orders: [.init(orderIndex: 0, patternIndex: 0), .init(orderIndex: 1, patternIndex: 1)],
                patternsByIndex: [0: .init(index: 0, rows: rows), 1: .init(index: 1, rows: [.init(index: 0, cells: [c(0, 0, 0, 4), c(0, 0, 0, 6), c()])])],
                instrumentsByIndex: seed.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate), plan = try XCTUnwrap(runtime.plan)
            let ds = plan.diagnostics.vibratoEffects.filter { $0.syntheticRow == 1 }
            XCTAssertEqual(ds.filter { $0.channelIndex == 0 }.map(\.activeEventIndex), [0, 2])
            XCTAssertEqual(ds.filter { $0.channelIndex == 1 }.map(\.activeEventIndex), [1, 3])
            XCTAssertEqual(ds.last { $0.channelIndex == 0 }?.phaseAfter, 32)
            XCTAssertEqual(ds.last { $0.channelIndex == 1 }?.phaseAfter, 48)
            XCTAssertEqual(plan.diagnostics.vibratoEffects.filter { $0.source.orderIndex == 1 }.map(\.activeEventIndex), [2, 3])
            let renderer = R(), request = PlaybackSongOfflineRenderRequest(song: input, orderCount: 2,
                config: .init(sampleRate: rate), frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let whole = renderer.render(request).block.interleavedPCM
            for size in [1, 2, 3] {
                let indexed = renderer.renderWindowed(request, windowRows: size).block.interleavedPCM
                XCTAssertLessThanOrEqual(zip(whole, indexed).map { abs($0 - $1) }.max() ?? 0, 1e-7)
                #if DEBUG
                XCTAssertEqual(indexed, renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: size).block.interleavedPCM)
                #endif
            }
        } }
    }

    private func assertBirthCursor(_ input: PlaybackSong, _ rate: Double, oldStep: Double, newbornStep: Double) throws {
        let renderer = R(), request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 3)
        let session = renderer.prepare(request), n = 9 * Int(rate / 50)
        let mixer = try XCTUnwrap(Mirror(reflecting: session).children.first { $0.label == "mixer" }?.value as? CSoftwareMixer)
        _ = session.render(frames: n)
        let oldVoice = try XCTUnwrap(session.scheduledVoiceIndices[0])
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: oldVoice)?.sampleStep, oldStep)
        let history = R.PitchSourceHistory(plan: session.plan)
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: oldVoice)?.samplePosition, history.advancedPosition(for: 0, at: n))
        _ = session.render(frames: 1)
        let newborn = try XCTUnwrap(session.scheduledVoiceIndices[1])
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: newborn)?.sampleStep, newbornStep)
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: newborn)?.samplePosition, newbornStep)
        XCTAssertEqual(history.advancedPosition(for: 1, at: n + 1), newbornStep)
    }

    private func rowWrites(_ plan: PlaybackSongSyntheticPlan, row: Int = 1) -> [(Int, PlaybackSongSyntheticTonePortamentoStepUpdate)] {
        plan.diagnostics.vibratoEffects.filter { $0.syntheticRow == row }.flatMap { d in d.stepUpdates.map { (d.activeEventIndex ?? -1, $0) } }
    }

    private func native(_ u: PlaybackSongSyntheticTonePortamentoStepUpdate, _ linear: Bool) -> Double {
        linear ? u.linearPeriodAfter : (u.amigaPeriodAfter ?? 0) / 4
    }

    private func c(_ n: UInt8 = 0, _ i: UInt8 = 0, _ v: UInt8 = 0, _ e: UInt8 = 0, _ p: UInt8 = 0) -> PlaybackCell {
        .init(note: n, instrument: i, volumeColumn: v, effectType: e, effectParam: p)
    }

    private func song(_ linear: Bool, delay: Int = 3, alternate: Bool = false, cells: [PlaybackCell]? = nil,
        rowSpeed: Int = 6, rowBPM: Int = 125, oldFrames: Int = 32768, oldVolume: Float = 0.5,
        destination: Int? = 0, empty: Bool = false, refused: Bool = false) -> PlaybackSong {
        let rows = cells ?? [c(49, 1, 0xA4), c(alternate ? 61 : 49, alternate ? 2 : 0, 0xB8, 14, UInt8(0xD0 + delay)), c()]
        let instruments = Dictionary(uniqueKeysWithValues: (1...2).map { i in
            (i, PlaybackInstrument(index: i, samples: [PlaybackSample(instrumentIndex: i, sampleIndex: 0,
                pcm: (0..<(i == 1 ? oldFrames : 32768)).map { Float(($0 * (i == 1 ? 137 : 197) + (i == 1 ? 0 : 731)) % 16384 - 8192) / 32768 },
                volume: i == 1 ? oldVolume : 0.5, panning: 128, relativeNote: i == 1 ? 0 : refused ? 96 : 3, finetune: i == 1 ? 0 : 24, baseSampleRate: 8363)],
                noteSampleMap: i == 1 ? Array(repeating: 0, count: 96) : destination.map { Array(repeating: $0, count: 96) }))
        })
        return .init(title: "Original delayed Bx control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map {
                .init(index: $0.offset, cells: [$0.element, $0.offset == 1 ? c(0, 0, 0, 15, UInt8(rowSpeed)) : c(), $0.offset == 1 ? c(0, 0, 0, 15, UInt8(rowBPM)) : c()])
            })],
            instrumentsByIndex: instruments, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: empty ? [2: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false, volume: 40, panning: 128, finetune: 24, relativeNote: 12)]] : [:])
    }
}
