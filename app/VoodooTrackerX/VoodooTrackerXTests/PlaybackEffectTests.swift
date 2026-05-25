import AppKit
import AudioToolbox
import XCTest

final class PlaybackEffectTests: XCTestCase {
    func testPlaybackVolumeColumnPanningMappingAndClamp() {
        XCTAssertEqual(PlaybackEffectHandler.volumeColumnCommand(0xC0), .setPanning(value: 0))
        XCTAssertEqual(PlaybackEffectHandler.volumeColumnCommand(0xCC), .setPanning(value: 204))
        XCTAssertEqual(PlaybackEffectHandler.volumeColumnCommand(0xCF), .setPanning(value: 255))

        var state = PlaybackChannelState(panning: 128)
        XCTAssertTrue(state.apply(volumeColumnCommand: PlaybackEffectHandler.volumeColumnCommand(0xCF)))
        XCTAssertEqual(state.panning, 255)
        XCTAssertEqual(state.audioControls.panning, 1.0, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackVolumeColumnSetVolumePreservesCxxOverride() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x20, effectType: 0x0C, effectParam: 0x30)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.volumeScale ?? 0, 0.75, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackVolumeColumnPanningPreserves8xxOverride() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0xCC, effectType: 0x08, effectParam: 0x40)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.panning ?? 0, PlaybackEffectHandler.audioPanning(forXMValue: 64), accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackTraceDecodesCommonVolumeColumnValues() {
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput(), traceWriter: traceWriter)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0x20),
                    makePlaybackRow(index: 1, volumeColumn: 0x3D),
                    makePlaybackRow(index: 2, volumeColumn: 0x50),
                    makePlaybackRow(index: 3, volumeColumn: 0xC0),
                    makePlaybackRow(index: 4, volumeColumn: 0xCC),
                    makePlaybackRow(index: 5, volumeColumn: 0xCF)
                ]
            ]
        ))
        engine.configureTiming(PlaybackTiming(speed: 1, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        for _ in 0..<5 {
            engine.advanceOneTick()
        }

        let rowEvents = traceWriter.events.filter { $0.channelIndex == 0 && $0.tickInRow == 0 }
        let decodedByRaw = Dictionary(uniqueKeysWithValues: rowEvents.compactMap { event -> (String, PlaybackTraceEvent)? in
            guard let raw = event.rawVolumeColumn else {
                return nil
            }
            return (raw, event)
        })

        XCTAssertEqual(decodedByRaw["20"]?.decodedVolumeColumnCommand, "setVolume")
        XCTAssertEqual(decodedByRaw["20"]?.volumeColumnVolume, 16)
        XCTAssertEqual(decodedByRaw["3D"]?.volumeColumnVolume, 45)
        XCTAssertEqual(decodedByRaw["50"]?.volumeColumnVolume, 64)
        XCTAssertEqual(decodedByRaw["C0"]?.decodedVolumeColumnCommand, "setPanning")
        XCTAssertEqual(decodedByRaw["C0"]?.volumeColumnPanning, 0)
        XCTAssertEqual(decodedByRaw["CC"]?.volumeColumnPanning, 204)
        XCTAssertEqual(decodedByRaw["CF"]?.volumeColumnPanning, 255)
    }

    func testPlaybackEffectHandlerDecodesSpeedAndBPM() {
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0F, effectParam: 0x06), .setSpeed(6))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0F, effectParam: 0x1F), .setSpeed(31))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0F, effectParam: 0x20), .setBPM(32))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0F, effectParam: 0x7D), .setBPM(125))
        XCTAssertNil(PlaybackEffectHandler.command(effectType: 0x0F, effectParam: 0x00))
    }

    func testPlaybackEffectHandlerDecodesPositionJumpAndPatternBreak() {
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0B, effectParam: 0x03), .positionJump(orderIndex: 3))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0D, effectParam: 0x12), .patternBreak(rowIndex: 12))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0D, effectParam: 0x09), .patternBreak(rowIndex: 9))
        XCTAssertNil(PlaybackEffectHandler.command(effectType: 0x0D, effectParam: 0x1A))
    }

    func testPlaybackEffectHandlerDecodesSetVolumeWithClamp() {
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0C, effectParam: 0x20), .setVolume(0.5))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0C, effectParam: 0x40), .setVolume(1.0))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0C, effectParam: 0x7F), .setVolume(1.0))
    }

    func testPlaybackEffectHandlerDecodesPanningWithClamp() {
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x08, effectParam: 0x00), .setPanning(0))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x08, effectParam: 0x80), .setPanning(128))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x08, effectParam: 0xFF), .setPanning(255))
        XCTAssertEqual(PlaybackEffectHandler.clampedPanning(-1), 0)
        XCTAssertEqual(PlaybackEffectHandler.clampedPanning(300), 255)
        XCTAssertEqual(PlaybackEffectHandler.audioPanning(forXMValue: 0), -1.0, accuracy: 0.0001)
        XCTAssertEqual(PlaybackEffectHandler.audioPanning(forXMValue: 255), 1.0, accuracy: 0.0001)
    }

    func testPlaybackEffectHandlerDecodesGlobalVolumeAndPatternDelay() {
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x10, effectParam: 0x20), .setGlobalVolume(0.5))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x10, effectParam: 0x40), .setGlobalVolume(1.0))
        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x10, effectParam: 0x7F), .setGlobalVolume(1.0))

        XCTAssertEqual(PlaybackEffectHandler.command(effectType: 0x0E, effectParam: 0xE2), .patternDelay(rowDurations: 2))
        XCTAssertEqual(PlaybackEffectHandler.extendedTimingEffect(effectParam: 0xE0), .patternDelay(rowDurations: 0))
    }

    func testPlaybackEffectHandlerDecodesContinuousEffectsWithMemory() {
        XCTAssertEqual(PlaybackEffectHandler.arpeggio(effectParam: 0x37, memory: nil), .arpeggio(x: 3, y: 7))
        XCTAssertEqual(PlaybackEffectHandler.arpeggio(effectParam: 0x00, memory: 0x37), .arpeggio(x: 3, y: 7))
        XCTAssertNil(PlaybackEffectHandler.arpeggio(effectParam: 0x00, memory: nil))

        XCTAssertEqual(PlaybackEffectHandler.volumeSlide(effectParam: 0x40, memory: nil), .volumeSlide(up: 4, down: 0))
        XCTAssertEqual(PlaybackEffectHandler.volumeSlide(effectParam: 0x05, memory: nil), .volumeSlide(up: 0, down: 5))
        XCTAssertEqual(PlaybackEffectHandler.volumeSlide(effectParam: 0x45, memory: nil), .volumeSlide(up: 4, down: 0))
        XCTAssertEqual(PlaybackEffectHandler.volumeSlide(effectParam: 0x00, memory: 0x05), .volumeSlide(up: 0, down: 5))
        XCTAssertNil(PlaybackEffectHandler.volumeSlide(effectParam: 0x00, memory: nil))

        XCTAssertEqual(PlaybackEffectHandler.portamentoUp(effectParam: 0x08, memory: nil), .portamentoUp(amount: 8))
        XCTAssertEqual(PlaybackEffectHandler.portamentoDown(effectParam: 0x00, memory: 0x09), .portamentoDown(amount: 9))
        XCTAssertNil(PlaybackEffectHandler.portamentoUp(effectParam: 0x00, memory: nil))
        XCTAssertNil(PlaybackEffectHandler.portamentoDown(effectParam: 0x00, memory: nil))
    }

    func testPlaybackEffectHandlerDecodesTonePortamentoAndVibratoWithMemory() {
        XCTAssertEqual(PlaybackEffectHandler.tonePortamento(effectParam: 0x10, memory: nil), .tonePortamento(amount: 16))
        XCTAssertEqual(PlaybackEffectHandler.tonePortamento(effectParam: 0x00, memory: 0x08), .tonePortamento(amount: 8))
        XCTAssertNil(PlaybackEffectHandler.tonePortamento(effectParam: 0x00, memory: nil))

        XCTAssertEqual(PlaybackEffectHandler.vibrato(effectParam: 0x47, memory: nil), .vibrato(speed: 4, depth: 7))
        XCTAssertEqual(PlaybackEffectHandler.vibrato(effectParam: 0x00, memory: 0x25), .vibrato(speed: 2, depth: 5))
        XCTAssertNil(PlaybackEffectHandler.vibrato(effectParam: 0x00, memory: nil))

        XCTAssertEqual(PlaybackEffectHandler.tremolo(effectParam: 0x47, memory: nil), .tremolo(speed: 4, depth: 7))
        XCTAssertEqual(PlaybackEffectHandler.tremolo(effectParam: 0x00, memory: 0x25), .tremolo(speed: 2, depth: 5))
        XCTAssertNil(PlaybackEffectHandler.tremolo(effectParam: 0x00, memory: nil))

        XCTAssertEqual(
            PlaybackEffectHandler.combinedTonePortamentoVolumeSlide(
                toneEffect: .tonePortamento(amount: 8),
                slideEffect: .volumeSlide(up: 2, down: 0)
            ),
            .tonePortamentoVolumeSlide(amount: 8, up: 2, down: 0)
        )
        XCTAssertEqual(
            PlaybackEffectHandler.combinedVibratoVolumeSlide(
                vibratoEffect: .vibrato(speed: 4, depth: 7),
                slideEffect: .volumeSlide(up: 0, down: 2)
            ),
            .vibratoVolumeSlide(speed: 4, depth: 7, up: 0, down: 2)
        )
    }

    func testPlaybackEffectHandlerDecodesSampleTimingEffects() {
        XCTAssertEqual(PlaybackEffectHandler.sampleOffset(effectParam: 0x02), 512)
        XCTAssertEqual(PlaybackEffectHandler.sampleOffset(effectParam: 0x00), 0)

        XCTAssertEqual(PlaybackEffectHandler.extendedTimingEffect(effectParam: 0x93), .retrigger(interval: 3))
        XCTAssertEqual(PlaybackEffectHandler.extendedTimingEffect(effectParam: 0x90), .retrigger(interval: 0))
        XCTAssertEqual(PlaybackEffectHandler.extendedTimingEffect(effectParam: 0xC2), .noteCut(tick: 2))
        XCTAssertEqual(PlaybackEffectHandler.extendedTimingEffect(effectParam: 0xD4), .noteDelay(tick: 4))
        XCTAssertEqual(PlaybackEffectHandler.extendedTimingEffect(effectParam: 0xE2), .patternDelay(rowDurations: 2))
        XCTAssertNil(PlaybackEffectHandler.extendedTimingEffect(effectParam: 0xA1))
    }

    func testPlaybackEffectHandlerDecodesGlobalVolumeSlideWithMemory() {
        XCTAssertEqual(PlaybackEffectHandler.globalVolumeSlide(effectParam: 0x20, memory: nil), PlaybackGlobalVolumeSlide(up: 2, down: 0))
        XCTAssertEqual(PlaybackEffectHandler.globalVolumeSlide(effectParam: 0x05, memory: nil), PlaybackGlobalVolumeSlide(up: 0, down: 5))
        XCTAssertEqual(PlaybackEffectHandler.globalVolumeSlide(effectParam: 0x25, memory: nil), PlaybackGlobalVolumeSlide(up: 2, down: 0))
        XCTAssertEqual(PlaybackEffectHandler.globalVolumeSlide(effectParam: 0x00, memory: 0x05), PlaybackGlobalVolumeSlide(up: 0, down: 5))
        XCTAssertNil(PlaybackEffectHandler.globalVolumeSlide(effectParam: 0x00, memory: nil))
    }

    func testPlaybackEffectHandlerDecodesPanningSlideWithMemory() {
        XCTAssertEqual(PlaybackEffectHandler.panningSlide(effectParam: 0x20, memory: nil), .panningSlide(right: 2, left: 0))
        XCTAssertEqual(PlaybackEffectHandler.panningSlide(effectParam: 0x05, memory: nil), .panningSlide(right: 0, left: 5))
        XCTAssertEqual(PlaybackEffectHandler.panningSlide(effectParam: 0x25, memory: nil), .panningSlide(right: 2, left: 0))
        XCTAssertEqual(PlaybackEffectHandler.panningSlide(effectParam: 0x00, memory: 0x05), .panningSlide(right: 0, left: 5))
        XCTAssertNil(PlaybackEffectHandler.panningSlide(effectParam: 0x00, memory: nil))
    }

    func testPlaybackChannelStateTreatsZeroedSupportedEffectsWithoutMemoryAsNoOps() {
        var state = PlaybackChannelState()

        XCTAssertTrue(state.apply(effectType: 0x03, effectParam: 0x00))
        XCTAssertTrue(state.apply(effectType: 0x04, effectParam: 0x00))
        XCTAssertTrue(state.apply(effectType: 0x05, effectParam: 0x00))
        XCTAssertTrue(state.apply(effectType: 0x06, effectParam: 0x00))
        XCTAssertTrue(state.apply(effectType: 0x07, effectParam: 0x00))
        XCTAssertNil(state.activeEffect)
    }

    func testPlaybackChannelStateAppliesSampleTimingEffects() {
        var state = PlaybackChannelState()

        XCTAssertTrue(state.apply(effectType: 0x09, effectParam: 0x02))
        XCTAssertEqual(state.sampleStartOffset, 512)

        XCTAssertTrue(state.apply(effectType: 0x0E, effectParam: 0x93))
        XCTAssertEqual(state.retriggerInterval, 3)

        XCTAssertTrue(state.apply(effectType: 0x0E, effectParam: 0x90))
        XCTAssertEqual(state.retriggerInterval, 3)

        XCTAssertTrue(state.apply(effectType: 0x0E, effectParam: 0xC2))
        XCTAssertEqual(state.noteCutTick, 2)

        XCTAssertTrue(state.apply(effectType: 0x0E, effectParam: 0xD4))
        XCTAssertEqual(state.noteDelayTick, 4)
        XCTAssertTrue(state.suppressesNoteTrigger)
    }

    func testPlaybackChannelStateAppliesPanningEffectsWithBounds() {
        var setState = PlaybackChannelState()
        XCTAssertEqual(setState.panning, 128)
        setState.panning = PlaybackEffectHandler.clampedPanning(300)
        XCTAssertEqual(setState.panning, 255)
        XCTAssertEqual(setState.audioControls.panning, 1.0, accuracy: 0.0001)

        var rightState = PlaybackChannelState(panning: 254)
        XCTAssertTrue(rightState.apply(effectType: 0x19, effectParam: 0x20))
        rightState.advanceContinuousEffect(tickInRow: 1)
        XCTAssertEqual(rightState.panning, 255)

        var leftState = PlaybackChannelState(panning: 1)
        XCTAssertTrue(leftState.apply(effectType: 0x19, effectParam: 0x02))
        leftState.advanceContinuousEffect(tickInRow: 1)
        XCTAssertEqual(leftState.panning, 0)
    }

    func testPlaybackChannelStateAppliesContinuousEffectsAcrossTicks() {
        var arpeggioState = PlaybackChannelState()
        XCTAssertTrue(arpeggioState.apply(effectType: 0x00, effectParam: 0x37))
        arpeggioState.advanceContinuousEffect(tickInRow: 1)
        XCTAssertEqual(arpeggioState.pitchOffsetSemitones, 3)
        arpeggioState.advanceContinuousEffect(tickInRow: 2)
        XCTAssertEqual(arpeggioState.pitchOffsetSemitones, 7)
        arpeggioState.advanceContinuousEffect(tickInRow: 3)
        XCTAssertEqual(arpeggioState.pitchOffsetSemitones, 0)

        var slideState = PlaybackChannelState(volume: 0.5)
        XCTAssertTrue(slideState.apply(effectType: 0x0A, effectParam: 0x20))
        slideState.advanceContinuousEffect(tickInRow: 1)
        XCTAssertEqual(slideState.volume, 0.53125, accuracy: 0.0001)

        var portamentoState = PlaybackChannelState()
        XCTAssertTrue(portamentoState.apply(effectType: 0x01, effectParam: 0x08))
        portamentoState.advanceContinuousEffect(tickInRow: 1)
        XCTAssertEqual(portamentoState.pitchOffsetSemitones, 0.125, accuracy: 0.0001)
        XCTAssertTrue(portamentoState.apply(effectType: 0x02, effectParam: 0x10))
        portamentoState.advanceContinuousEffect(tickInRow: 2)
        XCTAssertEqual(portamentoState.pitchOffsetSemitones, -0.125, accuracy: 0.0001)

        var tremoloState = PlaybackChannelState(volume: 0.5)
        XCTAssertTrue(tremoloState.apply(effectType: 0x07, effectParam: 0x48))
        tremoloState.advanceContinuousEffect(tickInRow: 1)
        let firstTremoloVolume = tremoloState.audioControls.volumeScale
        XCTAssertGreaterThan(firstTremoloVolume, 0.5)
        tremoloState.advanceContinuousEffect(tickInRow: 2)
        XCTAssertNotEqual(tremoloState.audioControls.volumeScale, firstTremoloVolume)
    }

    func testPlaybackGlobalStateAppliesVolumeSlideWithBounds() {
        var upwardState = PlaybackGlobalState(volume: 0.95)
        XCTAssertTrue(upwardState.applyVolumeSlide(effectParam: 0x40))
        upwardState.advanceContinuousEffects()
        XCTAssertEqual(upwardState.volume, 1.0, accuracy: 0.0001)

        var downwardState = PlaybackGlobalState(volume: 0.05)
        XCTAssertTrue(downwardState.applyVolumeSlide(effectParam: 0x04))
        downwardState.advanceContinuousEffects()
        XCTAssertEqual(downwardState.volume, 0.0, accuracy: 0.0001)
    }

    func testPlaybackChannelStateClampsRepeatedPortamentoPitchOffset() {
        var upwardState = PlaybackChannelState()
        XCTAssertTrue(upwardState.apply(effectType: 0x01, effectParam: 0xFF))
        for tick in 1...20 {
            upwardState.advanceContinuousEffect(tickInRow: tick)
        }
        XCTAssertEqual(upwardState.pitchOffsetSemitones, PlaybackChannelState.pitchOffsetRange.upperBound)

        var downwardState = PlaybackChannelState()
        XCTAssertTrue(downwardState.apply(effectType: 0x02, effectParam: 0xFF))
        for tick in 1...20 {
            downwardState.advanceContinuousEffect(tickInRow: tick)
        }
        XCTAssertEqual(downwardState.pitchOffsetSemitones, PlaybackChannelState.pitchOffsetRange.lowerBound)
    }

    func testPlaybackChannelStateAppliesTonePortamentoTowardTargetNote() {
        var state = PlaybackChannelState()
        state.start(note: 49)
        state.beginRow()
        state.setTonePortamentoTarget(note: 53)
        XCTAssertTrue(state.suppressesNoteTrigger)
        XCTAssertTrue(state.apply(effectType: 0x03, effectParam: 0x10))

        state.advanceContinuousEffect(tickInRow: 1)
        XCTAssertEqual(state.pitchOffsetSemitones, 0.25, accuracy: 0.0001)

        for tick in 2...32 {
            state.advanceContinuousEffect(tickInRow: tick)
        }
        XCTAssertEqual(state.pitchOffsetSemitones, 4.0, accuracy: 0.0001)
    }

    func testPlaybackChannelStateAppliesVibratoAndCombinedVolumeSlides() {
        var vibratoState = PlaybackChannelState()
        XCTAssertTrue(vibratoState.apply(effectType: 0x04, effectParam: 0x48))
        vibratoState.advanceContinuousEffect(tickInRow: 1)
        let firstOffset = vibratoState.audioControls.pitchOffsetSemitones
        XCTAssertGreaterThan(firstOffset, 0)
        vibratoState.advanceContinuousEffect(tickInRow: 2)
        XCTAssertNotEqual(vibratoState.audioControls.pitchOffsetSemitones, firstOffset)

        var combinedState = PlaybackChannelState(volume: 0.5, lastTonePortamentoParam: 0x08)
        combinedState.start(note: 49)
        combinedState.setTonePortamentoTarget(note: 53)
        XCTAssertTrue(combinedState.apply(effectType: 0x05, effectParam: 0x20))
        combinedState.advanceContinuousEffect(tickInRow: 1)
        XCTAssertEqual(combinedState.volume, 0.53125, accuracy: 0.0001)
        XCTAssertEqual(combinedState.pitchOffsetSemitones, 0.125, accuracy: 0.0001)
    }
}
