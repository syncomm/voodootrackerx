import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class TonePortamentoDirectionLatchTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    typealias Direction = PlaybackSongSyntheticTonePortamentoDirection
    private let rates = [44_100.0, 48_000]

    func testTargetAdmissionLatchesLowerHigherOrNoneOnEverySurface() throws {
        for linear in [true, false] { for rate in rates { for surface in 0..<3 {
            for (note, direction): (UInt8, Direction) in [(53,.towardLowerPeriod),(45,.towardHigherPeriod),(49,.none)] {
                let (context, states) = inspect([[c(49,1)],[c(fx: 3,param: 4)],[admit(surface,note)],[continueTone(surface)]],linear,rate)
                let d = try XCTUnwrap(context.tonePortamentoEffects.first { $0.syntheticRow == 2 })
                XCTAssertEqual(d.directionBefore,.none)
                XCTAssertEqual(d.directionAtExecution,direction)
                XCTAssertEqual(states[2].tonePortamentoTargetNote,note)
                XCTAssertEqual(states[2].tonePortamentoSpeed,surface == 2 ? 16 : 4)
                XCTAssertEqual(context.events.count,1)
                XCTAssertFalse(d.noteTriggerEventCreated || d.samplePositionReset)
            }
        } } }
    }

    func testIdenticalCurrentTargetAndSpeedHaveDifferentHistoricalDirections() throws {
        for linear in [true,false] { for rate in rates {
            let prefix = [[c(49,1)],[c(50,fx: 3,param: 4)],[c(50,1,fx: 1,param: 15),c(fx: 15,param: 2)]]
            let retained = inspect(prefix + [[c(fx: 3),c(fx: 15,param: 3)]],linear,rate).0
            let replaced = inspect(prefix + [[c(50,fx: 3),c(fx: 15,param: 3)]],linear,rate).0
            let a = try XCTUnwrap(retained.tonePortamentoEffects.last), b = try XCTUnwrap(replaced.tonePortamentoEffects.last)
            XCTAssertEqual(a.currentLinearPeriodBefore,b.currentLinearPeriodBefore)
            XCTAssertEqual(a.currentAmigaPeriodBefore,b.currentAmigaPeriodBefore)
            XCTAssertEqual(a.targetNote,b.targetNote)
            XCTAssertEqual(a.portamentoSpeed,b.portamentoSpeed)
            XCTAssertEqual(a.directionAtExecution,.towardLowerPeriod)
            XCTAssertEqual(b.directionAtExecution,.towardHigherPeriod)
            XCTAssertEqual(a.stepUpdates.map(\.linearPeriodAfter),linear ? [4544] : [6464])
            XCTAssertEqual(b.stepUpdates.map(\.linearPeriodAfter),linear ? [4500,4516] : [6288,6352])
            XCTAssertEqual(a.stepUpdates.map(\.scheduledFrame),[9*Int(rate/50)])
            XCTAssertEqual(retained.events.count,2)
            XCTAssertEqual(retained.events[1].initialSourceFrame,0)
            XCTAssertEqual(a.activeEventIndex,1)
        } }
    }

    func testCrossingsUseRetainedDirectionFor300500AndF0() throws {
        for linear in [true,false] { for rate in rates { for surface in 0..<3 {
            let cases: [([[PlaybackCell]],Double,Int)] = [
                ([[c(49,1)],[c(53,fx: 3,param: 4)],[c(61,1)]],linear ? 4352 : 5424,1),
                ([[c(53,1)],[c(49,fx: 3,param: 4)],[c(37,2)]],linear ? 4608 : 6848,1),
                ([[c(49,1)],[c(50,fx: 3,param: 4)],[c(fx: 1,param: 32),c(fx: 15,param: 2)]],linear ? 4544 : 6464,0),
                ([[c(50,1)],[c(49,fx: 3,param: 4)],[c(fx: 2,param: 32),c(fx: 15,param: 2)]],linear ? 4608 : 6848,0),
                ([[c(49,1)],[c(50,fx: 3,param: 4)],[c(51,1)]],linear ? 4544 : 6464,1),
                ([[c(49,1)],[c(50,fx: 3,param: 4)],[c(50,3)]],linear ? 4544 : 6464,1)
            ]
            for (rows,target,generation) in cases {
                let (context,states) = inspect(rows + [[continueTone(surface),c(fx: 15,param: 3)]],linear,rate)
                let d = try XCTUnwrap(context.tonePortamentoEffects.last)
                XCTAssertEqual(d.stepUpdates.map(\.linearPeriodAfter),[target])
                XCTAssertEqual(d.directionAfter,.towardHigherPeriod)
                XCTAssertEqual(states[2].tonePortamentoDirection,states[1].tonePortamentoDirection)
                XCTAssertEqual(d.activeEventIndex,generation)
                XCTAssertEqual(context.events.count,generation+1)
            }
        } } }
    }

    func testLinearFineExtraFineAndFinetuneCrossingsKeepTheLatch() throws {
        for rate in rates {
            for (fx,param,start,target,speed): (UInt8,UInt8,UInt8,UInt8,UInt8) in [
                (14,0x11,49,50,4),(14,0x1f,49,50,4),(14,0x2f,50,49,4),
                (33,0x11,49,50,1),(33,0x1f,49,50,1),(33,0x2f,50,49,1),(14,0x5f,49,50,4)
            ] {
                let (context,states) = inspect([[c(start,1)],[c(target,fx: 3,param: speed)],[c(target,1,fx: fx,param: param)],[c(fx: 3)]],true,rate)
                XCTAssertEqual(states[2].tonePortamentoDirection,states[1].tonePortamentoDirection)
                XCTAssertEqual(context.tonePortamentoEffects.last?.stepUpdates.map(\.linearPeriodAfter),[target == 50 ? 4544 : 4608])
                XCTAssertEqual(context.events.count,2)
            }
        }
    }

    func testArrivalEqualAdmissionAndMoveAwayAreDistinct() throws {
        for linear in [true,false] { for rate in rates {
            for surface in 0..<3 {
                let prefix = [[c(49,1)],[c(50,fx: 3,param: 64)]]
                let equal = inspect(prefix + [[admit(surface,50)],[c(61,1)],[continueTone(surface)]],linear,rate)
                XCTAssertEqual(equal.1[1].tonePortamentoDirection,.towardHigherPeriod)
                XCTAssertEqual(equal.1[2].tonePortamentoDirection,.none)
                XCTAssertTrue(equal.0.tonePortamentoEffects.last?.stepUpdates.isEmpty == true)
                XCTAssertEqual(equal.1.last?.tonePortamentoTargetNote,50)
            }
            for (note,expected): (UInt8,[Double]) in [(49,linear ? [4544] : [6464]),(51,linear ? [4496,4512] : [6160,6224])] {
                let (context,states) = inspect([[c(49,1)],[c(50,fx: 3,param: 64)],[c(fx: 3,param: 4)],[c(note,1)],[c(fx: 3)]],linear,rate)
                XCTAssertEqual(states[1].tonePortamentoDirection,.towardHigherPeriod)
                XCTAssertEqual(context.tonePortamentoEffects.last?.directionAtExecution,.towardHigherPeriod)
                XCTAssertEqual(context.tonePortamentoEffects.last?.stepUpdates.map(\.linearPeriodAfter),expected)
            }
            let away = inspect([[c(49,1)],[c(53,fx: 3,param: 4)],[c(37,1)],[c(fx: 3)]],linear,rate).0
            XCTAssertEqual(away.tonePortamentoEffects.last?.stepUpdates.map(\.linearPeriodAfter),linear ? [5360,5344] : [13632,13568])
        } }
    }

    func testColdOwnershipAndZeroSpeedClampCreateNoSpeedMemory() throws {
        for linear in [true,false] { for rate in rates { for surface in 0..<3 {
            let (context,states) = inspect([[c()],[admit(surface,53,1)],[c(49,1)],[continueTone(surface)]],linear,rate)
            XCTAssertNil(states[1].activeEventIndex)
            XCTAssertEqual(states[1].tonePortamentoDirection,.towardHigherPeriod)
            XCTAssertEqual(states[1].tonePortamentoSpeed,surface == 1 ? nil : surface == 2 ? 16 : 4)
            XCTAssertEqual(states.last?.tonePortamentoSpeed,states[1].tonePortamentoSpeed)
            XCTAssertEqual(context.events.count,1)
            XCTAssertEqual(context.tonePortamentoEffects.last?.stepUpdates.map(\.linearPeriodAfter),linear ? [4352] : [5424])
        } } }
    }

    func testRoutesReleaseAndReplacementKeepTheirOwnAuthorities() throws {
        for linear in [true,false] { for rate in rates {
            for boundary in [c(0,2),c(97),c(fx: 20),c(0,2,fx: 20)] {
                let (context,states) = inspect([[c(49,1)],[c(53,fx: 3,param: 4)],[c(61)],[boundary],[c(fx: 3)]],linear,rate)
                XCTAssertEqual(states[3].tonePortamentoDirection,.towardLowerPeriod)
                XCTAssertEqual(context.events.count,2)
                XCTAssertEqual(context.tonePortamentoEffects.last?.activeEventIndex,1)
            }
            for empty in [false,true] {
                let (context,states) = inspect([[c(49,1)],[c(53,fx: 3,param: 4)],[c(empty ? 70 : 61,1)],[c(fx: 3)]],linear,rate,completed: !empty)
                XCTAssertEqual(states[2].tonePortamentoDirection,.towardLowerPeriod)
                XCTAssertEqual(states.last?.tonePortamentoDirection,.towardHigherPeriod)
                XCTAssertEqual(context.events.count,empty ? 1 : 2)
            }
            for surface in 0..<3 {
                let context = inspect([[c(49,1)],[c(53,fx: 3,param: 4)],[c(61,1)],[admit(surface,49,1)],[continueTone(surface)]],linear,rate).0
                let d = try XCTUnwrap(context.tonePortamentoEffects.first { $0.syntheticRow == 3 })
                XCTAssertEqual(d.directionBefore,.towardLowerPeriod)
                XCTAssertEqual(d.directionAtExecution,.towardHigherPeriod)
                XCTAssertEqual(d.noteTargetBefore,53); XCTAssertEqual(d.noteTargetAfter,49)
                XCTAssertEqual(d.portamentoSpeed,surface == 2 ? 16 : 4)
                XCTAssertEqual(context.events.count,2)
            }
            for writer in [c(fx: 3,param: 8),c(vol: 0xf1)] {
                let context = inspect([[c(49,1)],[c(53,fx: 3,param: 4)],[c(61,1)],[writer]],linear,rate).0
                XCTAssertEqual(context.tonePortamentoEffects.last?.directionAtExecution,.towardLowerPeriod)
            }
            let fresh = inspect([[c()],[c(fx: 3)],[c(fx: 5)],[c(vol: 0xf0)]],linear,rate)
            XCTAssertTrue(fresh.1.allSatisfy { $0.tonePortamentoDirection == .none && $0.tonePortamentoTargetNote == nil })
            XCTAssertTrue(fresh.0.events.isEmpty)
        } }
    }

    func testPublicFixtureWholeWindowRuntimeAndDiagnostics() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/tone-portamento-direction-latch.xm")
        let parsed = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
        for linear in [true,false] { for rate in rates {
            let song = PlaybackSong(title: parsed.title,orders: parsed.orders,patternsByIndex: parsed.patternsByIndex,
                instrumentsByIndex: parsed.instrumentsByIndex,restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: parsed.initialTiming,usesLinearFrequencyTable: linear)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song,sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: song,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(),whole = renderer.render(request)
            XCTAssertEqual(runtime.plan,whole.plan)
            for rows in [1,2,3] { assertPCM(whole.block.interleavedPCM,renderer.renderWindowed(request,windowRows: rows).block.interleavedPCM) }
#if DEBUG
            for offset in [-1,0,1] {
                assertPCM(whole.block.interleavedPCM,renderer.renderWindowedAtFrameBoundariesForTesting(request,
                    boundaries: [3,6,8,9,11].map { $0*Int(rate/50)+offset }).block.interleavedPCM)
            }
#endif
            let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: whole)
            let tones = try XCTUnwrap(json["tone_portamento_effects"] as? [[String:Any]])
            XCTAssertTrue(tones.contains { $0["direction_at_execution"] as? String == "toward_lower_period" && $0["direction_after"] as? String == "toward_higher_period" })
        } }
    }

    private func c(_ note: UInt8 = 0,_ ins: UInt8 = 0,fx: UInt8 = 0,param: UInt8 = 0,vol: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: ins,volumeColumn: vol,effectType: fx,effectParam: param)
    }
    private func admit(_ surface: Int,_ note: UInt8,_ ins: UInt8 = 0) -> PlaybackCell {
        surface == 0 ? c(note,ins,fx: 3,param: 4) : surface == 1 ? c(note,ins,fx: 5) : c(note,ins,vol: 0xf1)
    }
    private func continueTone(_ surface: Int) -> PlaybackCell { surface == 0 ? c(fx: 3) : surface == 1 ? c(fx: 5) : c(vol: 0xf0) }
    private func inspect(_ rows: [[PlaybackCell]],_ linear: Bool,_ rate: Double,completed: Bool = false) -> (Adapter.AdapterRowContext,[Adapter.ChannelState]) {
        func sample(_ instrument: Int,_ slot: Int,_ volume: Int,_ finetune: Int = 0) -> PlaybackSample {
            .init(instrumentIndex: instrument,sampleIndex: slot,pcm: Array(repeating: 1/32,count: completed ? 1 : 256),
                volume: Float(volume)/64,panning: 128,relativeNote: 0,finetune: finetune,baseSampleRate: 8363,
                loopStart: 0,loopLength: completed ? 0 : 256,loopType: completed ? 0 : 1)
        }
        var map = Array(repeating: 0,count: 96); map[50] = 1; map[69] = 2
        let song = PlaybackSong(title: "Public direction",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0:.init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: [1:.init(index: 1,samples: [sample(1,0,32),sample(1,1,20)],noteSampleMap: map),
                2:.init(index: 2,samples: [sample(2,0,48)],noteSampleMap: Array(repeating: 0,count: 96)),
                3:.init(index: 3,samples: [sample(3,0,32,112)],noteSampleMap: Array(repeating: 0,count: 96))],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: 3,bpm: 125),usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [1:[.init(sampleIndex: 2,decodedPayloadLength: 0,isCanonicalEmptySlotHeader: false,volume: 24,panning: 128)]])
        let traversal = PlaybackSongTraversalPlanner.plan(song,startOrderIndex: 0,orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(song,traversalPlan: traversal,sampleRate: rate)
        var context = Adapter.AdapterRowContext(),states = [Adapter.ChannelState]()
        for (i,row) in traversal.rows.enumerated() {
            _ = Adapter.appendEvents(from: row.row,source: row.source,syntheticRow: row.syntheticRow,song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow),timingPlan: timing,scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: i+1<traversal.rows.count ? traversal.rows[i+1].row : nil,context: &context)
            states.append(context.channelStates[0])
        }
        return (context,states)
    }
    private func assertPCM(_ a: [Float],_ b: [Float],file: StaticString = #filePath,line: UInt = #line) {
        XCTAssertEqual(a.count,b.count,file: file,line: line)
        XCTAssertLessThanOrEqual(zip(a,b).map { abs($0-$1) }.max() ?? 0,1e-7,file: file,line: line)
    }
}
