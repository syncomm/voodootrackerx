import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class TonePortamentoRetainedSourceResetTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0,48_000]
    private var surfaces: [(Bool,UInt8,UInt8,UInt8)] { [(true,3,4,0),(false,3,4,0),(true,3,0,0),(false,3,0,0),(true,5,4,0),(true,0,0,0xF4)] }

    func testRetainedHeaderOwnershipAcrossSurfacesRoutesSpeedsAndFxxChannelOrder() throws {
        for rate in rates {
            for (linear,fx,param,volume) in surfaces {
                for speed in [1,2,3,6] {
                    for channel in [0,1] {
                        for route in 0...2 {
                            func lane(_ cell: PlaybackCell) -> [PlaybackCell] { var r = [c(),c()]; r[channel] = cell; return r }
                            var reset = lane(c(fx,param,note: route == 0 ? 53 : 61,instrument: route == 2 ? 2 : 1,volume: volume))
                            reset[1-channel] = c(15,UInt8(speed))
                            let module = song([lane(c(12,64,note: 49,instrument: 1)),lane(c(3,4,note: 53,volume: 0xCF)),reset],linear: linear)
                            let (context,states) = inspect(module,rate)
                            let before = states[1][channel], after = states[2][channel]
                            XCTAssertEqual(before.baseChannelVolume,64); XCTAssertEqual(before.panningValue,240)
                            XCTAssertEqual(after.baseChannelVolume,fx == 5 ? max(0,32-4*(speed-1)) : 32)
                            XCTAssertEqual(after.outputChannelVolume,after.baseChannelVolume)
                            XCTAssertEqual(after.panningValue,96)
                            XCTAssertEqual(after.triggeredSampleDefaultVolume,32); XCTAssertEqual(after.triggeredSampleDefaultPan,96)
                            XCTAssertEqual(after.activeInstrumentIndex,1); XCTAssertEqual(after.activeSampleIndex,0)
                            XCTAssertEqual(after.semanticInstrumentIndex,1); XCTAssertEqual(after.activeSampleVolume,0.5)
                            XCTAssertEqual(after.carriedInstrumentIndex,route == 2 ? 2 : 1)
                            XCTAssertEqual(after.activeEventIndex,before.activeEventIndex)
                            XCTAssertEqual(context.events.count,1)
                            let resetEvent = try XCTUnwrap(context.playbackStateEvents.first)
                            XCTAssertEqual(resetEvent.activeEventIndex,0); XCTAssertEqual(resetEvent.scheduledFrame,12*Int(rate/50))
                            let d = try XCTUnwrap(context.tonePortamentoEffects.last)
                            XCTAssertTrue(d.envelopeReset && d.envelopeResetModeled)
                            XCTAssertFalse(d.noteTriggerEventCreated || d.voiceReplacement || d.samplePositionReset)
                            XCTAssertEqual(d.instrumentIndexAfter,1); XCTAssertEqual(d.sampleSelectedAfter,0)
                            XCTAssertEqual(d.portamentoSpeed,volume == 0 ? 4 : 64)
                            XCTAssertEqual(d.stepUpdates.map(\.scheduledFrame),(0..<d.stepUpdates.count).map { (13+$0)*Int(rate/50) })
                            if speed == 1 { XCTAssertTrue(d.stepUpdates.isEmpty) }
                            if fx == 5 {
                                XCTAssertEqual(after.volumeSlideMemory?.parameter,speed > 1 ? 4 : nil)
                            } else { XCTAssertEqual(after.volumeSlideMemory,before.volumeSlideMemory) }
                        }
                    }
                }
            }
        }
    }

    func testResetReconstructsEnvelopeSegmentsKeyFadeoutAndExistingModulationState() throws {
        for rate in rates {
            for (linear,fx,param,volume) in surfaces {
                for preparation in [c(0x15,5),c(note: 97),c(4,0x48),c(7,0x48)] {
                    let module = song([[c(12,64,note: 49,instrument: 1)],[preparation],
                        [c(fx,param,note: 61,instrument: 2,volume: volume)],[c(note: 97)],
                        [c(fx,param,note: 61,instrument: 2,volume: volume)]],linear: linear,envelope: true)
                    let plan = Adapter.adapt(module,orderIndex: 0,sampleRate: rate)
                    let updates = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
                    for row in [2,4] {
                        let reset = updates.filter { $0.source.rowIndex == row }
                        XCTAssertEqual(reset.map { $0.state.volumeTick },[0,1,2,3,3,3])
                        XCTAssertEqual(reset.map { $0.state.panTick },[0,1,2,3,4,5])
                        XCTAssertEqual(reset.map { $0.state.volumeValue },[1,0.9375,0.875,0.8125,0.8125,0.8125])
                        XCTAssertEqual(reset.map { $0.state.panValue },[0.5,0.53125,0.5625,0.59375,0.625,0.65625])
                        XCTAssertTrue(reset.allSatisfy { $0.state.keyOn && $0.state.fadeoutAccumulator == 32768 })
                    }
                    XCTAssertEqual(updates.filter { $0.source.rowIndex == 3 }.map { $0.state.fadeoutAccumulator },[32512,32256,32000,31744,31488,31232])
                    XCTAssertEqual(plan.pattern.events.first?.keyOffFrame,preparation.note == 97 ? 6*Int(rate/50) : 18*Int(rate/50))
                    XCTAssertEqual(plan.pattern.events.count,1)
                    let (_,states) = inspect(module,rate)
                    XCTAssertEqual(states[2][0].vibratoPhase,0); XCTAssertEqual(states[2][0].tremolo.phase,0)
                    XCTAssertEqual(states[2][0].vibratoSpeed,states[1][0].vibratoSpeed)
                    XCTAssertEqual(states[2][0].tremolo.speed,states[1][0].tremolo.speed)
                }
            }
        }
    }

    func testExplicitWritersFollowResetAndNoSpeedStillResets() throws {
        for rate in rates {
            for (linear,fx,param,volume) in surfaces {
                let writers: [(UInt8,UInt8,UInt8,Int,Double)] = volume == 0
                    ? [(fx,param,0x25,21,96),(fx,param,0x93,35,96),(fx,param,0xCF,32,240)]
                    : [(12,21,volume,21,96),(8,224,volume,32,224)]
                for (effect,byte,column,base,pan) in writers {
                    let (context,states) = inspect(song([[c(12,64,note: 49,instrument: 1)],
                        [c(3,4,note: 53,volume: 0xCF)],[c(effect,byte,note: 61,instrument: 2,volume: column)]],linear: linear),rate)
                    XCTAssertEqual(states[2][0].baseChannelVolume,fx == 5 ? max(0,base-20) : base)
                    XCTAssertEqual(states[2][0].panningValue,pan)
                    let reset = try XCTUnwrap(context.voiceStateUpdates.first { $0.syntheticRow == 2 && $0.commandSource == .instrumentState })
                    XCTAssertEqual(reset.effectiveVolumeAfter,32); XCTAssertEqual(reset.effectivePanAfter,-0.25)
                }
            }
            let (context,states) = inspect(song([[c(12,64,note: 49,instrument: 1)],[c(3,note: 61,instrument: 2)]]),rate)
            XCTAssertEqual(states[1][0].baseChannelVolume,32)
            XCTAssertEqual(context.tonePortamentoEffects.last?.status,.noSpeed)
            XCTAssertEqual(context.tonePortamentoEffects.last?.envelopeReset,true)
        }
    }

    func testDisabledEnvelopeClocksKeepTheirCarriedInactiveState() throws {
        for rate in rates {
            let module = song([[c(note: 49,instrument: 1)],[c(3,4,note: 61,instrument: 2)],
                [c(note: 61)],[c(3,4,note: 53,instrument: 1)]],envelope: true)
            let history = try XCTUnwrap(Adapter.adapt(module,orderIndex: 0,sampleRate: rate).xmEnvelopeTimeline?.updatesByEvent[1])
            let before = try XCTUnwrap(history.last { $0.source.rowIndex == 2 })
            let after = try XCTUnwrap(history.first { $0.source.rowIndex == 3 })
            XCTAssertGreaterThan(before.state.volumeTick,0); XCTAssertGreaterThan(before.state.panTick,0)
            XCTAssertEqual(after.state.volumeTick,before.state.volumeTick)
            XCTAssertEqual(after.state.panTick,before.state.panTick)
            XCTAssertEqual(after.state.volumeValue,1); XCTAssertEqual(after.state.panValue,0.5)
        }
    }

    func testSoundingMetadataGainAndLaterNoteOnlyUseIndependentCarriedOwner() throws {
        for rate in rates {
            let module = song([[c(12,64,note: 49,instrument: 1)],[c(3,4,note: 61,instrument: 2)],
                [c()],[c(note: 61)]],speed: 3)
            let (context,states) = inspect(module,rate)
            XCTAssertEqual(states[1][0].activeInstrumentIndex,1); XCTAssertEqual(states[1][0].activeSampleVolume,0.5)
            XCTAssertEqual(states[1][0].carriedInstrumentIndex,2)
            XCTAssertEqual(context.events.count,2)
            XCTAssertEqual(context.eventMappings.map(\.instrumentIndex),[1,2])
            XCTAssertEqual(context.events.last?.gain,0.5) // Header 20 is not an extra song multiplier.
            let full = PlaybackSongOfflineRenderer().render(.init(song: module,config: .init(sampleRate: rate,channelCount: 1),rows: 4))
            XCTAssertEqual(full.block.interleavedPCM[6*Int(rate/50)+100],0.5/32,accuracy: 1e-7)
        }
    }

    func testTargetPitchUsesRoutedHeaderWithoutChangingSoundingPitchMetadata() throws {
        for rate in rates {
            for (linear,fx,param,volume) in surfaces {
                for instrument: UInt8 in [1,2] {
                    let module = song([[c(12,64,note: 49,instrument: 1)],
                        [c(3,4,note: 53)],
                        [c(fx,param,note: 61,instrument: instrument,volume: volume)]],
                        linear: linear,targetRelativeNote: 12,targetFinetune: 64)
                    let (context,states) = inspect(module,rate)
                    let diagnostic = try XCTUnwrap(context.tonePortamentoEffects.last)
                    let state = states[2][0]
                    XCTAssertEqual(state.activeSampleRelativeNote,0)
                    XCTAssertEqual(state.activeSampleFinetune,0)
                    XCTAssertEqual(state.activeInstrumentIndex,1)
                    XCTAssertEqual(state.activeSampleIndex,0)
                    XCTAssertEqual(state.carriedInstrumentIndex,Int(instrument))
                    if linear {
                        let target = try XCTUnwrap(Adapter.linearPitchTarget(note: 61,relativeNote: 12,
                            finetune: 64,baseSampleRate: 8363,outputSampleRate: rate))
                        XCTAssertEqual(diagnostic.targetLinearPeriod,target.linearPeriod)
                        XCTAssertEqual(diagnostic.targetPlaybackStep,target.playbackStep)
                    } else {
                        let target = try XCTUnwrap(Adapter.amigaPitchTarget(note: 61,relativeNote: 12,
                            finetune: 64,baseSampleRate: 8363,outputSampleRate: rate))
                        XCTAssertEqual(diagnostic.targetAmigaPeriod,target.amigaPeriod)
                        XCTAssertEqual(diagnostic.targetPlaybackStep,target.playbackStep)
                    }
                }
            }
        }
    }

    func testNoteOnlyEmptyInstrumentOnlyColdCompletedAndUnavailableExclusions() throws {
        for rate in rates {
            for cell in [c(3,4,note: 61),c(5,4,note: 61),c(note: 61,volume: 0xF4),c(3)] {
                let (context,states) = inspect(song([[c(12,21,note: 49,instrument: 1)],[cell]]),rate)
                XCTAssertTrue(context.playbackStateEvents.isEmpty)
                XCTAssertEqual(states[1][0].baseChannelVolume,cell.effectType == 5 ? 1 : 21)
            }
            let (instrumentOnly,_) = inspect(song([[c(12,21,note: 49,instrument: 1)],[c(instrument: 2)]]),rate)
            XCTAssertEqual(instrumentOnly.playbackStateEvents.count,1)
            for cell in [c(3,4,note: 61,instrument: 99),c(3,4,note: 61,instrument: 1)] {
                let (context,states) = inspect(song([[c(12,64,note: 49,instrument: 1)],[cell]],unavailable: true),rate)
                XCTAssertTrue(context.playbackStateEvents.isEmpty)
                XCTAssertEqual(states[1][0].baseChannelVolume,64); XCTAssertEqual(context.events.count,1)
            }
            let cold = inspect(song([[c(3,4,note: 61,instrument: 2)]]),rate)
            XCTAssertTrue(cold.0.events.isEmpty && cold.0.playbackStateEvents.isEmpty)
            XCTAssertEqual(cold.1[0][0].triggeredSampleDefaultVolume,0)
            XCTAssertNil(cold.1[0][0].activeSampleVolume)
            let completed = song([[c(note: 49,instrument: 1)],[c(3,4,note: 61,instrument: 2)]],completed: true)
            let block = PlaybackSongOfflineRenderer().render(.init(song: completed,config: .init(sampleRate: rate,channelCount: 1),rows: 2))
            XCTAssertEqual(block.plan.pattern.events.count,1)
            XCTAssertTrue(block.block.interleavedPCM[(6*Int(rate/50))...].allSatisfy { $0 == 0 })
        }
    }

    func testPublicFixtureWholeWindowRuntimePlansAndResetSplits() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/tone-portamento-retained-source-reset.xm")
        let parsed = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
        for linear in [true,false] {
            let module = linear ? parsed : amigaProjection(parsed)
            for rate in rates {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module,sampleRate: rate)
                let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
                let renderer = PlaybackSongOfflineRenderer(), whole = renderer.render(request)
                XCTAssertEqual(whole.plan,runtime.plan)
                for rows in [1,3,5] { assertPCM(whole.block.interleavedPCM,renderer.renderWindowed(request,windowRows: rows).block.interleavedPCM) }
                XCTAssertFalse(whole.diagnostics.tonePortamentoEffects.contains { $0.status == .unsupportedFrequencyTable })
                XCTAssertFalse(whole.plan.playbackStateEvents.contains { $0.channelIndex == 4 })
#if DEBUG
                let timing = PlaybackSongFxxTimingPlanner.plan(module,startOrderIndex: 0,orderCount: 1,sampleRate: rate)
                let frames = [timing.frameFor(row: 2),timing.frameFor(row: 2,tick: 1),timing.frameFor(row: 3)]
                for offset in [-1,0,1] { assertPCM(whole.block.interleavedPCM,renderer.renderWindowedAtFrameBoundariesForTesting(request,boundaries: frames.map { $0+offset }).block.interleavedPCM) }
#endif
            }
        }
    }

    private func amigaProjection(_ module: PlaybackSong) -> PlaybackSong {
        let patterns = module.patternsByIndex.mapValues { pattern in
            PlaybackPattern(index: pattern.index,rows: pattern.rows.map { row in
                PlaybackRow(index: row.index,cells: row.cells.map { cell in
                    cell.effectType == 5 || cell.volumeColumn >= 0xF0 ? c() : cell
                })
            })
        }
        return PlaybackSong(title: module.title,orders: module.orders,patternsByIndex: patterns,instrumentsByIndex: module.instrumentsByIndex,
            restartOrderIndex: module.restartOrderIndex,endBehavior: module.endBehavior,initialTiming: module.initialTiming,
            usesLinearFrequencyTable: false,xmSampleSlotProvenanceByInstrument: module.xmSampleSlotProvenanceByInstrument)
    }
    private func c(_ fx: UInt8 = 0, _ param: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: instrument,volumeColumn: volume,effectType: fx,effectParam: param)
    }
    private func song(_ rows: [[PlaybackCell]], linear: Bool = true, speed: Int = 6, envelope: Bool = false, completed: Bool = false, unavailable: Bool = false,
                      targetRelativeNote: Int = 0, targetFinetune: Int = 0) -> PlaybackSong {
        let source = PlaybackSample(instrumentIndex: 1,sampleIndex: 0,pcm: Array(repeating: 1/32,count: 32),volume: 0.5,panning: 96,
            relativeNote: 0,finetune: 0,baseSampleRate: 8363,loopStart: 0,loopLength: completed ? 0 : 32,loopType: completed ? 0 : 1)
        let target = PlaybackSample(instrumentIndex: 1,sampleIndex: 1,pcm: Array(repeating: 1/8,count: 32),volume: 20/64,panning: 192,
            relativeNote: targetRelativeNote,finetune: targetFinetune,baseSampleRate: 8363,loopStart: 0,loopLength: 32,loopType: 1)
        let other = PlaybackSample(instrumentIndex: 2,sampleIndex: 0,pcm: target.pcm,volume: target.volume,panning: 192,
            relativeNote: targetRelativeNote,finetune: targetFinetune,baseSampleRate: 8363,loopStart: 0,loopLength: 32,loopType: 1)
        let volumeEnvelope = envelope ? PlaybackVolumeEnvelope(enabled: true,
            points: [.init(tick: 0,value: 64),.init(tick: 3,value: 52),.init(tick: 6,value: 40)],
            sustainPointIndex: 1,loopStartPointIndex: 0,loopEndPointIndex: 2,typeFlags: 7,fadeout: 256) : .disabled
        let panEnvelope = envelope ? PlaybackPanningEnvelope(enabled: true,
            points: [.init(tick: 0,value: 32),.init(tick: 3,value: 38),.init(tick: 6,value: 44)],
            sustainPointIndex: nil,loopStartPointIndex: 0,loopEndPointIndex: 2,typeFlags: 5) : .disabled
        return PlaybackSong(title: "Retained tone reset",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: [1: .init(index: 1,samples: unavailable ? [source] : [source,target],volumeEnvelope: volumeEnvelope,panningEnvelope: panEnvelope,noteSampleMap: (0..<96).map { $0 < 54 ? 0 : 1 }),
                2: .init(index: 2,samples: [other],noteSampleMap: Array(repeating: 0,count: 96))],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: speed,bpm: 125),usesLinearFrequencyTable: linear)
    }
    private func inspect(_ module: PlaybackSong, _ rate: Double) -> (Adapter.AdapterRowContext,[[Adapter.ChannelState]]) {
        let traversal = PlaybackSongTraversalPlanner.plan(module,startOrderIndex: 0,orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(module,traversalPlan: traversal,sampleRate: rate)
        var context = Adapter.AdapterRowContext(), states = [[Adapter.ChannelState]]()
        for (index,row) in traversal.rows.enumerated() {
            _ = Adapter.appendEvents(from: row.row,source: row.source,syntheticRow: row.syntheticRow,song: module,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow),timingPlan: timing,scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: index+1<traversal.rows.count ? traversal.rows[index+1].row : nil,context: &context)
            states.append(context.channelStates)
        }
        return (context,states)
    }
    private func assertPCM(_ a: [Float], _ b: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count,b.count,file: file,line: line)
        XCTAssertLessThanOrEqual(zip(a,b).map { abs($0-$1) }.max() ?? 0,1e-7,file: file,line: line)
    }
}
