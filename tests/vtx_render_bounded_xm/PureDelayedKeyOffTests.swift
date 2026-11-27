import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Public original XM plus expectations derived from ordinary release and the row clock.
final class PureDelayedKeyOffTests: XCTestCase {
    private let rates = [44_100.0, 48_000.0]
    private func cell(_ note: UInt8 = 0, _ instrument: UInt8 = 0, _ volume: UInt8 = 0,
                      _ effect: UInt8 = 0, _ parameter: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }
    private func fixture(_ linear: Bool, minimal: Bool = false) throws -> PlaybackSong {
        let name = "pure-delayed-keyoff-v1-\(minimal ? "minimal" : "held")-\(linear ? "linear" : "amiga").xm"
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/" + name).path
        return try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: path), modulePath: path)
    }
    private func song(_ base: PlaybackSong, target: PlaybackCell, speed: Int = 6, channel: Int = 0,
                      delays: [UInt8] = [2], fxx: UInt8? = nil, prefix: PlaybackCell? = nil,
                      following: PlaybackCell? = nil, instruments: [Int: PlaybackInstrument]? = nil) -> PlaybackSong {
        var rows = base.patternsByIndex[0]!.rows.map(\.cells)
        for row in rows.indices { rows[row].swapAt(0, channel) }
        if let prefix { rows[0][channel] = prefix; rows[1][channel] = cell() }
        rows[2] = Array(repeating: cell(), count: 4); rows[2][channel] = target
        let controls = (0..<4).filter { $0 != channel }
        for (index, value) in delays.enumerated() { rows[2][controls[index]] = cell(0, 0, 0, 14, 0xE0 | value) }
        if let fxx { rows[2][controls.last!] = cell(0, 0, 0, 15, fxx) }
        if let following { rows[3][channel] = following }
        return .init(title: base.title, orders: base.orders,
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: instruments ?? base.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
            initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: base.usesLinearFrequencyTable,
            xmSampleSlotProvenanceByInstrument: base.xmSampleSlotProvenanceByInstrument)
    }
    private func adapt(_ input: PlaybackSong, _ rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
    }
    private func ticks(_ plan: PlaybackSongSyntheticPlan, row: Int = 2, channel: Int = 0) -> [PlaybackXMChannelUpdate] {
        (plan.xmEnvelopeTimeline?.channelUpdates ?? []).filter { $0.source.rowIndex == row && $0.channelIndex == channel }
    }
    // The fixture holds point 1 at tick 2. A release holds it once, then follows signed Q8 segments.
    private func q8(_ tick: Int, pan: Bool = false) -> Int {
        if tick < 8 { return (pan ? 10240 : 12288) + (pan ? -682 : -1365) * (tick - 2) }
        if tick < 20 { return (pan ? 6144 : 4096) + (pan ? 170 : -341) * (tick - 8) }
        return pan ? 8192 : 0
    }

    func testActualDispatchAndIndependentReleaseCurveAcrossModesRatesAndSpeeds() throws {
        let cases = [(6,0,0),(6,0,2),(6,1,0),(6,1,1),(6,1,2),(6,2,2),(6,5,2),
                     (6,6,2),(6,15,2),(1,0,2),(1,1,2),(3,2,2),(3,3,2),(16,15,1)]
        for linear in [true, false] { let base = try fixture(linear)
            for rate in rates { for (speed, delay, cycles) in cases {
                let p = adapt(song(base, target: cell(97,0,0,14,UInt8(0xD0 + delay)), speed: speed,
                                   delays: [UInt8(cycles)]), rate)
                let expected = delay < speed ? (0...cycles).map { $0 * speed + delay } : []
                let releases = p.diagnostics.keyOffEvents.filter { $0.source.rowIndex == 2 }
                XCTAssertEqual(releases.map(\.syntheticTick), expected)
                XCTAssertEqual(releases.map(\.scheduledFrame), expected.map { Optional((2 * speed + $0) * Int(rate / 50)) })
                XCTAssertEqual(p.diagnostics.rowTiming[2].actualTickCount, speed * (cycles + 1))
                XCTAssertEqual(p.pattern.events.count, 1)
                XCTAssertEqual(p.diagnostics.eventMappings.first?.instrumentIndex, 1)
                XCTAssertEqual(p.diagnostics.eventMappings.first?.sampleIndex, 0)
                XCTAssertFalse(p.diagnostics.eventMappings.first!.firstPlayableSampleFallbackUsed)
                XCTAssertFalse(p.rowEntryTriggerResetFacts.facts.contains { $0.syntheticRow == 2 })
                XCTAssertFalse(p.delayedInstrumentResetFacts.facts.contains { $0.syntheticRow == 2 })
                for update in ticks(p) {
                    let elapsed = update.tick, released = expected.first.map { elapsed >= $0 } ?? false
                    let position = released ? 2 + elapsed - expected[0] : 2
                    let clock = try XCTUnwrap(p.canonicalTickClock.coordinate(syntheticRow: 2, tick: elapsed, channel: 0))
                    XCTAssertEqual(clock.localEffectPhase, elapsed % speed)
                    XCTAssertEqual(clock.isFreshEntry, elapsed == 0)
                    XCTAssertEqual(update.state.keyOn, !released)
                    XCTAssertEqual(update.state.volumeTick, position)
                    XCTAssertEqual(update.state.panTick, position)
                    XCTAssertEqual(update.state.volumeValue, Float(q8(position)) / 16384)
                    XCTAssertEqual(update.state.panValue, Float(q8(position, pan: true)) / 16384)
                    XCTAssertEqual(update.state.fadeoutAccumulator, released ? max(0,32768 - (elapsed - expected[0] + 1) * 256) : 32768)
                    XCTAssertEqual(update.sourceEventIndex, 0)
                }
            } }
        }
    }

    func testNonzeroFxxAndLastGlobalDelayWriterAreChannelOrdered() throws {
        for linear in [true, false] { let base = try fixture(linear)
            for rate in rates { for channel in [0,3] { for command: UInt8 in [1,3,6,150] {
                for delays: [UInt8] in [[0,2],[2,0]] {
                    let p = adapt(song(base, target: cell(97,0,0,14,0xD1), channel: channel, delays: delays, fxx: command), rate)
                    let speed = command < 32 ? Int(command) : 6, bpm = command >= 32 ? Int(command) : 125
                    let expected = speed > 1 ? (0...Int(delays.last!)).map { $0 * speed + 1 } : []
                    let release = p.diagnostics.keyOffEvents.filter { $0.source.rowIndex == 2 && $0.channelIndex == channel }
                    XCTAssertEqual(release.map(\.syntheticTick), expected)
                    XCTAssertEqual(release.map(\.scheduledFrame), expected.map { Optional(12 * Int(rate/50) + $0 * Int(rate*2.5/Double(bpm))) })
                    XCTAssertEqual(p.diagnostics.rowTiming[2].effectiveSpeed, speed)
                    XCTAssertEqual(p.diagnostics.rowTiming[2].effectiveBPM, bpm)
                }
            } } }
        }
    }

    func testNativeDueFramePCMAndWholeWindowStreamAndContinuation() throws {
        for linear in [true, false] { for rate in rates { for held in [false,true] {
            let input = try fixture(linear, minimal: !held), p = adapt(input, rate), due = (held ? 13 : 7) * Int(rate/50)
            XCTAssertEqual(p.diagnostics.keyOffEvents.first?.scheduledFrame, due)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate, channelCount: 1), rows: held ? 6 : 2)
            let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
            let event = try XCTUnwrap(full.plan.pattern.events.first), duration = Int(rate/50)
            let old: Float = 0.75 * 0.75, first = old * 32512 / 32768
            let next = Float(0.75) * Float(10923)/16384 * 32256/32768
            XCTAssertEqual(full.plan.xmAudibleTimeline?.updatesByEvent[0]?.first { $0.scheduledFrame == due }?.amplitude, first)
            for offset in [-1,0,1,duration/2,duration-1,duration,duration+1] {
                let frame = due + offset, position = (Double(frame) * event.playbackStep).truncatingRemainder(dividingBy: 256)
                let index = Int(position), fraction = Float(position - Double(index))
                let sample = event.sample.monoPCM[index] + (event.sample.monoPCM[(index+1)%256] - event.sample.monoPCM[index]) * fraction
                let gain = offset < 0 ? old : offset < duration ? old + (first-old) * Float(offset)/Float(duration)
                    : first + (next-first) * Float(offset-duration)/Float(duration)
                XCTAssertEqual(full.block.interleavedPCM[frame], sample * gain, accuracy: 0.0000001)
            }
            let runtime = RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate)
            let before = UserLoopProducerPCMTests.Consumer(rate: rate)
            _ = try before.render([(runtime,due)], partitions: [127,31])
            XCTAssertTrue(try XCTUnwrap(before.mixer.voiceDiagnostic(forVoiceAt: before.voices[0]!)?.envelopeSemanticState).keyOn)
            let after = UserLoopProducerPCMTests.Consumer(rate: rate)
            _ = try after.render([(runtime,due+1)], partitions: [127,31])
            let voice = try XCTUnwrap(after.mixer.voiceDiagnostic(forVoiceAt: after.voices[0]!))
            XCTAssertFalse(try XCTUnwrap(voice.envelopeSemanticState).keyOn)
            XCTAssertEqual(voice.sampleStep, event.playbackStep)
            XCTAssertEqual(voice.samplePosition, (Double(due+1) * event.playbackStep).truncatingRemainder(dividingBy: 256))
            for rows in [1,3] { XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, full.block.interleavedPCM) }
            var stream = [Float]()
            _ = renderer.renderStreaming(request, chunkFrameCount: 997) { _,_,block in stream += block.interleavedPCM }
            XCTAssertEqual(stream, full.block.interleavedPCM)
