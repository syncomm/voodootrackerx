import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Independently authored XM controls for the characterized logical tremor/output contract.
final class TremorTests: XCTestCase {
    func testObservedDurationsMemoryAndReplacementInBothModesAndRates() {
        let cases: [(UInt8,[Int])] = [(0,[48,0,48,0]),(0x10,[48,48,0]),(1,[48,0,0]),
            (0x11,[48,48,0,0]),(0x21,[48,48,48,0,0]),(0x12,[48,48,0,0,0]),
            (0x02,[48,0,0,0]),(0x0F,[48]+Array(repeating:0,count:16)),
            (0xF0,Array(repeating:48,count:16)+[0]),(0xFF,Array(repeating:48,count:16)+Array(repeating:0,count:16)),
            (0x34,Array(repeating:48,count:4)+Array(repeating:0,count:5))]
        for linear in [true,false] { for rate in [44_100.0,48_000] {
            for (byte,cycle) in cases {
                let p = adapt(song([[c(29,byte,note:49,instrument:1)],[c(29)],[c()],[c(29)]],linear:linear,speed:31),rate)
                let calls = tremor(p)
                XCTAssertEqual(calls.count,90)
                for (i,u) in calls.enumerated() {
                    XCTAssertEqual(u.effectiveVolumeAfter,cycle[i % cycle.count])
                    if case let .txyTremor(parameter,_,_,phase,base) = u.command {
                        XCTAssertEqual(parameter,byte); XCTAssertEqual(base,48)
                        XCTAssertEqual(phase > 0,u.effectiveVolumeAfter == 48)
                    } else { XCTFail("Missing typed tremor") }
                    XCTAssertEqual(u.scheduledFrame,(u.syntheticRow*31+u.syntheticTick)*Int(rate/50))
                }
                XCTAssertTrue(p.diagnostics.deferredCellFields.isEmpty)
            }
            let p = adapt(song([[c(29,0x34,note:49,instrument:1)],[c(29,2)],[c(29)],[c(29,0x40)]],linear:linear,speed:3),rate)
            XCTAssertEqual(tremor(p).map(phase),[4,3,2,1,-3,-2,-1,5])
            XCTAssertEqual(p.xmChannelRows.map { $0.controls.tremorMemory },[0,0x34,2,2])
            let cold = adapt(song([[c(29,0x21)],[c(29)]],linear:linear),rate)
            XCTAssertTrue(cold.pattern.events.isEmpty)
            XCTAssertTrue(tremor(cold).allSatisfy { !$0.activeVoiceUpdated })
        } }
        XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticAdapter.ChannelState>.stride,1152)
        XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticVoiceStateUpdateDiagnostic>.stride,520)
    }

    func testSpeedOneDoesNotSeedOrReplaceAndLastFxxOwnsTheRow() {
        for first in [true,false] { for linear in [true,false] { for rate in [44_100.0,48_000] {
            let bytes:[UInt8] = [0x34,0,0x21,0x12,0]
            let speeds:[UInt8] = [1,3,6,1,3]
            let rows = zip(bytes,speeds).enumerated().map { i,pair -> [PlaybackCell] in
                let t = c(29,pair.0,note:i==0 ? 49:0,instrument:i==0 ? 1:0)
                return first ? [c(15,pair.1),t] : [t,c(15,pair.1)]
            }
            let p = adapt(song(rows,linear:linear),rate)
            let ch=first ? 1:0
            XCTAssertEqual(p.xmChannelRows.filter { $0.channelIndex==ch }.map { $0.controls.tremorMemory },[0,0,0,0x21,0x21])
            XCTAssertEqual(tremor(p).map(\.syntheticRow),[1,1,2,2,2,2,2,4,4])
            let conflict = adapt(song([[c(15,3),c(29,0x34,note:49,instrument:1),c(15,1)],
                [c(15,1),c(29),c(15,3)]]),rate)
            XCTAssertEqual(tremor(conflict).map(\.effectiveVolumeAfter),[48,0])
        } } }
    }

    func testColumnPrecedenceHeldOutputAndQuickFinalOnlyDelivery() throws {
        for linear in [true,false] { for rate in [44_100.0,48_000] {
            let s=song([[c(note:49,instrument:1)],[c(29,0x11,volume:0x61)],[c()],
                        [c(12,32)],[c(29)],[c(10)],[c(7,0x48)],[c(29)]],linear:linear)
            let p=adapt(s,rate), writes=tremor(p).filter { $0.syntheticRow==1 }
            XCTAssertEqual(writes.map(\.effectiveVolumeAfter),[47,46,0,0,43])
            XCTAssertEqual(writes.map { u -> Int in if case let .txyTremor(_,_,_,_,base)=u.command {return base};return -1 },[47,46,45,44,43])
            XCTAssertEqual(p.xmChannelRows.first { $0.syntheticRow==2 }?.controls.outputChannelVolume,43)
            XCTAssertEqual(p.xmChannelRows.first { $0.syntheticRow==3 }?.controls.outputChannelVolume,32)
            let runtime=RuntimeCMixerAdapterEventPlan.make(song:s,sampleRate:rate)
            XCTAssertEqual(runtime.plan,p)
            XCTAssertFalse(runtime.events.contains { $0.effectType==29 && $0.categories.contains("gain_pan_update") })
            let quick=p.xmAudibleTimeline!.updates.filter { $0.source.rowIndex==1 }
            XCTAssertTrue(quick.allSatisfy { $0.durationFrames==Int(rate*0.005) })
            let request=PlaybackSongOfflineRenderRequest(song:s,config:.init(sampleRate:rate),rows:8)
            let full=PlaybackSongOfflineRenderer().render(request)
            let renderer=PlaybackSongOfflineRenderer(preparedPlan:p)
            XCTAssertEqual(full.block.interleavedPCM,renderer.renderWindowed(request,windowRows:1).block.interleavedPCM)
            #if DEBUG
            XCTAssertEqual(full.block.interleavedPCM,renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries:[1,7*Int(rate/50),7*Int(rate/50)+Int(rate*0.0025),9*Int(rate/50)+1]).block.interleavedPCM)
            #endif
        } }
    }

    func testGlobalRefreshAndMovingEnvelopeKeepQuickIntent() {
        for rate in [44_100.0,48_000] {
            let rows=[[c(note:49,instrument:1),c(note:49,instrument:1),c(note:49,instrument:1),c(note:49,instrument:1)],
                [c(16,32),c(29,0x11),c(16,64),c(29,0x11)],
                [c(17,1),c(29),c(17,16),c(29)]]
            let p=adapt(song(rows),rate)
            let targets=p.xmAudibleTimeline!.updates
            let repaired=targets.first { $0.channelIndex==1 && $0.source.rowIndex==1 && $0.tick==1 }
            XCTAssertEqual(repaired?.amplitude,0.75)
            XCTAssertEqual(repaired?.durationFrames,Int(rate*0.005))
            XCTAssertEqual(targets.first { $0.channelIndex==1 && $0.source.rowIndex==2 && $0.tick==1 }?.amplitude,0.73828125)
            XCTAssertEqual(targets.first { $0.channelIndex==3 && $0.source.rowIndex==2 && $0.tick==1 }?.amplitude,nil) // unchanged .75
            XCTAssertTrue(p.diagnostics.voiceStateUpdates.filter { $0.command.isTremorPublication }.allSatisfy { $0.physicalGainChange==nil })
            let moving=adapt(song([[c(29,0x21,note:49,instrument:1)],[c(29,note:97)],[c(29)]],envelope:true),rate)
            XCTAssertEqual(moving.xmAudibleTimeline!.updates.prefix(4).map(\.durationFrames),[0,Int(rate*0.005),Int(rate*0.005),Int(rate*0.005)])
            XCTAssertTrue(moving.xmAudibleTimeline!.updates.contains { $0.amplitude==0 })
        }
    }

    func testResetAndRestartDomainsIncludingChildlessE9AndDelay() {
        for empty in [false,true] { for linear in [true,false] { for rate in [44_100.0,48_000] {
            let note:UInt8=empty ? 51:49
            let rows=[Array(repeating:c(29,0x21,note:note,instrument:1),count:4),Array(repeating:c(29),count:4),
                [c(14,0x92),c(27,0x92),c(14,0x90),c(14,0xD1,note:note,instrument:1)],Array(repeating:c(29),count:4)]
            let p=adapt(song(rows,linear:linear,speed:3),rate)
            XCTAssertEqual(tremor(p).filter { $0.syntheticRow==3 && $0.syntheticTick==1 }.map(phase),[3,-1,-1,3])
            if empty { XCTAssertTrue(p.pattern.events.isEmpty) }
            let resets=adapt(song([[c(29,0x21,note:49,instrument:1)],[c(29)],
                [c(29,instrument:1)],[c(29,note:49)],[c(14,0xC0)],[c(29)],[c(12,32)],[c(29)]],linear:linear,speed:3),rate)
            XCTAssertEqual(tremor(resets).filter { $0.syntheticRow==2 }.map(phase),[3,2])
            XCTAssertEqual(tremor(resets).filter { $0.syntheticRow==3 }.map(phase),[1,-2])
            XCTAssertTrue(tremor(resets).filter { $0.syntheticRow==5 }.allSatisfy { $0.effectiveVolumeAfter==0 })
            XCTAssertEqual(resets.pattern.events.count,2)
        } } }
    }

    func testDenseCapacityAndSilentVariantRemainLinearAndSparse() throws {
        for volume:Float in [0,0.75] {
            let rows=(0..<64).map { row in (0..<32).map { _ in c(29,note:row==0 ? 49:0,instrument:row==0 ? 1:0) } }
            let s=song(rows,volume:volume),p=adapt(s,48_000)
            XCTAssertEqual(tremor(p).count,10_240)
            XCTAssertEqual(p.pattern.events.count,32)
            let output=try XCTUnwrap(p.xmAudibleTimeline?.updates)
            XCTAssertEqual(output.count,volume==0 ? 32:10_240)
            let runtime=RuntimeCMixerAdapterEventPlan.make(song:s,sampleRate:48_000)
            XCTAssertEqual(runtime.events.count,32+output.count)
            XCTAssertEqual(Set(runtime.events.map(\.id)).count,runtime.events.count)
            XCTAssertFalse(runtime.events.contains { $0.categories.contains("gain_pan_update") })
            let request=PlaybackSongOfflineRenderRequest(song:s,config:.init(sampleRate:48_000),rows:64)
            let renderer=PlaybackSongOfflineRenderer(preparedPlan:p),whole=renderer.render(request)
            XCTAssertEqual(whole.block.interleavedPCM,renderer.renderWindowed(request,windowRows:64).block.interleavedPCM)
            XCTAssertTrue(whole.scheduledVoiceRejectionReasons.allSatisfy { $0 == nil })
            XCTAssertTrue(p.diagnostics.voiceStateUpdates.allSatisfy { $0.physicalGainChange == nil })
        }
    }

    private func phase(_ u:PlaybackSongSyntheticVoiceStateUpdateDiagnostic) -> Int8 {
        if case let .txyTremor(_,_,_,after,_)=u.command {return after};return 0
    }
    private func tremor(_ p:PlaybackSongSyntheticPlan) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        p.diagnostics.voiceStateUpdates.filter { if case .txyTremor=$0.command {return true};return false }
    }
    func adapt(_ s:PlaybackSong,_ rate:Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(s,startOrderIndex:0,orderCount:s.orders.count,sampleRate:rate)
    }
    private func c(_ f:UInt8=0,_ p:UInt8=0,note:UInt8=0,instrument:UInt8=0,volume:UInt8=0) -> PlaybackCell {
        .init(note:note,instrument:instrument,volumeColumn:volume,effectType:f,effectParam:p)
    }
    private func song(_ rows:[[PlaybackCell]],linear:Bool=true,speed:Int=6,volume:Float=0.75,envelope:Bool=false) -> PlaybackSong {
        let sample=PlaybackSample(instrumentIndex:1,sampleIndex:0,pcm:Array(repeating:0.25,count:256),volume:volume,
            panning:128,relativeNote:0,finetune:0,baseSampleRate:8363,loopStart:0,loopLength:256,loopType:1)
        var map=Array(repeating:0,count:96);map[50]=1
        let ve=PlaybackVolumeEnvelope(enabled:envelope,points:[.init(tick:0,value:64),.init(tick:5,value:16),.init(tick:32,value:48)],
            sustainPointIndex:nil,loopStartPointIndex:nil,loopEndPointIndex:nil,typeFlags:envelope ? 1:0,fadeout:512)
        return PlaybackSong(title:"Original tremor control",orders:[.init(orderIndex:0,patternIndex:0)],
            patternsByIndex:[0:.init(index:0,rows:rows.enumerated().map { .init(index:$0.offset,cells:$0.element) })],
            instrumentsByIndex:[1:.init(index:1,samples:[sample],volumeEnvelope:ve,panningEnvelope:.disabled,noteSampleMap:map)],
            restartOrderIndex:0,endBehavior:.stopAtEnd,initialTiming:.init(speed:speed,bpm:125),usesLinearFrequencyTable:linear,
            xmSampleSlotProvenanceByInstrument:[1:[.init(sampleIndex:1,decodedPayloadLength:0,isCanonicalEmptySlotHeader:false,
                volume:48,panning:128,finetune:0,relativeNote:0)]])
    }
}
