import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class ExtremePitchStateTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]

    private func append(_ value: Int, bytes: Int = 2, to hash: inout UInt64) {
        for shift in stride(from: 0, to: bytes * 8, by: 8) {
            hash = (hash ^ UInt64((value >> shift) & 255)) &* 1099511628211
        }
    }

    func testExhaustiveAdmissionAndOrdinaryAmigaLookupReferenceFingerprints() throws {
        // Independently observed pinned FT2 outcomes, raw-note-major/relative-minor.
        var admission: UInt64 = 14695981039346656037
        for note in 1...96 { for relative in -128...127 {
            let outcome = A.ordinaryPitchAdmission(note: UInt8(note), relativeNote: relative)
            let value: Int
            switch outcome { case .refused: value = 0; case .retained: value = 1; case .lookup: value = 2 }
            append(value, bytes: 1, to: &admission)
        } }
        XCTAssertEqual(admission, 0x11129a8eb47715c5)
        var lookup: UInt64 = 14695981039346656037
        var periods = [Int]()
        for note in 1...119 { for fine in -128...127 {
            let p = try XCTUnwrap(A.amigaPitchTarget(note: UInt8(note), relativeNote: 0,
                finetune: fine, baseSampleRate: 8363, outputSampleRate: 48000)).amigaPeriod
            XCTAssertEqual(p.truncatingRemainder(dividingBy: 4), 0)
            periods.append(Int(p))
            append(Int(p / 4), to: &lookup)
        } }
        XCTAssertEqual(lookup, 0x6ee80d5003be78e5)
        XCTAssertEqual(periods.min(), 88)
        XCTAssertEqual(periods.max(), 116096)
    }

    func testFullUInt16SlideFingerprintsPreserveDistinctSignedPolicies() {
        // Native UInt16 byte fingerprints from unchanged reference tick dispatch.
        let vectors: [(Int, UInt64)] = [(-4,0x16d6b87efe00aca4),(-60,0xad0d520c8d69e1a4),
            (-1020,0x1d30ad2e14d4e9a4),(4,0x0d62b357f715fe25),(60,0x1dcfe3deeccc7c25),
            (1020,0x436e3ef6cb8dc625),(-1,0x845169c2c67db83c),(-15,0x5729f6a18eb6b5fc),
            (1,0xd5a0aec02e31c825),(15,0xb22a3da964602e25)]
        for linear in [true,false] { for (delta, expected) in vectors {
            var hash: UInt64 = 14695981039346656037
            for period in 0...65535 {
                let scale = linear ? 1.0 : 4
                append(Int(A.pitchSlidePeriod(Double(period) * scale, nativeDelta: delta,linear: linear) / scale), to: &hash)
            }
            XCTAssertEqual(hash, expected, "native delta \(delta)")
        } }
    }

    func testExhaustiveToneIndexAdmissionAndLookupPreservePriorTargetOnRefusal() {
        // Reference tick-zero admission with current native39139, prior target1700,
        // direction1, speed0; note/relative/tuning-group order. This independently
        // distinguishes the tone index boundary from ordinary UInt8 admission.
        for (linear,expected): (Bool,UInt64) in [(false,0x318a63c20e73de25),(true,0xaae8be13bcfc6f25)] {
            var hash: UInt64 = 14695981039346656037
            for note in 1...96 { for relative in -128...127 { for fine in stride(from: -128,through: 120,by: 8) {
                let target = A.toneTargetPeriod(note: UInt8(note),relativeNote: relative,finetune: fine,linear: linear)
                append(target.map { Int($0 / (linear ? 1 : 4)) } ?? 1700,to: &hash)
                append(target == nil ? 1 : 2,bytes: 1,to: &hash)
            } } }
            XCTAssertEqual(hash,expected)
        }
        XCTAssertEqual(A.ordinaryPitchAdmission(note: 96,relativeNote: 24),.refused)
        XCTAssertEqual(A.toneTargetPeriod(note: 96,relativeNote: 24,finetune: 127,linear: false),0)
        XCTAssertEqual(A.toneTargetPeriod(note: 96,relativeNote: 24,finetune: 127,linear: true),4)
        XCTAssertEqual(A.toneTargetPeriod(note: 1,relativeNote: -1,finetune: 0,linear: false),116096)
        for linear in [true,false] {
            let rows = [[c(49,1)],[c(55,fx: 3,param: 4)],[c(1,2)],[c(1,fx: 3)]]
            let (context,states) = inspect(song(rows,linear: linear),48000)
            XCTAssertEqual(context.events.count,1)
            XCTAssertEqual(states[3].tonePortamentoTargetNote,55)
            XCTAssertEqual(states[3].tonePortamentoTargetLinearPeriod,states[1].tonePortamentoTargetLinearPeriod)
            XCTAssertEqual(states[3].tonePortamentoTargetAmigaPeriod,states[1].tonePortamentoTargetAmigaPeriod)
            XCTAssertEqual(states[3].tonePortamentoSpeed,4)
            XCTAssertEqual(context.tonePortamentoEffects.last?.stepUpdates.count,2)
        }
    }

    func testInverseArpeggioProjectionIncludingZeroNibbleMatchesReference() throws {
        // Note-major within each signed tuning group, then offsets 0...15.
        // Zero-nibble X/Y projection is distinct from G25's unprojected base phase.
        for (linear, expected): (Bool, UInt64) in [(false,0x2a17b94ee1f3f01f),(true,0x004b064699a31735)] {
            var hash: UInt64 = 14695981039346656037
            for fine in stride(from: -128, through: 120, by: 8) { for note in 1...119 {
                let base = linear ? Double(A.quantizedLinearPeriod(effectiveNote: note, finetune: fine))
                    : A.amigaPeriodFromLookup(effectiveNoteValue: note, finetune: fine)
                for offset in 0...15 {
                    let projected = A.arpeggioPeriod(base, finetune: fine, offset: offset, linear: linear)
                    append(Int(projected / (linear ? 1 : 4)), to: &hash)
                }
            } }
            XCTAssertEqual(hash, expected)
        }
        XCTAssertEqual(A.arpeggioPeriod(1600, finetune: 0, offset: 3, linear: true),1540)
        XCTAssertEqual(A.arpeggioPeriod(452, finetune: 0, offset: 7, linear: false),428)
    }

    func testActualRelativeBoundariesAndFinetunesAdmitRetainOrRefuse() throws {
        let controls = [(1,-4,0),(1,-3,0),(1,-2,0),(1,-1,1),(1,0,2),(1,1,2),(1,2,2),(1,3,2),(1,4,2),
            (96,17,2),(96,18,2),(96,19,2),(96,20,2),(96,21,2),(96,22,2),(96,23,2),
            (96,24,0),(96,25,0),(96,26,0),(1,-128,0),(96,127,0)]
        for linear in [true,false] { for rate in rates { for (note, relative, outcome) in controls {
            for fine in [-128,-127,126,127] {
                let module = song([[c(49,1)],[c(UInt8(note),2)]], linear: linear, relative: relative, fine: fine)
                let (context, states) = inspect(module,rate)
                XCTAssertEqual(context.events.count,outcome == 0 ? 1 : 2)
                XCTAssertEqual(states[1].activeEventIndex,outcome == 0 ? 0 : 1)
                if outcome < 2 { XCTAssertEqual(period(states[1]),period(states[0])) }
                if outcome == 1 {
                    XCTAssertEqual(context.eventMappings[1].effectiveNoteValue,0)
                    XCTAssertEqual(context.events[1].initialSourceFrame,0)
                    XCTAssertEqual(states[1].triggeredSampleDefaultVolume,48)
                    XCTAssertEqual(states[1].activeSampleFinetune,fine)
                } else if outcome == 0 {
                    XCTAssertEqual(states[1].triggeredSampleDefaultVolume,24)
                    XCTAssertEqual(states[1].activeInstrumentIndex,1)
                    XCTAssertEqual(states[1].activeSampleIndex,0)
                    XCTAssertEqual(states[1].semanticInstrumentIndex,2)
                    XCTAssertEqual(states[1].activeSampleFinetune,0)
                    XCTAssertTrue(context.ignoredCells.contains { $0.reason == .effectiveNoteRefused })
                }
            }
        } } }
        for linear in [true,false] { for rate in rates {
            let mapped = song([[c(49,1)],[c(50,fx: 3,param: 1)],[c(1,1,14,0x5f)]],
                linear: linear,mappedRelative: -1)
            let (same,states) = inspect(mapped,rate)
            XCTAssertEqual(same.events.count,2)
            XCTAssertEqual(same.eventMappings[1].sampleIndex,1)
            XCTAssertEqual(same.eventMappings[1].effectiveNoteValue,0)
            XCTAssertEqual(period(states[2]),period(states[1]))
            XCTAssertEqual(states[2].activeSampleFinetune,112)
            XCTAssertEqual(states[2].tonePortamentoTargetNote,states[1].tonePortamentoTargetNote)
            XCTAssertEqual(states[2].tonePortamentoDirection,states[1].tonePortamentoDirection)
            XCTAssertEqual(states[2].tonePortamentoSpeed,states[1].tonePortamentoSpeed)
            let noteOnly = song([[c(50,2)],[c(fx: 12,param: 16)],[c(97)],[c(1)]],linear: linear,relative: -1)
            let (carried,carriedStates) = inspect(noteOnly,rate)
            XCTAssertEqual(carried.events.count,2)
            XCTAssertEqual(carried.events[1].gain,0.25)
            XCTAssertEqual(period(carriedStates[3]),period(carriedStates[0]))
            let carriedPlan = A.adapt(noteOnly,orderIndex: 0,sampleRate: rate)
            XCTAssertTrue(carriedPlan.noteOnlyEventIndices.contains(1))
            XCTAssertFalse(try XCTUnwrap(carriedPlan.xmEnvelopeTimeline?.updatesByEvent[1]?.first).state.keyOn)
            for completed in [true,false] {
                let module = song([[c(49,1)],[c(97)],[c(1,2)]],linear: linear,relative: -1,completed: completed)
                let (context,owners) = inspect(module,rate)
                XCTAssertEqual(context.events.count,2)
                XCTAssertEqual(period(owners[2]),period(owners[0]))
                XCTAssertEqual(owners[2].activeInstrumentIndex,2)
                XCTAssertEqual(owners[2].triggeredSampleDefaultVolume,48)
                let plan = A.adapt(module,orderIndex: 0,sampleRate: rate)
                let reset = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first)
                XCTAssertTrue(reset.state.keyOn)
                XCTAssertEqual(reset.state.volumeTick,0)
                XCTAssertEqual(reset.state.fadeoutAccumulator,32768)
            }
        } }
    }

    func testRefusedSourceAndIndependentResetDefaultOwnershipAndWriterOrder() throws {
        let controls: [(PlaybackCell, Bool, Int, Double)] = [
            (c(1,1),true,24,96),(c(1,2),true,24,96),(c(1),false,16,80),
            (c(1,2,14,0x5f),true,24,96),(c(1,2,volume: 0x30),true,32,96),
            (c(1,2,8,48),true,24,48)]
        for linear in [true,false] { for rate in rates { for (refused,reset,volume,pan) in controls {
            let prefix = [[c(49,1)],[c(50,fx: 3,param: 1)],[c(fx: 12,param: 16)],
                [c(fx: 8,param: 80)],[c(97)]]
            let module = song(prefix+[[refused],[c(97)]],linear: linear)
            let (context,states) = inspect(module,rate)
            let before = states[4],after = states[5]
            XCTAssertEqual(context.events.count,1)
            XCTAssertEqual(after.activeEventIndex,0)
            XCTAssertEqual(after.activeInstrumentIndex,1)
            XCTAssertEqual(after.activeSampleIndex,0)
            XCTAssertEqual(period(after),period(before))
            XCTAssertEqual(after.activePlaybackStep,before.activePlaybackStep)
            XCTAssertEqual(after.tonePortamentoTargetNote,before.tonePortamentoTargetNote)
            XCTAssertEqual(after.tonePortamentoDirection,before.tonePortamentoDirection)
            XCTAssertEqual(after.tonePortamentoSpeed,before.tonePortamentoSpeed)
            XCTAssertEqual(after.triggeredSampleDefaultVolume,24)
            XCTAssertEqual(after.triggeredSampleDefaultPan,96)
            XCTAssertEqual(after.activeSampleFinetune,0) // Both header and E5 are rejected.
            XCTAssertEqual(after.baseChannelVolume,volume)
            XCTAssertEqual(after.outputChannelVolume,volume)
            XCTAssertEqual(after.panningValue,pan)
            let plan = A.adapt(module,orderIndex: 0,sampleRate: rate)
            let frame = 15*Int(rate/50)
            let state = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0,atOrBefore: frame))
            XCTAssertEqual(state.sourceEventIndex,0)
            XCTAssertEqual(state.state.keyOn,reset)
            if reset {
                XCTAssertEqual(state.state.volumeTick,0)
                XCTAssertEqual(state.state.panTick,0)
                XCTAssertEqual(state.state.fadeoutAccumulator,32768)
                XCTAssertEqual(state.state.volumeValue,refused.instrument == 2 ? 0.75 : 1)
                XCTAssertEqual(state.state.panValue,refused.instrument == 2 ? 0.25 : 0.5)
                let released = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0,atOrBefore: frame+3*Int(rate/50)))
                XCTAssertEqual(released.state.fadeoutAccumulator,32768-(refused.instrument == 2 ? 2048 : 512))
            } else {
                XCTAssertGreaterThan(state.state.volumeTick,0)
                XCTAssertLessThan(state.state.fadeoutAccumulator,32768)
            }
        } } }
    }

    func testDelayedRefusalResetsAtDispatchWithoutPrematureWritersOrSource() throws {
        for linear in [true,false] { for rate in rates { for instrument: UInt8 in [0,1,2] {
            let rows = [[c(49,1)],[c(fx: 12,param: 16)],[c(fx: 8,param: 80)],[c(97)],
                [c(1,instrument,14,0xd1,volume: 0x30)],[c()]]
            let module = song(rows,linear: linear)
            let (context,states) = inspect(module,rate)
            XCTAssertEqual(context.events.count,1)
            XCTAssertEqual(states[4].activeEventIndex,0)
            XCTAssertEqual(period(states[4]),period(states[3]))
            XCTAssertEqual(states[4].baseChannelVolume,32)
            XCTAssertEqual(states[4].panningValue,instrument == 0 ? 80 : 96)
            let delay = try XCTUnwrap(context.noteDelayEffects.first)
            XCTAssertEqual(delay.status,.sourceRefused)
            XCTAssertNil(delay.eventIndex)
            let plan = A.adapt(module,orderIndex: 0,sampleRate: rate),unit = Int(rate/50)
            let before = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0,atOrBefore: 12*unit))
            let reset = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0,atOrBefore: 13*unit))
            XCTAssertFalse(before.state.keyOn)
            XCTAssertTrue(reset.state.keyOn)
            XCTAssertEqual(reset.state.volumeTick,0)
            XCTAssertEqual(reset.state.panTick,0)
            XCTAssertEqual(reset.state.fadeoutAccumulator,32768)
            XCTAssertEqual(reset.sourceEventIndex,0)
            XCTAssertEqual(context.playbackStateEvents.filter { $0.scheduledFrame == 13*unit }.count,1)
            XCTAssertFalse(context.voiceStateUpdates.contains { $0.source.rowIndex == 4 && $0.scheduledFrame < 13*unit })
        } } }
    }

    func testRefusalOnCompletedEmptyAndColdOwnersNeverCreatesPCM() throws {
        for ownership in [0,1,2] { // completed source, declared empty header, cold explicit owner
            let rows = ownership == 2 ? [[c(1,2)],[c()]] : [[c(49,1)],[c(97)],[c(1,2)],[c()]]
            let module = song(rows,linear: false,completed: ownership == 0,empty: ownership == 1)
            let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: 48000),rows: rows.count)
            let renderer = PlaybackSongOfflineRenderer(),whole = renderer.render(request)
            XCTAssertEqual(whole.plan.pattern.events.count,ownership == 0 ? 1 : 0)
            XCTAssertTrue(whole.block.interleavedPCM[(5760*2)...].allSatisfy { $0 == 0 })
            let frame = (ownership == 2 ? 0 : 6)*960
            let semantic = try XCTUnwrap(whole.plan.xmEnvelopeTimeline?.channelState(channelIndex: 0,atOrBefore: frame))
            XCTAssertTrue(semantic.state.keyOn)
            XCTAssertEqual(semantic.state.volumeTick,0)
            XCTAssertEqual(semantic.state.fadeoutAccumulator,32768)
            XCTAssertEqual(semantic.instrumentIndex,2)
            XCTAssertEqual(renderer.renderWindowed(request,windowRows: 1).block.interleavedPCM,whole.block.interleavedPCM)
        }
        let unowned = inspect(song([[c(1)]],linear: false),48000)
        XCTAssertTrue(unowned.0.events.isEmpty)
        XCTAssertTrue(unowned.0.xmInstrumentSelections.isEmpty)
    }

    func testDelayedEffectiveZeroStartsAtRetainedPitchWithNewDefaultsOnlyAtDispatch() throws {
        for linear in [true,false] { for rate in rates {
            let module = song([[c(49,1)],[c(97)],[c(1,2,14,0xd1)],[c()]],linear: linear,relative: -1)
            let (context,states) = inspect(module,rate)
            XCTAssertEqual(context.events.count,2)
            XCTAssertEqual(context.events[1].scheduledStartFrame,7*Int(rate/50))
            XCTAssertEqual(context.events[1].initialSourceFrame,0)
            XCTAssertEqual(context.events[1].gain,0.75)
            XCTAssertEqual(period(states[2]),period(states[0]))
            XCTAssertEqual(states[2].triggeredSampleDefaultVolume,48)
            XCTAssertEqual(states[2].triggeredSampleDefaultPan,192)
            let plan = A.adapt(module,orderIndex: 0,sampleRate: rate),unit = Int(rate/50)
            let before = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0,atOrBefore: 6*unit))
            let after = try XCTUnwrap(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0,atOrBefore: 7*unit))
            XCTAssertEqual(before.sourceEventIndex,0)
            XCTAssertFalse(before.state.keyOn)
            XCTAssertEqual(after.sourceEventIndex,1)
            XCTAssertTrue(after.state.keyOn)
            XCTAssertEqual(after.state.volumeTick,0)
            XCTAssertEqual(after.state.panTick,0)
            XCTAssertEqual(after.cachedDefaultVolume,48)
            XCTAssertEqual(after.cachedDefaultPan,192)
            XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?.last?.channelPanningValue,96)
            XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.channelPanningValue,192)
        } }
    }

    func testColdEffectiveZeroHoldsBeforeFirstSampleAndAcrossWindows() throws {
        for linear in [true,false] { for rate in rates {
            let module = song([[c(1,2)],[c()],[c(49,1)]],linear: linear,relative: -1)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module,sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan)
            XCTAssertEqual(plan.initialHeldPitchEventIndices,[0])
            XCTAssertEqual(plan.diagnostics.eventMappings[0].playbackStep,0)
            let events = runtime.eventStorage.ordering.map { runtime.events[$0.eventIndex] }
            let trigger = try XCTUnwrap(events.firstIndex { if case .noteTrigger = $0.action { return true }; return false })
            let hold = try XCTUnwrap(events.firstIndex { $0.categories.contains("initial_pitch_hold") })
            XCTAssertGreaterThan(hold,trigger)
            XCTAssertEqual(events[hold].scheduledFrame,0)
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate))
            let voices = SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern,on: mixer)
            let voice = try XCTUnwrap(voices[0])
            PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(plan,voiceIndexByEventIndex: [0:voice],on: mixer)
            _ = mixer.render(frames: Int(rate/50)*3)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition,0)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.sampleStep,0)
            XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.active,true)
            let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: rate),rows: 3)
            let renderer = PlaybackSongOfflineRenderer(),whole = renderer.render(request)
            let index = renderer.makeWindowedRenderScheduleIndex(for: plan,totalFrames: whole.block.frameCount,
                windowRows: 1,includedEventIndices: nil)
            let carry = try XCTUnwrap(index.windows[1].continuations.first)
            XCTAssertEqual(carry.playbackStep,0)
            XCTAssertEqual(carry.runtimeState.samplePosition,0)
            XCTAssertEqual(renderer.renderWindowed(request,windowRows: 1).block.interleavedPCM,whole.block.interleavedPCM)
        } }
    }

    func testED0RefusalReportsDispatchWithoutAReplacementSource() {
        for linear in [true,false] {
            let (context,states) = inspect(song([[c(49,1)],[c(97)],[c(1,2,14,0xd0)]],linear: linear),48000)
            XCTAssertEqual(context.events.count,1)
            XCTAssertEqual(period(states[2]),period(states[0]))
            XCTAssertEqual(context.noteDelayEffects.last?.status,.sourceRefused)
            XCTAssertEqual(context.noteDelayEffects.last?.delayedFrame,5760)
            XCTAssertEqual(context.playbackStateEvents.last?.scheduledFrame,5760)
        }
    }

    func testConsecutiveRefusedResetPublishesCachedDefaultsAfterAnExplicitWriter() throws {
        for linear in [true,false] { for rate in rates {
            let module = song([[c(49,1)],[c(1,2,volume: 0x30)],[c(1,2)]],linear: linear)
            let plan = A.adapt(module,orderIndex: 0,sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.count,1)
            let reset = try XCTUnwrap(plan.diagnostics.voiceStateUpdates.last { $0.source.rowIndex == 2 })
            XCTAssertTrue(reset.activeVoiceUpdated)
            XCTAssertEqual(reset.activeEventIndex,0)
            XCTAssertEqual(reset.gainBefore,0.5)
            XCTAssertEqual(reset.gainAfter,0.375)
            let target = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0]?.first {
                $0.scheduledFrame == 6*Int(rate/50)
            })
            XCTAssertEqual(target.intent,"nonretriggering_reset")
            XCTAssertEqual(target.amplitude,0.375*0.75)
        } }
    }

    func testEffectiveZeroDeclaredEmptyHeaderRetainsPitchWithoutPCM() {
        for linear in [true,false] {
            let module = song([[c(50,2)],[c(49,1)]],linear: linear,relative: -1,
                empty: true,emptyRelative: -49)
            let (context,states) = inspect(module,48000)
            XCTAssertEqual(context.events.count,1)
            XCTAssertEqual(period(states[1]),period(states[0]))
            XCTAssertNil(states[1].activeEventIndex)
            XCTAssertEqual(states[1].triggeredSampleDefaultVolume,24)
            XCTAssertEqual(states[1].semanticInstrumentIndex,1)
        }
    }

    func testPublicExtremeFixturesWholeWindowAndRuntimePlanBoundaries() throws {
        for linear in [true,false] { for rate in rates {
            let name = "extreme-pitch-state-\(linear ? "linear" : "amiga").xm"
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("reference-xm/generated/"+name)
            let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module,sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan)
            XCTAssertFalse(plan.diagnostics.eventMappings.contains { $0.channelIndex == 18 || $0.channelIndex == 17 })
            XCTAssertFalse(plan.diagnostics.eventMappings.contains { [1,16].contains($0.channelIndex) && $0.source.rowIndex == 2 })
            let retained = try XCTUnwrap(plan.diagnostics.eventMappings.first { $0.channelIndex == 0 && $0.source.rowIndex == 2 })
            XCTAssertEqual(retained.effectiveNoteValue,0)
            XCTAssertEqual(linear ? retained.linearPeriod : retained.amigaPeriod,linear ? 4608 : 6848)
            XCTAssertEqual(retained.sampleIndex,0)
            XCTAssertEqual(retained.instrumentIndex,2)
            XCTAssertTrue(plan.diagnostics.noteDelayEffects.contains { $0.channelIndex == 4 && $0.source.rowIndex == 2 && $0.status == .sourceRefused && $0.delayedFrame == 13*Int(rate/50) })
            if !linear {
                for channel in [7,8,9] {
                    let tone = try XCTUnwrap(plan.diagnostics.tonePortamentoEffects.first { $0.channelIndex == channel && $0.source.rowIndex == 3 })
                    XCTAssertEqual(tone.currentAmigaPeriodBefore,156556)
                    XCTAssertEqual(tone.stepUpdates.first?.amigaPeriodAfter,480)
                    XCTAssertEqual(tone.directionAfter,.towardHigherPeriod)
                }
                XCTAssertTrue(plan.diagnostics.vibratoEffects.flatMap(\.stepUpdates).contains { $0.amigaPeriodAfter == 0 && $0.playbackStepAfter == 0 })
            }
            let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(),whole = renderer.render(request)
            XCTAssertEqual(whole.plan,runtime.plan)
            for rows in [1,5,11] {
                let window = renderer.renderWindowed(request,windowRows: rows)
                XCTAssertEqual(window.block.interleavedPCM.count,whole.block.interleavedPCM.count)
                XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM,whole.block.interleavedPCM).map { abs($0-$1) }.max() ?? 0,1e-7)
            }
