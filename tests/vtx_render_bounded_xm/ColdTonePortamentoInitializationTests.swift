import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class ColdTonePortamentoInitializationTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]

    func testColdSurfacesAdmitTargetAndSpeedWithoutHeaderOrSourceAndLaterNoteOnlyStartsSilently() throws {
        for rate in rates {
            for speed in [1, 3, 6] {
                for (linear, effect, parameter, column, seed): (Bool, UInt8, UInt8, UInt8, PlaybackCell?) in [
                    (true,3,4,0,nil), (false,3,4,0,nil), (true,3,0,0,nil), (false,3,0,0,nil),
                    (true,3,0,0,c(3,4)), (false,3,0,0,c(3,4)), (true,5,4,0,nil), (true,5,0,0,nil),
                    (true,0,0,0xF4,nil), (true,0,0,0xF0,nil), (true,0,0,0xF0,c(volume: 0xF4))
                ] {
                    let prefix = seed.map { [$0] } ?? []
                    let module = song(prefix + [c(effect,parameter,note: 49,instrument: 1,volume: column),c(note: 61),c(3)],
                        linear: linear,speed: speed,tuned: true)
                    let (context,states) = inspect(module,rate)
                    let cold = states[prefix.count], later = states[prefix.count+1]
                    XCTAssertEqual(cold.carriedInstrumentIndex,1)
                    XCTAssertEqual(cold.baseChannelVolume,0); XCTAssertEqual(cold.outputChannelVolume,0)
                    XCTAssertEqual(cold.panningValue,128); XCTAssertEqual(cold.pan,0)
                    XCTAssertNil(cold.activeEventIndex); XCTAssertNil(cold.semanticInstrumentIndex)
                    XCTAssertNil(cold.semanticSampleIndex); XCTAssertNil(cold.activeSampleVolume)
                    XCTAssertNil(cold.activeSampleRelativeNote); XCTAssertNil(cold.activeSampleFinetune)
                    XCTAssertEqual(cold.triggeredSampleDefaultVolume,0); XCTAssertEqual(cold.triggeredSampleDefaultPan,128)
                    XCTAssertEqual(cold.tonePortamentoTargetNote,49)
                    XCTAssertEqual(cold.tonePortamentoTargetLinearPeriod,linear ? 4608 : nil)
                    XCTAssertEqual(cold.tonePortamentoTargetAmigaPeriod,linear ? nil : 6848)
                    let expectedSpeed = column == 0xF4 || seed?.volumeColumn == 0xF4 ? 64 : parameter > 0 && effect == 3 || seed?.effectType == 3 ? 4 : nil
                    XCTAssertEqual(cold.tonePortamentoSpeed,expectedSpeed)
                    XCTAssertEqual(context.events.count,1)
                    XCTAssertEqual(context.events[0].scheduledStartFrame,(prefix.count+1)*speed*Int(rate/50))
                    XCTAssertEqual(context.events[0].gain,0); XCTAssertEqual(context.events[0].pan,0)
                    XCTAssertEqual(context.eventMappings[0].sampleIndex,1)
                    XCTAssertEqual(later.activeEventIndex,0); XCTAssertEqual(later.activeSampleIndex,1)
                    XCTAssertEqual(later.activeSampleVolume,20/64)
                    XCTAssertEqual(later.triggeredSampleDefaultVolume,20); XCTAssertEqual(later.triggeredSampleDefaultPan,192)
                    XCTAssertEqual(later.baseChannelVolume,0); XCTAssertEqual(later.panningValue,128)
                    XCTAssertEqual(later.tonePortamentoTargetNote,49)
                    let coldDiagnostic = try XCTUnwrap(context.tonePortamentoEffects.first { $0.syntheticRow == prefix.count })
                    XCTAssertEqual(coldDiagnostic.policy,"same_cell_tone_portamento_cold_initialization_no_source")
                    XCTAssertTrue(coldDiagnostic.instrumentStateUpdated && coldDiagnostic.targetExistsAfter)
                    XCTAssertEqual(coldDiagnostic.noteTargetAfter,49)
                    XCTAssertFalse(coldDiagnostic.noteTriggerEventCreated || coldDiagnostic.voiceReplacement || coldDiagnostic.samplePositionReset)
                    let full = PlaybackSongOfflineRenderer().render(.init(song: module,config: .init(sampleRate: rate),rows: prefix.count+3))
                    XCTAssertTrue(full.block.interleavedPCM.allSatisfy { $0 == 0 })
                }
            }
        }
    }

    func testSharedSlideExecutesOnColdZeroAndPreservesExecutedTickMemory() throws {
        for rate in rates {
            for speed in [1,3,6] {
                for family: UInt8 in [5,6,10] {
                    for byte: UInt8 in [4,0x40] {
                        let module = song([c(family,byte),c(5,note: 49,instrument: 1),c(note: 61)],speed: speed)
                        let (context,states) = inspect(module,rate)
                        let expected = byte == 4 ? 0 : 4*(speed-1)
                        XCTAssertEqual(states[1].baseChannelVolume,expected)
                        XCTAssertEqual(states[1].outputChannelVolume,expected)
                        XCTAssertEqual(states[1].volumeSlideMemory?.parameter,speed == 1 ? nil : byte)
                        XCTAssertEqual(states[1].volumeSlideMemory?.source.effectType,speed == 1 ? nil : family)
                        XCTAssertNil(states[1].activeEventIndex)
                        XCTAssertEqual(context.events[0].gain,Float(expected)/64)
                        let writes = context.voiceStateUpdates.filter { $0.syntheticRow == 1 && $0.syntheticTick > 0 }
                        XCTAssertEqual(writes.count,speed-1)
                        XCTAssertTrue(writes.allSatisfy { $0.applied && !$0.activeVoiceUpdated })
                    }
                }
                let down = inspect(song([c(5,4,note: 49,instrument: 1),c(note: 61)],speed: speed),rate)
                XCTAssertEqual(down.1[0].volumeSlideMemory?.parameter,speed == 1 ? nil : 4)
                XCTAssertEqual(down.1[0].baseChannelVolume,0)
            }
        }
    }

    func testExplicitWritersFollowColdResetAndCanMakeLaterNoteAudible() throws {
        for rate in rates {
            for (effect,parameter,column,volume,pan): (UInt8,UInt8,UInt8,Int,Double) in [
                (3,4,0x30,32,128), (3,4,0x93,3,128), (12,32,0xF4,32,128),
                (3,4,0xC3,0,48), (8,48,0xF4,0,48)
            ] {
                let module = song([c(12,21,volume: 0xCF),c(effect,parameter,note: 49,instrument: 1,volume: column),c(note: 61)],speed: 3)
                let (context,states) = inspect(module,rate)
                XCTAssertEqual(states[1].baseChannelVolume,volume); XCTAssertEqual(states[1].panningValue,pan)
                XCTAssertEqual(states[2].baseChannelVolume,volume); XCTAssertEqual(states[2].panningValue,pan)
                XCTAssertEqual(context.events[0].gain,Float(volume)/64)
                let reset = try XCTUnwrap(context.voiceStateUpdates.first { $0.syntheticRow == 1 && $0.commandSource == .instrumentState })
                XCTAssertEqual(reset.effectiveVolumeAfter,0); XCTAssertEqual(reset.effectivePanAfter,0)
                let full = PlaybackSongOfflineRenderer().render(.init(song: module,config: .init(sampleRate: rate,channelCount: 1),rows: 3))
                XCTAssertEqual(full.block.interleavedPCM[6*Int(rate/50)+300],Float(volume)/64/8,accuracy: 1e-7)
            }
        }
    }

    func testColdReleaseResetPreservesInactivePanClockAndNeutralDecrementOnNoteOnly() throws {
        for rate in rates {
            for released in [false,true] {
                let prefix = released ? [c(note: 97)] : []
                let module = song(prefix + [c(3,4,note: 49,instrument: 1,volume: 0x30),c(note: 61),c(note: 97)],speed: 3,envelope: true)
                let plan = Adapter.adapt(module,orderIndex: 0,sampleRate: rate)
                let history = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
                let start = try XCTUnwrap(history.first)
                XCTAssertTrue(start.state.keyOn); XCTAssertEqual(start.state.fadeoutAccumulator,32768)
                XCTAssertEqual(start.state.volumeTick,1); XCTAssertEqual(start.state.volumeValue,0)
                XCTAssertEqual(start.state.panTick,released ? 0 : 1)
                XCTAssertEqual(start.state.panValue,released ? 0.5 : 0)
                XCTAssertTrue(history.allSatisfy { $0.state.fadeoutAccumulator == 32768 }) // No instrument-trigger decrement.
                XCTAssertEqual(plan.pattern.events[0].gain,0.5)
                XCTAssertNil(plan.xmEnvelopeTimeline?.channelState(channelIndex: 0,atOrBefore: (prefix.count+1)*3*Int(rate/50)-1))
                let pcm = PlaybackSongOfflineRenderer().render(.init(song: module,config: .init(sampleRate: rate),rows: prefix.count+3)).block.interleavedPCM
                XCTAssertTrue(pcm.prefix((prefix.count+2)*3*Int(rate/50)*2).allSatisfy { $0 == 0 })
            }
        }
    }

    func testDeclaredEmptyCompletedReleasedAndColdInstrumentOnlyKeepDistinctOwnership() throws {
        let parsed = try fixture()
        for rate in rates {
            // Target availability must not turn an unselected empty header into an owner.
            let emptyTarget = PlaybackSong(title: parsed.title,orders: parsed.orders,
                patternsByIndex: [0:.init(index: 0,rows: [c(3,4,note: 70,instrument: 1),c(note: 53)].enumerated().map {
                    .init(index: $0.offset,cells: [$0.element])
                })],instrumentsByIndex: parsed.instrumentsByIndex,restartOrderIndex: 0,endBehavior: .stopAtEnd,
                initialTiming: parsed.initialTiming,usesLinearFrequencyTable: true,
                xmSampleSlotProvenanceByInstrument: parsed.xmSampleSlotProvenanceByInstrument)
            let (emptyContext,emptyStates) = inspect(emptyTarget,rate)
            XCTAssertEqual(emptyStates[0].baseChannelVolume,0); XCTAssertEqual(emptyStates[0].panningValue,128)
            XCTAssertNil(emptyStates[0].semanticInstrumentIndex); XCTAssertNil(emptyStates[0].activeSampleVolume)
            XCTAssertEqual(emptyStates[0].tonePortamentoTargetLinearPeriod,3264)
            XCTAssertEqual(emptyContext.events.count,1); XCTAssertEqual(emptyContext.events[0].gain,0)
            XCTAssertEqual(emptyContext.eventMappings[0].sampleIndex,1)
            let instrument = try XCTUnwrap(parsed.instrumentsByIndex[1])
            let tuned = PlaybackSample(instrumentIndex: 1,sampleIndex: 0,pcm: instrument.samples[0].pcm,
                volume: 0.5,panning: 96,relativeNote: 12,finetune: 64,baseSampleRate: 8363,loopStart: 0,loopLength: 256,loopType: 1)
            let ownedEmpty = PlaybackSong(title: parsed.title,orders: parsed.orders,
                patternsByIndex: [0:.init(index: 0,rows: [c(note: 70,instrument: 1),c(3,4,note: 49,instrument: 1)].enumerated().map {
                    .init(index: $0.offset,cells: [$0.element])
                })],instrumentsByIndex: [1:.init(index: 1,samples: [tuned]+instrument.samples.dropFirst(),
                    volumeEnvelope: instrument.volumeEnvelope,panningEnvelope: instrument.panningEnvelope,noteSampleMap: instrument.noteSampleMap)],
                restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: parsed.initialTiming,usesLinearFrequencyTable: true,
                xmSampleSlotProvenanceByInstrument: parsed.xmSampleSlotProvenanceByInstrument)
            let owned = inspect(ownedEmpty,rate)
            XCTAssertEqual(owned.1[1].baseChannelVolume,24); XCTAssertEqual(owned.1[1].panningValue,80)
            XCTAssertEqual(owned.1[1].activeSampleRelativeNote,0); XCTAssertEqual(owned.1[1].activeSampleFinetune,0)
            XCTAssertEqual(owned.1[1].tonePortamentoTargetLinearPeriod,4608)
            XCTAssertTrue(owned.0.events.isEmpty)
            let plan = Adapter.adapt(parsed,orderIndex: 0,sampleRate: rate)
            let row = plan.xmChannelRows.filter { $0.syntheticRow == 9 }
            for channel in [12,13,14] {
                let state = try XCTUnwrap(row.first { $0.channelIndex == channel }).controls
                XCTAssertEqual(state.baseChannelVolume,channel == 12 ? 24 : 32)
                XCTAssertEqual(state.semanticInstrumentIndex,1)
                XCTAssertEqual(state.activeEventIndex == nil,channel == 12)
                XCTAssertEqual(state.panningValue,channel == 12 ? 80 : 128)
            }
            let cold = plan.xmChannelRows.first { $0.syntheticRow == 7 && $0.channelIndex == 10 }!.controls
            XCTAssertNil(cold.semanticInstrumentIndex); XCTAssertNil(cold.activeEventIndex)
            XCTAssertEqual(cold.baseChannelVolume,0); XCTAssertEqual(cold.panningValue,128)
            XCTAssertEqual(plan.pattern.events.filter { $0.row == 13 }.first?.gain,0.5)
        }
    }

    func testPublicFixtureWholeWindowRuntimePlansAndInitializationBoundaries() throws {
        for linear in [true,false] {
            let module = try fixture(linear: linear)
            for rate in rates {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module,sampleRate: rate)
                let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
                let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
                XCTAssertEqual(full.plan,runtime.plan)
                for rows in [1,3,5] { assertPCM(full.block.interleavedPCM,renderer.renderWindowed(request,windowRows: rows).block.interleavedPCM) }
#if DEBUG
                let timing = PlaybackSongFxxTimingPlanner.plan(module,startOrderIndex: 0,orderCount: 1,sampleRate: rate)
                for offset in [-1,0,1] {
                    let boundaries = [timing.frameFor(row: 1),timing.frameFor(row: 2),timing.frameFor(row: 4),timing.frameFor(row: 5)].map { $0+offset }
                    assertPCM(full.block.interleavedPCM,renderer.renderWindowedAtFrameBoundariesForTesting(request,boundaries: boundaries).block.interleavedPCM)
                }
#endif
            }
        }
    }

    private func fixture(linear: Bool = true) throws -> PlaybackSong {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/cold-tone-portamento-initialization.xm")
        let p = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
        let patterns = linear ? p.patternsByIndex : p.patternsByIndex.mapValues { pattern in
            PlaybackPattern(index: pattern.index,rows: pattern.rows.map { row in
                PlaybackRow(index: row.index,cells: row.cells.map { $0.effectType == 5 || $0.volumeColumn >= 0xF0 ? c() : $0 })
            })
        }
        return PlaybackSong(title: p.title,orders: p.orders,patternsByIndex: patterns,instrumentsByIndex: p.instrumentsByIndex,
            restartOrderIndex: p.restartOrderIndex,endBehavior: p.endBehavior,initialTiming: p.initialTiming,
            usesLinearFrequencyTable: linear,xmSampleSlotProvenanceByInstrument: p.xmSampleSlotProvenanceByInstrument)
    }
    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: instrument,volumeColumn: volume,effectType: effect,effectParam: parameter)
    }
    private func song(_ cells: [PlaybackCell],linear: Bool = true,speed: Int = 6,envelope: Bool = false,tuned: Bool = false) -> PlaybackSong {
        let samples = [PlaybackSample(instrumentIndex: 1,sampleIndex: 0,pcm: Array(repeating: 1/32,count: 32),volume: 0.5,panning: 96,
            relativeNote: tuned ? 12 : 0,finetune: tuned ? 64 : 0,baseSampleRate: 8363,loopStart: 0,loopLength: 32,loopType: 1),
            PlaybackSample(instrumentIndex: 1,sampleIndex: 1,pcm: Array(repeating: 1/8,count: 32),volume: 20/64,panning: 192,
            relativeNote: 0,finetune: 0,baseSampleRate: 8363,loopStart: 0,loopLength: 32,loopType: 1)]
        let volume = envelope ? PlaybackVolumeEnvelope(enabled: true,points: [.init(tick: 0,value: 64),.init(tick: 6,value: 52)],
            sustainPointIndex: nil,loopStartPointIndex: nil,loopEndPointIndex: nil,typeFlags: 1,fadeout: 256) : .disabled
        let pan = envelope ? PlaybackPanningEnvelope(enabled: true,points: [.init(tick: 0,value: 32),.init(tick: 6,value: 38)],
            sustainPointIndex: nil,loopStartPointIndex: nil,loopEndPointIndex: nil,typeFlags: 1) : .disabled
        return PlaybackSong(title: "Cold tone initialization",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0:.init(index: 0,rows: cells.enumerated().map { .init(index: $0.offset,cells: [$0.element]) })],
            instrumentsByIndex: [1:.init(index: 1,samples: samples,volumeEnvelope: volume,panningEnvelope: pan,noteSampleMap: (0..<96).map { $0 < 54 ? 0 : 1 })],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: speed,bpm: 125),usesLinearFrequencyTable: linear)
    }
    private func inspect(_ module: PlaybackSong,_ rate: Double) -> (Adapter.AdapterRowContext,[Adapter.ChannelState]) {
        let traversal = PlaybackSongTraversalPlanner.plan(module,startOrderIndex: 0,orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(module,traversalPlan: traversal,sampleRate: rate)
        var context = Adapter.AdapterRowContext(), states = [Adapter.ChannelState]()
        for (index,row) in traversal.rows.enumerated() {
            _ = Adapter.appendEvents(from: row.row,source: row.source,syntheticRow: row.syntheticRow,song: module,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow),timingPlan: timing,scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: index+1<traversal.rows.count ? traversal.rows[index+1].row : nil,context: &context)
            states.append(context.channelStates[0])
        }
        return (context,states)
    }
    private func assertPCM(_ a: [Float],_ b: [Float],file: StaticString = #filePath,line: UInt = #line) {
        XCTAssertEqual(a.count,b.count,file: file,line: line)
        XCTAssertLessThanOrEqual(zip(a,b).map { abs($0-$1) }.max() ?? 0,1e-7,file: file,line: line)
    }
}
