import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original controls pin the ordinary EEx observations from G35A, independently of traversal conflicts.
final class PatternDelayTests: XCTestCase {
    private let rates = [44_100.0, 48_000]

    func testActualTicksFramesLastWriterAndPatternEdgeAcrossModesAndRates() throws {
        for linear in [true, false] { for rate in rates { for speed in [1, 3, 6, 31] {
            for delay: UInt8 in [0, 1, 2, 15] {
                let p = adapt(song([[c(note: 49, instrument: 1), c(14, 0xE0 | delay)],
                                    [c(note: 53), c()]], linear: linear, speed: speed), rate)
                let ticks = speed * (Int(delay) + 1), frame = Int(rate / 50)
                XCTAssertEqual(p.diagnostics.rowTiming.map(\.effectiveSpeed), [speed, speed])
                XCTAssertEqual(p.diagnostics.rowTiming.map(\.actualTickCount), [ticks, speed])
                XCTAssertEqual(p.diagnostics.rowTiming.map(\.rowStartFrame), [0, ticks * frame])
                XCTAssertEqual(p.canonicalTickClock.totalCanonicalTicks, ticks + speed)
                XCTAssertEqual(p.pattern.events.count, 2)
                XCTAssertEqual(p.pattern.events[1].scheduledStartFrame, ticks * frame)
                for tick in 0..<ticks {
                    let coordinate = try XCTUnwrap(p.canonicalTickClock.coordinate(syntheticRow: 0, tick: tick, channel: 0))
                    XCTAssertEqual(coordinate.absoluteFrame, tick * frame)
                    XCTAssertEqual(coordinate.canonicalTickOrdinal, tick)
                    XCTAssertEqual(coordinate.localEffectPhase, tick % speed)
                    XCTAssertEqual(coordinate.isFreshEntry, tick == 0)
                }
                XCTAssertNil(p.canonicalTickClock.coordinate(syntheticRow: 0, tick: ticks, channel: 0))
            }
            for (first, last): (UInt8, UInt8) in [(1, 2), (2, 1), (2, 0), (0, 2)] {
                let p = adapt(song([[c(14, 0xE0 | first), c(14, 0xE0 | last)], [c(), c()]],
                                   linear: linear, speed: speed), rate)
                XCTAssertEqual(p.diagnostics.rowTiming[0].actualTickCount, speed * (Int(last) + 1))
                let config = SyntheticTrackerTimingConfig(speed: speed, bpm: 125, sampleRate: rate, patternDelayCycles: Int(last))
                let status = PlaybackSongSyntheticAdapter.effectCommandStatus(c(14, 0xE0 | first),
                    timingConfig: config, channelState: .init())
                XCTAssertEqual(status, last == 0 ? .deferredUnsupported : .applied)
            }
        }
            let s = song([[c(note: 49, instrument: 1), c()], [c(), c(14, 0xE1)],
                          [c(note: 53), c()]], linear: linear)
            let edge = PlaybackSong(title: s.title, orders: [.init(orderIndex: 0, patternIndex: 0), .init(orderIndex: 1, patternIndex: 1)],
                patternsByIndex: [0: .init(index: 0, rows: Array(s.patternsByIndex[0]!.rows.prefix(2))),
                                  1: .init(index: 1, rows: [.init(index: 0, cells: [c(note: 53), c()])])],
                instrumentsByIndex: s.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: s.initialTiming, usesLinearFrequencyTable: linear)
            let p = adapt(edge, rate)
            XCTAssertEqual(p.diagnostics.rowTiming.last?.source.orderIndex, 1)
            XCTAssertEqual(p.diagnostics.rowTiming.last?.rowStartFrame, 18 * Int(rate / 50))
        } }
    }

