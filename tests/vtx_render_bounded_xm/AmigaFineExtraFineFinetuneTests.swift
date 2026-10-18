import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class AmigaFineExtraFineFinetuneTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]
    private typealias Observation = (row: Int, channel: Int, period: Double?, step: Double?, folded: Bool,
        execution: PlaybackSongSyntheticFinePitchExecution, updates: [PlaybackSongSyntheticTonePortamentoStepUpdate])

    func testReferenceNibbleGridTickZeroAndOrdinaryTriggerFolding() throws {
        for rate in rates { for family in 1...4 { for nibble in [1,2,4,8,15] { for form in 0...2 {
            let note: UInt8 = form == 0 ? 0 : 50
            let (context,states) = inspect(song([[c(49,1)],[pitch(family,nibble,note,form == 1 ? 1 : 0)],[c()]]),rate)
            let d = try XCTUnwrap(observations(context).first)
            let before = form == 0 ? 6848.0 : 6464
            let delta = Double(nibble * (family < 3 ? 16 : 4)) * (family == 1 || family == 3 ? -1 : 1)
            XCTAssertEqual(d.period,before+delta)
            XCTAssertEqual(try XCTUnwrap(d.step),8363*6848/(before+delta)/rate,accuracy: 1e-12)
            XCTAssertEqual(d.execution.memoryValue,nibble)
            XCTAssertEqual(d.execution.memoryOrigin?.source.rowIndex,1)
            XCTAssertFalse(d.execution.usesLinearFrequencyTable)
            XCTAssertEqual(d.folded,form != 0)
            XCTAssertEqual(context.events.count,form == 0 ? 1 : 2)
            XCTAssertNil(states[1][0].activeLinearPeriod)
            if form == 0 {
                let update = try XCTUnwrap(d.updates.first)
                XCTAssertEqual(update.syntheticTick,0)
                XCTAssertEqual(update.scheduledFrame,3*Int(rate/50))
                XCTAssertEqual(update.amigaPeriodBefore,before)
                XCTAssertEqual(update.amigaPeriodAfter,before+delta)
                XCTAssertEqual(states[1][0].activeEventIndex,0)
            } else {
                XCTAssertTrue(d.updates.isEmpty)
                XCTAssertEqual(context.events[1].initialSourceFrame,0)
                XCTAssertEqual(context.events[1].scheduledStartFrame,3*Int(rate/50))
            }
        } } } }
    }

    func testDirectionalReplayOriginsAndFineExtraChannelIndependence() throws {
        for rate in rates { for seed in [1,15] {
            let rows = [[c(49,1),c(49,1)],
                [pitch(1,seed),pitch(2,2)],[pitch(2,4),pitch(1,8)],
                [pitch(3,2),pitch(4,4)],[pitch(4,8),pitch(3,1)],
                [pitch(1,0),pitch(1,0)],[pitch(2,0),pitch(2,0)],
                [pitch(3,0),pitch(3,0)],[pitch(4,0),pitch(4,0)]]
            let (context,states) = inspect(song(rows),rate)
            let last = states.last!
            for (channel,amounts) in [(0,[seed,4,2,8]),(1,[8,2,1,4])] {
                let s = last[channel]
                XCTAssertEqual([s.finePitchUpMemory?.amount,s.finePitchDownMemory?.amount,
                    s.extraFinePitchUpMemory?.amount,s.extraFinePitchDownMemory?.amount],amounts.map(Optional.some))
                let replays = observations(context).filter { $0.channel == channel && $0.row >= 5 }
                XCTAssertEqual(replays.map { $0.execution.memoryValue },amounts.map(Optional.some))
                XCTAssertTrue(replays.allSatisfy { $0.execution.effectMemoryReused })
                XCTAssertEqual(replays.map { $0.execution.memoryOrigin?.source.rowIndex },channel == 0 ? [1,2,3,4] : [2,1,4,3])
            }
            XCTAssertEqual(context.events.count,2)
        } }
        // The same nibble changes Amiga fine pitch by four extra-fine steps.
        for rate in rates { for nibble in [1,2,4,8,15] {
            let fine = inspect(song([[c(49,1)],[pitch(1,nibble)]]),rate).1.last![0].activeAmigaPeriod!
            let extra = inspect(song([[c(49,1)],[pitch(3,nibble)]]),rate).1.last![0].activeAmigaPeriod!
            XCTAssertEqual(6848-fine,4*(6848-extra))
        } }
    }

    func testColdReleasedCompletedAndExactEmptyRoutesDoNotInventSources() throws {
        for rate in rates { for family in 1...4 {
            let cold = inspect(song([[pitch(family,0)],[pitch(family,15)],[pitch(family,0)]]),rate)
            XCTAssertTrue(cold.0.events.isEmpty)
            XCTAssertTrue(cold.1.allSatisfy { $0[0].activeAmigaPeriod == nil })
            XCTAssertTrue(observations(cold.0).last?.execution.effectMemoryReused == true)
            XCTAssertNil(observations(cold.0).first?.execution.memoryOrigin)
            for boundary in [c(97),c(fx: 20),c(70)] {
                let (context,states) = inspect(song([[c(49,1)],[boundary],[pitch(family,15)],[pitch(family,0)]]),rate)
                XCTAssertEqual(context.events.count,1)
                XCTAssertEqual(states.last![0].tonePortamentoDirection,.none)
                XCTAssertNil(states.last![0].tonePortamentoTargetNote)
                XCTAssertTrue(observations(context).last?.execution.effectMemoryReused == true)
                if boundary.note == 70 {
                    XCTAssertNil(states.last![0].activeEventIndex)
                    XCTAssertTrue(observations(context).allSatisfy { $0.updates.isEmpty })
                }
            }
            let noteOff = inspect(song([[c(49,1)],[pitch(family,15,97)]]),rate)
            XCTAssertEqual(noteOff.0.events.count,1)
            XCTAssertNotEqual(noteOff.1.last![0].activeAmigaPeriod,6848)
            let completeSong = song([[c(49,1)],[pitch(family,15)],[pitch(family,0)]],completed: true)
            let plan = Adapter.adapt(completeSong,orderIndex: 0,sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.count,1)
            XCTAssertTrue((plan.diagnostics.finePortamentoUpEffects.flatMap(\.stepUpdates)
                + plan.diagnostics.finePortamentoDownEffects.flatMap(\.stepUpdates)
                + plan.diagnostics.extraFinePortamentoEffects.flatMap(\.stepUpdates)).isEmpty)
        } }
    }

    func testE5ReferenceMappingOverridesHeaderButPreservesRelativeNoteAndExactRoute() throws {
        let grid = [(0,7256.0),(1,7200),(4,7048),(7,6896),(8,6848),(11,6704),(14,6560),(15,6512)]
        for rate in rates { for (nibble,base) in grid { for header in [-128,-1,0,1,127] { for relative in [-12,0,12] {
            for form in 0...2 {
                let trigger = c(49,form == 0 ? 1 : form == 1 ? 0 : 2,fx: 14,param: UInt8(0x50+nibble))
                let (context,states) = inspect(song([[c(49,1)],[trigger]],finetune: header,relative: relative),rate)
                let d = try XCTUnwrap(context.setFinetuneEffects.first)
                let mapping = try XCTUnwrap(context.eventMappings.last)
                let expected = base * pow(2,-Double(relative)/12)
                XCTAssertEqual(d.status,.applied)
                XCTAssertEqual(d.sampleFinetune,header)
                XCTAssertEqual(d.effectiveFinetune,16*nibble-128)
                XCTAssertEqual(mapping.amigaPeriod,expected)
                XCTAssertEqual(mapping.playbackStep,8363*6848/expected/rate,accuracy: 1e-12)
                XCTAssertEqual(states.last![0].activeSampleRelativeNote,relative)
                XCTAssertEqual(context.events.count,2)
                XCTAssertEqual(context.events[1].initialSourceFrame,0)
                XCTAssertEqual(mapping.instrumentIndex,form == 2 ? 2 : 1)
            }
        } } } }
        for rate in rates {
            let (context,_) = inspect(song([[c(49,1)],[c(51,1,fx: 14,param: 0x57)]]),rate)
            XCTAssertEqual(context.eventMappings.last?.sampleIndex,1)
            XCTAssertEqual(context.eventMappings.last?.effectiveFinetune,-16)
            XCTAssertEqual(context.events.count,2)
            let empty = inspect(song([[c(49,1)],[c(70,1,fx: 14,param: 0x5f)]]),rate)
            XCTAssertEqual(empty.0.events.count,1)
            XCTAssertNil(empty.1.last![0].activeEventIndex)
            XCTAssertEqual(empty.1.last![0].activeSampleFinetune,112)
            XCTAssertEqual(empty.0.setFinetuneEffects.first?.status,.applied)
        }
    }

    func testNoNoteE5IsInertAndDoesNotAffectALaterOrdinaryTrigger() {
        for rate in rates { for nibble in [0,7,15] { for cold in [false,true] {
            let prefix = cold ? c() : c(49,1)
            let candidate = inspect(song([[prefix],[c(fx: 14,param: UInt8(0x50+nibble))],[c(49,1)]]),rate)
            let control = inspect(song([[prefix],[c()],[c(49,1)]]),rate)
            XCTAssertEqual(candidate.1,control.1)
            XCTAssertEqual(candidate.0.events,control.0.events)
            XCTAssertEqual(candidate.0.eventMappings.last?.effectiveFinetune,0)
            XCTAssertEqual(candidate.0.eventMappings.last?.amigaPeriod,6848)
            XCTAssertEqual(candidate.0.setFinetuneEffects.first?.status,.noNoteInert)
            XCTAssertTrue(candidate.0.setFinetuneEffects.first?.ignoredAsNoOp == true)
            XCTAssertFalse(candidate.0.setFinetuneEffects.first?.effectMemoryDeferred == true)
        } } }
    }

    func testAllFiveActualCrossingsPreserveTargetDirectionAndSpeedThenClamp() throws {
        let cases = [(1,15,49,50,4,6224.0,6464.0),(2,15,50,49,4,7088,6848),
            (3,8,49,50,1,6432,6464),(4,8,50,49,1,6880,6848),(5,15,49,50,4,6144,6464)]
        for rate in rates { for (family,nibble,start,target,speed,crossed,goal) in cases {
            let trigger = family == 5 ? c(UInt8(target),1,fx: 14,param: UInt8(0x50+nibble)) : pitch(family,nibble,UInt8(target),1)
            let (context,states) = inspect(song([[c(UInt8(start),1)],[c(UInt8(target),fx: 3,param: UInt8(speed))],
                [trigger],[c(fx: 3)],[c(fx: 3)]]),rate)
            XCTAssertEqual(states[2][0].activeAmigaPeriod,crossed)
            XCTAssertEqual(states[2][0].tonePortamentoTargetAmigaPeriod,goal)
            XCTAssertEqual(states[2][0].tonePortamentoDirection,states[1][0].tonePortamentoDirection)
            XCTAssertEqual(states[2][0].tonePortamentoSpeed,speed)
            let later = try XCTUnwrap(context.tonePortamentoEffects.first { $0.syntheticRow == 3 })
            XCTAssertEqual(later.stepUpdates.map(\.amigaPeriodAfter),[goal])
            XCTAssertEqual(later.stepUpdates.map(\.scheduledFrame),[10*Int(rate/50)])
            XCTAssertEqual(later.directionAfter,.towardHigherPeriod)
            XCTAssertEqual(states[3][0].activeAmigaPeriod,goal)
            XCTAssertEqual(states[4][0].activeAmigaPeriod,goal)
            XCTAssertEqual(context.events.count,2)
            XCTAssertEqual(later.activeEventIndex,1)
            XCTAssertEqual(context.events[1].initialSourceFrame,0)
        } }
    }

    func testSameRowFxxBeforeAndAfterKeepsAllOperationsAtTickZero() throws {
        for rate in rates { for family in 1...5 { for speed in [1,2,3,6] { for channel in [0,1] {
            var first = [c(),c()],second = [c(),c()]
            first[channel] = c(49,1)
            second[channel] = family == 5 ? c(49,1,fx: 14,param: 0x57) : pitch(family,4)
            second[1-channel] = c(fx: 15,param: UInt8(speed))
            let (context,states) = inspect(song([first,second]),rate)
            let expected = family == 5 ? 6896.0 : 6848+Double(family < 3 ? 64 : 16)*(family == 1 || family == 3 ? -1 : 1)
            XCTAssertEqual(states[1][channel].activeAmigaPeriod,expected)
            if family == 5 {
                XCTAssertEqual(context.setFinetuneEffects.first?.rowSpeed,speed)
                XCTAssertEqual(context.events.last?.scheduledStartFrame,3*Int(rate/50))
            } else {
                XCTAssertEqual(observations(context).first?.updates.map(\.scheduledFrame),[3*Int(rate/50)])
            }
        } } } }
    }

    func testE5UsesOrdinaryDefaultsEnvelopeResetAndColumnWriterPrecedence() throws {
        for rate in rates { for column: UInt8 in [0,0x20,0xc3] {
            let module = song([[c(49,1)],[c(97)],[c(49,2,fx: 14,param: 0x5f,vol: column)]],envelope: true)
            let (context,states) = inspect(module,rate)
            XCTAssertEqual(context.events.count,2)
            XCTAssertEqual(states[2][0].baseChannelVolume,column == 0x20 ? 16 : 48)
            XCTAssertEqual(states[2][0].panningValue,column == 0xc3 ? 48 : 192)
            XCTAssertEqual(context.events[1].initialSourceFrame,0)
            let plan = Adapter.adapt(module,orderIndex: 0,sampleRate: rate)
            let reset = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first)
            XCTAssertEqual(reset.state.volumeTick,0)
            XCTAssertTrue(reset.state.keyOn)
            XCTAssertEqual(reset.state.fadeoutAccumulator,32768)
            XCTAssertEqual(plan.diagnostics.eventMappings.last?.effectiveFinetune,112)
        } }
    }

    func testG30RangeAndConversionPoliciesRemainSeparate() {
        for rate in rates {
            let high = inspect(song([[c(96,1)],[pitch(1,15,96,1)]],relative: 12),rate)
            XCTAssertEqual(high.1[1][0].activeAmigaPeriod,107) // FT2 reaches native period 1; retained G30 minimum.
            XCTAssertTrue(high.0.finePortamentoUpEffects.first?.clamped == true)
            let low = inspect(song([[c(1,1)],[pitch(2,15,1,1)]],relative: -12),rate)
            XCTAssertEqual(low.1[1][0].activeAmigaPeriod,109808) // Existing base-note admission differs from FT2 here.
            let nongrid = inspect(song([[c(49,1)],[pitch(3,1)]],finetune: 1),rate)
            XCTAssertEqual(nongrid.1[0][0].activeAmigaPeriod,6848)
            XCTAssertEqual(nongrid.1[1][0].activeAmigaPeriod,6844)
        }
    }

    func testPublicFixtureWholeWindowRuntimeAndBoundaryParity() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/amiga-fine-extra-fine-finetune.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
        XCTAssertFalse(module.usesLinearFrequencyTable)
        for rate in rates {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module,sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(),whole = renderer.render(request)
            XCTAssertEqual(runtime.plan,whole.plan)
            for rows in [1,2,5] { assertPCM(whole.block.interleavedPCM,renderer.renderWindowed(request,windowRows: rows).block.interleavedPCM) }
#if DEBUG
            let timing = PlaybackSongFxxTimingPlanner.plan(module,startOrderIndex: 0,orderCount: 1,sampleRate: rate)
            for offset in [-1,0,1] {
                let boundaries = [1,2,3,4,5,6,9,10,13].map { timing.frameFor(row: $0)+offset }
                assertPCM(whole.block.interleavedPCM,renderer.renderWindowedAtFrameBoundariesForTesting(request,boundaries: boundaries).block.interleavedPCM)
            }
#endif
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: whole)
            let fine = try XCTUnwrap(json["fine_portamento_up_effects"] as? [[String:Any]])
            XCTAssertTrue(fine.contains { $0["frequency_table"] as? String == "amiga" && $0["applied"] as? Bool == true })
        }
    }

    private func c(_ note: UInt8 = 0,_ ins: UInt8 = 0,fx: UInt8 = 0,param: UInt8 = 0,vol: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: ins,volumeColumn: vol,effectType: fx,effectParam: param)
    }
    private func pitch(_ family: Int,_ amount: Int,_ note: UInt8 = 0,_ ins: UInt8 = 0) -> PlaybackCell {
        c(note,ins,fx: family < 3 ? 14 : 33,param: UInt8((family < 3 ? family : family-2)*16+amount))
    }
    private func observations(_ context: Adapter.AdapterRowContext) -> [Observation] {
        (context.finePortamentoUpEffects.map { ($0.syntheticRow,$0.channelIndex,$0.currentLinearPeriodAfter,$0.currentPlaybackStepAfter,$0.appliedToInitialPlaybackStep,$0.execution,$0.stepUpdates) }
         + context.finePortamentoDownEffects.map { ($0.syntheticRow,$0.channelIndex,$0.currentLinearPeriodAfter,$0.currentPlaybackStepAfter,$0.appliedToInitialPlaybackStep,$0.execution,$0.stepUpdates) }
         + context.extraFinePortamentoEffects.map { ($0.syntheticRow,$0.channelIndex,$0.currentLinearPeriodAfter,$0.currentPlaybackStepAfter,$0.appliedToInitialPlaybackStep,$0.execution,$0.stepUpdates) })
            .sorted { ($0.0,$0.1) < ($1.0,$1.1) }
    }
    private func song(_ rows: [[PlaybackCell]],finetune: Int = 0,relative: Int = 0,completed: Bool = false,envelope: Bool = false) -> PlaybackSong {
        func sample(_ instrument: Int,_ slot: Int,_ volume: Int,_ pan: UInt8) -> PlaybackSample {
            .init(instrumentIndex: instrument,sampleIndex: slot,pcm: Array(repeating: 1/32,count: completed ? 1 : 256),volume: Float(volume)/64,
                panning: pan,relativeNote: relative,finetune: finetune,baseSampleRate: 8363,loopStart: 0,loopLength: completed ? 0 : 256,loopType: completed ? 0 : 1)
        }
        var map = Array(repeating: 0,count: 96);map[50] = 1;map[69] = 2
        let env = envelope ? PlaybackVolumeEnvelope(enabled: true,points: [.init(tick: 0,value: 64),.init(tick: 3,value: 40)],sustainPointIndex: nil,loopStartPointIndex: nil,loopEndPointIndex: nil,typeFlags: 1,fadeout: 256) : .disabled
        return PlaybackSong(title: "Public Amiga G29",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0:.init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: [1:.init(index: 1,samples: [sample(1,0,32,128),sample(1,1,20,96)],volumeEnvelope: env,noteSampleMap: map),
                2:.init(index: 2,samples: [sample(2,0,48,192)],volumeEnvelope: env,noteSampleMap: Array(repeating: 0,count: 96))],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: 3,bpm: 125),usesLinearFrequencyTable: false,
            xmSampleSlotProvenanceByInstrument: [1:[.init(sampleIndex: 2,decodedPayloadLength: 0,isCanonicalEmptySlotHeader: false,volume: 24,panning: 128)]])
    }
    private func inspect(_ module: PlaybackSong,_ rate: Double) -> (Adapter.AdapterRowContext,[[Adapter.ChannelState]]) {
        let traversal = PlaybackSongTraversalPlanner.plan(module,startOrderIndex: 0,orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(module,traversalPlan: traversal,sampleRate: rate)
        var context = Adapter.AdapterRowContext(),states = [[Adapter.ChannelState]]()
        for (i,row) in traversal.rows.enumerated() {
            _ = Adapter.appendEvents(from: row.row,source: row.source,syntheticRow: row.syntheticRow,song: module,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow),timingPlan: timing,scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: i+1<traversal.rows.count ? traversal.rows[i+1].row : nil,context: &context)
            states.append(context.channelStates)
        }
        return (context,states)
    }
    private func assertPCM(_ a: [Float],_ b: [Float],file: StaticString = #filePath,line: UInt = #line) {
        XCTAssertEqual(a.count,b.count,file: file,line: line)
        XCTAssertLessThanOrEqual(zip(a,b).map { abs($0-$1) }.max() ?? 0,1e-7,file: file,line: line)
    }
}
