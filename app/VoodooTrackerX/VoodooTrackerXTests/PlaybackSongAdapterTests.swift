import AppKit
import AudioToolbox
import XCTest

final class PlaybackSongAdapterTests: XCTestCase {
    func testPlaybackSongSyntheticAdapterEmptyAndInvalidOrdersAreSafe() {
        let emptySong = makePlaybackSong(orderPatternIndices: [], patternRowCounts: [:])
        let emptySelection = PlaybackSongSyntheticAdapter.adapt(emptySong, startOrderIndex: 0, orderCount: 0, sampleRate: 100)
        let invalidSelection = PlaybackSongSyntheticAdapter.adapt(emptySong, orderIndex: 0, sampleRate: 100)
        let missingPatternSong = makePlaybackSong(orderPatternIndices: [9], patternRowCounts: [:])
        let missingPattern = PlaybackSongSyntheticAdapter.adapt(missingPatternSong, orderIndex: 0, sampleRate: 100)
        let emptyPatternSong = makePlaybackSong(orderPatternIndices: [2], patternRowsByIndex: [2: []])
        let emptyPattern = PlaybackSongSyntheticAdapter.adapt(emptyPatternSong, orderIndex: 0, sampleRate: 100)

        XCTAssertEqual(emptySelection.pattern.rowCount, 0)
        XCTAssertEqual(emptySelection.pattern.events, [])
        XCTAssertEqual(cSyntheticPatternBlock(pattern: emptySelection.pattern, frames: 3).interleavedPCM, [0, 0, 0])

        XCTAssertEqual(invalidSelection.pattern.rowCount, 0)
        XCTAssertEqual(invalidSelection.diagnostics.adaptedOrders.map(\.status), [.invalidOrder])
        XCTAssertEqual(missingPattern.diagnostics.adaptedOrders.map(\.status), [.missingPattern])
        XCTAssertEqual(emptyPattern.pattern.rowCount, 0)
        XCTAssertEqual(emptyPattern.pattern.events, [])
        XCTAssertEqual(emptyPattern.diagnostics.adaptedOrders.map(\.status), [.adapted])
    }