#if DEBUG
            let timing = PlaybackSongFxxTimingPlanner.plan(module,startOrderIndex: 0,orderCount: 1,sampleRate: rate)
            let boundaries = [timing.frameFor(row: 2),timing.frameFor(row: 2,tick: 1),
                timing.frameFor(row: 3,tick: 1),timing.frameFor(row: 6),timing.frameFor(row: 12,tick: 4)]
            let split = renderer.renderWindowedAtFrameBoundariesForTesting(request,boundaries: boundaries.flatMap { [$0-1,$0,$0+1] })
            XCTAssertEqual(split.block.interleavedPCM.count,whole.block.interleavedPCM.count)
            XCTAssertLessThanOrEqual(zip(split.block.interleavedPCM,whole.block.interleavedPCM).map { abs($0-$1) }.max() ?? 0,1e-7)
#endif
        } }
    }

    func testSignedConsumerFamiliesAndZeroSpeedToneContinuation() throws {
        let prefix = [[c(1,3)],[c(fx: 2,param: 255)],[c(fx: 2,param: 255)]]
        for rate in rates {
            for (last,expected): (PlaybackCell,Double) in [(c(fx: 1,param: 1),4),
                (c(fx: 14,param: 0x11),4),(c(fx: 14,param: 0x21),156572),
                (c(fx: 33,param: 0x11),4),(c(fx: 33,param: 0x21),156560)] {
                let (context,states) = inspect(song(prefix+[[last]],linear: false,speed: 6),rate)
                XCTAssertEqual(states[0].activeAmigaPeriod,116096)
                XCTAssertEqual(states[1].activeAmigaPeriod,136156)
                XCTAssertEqual(states[2].activeAmigaPeriod,156556)
                XCTAssertEqual(states[3].activeAmigaPeriod,expected)
                XCTAssertEqual(context.events.count,1)
                XCTAssertEqual(states[3].activePlaybackStep,A.playbackStep(amigaPeriod: expected,baseSampleRate: 8363,outputSampleRate: rate))
            }
            for last in [c(96,fx: 3,param: 1),c(96,fx: 5,param: 1),c(96,volume: 0xf1)] {
                let (context,states) = inspect(song(prefix+[[last],[c(fx: 3)],[c(fx: 5)],[c(volume: 0xf0)]],linear: false,speed: 6),rate)
                let first = try XCTUnwrap(context.tonePortamentoEffects.first)
                XCTAssertEqual(first.currentAmigaPeriodBefore,156556)
                XCTAssertEqual(first.targetAmigaPeriod,480)
                XCTAssertEqual(first.directionAtExecution,.towardLowerPeriod)
                XCTAssertEqual(first.stepUpdates.first?.amigaPeriodAfter,480)
                XCTAssertEqual(first.stepUpdates.first?.scheduledFrame,19*Int(rate/50))
                XCTAssertEqual(states[3].tonePortamentoDirection,.towardHigherPeriod)
                XCTAssertTrue(states[3...].allSatisfy { $0.activeAmigaPeriod == 480 && $0.activeEventIndex == 0 })
                XCTAssertEqual(context.events.count,1)
                if last.effectType == 5 { XCTAssertNil(states.last?.tonePortamentoSpeed) }
            }
        }
        XCTAssertEqual(MemoryLayout<A.ChannelState>.size,1152)
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride,1152)
    }

    private func c(_ note: UInt8 = 0,_ instrument: UInt8 = 0,_ fx: UInt8 = 0,_ param: UInt8 = 0,
        volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: instrument,volumeColumn: volume,effectType: fx,effectParam: param)
    }
    private func c(_ note: UInt8 = 0,fx: UInt8,param: UInt8 = 0,volume: UInt8 = 0) -> PlaybackCell {
        c(note,0,fx,param,volume: volume)
    }
    private func period(_ state: A.ChannelState) -> Double? { state.activeAmigaPeriod ?? state.activeLinearPeriod }
    private func song(_ rows: [[PlaybackCell]],linear: Bool,relative: Int = -2,fine: Int = 127,
        speed: Int = 3,completed: Bool = false,empty: Bool = false,emptyRelative: Int = 0,
        mappedRelative: Int = -2) -> PlaybackSong {
        func sample(_ index: Int,_ slot: Int,_ volume: Int,_ pan: UInt8,_ relative: Int,_ fine: Int,_ oneShot: Bool = false) -> PlaybackSample {
            .init(instrumentIndex: index,sampleIndex: slot,pcm: (0..<256).map { Float(sin(Double($0) * .pi / 8)/16) },
                volume: Float(volume)/64,panning: pan,relativeNote: relative,finetune: fine,baseSampleRate: 8363,
                loopStart: 0,loopLength: oneShot ? 0 : 256,loopType: oneShot ? 0 : 1)
        }
        func envelope(_ value: Int,_ fadeout: Int) -> PlaybackVolumeEnvelope {
            .init(enabled: true,points: [.init(tick: 0,value: value),.init(tick: 24,value: value)],
                sustainPointIndex: nil,loopStartPointIndex: nil,loopEndPointIndex: nil,typeFlags: 1,fadeout: fadeout)
        }
        func panEnvelope(_ value: Int) -> PlaybackPanningEnvelope {
            .init(enabled: true,points: [.init(tick: 0,value: value),.init(tick: 24,value: value)],
                sustainPointIndex: nil,loopStartPointIndex: nil,loopEndPointIndex: nil,typeFlags: 1)
        }
        var map = Array(repeating: 0,count: 96);map[0] = 1
        let firstSamples = (empty ? [] : [sample(1,0,24,96,0,0,completed)]) + [sample(1,1,48,192,mappedRelative,127)]
        let first = PlaybackInstrument(index: 1,samples: firstSamples,
            volumeEnvelope: envelope(64,512),panningEnvelope: panEnvelope(32),noteSampleMap: map)
        let second = PlaybackInstrument(index: 2,samples: [sample(2,0,48,192,relative,fine)],
            volumeEnvelope: envelope(48,2048),panningEnvelope: panEnvelope(16),noteSampleMap: Array(repeating: 0,count: 96))
        let low = PlaybackInstrument(index: 3,samples: [sample(3,0,32,128,0,-128)],noteSampleMap: Array(repeating: 0,count: 96))
        return .init(title: "Public extreme state",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0:.init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: [1:first,2:second,3:low],restartOrderIndex: 0,endBehavior: .stopAtEnd,
            initialTiming: .init(speed: speed,bpm: 125),usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: empty ? [1:[.init(sampleIndex: 0,decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false,volume: 24,panning: 96,relativeNote: emptyRelative)]] : [:])
    }
    private func inspect(_ song: PlaybackSong,_ rate: Double) -> (A.AdapterRowContext,[A.ChannelState]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song,startOrderIndex: 0,orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(song,traversalPlan: traversal,sampleRate: rate)
        var context = A.AdapterRowContext(),states = [A.ChannelState]()
        for (i,row) in traversal.rows.enumerated() {
            _ = A.appendEvents(from: row.row,source: row.source,syntheticRow: row.syntheticRow,song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow),timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: i+1<traversal.rows.count ? traversal.rows[i+1].row : nil,context: &context)
            states.append(context.channelStates[0])
        }
        return (context,states)
    }
}
