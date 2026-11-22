import Foundation
import CryptoKit
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class XMPanningEnvelopeTests: XCTestCase {
    func testFT2AllBytesMatchNativeQ16DigestAcrossHeaderEffectAndColumnRoutes() throws {
        var measured = Data()
        for byte in 0...255 {
            let expected = [nativeQ16Gain(256 - byte), nativeQ16Gain(byte)]
            let header = PlaybackSamplePanningPolicy.plannedPan(byte)
            let effect = PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: byte)
            for pan in [header, effect] {
                let actual = [MixerPanLaw.ft2EqualPower.leftGain(for: pan),
                    MixerPanLaw.ft2EqualPower.rightGain(for: pan)]
                XCTAssertEqual(actual, expected, "byte=\(byte) pan=\(pan)")
                XCTAssertEqual(MixerPanLaw.linear.leftGain(for: pan), 1 - max(pan, 0))
                XCTAssertEqual(MixerPanLaw.linear.rightGain(for: pan), 1 + min(pan, 0))
            }
            for gain in [MixerPanLaw.ft2EqualPower.leftGain(for: header),
                         MixerPanLaw.ft2EqualPower.rightGain(for: header)] {
                var word = UInt32(gain * 65_536).littleEndian
                withUnsafeBytes(of: &word) { measured.append(contentsOf: $0) }
            }
            if byte > 0 {
                XCTAssertEqual(expected[1], MixerPanLaw.ft2EqualPower.leftGain(
                    for: PlaybackSamplePanningPolicy.plannedPan(256 - byte)))
            }
        }
        // Unchanged native extraction, pinned ft2-clone 87be425; UInt32LE L,R for bytes 0...255.
        XCTAssertEqual(SHA256.hash(data: measured).map { String(format: "%02x", $0) }.joined(),
            "350aa9724b32ab0a3a48071414775821c92f6a3155dbe83c1ed385f416144b50")
        for nibble in 0...15 {
            let column = PlaybackSongVolumeColumnDecoder.decode(UInt8(0xC0 + nibble))
            XCTAssertEqual(column.appliedPanningValue, 16 * nibble)
            let pan = try XCTUnwrap(column.appliedPan)
            XCTAssertEqual(MixerPanLaw.ft2EqualPower.leftGain(for: pan), nativeQ16Gain(256 - 16 * nibble))
            XCTAssertEqual(MixerPanLaw.ft2EqualPower.rightGain(for: pan), nativeQ16Gain(16 * nibble))
        }
        XCTAssertEqual(MixerPanLaw.ft2EqualPower.leftGain(for: 1), 0.0625)
        XCTAssertEqual(MixerPanLaw.ft2EqualPower.rightGain(for: 1), 0.998046875)
        XCTAssertEqual(MixerMixProfile.ft2.outputScale, 0.3125)
        XCTAssertEqual(MixerRenderConfig().mixProfile, .vtx)
    }

    func testFT2BoundedEnvelopeTargetsAndPanOnlySourceIsolationInBothModesAndRates() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let tick = Int(rate / 50), row = 6 * tick
            let commands = [1: cell(effect: 8, param: 192)]
            for value in [32, 48] {
                let module = song(envelope([(0, value), (100, value)]), header: 64,
                    commands: commands, linear: linear)
                let config = MixerRenderConfig(sampleRate: rate, mixProfile: .ft2)
                let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 8)
                let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
                let product = renderer.render(.init(song: module, config: .init(sampleRate: rate), rows: 8))
                XCTAssertEqual(full.plan, product.plan) // Profiles change coefficients only.
                XCTAssertEqual(full.plan.pattern.events.count, 1)
                XCTAssertEqual(full.plan.xmChannelRows.map { $0.controls.panningValue }, [64,192,192,192,192,192,192,192])
                XCTAssertEqual(full.block.interleavedPCM,
                    renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM)
                let targets = try XCTUnwrap(full.plan.xmAudibleTimeline?.updates)
                for (frame, byte) in [(0, value == 32 ? 64 : 96), (row, value == 32 ? 192 : 224)] {
                    let target = try XCTUnwrap(targets.first { $0.scheduledFrame == frame })
                    XCTAssertEqual(target.amplitude, 1)
                    let settled = frame + tick + 1
                    XCTAssertEqual(full.block.interleavedPCM[settled * 2], 0.25 * nativeQ16Gain(256 - byte) * 0.3125)
                    XCTAssertEqual(full.block.interleavedPCM[settled * 2 + 1], 0.25 * nativeQ16Gain(byte) * 0.3125)
                    let oldLeft: Float = target.pan <= 0 ? 1 : 1 - target.pan
                    let oldRight: Float = target.pan >= 0 ? 1 : 1 + target.pan
                    XCTAssertEqual(product.block.interleavedPCM[settled * 2], 0.25 * oldLeft)
                    XCTAssertEqual(product.block.interleavedPCM[settled * 2 + 1], 0.25 * oldRight)
                }
                if value == 32 {
                    let plain = renderer.render(.init(song: song(header: 64, commands: commands, linear: linear),
                        config: config, rows: 8))
                    XCTAssertEqual(full.block.interleavedPCM, plain.block.interleavedPCM)
                }
                let mixer = CSoftwareMixer(config: config)
                let voices = SyntheticPatternScheduler(config: full.plan.timingConfig).schedule(full.plan.pattern, on: mixer)
                let voice = try XCTUnwrap(voices[0])
                PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(full.plan,
                    voiceIndexByEventIndex: [0: voice], on: mixer)
                _ = mixer.render(frames: row)
                let before = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                let change = try XCTUnwrap(targets.first { $0.scheduledFrame == row })
                XCTAssertTrue(mixer.publishAudibleOutput(change, forVoiceAt: voice))
                let after = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                XCTAssertEqual(before.samplePosition, after.samplePosition)
                XCTAssertEqual(before.sampleStep, after.sampleStep)
                XCTAssertEqual(before.channelTag, after.channelTag)
                XCTAssertEqual(before.gain, after.gain)
                XCTAssertEqual(before.envelopeSemanticState, after.envelopeSemanticState)
                XCTAssertEqual(before.fadeoutValue, after.fadeoutValue)
                XCTAssertTrue(after.loaded && after.active)
                _ = mixer.render(frames: 2 * tick + 1)
                let advanced = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voice))
                XCTAssertEqual(advanced.samplePosition,
                    (before.samplePosition + Double(2 * tick + 1) * before.sampleStep).truncatingRemainder(dividingBy: 256))
            }
        } }
    }

    private func nativeQ16Gain(_ index: Int) -> Float {
        Float((sqrt(Double(index) / 256) * 65_536).rounded()) / 65_536
    }

    func testNeutralAndDisabledEnvelopePreserveStaticAudioAndFinalTargets() throws {
        for rate in [44_100.0, 48_000] {
            for header: UInt8 in [0, 64, 128, 224, 255] {
                let commands = [1: cell(effect: 8, param: 224), 2: cell(volume: 0x30), 3: cell(instrument: 1)]
                let baseline = render(song(header: header, commands: commands, volumeEnvelope: false), rate)
                for pan in [envelope([(0, 32), (4, 32)], sustain: 1, loop: (0, 1)),
                    PlaybackPanningEnvelope(enabled: false, points: [.init(tick: 0, value: 16)],
                        sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 0)] {
                    let result = render(song(pan, header: header, commands: commands, volumeEnvelope: false), rate)
                    XCTAssertEqual(result.block.interleavedPCM, baseline.block.interleavedPCM)
                    XCTAssertEqual(result.plan.xmAudibleTimeline?.updates, baseline.plan.xmAudibleTimeline?.updates)
                }
            }
        }
    }

    func testObservedIntegerCombinationRuleAndEndpointClampAtBothRates() throws {
        // Project-authored constant curves, observed with the pinned FT2 loader/replayer.
        let cases: [(UInt8, Int, Int)] = [(0, 16, 0), (0, 48, 0), (64, 16, 32), (64, 48, 96),
            (128, 16, 64), (128, 32, 128), (128, 48, 192), (128, 0, 0), (128, 63, 252),
            (128, 64, 252), (224, 16, 208), (224, 48, 240), (255, 0, 254), (255, 64, 255),
            (1, 16, 0), (127, 33, 130), (129, 31, 125)]
        for rate in [44_100.0, 48_000] {
            for (header, value, expectedByte) in cases {
                let result = render(song(envelope([(0, value), (100, value)]), header: header), rate)
                let update = try XCTUnwrap(result.plan.xmAudibleTimeline?.updates.first)
                XCTAssertEqual(update.pan, PlaybackSamplePanningPolicy.plannedPan(expectedByte), accuracy: 1e-7)
                XCTAssertEqual(update.amplitude, 1) // G01 remains one channel/header ownership.
                XCTAssertEqual(update.durationFrames, 0)
                let config = MixerRenderConfig(sampleRate: rate)
                let settled = 2 * Int(rate * 0.005)
                XCTAssertEqual(Array(result.block.interleavedPCM.prefix(2)), [0, 0])
                XCTAssertEqual(result.block.interleavedPCM[settled], 0.25 * config.panLaw.leftGain(for: update.pan), accuracy: 1e-7)
                XCTAssertEqual(result.block.interleavedPCM[settled + 1], 0.25 * config.panLaw.rightGain(for: update.pan), accuracy: 1e-7)
                XCTAssertEqual(result.plan.xmChannelRows.first?.controls.panningValue, Double(header))
            }
        }
    }

    func testMotionSustainLoopReleaseAndResetConsumeExistingClock() throws {
        for rate in [44_100.0, 48_000] {
            let motion = envelope([(0, 32), (4, 16), (8, 48), (12, 32)])
            let plain = render(song(motion), rate).plan
            let targets = try XCTUnwrap(plain.xmAudibleTimeline?.updatesByEvent[0])
            XCTAssertEqual(targets[4].pan, -0.5)
            XCTAssertEqual(targets[8].pan, 64.0 / 127)
            XCTAssertEqual(targets[12].pan, 0)
            XCTAssertEqual(targets.map(\.scheduledFrame), plain.xmEnvelopeTimeline?.updates.map(\.scheduledFrame))
            let held = render(song(envelope([(0, 32), (4, 16), (8, 48), (12, 32)], sustain: 1),
                commands: [2: cell(note: 97)]), rate).plan
            let states = try XCTUnwrap(held.xmEnvelopeTimeline?.updatesByEvent[0])
            XCTAssertEqual(states[4...12].map(\.state.panTick), Array(repeating: 4, count: 9))
            XCTAssertEqual(states[4...12].map(\.state.panValue), Array(repeating: 0.25, count: 9))
            XCTAssertFalse(states[12].state.keyOn)
            // Retain VTX's logical release rule; FT2's raw pan-sustain release quirk is separate.
            XCTAssertEqual(states[13].state.panTick, 5)
            XCTAssertEqual(states[13].state.panValue, 0.375)
            XCTAssertEqual(held.xmAudibleTimeline?.updatesByEvent[0]?[13].pan, -0.25)
            let loop = render(song(envelope([(0, 32), (2, 16), (6, 48), (10, 32)], loop: (1, 2)),
                commands: [2: cell(note: 97)]), rate).plan
            XCTAssertEqual(loop.xmEnvelopeTimeline?.updatesByEvent[0]?.prefix(11).map(\.state.panTick),
                [0, 1, 2, 3, 4, 5, 2, 3, 4, 5, 2])
            XCTAssertEqual(loop.xmAudibleTimeline?.updatesByEvent[0]?[6].pan, -0.5)
            XCTAssertEqual(loop.xmAudibleTimeline?.updatesByEvent[0]?[14].pan, -0.5)
            let carry = render(song(motion, commands: [1: cell(note: 49), 2: cell(instrument: 1), 3: cell(note: 49)]), rate).plan
            XCTAssertEqual(carry.pattern.events.count, 3)
            XCTAssertEqual(carry.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.state.panTick, 6)
            let reset = try XCTUnwrap(carry.xmAudibleTimeline?.updatesByEvent[1]?.first { $0.source.rowIndex == 2 })
            XCTAssertEqual(reset.pan, 0)
            XCTAssertEqual(reset.durationFrames, Int(rate * 0.005))
            XCTAssertTrue(reset.rebaseFromCurrent)
            XCTAssertEqual(carry.xmEnvelopeTimeline?.updatesByEvent[2]?.first?.state.panTick, 6)
        }
    }

    func testLxxPositionsPanOnlyWhenVolumeSustainFlagIsSet() throws {
        for rate in [44_100.0, 48_000] {
            for volumeSustain in [false, true] {
                let pan = envelope([(0, 32), (4, 16), (20, 48)])
                let baseline = render(song(pan, volumeSustain: volumeSustain), rate).plan
                let positioned = render(song(pan, commands: [1: cell(effect: 0x15, param: 8)], volumeSustain: volumeSustain), rate).plan
                if volumeSustain {
                    XCTAssertEqual(positioned.xmEnvelopeTimeline?.updatesByEvent[0]?[6].state.panTick, 8)
                    XCTAssertEqual(positioned.xmEnvelopeTimeline?.updatesByEvent[0]?[6].state.panValue, 0.375)
                    XCTAssertEqual(positioned.xmAudibleTimeline?.updatesByEvent[0]?[6].pan, -0.25)
                } else {
                    XCTAssertEqual(positioned.xmEnvelopeTimeline?.updates.map(\.state.panTick), baseline.xmEnvelopeTimeline?.updates.map(\.state.panTick))
                    XCTAssertEqual(positioned.xmEnvelopeTimeline?.updates.map(\.state.panValue), baseline.xmEnvelopeTimeline?.updates.map(\.state.panValue))
                    XCTAssertEqual(positioned.xmAudibleTimeline?.updates.map(\.pan), baseline.xmAudibleTimeline?.updates.map(\.pan))
                }
                XCTAssertEqual(positioned.xmEnvelopeTimeline?.updatesByEvent[0]?[6].state.volumeTick, 8)
            }
        }
    }

    func testLogicalPanSustainReleaseBoundariesKeepTheAuthoredTailInBothModes() throws {
        let curve = envelope([(0,32),(4,16),(8,48),(12,32)], sustain: 1)
        // Independent release/next-tick vectors; the observed FT2 stale hold is not the oracle.
        let cases: [(Int, PlaybackCell, Int, Int, Int)] = [
            (3, cell(note: 49, instrument: 1, effect: 20, param: 3), 0, 3, 4096),
            (4, cell(note: 49, instrument: 1, effect: 20, param: 4), 0, 4, 6144),
            (5, cell(note: 49, instrument: 1, effect: 20, param: 5), 0, 4, 6144),
            (6, cell(effect: 20), 1, 4, 6144), (6, cell(note: 97), 1, 4, 6144)]
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let tick = Int(rate / 50), config = MixerRenderConfig(sampleRate: rate, mixProfile: .ft2)
            for (release, command, row, position, nextQ8) in cases {
                let module = song(curve, commands: [row: command], linear: linear)
                let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 8)
                let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
                let states = try XCTUnwrap(full.plan.xmEnvelopeTimeline?.updatesByEvent[0])
                XCTAssertEqual(states[release].state.panTick, position)
                XCTAssertEqual(states[release].state.panValue * 16384, release == 3 ? 5120 : 4096)
                XCTAssertFalse(states[release].state.keyOn)
                XCTAssertEqual(states[release + 1].state.panTick, position + 1)
                XCTAssertEqual(states[release + 1].state.panValue * 16384, Float(nextQ8))
                XCTAssertEqual(states[release + 1].scheduledFrame, (release + 1) * tick)
                XCTAssertEqual(full.plan.diagnostics.eventMappings.map(\.instrumentIndex), [1])
                XCTAssertEqual(full.plan.diagnostics.eventMappings.map(\.sampleIndex), [0])
                let target = try XCTUnwrap(full.plan.xmAudibleTimeline?.updatesByEvent[0]?.last {
                    $0.scheduledFrame <= (release + 1) * tick })
                let byte = nextQ8 / 64
                XCTAssertEqual(target.pan, PlaybackSamplePanningPolicy.plannedPan(byte))
                XCTAssertEqual(target.durationFrames, tick)
                let settled = (release + 2) * tick * 2
                XCTAssertEqual(full.block.interleavedPCM[settled], 0.25 * 0.3125 * nativeQ16Gain(256 - byte))
                XCTAssertEqual(full.block.interleavedPCM[settled + 1], 0.25 * 0.3125 * nativeQ16Gain(byte))
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, full.block.interleavedPCM)
                XCTAssertEqual(renderer.render(request, splitFrameCounts: [7 * tick + 1, 41 * tick - 1]).block.interleavedPCM,
                    full.block.interleavedPCM)
