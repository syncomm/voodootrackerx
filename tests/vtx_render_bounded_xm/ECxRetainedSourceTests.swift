import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original public controls: exact routes, asymmetric PCM and literal tick/frame expectations.
final class ECxRetainedSourceTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer

    func testEC0AndEC3QuickOutputKeepsGenerationAndCanonicalVolume() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for cut in [0, 3] {
            let module = song(cut: cut, linear: linear, constant: true)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 5)
            let result = R().render(request), plan = result.plan
            let tick = Int(rate / 50), n = (6 + cut) * tick, d = Int(rate * 0.005)
            let diagnostic = try XCTUnwrap(plan.diagnostics.noteCutEffects.first)
            XCTAssertEqual(diagnostic.scheduledFrame, n)
            XCTAssertEqual(diagnostic.syntheticTick, cut)
            XCTAssertEqual(diagnostic.activeEventIndex, 0)
            XCTAssertTrue(diagnostic.applied)
            XCTAssertEqual(plan.pattern.events.count, 1)
            let row = try XCTUnwrap(plan.xmChannelRows.first { $0.syntheticRow == 1 && $0.channelIndex == 0 })
            XCTAssertEqual(row.controls.baseChannelVolume, cut == 0 ? 0 : 32)
            let blank = try XCTUnwrap(plan.xmChannelRows.first { $0.syntheticRow == 2 && $0.channelIndex == 0 })
            XCTAssertEqual(blank.controls.baseChannelVolume, 0)
            XCTAssertEqual(blank.controls.outputChannelVolume, 0)
            XCTAssertEqual(blank.controls.activeEventIndex, 0)
            let target = plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == n }
            XCTAssertEqual(target?.amplitude, 0)
            XCTAssertEqual(target?.durationFrames, d)
            let pcm = result.block.interleavedPCM
            for k in [0, 1, 32, d / 2, d - 1, d, d + 1] {
                XCTAssertEqual(pcm[2 * (n + k)], 0.125 * max(0, 1 - Float(k) / Float(d)), accuracy: 1e-7)
            }
            XCTAssertTrue(pcm[(2 * (n + d))..<(2 * tick * 18)].allSatisfy { $0 == 0 })
            print("G04 constant linear=\(linear) rate=\(rate) N=\(n) D=\(d) before=\(pcm[2*n-2]) start=\(pcm[2*n]) half=\(pcm[2*(n+d/2)]) end=\(pcm[2*(n+d)])")
        } } }
    }

    func testSilentCursorAndCxxRecoveryMatchProgressedPCMAndAllWindows() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for cut in [0, 3] {
            let module = song(cut: cut, linear: linear)
            let config = MixerRenderConfig(sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 5)
            let renderer = R(), result = renderer.render(request), plan = result.plan
            let tick = Int(rate / 50), n = (6 + cut) * tick, d = Int(rate * 0.005), restore = tick * 18
            let history = R.PitchSourceHistory(plan: plan)
            XCTAssertNil(history.cutFrame(for: 0))
            XCTAssertTrue(R.hasActiveSource(eventIndex: 0, at: restore, plan: plan, pitchHistory: history))
            let mixer = CSoftwareMixer(config: config)
            let slots = SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)
            let voice = try XCTUnwrap(slots[0])
            R.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: voice], on: mixer)
            _ = mixer.render(frames: n)
            let before = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            _ = mixer.render(frames: restore - n)
            let silent = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertTrue(silent.active)
            XCTAssertEqual(silent.sampleStep, before.sampleStep)
            XCTAssertEqual(silent.channelTag, before.channelTag)
            XCTAssertEqual(silent.audibleOutputState?.current, [0, 0, 0])
            XCTAssertEqual(silent.samplePosition,
                (before.samplePosition + Double(restore - n) * before.sampleStep).truncatingRemainder(dividingBy: 2048), accuracy: 1e-8)
            let uncut = R().render(.init(song: song(cut: nil, linear: linear), config: config, rows: 5)).block.interleavedPCM
            for frame in [restore + d, restore + d + 1, restore + tick, restore + 2 * tick] {
                XCTAssertEqual(result.block.interleavedPCM[frame * 2], uncut[frame * 2], accuracy: 1e-7)
            }
            XCTAssertGreaterThan(result.block.interleavedPCM[(restore + d) * 2], 0)
            for rows in [1, 2, 3] {
                let indexed = renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM
                let scan = renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: rows).block.interleavedPCM
                XCTAssertEqual(indexed, scan)
                XCTAssertEqual(indexed, result.block.interleavedPCM)
            }
            #if DEBUG
            let splits = [n - 1, n, n + 1, n + d - 1, n + d, restore - 1, restore, restore + 1, restore + d]
            XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: splits).block.interleavedPCM,
                result.block.interleavedPCM)
            #endif
            print("G04 cursor linear=\(linear) rate=\(rate) event=0 before=\(before.samplePosition) silent=\(silent.samplePosition) step=\(silent.sampleStep)")
        } } }
    }

    func testEffectiveSpeedChannelOrderAndOutOfRowCuts() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] { for cut in [0, 1, 3, 6] { for channel in [0, 2] {
                let rows: [[PlaybackCell]] = (0..<3).map { row in (0..<3).map { col in
                    if col == channel { return row == 0 ? c(note: 49, instrument: 1) :
                        row == 1 ? c(effect: 14, param: UInt8(0xC0 + cut)) : c() }
                    return row == 1 && col == 1 ? c(effect: 15, param: UInt8(speed)) : c()
                } }
                let input = replacingRows(song(cut: nil, linear: linear), rows)
                let plan = A.adapt(input, orderIndex: 0, sampleRate: rate)
                let diagnostic = try XCTUnwrap(plan.diagnostics.noteCutEffects.first)
                XCTAssertEqual(diagnostic.rowSpeed, speed)
                XCTAssertEqual(diagnostic.applied, cut < speed)
                XCTAssertEqual(diagnostic.outOfRow, cut >= speed)
                XCTAssertEqual(diagnostic.scheduledFrame, cut < speed ? (6 + cut) * Int(rate / 50) : nil)
                let after = try XCTUnwrap(plan.xmChannelRows.first { $0.channelIndex == channel && $0.syntheticRow == 2 })
                XCTAssertEqual(after.controls.baseChannelVolume, cut < speed ? 0 : 32)
                XCTAssertEqual(after.controls.activeEventIndex, 0)
                XCTAssertEqual(plan.pattern.events.count, 1)
            } } }
        } }
    }

    func testColumnSlidesAreCausalAcrossTheCutAndPitchStillTargetsSameSource() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for cut in [0, 3] {
            for column: UInt8 in [0x61, 0x71] {
                let module = replacingRows(song(cut: nil, linear: linear), [
                    [c(note: 49, instrument: 1)], [c(volume: column, effect: 14, param: UInt8(0xC0 + cut))],
                    [c(effect: 14, param: 0x11)], [c(effect: 12, param: 32)], [c()]])
                let plan = A.adapt(module, orderIndex: 0, sampleRate: rate)
                let after = try XCTUnwrap(plan.xmChannelRows.first { $0.syntheticRow == 2 })
                XCTAssertEqual(after.controls.baseChannelVolume, column == 0x71 ? 5 - cut : 0)
                let pitch = try XCTUnwrap(plan.diagnostics.finePortamentoUpEffects.first)
                XCTAssertEqual(pitch.activeEventIndex, 0)
                XCTAssertTrue(pitch.execution.sourceEligible)
                XCTAssertFalse(pitch.stepUpdates.isEmpty)
                XCTAssertEqual(plan.pattern.events.count, 1)
                let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 5)
                let renderer = R(preparedPlan: plan)
                XCTAssertEqual(renderer.render(request).block.interleavedPCM,
                    renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM)
            }
        } } }
    }

    func testColdExpiredEmptyAndUnavailableSourcesNeverAcquireAVoice() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let original = song(cut: 3, linear: linear)
            for kind in 0..<4 {
                let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
                    pcm: kind == 2 ? [] : Array(repeating: 0.25, count: 32), volume: 0.5,
                    panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
                let module = replacingRows(original, [[kind == 0 ? c() : c(note: 49, instrument: 1)],
                    [c(effect: 14, param: 0xC3)], [c(effect: 12, param: 32)], [c(effect: 14, param: 0x11)]],
                    instrument: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: kind == 3 ? 7 : 0, count: 96)))
                let plan = A.adapt(module, orderIndex: 0, sampleRate: rate)
                XCTAssertEqual(plan.pattern.events.count, kind == 1 ? 1 : 0)
                XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
                XCTAssertFalse(R.hasActiveSource(eventIndex: 0, at: 18 * Int(rate / 50), plan: plan))
                XCTAssertTrue(plan.diagnostics.finePortamentoUpEffects.allSatisfy { $0.stepUpdates.isEmpty })
                let renderer = R(preparedPlan: plan)
                let request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 4)
                let full = renderer.render(request).block.interleavedPCM
                XCTAssertTrue(full[(12 * Int(rate / 50) * 2)...].allSatisfy { $0 == 0 })
                XCTAssertEqual(full, renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM)
            }
        } }
    }

    func testFiniteCompletionAndOrdinaryReplacementStillRetireTheGeneration() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for finite in [true, false] {
            let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
                pcm: (0..<2048).map { Float(64 + ($0 * 37 % 191)) / 1024 }, volume: 0.5, panning: 128,
                relativeNote: 0, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: finite ? 0 : 2048, loopType: finite ? 0 : 1)
            let alternate = PlaybackSample(instrumentIndex: 1, sampleIndex: 1,
                pcm: Array(repeating: -0.125, count: 2048), volume: 0.25, panning: 128,
                relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 2048, loopType: 1)
            var map = Array(repeating: 0, count: 96); map[60] = 1
            let input = replacingRows(song(cut: nil, linear: linear), [[c(note: 49, instrument: 1)],
                [c(effect: 14, param: 0xC3)], [c()], [c(effect: 12, param: 32)],
                [c(note: 61, instrument: 1)], [c()]],
                instrument: .init(index: 1, samples: [sample, alternate], noteSampleMap: map))
            let renderer = R(), config = MixerRenderConfig(sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: config, rows: 6)
            let full = renderer.render(request), plan = full.plan
            let completion = Int(ceil(2048 / plan.pattern.events[0].playbackStep)), replacement = 24 * Int(rate / 50)
            XCTAssertEqual(plan.pattern.events.count, 2)
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 1])
            XCTAssertNotEqual(plan.pattern.events[0].sample, plan.pattern.events[1].sample)
            XCTAssertEqual(R.hasActiveSource(eventIndex: 0, at: completion, plan: plan), !finite)
            XCTAssertTrue(R.hasActiveSource(eventIndex: 1, at: replacement, plan: plan))
            for rows in [1, 2] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, full.block.interleavedPCM)
                XCTAssertEqual(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: rows).block.interleavedPCM,
                    full.block.interleavedPCM)
            }
            #if DEBUG
            let split = renderer.renderWindowedAtFrameBoundariesForTesting(request,
                boundaries: [completion - 1, completion, completion + 1, replacement - 1, replacement,
                    replacement + 1, replacement + 31, replacement + 32])
            XCTAssertEqual(split.block.interleavedPCM, full.block.interleavedPCM)
            #endif
            if finite {
                XCTAssertTrue(full.block.interleavedPCM[(completion * 2)..<(replacement * 2)].allSatisfy { $0 == 0 })
            }
        } } }
    }

    func testEC0NewbornStartsSilentAndRecoveryRetainsItsGeneration() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for held in [false, true] {
            let cut = c(note: 49, instrument: 1, effect: 14, param: 0xC0)
            let module = replacingRows(song(cut: nil, linear: linear), [[held ? c(note: 49, instrument: 1) : cut],
                [held ? cut : c()], [c()], [c(effect: 12, param: 32)], [c()]])
            let renderer = R(), request = PlaybackSongOfflineRenderRequest(song: module, config: .init(sampleRate: rate), rows: 5)
            let full = renderer.render(request), index = held ? 1 : 0, n = held ? 6 * Int(rate / 50) : 0
            XCTAssertEqual(full.plan.pattern.events.count, held ? 2 : 1)
            let target = try XCTUnwrap(full.plan.xmAudibleTimeline?.updatesByEvent[index]?.first)
            XCTAssertEqual(target.scheduledFrame, n)
            XCTAssertEqual(target.amplitude, 0)
            XCTAssertNil(target.activation)
            // The existing replacement tail remains 32 frames (G03), independently
            // of the newborn's zero target and retained moving source.
            XCTAssertTrue(full.block.interleavedPCM[((n + 32) * 2)..<(18 * Int(rate / 50) * 2)].allSatisfy { $0 == 0 })
            XCTAssertGreaterThan(full.block.interleavedPCM[(18 * Int(rate / 50) + Int(rate * 0.005)) * 2], 0)
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, full.block.interleavedPCM)
        } } }
    }

    func testPingPongDirectionAndCursorContinueWhileSilent() throws {
        for rate in [44_100.0, 48_000] { for linear in [true, false] {
            let source = try XCTUnwrap(song(cut: nil, linear: linear).instrumentsByIndex[1]?.samples.first)
            let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: source.pcm,
                volume: 0.5, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: 2048, loopType: 2)
            var voices = [CSoftwareMixerVoiceDiagnostic]()
            for cut in [nil, 3] as [Int?] {
                let seed = song(cut: cut, linear: linear)
                let module = replacingRows(seed, seed.patternsByIndex[0]!.rows.map(\.cells),
                    instrument: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96)))
                let plan = A.adapt(module, orderIndex: 0, sampleRate: rate), mixer = CSoftwareMixer(config: .init(sampleRate: rate))
                let slot = try XCTUnwrap(SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)[0])
                R.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: slot], on: mixer)
                _ = mixer.render(frames: 18 * Int(rate / 50))
                voices.append(try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: slot)))
            }
            XCTAssertTrue(voices[1].active)
            XCTAssertTrue(voices[1].keyOn)
            XCTAssertEqual(voices[0].samplePosition, voices[1].samplePosition)
            XCTAssertEqual(voices[0].sampleStep, voices[1].sampleStep)
            XCTAssertEqual(voices[0].pingPongDirection, voices[1].pingPongDirection)
            XCTAssertEqual(voices[1].pingPongDirection, -1)
        } }
    }

    private func replacingRows(_ module: PlaybackSong, _ rows: [[PlaybackCell]], instrument: PlaybackInstrument? = nil) -> PlaybackSong {
        .init(title: module.title, orders: module.orders,
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: $0.element) })],
            instrumentsByIndex: instrument.map { [1: $0] } ?? module.instrumentsByIndex,
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: module.initialTiming, usesLinearFrequencyTable: module.usesLinearFrequencyTable)
    }

    private func c(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0,
                   effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(cut: Int?, linear: Bool, constant: Bool = false) -> PlaybackSong {
        let pcm = (0..<2048).map { constant ? Float(0.25) : Float(64 + ($0 * 37 % 191)) / 1024 }
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: pcm, volume: 0.5, panning: 128,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 2048, loopType: 1)
        let rows = [c(note: 49, instrument: 1), cut.map { c(effect: 14, param: UInt8(0xC0 + $0)) } ?? c(),
                    c(), c(effect: 12, param: 32), c()]
        return .init(title: "Original ECx retained source", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: rows.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
