import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class CausalReleaseResultTests: XCTestCase {
    private let rates = [44_100.0, 48_000.0]

    func testDecisionOwnsFrozenValuesWithoutMutatingInputsAndProjectionDoesNotRecomputeThem() throws {
        for rate in rates {
            let plan = PlaybackSongSyntheticAdapter.adapt(Self.song([:]), orderIndex: 0, sampleRate: rate)
            let controls = plan.xmChannelRows[0].controls
            let source = PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1)
            let decision = PlaybackSongSyntheticAdapter.decideKeyOff(source: source, channelIndex: 0,
                syntheticRow: 1, syntheticTick: 2, scheduledFrame: 0, rowSpeed: 6, rowBPM: 137,
                cell: Self.cell(effect: 0x14, parameter: 2), channelState: controls,
                events: plan.pattern.events, eventMappings: plan.diagnostics.eventMappings, globalVolume: 64,
                effectType: 0x14, effectParam: 2)
            XCTAssertNil(plan.pattern.events[0].keyOffFrame)
            XCTAssertFalse(plan.diagnostics.eventMappings[0].volumeEnvelopeSemantics.keyOffEncountered)
            XCTAssertEqual(plan.xmChannelRows[0].controls, controls)
            XCTAssertEqual(decision.channelVolumeAfter, 0)
            let annotation = try XCTUnwrap(decision.sourceAnnotation)
            XCTAssertTrue(annotation.zeroOnsetGain)
            XCTAssertEqual(annotation.eventIndex, 0)
            XCTAssertEqual(annotation.mappingIndex, 0)
            XCTAssertEqual(annotation.volumeUpdate?.effectiveVolumeAfter, 0)

            // Change destination envelope metadata after deciding. Projection must copy the frozen result.
            let other = PlaybackSongSyntheticAdapter.adapt(Self.song([:], envelope: true), orderIndex: 0, sampleRate: rate)
            var events = plan.pattern.events, mappings = other.diagnostics.eventMappings
            var diagnostics = [PlaybackSongSyntheticKeyOffDiagnostic]()
            var updates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
            PlaybackSongSyntheticAdapter.applyLegacyReleaseProjection(decision, events: &events,
                eventMappings: &mappings, keyOffEvents: &diagnostics, voiceStateUpdates: &updates)
            XCTAssertEqual(events[0].keyOffFrame, annotation.releaseFrame)
            XCTAssertEqual(events[0].fadeoutFrameDecrement, annotation.fadeoutFrameDecrement)
            XCTAssertEqual(events[0].gain, 0)
            XCTAssertEqual(mappings[0].volumeEnvelopeSemantics, annotation.volumeEnvelopeSemantics)
            XCTAssertEqual(diagnostics, [decision.diagnostic])
            XCTAssertEqual(updates, [try XCTUnwrap(annotation.volumeUpdate)])
        }
    }

    func testUnownedInvalidAndBeforeOnsetReleasesRemainDeferredWithoutSourceProjection() throws {
        let plan = PlaybackSongSyntheticAdapter.adapt(Self.song([:]), orderIndex: 0, sampleRate: 48_000)
        let owned = plan.xmChannelRows[0].controls
        var invalid = owned
        invalid.activeEventMappingIndex = 99
        for (state, frame, found) in [(PlaybackSongSyntheticAdapter.ChannelState(), 0, false), (invalid, 0, true), (owned, -1, true)] {
            let decision = PlaybackSongSyntheticAdapter.decideKeyOff(
                source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), channelIndex: 0,
                syntheticRow: 0, syntheticTick: 0, scheduledFrame: frame, rowSpeed: 6, rowBPM: 137,
                cell: Self.cell(note: 97), channelState: state, events: plan.pattern.events,
                eventMappings: plan.diagnostics.eventMappings, globalVolume: 64)
            XCTAssertEqual(decision.diagnostic.reason, .noActiveVoice)
            XCTAssertEqual(decision.diagnostic.activeVoiceFound, found)
            XCTAssertTrue(decision.diagnostic.deferred)
            XCTAssertFalse(decision.diagnostic.applied)
            XCTAssertNil(decision.diagnostic.releaseFrame)
            XCTAssertNil(decision.diagnostic.activeEventIndex)
            XCTAssertNil(decision.channelVolumeAfter)
            XCTAssertNil(decision.sourceAnnotation)
        }
    }

    func testRepeatedReleasesKeepFirstTriggerAndLatestMappingAndFirstDiagnostic() throws {
        for rate in rates {
            for enabled in [false, true] {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: Self.song([
                    1: Self.cell(effect: 0x14, parameter: 2), 2: Self.cell(note: 97),
                    3: Self.cell(effect: 0x14, parameter: 1)
                ], envelope: enabled), sampleRate: rate)
                let plan = try XCTUnwrap(runtime.plan)
                let releases = plan.diagnostics.keyOffEvents
                XCTAssertEqual(releases.map(\.syntheticRow), [1, 2, 3])
                XCTAssertEqual(releases.map(\.syntheticTick), [2, 0, 1])
                XCTAssertEqual(releases.map(\.activeEventIndex), [0, 0, 0])
                XCTAssertEqual(plan.pattern.events[0].keyOffFrame, releases[0].releaseFrame)
                XCTAssertEqual(plan.pattern.events[0].fadeoutFrameDecrement,
                    PlaybackSongSyntheticAdapter.fadeoutFrameDecrement(fadeoutValue: 1024, sampleRate: rate))
                let annotation = plan.diagnostics.eventMappings[0].volumeEnvelopeSemantics
                XCTAssertEqual(annotation.releaseFrame, releases[2].releaseFrame)
                XCTAssertEqual(annotation.keyOffSource, releases[2].source)
                XCTAssertEqual(annotation.keyOffSyntheticTick, 1)
                XCTAssertTrue(annotation.keyOffEncountered && annotation.keyOffApplied && annotation.fadeoutApplied)
                XCTAssertFalse(annotation.keyOffDeferred || annotation.fadeoutDeferred)
                let onset = try XCTUnwrap(runtime.events.first { $0.primaryCategory == "note_trigger" })
                XCTAssertTrue(onset.categories.contains("key_off"))
                XCTAssertTrue(onset.categories.contains("kxx_key_off"))
                XCTAssertEqual(onset.effectType, 0x14)
                XCTAssertEqual(onset.effectParam, 2)
            }
        }
    }

    func testNote97AndKxxInOneCellPreserveBothDecisionsAndNote97DiagnosticPrecedence() throws {
        for rate in rates {
            for tick: UInt8 in [0, 2] {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: Self.song([
                    1: Self.cell(note: 97, effect: 0x14, parameter: tick)
                ]), sampleRate: rate)
                let plan = try XCTUnwrap(runtime.plan), releases = plan.diagnostics.keyOffEvents
                XCTAssertEqual(releases.count, 2)
                XCTAssertEqual(releases.map(\.syntheticTick), [0, Int(tick)])
                XCTAssertEqual(releases.map(\.effectType), [nil, 0x14])
                XCTAssertEqual(plan.pattern.events[0].keyOffFrame, releases[0].releaseFrame)
                XCTAssertEqual(plan.diagnostics.eventMappings[0].volumeEnvelopeSemantics.releaseFrame, releases[1].releaseFrame)
                XCTAssertEqual(plan.diagnostics.voiceStateUpdates.map(\.effectiveVolumeAfter), [0, 0])
                let onset = try XCTUnwrap(runtime.events.first { $0.primaryCategory == "note_trigger" })
                XCTAssertTrue(onset.categories.contains("key_off"))
                XCTAssertFalse(onset.categories.contains("kxx_key_off"))
                XCTAssertNil(onset.effectType)
                XCTAssertNil(onset.effectParam)
            }
        }
    }

    func testSameCellK00ZerosOnsetAndInstrumentOnlyK00RetainsRestoredOrExplicitVolume() throws {
        for rate in rates {
            let onset = PlaybackSongSyntheticAdapter.adapt(Self.song([
                0: Self.cell(note: 49, instrument: 1, volume: 0x30, effect: 0x14)
            ]), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(onset.pattern.events[0].gain, 0)
            XCTAssertEqual(onset.pattern.events[0].keyOffFrame, 0)
            XCTAssertFalse(onset.diagnostics.voiceStateUpdates[0].activeVoiceUpdated)
            for (volume, expected): (UInt8, Int) in [(0, 48), (0x30, 32)] {
                let plan = PlaybackSongSyntheticAdapter.adapt(Self.song([
                    1: Self.cell(instrument: 1, volume: volume, effect: 0x14)
                ]), orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.pattern.events.count, 1)
                XCTAssertEqual(plan.xmChannelRows[1].controls.baseChannelVolume, expected)
                XCTAssertEqual(plan.xmChannelRows[1].controls.outputChannelVolume, expected)
                XCTAssertTrue(plan.diagnostics.keyOffEvents[0].applied)
                XCTAssertFalse(plan.diagnostics.voiceStateUpdates.contains { $0.command == .keyOffWithoutEnvelope })
            }
        }
    }

    func testSilentDeclaredRouteReleaseRetainsHeaderChannelClocksAndNilSource() throws {
        for rate in rates {
            for enabled in [false, true] {
                let plan = PlaybackSongSyntheticAdapter.adapt(Self.song([
                    0: Self.cell(note: 50, instrument: 1), 1: Self.cell(note: 97, effect: 0x14, parameter: 2)
                ], envelope: enabled, panClock: true), orderIndex: 0, sampleRate: rate)
                XCTAssertTrue(plan.pattern.events.isEmpty)
                XCTAssertTrue(plan.diagnostics.eventMappings.isEmpty)
                XCTAssertEqual(plan.diagnostics.keyOffEvents.map(\.reason), [.releasedSilentChannel, .releasedSilentChannel])
                XCTAssertTrue(plan.diagnostics.keyOffEvents.allSatisfy { $0.activeEventIndex == nil && !$0.activeVoiceFound })
                XCTAssertEqual(plan.xmChannelRows[1].controls.semanticSampleIndex, 1)
                XCTAssertEqual(plan.xmChannelRows[1].controls.triggeredSampleDefaultVolume, 40)
                XCTAssertEqual(plan.xmChannelRows[1].controls.baseChannelVolume, enabled ? 40 : 0)
                let release = try XCTUnwrap(plan.diagnostics.keyOffEvents.last?.releaseFrame)
                let state = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0, atOrBefore: release))
                XCTAssertNil(state.sourceEventIndex)
                XCTAssertEqual(state.sampleIndex, 1)
                XCTAssertFalse(state.state.keyOn)
                XCTAssertLessThan(state.state.fadeoutAccumulator, 32_768)
                XCTAssertGreaterThan(state.state.panTick, 0)
            }
        }
    }

    func testNoteOnlyAndReplacementReleasesKeepExactSourceOwnership() throws {
        for rate in rates {
            let plan = PlaybackSongSyntheticAdapter.adapt(Self.song([
                1: Self.cell(note: 97), 2: Self.cell(note: 53),
                3: Self.cell(effect: 0x14, parameter: 2), 4: Self.cell(note: 55, instrument: 1),
                5: Self.cell(note: 97)
            ], envelope: true), orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.count, 3)
            XCTAssertEqual(plan.noteOnlyEventIndices, [1])
            XCTAssertEqual(plan.diagnostics.keyOffEvents.map(\.activeEventIndex), [0, 1, 2])
            XCTAssertEqual(plan.pattern.events.map(\.keyOffFrame), plan.diagnostics.keyOffEvents.map(\.releaseFrame))
            XCTAssertEqual(plan.diagnostics.eventMappings.map { $0.volumeEnvelopeSemantics.keyOffSyntheticRow }, [1, 3, 5])
        }
    }

    func testE9InheritsLatestParentMappingAtCreationWithoutReleasingNewTriggers() throws {
        for rate in rates {
            for enabled in [false, true] {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: Self.song([
                    1: Self.cell(effect: 0x14, parameter: 1), 2: Self.cell(note: 97),
                    3: Self.cell(effect: 0x0E, parameter: 0x92), 4: Self.cell(effect: 0x14, parameter: 2)
                ], envelope: enabled), sampleRate: rate)
                let plan = try XCTUnwrap(runtime.plan)
                XCTAssertEqual(plan.pattern.events.count, 3)
                let mappings = plan.diagnostics.eventMappings
                XCTAssertEqual(mappings[1].volumeEnvelopeSemantics, mappings[0].volumeEnvelopeSemantics)
                XCTAssertEqual(mappings[1].volumeEnvelopeSemantics.keyOffSyntheticRow, 2)
                XCTAssertNil(plan.pattern.events[1].keyOffFrame)
                XCTAssertEqual(mappings[2].volumeEnvelopeSemantics.keyOffSyntheticRow, 4)
                XCTAssertEqual(plan.pattern.events[2].keyOffFrame, plan.diagnostics.keyOffEvents.last?.releaseFrame)
                let middle = try XCTUnwrap(runtime.events.first { $0.activeEventIndex == 1 && $0.primaryCategory == "note_trigger" })
                XCTAssertFalse(middle.categories.contains("key_off"))
                XCTAssertEqual(middle.effectType, 0x0E)
                XCTAssertEqual(middle.effectParam, 0x92)
            }
        }
    }

    func testLoopTemplateKeepsSuccessorRestorationAtThePredecessorBoundary() throws {
        for rate in rates {
            for continuing in [false, true] {
                let module = Self.loopSong(continuing: continuing)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate)
                let range = try XCTUnwrap(module.patternLoopRange(containing: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0)))
                let loop = try XCTUnwrap(runtime.adapterEventLoopRange(for: range))
                let restorations = loop.events.filter { event in
                    guard event.source.orderIndex == 0, event.source.rowIndex == 7,
                          event.scheduledFrame == loop.plannedEndFrame else { return false }
                    if case .stepUpdate = event.action { return true }
                    return false
                }
                XCTAssertEqual(restorations.count, continuing ? 0 : 1)
                XCTAssertTrue(loop.events.allSatisfy { $0.source.orderIndex == 0 })
                XCTAssertTrue(restorations.allSatisfy { $0.activeEventIndex == 0 })
                XCTAssertEqual(loop.events, runtime.events(in: range))
            }
        }
    }

    // Public model-built controls shared with the external old/new complete-plan oracle.
    static func loopSong(continuing: Bool) -> PlaybackSong {
        let base = song([1: cell(note: 97), 7: cell(effect: 4, parameter: 0x47)], envelope: true)
        let successor = PlaybackPattern(index: 1, rows: [.init(index: 0,
            cells: [continuing ? cell(effect: 4, parameter: 0x47) : cell()])])
        return .init(title: "Release loop boundary control",
            orders: [.init(orderIndex: 0, patternIndex: 0), .init(orderIndex: 1, patternIndex: 1)],
            patternsByIndex: [0: base.patternsByIndex[0]!, 1: successor], instrumentsByIndex: base.instrumentsByIndex,
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: base.initialTiming,
            usesLinearFrequencyTable: true, xmSampleSlotProvenanceByInstrument: base.xmSampleSlotProvenanceByInstrument)
    }

    static func controls() -> [(String, PlaybackSong)] {
        let cases: [(String, [Int: PlaybackCell])] = [
            ("first_note97", [1: cell(note: 97)]), ("first_k02", [1: cell(effect: 0x14, parameter: 2)]),
            ("repeated", [1: cell(effect: 0x14, parameter: 2), 2: cell(note: 97), 3: cell(effect: 0x14, parameter: 1)]),
            ("note97_k02", [1: cell(note: 97, effect: 0x14, parameter: 2)]),
            ("note97_k00", [1: cell(note: 97, effect: 0x14)]),
            ("empty_route", [0: cell(note: 50, instrument: 1), 1: cell(note: 97, effect: 0x14, parameter: 2)]),
            ("onset_k00", [0: cell(note: 49, instrument: 1, volume: 0x30, effect: 0x14)]),
            ("instrument_k00", [1: cell(instrument: 1, effect: 0x14)]),
            ("instrument_volume_k00", [1: cell(instrument: 1, volume: 0x30, effect: 0x14)]),
            ("note_only", [1: cell(note: 97), 2: cell(note: 53), 3: cell(effect: 0x14, parameter: 2)]),
            ("e9_inheritance", [1: cell(effect: 0x14, parameter: 1), 2: cell(note: 97), 3: cell(effect: 0x0E, parameter: 0x92), 4: cell(effect: 0x14, parameter: 2)]),
            ("replacement", [1: cell(note: 97), 2: cell(note: 55, instrument: 1), 3: cell(effect: 0x14, parameter: 2)]),
            ("cold_release", [0: cell(note: 97)]), ("out_of_row", [1: cell(effect: 0x14, parameter: 6)])
        ]
        return [false, true].flatMap { enabled in
            cases.map { ("\($0.0)_env_\(enabled)", song($0.1, envelope: enabled, panClock: true)) }
        }
    }

    static func cell(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0,
                     effect: UInt8 = 0, parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    static func song(_ cells: [Int: PlaybackCell], envelope: Bool = false, panClock: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.5, count: 64),
            volume: 0.75, relativeNote: 0, finetune: 0, baseSampleRate: 100,
            loopStart: 0, loopLength: 64, loopType: 1)
        var map = Array(repeating: 0, count: 96)
        map[49] = 1
        let volume = PlaybackVolumeEnvelope(enabled: envelope,
            points: envelope ? [.init(tick: 0, value: 48), .init(tick: 4, value: 64), .init(tick: 16, value: 24)] : [],
            sustainPointIndex: envelope ? 1 : nil, loopStartPointIndex: nil, loopEndPointIndex: nil,
            typeFlags: envelope ? 3 : 0, fadeout: 1024)
        let pan = PlaybackPanningEnvelope(enabled: panClock,
            points: panClock ? [.init(tick: 0, value: 16), .init(tick: 40, value: 48)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: panClock ? 1 : 0)
        let empty = XMSourceSampleSlotProvenance(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: false,
            volume: 40, panning: 224)
        return PlaybackSong(title: "Release characterization", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<8).map { row in
                .init(index: row, cells: [cells[row] ?? (row == 0 ? cell(note: 49, instrument: 1) : cell())])
            })], instrumentsByIndex: [1: .init(index: 1, samples: [sample],
                volumeEnvelope: volume, panningEnvelope: pan, noteSampleMap: map)], restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: 6, bpm: 137), usesLinearFrequencyTable: true,
            xmSampleSlotProvenanceByInstrument: [1: [empty]])
    }
}