#if DEBUG
                let actual = PlaybackSongOfflineRenderSession(request: request)
                let control = PlaybackSongOfflineRenderSession(request: .init(song: song(curve, linear: linear), config: config, rows: 8))
                _ = actual.render(frames: 8 * tick + 1); _ = control.render(frames: 8 * tick + 1)
                let voice = try XCTUnwrap(actual.sourceVoiceForTesting(0))
                XCTAssertEqual(voice.envelopeSemanticState, states[8].state)
                XCTAssertEqual(control.sourceVoiceForTesting(0)?.envelopeSemanticState?.panTick, 4)
                XCTAssertEqual(voice.samplePosition, control.sourceVoiceForTesting(0)?.samplePosition)
                XCTAssertEqual(voice.sampleStep, control.sourceVoiceForTesting(0)?.sampleStep)
                XCTAssertTrue(voice.active)
#endif
            }
            for (pan, expected) in [(envelope([(0,32),(4,16)], sustain: 1), Float(4096)),
                (envelope([(0,32),(4,16),(8,48),(12,32)], sustain: 1, loop: (1,2)), Float(6144))] {
                let plan = render(song(pan, commands: [1: cell(note: 97)], linear: linear), rate).plan
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?[6].state.panTick, 4)
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?[7].state.panTick, 5)
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?[7].state.panValue, expected / 16384)
            }
        } }
    }

    func testLogicalPanReleaseKeepsSilentPCMAndExactEmptyRouteDistinct() throws {
        let pan = envelope([(0,32),(4,16),(8,48),(12,32)], sustain: 1)
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for empty in [false, true] {
            var commands = [1: cell(note: 97), 3: cell(effect: 12, param: 64)]
            if empty { commands[0] = cell(note: 50, instrument: 1) }
            let result = render(song(pan, commands: commands, empty: empty, linear: linear, sampleVolume: 0), rate)
            let states = try XCTUnwrap(result.plan.xmEnvelopeTimeline?.channelUpdates)
            XCTAssertEqual(states[6].state.panTick, 4)
            XCTAssertEqual(states[6].state.panValue, 4096.0 / 16384)
            XCTAssertEqual(states[7].state.panTick, 5)
            XCTAssertEqual(states[7].state.panValue, 6144.0 / 16384)
            XCTAssertEqual(states[7].sampleIndex, empty ? 1 : 0)
            XCTAssertEqual(result.plan.pattern.events.count, empty ? 0 : 1)
            XCTAssertEqual(states[7].sourceEventIndex, empty ? nil : 0)
            let reveal = 18 * Int(rate / 50) * 2
            XCTAssertTrue(result.block.interleavedPCM[..<reveal].allSatisfy { $0 == 0 })
            if empty {
                XCTAssertTrue(result.block.interleavedPCM.allSatisfy { $0 == 0 })
                XCTAssertTrue(result.plan.xmAudibleTimeline?.updates.isEmpty == true)
            } else {
                XCTAssertGreaterThan(result.block.interleavedPCM[reveal + 2 * Int(rate / 50)], 0)
            }
        } } }
    }

    func testLxxRawVolumeSustainGateDoesNotRequireVolumeEnableOrLoop() throws {
        for rate in [44_100.0, 48_000] {
            for flags: UInt8 in 0...7 {
                let pan = envelope([(0, 32), (4, 16), (8, 48), (12, 32)])
                let commands = [2: cell(effect: 0x15, param: 8)]
                let result = render(song(pan, commands: commands, volumeFlags: flags), rate)
                let baseline = render(song(pan, volumeFlags: flags), rate)
                let state = try XCTUnwrap(result.plan.xmEnvelopeTimeline?.updatesByEvent[0]?[12].state)
                XCTAssertEqual(state.panTick, flags & 2 == 0 ? 12 : 8)
                XCTAssertEqual(state.panValue, flags & 2 == 0 ? 0.5 : 0.75)
                XCTAssertEqual(state.volumeTick, flags & 1 == 0 ? 0 : 8)
                let commandFrame = Int(rate / 50) * 12
                XCTAssertEqual(Array(result.block.interleavedPCM[..<(commandFrame * 2)]),
                    Array(baseline.block.interleavedPCM[..<(commandFrame * 2)]))
                if flags & 2 == 0 {
                    XCTAssertEqual(result.plan.xmAudibleTimeline?.updates.map(\.pan), baseline.plan.xmAudibleTimeline?.updates.map(\.pan))
                }
                // The legacy Lxx diagnostic remains the volume-position view.
                XCTAssertEqual(result.plan.diagnostics.envelopePositionEffects.first?.applied, flags & 1 != 0)
            }
        }
    }

    func testLxxZeroMidEndAndBeyondSelectCurrentInterpolatorWithoutClampingClock() throws {
        let points = [(0, 32), (4, 16), (8, 48), (12, 32)]
        for rate in [44_100.0, 48_000] {
            for (position, values) in [(0, [32, 28, 24, 20]), (2, [24, 20, 16, 24]),
                (4, [16, 24, 32, 40]), (8, [48, 44, 40, 36]), (10, [40, 36, 32, 32]),
                (12, [32, 32, 32, 32]), (16, [32, 32, 32, 32]), (255, [32, 32, 32, 32])] {
                let result = render(song(envelope(points), commands: [2: cell(effect: 0x15, param: UInt8(position))], volumeSustain: true), rate)
                let states = try XCTUnwrap(result.plan.xmEnvelopeTimeline?.updatesByEvent[0])
                XCTAssertEqual(states[12..<16].map(\.state.panTick), Array(position..<(position + 4)))
                XCTAssertEqual(states[12..<16].map(\.state.panValue), values.map { Float($0) / 64 })
            }
        }
    }

    func testLxxAtLoopEndWrapsAndPastLoopEndEscapesUntilReset() throws {
        for rate in [44_100.0, 48_000] {
            let pan = envelope([(0, 32), (4, 16), (8, 48), (12, 32)], loop: (1, 2))
            for (position, expected) in [(6, [6, 7, 4, 5, 6, 7]), (8, [4, 5, 6, 7, 4, 5]),
                (10, [10, 11, 12, 13, 14, 15]), (16, [16, 17, 18, 19, 20, 21])] {
                let plan = render(song(pan, commands: [2: cell(effect: 0x15, param: UInt8(position))], volumeSustain: true), rate).plan
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?[12..<18].map(\.state.panTick), expected)
            }
            let reset = render(song(pan, commands: [2: cell(effect: 0x15, param: 10), 3: cell(instrument: 1)], volumeSustain: true), rate).plan
            XCTAssertEqual(reset.xmEnvelopeTimeline?.updatesByEvent[0]?[18..<27].map(\.state.panTick), [0, 1, 2, 3, 4, 5, 6, 7, 4])
            let carry = render(song(pan, commands: [2: cell(effect: 0x15, param: 10), 3: cell(note: 49)], volumeSustain: true), rate).plan
            XCTAssertEqual(carry.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.state.panTick, 16)
        }
    }

    func testLxxReleaseOrderingAndExistingPanSustainBoundary() throws {
        for rate in [44_100.0, 48_000] {
            let pan = envelope([(0, 32), (4, 16), (8, 48), (12, 32)], sustain: 1)
            for commands in [[1: cell(note: 97), 2: cell(effect: 0x15, param: 8)],
                [2: cell(note: 97, effect: 0x15, param: 8)], [2: cell(effect: 0x15, param: 8), 3: cell(note: 97)]] {
                let plan = render(song(pan, commands: commands, volumeSustain: true), rate).plan
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?[12..<16].map(\.state.panTick), [8, 9, 10, 11])
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?[12..<16].map(\.state.panValue), [0.75, 0.6875, 0.625, 0.5625])
            }
            let held = render(song(pan, commands: [2: cell(effect: 0x15, param: 4), 3: cell(note: 97)], volumeSustain: true), rate).plan
            XCTAssertEqual(held.xmEnvelopeTimeline?.updatesByEvent[0]?[12...18].map(\.state.panTick), Array(repeating: 4, count: 7))
            XCTAssertEqual(held.xmEnvelopeTimeline?.updatesByEvent[0]?[19].state.panTick, 5) // Retained G06 logical release.
            let loopEnd = envelope([(0, 32), (4, 16), (8, 48), (12, 32)], sustain: 2, loop: (1, 2))
            for released in [false, true] {
                var commands = [2: cell(effect: 0x15, param: 8)]
                if released { commands[1] = cell(note: 97) }
                let plan = render(song(loopEnd, commands: commands, volumeSustain: true), rate).plan
                XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[0]?[12].state.panTick, released ? 8 : 4)
            }
        }
    }

    func testLxxSilentCarryAndSameCellNoteOrInstrumentResetKeepExactRoutes() throws {
        for rate in [44_100.0, 48_000] {
            let pan = envelope([(0, 32), (4, 16), (8, 48), (12, 32)])
            for reset in [false, true] {
                let result = render(song(pan, commands: [1: cell(note: 50),
                    2: cell(instrument: reset ? 1 : 0, effect: 0x15, param: 8), 3: cell(note: 49)],
                    volumeSustain: true, empty: true), rate)
                let frame = Int(rate / 50) * 12
                let silent = try XCTUnwrap(result.plan.xmEnvelopeTimeline?.channelState(channelIndex: 0, atOrBefore: frame))
                XCTAssertNil(silent.sourceEventIndex)
                XCTAssertEqual(silent.state.panTick, 8)
                XCTAssertEqual(silent.state.panValue, 0.75)
                XCTAssertEqual(result.plan.pattern.events.count, 2)
                XCTAssertEqual(result.plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 0])
                XCTAssertEqual(result.plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.state.panTick, 14)
                XCTAssertTrue(result.block.interleavedPCM[(Int(rate / 50) * 12)..<(Int(rate / 50) * 36)].allSatisfy { $0 == 0 })
            }
            for commands in [[0: cell(note: 49, instrument: 1, effect: 0x15, param: 8)],
                [2: cell(note: 49, effect: 0x15, param: 8)], [2: cell(instrument: 1, effect: 0x15, param: 8)]] {
                let plan = render(song(pan, commands: commands, volumeSustain: true), rate).plan
                let row = commands[0] == nil ? 2 : 0
                let update = try XCTUnwrap(plan.xmEnvelopeTimeline?.updates.first { $0.source.rowIndex == row })
                XCTAssertEqual(update.state.panTick, 8)
                XCTAssertEqual(update.state.volumeTick, 8)
                XCTAssertEqual(plan.pattern.events.count, commands[2]?.note == 49 ? 2 : 1)
            }
        }
    }

    func testLxxPanDoesNotChangeVolumePositioningPCMOrStaticGainOwnership() throws {
        for rate in [44_100.0, 48_000] {
            for flags: UInt8 in [1, 2, 3, 7] {
                let commands = [1: cell(effect: 0x15, param: 2), 2: cell(effect: 0x15, param: 255)]
                let points = [(0, 64), (4, 32), (12, 64)]
                let baseline = song(commands: commands, volumeFlags: flags, volumePoints: points)
                let positioned = song(envelope([(0, 32), (4, 16), (8, 48), (12, 32)]),
                    commands: commands, volumeFlags: flags, volumePoints: points)
                let renderer = PlaybackSongOfflineRenderer(), config = MixerRenderConfig(sampleRate: rate, channelCount: 1)
                let before = renderer.render(.init(song: baseline, config: config, rows: 8))
                let after = renderer.render(.init(song: positioned, config: config, rows: 8))
                XCTAssertEqual(before.block.interleavedPCM, after.block.interleavedPCM)
                if flags & 1 != 0 {
                    XCTAssertEqual(before.plan.xmEnvelopeTimeline?.updates.map(\.state.volumeTick), after.plan.xmEnvelopeTimeline?.updates.map(\.state.volumeTick))
                    XCTAssertEqual(before.plan.xmEnvelopeTimeline?.updates.map(\.state.volumeValue), after.plan.xmEnvelopeTimeline?.updates.map(\.state.volumeValue))
                } else {
                    XCTAssertTrue(after.plan.xmEnvelopeTimeline!.updates.allSatisfy { $0.state.volumeTick == 0 && $0.state.volumeValue == 1 })
                }
                XCTAssertEqual(before.plan.pattern.events.map(\.gain), after.plan.pattern.events.map(\.gain))
                XCTAssertEqual(before.plan.xmChannelRows.map(\.controls.panningValue), after.plan.xmChannelRows.map(\.controls.panningValue))
            }
        }
    }

    func testLxxGateUsesSoundingInstrumentAfterInstrumentOnlySelection() throws {
        for rate in [44_100.0, 48_000] {
            for (soundingFlags, selectedFlags): (UInt8, UInt8) in [(3, 1), (1, 3)] {
                let result = render(song(envelope([(0, 32), (4, 16), (8, 48), (12, 32)]),
                    commands: [2: cell(instrument: 2, effect: 0x15, param: 8)],
                    volumeFlags: soundingFlags, secondVolumeFlags: selectedFlags), rate)
                let update = try XCTUnwrap(result.plan.xmEnvelopeTimeline?.channelState(channelIndex: 0, atOrBefore: Int(rate / 50) * 12))
                XCTAssertEqual(update.instrumentIndex, 1)
                XCTAssertEqual(update.carriedInstrumentIndex, 2)
                XCTAssertEqual(update.state.panTick, soundingFlags & 2 != 0 ? 8 : 0)
                XCTAssertEqual(result.plan.diagnostics.eventMappings.map(\.instrumentIndex), [1])
                XCTAssertEqual(result.plan.pattern.events.count, 1)
            }
        }
    }

    func test8xxAndVolumeColumnPanKeepTheirStoredStateAndConversionBaseline() throws {
        for rate in [44_100.0, 48_000] {
            let result = render(song(envelope([(0, 32), (2, 16), (6, 48), (10, 32)], loop: (1, 2)),
                commands: [1: cell(effect: 8, param: 224), 2: cell(volume: 0xC4)]), rate)
            let targets = try XCTUnwrap(result.plan.xmAudibleTimeline?.updatesByEvent[0])
            let rows = result.plan.xmChannelRows.map(\.controls)
            XCTAssertEqual(rows[1].panningValue, 224)
            XCTAssertEqual(rows[2].panningValue, 64) // C4 supplies the G11 byte; G40 conversion is unchanged.
            XCTAssertEqual(targets[8].pan, rows[1].pan) // Envelope is neutral at tick 4.
            let delta = PlaybackSamplePanningPolicy.plannedPan(232) - PlaybackSamplePanningPolicy.plannedPan(224)
            XCTAssertEqual(targets[9].pan, rows[1].pan + delta)
            XCTAssertEqual(targets[12].pan, rows[2].pan) // Neutral loop position again.
        }
    }

    func testPanOnlyBirthPreservesEarlierAudioAndOneOutputRamp() throws {
        let pan = envelope([(0, 32), (2, 32), (4, 16), (8, 48)])
        for rate in [44_100.0, 48_000] {
            let result = render(song(pan, volumeEnvelope: false), rate)
            let baseline = render(song(volumeEnvelope: false), rate)
            let first = try XCTUnwrap(result.plan.xmAudibleTimeline?.updates.first)
            XCTAssertEqual(first.scheduledFrame, 0)
            XCTAssertNil(first.activation)
            let firstMotion = Int(rate / 50) * 3
            XCTAssertEqual(Array(result.block.interleavedPCM[..<(firstMotion * 2)]),
                Array(baseline.block.interleavedPCM[..<(firstMotion * 2)]))
            let mixer = CSoftwareMixer(config: .init(sampleRate: rate))
            let voices = SyntheticPatternScheduler(config: result.plan.timingConfig).schedule(result.plan.pattern, on: mixer)
            PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(result.plan, voiceIndexByEventIndex: [0: voices[0]!], on: mixer)
            _ = mixer.render(frames: firstMotion + 1)
            let diagnostic = try XCTUnwrap(mixer.voiceDiagnostic(forVoiceAt: voices[0]!))
            XCTAssertNotNil(diagnostic.audibleOutputState)
            XCTAssertNil(diagnostic.gainRamp)
            XCTAssertNil(diagnostic.panRamp)
        }
    }

    func testSilentRoutesAndCompletedSourceKeepClockWithoutCreatingOutput() throws {
        for rate in [44_100.0, 48_000] {
            let module = song(envelope([(0, 32), (24, 8)]), commands: [1: cell(note: 50), 3: cell(note: 49)], empty: true)
            let result = render(module, rate), plan = result.plan
            let rowFrames = Int(rate / 50) * 6
            let silent = try XCTUnwrap(plan.xmEnvelopeTimeline).channelUpdates.filter {
                (rowFrames..<(3 * rowFrames)).contains($0.scheduledFrame)
            }
            XCTAssertTrue(silent.allSatisfy { $0.sourceEventIndex == nil })
            XCTAssertEqual(silent.map(\.state.panTick), Array(6..<18))
            XCTAssertEqual(plan.pattern.events.count, 2)
            XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), [0, 0])
            XCTAssertFalse(plan.xmAudibleTimeline!.updates.contains { (rowFrames..<(3 * rowFrames)).contains($0.scheduledFrame) })
            XCTAssertTrue(result.block.interleavedPCM[(rowFrames * 2)..<(3 * rowFrames * 2)].allSatisfy { $0 == 0 })
            XCTAssertEqual(plan.xmEnvelopeTimeline?.updatesByEvent[1]?.first?.state.panTick, 18)
            XCTAssertEqual(plan.xmAudibleTimeline?.updatesByEvent[1]?.first?.pan, -0.5625)
            let ended = render(song(envelope([(0, 32), (24, 8)]), oneShot: true), rate)
            XCTAssertGreaterThan(ended.plan.xmEnvelopeTimeline!.updates.last!.state.panTick, 0)
            XCTAssertTrue(ended.block.interleavedPCM[(Int(rate / 50) * 4)...].allSatisfy { $0 == 0 })
        }
    }

    func testWholeWindowAndRuntimePlanParityForEveryTransition() throws {
        for rate in [44_100.0, 48_000] {
            for profile in MixerMixProfile.allCases {
                let module = song(envelope([(0, 32), (2, 16), (6, 48), (10, 32)], loop: (1, 2)),
                    commands: [1: cell(effect: 8, param: 224), 2: cell(instrument: 1),
                        3: cell(effect: 15, param: 250), 4: cell(note: 97),
                        5: cell(effect: 0x15, param: 0), 6: cell(effect: 0x15, param: 8),
                        7: cell(effect: 0x15, param: 16)], volumeSustain: true)
                let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
                let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 8)
                let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
                XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, full.plan)
                for window in [1, 2, 3] {
                    XCTAssertEqual(renderer.renderWindowed(request, windowRows: window).block.interleavedPCM, full.block.interleavedPCM)
                }
                let mixer = CSoftwareMixer(config: config)
                let voices = SyntheticPatternScheduler(config: full.plan.timingConfig).schedule(full.plan.pattern, on: mixer)
                PlaybackSongOfflineRenderer.schedulePlaybackStateEvents(full.plan, voiceIndexByEventIndex: [0: voices[0]!], on: mixer)
                for update in full.plan.xmAudibleTimeline!.updates {
                    let boundary = update.scheduledFrame + max(1, update.durationFrames / 2)
                    _ = mixer.render(frames: boundary - Int(mixer.currentFrame))
                    XCTAssertEqual(mixer.voiceDiagnostic(forVoiceAt: voices[0]!)?.audibleOutputState,
                        full.plan.xmAudibleTimeline?.state(eventIndex: 0, before: boundary, config: config))
                }
            }
        }
    }

    func testPanQ8IndependentNativeVectorsAndFinalTargetsPreserveRawPoints() throws {
        // Original recipe-v1 stimuli, executed by pinned ft2-clone 87be425.
        let vectors: [([(Int, Int)], [Int])] = [
            ([(0, 13), (6, 14), (13, 61)], [3328,3370,3412,3454,3496,3538,3584,5302]),
            ([(0, 61), (7, 13)], [15616,13861,12106,10351,8596,6841,5086,3328]),
            ([(0, 13), (7, 64)], [3328,5156,6984,8812,10640,12468,14296,16128]),
            ([(0, 64), (7, 13)], [16128,14300,12472,10644,8816,6988,5160,3328]),
            ([(0, 0), (3, 63)], [0,5376,10752,16128])]
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for (points, expected) in vectors {
                let curve = envelope(points), module = song(curve, linear: linear)
                let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: rate)
                let states = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[0])
                let targets = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[0])
                XCTAssertEqual(module.instrumentsByIndex[1]?.panningEnvelope, curve)
                XCTAssertEqual(plan.diagnostics.eventMappings.first?.instrumentIndex, 1)
                XCTAssertEqual(plan.diagnostics.eventMappings.first?.sampleIndex, 0)
                for (tick, q8) in expected.enumerated() {
                    let state = states[tick], byte = q8 / 64
                    XCTAssertEqual(state.state.panTick, tick)
                    XCTAssertEqual(state.scheduledFrame, tick * Int(rate / 50))
                    XCTAssertEqual(state.state.panValue, Float(q8) / 16384)
                    XCTAssertEqual(state.state.volumeValue, 1)
                    let target = try XCTUnwrap(targets.last { $0.scheduledFrame <= state.scheduledFrame })
                    XCTAssertEqual(target.pan, PlaybackSamplePanningPolicy.plannedPan(byte), accuracy: 1e-7)
                    var output = MixerAudibleOutputState()
                    output.publish(target, config: .init(sampleRate: rate, mixProfile: .ft2))
                    XCTAssertEqual(output.target, [1, nativeQ16Gain(256 - byte), nativeQ16Gain(byte)])
                }
            }
        } }
    }

    func testPanQ8SubQuantumSlopesArriveExactlyAcrossThe64RowWindow() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for (start, end) in [(32,33), (33,32)] {
                let module = song(envelope([(0,start),(512,end)]), linear: linear, rowCount: 96)
                for profile in MixerMixProfile.allCases {
                    let config = MixerRenderConfig(sampleRate: rate, mixProfile: profile)
                    let request = PlaybackSongOfflineRenderRequest(song: module, config: config, rows: 96)
                    let renderer = PlaybackSongOfflineRenderer(), full = renderer.render(request)
                    let states = try XCTUnwrap(full.plan.xmEnvelopeTimeline?.updatesByEvent[0])
                    XCTAssertEqual(states[511].state.panValue, Float(start) / 64)
                    XCTAssertEqual(states[512].state.panValue, Float(end) / 64)
                    XCTAssertEqual(states[512].scheduledFrame, 512 * Int(rate / 50))
                    XCTAssertEqual(renderer.renderWindowed(request, windowRows: 64).block.interleavedPCM, full.block.interleavedPCM)
                    XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate).plan, full.plan)
                }
            }
        } }
    }

    func testPanQ8PendingCarryAndResetKeepBoundedOutputInBothProfiles() throws {
        let commands = [1: cell(instrument: 2), 2: cell(note: 49)]
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for extreme in [false, true] {
                let old = envelope([(0,13),(7,extreme ? 61 : 19)])
                let next = envelope([(0,13),(13,extreme ? 61 : 29)])
                let module = song(old, commands: commands, linear: linear, secondPan: next)
                let plan = PlaybackSongSyntheticAdapter.adapt(module, orderIndex: 0, sampleRate: rate)
                let states = try XCTUnwrap(plan.xmEnvelopeTimeline?.updatesByEvent[1])
                XCTAssertEqual(states[0].state.panTick, 6)
                XCTAssertEqual(states[1].state.panTick, 7)
                XCTAssertEqual(states[1].state.panValue, Float(extreme ? 15613 : 4861) / 16384)
                XCTAssertEqual(states[2].state.panValue, extreme ? 1 : Float(5080) / 16384)
                XCTAssertEqual(states[7].state.panTick, 13)
                XCTAssertEqual(states[7].state.panValue, Float(extreme ? 61 : 29) / 64)
                XCTAssertEqual(plan.pattern.events.count, 2)
                XCTAssertEqual(plan.diagnostics.eventMappings.last?.instrumentIndex, 2)
                XCTAssertEqual(plan.diagnostics.eventMappings.last?.sampleIndex, 0)
                let frame = 14 * Int(rate / 50)
                let target = try XCTUnwrap(plan.xmAudibleTimeline?.updatesByEvent[1]?.last { $0.scheduledFrame <= frame })
                let byte = extreme ? 252 : 79
                XCTAssertEqual(target.pan, PlaybackSamplePanningPolicy.plannedPan(byte), accuracy: 1e-7)
                for profile in MixerMixProfile.allCases {
                    var output = MixerAudibleOutputState()
                    output.publish(target, config: .init(sampleRate: rate, mixProfile: profile))
                    if extreme {
                        // Native reference emits byte 0 here. Approved G06 policy retains 252.
                        XCTAssertGreaterThan(output.target[2], output.target[1])
                        XCTAssertGreaterThan(output.target[1], 0)
                    }
                }
            }
            let reset = PlaybackSongSyntheticAdapter.adapt(song(envelope([(0,64),(7,13)]),
                commands: [1: cell(instrument: 1)], linear: linear), orderIndex: 0, sampleRate: rate)
            let state = try XCTUnwrap(reset.xmEnvelopeTimeline?.updatesByEvent[0]?[6])
            XCTAssertEqual(state.state.panTick, 0)
            XCTAssertEqual(state.state.panValue, Float(63) / 64)
        } }
    }

    private func envelope(_ points: [(Int, Int)], sustain: Int? = nil, loop: (Int, Int)? = nil) -> PlaybackPanningEnvelope {
        .init(enabled: true, points: points.map { .init(tick: $0.0, value: $0.1) }, sustainPointIndex: sustain,
            loopStartPointIndex: loop?.0, loopEndPointIndex: loop?.1, typeFlags: 1 | (sustain == nil ? 0 : 2) | (loop == nil ? 0 : 4))
    }

    private func cell(note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(_ pan: PlaybackPanningEnvelope = .disabled, header: UInt8 = 128, commands: [Int: PlaybackCell] = [:],
                      volumeEnvelope: Bool = true, volumeSustain: Bool = false, empty: Bool = false, oneShot: Bool = false,
                      volumeFlags: UInt8? = nil, volumePoints: [(Int, Int)] = [(0, 64), (100, 64)], secondVolumeFlags: UInt8? = nil,
                      linear: Bool = true, secondPan: PlaybackPanningEnvelope? = nil, rowCount: Int = 8,
                      sampleVolume: Float = 1) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 256),
            volume: sampleVolume, panning: header, relativeNote: 0, finetune: 0, baseSampleRate: 8_363,
            loopStart: 0, loopLength: oneShot ? 0 : 256, loopType: oneShot ? 0 : 1)
        var map = Array(repeating: 0, count: 96)
        if empty { map[49] = 1 }
        let flags = volumeFlags ?? (volumeEnvelope ? (volumeSustain ? 3 : 1) : 0)
        let volume = PlaybackVolumeEnvelope(enabled: flags & 1 != 0, points: volumePoints.map { .init(tick: $0.0, value: $0.1) },
            sustainPointIndex: flags & 2 == 0 ? nil : 1, loopStartPointIndex: flags & 4 == 0 ? nil : 0,
            loopEndPointIndex: flags & 4 == 0 ? nil : volumePoints.count - 1, typeFlags: flags, fadeout: 0)
        var instruments = [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: volume, panningEnvelope: pan, noteSampleMap: map)]
        if let otherFlags = secondVolumeFlags ?? secondPan.map({ _ in flags }) {
            let otherVolume = PlaybackVolumeEnvelope(enabled: otherFlags & 1 != 0, points: volume.points,
                sustainPointIndex: otherFlags & 2 == 0 ? nil : 1, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: otherFlags, fadeout: 0)
            let otherSample = PlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: sample.pcm, volume: 1,
                panning: header, relativeNote: 0, finetune: 0, baseSampleRate: 8_363, loopStart: 0, loopLength: 256, loopType: 1)
            instruments[2] = .init(index: 2, samples: [otherSample], volumeEnvelope: otherVolume, panningEnvelope: secondPan ?? pan, noteSampleMap: map)
        }
        return PlaybackSong(title: "Public G06 control", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<rowCount).map { row in
                .init(index: row, cells: [commands[row] ?? (row == 0 ? cell(note: 49, instrument: 1) : cell())])
            })], instrumentsByIndex: instruments,
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear,
            xmSampleSlotProvenanceByInstrument: empty ? [1: [.init(sampleIndex: 1, decodedPayloadLength: 0,
                isCanonicalEmptySlotHeader: true, volume: 0, panning: 0, finetune: 0, relativeNote: 0)]] : [:])
    }

    private func render(_ module: PlaybackSong, _ rate: Double) -> PlaybackSongOfflineRenderResult {
        PlaybackSongOfflineRenderer().render(.init(song: module, config: .init(sampleRate: rate), rows: 8))
    }
}
