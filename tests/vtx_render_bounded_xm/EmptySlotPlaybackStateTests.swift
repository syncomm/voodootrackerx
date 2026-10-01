import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class EmptySlotPlaybackStateTests: XCTestCase {
    func testDeclaredEmptyHeadersRetainPlaybackFieldsWithoutSamplesOrRoutingFallback() throws {
        let song = try fixture(), instrument = try XCTUnwrap(song.instrumentsByIndex[1])
        let slots = try XCTUnwrap(song.xmSampleSlotProvenanceByInstrument[1])
        XCTAssertEqual(slots.map(\.sampleIndex), Array(0...6))
        XCTAssertEqual(instrument.samples.map(\.sampleIndex), [0])
        XCTAssertEqual(slots.dropFirst().map(\.declaredPayloadLength), Array(repeating: 0, count: 6))
        XCTAssertEqual(slots.dropFirst().map(\.decodedPayloadLength), Array(repeating: 0, count: 6))
        XCTAssertEqual(slots.dropFirst().map(\.isCanonicalEmptySlotHeader), [true, false, false, false, false, false])
        XCTAssertEqual(slots.dropFirst().map(\.volume), [0, 40, 0, 0, 0, 40])
        XCTAssertEqual(slots.dropFirst().map(\.panning), [0, 0, 224, 0, 0, 224])
        XCTAssertEqual(slots.dropFirst().map(\.finetune), [0, 0, 0, 64, 0, 64])
        XCTAssertEqual(slots.dropFirst().map(\.relativeNote), [0, 0, 0, 0, 12, 12])
        XCTAssertEqual(instrument.noteSampleMap?.count, 96)
        XCTAssertEqual(Array(try XCTUnwrap(instrument.noteSampleMap)[48...53]), [2, 1, 3, 4, 5, 6])
        for note: UInt8 in 49...54 {
            XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(instrumentIndex: 1, note: note, instrument: instrument))
        }
    }

    func testEmptyDefaultsSameCellOverridesSilentResetAndExplicitRefresh() throws {
        let plan = PlaybackSongSyntheticAdapter.adapt(try fixture(), orderIndex: 0, sampleRate: 48_000)
        let rows = plan.xmChannelRows.filter { $0.channelIndex == 0 }.map(\.controls)
        for row in [2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15] {
            XCTAssertNil(rows[row].activeEventIndex)
            XCTAssertNil(rows[row].activeSampleVolume)
            XCTAssertEqual(rows[row].semanticInstrumentIndex, 1)
        }
        XCTAssertEqual(rows[2].triggeredSampleDefaultVolume, 40)
        XCTAssertEqual(rows[4].baseChannelVolume, 40)
        XCTAssertEqual(rows[4].outputChannelVolume, 40)
        XCTAssertEqual(rows[4].triggeredSampleDefaultPan, 0)
        XCTAssertEqual(rows[7].baseChannelVolume, 32)
        XCTAssertEqual(rows[7].panningValue, 224)
        XCTAssertEqual(rows[7].triggeredSampleDefaultVolume, 40)
        for row in [8, 16] {
            XCTAssertEqual(rows[row].baseChannelVolume, 48)
            XCTAssertEqual(rows[row].triggeredSampleDefaultVolume, 48)
            XCTAssertEqual(rows[row].panningValue, 32)
            XCTAssertEqual(rows[row].semanticSampleIndex, 0)
        }
        XCTAssertEqual(rows[10].triggeredSampleDefaultPan, 224)
        XCTAssertEqual(rows[11].activeLinearPeriod, 4384) // D#4 with finetune +64.
        XCTAssertEqual(rows[12].activeLinearPeriod, 3584) // E5 from relative note +12.
        XCTAssertEqual(rows[13].activeLinearPeriod, 3488) // F5 with finetune +64.
        XCTAssertEqual(rows[14].tonePortamentoTargetLinearPeriod, 3360)
        XCTAssertEqual(rows[15].tonePortamentoSpeed, 4)
        XCTAssertEqual(rows[15].tonePortamentoTargetLinearPeriod, 3360)
        XCTAssertTrue(plan.playbackStateEvents.allSatisfy { $0.channelIndex != 0 })
        XCTAssertEqual(plan.diagnostics.eventMappings.filter { $0.channelIndex == 0 }.map(\.source.rowIndex), [0, 8, 16])
    }

    func testSilentClocksReleaseFadeoutAndFxxUseOneTimelineAndNoAudibleUpdates() throws {
        let module = try fixture()
        let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
        let timeline = try XCTUnwrap(plan.xmEnvelopeTimeline)
        func state(_ frame: Int) throws -> MixerEnvelopeSemanticState {
            try XCTUnwrap(timeline.channelState(channelIndex: 0, atOrBefore: frame)).state
        }
        XCTAssertEqual(try state(11_520).volumeTick, 0)
        XCTAssertEqual(try state(11_520).volumeValue, 0.5)
        XCTAssertEqual(try state(17_280).volumeTick, 6)
        XCTAssertFalse(try state(17_280).keyOn)
        XCTAssertEqual(try state(17_280).fadeoutAccumulator, 32_256)
        XCTAssertEqual(try state(23_040), .init(volumeValue: 0.5))
        XCTAssertEqual(try state(28_800).volumeTick, 6)
        XCTAssertEqual(try state(29_280).volumeTick, 7)
        XCTAssertEqual(try state(32_160).fadeoutAccumulator, 32_256)
        XCTAssertEqual(try state(34_560), .init(volumeValue: 0.5))
        XCTAssertEqual(try state(37_439).volumeTick, 5)
        XCTAssertEqual(try state(37_440), .init(volumeValue: 0.5))
        let silent = timeline.channelUpdates.filter { $0.channelIndex == 0 && (11_520..<37_440).contains($0.scheduledFrame) }
        XCTAssertTrue(silent.allSatisfy { $0.sourceEventIndex == nil && $0.instrumentIndex == 1 && $0.sampleIndex == 2 })
        XCTAssertEqual(silent.first?.source, .init(orderIndex: 0, patternIndex: 0, rowIndex: 2))
        XCTAssertEqual(silent.first?.tick, 0)
        XCTAssertTrue(silent.allSatisfy { $0.carriedInstrumentIndex == 1 && $0.cachedDefaultVolume == 40 && $0.cachedDefaultPan == 0 })
        XCTAssertEqual(Array(silent.prefix(5)).map(\.state.panTick), [0, 1, 2, 3, 0])
        XCTAssertFalse(timeline.updates.contains { $0.channelIndex == 0 && (11_520..<37_440).contains($0.scheduledFrame) })
        XCTAssertFalse(plan.xmAudibleTimeline!.updates.contains { $0.channelIndex == 0 && (11_520..<37_440).contains($0.scheduledFrame) })
        let runtime = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: 48_000)
        XCTAssertEqual(runtime.plan, plan)
        let runtimeSilent = runtime.events.compactMap { event -> PlaybackXMChannelUpdate? in
            if case let .channelSemanticUpdate(update) = event.action { return update }; return nil
        }
        XCTAssertEqual(runtimeSilent, timeline.channelUpdates)
    }

    func testWindowParityAndSourceRetirementWithoutHiddenVoice() throws {
        let module = try fixture(), renderer = PlaybackSongOfflineRenderer()
        for rate in [44_100.0, 48_000] {
            let config = MixerRenderConfig(sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 24)
            let full = renderer.render(request)
            for window in [1, 2, 3, 5, 7] {
                let result = renderer.renderWindowed(request, windowRows: window)
                XCTAssertEqual(result.plan.xmEnvelopeTimeline?.channelUpdates, full.plan.xmEnvelopeTimeline?.channelUpdates)
                XCTAssertLessThan(zip(result.block.interleavedPCM, full.block.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
            }
            let index = renderer.makeWindowedRenderScheduleIndex(for: full.plan, totalFrames: full.block.frameCount,
                windowRows: 1, includedEventIndices: nil, config: config)
            for row in [3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15] {
                XCTAssertFalse(index.windows[row].continuations.contains { [0, 3].contains($0.eventIndex) })
            }
            let mixer = CSoftwareMixer(config: config)
            let event = full.plan.pattern.events[0]
            let voice = mixer.addVoice(sample: event.sample, playbackStep: event.playbackStep, loop: event.loop)
            PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(full.plan, voiceIndexByEventIndex: [0: voice], on: mixer)
            let emptyFrame = full.plan.xmEmptyRoutes.first { $0.channelIndex == 0 }!.scheduledFrame
            _ = mixer.render(frames: emptyFrame + 1)
            XCTAssertEqual(mixer.activeVoiceCount, 0)
            XCTAssertEqual(mixer.loadedVoiceCount, 0)
            XCTAssertTrue(mixer.render(frames: 1000).interleavedPCM.allSatisfy { $0 == 0 })
            XCTAssertFalse(mixer.setEnvelopeSemanticState(.init(), forVoiceAt: voice))
        }
    }

    func testStaleResetCannotTargetAnEmptyRouteAndNormalNoteOnlyStaysDeferred() throws {
        let source = try fixture()
        var rows = source.patternsByIndex[0]!.rows
        rows[6] = .init(index: 6, cells: [.init(note: 37, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0), rows[6].cells[1]])
        let module = PlaybackSong(title: source.title, orders: source.orders, patternsByIndex: [0: .init(index: 0, rows: rows)],
            instrumentsByIndex: source.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: source.initialTiming, xmSampleSlotProvenanceByInstrument: source.xmSampleSlotProvenanceByInstrument)
        var plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
        plan.playbackStateEvents.append(.init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 31_680,
            change: .reset(.init(volumeEnvelope: true, panEnvelope: true, keyOn: true, fadeout: true))))
        XCTAssertFalse(PlaybackSongOfflineRenderer.carriedPlaybackStateEvents(for: plan).contains { $0.activeEventIndex == 0 })
        XCTAssertFalse(plan.diagnostics.eventMappings.contains { $0.channelIndex == 0 && $0.source.rowIndex == 6 })
        XCTAssertEqual(plan.xmChannelRows.first { $0.channelIndex == 0 && $0.syntheticRow == 6 }?.controls.baseChannelVolume, 40)
        XCTAssertEqual(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0, atOrBefore: 31_680)?.state.volumeTick, 12)
    }

    func testSilentSpeedChangeSameCellWritersAndFinetuneOverride() throws {
        let source = try fixture()
        var rows = source.patternsByIndex[0]!.rows
        rows[2] = .init(index: 2, cells: [.init(note: 49, instrument: 1, volumeColumn: 0x30, effectType: 8, effectParam: 224), rows[2].cells[1]])
        rows[5] = .init(index: 5, cells: [.init(note: 0, instrument: 0, volumeColumn: 0, effectType: 15, effectParam: 3), rows[5].cells[1]])
        rows[13] = .init(index: 13, cells: [.init(note: 54, instrument: 1, volumeColumn: 0, effectType: 14, effectParam: 0x53), rows[13].cells[1]])
        let module = PlaybackSong(title: source.title, orders: source.orders, patternsByIndex: [0: .init(index: 0, rows: rows)],
            instrumentsByIndex: source.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: source.initialTiming, xmSampleSlotProvenanceByInstrument: source.xmSampleSlotProvenanceByInstrument)
        let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
        let controls = plan.xmChannelRows.filter { $0.channelIndex == 0 }.map(\.controls)
        XCTAssertEqual(controls[2].baseChannelVolume, 32)
        XCTAssertEqual(controls[2].panningValue, 224)
        XCTAssertEqual(controls[2].triggeredSampleDefaultVolume, 40)
        XCTAssertEqual(controls[4].baseChannelVolume, 40)
        XCTAssertEqual(controls[4].panningValue, 0)
        XCTAssertEqual(controls[13].activeSampleFinetune, -80)
        XCTAssertEqual(controls[13].activeLinearPeriod, 3560)
        let timeline = try XCTUnwrap(plan.xmEnvelopeTimeline)
        let speedRow = timeline.channelUpdates.filter { $0.channelIndex == 0 && $0.source.rowIndex == 5 }
        XCTAssertEqual(speedRow.map(\.scheduledFrame), [28_800, 29_760, 30_720])
        XCTAssertEqual(speedRow.map(\.state.volumeTick), [6, 7, 8])
        XCTAssertEqual(timeline.channelState(channelIndex: 0, atOrBefore: 31_680)?.state.volumeTick, 9)
        XCTAssertEqual(timeline.channelState(channelIndex: 0, atOrBefore: 32_640)?.state.fadeoutAccumulator, 32_256)
    }

    func testSilentResetSharesInstrumentOnlyK00AndDelayPrecedence() throws {
        let source = try fixture()
        for (volume, effect, parameter, resets): (UInt8, UInt8, UInt8, Bool) in [
            (0, 0, 0, true), (0, 0x14, 0, false), (0xF0, 0x14, 0, true),
            (0, 0x0E, 0xD0, true), (0, 0x0E, 0xD1, false),
        ] {
            var rows = source.patternsByIndex[0]!.rows
            rows[4] = .init(index: 4, cells: [.init(note: 0, instrument: 1,
                volumeColumn: volume, effectType: effect, effectParam: parameter), rows[4].cells[1]])
            let module = PlaybackSong(title: source.title, orders: source.orders,
                patternsByIndex: [0: .init(index: 0, rows: rows)], instrumentsByIndex: source.instrumentsByIndex,
                restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: source.initialTiming,
                xmSampleSlotProvenanceByInstrument: source.xmSampleSlotProvenanceByInstrument)
            let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: 48_000)
            let state = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0, atOrBefore: 23_040))
            XCTAssertEqual(state.state.volumeTick, resets ? 0 : 12)
            XCTAssertEqual(state.state.keyOn, resets)
            XCTAssertNil(state.sourceEventIndex)
            XCTAssertFalse(plan.playbackStateEvents.contains { $0.channelIndex == 0 })
        }
    }

    func testStoppingSourceRemovesQueuedResetsBeforePhysicalSlotReuse() throws {
        let mixer = CSoftwareMixer(config: .init(sampleRate: 48_000, channelCount: 1))
        let voice = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 0.25, count: 256)))
        XCTAssertTrue(mixer.schedulePlaybackStateChange(.keyOff(fadeoutDecrement: 0.25),
            voiceIndex: voice, scheduledFrame: 10).wasAccepted)
        XCTAssertTrue(mixer.stopVoice(at: voice))
        XCTAssertEqual(mixer.activeVoiceCount, 0)
        let replacement = mixer.addVoice(sample: .init(monoPCM: Array(repeating: 0.25, count: 256)))
        _ = mixer.render(frames: 20)
        XCTAssertTrue(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: replacement)).keyOn)
        XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: replacement)?.fadeoutValue, 1)
    }

    private func fixture() throws -> PlaybackSong {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/empty-slot-playback-state.xm")
        return try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
    }
}