#if DEBUG
            for offset in [-1,0,1] {
                XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: [due+offset]).block.interleavedPCM, full.block.interleavedPCM)
            }
#endif
            XCTAssertEqual(runtime.plan, full.plan)
            XCTAssertEqual(try UserLoopProducerPCMTests.Consumer(rate: rate).render([(runtime,request.boundedFrameCount)], partitions: [1,127,31,509]), full.block.interleavedPCM)
            for cap in [1,3] {
                let producer = try PlaybackSongUserLoopProducer(song: input, initialPosition: input.startPosition!,
                    sampleRate: rate, sourceGeneration: 7, transportEpoch: 9, mode: .finiteSong)
                var batches = [(RuntimeCMixerAdapterEventPlan,Int)]()
                repeat {
                    let batch = try producer.next(minimumHorizonFrames: Int.max, maximumRows: cap)
                    batches.append((batch.adapterPlan,batch.endFrame))
                    if batch.terminalStopReason != nil { break }
                } while batches.count < 8
                XCTAssertEqual(try UserLoopProducerPCMTests.Consumer(rate: rate).render(batches, partitions: [1,127,31,509]), full.block.interleavedPCM)
            }
        } } }
    }

    func testReleasedEmptyCompletedAndColdRoutesKeepHonestOwnership() throws {
        for linear in [true,false] { let base = try fixture(linear)
            for rate in rates {
                for prefix in [cell(),cell(0,1),cell(51,1)] {
                    let input = song(base, target: cell(97,0,0,14,0xD1), prefix: prefix, following: cell(49))
                    let p = adapt(input,rate)
                    XCTAssertFalse(p.diagnostics.eventMappings.contains { $0.source.rowIndex == 2 })
                    let releases = p.diagnostics.keyOffEvents.filter { $0.source.rowIndex == 2 }
                    XCTAssertEqual(releases.map(\.syntheticTick),[1,7,13])
                    XCTAssertTrue(releases.allSatisfy { $0.activeEventIndex == nil &&
                        $0.reason == (prefix.instrument == 0 ? .noActiveVoice : .releasedSilentChannel) })
                    XCTAssertTrue(ticks(p).filter { $0.tick >= 1 }.allSatisfy { !$0.state.keyOn })
                    // Selection alone starts no envelope clock; an explicit empty note does.
                    if prefix.note == 51 {
                        XCTAssertEqual(ticks(p).count,18)
                        let entry = try XCTUnwrap(ticks(p).first)
                        XCTAssertTrue(entry.state.keyOn)
                        XCTAssertNil(entry.sourceEventIndex)
                    } else {
                        XCTAssertTrue(ticks(p).isEmpty)
                    }
                    let cold = PlaybackSongSyntheticAdapter.adapt(input,startOrderIndex: 0,orderCount: 1,sampleRate: rate,
                        initialPosition: .init(orderIndex: 0,patternIndex: 0,rowIndex: 2))
                    XCTAssertTrue(cold.pattern.events.isEmpty)
                }
                var instruments = base.instrumentsByIndex
                let old = instruments[1]!, sample = old.samples[0]
                instruments[1] = .init(index: 1, samples: [.init(instrumentIndex: 1,sampleIndex: 0,pcm: [0.25,0.25],
                    volume: sample.volume,panning: sample.panning,relativeNote: 0,finetune: 0,baseSampleRate: sample.baseSampleRate)],
                    volumeEnvelope: old.volumeEnvelope,panningEnvelope: old.panningEnvelope,noteSampleMap: old.noteSampleMap)
                let completed = adapt(song(base,target: cell(97,0,0,14,0xD1),instruments: instruments),rate)
                XCTAssertEqual(completed.pattern.events.count,1)
                XCTAssertTrue(try XCTUnwrap(ticks(completed).first).state.keyOn)
                XCTAssertFalse(PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: 0,at: 13 * Int(rate/50),plan: completed))
                XCTAssertFalse(try XCTUnwrap(ticks(completed).first { $0.tick == 1 }).state.keyOn)
                // A genuine prior sounding release, rather than an unplayed source, continues its fadeout.
                var rows = base.patternsByIndex[0]!.rows.map(\.cells); rows[1][0] = cell(97)
                let warm = PlaybackSong(title: base.title,orders: base.orders,
                    patternsByIndex: [0: .init(index: 0,rows: rows.enumerated().map { .init(index:$0.offset,cells:$0.element) })],
                    instrumentsByIndex: base.instrumentsByIndex,restartOrderIndex: 0,endBehavior: .stopAtEnd,
                    usesLinearFrequencyTable: linear)
                XCTAssertEqual(ticks(adapt(warm,rate)).prefix(2).map { $0.state.fadeoutAccumulator },[30976,30720])
            }
        }
    }

    func testDisabledEnvelopeZeroFadeoutAndNoEscapeToNextGeneration() throws {
        for linear in [true,false] { let base = try fixture(linear)
            for rate in rates { for enabled in [false,true] { for fadeout in [0,256] {
                var instruments = base.instrumentsByIndex; let old = instruments[1]!
                let envelope = PlaybackVolumeEnvelope(enabled: enabled,points: old.volumeEnvelope.points,sustainPointIndex: 1,
                    loopStartPointIndex: nil,loopEndPointIndex: nil,typeFlags: enabled ? 3 : 0,fadeout: fadeout)
                instruments[1] = .init(index: 1,samples: old.samples,volumeEnvelope: envelope,
                    panningEnvelope: old.panningEnvelope,noteSampleMap: old.noteSampleMap)
                let p = adapt(song(base,target: cell(97,0,0,14,0xD1),instruments: instruments),rate)
                XCTAssertTrue(ticks(p)[0].state.keyOn)
                XCTAssertFalse(ticks(p)[1].state.keyOn)
                XCTAssertEqual(ticks(p)[1].state.fadeoutAccumulator,32768-fadeout)
                if !enabled { XCTAssertEqual(p.xmAudibleTimeline?.updatesByEvent[0]?.first { $0.scheduledFrame == 13 * Int(rate/50) }?.amplitude,0) }
            } }
                let escaped = adapt(song(base,target: cell(97,0,0,14,0xD6),following: cell(53,2)),rate)
                XCTAssertFalse(escaped.diagnostics.keyOffEvents.contains { $0.source.rowIndex == 2 })
                XCTAssertEqual(escaped.pattern.events.count,2)
                XCTAssertTrue(ticks(escaped,row: 3).allSatisfy { $0.state.keyOn && $0.state.fadeoutAccumulator == 32768 })
            }
        }
    }

    func testOrdinaryDecoratedK20AndDelayedTriggerNeighborsRemainSeparate() throws {
        let base = try fixture(true)
        for target in [cell(97),cell(97,2,0,14,0xD1),cell(97,0,0x30,14,0xD1)] {
            let p = adapt(song(base,target: target),48000)
            XCTAssertEqual(p.diagnostics.keyOffEvents.first { $0.source.rowIndex == 2 }?.syntheticTick,0)
        }
        let masked = adapt(song(base,target: cell(0,2,0,20,0x20)),48000)
        XCTAssertTrue(ticks(masked).allSatisfy { $0.state.keyOn })
        for note: UInt8 in [0,53] {
            let p = adapt(song(base,target: cell(note,2,0,14,0xD1)),48000)
            let births = p.diagnostics.eventMappings.filter { $0.source.rowIndex == 2 }
            XCTAssertEqual(births.map(\.syntheticTick),[1,7,13])
            XCTAssertEqual(births.map(\.sampleIndex),Array(repeating:note == 0 ? 0 : 1,count:3))
        }
        let fresh = adapt(song(base,target: cell(97,0,0,14,0xD1),delays: [0],following: cell(97,0,0,14,0xD1)),48000)
        XCTAssertEqual(fresh.diagnostics.keyOffEvents.filter { [2,3].contains($0.source.rowIndex) }.map(\.syntheticTick),[1,1])
    }
}
