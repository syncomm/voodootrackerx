import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class AmigaZeroAmountUpClampTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]

    func testColdUpConsumersClampOwnedPitchWithoutSeedingMemoryOrChangingToneState() throws {
        for rate in rates { for fx: UInt8 in [14, 33, 1] { for speed in [1, 2, 3, 6] {
            for count in [0, 1, 256] {
                // Admit a latent target at speed one, then reach the signed-negative
                // word through actual 2FF execution before changing command-row speed.
                let rows = [[c(1,1),c()], [c(2,fx: 3,p: 1),c(fx: 15,p: 1)],
                    [c(fx: 2,p: 255),c(fx: 15,p: 6)],
                    [c(fx: fx,p: fx == 1 ? 0 : 0x10),c(fx: 15,p: UInt8(speed))]]
                let module = song(rows,count: count), (context,states) = inspect(module,rate)
                let before = states[2], after = states[3]
                let executes = fx != 1 || speed > 1
                XCTAssertEqual(before.activeAmigaPeriod,136156)
                XCTAssertEqual(after.activeAmigaPeriod,executes ? 4 : 136156)
                XCTAssertEqual(after.activeEventIndex,before.activeEventIndex)
                XCTAssertEqual(after.tonePortamentoTargetAmigaPeriod,before.tonePortamentoTargetAmigaPeriod)
                XCTAssertEqual(after.tonePortamentoDirection,before.tonePortamentoDirection)
                XCTAssertEqual(after.tonePortamentoSpeed,before.tonePortamentoSpeed)
                XCTAssertNotNil(after.tonePortamentoTargetAmigaPeriod)
                XCTAssertNil(after.finePitchUpMemory); XCTAssertNil(after.extraFinePitchUpMemory)
                XCTAssertNil(after.portamentoUpMemory)
                XCTAssertEqual(context.events.count,count == 0 ? 0 : 1)
                let plan = A.adapt(module,orderIndex: 0,sampleRate: rate)
                let updates: [PlaybackSongSyntheticTonePortamentoStepUpdate]
                if fx == 1 {
                    let d = try XCTUnwrap(plan.diagnostics.portamentoSlideEffects.last)
                    XCTAssertEqual(d.slideAmount,0); XCTAssertTrue(d.effectMemoryMissing)
                    XCTAssertFalse(d.effectMemoryReused); XCTAssertFalse(d.effectMemoryDeferred); XCTAssertNil(d.memorySource)
                    updates = d.stepUpdates
                } else {
                    let d = try XCTUnwrap(observations(plan.diagnostics).last)
                    XCTAssertTrue(d.0.cold); XCTAssertNil(d.0.memoryValue); XCTAssertNil(d.0.memoryOrigin)
                    XCTAssertFalse(d.0.effectMemoryReused); XCTAssertTrue(d.0.canonicalPitchValid)
                    XCTAssertTrue(d.0.publicationRequested); XCTAssertTrue(d.1)
                    if count != 256 { XCTAssertEqual(d.0.publicationSuppressionReason,"no_active_source") }
                    updates = d.2
                }
                // Regular diagnostics retain semantic updates for absent/completed
                // owners; fine consumers suppress those publications separately.
                XCTAssertEqual(updates.count,(count == 256 || fx == 1) && executes ? 1 : 0)
                if let update = updates.first {
                    XCTAssertEqual(update.syntheticTick,fx == 1 ? 1 : 0)
                    XCTAssertEqual(update.scheduledFrame,(13 + (fx == 1 ? 1 : 0))*Int(rate/50))
                    XCTAssertEqual(update.amigaPeriodAfter,4)
                    XCTAssertEqual(update.playbackStepAfter,A.playbackStep(amigaPeriod: 4,baseSampleRate: 8363,outputSampleRate: rate))
                }
            }
        } } }
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride,1152)
    }

    func testSeededFineExtraAndDownwardReplayRetainAmountsOriginsAndChannelLocality() throws {
        for rate in rates { for fx: UInt8 in [14,33] { for seed: UInt8 in [0x11,0x1f,0x21] {
            for negative in [false,true] {
                var rows = [[c(negative ? 1 : 49,1,fx: fx,p: seed),c(49,1)]]
                if negative { rows.append([c(fx: 2,p: 255),c()]) }
                rows.append([c(fx: fx,p: seed & 0xf0),c(fx: fx,p: seed & 0xf0)])
                let module = song(rows,fine: negative ? -128 : 0)
                let (context,states) = inspect(module,rate)
                let last = try XCTUnwrap(observations(A.adapt(module,orderIndex: 0,sampleRate: rate).diagnostics).first { $0.0.effectMemoryReused })
                XCTAssertEqual(last.0.memoryValue,Int(seed & 15))
                XCTAssertEqual(last.0.memoryOrigin?.source.rowIndex,0)
                XCTAssertEqual(last.0.memoryOrigin?.channelIndex,0)
                let delta = Double(seed & 15) * (fx == 14 ? 16 : 4)
                let prior = try XCTUnwrap(states[states.count-2].activeAmigaPeriod)
                XCTAssertEqual(states.last?.activeAmigaPeriod,negative && seed < 0x20 ? 4 : prior + (seed < 0x20 ? -delta : delta))
                let cold = fx == 14 ? context.finePortamentoUpEffects.filter { $0.channelIndex == 1 }.map(\.execution)
                    + context.finePortamentoDownEffects.filter { $0.channelIndex == 1 }.map(\.execution)
                    : context.extraFinePortamentoEffects.filter { $0.channelIndex == 1 }.map(\.execution)
                XCTAssertTrue(cold.allSatisfy { $0.cold && $0.memoryValue == nil && $0.memoryOrigin == nil })
            }
        } } }
    }

    func testDownwardZeroRegularReplayAndUnownedChannelsKeepTheirBoundaries() throws {
        for rate in rates { for (fx,p): (UInt8,UInt8) in [(14,0x20),(33,0x20),(2,0)] {
            let (context,states) = inspect(song([[c(1,1)],[c(fx: 2,p: 255)],[c(fx: fx,p: p)]]),rate)
            XCTAssertEqual(states.last?.activeAmigaPeriod,fx == 2 ? 156556 : 136156)
            XCTAssertNil(states.last?.finePitchDownMemory); XCTAssertNil(states.last?.extraFinePitchDownMemory)
            if fx == 2 { XCTAssertEqual(context.portamentoSlideEffects.last?.slideAmount,255) }
        } }
        for linear in [true,false] { for rate in rates { for fx: UInt8 in [14,33,1] {
            let (cold,states) = inspect(song([[c(fx: fx,p: fx == 1 ? 0 : 0x10)]],linear: linear),rate)
            XCTAssertTrue(cold.events.isEmpty); XCTAssertNil(states.last?.activeAmigaPeriod)
            XCTAssertNil(states.last?.activeLinearPeriod); XCTAssertNil(states.last?.activePlaybackStep)
            XCTAssertNil(states.last?.finePitchUpMemory); XCTAssertNil(states.last?.extraFinePitchUpMemory)
            XCTAssertNil(states.last?.portamentoUpMemory)
            if linear {
                let (_,owned) = inspect(song([[c(49,1)],[c(fx: fx,p: fx == 1 ? 0 : 0x10)]],fine: 0,linear: true),rate)
                XCTAssertEqual(owned[0].activeLinearPeriod,owned[1].activeLinearPeriod)
                XCTAssertEqual(owned[0].activePlaybackStep,owned[1].activePlaybackStep)
            }
        } } }
    }

    func testPublicExtremeFixtureWholeWindowPlansAndActiveCursorContinuity() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/extreme-pitch-state-amiga.xm")
        let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
        for rate in rates {
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: module,sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan)
            for (channel,fx): (Int,UInt8) in [(21,14),(22,33),(23,1)] {
                let event = try XCTUnwrap(plan.diagnostics.eventMappings.first { $0.channelIndex == channel })
                let update = try XCTUnwrap(runtime.events.first {
                    $0.channelIndex == channel && $0.source.rowIndex == 2 && $0.categories.contains("step_update")
                })
                guard case let .stepUpdate(index,step) = update.action else { return XCTFail("Expected clamp step") }
                XCTAssertEqual(index,event.eventIndex)
                XCTAssertEqual(update.scheduledFrame,(12 + (fx == 1 ? 1 : 0))*Int(rate/50))
                let mixer = CSoftwareMixer(config: .init(sampleRate: rate,channelCount: 1))
                let source = plan.pattern.events[index]
                let voice = mixer.addVoice(sample: source.sample,gain: source.gain,pan: source.pan,
                    playbackStep: source.playbackStep,loop: source.loop)
                for e in runtime.events where e.scheduledFrame <= update.scheduledFrame {
                    if case let .stepUpdate(target,value) = e.action, target == index {
                        XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice,scheduledFrame: e.scheduledFrame,playbackStep: value).wasAccepted)
                    }
                }
                _ = mixer.render(frames: update.scheduledFrame)
                let before = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                _ = mixer.render(frames: 1)
                let after = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                XCTAssertTrue(before.active && after.active); XCTAssertEqual(after.sampleStep,step)
                XCTAssertEqual(after.samplePosition,(before.samplePosition+step).truncatingRemainder(dividingBy: 256),accuracy: 1e-9)
            }
            let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: rate),frames: try XCTUnwrap(runtime.plannedSongEndFrame))
            let renderer = PlaybackSongOfflineRenderer(),whole = renderer.render(request)
            XCTAssertEqual(whole.plan,runtime.plan)
            let window = renderer.renderWindowed(request,windowRows: 1)
            XCTAssertEqual(whole.block.interleavedPCM.count,window.block.interleavedPCM.count)
            XCTAssertLessThanOrEqual(zip(whole.block.interleavedPCM,window.block.interleavedPCM).map { abs($0-$1) }.max() ?? 0,1e-7)
        }
    }

    private func c(_ note: UInt8 = 0,_ ins: UInt8 = 0,fx: UInt8 = 0,p: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: ins,volumeColumn: 0,effectType: fx,effectParam: p)
    }
    private func song(_ rows: [[PlaybackCell]],count: Int = 256,fine: Int = -128,linear: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1,sampleIndex: 0,pcm: Array(repeating: 1/32,count: count),
            volume: 0.5,panning: 128,relativeNote: 0,finetune: fine,baseSampleRate: 8363,
            loopStart: 0,loopLength: count == 256 ? 256 : 0,loopType: count == 256 ? 1 : 0)
        return .init(title: "Public zero-amount clamp",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0:.init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: [1:.init(index: 1,samples: [sample],noteSampleMap: Array(repeating: 0,count: 96))],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: 6,bpm: 125),usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: count == 0 ? [1:[.init(sampleIndex: 0,decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: false,volume: 32,panning: 128,finetune: fine,relativeNote: 0)]] : [:])
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
    private func observations(_ d: PlaybackSongSyntheticDiagnostics) -> [(PlaybackSongSyntheticFinePitchExecution,Bool,[PlaybackSongSyntheticTonePortamentoStepUpdate])] {
        d.finePortamentoUpEffects.map { ($0.execution,$0.clamped,$0.stepUpdates) }
            + d.finePortamentoDownEffects.map { ($0.execution,$0.clamped,$0.stepUpdates) }
            + d.extraFinePortamentoEffects.map { ($0.execution,$0.clamped,$0.stepUpdates) }
    }
}