    func testPlaybackSongSyntheticAdapterEmitsBasicTriggerAndDiagnostics() throws {
        let samplePCM: [Float] = [0.25, 0.5, -0.25, 0.75]
        let sample = makePlaybackSample(pcm: samplePCM, volume: 0.625, baseSampleRate: 44_100, loopStart: 1, loopLength: 2, loopType: 1)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 183)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 44_100)
        let event = try XCTUnwrap(plan.pattern.events.first)

        XCTAssertEqual(plan.timingConfig, SyntheticTrackerTimingConfig(speed: 3, bpm: 183, sampleRate: 44_100))
        XCTAssertEqual(plan.pattern.rowCount, 2)
        XCTAssertEqual(event.row, 1)
        XCTAssertEqual(event.tick, 0)
        XCTAssertEqual(event.sample, MixerSampleBuffer(monoPCM: samplePCM))
        XCTAssertEqual(event.gain, 0.625)
        XCTAssertEqual(event.pan, 0)
        XCTAssertEqual(event.playbackStep, 1)
        XCTAssertEqual(event.loop, MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3))
        XCTAssertEqual(plan.diagnostics.emittedRowCount, 2)
        XCTAssertEqual(plan.diagnostics.emittedEventCount, 1)
        XCTAssertEqual(plan.diagnostics.syntheticRowCount, 2)
        XCTAssertEqual(plan.diagnostics.sampleRate, 44_100)
        XCTAssertEqual(plan.diagnostics.initialSpeed, 3)
        XCTAssertEqual(plan.diagnostics.initialBPM, 183)
        XCTAssertTrue(plan.diagnostics.usesLinearFrequencyTable)
        XCTAssertEqual(plan.diagnostics.rowMappings.map(\.syntheticRow), [0, 1])
        XCTAssertEqual(plan.diagnostics.rowDiagnostics.map(\.emittedEventCount), [0, 1])
        let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)
        XCTAssertEqual(mapping.source, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(mapping.channelIndex, 0)
        XCTAssertEqual(mapping.note, 49)
        XCTAssertEqual(mapping.instrumentIndex, 1)
        XCTAssertEqual(mapping.sampleIndex, 0)
        XCTAssertFalse(mapping.sampleMapKeymapPresent)
        XCTAssertNil(mapping.mappedSampleIndex)
        XCTAssertFalse(mapping.mappedSampleValid)
        XCTAssertEqual(mapping.sampleSelectionMethod, .firstPlayableFallback)
        XCTAssertEqual(mapping.sampleSelectionStrategy, "first_playable_fallback")
        XCTAssertTrue(mapping.firstPlayableSampleFallbackUsed)
        XCTAssertFalse(mapping.sampleMapKeymapBehaviorDeferred)
        XCTAssertFalse(mapping.sampleMapKeymapMissingOrDeferred)
        XCTAssertEqual(mapping.syntheticRow, 1)
        XCTAssertEqual(mapping.syntheticTick, 0)
        XCTAssertEqual(mapping.eventIndex, 0)
        XCTAssertEqual(mapping.loopMode, .forward)
        XCTAssertEqual(mapping.volumeColumn, PlaybackSongVolumeColumnDecoder.decode(0))
        XCTAssertFalse(mapping.hasIgnoredVolumeColumn)
        XCTAssertFalse(mapping.hasIgnoredEffect)
        XCTAssertEqual(mapping.effectiveVolumeValue, 64)
        XCTAssertEqual(mapping.effectivePan, 0)
        XCTAssertEqual(mapping.volumeEnvelopeStatus, .absent)
        XCTAssertEqual(mapping.sourceVolumeEnvelopePointCount, 0)
        XCTAssertEqual(mapping.mappedVolumeEnvelopePointCount, 0)
        XCTAssertFalse(mapping.hasDeferredVolumeEnvelopeSustain)
        XCTAssertFalse(mapping.hasDeferredVolumeEnvelopeLoop)
        XCTAssertFalse(mapping.hasDeferredVolumeEnvelopeFadeout)
        XCTAssertFalse(mapping.volumeEnvelopeSemantics.envelopeEnabled)
        XCTAssertEqual(mapping.sampleBaseSampleRate, 44_100)
        XCTAssertEqual(mapping.sampleRelativeNote, 0)
        XCTAssertEqual(mapping.sampleFinetune, 0)
        XCTAssertEqual(mapping.outputSampleRate, 44_100)
        XCTAssertEqual(mapping.effectiveNoteValue, 49)
        XCTAssertEqual(mapping.effectiveNoteIndex, 48)
        XCTAssertEqual(mapping.effectiveFinetune, 0)
        XCTAssertEqual(mapping.linearPeriod, 4_608)
        XCTAssertEqual(mapping.linearFrequency, 44_100)
        XCTAssertEqual(mapping.finetuneStatus, .applied)
        XCTAssertTrue(mapping.usesLinearFrequencyTable)
        XCTAssertEqual(mapping.frequencyTableStatus, .linearApplied)
        XCTAssertTrue(mapping.linearFrequencyApplied)
        XCTAssertFalse(mapping.amigaFrequencyDeferred)
        XCTAssertEqual(mapping.playbackStep, 1)
        XCTAssertTrue(mapping.pitchMappingApplied)
        XCTAssertTrue(mapping.pitchMappingUsedNeutralStep)
    }

    func testPlaybackSongSyntheticAdapterMapsPingPongLoopMetadata() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3, 4], loopStart: 1, loopLength: 3, loopType: 2)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let event = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).pattern.events.first)

        XCTAssertEqual(event.loop, MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4))
    }

    func testPlaybackSongSyntheticAdapterIgnoresUnsupportedCellsSafely() {
        let silentSample = makePlaybackSample(pcm: [], volume: 1)
        let zeroVolumeSample = makePlaybackSample(instrumentIndex: 4, pcm: [1], volume: 0)
        let row = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 0, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 97, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 98, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 2, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 3, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 4, volumeColumn: 0, effectType: 0, effectParam: 0)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [row]],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [makePlaybackSample()]),
                3: PlaybackInstrument(index: 3, samples: [silentSample]),
                4: PlaybackInstrument(index: 4, samples: [zeroVolumeSample])
            ]
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)

        XCTAssertEqual(plan.pattern.events, [])
        XCTAssertEqual(plan.diagnostics.ignoredCellCount, 6)
        XCTAssertEqual(plan.diagnostics.emptyOrSkippedRowCount, 1)
        XCTAssertEqual(plan.diagnostics.ignoredCells.map(\.reason), [
            .instrumentOnly,
            .keyOff,
            .invalidNote,
            .unknownInstrument,
            .samplePCMEmpty,
            .instrumentHasNoPlayableSample
        ])
        XCTAssertEqual(plan.diagnostics.ignoredCells.map(\.channelIndex), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(plan.diagnostics.deferredCellFields.map(\.field), [.keyOff])
    }

    func testPlaybackSongSyntheticAdapterReportsEventCoverageAndSkipReasons() throws {
        let playableSample = makePlaybackSample(sampleIndex: 1, pcm: [0.25, 0.5], volume: 1, baseSampleRate: 100)
        let emptySample = makePlaybackSample(instrumentIndex: 2, pcm: [], volume: 1)
        let zeroVolumeSample = makePlaybackSample(instrumentIndex: 3, pcm: [1], volume: 0)
        let row = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 97, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 9, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 2, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 3, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 98, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 0, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [row]],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [
                    makePlaybackSample(pcm: [], volume: 1),
                    playableSample
                ]),
                2: PlaybackInstrument(index: 2, samples: [emptySample]),
                3: PlaybackInstrument(index: 3, samples: [zeroVolumeSample])
            ]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))
        let coverage = result.diagnostics.eventCoverage
        let scheduled = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(coverage.totalCellsVisited, 9)
        XCTAssertEqual(coverage.emptyCells, 1)
        XCTAssertEqual(coverage.normalNoteCells, 5)
        XCTAssertEqual(coverage.noteOffCells, 1)
        XCTAssertEqual(coverage.invalidNoteCells, 1)
        XCTAssertEqual(coverage.instrumentOnlyCells, 1)
        XCTAssertEqual(coverage.noteWithInstrumentCells, 4)
        XCTAssertEqual(coverage.noteWithMissingOrZeroInstrumentCells, 1)
        XCTAssertEqual(coverage.scheduledNoteEvents, 1)
        XCTAssertEqual(coverage.skippedNoteEvents, 4)
        XCTAssertEqual(coverage.skippedNoteOffEventsNoActiveVoice, 1)
        XCTAssertEqual(coverage.sampleMapSelectionEvents, 0)
        XCTAssertEqual(coverage.firstPlayableSampleFallbackEvents, 1)
        XCTAssertEqual(coverage.fallbackAfterInvalidSampleMapEvents, 0)
        XCTAssertEqual(coverage.skippedNoValidSampleEvents, 2)
        XCTAssertEqual(coverage.sampleMapKeymapDeferredEvents, 1)
        XCTAssertEqual(scheduled.source, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(scheduled.channelIndex, 6)
        XCTAssertEqual(scheduled.sampleIndex, 1)
        XCTAssertEqual(scheduled.selectedSampleLength, 2)
        XCTAssertFalse(scheduled.sampleMapKeymapPresent)
        XCTAssertNil(scheduled.mappedSampleIndex)
        XCTAssertFalse(scheduled.mappedSampleValid)
        XCTAssertEqual(scheduled.sampleSelectionMethod, .firstPlayableFallback)
        XCTAssertEqual(scheduled.sampleSelectionStrategy, "first_playable_fallback")
        XCTAssertTrue(scheduled.firstPlayableSampleFallbackUsed)
        XCTAssertTrue(scheduled.sampleMapKeymapBehaviorDeferred)
        XCTAssertTrue(scheduled.sampleMapKeymapMissingOrDeferred)
        XCTAssertEqual(result.diagnostics.ignoredCells.map(\.skipReason), [
            .emptyCell,
            .noteOffKeyOffOnly,
            .missingInstrument,
            .unknownInstrument,
            .samplePCMEmpty,
            .instrumentHasNoPlayableSample,
            .invalidNote,
            .instrumentOnly
        ])
        XCTAssertEqual(result.diagnostics.ignoredCells[2].source, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(result.diagnostics.ignoredCells[2].channelIndex, 2)
    }

    func testPlaybackSongSyntheticAdapterUsesNoteSampleMapForMultiSampleInstrument() throws {
        let lowSample = makePlaybackSample(sampleIndex: 0, pcm: [1], baseSampleRate: 100)
        let highSample = makePlaybackSample(sampleIndex: 1, pcm: [0.25], baseSampleRate: 100)
        let row = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
            PlaybackCell(note: 61, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [row]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [lowSample, highSample],
                    noteSampleMap: makeNoteSampleMap(overrides: [49: 0, 61: 1])
                )
            ]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))

        XCTAssertEqual(result.diagnostics.eventMappings.map(\.sampleIndex), [0, 1])
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.mappedSampleIndex), [0, 1])
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.sampleSelectionMethod), [.sampleMap, .sampleMap])
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.firstPlayableSampleFallbackUsed), [false, false])
        XCTAssertEqual(result.diagnostics.eventCoverage.normalNoteCells, 2)
        XCTAssertEqual(result.diagnostics.eventCoverage.scheduledNoteEvents, 2)
        XCTAssertEqual(result.diagnostics.eventCoverage.sampleMapSelectionEvents, 2)
        XCTAssertEqual(result.diagnostics.eventCoverage.firstPlayableSampleFallbackEvents, 0)
        XCTAssertEqual(result.diagnostics.eventCoverage.skippedNoteEvents, 0)
    }

    func testPlaybackSongSyntheticAdapterMappedSampleMetadataDrivesPitchLoopVolumeAndEnvelope() throws {
        let unusedSample = makePlaybackSample(sampleIndex: 0, pcm: [9], baseSampleRate: 100)
        let mappedSample = makePlaybackSample(
            sampleIndex: 1,
            pcm: [0, 1, 2, 3, 4],
            volume: 0.5,
            relativeNote: 12,
            finetune: 64,
            baseSampleRate: 100,
            loopStart: 1,
            loopLength: 3,
            loopType: 1
        )
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 1, value: 32)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [unusedSample, mappedSample],
                    volumeEnvelope: envelope,
                    noteSampleMap: makeNoteSampleMap(overrides: [49: 1])
                )
            ]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.sampleSelectionMethod, .sampleMap)
        XCTAssertEqual(mapping.sampleIndex, 1)
        XCTAssertEqual(mapping.sampleRelativeNote, 12)
        XCTAssertEqual(mapping.sampleFinetune, 64)
        XCTAssertEqual(mapping.sampleBaseSampleRate, 100)
        XCTAssertEqual(mapping.playbackStep, 2 * pow(2.0, 0.5 / 12.0), accuracy: 0.000000001)
        XCTAssertEqual(event.gain, 0.5)
        XCTAssertEqual(event.loop, MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4))
        XCTAssertEqual(mapping.volumeEnvelopeStatus, .mapped)
        XCTAssertEqual(mapping.mappedVolumeEnvelopePointCount, 2)
    }

    func testPlaybackSongSyntheticAdapterFallsBackAfterInvalidMappedSampleIndex() throws {
        let fallbackSample = makePlaybackSample(sampleIndex: 0, pcm: [0.25], baseSampleRate: 100)
        let alternateSample = makePlaybackSample(sampleIndex: 1, pcm: [0.5], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [fallbackSample, alternateSample],
                    noteSampleMap: makeNoteSampleMap(overrides: [49: 9])
                )
            ]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.sampleIndex, 0)
        XCTAssertEqual(mapping.mappedSampleIndex, 9)
        XCTAssertFalse(mapping.mappedSampleValid)
        XCTAssertEqual(mapping.sampleSelectionMethod, .fallbackAfterInvalidMap)
        XCTAssertTrue(mapping.firstPlayableSampleFallbackUsed)
        XCTAssertEqual(result.diagnostics.eventCoverage.fallbackAfterInvalidSampleMapEvents, 1)
        XCTAssertEqual(result.diagnostics.eventCoverage.firstPlayableSampleFallbackEvents, 1)
        XCTAssertEqual(result.block.interleavedPCM, [0.25])
    }

    func testPlaybackSongSyntheticAdapterMappedEmptyPCMUsesFallbackWhenAvailable() throws {
        let fallbackSample = makePlaybackSample(sampleIndex: 0, pcm: [0.25], baseSampleRate: 100)
        let emptyMappedSample = makePlaybackSample(sampleIndex: 1, pcm: [], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [fallbackSample, emptyMappedSample],
                    noteSampleMap: makeNoteSampleMap(overrides: [49: 1])
                )
            ]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.sampleIndex, 0)
        XCTAssertEqual(mapping.mappedSampleIndex, 1)
        XCTAssertFalse(mapping.mappedSampleValid)
        XCTAssertEqual(mapping.sampleSelectionMethod, .fallbackAfterInvalidMap)
        XCTAssertEqual(result.block.interleavedPCM, [0.25])
    }

    func testPlaybackSongSyntheticAdapterSkipsMappedEmptyPCMWhenNoFallbackExists() throws {
        let emptyMappedSample = makePlaybackSample(sampleIndex: 0, pcm: [], volume: 1, baseSampleRate: 100)
        let zeroVolumeSample = makePlaybackSample(sampleIndex: 1, pcm: [1], volume: 0, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [emptyMappedSample, zeroVolumeSample],
                    noteSampleMap: makeNoteSampleMap(overrides: [49: 0])
                )
            ]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        ))
        let ignored = try XCTUnwrap(result.diagnostics.ignoredCells.first)

        XCTAssertEqual(result.plan.pattern.events, [])
        XCTAssertEqual(result.block.interleavedPCM, [0])
        XCTAssertEqual(ignored.reason, .samplePCMEmpty)
        XCTAssertEqual(ignored.skipReason, .samplePCMEmpty)
        XCTAssertEqual(ignored.mappedSampleIndex, 0)
        XCTAssertEqual(ignored.sampleSelectionMethod, .skippedNoValidSample)
        XCTAssertEqual(result.diagnostics.eventCoverage.skippedNoValidSampleEvents, 1)
    }

    func testPlaybackSongSyntheticAdapterFlattensBoundedMultiOrderRows() {
        let sample = makePlaybackSample(pcm: [1])
        let song = makePlaybackSong(
            orderPatternIndices: [2, 5],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1)
                ],
                5: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderRange: 0..<2, sampleRate: 100)

        XCTAssertEqual(plan.pattern.rowCount, 3)
        XCTAssertEqual(plan.pattern.events.map(\.row), [2])
        XCTAssertEqual(plan.diagnostics.adaptedOrders, [
            PlaybackSongSyntheticOrderDiagnostic(requestedOrderIndex: 0, patternIndex: 2, syntheticStartRow: 0, rowCount: 2, status: .adapted),
            PlaybackSongSyntheticOrderDiagnostic(requestedOrderIndex: 1, patternIndex: 5, syntheticStartRow: 2, rowCount: 1, status: .adapted)
        ])
        XCTAssertEqual(plan.diagnostics.rowMappings, [
            PlaybackSongSyntheticRowMapping(source: PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0), syntheticRow: 0),
            PlaybackSongSyntheticRowMapping(source: PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1), syntheticRow: 1),
            PlaybackSongSyntheticRowMapping(source: PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 0), syntheticRow: 2)
        ])
    }

    func testPlaybackSongSyntheticAdapterAppliesSupportedVolumeColumnAndStillIgnoresEffectColumn() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 0.5)
        let plainSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 125)
        )
        let volumeOnlySong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x20)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 125)
        )
        let volumeAndEffectSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x20, effectType: 0x07, effectParam: 0x43)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 125)
        )

        let plain = PlaybackSongSyntheticAdapter.adapt(plainSong, orderIndex: 0, sampleRate: 100)
        let volumeOnly = PlaybackSongSyntheticAdapter.adapt(volumeOnlySong, orderIndex: 0, sampleRate: 100)
        let volumeAndEffect = PlaybackSongSyntheticAdapter.adapt(volumeAndEffectSong, orderIndex: 0, sampleRate: 100)
        let volumeMapping = try XCTUnwrap(volumeAndEffect.diagnostics.eventMappings.first)

        XCTAssertEqual(volumeAndEffect.timingConfig, SyntheticTrackerTimingConfig(speed: 4, bpm: 125, sampleRate: 100))
        XCTAssertNotEqual(volumeOnly.pattern.events, plain.pattern.events)
        XCTAssertEqual(volumeAndEffect.pattern.events, volumeOnly.pattern.events)
        XCTAssertEqual(try XCTUnwrap(volumeAndEffect.pattern.events.first).gain, 0.125)
        XCTAssertEqual(volumeMapping.volumeColumn.command, .setVolume(value: 16))
        XCTAssertTrue(volumeMapping.volumeColumn.applied)
        XCTAssertFalse(volumeMapping.hasIgnoredVolumeColumn)
        XCTAssertTrue(volumeMapping.hasIgnoredEffect)
        XCTAssertEqual(volumeAndEffect.diagnostics.ignoredVolumeColumnFieldCount, 0)
        XCTAssertEqual(volumeAndEffect.diagnostics.ignoredEffectFieldCount, 1)
        XCTAssertEqual(volumeAndEffect.diagnostics.deferredCellFields.map(\.field), [.effect])
    }

    func testPlaybackSongAdapterNoFxxTimingMatchesConstantInitialTiming() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1),
                    makePlaybackRow(index: 2, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 14
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)

        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6, 12])
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 6, 6])
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.effectiveBPM), [250, 250, 250])
        XCTAssertEqual(result.diagnostics.timingChanges, [])
        XCTAssertEqual(event.scheduledStartFrame, 12)
        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 12) + [1, 0])
    }

    func testPlaybackSongAdapterFxxSpeedChangeAffectsFollowingRowStartFrames() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                    makePlaybackRow(index: 1),
                    makePlaybackRow(index: 2, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 11
        ))
        let change = try XCTUnwrap(result.diagnostics.timingChanges.first)
        let event = try XCTUnwrap(result.plan.pattern.events.first)

        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6, 9])
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 3, 3])
        XCTAssertEqual(change.kind, .speed)
        XCTAssertTrue(change.applied)
        XCTAssertEqual(change.speedBefore, 6)
        XCTAssertEqual(change.speedAfter, 3)
        XCTAssertEqual(change.bpmAfter, 250)
        XCTAssertEqual(change.rowStartFrame, 0)
        XCTAssertEqual(change.appliesToSyntheticRowAfter, 1)
        XCTAssertEqual(event.scheduledStartFrame, 9)
        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 9) + [1, 0])
    }

    func testPlaybackSongAdapterFxxBPMChangeAffectsFollowingRowStartFrames() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x7D),
                    makePlaybackRow(index: 1),
                    makePlaybackRow(index: 2, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        ))
        let change = try XCTUnwrap(result.diagnostics.timingChanges.first)
        let event = try XCTUnwrap(result.plan.pattern.events.first)

        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 2, 6])
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.effectiveBPM), [250, 125, 125])
        XCTAssertEqual(change.kind, .bpm)
        XCTAssertEqual(change.bpmBefore, 250)
        XCTAssertEqual(change.bpmAfter, 125)
        XCTAssertEqual(change.speedAfter, 2)
        XCTAssertEqual(event.scheduledStartFrame, 6)
        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 6) + [1, 0])
    }

    func testPlaybackSongAdapterFxxSpeedAndBPMChangesUseChannelOrderForFollowingRows() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let timingRow = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0F, effectParam: 0x03),
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0F, effectParam: 0x7D)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    timingRow,
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)

        XCTAssertEqual(result.diagnostics.timingChanges.map(\.channelIndex), [0, 1])
        XCTAssertEqual(result.diagnostics.timingChanges.map(\.kind), [.speed, .bpm])
        XCTAssertEqual(result.diagnostics.timingChanges[1].speedBefore, 3)
        XCTAssertEqual(result.diagnostics.timingChanges[1].bpmBefore, 250)
        XCTAssertEqual(result.diagnostics.timingChanges[1].speedAfter, 3)
        XCTAssertEqual(result.diagnostics.timingChanges[1].bpmAfter, 125)
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6])
        XCTAssertEqual(result.diagnostics.rowTiming[1].effectiveSpeed, 3)
        XCTAssertEqual(result.diagnostics.rowTiming[1].effectiveBPM, 125)
        XCTAssertEqual(event.scheduledStartFrame, 6)
    }

    func testPlaybackSongAdapterF00IsDiagnosedAsIgnoredNoOpForFollowingRows() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x00),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        ))
        let change = try XCTUnwrap(result.diagnostics.timingChanges.first)
        let event = try XCTUnwrap(result.plan.pattern.events.first)

        XCTAssertEqual(change.kind, .ignoredF00)
        XCTAssertFalse(change.applied)
        XCTAssertEqual(change.speedBefore, change.speedAfter)
        XCTAssertEqual(change.bpmBefore, change.bpmAfter)
        XCTAssertEqual(result.diagnostics.deferredCellFields.map(\.field), [])
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6])
        XCTAssertEqual(event.scheduledStartFrame, 6)
        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 6) + [1, 0])
    }

    func testPlaybackSongAdapterVolumeColumnSetVolumeAndPanningStillApplyWithFxxTiming() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let noteRow = PlaybackRow(index: 1, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0, effectParam: 0),
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0xCF, effectType: 0, effectParam: 0)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                    noteRow
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 2),
            frames: 8
        ))

        XCTAssertEqual(result.plan.pattern.events.map(\.scheduledStartFrame), [6, 6])
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.volumeColumn.command), [
            .setVolume(value: 32),
            .setPanning(value: 255)
        ])
        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 12) + [0.5, 1.5, 0, 0])
    }

    func testPlaybackSongAdapterParsedVolumeEnvelopeUsesEventTimingWithFxxBPM() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 1, value: 32)
        ])
        let sample = makePlaybackSample(pcm: [1, 1, 1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x7D),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(event.volumeEnvelope, MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 1),
            MixerEnvelopePoint(positionFrame: 2, value: 0.5)
        ]))
        XCTAssertEqual(mapping.volumeEnvelopeStatus, .mapped)
        XCTAssertEqual(result.diagnostics.rowTiming[1].effectiveBPM, 125)
        XCTAssertEqual(result.block.interleavedPCM, [0, 1, 0.75, 0.5])
    }

    func testPlaybackSongAdapterPitchStepSplitAndResetRemainDeterministicWithFxxTiming() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3, 4, 5, 6, 7], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                    makePlaybackRow(index: 1, note: 61, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 10
        )
        let renderer = PlaybackSongOfflineRenderer()

        let single = renderer.render(request)
        let repeated = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [2, 3, 5])
        let session = renderer.prepare(request)
        let resetFirst = session.render(frames: 10)
        _ = session.render(frames: 2)
        session.reset()
        let resetSecond = session.render(frames: 10)
        let mapping = try XCTUnwrap(single.diagnostics.eventMappings.first)
        let event = try XCTUnwrap(single.plan.pattern.events.first)

        XCTAssertEqual(event.scheduledStartFrame, 6)
        XCTAssertEqual(mapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertEqual(single.block.interleavedPCM, Array(repeating: Float(0), count: 7) + [2, 4, 6])
        XCTAssertEqual(repeated.block, single.block)
        XCTAssertEqual(split.block, single.block)
        XCTAssertEqual(resetFirst, resetSecond)
        XCTAssertEqual(resetFirst, single.block)
    }

    func testPlaybackSongSyntheticAdapterCSoftwareMixerRenderStartsAtExpectedFrame() {
        let sample = makePlaybackSample(pcm: [1, 0.5])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )
        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)

        let block = cSyntheticPatternBlock(pattern: plan.pattern, frames: 5, timingConfig: plan.timingConfig)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 1, 0.5, 0])
    }

    func testPlaybackSongSyntheticAdapterNeutralPitchStepPreservesBaselineOutput() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.playbackStep, 1, accuracy: 0.000000001)
        XCTAssertTrue(mapping.pitchMappingApplied)
        XCTAssertTrue(mapping.pitchMappingUsedNeutralStep)
        XCTAssertEqual(result.block.interleavedPCM, [0, 1, 2, 3, 0])
    }

    func testPlaybackSongSyntheticAdapterFractionalPitchStepUsesLinearInterpolation() throws {
        let sample = makePlaybackSample(pcm: [0, 10, 20, 30], baseSampleRate: 150)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.playbackStep, 1.5, accuracy: 0.000000001)
        XCTAssertEqual(result.block.interleavedPCM, [0, 15, 30, 0])
        XCTAssertNotEqual(result.block.interleavedPCM, [0, 10, 30, 0])
    }

    func testPlaybackSongSyntheticAdapterDifferentNotesProduceDifferentStepsAndOutputProgression() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3, 4, 5, 6, 7], baseSampleRate: 100)
        let lowSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let highSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let low = renderer.render(PlaybackSongOfflineRenderRequest(song: lowSong, orderIndex: 0, config: config, frames: 4))
        let high = renderer.render(PlaybackSongOfflineRenderRequest(song: highSong, orderIndex: 0, config: config, frames: 4))
        let lowMapping = try XCTUnwrap(low.diagnostics.eventMappings.first)
        let highMapping = try XCTUnwrap(high.diagnostics.eventMappings.first)

        XCTAssertEqual(lowMapping.playbackStep, 1, accuracy: 0.000000001)
        XCTAssertEqual(highMapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertGreaterThan(highMapping.playbackStep, lowMapping.playbackStep)
        XCTAssertNotEqual(low.block.interleavedPCM, high.block.interleavedPCM)
        XCTAssertEqual(low.block.interleavedPCM, [0, 1, 2, 3])
        XCTAssertEqual(high.block.interleavedPCM, [0, 2, 4, 6])
    }

    func testPlaybackSongSyntheticAdapterLinearPitchStepsAreMonotonicAndOctavesDouble() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3, 4, 5, 6, 7], baseSampleRate: 100)
        let notes: [UInt8] = [48, 49, 50, 61]
        let steps = try notes.map { note -> Double in
            let song = makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: note, instrument: 1)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
            )
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            return try XCTUnwrap(plan.diagnostics.eventMappings.first).playbackStep
        }

        XCTAssertLessThan(steps[0], steps[1])
        XCTAssertLessThan(steps[1], steps[2])
        XCTAssertEqual(steps[3], steps[1] * 2, accuracy: 0.000000001)
    }

    func testPlaybackSongSyntheticAdapterMatchesFT2LinearPeriodExpectedValues() throws {
        struct LinearPitchCase {
            let name: String
            let note: UInt8
            let relativeNote: Int
            let sampleFinetune: Int
            let effectParam: UInt8?
            let outputSampleRate: Double
            let expectedEffectiveNoteValue: Int
            let expectedEffectiveNoteIndex: Int
            let expectedFinetune: Int
            let expectedLinearPeriod: Double
            let expectedLinearFrequency: Double
        }

        let baseSampleRate = 8_363.0
        let cases = [
            LinearPitchCase(
                name: "C-0",
                note: 1,
                relativeNote: 0,
                sampleFinetune: 0,
                effectParam: nil,
                outputSampleRate: 44_100,
                expectedEffectiveNoteValue: 1,
                expectedEffectiveNoteIndex: 0,
                expectedFinetune: 0,
                expectedLinearPeriod: 7_680,
                expectedLinearFrequency: baseSampleRate / 16.0
            ),
            LinearPitchCase(
                name: "C-1",
                note: 13,
                relativeNote: 0,
                sampleFinetune: 0,
                effectParam: nil,
                outputSampleRate: 44_100,
                expectedEffectiveNoteValue: 13,
                expectedEffectiveNoteIndex: 12,
                expectedFinetune: 0,
                expectedLinearPeriod: 6_912,
                expectedLinearFrequency: baseSampleRate / 8.0
            ),
            LinearPitchCase(
                name: "C-4 at 44.1 kHz",
                note: 49,
                relativeNote: 0,
                sampleFinetune: 0,
                effectParam: nil,
                outputSampleRate: 44_100,
                expectedEffectiveNoteValue: 49,
                expectedEffectiveNoteIndex: 48,
                expectedFinetune: 0,
                expectedLinearPeriod: 4_608,
                expectedLinearFrequency: baseSampleRate
            ),
            LinearPitchCase(
                name: "C-4 at 48 kHz",
                note: 49,
                relativeNote: 0,
                sampleFinetune: 0,
                effectParam: nil,
                outputSampleRate: 48_000,
                expectedEffectiveNoteValue: 49,
                expectedEffectiveNoteIndex: 48,
                expectedFinetune: 0,
                expectedLinearPeriod: 4_608,
                expectedLinearFrequency: baseSampleRate
            ),
            LinearPitchCase(
                name: "C-5",
                note: 61,
                relativeNote: 0,
                sampleFinetune: 0,
                effectParam: nil,
                outputSampleRate: 44_100,
                expectedEffectiveNoteValue: 61,
                expectedEffectiveNoteIndex: 60,
                expectedFinetune: 0,
                expectedLinearPeriod: 3_840,
                expectedLinearFrequency: baseSampleRate * 2.0
            ),
            LinearPitchCase(
                name: "relative note -12",
                note: 49,
                relativeNote: -12,
                sampleFinetune: 0,
                effectParam: nil,
                outputSampleRate: 44_100,
                expectedEffectiveNoteValue: 37,
                expectedEffectiveNoteIndex: 36,
                expectedFinetune: 0,
                expectedLinearPeriod: 5_376,
                expectedLinearFrequency: baseSampleRate / 2.0
            ),
            LinearPitchCase(
                name: "relative note +12",
                note: 49,
                relativeNote: 12,
                sampleFinetune: 0,
                effectParam: nil,
                outputSampleRate: 44_100,
                expectedEffectiveNoteValue: 61,
                expectedEffectiveNoteIndex: 60,
                expectedFinetune: 0,
                expectedLinearPeriod: 3_840,
                expectedLinearFrequency: baseSampleRate * 2.0
            ),
            LinearPitchCase(
                name: "negative finetune",
                note: 49,
                relativeNote: 0,
                sampleFinetune: -64,
                effectParam: nil,
                outputSampleRate: 44_100,
                expectedEffectiveNoteValue: 49,
                expectedEffectiveNoteIndex: 48,
                expectedFinetune: -64,
                expectedLinearPeriod: 4_640,
                expectedLinearFrequency: baseSampleRate * pow(2.0, -32.0 / 768.0)
            ),
            LinearPitchCase(
                name: "positive finetune",
                note: 49,
                relativeNote: 0,
                sampleFinetune: 64,
                effectParam: nil,
                outputSampleRate: 44_100,
                expectedEffectiveNoteValue: 49,
                expectedEffectiveNoteIndex: 48,
                expectedFinetune: 64,
                expectedLinearPeriod: 4_576,
                expectedLinearFrequency: baseSampleRate * pow(2.0, 32.0 / 768.0)
            ),
            LinearPitchCase(
                name: "E5F finetune override",
                note: 49,
                relativeNote: 0,
                sampleFinetune: -64,
                effectParam: 0x5F,
                outputSampleRate: 44_100,
                expectedEffectiveNoteValue: 49,
                expectedEffectiveNoteIndex: 48,
                expectedFinetune: 112,
                expectedLinearPeriod: 4_552,
                expectedLinearFrequency: baseSampleRate * pow(2.0, 56.0 / 768.0)
            ),
        ]

        for pitchCase in cases {
            let sample = makePlaybackSample(
                pcm: [0, 1, 2, 3],
                relativeNote: pitchCase.relativeNote,
                finetune: pitchCase.sampleFinetune,
                baseSampleRate: baseSampleRate
            )
            let row = makePlaybackRow(
                index: 0,
                note: pitchCase.note,
                instrument: 1,
                effectType: pitchCase.effectParam == nil ? 0 : 0x0E,
                effectParam: pitchCase.effectParam ?? 0
            )
            let song = makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [row]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
            )

            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: pitchCase.outputSampleRate)
            let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first, pitchCase.name)

            XCTAssertEqual(mapping.sampleBaseSampleRate, baseSampleRate, pitchCase.name)
            XCTAssertEqual(mapping.outputSampleRate, pitchCase.outputSampleRate, pitchCase.name)
            XCTAssertEqual(mapping.effectiveNoteValue, pitchCase.expectedEffectiveNoteValue, pitchCase.name)
            XCTAssertEqual(mapping.effectiveNoteIndex, pitchCase.expectedEffectiveNoteIndex, pitchCase.name)
            XCTAssertEqual(mapping.effectiveFinetune, pitchCase.expectedFinetune, pitchCase.name)
            XCTAssertEqual(
                try XCTUnwrap(mapping.linearPeriod, pitchCase.name),
                pitchCase.expectedLinearPeriod,
                accuracy: 0.000_001,
                pitchCase.name
            )
            XCTAssertEqual(
                try XCTUnwrap(mapping.linearFrequency, pitchCase.name),
                pitchCase.expectedLinearFrequency,
                accuracy: 0.000_001,
                pitchCase.name
            )
            XCTAssertEqual(
                mapping.playbackStep,
                pitchCase.expectedLinearFrequency / pitchCase.outputSampleRate,
                accuracy: 0.000_001,
                pitchCase.name
            )
        }
    }

    func testPlaybackSongSyntheticAdapterRelativeNoteUsesXMRealNoteRange() throws {
        func mapping(note: UInt8, relativeNote: Int) throws -> PlaybackSongSyntheticEventMapping {
            let sample = makePlaybackSample(
                pcm: [0, 1, 2, 3],
                relativeNote: relativeNote,
                baseSampleRate: 8_363
            )
            let song = makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: note, instrument: 1)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
            )
            return try XCTUnwrap(
                PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 44_100)
                    .diagnostics
                    .eventMappings
                    .first
            )
        }

        let highTransposed = try mapping(note: 96, relativeNote: 12)
        let lowTransposed = try mapping(note: 1, relativeNote: -12)

        XCTAssertEqual(highTransposed.effectiveNoteValue, 108)
        XCTAssertEqual(highTransposed.effectiveNoteIndex, 107)
        XCTAssertEqual(try XCTUnwrap(highTransposed.linearPeriod), 832, accuracy: 0.000_001)
        XCTAssertEqual(
            try XCTUnwrap(highTransposed.linearFrequency),
            8_363.0 * pow(2.0, (4_608.0 - 832.0) / 768.0),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            highTransposed.playbackStep,
            (8_363.0 * pow(2.0, (4_608.0 - 832.0) / 768.0)) / 44_100.0,
            accuracy: 0.000_001
        )

        XCTAssertEqual(lowTransposed.effectiveNoteValue, 1)
        XCTAssertEqual(lowTransposed.effectiveNoteIndex, 0)
        XCTAssertEqual(try XCTUnwrap(lowTransposed.linearPeriod), 7_680, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(lowTransposed.linearFrequency), 8_363.0 / 16.0, accuracy: 0.000_001)
    }

    func testPlaybackSongSyntheticAdapterUsesRelativeNoteAndFinetuneInPlaybackStep() throws {
        let relativeSample = makePlaybackSample(pcm: [0, 1, 2, 3], relativeNote: 12, baseSampleRate: 100)
        let negativeRelativeSample = makePlaybackSample(pcm: [0, 1, 2, 3], relativeNote: -12, baseSampleRate: 100)
        let finetunedSample = makePlaybackSample(pcm: [0, 1, 2, 3], finetune: 64, baseSampleRate: 100)
        let negativeFinetunedSample = makePlaybackSample(pcm: [0, 1, 2, 3], finetune: -64, baseSampleRate: 100)
        let relativeSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [relativeSample])]
        )
        let negativeRelativeSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [negativeRelativeSample])]
        )
        let finetunedSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [finetunedSample])]
        )
        let negativeFinetunedSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [negativeFinetunedSample])]
        )

        let relative = PlaybackSongSyntheticAdapter.adapt(relativeSong, orderIndex: 0, sampleRate: 100)
        let negativeRelative = PlaybackSongSyntheticAdapter.adapt(negativeRelativeSong, orderIndex: 0, sampleRate: 100)
        let finetuned = PlaybackSongSyntheticAdapter.adapt(finetunedSong, orderIndex: 0, sampleRate: 100)
        let negativeFinetuned = PlaybackSongSyntheticAdapter.adapt(negativeFinetunedSong, orderIndex: 0, sampleRate: 100)
        let relativeMapping = try XCTUnwrap(relative.diagnostics.eventMappings.first)
        let negativeRelativeMapping = try XCTUnwrap(negativeRelative.diagnostics.eventMappings.first)
        let finetunedMapping = try XCTUnwrap(finetuned.diagnostics.eventMappings.first)
        let negativeFinetunedMapping = try XCTUnwrap(negativeFinetuned.diagnostics.eventMappings.first)

        XCTAssertEqual(relativeMapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertEqual(relativeMapping.sampleRelativeNote, 12)
        XCTAssertEqual(negativeRelativeMapping.playbackStep, 0.5, accuracy: 0.000000001)
        XCTAssertEqual(negativeRelativeMapping.sampleRelativeNote, -12)
        XCTAssertEqual(finetunedMapping.playbackStep, pow(2.0, 0.5 / 12.0), accuracy: 0.000000001)
        XCTAssertEqual(finetunedMapping.sampleFinetune, 64)
        XCTAssertEqual(finetunedMapping.finetuneStatus, .applied)
        XCTAssertEqual(negativeFinetunedMapping.playbackStep, pow(2.0, -0.5 / 12.0), accuracy: 0.000000001)
        XCTAssertEqual(negativeFinetunedMapping.sampleFinetune, -64)
        XCTAssertLessThan(negativeFinetunedMapping.playbackStep, 1)
        XCTAssertGreaterThan(finetunedMapping.playbackStep, 1)
    }

    func testPlaybackSongSyntheticAdapterE5xSetFinetuneAdjustsSameCellSampleStep() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3], baseSampleRate: 100)
        let baselineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let e5xSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x5F)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let baseline = PlaybackSongSyntheticAdapter.adapt(baselineSong, orderIndex: 0, sampleRate: 100)
        let e5x = PlaybackSongSyntheticAdapter.adapt(e5xSong, orderIndex: 0, sampleRate: 100)
        let baselineMapping = try XCTUnwrap(baseline.diagnostics.eventMappings.first)
        let e5xMapping = try XCTUnwrap(e5x.diagnostics.eventMappings.first)
        let diagnostic = try XCTUnwrap(e5x.diagnostics.setFinetuneEffects.first)

        XCTAssertEqual(e5x.diagnostics.setFinetuneEffectCount, 1)
        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.finetuneNibble, 15)
        XCTAssertEqual(diagnostic.sampleFinetune, 0)
        XCTAssertEqual(diagnostic.effectiveFinetune, 112)
        XCTAssertEqual(e5xMapping.sampleFinetune, 0)
        XCTAssertEqual(e5xMapping.effectiveFinetune, 112)
        XCTAssertEqual(e5xMapping.playbackStep, pow(2.0, 0.875 / 12.0), accuracy: 0.000000001)
        XCTAssertGreaterThan(e5xMapping.playbackStep, baselineMapping.playbackStep)
    }

    func testPlaybackSongSyntheticAdapterE50AndE5FProduceDistinctDeterministicSteps() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3], baseSampleRate: 100)
        func step(for effectParam: UInt8) throws -> PlaybackSongSyntheticEventMapping {
            let song = makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: effectParam)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
            )
            return try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.eventMappings.first)
        }

        let e50 = try step(for: 0x50)
        let e5f = try step(for: 0x5F)

        XCTAssertEqual(e50.effectiveFinetune, -128)
        XCTAssertEqual(e5f.effectiveFinetune, 112)
        XCTAssertEqual(e50.playbackStep, pow(2.0, -1.0 / 12.0), accuracy: 0.000000001)
        XCTAssertEqual(e5f.playbackStep, pow(2.0, 0.875 / 12.0), accuracy: 0.000000001)
        XCTAssertLessThan(e50.playbackStep, e5f.playbackStep)
    }

    func testPlaybackSongSyntheticAdapterE5xWithoutNoteIsDeferredAndDoesNotAffectLaterNotes() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0x5F),
                makePlaybackRow(index: 1, note: 49, instrument: 1),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let setFinetune = try XCTUnwrap(diagnostics.setFinetuneEffects.first)
        let laterNote = try XCTUnwrap(diagnostics.eventMappings.first)
        let effectCommand = try XCTUnwrap(diagnostics.effectCommandDiagnostics.first { $0.decodedLabel == "E5x set finetune" })

        XCTAssertEqual(diagnostics.setFinetuneEffectCount, 1)
        XCTAssertEqual(setFinetune.status, .noNoteDeferred)
        XCTAssertTrue(setFinetune.deferred)
        XCTAssertTrue(setFinetune.effectMemoryDeferred)
        XCTAssertEqual(setFinetune.finetuneNibble, 15)
        XCTAssertEqual(effectCommand.status, .deferredUnsupported)
        XCTAssertEqual(laterNote.effectiveFinetune, 0)
        XCTAssertEqual(laterNote.playbackStep, 1, accuracy: 0.000000001)
    }

    func testPlaybackSongSyntheticAdapterE5xWindowedRenderIsDeterministic() {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x50),
                makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x5F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        )
        let renderer = PlaybackSongOfflineRenderer()

        let firstWindowed = renderer.renderWindowed(request, windowRows: 1)
        let secondWindowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(secondWindowed.block.interleavedPCM, firstWindowed.block.interleavedPCM)
        XCTAssertEqual(firstWindowed.diagnostics.setFinetuneEffectCount, 2)
        XCTAssertEqual(secondWindowed.diagnostics.setFinetuneEffectCount, 2)
    }

    func testPlaybackSongSyntheticAdapterArpeggioSchedulesDeterministicCycle() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x00, effectParam: 0x37),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.arpeggioEffects.first)
        let baseStep = try XCTUnwrap(plan.diagnostics.eventMappings.first?.playbackStep)
        let effectCommand = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first { $0.decodedLabel == "0xy arpeggio" })

        XCTAssertEqual(plan.diagnostics.arpeggioEffectCount, 1)
        XCTAssertEqual(effectCommand.status, .applied)
        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.xSemitoneOffset, 3)
        XCTAssertEqual(diagnostic.ySemitoneOffset, 7)
        XCTAssertEqual(diagnostic.stepUpdates.map(\.syntheticTick), [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [6, 7, 8, 9, 10, 11, 12])
        XCTAssertEqual(diagnostic.stepUpdates[0].playbackStepAfter, baseStep, accuracy: 0.000000001)
        XCTAssertGreaterThan(diagnostic.stepUpdates[1].playbackStepAfter, diagnostic.stepUpdates[0].playbackStepAfter)
        XCTAssertGreaterThan(diagnostic.stepUpdates[2].playbackStepAfter, diagnostic.stepUpdates[1].playbackStepAfter)
        XCTAssertEqual(diagnostic.stepUpdates[3].playbackStepAfter, baseStep, accuracy: 0.000000001)
        XCTAssertEqual(diagnostic.stepUpdates[4].playbackStepAfter, diagnostic.stepUpdates[1].playbackStepAfter, accuracy: 0.000000001)
        XCTAssertEqual(diagnostic.stepUpdates[5].playbackStepAfter, diagnostic.stepUpdates[2].playbackStepAfter, accuracy: 0.000000001)
        XCTAssertEqual(diagnostic.stepUpdates[6].playbackStepAfter, baseStep, accuracy: 0.000000001)
        XCTAssertTrue(diagnostic.stepUpdates[6].reachedTarget)
    }

    func testPlaybackSongSyntheticAdapterArpeggioNoOpAndNoActiveVoiceDiagnostics() throws {
        let noOpSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x00, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])]
        )
        let noActiveSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x00, effectParam: 0x37),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])]
        )

        let noOpDiagnostics = PlaybackSongSyntheticAdapter.adapt(noOpSong, orderIndex: 0, sampleRate: 100).diagnostics
        let noActiveDiagnostics = PlaybackSongSyntheticAdapter.adapt(noActiveSong, orderIndex: 0, sampleRate: 100).diagnostics
        let noActive = try XCTUnwrap(noActiveDiagnostics.arpeggioEffects.first)

        XCTAssertEqual(noOpDiagnostics.arpeggioEffects, [])
        XCTAssertFalse(noOpDiagnostics.effectCommandDiagnostics.contains { $0.decodedLabel == "0xy arpeggio" })
        XCTAssertEqual(noOpDiagnostics.deferredCellFields, [])
        XCTAssertEqual(noOpDiagnostics.eventMappings.count, 1)
        XCTAssertEqual(noActiveDiagnostics.arpeggioEffectCount, 1)
        XCTAssertEqual(noActive.status, .noActiveVoice)
        XCTAssertFalse(noActive.applied)
        XCTAssertFalse(noActive.activeVoiceFound)
        XCTAssertEqual(noActive.stepUpdates, [])
        XCTAssertEqual(noActive.xSemitoneOffset, 3)
        XCTAssertEqual(noActive.ySemitoneOffset, 7)
    }

    func testPlaybackSongSyntheticAdapterSameCellArpeggioTriggersOnceAndBridgesRuntimeMetadata() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x00, effectParam: 0x37),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let adaptedPlan = try XCTUnwrap(plan.plan)
        let diagnostic = try XCTUnwrap(adaptedPlan.diagnostics.arpeggioEffects.first)
        let noteTrigger = try XCTUnwrap(plan.events.first { $0.categories.contains("note_trigger") })
        let stepUpdates = plan.events.filter { $0.categories.contains("arpeggio_0xy") && $0.categories.contains("step_update") }

        XCTAssertEqual(adaptedPlan.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(adaptedPlan.pattern.events.count, 1)
        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.activeEventIndex, 0)
        XCTAssertEqual(diagnostic.stepUpdates.map(\.syntheticTick), [1, 2, 3, 4, 5, 6])
        XCTAssertTrue(plan.categories.contains("arpeggio_0xy"))
        XCTAssertTrue(noteTrigger.categories.contains("arpeggio_0xy"))
        XCTAssertEqual(noteTrigger.effectType, 0x00)
        XCTAssertEqual(noteTrigger.effectParam, 0x37)
        XCTAssertEqual(stepUpdates.map(\.syntheticTick), [1, 2, 3, 4, 5, 6])
        XCTAssertTrue(stepUpdates.allSatisfy { $0.effectType == 0x00 && $0.effectParam == 0x37 })
    }

    func testPlaybackSongSyntheticAdapterE1xEAxAndEBxApply() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3], baseSampleRate: 100)
        let row = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x0E, effectParam: 0x11),
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x0E, effectParam: 0xA1),
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x0E, effectParam: 0xB1),
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [row]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let statuses = Dictionary(uniqueKeysWithValues: diagnostics.effectCommandDiagnostics.map { ($0.decodedLabel, $0.status) })

        XCTAssertEqual(diagnostics.setFinetuneEffects, [])
        XCTAssertEqual(diagnostics.portamentoSlideEffects, [])
        XCTAssertEqual(diagnostics.finePortamentoUpEffects.map(\.status), [.applied])
        XCTAssertEqual(diagnostics.finePortamentoDownEffects, [])
        XCTAssertEqual(statuses["E1x fine portamento up"], .applied)
        XCTAssertEqual(statuses["EAx fine volume slide up"], .applied)
        XCTAssertEqual(statuses["EBx fine volume slide down"], .applied)
        XCTAssertTrue(diagnostics.voiceStateUpdates.contains { update in
            update.command == .eaxFineVolumeSlideUp(amount: 1)
        })
        XCTAssertTrue(diagnostics.voiceStateUpdates.contains { update in
            update.command == .ebxFineVolumeSlideDown(amount: 1)
        })
    }

    func testPlaybackSongSyntheticAdapterXxyExtraFinePortamentoDiagnostics() throws {
        let sample = makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)
        let rows = [
            makePlaybackRow(index: 0, effectType: 0x21, effectParam: 0x1F),
            makePlaybackRow(index: 1, note: 49, instrument: 1),
            makePlaybackRow(index: 2, effectType: 0x21, effectParam: 0x11),
            makePlaybackRow(index: 3, effectType: 0x21, effectParam: 0x21),
            makePlaybackRow(index: 4, effectType: 0x21, effectParam: 0x10),
            makePlaybackRow(index: 5, effectType: 0x21, effectParam: 0x20),
            makePlaybackRow(index: 6, effectType: 0x21, effectParam: 0x31),
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let effects = diagnostics.extraFinePortamentoEffects
        let noActive = try XCTUnwrap(effects.first { $0.status == .noActiveVoice })
        let up = try XCTUnwrap(effects.first { $0.status == .applied && $0.direction == .up })
        let down = try XCTUnwrap(effects.first { $0.status == .applied && $0.direction == .down })
        let zeros = effects.filter { $0.status == .zeroAmountEffectMemoryDeferred }
        let unsupported = try XCTUnwrap(effects.first { $0.status == .unsupportedSubcommand })
        let commandStatuses = diagnostics.effectCommandDiagnostics
            .filter { $0.decodedLabel == "Xxy extra fine portamento" }
            .map(\.status)

        XCTAssertEqual(diagnostics.extraFinePortamentoEffectCount, 6)
        XCTAssertEqual(commandStatuses, [.applied, .applied, .applied, .ignoredNoOp, .ignoredNoOp, .deferredUnsupported])
        XCTAssertEqual(noActive.direction, .up)
        XCTAssertEqual(noActive.amount, 15)
        XCTAssertFalse(noActive.activeVoiceFound)
        XCTAssertEqual(up.subcommand, 1)
        XCTAssertEqual(up.amount, 1)
        XCTAssertEqual(up.stepUpdates.map(\.syntheticTick), [0])
        XCTAssertEqual(up.stepUpdates.map(\.scheduledFrame), [8])
        XCTAssertLessThan(try XCTUnwrap(up.currentLinearPeriodAfter), try XCTUnwrap(up.currentLinearPeriodBefore))
        XCTAssertGreaterThan(try XCTUnwrap(up.currentPlaybackStepAfter), try XCTUnwrap(up.currentPlaybackStepBefore))
        XCTAssertEqual(down.subcommand, 2)
        XCTAssertEqual(down.amount, 1)
        XCTAssertGreaterThan(try XCTUnwrap(down.currentLinearPeriodAfter), try XCTUnwrap(down.currentLinearPeriodBefore))
        XCTAssertLessThan(try XCTUnwrap(down.currentPlaybackStepAfter), try XCTUnwrap(down.currentPlaybackStepBefore))
        XCTAssertEqual(zeros.compactMap(\.direction), [.up, .down])
        XCTAssertTrue(zeros.allSatisfy(\.effectMemoryDeferred))
        XCTAssertEqual(unsupported.subcommand, 3)
        XCTAssertTrue(unsupported.deferred)
        XCTAssertEqual(unsupported.stepUpdates, [])
    }

    func testPlaybackSongSyntheticAdapterSameCellXxyFoldsIntoInitialStep() throws {
        let sample = makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)
        let baselineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let xxySong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                PlaybackRow(index: 0, cells: [
                    PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x21, effectParam: 0x1F),
                    PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x21, effectParam: 0x2F),
                ])
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let baseline = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(baselineSong, orderIndex: 0, sampleRate: 100).diagnostics.eventMappings.first)
        let plan = PlaybackSongSyntheticAdapter.adapt(xxySong, orderIndex: 0, sampleRate: 100)
        let mappings = plan.diagnostics.eventMappings
        let up = try XCTUnwrap(plan.diagnostics.extraFinePortamentoEffects.first { $0.direction == .up })
        let down = try XCTUnwrap(plan.diagnostics.extraFinePortamentoEffects.first { $0.direction == .down })

        XCTAssertEqual(mappings.count, 2)
        XCTAssertEqual(plan.diagnostics.extraFinePortamentoEffects.map(\.status), [.applied, .applied])
        XCTAssertTrue(up.appliedToInitialPlaybackStep)
        XCTAssertTrue(down.appliedToInitialPlaybackStep)
        XCTAssertEqual(up.stepUpdates, [])
        XCTAssertEqual(down.stepUpdates, [])
        XCTAssertGreaterThan(mappings[0].playbackStep, baseline.playbackStep)
        XCTAssertLessThan(mappings[1].playbackStep, baseline.playbackStep)
    }

    func testPlaybackSongSyntheticAdapterXxyClampsLinearPeriodBounds() throws {
        let highSample = makeRampPlaybackSample(
            frameCount: 600,
            instrumentIndex: 1,
            relativeNote: 23,
            finetune: 127,
            baseSampleRate: 100
        )
        let lowSample = makeRampPlaybackSample(
            frameCount: 600,
            instrumentIndex: 2,
            relativeNote: -100,
            finetune: -128,
            baseSampleRate: 100
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 96, instrument: 1, effectType: 0x21, effectParam: 0x1F),
                makePlaybackRow(index: 1, note: 1, instrument: 2, effectType: 0x21, effectParam: 0x2F),
            ]],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [highSample]),
                2: PlaybackInstrument(index: 2, samples: [lowSample]),
            ]
        )

        let effects = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.extraFinePortamentoEffects
        let upClamp = try XCTUnwrap(effects.first { $0.direction == .up })
        let downClamp = try XCTUnwrap(effects.first { $0.direction == .down })

        XCTAssertTrue(upClamp.clamped)
        XCTAssertTrue(downClamp.clamped)
        XCTAssertEqual(try XCTUnwrap(upClamp.currentLinearPeriodAfter), PlaybackSongSyntheticAdapter.xmLinearMinimumSafePeriod, accuracy: 0.000000001)
        XCTAssertEqual(try XCTUnwrap(downClamp.currentLinearPeriodAfter), PlaybackSongSyntheticAdapter.xmLinearMaximumSafePeriod, accuracy: 0.000000001)
    }

    func testPlaybackSongSyntheticAdapterXxySplitAndWindowedRenderDeterministic() {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x21, effectParam: 0x1F),
                makePlaybackRow(index: 1, effectType: 0x21, effectParam: 0x21),
                makePlaybackRow(index: 2, note: 49, instrument: 1, effectType: 0x21, effectParam: 0x2F),
                makePlaybackRow(index: 3, effectType: 0x21, effectParam: 0x11),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 16
        )
        let renderer = PlaybackSongOfflineRenderer()
        let single = renderer.render(request)
        let repeated = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [3, 5, 8])
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertEqual(single.diagnostics.extraFinePortamentoEffectCount, 4)
        XCTAssertFloatArrayEqual(repeated.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(split.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, single.block.interleavedPCM)
    }

    func testPlaybackSongSyntheticAdapterSampleAndOutputRatesAffectPlaybackStep() throws {
        let baseSample = makePlaybackSample(pcm: [0, 1, 2, 3], baseSampleRate: 100)
        let higherBaseSample = makePlaybackSample(pcm: [0, 1, 2, 3], baseSampleRate: 200)
        let baseSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [baseSample])]
        )
        let higherBaseSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [higherBaseSample])]
        )

        let base = PlaybackSongSyntheticAdapter.adapt(baseSong, orderIndex: 0, sampleRate: 100)
        let higherBase = PlaybackSongSyntheticAdapter.adapt(higherBaseSong, orderIndex: 0, sampleRate: 100)
        let higherOutputRate = PlaybackSongSyntheticAdapter.adapt(baseSong, orderIndex: 0, sampleRate: 200)
        let baseMapping = try XCTUnwrap(base.diagnostics.eventMappings.first)
        let higherBaseMapping = try XCTUnwrap(higherBase.diagnostics.eventMappings.first)
        let higherOutputRateMapping = try XCTUnwrap(higherOutputRate.diagnostics.eventMappings.first)

        XCTAssertEqual(baseMapping.playbackStep, 1, accuracy: 0.000000001)
        XCTAssertEqual(higherBaseMapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertEqual(try XCTUnwrap(higherBaseMapping.linearFrequency), 200, accuracy: 0.000000001)
        XCTAssertEqual(higherOutputRateMapping.playbackStep, 0.5, accuracy: 0.000000001)
        XCTAssertEqual(higherOutputRateMapping.outputSampleRate, 200)
    }

    func testPlaybackSongSyntheticAdapterReportsLinearAndAmigaFrequencyTableStatus() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3], baseSampleRate: 100)
        let linearSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            usesLinearFrequencyTable: true
        )
        let amigaSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            usesLinearFrequencyTable: false
        )

        let linear = PlaybackSongSyntheticAdapter.adapt(linearSong, orderIndex: 0, sampleRate: 100)
        let amiga = PlaybackSongSyntheticAdapter.adapt(amigaSong, orderIndex: 0, sampleRate: 100)
        let linearMapping = try XCTUnwrap(linear.diagnostics.eventMappings.first)
        let amigaMapping = try XCTUnwrap(amiga.diagnostics.eventMappings.first)

        XCTAssertTrue(linear.diagnostics.usesLinearFrequencyTable)
        XCTAssertEqual(linearMapping.frequencyTableStatus, .linearApplied)
        XCTAssertEqual(try XCTUnwrap(linearMapping.linearFrequency), 200, accuracy: 0.000000001)
        XCTAssertFalse(amiga.diagnostics.usesLinearFrequencyTable)
        XCTAssertEqual(amigaMapping.frequencyTableStatus, .amigaApplied)
        XCTAssertEqual(try XCTUnwrap(amigaMapping.amigaPeriod), 3_424, accuracy: 0.000000001)
        XCTAssertEqual(try XCTUnwrap(amigaMapping.amigaFrequency), 200, accuracy: 0.000000001)
        XCTAssertEqual(amigaMapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertTrue(amigaMapping.pitchMappingApplied)
        XCTAssertFalse(amigaMapping.pitchMappingUsedNeutralStep)
        XCTAssertFalse(amigaMapping.linearFrequencyApplied)
        XCTAssertTrue(amigaMapping.amigaFrequencyApplied)
        XCTAssertFalse(amigaMapping.amigaFrequencyDeferred)
    }

    func testPlaybackSongSyntheticAdapterAmigaPitchHelperExpectedValues() throws {
        let c4 = try XCTUnwrap(PlaybackSongSyntheticAdapter.amigaPitchTarget(
            note: 49,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            outputSampleRate: 48_000
        ))
        let c5 = try XCTUnwrap(PlaybackSongSyntheticAdapter.amigaPitchTarget(
            note: 61,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            outputSampleRate: 48_000
        ))
        let relativeC5 = try XCTUnwrap(PlaybackSongSyntheticAdapter.amigaPitchTarget(
            note: 49,
            relativeNote: 12,
            finetune: 0,
            baseSampleRate: 8_363,
            outputSampleRate: 48_000
        ))
        let finetunedUp = try XCTUnwrap(PlaybackSongSyntheticAdapter.amigaPitchTarget(
            note: 49,
            relativeNote: 0,
            finetune: 64,
            baseSampleRate: 8_363,
            outputSampleRate: 48_000
        ))
        let finetunedDown = try XCTUnwrap(PlaybackSongSyntheticAdapter.amigaPitchTarget(
            note: 49,
            relativeNote: 0,
            finetune: -128,
            baseSampleRate: 8_363,
            outputSampleRate: 48_000
        ))

        XCTAssertEqual(c4.amigaPeriod, 6_848, accuracy: 0.000000001)
        XCTAssertEqual(c4.amigaFrequency, 8_363, accuracy: 0.000000001)
        XCTAssertEqual(c4.playbackStep, 8_363.0 / 48_000.0, accuracy: 0.000000001)
        XCTAssertEqual(c5.amigaPeriod, 3_424, accuracy: 0.000000001)
        XCTAssertEqual(c5.amigaFrequency, 16_726, accuracy: 0.000000001)
        XCTAssertEqual(relativeC5.amigaPeriod, c5.amigaPeriod, accuracy: 0.000000001)
        XCTAssertEqual(finetunedUp.amigaPeriod, 6_653, accuracy: 0.000000001)
        XCTAssertGreaterThan(finetunedUp.amigaFrequency, c4.amigaFrequency)
        XCTAssertEqual(finetunedDown.amigaPeriod, 7_255, accuracy: 0.000000001)
        XCTAssertLessThan(finetunedDown.amigaFrequency, c4.amigaFrequency)
    }

    func testPlaybackSongSyntheticAdapterAmigaE5xSetFinetuneRemainsDeferred() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x5F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 300, baseSampleRate: 8_363)])],
            usesLinearFrequencyTable: false
        )

        let result = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 48_000)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)
        let diagnostic = try XCTUnwrap(result.diagnostics.setFinetuneEffects.first)

        XCTAssertEqual(mapping.frequencyTableStatus, .amigaApplied)
        XCTAssertEqual(mapping.effectiveFinetune, 0)
        XCTAssertEqual(diagnostic.status, .unsupportedFrequencyTable)
        XCTAssertFalse(diagnostic.applied)
    }

    func testPlaybackSongSyntheticAdapterInvalidSampleRateFallsBackToNeutralStep() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2], baseSampleRate: 0)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.playbackStep, 1)
        XCTAssertFalse(mapping.pitchMappingApplied)
        XCTAssertTrue(mapping.pitchMappingUsedNeutralStep)
        XCTAssertEqual(mapping.finetuneStatus, .deferred)
        XCTAssertEqual(result.block.interleavedPCM, [0, 1, 2, 0])
    }

    func testPlaybackSongSyntheticAdapterInvalidOutputRateUsesSafeDefaultRate() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: -1)
        let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)

        XCTAssertEqual(plan.timingConfig.sampleRate, MixerRenderConfig.defaultSampleRate)
        XCTAssertEqual(mapping.outputSampleRate, MixerRenderConfig.defaultSampleRate)
        XCTAssertTrue(mapping.pitchMappingApplied)
        XCTAssertGreaterThan(mapping.playbackStep, 0)
    }

    func testPlaybackSongSyntheticAdapterPitchDiagnosticsIncludeLinearPeriodAndFrequencyFields() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2], relativeNote: 12, finetune: 64, baseSampleRate: 8_363)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 44_100)
        let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.outputSampleRate, 44_100)
        XCTAssertEqual(mapping.effectiveNoteValue, 61)
        XCTAssertEqual(mapping.effectiveNoteIndex, 60)
        XCTAssertEqual(mapping.effectiveFinetune, 64)
        XCTAssertEqual(try XCTUnwrap(mapping.linearPeriod), 3_808, accuracy: 0.000000001)
        XCTAssertEqual(mapping.linearFrequency ?? 0, 8_363 * pow(2.0, 800.0 / 768.0), accuracy: 0.0001)
        XCTAssertTrue(mapping.linearFrequencyApplied)
        XCTAssertFalse(mapping.amigaFrequencyDeferred)
        XCTAssertFalse(mapping.pitchMappingUsedNeutralStep)
    }

    func testPlaybackSongSyntheticAdapterCSoftwareMixerSplitAndResetAreDeterministic() {
        let sample = makePlaybackSample(pcm: [1, 0.5, -0.5])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )
        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let scheduler = SyntheticPatternScheduler(config: plan.timingConfig)
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: plan.timingConfig.sampleRate, channelCount: 1))
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: plan.timingConfig.sampleRate, channelCount: 1))
        let resetMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: plan.timingConfig.sampleRate, channelCount: 1))
        _ = scheduler.schedule(plan.pattern, on: singleRenderMixer)
        _ = scheduler.schedule(plan.pattern, on: splitRenderMixer)
        _ = scheduler.schedule(plan.pattern, on: resetMixer)

        let singleRender = singleRenderMixer.render(frames: 6)
        let splitRender = splitRenderMixer.render(frames: 1).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM
        let firstResetRender = resetMixer.render(frames: 6)
        _ = resetMixer.render(frames: 3)
        resetMixer.reset()
        let secondResetRender = resetMixer.render(frames: 6)

        XCTAssertEqual(singleRender.interleavedPCM, [0, 0, 1, 0.5, -0.5, 0])
        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        XCTAssertEqual(firstResetRender, secondResetRender)
    }

    func testPlaybackSongSyntheticAdapterPitchMappedSplitResetAndRepeatedRendersAreDeterministic() {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3, 4, 5, 6, 7], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        )
        let renderer = PlaybackSongOfflineRenderer()

        let first = renderer.render(request)
        let repeated = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [1, 2, 2])
        let session = renderer.prepare(request)
        let resetFirst = session.render(frames: 5)
        _ = session.render(frames: 2)
        session.reset()
        let resetSecond = session.render(frames: 5)

        XCTAssertEqual(first.block.interleavedPCM, [0, 2, 4, 6, 0])
        XCTAssertEqual(first.block, repeated.block)
        XCTAssertEqual(split.block, first.block)
        XCTAssertEqual(resetFirst, resetSecond)
        XCTAssertEqual(resetFirst, first.block)
    }

    func testPlaybackSongAdapterNo9xxPreservesBaselineRenderAndDiagnostics() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertPCMEqual(result.block.interleavedPCM, [0, 0.001, 0.002, 0.003])
        XCTAssertEqual(event.initialSourceFrame, 0)
        XCTAssertEqual(mapping.effectType, 0)
        XCTAssertEqual(mapping.effectParam, 0)
        XCTAssertEqual(mapping.sampleOffset.status, .notPresent)
        XCTAssertFalse(mapping.sampleOffset.detected)
        XCTAssertEqual(result.diagnostics.sampleOffsetEffects, [])
    }

    func testPlaybackSongAdapterSampleOffset9xxStartsAtExpectedFrame() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)
        let offset = try XCTUnwrap(result.diagnostics.sampleOffsetEffects.first)

        XCTAssertPCMEqual(result.block.interleavedPCM, [0.256, 0.257, 0.258, 0.259])
        XCTAssertEqual(event.initialSourceFrame, 256)
        XCTAssertEqual(mapping.effectType, 0x09)
        XCTAssertEqual(mapping.effectParam, 0x01)
        XCTAssertEqual(mapping.sampleOffset.status, .applied)
        XCTAssertEqual(mapping.sampleOffset.computedOffsetFrames, 256)
        XCTAssertEqual(mapping.sampleOffset.appliedOffsetFrames, 256)
        XCTAssertEqual(mapping.sampleOffset.selectedSampleLength, 300)
        XCTAssertFalse(mapping.hasIgnoredEffect)
        XCTAssertEqual(offset, mapping.sampleOffset)
    }

    func testPlaybackSongAdapterSampleOffset900ReusesPrior9xxMemory() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01),
                makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let mappings = plan.diagnostics.eventMappings
        let offsetEffects = plan.diagnostics.sampleOffsetEffects
        let memoryOffset = try XCTUnwrap(offsetEffects.last)

        XCTAssertEqual(plan.pattern.events.map(\.initialSourceFrame), [256, 256])
        XCTAssertEqual(mappings.map(\.sampleOffset.appliedOffsetFrames), [256, 256])
        XCTAssertFalse(try XCTUnwrap(offsetEffects.first).effectMemoryReused)
        XCTAssertTrue(memoryOffset.effectMemoryReused)
        XCTAssertFalse(memoryOffset.effectMemoryMissing)
        XCTAssertEqual(memoryOffset.memorySource?.source.rowIndex, 0)
        XCTAssertEqual(memoryOffset.memorySource?.channelIndex, 0)
        XCTAssertEqual(memoryOffset.memorySource?.effectType, 0x09)
        XCTAssertEqual(memoryOffset.memorySource?.effectParam, 0x01)
        XCTAssertFalse(try XCTUnwrap(mappings.last).hasIgnoredEffect)
    }

    func testPlaybackSongAdapterSampleOffset9xxMemoryIsPerChannel() throws {
        let sample = makeRampPlaybackSample(frameCount: 700)
        let row0 = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x09, effectParam: 0x01),
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x09, effectParam: 0x02),
        ])
        let row1 = PlaybackRow(index: 1, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x09, effectParam: 0x00),
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0x09, effectParam: 0x00),
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [row0, row1]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let mappings = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.eventMappings
        let row1Offsets = mappings
            .filter { $0.source.rowIndex == 1 }
            .sorted { $0.channelIndex < $1.channelIndex }
            .map(\.sampleOffset)

        XCTAssertEqual(row1Offsets.map(\.appliedOffsetFrames), [256, 512])
        XCTAssertTrue(row1Offsets.allSatisfy(\.effectMemoryReused))
        XCTAssertEqual(row1Offsets.map { $0.memorySource?.channelIndex }, [0, 1])
        XCTAssertEqual(row1Offsets.map { $0.memorySource?.effectParam }, [0x01, 0x02])
    }

    func testPlaybackSongAdapterSampleOffset900MemoryCarriesAcrossWindowedRenderBoundaries() throws {
        let sample = makeRampPlaybackSample(frameCount: 260)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01),
                makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 30
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)
        let memoryOffset = try XCTUnwrap(windowed.diagnostics.sampleOffsetEffects.last)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertEqual(windowed.diagnostics.eventMappings.map(\.sampleOffset.appliedOffsetFrames), [256, 256])
        XCTAssertTrue(memoryOffset.effectMemoryReused)
        XCTAssertEqual(memoryOffset.memorySource?.source.rowIndex, 0)
    }

    func testPlaybackSongAdapterSampleOffset900DirectStartWithoutPriorMemoryIsDeferredNoOp() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let song = makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)],
                3: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x00)],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 1, orderCount: 1, sampleRate: 100)
        let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)
        let diagnostic = try XCTUnwrap(plan.diagnostics.sampleOffsetEffects.first)

        XCTAssertEqual(plan.pattern.events.first?.initialSourceFrame, 0)
        XCTAssertEqual(mapping.sampleOffset.status, .ignored900NoOp)
        XCTAssertTrue(mapping.hasIgnoredEffect)
        XCTAssertTrue(diagnostic.effectMemoryMissing)
        XCTAssertTrue(diagnostic.effectMemoryDeferred)
        XCTAssertEqual(diagnostic.memoryUnavailableReason, "missing_9xx_sample_offset_memory")
    }

    func testPlaybackSongAdapterSampleOffset9xxUsesMappedSample() throws {
        let fallbackSample = makePlaybackSample(sampleIndex: 0, pcm: Array(repeating: Float(9), count: 300), baseSampleRate: 100)
        let mappedSample = makeRampPlaybackSample(frameCount: 300, sampleIndex: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [fallbackSample, mappedSample],
                    noteSampleMap: makeNoteSampleMap(overrides: [49: 1])
                )
            ]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.sampleIndex, 1)
        XCTAssertEqual(mapping.sampleSelectionMethod, .sampleMap)
        XCTAssertEqual(mapping.sampleOffset.status, .applied)
        XCTAssertEqual(mapping.sampleOffset.appliedOffsetFrames, 256)
        XCTAssertPCMEqual(result.block.interleavedPCM, [0.256, 0.257, 0.258, 0.259])
    }

    func testPlaybackSongAdapterFxxTimingAndVolumeColumnWorkWithMappedSample() throws {
        let fallbackSample = makePlaybackSample(sampleIndex: 0, pcm: [9], baseSampleRate: 100)
        let mappedSample = makePlaybackSample(sampleIndex: 1, pcm: [1], volume: 0.5, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0x20)
                ]
            ],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [fallbackSample, mappedSample],
                    noteSampleMap: makeNoteSampleMap(overrides: [49: 1])
                )
            ],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(event.scheduledStartFrame, 6)
        XCTAssertEqual(event.gain, 0.125)
        XCTAssertEqual(mapping.sampleIndex, 1)
        XCTAssertEqual(mapping.sampleSelectionMethod, .sampleMap)
        XCTAssertEqual(mapping.volumeColumn.command, .setVolume(value: 16))
        XCTAssertEqual(mapping.effectiveVolumeValue, 16)
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6])
        XCTAssertEqual(result.diagnostics.timingChanges.first?.kind, .speed)
        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 6) + [0.125, 0])
    }

    func testPlaybackSongAdapterSampleOffset9xxCombinesWithPitchStep() throws {
        let sample = makeRampPlaybackSample(frameCount: 300, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertEqual(mapping.sampleOffset.status, .applied)
        XCTAssertPCMEqual(result.block.interleavedPCM, [0.256, 0.258, 0.260])
    }

    func testPlaybackSongAdapterSampleOffset9xxCombinesWithLinearInterpolation() throws {
        let sample = makeRampPlaybackSample(frameCount: 300, baseSampleRate: 150)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.playbackStep, 1.5, accuracy: 0.000000001)
        XCTAssertEqual(mapping.sampleOffset.status, .applied)
        XCTAssertPCMEqual(result.block.interleavedPCM, [0.256, 0.2575, 0.259, 0.2605])
    }

    func testPlaybackSongAdapterSampleOffset9xxWorksWithForwardLoopOffsets() throws {
        let offsetBeforeLoop = makeRampPlaybackSample(frameCount: 260, loopStart: 258, loopLength: 2, loopType: 1)
        let offsetInsideLoop = makeRampPlaybackSample(frameCount: 260, loopStart: 256, loopLength: 3, loopType: 1)
        let offsetBeyondLoop = makeRampPlaybackSample(frameCount: 300, loopStart: 1, loopLength: 2, loopType: 1)
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let before = renderer.render(PlaybackSongOfflineRenderRequest(
            song: makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [offsetBeforeLoop])]
            ),
            orderIndex: 0,
            config: config,
            frames: 5
        ))
        let inside = renderer.render(PlaybackSongOfflineRenderRequest(
            song: makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [offsetInsideLoop])]
            ),
            orderIndex: 0,
            config: config,
            frames: 5
        ))
        let beyond = renderer.render(PlaybackSongOfflineRenderRequest(
            song: makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [offsetBeyondLoop])]
            ),
            orderIndex: 0,
            config: config,
            frames: 4
        ))

        XCTAssertPCMEqual(before.block.interleavedPCM, [0.256, 0.257, 0.258, 0.259, 0.258])
        XCTAssertEqual(try XCTUnwrap(before.diagnostics.eventMappings.first).loopMode, .forward)
        XCTAssertPCMEqual(inside.block.interleavedPCM, [0.256, 0.257, 0.258, 0.256, 0.257])
        XCTAssertEqual(try XCTUnwrap(inside.diagnostics.eventMappings.first).loopMode, .forward)
        XCTAssertPCMEqual(beyond.block.interleavedPCM, [0.256, 0.001, 0.002, 0.001])
        XCTAssertEqual(try XCTUnwrap(beyond.diagnostics.eventMappings.first).loopMode, .forward)
    }

    func testPlaybackSongAdapterSampleOffset9xxWorksWithPingPongLoopOffset() throws {
        let sample = makeRampPlaybackSample(frameCount: 260, loopStart: 256, loopLength: 3, loopType: 2)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.loopMode, .pingPong)
        XCTAssertEqual(mapping.sampleOffset.status, .applied)
        XCTAssertPCMEqual(result.block.interleavedPCM, [0.256, 0.257, 0.258, 0.257, 0.256, 0.257])
    }

    func testPlaybackSongAdapterSampleOffset9xxBeyondSampleLengthSkipsVoiceSafely() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x02)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let diagnostic = try XCTUnwrap(result.diagnostics.sampleOffsetEffects.first)

        XCTAssertEqual(result.plan.pattern.events, [])
        XCTAssertEqual(result.diagnostics.emittedEventCount, 0)
        XCTAssertEqual(result.diagnostics.ignoredCells.map(\.reason), [.sampleOffsetOutOfRange])
        XCTAssertEqual(result.block.interleavedPCM, [0, 0, 0, 0])
        XCTAssertEqual(diagnostic.status, .outOfRangeSkipped)
        XCTAssertTrue(diagnostic.detected)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertTrue(diagnostic.skipped)
        XCTAssertTrue(diagnostic.outOfRange)
        XCTAssertEqual(diagnostic.computedOffsetFrames, 512)
        XCTAssertNil(diagnostic.appliedOffsetFrames)
        XCTAssertEqual(diagnostic.selectedSampleLength, 300)
    }

    func testPlaybackSongAdapterSampleOffset900IsDiagnosedAsIgnoredDeferredNoOp() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x00)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)
        let diagnostic = try XCTUnwrap(result.diagnostics.sampleOffsetEffects.first)

        XCTAssertPCMEqual(result.block.interleavedPCM, [0, 0.001, 0.002])
        XCTAssertEqual(result.plan.pattern.events.first?.initialSourceFrame, 0)
        XCTAssertEqual(mapping.sampleOffset.status, .ignored900NoOp)
        XCTAssertEqual(diagnostic.status, .ignored900NoOp)
        XCTAssertTrue(diagnostic.detected)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertTrue(diagnostic.deferred)
        XCTAssertTrue(diagnostic.ignoredAsNoOp)
        XCTAssertFalse(diagnostic.effectMemoryReused)
        XCTAssertTrue(diagnostic.effectMemoryMissing)
        XCTAssertTrue(diagnostic.effectMemoryDeferred)
        XCTAssertNil(diagnostic.memorySource)
        XCTAssertEqual(diagnostic.memoryUnavailableReason, "missing_9xx_sample_offset_memory")
        XCTAssertEqual(diagnostic.computedOffsetFrames, 0)
        XCTAssertEqual(diagnostic.appliedOffsetFrames, 0)
        XCTAssertTrue(mapping.hasIgnoredEffect)
        XCTAssertEqual(result.diagnostics.deferredCellFields.map(\.field), [.effect])
    }

    func testPlaybackSongAdapterTonePortamento3xxWithNoteSetsTargetWithoutRetriggering() throws {
        let sample = makeRampPlaybackSample(frameCount: 300, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        ))
        let diagnostic = try XCTUnwrap(result.diagnostics.tonePortamentoEffects.first)
        let command = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first { $0.effectType == 0x03 })

        XCTAssertEqual(result.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(result.plan.pattern.events.count, 1)
        XCTAssertTrue(diagnostic.applied)
        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.activeEventIndex, 0)
        XCTAssertEqual(diagnostic.targetNote, 61)
        XCTAssertEqual(try XCTUnwrap(diagnostic.targetPlaybackStep), 2, accuracy: 0.000_001)
        XCTAssertEqual(command.status, .applied)
        XCTAssertEqual(result.diagnostics.deferredCellFields.map(\.effectType), [])
    }

    func testPlaybackSongAdapterTonePortamento3xxSlidesStepTowardTargetAndSpeedAffectsAmount() throws {
        let slow = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 300, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let fast = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x80),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 300, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let slowDiagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(slow, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects.first)
        let fastDiagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(fast, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects.first)
        let slowFirst = try XCTUnwrap(slowDiagnostic.stepUpdates.first)
        let fastFirst = try XCTUnwrap(fastDiagnostic.stepUpdates.first)

        XCTAssertEqual(slowDiagnostic.stepUpdates.map(\.scheduledFrame), [5, 6, 7])
        XCTAssertEqual(slowFirst.playbackStepBefore, 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(slowFirst.playbackStepAfter, slowFirst.playbackStepBefore)
        XCTAssertGreaterThan(fastFirst.playbackStepAfter, slowFirst.playbackStepAfter)
        XCTAssertEqual(slowDiagnostic.portamentoSpeed, 0x40)
        XCTAssertEqual(fastDiagnostic.portamentoSpeed, 0x80)
    }

    func testPlaybackSongAdapterAmigaTonePortamento3xxSlidesTowardTargetPeriod() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250),
            usesLinearFrequencyTable: false
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.tonePortamentoEffects.first)
        let firstUpdate = try XCTUnwrap(diagnostic.stepUpdates.first)

        XCTAssertEqual(plan.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(plan.pattern.events.count, 1)
        XCTAssertTrue(diagnostic.applied)
        XCTAssertEqual(diagnostic.frequencyTableStatus, .amigaApplied)
        XCTAssertTrue(diagnostic.sameCellNote)
        XCTAssertFalse(diagnostic.noteTriggerEventCreated)
        XCTAssertTrue(diagnostic.cMixerReceivesOnlyStateUpdates)
        XCTAssertEqual(diagnostic.targetNote, 61)
        XCTAssertEqual(try XCTUnwrap(diagnostic.targetAmigaPeriod), 3_424, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(diagnostic.currentAmigaPeriodBefore), 6_848, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(firstUpdate.amigaPeriodBefore), 6_848, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(firstUpdate.amigaPeriodAfter), 6_848 - (0x10 * 16), accuracy: 0.000_001)
        XCTAssertGreaterThan(firstUpdate.playbackStepAfter, firstUpdate.playbackStepBefore)
    }

    func testPlaybackSongAdapterAmigaTonePortamento3xxDiagnosticsCoverNoActiveNoTargetAndNoSpeed() throws {
        let sample = makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)
        let noActive = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x10)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250),
            usesLinearFrequencyTable: false
        )
        let noTarget = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x03, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250),
            usesLinearFrequencyTable: false
        )
        let noSpeed = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250),
            usesLinearFrequencyTable: false
        )

        let noActiveDiagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(noActive, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects.first)
        let noTargetDiagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(noTarget, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects.first)
        let noSpeedDiagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(noSpeed, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects.first)

        XCTAssertEqual(noActiveDiagnostic.status, .noActiveVoice)
        XCTAssertEqual(noTargetDiagnostic.status, .noTarget)
        XCTAssertEqual(noSpeedDiagnostic.status, .noSpeed)
        XCTAssertEqual(noActiveDiagnostic.frequencyTableStatus, .amigaApplied)
        XCTAssertEqual(noTargetDiagnostic.frequencyTableStatus, .amigaApplied)
        XCTAssertEqual(noSpeedDiagnostic.frequencyTableStatus, .amigaApplied)
        XCTAssertFalse(noActiveDiagnostic.applied)
        XCTAssertFalse(noTargetDiagnostic.applied)
        XCTAssertFalse(noSpeedDiagnostic.applied)
        XCTAssertEqual(noSpeedDiagnostic.targetAmigaPeriod, 3_424)
    }

    func testPlaybackSongAdapterTonePortamento3xxClampsAtTargetWithoutOvershooting() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 50, instrument: 1, effectType: 0x03, effectParam: 0xFF),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 300, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects.first)
        let update = try XCTUnwrap(diagnostic.stepUpdates.first)

        XCTAssertTrue(update.reachedTarget)
        XCTAssertEqual(diagnostic.stepUpdates.count, 1)
        XCTAssertEqual(update.linearPeriodAfter, try XCTUnwrap(diagnostic.targetLinearPeriod), accuracy: 0.000_001)
        XCTAssertEqual(update.playbackStepAfter, try XCTUnwrap(diagnostic.targetPlaybackStep), accuracy: 0.000_001)
    }

    func testPlaybackSongAdapterTonePortamento3xxWithoutNoteContinuesExistingTarget() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, effectType: 0x03, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 300, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects

        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertTrue(diagnostics.allSatisfy(\.applied))
        XCTAssertEqual(diagnostics[1].targetNote, 61)
        XCTAssertEqual(diagnostics[1].portamentoSpeed, 0x40)
        XCTAssertGreaterThan(diagnostics[1].currentPlaybackStepAfter ?? 0, diagnostics[0].currentPlaybackStepAfter ?? 0)
    }

    func testPlaybackSongAdapterTonePortamento3xxWithoutTargetIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x03, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 300)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects.first)

        XCTAssertEqual(diagnostic.status, .noTarget)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertTrue(diagnostic.activeVoiceFound)
    }

    func testPlaybackSongAdapterTonePortamento3xxWithNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 300)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.tonePortamentoEffects.first)

        XCTAssertEqual(plan.pattern.events.count, 0)
        XCTAssertEqual(diagnostic.status, .noActiveVoice)
        XCTAssertFalse(diagnostic.activeVoiceFound)
    }

    func testPlaybackSongAdapterTonePortamento3xxUsesLinearFrequencyAndSampleMetadata() throws {
        let sample = makeRampPlaybackSample(frameCount: 300, relativeNote: 1, finetune: 2, baseSampleRate: 200)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 50, instrument: 1, effectType: 0x03, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects.first)
        let expectedPeriod = 7_680.0 - (Double((50 + 1) - 1) * 64.0) - 1.0
        let expectedStep = 200.0 * pow(2.0, (4_608.0 - expectedPeriod) / 768.0) / 100.0

        XCTAssertEqual(try XCTUnwrap(diagnostic.targetLinearPeriod), expectedPeriod, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(diagnostic.targetPlaybackStep), expectedStep, accuracy: 0.000_001)
    }

    func testPlaybackSongAdapterTonePortamento3xxUsesFxxTiming() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                makePlaybackRow(index: 1, note: 49, instrument: 1),
                makePlaybackRow(index: 2, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 300, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.tonePortamentoEffects.first)

        XCTAssertEqual(diagnostic.rowSpeed, 3)
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [10, 11])
    }

    func testPlaybackSongAdapterTonePortamento3xxWindowedCarryoverMatchesDefaultRender() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, effectType: 0x03, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 12
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 0)
    }

    func testPlaybackSongAdapterPortamento1xxSlidesActiveVoicePitchUpOverTicks() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.portamentoSlideEffects.first)
        let command = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first { $0.effectType == 0x01 })

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertTrue(diagnostic.applied)
        XCTAssertEqual(diagnostic.direction, .up)
        XCTAssertEqual(diagnostic.slideAmount, 0x40)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.activeEventIndex, 0)
        XCTAssertEqual(diagnostic.rowSpeed, 4)
        XCTAssertEqual(diagnostic.rowBPM, 250)
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [5, 6, 7])
        XCTAssertLessThan(try XCTUnwrap(diagnostic.currentLinearPeriodAfter), try XCTUnwrap(diagnostic.currentLinearPeriodBefore))
        XCTAssertGreaterThan(try XCTUnwrap(diagnostic.currentPlaybackStepAfter), try XCTUnwrap(diagnostic.currentPlaybackStepBefore))
        XCTAssertEqual(command.status, .applied)
    }

    func testPlaybackSongAdapterPortamento2xxSlidesActiveVoicePitchDownOverTicks() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x02, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(
            PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
                .diagnostics.portamentoSlideEffects.first
        )

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.direction, .down)
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [5, 6, 7])
        XCTAssertGreaterThan(try XCTUnwrap(diagnostic.currentLinearPeriodAfter), try XCTUnwrap(diagnostic.currentLinearPeriodBefore))
        XCTAssertLessThan(try XCTUnwrap(diagnostic.currentPlaybackStepAfter), try XCTUnwrap(diagnostic.currentPlaybackStepBefore))
    }

    func testPlaybackSongAdapterAmigaPortamento2xxSlidesPeriodDownOverTicks() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x02, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250),
            usesLinearFrequencyTable: false
        )

        let diagnostic = try XCTUnwrap(
            PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
                .diagnostics.portamentoSlideEffects.first
        )
        let firstUpdate = try XCTUnwrap(diagnostic.stepUpdates.first)

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.direction, .down)
        XCTAssertEqual(diagnostic.frequencyTableStatus, .amigaApplied)
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [5, 6, 7])
        XCTAssertEqual(try XCTUnwrap(diagnostic.currentAmigaPeriodBefore), 6_848, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(diagnostic.currentAmigaPeriodAfter), 6_848 + (3 * 0x10 * 16), accuracy: 0.000_001)
        XCTAssertGreaterThan(try XCTUnwrap(firstUpdate.amigaPeriodAfter), try XCTUnwrap(firstUpdate.amigaPeriodBefore))
        XCTAssertLessThan(try XCTUnwrap(diagnostic.currentPlaybackStepAfter), try XCTUnwrap(diagnostic.currentPlaybackStepBefore))
    }

    func testPlaybackSongAdapterAmigaPortamento2xxClampsAtSafePeriodBound() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 1, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x02, effectParam: 0xFF),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 100, bpm: 250),
            usesLinearFrequencyTable: false
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.portamentoSlideEffects.first)

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertTrue(diagnostic.clamped)
        XCTAssertEqual(try XCTUnwrap(diagnostic.currentAmigaPeriodAfter), PlaybackSongSyntheticAdapter.xmAmigaMaximumSafePeriod, accuracy: 0.000_001)
        XCTAssertTrue(try XCTUnwrap(diagnostic.stepUpdates.last).clamped)
    }

    func testPlaybackSongAdapterPortamentoSlideParameterChangesAmount() throws {
        let slow = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let fast = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let slowUpdate = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(slow, orderIndex: 0, sampleRate: 100).diagnostics.portamentoSlideEffects.first?.stepUpdates.first)
        let fastUpdate = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(fast, orderIndex: 0, sampleRate: 100).diagnostics.portamentoSlideEffects.first?.stepUpdates.first)

        XCTAssertEqual(slowUpdate.linearPeriodBefore - slowUpdate.linearPeriodAfter, 0x10, accuracy: 0.000_001)
        XCTAssertEqual(fastUpdate.linearPeriodBefore - fastUpdate.linearPeriodAfter, 0x40, accuracy: 0.000_001)
        XCTAssertGreaterThan(fastUpdate.playbackStepAfter, slowUpdate.playbackStepAfter)
    }

    func testPlaybackSongAdapterPortamentoSlideZeroParamIsEffectMemoryDeferred() throws {
        func assertMissing(
            effectType: UInt8,
            direction: PlaybackSongSyntheticPortamentoSlideDirection,
            reason: String
        ) throws {
            let song = makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: effectType, effectParam: 0x00),
                ]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
                initialTiming: PlaybackTiming(speed: 4, bpm: 250)
            )
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            let diagnostic = try XCTUnwrap(plan.diagnostics.portamentoSlideEffects.first)
            let command = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first { $0.effectType == effectType })

            XCTAssertEqual(diagnostic.status, .zeroParamEffectMemoryDeferred)
            XCTAssertFalse(diagnostic.applied)
            XCTAssertTrue(diagnostic.deferred)
            XCTAssertTrue(diagnostic.ignoredAsNoOp)
            XCTAssertEqual(diagnostic.direction, direction)
            XCTAssertTrue(diagnostic.effectMemoryMissing)
            XCTAssertTrue(diagnostic.effectMemoryDeferred)
            XCTAssertEqual(diagnostic.memoryUnavailableReason, reason)
            XCTAssertTrue(diagnostic.activeVoiceFound)
            XCTAssertEqual(diagnostic.slideAmount, 0)
            XCTAssertEqual(diagnostic.stepUpdates, [])
            XCTAssertEqual(command.status, .ignoredNoOp)
        }

        try assertMissing(effectType: 0x01, direction: .up, reason: "missing_1xx_portamento_memory")
        try assertMissing(effectType: 0x02, direction: .down, reason: "missing_2xx_portamento_memory")
    }

    func testPlaybackSongAdapterPortamentoMemoryReusesPriorSameChannelAmount() throws {
        let cases: [(effectType: UInt8, amount: UInt8, direction: PlaybackSongSyntheticPortamentoSlideDirection)] = [
            (0x01, 0x20, .up),
            (0x02, 0x18, .down),
        ]

        for item in cases {
            let song = makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: item.effectType, effectParam: item.amount),
                    makePlaybackRow(index: 2, effectType: item.effectType, effectParam: 0x00),
                ]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
                initialTiming: PlaybackTiming(speed: 4, bpm: 250)
            )
            let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
                .diagnostics.portamentoSlideEffects
            let stored = try XCTUnwrap(diagnostics.first)
            let replayed = try XCTUnwrap(diagnostics.last)

            XCTAssertEqual(stored.direction, item.direction)
            XCTAssertFalse(stored.effectMemoryReused)
            XCTAssertEqual(stored.slideAmount, Int(item.amount))
            XCTAssertEqual(replayed.status, .applied)
            XCTAssertEqual(replayed.direction, item.direction)
            XCTAssertTrue(replayed.effectMemoryReused)
            XCTAssertFalse(replayed.effectMemoryMissing)
            XCTAssertEqual(replayed.effectParam, 0)
            XCTAssertEqual(replayed.slideAmount, Int(item.amount))
            XCTAssertEqual(replayed.memorySource?.source.rowIndex, 1)
            XCTAssertEqual(replayed.memorySource?.channelIndex, 0)
            XCTAssertEqual(replayed.memorySource?.effectType, item.effectType)
            XCTAssertEqual(replayed.memorySource?.effectParam, item.amount)
            XCTAssertEqual(replayed.stepUpdates.map(\.scheduledFrame), [9, 10, 11])
        }
    }

    func testPlaybackSongAdapterPortamentoMemoryIsPerChannel() throws {
        func assertPerChannel(effectType: UInt8, amount: UInt8, reason: String) {
            let sample = makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)
            let rows = [
                PlaybackRow(index: 0, cells: [
                    PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                    PlaybackCell(note: 52, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                ]),
                PlaybackRow(index: 1, cells: [
                    PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: effectType, effectParam: amount),
                    PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
                ]),
                PlaybackRow(index: 2, cells: [
                    PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: effectType, effectParam: 0x00),
                    PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: effectType, effectParam: 0x00),
                ]),
            ]
            let song = makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: rows],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
                initialTiming: PlaybackTiming(speed: 4, bpm: 250)
            )
            let row2Diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
                .diagnostics.portamentoSlideEffects
                .filter { $0.source.rowIndex == 2 }
                .sorted { $0.channelIndex < $1.channelIndex }

            XCTAssertEqual(row2Diagnostics.map(\.channelIndex), [0, 1])
            XCTAssertEqual(row2Diagnostics[0].status, .applied)
            XCTAssertTrue(row2Diagnostics[0].effectMemoryReused)
            XCTAssertEqual(row2Diagnostics[0].memorySource?.channelIndex, 0)
            XCTAssertEqual(row2Diagnostics[0].slideAmount, Int(amount))
            XCTAssertEqual(row2Diagnostics[1].status, .zeroParamEffectMemoryDeferred)
            XCTAssertTrue(row2Diagnostics[1].effectMemoryMissing)
            XCTAssertEqual(row2Diagnostics[1].memoryUnavailableReason, reason)
        }

        assertPerChannel(effectType: 0x01, amount: 0x20, reason: "missing_1xx_portamento_memory")
        assertPerChannel(effectType: 0x02, amount: 0x24, reason: "missing_2xx_portamento_memory")
    }

    func testPlaybackSongAdapterPortamento1xxAnd2xxMemoryRemainDistinct() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x10),
                makePlaybackRow(index: 2, effectType: 0x02, effectParam: 0x30),
                makePlaybackRow(index: 3, effectType: 0x01, effectParam: 0x00),
                makePlaybackRow(index: 4, effectType: 0x02, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.portamentoSlideEffects
        let replayedUp = try XCTUnwrap(diagnostics.first { $0.source.rowIndex == 3 })
        let replayedDown = try XCTUnwrap(diagnostics.first { $0.source.rowIndex == 4 })

        XCTAssertEqual(replayedUp.direction, .up)
        XCTAssertTrue(replayedUp.effectMemoryReused)
        XCTAssertEqual(replayedUp.slideAmount, 0x10)
        XCTAssertEqual(replayedUp.memorySource?.effectType, 0x01)
        XCTAssertEqual(replayedUp.memorySource?.effectParam, 0x10)
        XCTAssertEqual(replayedDown.direction, .down)
        XCTAssertTrue(replayedDown.effectMemoryReused)
        XCTAssertEqual(replayedDown.slideAmount, 0x30)
        XCTAssertEqual(replayedDown.memorySource?.effectType, 0x02)
        XCTAssertEqual(replayedDown.memorySource?.effectParam, 0x30)
    }

    func testPlaybackSongAdapterPortamentoMemoryWindowedCarryoverMatchesDefaultRender() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x20),
                makePlaybackRow(index: 2, effectType: 0x01, effectParam: 0x00),
                makePlaybackRow(index: 3, effectType: 0x02, effectParam: 0x10),
                makePlaybackRow(index: 4, effectType: 0x02, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 800, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 20
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)
        let memoryReplayed = windowed.diagnostics.portamentoSlideEffects.filter { $0.applied && $0.effectMemoryReused }

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertEqual(memoryReplayed.map(\.source.rowIndex), [2, 4])
        XCTAssertTrue(memoryReplayed.allSatisfy { !$0.stepUpdates.isEmpty })
    }

    func testPlaybackSongAdapterAmigaPortamentoWindowedCarryoverMatchesDefaultRender() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x02, effectParam: 0x10),
                makePlaybackRow(index: 2, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x10),
                makePlaybackRow(index: 3, effectType: 0x03, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 800, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250),
            usesLinearFrequencyTable: false
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 16
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 0)
    }

    func testRuntimeAdapterPlanMarksAmigaPitchStepUpdates() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x02, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250),
            usesLinearFrequencyTable: false
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let stepUpdate = try XCTUnwrap(plan.events.first { $0.categories.contains("portamento_2xx") })

        XCTAssertTrue(stepUpdate.categories.contains("amiga_frequency_table"))
        XCTAssertTrue(stepUpdate.categories.contains("amiga_period_sample_step"))
    }

    func testPlaybackSongAdapterPortamentoDirectStartWithoutPriorMemoryIsDeterministic() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x20),
                ],
                3: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x01, effectParam: 0x00),
                    makePlaybackRow(index: 1, effectType: 0x02, effectParam: 0x00),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            startOrderIndex: 1,
            orderCount: 1,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        )
        let renderer = PlaybackSongOfflineRenderer()

        let firstRender = renderer.render(request)
        let secondRender = renderer.render(request)
        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 1, orderCount: 1, sampleRate: 100)
            .diagnostics.portamentoSlideEffects

        XCTAssertFloatArrayEqual(secondRender.block.interleavedPCM, firstRender.block.interleavedPCM)
        XCTAssertEqual(diagnostics.map(\.status), [.zeroParamEffectMemoryDeferred, .zeroParamEffectMemoryDeferred])
        XCTAssertEqual(diagnostics[0].memoryUnavailableReason, "missing_1xx_portamento_memory")
        XCTAssertEqual(diagnostics[1].memoryUnavailableReason, "missing_2xx_portamento_memory")
        XCTAssertTrue(diagnostics.allSatisfy(\.effectMemoryMissing))
    }

    func testPlaybackSongAdapterPortamentoSlideNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, effectType: 0x02, effectParam: 0x20)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.portamentoSlideEffects.first)

        XCTAssertEqual(plan.pattern.events.count, 0)
        XCTAssertEqual(diagnostic.status, .noActiveVoice)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertFalse(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.direction, .down)
    }

    func testPlaybackSongAdapterAmigaPortamento2xxNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, effectType: 0x02, effectParam: 0x20)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250),
            usesLinearFrequencyTable: false
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.portamentoSlideEffects.first)

        XCTAssertEqual(diagnostic.status, .noActiveVoice)
        XCTAssertEqual(diagnostic.frequencyTableStatus, .amigaApplied)
        XCTAssertFalse(diagnostic.applied)
    }

    func testPlaybackSongAdapterPortamentoSlideClampsSafely() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 96, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0xFF),
            ]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makeRampPlaybackSample(frameCount: 600, relativeNote: 23, baseSampleRate: 100)]
                )
            ],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.portamentoSlideEffects.first)
        let update = try XCTUnwrap(diagnostic.stepUpdates.first)

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertTrue(diagnostic.clamped)
        XCTAssertTrue(update.clamped)
        XCTAssertEqual(diagnostic.stepUpdates.count, 1)
        XCTAssertLessThan(update.linearPeriodAfter, update.linearPeriodBefore)
        XCTAssertGreaterThan(update.playbackStepAfter, update.playbackStepBefore)
    }

    func testPlaybackSongAdapterPortamentoSlideUsesLinearFrequencyAndSampleMetadata() throws {
        let sample = makeRampPlaybackSample(frameCount: 600, relativeNote: 1, finetune: 2, baseSampleRate: 200)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.portamentoSlideEffects.first)
        let expectedPeriod = 7_680.0 - (Double((49 + 1) - 1) * 64.0) - 1.0
        let expectedStep = 200.0 * pow(2.0, (4_608.0 - expectedPeriod) / 768.0) / 100.0

        XCTAssertEqual(try XCTUnwrap(diagnostic.currentLinearPeriodBefore), expectedPeriod, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(diagnostic.currentPlaybackStepBefore), expectedStep, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(diagnostic.currentLinearPeriodAfter), expectedPeriod - Double(3 * 0x10), accuracy: 0.000_001)
    }

    func testPlaybackSongAdapterPortamentoSlideUsesFxxTiming() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                makePlaybackRow(index: 1, note: 49, instrument: 1),
                makePlaybackRow(index: 2, effectType: 0x01, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.portamentoSlideEffects.first)

        XCTAssertEqual(diagnostic.rowSpeed, 3)
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [10, 11])
    }

    func testPlaybackSongAdapterPortamentoSlideWindowedCarryoverMatchesDefaultRender() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x40),
                makePlaybackRow(index: 2, effectType: 0x01, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 12
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 0)
    }

    func testPlaybackSongAdapterPortamentoSlideWithNonLinearTableIsDeferred() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x01, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250),
            usesLinearFrequencyTable: false
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.portamentoSlideEffects.first)

        XCTAssertEqual(diagnostic.status, .unsupportedFrequencyTable)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertTrue(diagnostic.deferred)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.stepUpdates, [])
    }

    func testPlaybackSongAdapterE1xFinePortamentoUpAppliesRowLevelStepUpdate() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x12),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.finePortamentoUpEffects.first)
        let update = try XCTUnwrap(diagnostic.stepUpdates.first)
        let command = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first { $0.decodedLabel == "E1x fine portamento up" })

        XCTAssertEqual(plan.pattern.events.count, 1)
        XCTAssertEqual(plan.diagnostics.finePortamentoUpEffectCount, 1)
        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertTrue(diagnostic.applied)
        XCTAssertEqual(diagnostic.fineAmount, 2)
        XCTAssertEqual(diagnostic.fineAmountNibble, 2)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.activeEventIndex, 0)
        XCTAssertEqual(diagnostic.scheduledFrame, 4)
        XCTAssertFalse(diagnostic.appliedToInitialPlaybackStep)
        XCTAssertEqual(diagnostic.stepUpdates.count, 1)
        XCTAssertEqual(update.syntheticTick, 0)
        XCTAssertEqual(update.scheduledFrame, 4)
        XCTAssertEqual(update.linearPeriodBefore - update.linearPeriodAfter, 2, accuracy: 0.000_001)
        XCTAssertLessThan(try XCTUnwrap(diagnostic.currentLinearPeriodAfter), try XCTUnwrap(diagnostic.currentLinearPeriodBefore))
        XCTAssertGreaterThan(try XCTUnwrap(diagnostic.currentPlaybackStepAfter), try XCTUnwrap(diagnostic.currentPlaybackStepBefore))
        XCTAssertEqual(command.status, .applied)
    }

    func testPlaybackSongAdapterE11AndE1FProduceDistinctFinePortamentoSteps() throws {
        func song(amount: UInt8) -> PlaybackSong {
            makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x10 | amount),
                ]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
                initialTiming: PlaybackTiming(speed: 4, bpm: 250)
            )
        }

        let e11 = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song(amount: 0x01), orderIndex: 0, sampleRate: 100).diagnostics.finePortamentoUpEffects.first?.stepUpdates.first)
        let e1f = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song(amount: 0x0F), orderIndex: 0, sampleRate: 100).diagnostics.finePortamentoUpEffects.first?.stepUpdates.first)

        XCTAssertEqual(e11.linearPeriodBefore - e11.linearPeriodAfter, 1, accuracy: 0.000_001)
        XCTAssertEqual(e1f.linearPeriodBefore - e1f.linearPeriodAfter, 15, accuracy: 0.000_001)
        XCTAssertGreaterThan(e1f.playbackStepAfter, e11.playbackStepAfter)
    }

    func testPlaybackSongAdapterE10IsEffectMemoryDeferredNoOp() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x10),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.finePortamentoUpEffects.first)
        let command = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first { $0.decodedLabel == "E1x fine portamento up" })

        XCTAssertEqual(diagnostic.status, .zeroAmountEffectMemoryDeferred)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertTrue(diagnostic.deferred)
        XCTAssertTrue(diagnostic.ignoredAsNoOp)
        XCTAssertTrue(diagnostic.effectMemoryDeferred)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.fineAmount, 0)
        XCTAssertEqual(diagnostic.stepUpdates, [])
        XCTAssertEqual(command.status, .ignoredNoOp)
    }

    func testPlaybackSongAdapterE1xNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0x1F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.finePortamentoUpEffects.first)

        XCTAssertEqual(plan.pattern.events.count, 0)
        XCTAssertEqual(diagnostic.status, .noActiveVoice)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertFalse(diagnostic.deferred)
        XCTAssertTrue(diagnostic.ignoredAsNoOp)
        XCTAssertFalse(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.fineAmount, 15)
        XCTAssertEqual(diagnostic.stepUpdates, [])
    }

    func testPlaybackSongAdapterE1xSameCellNoteTriggersOnceAndFoldsIntoInitialStep() throws {
        let sample = makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)
        let baseline = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let e1x = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x1F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let baselinePlan = PlaybackSongSyntheticAdapter.adapt(baseline, orderIndex: 0, sampleRate: 100)
        let plan = PlaybackSongSyntheticAdapter.adapt(e1x, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.finePortamentoUpEffects.first)
        let event = try XCTUnwrap(plan.pattern.events.first)
        let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)

        XCTAssertEqual(plan.pattern.events.count, 1)
        XCTAssertEqual(plan.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.activeEventIndex, 0)
        XCTAssertTrue(diagnostic.appliedToInitialPlaybackStep)
        XCTAssertEqual(diagnostic.stepUpdates, [])
        XCTAssertEqual(diagnostic.scheduledFrame, 0)
        XCTAssertEqual(event.playbackStep, mapping.playbackStep, accuracy: 0.000_001)
        XCTAssertGreaterThan(event.playbackStep, try XCTUnwrap(baselinePlan.pattern.events.first?.playbackStep))
        let periodAfter = try XCTUnwrap(diagnostic.currentLinearPeriodAfter)
        let periodBefore = try XCTUnwrap(diagnostic.currentLinearPeriodBefore)
        XCTAssertEqual(periodBefore - periodAfter, 15, accuracy: 0.000_001)
    }

    func testPlaybackSongAdapterE1xWindowedCarryoverMatchesDefaultRender() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x11),
                makePlaybackRow(index: 2, effectType: 0x0E, effectParam: 0x1F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 12
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 0)
        XCTAssertEqual(windowed.diagnostics.finePortamentoUpEffects.filter(\.applied).count, 2)
    }

    func testPlaybackSongAdapterE2xFinePortamentoDownAppliesRowLevelStepUpdate() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x22),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.finePortamentoDownEffects.first)
        let update = try XCTUnwrap(diagnostic.stepUpdates.first)
        let command = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first { $0.decodedLabel == "E2x fine portamento down" })

        XCTAssertEqual(plan.diagnostics.finePortamentoDownEffectCount, 1)
        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertTrue(diagnostic.applied)
        XCTAssertEqual(diagnostic.fineAmount, 2)
        XCTAssertEqual(diagnostic.fineAmountNibble, 2)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.activeEventIndex, 0)
        XCTAssertEqual(diagnostic.scheduledFrame, 4)
        XCTAssertFalse(diagnostic.appliedToInitialPlaybackStep)
        XCTAssertEqual(diagnostic.stepUpdates.count, 1)
        XCTAssertEqual(update.syntheticTick, 0)
        XCTAssertEqual(update.scheduledFrame, 4)
        XCTAssertEqual(update.linearPeriodAfter - update.linearPeriodBefore, 2, accuracy: 0.000_001)
        XCTAssertGreaterThan(try XCTUnwrap(diagnostic.currentLinearPeriodAfter), try XCTUnwrap(diagnostic.currentLinearPeriodBefore))
        XCTAssertLessThan(try XCTUnwrap(diagnostic.currentPlaybackStepAfter), try XCTUnwrap(diagnostic.currentPlaybackStepBefore))
        XCTAssertEqual(command.status, .applied)
    }

    func testPlaybackSongAdapterE21AndE2FProduceDistinctFinePortamentoSteps() throws {
        func song(amount: UInt8) -> PlaybackSong {
            makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x20 | amount),
                ]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
                initialTiming: PlaybackTiming(speed: 4, bpm: 250)
            )
        }

        let e21 = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song(amount: 0x01), orderIndex: 0, sampleRate: 100).diagnostics.finePortamentoDownEffects.first?.stepUpdates.first)
        let e2f = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song(amount: 0x0F), orderIndex: 0, sampleRate: 100).diagnostics.finePortamentoDownEffects.first?.stepUpdates.first)

        XCTAssertEqual(e21.linearPeriodAfter - e21.linearPeriodBefore, 1, accuracy: 0.000_001)
        XCTAssertEqual(e2f.linearPeriodAfter - e2f.linearPeriodBefore, 15, accuracy: 0.000_001)
        XCTAssertLessThan(e2f.playbackStepAfter, e21.playbackStepAfter)
    }

    func testPlaybackSongAdapterE20IsEffectMemoryDeferredNoOp() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x20),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.finePortamentoDownEffects.first)
        let command = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first { $0.decodedLabel == "E2x fine portamento down" })

        XCTAssertEqual(diagnostic.status, .zeroAmountEffectMemoryDeferred)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertTrue(diagnostic.deferred)
        XCTAssertTrue(diagnostic.ignoredAsNoOp)
        XCTAssertTrue(diagnostic.effectMemoryDeferred)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.fineAmount, 0)
        XCTAssertEqual(diagnostic.stepUpdates, [])
        XCTAssertEqual(command.status, .ignoredNoOp)
    }

    func testPlaybackSongAdapterE2xNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0x2F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.finePortamentoDownEffects.first)

        XCTAssertEqual(plan.pattern.events.count, 0)
        XCTAssertEqual(diagnostic.status, .noActiveVoice)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertFalse(diagnostic.deferred)
        XCTAssertTrue(diagnostic.ignoredAsNoOp)
        XCTAssertFalse(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.fineAmount, 15)
        XCTAssertEqual(diagnostic.stepUpdates, [])
    }

    func testPlaybackSongAdapterE2xSameCellNoteTriggersOnceAndFoldsIntoInitialStep() throws {
        let sample = makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)
        let baseline = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let e2x = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x2F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let baselinePlan = PlaybackSongSyntheticAdapter.adapt(baseline, orderIndex: 0, sampleRate: 100)
        let plan = PlaybackSongSyntheticAdapter.adapt(e2x, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.finePortamentoDownEffects.first)
        let event = try XCTUnwrap(plan.pattern.events.first)
        let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)

        XCTAssertEqual(plan.pattern.events.count, 1)
        XCTAssertEqual(plan.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.activeEventIndex, 0)
        XCTAssertTrue(diagnostic.appliedToInitialPlaybackStep)
        XCTAssertEqual(diagnostic.stepUpdates, [])
        XCTAssertEqual(diagnostic.scheduledFrame, 0)
        XCTAssertEqual(event.playbackStep, mapping.playbackStep, accuracy: 0.000_001)
        XCTAssertLessThan(event.playbackStep, try XCTUnwrap(baselinePlan.pattern.events.first?.playbackStep))
        let periodAfter = try XCTUnwrap(diagnostic.currentLinearPeriodAfter)
        let periodBefore = try XCTUnwrap(diagnostic.currentLinearPeriodBefore)
        XCTAssertEqual(periodAfter - periodBefore, 15, accuracy: 0.000_001)
    }

    func testPlaybackSongAdapterE2xWindowedCarryoverMatchesDefaultRender() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x21),
                makePlaybackRow(index: 2, effectType: 0x0E, effectParam: 0x2F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 12
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 0)
        XCTAssertEqual(windowed.diagnostics.finePortamentoDownEffects.filter(\.applied).count, 2)
    }

    func testPlaybackSongAdapterVibrato4xySchedulesSampleStepUpdates() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.vibratoEffects.first)
        let command = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first { $0.effectType == 0x04 })

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertTrue(diagnostic.applied)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.activeEventIndex, 0)
        XCTAssertEqual(diagnostic.vibratoSpeed, 4)
        XCTAssertEqual(diagnostic.vibratoDepth, 8)
        XCTAssertEqual(diagnostic.vibratoControlValue, 0)
        XCTAssertEqual(diagnostic.vibratoWaveform, "sine")
        XCTAssertEqual(diagnostic.vibratoWaveformSource, "default_sine")
        XCTAssertEqual(diagnostic.rowSpeed, 4)
        XCTAssertEqual(diagnostic.rowBPM, 250)
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [5, 6, 7, 8])
        XCTAssertGreaterThan(try XCTUnwrap(diagnostic.stepUpdates.first?.playbackStepAfter), try XCTUnwrap(diagnostic.currentPlaybackStepBefore))
        XCTAssertEqual(try XCTUnwrap(diagnostic.stepUpdates.last?.playbackStepAfter), try XCTUnwrap(diagnostic.currentPlaybackStepBefore), accuracy: 0.000_001)
        XCTAssertEqual(command.status, .applied)
        XCTAssertEqual(plan.diagnostics.deferredCellFields.map(\.effectType), [])
    }

    func testPlaybackSongAdapterE40StoresDefaultSineWithoutPlayback() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let control = try XCTUnwrap(diagnostics.vibratoControlEffects.first)
        let command = try XCTUnwrap(diagnostics.effectCommandDiagnostics.first { $0.effectType == 0x0E && $0.effectParam == 0x40 })

        XCTAssertEqual(diagnostics.vibratoControlEffects.count, 1)
        XCTAssertEqual(diagnostics.eventMappings.count, 0)
        XCTAssertEqual(control.status, .stored)
        XCTAssertTrue(control.detected)
        XCTAssertTrue(control.applied)
        XCTAssertTrue(control.stored)
        XCTAssertFalse(control.deferred)
        XCTAssertFalse(control.activeVoiceFound)
        XCTAssertEqual(control.controlValue, 0)
        XCTAssertEqual(control.waveformID, 0)
        XCTAssertEqual(control.waveformName, "sine")
        XCTAssertTrue(control.affectsLaterVibrato)
        XCTAssertEqual(command.status, .applied)
        XCTAssertEqual(diagnostics.deferredCellFields.map(\.effectType), [])
    }

    func testPlaybackSongAdapterE4xWithoutActiveVoiceAffectsLater4xy() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0x41),
                makePlaybackRow(index: 1, note: 49, instrument: 1),
                makePlaybackRow(index: 2, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let control = try XCTUnwrap(diagnostics.vibratoControlEffects.first)
        let vibrato = try XCTUnwrap(diagnostics.vibratoEffects.first)

        XCTAssertEqual(control.status, .stored)
        XCTAssertFalse(control.activeVoiceFound)
        XCTAssertEqual(control.controlValue, 1)
        XCTAssertEqual(control.waveformName, "ramp_down")
        XCTAssertEqual(vibrato.status, .applied)
        XCTAssertEqual(vibrato.vibratoControlValue, 1)
        XCTAssertEqual(vibrato.vibratoWaveform, "ramp_down")
        XCTAssertEqual(vibrato.vibratoWaveformSource, "e4x_channel_state")
        XCTAssertEqual(vibrato.stepUpdates.map(\.scheduledFrame), [9, 10, 11, 12])
        XCTAssertEqual(diagnostics.deferredCellFields.map(\.effectType), [])
    }

    func testPlaybackSongAdapterE4xWaveformChangesLater4xyDeterministically() throws {
        let sample = makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)
        let sineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let rampSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x41),
                makePlaybackRow(index: 2, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let sine = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(sineSong, orderIndex: 0, sampleRate: 100).diagnostics.vibratoEffects.first)
        let ramp = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(rampSong, orderIndex: 0, sampleRate: 100).diagnostics.vibratoEffects.first)

        XCTAssertEqual(sine.vibratoWaveform, "sine")
        XCTAssertEqual(ramp.vibratoWaveform, "ramp_down")
        XCTAssertNotEqual(
            sine.stepUpdates.map(\.playbackStepAfter),
            ramp.stepUpdates.map(\.playbackStepAfter)
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(ramp.stepUpdates.first?.playbackStepAfter),
            try XCTUnwrap(sine.stepUpdates.first?.playbackStepAfter)
        )
    }

    func testPlaybackSongAdapterE43RandomWaveformIsRepeatable() throws {
        let sample = makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0x43),
                makePlaybackRow(index: 1, note: 49, instrument: 1),
                makePlaybackRow(index: 2, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let first = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let second = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let firstVibrato = try XCTUnwrap(first.vibratoEffects.first)
        let secondVibrato = try XCTUnwrap(second.vibratoEffects.first)

        XCTAssertEqual(first.vibratoControlEffects.first?.waveformName, "random")
        XCTAssertEqual(firstVibrato.vibratoWaveform, "random")
        XCTAssertEqual(
            firstVibrato.stepUpdates.map(\.playbackStepAfter),
            secondVibrato.stepUpdates.map(\.playbackStepAfter)
        )
        XCTAssertEqual(first.deferredCellFields.map(\.effectType), [])
    }

    func testPlaybackSongAdapterUnsupportedE4xControlIsDeferredExplicitly() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x44),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let control = try XCTUnwrap(diagnostics.vibratoControlEffects.first)
        let command = try XCTUnwrap(diagnostics.effectCommandDiagnostics.first { $0.effectType == 0x0E && $0.effectParam == 0x44 })

        XCTAssertEqual(control.status, .unsupportedWaveform)
        XCTAssertTrue(control.detected)
        XCTAssertFalse(control.applied)
        XCTAssertFalse(control.stored)
        XCTAssertTrue(control.deferred)
        XCTAssertTrue(control.unsupportedWaveform)
        XCTAssertEqual(control.controlValue, 4)
        XCTAssertEqual(control.waveformID, 0)
        XCTAssertEqual(control.waveformName, "unsupported")
        XCTAssertTrue(control.retriggerSuppressed)
        XCTAssertFalse(control.affectsLaterVibrato)
        XCTAssertEqual(command.status, .deferredUnsupported)
        XCTAssertEqual(diagnostics.deferredCellFields.map(\.field), [.effect])
    }

    func testPlaybackSongAdapterE4xWindowedCarryoverMatchesDefaultRender() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0x41),
                makePlaybackRow(index: 1, note: 49, instrument: 1),
                makePlaybackRow(index: 2, effectType: 0x04, effectParam: 0x48),
                makePlaybackRow(index: 3, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 16
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertEqual(windowed.diagnostics.vibratoControlEffects.first?.status, .stored)
        XCTAssertEqual(windowed.diagnostics.vibratoEffects.map(\.vibratoWaveform), ["ramp_down", "ramp_down"])
    }

    func testPlaybackSongAdapterVibrato4xySameCellNoteTriggersAndApplies() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.vibratoEffects.first)

        XCTAssertEqual(plan.pattern.events.count, 1)
        XCTAssertEqual(plan.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(plan.diagnostics.eventMappings.first?.effectType, 0x04)
        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.activeEventIndex, 0)
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [1, 2, 3, 4])
    }

    func testPlaybackSongAdapterVibrato4xyNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.vibratoEffects.first)

        XCTAssertEqual(plan.pattern.events.count, 0)
        XCTAssertEqual(diagnostic.status, .noActiveVoice)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertFalse(diagnostic.deferred)
        XCTAssertTrue(diagnostic.ignoredAsNoOp)
        XCTAssertFalse(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.vibratoSpeed, 4)
        XCTAssertEqual(diagnostic.vibratoDepth, 8)
        XCTAssertEqual(diagnostic.stepUpdates, [])
    }

    func testPlaybackSongAdapterVibrato400IsEffectMemoryDeferredNoOp() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x04, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.vibratoEffects.first)
        let command = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first { $0.effectType == 0x04 })

        XCTAssertEqual(diagnostic.status, .zeroParamEffectMemoryDeferred)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertTrue(diagnostic.deferred)
        XCTAssertTrue(diagnostic.ignoredAsNoOp)
        XCTAssertTrue(diagnostic.activeVoiceFound)
        XCTAssertEqual(diagnostic.vibratoSpeed, 0)
        XCTAssertEqual(diagnostic.vibratoDepth, 0)
        XCTAssertTrue(diagnostic.effectMemoryMissing)
        XCTAssertTrue(diagnostic.effectMemoryDeferred)
        XCTAssertEqual(diagnostic.memoryUnavailableReason, "missing_vibrato_speed_depth_memory")
        XCTAssertEqual(diagnostic.stepUpdates, [])
        XCTAssertEqual(command.status, .ignoredNoOp)
    }

    func testPlaybackSongAdapterVibrato400ReusesPrior4xyMemory() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
                makePlaybackRow(index: 1, effectType: 0x04, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let memoryDiagnostic = try XCTUnwrap(diagnostics.vibratoEffects.last)

        XCTAssertEqual(memoryDiagnostic.status, .applied)
        XCTAssertTrue(memoryDiagnostic.applied)
        XCTAssertTrue(memoryDiagnostic.effectMemoryReused)
        XCTAssertFalse(memoryDiagnostic.effectMemoryMissing)
        XCTAssertEqual(memoryDiagnostic.vibratoSpeed, 4)
        XCTAssertEqual(memoryDiagnostic.vibratoDepth, 8)
        XCTAssertEqual(memoryDiagnostic.vibratoSpeedSource, "4xy_channel_state")
        XCTAssertEqual(memoryDiagnostic.vibratoDepthSource, "4xy_channel_state")
        XCTAssertEqual(memoryDiagnostic.vibratoSpeedMemorySource?.source.rowIndex, 0)
        XCTAssertEqual(memoryDiagnostic.vibratoDepthMemorySource?.source.rowIndex, 0)
        XCTAssertEqual(memoryDiagnostic.stepUpdates.map(\.scheduledFrame), [5, 6, 7, 8])
        XCTAssertEqual(diagnostics.deferredCellFields.map(\.effectType), [])
    }

    func testPlaybackSongAdapterVibrato4xyZeroNibbleIsEffectMemoryDeferredNoOp() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x04, effectParam: 0x40),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.vibratoEffects.first)

        XCTAssertEqual(diagnostic.status, .zeroSpeedOrDepthEffectMemoryDeferred)
        XCTAssertFalse(diagnostic.applied)
        XCTAssertTrue(diagnostic.deferred)
        XCTAssertEqual(diagnostic.vibratoSpeed, 4)
        XCTAssertEqual(diagnostic.vibratoDepth, 0)
        XCTAssertTrue(diagnostic.effectMemoryMissing)
        XCTAssertTrue(diagnostic.effectMemoryDeferred)
        XCTAssertEqual(diagnostic.memoryUnavailableReason, "missing_vibrato_depth_memory")
        XCTAssertEqual(diagnostic.stepUpdates, [])
    }

    func testPlaybackSongAdapterVibrato4x0ReusesPriorDepthMemory() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
                makePlaybackRow(index: 1, effectType: 0x04, effectParam: 0x60),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.vibratoEffects.last)

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.vibratoSpeed, 6)
        XCTAssertEqual(diagnostic.vibratoDepth, 8)
        XCTAssertEqual(diagnostic.vibratoSpeedSource, "effect_param")
        XCTAssertEqual(diagnostic.vibratoDepthSource, "4xy_channel_state")
        XCTAssertTrue(diagnostic.effectMemoryReused)
        XCTAssertNil(diagnostic.vibratoSpeedMemorySource)
        XCTAssertEqual(diagnostic.vibratoDepthMemorySource?.source.rowIndex, 0)
    }

    func testPlaybackSongAdapterVibrato40yReusesPriorSpeedMemory() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
                makePlaybackRow(index: 1, effectType: 0x04, effectParam: 0x05),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostic = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.vibratoEffects.last)

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.vibratoSpeed, 4)
        XCTAssertEqual(diagnostic.vibratoDepth, 5)
        XCTAssertEqual(diagnostic.vibratoSpeedSource, "4xy_channel_state")
        XCTAssertEqual(diagnostic.vibratoDepthSource, "effect_param")
        XCTAssertTrue(diagnostic.effectMemoryReused)
        XCTAssertEqual(diagnostic.vibratoSpeedMemorySource?.source.rowIndex, 0)
        XCTAssertNil(diagnostic.vibratoDepthMemorySource)
    }

    func testPlaybackSongAdapterVibrato4xyWindowedCarryoverMatchesDefaultRender() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x04, effectParam: 0x48),
                makePlaybackRow(index: 2, effectType: 0x04, effectParam: 0x48),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 12
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 0)
    }

    func testPlaybackSongAdapterVibratoVolumeSlideRequiresPrior4xyStateAndVolumeColumnVibratoRemainsDeferred() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0xB4, effectType: 0x06, effectParam: 0x20),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])]
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let effect = try XCTUnwrap(diagnostics.effectCommandDiagnostics.first { $0.effectType == 0x06 })
        let volumeColumn = try XCTUnwrap(diagnostics.volumeColumnMappings.first?.volumeColumn)
        let diagnostic = try XCTUnwrap(diagnostics.vibratoEffects.first { $0.effectType == 0x06 })

        XCTAssertEqual(diagnostic.status, .zeroSpeedOrDepthEffectMemoryDeferred)
        XCTAssertEqual(diagnostic.vibratoSpeedSource, "missing_4xy_channel_state")
        XCTAssertTrue(diagnostic.effectMemoryMissing)
        XCTAssertTrue(diagnostic.effectMemoryDeferred)
        XCTAssertEqual(diagnostic.memoryUnavailableReason, "missing_vibrato_speed_depth_memory")
        XCTAssertEqual(diagnostic.volumeSlideUp, 2)
        XCTAssertEqual(diagnostic.volumeSlideDown, 0)
        XCTAssertEqual(effect.status, .applied)
        XCTAssertEqual(volumeColumn.command, .vibrato(amount: 4))
        XCTAssertTrue(volumeColumn.deferred)
    }

    func testPlaybackSongAdapterVibratoVolumeSlide6xySchedulesStepAndGainUpdates() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x04, effectParam: 0x48),
                makePlaybackRow(index: 1, effectType: 0x06, effectParam: 0x02),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let diagnostic = try XCTUnwrap(plan.diagnostics.vibratoEffects.first { $0.effectType == 0x06 })
        let update = try XCTUnwrap(plan.diagnostics.voiceStateUpdates.first { update in
            if case .effect6xyVolumeSlide = update.command {
                return true
            }
            return false
        })

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertEqual(diagnostic.vibratoSpeed, 4)
        XCTAssertEqual(diagnostic.vibratoDepth, 8)
        XCTAssertEqual(diagnostic.vibratoSpeedSource, "4xy_channel_state")
        XCTAssertEqual(diagnostic.vibratoDepthSource, "4xy_channel_state")
        XCTAssertTrue(diagnostic.effectMemoryReused)
        XCTAssertFalse(diagnostic.effectMemoryMissing)
        XCTAssertEqual(diagnostic.vibratoSpeedMemorySource?.source.rowIndex, 0)
        XCTAssertEqual(diagnostic.vibratoDepthMemorySource?.source.rowIndex, 0)
        XCTAssertEqual(diagnostic.volumeSlideUp, 0)
        XCTAssertEqual(diagnostic.volumeSlideDown, 2)
        XCTAssertEqual(diagnostic.volumeSlideAmount, 2)
        XCTAssertEqual(diagnostic.volumeSlideDirection, "down")
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [5, 6, 7, 8])
        XCTAssertEqual(update.status, .applied)
        XCTAssertTrue(update.activeVoiceUpdated)
        XCTAssertEqual(update.effectiveVolumeBefore, 32)
        XCTAssertEqual(update.effectiveVolumeAfter, 30)
        XCTAssertEqual(update.gainBefore, 0.5)
        XCTAssertEqual(update.gainAfter, 30.0 / 64.0)
    }

    func testPlaybackSongAdapterVibratoVolumeSlide600ReusesPriorVibratoMemoryWithoutVolumeSlideMemory() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
                makePlaybackRow(index: 1, effectType: 0x06, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let diagnostic = try XCTUnwrap(diagnostics.vibratoEffects.first { $0.effectType == 0x06 })
        let update = try XCTUnwrap(diagnostics.voiceStateUpdates.first { update in
            if case .effect6xyVolumeSlide = update.command {
                return true
            }
            return false
        })

        XCTAssertEqual(diagnostic.status, .applied)
        XCTAssertTrue(diagnostic.applied)
        XCTAssertFalse(diagnostic.deferred)
        XCTAssertFalse(diagnostic.ignoredAsNoOp)
        XCTAssertTrue(diagnostic.effectMemoryReused)
        XCTAssertFalse(diagnostic.effectMemoryMissing)
        XCTAssertEqual(diagnostic.vibratoSpeed, 4)
        XCTAssertEqual(diagnostic.vibratoDepth, 8)
        XCTAssertEqual(diagnostic.volumeSlideAmount, 0)
        XCTAssertEqual(diagnostic.volumeSlideDirection, "none")
        XCTAssertEqual(diagnostic.stepUpdates.map(\.scheduledFrame), [5, 6, 7, 8])
        XCTAssertEqual(update.status, .ignoredNoOp)
        XCTAssertTrue(update.ignoredAsNoOp)
    }

    func testPlaybackSongAdapterVibratoVolumeSlide600WithoutPriorVibratoMemoryIsDeferredNoOp() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x06, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let diagnostic = try XCTUnwrap(diagnostics.vibratoEffects.first { $0.effectType == 0x06 })

        XCTAssertEqual(diagnostic.status, .zeroParamEffectMemoryDeferred)
        XCTAssertTrue(diagnostic.deferred)
        XCTAssertTrue(diagnostic.ignoredAsNoOp)
        XCTAssertTrue(diagnostic.effectMemoryMissing)
        XCTAssertTrue(diagnostic.effectMemoryDeferred)
        XCTAssertEqual(diagnostic.memoryUnavailableReason, "missing_vibrato_speed_depth_memory")
        XCTAssertEqual(diagnostic.stepUpdates, [])
    }

    func testPlaybackSongAdapterTonePortamentoVolumeSlide5xySchedulesStepAndGainUpdates() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30),
                makePlaybackRow(index: 1, note: 61, instrument: 1, volumeColumn: 0x30, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, effectType: 0x05, effectParam: 0x02),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let five = try XCTUnwrap(diagnostics.tonePortamentoEffects.first { $0.effectType == 0x05 })
        let update = try XCTUnwrap(diagnostics.voiceStateUpdates.first { update in
            if case .effect5xyVolumeSlide = update.command {
                return update.applied
            }
            return false
        })

        XCTAssertEqual(five.status, .applied)
        XCTAssertEqual(five.targetNote, 61)
        XCTAssertEqual(five.portamentoSpeed, 0x40)
        XCTAssertEqual(five.stepUpdates.map(\.scheduledFrame), [9, 10, 11])
        XCTAssertEqual(update.syntheticTick, 1)
        XCTAssertEqual(update.scheduledFrame, 9)
        XCTAssertEqual(update.command, .effect5xyVolumeSlide(up: 0, down: 2))
        XCTAssertEqual(update.effectiveVolumeBefore, 32)
        XCTAssertEqual(update.effectiveVolumeAfter, 30)
        XCTAssertTrue(update.activeVoiceUpdated)
        XCTAssertEqual(update.volumeSlidePolicy, "single_nonzero_nibble")
    }

    func testPlaybackSongAdapterTonePortamentoVolumeSlide5xyIsDetectedAndCounted() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, effectType: 0x05, effectParam: 0x01),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let effect = try XCTUnwrap(diagnostics.effectCommandDiagnostics.first { $0.effectType == 0x05 })
        let fiveEffects = diagnostics.tonePortamentoEffects.filter { $0.effectType == 0x05 }

        XCTAssertEqual(effect.decodedLabel, "5xy tone portamento + volume slide")
        XCTAssertEqual(effect.status, .applied)
        XCTAssertEqual(fiveEffects.count, 1)
        XCTAssertEqual(fiveEffects.first?.effectParam, 0x01)
    }

    func testPlaybackSongAdapterTonePortamentoVolumeSlide500WithoutTargetDiagnosesNoOp() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x05, effectParam: 0x00),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let tone = try XCTUnwrap(diagnostics.tonePortamentoEffects.first { $0.effectType == 0x05 })
        let volume = try XCTUnwrap(diagnostics.voiceStateUpdates.first { update in
            if case .effect5xyVolumeSlide = update.command {
                return true
            }
            return false
        })

        XCTAssertEqual(tone.status, .noTarget)
        XCTAssertFalse(tone.applied)
        XCTAssertTrue(tone.ignoredAsNoOp)
        XCTAssertEqual(volume.status, .ignoredNoOp)
        XCTAssertEqual(volume.command, .effect5xyVolumeSlide(up: 0, down: 0))
        XCTAssertEqual(volume.volumeSlidePolicy, "500_no_volume_slide_memory_no_op")
        XCTAssertFalse(volume.activeVoiceUpdated)
    }

    func testPlaybackSongAdapterTonePortamentoVolumeSlide5xyNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x05, effectParam: 0x02),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let tone = try XCTUnwrap(diagnostics.tonePortamentoEffects.first { $0.effectType == 0x05 })
        let volume = try XCTUnwrap(diagnostics.voiceStateUpdates.first { update in
            if case .effect5xyVolumeSlide = update.command {
                return true
            }
            return false
        })

        XCTAssertEqual(tone.status, .noActiveVoice)
        XCTAssertFalse(tone.activeVoiceFound)
        XCTAssertFalse(tone.applied)
        XCTAssertEqual(volume.command, .effect5xyVolumeSlide(up: 0, down: 2))
        XCTAssertFalse(volume.activeVoiceUpdated)
    }

    func testPlaybackSongAdapterSameCellNote5xySetsTargetWithoutRetriggering() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, note: 65, instrument: 1, effectType: 0x05, effectParam: 0x01),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let five = try XCTUnwrap(diagnostics.tonePortamentoEffects.first { $0.effectType == 0x05 })

        XCTAssertEqual(diagnostics.eventMappings.count, 1)
        XCTAssertEqual(five.status, .applied)
        XCTAssertEqual(five.sameCellNote, true)
        XCTAssertEqual(five.targetNote, 65)
        XCTAssertEqual(five.noteTriggerEventCreated, false)
        XCTAssertEqual(five.voiceReplacement, false)
        XCTAssertEqual(five.samplePositionReset, false)
        XCTAssertEqual(five.cMixerReceivesNewVoice, false)
        XCTAssertEqual(five.cMixerReceivesOnlyStateUpdates, true)
    }

    func testPlaybackSongAdapterTonePortamentoVolumeSlide5xyUsesMixedNibbleVolumePolicy() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30),
                makePlaybackRow(index: 1, note: 61, instrument: 1, volumeColumn: 0x30, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, effectType: 0x05, effectParam: 0x2F),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let update = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .voiceStateUpdates
            .first { update in
                if case .effect5xyVolumeSlide = update.command {
                    return true
                }
                return false
            })

        XCTAssertEqual(update.command, .effect5xyVolumeSlide(up: 2, down: 0))
        XCTAssertEqual(update.volumeSlideRawUpNibble, 2)
        XCTAssertEqual(update.volumeSlideRawDownNibble, 15)
        XCTAssertEqual(update.volumeSlideBothNibblesNonzero, true)
        XCTAssertEqual(update.volumeSlidePolicy, "up_nibble_precedence_mikmod_observed")
        XCTAssertEqual(update.effectiveVolumeBefore, 32)
        XCTAssertEqual(update.effectiveVolumeAfter, 34)
    }

    func testPlaybackSongAdapterTonePortamentoVolumeSlide5xyWindowedAndSplitRendersRemainDeterministic() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 64), volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, effectType: 0x05, effectParam: 0x02),
                makePlaybackRow(index: 3),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 12
        )
        let renderer = PlaybackSongOfflineRenderer()

        let single = renderer.render(request)
        let repeated = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [2, 4, 6])
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(repeated.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(split.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 0)
    }

    func testPlaybackSongAdapterVolumeColumnTonePortamentoIsDecodedAsSupported() {
        let diagnostic = PlaybackSongVolumeColumnDecoder.decode(0xF4)

        XCTAssertEqual(diagnostic.command, .tonePortamento(amount: 4))
        XCTAssertEqual(diagnostic.classification, .supported)
        XCTAssertTrue(diagnostic.applied)
        XCTAssertFalse(diagnostic.deferred)
        XCTAssertEqual(diagnostic.behavior, .tickLevelAfterTick0)
    }

    func testPlaybackSongAdapterVolumeColumnTonePortamentoSchedulesStepUpdates() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, volumeColumn: 0xF4),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let volumeColumn = try XCTUnwrap(diagnostics.volumeColumnMappings.first { $0.source.rowIndex == 2 }?.volumeColumn)
        let tone = try XCTUnwrap(diagnostics.tonePortamentoEffects.first { $0.commandSource == .volumeColumn })

        XCTAssertEqual(volumeColumn.command, .tonePortamento(amount: 4))
        XCTAssertTrue(volumeColumn.applied)
        XCTAssertFalse(volumeColumn.deferred)
        XCTAssertEqual(tone.status, .applied)
        XCTAssertEqual(tone.rawVolumeColumn, 0xF4)
        XCTAssertEqual(tone.targetNote, 61)
        XCTAssertEqual(tone.portamentoSpeed, 4)
        XCTAssertEqual(tone.stepUpdates.map(\.scheduledFrame), [9, 10, 11])
    }

    func testPlaybackSongAdapterSameCellVolumeColumnTonePortamentoSetsTargetWithoutRetriggering() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, note: 65, instrument: 1, volumeColumn: 0xF4),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let diagnostics = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics
        let tone = try XCTUnwrap(diagnostics.tonePortamentoEffects.first { $0.commandSource == .volumeColumn })

        XCTAssertEqual(diagnostics.eventMappings.count, 1)
        XCTAssertEqual(tone.status, .applied)
        XCTAssertEqual(tone.sameCellNote, true)
        XCTAssertEqual(tone.targetNote, 65)
        XCTAssertEqual(tone.noteTriggerEventCreated, false)
        XCTAssertEqual(tone.voiceReplacement, false)
        XCTAssertEqual(tone.samplePositionReset, false)
        XCTAssertEqual(tone.cMixerReceivesNewVoice, false)
        XCTAssertEqual(tone.cMixerReceivesOnlyStateUpdates, true)
    }

    func testPlaybackSongAdapterVolumeColumnTonePortamentoNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, volumeColumn: 0xF4),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let tone = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .tonePortamentoEffects
            .first { $0.commandSource == .volumeColumn })

        XCTAssertEqual(tone.status, .noActiveVoice)
        XCTAssertFalse(tone.activeVoiceFound)
        XCTAssertFalse(tone.applied)
        XCTAssertEqual(tone.stepUpdates, [])
    }

    func testPlaybackSongAdapterVolumeColumnTonePortamentoMissingTargetAndSpeedAreDiagnosed() throws {
        let noTargetSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, volumeColumn: 0xF4),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let noSpeedSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x00),
                makePlaybackRow(index: 2, volumeColumn: 0xF0),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )

        let noTarget = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(noTargetSong, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .tonePortamentoEffects
            .first { $0.commandSource == .volumeColumn })
        let noSpeed = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(noSpeedSong, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .tonePortamentoEffects
            .first { $0.commandSource == .volumeColumn })

        XCTAssertEqual(noTarget.status, .noTarget)
        XCTAssertEqual(noTarget.portamentoSpeed, 4)
        XCTAssertEqual(noTarget.stepUpdates, [])
        XCTAssertEqual(noSpeed.status, .noSpeed)
        XCTAssertEqual(noSpeed.targetNote, 61)
        XCTAssertEqual(noSpeed.portamentoSpeed, 0)
        XCTAssertEqual(noSpeed.stepUpdates, [])
    }

    func testPlaybackSongAdapterVolumeColumnTonePortamentoWindowedAndSplitRendersRemainDeterministic() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 64), volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, note: 61, instrument: 1, effectType: 0x03, effectParam: 0x40),
                makePlaybackRow(index: 2, volumeColumn: 0xF4),
                makePlaybackRow(index: 3),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 12
        )
        let renderer = PlaybackSongOfflineRenderer()

        let single = renderer.render(request)
        let repeated = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [2, 4, 6])
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(repeated.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(split.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 0)
    }

    func testPlaybackSongAdapterSampleOffset9xxKeepsVolumeColumnSetVolumeAndPanning() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let row = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x09, effectParam: 0x01),
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0xCF, effectType: 0x09, effectParam: 0x01)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [row]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 2),
            frames: 1
        ))

        XCTAssertPCMEqual(result.block.interleavedPCM, [0.128, 0.384])
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.volumeColumn.command), [
            .setVolume(value: 32),
            .setPanning(value: 255)
        ])
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.sampleOffset.status), [.applied, .applied])
    }

    func testPlaybackSongAdapterSampleOffset9xxKeepsVolumeColumnSlides() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0x30),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0x64, effectType: 0x09, effectParam: 0x01)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertPCMEqual(result.block.interleavedPCM, [0, 0.112, 0.1124375])
        XCTAssertEqual(mapping.volumeColumn.command, .volumeSlideDown(amount: 4))
        XCTAssertEqual(mapping.volumeColumn.effectiveVolumeBefore, 32)
        XCTAssertEqual(mapping.volumeColumn.effectiveVolumeAfter, 28)
        XCTAssertEqual(mapping.sampleOffset.status, .applied)
    }

    func testPlaybackSongAdapterSampleOffset9xxKeepsParsedVolumeEnvelope() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 32)
        ])
        let sample = makeRampPlaybackSample(frameCount: 300)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertPCMEqual(result.block.interleavedPCM, [0.128, 0.1285])
        XCTAssertEqual(mapping.volumeEnvelopeStatus, .mapped)
        XCTAssertEqual(mapping.sampleOffset.status, .applied)
    }

    func testPlaybackSongAdapterSampleOffset9xxKeepsNoteOffEnvelopeRelease() throws {
        let envelope = makePlaybackVolumeEnvelope(enabled: false, points: [], typeFlags: 0, fadeout: 65_536)
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 300), baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01),
                    makePlaybackRow(index: 1, note: 97)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 1, 0.5, 0])
        XCTAssertEqual(result.plan.pattern.events.first?.initialSourceFrame, 256)
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.keyOffApplied)
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.fadeoutApplied)
        XCTAssertEqual(mapping.sampleOffset.status, .applied)
    }

    func testPlaybackSongAdapterOtherEffectColumnsRemainDeferredWith9xxDecoder() throws {
        let sample = makeRampPlaybackSample(frameCount: 300)
        let baselineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let otherEffectSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x07, effectParam: 0x42)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let baseline = renderer.render(PlaybackSongOfflineRenderRequest(song: baselineSong, orderIndex: 0, config: config, frames: 3))
        let other = renderer.render(PlaybackSongOfflineRenderRequest(song: otherEffectSong, orderIndex: 0, config: config, frames: 3))
        let mapping = try XCTUnwrap(other.diagnostics.eventMappings.first)

        XCTAssertEqual(other.block, baseline.block)
        XCTAssertEqual(mapping.sampleOffset.status, .notPresent)
        XCTAssertTrue(mapping.hasIgnoredEffect)
        XCTAssertEqual(other.diagnostics.deferredCellFields.map(\.field), [.effect])
        XCTAssertEqual(other.diagnostics.deferredCellFields.first?.effectType, 0x07)
    }

    func testPlaybackSongAdapterSampleOffset9xxSplitResetAndWAVExportRemainDeterministic() throws {
        let fallbackSample = makePlaybackSample(sampleIndex: 0, pcm: Array(repeating: Float(9), count: 300), baseSampleRate: 100)
        let mappedSample = makeRampPlaybackSample(frameCount: 300, sampleIndex: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [fallbackSample, mappedSample],
                    noteSampleMap: makeNoteSampleMap(overrides: [49: 1])
                )
            ]
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        )
        let renderer = PlaybackSongOfflineRenderer()
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let firstURL = tempDirectory.appendingPathComponent("first-candidate.wav")
        let secondURL = tempDirectory.appendingPathComponent("second-candidate.wav")

        let single = renderer.render(request)
        let repeated = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [1, 1, 2])
        let session = renderer.prepare(request)
        let resetFirst = session.render(frames: 4)
        _ = session.render(frames: 2)
        session.reset()
        let resetSecond = session.render(frames: 4)
        try renderer.exportWAV(request, to: firstURL)
        try renderer.exportWAV(request, to: secondURL)

        XCTAssertPCMEqual(single.block.interleavedPCM, [0.256, 0.257, 0.258, 0.259])
        XCTAssertEqual(single.diagnostics.eventMappings.first?.sampleSelectionMethod, .sampleMap)
        XCTAssertEqual(single.diagnostics.eventMappings.first?.sampleIndex, 1)
        XCTAssertEqual(repeated.block, single.block)
        XCTAssertEqual(split.block, single.block)
        XCTAssertEqual(resetFirst, resetSecond)
        XCTAssertEqual(resetFirst, single.block)
        XCTAssertEqual(try Data(contentsOf: firstURL), try Data(contentsOf: secondURL))
    }

    func testPlaybackSongAdapterNoteDelayEDxDelaysNoteToRequestedTick() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD2)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)
        let delay = try XCTUnwrap(result.diagnostics.noteDelayEffects.first)
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(event.scheduledStartFrame, 2)
        XCTAssertEqual(event.tick, 2)
        XCTAssertEqual(mapping.syntheticTick, 2)
        XCTAssertEqual(delay.status, .applied)
        XCTAssertEqual(delay.requestedTick, 2)
        XCTAssertEqual(delay.originalFrame, 0)
        XCTAssertEqual(delay.delayedFrame, 2)
        XCTAssertEqual(delay.rowSpeed, 6)
        XCTAssertEqual(delay.rowBPM, 250)
        XCTAssertEqual(delay.eventIndex, 0)
        XCTAssertEqual(effect.decodedLabel, "EDx note delay")
        XCTAssertEqual(effect.status, .applied)
        XCTAssertEqual(result.block.interleavedPCM, [0, 0, 1, 0])
    }

    func testPlaybackSongAdapterNoteDelayED0SchedulesAtRowStart() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD0)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let delay = try XCTUnwrap(result.diagnostics.noteDelayEffects.first)

        XCTAssertEqual(event.scheduledStartFrame, 0)
        XCTAssertEqual(event.tick, 0)
        XCTAssertEqual(delay.status, .applied)
        XCTAssertEqual(delay.requestedTick, 0)
        XCTAssertEqual(delay.originalFrame, 0)
        XCTAssertEqual(delay.delayedFrame, 0)
        XCTAssertEqual(result.block.interleavedPCM, [1, 0])
    }

    func testPlaybackSongAdapterNoteDelayEDxUsesFxxTimingAndPreservesEventMetadata() throws {
        let fallbackSample = makePlaybackSample(sampleIndex: 0, pcm: [9], baseSampleRate: 100)
        let mappedSample = makePlaybackSample(sampleIndex: 1, pcm: [1, 1, 1], volume: 0.5, baseSampleRate: 200)
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 1, value: 32)
        ])
        let stateRow = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 0x30, effectType: 0x08, effectParam: 0xFF)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                stateRow,
                makePlaybackRow(index: 1, effectType: 0x0F, effectParam: 0x03),
                makePlaybackRow(index: 2, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD2)
            ]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [fallbackSample, mappedSample],
                    volumeEnvelope: envelope,
                    noteSampleMap: makeNoteSampleMap(overrides: [49: 1])
                )
            ],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 2),
            frames: 16
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)
        let delay = try XCTUnwrap(result.diagnostics.noteDelayEffects.first)

        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6, 12])
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 6, 3])
        XCTAssertEqual(event.scheduledStartFrame, 14)
        XCTAssertEqual(delay.originalFrame, 12)
        XCTAssertEqual(delay.delayedFrame, 14)
        XCTAssertEqual(delay.rowSpeed, 3)
        XCTAssertEqual(delay.rowBPM, 250)
        XCTAssertEqual(mapping.sampleIndex, 1)
        XCTAssertEqual(mapping.sampleSelectionMethod, .sampleMap)
        XCTAssertEqual(mapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertEqual(mapping.effectiveVolumeValue, 32)
        XCTAssertEqual(mapping.effectivePan, 1)
        XCTAssertEqual(mapping.volumeEnvelopeStatus, .mapped)
        XCTAssertEqual(mapping.sampleOffset.status, .notPresent)
        XCTAssertEqual(event.gain, 0.25)
        XCTAssertEqual(event.pan, 1)
    }

    func testPlaybackSongAdapterNoteDelayEDxWithoutNoteIsDiagnosedAndDoesNotSchedule() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0xD2)
            ]],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let delay = try XCTUnwrap(result.diagnostics.noteDelayEffects.first)
        let ignored = try XCTUnwrap(result.diagnostics.ignoredCells.first)
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(result.plan.pattern.events, [])
        XCTAssertEqual(result.block.interleavedPCM, [0, 0, 0])
        XCTAssertEqual(delay.status, .noNoteDeferred)
        XCTAssertTrue(delay.deferred)
        XCTAssertEqual(delay.requestedTick, 2)
        XCTAssertNil(delay.delayedFrame)
        XCTAssertEqual(ignored.reason, .noteDelayWithoutNote)
        XCTAssertEqual(effect.status, .deferredUnsupported)
    }

    func testPlaybackSongAdapterNoteDelayEDxOutOfRowSkipsSafelyAndDiagnosesNoOp() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD2)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let delay = try XCTUnwrap(result.diagnostics.noteDelayEffects.first)
        let ignored = try XCTUnwrap(result.diagnostics.ignoredCells.first)
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(result.plan.pattern.events, [])
        XCTAssertEqual(result.block.interleavedPCM, [0, 0, 0])
        XCTAssertEqual(delay.status, .outOfRowNoOp)
        XCTAssertTrue(delay.outOfRow)
        XCTAssertTrue(delay.ignoredAsNoOp)
        XCTAssertEqual(delay.requestedTick, 2)
        XCTAssertEqual(delay.rowSpeed, 2)
        XCTAssertNil(delay.delayedFrame)
        XCTAssertEqual(ignored.reason, .noteDelayOutOfRow)
        XCTAssertEqual(effect.status, .ignoredNoOp)
    }

    func testPlaybackSongAdapterNoteCutECxCutsActiveVoiceAtRequestedTick() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1, 1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC2)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let cut = try XCTUnwrap(result.diagnostics.noteCutEffects.first)
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 1, 0, 0])
        XCTAssertEqual(cut.status, .applied)
        XCTAssertEqual(cut.requestedTick, 2)
        XCTAssertEqual(cut.scheduledFrame, 2)
        XCTAssertEqual(cut.rowSpeed, 6)
        XCTAssertEqual(cut.rowBPM, 250)
        XCTAssertEqual(cut.activeEventIndex, 0)
        XCTAssertEqual(effect.decodedLabel, "ECx note cut")
        XCTAssertEqual(effect.status, .applied)
    }

    func testPlaybackSongAdapterNoteCutECxUsesFxxTiming() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 8), baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC2)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 10
        ))
        let cut = try XCTUnwrap(result.diagnostics.noteCutEffects.first)

        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6])
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 3])
        XCTAssertEqual(cut.scheduledFrame, 8)
        XCTAssertEqual(cut.rowSpeed, 3)
        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 6) + [1, 1, 0, 0])
    }

    func testPlaybackSongAdapterNoteCutECxNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0xC1)
            ]],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))
        let cut = try XCTUnwrap(result.diagnostics.noteCutEffects.first)

        XCTAssertEqual(result.plan.pattern.events, [])
        XCTAssertEqual(result.block.interleavedPCM, [0, 0])
        XCTAssertEqual(cut.status, .noActiveVoice)
        XCTAssertFalse(cut.applied)
        XCTAssertTrue(cut.ignoredAsNoOp)
        XCTAssertEqual(cut.scheduledFrame, 1)
        XCTAssertNil(cut.activeEventIndex)
    }

    func testPlaybackSongAdapterNoteCutECxOutOfRowDoesNotCut() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC2)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let cut = try XCTUnwrap(result.diagnostics.noteCutEffects.first)
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 1, 1])
        XCTAssertEqual(cut.status, .outOfRowNoOp)
        XCTAssertTrue(cut.outOfRow)
        XCTAssertFalse(cut.applied)
        XCTAssertNil(cut.scheduledFrame)
        XCTAssertEqual(effect.status, .ignoredNoOp)
    }

    func testPlaybackSongAdapterNoteCutECxWorksWithLoopedSamples() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5], baseSampleRate: 100, loopStart: 0, loopLength: 2, loopType: 1)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC2)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.loopMode, .forward)
        XCTAssertEqual(result.diagnostics.noteCutEffects.first?.status, .applied)
        XCTAssertEqual(result.block.interleavedPCM, [1, 0.5, 0, 0, 0])
    }

    func testPlaybackSongAdapterNoteCutECxIsHardGainCutNotKeyOffRelease() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], baseSampleRate: 100)
        let envelope = makePlaybackVolumeEnvelope(enabled: false, points: [], typeFlags: 0, fadeout: 65_536)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC1)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 0, 0])
        XCTAssertEqual(result.diagnostics.noteCutEffects.first?.status, .applied)
        XCTAssertEqual(result.diagnostics.keyOffEvents, [])
        XCTAssertFalse(mapping.volumeEnvelopeSemantics.keyOffApplied)
        XCTAssertFalse(mapping.volumeEnvelopeSemantics.fadeoutApplied)
    }

    func testPlaybackSongAdapterRetriggerE9xSchedulesExpectedTicksAndFrames() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5, 0.25], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x92)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(result.plan.pattern.events.map(\.scheduledStartFrame), [0, 2, 4])
        XCTAssertEqual(result.plan.pattern.events.map(\.tick), [0, 2, 4])
        XCTAssertEqual(retrigger.status, .applied)
        XCTAssertTrue(retrigger.activeVoiceFound)
        XCTAssertEqual(retrigger.retriggerIntervalTicks, 2)
        XCTAssertEqual(retrigger.rowSpeed, 6)
        XCTAssertEqual(retrigger.rowBPM, 250)
        XCTAssertEqual(retrigger.retriggerTicks, [2, 4])
        XCTAssertEqual(retrigger.retriggerFrames, [2, 4])
        XCTAssertEqual(retrigger.retriggerEventIndices, [1, 2])
        XCTAssertEqual(retrigger.replacedEventIndices, [0, 1])
        XCTAssertEqual(effect.decodedLabel, "E9x retrigger")
        XCTAssertEqual(effect.status, .applied)
        XCTAssertPCMEqual(result.block.interleavedPCM, [1, 0.5, 1, 0.5, 1, 0.5])
    }

    func testPlaybackSongAdapterRetriggerE9xUsesFxxTimingForAbsoluteFrames() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5, 0.25], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x92)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 10
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)

        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6])
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.effectiveSpeed), [6, 3])
        XCTAssertEqual(result.plan.pattern.events.map(\.scheduledStartFrame), [6, 8])
        XCTAssertEqual(retrigger.rowSpeed, 3)
        XCTAssertEqual(retrigger.rowBPM, 250)
        XCTAssertEqual(retrigger.retriggerTicks, [2])
        XCTAssertEqual(retrigger.retriggerFrames, [8])
        XCTAssertPCMEqual(result.block.interleavedPCM, [0, 0, 0, 0, 0, 0, 1, 0.5, 1, 0.5])
    }

    func testPlaybackSongAdapterRetriggerE9xAtOrBeyondSpeedDiagnosesNoOp() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5, 0.25], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x92)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(result.plan.pattern.events.count, 1)
        XCTAssertEqual(retrigger.status, .outOfRowNoOp)
        XCTAssertTrue(retrigger.outOfRow)
        XCTAssertTrue(retrigger.ignoredAsNoOp)
        XCTAssertEqual(retrigger.retriggerFrames, [])
        XCTAssertEqual(effect.status, .ignoredNoOp)
        XCTAssertPCMEqual(result.block.interleavedPCM, [1, 0.5, 0.25, 0])
    }

    func testPlaybackSongAdapterRetriggerE90IsDeferredNoEffectMemory() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5, 0.25], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x90)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(result.plan.pattern.events.count, 1)
        XCTAssertEqual(retrigger.status, .ignoredE90NoEffectMemory)
        XCTAssertTrue(retrigger.deferred)
        XCTAssertTrue(retrigger.ignoredAsNoOp)
        XCTAssertEqual(retrigger.retriggerIntervalTicks, 0)
        XCTAssertEqual(retrigger.retriggerFrames, [])
        XCTAssertTrue(mapping.hasIgnoredEffect)
        XCTAssertEqual(effect.status, .ignoredNoOp)
        XCTAssertEqual(result.diagnostics.deferredCellFields.map(\.field), [.effect])
    }

    func testPlaybackSongAdapterRetriggerE9xNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0x92)
            ]],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)

        XCTAssertEqual(result.plan.pattern.events, [])
        XCTAssertEqual(result.block.interleavedPCM, [0, 0, 0])
        XCTAssertEqual(retrigger.status, .noActiveVoice)
        XCTAssertFalse(retrigger.activeVoiceFound)
        XCTAssertTrue(retrigger.ignoredAsNoOp)
        XCTAssertEqual(retrigger.retriggerFrames, [])
    }

    func testPlaybackSongAdapterRetriggerE9xPreservesPitchVolumeAndPanState() throws {
        let sample = makePlaybackSample(pcm: [1, 2, 3, 4], volume: 0.5, baseSampleRate: 200)
        let stateRow = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 0x30, effectType: 0x08, effectParam: 0xFF)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                stateRow,
                makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x91)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)
        let retriggerMapping = try XCTUnwrap(result.diagnostics.eventMappings.last)

        XCTAssertEqual(result.plan.pattern.events.map(\.playbackStep), [2, 2])
        XCTAssertEqual(result.plan.pattern.events.map(\.gain), [0.25, 0.25])
        XCTAssertEqual(result.plan.pattern.events.map(\.pan), [1, 1])
        XCTAssertEqual(try XCTUnwrap(retrigger.playbackStep), 2, accuracy: 0.000000001)
        XCTAssertEqual(retrigger.gain, 0.25)
        XCTAssertEqual(retrigger.pan, 1)
        XCTAssertEqual(retriggerMapping.effectiveVolumeValue, 32)
        XCTAssertEqual(retriggerMapping.effectivePan, 1)
        XCTAssertPCMEqual(result.block.interleavedPCM, [0, 0, 0.25, 0.25])
    }

    func testPlaybackSongAdapterRetriggerE9xPreservesSampleOffset() throws {
        let pcm = (0..<260).map { Float($0) / 1000 }
        let sample = makePlaybackSample(pcm: pcm, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x01),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x91)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)

        XCTAssertEqual(result.plan.pattern.events.map(\.initialSourceFrame), [256, 256])
        XCTAssertEqual(retrigger.initialSourceFrame, 256)
        XCTAssertEqual(result.diagnostics.sampleOffsetEffects.first?.status, .applied)
        XCTAssertPCMEqual(result.block.interleavedPCM, [0.256, 0.257, 0.258, 0.256])
    }

    func testPlaybackSongAdapterRetriggerE9xWorksWithLoopedSamples() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5], baseSampleRate: 100, loopStart: 0, loopLength: 2, loopType: 1)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x92)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))

        XCTAssertEqual(result.plan.pattern.events.map(\.loop.mode), [.forward, .forward, .forward])
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.loopMode), [.forward, .forward, .forward])
        XCTAssertEqual(result.diagnostics.retriggerEffects.first?.status, .applied)
        XCTAssertPCMEqual(result.block.interleavedPCM, [1, 0.5, 1, 0.5, 1, 0.5])
    }

    func testPlaybackSongAdapterRetriggerE9xRestartsEnvelopeOnGeneratedEvents() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 1, value: 32)
        ])
        let sample = makePlaybackSample(pcm: [1, 1, 1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x91)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)

        XCTAssertEqual(retrigger.envelopePolicy, "fresh_event_restarts_envelope")
        XCTAssertTrue(result.plan.pattern.events.allSatisfy { $0.volumeEnvelope != nil })
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.volumeEnvelopeStatus), [.mapped, .mapped])
        XCTAssertPCMEqual(result.block.interleavedPCM, [1, 1])
    }

    func testPlaybackSongAdapterRetriggerRxyIsDetectedAndSchedulesExpectedTicks() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5, 0.25], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x1B, effectParam: 0x02)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(effect.decodedLabel, "Rxy multi retrigger")
        XCTAssertEqual(effect.status, .applied)
        XCTAssertEqual(result.diagnostics.retriggerEffectCount, 1)
        XCTAssertEqual(result.plan.pattern.events.map(\.scheduledStartFrame), [0, 2, 4])
        XCTAssertEqual(retrigger.status, .applied)
        XCTAssertEqual(retrigger.effectType, 0x1B)
        XCTAssertEqual(retrigger.volumeModeNibble, 0)
        XCTAssertEqual(retrigger.intervalNibble, 2)
        XCTAssertEqual(retrigger.retriggerTicks, [2, 4])
        XCTAssertEqual(retrigger.retriggerFrames, [2, 4])
        XCTAssertEqual(retrigger.retriggerEventIndices, [1, 2])
        XCTAssertEqual(retrigger.volumeChangeCount, 0)
        XCTAssertPCMEqual(result.block.interleavedPCM, [1, 0.5, 1, 0.5, 1, 0.5])
    }

    func testPlaybackSongAdapterRetriggerRxyZeroIntervalIsDeferredNoOp() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5, 0.25], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x1B, effectParam: 0xA0)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.plan.pattern.events.count, 1)
        XCTAssertEqual(retrigger.status, .ignoredRxyZeroIntervalNoEffectMemory)
        XCTAssertTrue(retrigger.deferred)
        XCTAssertTrue(retrigger.ignoredAsNoOp)
        XCTAssertEqual(retrigger.volumeModeNibble, 10)
        XCTAssertEqual(retrigger.intervalNibble, 0)
        XCTAssertEqual(retrigger.retriggerFrames, [])
        XCTAssertTrue(mapping.hasIgnoredEffect)
        XCTAssertEqual(result.diagnostics.deferredCellFields.map(\.field), [.effect])
    }

    func testPlaybackSongAdapterRetriggerRxyNoActiveVoiceIsDiagnosed() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x1B, effectParam: 0xA2)
            ]],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)

        XCTAssertEqual(result.plan.pattern.events, [])
        XCTAssertEqual(retrigger.status, .noActiveVoice)
        XCTAssertFalse(retrigger.activeVoiceFound)
        XCTAssertTrue(retrigger.ignoredAsNoOp)
        XCTAssertEqual(retrigger.volumeModeNibble, 10)
        XCTAssertEqual(retrigger.intervalNibble, 2)
        XCTAssertEqual(retrigger.retriggerFrames, [])
    }

    func testPlaybackSongAdapterSameCellNoteAndRxyTriggersOnceThenRetriggersLater() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x1B, effectParam: 0x02)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)

        XCTAssertEqual(result.plan.pattern.events.map(\.tick), [0, 2, 4])
        XCTAssertEqual(result.plan.pattern.events.filter { $0.tick == 0 }.count, 1)
        XCTAssertEqual(retrigger.replacedEventIndices, [0, 1])
        XCTAssertPCMEqual(result.block.interleavedPCM, [1, 1, 1, 1, 1, 1])
    }

    func testPlaybackSongAdapterRetriggerRxyVolumeModeAdjustsAndClamps() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 8), baseSampleRate: 100)
        let upward = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0C, effectParam: 60),
                makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x1B, effectParam: 0xF1)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 250)
        )
        let downward = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x0C, effectParam: 8),
                makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x1B, effectParam: 0x51)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let upResult = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: upward,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        ))
        let downResult = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: downward,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let upRetrigger = try XCTUnwrap(upResult.diagnostics.retriggerEffects.first)
        let downRetrigger = try XCTUnwrap(downResult.diagnostics.retriggerEffects.first)

        let expectedUpGains: [Float] = [60.0 / 64.0, 1, 1, 1]
        XCTAssertEqual(upResult.plan.pattern.events.map(\.gain), expectedUpGains)
        XCTAssertEqual(upRetrigger.volumeModeNibble, 15)
        XCTAssertEqual(upRetrigger.volumeValuesBefore, [60, 64, 64])
        XCTAssertEqual(upRetrigger.volumeValuesAfter, [64, 64, 64])
        XCTAssertEqual(upRetrigger.volumeChangeCount, 1)
        XCTAssertEqual(upRetrigger.retriggerGains, [1, 1, 1])
        let expectedDownGains: [Float] = [8.0 / 64.0, 0, 0]
        XCTAssertEqual(downResult.plan.pattern.events.map(\.gain), expectedDownGains)
        XCTAssertEqual(downRetrigger.volumeModeNibble, 5)
        XCTAssertEqual(downRetrigger.volumeValuesBefore, [8, 0])
        XCTAssertEqual(downRetrigger.volumeValuesAfter, [0, 0])
        XCTAssertEqual(downRetrigger.volumeChangeCount, 1)
        XCTAssertEqual(downRetrigger.retriggerGains, [0, 0])
    }

    func testPlaybackSongAdapterRetriggerRxyUsesCommonXMVolumeModeTable() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 8), baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x1B, effectParam: 0xA2)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let retrigger = try XCTUnwrap(result.diagnostics.retriggerEffects.first)

        let expectedGains: [Float] = [0.5, 34.0 / 64.0, 36.0 / 64.0]
        XCTAssertEqual(result.plan.pattern.events.map(\.gain), expectedGains)
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.effectiveVolumeValue), [32, 34, 36])
        XCTAssertEqual(retrigger.volumeModeNibble, 10)
        XCTAssertEqual(retrigger.volumeValuesBefore, [32, 34])
        XCTAssertEqual(retrigger.volumeValuesAfter, [34, 36])
        XCTAssertEqual(retrigger.volumeChangeCount, 2)
        XCTAssertEqual(retrigger.volumeChangePolicy, "xm_common_multi_retrigger_volume_table_first_pass")
    }

    func testPlaybackSongAdapterRetriggerRxyCommonVolumeModeTableIsDeterministic() {
        let adjusted = (0...15).map {
            PlaybackSongSyntheticAdapter.retriggerVolumeAdjustment(modeNibble: $0, currentVolume: 32).volumeAfter
        }

        XCTAssertEqual(adjusted, [32, 31, 30, 28, 24, 16, 21, 16, 32, 33, 34, 36, 40, 48, 48, 64])
    }

    func testPlaybackSongAdapterRetriggerRxyWindowedAndSplitRendersRemainDeterministic() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 64), baseSampleRate: 100, loopStart: 0, loopLength: 64, loopType: 1)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30),
                makePlaybackRow(index: 1, effectType: 0x1B, effectParam: 0xA1),
                makePlaybackRow(index: 2),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 9
        )
        let renderer = PlaybackSongOfflineRenderer()

        let single = renderer.render(request)
        let repeated = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [2, 3, 4])
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(repeated.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(split.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertEqual(single.diagnostics.retriggerEffects.first?.status, .applied)
        XCTAssertEqual(single.diagnostics.retriggerEffects.first?.retriggerFrames, [4, 5])
    }

    func testPlaybackSongAdapterOtherExtendedECommandsRemainDeferredWithECxEDxSupport() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x44)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))
        let effect = try XCTUnwrap(result.diagnostics.effectCommandDiagnostics.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 0])
        XCTAssertEqual(effect.decodedLabel, "E4x vibrato control")
        XCTAssertEqual(effect.status, .deferredUnsupported)
        XCTAssertEqual(result.diagnostics.deferredCellFields.map(\.field), [.effect])
        XCTAssertEqual(result.diagnostics.noteCutEffects, [])
        XCTAssertEqual(result.diagnostics.noteDelayEffects, [])
        XCTAssertEqual(result.diagnostics.retriggerEffects, [])
    }

    func testPlaybackSongAdapterDisabledVolumeEnvelopePreservesOutput() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1])
        let disabledEnvelope = makePlaybackVolumeEnvelope(
            enabled: false,
            points: [PlaybackEnvelopePoint(tick: 0, value: 32)],
            typeFlags: 0
        )
        let baselineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let disabledEnvelopeSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: disabledEnvelope)]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let baseline = renderer.render(PlaybackSongOfflineRenderRequest(song: baselineSong, orderIndex: 0, config: config, frames: 3))
        let disabled = renderer.render(PlaybackSongOfflineRenderRequest(song: disabledEnvelopeSong, orderIndex: 0, config: config, frames: 3))
        let disabledEvent = try XCTUnwrap(disabled.plan.pattern.events.first)

        XCTAssertEqual(disabled.block, baseline.block)
        XCTAssertNil(disabledEvent.volumeEnvelope)
        XCTAssertEqual(try XCTUnwrap(disabled.diagnostics.eventMappings.first).volumeEnvelopeStatus, .disabled)
    }

    func testPlaybackSongAdapterMapsBasicParsedVolumeEnvelopePoints() throws {
        let sample = makePlaybackSample(pcm: [1, 1])
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 32)
        ])
        let baselineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)
            ],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )
        let requestConfig = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let baseline = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: baselineSong,
            orderIndex: 0,
            config: requestConfig,
            frames: 2
        ))
        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: requestConfig,
            frames: 2
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(event.volumeEnvelope, MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0.5)
        ]))
        XCTAssertEqual(mapping.volumeEnvelopeStatus, .mapped)
        XCTAssertEqual(mapping.sourceVolumeEnvelopePointCount, 1)
        XCTAssertEqual(mapping.mappedVolumeEnvelopePointCount, 1)
        XCTAssertEqual(baseline.block.interleavedPCM, [1, 1])
        XCTAssertEqual(result.block.interleavedPCM, [0.5, 0.5])
    }

    func testPlaybackSongAdapterDescendingVolumeEnvelopeReducesLaterFrames() {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 2, value: 32)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [makePlaybackSample(pcm: [1, 1, 1, 1])], volumeEnvelope: envelope)
            ],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))

        XCTAssertEqual(result.block.interleavedPCM, [1, 0.75, 0.5, 0.5])
        XCTAssertLessThan(result.block.interleavedPCM[2], result.block.interleavedPCM[0])
    }

    func testPlaybackSongAdapterVolumeEnvelopeStillAppliesWithPitchMappedStep() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 2, value: 32)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makePlaybackSample(pcm: Array(repeating: Float(1), count: 10), baseSampleRate: 100)],
                    volumeEnvelope: envelope
                )
            ],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertEqual(mapping.volumeEnvelopeStatus, .mapped)
        XCTAssertEqual(result.block.interleavedPCM, [1, 0.75, 0.5, 0.5])
    }

    func testPlaybackSongAdapterAscendingVolumeEnvelopeRaisesLaterFrames() {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 16),
            PlaybackEnvelopePoint(tick: 2, value: 64)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [makePlaybackSample(pcm: [1, 1, 1, 1])], volumeEnvelope: envelope)
            ],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))

        XCTAssertEqual(result.block.interleavedPCM, [0.25, 0.625, 1, 1])
        XCTAssertGreaterThan(result.block.interleavedPCM[2], result.block.interleavedPCM[0])
    }

    func testPlaybackSongAdapterInvalidOrEmptyVolumeEnvelopeIsIgnoredSafely() throws {
        let sample = makePlaybackSample(pcm: [1, 1])
        let invalidEnvelope = makePlaybackVolumeEnvelope(enabled: true, points: [])
        let baselineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let invalidEnvelopeSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: invalidEnvelope)]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let baseline = renderer.render(PlaybackSongOfflineRenderRequest(song: baselineSong, orderIndex: 0, config: config, frames: 2))
        let invalid = renderer.render(PlaybackSongOfflineRenderRequest(song: invalidEnvelopeSong, orderIndex: 0, config: config, frames: 2))

        XCTAssertEqual(invalid.block, baseline.block)
        XCTAssertEqual(try XCTUnwrap(invalid.diagnostics.eventMappings.first).volumeEnvelopeStatus, .invalidOrEmptyIgnored)
        XCTAssertNil(try XCTUnwrap(invalid.plan.pattern.events.first).volumeEnvelope)
    }

    func testPlaybackSongAdapterVolumeEnvelopeMappingUsesInitialTiming() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 0),
            PlaybackEnvelopePoint(tick: 3, value: 64)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x03)]
            ],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [makePlaybackSample(pcm: [1])], volumeEnvelope: envelope)
            ],
            initialTiming: PlaybackTiming(speed: 6, bpm: 125)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 1_000)
        let mappedEnvelope = try XCTUnwrap(try XCTUnwrap(plan.pattern.events.first).volumeEnvelope)

        XCTAssertEqual(mappedEnvelope.points, [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 60, value: 1)
        ])
        XCTAssertEqual(plan.diagnostics.initialSpeed, 6)
        XCTAssertEqual(plan.diagnostics.initialBPM, 125)
        XCTAssertEqual(plan.diagnostics.ignoredEffectFieldCount, 1)
    }

    func testPlaybackSongAdapterReportsAppliedEnvelopeSustainLoopAndDeferredFadeoutUntilKeyOff() throws {
        let envelope = makePlaybackVolumeEnvelope(
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 32)
            ],
            sustainPointIndex: 0,
            loopStartPointIndex: 0,
            loopEndPointIndex: 1,
            typeFlags: 0x07,
            fadeout: 128
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [makePlaybackSample(pcm: [1])], volumeEnvelope: envelope)
            ]
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let event = try XCTUnwrap(plan.diagnostics.eventMappings.first)

        XCTAssertEqual(event.volumeEnvelopeStatus, .mapped)
        XCTAssertFalse(event.hasDeferredVolumeEnvelopeSustain)
        XCTAssertFalse(event.hasDeferredVolumeEnvelopeLoop)
        XCTAssertTrue(event.hasDeferredVolumeEnvelopeFadeout)
        XCTAssertTrue(event.volumeEnvelopeSemantics.sustainApplied)
        XCTAssertTrue(event.volumeEnvelopeSemantics.loopApplied)
        XCTAssertEqual(event.volumeEnvelopeSemantics.sustainPointIndex, 0)
        XCTAssertEqual(event.volumeEnvelopeSemantics.sustainFrame, 0)
        XCTAssertEqual(event.volumeEnvelopeSemantics.loopStartPointIndex, 0)
        XCTAssertEqual(event.volumeEnvelopeSemantics.loopEndPointIndex, 1)
        XCTAssertEqual(event.volumeEnvelopeSemantics.loopStartFrame, 0)
        XCTAssertEqual(event.volumeEnvelopeSemantics.loopEndFrame, 2)
        XCTAssertEqual(event.volumeEnvelopeSemantics.fadeoutValue, 128)
        XCTAssertEqual(plan.diagnostics.deferredCellFields.map(\.field), [])
    }

    func testPlaybackSongAdapterSustainHoldsWithoutNoteOff() throws {
        let envelope = makePlaybackVolumeEnvelope(
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 32),
                PlaybackEnvelopePoint(tick: 2, value: 0)
            ],
            sustainPointIndex: 1,
            typeFlags: 0x03
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makePlaybackSample(pcm: Array(repeating: Float(1), count: 6), baseSampleRate: 100)],
                    volumeEnvelope: envelope
                )
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 0.5, 0.5, 0.5, 0.5])
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.sustainApplied)
        XCTAssertFalse(mapping.volumeEnvelopeSemantics.keyOffEncountered)
    }

    func testPlaybackSongAdapterEnvelopeLoopRepeatsWithoutNoteOff() throws {
        let envelope = makePlaybackVolumeEnvelope(
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 32),
                PlaybackEnvelopePoint(tick: 2, value: 16)
            ],
            loopStartPointIndex: 1,
            loopEndPointIndex: 2,
            typeFlags: 0x05
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makePlaybackSample(pcm: Array(repeating: Float(1), count: 6), baseSampleRate: 100)],
                    volumeEnvelope: envelope
                )
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 0.5, 0.25, 0.5, 0.25])
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.loopApplied)
        XCTAssertFalse(mapping.volumeEnvelopeSemantics.keyOffEncountered)
    }

    func testPlaybackSongAdapterInvalidEnvelopeSemanticIndicesAreDeferredSafely() throws {
        let envelope = makePlaybackVolumeEnvelope(
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 32)
            ],
            sustainPointIndex: 9,
            loopStartPointIndex: 0,
            loopEndPointIndex: 9,
            typeFlags: 0x07,
            fadeout: 0
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makePlaybackSample(pcm: [1, 1, 1], baseSampleRate: 100)],
                    volumeEnvelope: envelope
                )
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 0.5, 0.5])
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.sustainDeferred)
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.loopDeferred)
        XCTAssertNil(result.plan.pattern.events.first?.volumeEnvelope?.sustainFrame)
        XCTAssertNil(result.plan.pattern.events.first?.volumeEnvelope?.loopEndFrame)
    }

    func testPlaybackSongAdapterNoteOffReleasesSustainAndReportsKeyOffApplied() throws {
        let envelope = makePlaybackVolumeEnvelope(
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 0)
            ],
            sustainPointIndex: 0,
            typeFlags: 0x03
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 97),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makePlaybackSample(pcm: Array(repeating: Float(1), count: 4), baseSampleRate: 100)],
                    volumeEnvelope: envelope
                )
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)
        let keyOff = try XCTUnwrap(result.diagnostics.keyOffEvents.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 1, 0, 0])
        XCTAssertEqual(result.plan.pattern.events.first?.keyOffFrame, 1)
        XCTAssertTrue(keyOff.applied)
        XCTAssertEqual(keyOff.releaseFrame, 1)
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.keyOffEncountered)
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.keyOffApplied)
        XCTAssertEqual(mapping.volumeEnvelopeSemantics.releaseFrame, 1)
    }

    func testPlaybackSongAdapterFadeoutAppliesAfterNoteOff() throws {
        let envelope = makePlaybackVolumeEnvelope(enabled: false, points: [], typeFlags: 0, fadeout: 65_536)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 97)
                ]
            ],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makePlaybackSample(pcm: Array(repeating: Float(1), count: 6), baseSampleRate: 100)],
                    volumeEnvelope: envelope
                )
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [1, 1, 0.5, 0])
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.keyOffApplied)
        XCTAssertTrue(mapping.volumeEnvelopeSemantics.fadeoutApplied)
        XCTAssertEqual(mapping.volumeEnvelopeSemantics.fadeoutValue, 65_536)
    }

    private func makeKxxSyntheticPlan(
        rows: [PlaybackRow],
        speed: Int = 4,
        bpm: Int = 250,
        samplePCM: [Float] = Array(repeating: Float(1), count: 8),
        volumeEnvelope: PlaybackVolumeEnvelope = .disabled
    ) -> PlaybackSongSyntheticPlan {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makePlaybackSample(pcm: samplePCM, baseSampleRate: 100)],
                    volumeEnvelope: volumeEnvelope
                )
            ],
            initialTiming: PlaybackTiming(speed: speed, bpm: bpm)
        )

        return PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
    }

    private func renderKxxRows(
        _ rows: [PlaybackRow],
        samplePCM: [Float],
        volumeEnvelope: PlaybackVolumeEnvelope,
        frames: Int
    ) -> PlaybackSongOfflineRenderResult {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makePlaybackSample(pcm: samplePCM, baseSampleRate: 100)],
                    volumeEnvelope: volumeEnvelope
                )
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        return PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: frames
        ))
    }

    func testPlaybackSongAdapterKxxSchedulesRowStartAndTickOneKeyOffs() throws {
        let k00 = makeKxxSyntheticPlan(rows: [
            makePlaybackRow(index: 0, note: 49, instrument: 1),
            makePlaybackRow(index: 1, effectType: 0x14, effectParam: 0x00)
        ])
        let k00Event = try XCTUnwrap(k00.pattern.events.first)
        let k00KeyOff = try XCTUnwrap(k00.diagnostics.keyOffEvents.first)

        XCTAssertEqual(k00.diagnostics.keyOffEvents.count, 1)
        XCTAssertEqual(k00Event.keyOffFrame, 4)
        XCTAssertEqual(k00KeyOff.effectType, 0x14)
        XCTAssertEqual(k00KeyOff.effectParam, 0x00)
        XCTAssertTrue(k00KeyOff.detected)
        XCTAssertTrue(k00KeyOff.applied)
        XCTAssertEqual(k00KeyOff.reason, .releasedActiveVoice)
        XCTAssertEqual(k00KeyOff.requestedTick, 0)
        XCTAssertEqual(k00KeyOff.syntheticTick, 0)
        XCTAssertEqual(k00KeyOff.scheduledFrame, 4)
        XCTAssertEqual(k00KeyOff.releaseFrame, 4)
        XCTAssertTrue(k00KeyOff.activeVoiceReleased)
        XCTAssertFalse(k00.diagnostics.deferredCellFields.contains { $0.effectType == 0x14 })

        let k01 = makeKxxSyntheticPlan(rows: [
            makePlaybackRow(index: 0, note: 49, instrument: 1),
            makePlaybackRow(index: 1, effectType: 0x14, effectParam: 0x01)
        ])
        let k01KeyOff = try XCTUnwrap(k01.diagnostics.keyOffEvents.first)

        XCTAssertEqual(k01.pattern.events.first?.keyOffFrame, 5)
        XCTAssertEqual(k01KeyOff.requestedTick, 1)
        XCTAssertEqual(k01KeyOff.syntheticTick, 1)
        XCTAssertEqual(k01KeyOff.scheduledFrame, 5)
        XCTAssertEqual(k01KeyOff.rowSpeed, 4)
        XCTAssertEqual(k01KeyOff.rowBPM, 250)
    }

    func testPlaybackSongAdapterKxxNoActiveVoiceIsDiagnosed() throws {
        let plan = makeKxxSyntheticPlan(rows: [makePlaybackRow(index: 0, effectType: 0x14, effectParam: 0x00)])
        let keyOff = try XCTUnwrap(plan.diagnostics.keyOffEvents.first)

        XCTAssertEqual(plan.pattern.events, [])
        XCTAssertEqual(keyOff.effectType, 0x14)
        XCTAssertFalse(keyOff.applied)
        XCTAssertTrue(keyOff.deferred)
        XCTAssertEqual(keyOff.reason, .noActiveVoice)
        XCTAssertEqual(keyOff.scheduledFrame, 0)
        XCTAssertFalse(keyOff.activeVoiceFound)
        XCTAssertFalse(keyOff.activeVoiceReleased)
    }

    func testPlaybackSongAdapterSameCellNoteAndKxxTriggersOnceThenKeysOff() throws {
        let plan = makeKxxSyntheticPlan(rows: [
            makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x14, effectParam: 0x01)
        ])
        let event = try XCTUnwrap(plan.pattern.events.first)
        let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)
        let keyOff = try XCTUnwrap(plan.diagnostics.keyOffEvents.first)

        XCTAssertEqual(plan.pattern.events.count, 1)
        XCTAssertEqual(plan.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(event.scheduledStartFrame, 0)
        XCTAssertEqual(event.keyOffFrame, 1)
        XCTAssertEqual(mapping.effectType, 0x14)
        XCTAssertEqual(mapping.effectParam, 0x01)
        XCTAssertEqual(keyOff.activeEventIndex, 0)
        XCTAssertEqual(keyOff.releaseFrame, 1)
    }

    func testPlaybackSongAdapterKxxReleasesEnvelopeSustainAndStartsFadeout() throws {
        let sustainEnvelope = makePlaybackVolumeEnvelope(
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 0)
            ],
            sustainPointIndex: 0,
            typeFlags: 0x03
        )
        let sustain = renderKxxRows([
            makePlaybackRow(index: 0, note: 49, instrument: 1),
            makePlaybackRow(index: 1, effectType: 0x14, effectParam: 0x00),
            makePlaybackRow(index: 2)
        ], samplePCM: Array(repeating: Float(1), count: 4), volumeEnvelope: sustainEnvelope, frames: 4)
        let sustainMapping = try XCTUnwrap(sustain.diagnostics.eventMappings.first)

        XCTAssertEqual(sustain.block.interleavedPCM, [1, 1, 0, 0])
        XCTAssertTrue(sustainMapping.volumeEnvelopeSemantics.sustainApplied)
        XCTAssertTrue(sustainMapping.volumeEnvelopeSemantics.keyOffApplied)
        XCTAssertEqual(sustain.diagnostics.keyOffEvents.first?.effectType, 0x14)

        let fadeout = renderKxxRows([
            makePlaybackRow(index: 0, note: 49, instrument: 1),
            makePlaybackRow(index: 1, effectType: 0x14, effectParam: 0x00)
        ], samplePCM: Array(repeating: Float(1), count: 6), volumeEnvelope: makePlaybackVolumeEnvelope(enabled: false, points: [], typeFlags: 0, fadeout: 65_536), frames: 4)
        let fadeoutMapping = try XCTUnwrap(fadeout.diagnostics.eventMappings.first)

        XCTAssertEqual(fadeout.block.interleavedPCM, [1, 1, 0.5, 0])
        XCTAssertTrue(fadeoutMapping.volumeEnvelopeSemantics.keyOffApplied)
        XCTAssertTrue(fadeoutMapping.volumeEnvelopeSemantics.fadeoutApplied)
        XCTAssertEqual(fadeout.diagnostics.keyOffEvents.first?.effectType, 0x14)
    }

    func testPlaybackSongAdapterEnvelopeSemanticsSplitAndResetRemainDeterministic() {
        let envelope = makePlaybackVolumeEnvelope(enabled: false, points: [], typeFlags: 0, fadeout: 65_536)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 97)
                ]
            ],
            instrumentsByIndex: [
                1: PlaybackInstrument(
                    index: 1,
                    samples: [makePlaybackSample(pcm: Array(repeating: Float(1), count: 6), baseSampleRate: 100)],
                    volumeEnvelope: envelope
                )
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        )
        let renderer = PlaybackSongOfflineRenderer()

        let single = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [1, 1, 2])
        let session = renderer.prepare(request)
        let resetFirst = session.render(frames: 4)
        _ = session.render(frames: 2)
        session.reset()
        let resetSecond = session.render(frames: 4)

        XCTAssertEqual(single.block.interleavedPCM, [1, 1, 0.5, 0])
        XCTAssertEqual(split.block, single.block)
        XCTAssertEqual(resetFirst, resetSecond)
        XCTAssertEqual(resetFirst, single.block)
    }

    func testPlaybackSongAdapterLoopedSamplesStillWorkWithEnvelopeSemantics() throws {
        let envelope = makePlaybackVolumeEnvelope(
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 32)
            ],
            sustainPointIndex: 1,
            typeFlags: 0x03,
            fadeout: 65_536
        )
        let forwardSample = makePlaybackSample(pcm: [1, 0.5, 0.25], baseSampleRate: 100, loopStart: 0, loopLength: 3, loopType: 1)
        let pingPongSample = makePlaybackSample(pcm: [1, 0.5, 0.25], baseSampleRate: 100, loopStart: 0, loopLength: 3, loopType: 2)
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let forward = renderer.render(PlaybackSongOfflineRenderRequest(
            song: makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [forwardSample], volumeEnvelope: envelope)],
                initialTiming: PlaybackTiming(speed: 1, bpm: 250)
            ),
            orderIndex: 0,
            config: config,
            frames: 5
        ))
        let pingPong = renderer.render(PlaybackSongOfflineRenderRequest(
            song: makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [pingPongSample], volumeEnvelope: envelope)],
                initialTiming: PlaybackTiming(speed: 1, bpm: 250)
            ),
            orderIndex: 0,
            config: config,
            frames: 5
        ))

        XCTAssertEqual(try XCTUnwrap(forward.diagnostics.eventMappings.first).loopMode, .forward)
        XCTAssertEqual(try XCTUnwrap(pingPong.diagnostics.eventMappings.first).loopMode, .pingPong)
        XCTAssertEqual(forward.block.interleavedPCM, [1, 0.25, 0.125, 0.5, 0.25])
        XCTAssertEqual(pingPong.block.interleavedPCM, [1, 0.25, 0.125, 0.25, 0.5])
    }

    func testPlaybackSongAdapterNoVolumeColumnPreservesBaselineRender() {
        let sample = makePlaybackSample(pcm: [1, 0.5], volume: 0.5, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))

        XCTAssertEqual(result.block.interleavedPCM, [0.5, 0.25, 0])
        XCTAssertEqual(result.plan.pattern.events.first?.gain, 0.5)
        XCTAssertEqual(result.diagnostics.eventMappings.first?.volumeColumn.rawValue, 0)
        XCTAssertEqual(result.diagnostics.eventMappings.first?.volumeColumn.classification, .ignoredNoOp)
    }

    func testPlaybackSongAdapterVolumeColumnSetVolumeChangesAmplitudeAndDiagnostics() throws {
        let sample = makePlaybackSample(pcm: [1, 1], volume: 1, baseSampleRate: 100)
        let baselineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let volumeSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let baseline = renderer.render(PlaybackSongOfflineRenderRequest(song: baselineSong, orderIndex: 0, config: config, frames: 2))
        let volume = renderer.render(PlaybackSongOfflineRenderRequest(song: volumeSong, orderIndex: 0, config: config, frames: 2))
        let mapping = try XCTUnwrap(volume.diagnostics.eventMappings.first)

        XCTAssertEqual(baseline.block.interleavedPCM, [1, 1])
        XCTAssertEqual(volume.block.interleavedPCM, [0.5, 0.5])
        XCTAssertNotEqual(volume.block.interleavedPCM, baseline.block.interleavedPCM)
        XCTAssertEqual(try XCTUnwrap(volume.plan.pattern.events.first).gain, 0.5)
        XCTAssertEqual(mapping.volumeColumn.rawValue, 0x30)
        XCTAssertEqual(mapping.volumeColumn.command, .setVolume(value: 32))
        XCTAssertEqual(mapping.volumeColumn.classification, .supported)
        XCTAssertTrue(mapping.volumeColumn.applied)
        XCTAssertFalse(mapping.hasIgnoredVolumeColumn)
        XCTAssertEqual(mapping.volumeColumn.appliedGainMultiplier, 0.5)
    }

    func testPlaybackSongAdapterVolumeColumnSetVolumeEdgesClampSafely() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let zeroSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x10)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let fullSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x50)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let zero = renderer.render(PlaybackSongOfflineRenderRequest(song: zeroSong, orderIndex: 0, config: config, frames: 2))
        let full = renderer.render(PlaybackSongOfflineRenderRequest(song: fullSong, orderIndex: 0, config: config, frames: 2))
        let zeroMapping = try XCTUnwrap(zero.diagnostics.eventMappings.first)
        let fullMapping = try XCTUnwrap(full.diagnostics.eventMappings.first)

        XCTAssertEqual(zero.block.interleavedPCM, [0, 0])
        XCTAssertEqual(full.block.interleavedPCM, [1, 0])
        XCTAssertEqual(zeroMapping.volumeColumn.appliedVolumeValue, 0)
        XCTAssertEqual(zeroMapping.volumeColumn.appliedGainMultiplier, 0)
        XCTAssertEqual(fullMapping.volumeColumn.appliedVolumeValue, 64)
        XCTAssertEqual(fullMapping.volumeColumn.appliedGainMultiplier, 1)
        XCTAssertEqual(try XCTUnwrap(zero.plan.pattern.events.first).gain, 0)
        XCTAssertEqual(try XCTUnwrap(full.plan.pattern.events.first).gain, 1)
    }

    func testPlaybackSongAdapterVolumeColumnSetPanningChangesStereoBalanceAndDiagnostics() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let centerSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let leftSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0xC0)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let rightSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0xCF)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 2)

        let center = renderer.render(PlaybackSongOfflineRenderRequest(song: centerSong, orderIndex: 0, config: config, frames: 2))
        let left = renderer.render(PlaybackSongOfflineRenderRequest(song: leftSong, orderIndex: 0, config: config, frames: 2))
        let right = renderer.render(PlaybackSongOfflineRenderRequest(song: rightSong, orderIndex: 0, config: config, frames: 2))
        let leftMapping = try XCTUnwrap(left.diagnostics.eventMappings.first)
        let rightMapping = try XCTUnwrap(right.diagnostics.eventMappings.first)

        XCTAssertEqual(center.block.interleavedPCM, [1, 1, 0, 0])
        XCTAssertEqual(left.block.interleavedPCM, [1, 0, 0, 0])
        XCTAssertEqual(right.block.interleavedPCM, [0, 1, 0, 0])
        XCTAssertNotEqual(left.block.interleavedPCM, center.block.interleavedPCM)
        XCTAssertNotEqual(right.block.interleavedPCM, center.block.interleavedPCM)
        XCTAssertEqual(leftMapping.volumeColumn.command, .setPanning(value: 0))
        XCTAssertEqual(leftMapping.volumeColumn.appliedPanningValue, 0)
        XCTAssertEqual(leftMapping.volumeColumn.appliedPan, -1)
        XCTAssertTrue(leftMapping.volumeColumn.applied)
        XCTAssertFalse(leftMapping.hasIgnoredVolumeColumn)
        XCTAssertEqual(rightMapping.volumeColumn.command, .setPanning(value: 255))
        XCTAssertEqual(rightMapping.volumeColumn.appliedPanningValue, 255)
        XCTAssertEqual(rightMapping.volumeColumn.appliedPan, 1)
    }

    func testPlaybackSongAdapterVolumeColumnCombinesWithSampleVolume() {
        let sample = makePlaybackSample(pcm: [1, 1], volume: 0.5, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))

        XCTAssertEqual(result.block.interleavedPCM, [0.25, 0.25])
        XCTAssertEqual(result.plan.pattern.events.first?.gain, 0.25)
    }

    func testPlaybackSongAdapterVolumeColumnCombinesWithParsedVolumeEnvelope() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 32)
        ])
        let sample = makePlaybackSample(pcm: [1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30)]],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)
            ]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [0.25, 0.25])
        XCTAssertEqual(mapping.volumeColumn.appliedGainMultiplier, 0.5)
        XCTAssertEqual(mapping.volumeEnvelopeStatus, .mapped)
    }

    func testPlaybackSongAdapterVolumeColumnCombinesWithPitchStep() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3, 4, 5, 6, 7], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1, volumeColumn: 0x30)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertEqual(mapping.volumeColumn.command, .setVolume(value: 32))
        XCTAssertEqual(result.block.interleavedPCM, [0, 1, 2, 3])
    }

    func testPlaybackSongAdapterUnsupportedVolumeColumnsAreDeferredAndDoNotChangeOutput() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5], volume: 0.5, baseSampleRate: 100)
        let baselineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)
        let baseline = renderer.render(PlaybackSongOfflineRenderRequest(song: baselineSong, orderIndex: 0, config: config, frames: 3))
        let deferredCases: [(UInt8, PlaybackSongSyntheticVolumeColumnCommand)] = [
            (0xA0, .setVibratoSpeed(amount: 0)),
            (0xB0, .vibrato(amount: 0))
        ]

        for (rawValue, command) in deferredCases {
            let song = makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: rawValue)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
            )
            let result = renderer.render(PlaybackSongOfflineRenderRequest(song: song, orderIndex: 0, config: config, frames: 3))
            let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

            XCTAssertEqual(result.block, baseline.block)
            XCTAssertEqual(mapping.volumeColumn.command, command)
            XCTAssertTrue(mapping.volumeColumn.deferred)
            XCTAssertTrue(mapping.hasIgnoredVolumeColumn)
            XCTAssertEqual(result.diagnostics.deferredCellFields.map(\.field), [.volumeColumn])
            XCTAssertEqual(result.diagnostics.deferredCellFields.first?.volumeColumnDiagnostic.command, command)
        }
    }

    func testPlaybackSongAdapterVolumeSlideDownChangesAmplitudeAndDiagnostics() throws {
        let sample = makePlaybackSample(pcm: [1, 1], volume: 1, baseSampleRate: 100)
        let baselineSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let slideSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x64)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let baseline = renderer.render(PlaybackSongOfflineRenderRequest(song: baselineSong, orderIndex: 0, config: config, frames: 2))
        let result = renderer.render(PlaybackSongOfflineRenderRequest(song: slideSong, orderIndex: 0, config: config, frames: 2))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)
        let volumeMapping = try XCTUnwrap(result.diagnostics.volumeColumnMappings.first)

        XCTAssertEqual(baseline.block.interleavedPCM, [1, 1])
        XCTAssertEqual(result.block.interleavedPCM, [0.9375, 0.9375])
        XCTAssertNotEqual(result.block, baseline.block)
        XCTAssertEqual(mapping.volumeColumn.command, .volumeSlideDown(amount: 4))
        XCTAssertEqual(mapping.volumeColumn.slideDirection, .volumeDown)
        XCTAssertEqual(mapping.volumeColumn.effectiveVolumeBefore, 64)
        XCTAssertEqual(mapping.volumeColumn.effectiveVolumeAfter, 60)
        XCTAssertEqual(mapping.volumeColumn.behavior, .rowLevelApproximation)
        XCTAssertTrue(mapping.volumeColumn.applied)
        XCTAssertFalse(mapping.hasIgnoredVolumeColumn)
        XCTAssertEqual(volumeMapping.syntheticRow, 0)
        XCTAssertEqual(volumeMapping.syntheticTick, 0)
    }

    func testPlaybackSongAdapterVolumeSlideUpAndSetVolumeCombineDeterministically() throws {
        let sample = makePlaybackSample(pcm: [1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0x30),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0x74)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [0, 0.5625, 0.5625])
        XCTAssertEqual(mapping.volumeColumn.command, .volumeSlideUp(amount: 4))
        XCTAssertEqual(mapping.volumeColumn.effectiveVolumeBefore, 32)
        XCTAssertEqual(mapping.volumeColumn.effectiveVolumeAfter, 36)
        XCTAssertEqual(mapping.effectiveVolumeValue, 36)
        XCTAssertEqual(result.diagnostics.volumeColumnMappings.map(\.volumeColumn.command), [
            .setVolume(value: 32),
            .volumeSlideUp(amount: 4)
        ])
    }

    func testPlaybackSongAdapterFineVolumeSlidesApplyAndClampSafely() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let fineDown = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x88)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let fineUp = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0x20),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0x98)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let clampDown = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0x10),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0x6F)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let clampUp = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x7F)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 1)

        let down = renderer.render(PlaybackSongOfflineRenderRequest(song: fineDown, orderIndex: 0, config: config, frames: 1))
        let up = renderer.render(PlaybackSongOfflineRenderRequest(song: fineUp, orderIndex: 0, config: config, frames: 2))
        let min = renderer.render(PlaybackSongOfflineRenderRequest(song: clampDown, orderIndex: 0, config: config, frames: 2))
        let max = renderer.render(PlaybackSongOfflineRenderRequest(song: clampUp, orderIndex: 0, config: config, frames: 1))
        let downMapping = try XCTUnwrap(down.diagnostics.eventMappings.first)
        let upMapping = try XCTUnwrap(up.diagnostics.eventMappings.first)
        let minMapping = try XCTUnwrap(min.diagnostics.eventMappings.first)
        let maxMapping = try XCTUnwrap(max.diagnostics.eventMappings.first)

        XCTAssertEqual(down.block.interleavedPCM, [0.875])
        XCTAssertEqual(downMapping.volumeColumn.command, .fineVolumeSlideDown(amount: 8))
        XCTAssertEqual(downMapping.volumeColumn.effectiveVolumeAfter, 56)
        XCTAssertEqual(up.block.interleavedPCM, [0, 0.375])
        XCTAssertEqual(upMapping.volumeColumn.command, .fineVolumeSlideUp(amount: 8))
        XCTAssertEqual(upMapping.volumeColumn.effectiveVolumeBefore, 16)
        XCTAssertEqual(upMapping.volumeColumn.effectiveVolumeAfter, 24)
        XCTAssertEqual(min.block.interleavedPCM, [0, 0])
        XCTAssertEqual(minMapping.volumeColumn.effectiveVolumeAfter, 0)
        XCTAssertEqual(max.block.interleavedPCM, [1])
        XCTAssertEqual(maxMapping.volumeColumn.effectiveVolumeAfter, 64)
    }

    func testPlaybackSongAdapterPanningSlidesChangeStereoBalanceAndClampSafely() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let leftSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0xDF)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let rightSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0xEF)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let clampLeftSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0xC0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0xDF)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let clampRightSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0xCF),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0xEF)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let setThenSlideSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0xC0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0xEF)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let renderer = PlaybackSongOfflineRenderer()
        let config = MixerRenderConfig(sampleRate: 100, channelCount: 2)

        let left = renderer.render(PlaybackSongOfflineRenderRequest(song: leftSong, orderIndex: 0, config: config, frames: 1))
        let right = renderer.render(PlaybackSongOfflineRenderRequest(song: rightSong, orderIndex: 0, config: config, frames: 1))
        let clampLeft = renderer.render(PlaybackSongOfflineRenderRequest(song: clampLeftSong, orderIndex: 0, config: config, frames: 2))
        let clampRight = renderer.render(PlaybackSongOfflineRenderRequest(song: clampRightSong, orderIndex: 0, config: config, frames: 2))
        let setThenSlide = renderer.render(PlaybackSongOfflineRenderRequest(song: setThenSlideSong, orderIndex: 0, config: config, frames: 2))
        let leftMapping = try XCTUnwrap(left.diagnostics.eventMappings.first)
        let rightMapping = try XCTUnwrap(right.diagnostics.eventMappings.first)
        let clampLeftMapping = try XCTUnwrap(clampLeft.diagnostics.eventMappings.first)
        let clampRightMapping = try XCTUnwrap(clampRight.diagnostics.eventMappings.first)
        let setThenSlideMapping = try XCTUnwrap(setThenSlide.diagnostics.eventMappings.first)

        XCTAssertEqual(left.block.interleavedPCM[0], 1, accuracy: 0.0001)
        XCTAssertEqual(left.block.interleavedPCM[1], 0.88235295, accuracy: 0.0001)
        XCTAssertEqual(leftMapping.volumeColumn.command, .panningSlideLeft(amount: 15))
        XCTAssertEqual(leftMapping.volumeColumn.slideDirection, .panningLeft)
        XCTAssertEqual(leftMapping.volumeColumn.effectivePanAfter ?? 0, -0.11764705, accuracy: 0.0001)
        XCTAssertEqual(right.block.interleavedPCM[0], 0.88235295, accuracy: 0.0001)
        XCTAssertEqual(right.block.interleavedPCM[1], 1, accuracy: 0.0001)
        XCTAssertEqual(rightMapping.volumeColumn.command, .panningSlideRight(amount: 15))
        XCTAssertEqual(rightMapping.volumeColumn.effectivePanAfter ?? 0, 0.11764705, accuracy: 0.0001)
        XCTAssertEqual(clampLeft.block.interleavedPCM, [0, 0, 1, 0])
        XCTAssertEqual(clampLeftMapping.volumeColumn.effectivePanAfter, -1)
        XCTAssertEqual(clampRight.block.interleavedPCM, [0, 0, 0, 1])
        XCTAssertEqual(clampRightMapping.volumeColumn.effectivePanAfter, 1)
        XCTAssertEqual(setThenSlide.block.interleavedPCM[2], 1, accuracy: 0.0001)
        XCTAssertEqual(setThenSlide.block.interleavedPCM[3], 0.11764705, accuracy: 0.0001)
        XCTAssertEqual(setThenSlideMapping.volumeColumn.effectivePanBefore, -1)
        XCTAssertEqual(setThenSlideMapping.volumeColumn.effectivePanAfter ?? 0, -0.88235295, accuracy: 0.0001)
        XCTAssertEqual(clampRight.diagnostics.deferredCellFields.map(\.field), [])
    }

    func testPlaybackSongAdapterVolumeColumnSlidesWorkWithFxxEnvelopeAndPitch() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [PlaybackEnvelopePoint(tick: 0, value: 32)])
        let sample = makePlaybackSample(pcm: [1, 1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0x30, effectType: 0x0F, effectParam: 0x03),
                    makePlaybackRow(index: 1, note: 61, instrument: 1, volumeColumn: 0x64)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6])
        XCTAssertEqual(result.diagnostics.timingChanges.first?.kind, .speed)
        XCTAssertEqual(mapping.volumeColumn.command, .volumeSlideDown(amount: 4))
        XCTAssertEqual(mapping.volumeColumn.effectiveVolumeBefore, 32)
        XCTAssertEqual(mapping.volumeColumn.effectiveVolumeAfter, 28)
        XCTAssertEqual(mapping.volumeEnvelopeStatus, .mapped)
        XCTAssertEqual(mapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 6) + [0.21875, 0.21875])
    }

    func testPlaybackSongAdapterLxxIsDetectedAndDiagnosesNoActiveVoice() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, effectType: 0x15, effectParam: 0x02),
            ]],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let command = try XCTUnwrap(plan.diagnostics.effectCommandDiagnostics.first)
        let lxx = try XCTUnwrap(plan.diagnostics.envelopePositionEffects.first)

        XCTAssertEqual(command.effectType, 0x15)
        XCTAssertEqual(command.decodedLabel, "Lxx set envelope position")
        XCTAssertEqual(command.status, .applied)
        XCTAssertEqual(plan.diagnostics.envelopePositionEffectCount, 1)
        XCTAssertEqual(lxx.status, .noActiveVoice)
        XCTAssertEqual(lxx.requestedPosition, 2)
        XCTAssertEqual(lxx.requestedPositionFrame, 2)
        XCTAssertNil(lxx.appliedPositionFrame)
        XCTAssertFalse(lxx.activeVoiceFound)
        XCTAssertEqual(plan.diagnostics.deferredCellFields.map(\.field), [])
    }

    func testPlaybackSongAdapterLxxSetsActiveVolumeEnvelopePosition() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 1, value: 32),
            PlaybackEnvelopePoint(tick: 2, value: 0),
        ])
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 100,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x15, effectParam: 0x02),
                makePlaybackRow(index: 2),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let lxx = try XCTUnwrap(result.diagnostics.envelopePositionEffects.first)

        XCTAssertEqual(lxx.status, .applied)
        XCTAssertTrue(lxx.activeVoiceFound)
        XCTAssertEqual(lxx.activeEventIndex, 0)
        XCTAssertEqual(lxx.requestedPosition, 2)
        XCTAssertEqual(lxx.requestedPositionFrame, 2)
        XCTAssertEqual(lxx.appliedPositionFrame, 2)
        XCTAssertFalse(lxx.clamped)
        XCTAssertEqual(result.block.interleavedPCM, [1, 0, 0])
    }

    func testPlaybackSongAdapterLxxClampsOutOfRangeEnvelopePosition() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 1, value: 32),
            PlaybackEnvelopePoint(tick: 2, value: 0),
        ])
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 100,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x15, effectParam: 0xFF),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))
        let lxx = try XCTUnwrap(result.diagnostics.envelopePositionEffects.first)

        XCTAssertEqual(lxx.status, .applied)
        XCTAssertEqual(lxx.requestedPosition, 255)
        XCTAssertEqual(lxx.requestedPositionFrame, 255)
        XCTAssertEqual(lxx.appliedPositionFrame, 2)
        XCTAssertTrue(lxx.clamped)
        XCTAssertEqual(result.block.interleavedPCM, [1, 0])
    }

    func testPlaybackSongAdapterLxxNoEnvelopeIsNoOp() throws {
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 100,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x15, effectParam: 0x01),
                makePlaybackRow(index: 2),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let lxx = try XCTUnwrap(result.diagnostics.envelopePositionEffects.first)

        XCTAssertEqual(lxx.status, .noEnvelope)
        XCTAssertTrue(lxx.activeVoiceFound)
        XCTAssertFalse(lxx.applied)
        XCTAssertTrue(lxx.ignoredAsNoOp)
        XCTAssertNil(lxx.appliedPositionFrame)
        XCTAssertEqual(result.block.interleavedPCM, [1, 1, 1])
    }

    func testPlaybackSongAdapterSameCellNoteAndLxxTriggersOnceAndAppliesPosition() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 1, value: 32),
            PlaybackEnvelopePoint(tick: 2, value: 0),
        ])
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 100,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x15, effectParam: 0x02),
                makePlaybackRow(index: 1),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        ))
        let lxx = try XCTUnwrap(result.diagnostics.envelopePositionEffects.first)

        XCTAssertEqual(result.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(lxx.status, .applied)
        XCTAssertEqual(lxx.activeEventIndex, 0)
        XCTAssertEqual(lxx.scheduledFrame, 0)
        XCTAssertEqual(lxx.appliedPositionFrame, 2)
        XCTAssertEqual(result.block.interleavedPCM, [0, 0])
    }

    func testPlaybackSongAdapterLxxSplitAndWindowedRenderRemainDeterministic() {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 1, value: 32),
            PlaybackEnvelopePoint(tick: 2, value: 0),
        ])
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 100,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x15, effectParam: 0x00),
                makePlaybackRow(index: 2),
                makePlaybackRow(index: 3),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        )
        let renderer = PlaybackSongOfflineRenderer()

        let full = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [1, 1, 2])
        let windowed = renderer.renderWindowed(request, windowRows: 2)

        XCTAssertFloatArrayEqual(full.block.interleavedPCM, [1, 1, 0.5, 0])
        XCTAssertEqual(split.block, full.block)
        XCTAssertEqual(windowed.block, full.block)
    }

    func testPlaybackSongAdapterVolumeColumnSplitAndResetRemainDeterministic() {
        let sample = makePlaybackSample(pcm: [1, 0.5, -0.5], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0x30),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0x64)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        )
        let renderer = PlaybackSongOfflineRenderer()

        let single = renderer.render(request)
        let repeated = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [1, 2, 2])
        let session = renderer.prepare(request)
        let resetFirst = session.render(frames: 5)
        _ = session.render(frames: 2)
        session.reset()
        let resetSecond = session.render(frames: 5)

        XCTAssertEqual(single.block.interleavedPCM, [0, 0.4375, 0.21875, -0.21875, 0])
        XCTAssertEqual(repeated.block, single.block)
        XCTAssertEqual(split.block, single.block)
        XCTAssertEqual(resetFirst, resetSecond)
        XCTAssertEqual(resetFirst, single.block)
    }

    func testPlaybackSongAdapterEmptyNoteVolumeColumnSetVolumeUpdatesActiveVoice() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, volumeColumn: 0x30),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let update = try XCTUnwrap(result.diagnostics.voiceStateUpdates.first { $0.hasEmptyNote && $0.commandSource == .volumeColumn })

        XCTAssertFloatArrayEqual(result.block.interleavedPCM, [1, 0.984375, 0.96875])
        XCTAssertEqual(update.scheduledFrame, 1)
        XCTAssertEqual(update.activeVoiceUpdated, true)
        XCTAssertEqual(update.effectiveVolumeBefore, 64)
        XCTAssertEqual(update.effectiveVolumeAfter, 32)
        XCTAssertEqual(update.gainBefore, 1)
        XCTAssertEqual(update.gainAfter, 0.5)
        if case .volumeColumn(.setVolume(value: 32)) = update.command {
            XCTAssertTrue(update.applied)
        } else {
            XCTFail("expected empty-note volume-column set-volume update")
        }
    }

    func testPlaybackSongAdapterEmptyNoteVolumeColumnSetPanningUpdatesActiveVoice() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, volumeColumn: 0xCF),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 2),
            frames: 3
        ))
        let update = try XCTUnwrap(result.diagnostics.voiceStateUpdates.first { $0.hasEmptyNote && $0.commandSource == .volumeColumn })

        XCTAssertFloatArrayEqual(result.block.interleavedPCM, [1, 1, 0.96875, 1, 0.9375, 1])
        XCTAssertEqual(update.activeVoiceUpdated, true)
        XCTAssertEqual(update.effectivePanBefore, 0)
        XCTAssertEqual(update.effectivePanAfter, 1)
        if case .volumeColumn(.setPanning(value: 255)) = update.command {
            XCTAssertTrue(update.applied)
        } else {
            XCTFail("expected empty-note volume-column set-panning update")
        }
    }

    func testPlaybackSongAdapterSameCell3xxVolumeColumnSetVolumeUpdatesActiveVoiceWithoutRetrigger() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 53, instrument: 1, volumeColumn: 0x30, effectType: 0x03, effectParam: 0xFF),
                    makePlaybackRow(index: 2),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let update = try XCTUnwrap(result.diagnostics.voiceStateUpdates.first { $0.rawVolumeColumn == 0x30 })
        let tonePortamento = try XCTUnwrap(result.diagnostics.tonePortamentoEffects.first)

        XCTAssertFloatArrayEqual(result.block.interleavedPCM, [1, 0.984375, 0.96875])
        XCTAssertEqual(result.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(result.plan.pattern.events.count, 1)
        XCTAssertEqual(tonePortamento.status, .applied)
        XCTAssertEqual(tonePortamento.targetNote, 53)
        XCTAssertEqual(update.scheduledFrame, 1)
        XCTAssertEqual(update.cellNote, 53)
        XCTAssertEqual(update.activeVoiceUpdated, true)
        XCTAssertEqual(update.activeEventIndex, 0)
        XCTAssertEqual(update.effectiveVolumeBefore, 64)
        XCTAssertEqual(update.effectiveVolumeAfter, 32)
        XCTAssertEqual(update.gainBefore, 1)
        XCTAssertEqual(update.gainAfter, 0.5)
        if case .volumeColumn(.setVolume(value: 32)) = update.command {
            XCTAssertTrue(update.applied)
        } else {
            XCTFail("expected same-cell 3xx volume-column set-volume update")
        }
    }

    func testPlaybackSongAdapterNoteTriggerRestoresInstrumentDefaultVolumeAfterAxySlide() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x11, effectType: 0x0A, effectParam: 0x0F),
                    makePlaybackRow(index: 1, note: 53, instrument: 1),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let axyUpdate = try XCTUnwrap(result.diagnostics.voiceStateUpdates.first { $0.effectType == 0x0A })
        let secondMapping = try XCTUnwrap(result.diagnostics.eventMappings.last)
        let secondEvent = try XCTUnwrap(result.plan.pattern.events.last)

        XCTAssertEqual(result.diagnostics.eventMappings.count, 2)
        XCTAssertEqual(result.plan.pattern.events.count, 2)
        XCTAssertEqual(axyUpdate.effectiveVolumeBefore, 1)
        XCTAssertEqual(axyUpdate.effectiveVolumeAfter, 0)
        XCTAssertEqual(secondMapping.source.rowIndex, 1)
        XCTAssertEqual(secondMapping.effectiveVolumeValue, 64)
        XCTAssertEqual(secondEvent.gain, 1)
    }

    func testPlaybackSongAdapterSameCell3xxRestoresInstrumentDefaultVolumeWithoutRetrigger() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x11, effectType: 0x0A, effectParam: 0x0F),
                    makePlaybackRow(index: 1, note: 53, instrument: 1, effectType: 0x03, effectParam: 0xFF),
                    makePlaybackRow(index: 2),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let update = try XCTUnwrap(result.diagnostics.voiceStateUpdates.first { $0.commandSource == .instrumentState })
        let tonePortamento = try XCTUnwrap(result.diagnostics.tonePortamentoEffects.first)

        XCTAssertEqual(result.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(result.plan.pattern.events.count, 1)
        XCTAssertEqual(tonePortamento.status, .applied)
        XCTAssertEqual(tonePortamento.targetNote, 53)
        XCTAssertEqual(tonePortamento.sameCellNote, true)
        XCTAssertEqual(tonePortamento.noteTriggerEventCreated, false)
        XCTAssertEqual(tonePortamento.voiceReplacement, false)
        XCTAssertEqual(tonePortamento.samplePositionReset, false)
        XCTAssertEqual(tonePortamento.instrumentStateUpdated, true)
        XCTAssertEqual(tonePortamento.instrumentDefaultVolumeApplied, true)
        XCTAssertEqual(tonePortamento.envelopeReset, false)
        XCTAssertEqual(tonePortamento.channelVolumeBefore, 0)
        XCTAssertEqual(tonePortamento.channelVolumeAfter, 64)
        XCTAssertEqual(tonePortamento.gainBefore, 0)
        XCTAssertEqual(tonePortamento.gainAfter, 1)
        XCTAssertEqual(tonePortamento.sampleSelectedBefore, 0)
        XCTAssertEqual(tonePortamento.sampleSelectedAfter, 0)
        XCTAssertEqual(tonePortamento.audibleTransientExpected, true)
        XCTAssertEqual(tonePortamento.cMixerReceivesNewVoice, false)
        XCTAssertEqual(tonePortamento.cMixerReceivesOnlyStateUpdates, true)
        XCTAssertEqual(update.command, .instrumentDefaultVolume(value: 64))
        XCTAssertEqual(update.scheduledFrame, 2)
        XCTAssertEqual(update.activeVoiceUpdated, true)
        XCTAssertEqual(update.activeEventIndex, 0)
        XCTAssertEqual(update.effectiveVolumeBefore, 0)
        XCTAssertEqual(update.effectiveVolumeAfter, 64)
        XCTAssertEqual(update.gainBefore, 0)
        XCTAssertEqual(update.gainAfter, 1)
    }

    func testPlaybackSongAdapterSameCell3xxVolumeColumnSetVolumeOverridesRestoredInstrumentDefault() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x11, effectType: 0x0A, effectParam: 0x0F),
                    makePlaybackRow(index: 1, note: 53, instrument: 1, volumeColumn: 0x30, effectType: 0x03, effectParam: 0xFF),
                    makePlaybackRow(index: 2),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let instrumentUpdate = try XCTUnwrap(result.diagnostics.voiceStateUpdates.first { $0.commandSource == .instrumentState })
        let volumeColumnUpdate = try XCTUnwrap(result.diagnostics.voiceStateUpdates.first { $0.rawVolumeColumn == 0x30 })
        let tonePortamento = try XCTUnwrap(result.diagnostics.tonePortamentoEffects.first)

        XCTAssertEqual(result.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(result.plan.pattern.events.count, 1)
        XCTAssertEqual(instrumentUpdate.effectiveVolumeBefore, 0)
        XCTAssertEqual(instrumentUpdate.effectiveVolumeAfter, 64)
        XCTAssertEqual(volumeColumnUpdate.effectiveVolumeBefore, 64)
        XCTAssertEqual(volumeColumnUpdate.effectiveVolumeAfter, 32)
        XCTAssertEqual(volumeColumnUpdate.gainBefore, 1)
        XCTAssertEqual(volumeColumnUpdate.gainAfter, 0.5)
        XCTAssertEqual(tonePortamento.channelVolumeBefore, 0)
        XCTAssertEqual(tonePortamento.channelVolumeAfter, 32)
        XCTAssertEqual(tonePortamento.gainBefore, 0)
        XCTAssertEqual(tonePortamento.gainAfter, 0.5)
        XCTAssertEqual(tonePortamento.instrumentDefaultVolumeApplied, true)
        XCTAssertEqual(tonePortamento.noteTriggerEventCreated, false)
        XCTAssertEqual(tonePortamento.samplePositionReset, false)
        if case .volumeColumn(.setVolume(value: 32)) = volumeColumnUpdate.command {
            XCTAssertTrue(volumeColumnUpdate.applied)
        } else {
            XCTFail("expected same-cell 3xx volume-column set-volume override")
        }
    }

    func testPlaybackSongAdapterSameCell3xxInstrumentSelectionUpdatesDefaultGainWithoutRetrigger() throws {
        let firstSample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [1, 1, 1], volume: 0.25, baseSampleRate: 100)
        let secondSample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 1, pcm: [0.5, 0.5, 0.5], volume: 0.5, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 53, instrument: 2, effectType: 0x03, effectParam: 0xFF),
                    makePlaybackRow(index: 2),
                ],
            ],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [firstSample]),
                2: PlaybackInstrument(index: 2, samples: [secondSample]),
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let update = try XCTUnwrap(result.diagnostics.voiceStateUpdates.first { $0.commandSource == .instrumentState })
        let tonePortamento = try XCTUnwrap(result.diagnostics.tonePortamentoEffects.first)

        XCTAssertEqual(result.diagnostics.eventMappings.count, 1)
        XCTAssertEqual(result.plan.pattern.events.count, 1)
        XCTAssertEqual(tonePortamento.instrumentIndexBefore, 1)
        XCTAssertEqual(tonePortamento.instrumentIndexAfter, 2)
        XCTAssertEqual(tonePortamento.sampleSelectedBefore, 0)
        XCTAssertEqual(tonePortamento.sampleSelectedAfter, 1)
        XCTAssertEqual(tonePortamento.instrumentDefaultVolumeApplied, true)
        XCTAssertEqual(tonePortamento.channelVolumeBefore, 64)
        XCTAssertEqual(tonePortamento.channelVolumeAfter, 64)
        XCTAssertEqual(tonePortamento.gainBefore, 0.25)
        XCTAssertEqual(tonePortamento.gainAfter, 0.5)
        XCTAssertEqual(tonePortamento.noteTriggerEventCreated, false)
        XCTAssertEqual(tonePortamento.samplePositionReset, false)
        XCTAssertEqual(update.activeVoiceUpdated, true)
        XCTAssertEqual(update.effectiveVolumeBefore, 64)
        XCTAssertEqual(update.effectiveVolumeAfter, 64)
        XCTAssertEqual(update.gainBefore, 0.25)
        XCTAssertEqual(update.gainAfter, 0.5)
    }

    func testPlaybackSongAdapterA0FSpeed3AppliesOnTicksAfterTick0() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x0F),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let event = try XCTUnwrap(plan.pattern.events.first)
        let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.first)
        let updates = plan.diagnostics.voiceStateUpdates.filter { $0.effectType == 0x0A }

        XCTAssertEqual(plan.pattern.events.count, 1)
        XCTAssertEqual(event.tick, 0)
        XCTAssertEqual(event.gain, 0.5)
        XCTAssertEqual(mapping.effectiveVolumeValue, 32)
        XCTAssertEqual(updates.map(\.syntheticTick), [1, 2])
        XCTAssertEqual(updates.map(\.scheduledFrame), [1, 2])
        XCTAssertEqual(updates.map(\.effectiveVolumeBefore), [32, 17])
        XCTAssertEqual(updates.map(\.effectiveVolumeAfter), [17, 2])
        XCTAssertTrue(updates.allSatisfy { $0.activeVoiceUpdated })
        XCTAssertTrue(updates.allSatisfy { $0.command == .axyVolumeSlide(up: 0, down: 15) })
        XCTAssertTrue(updates.allSatisfy { $0.behavior == .tickLevelAfterTick0 })
        XCTAssertTrue(updates.allSatisfy { $0.volumeSlideTick0Suppressed == true })
        XCTAssertFalse(updates.contains { $0.syntheticTick == 0 })
    }

    func testPlaybackSongAdapterA0FSpeed2AppliesOnceAfterTick0() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x0F),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let updates = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .voiceStateUpdates
            .filter { $0.effectType == 0x0A }

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.syntheticTick, 1)
        XCTAssertEqual(updates.first?.scheduledFrame, 1)
        XCTAssertEqual(updates.first?.effectiveVolumeBefore, 32)
        XCTAssertEqual(updates.first?.effectiveVolumeAfter, 17)
    }

    func testPlaybackSongAdapterA0FClampsAtVolumeZero() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x11, effectType: 0x0A, effectParam: 0x0F),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let update = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .voiceStateUpdates
            .first { $0.effectType == 0x0A })

        XCTAssertEqual(update.effectiveVolumeBefore, 1)
        XCTAssertEqual(update.effectiveVolumeAfter, 0)
        XCTAssertEqual(update.volumeSlideClamped, true)
    }

    func testPlaybackSongAdapterAF0ClampsAtVolume64() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x4F, effectType: 0x0A, effectParam: 0xF0),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let update = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .voiceStateUpdates
            .first { $0.effectType == 0x0A })

        XCTAssertEqual(update.effectiveVolumeBefore, 63)
        XCTAssertEqual(update.effectiveVolumeAfter, 64)
        XCTAssertEqual(update.volumeSlideClamped, true)
    }

    func testPlaybackSongAdapterVolumeColumnSetVolumeThenAxyOrderingIsDeterministic() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1, 1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x0F),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let updates = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100).diagnostics.voiceStateUpdates
        let volumeColumn = try XCTUnwrap(updates.first { $0.rawVolumeColumn == 0x30 })
        let axy = updates.filter { $0.effectType == 0x0A }

        XCTAssertEqual(volumeColumn.syntheticTick, 0)
        XCTAssertEqual(volumeColumn.scheduledFrame, 3)
        XCTAssertEqual(volumeColumn.effectiveVolumeBefore, 64)
        XCTAssertEqual(volumeColumn.effectiveVolumeAfter, 32)
        XCTAssertEqual(axy.map(\.syntheticTick), [1, 2])
        XCTAssertEqual(axy.map(\.scheduledFrame), [4, 5])
        XCTAssertEqual(axy.map(\.effectiveVolumeBefore), [32, 17])
        XCTAssertEqual(axy.map(\.effectiveVolumeAfter), [17, 2])
    }

    func testPlaybackSongAdapterA2FMixedNibbleUsesMikModObservedUpNibblePrecedence() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x2F),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let update = try XCTUnwrap(PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .voiceStateUpdates
            .first { $0.effectType == 0x0A })

        XCTAssertEqual(update.command, .axyVolumeSlide(up: 2, down: 0))
        XCTAssertEqual(update.effectiveVolumeBefore, 32)
        XCTAssertEqual(update.effectiveVolumeAfter, 34)
        XCTAssertEqual(update.volumeSlideRawUpNibble, 2)
        XCTAssertEqual(update.volumeSlideRawDownNibble, 15)
        XCTAssertEqual(update.volumeSlideBothNibblesNonzero, true)
        XCTAssertEqual(update.volumeSlidePolicy, "up_nibble_precedence_mikmod_observed")
    }

    func testPlaybackSongAdapterA00RemainsNoOpWithoutVolumeSlideMemory() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x00),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let update = try XCTUnwrap(plan.diagnostics.voiceStateUpdates.first { $0.effectType == 0x0A })

        XCTAssertEqual(update.status, .ignoredNoOp)
        XCTAssertEqual(update.syntheticTick, 0)
        XCTAssertEqual(update.command, .axyVolumeSlide(up: 0, down: 0))
        XCTAssertEqual(update.effectiveVolumeBefore, 32)
        XCTAssertEqual(update.effectiveVolumeAfter, 32)
        XCTAssertEqual(update.volumeSlidePolicy, "a00_no_volume_slide_memory_no_op")
        XCTAssertEqual(update.effectMemoryMissing, true)
        XCTAssertEqual(update.effectMemoryDeferred, true)
        XCTAssertEqual(update.memoryUnavailableReason, "missing_axy_volume_slide_memory")
        XCTAssertFalse(update.activeVoiceUpdated)
    }

    func testPlaybackSongAdapterA00ReusesPriorAxyVolumeSlideMemory() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 32), volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x01),
                    makePlaybackRow(index: 1, effectType: 0x0A, effectParam: 0x00),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let updates = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .voiceStateUpdates
            .filter { $0.effectType == 0x0A }
        let memoryUpdates = updates.filter { $0.effectParam == 0 }

        XCTAssertEqual(updates.map(\.syntheticTick), [1, 2, 1, 2])
        XCTAssertEqual(memoryUpdates.map(\.scheduledFrame), [4, 5])
        XCTAssertTrue(memoryUpdates.allSatisfy(\.applied))
        XCTAssertTrue(memoryUpdates.allSatisfy(\.activeVoiceUpdated))
        XCTAssertTrue(memoryUpdates.allSatisfy(\.effectMemoryReused))
        XCTAssertTrue(memoryUpdates.allSatisfy { $0.command == .axyVolumeSlide(up: 0, down: 1) })
        XCTAssertEqual(memoryUpdates.map(\.effectiveVolumeBefore), [30, 29])
        XCTAssertEqual(memoryUpdates.map(\.effectiveVolumeAfter), [29, 28])
        XCTAssertEqual(memoryUpdates.first?.memorySource?.source.rowIndex, 0)
        XCTAssertEqual(memoryUpdates.first?.memorySource?.effectType, 0x0A)
        XCTAssertEqual(memoryUpdates.first?.memorySource?.effectParam, 0x01)
    }

    func testPlaybackSongAdapterA00VolumeSlideMemoryIsPerChannel() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 32), volume: 1, baseSampleRate: 100)
        let rows = [
            PlaybackRow(index: 0, cells: [
                PlaybackCell(note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x01),
                PlaybackCell(note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0, effectParam: 0),
            ]),
            PlaybackRow(index: 1, cells: [
                PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0A, effectParam: 0x00),
                PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0A, effectParam: 0x00),
            ]),
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )

        let updates = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .voiceStateUpdates
            .filter { $0.effectType == 0x0A && $0.effectParam == 0 }
        let channel0 = try XCTUnwrap(updates.first { $0.channelIndex == 0 })
        let channel1 = try XCTUnwrap(updates.first { $0.channelIndex == 1 })

        XCTAssertEqual(channel0.status, .applied)
        XCTAssertEqual(channel0.effectMemoryReused, true)
        XCTAssertEqual(channel0.command, .axyVolumeSlide(up: 0, down: 1))
        XCTAssertEqual(channel1.status, .ignoredNoOp)
        XCTAssertEqual(channel1.effectMemoryMissing, true)
        XCTAssertEqual(channel1.memoryUnavailableReason, "missing_axy_volume_slide_memory")
    }

    func testPlaybackSongAdapterSameCellNoteA00TriggersOnceAndReusesMemoryAfterTick0() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 32), volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30, effectType: 0x0A, effectParam: 0x01),
                    makePlaybackRow(index: 1, note: 52, instrument: 1, effectType: 0x0A, effectParam: 0x00),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let row1Events = plan.diagnostics.eventMappings.filter { $0.source.rowIndex == 1 }
        let memoryUpdates = plan.diagnostics.voiceStateUpdates.filter {
            $0.effectType == 0x0A && $0.effectParam == 0
        }

        XCTAssertEqual(row1Events.count, 1)
        XCTAssertEqual(row1Events.first?.note, 52)
        XCTAssertEqual(row1Events.first?.syntheticTick, 0)
        XCTAssertEqual(row1Events.first?.effectiveVolumeValue, 30)
        XCTAssertEqual(memoryUpdates.map(\.syntheticTick), [1, 2])
        XCTAssertEqual(memoryUpdates.map(\.effectiveVolumeBefore), [30, 29])
        XCTAssertEqual(memoryUpdates.map(\.effectiveVolumeAfter), [29, 28])
        XCTAssertTrue(memoryUpdates.allSatisfy(\.effectMemoryReused))
        XCTAssertEqual(Set(memoryUpdates.compactMap(\.activeEventIndex)), [1])
    }

    func testPlaybackSongAdapter500ReusesSharedAxyStyleVolumeSlideMemory() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 32), volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30),
                    makePlaybackRow(index: 1, effectType: 0x05, effectParam: 0x02),
                    makePlaybackRow(index: 2, effectType: 0x05, effectParam: 0x00),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )

        let updates = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
            .diagnostics
            .voiceStateUpdates
            .filter { update in
                if case .effect5xyVolumeSlide = update.command {
                    return true
                }
                return false
            }
        let memoryUpdates = updates.filter { $0.effectParam == 0 }

        XCTAssertEqual(updates.count, 4)
        XCTAssertEqual(memoryUpdates.map(\.syntheticTick), [1, 2])
        XCTAssertTrue(memoryUpdates.allSatisfy(\.effectMemoryReused))
        XCTAssertTrue(memoryUpdates.allSatisfy { $0.command == .effect5xyVolumeSlide(up: 0, down: 2) })
        XCTAssertEqual(memoryUpdates.first?.memorySource?.effectType, 0x05)
        XCTAssertEqual(memoryUpdates.first?.memorySource?.effectParam, 0x02)
    }

    func testPlaybackSongAdapterAxyWindowedAndSplitRendersPreserveVolumeSlideMemory() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 32), volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30),
                    makePlaybackRow(index: 1, effectType: 0x0A, effectParam: 0x01),
                    makePlaybackRow(index: 2, effectType: 0x0A, effectParam: 0x00),
                    makePlaybackRow(index: 3),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 12
        )
        let renderer = PlaybackSongOfflineRenderer()

        let single = renderer.render(request)
        let repeated = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [3, 3, 6])
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(repeated.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(split.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, single.block.interleavedPCM)
    }

    func testPlaybackSongAdapterCxxAnd8xxUpdateActiveVoiceState() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], volume: 1, baseSampleRate: 100)
        let volumeSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: 0x0C, effectParam: 0x20),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let panSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: 0x08, effectParam: 0xFF),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let renderer = PlaybackSongOfflineRenderer()

        let volume = renderer.render(PlaybackSongOfflineRenderRequest(
            song: volumeSong,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let pan = renderer.render(PlaybackSongOfflineRenderRequest(
            song: panSong,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 2),
            frames: 3
        ))
        let cxxUpdate = try XCTUnwrap(volume.diagnostics.voiceStateUpdates.first { $0.effectType == 0x0C })
        let panUpdate = try XCTUnwrap(pan.diagnostics.voiceStateUpdates.first { $0.effectType == 0x08 })

        XCTAssertFloatArrayEqual(volume.block.interleavedPCM, [1, 0.984375, 0.96875])
        XCTAssertEqual(cxxUpdate.activeVoiceUpdated, true)
        XCTAssertEqual(cxxUpdate.effectiveVolumeBefore, 64)
        XCTAssertEqual(cxxUpdate.effectiveVolumeAfter, 32)
        XCTAssertFloatArrayEqual(pan.block.interleavedPCM, [1, 1, 0.96875, 1, 0.9375, 1])
        XCTAssertEqual(panUpdate.activeVoiceUpdated, true)
        XCTAssertEqual(panUpdate.effectivePanBefore, 0)
        XCTAssertEqual(panUpdate.effectivePanAfter, 1)
    }

    func testPlaybackSongAdapterStateUpdatesFeedSubsequentNoteTriggers() throws {
        let sample = makePlaybackSample(pcm: [1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, volumeColumn: 0x30, effectType: 0x08, effectParam: 0xFF),
                    makePlaybackRow(index: 1, note: 49, instrument: 1),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 2),
            frames: 3
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [0, 0, 0, 0.5, 0, 0.5])
        XCTAssertEqual(mapping.effectiveVolumeValue, 32)
        XCTAssertEqual(mapping.effectivePan, 1)
        XCTAssertTrue(result.diagnostics.voiceStateUpdates.allSatisfy { !$0.activeVoiceUpdated })
    }

    func testPlaybackSongAdapterWindowedCarryoverAppliesActiveVolumeUpdatesAtBoundary() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, volumeColumn: 0x30),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(defaultRender.block.interleavedPCM, [1, 0.984375, 0.96875])
        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertEqual(windowed.windowedRenderSummary?.windowRows, 1)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedVoices ?? 0, 0)
        XCTAssertEqual(windowed.diagnostics.voiceStateUpdates.first?.activeVoiceUpdated, true)
    }

    func testPlaybackSongAdapterSameChannelRepeatedNotesUseBoundedReplacementRamp() throws {
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 6_400,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 49, instrument: 1),
                    makePlaybackRow(index: 2, note: 49, instrument: 1),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 6_400, channelCount: 1),
            frames: 160
        ))
        let lifetime = result.sameChannelVoiceLifetime

        XCTAssertEqual(lifetime.sameChannelReplacementStartCount, 2)
        XCTAssertEqual(lifetime.sameChannelReplacementCompletionCount, 2)
        XCTAssertEqual(lifetime.sameChannelVoiceOverlapFrames, CSoftwareMixer.replacementStopRampFrameCount * 2)
        XCTAssertEqual(lifetime.sameChannelActiveVoiceCount, 2)
        XCTAssertEqual(lifetime.maxVoicesPerSourceChannel[0], 2)
        XCTAssertEqual(lifetime.loadedVoicesBySourceChannel[0], 3)
        XCTAssertEqual(lifetime.activeVoicesBySourceChannel[0], 1)
        XCTAssertEqual(
            lifetime.oldVoiceKeptReasonCounts[PlaybackSongSameChannelVoiceLifetimeDiagnostics.oldVoiceKeptReasonReplacementRamp],
            2
        )
        XCTAssertEqual(result.block.interleavedPCM[63], 1, accuracy: 0.000_001)
        XCTAssertEqual(result.block.interleavedPCM[64], 1.96875, accuracy: 0.000_001)
        XCTAssertEqual(result.block.interleavedPCM[94], 1.03125, accuracy: 0.000_001)
        XCTAssertEqual(result.block.interleavedPCM[95], 1, accuracy: 0.000_001)
        XCTAssertEqual(result.block.interleavedPCM[128], 1.96875, accuracy: 0.000_001)
    }

    func testPlaybackSongAdapterSameChannelReplacementWindowedRenderMatchesFullRender() throws {
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 6_400,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 49, instrument: 1),
                    makePlaybackRow(index: 2, note: 49, instrument: 1),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 6_400, channelCount: 1),
            frames: 160
        )
        let renderer = PlaybackSongOfflineRenderer()

        let full = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, full.block.interleavedPCM)
        XCTAssertEqual(windowed.sameChannelVoiceLifetime.sameChannelReplacementStartCount, 2)
        XCTAssertEqual(windowed.sameChannelVoiceLifetime.windowBoundaryPruneCount, 0)
        XCTAssertEqual(windowed.windowedRenderSummary?.totalCarriedVoices, 2)
    }

    func testPlaybackSongAdapterEnvelopeVoicesDoNotSurviveSameChannelReplacementPastRamp() throws {
        let envelope = makePlaybackVolumeEnvelope(
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 64),
            ],
            sustainPointIndex: 0,
            typeFlags: 0x03
        )
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 6_400,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 49, instrument: 1),
                    makePlaybackRow(index: 2),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 6_400, channelCount: 1),
            frames: 128
        ))

        XCTAssertEqual(result.sameChannelVoiceLifetime.sameChannelReplacementStartCount, 1)
        XCTAssertEqual(result.sameChannelVoiceLifetime.sameChannelReplacementCompletionCount, 1)
        XCTAssertEqual(result.block.interleavedPCM[64], 1.96875, accuracy: 0.000_001)
        XCTAssertEqual(result.block.interleavedPCM[95], 1, accuracy: 0.000_001)
        XCTAssertEqual(result.block.interleavedPCM[127], 1, accuracy: 0.000_001)
    }

    func testPlaybackSongAdapterSameCell3xxDoesNotReplaceUntilPlainNote() throws {
        let sample = makePlaybackSample(
            pcm: [1],
            baseSampleRate: 6_400,
            loopStart: 0,
            loopLength: 1,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 53, instrument: 1, effectType: 0x03, effectParam: 0x04),
                    makePlaybackRow(index: 2, note: 55, instrument: 1),
                ],
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 6_400, channelCount: 1),
            frames: 160
        ))
        let runtimePlan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 6_400)
        let tonePortamento = try XCTUnwrap(result.diagnostics.tonePortamentoEffects.first)

        XCTAssertEqual(result.diagnostics.eventMappings.map(\.source.rowIndex), [0, 2])
        XCTAssertFalse(tonePortamento.noteTriggerEventCreated)
        XCTAssertFalse(tonePortamento.cMixerReceivesNewVoice)
        XCTAssertEqual(result.sameChannelVoiceLifetime.sameChannelReplacementStartCount, 1)
        XCTAssertEqual(runtimePlan.events.filter { $0.categories.contains("replacement") }.count, 1)
        XCTAssertEqual(runtimePlan.events.filter { $0.categories.contains("replacement") }.count, result.sameChannelVoiceLifetime.sameChannelReplacementStartCount)
        XCTAssertEqual(result.block.interleavedPCM[127], 1, accuracy: 0.000_001)
        XCTAssertEqual(result.block.interleavedPCM[128], 1.96875, accuracy: 0.000_001)
    }

    func testPlaybackSongAdapterWindowedCarryoverPreservesActiveGainRampState() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, volumeColumn: 0x30),
                    makePlaybackRow(index: 2),
                    makePlaybackRow(index: 3)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 2)

        XCTAssertFloatArrayEqual(defaultRender.block.interleavedPCM, [1, 0.984375, 0.96875, 0.953125])
        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedVoices ?? 0, 0)
    }

    func testPlaybackSongAdapterAxyAndHxyGlobalVolumeSlidesUpdateActiveVoiceGain() throws {
        let sample = makePlaybackSample(pcm: Array(repeating: Float(1), count: 8), volume: 1, baseSampleRate: 100)
        let axySong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: 0x0A, effectParam: 0x04),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )
        let hxySong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: 0x11, effectParam: 0x04),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let renderer = PlaybackSongOfflineRenderer()

        let axy = renderer.render(PlaybackSongOfflineRenderRequest(
            song: axySong,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let hxy = renderer.render(PlaybackSongOfflineRenderRequest(
            song: hxySong,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let axyUpdates = axy.diagnostics.voiceStateUpdates.filter { $0.effectType == 0x0A }
        let hxyUpdate = try XCTUnwrap(hxy.diagnostics.voiceStateUpdates.first { $0.effectType == 0x11 })

        XCTAssertEqual(axyUpdates.count, 2)
        XCTAssertEqual(axyUpdates.map(\.syntheticTick), [1, 2])
        XCTAssertEqual(axyUpdates.map(\.scheduledFrame), [4, 5])
        XCTAssertTrue(axyUpdates.allSatisfy(\.activeVoiceUpdated))
        XCTAssertEqual(axyUpdates.map(\.effectiveVolumeBefore), [64, 60])
        XCTAssertEqual(axyUpdates.map(\.effectiveVolumeAfter), [60, 56])
        XCTAssertTrue(axyUpdates.allSatisfy { $0.behavior == .tickLevelAfterTick0 })
        XCTAssertFloatArrayEqual(hxy.block.interleavedPCM, [1, 0.9980469, 0.99609375])
        XCTAssertTrue(hxyUpdate.applied)
        XCTAssertEqual(hxyUpdate.activeVoiceUpdated, true)
        XCTAssertEqual(hxyUpdate.globalVolumeBefore, 64)
        XCTAssertEqual(hxyUpdate.globalVolumeAfter, 60)
        XCTAssertEqual(hxyUpdate.globalVolumeSlideDirection, .down)
        XCTAssertEqual(hxyUpdate.globalVolumeSlideAmount, 4)
        XCTAssertEqual(hxyUpdate.gainBefore, 1)
        XCTAssertEqual(hxyUpdate.gainAfter, 0.9375)
        XCTAssertFalse(hxy.diagnostics.deferredCellFields.contains { $0.effectType == 0x11 })
    }

    func testPlaybackSongAdapterHxyGlobalVolumeSlideUpRaisesGainAfterPriorDownSlide() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: 0x11, effectParam: 0x04),
                    makePlaybackRow(index: 2, effectType: 0x11, effectParam: 0x20),
                    makePlaybackRow(index: 3)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        ))
        let hxyUpdates = result.diagnostics.voiceStateUpdates.filter { $0.effectType == 0x11 }

        XCTAssertEqual(hxyUpdates.count, 2)
        XCTAssertEqual(hxyUpdates[0].globalVolumeAfter, 60)
        XCTAssertEqual(hxyUpdates[0].globalVolumeSlideDirection, .down)
        XCTAssertEqual(hxyUpdates[1].globalVolumeBefore, 60)
        XCTAssertEqual(hxyUpdates[1].globalVolumeAfter, 62)
        XCTAssertEqual(hxyUpdates[1].globalVolumeSlideDirection, .up)
        XCTAssertGreaterThan(hxyUpdates[1].gainAfter ?? 0, hxyUpdates[0].gainAfter ?? 1)
    }

    func testPlaybackSongAdapterExpectedGainFormulaIncludesSampleChannelGlobalAndEnvelope() throws {
        let envelope = makePlaybackVolumeEnvelope(points: [
            PlaybackEnvelopePoint(tick: 0, value: 32)
        ])
        let sample = makePlaybackSample(pcm: [1, 1, 1, 1], volume: 0.5, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x10, effectParam: 0x20),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0x30),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        ))
        let event = try XCTUnwrap(result.plan.pattern.events.first)
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(event.gain, 0.125, accuracy: 0.000_001)
        XCTAssertEqual(mapping.effectiveVolumeValue, 32)
        XCTAssertEqual(mapping.effectiveGlobalVolumeValue, 32)
        XCTAssertEqual(mapping.effectiveGlobalVolumeMultiplier, 0.5, accuracy: 0.000_001)
        XCTAssertFloatArrayEqual(result.block.interleavedPCM, [0, 0.0625, 0.0625])
    }

    func testPlaybackSongAdapterGainFormulaNormalizesSampleChannelAndGlobalVolumes() throws {
        func render(
            sampleVolume: Float = 1,
            rows: [PlaybackRow],
            frames: Int
        ) -> PlaybackSongOfflineRenderResult {
            let sample = makePlaybackSample(pcm: [1, 1, 1, 1], volume: sampleVolume, baseSampleRate: 100)
            let song = makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: rows],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
                initialTiming: PlaybackTiming(speed: 1, bpm: 250)
            )
            return PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
                song: song,
                orderIndex: 0,
                config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
                frames: frames
            ))
        }

        let full = render(rows: [makePlaybackRow(index: 0, note: 49, instrument: 1)], frames: 2)
        let halfSample = render(
            sampleVolume: 0.5,
            rows: [makePlaybackRow(index: 0, note: 49, instrument: 1)],
            frames: 2
        )
        let halfChannel = render(rows: [
            makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x30)
        ], frames: 2)
        let halfGlobal = render(rows: [
            makePlaybackRow(index: 0, effectType: 0x10, effectParam: 0x20),
            makePlaybackRow(index: 1, note: 49, instrument: 1)
        ], frames: 3)

        XCTAssertEqual(try XCTUnwrap(full.plan.pattern.events.first).gain, 1, accuracy: 0.000_001)
        XCTAssertFloatArrayEqual(full.block.interleavedPCM, [1, 1])
        XCTAssertEqual(try XCTUnwrap(halfSample.plan.pattern.events.first).gain, 0.5, accuracy: 0.000_001)
        XCTAssertFloatArrayEqual(halfSample.block.interleavedPCM, [0.5, 0.5])
        XCTAssertEqual(try XCTUnwrap(halfChannel.plan.pattern.events.first).gain, 0.5, accuracy: 0.000_001)
        XCTAssertFloatArrayEqual(halfChannel.block.interleavedPCM, [0.5, 0.5])
        XCTAssertEqual(try XCTUnwrap(halfGlobal.plan.pattern.events.first).gain, 0.5, accuracy: 0.000_001)
        XCTAssertFloatArrayEqual(halfGlobal.block.interleavedPCM, [0, 0.5, 0.5])
    }

    func testPlaybackSongAdapterGxxSetGlobalVolumeUpdatesActiveVoiceAndFutureNotes() throws {
        let sample = makePlaybackSample(pcm: [1, 1, 1, 1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, effectType: 0x10, effectParam: 0x20),
                    makePlaybackRow(index: 2, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let gxxUpdate = try XCTUnwrap(result.diagnostics.voiceStateUpdates.first { $0.effectType == 0x10 })

        XCTAssertTrue(gxxUpdate.applied)
        XCTAssertEqual(gxxUpdate.command.label, "Gxx set global volume")
        XCTAssertEqual(gxxUpdate.activeVoiceUpdated, true)
        XCTAssertEqual(gxxUpdate.globalVolumeBefore, 64)
        XCTAssertEqual(gxxUpdate.globalVolumeAfter, 32)
        XCTAssertEqual(try XCTUnwrap(gxxUpdate.globalVolumeMultiplierBefore), 1, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(gxxUpdate.globalVolumeMultiplierAfter), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(gxxUpdate.gainBefore, 1)
        XCTAssertEqual(gxxUpdate.gainAfter, 0.5)
        XCTAssertEqual(result.pattern.events.map(\.gain), [1, 0.5])
        XCTAssertEqual(result.diagnostics.eventMappings.map(\.effectiveGlobalVolumeValue), [64, 32])
        XCTAssertFalse(result.diagnostics.deferredCellFields.contains { $0.effectType == 0x10 })
    }

    func testPlaybackSongAdapterHxyClampsAndDiagnosesNoOpAndBothNibblePolicy() throws {
        let rows = [
            makePlaybackRow(index: 0, effectType: 0x11, effectParam: 0x10),
            makePlaybackRow(index: 1, effectType: 0x11, effectParam: 0x00),
            makePlaybackRow(index: 2, effectType: 0x11, effectParam: 0x25),
            makePlaybackRow(index: 3, effectType: 0x11, effectParam: 0x0F),
            makePlaybackRow(index: 4, effectType: 0x11, effectParam: 0x0F),
            makePlaybackRow(index: 5, effectType: 0x11, effectParam: 0x0F),
            makePlaybackRow(index: 6, effectType: 0x11, effectParam: 0x0F),
            makePlaybackRow(index: 7, effectType: 0x11, effectParam: 0x0F),
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 8
        ))
        let hxyUpdates = result.diagnostics.voiceStateUpdates.filter { $0.effectType == 0x11 }
        let h00 = try XCTUnwrap(hxyUpdates.first { $0.effectParam == 0x00 })
        let bothNibble = try XCTUnwrap(hxyUpdates.first { $0.effectParam == 0x25 })
        let maxClamp = try XCTUnwrap(hxyUpdates.first { $0.effectParam == 0x10 })
        let minClamp = try XCTUnwrap(hxyUpdates.last)

        XCTAssertEqual(hxyUpdates.count, 8)
        XCTAssertEqual(maxClamp.globalVolumeBefore, 64)
        XCTAssertEqual(maxClamp.globalVolumeAfter, 64)
        XCTAssertEqual(maxClamp.globalVolumeSlideClamped, true)
        XCTAssertTrue(h00.ignoredAsNoOp)
        XCTAssertEqual(h00.globalVolumeSlideDirection, PlaybackSongSyntheticGlobalVolumeSlideDirection.none)
        XCTAssertEqual(h00.globalVolumeSlidePolicy, "h00_no_effect_memory_no_op")
        XCTAssertTrue(bothNibble.applied)
        XCTAssertEqual(bothNibble.globalVolumeBefore, 64)
        XCTAssertEqual(bothNibble.globalVolumeAfter, 64)
        XCTAssertEqual(bothNibble.globalVolumeSlideDirection, .up)
        XCTAssertEqual(bothNibble.globalVolumeSlideBothNibblesNonzero, true)
        XCTAssertEqual(bothNibble.globalVolumeSlidePolicy, "up_nibble_precedence_matches_runtime")
        XCTAssertEqual(minClamp.globalVolumeAfter, 0)
        XCTAssertEqual(minClamp.globalVolumeSlideClamped, true)
    }

    func testPlaybackSongAdapterHxyAffectsSubsequentNotesAndWindowedRenders() throws {
        let sample = makePlaybackSample(pcm: [1], volume: 1, baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x11, effectParam: 0x04),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        )
        let renderer = PlaybackSongOfflineRenderer()

        let defaultRender = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)
        let mapping = try XCTUnwrap(defaultRender.diagnostics.eventMappings.first)

        XCTAssertFloatArrayEqual(defaultRender.block.interleavedPCM, [0, 0.9375])
        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, defaultRender.block.interleavedPCM)
        XCTAssertEqual(mapping.effectiveGlobalVolumeValue, 60)
        XCTAssertEqual(mapping.effectiveGlobalVolumeMultiplier, 0.9375)
        XCTAssertEqual(windowed.windowedRenderSummary?.windowRows, 1)
    }

    func testTraversalD00BreaksToRowZeroOfNextOrder() {
        let song = makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0D, effectParam: 0x00)],
                3: [makePlaybackRow(index: 0), makePlaybackRow(index: 1)]
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 0, orderCount: 2, sampleRate: 100)

        XCTAssertEqual(plan.diagnostics.rowMappings.map(\.source), [
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0),
            PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 0),
            PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 1),
        ])
        XCTAssertEqual(plan.diagnostics.traversalDiagnostics.first?.status, .applied)
        XCTAssertEqual(plan.diagnostics.traversalDiagnostics.first?.targetRowIndex, 0)
    }

    func testTraversalDxxUsesXMBCDRowTargetAndDiagnosesInvalidBCD() throws {
        let nextRows = (0..<40).map { makePlaybackRow(index: $0) }
        let validSong = makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0D, effectParam: 0x31)],
                3: nextRows
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let invalidSong = makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0D, effectParam: 0xFA)],
                3: nextRows
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let valid = PlaybackSongSyntheticAdapter.adapt(validSong, startOrderIndex: 0, orderCount: 2, sampleRate: 100)
        let invalid = PlaybackSongSyntheticAdapter.adapt(invalidSong, startOrderIndex: 0, orderCount: 2, sampleRate: 100)
        let invalidTraversal = try XCTUnwrap(invalid.diagnostics.traversalDiagnostics.first)

        XCTAssertEqual(valid.diagnostics.rowMappings[1].source, PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 31))
        XCTAssertEqual(valid.diagnostics.traversalDiagnostics.first?.targetRowIndex, 31)
        XCTAssertEqual(invalidTraversal.status, .invalidTarget)
        XCTAssertEqual(invalidTraversal.policy, "invalid_bcd_clamped_to_row_zero")
        XCTAssertEqual(invalid.diagnostics.rowMappings[1].source, PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 0))
    }

    func testTraversalBxxJumpsToTargetOrderRowZeroAndOutOfRangeStopsSafely() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let jumpSong = makePlaybackSong(
            orderPatternIndices: [2, 3, 4],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0B, effectParam: 0x02)],
                3: [makePlaybackRow(index: 0, note: 49, instrument: 1)],
                4: [makePlaybackRow(index: 0, note: 49, instrument: 1)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let outOfRangeSong = makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0B, effectParam: 0x7F)],
                3: [makePlaybackRow(index: 0, note: 49, instrument: 1)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let jump = PlaybackSongSyntheticAdapter.adapt(jumpSong, startOrderIndex: 0, orderCount: 3, sampleRate: 100)
        let outOfRange = PlaybackSongSyntheticAdapter.adapt(outOfRangeSong, startOrderIndex: 0, orderCount: 2, sampleRate: 100)
        let outOfRangeTraversal = try XCTUnwrap(outOfRange.diagnostics.traversalDiagnostics.first)

        XCTAssertEqual(jump.diagnostics.rowMappings.map(\.source), [
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0),
            PlaybackPosition(orderIndex: 2, patternIndex: 4, rowIndex: 0),
        ])
        XCTAssertEqual(jump.diagnostics.traversalDiagnostics.first?.status, .applied)
        XCTAssertEqual(jump.diagnostics.traversalDiagnostics.first?.targetOrderIndex, 2)
        XCTAssertEqual(jump.diagnostics.traversalDiagnostics.first?.targetRowIndex, 0)
        XCTAssertEqual(outOfRangeTraversal.status, .outOfRange)
        XCTAssertEqual(outOfRange.diagnostics.traversalStopReason, .outOfRange)
        XCTAssertEqual(outOfRange.diagnostics.rowMappings.map(\.source), [
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0),
        ])
    }

    func testTraversalCombinedBxxDxxUsesJumpOrderAndBreakRow() throws {
        let row = PlaybackRow(index: 0, cells: [
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0B, effectParam: 0x02),
            PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0x0D, effectParam: 0x02),
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [2, 3, 4],
            patternRowsByIndex: [
                2: [row],
                3: [makePlaybackRow(index: 0)],
                4: (0..<4).map { makePlaybackRow(index: $0) }
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 0, orderCount: 3, sampleRate: 100)
        let bxx = try XCTUnwrap(plan.diagnostics.traversalDiagnostics.first { $0.kind == .bxxPositionJump })
        let dxx = try XCTUnwrap(plan.diagnostics.traversalDiagnostics.first { $0.kind == .dxxPatternBreak })

        XCTAssertEqual(plan.diagnostics.rowMappings[1].source, PlaybackPosition(orderIndex: 2, patternIndex: 4, rowIndex: 2))
        XCTAssertEqual(bxx.status, .applied)
        XCTAssertTrue(bxx.combinedWithDxx)
        XCTAssertEqual(bxx.policy, "bxx_uses_dxx_row_target_when_same_row")
        XCTAssertTrue(dxx.combinedWithBxx)
        XCTAssertEqual(dxx.targetOrderIndex, 2)
        XCTAssertEqual(dxx.targetRowIndex, 2)
    }

    func testTraversalE6xMarksLoopStartAndRepeatsRequestedCount() {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x60),
                    makePlaybackRow(index: 2, effectType: 0x0E, effectParam: 0x62),
                    makePlaybackRow(index: 3)
                ]
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let summary = plan.diagnostics.traversalSummary

        XCTAssertEqual(plan.diagnostics.rowMappings.map { $0.source.rowIndex }, [0, 1, 2, 1, 2, 1, 2, 3])
        XCTAssertEqual(summary.e6xLoopStartCount, 3)
        XCTAssertEqual(summary.e6xLoopTakenCount, 2)
        XCTAssertEqual(plan.diagnostics.traversalDiagnostics.filter(\.loopTaken).map(\.loopRemaining), [1, 0])
    }

    func testTraversalE6xMissingLoopStartIsDiagnosedWithoutInventingLoop() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0x61),
                    makePlaybackRow(index: 1)
                ]
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)
        let traversal = try XCTUnwrap(plan.diagnostics.traversalDiagnostics.first)

        XCTAssertEqual(plan.diagnostics.rowMappings.map { $0.source.rowIndex }, [0, 1])
        XCTAssertEqual(traversal.status, .missingLoopStart)
        XCTAssertTrue(traversal.missingLoopStart)
        XCTAssertEqual(traversal.policy, "missing_e60_loop_start_diagnosed_no_loop")
    }

    func testTraversalGuardStopsInfinitePositionJumpLoop() {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0B, effectParam: 0x00)]
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: 100)

        XCTAssertTrue(plan.diagnostics.traversalGuardHit)
        XCTAssertEqual(plan.diagnostics.traversalStopReason, .traversalGuardHit)
        XCTAssertEqual(plan.diagnostics.traversalPathLength, 1)
        XCTAssertEqual(plan.diagnostics.traversalSummary.bxxDetectedCount, 1)
        XCTAssertEqual(plan.diagnostics.traversalSummary.e6xLoopLimitHitCount, 0)
        XCTAssertEqual(plan.diagnostics.traversalDiagnostics.first?.status, .loopLimitHit)
        XCTAssertEqual(plan.diagnostics.traversalDiagnostics.first?.policy, "bxx_position_cycle_guard")
    }

    func testRuntimeAdapterPlanningDoesNotExpandLongOrderTablePositionJumpCycle() {
        let orderCount = 512
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        var orderPatternIndices = Array(repeating: 2, count: orderCount - 1)
        orderPatternIndices.append(3)
        let song = makePlaybackSong(
            orderPatternIndices: orderPatternIndices,
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1)],
                3: [makePlaybackRow(index: 0, effectType: 0x0B, effectParam: 0x00)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )

        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(plan.plannedEventCount, orderCount - 1)
        XCTAssertEqual(plan.plan?.diagnostics.traversalGuardHit, true)
        XCTAssertEqual(plan.plan?.diagnostics.traversalStopReason, .traversalGuardHit)
        XCTAssertEqual(plan.plan?.diagnostics.traversalPathLength, orderCount)
        XCTAssertEqual(plan.plan?.diagnostics.requestedOrderCount, orderCount)
        XCTAssertEqual(plan.plan?.diagnostics.adaptedOrders.count, orderCount)
    }

    func testTraversalOfflineRenderRuntimePlanAndDirectStartRemainDeterministic() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0D, effectParam: 0x01)],
                3: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            startOrderIndex: 0,
            orderCount: 2,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        )
        let renderer = PlaybackSongOfflineRenderer()

        let first = renderer.render(request)
        let second = renderer.render(request)
        let runtimePlan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let direct = PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 1, orderCount: 1, sampleRate: 100)

        XCTAssertEqual(first.block.interleavedPCM, [0, 1])
        XCTAssertEqual(first.block.interleavedPCM, second.block.interleavedPCM)
        XCTAssertEqual(first.diagnostics.eventMappings.first?.source, PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 1))
        XCTAssertEqual(runtimePlan.events.first?.source, PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 1))
        XCTAssertEqual(runtimePlan.plan?.diagnostics.rowMappings.map(\.source), first.diagnostics.rowMappings.map(\.source))
        XCTAssertEqual(direct.diagnostics.rowMappings.map(\.source), [
            PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 0),
            PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 1),
        ])
    }
}
