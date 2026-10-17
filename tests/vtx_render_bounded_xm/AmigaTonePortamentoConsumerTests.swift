import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class AmigaTonePortamentoConsumerTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]
    private var preparations: [PlaybackCell] { [c(), c(3, note: 53), c(3, 4), c(3, 4, note: 53)] }

    func test5xyComposesSharedToneAndVolumeAtEarlierLaterFxxSpeeds() throws {
        // Pinned FT2 observations: independent halves, upper-nibble precedence,
        // whole-byte slide memory, and execution only on nonzero ticks.
        for rate in rates {
            for speed in [1,2,3,6] {
                for channel in [0,1] {
                    func lane(_ cell: PlaybackCell) -> [PlaybackCell] {
                        var row = [c(),c()]; row[channel] = cell; return row
                    }
                    for prep in preparations {
                        for byte: UInt8 in [0,1,4,0x10,0x40,0x7F,0xF1,0xFF] {
                            var command = lane(c(5, byte)); command[1-channel] = c(15, UInt8(speed))
                            let rows = [lane(c(note: 49, instrument: 1)), lane(prep), command, lane(c(5))]
                            let (context, states) = inspect(song(rows), rate)
                            let d = try XCTUnwrap(context.tonePortamentoEffects.first { $0.syntheticRow == 2 })
                            XCTAssertEqual(d.rowSpeed, speed)
                            XCTAssertEqual(d.portamentoSpeed, prep.effectParam == 0 ? 0 : 4)
                            XCTAssertEqual(d.status, prep.note == 0 ? .noTarget : prep.effectParam == 0 ? .noSpeed : .applied)
                            XCTAssertEqual(context.events.count, 1)
                            XCTAssertEqual(states[2][channel].activeEventIndex, states[1][channel].activeEventIndex)
                            XCTAssertEqual(states[2][channel].tonePortamentoTargetNote, states[1][channel].tonePortamentoTargetNote)
                            XCTAssertEqual(states[2][channel].tonePortamentoSpeed, states[1][channel].tonePortamentoSpeed)
                            XCTAssertEqual(states[2][channel].volumeSlideMemory?.parameter, speed > 1 && byte > 0 ? byte : nil)
                            XCTAssertNil(states[2][1-channel].volumeSlideMemory)
                            let volumes = context.voiceStateUpdates.filter { $0.syntheticRow == 2 && $0.effectType == 5 && $0.applied }
                            XCTAssertEqual(volumes.map(\.syntheticTick), Array(1..<speed))
                            let delta = byte >> 4 > 0 ? Int(byte >> 4) : -Int(byte & 15)
                            XCTAssertEqual(volumes.map(\.effectiveVolumeAfter), (1..<speed).map { max(0,min(64,32+$0*delta)) })
                            XCTAssertTrue(volumes.allSatisfy { !$0.effectMemoryMissing && !$0.effectMemoryDeferred })
                            if prep.note != 0 && prep.effectParam > 0 {
                                XCTAssertEqual(d.stepUpdates.map(\.amigaPeriodAfter), (1..<speed).map { 6528-Double($0)*64 })
                                XCTAssertEqual(d.stepUpdates.map(\.scheduledFrame), (1..<speed).map { (12+$0)*Int(rate/50) })
                            }
                        }
                    }
                }
            }
        }
    }

    func testSharedSeedsColdRestorationHeldTargetsAndSpeedOneAdmission() throws {
        for rate in rates {
            for prep in preparations {
                for (family, byte): (UInt8,UInt8) in [(10,4),(5,4),(6,4),(10,0x24)] {
                    let (context, states) = inspect(song([[c(note: 49,instrument: 1)], [prep], [c(family,byte)], [c(5)]]), rate)
                    XCTAssertEqual(states[3][0].volumeSlideMemory?.parameter, byte)
                    XCTAssertEqual(states[3][0].volumeSlideMemory?.source.effectType, family)
                    XCTAssertEqual(states[3][0].volumeSlideMemory?.source.source.rowIndex, 2)
                    XCTAssertTrue(context.voiceStateUpdates.filter { $0.syntheticRow == 3 && $0.effectType == 5 }.allSatisfy { $0.applied && $0.effectMemoryReused && $0.memorySource?.effectType == family })
                }
                let (context, states) = inspect(song([[c(note: 49,instrument: 1)], [prep], [c(7,0x48)], [c(5)]]), rate)
                XCTAssertEqual(states[2][0].outputChannelVolume, 63)
                XCTAssertEqual(states[3][0].outputChannelVolume, 32)
                XCTAssertEqual(states[3][0].tremolo, states[2][0].tremolo)
                XCTAssertNil(states[3][0].volumeSlideMemory)
                XCTAssertEqual(context.voiceStateUpdates.filter { $0.syntheticRow == 3 && $0.effectType == 5 && $0.applied }.count, 5)
                let held = RuntimeCMixerAdapterEventPlan.make(song: song([[c(note: 49,instrument: 1)], [prep],
                    [c(),c(16,16)], [c(5)], [c(5)]], volume: 64), sampleRate: rate)
                let gains = held.events.filter { if case .gainPanUpdate = $0.action { return $0.source.rowIndex >= 3 }; return false }
                XCTAssertEqual(gains.count, 1); XCTAssertEqual(gains.first?.syntheticTick, 1)
                if case let .gainPanUpdate(index, gain, _) = gains.first?.action { XCTAssertEqual(index, 0); XCTAssertEqual(gain, 0.25) }
            }
            let (_, states) = inspect(song([[c(note: 49,instrument: 1),c()], [c(10,4),c()],
                [c(5,0xF1),c(15,1)], [c(5),c(15,3)]]), rate)
            XCTAssertEqual(states[2][0].volumeSlideMemory?.parameter, 4)
            XCTAssertEqual(states[3][0].volumeSlideMemory?.parameter, 4)
            XCTAssertEqual(states[3][0].baseChannelVolume, 4)
        }
    }

    func testVolumeColumnSpeedsF0SharedMemoryAndNoRetrigger() throws {
        for rate in rates {
            for speed in [1,2,3,6] {
                for nibble: UInt8 in [0,1,2,4,8,15] {
                    for prep in [c(),c(3,4,note: 53),c(note: 53,volume: 0xF2)] {
                        for target in [c(note: 61,instrument: 1,volume: 0xF0|nibble),c(note: 61,volume: 0xF0|nibble),c(volume: 0xF0|nibble)] {
                            let (context, states) = inspect(song([[c(note: 49,instrument: 1)], [prep], [target], [c(volume: 0xF0)], [c(3)]], speed: speed), rate)
                            let resolved = nibble > 0 ? Int(nibble)*16 : prep.volumeColumn > 0 ? 32 : Int(prep.effectParam)
                            XCTAssertEqual(states[2...4].map { $0[0].tonePortamentoSpeed ?? 0 }, Array(repeating: resolved,count: 3))
                            XCTAssertEqual(context.events.count, 1)
                            XCTAssertTrue(context.tonePortamentoEffects.allSatisfy { !$0.noteTriggerEventCreated && !$0.samplePositionReset })
                            if speed == 1 { XCTAssertTrue(context.tonePortamentoEffects.flatMap(\.stepUpdates).isEmpty) }
                            if target.note > 0 { XCTAssertEqual(states[2][0].tonePortamentoTargetAmigaPeriod, 3424) }
                            XCTAssertTrue(states.allSatisfy { $0[0].volumeSlideMemory == nil })
                        }
                    }
                }
            }
            for (volume, periods): (UInt8,[Double?]) in [(0xF1,[6592,6336,6080,5824,5568]),(0xF4,[5824,4800,3776,3424]),(0xFF,[3424])] {
                let (context, _) = inspect(song([[c(note: 49,instrument: 1)],[c(note: 61,volume: volume)]]), rate)
                XCTAssertEqual(context.tonePortamentoEffects.first?.stepUpdates.map(\.amigaPeriodAfter), periods)
            }
        }
    }

    func testSameCellRoutingQuantizedTuningOctavesReachedTargetsAndG30Boundary() throws {
        for rate in rates {
            for (fine, base, target): (Int,Double,Double) in [(-128,7680,7256),(0,7256,6848),(1,7256,6848),(127,6872,6488)] {
                for relative in [-12,0,12] {
                    for cell in [c(5,4,note: 49,instrument: 1),c(5,4,note: 49),c(note: 49,volume: 0xF4)] {
                        let (context, _) = inspect(song([[c(note: 48,instrument: 1)],[c(3,24)],[cell]], fine: fine, relative: relative), rate)
                        let d = try XCTUnwrap(context.tonePortamentoEffects.last)
                        let scale = pow(2,-Double(relative)/12)
                        XCTAssertEqual(d.currentAmigaPeriodBefore, base*scale)
                        XCTAssertEqual(d.targetAmigaPeriod, target*scale)
                        XCTAssertEqual(d.stepUpdates.last?.amigaPeriodAfter, target*scale)
                        XCTAssertEqual(context.events.count, 1)
                        XCTAssertFalse(d.samplePositionReset)
                    }
                }
            }
            for raw: UInt8 in [24,32] {
                for cell in [c(5,4,note: 50),c(note: 50,volume: 0xF0)] {
                    let (context, _) = inspect(song([[c(note: 49,instrument: 1)],[c(3,raw)],[cell],[c(5)]], speed: 3), rate)
                    let d = try XCTUnwrap(context.tonePortamentoEffects.first { $0.syntheticRow == 2 })
                    XCTAssertEqual(d.stepUpdates.map(\.amigaPeriodAfter), [6464])
                    XCTAssertEqual(d.stepUpdates.last?.reachedTarget, true)
                    XCTAssertTrue(context.tonePortamentoEffects.last?.stepUpdates.isEmpty == true)
                }
            }
            let (edge, _) = inspect(song([[c(note: 96,instrument: 1)],[c(3,4)],[c(5,4,note: 95)],[c(note: 96,volume: 0xF1)]], relative: 12), rate)
            XCTAssertEqual(edge.tonePortamentoEffects.last?.targetAmigaPeriod, 228)
            let (parent, _) = inspect(song([[c(note: 96,instrument: 1)],[c(3,4)],[c(3,note: 95)],[c(3,16,note: 96)]], relative: 12), rate)
            XCTAssertEqual(edge.tonePortamentoEffects.map(\.stepUpdates),parent.tonePortamentoEffects.map(\.stepUpdates))
            for cell in [c(5,4,note: 49),c(note: 49,volume: 0xF0)] {
                let (atTarget, _) = inspect(song([[c(note: 49,instrument: 1)],[c(3,24)],[cell],[c(5)]],speed: 3),rate)
                XCTAssertTrue(atTarget.tonePortamentoEffects.flatMap(\.stepUpdates).isEmpty)
                XCTAssertEqual(atTarget.tonePortamentoEffects.last?.targetAmigaPeriod,6848)
            }
            // The existing note-range clamp is G30; do not substitute an analytic target.
        }
    }

    func testColdOwnershipWritersAndLaterNoteOnlyAtEarlierLaterFxxSpeeds() throws {
        for rate in rates {
            for speed in [1,2,3,6] {
                for channel in [0,1] {
                    for (cell, volume, pan): (PlaybackCell,Int,Double) in [
                        (c(5,4,note: 49,instrument: 1),0,128),
                        (c(5,note: 49,instrument: 1),0,128),
                        (c(note: 49,instrument: 1,volume: 0xF4),0,128),
                        (c(note: 49,instrument: 1,volume: 0xF0),0,128),
                        (c(5,4,note: 49,instrument: 1,volume: 0x30),max(0,32-4*(speed-1)),128),
                        (c(5,4,note: 49,instrument: 1,volume: 0x93),max(0,3-4*(speed-1)),128),
                        (c(5,4,note: 49,instrument: 1,volume: 0xCF),0,240),
                        (c(12,32,note: 49,instrument: 1,volume: 0xF4),32,128),
                        (c(8,48,note: 49,instrument: 1,volume: 0xF4),0,48)
                    ] {
                        var cold = [c(),c()], later = [c(),c()]
                        cold[channel] = cell; cold[1-channel] = c(15,UInt8(speed)); later[channel] = c(note: 61)
                        let module = song([cold,later])
                        let (context,states) = inspect(module,rate)
                        let state = states[0][channel]
                        XCTAssertNil(state.activeEventIndex); XCTAssertNil(state.semanticInstrumentIndex)
                        XCTAssertNil(state.semanticSampleIndex); XCTAssertNil(state.activeSampleVolume)
                        XCTAssertEqual(state.triggeredSampleDefaultVolume,0); XCTAssertEqual(state.triggeredSampleDefaultPan,128)
                        XCTAssertEqual(state.carriedInstrumentIndex,1); XCTAssertEqual(state.tonePortamentoTargetAmigaPeriod,6848)
                        XCTAssertEqual(state.baseChannelVolume,volume); XCTAssertEqual(state.outputChannelVolume,volume)
                        XCTAssertEqual(state.panningValue,pan); XCTAssertEqual(states[1][channel].baseChannelVolume,volume)
                        XCTAssertEqual(context.events.count,1)
                        XCTAssertEqual(context.events[0].scheduledStartFrame,speed*Int(rate/50))
                        XCTAssertEqual(context.events[0].gain,Float(volume)/64); XCTAssertEqual(context.events[0].initialSourceFrame,0)
                        let d = try XCTUnwrap(context.tonePortamentoEffects.first)
                        XCTAssertEqual(d.policy,"same_cell_tone_portamento_cold_initialization_no_source")
                        XCTAssertEqual(d.rowSpeed,speed); XCTAssertTrue(d.stepUpdates.isEmpty)
                        if volume == 0 {
                            let full = PlaybackSongOfflineRenderer().render(.init(song: module,config: .init(sampleRate: rate),rows: 2))
                            XCTAssertTrue(full.block.interleavedPCM.allSatisfy { $0 == 0 })
                        }
                    }
                }
            }
        }
    }

    func testCold500ReplaysWholeSharedByteWithoutOwningHeader() throws {
        for rate in rates {
            for speed in [1,2,3,6] {
                for (family,byte): (UInt8,UInt8) in [(10,4),(5,4),(6,4),(10,0x24)] {
                    let (context,states) = inspect(song([[c(family,byte)],[c(5,note: 49,instrument: 1)],[c(note: 61)]],speed: speed),rate)
                    let value = byte == 4 ? 0 : 2*(speed-1)
                    XCTAssertNil(states[1][0].activeEventIndex); XCTAssertNil(states[1][0].semanticInstrumentIndex)
                    XCTAssertEqual(states[1][0].baseChannelVolume,value)
                    XCTAssertEqual(states[1][0].volumeSlideMemory?.parameter,speed == 1 ? nil : byte)
                    XCTAssertEqual(states[1][0].volumeSlideMemory?.source.effectType,speed == 1 ? nil : family)
                    XCTAssertEqual(context.events.count,1); XCTAssertEqual(context.events[0].gain,Float(value)/64)
                    let updates = context.voiceStateUpdates.filter { $0.syntheticRow == 1 && $0.effectType == 5 && $0.commandSource == .effectColumn && $0.applied }
                    XCTAssertEqual(updates.count,speed-1)
                    XCTAssertTrue(updates.allSatisfy { $0.effectMemoryReused && !$0.activeVoiceUpdated })
                }
            }
        }
    }

    func testAmigaNoteOnlyAndEmptyContinuationExcludeInstrumentReset() throws {
        for rate in rates {
            for cell in [c(5,4,note: 61),c(5,4),c(note: 61,volume: 0xF4),c(volume: 0xF0)] {
                let (context,states) = inspect(song([[c(12,21,note: 49,instrument: 1)],[c(3,4,note: 53)],[cell]]),rate)
                XCTAssertTrue(context.playbackStateEvents.isEmpty); XCTAssertEqual(context.events.count,1)
                XCTAssertEqual(states[2][0].activeEventIndex,0)
                XCTAssertEqual(states[2][0].baseChannelVolume,cell.effectType == 5 ? 1 : 21)
                XCTAssertFalse(context.tonePortamentoEffects.last?.instrumentStateUpdated == true)
            }
        }
    }

    func testPublicFixtureWholeWindowAndRuntimePlanFrames() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/amiga-tone-portamento-consumers.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
        XCTAssertFalse(module.usesLinearFrequencyTable)
        for rate in rates {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module,sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(), whole = renderer.render(request)
            XCTAssertEqual(whole.plan, runtime.plan)
            XCTAssertFalse(whole.diagnostics.tonePortamentoEffects.contains { $0.status == .unsupportedFrequencyTable })
            for rows in [1,3,5] { assertPCM(whole.block.interleavedPCM,renderer.renderWindowed(request,windowRows: rows).block.interleavedPCM) }
            let empty = try XCTUnwrap(whole.plan.xmChannelRows.first { $0.syntheticRow == 2 && $0.channelIndex == 9 }).controls
            XCTAssertNil(empty.activeEventIndex); XCTAssertEqual(empty.semanticSampleIndex,2)
            // The row-entry cache precedes the two 504 slide ticks.
            XCTAssertEqual(empty.baseChannelVolume,24); XCTAssertEqual(empty.panningValue,80)
            let later = try XCTUnwrap(whole.plan.xmChannelRows.first { $0.syntheticRow == 3 && $0.channelIndex == 9 }).controls
            XCTAssertEqual(later.activeSampleIndex,1); XCTAssertEqual(later.baseChannelVolume,16)
            XCTAssertEqual(later.panningValue,80); XCTAssertEqual(later.triggeredSampleDefaultPan,192)
            for d in whole.diagnostics.tonePortamentoEffects {
                guard let source = d.activeEventIndex else {
                    XCTAssertFalse(runtime.events.contains { $0.source == d.source && $0.channelIndex == d.channelIndex && $0.categories.contains("step_update") })
                    continue
                }
                for u in d.stepUpdates {
                    let event = try XCTUnwrap(runtime.events.first { $0.source == d.source && $0.channelIndex == d.channelIndex && $0.syntheticTick == u.syntheticTick && $0.categories.contains("step_update") })
                    guard case let .stepUpdate(index,step) = event.action else { return XCTFail("Expected tone step") }
                    XCTAssertEqual(index,source); XCTAssertEqual(event.scheduledFrame,u.scheduledFrame); XCTAssertEqual(step,u.playbackStepAfter)
                }
            }
#if DEBUG
            let steps = whole.diagnostics.tonePortamentoEffects.flatMap(\.stepUpdates)
            let boundaries = steps.prefix(3).map(\.scheduledFrame) + steps.filter(\.reachedTarget).map(\.scheduledFrame) + [Int(rate/50)*6]
            for offset in [-1,0,1] { assertPCM(whole.block.interleavedPCM,renderer.renderWindowedAtFrameBoundariesForTesting(request,boundaries: Set(boundaries.map { $0+offset }).sorted()).block.interleavedPCM) }
#endif
        }
    }

    private func c(_ fx: UInt8 = 0, _ param: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: instrument,volumeColumn: volume,effectType: fx,effectParam: param)
    }
    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, volume: Int = 32, fine: Int = 0, relative: Int = 0) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1,sampleIndex: 0,pcm: Array(repeating: 1/32,count: 256),volume: Float(volume)/64,
            relativeNote: relative,finetune: fine,baseSampleRate: 8363,loopStart: 0,loopLength: 256,loopType: 1)
        return PlaybackSong(title: "Public Amiga tone consumers",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: [1: .init(index: 1,samples: [sample],noteSampleMap: Array(repeating: 0,count: 96))],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: speed,bpm: 125),usesLinearFrequencyTable: false)
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
    private func assertPCM(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count,rhs.count,file: file,line: line)
        XCTAssertLessThanOrEqual(zip(lhs,rhs).map { abs($0-$1) }.max() ?? 0,1e-7,file: file,line: line)
    }
}
