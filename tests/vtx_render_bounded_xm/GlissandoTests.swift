import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Numeric expectations come from the pinned native observer, independently of VTX conversion.
final class GlissandoTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]
    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, _ effect: UInt8 = 0,
                   _ parameter: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    func testPinnedCrossingsAndPhysicalStepsPreserveContinuousPeriod() throws {
        for linear in [true, false] { for rate in rates { for descending in [false, true] {
            let rows = [[c(descending ? 61 : 49, 1, 14, 0x31)], [c(descending ? 49 : 61, 0, 3, 3)]]
            let plan = A.adapt(song(rows, linear), orderIndex: 0, sampleRate: rate)
            let tone = try XCTUnwrap(plan.diagnostics.tonePortamentoEffects.first)
            let raw: [Double] = linear ? (descending ? [3852,3864,3876,3888,3900] : [4596,4584,4572,4560,4548])
                : (descending ? [3472,3520,3568,3616,3664] : [6800,6752,6704,6656,6608])
            let output: [Double] = linear ? (descending ? [3840,3840,3904,3904,3904] : [4608,4608,4544,4544,4544])
                : (descending ? [3424,3424,3628,3628,3628] : [6848,6848,6848,6848,6464])
            XCTAssertEqual(tone.stepUpdates.map(\.linearPeriodAfter), raw)
            XCTAssertEqual(tone.stepUpdates.compactMap { $0.audibleNativePeriod(linear: linear) }, output)
            XCTAssertEqual(tone.stepUpdates.map(\.scheduledFrame), (7...11).map { $0 * Int(rate / 50) })
            let expectedFirst: Double = rate == 48_000 ? (descending ? 22836 : 11418) : (descending ? 24856 : 12428)
            XCTAssertEqual(tone.stepUpdates.first?.playbackStepAfter, expectedFirst / 65536)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.semanticPitchProjection.captureFailureCount, 0)
            let semantic = try XCTUnwrap(plan.semanticPitch(row: 1, tick: 5, channel: 0))
            XCTAssertEqual(semantic.base, .known(raw.last!)); XCTAssertEqual(semantic.output, .known(output.last!))
        } } }
    }

    func testGridTiesFinetuneAndBoundedHighProjection() {
        // Native Amiga periods use x4 VTX units; exact halfway chooses the lower pitch.
        for (linear, input, output): (Bool, Double, Double) in [
            (true,4575,4544),(true,4576,4608),(false,6652,6464),(false,6656,6848)] {
            XCTAssertEqual(A.arpeggioPeriod(input, finetune: 0, offset: 0, linear: linear), output)
        }
        XCTAssertEqual(A.arpeggioPeriod(4596, finetune: -128, offset: 0, linear: true), 4608)
        XCTAssertEqual(A.arpeggioPeriod(4596, finetune: 8, offset: 0, linear: true), 4604)
        for period in [884.0,772] {
            XCTAssertEqual(A.arpeggioPeriod(period,finetune: 127,offset: 0,linear: true),1540)
        }
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride, 1152)
        XCTAssertEqual(MemoryLayout<PlaybackSongSyntheticTonePortamentoStepUpdate>.stride, 144)
    }

    func testEveryAliasPersistsAcrossResetsAndIsChannelLocal() throws {
        for linear in [true,false] { for rate in rates { for nibble in UInt8(0)...15 {
            let rows = [[c(49,1,14,0x30+nibble),c(49,1)], [c(61,0,3,3),c(61,0,3,3)],
                [c(53,1)], [c(0,1)], [c(97)], [c(0,0,3)], [c(49)], [c(0,0,3)]]
            let (context, states) = inspect(song(rows,linear),rate)
            XCTAssertTrue(states.allSatisfy { $0.glissandoEnabled == (nibble != 0) })
            let first = try XCTUnwrap(context.tonePortamentoEffects.first { $0.channelIndex == 0 })
            let other = try XCTUnwrap(context.tonePortamentoEffects.first { $0.channelIndex == 1 })
            XCTAssertEqual(first.stepUpdates.first?.glissandoFinetune, nibble == 0 ? nil : 0)
            XCTAssertTrue(other.stepUpdates.allSatisfy { $0.glissandoFinetune == nil })
            XCTAssertEqual(first.activeEventIndex,0); XCTAssertFalse(first.samplePositionReset)
            XCTAssertFalse(A.hasDeferredEffect(c(0,0,14,0x30+nibble)))
        } } }
    }

    func testDisableHoldsPitchUntilNextToneInvocationAndResumesRawMovement() throws {
        for linear in [true,false] { for rate in rates {
            let rows = [[c(49,1,14,0x31)],[c(61,0,3,3)],[c(0,0,14,0x30)],[c()],[c(0,0,3)]]
            let (context, states) = inspect(song(rows,linear),rate)
            XCTAssertEqual(states[1].activePlaybackStep,states[2].activePlaybackStep)
            XCTAssertEqual(states[2].activePlaybackStep,states[3].activePlaybackStep)
            XCTAssertEqual(states[1].activeLinearPeriod,states[3].activeLinearPeriod)
            XCTAssertEqual(states[1].activeAmigaPeriod,states[3].activeAmigaPeriod)
            let resumed = try XCTUnwrap(context.tonePortamentoEffects.last?.stepUpdates.first)
            XCTAssertNil(resumed.glissandoFinetune)
            XCTAssertEqual(resumed.linearPeriodAfter,linear ? 4536 : 6560)
            XCTAssertEqual(context.events.count,1)
            let plan = A.adapt(song(rows,linear),orderIndex: 0,sampleRate: rate)
            XCTAssertEqual(plan.semanticPitch(row: 3,tick: 5,channel: 0)?.output,.known(linear ? 4544 : 6464))
        } }
    }

    func testSharedConsumersSameRowControlAndCommandRowSpeed() throws {
        for linear in [true,false] { for rate in rates {
            let rows = [[c(49,1)],[c(61,0,14,0x31,volume: 0xF1)],
                [c(0,0,14,0x30,volume: 0xF0)],[c(0,0,14,0x3F)],
                [c(0,0,5,1)],[c(0,0,3),c(0,0,15,1)],[c(0,0,3),c(0,0,15,3)]]
            let plan = A.adapt(song(rows,linear),orderIndex: 0,sampleRate: rate)
            let tones = plan.diagnostics.tonePortamentoEffects
            XCTAssertTrue(tones.first { $0.syntheticRow == 1 }!.stepUpdates.allSatisfy { $0.glissandoFinetune != nil })
            XCTAssertTrue(tones.first { $0.syntheticRow == 2 }!.stepUpdates.allSatisfy { $0.glissandoFinetune == nil })
            XCTAssertTrue(tones.first { $0.syntheticRow == 4 }!.stepUpdates.allSatisfy { $0.glissandoFinetune != nil })
            XCTAssertTrue(tones.first { $0.syntheticRow == 5 }!.stepUpdates.isEmpty)
            XCTAssertEqual(tones.first { $0.syntheticRow == 6 }!.stepUpdates.map(\.syntheticTick),[1,2])
            XCTAssertEqual(plan.pattern.events.count,1)
        } }
    }

    func testClampEqualityColdStartAndSourceLifetime() throws {
        for linear in [true,false] { for rate in rates {
            let rows = [[c(0,0,14,0x31)],[c(61,0,3,3)],[c(0,0,3)],
                [c(49,1)],[c(50,0,3,64)],[c(0,0,3)],[c(50,0,3)],[c(0,0,3)]]
            let plan = A.adapt(song(rows,linear),orderIndex: 0,sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.count,1)
            XCTAssertEqual(plan.diagnostics.tonePortamentoEffects.first?.status,.noActiveVoice)
            let arrived = try XCTUnwrap(plan.diagnostics.tonePortamentoEffects.first { $0.syntheticRow == 4 })
            XCTAssertTrue(arrived.stepUpdates.first?.reachedTarget == true)
            XCTAssertEqual(arrived.stepUpdates.count,5)
            XCTAssertTrue(plan.diagnostics.tonePortamentoEffects.first { $0.syntheticRow == 6 }!.stepUpdates.isEmpty)
            for completed in [false,true] {
                let held = A.adapt(song([[c(49,1,14,0x31)],[c(61,0,3,3)],[c(97)],[c(0,0,3)]],linear,completed: completed),orderIndex: 0,sampleRate: rate)
                XCTAssertEqual(held.pattern.events.count,1)
                XCTAssertFalse(held.diagnostics.tonePortamentoEffects.last!.samplePositionReset)
            }
        } }
    }

    func testAutovibratoComposesFromSnappedOutputAndDeliveryMatches() throws {
        for linear in [true,false] { for rate in rates {
            let input = song([[c(49,1,14,0x31)],[c(61,0,3,3)],[c()],[c(0,0,3)]],linear,automatic: true)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input,sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan)
            XCTAssertEqual(plan.semanticPitchProjection.captureFailureCount,0)
            let tone = plan.diagnostics.tonePortamentoEffects[0]
            let child = try XCTUnwrap(tone.stepUpdates.first)
            let clock = try XCTUnwrap(plan.instrumentAutovibrato(row: 1,tick: 1,channel: 0))
            let delta = PlaybackSongInstrumentAutovibratoComposition.delta(clock: clock)
            let bounds = PlaybackSongInstrumentAutovibratoComposition.Bounds(linear: linear,baseSampleRate: 8363,outputSampleRate: rate)
            XCTAssertEqual(child.playbackStepAfter,bounds.step(period: linear ? 4608 : 6848,delta: delta))
            let request = PlaybackSongOfflineRenderRequest(song: input,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(), whole = renderer.render(request)
            XCTAssertEqual(runtime.plan,whole.plan)
            for rows in [1,2] {
                XCTAssertEqual(whole.block.interleavedPCM,renderer.renderWindowed(request,windowRows: rows).block.interleavedPCM)
            }
        } }
    }

    func testRetunedSourceClampsContinuousOldTargetBeforeSnapping() throws {
        for linear in [true,false] { for rate in rates {
            let rows = [[c(49,1,14,0x31)],[c(61,0,3,48)],[c(53,1,14,0x50)],
                [c(volume: 0xF0)],[c(volume: 0xF0)]]
            let plan = A.adapt(song(rows,linear,finetune: 32,relative: 12),orderIndex: 0,sampleRate: rate)
            let tone = try XCTUnwrap(plan.diagnostics.tonePortamentoEffects.first { $0.syntheticRow == 3 })
            XCTAssertEqual(tone.currentLinearPeriodAfter,linear ? 3056 : nil)
            XCTAssertEqual(tone.currentAmigaPeriodAfter,linear ? nil : 1688)
            XCTAssertTrue(tone.stepUpdates.allSatisfy { $0.glissandoFinetune == -128 })
            XCTAssertEqual(tone.stepUpdates.first?.audibleNativePeriod(linear: linear),linear ? 3072 : 1712)
            XCTAssertEqual(tone.stepUpdates.first?.playbackStepAfter,Double(rate == 48000 ? 45673 : 49712)/65536)
            XCTAssertEqual(plan.pattern.events.count,2)
            XCTAssertEqual(plan.semanticPitchProjection.captureFailureCount,0)
        } }
    }

    func testPublicFixtureAndHeldLocalZeroDeliverTheSamePitch() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/glissando-tone-output.xm")
        let loaded = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
        for linear in [true,false] { for rate in rates {
            let input = PlaybackSong(title: loaded.title,orders: loaded.orders,patternsByIndex: loaded.patternsByIndex,
                instrumentsByIndex: loaded.instrumentsByIndex,restartOrderIndex: 0,endBehavior: .stopAtEnd,
                initialTiming: loaded.initialTiming,usesLinearFrequencyTable: linear)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input,sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: input,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(), whole = renderer.render(request)
            XCTAssertEqual(runtime.plan,whole.plan)
            XCTAssertEqual(whole.block.interleavedPCM,renderer.renderWindowed(request,windowRows: 1).block.interleavedPCM)
            let delayed = A.adapt(song([[c(49,1,14,0x31)],[c(61,0,3,3),c(0,0,14,0xE1)]],linear),orderIndex: 0,sampleRate: rate)
            let ticks = try XCTUnwrap(delayed.diagnostics.tonePortamentoEffects.first?.stepUpdates.map(\.syntheticTick))
            XCTAssertEqual(ticks,Array(1...11))
            XCTAssertEqual(delayed.pattern.events.count,1)
        } }
    }

    func testActualSelectedRangeStartsWithoutUnexecutedControlHistory() throws {
        for linear in [true,false] { for rate in rates {
            let seed = song([[c(0,0,14,0x31)]],linear)
            let later = song([[c(49,1)],[c(61,0,3,3)]],linear)
            let input = PlaybackSong(title: seed.title,
                orders: [.init(orderIndex: 0,patternIndex: 0),.init(orderIndex: 1,patternIndex: 1)],
                patternsByIndex: [0:seed.patternsByIndex[0]!,1:later.patternsByIndex[0]!],
                instrumentsByIndex: seed.instrumentsByIndex,restartOrderIndex: 0,endBehavior: .stopAtEnd,
                initialTiming: seed.initialTiming,usesLinearFrequencyTable: linear)
            let cold = A.adapt(input,startOrderIndex: 1,orderCount: 1,sampleRate: rate)
            let executed = A.adapt(input,startOrderIndex: 0,orderCount: 2,sampleRate: rate)
            XCTAssertTrue(cold.diagnostics.tonePortamentoEffects[0].stepUpdates.allSatisfy { $0.glissandoFinetune == nil })
            XCTAssertTrue(executed.diagnostics.tonePortamentoEffects[0].stepUpdates.allSatisfy { $0.glissandoFinetune != nil })
            XCTAssertEqual(cold.pattern.events.first?.scheduledStartFrame,0)
            // Explicit selected-range delivery is separate from the product's open #516 prewarm integration.
            XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: input,sampleRate: rate,preparedPlan: cold).plan,cold)
        } }
    }

    private func song(_ rows: [[PlaybackCell]], _ linear: Bool, completed: Bool = false,
                      automatic: Bool = false, finetune: Int = 0, relative: Int = 0) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1,sampleIndex: 0,
            pcm: (0..<(completed ? 1 : 256)).map { Float(sin(Double($0) * .pi / 8)) / 8 },
            volume: 0.75,panning: 128,relativeNote: relative,finetune: finetune,baseSampleRate: 8363,
            loopStart: 0,loopLength: completed ? 0 : 256,loopType: completed ? 0 : 1)
        return .init(title: "Original G36",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0:.init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: [1:.init(index: 1,samples: [sample],autoVibrato: automatic
                ? .init(waveformType: 0,sweep: 0,depth: 4,rate: 3) : .disabled,noteSampleMap: Array(repeating: 0,count: 96))],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: 6,bpm: 125),usesLinearFrequencyTable: linear)
    }

    private func inspect(_ song: PlaybackSong,_ rate: Double) -> (A.AdapterRowContext,[A.ChannelState]) {
        let traversal = PlaybackSongTraversalPlanner.plan(song,startOrderIndex: 0,orderCount: 1)
        let timing = PlaybackSongFxxTimingPlanner.plan(song,traversalPlan: traversal,sampleRate: rate)
        var context = A.AdapterRowContext(), states = [A.ChannelState]()
        for (index,row) in traversal.rows.enumerated() {
            _ = A.appendEvents(from: row.row,source: row.source,syntheticRow: row.syntheticRow,song: song,
                timingConfig: timing.timingConfig(forSyntheticRow: row.syntheticRow),timingPlan: timing,
                scheduledStartFrame: timing.frameFor(row: row.syntheticRow),
                nextRow: index+1 < traversal.rows.count ? traversal.rows[index+1].row : nil,context: &context)
            states.append(context.channelStates[0])
        }
        return (context,states)
    }
}