    func testSameRowSpeedAndBPMOwnEveryHeldCycleRegardlessOfChannelOrder() {
        for linear in [true, false] { for rate in rates { for reversed in [false, true] {
            let commands = [c(15, 3), c(14, 0xE2), c(15, 150)]
            let p = adapt(song([[c(note: 49, instrument: 1), c(), c()],
                reversed ? Array(commands.reversed()) : commands, [c(), c(), c()]], linear: linear), rate)
            XCTAssertEqual(p.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 3, 3])
            XCTAssertEqual(p.diagnostics.rowTiming.map(\.effectiveBPM), [125, 150, 150])
            XCTAssertEqual(p.diagnostics.rowTiming.map(\.actualTickCount), [6, 9, 3])
            XCTAssertEqual(p.diagnostics.rowTiming.map(\.rowStartFrame), [0, Int(rate * 0.12), Int(rate * 0.27)])
        } } }
    }

    func testHeldZeroDispatchAdmitsSlidesAndMemoryButFineEffectsAndEntryRunOnce() throws {
        for linear in [true, false] { for rate in rates { for speed in [1, 6] {
            let delay: UInt8 = speed == 1 ? 2 : 1
            let p = adapt(song([[c(note: 49, instrument: 1), c()],
                [c(10, 1), c(14, 0xE0 | delay)], [c(10), c()]], linear: linear, speed: speed, volume: 0.5), rate)
            let calls = p.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 1 && $0.effectType == 10 && $0.applied }
            let count = speed * (Int(delay) + 1)
            XCTAssertEqual(calls.map(\.syntheticTick), Array(1..<count))
            XCTAssertEqual(calls.map(\.effectiveVolumeAfter), (1..<count).map { 32 - $0 })
            let after = try XCTUnwrap(p.xmChannelRows.first { $0.syntheticRow == 2 && $0.channelIndex == 0 })
            XCTAssertEqual(after.controls.baseChannelVolume, 32 - count + 1)
            XCTAssertEqual(after.controls.volumeSlideMemory?.parameter, 1)
            let status = PlaybackSongSyntheticAdapter.effectCommandStatus(c(10),
                timingConfig: .init(speed: speed, bpm: 125, sampleRate: rate, patternDelayCycles: Int(delay)),
                channelState: after.controls)
            XCTAssertEqual(status, .applied)
            XCTAssertEqual(p.pattern.events.count, 1)
            let fine = adapt(song([[c(note: 49, instrument: 1), c()],
                [c(14, 0xA1), c(14, 0xE2)], [c(), c()]], linear: linear, speed: speed, volume: 0.5), rate)
            XCTAssertEqual(fine.xmChannelRows.last { $0.channelIndex == 0 }?.controls.baseChannelVolume, 33)
            XCTAssertEqual(fine.pattern.events.count, 1)
            let pitch = adapt(song([[c(note: 49, instrument: 1), c()],
                [c(1, 1, volume: 0x61), c(14, 0xE0 | delay)], [c(1), c()]], linear: linear, speed: speed, volume: 0.5), rate)
            let slides = try XCTUnwrap(pitch.diagnostics.portamentoSlideEffects.first)
            XCTAssertEqual(slides.stepUpdates.map(\.syntheticTick), Array(1..<count))
            let base = linear ? 4608.0 : 6848.0, delta = linear ? 4.0 : 16.0
            XCTAssertEqual(slides.stepUpdates.map(\.linearPeriodAfter), (1..<count).map { base - Double($0) * delta })
            XCTAssertEqual(pitch.diagnostics.portamentoSlideEffects.last?.slideAmount, 1)
            XCTAssertEqual(pitch.xmChannelRows.last { $0.channelIndex == 0 }?.controls.baseChannelVolume, 32 - count + 1)
        } } }
    }

    func testHeldDelayAndRetriggerChildrenHaveDistinctCursorZeroGenerations() {
        for linear in [true, false] { for rate in rates {
            for (effect, parameter, ticks): (UInt8, UInt8, [Int]) in [
                (14, 0xD0, [0, 6]), (14, 0xD1, [1, 7]),
                (14, 0x92, [2, 4, 6, 8, 10]), (27, 2, [1, 3, 5, 7, 9, 11])] {
                let delayed = parameter == 0xD0 || parameter == 0xD1
                let p = adapt(song([[c(note: 49, instrument: 1), c()],
                    [c(effect, parameter, note: delayed ? 53 : 0, instrument: delayed ? 1 : 0), c(14, 0xE1)],
                    [c(), c()]], linear: linear), rate)
                let births = p.diagnostics.eventMappings.filter { $0.syntheticRow == 1 && $0.channelIndex == 0 }
                XCTAssertEqual(births.map(\.syntheticTick), ticks, "effect \(effect), parameter \(parameter)")
                XCTAssertEqual(Set(births.map(\.eventIndex)).count, ticks.count)
                for birth in births {
                    let event = p.pattern.events[birth.eventIndex]
                    XCTAssertEqual(event.initialSourceFrame, 0)
                    XCTAssertEqual(event.scheduledStartFrame, (6 + birth.syntheticTick) * Int(rate / 50))
                    XCTAssertEqual(birth.instrumentIndex, 1); XCTAssertEqual(birth.sampleIndex, 0)
                    XCTAssertFalse(birth.firstPlayableSampleFallbackUsed)
                }
            }
        } }
    }

    func testHeldNoteOnlyDelayResetsAtEachRealChildWithoutDuplicateColumnVibrato() throws {
        for linear in [true, false] { for rate in rates { for delay: UInt8 in [0, 1] {
            let p = adapt(song([[c(note: 49, instrument: 1, volume: 0xA4), c()], [c(note: 97), c()],
                [c(14, 0xD0 | delay, note: 53, volume: 0xB8), c(14, 0xE2)], [c(), c()]],
                linear: linear, envelope: true, auto: true), rate)
            let births = p.diagnostics.eventMappings.filter { $0.syntheticRow == 2 && $0.channelIndex == 0 }
            XCTAssertEqual(births.map(\.syntheticTick), [Int(delay), 6 + Int(delay), 12 + Int(delay)])
            for birth in births where birth.syntheticTick > 0 {
                XCTAssertFalse(p.noteOnlyEventIndices.contains(birth.eventIndex))
                XCTAssertFalse(p.coldReleasedEventIndices.contains(birth.eventIndex))
                let state = try XCTUnwrap(p.xmEnvelopeTimeline?.updatesByEvent[birth.eventIndex]?.first?.state)
                XCTAssertEqual(state.volumeTick, 0)
                XCTAssertEqual(state.fadeoutAccumulator, 32768)
                XCTAssertTrue(state.keyOn)
                let clock = try XCTUnwrap(p.instrumentAutovibrato(row: 2, tick: birth.syntheticTick, channel: 0))
                XCTAssertEqual(clock.phaseBefore, 0)
                XCTAssertEqual(clock.lastResetOrdinal, 12 + birth.syntheticTick)
            }
            let writes = p.diagnostics.vibratoEffects.filter { $0.syntheticRow == 2 }
                .flatMap { $0.stepUpdates + $0.inactiveSourceStepUpdates + [$0.supersededDelayedBirth].compactMap { $0 } }
                .filter { $0.syntheticTick < 18 }
            XCTAssertEqual(writes.map(\.syntheticTick).sorted(), Array(1..<18))
        } } }
    }

    func testDelayedNoteWithColumnFxStartsChildrenWithoutSeedingNewPortamentoMemory() {
        for linear in [true, false] { for rate in rates { for seeded in [false, true] {
            let p = adapt(song([[c(note: 49, instrument: 1), c()],
                [seeded ? c(3, 4, note: 53) : c(), c()],
                [c(14, 0xD1, note: 56, instrument: 1, volume: 0xF8), c(14, 0xE1)], [c(), c()]], linear: linear), rate)
            XCTAssertEqual(p.diagnostics.eventMappings.filter { $0.syntheticRow == 2 }.map(\.syntheticTick), [1, 7])
            XCTAssertEqual(p.xmChannelRows.last { $0.channelIndex == 0 }?.controls.tonePortamentoSpeed, seeded ? 4 : nil)
            XCTAssertEqual(p.pattern.events.count, 3)
        } } }
    }

    func testInstrumentOnlyDelayedChildrenKeepEachActualDispatchDiagnostic() {
        for linear in [true, false] { for rate in rates {
            let p = adapt(song([[c(note: 49, instrument: 1), c()],
                [c(14, 0xD1, instrument: 1), c(14, 0xE2)], [c(), c()]], linear: linear), rate)
            let births = p.diagnostics.eventMappings.filter { $0.syntheticRow == 1 && $0.channelIndex == 0 }
            let delays = p.diagnostics.noteDelayEffects.filter { $0.syntheticRow == 1 && $0.channelIndex == 0 }
            XCTAssertEqual(births.map(\.syntheticTick), [1, 7, 13])
            XCTAssertEqual(delays.map(\.syntheticTick), [1, 7, 13])
            XCTAssertEqual(delays.map(\.eventIndex), births.map { Optional($0.eventIndex) })
            XCTAssertEqual(delays.map(\.delayedFrame), [7, 13, 19].map { Optional($0 * Int(rate / 50)) })
            XCTAssertTrue(delays.allSatisfy { $0.status == .instrumentOnlyStarted })
            let ed0 = adapt(song([[c(note: 49, instrument: 1), c()],
                [c(14, 0xD0, instrument: 1), c(14, 0xE1)], [c(), c()]], linear: linear), rate)
            XCTAssertEqual(ed0.diagnostics.eventMappings.filter { $0.syntheticRow == 1 }.map(\.syntheticTick), [6])
            XCTAssertEqual(ed0.diagnostics.noteDelayEffects.map(\.syntheticTick), [0, 6])
            XCTAssertEqual(ed0.diagnostics.noteDelayEffects.map(\.status), [.instrumentOnlyImmediate, .instrumentOnlyStarted])
        } }
    }

    func testEveryActualTickAdvancesEnvelopeReleaseAndIndependentAutovibratoOnce() throws {
        for linear in [true, false] { for rate in rates {
            let p = adapt(song([[c(note: 49, instrument: 1), c(14, 0xE2)],
                [c(note: 97), c(14, 0xE1)], [c(), c()]], linear: linear, envelope: true, auto: true), rate)
            let updates = try XCTUnwrap(p.xmEnvelopeTimeline).channelUpdates.filter { $0.channelIndex == 0 }
            XCTAssertEqual(updates.count, 36)
            XCTAssertEqual(updates.prefix(18).map { $0.state.volumeTick }, Array(0..<18))
            XCTAssertEqual(updates.prefix(18).map { $0.state.volumeValue }, (0..<18).map { Float(64 - $0) / 64 })
            XCTAssertEqual(updates.suffix(18).map { $0.state.fadeoutAccumulator }, (1...18).map { 32768 - $0 * 512 })
            for row in 0..<3 { for tick in 0..<p.diagnostics.rowTiming[row].actualTickCount {
                let clock = try XCTUnwrap(p.instrumentAutovibrato(row: row, tick: tick, channel: 0))
                let ordinal = try XCTUnwrap(p.canonicalTickClock.coordinate(syntheticRow: row, tick: tick, channel: 0)).canonicalTickOrdinal
                XCTAssertEqual(clock.elapsedTicks, ordinal + 1)
                XCTAssertEqual(clock.phaseAfter, UInt8(((ordinal + 1) * 7) & 255))
                XCTAssertEqual(clock.lastResetOrdinal, 0)
            } }
            XCTAssertEqual(p.pattern.events.count, 1)
        } }
    }

    func testT11AndSpeedFiveArpeggioUseLocalPhaseWithoutFreshZeroReplay() throws {
        for linear in [true, false] { for rate in rates {
            let tremor = adapt(song([[c(note: 49, instrument: 1), c()],
                [c(29, 0x11), c(14, 0xE1)], [c(), c()]], linear: linear), rate)
            let writes = tremor.diagnostics.voiceStateUpdates.filter { $0.syntheticRow == 1 && $0.effectType == 29 && $0.applied }
            XCTAssertEqual(writes.map(\.syntheticTick), Array(1..<12))
            XCTAssertEqual(writes.map(\.effectiveVolumeAfter), [48, 48, 0, 0, 48, 48, 0, 0, 48, 48, 0])
            let arpSong = song([[c(note: 49, instrument: 1), c()],
                [c(0, 0x37), c(14, 0xE1)], [c(), c()]], linear: linear, speed: 5)
            let arp = adapt(arpSong, rate)
            let updates = arp.diagnostics.arpeggioEffects.first!.stepUpdates.filter { $0.syntheticTick < 10 }
            XCTAssertEqual(updates.map(\.syntheticTick), Array(0..<10))
            let offsets = [0, 3, 0, 7, 3, 7, 3, 0, 7, 3]
            for (u, offset) in zip(updates, offsets) {
                if linear { XCTAssertEqual(u.linearPeriodAfter, Double(4608 - 64 * offset)) }
                else { XCTAssertEqual(u.amigaPeriodAfter, Double(offset == 0 ? 6848 : offset == 3 ? 5760 : 4560)) }
                XCTAssertEqual(u.scheduledFrame, (5 + u.syntheticTick) * Int(rate / 50))
            }
            XCTAssertEqual(arp.pattern.events.count, 1)
            let rendered = PlaybackSongOfflineRenderer(preparedPlan: arp).render(.init(song: arpSong,
                config: .init(sampleRate: rate), frames: 1))
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: rendered)
            let commands = try XCTUnwrap(json["arpeggio_effects"] as? [[String: Any]])
            let children = try XCTUnwrap(commands.first?["step_updates"] as? [[String: Any]])
            XCTAssertEqual(children.first { $0["synthetic_tick"] as? Int == 5 }?["selected_semitone_offset"] as? Int, 7)
            XCTAssertEqual(children.first { $0["synthetic_tick"] as? Int == 10 }?["selected_semitone_offset"] as? Int, 0)
        } }
    }

    func testDirectRowHelperExcludesTheActualDelayedExitWithoutProjectionCapture() throws {
        for linear in [true, false] { for rate in rates {
            let s = song([[c(note: 49, instrument: 1), c()],
                [c(4, 0x48), c(14, 0xE1)], [c(33, 0x11), c()]], linear: linear)
            let traversal = PlaybackSongTraversalPlanner.plan(s, startOrderIndex: 0, orderCount: 1)
            let timing = PlaybackSongFxxTimingPlanner.plan(s, traversalPlan: traversal, sampleRate: rate)
            var context = PlaybackSongSyntheticAdapter.AdapterRowContext()
            for (index, row) in traversal.rows.enumerated() {
                _ = PlaybackSongSyntheticAdapter.appendEvents(from: row.row, source: row.source,
                    syntheticRow: row.syntheticRow, song: s, timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow),
                    timingPlan: timing, scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                    nextRow: index + 1 < traversal.rows.count ? traversal.rows[index + 1].row : nil, context: &context)
            }
            XCTAssertEqual(context.semanticPitchBuilder.speed, 0)
            let span = try XCTUnwrap(context.nativePitchWriterObserver.spans.first { $0.family == .vibrato })
            XCTAssertEqual(span.capturedChildCount, 11)
            XCTAssertEqual(span.originalChildren.last?.syntheticTick, 12)
            XCTAssertEqual(context.vibratoEffects.first?.stepUpdates.map(\.syntheticTick), Array(1..<12))
        } }
    }

    func testHeldChildrenAndTargetsDeliverIdenticallyAcrossWholeSplitStreamAndWindows() throws {
        for linear in [true, false] { for rate in rates {
            let s = song([[c(note: 49, instrument: 1), c(note: 49, instrument: 1), c()],
                [c(14, 0xD1, note: 53, instrument: 1), c(27, 2), c(14, 0xE2)],
                [c(29, 0x11), c(0, 0x37), c()]], linear: linear, envelope: true, auto: true)
            let p = adapt(s, rate), runtime = RuntimeCMixerAdapterEventPlan.make(song: s, sampleRate: rate)
            XCTAssertEqual(runtime.plan, p)
            XCTAssertEqual(Set(runtime.events.map(\.id)).count, runtime.events.count)
            let request = PlaybackSongOfflineRenderRequest(song: s, config: .init(sampleRate: rate),
                frames: Int(p.diagnostics.rowTiming.last!.rowEndExactFrame))
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: p), whole = renderer.render(request)
            try whole.controlAdmission.requireSuccess()
            XCTAssertTrue(whole.scheduledVoiceRejectionReasons.allSatisfy { $0 == nil })
            var streamed: [Float] = []
            let stream = renderer.renderStreaming(request, chunkFrameCount: 257) { _, _, block in streamed += block.interleavedPCM }
            try stream.controlAdmission.requireSuccess(); assertSourcePCM(streamed, whole.block.interleavedPCM)
            assertSourcePCM(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole.block.interleavedPCM)
            var windowStream: [Float] = []
            let result = renderer.renderWindowedStreaming(request, windowRows: 1) { _, _, _, block in windowStream += block.interleavedPCM }
            try result.controlAdmission.requireSuccess(); assertSourcePCM(windowStream, whole.block.interleavedPCM)
            #if DEBUG
            let boundary = 12 * Int(rate / 50)
            assertSourcePCM(renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [boundary - 1, boundary, boundary + 1]).block.interleavedPCM, whole.block.interleavedPCM)
            #endif
        } }
    }

    func testBounded32ChannelEEFPressurePreservesSourceAdmissionAndContinuation() throws {
        for rate in rates { for linear in [true, false] {
            let first = (0..<32).map { channel in c(channel == 31 ? 14 : 29, channel == 31 ? 0xEF : 0x11, note: 49, instrument: 1) }
            let s = song([first, Array(repeating: c(), count: 32)], linear: linear, speed: 31)
            let p = adapt(s, rate)
            XCTAssertEqual(p.diagnostics.rowTiming.map(\.actualTickCount), [496, 31])
            XCTAssertEqual(p.canonicalTickClock.totalCanonicalTicks, 527)
            XCTAssertEqual(p.pattern.events.count, 32)
            XCTAssertEqual(p.diagnostics.voiceStateUpdates.filter { $0.effectType == 29 && $0.applied }.count, 31 * 495)
            let renderer = PlaybackSongOfflineRenderer(preparedPlan: p)
            let request = PlaybackSongOfflineRenderRequest(song: s, config: .init(sampleRate: rate), frames: 527 * Int(rate / 50))
            let whole = renderer.render(request)
            try whole.controlAdmission.requireSuccess()
            // Thirty-two eager sources need no source-admission ledger.
            XCTAssertEqual(whole.scheduledVoiceIndices.compactMap { $0 }.count, 32)
            assertSourcePCM(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, whole.block.interleavedPCM)
            // More than 256 logical generations exercise Q2's bounded sequential admission.
            let starts = (0..<32).map { $0 < 31 ? c(note: 49, instrument: 1) : c() }
            let repeated = (0..<32).map { $0 < 31 ? c(14, 0xD0, note: 53, instrument: 1) : c(14, 0xEF) }
            let childSong = song([starts, repeated, Array(repeating: c(), count: 32)], linear: linear)
            let children = adapt(childSong, rate)
            XCTAssertEqual(children.pattern.events.count, 527)
            let childRenderer = PlaybackSongOfflineRenderer(preparedPlan: children)
            let childRequest = PlaybackSongOfflineRenderRequest(song: childSong, config: .init(sampleRate: rate), frames: 108 * Int(rate / 50))
            let childWhole = childRenderer.render(childRequest)
            try childWhole.controlAdmission.requireSuccess()
            XCTAssertEqual(childWhole.controlAdmission.sources?.started, 527)
            XCTAssertEqual(childWhole.controlAdmission.sources?.rejected, 0)
            XCTAssertLessThanOrEqual(childWhole.controlAdmission.sources?.peakLoaded ?? .max, 256)
            assertSourcePCM(childRenderer.renderWindowed(childRequest, windowRows: 1).block.interleavedPCM, childWhole.block.interleavedPCM)
        } }
    }

    private func adapt(_ s: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(s, startOrderIndex: 0, orderCount: s.orders.count, sampleRate: rate)
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func song(_ rows: [[PlaybackCell]], linear: Bool = true, speed: Int = 6, volume: Float = 0.75,
                      envelope: Bool = false, auto: Bool = false) -> PlaybackSong {
        let pcm = (0..<256).map { Float(sin(Double($0) * .pi / 128) * 0.25) }
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: pcm, volume: volume,
            panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 256, loopType: 1)
        let ve = PlaybackVolumeEnvelope(enabled: envelope, points: [.init(tick: 0, value: 64), .init(tick: 64, value: 0)],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: 512)
        let instrument = PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: ve, panningEnvelope: .disabled,
            autoVibrato: auto ? .init(waveformType: 0, sweep: 0, depth: 8, rate: 7) : .disabled, noteSampleMap: Array(repeating: 0, count: 96))
        return PlaybackSong(title: "Original ordinary pattern-delay controls", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: [1: instrument], restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
