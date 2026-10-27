import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original public source reproduces the merged-base 23-request G32 identity witness.
final class G32EventIDGuardrailTests: XCTestCase {
    func testTwentyThreeAutomaticIDsRemainExactWhileNewOutputIDsStayUnique() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for bpm in [125, 250] {
            for managed in [false, true] {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: song(linear: linear, bpm: bpm, managed: managed), sampleRate: rate)
                let automatic = runtime.events.filter { $0.categories.contains("instrument_auto_pitch") }
                // Literal identities observed on the actual merged PR #511 base.
                XCTAssertEqual(automatic.map(\.id), Array(managed ? 73...95 : 13...35))
                let tick = Int(rate * 2.5 / Double(bpm))
                let ordinals = Array(1...6) + Array(13...29)
                XCTAssertEqual(automatic.map(\.scheduledFrame), ordinals.map { $0 * tick })
                XCTAssertEqual(automatic.map(\.syntheticTick), ordinals.map { $0 % 6 })
                XCTAssertEqual(automatic.map(\.activeEventIndex), Array(repeating: 0, count: 23))
                XCTAssertTrue(automatic.allSatisfy { $0.categories == ["step_update", "instrument_auto_pitch"] })
                XCTAssertEqual(Set(runtime.events.map(\.id)).count, runtime.events.count)
                let output = runtime.events.filter { if case .audibleTargetUpdate = $0.action { return true }; return false }
                if managed {
                    XCTAssertEqual(output.map(\.id), Array(43...72))
                } else {
                    XCTAssertEqual(output.map(\.id), [36, 37])
                    XCTAssertEqual(output.map(\.scheduledFrame), [0, 18 * tick])
                }
            }
        } } }
    }

    func testNeutralPanFutureReleaseAndPrunedPanPublicationsReserveOriginalSlots() throws {
        let neutral = panEnvelope([(0, 32), (100, 32)])
        let moving = panEnvelope([(0, 32), (1, 48), (100, 48)])
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let blanks = [[c(note: 49, instrument: 1)]] + Array(repeating: [c()], count: 5)
            var released = blanks; released[3] = [c(note: 97)]
            for (rows, pan, legacyCount) in [(blanks, neutral, 0), (blanks, moving, 35), (released, .disabled, 18)] {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: song(linear: linear, rows: rows, pan: pan), sampleRate: rate)
                try assertReservation(runtime, legacyCount: legacyCount)
                if legacyCount == 35 {
                    XCTAssertEqual(outputEvents(runtime).count, 2)
                    // Removed neutral/duplicate publications leave valid identity holes.
                    XCTAssertGreaterThan(try XCTUnwrap(runtime.events.map(\.id).max()), runtime.events.count - 1)
                }
            }
        } }
    }

    func testOffGridResetCountUsesPriorSemanticFactorsRatherThanLastNewPublication() throws {
        for cancels in [false, true] {
            let input = song()
            var plan = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: 48_000)
            plan.diagnostics.voiceStateUpdates = [write(frame: 8, before: 1, after: 0.5)] +
                (cancels ? [write(frame: 16, before: 0.5, after: 1)] : [])
            plan.playbackStateEvents = [.init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 16,
                change: .reset(.init(volumeEnvelope: true, panEnvelope: true, keyOn: true, fadeout: true)))]
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000, preparedPlan: plan)
            // Original semantic records are 0,16,960,...27840. At16 the original
            // fold compares final gain against frame0's gain, consuming both writers.
            try assertReservation(runtime, legacyCount: cancels ? 0 : 30)
            XCTAssertEqual(outputEvents(runtime).map(\.scheduledFrame), cancels ? [0, 8, 16] : [0, 8])
        }
    }

    func testMixedPlainAndManagedSameFrameOutputsKeepTheirOriginalSourceOrder() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let rows = [[c(note: 49, instrument: 1), c(note: 49, instrument: 2)]] +
                Array(repeating: [c(), c()], count: 4)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song(linear: linear, rows: rows), sampleRate: rate)
            try assertReservation(runtime, legacyCount: 30)
            let outputs = outputEvents(runtime)
            XCTAssertEqual(outputs.map(\.id), outputs.map(\.id).sorted())
            XCTAssertEqual(outputs.filter { $0.scheduledFrame == 0 }.map(\.activeEventIndex), [0, 1])
            let ordered = runtime.eventStorage.ordering.map { runtime.events[$0.eventIndex] }
            XCTAssertEqual(ordered.filter {
                if case .audibleTargetUpdate = $0.action { return $0.scheduledFrame == 0 }; return false
            }.map(\.activeEventIndex), [0, 1])
            let automatic = ordered.filter { $0.categories.contains("instrument_auto_pitch") }
            for burst in Dictionary(grouping: automatic, by: \.scheduledFrame).values {
                XCTAssertEqual(burst.map(\.activeEventIndex), [0, 1])
                XCTAssertEqual(burst.map(\.channelIndex), [0, 1])
            }
        } }
    }

    func testSevenOrdinaryFamiliesAndC14KeepTheirExistingPhysicalIDs() throws {
        let commands = [c(3, 1, note: 61), c(1, 1), c(14, 0x11), c(14, 0x21),
            c(33, 0x11), c(0, 0x37), c(4, 0x48)]
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for command in commands {
                let rows = [[c(note: 49, instrument: 1, volume: 0xA4)], [command], [c()]]
                let enabled = RuntimeCMixerAdapterEventPlan.make(song: song(linear: linear, rows: rows), sampleRate: rate)
                let ordinary = RuntimeCMixerAdapterEventPlan.make(song: song(linear: linear, rows: rows, automatic: false), sampleRate: rate)
                let original = ordinaryPitchEvents(ordinary), actual = ordinaryPitchEvents(enabled)
                XCTAssertFalse(original.isEmpty)
                XCTAssertEqual(actual.map(\.id), original.map(\.id))
                XCTAssertEqual(actual.map(\.categories), original.map(\.categories))
                XCTAssertEqual(actual.map(\.activeEventIndex), original.map(\.activeEventIndex))
                XCTAssertEqual(actual.map(\.scheduledFrame), original.map(\.scheduledFrame))
            }
        } }
        let c14 = RuntimeCMixerAdapterEventPlan.make(song: song(automatic: false), sampleRate: 48_000)
        let ordered = ordinaryPitchEvents(c14).filter { $0.scheduledFrame == 7680 }
        // This five-row witness also has C20: the actual merged-base IDs are4/5.
        XCTAssertEqual(ordered.map(\.id), [4, 5])
        XCTAssertEqual(ordered.compactMap { if case let .stepUpdate(_, step) = $0.action { return step }; return nil },
            [10963.0 / 65536, 10835.0 / 65536])
    }

    func testSkippedAutomaticRequestsCannotConsumeOrCollideWithPhysicalIdentities() throws {
        let input = song()
        var plan = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: 48_000)
        plan.instrumentAutovibratoRequests.insert(.init(row: 999, tick: 0, channel: 0, frame: 8, generation: 0, step: 1), at: 0)
        plan.instrumentAutovibratoInitialHoldEventIndices.insert(999)
        let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000, preparedPlan: plan)
        XCTAssertEqual(runtime.events.filter { $0.categories.contains("instrument_auto_pitch") }.map(\.id), Array(13...35))
        XCTAssertEqual(Set(runtime.events.map(\.id)).count, runtime.events.count)
        XCTAssertEqual(outputEvents(runtime).map(\.scheduledFrame), [0, 17_280])
        XCTAssertFalse(runtime.events.contains { $0.source.rowIndex == 999 })
    }

    func testOrdinaryZeroBirthHoldAndReplacementKeepGenerationOwnership() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for managed in [false, true] {
            let rows = [[c(note: 1, instrument: 1)], [c(note: 49, instrument: 1)], [c()]]
            let input = song(linear: linear, managed: managed, rows: rows, relative: -1)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let hold = try XCTUnwrap(runtime.events.first { $0.categories.contains("initial_pitch_hold") })
            XCTAssertEqual(hold.id, 2)
            XCTAssertEqual(hold.activeEventIndex, 0)
            XCTAssertEqual(hold.scheduledFrame, 0)
            let births = runtime.events.filter { if case .noteTrigger = $0.action { return true }; return false }
            XCTAssertEqual(births.map(\.activeEventIndex), [0, 1])
            XCTAssertEqual(births.map(\.scheduledFrame), [0, 6 * Int(rate / 50)])
            XCTAssertEqual(Set(runtime.events.map(\.id)).count, runtime.events.count)
            let result = PlaybackSongOfflineRenderer(preparedPlan: runtime.plan).render(.init(song: input,
                config: .init(sampleRate: rate), rows: 3))
            XCTAssertEqual(result.sameChannelVoiceLifetime.replacementEvents.first?.oldEventIndex, 0)
            XCTAssertEqual(result.sameChannelVoiceLifetime.replacementEvents.first?.newEventIndex, 1)
        } } }
    }

    func testInvalidRepresentedStartRetainsOldReservationWithoutCreatingOutput() throws {
        let rows = [[c(note: 49, instrument: 1), c(note: 49, instrument: 2)]] + Array(repeating: [c(), c()], count: 4)
        let input = song(rows: rows), seed = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: 48_000)
        let old = seed.pattern.events[1]
        let invalid = SyntheticTrackerEvent(row: old.row, tick: old.tick, scheduledStartFrame: old.scheduledStartFrame,
            sample: old.sample, gain: old.gain, pan: old.pan, playbackStep: old.playbackStep, loop: old.loop,
            initialSourceFrame: old.sample.frameCount, volumeEnvelope: old.volumeEnvelope, panEnvelope: old.panEnvelope)
        var plan = PlaybackSongSyntheticPlan(timingConfig: seed.timingConfig,
            pattern: .init(rowCount: seed.pattern.rowCount, events: [seed.pattern.events[0], invalid]), diagnostics: seed.diagnostics,
            canonicalTickClock: seed.canonicalTickClock, selectionDispatchFacts: seed.selectionDispatchFacts,
            instrumentAutovibratoRequests: seed.instrumentAutovibratoRequests,
            xmEnvelopeTimeline: seed.xmEnvelopeTimeline, xmChannelRows: seed.xmChannelRows)
        plan.xmAudibleTimeline = PlaybackXMAudibleTimeline(plan: plan)
        let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: 48_000, preparedPlan: plan)
        try assertReservation(runtime, legacyCount: 30)
        XCTAssertEqual(outputEvents(runtime).map(\.activeEventIndex), [0])
    }

    private func assertReservation(_ runtime: RuntimeCMixerAdapterEventPlan, legacyCount: Int,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let automatic = runtime.events.filter { $0.categories.contains("instrument_auto_pitch") }
        let outputs = outputEvents(runtime)
        let prefix = runtime.events.count - automatic.count - outputs.count
        XCTAssertEqual(try XCTUnwrap(automatic.first).id, prefix + legacyCount, file: file, line: line)
        // Construction IDs are grouped by causal producer; frame ordering can
        // interleave channels' IDs. Preserve that order while checking the range.
        XCTAssertEqual(automatic.map(\.id).sorted(), Array((prefix + legacyCount)..<(prefix + legacyCount + automatic.count)), file: file, line: line)
        XCTAssertEqual(Set(runtime.events.map(\.id)).count, runtime.events.count, file: file, line: line)
    }

    private func outputEvents(_ runtime: RuntimeCMixerAdapterEventPlan) -> [RuntimeCMixerAdapterEvent] {
        runtime.events.filter { if case .audibleTargetUpdate = $0.action { return true }; return false }
    }

    private func ordinaryPitchEvents(_ runtime: RuntimeCMixerAdapterEventPlan) -> [RuntimeCMixerAdapterEvent] {
        runtime.events.filter {
            if case .stepUpdate = $0.action { return !$0.categories.contains("instrument_auto_pitch") && !$0.categories.contains("initial_pitch_hold") }
            return false
        }
    }

    private func panEnvelope(_ points: [(Int, Int)]) -> PlaybackPanningEnvelope {
        .init(enabled: true, points: points.map { .init(tick: $0.0, value: $0.1) },
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1)
    }

    private func write(frame: Int, before: Float, after: Float) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        .init(source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), channelIndex: 0,
            syntheticRow: 0, syntheticTick: 0, scheduledFrame: frame, cellNote: 0, instrumentIndex: 1,
            commandSource: .effectColumn, command: .cxxSetVolume(value: Int(after * 64)), rawVolumeColumn: nil,
            effectType: 12, effectParam: UInt8(after * 64), status: .applied, behavior: nil, targetChannelIndex: nil,
            activeVoiceUpdated: true, activeEventIndex: 0, effectiveVolumeBefore: Int(before * 64), effectiveVolumeAfter: Int(after * 64),
            effectivePanBefore: nil, effectivePanAfter: nil, globalVolumeBefore: nil, globalVolumeAfter: nil,
            globalVolumeMultiplierBefore: nil, globalVolumeMultiplierAfter: nil, globalVolumeSlideDirection: nil,
            globalVolumeSlideAmount: nil, globalVolumeSlideClamped: nil, globalVolumeSlideBothNibblesNonzero: nil,
            globalVolumeSlidePolicy: nil, globalVolumeSlideResolvedParameter: nil, volumeSlideRawUpNibble: nil,
            volumeSlideRawDownNibble: nil, volumeSlideBothNibblesNonzero: nil, volumeSlidePolicy: nil, volumeSlideClamped: nil,
            volumeSlideTick0Suppressed: nil, volumeSlideRowSpeed: nil, effectMemoryReused: false, effectMemoryMissing: false,
            effectMemoryDeferred: false, memorySource: nil, memoryUnavailableReason: nil, gainBefore: before, gainAfter: after,
            panBefore: nil, panAfter: nil)
    }

    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                   instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private var witnessRows: [[PlaybackCell]] {
        [[c(note: 49, instrument: 1, volume: 0xA4)], [c(4, 0x48, volume: 0xB8)],
            [c()], [c(12, 32)], [c()]]
    }

    private func song(linear: Bool = true, bpm: Int = 125, managed: Bool = false,
                      rows: [[PlaybackCell]]? = nil, pan: PlaybackPanningEnvelope = .disabled,
                      relative: Int = 0, automatic: Bool = true) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: (0..<1024).map { Float(($0 * 131 + 711) % 16384 - 8192) / 32768 },
            volume: 1, panning: 128, relativeNote: relative, finetune: 0, baseSampleRate: 8363,
            loopLength: 1024, loopType: 1)
        let envelope = PlaybackVolumeEnvelope(enabled: managed,
            points: managed ? [.init(tick: 0, value: 64), .init(tick: 255, value: 64)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil,
            typeFlags: managed ? 1 : 0, fadeout: 0)
        let second = PlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: sample.pcm.map { -$0 * 0.5 },
            volume: 1, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopLength: 1024, loopType: 1)
        let selected = rows ?? witnessRows
        return .init(title: "Original G05 G32 identity guardrail", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: selected.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: envelope,
                panningEnvelope: pan, autoVibrato: automatic ? .init(waveformType: 0, sweep: 0, depth: 8, rate: 16) : .disabled,
                noteSampleMap: Array(repeating: 0, count: 96)),
                2: .init(index: 2, samples: [second],
                    volumeEnvelope: .init(enabled: true, points: [.init(tick: 0, value: 64)], sustainPointIndex: nil,
                        loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 0),
                    autoVibrato: automatic ? .init(waveformType: 0, sweep: 0, depth: 8, rate: 16) : .disabled,
                    noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: bpm), usesLinearFrequencyTable: linear)
    }
}
