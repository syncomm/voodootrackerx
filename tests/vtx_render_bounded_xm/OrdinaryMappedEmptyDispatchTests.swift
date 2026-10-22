import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class OrdinaryMappedEmptyDispatchTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer

    func testExplicitMappedEmptyED0DispatchesAtRowEntry() throws {
        try checkDispatch(delay: 0)
    }

    func testExplicitMappedEmptyED3RetainsOldSourceUntilDispatch() throws {
        try checkDispatch(delay: 3)
    }

    func testRepresentedMissingAndAbsentMapControlsRetainExistingDispositions() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for delay in [0, 3, 6] {
            for destination in [0, 7, nil] as [Int?] {
                let plan = A.adapt(song(delay: delay, linear: linear, destination: destination), orderIndex: 0, sampleRate: rate)
                let starts = delay < 6 && destination != 7
                XCTAssertEqual(plan.pattern.events.count, starts ? 2 : 1)
                XCTAssertTrue(plan.xmEmptyRoutes.isEmpty)
                if starts {
                    let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.last)
                    XCTAssertEqual(mapping.instrumentIndex, 2)
                    XCTAssertEqual(mapping.sampleIndex, 0)
                    XCTAssertEqual(plan.pattern.events[1].scheduledStartFrame, (6 + delay) * Int(rate / 50))
                    XCTAssertEqual(plan.pattern.events[1].initialSourceFrame, 0)
                    // Characterization only: ABSENT-KEYMAP-POLICY remains OPEN.
                    // This pins the legacy adapter outcome without approving that policy.
                    XCTAssertEqual(mapping.firstPlayableSampleFallbackUsed, destination == nil)
                    XCTAssertEqual(mapping.sampleSelectionMethod, destination == nil ? .firstPlayableFallback : .sampleMap)
                } else {
                    XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
                }
            }
        } } }
    }

    func testEffectiveSameRowSpeedBPMAndChannelOrderChooseOnlyInRowDispatch() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] { for delay in [0, 1, 3, 5, 6] {
                for channel in [0, 2] { for bpm in [125, 150] {
                    let input = song(delay: delay, linear: linear, rowSpeed: speed, rowBPM: bpm, sourceChannel: channel)
                    let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                    XCTAssertEqual(plan.xmEmptyRoutes.count, delay < speed ? 1 : 0)
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    let diagnostic = try XCTUnwrap(plan.diagnostics.noteDelayEffects.first)
                    XCTAssertEqual(diagnostic.rowSpeed, speed)
                    XCTAssertEqual(diagnostic.rowBPM, bpm)
                    XCTAssertEqual(diagnostic.outOfRow, delay >= speed)
                    if delay < speed {
                        let frame = 6 * Int(rate / 50) + delay * Int(rate / (bpm == 125 ? 50 : 60))
                        XCTAssertEqual(plan.xmEmptyRoutes.first?.scheduledFrame, frame)
                        XCTAssertEqual(plan.xmEmptyRoutes.first?.channelIndex, channel)
                        XCTAssertEqual(plan.xmEmptyRoutes.first?.stoppedEventIndex, 0)
                        XCTAssertEqual(diagnostic.delayedFrame, frame)
                    } else {
                        XCTAssertNil(diagnostic.delayedFrame)
                        XCTAssertEqual(plan.xmChannelRows.last { $0.channelIndex == channel }?.controls.activeEventIndex, 0)
                    }
                } }
            } }
        } }
    }

    func testDelayedSettersSlidesAndFineColumnsUseDispatchDefaults() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for delay in [1, 3, 5] {
                for column: UInt8 in [0, 0x20, 0xC3, 0x61, 0x81, 0x91, 0xA3, 0xB8] {
                    let input = song(delay: delay, linear: linear, rows: [c(49, 1),
                        c(49, 2, volume: column, effect: 14, param: UInt8(0xD0 | delay)), c()])
                    let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                    let entry = plan.xmChannelRows[1].controls, after = plan.xmChannelRows[2].controls
                    XCTAssertEqual(entry.baseChannelVolume, 20)
                    XCTAssertEqual(entry.panningValue, 48)
                    XCTAssertEqual(entry.activeInstrumentIndex, 1)
                    XCTAssertEqual(after.baseChannelVolume, column == 0x20 ? 16 : column == 0x61 ? 44 - (5 - delay) : 44)
                    XCTAssertEqual(after.panningValue, column == 0xC3 ? 48 : 208)
                    XCTAssertEqual(plan.xmEmptyRoutes.first?.scheduledFrame, (6 + delay) * Int(rate / 50))
                    XCTAssertTrue(plan.diagnostics.voiceStateUpdates.filter { $0.source.rowIndex == 1 }.allSatisfy { $0.syntheticTick > 0 })
                    // Bx is a routing control here; its separate numeric phase disagreement stays open.
                }
            }
            let plain = A.adapt(song(delay: 0, linear: linear, rows: [c(49, 1), c(49, 2), c()]), orderIndex: 0, sampleRate: rate)
            let ed0 = A.adapt(song(delay: 0, linear: linear), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plain.xmEmptyRoutes, ed0.xmEmptyRoutes)
            XCTAssertEqual(plain.xmChannelRows, ed0.xmChannelRows)
            XCTAssertEqual(plain.xmEnvelopeTimeline, ed0.xmEnvelopeTimeline)
        } }
    }

    func testWholeIndexedScanAndSplitPCMShareInclusiveCutsAndLaterGeneration() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for delay in [0, 1, 3, 5] { for start in [0, 1] {
            let input = song(delay: delay, linear: linear, rows: [c(49, 1),
                c(49, 2, effect: 14, param: UInt8(0xD0 | delay)), c(), c(61), c()], startOrder: start)
            let request = PlaybackSongOfflineRenderRequest(song: input, startOrderIndex: start, orderCount: 1,
                config: .init(sampleRate: rate), rows: 5)
            let renderer = R(), full = renderer.render(request), boundary = (6 + delay) * Int(rate / 50)
            let history = R.PitchSourceHistory(plan: full.plan), later = 18 * Int(rate / 50)
            XCTAssertEqual(full.plan.diagnostics.eventMappings.map(\.instrumentIndex), [1, 2])
            XCTAssertEqual(full.plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 0])
            XCTAssertTrue(full.plan.diagnostics.eventMappings.allSatisfy { $0.source.orderIndex == start })
            XCTAssertEqual(full.plan.pattern.events[1].initialSourceFrame, 0)
            XCTAssertFalse(R.hasActiveSource(eventIndex: 0, at: later, plan: full.plan, pitchHistory: history))
            XCTAssertTrue(R.hasActiveSource(eventIndex: 1, at: later, plan: full.plan, pitchHistory: history))
            for size in [1, 2, 3] {
                let indexed = renderer.renderWindowed(request, windowRows: size)
                let scanned = renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: size)
                XCTAssertEqual(indexed.block.interleavedPCM, scanned.block.interleavedPCM)
                XCTAssertLessThanOrEqual(zip(full.block.interleavedPCM, indexed.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
            #if DEBUG
            let split = renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [boundary - 1, boundary, boundary + 1, later, later + 1])
            XCTAssertLessThanOrEqual(zip(full.block.interleavedPCM, split.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            #endif
            XCTAssertTrue(full.block.interleavedPCM[(boundary * 2)..<(later * 2)].allSatisfy { $0 == 0 })
        } } } }
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride, 1152)
        XCTAssertEqual(MemoryLayout<PlaybackXMChannelRow>.stride, 8)
    }

    func testColdCompletedReleasedAndRefusedLifetimesRemainDistinct() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for delay in [0, 3] {
            let dispatch = c(49, 2, effect: 14, param: UInt8(0xD0 | delay))
            for cold in [false, true] { for frames in [32, 32_768] {
                let input = song(delay: delay, linear: linear, rows: [cold ? c() : c(49, 1), c(97), dispatch, c()],
                    oldFrames: frames, envelopes: true)
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                let route = try XCTUnwrap(plan.xmEmptyRoutes.first)
                XCTAssertEqual(route.scheduledFrame, (12 + delay) * Int(rate / 50))
                XCTAssertEqual(route.stoppedEventIndex, cold ? nil : 0)
                XCTAssertEqual(plan.pattern.events.count, cold ? 0 : 1)
                let reset = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelUpdates.first { $0.scheduledFrame == route.scheduledFrame })
                XCTAssertNil(reset.sourceEventIndex)
                XCTAssertTrue(reset.state.keyOn)
                XCTAssertEqual(reset.state.fadeoutAccumulator, 32_768)
                XCTAssertEqual(reset.state.volumeTick, 0)
                XCTAssertEqual(reset.state.panTick, 0)
                XCTAssertEqual(reset.cachedDefaultVolume, 44)
            } }
            let refused = A.adapt(song(delay: delay, linear: linear, emptyRelative: -128), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(refused.xmEmptyRoutes.isEmpty)
            XCTAssertEqual(refused.pattern.events.count, 1)
            XCTAssertEqual(refused.xmChannelRows.last?.controls.activeEventIndex, 0)
        } } }
    }

    func testRepresentedQuietEDCharacterizesUnchangedLegacyGain() {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for delay in [0, 3] {
            let quiet = A.adapt(song(delay: delay, linear: linear, destination: 0, quiet: true), orderIndex: 0, sampleRate: rate)
            XCTAssertTrue(quiet.xmEmptyRoutes.isEmpty)
            XCTAssertEqual(quiet.pattern.events.count, 2)
            // Unchanged baseline retains the prior gain for represented ED0/EDx,
            // even with a zero-volume header. Its correctness is a separate open issue.
            XCTAssertEqual(quiet.diagnostics.eventMappings[1].sampleVolume, 0)
            XCTAssertEqual(quiet.pattern.events[1].gain, 20.0 / 64)
            XCTAssertEqual(quiet.pattern.events[1].sample.frameCount, 512)
        } } }
    }

    private func checkDispatch(delay: Int) throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let input = song(delay: delay, linear: linear)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 3)
            let session = R().prepare(request), plan = session.plan
            let frame = (6 + delay) * Int(rate / 50)
            let route = plan.xmEmptyRoutes.first
            XCTAssertEqual(plan.xmEmptyRoutes.count, 1)
            XCTAssertEqual(route?.source.rowIndex, 1)
            XCTAssertEqual(route?.scheduledFrame, frame)
            XCTAssertEqual(route?.tick, delay)
            XCTAssertEqual(route?.instrumentIndex, 2)
            XCTAssertEqual(route?.sampleIndex, 2, "exact S03, never the represented S01")
            XCTAssertEqual(route?.stoppedEventIndex, 0)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), [1])
            XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
            let row = try XCTUnwrap(plan.xmEnvelopeTimeline).channelUpdates.filter { $0.source.rowIndex == 1 }
            XCTAssertEqual(row.count, 6)
            for state in row {
                let dispatched = state.tick >= delay
                XCTAssertEqual(state.instrumentIndex, dispatched ? 2 : 1)
                XCTAssertEqual(state.sampleIndex, dispatched ? 2 : 0)
                XCTAssertEqual(state.sourceEventIndex, dispatched ? nil : 0)
                XCTAssertEqual(state.cachedDefaultVolume, dispatched ? 44 : 20)
                XCTAssertEqual(state.cachedDefaultPan, dispatched ? 208 : 48)
                XCTAssertTrue(state.state.keyOn)
                XCTAssertEqual(state.state.fadeoutAccumulator, 32_768)
            }
            let after = try XCTUnwrap(plan.xmChannelRows.last).controls
            XCTAssertNil(after.activeEventIndex)
            XCTAssertNil(after.activeEventMappingIndex)
            XCTAssertEqual(after.semanticInstrumentIndex, 2)
            XCTAssertEqual(after.semanticSampleIndex, 2)
            XCTAssertEqual(after.baseChannelVolume, 44)
            XCTAssertEqual(after.panningValue, 208)
            XCTAssertEqual(after.activeSampleRelativeNote, -5)
            XCTAssertEqual(after.activeSampleFinetune, -17)
            // Literal native reference periods: Linear 4940, Amiga 2310 (VTX scale 4).
            if linear { XCTAssertEqual(after.activeLinearPeriod, 4940) }
            else { XCTAssertEqual(after.activeAmigaPeriod, 9240) }
            let history = R.PitchSourceHistory(plan: plan)
            XCTAssertEqual(history.cutFrame(for: 0), frame)
            let step = rate == 48_000 ? 11418.0 / 65536 : 12428.0 / 65536
            for n in [frame - 1, frame, frame + 1, frame + 2 * Int(rate / 50)] {
                XCTAssertEqual(R.hasActiveSource(eventIndex: 0, at: n, plan: plan), n < frame)
                XCTAssertEqual(R.hasActiveSource(eventIndex: 0, at: n, plan: plan, pitchHistory: history), n < frame)
                // Position integration alone does not establish lifetime eligibility.
                XCTAssertEqual(history.advancedPosition(for: 0, at: n), Double(n) * step)
            }
            let mixer = CSoftwareMixer(config: request.config)
            let old = plan.pattern.events[0]
            let voice = mixer.addVoice(sample: old.sample, playbackStep: old.playbackStep)
            mixer.setSourceStopSchedule(plan.xmEmptyRoutes.compactMap {
                $0.stoppedEventIndex == 0 ? (frame: $0.scheduledFrame, voice: voice) : nil
            })
            _ = mixer.render(frames: frame)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, Double(frame) * step)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.active, true)
            let tail = mixer.render(frames: Int(rate / 10))
            XCTAssertEqual(tail.interleavedPCM.max(), 0)
            XCTAssertEqual(tail.interleavedPCM.min(), 0)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.active, false)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.loaded, false)
            let pcm = R().render(request).block.interleavedPCM
            XCTAssertTrue(pcm.dropFirst(frame * request.config.channelCount).allSatisfy { $0 == 0 })
        } }
    }

    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, volume: UInt8 = 0,
                   effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(delay: Int, linear: Bool, destination: Int? = 2,
                      speed: Int = 6, rows: [PlaybackCell]? = nil, rowSpeed: Int? = nil,
                      rowBPM: Int? = nil, sourceChannel: Int = 0, oldFrames: Int = 32_768,
                      envelopes: Bool = false, emptyRelative: Int = -5, quiet: Bool = false,
                      startOrder: Int = 0) -> PlaybackSong {
        // Original integer triangle PCM; no external sample data or reference tables.
        let pcm = (0..<oldFrames).map { Float(($0 % 128 - 64) * 192) / 32_768 }
        let first = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: pcm,
            volume: 20.0 / 64, panning: 48, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        let alternate = PlaybackSample(instrumentIndex: 2, sampleIndex: 0,
            pcm: Array(repeating: -0.1875, count: 512), volume: quiet ? 0 : 28.0 / 64, panning: 80,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 512, loopType: 1)
        let map = destination.map { slot in (0..<96).map { $0 == 60 ? 0 : slot } }
        let volume = PlaybackVolumeEnvelope(enabled: envelopes, points: [.init(tick: 0, value: 64), .init(tick: 48, value: 32)],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelopes ? 1 : 0, fadeout: 512)
        let pan = PlaybackPanningEnvelope(enabled: envelopes, points: [.init(tick: 0, value: 16), .init(tick: 48, value: 48)],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelopes ? 1 : 0)
        let cells = rows ?? [c(49, 1), c(49, 2, effect: 14, param: UInt8(0xD0 | delay)), c()]
        let patternRows = cells.enumerated().map { index, cell -> PlaybackRow in
            var columns = Array(repeating: c(), count: rowSpeed == nil ? 1 : 3)
            columns[sourceChannel] = cell
            if index == 1, let rowSpeed, let rowBPM {
                let commands = [c(effect: 15, param: UInt8(rowSpeed)), c(effect: 15, param: UInt8(rowBPM))]
                for (i, channel) in columns.indices.filter({ $0 != sourceChannel }).enumerated() { columns[channel] = commands[i] }
            }
            return .init(index: index, cells: columns)
        }
        return .init(title: "Original mapped empty dispatch", orders: (0...startOrder).map { .init(orderIndex: $0, patternIndex: 0) },
            patternsByIndex: [0: .init(index: 0, rows: patternRows)],
            instrumentsByIndex: [1: .init(index: 1, samples: [first], volumeEnvelope: volume, panningEnvelope: pan, noteSampleMap: Array(repeating: 0, count: 96)),
                2: .init(index: 2, samples: [alternate], volumeEnvelope: volume, panningEnvelope: pan, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125),
            usesLinearFrequencyTable: linear, xmSampleSlotProvenanceByInstrument: [2: [
                .init(sampleIndex: 2, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: false,
                    volume: 44, panning: 208, finetune: -17, relativeNote: emptyRelative)]])
    }
}
