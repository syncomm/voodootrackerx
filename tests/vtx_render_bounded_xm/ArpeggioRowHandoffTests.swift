import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class ArpeggioRowHandoffTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer

    func testG32A0RFormerlyFailingBxRepeatedArpeggioAndBlankExit() throws {
        // Literal Q16 tick observations from original mathematical PCM/cells at
        // pinned ft2-clone 87be42543dac82cf802b5bddad917bda62ace131, not VTX output.
        let vectors: [(Bool, Double, [Int])] = [
            (true, 48000, [11173,10963,10835,10787,17108,13578]),
            (true, 44100, [12161,11933,11794,11741,18621,14779]),
            (false, 48000, [11260,11125,11044,11013,17147,13575]),
            (false, 44100, [12256,12109,12020,11986,18663,14775])
        ]
        for (linear, rate, v) in vectors {
            let input = song([c(49,1,0xA4), c(volume: 0xB8), c(param: 0x37), c(param: 0x37), c(), c()], linear)
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let plan = try XCTUnwrap(runtime.plan), base = rate == 48000 ? 11418 : 12428
            let phases = [v[4],v[5],base,v[4],v[5]]
            let expected = (Array(repeating: base, count: 8) + Array(v.prefix(4)) + [v[3]] + phases + [base] + phases + Array(repeating: base, count: 12)).map { Double($0)/65536 }
            let tick = Int(rate/50), history = R.PitchSourceHistory(plan: plan)
            XCTAssertEqual(plan.pattern.events.count, 1)
            XCTAssertEqual(plan.diagnostics.eventMappings.first?.sampleIndex, 0)
            XCTAssertEqual(plan.pattern.events[0].initialSourceFrame, 0)
            XCTAssertEqual(plan.diagnostics.arpeggioEffects.map(\.activeEventIndex), [0,0])
            let outgoing = try XCTUnwrap(plan.diagnostics.arpeggioEffects[0].subsumedRowExit)
            XCTAssertEqual(outgoing.scheduledFrame,18*tick)
            XCTAssertEqual(outgoing.playbackStepAfter,Double(base)/65536)
            let first = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first?.stepUpdates.first)
            XCTAssertEqual(first.playbackStepAfter, Double(v[3])/65536, "first 037 must hold Bx")
            XCTAssertEqual(linear ? first.linearPeriodAfter : first.amigaPeriodAfter! / 4, linear ? 4671 : 1775)
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
            let event = plan.pattern.events[0]
            let voice = mixer.addVoice(sample: event.sample, playbackStep: event.playbackStep)
            for entry in runtime.eventStorage.ordering {
                let e = runtime.events[entry.eventIndex]
                if case let .stepUpdate(source, step) = e.action {
                    XCTAssertEqual(source, 0)
                    XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice,
                        scheduledFrame: e.scheduledFrame, playbackStep: step).wasAccepted)
                }
            }
            var frames = Set(expected.indices.map { $0*tick })
            for n in [12,18,24,30] { frames.formUnion([n*tick-1,n*tick,n*tick+1]) }
            var rendered = 0
            for frame in frames.sorted() {
                if frame > rendered { _ = mixer.render(frames: frame-rendered) }
                let position = expected.prefix(frame/tick).reduce(0) { $0 + $1*Double(tick) }
                    + expected[frame/tick]*Double(frame%tick)
                XCTAssertEqual(history.advancedPosition(for: 0, at: frame), position)
                XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, position)
                _ = mixer.render(frames: 1); rendered = frame+1
                XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.sampleStep, expected[frame/tick])
                XCTAssertEqual(history.advancedPosition(for: 0, at: frame+1), position+expected[frame/tick])
                XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voice)?.samplePosition, position+expected[frame/tick])
            }
            try assertWindows(input, rate)
        }
    }

    func testG32A0RArpeggioExitPrecedesFineWritersAndInverseIsUnchanged() throws {
        for linear in [true,false] { for rate in [48000.0,44100] {
            for (effect,param): (UInt8,UInt8) in [(14,0x11),(14,0x21),(33,0x11),(33,0x21)] {
                let input = song([c(49,1),c(param: 0x37),c(effect: effect,param: param),c(),c(),c()],linear)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: input,sampleRate: rate)
                let plan = try XCTUnwrap(runtime.plan), frame = 12*Int(rate/50)
                let commands = runtime.eventStorage.ordering.map { runtime.events[$0.eventIndex] }.filter {
                    $0.scheduledFrame == frame && $0.primaryCategory == "step_update"
                }
                XCTAssertEqual(commands.count, 1, "outgoing restoration must be subsumed by the incoming writer")
                let step = try XCTUnwrap(commands.last).action
                let native = (linear ? 4608.0 : 1712) + (param >> 4 == 1 ? -1.0 : 1) * (effect == 14 ? 4 : 1)
                let expected = A.referencePlaybackStep(nativePeriod: native,linear: linear,baseSampleRate: 8363,outputSampleRate: rate)!
                XCTAssertEqual(step, .stepUpdate(activeEventIndex: 0,playbackStep: expected))
                if effect == 14 && param == 0x11 {
                    XCTAssertEqual(expected, rate == 48000 ? (linear ? 0.1748504638671875 : 0.1746368408203125)
                        : (linear ? 0.1903228759765625 : 0.1900787353515625))
                }
                let history = R.PitchSourceHistory(plan: plan)
                XCTAssertEqual(history.advancedPosition(for: 0,at: frame+1)! - history.advancedPosition(for: 0,at: frame)!,expected)
                XCTAssertEqual(plan.pattern.events.count,1)
                XCTAssertEqual(plan.diagnostics.arpeggioEffects[0].subsumedRowExit?.scheduledFrame,frame)
                let result = R().render(.init(song: input,config: .init(sampleRate: rate),rows: 6))
                let json = PlaybackSongDiagnosticsJSONExporter.jsonObject(from: result)
                let arpeggios = try XCTUnwrap(json["arpeggio_effects"] as? [[String: Any]])
                XCTAssertEqual((arpeggios[0]["subsumed_row_exit"] as? [String: Any])?["scheduled_frame"] as? Int,frame)
                try assertWindows(input,rate)
                let inverse = A.adapt(song([c(49,1),c(effect: effect,param: param),c(param: 0x37),c()],linear),orderIndex: 0,sampleRate: rate)
                XCTAssertEqual(inverse.diagnostics.arpeggioEffects.first?.stepUpdates.first?.playbackStepAfter,expected)
            }
        } }
    }

    func testG32A0RNarrowHeldOutputControlsSpeedsFxxOrderAndSilentRoutes() throws {
        for linear in [true,false] { for rate in [48000.0,44100] {
            for speed in [1,3,6] { for prior: UInt8 in [0,4,6] {
                for parameter: UInt8 in [0x37,0x73] {
                    let rows = [c(49,1,0xA4),c(volume: prior == 0 ? 0xB8 : 0,effect: prior,param: prior == 4 ? 0x48 : 0),c(param: parameter),c(),c()]
                    let plan = A.adapt(song(rows,linear,speed: speed),orderIndex: 0,sampleRate: rate)
                    let first = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first?.stepUpdates.first)
                    let held = plan.diagnostics.vibratoEffects.last?.stepUpdates.last?.playbackStepAfter ?? plan.pattern.events[0].playbackStep
                    XCTAssertEqual(first.playbackStepAfter,held)
                    let base = plan.pattern.events[0].playbackStep
                    XCTAssertEqual(plan.diagnostics.arpeggioEffects.last?.currentPlaybackStepAfter,base)
                }
            } }
            for parameters: [UInt8] in [[0x37,0x73],[0x73,0x37],[0x37,0],[0x73,0]] {
                for sourceChannel in [0,1] {
                    let rows = [c(49,1,0xA4),c(volume: 0xB8),c(param: parameters[0]),c(param: parameters[1]),c(),c()]
                    try assertWindows(song(rows,linear,sourceChannel: sourceChannel,fxx: 3),rate)
                }
            }
            for kind in 0...3 {
                let input = song([c(kind == 0 ? 0 : 49,kind == 0 ? 0 : 1,0xA4),c(volume: 0xB8),c(param: 0x37),c(effect: 14,param: 0x11),c()],linear,kind: kind)
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: input,sampleRate: rate)
                let plan = try XCTUnwrap(runtime.plan)
                XCTAssertEqual(plan.pattern.events.count,kind == 1 ? 1 : 0)
                if kind != 1 { XCTAssertFalse(runtime.events.contains { if case .noteTrigger = $0.action { return true }; return false }) }
                try assertWindows(input,rate)
            }
        } }
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride,1152)
    }

    private func assertWindows(_ input: PlaybackSong,_ rate: Double) throws {
        let renderer = R(), runtime = RuntimeCMixerAdapterEventPlan.make(song: input,sampleRate: rate)
        let plan = try XCTUnwrap(runtime.plan), end = try XCTUnwrap(runtime.plannedSongEndFrame)
        let request = PlaybackSongOfflineRenderRequest(song: input,config: .init(sampleRate: rate),frames: end)
        let whole = renderer.render(request).block.interleavedPCM
        for size in [1,2,3,5] {
            let window = renderer.renderWindowed(request,windowRows: size).block.interleavedPCM
            XCTAssertEqual(whole.count,window.count)
            XCTAssertLessThanOrEqual(zip(whole,window).map { abs($0-$1) }.max() ?? 0,1e-7)
#if DEBUG
            XCTAssertEqual(window,renderer.renderWindowedUsingScanPerWindowSchedulingReference(request,windowRows: size).block.interleavedPCM)
            XCTAssertEqual(renderer.makeWindowedRenderScheduleIndex(for: plan,totalFrames: end,windowRows: size,includedEventIndices: nil,config: request.config).windows,
                renderer.currentWindowedRenderPreAcceptanceInputs(for: plan,totalFrames: end,windowRows: size,includedEventIndices: nil,config: request.config))
#endif
        }
#if DEBUG
        let boundaries = plan.diagnostics.rowTiming.dropFirst().flatMap { [$0.rowStartFrame-1,$0.rowStartFrame,$0.rowStartFrame+1] }
        let split = renderer.renderWindowedAtFrameBoundariesForTesting(request,boundaries: boundaries).block.interleavedPCM
        XCTAssertLessThanOrEqual(zip(whole,split).map { abs($0-$1) }.max() ?? 0,1e-7)
#endif
    }

    private func c(_ note: UInt8 = 0,_ instrument: UInt8 = 0,_ volume: UInt8 = 0,
                   volume explicit: UInt8? = nil,effect: UInt8 = 0,param: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: instrument,volumeColumn: explicit ?? volume,effectType: effect,effectParam: param)
    }

    private func song(_ cells: [PlaybackCell],_ linear: Bool,speed: Int = 6,sourceChannel: Int = 0,fxx: UInt8 = 0,kind: Int = -1) -> PlaybackSong {
        // Original analytic PCM, quantized exactly as the independently authored XM.
        let sample = PlaybackSample(instrumentIndex: 1,sampleIndex: 0,
            pcm: (0..<(kind == 1 ? 4 : 32768)).map { Float((8192*sin(Double($0)*0.17)).rounded())/32768 },volume: 0.5,
            panning: 128,relativeNote: kind == 3 ? 127 : 0,finetune: 0,baseSampleRate: 8363)
        let rows = cells.enumerated().map { i,cell in
            PlaybackRow(index: i,cells: sourceChannel == 0 ? [cell,c(effect: fxx == 0 || i != 2 ? 0 : 15,param: fxx)]
                : [c(effect: i == 2 ? 15 : 0,param: fxx),cell])
        }
        return .init(title: "Public arpeggio row handoff",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0,rows: rows)],instrumentsByIndex: [1: .init(index: 1,samples: [sample],noteSampleMap: Array(repeating: kind == 2 ? 1 : 0,count: 96))],
            restartOrderIndex: 0,endBehavior: .stopAtEnd,initialTiming: .init(speed: speed,bpm: 125),usesLinearFrequencyTable: linear)
    }
}
