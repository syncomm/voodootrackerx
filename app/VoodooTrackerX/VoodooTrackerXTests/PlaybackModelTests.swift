import AppKit
import AudioToolbox
import XCTest

final class PlaybackModelTests: XCTestCase {
    func testPlaybackSongVolumeColumnDecoderClassifiesSupportedIgnoredAndDeferredCommands() {
        let empty = PlaybackSongVolumeColumnDecoder.decode(0)
        let setVolume = PlaybackSongVolumeColumnDecoder.decode(0x3D)
        let setPanning = PlaybackSongVolumeColumnDecoder.decode(0xCC)
        let slide = PlaybackSongVolumeColumnDecoder.decode(0x6F)
        let vibrato = PlaybackSongVolumeColumnDecoder.decode(0xB0)
        let unsupported = PlaybackSongVolumeColumnDecoder.decode(0x51)

        XCTAssertEqual(empty.command, .none)
        XCTAssertEqual(empty.classification, .ignoredNoOp)
        XCTAssertTrue(empty.ignoredAsEmptyOrNoOp)
        XCTAssertEqual(setVolume.command, .setVolume(value: 45))
        XCTAssertEqual(setVolume.classification, .supported)
        XCTAssertEqual(setVolume.appliedVolumeValue, 45)
        XCTAssertEqual(setVolume.appliedGainMultiplier ?? 0, Float(45) / 64.0)
        XCTAssertEqual(setPanning.command, .setPanning(value: 204))
        XCTAssertEqual(setPanning.appliedPanningValue, 204)
        XCTAssertEqual(setPanning.appliedPan ?? 0, 0.6, accuracy: 0.0001)
        XCTAssertEqual(slide.command, .volumeSlideDown(amount: 15))
        XCTAssertEqual(slide.classification, .supported)
        XCTAssertTrue(slide.applied)
        XCTAssertEqual(slide.slideAmount, 15)
        XCTAssertEqual(slide.slideDirection, .volumeDown)
        XCTAssertEqual(slide.behavior, .rowLevelApproximation)
        XCTAssertEqual(vibrato.command, .vibrato(amount: 0))
        XCTAssertTrue(vibrato.deferred)
        XCTAssertEqual(unsupported.command, .unsupported(rawValue: 0x51))
        XCTAssertTrue(unsupported.deferred)
    }

    func testFocusedVolumeColumnValuesMatchRuntimeDecoder() {
        for rawVolumeColumn in [UInt8(0x20), UInt8(0x24), UInt8(0x40), UInt8(0x42)] {
            let runtimeCommand = PlaybackEffectHandler.volumeColumnCommand(rawVolumeColumn)
            let offlineDiagnostic = PlaybackSongVolumeColumnDecoder.decode(rawVolumeColumn)
            guard case let .setVolume(runtimeValue) = runtimeCommand,
                  case let .setVolume(offlineValue) = offlineDiagnostic.command else {
                return XCTFail("Focused volume column \(rawVolumeColumn) should decode as setVolume")
            }

            XCTAssertEqual(runtimeValue, offlineValue)
            XCTAssertEqual(offlineValue, Int(rawVolumeColumn - 0x10))
            XCTAssertEqual(offlineDiagnostic.classification, .supported)
            XCTAssertEqual(offlineDiagnostic.appliedVolumeValue, offlineValue)
            XCTAssertEqual(offlineDiagnostic.appliedGainMultiplier, Float(offlineValue) / 64.0)
        }
    }

