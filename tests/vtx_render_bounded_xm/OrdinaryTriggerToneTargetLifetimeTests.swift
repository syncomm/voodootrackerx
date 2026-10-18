import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class OrdinaryTriggerToneTargetLifetimeTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]
    private var prefix: [[PlaybackCell]] { [[c(note: 49, instrument: 1)], [c(3, 4, note: 53)]] }

    func testOrdinaryEffectsRetainTargetAndSpeedOnTheNewGeneration() throws {
        // Pinned FT2 controls at both rates: ordinary triggers preserve the target
        // independently of their own pitch/volume writers. Amiga G29 stays deferred.
        let effects: [(UInt8, UInt8)] = [(0,0),(0,0x37),(1,4),(2,4),(4,0x48),(10,4),(12,32),(8,48),
            (14,0x11),(14,0x21),(33,0x11),(33,0x21),(14,0x58),(14,0x57)]
        for linear in [true, false] {
            for rate in rates {
                for (effect, byte) in effects {
                    let (context, states) = inspect(song(prefix + [[c(effect,byte,note: 49,instrument: 1)],[c(3)]],linear: linear),rate)
                    assertTarget(states[2], equals: states[1])
                    XCTAssertEqual(states[2].tonePortamentoSpeed,4)
                    XCTAssertEqual(context.events.count,2)
                    XCTAssertEqual(states[2].activeEventIndex,1)
                    XCTAssertEqual(context.events[1].initialSourceFrame,0)
                    XCTAssertEqual(context.events[1].scheduledStartFrame,6*Int(rate/50))
                    let later = try XCTUnwrap(context.tonePortamentoEffects.last)
                    XCTAssertEqual(later.source.rowIndex,3)
                    XCTAssertEqual(later.activeEventIndex,1)
                    XCTAssertTrue(later.targetExistsBefore && later.targetExistsAfter)
                    XCTAssertEqual(later.targetNote,53)
                    let start = try XCTUnwrap(linear ? later.currentLinearPeriodBefore : later.currentAmigaPeriodBefore)
                    XCTAssertEqual(start,period(states[2]))
                    XCTAssertEqual(later.stepUpdates.map(\.linearPeriodAfter),[start-(linear ? 16 : 64),start-(linear ? 32 : 128)])
                    XCTAssertEqual(later.stepUpdates.map(\.scheduledFrame),[10,11].map { $0*Int(rate/50) })
                    if !linear && [14,33].contains(effect) {
                        XCTAssertEqual(context.events[1].playbackStep,8363/rate,accuracy: 1e-12)
                    }
                }
            }
        }
    }

    func testMappedSourceDefaultsAndCursorReplaceIndependentlyOfTarget() throws {
        for linear in [true,false] {
            for rate in rates {
                for (note, instrument, sample, volume): (UInt8,UInt8,Int,Int) in [(49,1,0,32),(51,1,1,20),(49,2,0,48),(49,0,0,32)] {
                    let (context,states) = inspect(song(prefix + [[c(note: note,instrument: instrument)],[c(3)]],linear: linear),rate)
                    assertTarget(states[2],equals: states[1])
                    let mapping = context.eventMappings[1]
                    XCTAssertEqual(mapping.instrumentIndex,instrument == 0 ? 1 : Int(instrument))
                    XCTAssertEqual(mapping.sampleIndex,sample)
                    XCTAssertEqual(states[2].carriedInstrumentIndex,instrument == 0 ? 1 : Int(instrument))
                    XCTAssertEqual(states[2].activeSampleIndex,sample)
                    XCTAssertEqual(states[2].triggeredSampleDefaultVolume,volume)
                    XCTAssertEqual(states[2].baseChannelVolume,volume)
                    XCTAssertEqual(states[2].panningValue,128)
                    XCTAssertEqual(context.events[1].initialSourceFrame,0)
                    XCTAssertEqual(context.tonePortamentoEffects.last?.activeEventIndex,1)
                    XCTAssertEqual(context.tonePortamentoEffects.last?.noteTargetBefore,53)
                }
            }
        }
    }

    func testExplicitToneCommandsReplaceTargetWithoutReplacingSource() throws {
        for linear in [true,false] {
            for rate in rates {
                for (command,speed,expected): (PlaybackCell,Int,[Double]) in [
                    (c(3,8,note: 55,instrument: 1),8,linear ? [4480,4448] : [6336,6208]),
                    (c(5,1,note: 55,instrument: 1),4,linear ? [4528,4512] : [6528,6464]),
                    (c(note: 55,instrument: 1,volume: 0xF1),16,linear ? [4384,4320] : [5952,5696])
                ] {
                    let (context,states) = inspect(song(prefix + [[command],[c(3)]],linear: linear),rate)
                    XCTAssertEqual(context.events.count,1)
                    XCTAssertEqual(states[2].activeEventIndex,0)
                    XCTAssertEqual(states[2].tonePortamentoTargetNote,55)
                    XCTAssertEqual(states[2].tonePortamentoTargetLinearPeriod,linear ? 4224 : nil)
                    XCTAssertEqual(states[2].tonePortamentoTargetAmigaPeriod,linear ? nil : 4832)
                    XCTAssertEqual(states[2].tonePortamentoSpeed,speed)
                    let replacement = context.tonePortamentoEffects[1]
                    XCTAssertEqual(replacement.noteTargetBefore,53)
                    XCTAssertEqual(replacement.noteTargetAfter,55)
                    XCTAssertFalse(replacement.noteTriggerEventCreated || replacement.samplePositionReset)
                    XCTAssertEqual(context.tonePortamentoEffects.last?.stepUpdates.map(\.linearPeriodAfter),expected)
                }
            }
        }
    }

    func testInstrumentReleaseEmptyCompletedAndColdBoundaries() throws {
        for linear in [true,false] {
            for rate in rates {
                for boundary in [c(instrument: 2),c(note: 97),c(20),c(20,instrument: 2),c(20,note: 49,instrument: 2)] {
                    let (context,states) = inspect(song(prefix + [[boundary],[c(3)]],linear: linear),rate)
                    assertTarget(states[2],equals: states[1])
                    XCTAssertEqual(context.events.count,1)
                    XCTAssertEqual(states[2].activeEventIndex,0)
                    XCTAssertEqual(states[2].tonePortamentoSpeed,4)
                    XCTAssertEqual(context.tonePortamentoEffects.last?.activeEventIndex,0)
                }
                let empty = inspect(song(prefix + [[c(note: 70,instrument: 1)],[c(note: 49,instrument: 1)],[c(3)]],linear: linear),rate)
                assertTarget(empty.1[2],equals: empty.1[1])
                XCTAssertNil(empty.1[2].activeEventIndex)
                XCTAssertEqual(empty.1[2].semanticSampleIndex,2)
                assertTarget(empty.1[3],equals: empty.1[1])
                XCTAssertEqual(empty.0.events.count,2)
                XCTAssertEqual(empty.0.tonePortamentoEffects.last?.activeEventIndex,1)
                let completed = inspect(song(prefix + [[c(note: 51,instrument: 1)],[c(3)]],linear: linear,completed: true),rate)
                assertTarget(completed.1[2],equals: completed.1[1])
                XCTAssertEqual(completed.0.events.count,2)
                XCTAssertEqual(completed.0.eventMappings[1].sampleIndex,1)
                let cold = inspect(song([[c(note: 49,instrument: 1)],[c(3)]],linear: linear),rate)
                XCTAssertNil(cold.1[0].tonePortamentoTargetNote)
                XCTAssertEqual(cold.0.tonePortamentoEffects.last?.status,.noTarget)
                // Cold target admission carries latent state, without claiming FT2's
                // separate latched-direction quirk in the existing progression engine.
                let seeded = inspect(song([[c(3,4,note: 53,instrument: 1)],[c(note: 49,instrument: 1)]],linear: linear),rate)
                XCTAssertNil(seeded.1[0].activeEventIndex)
                assertTarget(seeded.1[1],equals: seeded.1[0])
                XCTAssertEqual(seeded.0.events.count,1)
                XCTAssertEqual(seeded.0.events[0].initialSourceFrame,0)
            }
        }
    }

    func testUpdatedToneSpeedSurvivesAnOrdinaryTrigger() throws {
        for linear in [true,false] {
            for rate in rates {
                for (writer,speed): (PlaybackCell,Int) in [(c(3,8),8),(c(volume: 0xF1),16)] {
                    let (context,states) = inspect(song(prefix + [[writer],[c(note: 49,instrument: 1)],[c(3)]],linear: linear),rate)
                    assertTarget(states[3],equals: states[1])
                    XCTAssertEqual(states[3].tonePortamentoSpeed,speed)
                    let start = linear ? 4608.0 : 6848
                    let delta = Double(speed)*(linear ? 4 : 16)
                    XCTAssertEqual(context.tonePortamentoEffects.last?.stepUpdates.map(\.linearPeriodAfter),[start-delta,start-2*delta])
                }
            }
        }
    }

    func testPublicFixtureWholeWindowAndRuntimePlanTargets() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/ordinary-trigger-tone-target-lifetime.xm")
        let parsed = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
        for linear in [true,false] {
            let module = PlaybackSong(title: parsed.title,orders: parsed.orders,patternsByIndex: parsed.patternsByIndex,
                instrumentsByIndex: parsed.instrumentsByIndex,restartOrderIndex: 0,endBehavior: .stopAtEnd,
                initialTiming: parsed.initialTiming,usesLinearFrequencyTable: linear,
                xmSampleSlotProvenanceByInstrument: parsed.xmSampleSlotProvenanceByInstrument)
            for rate in rates {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module,sampleRate: rate)
                let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
                let renderer = PlaybackSongOfflineRenderer(),whole = renderer.render(request)
                XCTAssertEqual(whole.plan,runtime.plan)
                XCTAssertEqual(whole.plan.pattern.events.count,13)
                for rows in [1,2,3] { assertPCM(whole.block.interleavedPCM,renderer.renderWindowed(request,windowRows: rows).block.interleavedPCM) }
                for d in whole.diagnostics.tonePortamentoEffects where d.source.rowIndex == 3 {
                    XCTAssertTrue(d.targetExistsBefore && d.targetExistsAfter)
                    XCTAssertEqual(d.targetNote,d.channelIndex >= 4 && d.channelIndex <= 6 ? 55 : 53)
                    for update in d.stepUpdates {
                        let event = try XCTUnwrap(runtime.events.first { $0.source == d.source && $0.channelIndex == d.channelIndex && $0.syntheticTick == update.syntheticTick && $0.categories.contains("step_update") })
                        guard case let .stepUpdate(index,step) = event.action else { return XCTFail("Expected tone step") }
                        XCTAssertEqual(index,d.activeEventIndex)
                        XCTAssertEqual(event.scheduledFrame,update.scheduledFrame)
                        XCTAssertEqual(step,update.playbackStepAfter)
                    }
                }
#if DEBUG
                for offset in [-1,0,1] {
                    let boundaries = [6,9,10,11].map { $0*Int(rate/50)+offset }
                    assertPCM(whole.block.interleavedPCM,renderer.renderWindowedAtFrameBoundariesForTesting(request,boundaries: boundaries).block.interleavedPCM)
                }
#endif
            }
        }
    }

    private func c(_ fx: UInt8 = 0,_ byte: UInt8 = 0,note: UInt8 = 0,instrument: UInt8 = 0,volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: instrument,volumeColumn: volume,effectType: fx,effectParam: byte)
    }
    private func song(_ rows: [[PlaybackCell]],linear: Bool,completed: Bool = false) -> PlaybackSong {
        func sample(_ instrument: Int,_ slot: Int,_ volume: Int,_ short: Bool = false) -> PlaybackSample {
            .init(instrumentIndex: instrument,sampleIndex: slot,pcm: Array(repeating: 1/32,count: short ? 1 : 256),
                volume: Float(volume)/64,panning: 128,relativeNote: 0,finetune: 0,baseSampleRate: 8363,
                loopStart: 0,loopLength: short ? 0 : 256,loopType: short ? 0 : 1)
        }
        var map = Array(repeating: 0,count: 96); map[50] = 1; map[69] = 2
        return PlaybackSong(title: "Public target lifetime",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0:.init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: [1:.init(index: 1,samples: [sample(1,0,32,completed),sample(1,1,20)],noteSampleMap: map),
                2:.init(index: 2,samples: [sample(2,0,48)],noteSampleMap: Array(repeating: 0,count: 96))],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: 3,bpm: 125),usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: [1:[.init(sampleIndex: 2,decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false,volume: 24,panning: 128)]])
    }
    private func inspect(_ module: PlaybackSong,_ rate: Double) -> (Adapter.AdapterRowContext,[Adapter.ChannelState]) {
        let traversal = PlaybackSongTraversalPlanner.plan(module,startOrderIndex: 0,orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(module,traversalPlan: traversal,sampleRate: rate)
        var context = Adapter.AdapterRowContext(),states = [Adapter.ChannelState]()
        for (i,row) in traversal.rows.enumerated() {
            _ = Adapter.appendEvents(from: row.row,source: row.source,syntheticRow: row.syntheticRow,song: module,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow),timingPlan: timing,scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: i+1<traversal.rows.count ? traversal.rows[i+1].row : nil,context: &context)
            states.append(context.channelStates[0])
        }
        return (context,states)
    }
    private func period(_ state: Adapter.ChannelState) -> Double? { state.activeLinearPeriod ?? state.activeAmigaPeriod }
    private func assertTarget(_ value: Adapter.ChannelState,equals prior: Adapter.ChannelState,file: StaticString = #filePath,line: UInt = #line) {
        XCTAssertEqual(value.tonePortamentoTargetNote,prior.tonePortamentoTargetNote,file: file,line: line)
        XCTAssertEqual(value.tonePortamentoTargetLinearPeriod,prior.tonePortamentoTargetLinearPeriod,file: file,line: line)
        XCTAssertEqual(value.tonePortamentoTargetAmigaPeriod,prior.tonePortamentoTargetAmigaPeriod,file: file,line: line)
        XCTAssertEqual(value.tonePortamentoTargetPlaybackStep,prior.tonePortamentoTargetPlaybackStep,file: file,line: line)
    }
    private func assertPCM(_ lhs: [Float],_ rhs: [Float],file: StaticString = #filePath,line: UInt = #line) {
        XCTAssertEqual(lhs.count,rhs.count,file: file,line: line)
        XCTAssertLessThanOrEqual(zip(lhs,rhs).map { abs($0-$1) }.max() ?? 0,1e-7,file: file,line: line)
    }
}
