import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class BoundedPitchConversionTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private let rates = [44_100.0, 48_000]

    func testSignedFinetuneGroupsAndEveryValidNote() throws {
        // Observed FT2 C-4 groups at pin 87be42543dac82cf802b5bddad917bda62ace131.
        // Each group contains eight header bytes, with floor division for negatives.
        let anchors = [-128:4672, -127:4672, -65:4644, -64:4640, -63:4640,
            -2:4612, -1:4612, 0:4608, 1:4608, 2:4608, 63:4580, 64:4576,
            65:4576, 126:4548, 127:4548]
        for (fine, expected) in anchors {
            XCTAssertEqual(A.quantizedLinearPeriod(effectiveNote: 49, finetune: fine), expected)
        }
        for note in 1...119 { for group in -16...15 { for fine in (group*8)..<(group*8+8) {
            let expected = 4608 - (note-49)*64 - group*4
            XCTAssertEqual(A.quantizedLinearPeriod(effectiveNote: note, finetune: fine), expected)
            if note <= 107 {
                XCTAssertEqual(expected - A.quantizedLinearPeriod(effectiveNote: note+12, finetune: fine), 768)
            }
        } } }
        for rate in rates { for note in [13,24,25,48,49,60,61,84,85,96] {
            for relative in [-12,-1,0,1,12] where (1...119).contains(note+relative) {
                for fine in [-128,-127,-65,-1,1,63,65,127] {
                    let target = try XCTUnwrap(A.linearPitchTarget(note: UInt8(note), relativeNote: relative,
                        finetune: fine, baseSampleRate: 8363, outputSampleRate: rate))
                    XCTAssertEqual(target.effectiveNoteValue, note+relative)
                    XCTAssertEqual(target.effectiveFinetune, fine)
                    XCTAssertEqual(target.linearPeriod,
                        Double(A.quantizedLinearPeriod(effectiveNote: note+relative, finetune: fine)))
                }
            }
        } }
        // Invalid raw effective notes retain main's semantic clamp/analytic period.
        for (note,relative,period) in [(1,-1,7679.5), (96,24,127.5)] {
            XCTAssertEqual(A.linearPitchTarget(note: UInt8(note), relativeNote: relative, finetune: 1,
                baseSampleRate: 8363, outputSampleRate: 48000)?.linearPeriod, period)
        }
    }

    func testEveryUInt16PeriodAgainstPinnedReferenceFingerprints() throws {
        // Reference contract: UInt16 native periods; signed Int8 tuning. Positive
        // setup/exponent coefficients round to nearest, ties away from zero.
        // UInt64 products truncate at Q24, then the Linear UInt32 word and 5-bit
        // shift domains wrap; Amiga divides integers. Q16 / 65536 is an exact
        // Double payload, independent of canonical period/clamp/direction state.
        // FNV-1a of the little-endian IEEE Double step bytes, in period order.
        // These four fingerprints were produced by the external unchanged pinned
        // replayer, not the VTX formula. This covers all 262144 conversions without
        // shipping reference tables/code or duplicating the production algorithm.
        let vectors: [(Double,Bool,UInt64)] = [(44100,false,0x78abe44a2329c1a7),
            (44100,true,0x61366a5c6eed6d43), (48000,false,0xe5e949eb5d3603ef),
            (48000,true,0x7815dccb9e53bd6e)]
        for (rate,linear,expected) in vectors {
            var hash: UInt64 = 14695981039346656037
            for period in 0...65535 {
                let step = try XCTUnwrap(A.referencePlaybackStep(nativePeriod: Double(period), linear: linear,
                    baseSampleRate: 8363, outputSampleRate: rate))
                for shift in stride(from: 0, to: 64, by: 8) {
                    hash = (hash ^ ((step.bitPattern >> shift) & 255)) &* 1099511628211
                }
            }
            XCTAssertEqual(hash, expected, "rate \(rate), Linear \(linear)")
        }
    }

    func testIndependentSourceRateVectorsAndInvalidInputs() throws {
        // Q16 numerators from exact rational setup coefficients, rounded once,
        // followed by integer truncation. C-4 Linear and native Amiga 1711.
        let vectors: [(Double,Double,Int,Int)] = [(4000,44100,5944,5947),
            (4000,48000,5461,5464), (8363,44100,12428,12435),
            (8363,48000,11418,11424), (16726,44100,24856,24870),
            (16726,48000,22836,22849)]
        for (source,rate,linear,amiga) in vectors {
            XCTAssertEqual(A.playbackStep(linearPeriod: 4608, baseSampleRate: source, outputSampleRate: rate), Double(linear)/65536)
            XCTAssertEqual(A.playbackStep(amigaPeriod: 6844, baseSampleRate: source, outputSampleRate: rate), Double(amiga)/65536)
        }
        for invalid in [-1.0, .nan, .infinity] {
            XCTAssertNil(A.referencePlaybackStep(nativePeriod: invalid, linear: true, baseSampleRate: 8363, outputSampleRate: 48000))
            XCTAssertNil(A.referencePlaybackStep(nativePeriod: 4608, linear: true, baseSampleRate: invalid, outputSampleRate: 48000))
            XCTAssertNil(A.referencePlaybackStep(nativePeriod: 4608, linear: true, baseSampleRate: 8363, outputSampleRate: invalid))
        }
    }

    func testE5UsesOrdinaryQuantizationWithoutChangingTargetLifetime() throws {
        for rate in rates { for (nibble,period) in [(0,4672.0),(7,4616),(8,4608),(9,4600),(15,4552)] {
            let module = song([[c(49,1)],[c(50,fx: 3,param: 1)],
                [c(49,1,fx: 14,param: UInt8(0x50+nibble))],[c(fx: 3)],[c(fx: 14,param: 0x5f)],[c(49)]], fine: 65)
            let (context,states) = inspect(module,rate)
            XCTAssertEqual(context.events.count,3)
            XCTAssertEqual(context.eventMappings[1].effectiveFinetune,16*nibble-128)
            XCTAssertEqual(context.eventMappings[1].linearPeriod,period)
            XCTAssertEqual(context.eventMappings.last?.effectiveFinetune,65) // no-note E5 is inert.
            XCTAssertEqual(context.eventMappings.last?.linearPeriod,4576)
            XCTAssertEqual(states[2].tonePortamentoTargetLinearPeriod,4512)
            XCTAssertEqual(states[2].tonePortamentoDirection,.towardLowerPeriod)
            XCTAssertEqual(states[2].tonePortamentoSpeed,1)
            XCTAssertEqual(context.events[1].initialSourceFrame,0)
            XCTAssertEqual(context.events[1].scheduledStartFrame,6*Int(rate/50))
        } }
    }

    func testSustainedActualCandidateCursorsMatchReferenceAtAllCheckpoints() throws {
        // Literal cursor observations from the pinned reference, loop length 256.
        let exact = [[42.73944091796875,170.957763671875,86.788818359375],
                     [42.6982421875,170.79296875,85.96484375]]
        let negative = [[35.16917419433594,140.67669677734375,191.38348388671875],
                        [35.19091796875,140.763671875,191.818359375]]
        let between = [[43.63441467285156,175.38552856445312,110.05813598632812],
                       [43.533203125,174.923828125,107.673828125]]
        for (ri,rate) in rates.enumerated() { for (linear,fine,extra,expected) in [
            (true,0,false,exact), (true,1,false,exact), (true,-1,false,negative),
            (false,0,false,exact), (false,0,true,between)] {
            var rows = Array(repeating: [c()],count: 84); rows[0] = [c(49,1)]
            if extra { rows[1] = [c(fx: 33,param: 0x11)] }
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: song(rows,linear: linear,fine: fine),sampleRate: rate)
            let event = try XCTUnwrap(runtime.plan?.pattern.events.first)
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate,channelCount: 1))
            let voice = mixer.addVoice(sample: event.sample,gain: event.gain,pan: event.pan,
                playbackStep: event.playbackStep,loop: event.loop,initialSourceFrame: event.initialSourceFrame)
            for planned in runtime.events {
                if case let .stepUpdate(index,step) = planned.action {
                    XCTAssertEqual(index,0)
                    XCTAssertTrue(mixer.scheduleVoicePlaybackStepUpdate(voiceIndex: voice,
                        scheduledFrame: planned.scheduledFrame,playbackStep: step).wasAccepted)
                }
            }
            for (i,seconds) in [0.25,1.0,5.0].enumerated() {
                _ = mixer.render(frames: Int(rate*seconds)-Int(mixer.currentFrame))
                let diagnostic = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                XCTAssertTrue(diagnostic.active)
                XCTAssertEqual(diagnostic.samplePosition,expected[ri][i])
            }
        } }
    }

    func testExtremeSemanticFencesRetainBaselineAdmissionClampAndDirection() throws {
        for rate in rates {
            for (note,relative,period) in [(1,-2,109568.0),(1,-1,109568),(96,24,120)] {
                let (context,states) = inspect(song([[c(49,1)],[c(UInt8(note),2)]],
                    linear: false,secondRelative: relative),rate)
                XCTAssertEqual(context.events.count,2) // Baseline still starts, not reference refusal.
                XCTAssertEqual(context.events[1].initialSourceFrame,0)
                XCTAssertEqual(states[1].activeEventIndex,1)
                XCTAssertEqual(states[1].activeInstrumentIndex,2)
                XCTAssertEqual(states[1].activeAmigaPeriod,period)
                XCTAssertNil(states[1].tonePortamentoTargetNote)
            }
            let (low,states) = inspect(song([[c(1,1)],[c(fx: 2,param: 255)],
                [c(fx: 2,param: 255)],[c(96,fx: 3,param: 1)]],linear: false,fine: -128,speed: 6),rate)
            XCTAssertEqual(states.map(\.activeAmigaPeriod),[116096,136496,156896,156816])
            XCTAssertEqual(states.last?.tonePortamentoTargetAmigaPeriod,480)
            XCTAssertEqual(states.last?.tonePortamentoDirection,.towardLowerPeriod)
            XCTAssertEqual(states.last?.tonePortamentoSpeed,1)
            XCTAssertEqual(low.events.count,1)
            XCTAssertEqual(low.tonePortamentoEffects[0].stepUpdates.first?.amigaPeriodAfter,156880)
            XCTAssertEqual(low.tonePortamentoEffects[0].stepUpdates.first?.scheduledFrame,19*Int(rate/50))
            let (high,hs) = inspect(song([[c(96,1)],[c(fx: 1,param: 255)]],linear: false,speed: 6),rate)
            XCTAssertEqual(hs.last?.activeAmigaPeriod,107)
            XCTAssertEqual(high.portamentoSlideEffects[0].stepUpdates.count,1)
            XCTAssertEqual(hs.last?.activeEventIndex,0)
        }
        XCTAssertEqual(MemoryLayout<A.ChannelState>.size,1152)
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride,1152)
    }

    func testPublicFixturesShareQuantizedTargetsWholeWindowAndRuntimePlans() throws {
        for linear in [true,false] {
            let name = "bounded-pitch-conversion-\(linear ? "linear" : "amiga").xm"
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("reference-xm/generated/"+name)
            let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path),modulePath: url.path)
            for rate in rates {
                let runtime = RuntimeCMixerAdapterEventPlan.make(song: module,sampleRate: rate)
                let plan = try XCTUnwrap(runtime.plan)
                let periods = Array(plan.diagnostics.eventMappings.prefix(6)).map { linear ? $0.linearPeriod : $0.amigaPeriod }
                XCTAssertEqual(periods, (linear ? [4608.0,4612,4608,4672,4552,4548]
                    : [6848.0,6872,6848,7256,6512,6488]).map(Optional.some))
                XCTAssertEqual(Array(plan.diagnostics.eventMappings.prefix(6)).map(\.effectiveFinetune),[1,-1,0,-128,112,127])
                XCTAssertFalse(plan.diagnostics.arpeggioEffects.isEmpty)
                XCTAssertEqual(Set(plan.diagnostics.portamentoSlideEffects.map(\.effectType)),[1,2])
                XCTAssertTrue(Set(plan.diagnostics.tonePortamentoEffects.map(\.effectType)).isSuperset(of: [3,5]))
                XCTAssertTrue(plan.diagnostics.tonePortamentoEffects.contains { $0.rawVolumeColumn == 0xf1 })
                XCTAssertFalse(plan.diagnostics.finePortamentoUpEffects.isEmpty)
                XCTAssertFalse(plan.diagnostics.finePortamentoDownEffects.isEmpty)
                XCTAssertFalse(plan.diagnostics.extraFinePortamentoEffects.isEmpty)
                XCTAssertFalse(plan.diagnostics.vibratoEffects.isEmpty)
                let request = PlaybackSongOfflineRenderRequest(song: module,config: .init(sampleRate: rate),
                    frames: try XCTUnwrap(runtime.plannedSongEndFrame))
                let renderer = PlaybackSongOfflineRenderer(),whole = renderer.render(request)
                XCTAssertEqual(whole.plan,runtime.plan)
                for rows in [1,5,17] {
                    let window = renderer.renderWindowed(request,windowRows: rows)
                    XCTAssertEqual(window.block.interleavedPCM.count,whole.block.interleavedPCM.count)
                    XCTAssertLessThanOrEqual(zip(window.block.interleavedPCM,whole.block.interleavedPCM)
                        .map { abs($0-$1) }.max() ?? 0,1e-7)
                }
#if DEBUG
                let unit = Int(rate/50)
                let boundaries = [1,84*3*unit-1,84*3*unit,84*3*unit+1,85*3*unit+unit]
                let split = renderer.renderWindowedAtFrameBoundariesForTesting(request,boundaries: boundaries)
                XCTAssertLessThanOrEqual(zip(split.block.interleavedPCM,whole.block.interleavedPCM)
                    .map { abs($0-$1) }.max() ?? 0,1e-7)
#endif
            }
        }
    }

    private func c(_ note: UInt8 = 0,_ instrument: UInt8 = 0,fx: UInt8 = 0,param: UInt8 = 0) -> PlaybackCell {
        .init(note: note,instrument: instrument,volumeColumn: 0,effectType: fx,effectParam: param)
    }
    private func song(_ rows: [[PlaybackCell]],linear: Bool = true,fine: Int = 0,
        speed: Int = 3,secondRelative: Int? = nil) -> PlaybackSong {
        func instrument(_ index: Int,_ relative: Int) -> PlaybackInstrument {
            let sample = PlaybackSample(instrumentIndex: index,sampleIndex: 0,
                pcm: (0..<256).map { Float(sin(Double($0) * .pi / 8) / 16) },volume: 0.5,panning: 128,
                relativeNote: relative,finetune: fine,baseSampleRate: 8363,loopStart: 0,loopLength: 256,loopType: 1)
            return .init(index: index,samples: [sample],noteSampleMap: Array(repeating: 0,count: 96))
        }
        var instruments = [1:instrument(1,0)]
        if let relative = secondRelative { instruments[2] = instrument(2,relative) }
        return .init(title: "Public bounded pitch",orders: [.init(orderIndex: 0,patternIndex: 0)],
            patternsByIndex: [0:.init(index: 0,rows: rows.enumerated().map { .init(index: $0.offset,cells: $0.element) })],
            instrumentsByIndex: instruments,restartOrderIndex: 0,endBehavior: .stopAtEnd,
            initialTiming: .init(speed: speed,bpm: 125),usesLinearFrequencyTable: linear)
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
}
