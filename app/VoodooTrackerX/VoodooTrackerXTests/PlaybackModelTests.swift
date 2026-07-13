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

    func testModuleMetadataLoaderLoadsGeneratedMultiPatternLoopBoundaryFixture() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/multi-pattern-loop-boundary.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)

        XCTAssertEqual(metadata.type, "XM")
        XCTAssertEqual(metadata.title, "VTX LOOP BOUNDARY")
        XCTAssertEqual(metadata.version, "1.4")
        XCTAssertEqual(metadata.channels, 1)
        XCTAssertEqual(metadata.patterns, 3)
        XCTAssertEqual(metadata.instruments, 1)
        XCTAssertEqual(metadata.defaultTempo, 6)
        XCTAssertEqual(metadata.defaultBPM, 125)
        XCTAssertEqual(metadata.orderTable, [0, 1, 2])
        XCTAssertEqual(metadata.xmPatterns.map(\.index), [0, 1, 2])
        XCTAssertEqual(metadata.xmPatterns.map(\.rowCount), [4, 4, 4])
        XCTAssertEqual(metadata.xmPatterns.map(\.channels), [1, 1, 1])
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].note, 49)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].instrument, 1)
        XCTAssertEqual(metadata.xmPatterns[1].rows[0][0].note, 53)
        XCTAssertEqual(metadata.xmPatterns[1].rows[0][0].instrument, 1)
        XCTAssertEqual(metadata.xmPatterns[2].rows[0][0].note, 56)
        XCTAssertEqual(metadata.xmPatterns[2].rows[0][0].instrument, 1)
        XCTAssertEqual(metadata.xmPatterns[2].rows[1][0], .empty)
    }

    func testPlaybackSongBuilderPreservesGeneratedMultiPatternLoopBoundaryMapping() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/multi-pattern-loop-boundary.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)

        XCTAssertEqual(song.orders, [
            PlaybackOrderEntry(orderIndex: 0, patternIndex: 0),
            PlaybackOrderEntry(orderIndex: 1, patternIndex: 1),
            PlaybackOrderEntry(orderIndex: 2, patternIndex: 2),
        ])
        XCTAssertEqual(song.patternsByIndex.keys.sorted(), [0, 1, 2])
        XCTAssertEqual(song.pattern(for: 0)?.index, 0)
        XCTAssertEqual(song.pattern(for: 1)?.index, 1)
        XCTAssertEqual(song.pattern(for: 2)?.index, 2)
        XCTAssertEqual(song.row(at: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0))?.cells[0].note, 49)
        XCTAssertEqual(song.row(at: PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 0))?.cells[0].note, 53)
        XCTAssertEqual(song.row(at: PlaybackPosition(orderIndex: 2, patternIndex: 2, rowIndex: 0))?.cells[0].note, 56)
        XCTAssertEqual(song.row(at: PlaybackPosition(orderIndex: 2, patternIndex: 2, rowIndex: 1))?.cells[0], PlaybackCell(
            note: 0,
            instrument: 0,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        ))
        XCTAssertEqual(
            song.position(after: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 3)),
            .advanced(PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 0))
        )
        XCTAssertEqual(
            song.position(after: PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 3)),
            .advanced(PlaybackPosition(orderIndex: 2, patternIndex: 2, rowIndex: 0))
        )
        XCTAssertEqual(song.instrumentsByIndex[1]?.name, "BOUNDARY SAMPLE")
        XCTAssertEqual(song.instrumentsByIndex[1]?.firstPlayableSample?.name, "BOUNDARY64")
    }

    func testPlaybackSongBuilderLoadsExactNonCenterSamplePanningByte() throws {
        let fixtureURL = try temporaryBasicInstrumentFixture(samplePanning: 37)
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)

        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)

        XCTAssertEqual(song.instrumentsByIndex[1]?.samples.first?.panning, 37)
    }

    func testPlaybackSongBuilderLoadsCenterSamplePanningByte() throws {
        let fixtureURL = try temporaryBasicInstrumentFixture(samplePanning: 128)
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)

        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)

        XCTAssertEqual(song.instrumentsByIndex[1]?.samples.first?.panning, 128)
        XCTAssertEqual(song.instrumentsByIndex[1]?.panningEnvelope, .disabled)
        XCTAssertEqual(song.instrumentsByIndex[1]?.autoVibrato, .disabled)
    }

    func testPlaybackSongBuilderLoadsExactPanningEnvelopeWithNeighboringMetadata() throws {
        let panningEnvelope = PlaybackPanningEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 32),
                PlaybackEnvelopePoint(tick: 6, value: 48),
                PlaybackEnvelopePoint(tick: 18, value: 16),
            ],
            sustainPointIndex: 1,
            loopStartPointIndex: 0,
            loopEndPointIndex: 2,
            typeFlags: 0x07
        )
        let autoVibrato = PlaybackInstrumentAutoVibrato(
            waveformType: 3,
            sweep: 17,
            depth: 42,
            rate: 199
        )
        let fixtureURL = try temporaryBasicInstrumentFixture(
            samplePanning: 37,
            panningEnvelope: panningEnvelope,
            autoVibrato: autoVibrato,
            fadeout: 1_234
        )
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)

        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let instrument = try XCTUnwrap(song.instrumentsByIndex[1])
        let sample = try XCTUnwrap(instrument.samples.first)

        XCTAssertEqual(instrument.panningEnvelope, panningEnvelope)
        XCTAssertTrue(instrument.panningEnvelope.sustainEnabled)
        XCTAssertTrue(instrument.panningEnvelope.loopEnabled)
        XCTAssertFalse(instrument.volumeEnvelope.enabled)
        XCTAssertTrue(instrument.volumeEnvelope.points.isEmpty)
        XCTAssertEqual(instrument.volumeEnvelope.fadeout, 1_234)
        XCTAssertEqual(instrument.autoVibrato, autoVibrato)
        XCTAssertEqual(sample.panning, 37)
    }

    func testPlaybackSongBuilderLoadsExactInstrumentAutoVibratoBytesWithNeighboringMetadata() throws {
        let autoVibrato = PlaybackInstrumentAutoVibrato(
            waveformType: 3,
            sweep: 17,
            depth: 42,
            rate: 199
        )
        let fixtureURL = try temporaryBasicInstrumentFixture(
            samplePanning: 37,
            autoVibrato: autoVibrato,
            fadeout: 1_234
        )
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)

        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let instrument = try XCTUnwrap(song.instrumentsByIndex[1])
        let sample = try XCTUnwrap(instrument.samples.first)

        XCTAssertEqual(instrument.autoVibrato, autoVibrato)
        XCTAssertFalse(instrument.volumeEnvelope.enabled)
        XCTAssertTrue(instrument.volumeEnvelope.points.isEmpty)
        XCTAssertEqual(instrument.volumeEnvelope.fadeout, 1_234)
        XCTAssertEqual(sample.panning, 37)
        XCTAssertEqual(sample.name, "SINE64")
        XCTAssertEqual(sample.volume, 1)
    }

    func testIsolatedPatternLoopSongAnchorsDisplayedPatternAtSelectedOrderWithoutMutatingSourceSong() throws {
        let sourceSong = makePlaybackSong(
            orderPatternIndices: [3, 7],
            patternRowCounts: [3: 4, 7: 4, 42: 8],
            note: 49,
            instrument: 1
        )
        let before = sourceSong

        let isolatedSong = try XCTUnwrap(sourceSong.isolatedPatternLoopSong(patternIndex: 42, anchorOrderIndex: 1))
        let playbackRange = try XCTUnwrap(isolatedSong.patternLoopRange(containing: PlaybackPosition(
            orderIndex: 1,
            patternIndex: 42,
            rowIndex: 0
        )))

        XCTAssertEqual(sourceSong, before)
        XCTAssertEqual(isolatedSong.orders.count, 2)
        XCTAssertEqual(isolatedSong.orders[1], PlaybackOrderEntry(orderIndex: 1, patternIndex: 42))
        XCTAssertNotEqual(isolatedSong.orders[0].patternIndex, 42)
        XCTAssertEqual(playbackRange.orderIndex, 1)
        XCTAssertEqual(playbackRange.patternIndex, 42)
        XCTAssertEqual(playbackRange.rowCount, 8)
        XCTAssertEqual(isolatedSong.row(at: PlaybackPosition(orderIndex: 1, patternIndex: 42, rowIndex: 0))?.cells[0].note, 49)
    }

    func testPatternLoopTransportBoundaryIdentifiesGeneratedFixtureOrderRanges() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/multi-pattern-loop-boundary.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)

        let firstBoundary = try XCTUnwrap(TestPlaybackPatternLoopTransportBoundaryResolver.boundary(
            containing: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 2),
            in: song
        ))
        let secondBoundary = try XCTUnwrap(TestPlaybackPatternLoopTransportBoundaryResolver.boundary(
            containing: PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 2),
            in: song
        ))
        let thirdBoundary = try XCTUnwrap(TestPlaybackPatternLoopTransportBoundaryResolver.boundary(
            containing: PlaybackPosition(orderIndex: 2, patternIndex: 2, rowIndex: 2),
            in: song
        ))

        XCTAssertEqual(firstBoundary.range.orderEntry, PlaybackOrderEntry(orderIndex: 0, patternIndex: 0))
        XCTAssertEqual(firstBoundary.range.firstPosition, PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0))
        XCTAssertEqual(firstBoundary.range.lastPosition, PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 3))
        XCTAssertEqual(firstBoundary.range.rowCount, 4)
        XCTAssertTrue(firstBoundary.range.contains(PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0)))
        XCTAssertTrue(firstBoundary.range.contains(PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 3)))
        XCTAssertFalse(firstBoundary.range.contains(PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 0)))

        XCTAssertEqual(secondBoundary.range.firstPosition, PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 0))
        XCTAssertEqual(secondBoundary.range.lastPosition, PlaybackPosition(orderIndex: 1, patternIndex: 1, rowIndex: 3))
        XCTAssertEqual(thirdBoundary.range.firstPosition, PlaybackPosition(orderIndex: 2, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(thirdBoundary.range.lastPosition, PlaybackPosition(orderIndex: 2, patternIndex: 2, rowIndex: 3))

        for boundary in [firstBoundary, secondBoundary, thirdBoundary] {
            XCTAssertEqual(boundary.adapterPlanStrategy, .existingPlanRange)
            XCTAssertTrue(boundary.requiresRuntimeAdapterPlan)
            XCTAssertFalse(boundary.usesTimerDrivenTriggers)
            XCTAssertFalse(boundary.clearsActiveVoicesAtBoundary)
        }

        XCTAssertNil(TestPlaybackPatternLoopTransportBoundaryResolver.boundary(
            containing: PlaybackPosition(orderIndex: 1, patternIndex: 0, rowIndex: 0),
            in: song
        ))
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
            PlaybackDebugLaunchConfiguration.stopAfterSecondsEnvironmentKey: "10.5",
            PlaybackDebugLaunchConfiguration.replayAfterStopEnvironmentKey: "true",
            PlaybackDebugLaunchConfiguration.prePlayDelaySecondsEnvironmentKey: "5"
        ])

        XCTAssertEqual(configuration.startRequest?.requestedOrderIndex, 30)
        XCTAssertEqual(configuration.startRequest?.requestedRowIndex, 4)
        XCTAssertEqual(configuration.startRequest?.requestedTickInRow, 2)
        XCTAssertTrue(configuration.autoplay)
        XCTAssertEqual(configuration.stopAfterSeconds, 10.5)
        XCTAssertTrue(configuration.replayAfterStop)
        XCTAssertEqual(configuration.prePlayDelaySeconds, 5)
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

    func testPlaybackSampleDefaultsToXMCenterPanning() {
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25],
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363
        )

        XCTAssertEqual(sample.panning, 128)
    }

    func testPlaybackSamplePreservesLeftCenterRightAndIntermediatePanning() {
        for panning in [UInt8(0), 128, 255, 37] {
            let sample = PlaybackSample(
                instrumentIndex: 1,
                sampleIndex: 0,
                pcm: [0.25],
                volume: 1,
                panning: panning,
                relativeNote: 0,
                finetune: 0,
                baseSampleRate: 8_363
            )

            XCTAssertEqual(sample.panning, panning)
        }
    }

    func testPlaybackSampleAndInstrumentCopyHelpersPreservePanning() throws {
        let original = PlaybackSample(
            instrumentIndex: 3,
            sampleIndex: 2,
            name: "Source",
            pcm: [0, 0.5, -0.5],
            volume: 0.75,
            panning: 37,
            relativeNote: -2,
            finetune: 7,
            baseSampleRate: 8_363,
            sampleLength: 3,
            loopStart: 1,
            loopLength: 2,
            loopType: 1,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )

        let changed = original.withPanning(201)
        let renamedInstrument = PlaybackInstrument(index: 3, name: "Before", samples: [original])
            .withName("After")

        XCTAssertEqual(changed.panning, 201)
        XCTAssertEqual(changed.withPanning(37), original)
        XCTAssertEqual(try XCTUnwrap(renamedInstrument.samples.first).panning, 37)
    }

    func testPlaybackInstrumentAutoVibratoDefaultsToDisabledZeroBytes() {
        let instrument = PlaybackInstrument(index: 1, samples: [])

        XCTAssertEqual(instrument.panningEnvelope, .disabled)
        XCTAssertFalse(instrument.panningEnvelope.enabled)
        XCTAssertTrue(instrument.panningEnvelope.points.isEmpty)
        XCTAssertFalse(instrument.panningEnvelope.sustainEnabled)
        XCTAssertFalse(instrument.panningEnvelope.loopEnabled)
        XCTAssertEqual(instrument.autoVibrato, .disabled)
        XCTAssertEqual(instrument.autoVibrato.waveformType, 0)
        XCTAssertEqual(instrument.autoVibrato.sweep, 0)
        XCTAssertEqual(instrument.autoVibrato.depth, 0)
        XCTAssertEqual(instrument.autoVibrato.rate, 0)
    }

    func testPlaybackInstrumentPreservesExactAutoVibratoAndNeighboringFieldsThroughCopyHelper() throws {
        let sample = PlaybackSample(
            instrumentIndex: 3,
            sampleIndex: 0,
            pcm: [0, 0.5, -0.5],
            volume: 0.75,
            panning: 37,
            relativeNote: -2,
            finetune: 7,
            baseSampleRate: 8_363
        )
        let envelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [PlaybackEnvelopePoint(tick: 0, value: 64)],
            sustainPointIndex: 0,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0x03,
            fadeout: 512
        )
        let autoVibrato = PlaybackInstrumentAutoVibrato(
            waveformType: 255,
            sweep: 1,
            depth: 128,
            rate: 254
        )
        let panningEnvelope = PlaybackPanningEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 32),
                PlaybackEnvelopePoint(tick: 9, value: 48),
            ],
            sustainPointIndex: 1,
            loopStartPointIndex: 0,
            loopEndPointIndex: 1,
            typeFlags: 0x07
        )
        let instrument = PlaybackInstrument(
            index: 3,
            name: "Before",
            samples: [sample],
            volumeEnvelope: envelope,
            panningEnvelope: panningEnvelope,
            autoVibrato: autoVibrato,
            noteSampleMap: Array(repeating: 0, count: 96)
        )

        let renamed = instrument.withName("After")

        XCTAssertEqual(renamed.autoVibrato, autoVibrato)
        XCTAssertEqual(renamed.volumeEnvelope, envelope)
        XCTAssertEqual(renamed.panningEnvelope, panningEnvelope)
        XCTAssertTrue(renamed.panningEnvelope.sustainEnabled)
        XCTAssertTrue(renamed.panningEnvelope.loopEnabled)
        XCTAssertEqual(try XCTUnwrap(renamed.samples.first).panning, 37)
        XCTAssertEqual(renamed.noteSampleMap, Array(repeating: 0, count: 96))
    }

    func testPlaybackInstrumentMapsOneBasedSampleSlotsToStoredSampleIndices() {
        let first = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [1], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        let third = PlaybackSample(instrumentIndex: 1, sampleIndex: 2, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        let instrument = PlaybackInstrument(index: 1, samples: [third, first])

        XCTAssertEqual(instrument.availableSampleSlots, [1, 3])
        XCTAssertEqual(instrument.sample(selectedSampleSlot: 1), first)
        XCTAssertEqual(instrument.sample(selectedSampleSlot: 3), third)
        XCTAssertNil(instrument.sample(selectedSampleSlot: 2))
        XCTAssertNil(instrument.sample(selectedSampleSlot: 0))
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

    private func referenceXMFixtureURL(_ relativePath: String) throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("tests/reference-xm").appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing reference XM fixture \(relativePath)")
        }
        return url
    }

    private func temporaryBasicInstrumentFixture(
        samplePanning: UInt8,
        panningEnvelope: PlaybackPanningEnvelope = .disabled,
        autoVibrato: PlaybackInstrumentAutoVibrato = .disabled,
        fadeout: UInt16 = 0
    ) throws -> URL {
        let sourceURL = try referenceXMFixtureURL("generated/basic-instrument-sample.xm")
        var data = try Data(contentsOf: sourceURL)

        func le16(at offset: Int) -> Int {
            Int(data[offset]) | (Int(data[offset + 1]) << 8)
        }
        func le32(at offset: Int) -> Int {
            Int(data[offset]) |
                (Int(data[offset + 1]) << 8) |
                (Int(data[offset + 2]) << 16) |
                (Int(data[offset + 3]) << 24)
        }

        var offset = 60 + le32(at: 60)
        for _ in 0..<le16(at: 70) {
            let patternHeaderLength = le32(at: offset)
            let packedSize = le16(at: offset + 7)
            offset += patternHeaderLength + packedSize
        }
        let instrumentOffset = offset
        let instrumentHeaderLength = le32(at: instrumentOffset)
        XCTAssertGreaterThanOrEqual(instrumentHeaderLength, 241)
        XCTAssertLessThanOrEqual(panningEnvelope.points.count, 12)
        for (pointIndex, point) in panningEnvelope.points.enumerated() {
            let pointOffset = instrumentOffset + 177 + (pointIndex * 4)
            data[pointOffset] = UInt8(point.tick & 0x00FF)
            data[pointOffset + 1] = UInt8((point.tick >> 8) & 0x00FF)
            data[pointOffset + 2] = UInt8(point.value & 0x00FF)
            data[pointOffset + 3] = UInt8((point.value >> 8) & 0x00FF)
        }
        data[instrumentOffset + 226] = UInt8(panningEnvelope.points.count)
        data[instrumentOffset + 230] = UInt8(panningEnvelope.sustainPointIndex ?? 0)
        data[instrumentOffset + 231] = UInt8(panningEnvelope.loopStartPointIndex ?? 0)
        data[instrumentOffset + 232] = UInt8(panningEnvelope.loopEndPointIndex ?? 0)
        data[instrumentOffset + 234] = panningEnvelope.points.isEmpty ? 0 : panningEnvelope.typeFlags
        data[instrumentOffset + 235] = autoVibrato.waveformType
        data[instrumentOffset + 236] = autoVibrato.sweep
        data[instrumentOffset + 237] = autoVibrato.depth
        data[instrumentOffset + 238] = autoVibrato.rate
        data[instrumentOffset + 239] = UInt8(fadeout & 0x00FF)
        data[instrumentOffset + 240] = UInt8((fadeout >> 8) & 0x00FF)
        let sampleHeaderOffset = instrumentOffset + instrumentHeaderLength
        XCTAssertGreaterThanOrEqual(data.count, sampleHeaderOffset + 40)
        data[sampleHeaderOffset + 15] = samplePanning

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtx-sample-panning-loader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("sample-panning.xm")
        try data.write(to: url, options: .atomic)
        return url
    }
}
