import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Original phase-consumption witnesses executed against the pinned independent FT2 observer.
final class BxTremoloPhaseTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer

    func testBxAndBothOrderedCombinedFamiliesFeedLaterRampTremolo() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for family: UInt8 in [0, 4, 6] {
                let cells = [family == 0 ? c(note: 49, instrument: 1, volume: 0xA8) : c(4, 0x80, note: 49, instrument: 1),
                    c(family, volume: 0xB8), c(14, 0x71), c(7, 0x48), c(7), c(12, 32), c(note: 97)]
                let plan = A.adapt(song(cells, linear: linear), orderIndex: 0, sampleRate: rate)
                let ticks = tremolo(plan, row: 3)
                XCTAssertEqual(ticks.map { $0.1.vibratoPhase }, Array(repeating: family == 0 ? 160 : 224, count: 5))
                XCTAssertEqual(ticks.map { $0.1.outputVolume }, [63, 59, 55, 51, 47])
                XCTAssertEqual(tremolo(plan, row: 4).map { $0.1.outputVolume }, [43, 39, 35, 1, 5])
                XCTAssertEqual(ticks.map { $0.0.scheduledFrame }, (19...23).map { $0 * Int(rate / 50) })
                XCTAssertTrue(ticks.allSatisfy { $0.1.baseVolume == 32 && $0.0.activeEventIndex == 0 })
                XCTAssertEqual(plan.pattern.events.count, 1)
                if family != 0 {
                    let mixed = try XCTUnwrap(plan.diagnostics.vibratoEffects.first { $0.source.rowIndex == 1 })
                    let invocations = mixed.stepUpdates.compactMap(\.vibrato)
                    XCTAssertEqual(invocations.map(\.phaseBefore), [160, 192, 224, 0, 32, 64, 96, 128, 160, 192])
                    XCTAssertEqual(invocations.map(\.phaseAfter), [192, 224, 0, 32, 64, 96, 128, 160, 192, 224])
                }
            }
        } }
    }

    func testSameRowBxUsesEachInvocationPhaseAcrossSignAndByteWrap() {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let plan = A.adapt(song([c(note: 49, instrument: 1, volume: 0xA8), c(14, 0x71),
                c(7, 0x48, volume: 0xB8), c(7, volume: 0xB0), c(), c(note: 97)], linear: linear),
                orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(tremolo(plan, row: 2).map { $0.1.vibratoPhase }, [32, 64, 96, 128, 160])
            XCTAssertEqual(tremolo(plan, row: 2).map { $0.1.outputVolume }, [32, 36, 40, 51, 47])
            XCTAssertEqual(tremolo(plan, row: 3).map { $0.1.vibratoPhase }, [192, 224, 0, 32, 64])
            XCTAssertEqual(tremolo(plan, row: 3).map { $0.1.outputVolume }, [43, 39, 60, 32, 28])
            let native = plan.diagnostics.vibratoEffects.filter { [2, 3].contains($0.source.rowIndex) }
            XCTAssertEqual(native.map(\.phaseAfter), [160, 64])
            XCTAssertEqual(native.flatMap(\.stepUpdates).count, 10)
        } }
    }

    func testEffectColumnControlAndChannelLayoutRemainUnchanged() {
        XCTAssertEqual(MemoryLayout<A.ChannelState>.stride, 1152)
        let plan = A.adapt(song([c(4, 0x80, note: 49, instrument: 1), c(), c(14, 0x71), c(7, 0x48), c(7)]),
            orderIndex: 0, sampleRate: 48_000)
        XCTAssertEqual(tremolo(plan, row: 3).map { $0.1.vibratoPhase }, Array(repeating: 160, count: 5))
        XCTAssertEqual(tremolo(plan, row: 3).map { $0.1.outputVolume }, [63, 59, 55, 51, 47])
    }

    func testInstrumentResetsNoteOnlyCarryAndRampAliases() {
        for linear in [true, false] { for kind in 0...2 { for suppress: UInt8 in [0, 4] {
            let reset = c(note: kind == 0 ? 0 : 53, instrument: kind == 2 ? 0 : 1)
            let plan = A.adapt(song([c(14, 0x40 | suppress), c(note: 49, instrument: 1, volume: 0xA8),
                c(volume: 0xB8), reset, c(14, 0x79), c(7, 0x48), c(7)], linear: linear), orderIndex: 0, sampleRate: 48_000)
            let carried = suppress != 0 || kind == 2
            XCTAssertEqual(tremolo(plan, row: 5).map { $0.1.vibratoPhase }, Array(repeating: carried ? 160 : 0, count: 5))
            XCTAssertEqual(tremolo(plan, row: 5).map { $0.1.outputVolume }, carried ? [63, 59, 55, 51, 47] : [32, 36, 40, 44, 48])
        } } }
        for control: UInt8 in [0x71, 0x75, 0x79, 0x7D] {
            let plan = A.adapt(song([c(note: 49, instrument: 1, volume: 0xA8), c(volume: 0xB8),
                c(14, control), c(7, 0x48), c(), c(7)]), orderIndex: 0, sampleRate: 48_000)
            XCTAssertEqual(tremolo(plan, row: 3).map { $0.1.outputVolume }, [63, 59, 55, 51, 47])
            XCTAssertEqual(tremolo(plan, row: 5).map { $0.1.phaseBefore }, [80, 96, 112, 128, 144])
        }
    }

    func testA0B0EffectiveFxxAndEExHeldInvocations() {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let speeds = A.adapt(song([c(note: 49, instrument: 1, volume: 0xA8), c(15, 1, volume: 0xB0),
                c(15, 3, volume: 0xA0), c(15, 6, volume: 0xB0), c(14, 0x71), c(7, 0x48, volume: 0xB0)], linear: linear),
                orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(tremolo(speeds, row: 5).map { $0.1.vibratoPhase }, [192, 224, 0, 32, 64])
            XCTAssertEqual(tremolo(speeds, row: 5).map { $0.1.outputVolume }, [63, 59, 40, 44, 48])
            let held = A.adapt(song([c(note: 49, instrument: 1, volume: 0xA8), c(14, 0x75),
                c(7, 0x48, volume: 0xB8), c(7), c()], linear: linear,
                secondary: [c(), c(), c(14, 0xE1), c(), c()]), orderIndex: 0, sampleRate: rate)
            let ticks = tremolo(held, row: 2)
            XCTAssertEqual(ticks.map { $0.1.vibratoPhase }, [32, 64, 96, 128, 160, 192, 224, 0, 32, 64, 96])
            XCTAssertEqual(ticks.map { $0.1.outputVolume }, [32, 36, 40, 51, 47, 43, 39, 60, 32, 28, 24])
            XCTAssertEqual(ticks.map { $0.0.scheduledFrame }, (13...23).map { $0 * Int(rate / 50) })
        } }
    }

    func testDelayedBirthAndEmptyOrUnavailableRouteKeepCanonicalPhase() {
        for linear in [true, false] {
            let delayed = A.adapt(song([c(note: 49, instrument: 1, volume: 0xA8),
                c(14, 0xD1, note: 53, instrument: 1, volume: 0xB8), c(14, 0x71), c(7, 0x48)], linear: linear),
                orderIndex: 0, sampleRate: 48_000)
            XCTAssertEqual(tremolo(delayed, row: 3).map { $0.1.vibratoPhase }, Array(repeating: 128, count: 5))
            XCTAssertEqual(tremolo(delayed, row: 3).map { $0.1.outputVolume }, [63, 59, 55, 51, 47])
            XCTAssertEqual(delayed.pattern.events.map(\.scheduledStartFrame), [0, 6720])
            for route in [1, 2] {
                let plan = A.adapt(song([c(12, 32, note: 49, instrument: 1, volume: 0xA8), c(volume: 0xB8),
                    c(14, 0x71), c(7, 0x48, note: 53)], linear: linear, route: route), orderIndex: 0, sampleRate: 48_000)
                XCTAssertEqual(plan.pattern.events.count, 1)
                XCTAssertEqual(plan.pattern.events.first?.row, 3)
                XCTAssertEqual(tremolo(plan, row: 3).map { $0.1.vibratoPhase }, Array(repeating: 160, count: 5))
                XCTAssertEqual(tremolo(plan, row: 3).map { $0.1.outputVolume }, [63, 59, 55, 51, 47])
            }
        }
    }

    func testCutReleaseAndBothRetriggerFamiliesPreserveTheirResetDomains() throws {
        for linear in [true, false] {
            for (effect, parameter, suppress) in [(14, 0xC3, 0), (20, 1, 0), (27, 3, 0), (14, 0x93, 0), (14, 0x93, 4)] {
                let plan = A.adapt(song([c(14, UInt8(0x40 | suppress)), c(note: 49, instrument: 1, volume: 0xA8),
                    c(volume: 0xB8), c(UInt8(effect), UInt8(parameter)), c(14, 0x71), c(12, 32), c(7, 0x48), c(note: 97)],
                    linear: linear), orderIndex: 0, sampleRate: 48_000)
                let reset = effect == 14 && parameter == 0x93 && suppress == 0
                XCTAssertEqual(tremolo(plan, row: 6).map { $0.1.vibratoPhase }, Array(repeating: reset ? 0 : 160, count: 5))
                XCTAssertEqual(tremolo(plan, row: 6).first?.1.outputVolume, reset ? 32 : 63)
                if effect == 20 || parameter == 0xC3 {
                    XCTAssertEqual(plan.pattern.events.count, 1)
                    let quick = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == 28_800 })
                    XCTAssertEqual(quick.durationFrames, 240)
                }
            }
        }
    }

    func testOrdinaryTargetShapeSourceCursorAndEveryDeliveryPartition() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let cells = [c(note: 49, instrument: 1, volume: 0xA8), c(volume: 0xB8), c(14, 0x71),
                c(7, 0x48), c(7), c(12, 32), c(note: 97)]
            let input = song(cells, linear: linear)
            let config = MixerRenderConfig(sampleRate: rate, channelCount: 2)
            let request = PlaybackSongOfflineRenderRequest(song: input, config: config, rows: cells.count)
            let renderer = R(), result = renderer.render(request), plan = result.plan
            let tick = Int(rate / 50), n = 19 * tick
            let target = try XCTUnwrap(plan.xmAudibleTimeline?.updates.first { $0.scheduledFrame == n })
            XCTAssertEqual(target.amplitude, 63 / 64)
            XCTAssertEqual(target.durationFrames, tick)
            for k in [0, 1, tick / 2, tick - 1, tick] {
                XCTAssertEqual(result.block.interleavedPCM[2 * (n + k)],
                    0.5 + (63 / Float(64) - 0.5) * Float(k) / Float(tick), accuracy: 1e-7)
            }
            let mixer = CSoftwareMixer(config: config)
            let slots = SyntheticPatternScheduler(config: plan.timingConfig).schedule(plan.pattern, on: mixer)
            let voice = try XCTUnwrap(slots[0])
            R.schedulePlaybackStateEvents(plan, voiceIndexByEventIndex: [0: voice], on: mixer)
            _ = mixer.render(frames: n)
            let before = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            _ = mixer.render(frames: tick)
            let after = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
            XCTAssertTrue(before.active && after.active)
            XCTAssertEqual(before.channelTag, after.channelTag)
            XCTAssertEqual(before.sampleStep, after.sampleStep)
            XCTAssertEqual(after.samplePosition,
                (before.samplePosition + Double(tick) * before.sampleStep).truncatingRemainder(dividingBy: 256), accuracy: 1e-8)
            for rows in [1, 2, 3] {
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: rows).block.interleavedPCM, result.block.interleavedPCM)
                XCTAssertEqual(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: rows).block.interleavedPCM,
                    result.block.interleavedPCM)
            }
            var streamedPCM: [Float] = []
            let streamed = renderer.renderStreaming(request, chunkFrameCount: 257) { _, _, block in
                streamedPCM += block.interleavedPCM
            }
            try streamed.controlAdmission.requireSuccess()
            XCTAssertEqual(streamedPCM, result.block.interleavedPCM)
            var windowedPCM: [Float] = []
            let windowed = renderer.renderWindowedStreaming(request, windowRows: 2) { _, _, _, block in
                windowedPCM += block.interleavedPCM
            }
            try windowed.controlAdmission.requireSuccess()
            XCTAssertEqual(windowedPCM, result.block.interleavedPCM)
            #if DEBUG
            var seed: UInt64 = 3901
            var boundary = 0, boundaries = [n - 1, n, n + 1, n + tick - 1, n + tick]
            while boundary < result.block.frameCount {
                seed = seed &* 6364136223846793005 &+ 1
                boundary += 1 + Int(seed % 2048)
                if boundary < result.block.frameCount { boundaries.append(boundary) }
            }
            XCTAssertEqual(renderer.renderWindowedAtFrameBoundariesForTesting(request, boundaries: boundaries.sorted()).block.interleavedPCM,
                result.block.interleavedPCM)
            #endif
        } }
    }

    private func tremolo(_ plan: PlaybackSongSyntheticPlan, row: Int)
        -> [(PlaybackSongSyntheticVoiceStateUpdateDiagnostic, PlaybackSongSyntheticTremoloTick)] {
        plan.diagnostics.voiceStateUpdates.compactMap {
            guard $0.source.rowIndex == row, case let .tremolo(tick) = $0.command else { return nil }
            return ($0, tick)
        }
    }

    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                   instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ cells: [PlaybackCell], linear: Bool = true,
                      secondary: [PlaybackCell]? = nil, route: Int = 0) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 1, count: 256),
            volume: 0.5, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopLength: 256, loopType: 1)
        let empty = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [], volume: 0.5,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        let map = (0..<96).map { route != 0 && $0 == 48 ? 1 : 0 }
        return .init(title: "Original Bx ramp tremolo", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { entry in
                .init(index: entry.offset, cells: [entry.element] + (secondary.map { [$0[entry.offset]] } ?? []))
            })],
            instrumentsByIndex: [1: .init(index: 1, samples: route == 1 ? [sample, empty] : [sample], noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