    func testPlaybackTraceFormatterWritesJSONLWithStableFields() throws {
        let event = PlaybackTraceEvent(
            tickIndex: 12,
            orderIndex: 1,
            patternIndex: 3,
            rowIndex: 16,
            tickInRow: 2,
            channelIndex: 0,
            speed: 2,
            bpm: 183,
            tickDuration: 2.5 / 183.0,
            rowDuration: (2.5 / 183.0) * 2.0,
            usesLinearFrequencyTable: true,
            noteValue: 49,
            instrumentIndex: 2,
            sampleIndex: 1,
            relativeNote: -1,
            finetune: 16,
            sourceSampleRate: 8_363,
            audioBufferSampleRate: 44_100,
            effectCommand: "09",
            effectParameter: "02",
            effect: "0902",
            computedVolume: 0.5,
            computedPanning: nil,
            computedPitchSemitones: 0.25,
            targetFrequency: 49_612.5,
            computedRate: 1.125,
            rateBasis: PlaybackPitchCalculator.audioBufferSampleRateBasis,
            computedFrequency: 49_612.5,
            computedVarispeedRate: 1.014545,
            computedPeriodApproximation: 0.8888888889,
            sampleOffset: 512,
            sampleLength: 2048,
            loopStart: 128,
            loopLength: 512,
            loopType: 1,
            loopTypeName: "forward",
            loopEnabled: true,
            loopStartFrame: 128,
            loopEndFrame: 640,
            loopLengthFrames: 512,
            pingPongLoopApplied: false,
            envelopeEnabled: true,
            envelopeTick: 4,
            envelopeValue: 0.75,
            envelopeSustainActive: false,
            envelopeLoopActive: true,
            fadeoutValue: 0.875,
            finalAppliedVolume: 0.4375,
            decision: .triggered,
            decisionReason: "row_note"
        )

        let line = try PlaybackTraceJSONLFormatter.line(for: event)

        XCTAssertEqual(line.last, 0x0A)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["tickIndex"] as? Int, 12)
        XCTAssertEqual(object["orderIndex"] as? Int, 1)
        XCTAssertEqual(object["patternIndex"] as? Int, 3)
        XCTAssertEqual(object["rowIndex"] as? Int, 16)
        XCTAssertEqual(object["tickInRow"] as? Int, 2)
        XCTAssertEqual(object["channelIndex"] as? Int, 0)
        XCTAssertEqual(object["speed"] as? Int, 2)
        XCTAssertEqual(object["bpm"] as? Int, 183)
        XCTAssertTrue(object["runtimeAudioBackend"] is NSNull)
        XCTAssertEqual(object["usesLinearFrequencyTable"] as? Bool, true)
        XCTAssertEqual(object["startedFromDebugSeek"] as? Bool, false)
        XCTAssertTrue(object["requestedStartOrder"] is NSNull)
        XCTAssertTrue(object["actualStartOrder"] is NSNull)
        XCTAssertEqual(object["noteValue"] as? Int, 49)
        XCTAssertEqual(object["instrumentIndex"] as? Int, 2)
        XCTAssertEqual(object["sampleIndex"] as? Int, 1)
        XCTAssertEqual(object["relativeNote"] as? Int, -1)
        XCTAssertEqual(object["finetune"] as? Int, 16)
        XCTAssertEqual(object["sourceSampleRate"] as? Int, 8_363)
        XCTAssertEqual(object["audioBufferSampleRate"] as? Int, 44_100)
        XCTAssertEqual(object["effectCommand"] as? String, "09")
        XCTAssertEqual(object["effectParameter"] as? String, "02")
        XCTAssertEqual(object["effect"] as? String, "0902")
        XCTAssertEqual(object["computedVolume"] as? Double, 0.5)
        XCTAssertTrue(object["computedPanning"] is NSNull)
        XCTAssertEqual(object["targetFrequency"] as? Double, 49_612.5)
        XCTAssertEqual(object["rateBasis"] as? String, PlaybackPitchCalculator.audioBufferSampleRateBasis)
        XCTAssertEqual(object["computedFrequency"] as? Double, 49_612.5)
        XCTAssertEqual(object["computedVarispeedRate"] as? Double ?? 0, 1.014545, accuracy: 0.000001)
        XCTAssertEqual(object["sampleOffset"] as? Int, 512)
        XCTAssertEqual(object["sampleLength"] as? Int, 2048)
        XCTAssertEqual(object["loopStart"] as? Int, 128)
        XCTAssertEqual(object["loopLength"] as? Int, 512)
        XCTAssertEqual(object["loopType"] as? Int, 1)
        XCTAssertEqual(object["loopTypeName"] as? String, "forward")
        XCTAssertEqual(object["loopEnabled"] as? Bool, true)
        XCTAssertEqual(object["loopStartFrame"] as? Int, 128)
        XCTAssertEqual(object["loopEndFrame"] as? Int, 640)
        XCTAssertEqual(object["loopLengthFrames"] as? Int, 512)
        XCTAssertEqual(object["pingPongLoopApplied"] as? Bool, false)
        XCTAssertEqual(object["envelopeEnabled"] as? Bool, true)
        XCTAssertEqual(object["envelopeTick"] as? Int, 4)
        XCTAssertEqual(object["envelopeValue"] as? Double, 0.75)
        XCTAssertEqual(object["envelopeSustainActive"] as? Bool, false)
        XCTAssertEqual(object["envelopeLoopActive"] as? Bool, true)
        XCTAssertEqual(object["fadeoutValue"] as? Double, 0.875)
        XCTAssertEqual(object["finalAppliedVolume"] as? Double, 0.4375)
        XCTAssertEqual(object["decision"] as? String, "triggered")
        XCTAssertEqual(object["decisionReason"] as? String, "row_note")
    }

    func testPlaybackVolumeEnvelopeInterpolatesBetweenPoints() {
        let envelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 10, value: 32),
                PlaybackEnvelopePoint(tick: 20, value: 0)
            ],
            sustainPointIndex: nil,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0x01,
            fadeout: 0
        )

        XCTAssertEqual(envelope.value(at: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(envelope.value(at: 5), 0.75, accuracy: 0.0001)
        XCTAssertEqual(envelope.value(at: 15), 0.25, accuracy: 0.0001)
        XCTAssertEqual(envelope.value(at: 25), 0, accuracy: 0.0001)
    }

    func testPlaybackVolumeEnvelopeStateHoldsSustainUntilNoteOff() {
        let envelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 2, value: 32),
                PlaybackEnvelopePoint(tick: 4, value: 0)
            ],
            sustainPointIndex: 1,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0x03,
            fadeout: 0
        )
        var state = PlaybackVolumeEnvelopeState()
        state.reset(envelope: envelope)

        state.advanceTick()
        state.advanceTick()
        state.advanceTick()

        XCTAssertEqual(state.tick, 2)
        XCTAssertTrue(state.sustainActive)
        XCTAssertEqual(state.envelopeValue, 0.5, accuracy: 0.0001)

        state.noteOff()
        state.advanceTick()

        XCTAssertEqual(state.tick, 3)
        XCTAssertFalse(state.sustainActive)
        XCTAssertEqual(state.envelopeValue, 0.25, accuracy: 0.0001)
    }

    func testPlaybackVolumeEnvelopeStateLoopsBetweenLoopPoints() {
        let envelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 2, value: 32),
                PlaybackEnvelopePoint(tick: 4, value: 16)
            ],
            sustainPointIndex: nil,
            loopStartPointIndex: 1,
            loopEndPointIndex: 2,
            typeFlags: 0x05,
            fadeout: 0
        )
        var state = PlaybackVolumeEnvelopeState()
        state.reset(envelope: envelope)

        for _ in 0..<5 {
            state.advanceTick()
        }

        XCTAssertEqual(state.tick, 2)
        XCTAssertTrue(state.loopActive)
        XCTAssertEqual(state.envelopeValue, 0.5, accuracy: 0.0001)
    }

    func testPlaybackVolumeEnvelopeFadeoutClampsAfterNoteOff() {
        let envelope = PlaybackVolumeEnvelope(
            enabled: false,
            points: [],
            sustainPointIndex: nil,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0,
            fadeout: 65_536
        )
        var state = PlaybackVolumeEnvelopeState()
        state.reset(envelope: envelope)

        state.noteOff()
        state.advanceTick()
        state.advanceTick()

        XCTAssertEqual(state.fadeoutValue, 0, accuracy: 0.0001)
        XCTAssertEqual(state.volumeMultiplier, 0, accuracy: 0.0001)
        XCTAssertTrue(state.isFullyFadedOut)
    }

    func testPlaybackVolumeCalculatorCombinesAndClampsFinalVolume() {
        let nodeVolume = PlaybackVolumeCalculator.combinedNodeVolume(
            channelVolume: 0.5,
            globalVolume: 0.5,
            envelopeValue: 0.5,
            fadeoutValue: 0.5
        )

        XCTAssertEqual(nodeVolume, 0.0625, accuracy: 0.0001)
        XCTAssertEqual(PlaybackVolumeCalculator.finalAppliedVolume(sampleVolume: 0.5, nodeVolumeScale: nodeVolume), 0.03125, accuracy: 0.0001)
        XCTAssertEqual(PlaybackVolumeCalculator.finalAppliedVolume(sampleVolume: 4, nodeVolumeScale: 4), 1, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackTraceConfigurationIsOffWithoutDebugPath() {
        XCTAssertFalse(PlaybackTraceConfiguration.makeWriter(environment: [:]).isEnabled)
    }

    @MainActor
    func testPlaybackTraceConfigurationEnablesDebugPath() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vtx-playback-trace-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let writer = PlaybackTraceConfiguration.makeWriter(environment: [
            PlaybackTraceConfiguration.pathEnvironmentKey: url.path
        ])

        XCTAssertTrue(writer.isEnabled)
    }

    func testPlaybackDebugLaunchConfigurationParsesEnvironment() {
        let configuration = PlaybackDebugLaunchConfiguration.parse(environment: [
            PlaybackDebugLaunchConfiguration.startOrderEnvironmentKey: "30",
            PlaybackDebugLaunchConfiguration.startRowEnvironmentKey: "4",
            PlaybackDebugLaunchConfiguration.startTickEnvironmentKey: "2",
            PlaybackDebugLaunchConfiguration.autoplayEnvironmentKey: "1",
            PlaybackDebugLaunchConfiguration.stopAfterSecondsEnvironmentKey: "10.5"
        ])

        XCTAssertEqual(configuration.startRequest?.requestedOrderIndex, 30)
        XCTAssertEqual(configuration.startRequest?.requestedRowIndex, 4)
        XCTAssertEqual(configuration.startRequest?.requestedTickInRow, 2)
        XCTAssertTrue(configuration.autoplay)
        XCTAssertEqual(configuration.stopAfterSeconds, 10.5)
    }

    func testPlaybackSongStartsAtFirstOrderFirstRow() {
        let song = makePlaybackSong(orderPatternIndices: [2, 5], patternRowCounts: [2: 4, 5: 8])

        XCTAssertEqual(song.startPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
    }

    func testPlaybackSongStepsRowsWithinCurrentPattern() {
        let song = makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 4])
        let position = PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)

        XCTAssertEqual(song.position(after: position), .advanced(PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 2)))
    }

    func testPlaybackSongStepsFromPatternEndToNextOrderPattern() {
        let song = makePlaybackSong(orderPatternIndices: [2, 5], patternRowCounts: [2: 2, 5: 4])
        let position = PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)

        XCTAssertEqual(song.position(after: position), .advanced(PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 0)))
    }

    func testPlaybackSongEndsExplicitlyAtSongEnd() {
        let song = makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 2])
        let position = PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)

        XCTAssertEqual(song.position(after: position), .ended(restartPosition: nil))
    }

    func testPlaybackSongCanReturnRestartPlaceholderAtSongEnd() {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 2],
            endBehavior: .restartFromBeginning
        )
        let position = PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)

        XCTAssertEqual(
            song.position(after: position),
            .ended(restartPosition: PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        )
    }

    func testPlaybackSongFindsFirstPlayableInstrumentSample() {
        let silent = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        let playable = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [0, 0.5, -0.5], volume: 0.5, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 2],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [silent, playable])]
        )

        XCTAssertEqual(song.sample(forInstrument: 1), playable)
        XCTAssertNil(song.sample(forInstrument: 0))
        XCTAssertNil(song.sample(forInstrument: 2))
    }

    func testPlaybackTimingUsesXMDefaultTickDuration() {
        let timing = PlaybackTiming.xmDefault

        XCTAssertEqual(timing.ticksPerRow, 6)
        XCTAssertEqual(timing.tickDuration, 0.02, accuracy: 0.0001)
    }

    func testPlaybackTimingComputesXMRowDurationFromSpeedAndBPM() {
        let timing = PlaybackTiming(speed: 2, bpm: 183)

        XCTAssertEqual(timing.ticksPerRow, 2)
        XCTAssertEqual(timing.tickDuration, 2.5 / 183.0, accuracy: 0.000001)
        XCTAssertEqual(timing.rowDuration, (2.5 / 183.0) * 2.0, accuracy: 0.000001)
    }

    func testLinearPitchCalculationUsesNoteRelativeNoteAndFinetune() {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25],
            volume: 1,
            relativeNote: 12,
            finetune: 64,
            baseSampleRate: 8_363
        )

        let calculation = PlaybackPitchCalculator.calculation(note: 49, sample: sample, pitchOffsetSemitones: 0, outputSampleRate: 44_100)
        let expectedFrequency = 8_363.0 * pow(2.0, 12.5 / 12.0)

        XCTAssertEqual(calculation.relativeNote, 12)
        XCTAssertEqual(calculation.finetune, 64)
        XCTAssertEqual(calculation.sourceSampleRate, 8_363)
        XCTAssertEqual(calculation.audioBufferSampleRate, 44_100)
        XCTAssertEqual(calculation.targetFrequency, expectedFrequency, accuracy: 0.0001)
        XCTAssertEqual(calculation.frequency, expectedFrequency, accuracy: 0.0001)
        XCTAssertEqual(calculation.playbackRate, expectedFrequency / 44_100.0, accuracy: 0.000001)
        XCTAssertEqual(calculation.rateBasis, PlaybackPitchCalculator.audioBufferSampleRateBasis)
    }

    func testRateCalculationUsesAudioBufferSampleRateBasisFor8363HzSample() {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363
        )

        let base = PlaybackPitchCalculator.calculation(note: 49, sample: sample, pitchOffsetSemitones: 0, outputSampleRate: 44_100)
        let octave = PlaybackPitchCalculator.calculation(note: 61, sample: sample, pitchOffsetSemitones: 0, outputSampleRate: 44_100)

        XCTAssertEqual(base.targetFrequency, 8_363, accuracy: 0.0001)
        XCTAssertEqual(base.playbackRate, 8_363.0 / 44_100.0, accuracy: 0.000001)
        XCTAssertEqual(base.rateBasis, PlaybackPitchCalculator.audioBufferSampleRateBasis)
        XCTAssertEqual(octave.targetFrequency, 16_726, accuracy: 0.0001)
        XCTAssertEqual(octave.playbackRate, 16_726.0 / 44_100.0, accuracy: 0.000001)
    }

    func testPlaybackSampleKeepsSafeLoopMetadataInSampleFrames() {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1_000),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sampleLength: 1_000,
            loopStart: 100,
            loopLength: 300,
            loopType: 1
        )

        XCTAssertEqual(sample.sampleLength, 1_000)
        XCTAssertEqual(sample.loopStart, 100)
        XCTAssertEqual(sample.loopLength, 300)
        XCTAssertEqual(sample.loopType, 1)
        XCTAssertEqual(sample.loopRegion, PlaybackSampleLoopRegion(isEnabled: true, startFrame: 100, endFrame: 400, lengthFrames: 300, loopType: 1, loopTypeName: "forward"))
    }

    func testPlaybackSampleLoopRegionClampsInvalidMetadataSafely() {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1_000),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sampleLength: 1_000,
            loopStart: 900,
            loopLength: 500,
            loopType: 1
        )

        XCTAssertEqual(sample.loopRegion, PlaybackSampleLoopRegion(isEnabled: true, startFrame: 900, endFrame: 1_000, lengthFrames: 100, loopType: 1, loopTypeName: "forward"))
    }

    func testPlaybackSampleLoopRegionDisablesUnsafeInvalidLoops() {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1_000),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sampleLength: 1_000,
            loopStart: 1_500,
            loopLength: 200,
            loopType: 1
        )

        XCTAssertEqual(sample.loopRegion, PlaybackSampleLoopRegion(isEnabled: false, startFrame: 1_000, endFrame: 1_000, lengthFrames: 0, loopType: 1, loopTypeName: "forward"))
    }

    func testPlaybackSampleLoopRegionEnablesPingPongLoops() {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1_000),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sampleLength: 1_000,
            loopStart: 100,
            loopLength: 300,
            loopType: 2
        )

        XCTAssertEqual(sample.loopRegion, PlaybackSampleLoopRegion(isEnabled: true, startFrame: 100, endFrame: 400, lengthFrames: 300, loopType: 2, loopTypeName: "ping_pong"))
        XCTAssertTrue(sample.loopRegion.pingPongLoopApplied)
    }

    func testPingPongLoopFrameConstructionBuildsForwardThenReverseInterior() {
        let frameIndices = AudioSampleLoopFrameBuilder.pingPongFrameIndices(for: 2..<6, sampleFrameCount: 8)

        XCTAssertEqual(frameIndices, [2, 3, 4, 5, 4, 3])
    }

    func testPingPongLoopFrameConstructionRejectsInvalidBounds() {
        XCTAssertEqual(AudioSampleLoopFrameBuilder.pingPongFrameIndices(for: 6..<6, sampleFrameCount: 8), [])
        XCTAssertEqual(AudioSampleLoopFrameBuilder.pingPongFrameIndices(for: 6..<9, sampleFrameCount: 8), [])
        XCTAssertEqual(AudioSampleLoopFrameBuilder.pingPongFrameIndices(for: -1..<3, sampleFrameCount: 8), [])
    }

    func testAudioSamplePlaybackPlannerSchedulesForwardLoopAfterIntro() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1_000),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sampleLength: 1_000,
            loopStart: 200,
            loopLength: 300,
            loopType: 1
        )

        let plan = try XCTUnwrap(AudioSamplePlaybackPlanner.plan(for: sample, sampleStartOffset: 64))

        XCTAssertEqual(plan.introRange, 64..<500)
        XCTAssertEqual(plan.loopRange, 200..<500)
        XCTAssertEqual(plan.loopMode, .forward)
        XCTAssertTrue(plan.isLooped)
        XCTAssertFalse(plan.usesPingPongLoop)
    }

    func testAudioSamplePlaybackPlannerStartsInsideForwardLoopAndThenLoopsFullRegion() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1_000),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sampleLength: 1_000,
            loopStart: 200,
            loopLength: 300,
            loopType: 1
        )

        let plan = try XCTUnwrap(AudioSamplePlaybackPlanner.plan(for: sample, sampleStartOffset: 350))

        XCTAssertEqual(plan.introRange, 350..<500)
        XCTAssertEqual(plan.loopRange, 200..<500)
        XCTAssertEqual(plan.loopMode, .forward)
        XCTAssertTrue(plan.isLooped)
    }

    func testAudioSamplePlaybackPlannerSchedulesPingPongLoopAfterIntro() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1_000),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sampleLength: 1_000,
            loopStart: 200,
            loopLength: 300,
            loopType: 2
        )

        let plan = try XCTUnwrap(AudioSamplePlaybackPlanner.plan(for: sample, sampleStartOffset: 64))

        XCTAssertEqual(plan.introRange, 64..<200)
        XCTAssertEqual(plan.loopRange, 200..<500)
        XCTAssertEqual(plan.loopMode, .pingPong)
        XCTAssertTrue(plan.isLooped)
        XCTAssertTrue(plan.usesPingPongLoop)
    }

    func testAudioSamplePlaybackPlannerClampsInvalidPingPongBoundsSafely() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1_000),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sampleLength: 1_000,
            loopStart: 1_500,
            loopLength: 300,
            loopType: 2
        )

        let plan = try XCTUnwrap(AudioSamplePlaybackPlanner.plan(for: sample, sampleStartOffset: 64))

        XCTAssertEqual(sample.loopRegion, PlaybackSampleLoopRegion(isEnabled: false, startFrame: 1_000, endFrame: 1_000, lengthFrames: 0, loopType: 2, loopTypeName: "ping_pong"))
        XCTAssertEqual(plan.introRange, 64..<1_000)
        XCTAssertNil(plan.loopRange)
        XCTAssertNil(plan.loopMode)
        XCTAssertFalse(plan.isLooped)
    }

    func testAudioSamplePlaybackPlannerFallsBackToOneShotPastLoopEnd() throws {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1_000),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sampleLength: 1_000,
            loopStart: 200,
            loopLength: 300,
            loopType: 1
        )

        let plan = try XCTUnwrap(AudioSamplePlaybackPlanner.plan(for: sample, sampleStartOffset: 600))

        XCTAssertEqual(plan.introRange, 600..<1_000)
        XCTAssertNil(plan.loopRange)
        XCTAssertFalse(plan.isLooped)
    }

    func testPlaybackTickStateAdvancesRowsAfterConfiguredSpeed() {
        let timing = PlaybackTiming(speed: 3, bpm: 125)
        var tickState = PlaybackTickState()

        XCTAssertFalse(tickState.advance(timing: timing))
        XCTAssertFalse(tickState.advance(timing: timing))
        XCTAssertTrue(tickState.advance(timing: timing))
        XCTAssertEqual(tickState, PlaybackTickState(tickInRow: 0))
    }
}
