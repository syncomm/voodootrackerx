import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class PanningSlideTests: XCTestCase {
    func testObservedPriorityMemoryAndClampsInBothModesAndRates() {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] { for pan: UInt8 in [0, 1, 128, 254, 255] {
                for (parameter, delta): (UInt8, Int) in [(1,-1), (16,1), (17,1), (52,3)] {
                    let plan = adapt([c(25, parameter, note: 49, instrument: 1), c(25), c()],
                        rate, linear: linear, speed: speed, pan: pan)
                    let first = slides(plan).filter { $0.syntheticRow == 0 }
                    let expected = (1..<speed).map { Double(min(255, max(0, Int(pan) + $0 * delta))) }
                    XCTAssertEqual(first.map(\.channelPanningValueAfter), expected)
                    XCTAssertEqual(first.map(\.syntheticTick), Array(1..<speed))
                    XCTAssertEqual(first.map(\.scheduledFrame), (1..<speed).map { $0 * Int(rate / 50) })
                    XCTAssertEqual(plan.xmChannelRows.map { $0.controls.panningSlideMemory },
                        speed == 1 ? [0,0,0] : [0,parameter,parameter])
                    XCTAssertTrue(slides(plan).filter { $0.syntheticRow == 1 }.allSatisfy(\.effectMemoryReused))
                    XCTAssertFalse(plan.diagnostics.deferredCellFields.contains { $0.field == .effect })
                }
            } }
            let replaced = adapt([c(25,52,note:49,instrument:1),c(25),c(25,17),c(25),c(25,1),c(25),c()], rate, linear: linear)
            XCTAssertEqual(replaced.xmChannelRows.map { $0.controls.panningSlideMemory }, [0,52,52,17,17,1,1])
            XCTAssertEqual(replaced.xmChannelRows.map { $0.controls.panningValue }, [128,143,158,163,168,163,158])
            for initial: UInt8 in [0,128,255] {
                let cold = adapt([c(25,note:49,instrument:1),c(25)], rate, linear:linear, pan:initial)
                XCTAssertTrue(slides(cold).isEmpty)
                XCTAssertEqual(cold.xmAudibleTimeline?.updates.count, 1)
                XCTAssertEqual(cold.pattern.events[0].pan, PlaybackSamplePanningPolicy.plannedPan(initial))
            }
            let clamped = adapt([c(25,16,note:49,instrument:1),c(25)], rate, linear:linear, pan:255)
            XCTAssertEqual(slides(clamped).count, 10)
            XCTAssertEqual(clamped.xmAudibleTimeline?.updates.count, 1)
        } }
        XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticAdapter.ChannelState>.stride, 1152)
        XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticVoiceStateUpdateDiagnostic>.stride, 520)
    }

    func testSameRowSpeedAndChannelIndependenceDoNotAdmitSpeedOneMemory() {
        for first in [true, false] { for linear in [true, false] { for rate in [44_100.0,48_000] {
            let commands = [c(25,1,note:49,instrument:1),c(25),c(25,52),c(25,1),c(25)]
            let speeds: [UInt8] = [1,3,6,1,3]
            let rows = zip(commands,speeds).map { first ? [c(15,$1),$0] : [$0,c(15,$1)] }
            let plan = adapt(song(rows,linear:linear),rate)
            let channel = first ? 1 : 0
            XCTAssertEqual(plan.xmChannelRows.filter { $0.channelIndex == channel }.map { $0.controls.panningSlideMemory }, [0,0,0,52,52])
            XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 4 }.map(\.channelPanningValueAfter), [146,149])
            XCTAssertTrue(slides(plan).filter { $0.syntheticRow < 2 || $0.syntheticRow == 3 }.isEmpty)
            let independent = adapt(song([[c(25,1,note:49,instrument:1),c(25,52,note:49,instrument:1)], [c(25),c(25)]]),rate)
            XCTAssertEqual(independent.xmChannelRows.suffix(2).map { $0.controls.panningSlideMemory }, [1,52])
        } } }
    }

    func testColumnThenPUsesEachIntermediateClampAndStaticWriterPrecedence() {
        for rate in [44_100.0,48_000] {
            for (pan,column,parameter,expected): (UInt8,UInt8,UInt8,[Double]) in
                [(0,0xD1,16,[0,1]),(255,0xE1,1,[255,254])] {
                let plan = adapt([c(25,parameter,note:49,instrument:1,volume:column)],rate,pan:pan)
                let writes = plan.diagnostics.voiceStateUpdates.filter { $0.syntheticTick > 0 }
                XCTAssertEqual(writes.map(\.channelPanningValueAfter), Array(repeating: expected,count:5).flatMap { $0 })
                for tick in 1..<6 {
                    let pair = writes.filter { $0.syntheticTick == tick }
                    XCTAssertEqual(pair[0].commandSource, .volumeColumn)
                    XCTAssertEqual(pair[1].commandSource, .effectColumn)
                    if case let .pxyPanningSlide(byte,before) = pair[1].command {
                        XCTAssertEqual(byte,parameter); XCTAssertEqual(before,Double(pan))
                    } else { XCTFail("Missing typed P writer") }
                }
            }
            let plan = adapt([c(25,16,note:49,instrument:1,volume:0xC4),c(8,64,volume:0xCF),c(25),
                c(25,volume:0xD0),c(25,volume:0xE0),c()],rate)
            XCTAssertEqual(plan.xmChannelRows.map { $0.controls.panningValue }, [64,64,64,69,1,6])
            XCTAssertEqual(slides(plan).filter { $0.syntheticRow == 3 }.map(\.channelPanningValueAfter), [1,1,1,1,1])
        }
    }

    func testSourceOwnershipResetCarrySilentCompletionAndColdInitialization() throws {
        for linear in [true,false] { for rate in [44_100.0,48_000] {
            let plan = adapt([c(25,52,note:49,instrument:1),c(25,instrument:1),c(25,note:50),
                c(25,note:97),c(25,note:49,instrument:1)],rate,linear:linear)
            XCTAssertEqual(plan.pattern.events.count,3)
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex),[0,1,0])
            XCTAssertEqual(plan.xmChannelRows.map { $0.controls.panningValue },[128,128,143,158,128])
            XCTAssertTrue(plan.xmChannelRows.dropFirst().allSatisfy { $0.controls.panningSlideMemory == 52 })
            XCTAssertEqual(plan.pattern.events[1].initialSourceFrame,0)
            for finite in [false,true] {
                let route = adapt([c(note:finite ? 49 : 51,instrument:1),c(25,52),c(25),c(note:49)],
                    rate,linear:linear,finite:finite)
                XCTAssertEqual(route.pattern.events.count,finite ? 2 : 1)
                XCTAssertEqual(route.xmChannelRows.last?.controls.panningValue,finite ? 158 : 94)
                if !finite { XCTAssertTrue(slides(route).allSatisfy { !$0.activeVoiceUpdated }) }
            }
            let silent = adapt([c(25,52,note:49,instrument:1),c(25)],rate,linear:linear,volume:0)
            XCTAssertEqual(silent.pattern.events.count,1)
            XCTAssertTrue(slides(silent).allSatisfy(\.activeVoiceUpdated))
            XCTAssertTrue(silent.xmAudibleTimeline!.updates.allSatisfy { $0.amplitude == 0 })
            let cold = adapt([c(25),c(25,52),c(25)],rate,linear:linear)
            XCTAssertTrue(cold.pattern.events.isEmpty)
            XCTAssertEqual(cold.xmChannelRows.map { $0.controls.panningValue },[127.5,127.5,142.5])
            XCTAssertTrue(cold.xmAudibleTimeline?.updates.isEmpty ?? true)
        } }
    }

    func testExistingEnvelopeProjectionPositionAndHeldGlobalScalar() throws {
        for rate in [44_100.0,48_000] { for value in [16,32,48] {
            let envelope = PlaybackPanningEnvelope(enabled:true,points:[.init(tick:0,value:value),.init(tick:64,value:value)],
                sustainPointIndex:nil,loopStartPointIndex:nil,loopEndPointIndex:nil,typeFlags:1)
            let plan = adapt([c(25,1,note:49,instrument:1),c(21,8),c(25)],rate,envelope:envelope)
            let semantics = try XCTUnwrap(plan.xmEnvelopeTimeline?.updates)
            XCTAssertEqual(semantics.prefix(6).map(\.channelPanningValue),[128,127,126,125,124,123])
            XCTAssertEqual(semantics[6].state.panTick,8)
            let bytes = value == 16 ? [64,63,63,62,62,61] : value == 32 ? [128,127,126,125,124,123] : [192,190,189,187,186,184]
            for (tick,byte) in bytes.enumerated() {
                let stored = Int(semantics[tick].channelPanningValue)
                let baseline: Float = tick == 0 ? 0 : PlaybackSongVolumeColumnDecoder.audioPan(forXMValue:stored)
                let expected = baseline + PlaybackSamplePanningPolicy.plannedPan(byte) - PlaybackSamplePanningPolicy.plannedPan(stored)
                XCTAssertEqual(plan.xmAudibleTimeline!.updates[tick].pan,expected,accuracy:1e-7)
            }
        } }
        let rows = [Array(repeating:c(note:49,instrument:1),count:4),
            [c(17,1),c(25,16),c(17,16),c(25,1)], [c(25),c(25),c(),c()]]
        let plan = adapt(song(rows),48_000)
        let held = plan.xmAudibleTimeline!.updates.filter { $0.channelIndex == 1 && $0.scheduledFrame >= 6720 }
        XCTAssertFalse(held.isEmpty)
        XCTAssertTrue(held.allSatisfy { $0.amplitude == 63.0/64 })
        XCTAssertTrue(slides(plan).filter { $0.channelIndex == 0 }.isEmpty)
    }

    func testChangingEnvelopeAndAdjacentL08ConsumePostWriterPan() throws {
        let envelope = PlaybackPanningEnvelope(enabled:true,points:[.init(tick:0,value:32),.init(tick:4,value:16),
            .init(tick:8,value:48),.init(tick:12,value:32)],sustainPointIndex:nil,
            loopStartPointIndex:nil,loopEndPointIndex:nil,typeFlags:1)
        for linear in [true,false] { for rate in [44_100.0,48_000] {
            let plan = adapt([c(25,1,note:49,instrument:1),c(25),c(21,8),c(25)],rate,linear:linear,envelope:envelope)
            let semantics = try XCTUnwrap(plan.xmEnvelopeTimeline?.updates)
            for (tick,byte) in [128,111,94,78,62,92].enumerated() {
                let stored = Int(semantics[tick].channelPanningValue)
                let baseline: Float = tick == 0 ? 0 : PlaybackSongVolumeColumnDecoder.audioPan(forXMValue:stored)
                XCTAssertEqual(plan.xmAudibleTimeline!.updates[tick].pan,baseline + PlaybackSamplePanningPolicy.plannedPan(byte)
                    - PlaybackSamplePanningPolicy.plannedPan(stored),accuracy:1e-7)
            }
            XCTAssertEqual(semantics[12].state.panTick,8)
            XCTAssertEqual(semantics[12].channelPanningValue,118)
            XCTAssertEqual(semantics[19].channelPanningValue,117)
            XCTAssertEqual(plan.xmAudibleTimeline!.updates[12].scheduledFrame,12*Int(rate/50))
            let tail = plan.extendingEnvelopeTail(throughFrame:25*Int(rate/50))
            XCTAssertEqual(tail.xmEnvelopeTimeline?.updates.last?.channelPanningValue,113)
        } }
    }

    func testPublicFixtureWholeWindowFrameBoundariesAndPatternCarry() throws {
        for linear in [true,false] { for rate in [44_100.0,48_000] {
            let loaded = try Self.publicSong(linear:linear)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song:loaded,sampleRate:rate)
            let plan = try XCTUnwrap(runtime.plan), renderer = PlaybackSongOfflineRenderer(preparedPlan:plan)
            let request = PlaybackSongOfflineRenderRequest(song:loaded,orderCount:3,config:.init(sampleRate:rate),rows:16)
            let full = renderer.render(request)
            XCTAssertEqual(plan,full.plan)
            XCTAssertTrue(plan.diagnostics.deferredCellFields.isEmpty)
            XCTAssertEqual(plan.xmChannelRows.filter { $0.channelIndex == 0 && $0.syntheticRow >= 12 }.map { $0.controls.panningSlideMemory },[16,16,16,16])
            for rows in [1,3] { assertPCM(full.block,renderer.renderWindowed(request,windowRows:rows).block) }
            #if DEBUG
            let tick = Int(rate/50), quick = Int(rate*0.005)
            let splits = [1,quick-1,quick+1,7*tick-1,7*tick,7*tick+1,7*tick+quick,8*tick-1,18*tick+1]
            assertPCM(full.block,renderer.renderWindowedAtFrameBoundariesForTesting(request,boundaries:splits).block)
            #endif
        } }
    }

    /// Loads original public bytes; only the in-memory playback frequency mode varies.
    static func publicSong(linear:Bool) throws -> PlaybackSong {
        let path = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/panning-slide-semantics.xm").path
        return mode(try PlaybackSongBuilder.build(from:ModuleMetadataLoader().load(fromPath:path),modulePath:path),linear)
    }

    private func assertPCM(_ a:MixerRenderBlock,_ b:MixerRenderBlock) {
        XCTAssertEqual(a.frameCount,b.frameCount)
        XCTAssertLessThanOrEqual(zip(a.interleavedPCM,b.interleavedPCM).map { abs($0-$1) }.max() ?? 0,1e-7)
    }
    private func slides(_ p:PlaybackSongSyntheticPlan) -> [PlaybackSongSyntheticVoiceStateUpdateDiagnostic] {
        p.diagnostics.voiceStateUpdates.filter { if case .pxyPanningSlide = $0.command { return true }; return false }
    }
    private func adapt(_ s:PlaybackSong,_ rate:Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(s,startOrderIndex:0,orderCount:s.orders.count,sampleRate:rate)
    }
    private func adapt(_ cells:[PlaybackCell],_ rate:Double,linear:Bool=true,speed:Int=6,pan:UInt8=128,
                       volume:Float=1,finite:Bool=false,envelope:PlaybackPanningEnvelope?=nil) -> PlaybackSongSyntheticPlan {
        adapt(song(cells.map { [$0] },linear:linear,speed:speed,pan:pan,volume:volume,finite:finite,envelope:envelope),rate)
    }
    private func c(_ f:UInt8=0,_ p:UInt8=0,note:UInt8=0,instrument:UInt8=0,volume:UInt8=0) -> PlaybackCell {
        .init(note:note,instrument:instrument,volumeColumn:volume,effectType:f,effectParam:p)
    }
    private func song(_ rows:[[PlaybackCell]],linear:Bool=true,speed:Int=6,pan:UInt8=128,volume:Float=1,
                      finite:Bool=false,envelope:PlaybackPanningEnvelope?=nil) -> PlaybackSong {
        let samples = (0...1).map { i in PlaybackSample(instrumentIndex:1,sampleIndex:i,
            pcm:Array(repeating:i == 0 ? 0.25 : -0.125,count:finite ? 16 : 256),volume:volume,
            panning:i == 0 ? pan : 224,relativeNote:0,finetune:0,baseSampleRate:8363,
            loopStart:0,loopLength:finite ? 0 : 256,loopType:finite ? 0 : 1) }
        var map = Array(repeating:0,count:96);map[49]=1;map[50]=2
        let volumeEnvelope = PlaybackVolumeEnvelope(enabled:envelope != nil,points:[.init(tick:0,value:64),.init(tick:64,value:64)],
            sustainPointIndex:1,loopStartPointIndex:nil,loopEndPointIndex:nil,typeFlags:envelope == nil ? 0 : 3,fadeout:1024)
        return PlaybackSong(title:"Original G33 control",orders:[.init(orderIndex:0,patternIndex:0)],
            patternsByIndex:[0:.init(index:0,rows:rows.enumerated().map { .init(index:$0.offset,cells:$0.element) })],
            instrumentsByIndex:[1:.init(index:1,samples:samples,volumeEnvelope:volumeEnvelope,panningEnvelope:envelope ?? .disabled,noteSampleMap:map)],
            restartOrderIndex:0,endBehavior:.stopAtEnd,initialTiming:.init(speed:speed,bpm:125),usesLinearFrequencyTable:linear,
            xmSampleSlotProvenanceByInstrument:[1:[.init(sampleIndex:2,decodedPayloadLength:0,isCanonicalEmptySlotHeader:false,
                volume:32,panning:64,finetune:0,relativeNote:0)]])
    }
    private static func mode(_ s:PlaybackSong,_ linear:Bool) -> PlaybackSong {
        .init(title:s.title,orders:s.orders,patternsByIndex:s.patternsByIndex,instrumentsByIndex:s.instrumentsByIndex,
            restartOrderIndex:s.restartOrderIndex,endBehavior:s.endBehavior,initialTiming:s.initialTiming,
            usesLinearFrequencyTable:linear,xmSampleSlotProvenanceByInstrument:s.xmSampleSlotProvenanceByInstrument)
    }
}
