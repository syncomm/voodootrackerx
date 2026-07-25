import CryptoKit
import XCTest

final class BlankTrackerDocumentTests: XCTestCase {
    func testDeterministicSineGeneratorPinsRecipeMetadataHashAndC4Planning() throws {
        let samples = try (0..<2).map { _ in try XCTUnwrap(DeterministicSampleGenerator.sine(instrumentIndex: 1)) }
        let first = samples[0]
        XCTAssertEqual(first, samples[1])
        XCTAssertEqual(first.name, "Sine")
        XCTAssertEqual(
            [first.sampleLength, first.sourceBitDepthBits ?? 0, Int(first.xmVolume), Int(first.panning),
             first.relativeNote, first.finetune, first.loopType, first.loopStart, first.loopLength],
            [16_384, 16, 64, 128, 0, 0, 1, 0, 16_384]
        )
        XCTAssertEqual(first.sampleLength / 32, 512)
        XCTAssertEqual(Array(first.pcm.prefix(32)), Array(first.pcm.dropFirst(32).prefix(32)))
        XCTAssertNotEqual(Array(first.pcm.prefix(16)), Array(first.pcm.dropFirst(16).prefix(16)))
        XCTAssertTrue(first.pcm.allSatisfy { $0.isFinite && (-1...1).contains($0) })
        XCTAssertEqual(first.pcm.map(abs).max(), Float(12_000) / 32_768)
        XCTAssertEqual(abs(first.pcm[0] - first.pcm[31]), abs(first.pcm[1] - first.pcm[0]))
        XCTAssertEqual(pcmSHA256(first), "ac9e9e7dbfbf285d7ca2d98cabf2ed57e5c3ac9e53f1ec01ba4813c02d4a7b91")
        let pitches = [PlaybackPitchCalculator.c4NoteValue, PlaybackPitchCalculator.c4NoteValue + 12].map {
            PlaybackPitchCalculator.calculation(
                note: UInt8($0), sample: first, pitchOffsetSemitones: 0, outputSampleRate: 48_000
            )
        }
        let tones = pitches.map { $0.frequency / 32 }
        XCTAssertEqual(pitches[0].playbackRate, 8_363.0 / 48_000.0, accuracy: 0.000_000_001)
        XCTAssertEqual(tones[0], 8_363.0 / 32.0)
        XCTAssertEqual(tones[0], 261.625_565, accuracy: 0.5)
        XCTAssertEqual(tones[1] / tones[0], 2, accuracy: 0.000_000_001)
    }

    func testGeneratingSineCreatesOnlySelectedS01WithAllNoteDefaultMap() throws {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertEqual(document.addEmptyInstrument(), 2)
        document.selectInstrument(1)
        let before = document
        XCTAssertTrue(document.canGenerateSineInSelectedEmptySample)
        XCTAssertTrue(document.generateSineInSelectedEmptySample())
        let instrument = try XCTUnwrap(document.instrumentPalette[1])
        let sample = try XCTUnwrap(instrument.samples.first)
        XCTAssertEqual(instrument.samples.count, 1)
        XCTAssertEqual(sample.sampleIndex, 0)
        XCTAssertEqual(instrument.noteSampleMap, Array(repeating: 0, count: 96))
        XCTAssertEqual([UInt8(1), 49, 96].map(instrument.mappedSampleIndex(forNote:)), [0, 0, 0])
        XCTAssertEqual(document.selection, .default)
        XCTAssertEqual(document.instrumentPalette.count, before.instrumentPalette.count)
        XCTAssertEqual(document.instrumentPalette[2], before.instrumentPalette[2])
        XCTAssertTrue(document.patterns == before.patterns && document.orderTable == before.orderTable)
        XCTAssertTrue(document.songLength == before.songLength && document.tempo == before.tempo && document.speed == before.speed)
        guard case .potentiallyAvailable = document.noteAuditionAvailability else {
            return XCTFail("Generated S01 should be immediately auditionable")
        }
    }

    func testWAVImportFillsOnlyEmptyS01WithOwnedCanonicalSampleAndDefaultMap() throws {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertEqual(document.addEmptyInstrument(), 2)
        document.selectInstrument(1)
        let before = document
        let candidate = try normalizedImportCandidate(name: "Imported.wav", pcm: [-0.5, 0, 0.5])
        let destination = try XCTUnwrap(document.selectedSampleImportDestination)

        XCTAssertEqual(destination, .emptyS01(instrumentIndex: 1))
        XCTAssertTrue(document.importAudioSample(candidate, destination: destination))

        let instrument = try XCTUnwrap(document.instrumentPalette[1])
        let sample = try XCTUnwrap(instrument.samples.first)
        XCTAssertEqual(instrument.samples.count, 1)
        XCTAssertEqual(instrument.noteSampleMap, Array(repeating: 0, count: 96))
        XCTAssertEqual(document.selection, .default)
        XCTAssertEqual(sample, candidate.playbackSample(instrumentIndex: 1, sampleIndex: 0))
        XCTAssertEqual(document.instrumentPalette[2], before.instrumentPalette[2])
        XCTAssertEqual(document.patterns, before.patterns)
        XCTAssertNil(Mirror(reflecting: document).children.first { $0.value is URL })
        guard case let .potentiallyAvailable(descriptor) = document.noteAuditionAvailability else {
            return XCTFail("Imported S01 should be available to the next audition")
        }
        XCTAssertEqual(descriptor.previewPCM, candidate.pcm)
        XCTAssertEqual(descriptor.previewVolume, 1)
        XCTAssertEqual(descriptor.previewPanning, 128)
        XCTAssertEqual(descriptor.previewRelativeNote, candidate.relativeNote)
        XCTAssertEqual(descriptor.previewFinetune, candidate.finetune)
        XCTAssertEqual(descriptor.previewLoop.mode, .none)
    }

    func testWAVReplacementPreservesExactSlotKeymapAndUnrelatedInstrumentState() throws {
        let base = BlankTrackerDocument.makeDefault()
        let first = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, name: "Keep", pcm: [0.25])
        let replaced = makePlaybackSample(instrumentIndex: 1, sampleIndex: 1, name: "Old", pcm: [-0.25])
        let map = (0..<96).map { $0 < 48 ? 0 : 1 }
        let instrument = PlaybackInstrument(
            index: 1, name: "Layered", samples: [first, replaced],
            volumeEnvelope: PlaybackVolumeEnvelope(
                enabled: true, points: [.init(tick: 0, value: 64)], sustainPointIndex: nil,
                loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 0
            ),
            noteSampleMap: map
        )
        var document = BlankTrackerDocument(
            title: base.title, songLength: base.songLength, currentPosition: base.currentPosition,
            restartPosition: base.restartPosition, currentPatternIndex: base.currentPatternIndex,
            tempo: base.tempo, speed: base.speed, orderTable: base.orderTable,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2),
            instrumentPalette: [1: instrument], patterns: base.patterns
        )
        let before = document
        let candidate = try normalizedImportCandidate(name: "Replacement.wav", pcm: [-1, 1])
        let destination = try XCTUnwrap(document.selectedSampleImportDestination)

        XCTAssertEqual(destination, .represented(instrumentIndex: 1, sampleIndex: 1))
        XCTAssertTrue(document.importAudioSample(candidate, destination: destination))

        let updated = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(updated.samples[0], first)
        XCTAssertEqual(updated.samples[1], candidate.playbackSample(instrumentIndex: 1, sampleIndex: 1))
        XCTAssertEqual(updated.name, instrument.name)
        XCTAssertEqual(updated.noteSampleMap, map)
        XCTAssertEqual(updated.volumeEnvelope, instrument.volumeEnvelope)
        XCTAssertEqual(document.selection, before.selection)
        XCTAssertEqual(document.patterns, before.patterns)
        XCTAssertFalse(document.importAudioSample(candidate, destination: .emptyS01(instrumentIndex: 1)))
    }

    func testDefaultBlankDocumentUsesTrackerStartupDefaults() {
        let document = BlankTrackerDocument.makeDefault()

        XCTAssertEqual(document.title, "Untitled")
        XCTAssertEqual(document.songLength, 1)
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.restartPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 0)
        XCTAssertEqual(document.pattern.index, 0)
        XCTAssertEqual(document.pattern.rowCount, 64)
        XCTAssertEqual(document.pattern.channels, 8)
        XCTAssertEqual(document.tempo, 125)
        XCTAssertEqual(document.speed, 6)
        XCTAssertEqual(document.selection, .default)
        XCTAssertEqual(document.selection.selectedInstrument, 1)
        XCTAssertEqual(document.selection.selectedSample, 1)
        XCTAssertEqual(document.instrumentCount, 1)
        XCTAssertEqual(document.instrumentPalette.keys.sorted(), [1])
        XCTAssertNil(document.instrumentPalette[1]?.name)
        XCTAssertEqual(document.instrumentPalette[1]?.samples, [])
        XCTAssertEqual(document.metadata.instruments, 1)
        XCTAssertEqual(document.noteAuditionAvailability, .unavailable(.selectedSampleUnavailable))
        XCTAssertTrue(document.controlPanelMetadata.areInstrumentPlaceholdersEnabled)
    }

    func testAddingEmptyInstrumentAppendsWithoutFabricatingSampleData() throws {
        var document = BlankTrackerDocument.makeDefault()
        let before = document

        XCTAssertTrue(document.canAddEmptyInstrument)
        XCTAssertEqual(document.addEmptyInstrument(), 2)

        let created = try XCTUnwrap(document.instrumentPalette[2])
        XCTAssertEqual(created.index, 2)
        XCTAssertNil(created.name)
        XCTAssertTrue(created.samples.isEmpty)
        XCTAssertNil(created.noteSampleMap)
        XCTAssertEqual(created.volumeEnvelope, .disabled)
        XCTAssertEqual(created.panningEnvelope, .disabled)
        XCTAssertEqual(created.autoVibrato, .disabled)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))
        XCTAssertEqual(document.instrumentPalette[1], before.instrumentPalette[1])
        XCTAssertEqual(document.patterns, before.patterns)
        XCTAssertEqual(document.orderTable, before.orderTable)
    }

    func testAddingEmptyInstrumentUsesContiguousAppendPolicyAndStopsAtXMLimit() {
        let first = PlaybackInstrument(index: 1, samples: [])
        let third = PlaybackInstrument(index: 3, samples: [])
        var sparse = makeBlankDocument(instrumentPalette: [1: first, 3: third])

        XCTAssertEqual(sparse.addEmptyInstrument(), 4)
        XCTAssertNil(sparse.instrumentPalette[2])
        XCTAssertNotNil(sparse.instrumentPalette[4])

        var atLimit = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 255, selectedSample: 1),
            instrumentPalette: [255: PlaybackInstrument(index: 255, samples: [])]
        )
        let before = atLimit
        XCTAssertFalse(atLimit.canAddEmptyInstrument)
        XCTAssertNil(atLimit.addEmptyInstrument())
        XCTAssertEqual(atLimit, before)
    }

    func testTrackerEditorSelectionUsesOneBasedTrackerDefaultsAndClampsToSlotRange() {
        XCTAssertEqual(TrackerEditorSelection.default.selectedInstrument, 1)
        XCTAssertEqual(TrackerEditorSelection.default.selectedSample, 1)
        XCTAssertEqual(TrackerEditorSelection.default.instrumentDisplayTitle, "I01")
        XCTAssertEqual(TrackerEditorSelection.default.sampleDisplayTitle, "S01")

        let clampedLow = TrackerEditorSelection(selectedInstrument: 0, selectedSample: -8)
        XCTAssertEqual(clampedLow.selectedInstrument, 1)
        XCTAssertEqual(clampedLow.selectedSample, 1)

        let clampedHigh = TrackerEditorSelection(selectedInstrument: 999, selectedSample: 300)
        XCTAssertEqual(clampedHigh.selectedInstrument, 255)
        XCTAssertEqual(clampedHigh.selectedSample, 255)
        XCTAssertEqual(clampedHigh.instrumentDisplayTitle, "IFF")
        XCTAssertEqual(clampedHigh.sampleDisplayTitle, "SFF")
    }

    func testTrackerEditorSelectionPreservesOrResetsSampleWhenInstrumentChanges() {
        let selection = TrackerEditorSelection(selectedInstrument: 1, selectedSample: 3)

        let preserved = selection.withSelectedInstrument(2, availableSampleSlots: [1, 3])
        let resetToFirstAvailable = selection.withSelectedInstrument(2, availableSampleSlots: [1, 2])
        let resetToDefault = selection.withSelectedInstrument(2, availableSampleSlots: [])

        XCTAssertEqual(preserved, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 3))
        XCTAssertEqual(resetToFirstAvailable, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))
        XCTAssertEqual(resetToDefault, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))
    }

    func testSelectingRepresentedSamplelessInstrumentKeepsInstrumentAndHonestDefaultSample() {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            instrumentPalette: [
                1: PlaybackInstrument(index: 1, name: "Playable", samples: [sample]),
                2: PlaybackInstrument(index: 2, name: "Sampleless", samples: []),
            ]
        )

        document.selectInstrument(2)
        let state = InstrumentEditorDisplayState.editableDocument(document)

        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))
        XCTAssertTrue(document.availableSampleSlots(forInstrument: 2).isEmpty)
        XCTAssertEqual(state.instrumentName, "Sampleless")
        XCTAssertTrue(state.sampleSlots.isEmpty)
        XCTAssertNil(state.selectedSample)
        XCTAssertFalse(state.isSampleVolumeEditable || state.isSampleRelativeNoteEditable || state.isSampleFinetuneEditable || state.isSamplePanningEditable)
    }

    func testEditorNoteAuditionRequestCapturesNoteSelectionAndSourceContext() {
        let selection = TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3)
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: "q",
            selectedOctave: 4,
            selection: selection,
            sourceContext: .blankDocument,
            channelIndex: 2,
            rowIndex: 12
        )

        XCTAssertEqual(
            request,
            EditorNoteAuditionRequest(
                kind: .noteOn(noteValue: 61, selectedOctave: 4),
                selection: selection,
                sourceContext: .blankDocument,
                channelIndex: 2,
                rowIndex: 12
            )
        )
        XCTAssertEqual(request?.selectedInstrumentIndex, 7)
        XCTAssertEqual(request?.selectedSampleIndex, 3)
    }

    func testEditorNoteAuditionRequestRejectsNonNoteKeys() {
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: "i",
            selectedOctave: 4,
            selection: .default,
            sourceContext: .blankDocument
        )

        XCTAssertNil(request)
    }

    func testEditorPatternMutationPolicyKeepsLoadedModulesReadOnly() {
        XCTAssertTrue(EditorPatternMutationPolicy.canMutatePattern(sourceContext: .blankDocument))
        XCTAssertFalse(EditorPatternMutationPolicy.canMutatePattern(sourceContext: .loadedModule(patternIndex: 0)))
        XCTAssertTrue(EditorPatternMutationPolicy.canClearCurrentPattern(sourceContext: .blankDocument))
        XCTAssertFalse(EditorPatternMutationPolicy.canClearCurrentPattern(sourceContext: .loadedModule(patternIndex: 0)))
        XCTAssertTrue(EditorPatternMutationPolicy.canClearSongData(sourceContext: .blankDocument))
        XCTAssertFalse(EditorPatternMutationPolicy.canClearSongData(sourceContext: .loadedModule(patternIndex: 0)))
        XCTAssertTrue(EditorCommandAvailability.canClearCurrentPattern(
            hasBlankDocument: true,
            sourceContext: .blankDocument
        ))
        XCTAssertFalse(EditorCommandAvailability.canClearCurrentPattern(
            hasBlankDocument: false,
            sourceContext: .loadedModule(patternIndex: 0)
        ))
        XCTAssertTrue(EditorCommandAvailability.canClearSongData(
            hasBlankDocument: true,
            sourceContext: .blankDocument
        ))
        XCTAssertFalse(EditorCommandAvailability.canClearSongData(
            hasBlankDocument: false,
            sourceContext: .blankDocument
        ))
        XCTAssertFalse(EditorCommandAvailability.canClearSongData(
            hasBlankDocument: false,
            sourceContext: .loadedModule(patternIndex: 0)
        ))
        XCTAssertTrue(EditorCommandAvailability.canClearSongData(
            hasBlankDocument: false,
            sourceContext: .loadedModule(patternIndex: 0),
            loadedModuleCanMakeEditableCopy: true
        ))
    }

    func testBlankDocumentNoteAuditionAvailabilityIsUnavailableWithoutInstrumentSamplePayload() {
        let document = BlankTrackerDocument.makeDefault()
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: "z",
            selectedOctave: 4,
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            channelIndex: 0,
            rowIndex: 0
        )

        XCTAssertEqual(document.noteAuditionSourceContext, .blankDocument)
        XCTAssertEqual(document.noteAuditionAvailability, .unavailable(.selectedSampleUnavailable))
        let availability = request.map {
            EditorNoteAuditionAvailabilityResolver.availability(
                for: $0,
                hasRealInstrumentSamplePayload: false,
                selectedInstrumentSampleIsPlayable: false
            )
        }

        XCTAssertEqual(availability, .unavailable(.blankDocumentMissingInstrumentSamplePayload))
    }

    func testLoadedModuleNoteAuditionAvailabilityCanBePotentiallyAvailableWhenPlayableSampleResolves() {
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: 2),
            channelIndex: 0,
            rowIndex: 16
        )

        XCTAssertEqual(
            EditorNoteAuditionAvailabilityResolver.availability(
                for: request,
                hasRealInstrumentSamplePayload: true,
                selectedInstrumentSampleIsPlayable: true
            ),
            .potentiallyAvailable(EditorNoteAuditionSampleDescriptor(
                instrumentIndex: 1,
                sampleIndex: 0,
                sampleFrameCount: 0,
                hasSamplePayload: true,
                hasLoopMetadata: false,
                sourceContext: .loadedModule(patternIndex: 2)
            ))
        )
        XCTAssertEqual(
            EditorNoteAuditionAvailabilityResolver.availability(
                for: request,
                hasRealInstrumentSamplePayload: true,
                selectedInstrumentSampleIsPlayable: false
            ),
            .unavailable(.selectedInstrumentSampleNotPlayable)
        )
    }

    func testLoadedModuleNoteAuditionAvailabilityRequiresLoadedPlaybackSong() {
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )

        XCTAssertEqual(
            EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: nil),
            .unavailable(.loadedModuleMissingPlaybackSong)
        )
    }

    func testLoadedModuleNoteAuditionAvailabilityReturnsUnavailableWhenInstrumentDoesNotResolve() {
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [:]
        )
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )

        XCTAssertEqual(
            EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song),
            .unavailable(.selectedInstrumentUnavailable)
        )
    }

    func testLoadedModuleNoteAuditionAvailabilityDoesNotFallbackWhenSelectedSampleSlotIsUnavailable() {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25, -0.25])
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2),
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )

        XCTAssertEqual(
            EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song),
            .unavailable(.selectedSampleUnavailable)
        )
    }

    func testLoadedModuleNoteAuditionAvailabilityRoutesSelectedNonFirstSampleSlot() {
        let firstSample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [1, -1])
        let secondSample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 1,
            pcm: [0.125, 0.25, -0.125, -0.25],
            volume: 0.75,
            baseSampleRate: 12_000
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [firstSample, secondSample])]
        )
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2),
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )

        guard case let .potentiallyAvailable(descriptor) =
            EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song) else {
            return XCTFail("selected S02 should resolve to the second loaded sample slot")
        }
        XCTAssertEqual(descriptor.instrumentIndex, 1)
        XCTAssertEqual(descriptor.sampleIndex, 1)
        XCTAssertEqual(descriptor.sampleFrameCount, 4)
        XCTAssertEqual(descriptor.previewPCM, [0.125, 0.25, -0.125, -0.25])
        XCTAssertEqual(descriptor.previewVolume, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(descriptor.previewBaseSampleRate, 12_000, accuracy: 0.000_001)
    }

    func testLoadedModuleNoteAuditionAvailabilityReturnsUnavailableWhenResolvedSampleHasNoPayload() {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [])
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )

        XCTAssertEqual(
            EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song),
            .unavailable(.selectedSampleMissingPayload)
        )
    }

    func testLoadedModuleNoteAuditionAvailabilityReturnsPotentiallyAvailableDescriptorForSyntheticSamplePayload() {
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25, -0.25, 0.5, -0.5],
            loopStart: 1,
            loopLength: 2,
            loopType: 1
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )

        XCTAssertEqual(
            EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song),
            .potentiallyAvailable(EditorNoteAuditionSampleDescriptor(
                instrumentIndex: 1,
                sampleIndex: 0,
                sampleFrameCount: 4,
                hasSamplePayload: true,
                hasLoopMetadata: true,
                previewLoop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3),
                sourceContext: .loadedModule(patternIndex: 0),
                previewPCM: [0.25, -0.25, 0.5, -0.5],
                previewVolume: 1,
                previewBaseSampleRate: 100
            ))
        )
    }

    func testLoadedModuleNoteAuditionAvailabilityCapturesPingPongLoopMetadata() {
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25, -0.25, 0.5, -0.5],
            loopStart: 1,
            loopLength: 3,
            loopType: 2
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )

        guard case let .potentiallyAvailable(descriptor) =
            EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song) else {
            return XCTFail("ping-pong synthetic sample should resolve to previewable loop metadata")
        }

        XCTAssertTrue(descriptor.hasLoopMetadata)
        XCTAssertEqual(descriptor.previewLoop, MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4))
    }

    func testPublicMinimalXMFixtureDoesNotNeedPreviewableSamplePayload() throws {
        let fixtureURL = try fixtureURL("minimal.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let orderPatternIndices = metadata.orderTable.isEmpty
            ? [metadata.xmPatterns.first?.index ?? 0]
            : metadata.orderTable
        let patternRowCounts = metadata.xmPatterns.reduce(into: [Int: Int]()) { partialResult, pattern in
            partialResult[pattern.index] = pattern.rowCount
        }
        let song = makePlaybackSong(
            orderPatternIndices: orderPatternIndices,
            patternRowCounts: patternRowCounts,
            instrumentsByIndex: [:]
        )
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: metadata.xmPatterns.first?.index),
            channelIndex: 0,
            rowIndex: 0
        )

        if case .potentiallyAvailable = EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song) {
            XCTFail("minimal.xm should not be required to provide a previewable loaded sample payload")
        }
    }

    func testGeneratedBasicInstrumentSampleFixtureProvidesPositiveNoteAuditionAvailability() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/basic-instrument-sample.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)

        XCTAssertEqual(metadata.type, "XM")
        XCTAssertEqual(metadata.title, "VTX BASIC SAMPLE")
        XCTAssertEqual(metadata.version, "1.4")
        XCTAssertEqual(metadata.channels, 1)
        XCTAssertEqual(metadata.patterns, 1)
        XCTAssertEqual(metadata.instruments, 1)
        XCTAssertEqual(metadata.defaultTempo, 6)
        XCTAssertEqual(metadata.defaultBPM, 125)
        XCTAssertEqual(metadata.orderTable, [0])
        XCTAssertEqual(metadata.xmPatterns.count, 1)
        XCTAssertEqual(metadata.xmPatterns[0].rowCount, 16)
        XCTAssertEqual(metadata.xmPatterns[0].channels, 1)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].note, 49)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].instrument, 1)
        XCTAssertEqual(metadata.xmPatterns[0].rows[8][0].note, XMPatternEventCell.keyOffNoteValue)

        XCTAssertEqual(song.instrumentsByIndex.count, 1)
        let instrument = try XCTUnwrap(song.instrument(forInstrument: 1))
        XCTAssertEqual(instrument.name, "BASIC SAMPLE")
        XCTAssertEqual(instrument.samples.count, 1)
        let sample = try XCTUnwrap(instrument.sample(mappedSampleIndex: 0))
        XCTAssertEqual(sample.instrumentIndex, 1)
        XCTAssertEqual(sample.sampleIndex, 0)
        XCTAssertEqual(sample.name, "SINE64")
        XCTAssertEqual(sample.sampleLength, 64)
        XCTAssertEqual(sample.pcm.count, 64)
        XCTAssertFalse(sample.pcm.isEmpty)
        XCTAssertTrue(sample.isPlayable)
        XCTAssertEqual(sample.sourceBitDepthBits, 8)
        XCTAssertEqual(sample.sourceIsSignedPCM, true)
        XCTAssertEqual(sample.sourceIsDeltaEncoded, true)
        XCTAssertEqual(sample.volume, 1, accuracy: 0.000_001)
        // XM sample data does not store a WAV-style sample rate; VTX exposes
        // this neutral generated fixture sample at the expected 8,363 Hz base
        // rate. Keep this public fixture assertion separate from synthetic
        // helper tests that choose small explicit rates such as 100 Hz.
        XCTAssertEqual(sample.baseSampleRate, 8_363, accuracy: 0.000_001)
        XCTAssertEqual(sample.pcm[0], 0, accuracy: 0.000_001)
        XCTAssertEqual(sample.pcm[4], 0.375, accuracy: 0.000_001)
        XCTAssertEqual(sample.pcm[12], -0.375, accuracy: 0.000_001)

        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: metadata.xmPatterns.first?.index),
            channelIndex: 0,
            rowIndex: 0
        )
        let previewSink = RecordingEditorNoteAuditionPreviewSink()
        let availability = EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song)

        XCTAssertEqual(request.selectedInstrumentIndex, 1)
        XCTAssertEqual(request.selectedSampleIndex, 1)
        XCTAssertEqual(TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1).instrumentDisplayTitle, "I01")
        XCTAssertEqual(TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1).sampleDisplayTitle, "S01")
        guard case let .potentiallyAvailable(descriptor) = availability else {
            return XCTFail("generated fixture should provide positive note-audition availability")
        }
        XCTAssertEqual(descriptor.instrumentIndex, 1)
        XCTAssertEqual(descriptor.sampleIndex, 0)
        XCTAssertEqual(descriptor.sampleFrameCount, 64)
        XCTAssertTrue(descriptor.hasSamplePayload)
        XCTAssertFalse(descriptor.hasLoopMetadata)
        XCTAssertEqual(descriptor.sourceContext, .loadedModule(patternIndex: 0))
        XCTAssertEqual(descriptor.previewPCM.count, 64)
        XCTAssertEqual(descriptor.previewPCM[0], 0, accuracy: 0.000_001)
        XCTAssertEqual(descriptor.previewPCM[4], 0.375, accuracy: 0.000_001)
        XCTAssertEqual(descriptor.previewPCM[12], -0.375, accuracy: 0.000_001)
        XCTAssertEqual(descriptor.previewVolume, 1, accuracy: 0.000_001)
        XCTAssertEqual(descriptor.previewBaseSampleRate, 8_363, accuracy: 0.000_001)
        XCTAssertEqual(descriptor.previewRelativeNote, 0)
        XCTAssertEqual(descriptor.previewFinetune, 0)
        XCTAssertTrue(previewSink.events.isEmpty)
    }

    func testNoteAuditionPreviewerSkipsBlankDocumentsWithoutRealSamplePayload() {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let document = BlankTrackerDocument.makeDefault()
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: "z",
            selectedOctave: 4,
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            channelIndex: 0,
            rowIndex: 0
        )

        let outcome = previewer.preview(request: request, availability: document.noteAuditionAvailability)

        XCTAssertEqual(outcome, .skipped(.unavailable(.selectedSampleUnavailable)))
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testNoteAuditionPreviewerAttemptsDerivedEditableDocumentWithCopiedPayload() {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25, -0.25, 0.5],
            volume: 0.75,
            baseSampleRate: 8_363
        )
        let document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: "z",
            selectedOctave: 4,
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            channelIndex: 0,
            rowIndex: 0
        )

        let outcome = previewer.preview(request: request, availability: document.noteAuditionAvailability)

        guard case let .attempted(event) = outcome else {
            return XCTFail("copied editable palette should produce an actual preview event")
        }
        XCTAssertEqual(sink.events, [event])
        XCTAssertEqual(event.sampleDescriptor.sourceContext, .blankDocument)
        XCTAssertEqual(event.sampleDescriptor.previewPCM, [0.25, -0.25, 0.5])
        XCTAssertEqual(event.sampleDescriptor.previewVolume, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(event.sampleDescriptor.previewBaseSampleRate, 8_363, accuracy: 0.000_001)
    }

    func testNoteAuditionPreviewerSkipsKeyOffRequests() {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let request = EditorNoteAuditionRequest.previewKeyOff(
            selection: .default,
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 1,
            rowIndex: 2
        )
        let descriptor = EditorNoteAuditionSampleDescriptor(
            instrumentIndex: 1,
            sampleIndex: 0,
            sampleFrameCount: 4,
            hasSamplePayload: true,
            hasLoopMetadata: false,
            sourceContext: .loadedModule(patternIndex: 0)
        )

        let outcome = previewer.preview(request: request, availability: .potentiallyAvailable(descriptor))

        XCTAssertEqual(outcome, .skipped(.nonNoteRequest))
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testNoteAuditionPreviewerSkipsClearDeleteWithoutRequest() {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)

        let outcome = previewer.preview(
            request: nil,
            availability: .unavailable(.selectedInstrumentSampleNotPlayable)
        )

        XCTAssertEqual(outcome, .skipped(.missingRequest))
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testNoteAuditionPreviewerSkipsLoadedModuleUnavailableState() {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: .default,
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )

        let outcome = previewer.preview(
            request: request,
            availability: .unavailable(.selectedSampleMissingPayload)
        )

        XCTAssertEqual(outcome, .skipped(.unavailable(.selectedSampleMissingPayload)))
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testNoteAuditionPreviewerAttemptsSyntheticLoadedModuleNoteDescriptorAndDeliversMetadata() {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let selection = TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3)
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 61, selectedOctave: 4),
            selection: selection,
            sourceContext: .loadedModule(patternIndex: 2),
            channelIndex: 5,
            rowIndex: 16
        )
        let descriptor = EditorNoteAuditionSampleDescriptor(
            instrumentIndex: 7,
            sampleIndex: 2,
            sampleFrameCount: 128,
            hasSamplePayload: true,
            hasLoopMetadata: true,
            sourceContext: .loadedModule(patternIndex: 2),
            previewPCM: Array(repeating: 0.25, count: 128),
            previewVolume: 0.5,
            previewBaseSampleRate: 8_363
        )

        let outcome = previewer.preview(request: request, availability: .potentiallyAvailable(descriptor))

        XCTAssertEqual(
            outcome,
            .attempted(EditorNoteAuditionPreviewEvent(
                request: request,
                sampleDescriptor: descriptor,
                noteValue: 61,
                selectedOctave: 4
            ))
        )
        XCTAssertEqual(sink.events.count, 1)
        XCTAssertEqual(sink.events.first?.request.selectedInstrumentIndex, 7)
        XCTAssertEqual(sink.events.first?.request.selectedSampleIndex, 3)
        XCTAssertEqual(sink.events.first?.request.channelIndex, 5)
        XCTAssertEqual(sink.events.first?.request.rowIndex, 16)
        XCTAssertEqual(sink.events.first?.sampleDescriptor.instrumentIndex, 7)
        XCTAssertEqual(sink.events.first?.sampleDescriptor.sampleIndex, 2)
        XCTAssertEqual(sink.events.first?.sampleDescriptor.sampleFrameCount, 128)
        XCTAssertEqual(sink.events.first?.noteValue, 61)
        XCTAssertEqual(sink.events.first?.selectedOctave, 4)
    }

    func testNoteAuditionPreviewerStopsActivePreviewForMatchingKeyRelease() throws {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let event = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        let keyIdentity = try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "Z"))

        let outcome = previewer.preview(
            request: event.request,
            availability: .potentiallyAvailable(event.sampleDescriptor),
            keyIdentity: keyIdentity
        )

        XCTAssertEqual(outcome, .attempted(event))
        XCTAssertEqual(sink.events, [event])
        let token = try XCTUnwrap(previewer.activePreviewToken)
        XCTAssertEqual(token.keyIdentity, try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "z")))
        XCTAssertEqual(token.noteValue, 49)
        XCTAssertEqual(token.selectedOctave, 4)

        XCTAssertTrue(previewer.stopPreview(for: keyIdentity))

        XCTAssertNil(previewer.activePreviewToken)
        XCTAssertEqual(sink.releasePreviewCount, 1)
        XCTAssertEqual(sink.cancelPreviewCount, 0)
        sink.isPreviewAvailable = false
        XCTAssertEqual(previewer.preview(
            request: event.request, availability: .potentiallyAvailable(event.sampleDescriptor),
            keyIdentity: keyIdentity
        ), .skipped(.previewSinkRejected))
        sink.isPreviewAvailable = true
        XCTAssertTrue(previewer.preview(
            request: event.request,
            availability: .potentiallyAvailable(event.sampleDescriptor),
            keyIdentity: keyIdentity
        ).didAttemptPreview)
        previewer.invalidatePreviewState()
        XCTAssertNil(previewer.activePreviewToken)
        XCTAssertEqual(sink.cancelPreviewCount, 0)
    }

    func testNoteAuditionPreviewerStopsHeldLoopPreviewForMatchingKeyRelease() throws {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let event = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            baseSampleRate: 100,
            previewPCM: [0.25, 0.5, -0.25, -0.5],
            previewLoop: loop
        )
        let keyIdentity = try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "z"))

        XCTAssertTrue(previewer.preview(
            request: event.request,
            availability: .potentiallyAvailable(event.sampleDescriptor),
            keyIdentity: keyIdentity
        ).didAttemptPreview)

        XCTAssertTrue(previewer.stopPreview(for: keyIdentity))
        XCTAssertNil(previewer.activePreviewToken)
        XCTAssertEqual(sink.releasePreviewCount, 1)
        XCTAssertEqual(sink.cancelPreviewCount, 0)
        XCTAssertEqual(sink.events.first?.sampleDescriptor.previewLoop, loop)
    }

    func testNoteAuditionPreviewerPressingDifferentNoteReplacesActiveReleaseToken() throws {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let first = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        let second = try makePreviewEvent(trackerKey: "q", selectedOctave: 4, baseSampleRate: 100)

        XCTAssertTrue(previewer.preview(
            request: first.request,
            availability: .potentiallyAvailable(first.sampleDescriptor),
            keyIdentity: try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "z"))
        ).didAttemptPreview)
        let firstToken = try XCTUnwrap(previewer.activePreviewToken)

        XCTAssertTrue(previewer.preview(
            request: second.request,
            availability: .potentiallyAvailable(second.sampleDescriptor),
            keyIdentity: try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "q"))
        ).didAttemptPreview)
        let secondToken = try XCTUnwrap(previewer.activePreviewToken)

        XCTAssertEqual(sink.events, [first, second])
        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertEqual(secondToken.noteValue, 61)
        XCTAssertEqual(secondToken.keyIdentity, try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "q")))
    }

    func testStaleKeyReleaseFromOlderPreviewDoesNotCancelNewerPreview() throws {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let first = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        let second = try makePreviewEvent(trackerKey: "q", selectedOctave: 4, baseSampleRate: 100)
        let firstIdentity = try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "z"))
        let secondIdentity = try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "q"))

        XCTAssertTrue(previewer.preview(
            request: first.request,
            availability: .potentiallyAvailable(first.sampleDescriptor),
            keyIdentity: firstIdentity
        ).didAttemptPreview)
        let firstToken = try XCTUnwrap(previewer.activePreviewToken)
        XCTAssertTrue(previewer.preview(
            request: second.request,
            availability: .potentiallyAvailable(second.sampleDescriptor),
            keyIdentity: secondIdentity
        ).didAttemptPreview)
        let secondToken = try XCTUnwrap(previewer.activePreviewToken)

        XCTAssertFalse(previewer.stopPreview(for: firstToken))
        XCTAssertFalse(previewer.stopPreview(for: firstIdentity))

        XCTAssertEqual(previewer.activePreviewToken, secondToken)
        XCTAssertEqual(sink.releasePreviewCount, 0)
        XCTAssertEqual(sink.cancelPreviewCount, 0)
        XCTAssertTrue(previewer.stopPreview(for: secondIdentity))
        XCTAssertNil(previewer.activePreviewToken)
        XCTAssertEqual(sink.releasePreviewCount, 1)
        XCTAssertEqual(sink.cancelPreviewCount, 0)
    }

    func testNoteAuditionPreviewerSkipsRepeatedNoteKeyWithoutRetriggeringSink() {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let initialRequest = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: .default,
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )
        let repeatRequest = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: .default,
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0,
            isRepeatedKeyDown: true
        )
        let descriptor = EditorNoteAuditionSampleDescriptor(
            instrumentIndex: 1,
            sampleIndex: 0,
            sampleFrameCount: 4,
            hasSamplePayload: true,
            hasLoopMetadata: false,
            sourceContext: .loadedModule(patternIndex: 0),
            previewPCM: [0.25, 0.5, -0.25, -0.5]
        )
        let keyIdentity = EditorNoteAuditionKeyIdentity(trackerKey: "z")

        let initialOutcome = previewer.preview(
            request: initialRequest,
            availability: .potentiallyAvailable(descriptor),
            keyIdentity: keyIdentity
        )
        let activeToken = previewer.activePreviewToken
        let repeatOutcome = previewer.preview(
            request: repeatRequest,
            availability: .potentiallyAvailable(descriptor),
            keyIdentity: keyIdentity
        )

        XCTAssertTrue(initialOutcome.didAttemptPreview)
        XCTAssertEqual(repeatOutcome, .skipped(.repeatedKeyDown))
        XCTAssertEqual(sink.events.count, 1)
        XCTAssertFalse(sink.events.first?.request.isRepeatedKeyDown ?? true)
        XCTAssertEqual(previewer.activePreviewToken, activeToken)
    }

    func testNoteAuditionAvailabilityResolverUsesSelectedNonFirstInstrumentAndSample() throws {
        let selectedInstrument = PlaybackInstrument(
            index: 7,
            samples: [
                PlaybackSample(
                    instrumentIndex: 7,
                    sampleIndex: 0,
                    pcm: [1, -1],
                    volume: 1,
                    relativeNote: 0,
                    finetune: 0,
                    baseSampleRate: 8_363
                ),
                PlaybackSample(
                    instrumentIndex: 7,
                    sampleIndex: 2,
                    pcm: [0.125, 0.25, -0.125, -0.25],
                    volume: 0.75,
                    relativeNote: 0,
                    finetune: 0,
                    baseSampleRate: 12_000
                )
            ],
            noteSampleMap: Array(repeating: 2, count: 96)
        )
        let otherInstrument = PlaybackInstrument(
            index: 1,
            samples: [
                PlaybackSample(
                    instrumentIndex: 1,
                    sampleIndex: 0,
                    pcm: [1, -1],
                    volume: 1,
                    relativeNote: 0,
                    finetune: 0,
                    baseSampleRate: 8_363
                )
            ]
        )
        let song = PlaybackSong(
            title: "Synthetic public-safe preview routing",
            orders: [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [
                0: PlaybackPattern(index: 0, rows: [
                    PlaybackRow(index: 0, cells: [
                        PlaybackCell(note: 49, instrument: 7, volumeColumn: 0, effectType: 0, effectParam: 0)
                    ])
                ])
            ],
            instrumentsByIndex: [
                1: otherInstrument,
                7: selectedInstrument
            ],
            restartOrderIndex: 0,
            endBehavior: .stopAtEnd
        )
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3),
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )

        let availability = EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song)

        guard case let .potentiallyAvailable(descriptor) = availability else {
            return XCTFail("synthetic selected I07/S03 should resolve to a previewable descriptor")
        }
        XCTAssertEqual(descriptor.instrumentIndex, 7)
        XCTAssertEqual(descriptor.sampleIndex, 2)
        XCTAssertEqual(descriptor.sampleFrameCount, 4)
        XCTAssertEqual(descriptor.previewPCM, [0.125, 0.25, -0.125, -0.25])
        XCTAssertEqual(descriptor.previewVolume, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(descriptor.previewBaseSampleRate, 12_000, accuracy: 0.000_001)
    }

    func testNoteAuditionPreviewerCancelPreviewForwardsToSinkForDocumentReplacement() {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)

        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: .default,
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )
        let descriptor = EditorNoteAuditionSampleDescriptor(
            instrumentIndex: 1,
            sampleIndex: 0,
            sampleFrameCount: 4,
            hasSamplePayload: true,
            hasLoopMetadata: false,
            sourceContext: .loadedModule(patternIndex: 0),
            previewPCM: [0.25, 0.5, -0.25, -0.5]
        )
        XCTAssertTrue(previewer.preview(
            request: request,
            availability: .potentiallyAvailable(descriptor),
            keyIdentity: EditorNoteAuditionKeyIdentity(trackerKey: "z")
        ).didAttemptPreview)
        XCTAssertNotNil(previewer.activePreviewToken)

        previewer.cancelPreview()
        previewer.cancelPreview()

        XCTAssertEqual(sink.cancelPreviewCount, 2)
        XCTAssertNil(previewer.activePreviewToken)
        XCTAssertEqual(sink.events.count, 1)
    }

    func testNoteAuditionPreviewPitchLowerRowUsesSelectedOctave() throws {
        let event = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        let parameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: event, sampleRate: 100))

        XCTAssertEqual(event.noteValue, 49)
        XCTAssertEqual(event.selectedOctave, 4)
        XCTAssertEqual(parameters.playbackStep, 1, accuracy: 0.000_001)
    }

    func testNoteAuditionPreviewPitchUpperRowUsesSelectedOctavePlusOne() throws {
        let event = try makePreviewEvent(trackerKey: "q", selectedOctave: 4, baseSampleRate: 100)
        let parameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: event, sampleRate: 100))

        XCTAssertEqual(event.noteValue, 61)
        XCTAssertEqual(event.selectedOctave, 4)
        XCTAssertEqual(parameters.playbackStep, 2, accuracy: 0.000_001)
    }

    func testNoteAuditionPreviewUsesSharedSampleHeaderPanningPlan() throws {
        let left = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, samplePanning: 0, baseSampleRate: 100)
        let center = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, samplePanning: 128, baseSampleRate: 100)
        let right = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, samplePanning: 255, baseSampleRate: 100)
        let leftParameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: left, sampleRate: 100))
        let centerParameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: center, sampleRate: 100))
        let rightParameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: right, sampleRate: 100))
        let leftBlock = try XCTUnwrap(EditorNoteAuditionAudioSink.renderPreviewBlock(for: left, sampleRate: 100, frames: 4))
        let centerBlock = try XCTUnwrap(EditorNoteAuditionAudioSink.renderPreviewBlock(for: center, sampleRate: 100, frames: 4))
        let rightBlock = try XCTUnwrap(EditorNoteAuditionAudioSink.renderPreviewBlock(for: right, sampleRate: 100, frames: 4))

        XCTAssertEqual([leftParameters.pan, centerParameters.pan, rightParameters.pan], [-1, 0, 1])
        XCTAssertTrue(stride(from: 1, to: leftBlock.interleavedPCM.count, by: 2).allSatisfy { leftBlock.interleavedPCM[$0] == 0 })
        XCTAssertEqual(
            stride(from: 0, to: centerBlock.interleavedPCM.count, by: 2).map { centerBlock.interleavedPCM[$0] },
            stride(from: 1, to: centerBlock.interleavedPCM.count, by: 2).map { centerBlock.interleavedPCM[$0] }
        )
        XCTAssertTrue(stride(from: 0, to: rightBlock.interleavedPCM.count, by: 2).allSatisfy { rightBlock.interleavedPCM[$0] == 0 })
    }

    func testPersistentPreviewOutputActivationRouteChangeAndTeardownAreSingleTransitions() {
        var lifecycle = EditorNoteAuditionPersistentOutputLifecycle()
        XCTAssertEqual(lifecycle.activate(), .start)
        XCTAssertEqual(lifecycle.activate(), .none)
        XCTAssertEqual(lifecycle.routeOrFormatChanged(), .stopReconfigureAndStart)
        XCTAssertEqual(lifecycle.teardown(), .stopAndDispose)
        XCTAssertEqual(lifecycle.teardown(), .none)

        var unavailableLifecycle = EditorNoteAuditionPersistentOutputLifecycle()
        XCTAssertEqual(unavailableLifecycle.routeOrFormatChanged(), .start)
        unavailableLifecycle.startFailed()
        XCTAssertEqual(unavailableLifecycle.activate(), .start)
    }

    func testPersistentPreviewQuickHeldAndCancelledNotesHaveBoundedOrderedLifetimes() throws {
        let handoff = EditorNoteAuditionPreviewCommandHandoff(sampleRate: 100, queueCapacity: 8)
        let event = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        XCTAssertNotNil(handoff.publish(event))
        handoff.cancel()
        XCTAssertTrue(handoff.renderForTesting(frames: 4).allSatisfy { $0 == 0 })
        XCTAssertNil(handoff.lastRenderedGeneration)

        let quickGeneration = try XCTUnwrap(handoff.publish(event))
        XCTAssertEqual(handoff.release(generation: quickGeneration), .queued)
        XCTAssertTrue(handoff.renderForTesting(frames: 4).contains { $0 != 0 })
        XCTAssertTrue(handoff.renderForTesting(frames: 4).allSatisfy { $0 == 0 })

        let held = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100,
                                        previewLoop: MixerSampleLoop(mode: .forward, startFrame: 0, endFrame: 8))
        let generation = try XCTUnwrap(handoff.publish(held))
        XCTAssertTrue(handoff.renderForTesting(frames: 4).contains { $0 != 0 })
        XCTAssertEqual(handoff.release(generation: generation), .queued)
        XCTAssertTrue(handoff.renderForTesting(frames: 4).allSatisfy { $0 == 0 })
        XCTAssertEqual(handoff.lastRenderedGeneration, generation)
    }

    func testPersistentPreviewPreservesRapidNoteOrderAndStaleReleaseIdentity() throws {
        let handoff = EditorNoteAuditionPreviewCommandHandoff(sampleRate: 100, queueCapacity: 8)
        let left = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, samplePanning: 0, baseSampleRate: 100)
        let right = try makePreviewEvent(trackerKey: "s", selectedOctave: 4, samplePanning: 255, baseSampleRate: 100)
        let firstGeneration = try XCTUnwrap(handoff.publish(left))
        XCTAssertEqual(handoff.release(generation: firstGeneration), .queued)
        let secondGeneration = try XCTUnwrap(handoff.publish(right))
        XCTAssertEqual(handoff.release(generation: firstGeneration), .queued)

        let firstOnset = handoff.renderForTesting(frames: 4)
        let replacementOnset = handoff.renderForTesting(frames: 4)
        XCTAssertTrue(stride(from: 1, to: firstOnset.count, by: 2).allSatisfy { firstOnset[$0] == 0 })
        XCTAssertTrue(stride(from: 0, to: replacementOnset.count, by: 2).allSatisfy { replacementOnset[$0] == 0 })
        XCTAssertEqual(handoff.lastRenderedGeneration, secondGeneration)
    }

    func testPersistentPreviewOverflowAndConcurrentRenderingNeverLoseReleaseCancellationOrOwnership() throws {
        let handoff = EditorNoteAuditionPreviewCommandHandoff(sampleRate: 100, queueCapacity: 2)
        let first = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        let second = try makePreviewEvent(trackerKey: "s", selectedOctave: 4, baseSampleRate: 100)
        XCTAssertNotNil(handoff.publish(first))
        let secondGeneration = try XCTUnwrap(handoff.publish(second))
        XCTAssertNil(handoff.publish(first))
        XCTAssertEqual(handoff.rejectedNoteOnCount, 1)
        XCTAssertEqual(handoff.release(generation: secondGeneration), .atomicFallback)

        XCTAssertTrue(handoff.renderForTesting(frames: 4).contains { $0 != 0 })
        XCTAssertTrue(handoff.renderForTesting(frames: 4).contains { $0 != 0 })
        XCTAssertTrue(handoff.renderForTesting(frames: 4).allSatisfy { $0 == 0 })
        XCTAssertNotNil(handoff.publish(first))
        XCTAssertNotNil(handoff.publish(second))
        handoff.cancel()
        XCTAssertTrue(handoff.renderForTesting(frames: 4).allSatisfy { $0 == 0 })

        let renderStarted = DispatchSemaphore(value: 0)
        let renderFinished = expectation(description: "bounded render consumer finished")
        DispatchQueue.global().async {
            var output = Array(repeating: Float(0), count: 8)
            renderStarted.wait()
            for _ in 0..<2_000 { output.withUnsafeMutableBufferPointer { _ = handoff.render(into: $0, frames: 4) } }
            renderFinished.fulfill()
        }
        renderStarted.signal()
        for _ in 0..<250 {
            if let generation = handoff.publish(first) { _ = handoff.release(generation: generation) }
        }
        wait(for: [renderFinished], timeout: 5)
        handoff.cancel()
        _ = handoff.renderForTesting(frames: 4)
        handoff.shutdownAfterOutputStopped()
        XCTAssertEqual(handoff.outstandingVoiceCount, 0)
    }

    func testNoteAuditionPreviewPitchSemitoneKeysProduceDistinctSteps() throws {
        let c4 = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        let cSharp4 = try makePreviewEvent(trackerKey: "s", selectedOctave: 4, baseSampleRate: 100)
        let c4Parameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: c4, sampleRate: 100))
        let cSharp4Parameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: cSharp4, sampleRate: 100))

        XCTAssertEqual(c4.noteValue, 49)
        XCTAssertEqual(cSharp4.noteValue, 50)
        XCTAssertGreaterThan(cSharp4Parameters.playbackStep, c4Parameters.playbackStep)
        XCTAssertEqual(cSharp4Parameters.playbackStep, pow(2.0, 1.0 / 12.0), accuracy: 0.000_001)
    }

    func testNoteAuditionPreviewPitchC4AndC5UseDifferentSteps() throws {
        let c4 = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        let c5 = try makePreviewEvent(trackerKey: "q", selectedOctave: 4, baseSampleRate: 100)
        let c4Parameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: c4, sampleRate: 100))
        let c5Parameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: c5, sampleRate: 100))

        XCTAssertNotEqual(c4Parameters.playbackStep, c5Parameters.playbackStep)
        XCTAssertEqual(c5Parameters.playbackStep / c4Parameters.playbackStep, 2, accuracy: 0.000_001)
    }

    func testNoteAuditionPreviewMixerUsesDistinctStepsForTypedKeys() throws {
        let mixer = EditorNoteAuditionPreviewMixer(sampleRate: 100)
        let z = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        let s = try makePreviewEvent(trackerKey: "s", selectedOctave: 4, baseSampleRate: 100)
        let q = try makePreviewEvent(trackerKey: "q", selectedOctave: 4, baseSampleRate: 100)
        let two = try makePreviewEvent(trackerKey: "2", selectedOctave: 4, baseSampleRate: 100)

        XCTAssertTrue(mixer.replacePreview(with: z))
        let zStep = try XCTUnwrap(mixer.lastRenderParameters?.playbackStep)
        XCTAssertTrue(mixer.replacePreview(with: s))
        let sStep = try XCTUnwrap(mixer.lastRenderParameters?.playbackStep)
        XCTAssertTrue(mixer.replacePreview(with: q))
        let qStep = try XCTUnwrap(mixer.lastRenderParameters?.playbackStep)
        XCTAssertTrue(mixer.replacePreview(with: two))
        let twoStep = try XCTUnwrap(mixer.lastRenderParameters?.playbackStep)

        XCTAssertEqual(z.noteValue, 49)
        XCTAssertEqual(s.noteValue, 50)
        XCTAssertEqual(q.noteValue, 61)
        XCTAssertEqual(two.noteValue, 62)
        XCTAssertGreaterThan(sStep, zStep)
        XCTAssertEqual(qStep / zStep, 2, accuracy: 0.000_001)
        XCTAssertGreaterThan(twoStep, qStep)
    }

    func testNoteAuditionPreviewMixerRenderedOutputChangesWithTypedPitch() throws {
        let z = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            sampleVolume: 1,
            baseSampleRate: 100,
            previewPCM: [0, 0.25, 0.75, -0.5, -1, -0.25, 0.5, 1]
        )
        let q = try makePreviewEvent(
            trackerKey: "q",
            selectedOctave: 4,
            sampleVolume: 1,
            baseSampleRate: 100,
            previewPCM: [0, 0.25, 0.75, -0.5, -1, -0.25, 0.5, 1]
        )

        let zBlock = try XCTUnwrap(EditorNoteAuditionAudioSink.renderPreviewBlock(for: z, sampleRate: 100, frames: 6))
        let qBlock = try XCTUnwrap(EditorNoteAuditionAudioSink.renderPreviewBlock(for: q, sampleRate: 100, frames: 6))

        XCTAssertNotEqual(zBlock.interleavedPCM, qBlock.interleavedPCM)
    }

    func testNoteAuditionPreviewMixerReplacementCancelsPreviousVoiceWithoutLayering() throws {
        let mixer = EditorNoteAuditionPreviewMixer(sampleRate: 100)
        let first = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            sampleVolume: 1,
            baseSampleRate: 100,
            previewPCM: Array(repeating: 1, count: 64),
            previewLoop: MixerSampleLoop(mode: .forward, startFrame: 8, endFrame: 64)
        )
        let replacement = try makePreviewEvent(
            trackerKey: "q",
            selectedOctave: 4,
            sampleVolume: 1,
            baseSampleRate: 100,
            previewPCM: Array(repeating: -0.5, count: 64)
        )

        XCTAssertTrue(mixer.replacePreview(with: first))
        _ = mixer.render(frames: 8)
        XCTAssertTrue(mixer.replacePreview(with: replacement))

        XCTAssertEqual(mixer.loadedVoiceCount, 1)
        XCTAssertEqual(mixer.rampingOutVoiceCount, 0)
        let rendered = mixer.render(frames: 1)
        let expected = -0.5 * EditorNoteAuditionPreviewGainPolicy.gain(sampleVolume: 1)
        XCTAssertEqual(rendered.interleavedPCM.first ?? 0, expected, accuracy: 0.000_001)
    }

    func testNoteAuditionPreviewRenderParametersCarryForwardLoopMetadata() throws {
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let event = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            baseSampleRate: 100,
            previewPCM: [0.25, 0.5, -0.25, -0.5],
            previewLoop: loop
        )

        let parameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: event, sampleRate: 100))

        XCTAssertEqual(event.sampleDescriptor.previewLoop, loop)
        XCTAssertEqual(parameters.loop, loop)
    }

    func testNoteAuditionPreviewRenderParametersCarryPingPongLoopMetadata() throws {
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        let event = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            baseSampleRate: 100,
            previewPCM: [0.25, 0.5, -0.25, -0.5],
            previewLoop: loop
        )

        let parameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: event, sampleRate: 100))

        XCTAssertEqual(parameters.loop, loop)
    }

    func testHeldForwardLoopPreviewRemainsActiveBeyondOneShotLength() throws {
        let mixer = EditorNoteAuditionPreviewMixer(sampleRate: 100)
        let event = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            sampleVolume: 1,
            baseSampleRate: 100,
            previewPCM: [0.25, 0.5, -0.25, -0.5],
            previewLoop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        XCTAssertTrue(mixer.replacePreview(with: event))
        let rendered = mixer.render(frames: 12)

        XCTAssertEqual(mixer.activeVoiceCount, 1)
        XCTAssertGreaterThan(rendered.interleavedPCM.dropFirst(8).map { abs($0) }.max() ?? 0, 0)
    }

    func testHeldLoopPreviewCancelStopsActiveVoice() throws {
        let mixer = EditorNoteAuditionPreviewMixer(sampleRate: 100)
        let event = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            sampleVolume: 1,
            baseSampleRate: 100,
            previewPCM: [0.25, 0.5, -0.25, -0.5],
            previewLoop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        XCTAssertTrue(mixer.replacePreview(with: event))
        _ = mixer.render(frames: 12)
        XCTAssertEqual(mixer.activeVoiceCount, 1)

        mixer.cancelPreview()

        XCTAssertEqual(mixer.activeVoiceCount, 0)
        XCTAssertEqual(mixer.loadedVoiceCount, 0)
    }

    func testNonLoopingPreviewRemainsOneShot() throws {
        let mixer = EditorNoteAuditionPreviewMixer(sampleRate: 100)
        let event = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            sampleVolume: 1,
            baseSampleRate: 100,
            previewPCM: [0.25, 0.5, -0.25, -0.5]
        )

        XCTAssertTrue(mixer.replacePreview(with: event))
        let rendered = mixer.render(frames: 12)

        XCTAssertEqual(mixer.activeVoiceCount, 0)
        XCTAssertEqual(mixer.lastRenderParameters?.loop, MixerSampleLoop.none)
        XCTAssertEqual(rendered.interleavedPCM.dropFirst(8).map { abs($0) }.max() ?? 0, 0, accuracy: 0.000_001)
    }

    func testNoteAuditionPreviewMixerCarriesSelectedNonFirstInstrumentDescriptorToRenderPlan() throws {
        let event = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            sampleVolume: 0.5,
            baseSampleRate: 12_000,
            instrumentIndex: 7,
            sampleIndex: 2,
            previewPCM: [0.125, 0.25, -0.125, -0.25]
        )
        let mixer = EditorNoteAuditionPreviewMixer(sampleRate: 100)

        XCTAssertTrue(mixer.replacePreview(with: event))

        let parameters = try XCTUnwrap(mixer.lastRenderParameters)
        XCTAssertEqual(parameters.instrumentIndex, 7)
        XCTAssertEqual(parameters.sampleIndex, 2)
        XCTAssertEqual(parameters.playbackStep, 120, accuracy: 0.000_001)
    }

    func testNoteAuditionPreviewGainUsesRuntimeAdapterGainAndHeadroomBeforeSafetyCap() throws {
        let quietEvent = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            sampleVolume: 0.1,
            baseSampleRate: 100
        )
        let loudEvent = try makePreviewEvent(
            trackerKey: "z",
            selectedOctave: 4,
            sampleVolume: 1,
            baseSampleRate: 100
        )

        let quietParameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: quietEvent, sampleRate: 100))
        let loudParameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(for: loudEvent, sampleRate: 100))
        let runtimeHeadroom = RuntimeCMixerOutputPolicy.defaultPolicy.outputGain

        XCTAssertEqual(RuntimeCMixerOutputPolicy.defaultHeadroomDB, -12)
        XCTAssertEqual(
            quietParameters.gain,
            PlaybackSongSyntheticAdapter.adaptedGain(
                sampleVolume: 0.1,
                channelVolume: 64,
                globalVolume: PlaybackSongSyntheticAdapter.GlobalVolumeState.defaultValue
            ) * runtimeHeadroom,
            accuracy: 0.000_001
        )
        XCTAssertLessThan(quietParameters.gain, loudParameters.gain)
        XCTAssertEqual(
            loudParameters.gain,
            PlaybackSongSyntheticAdapter.adaptedGain(
                sampleVolume: 1,
                channelVolume: 64,
                globalVolume: PlaybackSongSyntheticAdapter.GlobalVolumeState.defaultValue
            ) * runtimeHeadroom,
            accuracy: 0.000_001
        )
        XCTAssertLessThan(loudParameters.gain, EditorNoteAuditionPreviewGainPolicy.maximumGain)
    }

    func testNoteAuditionAudioSinkOfflinePreviewRenderUsesCopiedPayloadAndConservativeGainWithoutHardware() throws {
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: .default,
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )
        let descriptor = EditorNoteAuditionSampleDescriptor(
            instrumentIndex: 1,
            sampleIndex: 0,
            sampleFrameCount: 4,
            hasSamplePayload: true,
            hasLoopMetadata: false,
            sourceContext: .loadedModule(patternIndex: 0),
            previewPCM: [1, 0.5, -0.5, -1],
            previewVolume: 0.5,
            // Synthetic helper value for deterministic unit math; generated
            // public XM fixture expectations assert the VTX 8,363 Hz base rate.
            previewBaseSampleRate: 100
        )
        let event = EditorNoteAuditionPreviewEvent(
            request: request,
            sampleDescriptor: descriptor,
            noteValue: 49,
            selectedOctave: 4
        )

        let block = EditorNoteAuditionAudioSink.renderPreviewBlock(
            for: event,
            sampleRate: 100,
            frames: 4
        )

        let rendered = try XCTUnwrap(block)
        XCTAssertEqual(rendered.frameCount, 4)
        XCTAssertEqual(rendered.interleavedPCM.count, 8)
        XCTAssertGreaterThan(rendered.interleavedPCM.map { abs($0) }.max() ?? 0, 0)
        XCTAssertLessThanOrEqual(
            rendered.interleavedPCM.map { abs($0) }.max() ?? 0,
            EditorNoteAuditionPreviewGainPolicy.maximumGain + 0.000_001
        )
    }

    func testGeneratedBasicInstrumentSampleFixturePreviewRenderIsNonSilentAndBoundedWithoutHardware() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/basic-instrument-sample.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let request = EditorNoteAuditionRequest(
            kind: .noteOn(noteValue: 49, selectedOctave: 4),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourceContext: .loadedModule(patternIndex: 0),
            channelIndex: 0,
            rowIndex: 0
        )
        let availability = EditorNoteAuditionAvailabilityResolver.availability(for: request, loadedPlaybackSong: song)
        guard case let .potentiallyAvailable(descriptor) = availability else {
            return XCTFail("generated fixture should resolve to previewable sample payload")
        }
        let event = EditorNoteAuditionPreviewEvent(
            request: request,
            sampleDescriptor: descriptor,
            noteValue: 49,
            selectedOctave: 4
        )

        let block = try XCTUnwrap(EditorNoteAuditionAudioSink.renderPreviewBlock(
            for: event,
            sampleRate: 44_100,
            frames: 256
        ))
        let peak = block.interleavedPCM.map { abs($0) }.max() ?? 0
        let parameters = try XCTUnwrap(EditorNoteAuditionAudioSink.previewRenderParameters(
            for: event,
            sampleRate: 44_100
        ))
        let expectedRuntimeEquivalentGain = PlaybackSongSyntheticAdapter.adaptedGain(
            sampleVolume: descriptor.previewVolume,
            channelVolume: 64,
            globalVolume: PlaybackSongSyntheticAdapter.GlobalVolumeState.defaultValue
        ) * RuntimeCMixerOutputPolicy.defaultPolicy.outputGain

        XCTAssertGreaterThan(peak, 0)
        XCTAssertGreaterThan(peak, 0.04)
        XCTAssertLessThan(peak, 1)
        XCTAssertLessThanOrEqual(peak, EditorNoteAuditionPreviewGainPolicy.maximumGain + 0.000_001)
        XCTAssertEqual(parameters.gain, expectedRuntimeEquivalentGain, accuracy: 0.000_001)
        XCTAssertGreaterThan(parameters.gain, 0.04)
        XCTAssertLessThan(parameters.gain, EditorNoteAuditionPreviewGainPolicy.maximumGain)
    }

    func testPreviewKeyReleaseRequestDoesNotWritePatternKeyOffData() {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let beforeRelease = document

        let request = EditorNoteAuditionRequest.previewKeyOff(
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            channelIndex: 0,
            rowIndex: 0
        )

        XCTAssertEqual(request.kind, .previewKeyOff)
        XCTAssertEqual(document, beforeRelease)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 01 .. ...")
        XCTAssertNotEqual(document.pattern.rows[0][0].note, TrackerNoteKeyMap.keyOffNoteValue)
    }

    func testEditorInputPolicyEditModeOffBlankNoteKeyDoesNotMutatePatternData() {
        var document = BlankTrackerDocument.makeDefault()
        let beforeInput = document
        let route = EditorNoteAuditionInputPolicy.route(
            input: .noteKey(isRepeat: false),
            editModeEnabled: false,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: true
        )
        let request = EditorNoteAuditionRequest.noteOn(
            trackerKey: "z",
            selectedOctave: 4,
            selection: document.selection,
            sourceContext: document.noteAuditionSourceContext,
            channelIndex: 0,
            rowIndex: 0
        )
        let previewer = EditorNoteAuditionPreviewer(sink: RecordingEditorNoteAuditionPreviewSink())
        let outcome = previewer.preview(request: request, availability: document.noteAuditionAvailability)

        XCTAssertTrue(route.shouldAttemptPreview)
        XCTAssertFalse(route.shouldMutatePattern)
        XCTAssertEqual(outcome, .skipped(.unavailable(.selectedSampleUnavailable)))
        if route.shouldMutatePattern {
            _ = document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0)
        }
        XCTAssertEqual(document, beforeInput)
        XCTAssertEqual(document.pattern.rows[0][0], .empty)
    }

    func testEditorInputPolicyEditModeOnBlankNoteEntryStillMutatesPatternData() {
        var document = BlankTrackerDocument.makeDefault()
        let route = EditorNoteAuditionInputPolicy.route(
            input: .noteKey(isRepeat: false),
            editModeEnabled: true,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: true
        )

        XCTAssertTrue(route.shouldAttemptPreview)
        XCTAssertTrue(route.shouldMutatePattern)
        XCTAssertFalse(route.shouldConsumeRepeatedNoteKey)
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 01 .. ...")
    }

    func testBlankDocumentWithPaletteNoteEntryWritesSelectedInstrument() {
        let sample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            instrumentPalette: [2: PlaybackInstrument(index: 2, samples: [sample])]
        )

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))

        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 02 .. ...")
    }

    func testEditorInputPolicyEditModeOffLoadedModuleNoteKeyPreviewsWithoutMutation() throws {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let event = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
        let loadedPatternBefore = XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        let route = EditorNoteAuditionInputPolicy.route(
            input: .noteKey(isRepeat: false),
            editModeEnabled: false,
            sourceContext: .loadedModule(patternIndex: 0),
            isNoteField: true
        )

        let outcome = previewer.preview(
            request: event.request,
            availability: .potentiallyAvailable(event.sampleDescriptor),
            keyIdentity: try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "z"))
        )

        XCTAssertTrue(route.shouldAttemptPreview)
        XCTAssertFalse(route.shouldMutatePattern)
        XCTAssertFalse(route.shouldConsumeRepeatedNoteKey)
        XCTAssertTrue(route.shouldConsumeNonMutatingInput(previewOutcome: outcome))
        XCTAssertEqual(outcome, .attempted(event))
        XCTAssertEqual(sink.events, [event])
        XCTAssertEqual(loadedPatternBefore, XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0))
    }

    func testEditorInputPolicyEditModeOnLoadedModulePreviewsButRemainsReadOnly() throws {
        let sink = RecordingEditorNoteAuditionPreviewSink()
        let previewer = EditorNoteAuditionPreviewer(sink: sink)
        let event = try makePreviewEvent(trackerKey: "q", selectedOctave: 4, baseSampleRate: 100)
        let route = EditorNoteAuditionInputPolicy.route(
            input: .noteKey(isRepeat: false),
            editModeEnabled: true,
            sourceContext: .loadedModule(patternIndex: 0),
            isNoteField: true
        )

        let outcome = previewer.preview(
            request: event.request,
            availability: .potentiallyAvailable(event.sampleDescriptor),
            keyIdentity: try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "q"))
        )

        XCTAssertTrue(route.shouldAttemptPreview)
        XCTAssertFalse(route.shouldMutatePattern)
        XCTAssertTrue(route.shouldConsumeNonMutatingInput(previewOutcome: outcome))
        XCTAssertEqual(outcome, .attempted(event))
        XCTAssertEqual(sink.events, [event])
    }

    func testEditorInputPolicyKeyReleaseStopsPreviewInEditAndNonEditModes() throws {
        for editModeEnabled in [true, false] {
            let sink = RecordingEditorNoteAuditionPreviewSink()
            let previewer = EditorNoteAuditionPreviewer(sink: sink)
            let event = try makePreviewEvent(trackerKey: "z", selectedOctave: 4, baseSampleRate: 100)
            let keyIdentity = try XCTUnwrap(EditorNoteAuditionKeyIdentity(trackerKey: "z"))

            XCTAssertTrue(previewer.preview(
                request: event.request,
                availability: .potentiallyAvailable(event.sampleDescriptor),
                keyIdentity: keyIdentity
            ).didAttemptPreview)

            let didStopPreview = previewer.stopPreview(for: keyIdentity)

            XCTAssertTrue(didStopPreview)
            XCTAssertTrue(EditorNoteAuditionInputPolicy.shouldConsumeNoteKeyRelease(
                didStopPreview: didStopPreview,
                editModeEnabled: editModeEnabled,
                isNoteField: true
            ))
            XCTAssertEqual(sink.releasePreviewCount, 1)
            XCTAssertEqual(sink.cancelPreviewCount, 0)
            XCTAssertNil(previewer.activePreviewToken)
        }
    }

    func testEditorInputPolicyKeyReleaseDoesNotWritePatternKeyOffDataInEitherMode() {
        for editModeEnabled in [true, false] {
            var document = BlankTrackerDocument.makeDefault()
            XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
            let beforeRelease = document

            _ = EditorNoteAuditionInputPolicy.shouldConsumeNoteKeyRelease(
                didStopPreview: false,
                editModeEnabled: editModeEnabled,
                isNoteField: true
            )

            XCTAssertEqual(document, beforeRelease)
            XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 01 .. ...")
            XCTAssertNotEqual(document.pattern.rows[0][0].note, TrackerNoteKeyMap.keyOffNoteValue)
        }
    }

    func testEditorInputPolicyBacktickKeyOffOnlyMutatesEditableBlankPattern() {
        var document = BlankTrackerDocument.makeDefault()
        let nonEditBlankRoute = EditorNoteAuditionInputPolicy.route(
            input: .keyOff,
            editModeEnabled: false,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: true
        )
        let editLoadedRoute = EditorNoteAuditionInputPolicy.route(
            input: .keyOff,
            editModeEnabled: true,
            sourceContext: .loadedModule(patternIndex: 0),
            isNoteField: true
        )
        let editBlankInstrumentFieldRoute = EditorNoteAuditionInputPolicy.route(
            input: .keyOff,
            editModeEnabled: true,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: false
        )
        let editBlankRoute = EditorNoteAuditionInputPolicy.route(
            input: .keyOff,
            editModeEnabled: true,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: true
        )

        XCTAssertFalse(nonEditBlankRoute.shouldAttemptPreview)
        XCTAssertFalse(nonEditBlankRoute.shouldMutatePattern)
        XCTAssertFalse(editLoadedRoute.shouldAttemptPreview)
        XCTAssertFalse(editLoadedRoute.shouldMutatePattern)
        XCTAssertFalse(editBlankInstrumentFieldRoute.shouldMutatePattern)
        XCTAssertTrue(editBlankRoute.shouldMutatePattern)
        XCTAssertTrue(document.enterKeyOff(row: 0, channel: 0))
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "=== .. .. ...")
    }

    func testKeyOffEntryDoesNotWriteSelectedInstrument() {
        let sample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            instrumentPalette: [2: PlaybackInstrument(index: 2, samples: [sample])]
        )

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 02 .. ...")
        XCTAssertTrue(document.enterKeyOff(row: 0, channel: 0))

        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "=== .. .. ...")
    }

    func testKeyOffEntryClearsStaleInstrumentAndPreservesOtherCellFields() {
        let sample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            instrumentPalette: [2: PlaybackInstrument(index: 2, samples: [sample])]
        )

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        document.patterns[0].rows[0][0] = XMPatternEventCell(
            note: document.pattern.rows[0][0].note,
            instrument: document.pattern.rows[0][0].instrument,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )

        XCTAssertTrue(document.enterKeyOff(row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0], XMPatternEventCell(
            note: TrackerNoteKeyMap.keyOffNoteValue,
            instrument: 0,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        ))
    }

    func testClearNoteClearsInstrumentAndPreservesVolumeAndEffects() {
        let sample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            instrumentPalette: [2: PlaybackInstrument(index: 2, samples: [sample])]
        )

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 02 .. ...")
        document.patterns[0].rows[0][0] = XMPatternEventCell(
            note: document.pattern.rows[0][0].note,
            instrument: document.pattern.rows[0][0].instrument,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )

        XCTAssertTrue(document.clearNote(row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0], XMPatternEventCell(
            note: 0,
            instrument: 0,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        ))
    }

    func testInstrumentFieldClearPreservesNoteVolumeAndEffects() {
        let sample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            instrumentPalette: [2: PlaybackInstrument(index: 2, samples: [sample])]
        )

        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: 0, channel: 0))
        document.patterns[0].rows[0][0] = XMPatternEventCell(
            note: document.pattern.rows[0][0].note,
            instrument: document.pattern.rows[0][0].instrument,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )

        XCTAssertTrue(document.clearField(.instrument, row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0], XMPatternEventCell(
            note: 51,
            instrument: 0,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        ))
    }

    func testEditorInputPolicyDeleteClearOnlyMutatesEditableBlankPattern() {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let beforeNonEditClear = document
        let nonEditBlankRoute = EditorNoteAuditionInputPolicy.route(
            input: .clearField,
            editModeEnabled: false,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: true
        )
        let editLoadedRoute = EditorNoteAuditionInputPolicy.route(
            input: .clearField,
            editModeEnabled: true,
            sourceContext: .loadedModule(patternIndex: 0),
            isNoteField: true
        )
        let editLoadedInstrumentFieldRoute = EditorNoteAuditionInputPolicy.route(
            input: .clearField,
            editModeEnabled: true,
            sourceContext: .loadedModule(patternIndex: 0),
            isNoteField: false
        )
        let editBlankRoute = EditorNoteAuditionInputPolicy.route(
            input: .clearField,
            editModeEnabled: true,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: true
        )
        let editBlankInstrumentFieldRoute = EditorNoteAuditionInputPolicy.route(
            input: .clearField,
            editModeEnabled: true,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: false
        )

        XCTAssertFalse(nonEditBlankRoute.shouldMutatePattern)
        XCTAssertFalse(editLoadedRoute.shouldMutatePattern)
        XCTAssertFalse(editLoadedInstrumentFieldRoute.shouldMutatePattern)
        XCTAssertEqual(document, beforeNonEditClear)
        XCTAssertTrue(editBlankRoute.shouldMutatePattern)
        XCTAssertTrue(editBlankInstrumentFieldRoute.shouldMutatePattern)
        XCTAssertTrue(document.clearNote(row: 0, channel: 0))
        XCTAssertEqual(document.pattern.rows[0][0], .empty)
    }

    func testEditorInputPolicySuppressesLoadedModuleAutoRepeatInEditAndNonEditModes() {
        for editModeEnabled in [true, false] {
            let route = EditorNoteAuditionInputPolicy.route(
                input: .noteKey(isRepeat: true),
                editModeEnabled: editModeEnabled,
                sourceContext: .loadedModule(patternIndex: 0),
                isNoteField: true
            )

            XCTAssertFalse(route.shouldAttemptPreview)
            XCTAssertFalse(route.shouldMutatePattern)
            XCTAssertTrue(route.shouldConsumeRepeatedNoteKey)
            XCTAssertTrue(route.shouldConsumeNonMutatingInput(previewOutcome: .skipped(.missingRequest)))
        }
    }

    func testEditableNoteKeyRepeatSuppressesSecondMutationAndRowAdvance() {
        var document = makeBlankDocument(
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)]
        )
        var cursor = PatternCursor(row: 0, channel: 0, field: .note)

        let first = applyPatternEditInput(.noteKey("z", isRepeat: false), to: &document, cursor: &cursor)
        let beforeRepeatDocument = document
        let beforeRepeatCursor = cursor
        let repeatInput = applyPatternEditInput(.noteKey("z", isRepeat: true), to: &document, cursor: &cursor)

        XCTAssertTrue(first.consumed)
        XCTAssertTrue(first.didMutate)
        XCTAssertTrue(first.route.shouldMutatePattern)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 .. .. ...")
        XCTAssertEqual(beforeRepeatCursor, PatternCursor(row: 1, channel: 0, field: .note))
        XCTAssertTrue(repeatInput.consumed)
        XCTAssertFalse(repeatInput.didMutate)
        XCTAssertFalse(repeatInput.route.shouldAttemptPreview)
        XCTAssertFalse(repeatInput.route.shouldMutatePattern)
        XCTAssertTrue(repeatInput.route.shouldConsumeRepeatedNoteKey)
        XCTAssertTrue(repeatInput.route.shouldSuppressRepeatedMutation)
        XCTAssertEqual(document, beforeRepeatDocument)
        XCTAssertEqual(cursor, beforeRepeatCursor)
        XCTAssertEqual(document.pattern.rows[1][0], .empty)
    }

    func testEditableKeyOffRepeatSuppressesSecondMutationAndRowAdvance() {
        var document = makeBlankDocument(
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)]
        )
        var cursor = PatternCursor(row: 0, channel: 0, field: .note)

        let first = applyPatternEditInput(.keyOff, to: &document, cursor: &cursor)
        let beforeRepeatDocument = document
        let beforeRepeatCursor = cursor
        let repeatInput = applyPatternEditInput(.repeatedKeyOff, to: &document, cursor: &cursor)

        XCTAssertTrue(first.consumed)
        XCTAssertTrue(first.didMutate)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "=== .. .. ...")
        XCTAssertEqual(beforeRepeatCursor, PatternCursor(row: 1, channel: 0, field: .note))
        XCTAssertTrue(repeatInput.consumed)
        XCTAssertFalse(repeatInput.didMutate)
        XCTAssertFalse(repeatInput.route.shouldMutatePattern)
        XCTAssertFalse(repeatInput.route.shouldConsumeRepeatedNoteKey)
        XCTAssertTrue(repeatInput.route.shouldSuppressRepeatedMutation)
        XCTAssertEqual(document, beforeRepeatDocument)
        XCTAssertEqual(cursor, beforeRepeatCursor)
        XCTAssertEqual(document.pattern.rows[1][0], .empty)
    }

    func testEditableDeleteRepeatSuppressesSecondClearMutation() {
        let sample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)],
            instrumentPalette: [2: PlaybackInstrument(index: 2, samples: [sample])]
        )
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: 1, channel: 0))
        var cursor = PatternCursor(row: 0, channel: 0, field: .note)

        let first = applyPatternEditInput(.clearField, to: &document, cursor: &cursor)
        let beforeRepeatDocument = document
        let beforeRepeatCursor = cursor
        let repeatInput = applyPatternEditInput(.repeatedClearField, to: &document, cursor: &cursor)

        XCTAssertTrue(first.consumed)
        XCTAssertTrue(first.didMutate)
        XCTAssertEqual(document.pattern.rows[0][0], .empty)
        XCTAssertEqual(beforeRepeatCursor, PatternCursor(row: 1, channel: 0, field: .note))
        XCTAssertTrue(repeatInput.consumed)
        XCTAssertFalse(repeatInput.didMutate)
        XCTAssertFalse(repeatInput.route.shouldMutatePattern)
        XCTAssertTrue(repeatInput.route.shouldSuppressRepeatedMutation)
        XCTAssertEqual(document, beforeRepeatDocument)
        XCTAssertEqual(cursor, beforeRepeatCursor)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[1][0]), "D-4 02 .. ...")
    }

    func testEditableInstrumentFieldDeleteRepeatSuppressesSecondClearMutation() {
        let sample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)],
            instrumentPalette: [2: PlaybackInstrument(index: 2, samples: [sample])]
        )
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: 1, channel: 0))
        var cursor = PatternCursor(row: 0, channel: 0, field: .instrument)

        let first = applyPatternEditInput(.clearField, to: &document, cursor: &cursor)
        let beforeRepeatDocument = document
        let beforeRepeatCursor = cursor
        let repeatInput = applyPatternEditInput(.repeatedClearField, to: &document, cursor: &cursor)

        XCTAssertTrue(first.consumed)
        XCTAssertTrue(first.didMutate)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 .. .. ...")
        XCTAssertEqual(beforeRepeatCursor, PatternCursor(row: 1, channel: 0, field: .instrument))
        XCTAssertTrue(repeatInput.consumed)
        XCTAssertFalse(repeatInput.didMutate)
        XCTAssertEqual(document, beforeRepeatDocument)
        XCTAssertEqual(cursor, beforeRepeatCursor)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[1][0]), "D-4 02 .. ...")
    }

    func testRepeatedMutationInputsDoNotMakeLoadedModulesEditable() {
        let loadedPattern = XMPatternData(
            index: 0,
            rowCount: 1,
            channels: 1,
            rows: [[XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0x40, effectType: 0x0F, effectParam: 0x7D)]]
        )
        let metadata = makeLoadedModuleMetadata(patterns: [loadedPattern])
        let beforeMetadata = metadata
        let inputs: [EditorNoteAuditionInputKind] = [
            .noteKey(isRepeat: true),
            .repeatedKeyOff,
            .repeatedClearField,
        ]

        for input in inputs {
            let route = EditorNoteAuditionInputPolicy.route(
                input: input,
                editModeEnabled: true,
                sourceContext: .loadedModule(patternIndex: 0),
                isNoteField: true
            )

            XCTAssertFalse(route.shouldAttemptPreview)
            XCTAssertFalse(route.shouldMutatePattern)
            XCTAssertTrue(route.shouldSuppressRepeatedMutation)
        }
        XCTAssertEqual(metadata, beforeMetadata)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].note, 49)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].instrument, 1)
    }

    func testDefaultBlankDocumentExposesOneEmptyPattern() {
        let metadata = BlankTrackerDocument.makeDefault().metadata

        XCTAssertEqual(metadata.title, "Untitled")
        XCTAssertEqual(metadata.songLength, 1)
        XCTAssertEqual(metadata.orderTable, [0])
        XCTAssertEqual(metadata.xmPatterns.count, 1)
        XCTAssertEqual(metadata.patterns, 1)
        XCTAssertEqual(metadata.xmPatterns[0].rowCount, 64)
        XCTAssertEqual(metadata.xmPatterns[0].channels, 8)
        XCTAssertEqual(metadata.xmPatterns[0].rows.count, 64)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0].count, 8)
        XCTAssertTrue(metadata.xmPatterns[0].rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
    }

    func testClearCurrentPatternRemovesNotesKeyOffsAndCellFields() {
        var document = BlankTrackerDocument.makeDefault()
        document.patterns[0].rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 0x02,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        document.patterns[0].rows[1][1] = XMPatternEventCell(
            note: TrackerNoteKeyMap.keyOffNoteValue,
            instrument: 0x03,
            volumeColumn: 0x30,
            effectType: 0x0E,
            effectParam: 0x9C
        )

        XCTAssertTrue(document.clearCurrentPattern())

        XCTAssertTrue(document.pattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "... .. .. ...")
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[1][1]), "... .. .. ...")
    }

    func testClearCurrentPatternPreservesSelectionTimingShapeAndOrderState() {
        var document = makeBlankDocument(
            currentPatternIndex: 1,
            tempo: 144,
            speed: 3,
            selection: TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3),
            orderTable: [0, 1],
            patterns: [
                BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 32, channels: 4),
                BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 48, channels: 6)
            ]
        )
        document.patterns[1].rows[2][3] = XMPatternEventCell(
            note: 52,
            instrument: 0x07,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x90
        )

        XCTAssertTrue(document.clearCurrentPattern())

        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3))
        XCTAssertEqual(document.tempo, 144)
        XCTAssertEqual(document.speed, 3)
        XCTAssertEqual(document.pattern.rowCount, 48)
        XCTAssertEqual(document.pattern.channels, 6)
        XCTAssertEqual(document.patterns.count, 2)
        XCTAssertEqual(document.orderTable, [0, 1])
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertTrue(document.pattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
    }

    func testClearCurrentPatternOnlyClearsSelectedPatternWhenMultiplePatternsExist() {
        var first = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 2)
        var second = BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 4, channels: 2)
        first.rows[0][0] = XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        second.rows[1][1] = XMPatternEventCell(
            note: TrackerNoteKeyMap.keyOffNoteValue,
            instrument: 2,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x80
        )
        var document = makeBlankDocument(
            currentPatternIndex: 1,
            orderTable: [0, 1],
            patterns: [first, second]
        )

        XCTAssertTrue(document.clearCurrentPattern())

        XCTAssertEqual(document.pattern(for: 0)?.rows[0][0].note, 49)
        XCTAssertEqual(document.pattern(for: 1)?.rows[1][1], .empty)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern(for: 1)?.rows[1][1] ?? XMPatternEventCell.empty), "... .. .. ...")
    }

    func testAssignPatternToSelectedOrderMutatesOnlySelectedOrderReference() {
        var hiddenPattern = BlankTrackerDocument.makeEmptyPattern(index: 2, rowCount: 8, channels: 1)
        hiddenPattern.rows[3][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        var document = BlankTrackerDocument(
            title: BlankTrackerDocument.defaultTitle,
            songLength: 3,
            currentPosition: 1,
            restartPosition: BlankTrackerDocument.defaultRestartPosition,
            currentPatternIndex: 0,
            tempo: 144,
            speed: 3,
            orderTable: [0, 0, 2],
            selection: TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3),
            instrumentPalette: [:],
            patterns: [
                BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1),
                hiddenPattern,
            ]
        )
        let beforePatterns = document.patterns

        XCTAssertTrue(document.assignPatternToSelectedOrder(2))

        XCTAssertEqual(document.orderTable, [0, 2, 2])
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 2)
        XCTAssertEqual(document.songLength, 3)
        XCTAssertEqual(document.restartPosition, BlankTrackerDocument.defaultRestartPosition)
        XCTAssertEqual(document.tempo, 144)
        XCTAssertEqual(document.speed, 3)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3))
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(document.pattern(for: 2)?.rows[3][0], hiddenPattern.rows[3][0])
    }

    func testAssignPatternToSelectedOrderRejectsMissingPatternAndInvalidSelectedOrderWithoutAllocation() {
        var missingPatternDocument = BlankTrackerDocument.makeDefault()
        let beforeMissingPatternDocument = missingPatternDocument

        XCTAssertFalse(missingPatternDocument.assignPatternToSelectedOrder(12))
        XCTAssertEqual(missingPatternDocument, beforeMissingPatternDocument)
        XCTAssertNil(missingPatternDocument.pattern(for: 12))

        var invalidOrderDocument = BlankTrackerDocument(
            title: BlankTrackerDocument.defaultTitle,
            songLength: 1,
            currentPosition: 1,
            restartPosition: BlankTrackerDocument.defaultRestartPosition,
            currentPatternIndex: 0,
            tempo: BlankTrackerDocument.defaultTempo,
            speed: BlankTrackerDocument.defaultSpeed,
            orderTable: [0],
            selection: .default,
            instrumentPalette: [:],
            patterns: [
                BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1),
                BlankTrackerDocument.makeEmptyPattern(index: 2, rowCount: 4, channels: 1),
            ]
        )
        let beforeInvalidOrderDocument = invalidOrderDocument

        XCTAssertFalse(invalidOrderDocument.assignPatternToSelectedOrder(2))
        XCTAssertEqual(invalidOrderDocument, beforeInvalidOrderDocument)
    }

    func testCreateBlankPatternAndSelectForEditingAllocatesNextPatternWithoutAssigningOrderAndPreservesSongState() {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var sourcePattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 12, channels: 3)
        sourcePattern.rows[2][1] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        var document = BlankTrackerDocument(
            title: BlankTrackerDocument.defaultTitle,
            songLength: 2,
            currentPosition: 1,
            restartPosition: BlankTrackerDocument.defaultRestartPosition,
            currentPatternIndex: 0,
            tempo: 144,
            speed: 3,
            orderTable: [0, 0],
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            instrumentPalette: [1: PlaybackInstrument(index: 1, name: "Lead", samples: [sample])],
            patterns: [sourcePattern]
        )
        let beforePalette = document.instrumentPalette

        XCTAssertTrue(document.createBlankPatternAndSelectForEditing())

        let newPattern = tryUnwrap(document.pattern(for: 1))
        XCTAssertEqual(document.orderTable, [0, 0])
        XCTAssertEqual(document.songLength, 2)
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertEqual(document.tempo, 144)
        XCTAssertEqual(document.speed, 3)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1))
        XCTAssertEqual(document.instrumentPalette, beforePalette)
        XCTAssertEqual(document.pattern(for: 0), sourcePattern)
        XCTAssertEqual(newPattern.rowCount, 12)
        XCTAssertEqual(newPattern.channels, 3)
        XCTAssertTrue(newPattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
    }

    func testCreateBlankPatternMultipleTimesAllocatesUniquePatternsAcrossBankBoundary() {
        var document = makeBlankDocument(
            currentPatternIndex: 0,
            orderTable: [0],
            patterns: (0..<SongOrderEditorDisplayState.bankSize).map { patternIndex in
                BlankTrackerDocument.makeEmptyPattern(index: patternIndex, rowCount: 6, channels: 2)
            }
        )

        XCTAssertTrue(document.createBlankPatternAndSelectForEditing())
        XCTAssertTrue(document.createBlankPatternAndSelectForEditing())

        XCTAssertNotNil(document.pattern(for: 64))
        XCTAssertNotNil(document.pattern(for: 65))
        XCTAssertEqual(Array(document.patterns.map(\.index).suffix(2)), [64, 65])
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 65)
        XCTAssertEqual(document.pattern(for: 65)?.rowCount, 6)
        XCTAssertEqual(document.pattern(for: 65)?.channels, 2)
    }

    func testCreateBlankPatternAndSelectForEditingDoesNotRequireSelectedOrderAssignment() {
        var document = BlankTrackerDocument(
            title: BlankTrackerDocument.defaultTitle,
            songLength: 1,
            currentPosition: 1,
            restartPosition: BlankTrackerDocument.defaultRestartPosition,
            currentPatternIndex: 0,
            tempo: BlankTrackerDocument.defaultTempo,
            speed: BlankTrackerDocument.defaultSpeed,
            orderTable: [0],
            selection: .default,
            instrumentPalette: [:],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)]
        )
        XCTAssertTrue(document.createBlankPatternAndSelectForEditing())
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertNotNil(document.pattern(for: 1))
    }

    func testInsertOrderAfterSelectedReferencesSelectedPatternAndPreservesPatternData() {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 16, channels: 2)
        pattern.rows[3][1] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        var document = makeBlankDocument(
            tempo: 144,
            speed: 3,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            orderTable: [0],
            patterns: [pattern],
            instrumentPalette: [1: PlaybackInstrument(index: 1, name: "Lead", samples: [sample])]
        )
        let beforePatterns = document.patterns
        let beforePalette = document.instrumentPalette

        XCTAssertTrue(document.insertOrderAfterSelected())

        let content = ControlPanelDisplayState.blankDocumentContent(
            for: document,
            selectedOctave: 6,
            isLoopEnabled: true,
            isEditModeEnabled: true,
            isPlaybackActive: false
        )
        XCTAssertEqual(document.orderTable, [0, 0])
        XCTAssertEqual(document.songLength, 2)
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 0)
        XCTAssertEqual(document.tempo, 144)
        XCTAssertEqual(document.speed, 3)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1))
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(document.instrumentPalette, beforePalette)
        XCTAssertEqual(document.pattern(for: 0)?.rows[3][1], pattern.rows[3][1])
        XCTAssertEqual(content.songPosition, "01")
        XCTAssertEqual(content.songLength, "02")
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: document.currentPatternIndex), "000")
    }

    func testInsertOrderAfterSelectedInMiddlePreservesSurroundingOrderReferences() {
        var document = makeBlankDocument(
            currentPatternIndex: 1,
            orderTable: [0, 1, 2],
            patterns: [
                BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 16, channels: 1),
                BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 32, channels: 1),
                BlankTrackerDocument.makeEmptyPattern(index: 2, rowCount: 48, channels: 1),
            ]
        )
        let beforePatterns = document.patterns

        XCTAssertTrue(document.insertOrderAfterSelected())

        XCTAssertEqual(document.orderTable, [0, 1, 1, 2])
        XCTAssertEqual(document.songLength, 4)
        XCTAssertEqual(document.currentPosition, 2)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(document.controlPanelMetadata.songPosition, "02")
    }

    func testDeleteSelectedOrderRemovesSlotWithoutDeletingReferencedPatternData() {
        var thirdPattern = BlankTrackerDocument.makeEmptyPattern(index: 2, rowCount: 48, channels: 1)
        thirdPattern.rows[7][0] = XMPatternEventCell(
            note: 52,
            instrument: 1,
            volumeColumn: 0x30,
            effectType: 0x0C,
            effectParam: 0x40
        )
        var document = makeBlankDocument(
            currentPatternIndex: 1,
            orderTable: [0, 1, 2],
            patterns: [
                BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 16, channels: 1),
                BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 32, channels: 1),
                thirdPattern,
            ]
        )
        let beforePatterns = document.patterns

        XCTAssertTrue(document.deleteSelectedOrder())

        XCTAssertEqual(document.orderTable, [0, 2])
        XCTAssertEqual(document.songLength, 2)
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 2)
        XCTAssertEqual(document.patterns, beforePatterns)
        XCTAssertEqual(document.pattern(for: 2)?.rows[7][0], thirdPattern.rows[7][0])
        XCTAssertEqual(document.controlPanelMetadata.songPosition, "01")
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: document.currentPatternIndex), "002")
        XCTAssertEqual(document.controlPanelMetadata.patternRowCount, "48")
    }

    func testDeleteSelectedOrderLastAndOnlyOrderStaySafe() {
        var document = makeBlankDocument(
            currentPatternIndex: 2,
            orderTable: [0, 1, 2],
            patterns: [
                BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 16, channels: 1),
                BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 32, channels: 1),
                BlankTrackerDocument.makeEmptyPattern(index: 2, rowCount: 48, channels: 1),
            ]
        )
        let beforePatterns = document.patterns

        XCTAssertTrue(document.deleteSelectedOrder())

        XCTAssertEqual(document.orderTable, [0, 1])
        XCTAssertEqual(document.songLength, 2)
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertEqual(document.patterns, beforePatterns)

        XCTAssertTrue(document.deleteSelectedOrder())
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.songLength, 1)
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 0)
        XCTAssertEqual(document.patterns, beforePatterns)

        let onlyOrderBefore = document
        XCTAssertFalse(document.deleteSelectedOrder())
        XCTAssertEqual(document, onlyOrderBefore)
        XCTAssertEqual(document.songLength, 1)
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertNotNil(document.pattern(for: document.orderTable[0]))
    }

    func testClearCurrentPatternOnAlreadyEmptyBlankPatternIsSafe() {
        var document = BlankTrackerDocument.makeDefault()
        let before = document

        XCTAssertTrue(document.clearCurrentPattern())

        XCTAssertEqual(document, before)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "... .. .. ...")
    }

    func testLoadedModuleClearCurrentPatternIsUnavailableAndDoesNotMutateMetadata() {
        let loadedPattern = XMPatternData(
            index: 0,
            rowCount: 1,
            channels: 1,
            rows: [[XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)]]
        )
        let metadata = ParsedModuleMetadata(
            type: "XM",
            title: "Loaded Module",
            version: "1.04",
            channels: 1,
            patterns: 1,
            instruments: 1,
            xmFlags: 0x0001,
            defaultTempo: 6,
            defaultBPM: 125,
            songLength: 1,
            restartPosition: 0,
            orderTable: [0],
            xmPatterns: [loadedPattern]
        )
        let before = metadata

        XCTAssertFalse(EditorCommandAvailability.canClearCurrentPattern(
            hasBlankDocument: false,
            sourceContext: .loadedModule(patternIndex: 0)
        ))
        XCTAssertEqual(metadata, before)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].note, 49)
    }

    func testClearedPatternDisplayRendersEmptyNoteCells() {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.enterKeyOff(row: 1, channel: 0))
        XCTAssertTrue(document.clearCurrentPattern())

        let renderedRows = ModuleMetadataLoader.renderXMPatternRows(document.pattern)

        XCTAssertTrue(renderedRows.gridText.contains("... .. .. ..."))
        XCTAssertFalse(renderedRows.gridText.contains("C-4"))
        XCTAssertFalse(renderedRows.gridText.contains("==="))
    }

    func testClearSongDataRemovesNotesKeyOffsAndCellFieldsAcrossMultiplePatterns() {
        var first = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 32, channels: 4)
        var second = BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 32, channels: 4)
        first.rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 0x02,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        first.rows[8][1] = XMPatternEventCell(
            note: TrackerNoteKeyMap.keyOffNoteValue,
            instrument: 0x03,
            volumeColumn: 0x30,
            effectType: 0x0E,
            effectParam: 0x9C
        )
        second.rows[2][2] = XMPatternEventCell(
            note: 55,
            instrument: 0x04,
            volumeColumn: 0x20,
            effectType: 0x0A,
            effectParam: 0x10
        )
        var document = makeBlankDocument(
            currentPatternIndex: 1,
            orderTable: [0, 1],
            patterns: [first, second]
        )

        document.clearSongData()

        XCTAssertEqual(document.patterns.count, 1)
        XCTAssertTrue(document.pattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "... .. .. ...")
        XCTAssertFalse(ModuleMetadataLoader.renderXMPatternRows(document.pattern).gridText.contains("==="))
        XCTAssertFalse(ModuleMetadataLoader.renderXMPatternRows(document.pattern).gridText.contains("C-4"))
    }

    func testClearSongDataResetsOrderStateToSimpleBlankSong() {
        var first = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 16, channels: 2)
        var second = BlankTrackerDocument.makeEmptyPattern(index: 1, rowCount: 48, channels: 6)
        first.rows[0][0] = XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        second.rows[4][3] = XMPatternEventCell(note: 52, instrument: 2, volumeColumn: 0, effectType: 0, effectParam: 0)
        var document = makeBlankDocument(
            currentPatternIndex: 1,
            orderTable: [0, 1, 0],
            patterns: [first, second]
        )

        document.clearSongData()

        XCTAssertEqual(document.songLength, 1)
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 0)
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.patterns.map(\.index), [0])
        XCTAssertEqual(document.metadata.songLength, 1)
        XCTAssertEqual(document.metadata.orderTable, [0])
        XCTAssertEqual(document.metadata.patterns, 1)
        XCTAssertEqual(document.metadata.xmPatterns.map(\.index), [0])
    }

    func testClearSongDataEditorResetPositionStartsAtFirstNoteCell() {
        XCTAssertEqual(
            EditorClearSongDataResetPosition.start,
            EditorClearSongDataResetPosition(row: 0, channel: 0, fieldRawValue: 0)
        )
    }

    func testClearSongDataPreservesSelectionTimingAndPatternShape() {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 3, rowCount: 48, channels: 6)
        pattern.rows[2][3] = XMPatternEventCell(
            note: 52,
            instrument: 0x07,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x90
        )
        var document = makeBlankDocument(
            currentPatternIndex: 3,
            tempo: 144,
            speed: 3,
            selection: TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3),
            orderTable: [3],
            patterns: [pattern]
        )

        document.clearSongData()

        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3))
        XCTAssertEqual(document.tempo, 144)
        XCTAssertEqual(document.speed, 3)
        XCTAssertEqual(document.pattern.rowCount, 48)
        XCTAssertEqual(document.pattern.channels, 6)
        XCTAssertEqual(document.controlPanelMetadata.selectedInstrumentDisplay, "I07")
        XCTAssertEqual(document.controlPanelMetadata.selectedSampleDisplay, "S03")
        XCTAssertEqual(document.controlPanelMetadata.tempo, "144")
        XCTAssertEqual(document.controlPanelMetadata.speed, "03")
        XCTAssertEqual(document.controlPanelMetadata.patternRowCount, "48")
        XCTAssertEqual(document.controlPanelMetadata.channelCount, "6")
    }

    func testClearSongDataPreservesBlankDocumentInstrumentSamplePaletteStateRepresentedBySelection() {
        var document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 0x10, selectedSample: 0x04)
        )

        document.clearSongData()

        XCTAssertEqual(document.selection.selectedInstrument, 0x10)
        XCTAssertEqual(document.selection.selectedSample, 0x04)
        XCTAssertEqual(document.metadata.instruments, 0)
        XCTAssertEqual(document.noteAuditionAvailability, .unavailable(.blankDocumentMissingInstrumentSamplePayload))
    }

    func testClearSongDataClearsCellsWhilePreservingPaletteAndSelection() {
        let sample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 16, channels: 2)
        pattern.rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 2,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        var document = makeBlankDocument(
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            patterns: [pattern],
            instrumentPalette: [2: PlaybackInstrument(index: 2, name: "Lead", samples: [sample])]
        )

        document.clearSongData()

        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))
        XCTAssertEqual(document.instrumentPalette[2]?.name, "Lead")
        XCTAssertEqual(document.controlPanelMetadata.selectedInstrumentDisplay, "I02 Lead")
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "... .. .. ...")
        XCTAssertTrue(document.pattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
    }

    func testClearSongDataOnAlreadyEmptyBlankDocumentIsSafe() {
        var document = BlankTrackerDocument.makeDefault()
        let before = document

        document.clearSongData()

        XCTAssertEqual(document, before)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "... .. .. ...")
    }

    func testLoadedModuleClearSongDataAvailabilityRequiresEditableCopyPalette() {
        let loadedPattern = XMPatternData(
            index: 0,
            rowCount: 1,
            channels: 1,
            rows: [[XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0x40, effectType: 0x0F, effectParam: 0x7D)]]
        )
        let metadata = ParsedModuleMetadata(
            type: "XM",
            title: "Loaded Module",
            version: "1.04",
            channels: 1,
            patterns: 1,
            instruments: 1,
            xmFlags: 0x0001,
            defaultTempo: 6,
            defaultBPM: 125,
            songLength: 1,
            restartPosition: 0,
            orderTable: [0],
            xmPatterns: [loadedPattern]
        )
        let before = metadata

        XCTAssertFalse(EditorCommandAvailability.canClearSongData(
            hasBlankDocument: false,
            sourceContext: .loadedModule(patternIndex: 0)
        ))
        XCTAssertTrue(EditorCommandAvailability.canClearSongData(
            hasBlankDocument: false,
            sourceContext: .loadedModule(patternIndex: 0),
            loadedModuleCanMakeEditableCopy: true
        ))
        XCTAssertEqual(metadata, before)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].note, 49)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].instrument, 1)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].volumeColumn, 0x40)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].effectType, 0x0F)
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].effectParam, 0x7D)
    }

    func testClearSongDataDisplayRendersEmptyCellsAfterRefreshInput() {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.enterKeyOff(row: 1, channel: 0))

        document.clearSongData()
        let renderedRows = ModuleMetadataLoader.renderXMPatternRows(document.pattern)

        XCTAssertTrue(renderedRows.gridText.contains("... .. .. ..."))
        XCTAssertFalse(renderedRows.gridText.contains("C-4"))
        XCTAssertFalse(renderedRows.gridText.contains("==="))
    }

    func testLoadedModuleClearSongDataCreatesEditableDocumentWithoutMutatingSourceData() {
        let loadedPattern = XMPatternData(
            index: 2,
            rowCount: 16,
            channels: 3,
            rows: [
                [
                    XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0x40, effectType: 0x0F, effectParam: 0x7D),
                    XMPatternEventCell.empty,
                    XMPatternEventCell.empty
                ]
            ] + Array(repeating: Array(repeating: XMPatternEventCell.empty, count: 3), count: 15)
        )
        let metadata = makeLoadedModuleMetadata(
            channels: 3,
            defaultTempo: 5,
            defaultBPM: 140,
            orderTable: [2],
            patterns: [loadedPattern]
        )
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            name: "Kick",
            pcm: [0.25, -0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 16],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, name: "Drums", samples: [sample])]
        )
        let beforeMetadata = metadata
        let beforeSong = song

        let document = BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourcePatternIndex: 2
        )

        let editable = tryUnwrap(document)
        XCTAssertEqual(metadata, beforeMetadata)
        XCTAssertEqual(song, beforeSong)
        XCTAssertEqual(editable.songLength, 1)
        XCTAssertEqual(editable.currentPosition, 0)
        XCTAssertEqual(editable.currentPatternIndex, 0)
        XCTAssertEqual(editable.orderTable, [0])
        XCTAssertEqual(editable.pattern.index, 0)
        XCTAssertEqual(editable.pattern.rowCount, 16)
        XCTAssertEqual(editable.pattern.channels, 3)
        XCTAssertEqual(editable.tempo, 140)
        XCTAssertEqual(editable.speed, 5)
        XCTAssertTrue(editable.pattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
        XCTAssertEqual(metadata.xmPatterns[0].rows[0][0].note, 49)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(editable.pattern.rows[0][0]), "... .. .. ...")
    }

    func testLoadedModuleEditableCopyUsesPaletteForNonXMSource() {
        let metadata = makeLoadedModuleMetadata(
            type: "MOD",
            channels: 4,
            instruments: 1,
            defaultTempo: 6,
            defaultBPM: 125,
            orderTable: [0],
            patterns: []
        )
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            name: "MOD Sample",
            pcm: [0.25, -0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, name: "MOD Inst", samples: [sample])]
        )

        let document = tryUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))

        XCTAssertEqual(metadata.type, "MOD")
        XCTAssertEqual(document.metadata.type, "XM")
        XCTAssertEqual(document.pattern.channels, 4)
        XCTAssertEqual(document.pattern.rowCount, BlankTrackerDocument.defaultRowCount)
        XCTAssertEqual(document.controlPanelMetadata.selectedInstrumentDisplay, "I01 MOD Inst")
        XCTAssertEqual(document.controlPanelMetadata.selectedSampleDisplay, "S01 MOD Sample")
        XCTAssertTrue(document.pattern.rows.allSatisfy { row in
            row.allSatisfy { $0 == .empty }
        })
    }

    func testLoadedModuleEditableCopyPreservesSelectedInstrumentSampleAndDisplayNames() {
        let metadata = makeLoadedModuleMetadata(instruments: 2)
        let firstSample = makePlaybackSample(
            instrumentIndex: 2,
            sampleIndex: 0,
            name: "Lead A",
            pcm: [0.125],
            volume: 1,
            baseSampleRate: 8_363
        )
        let secondSample = makePlaybackSample(
            instrumentIndex: 2,
            sampleIndex: 2,
            name: "Lead C",
            pcm: [0.25, -0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [
                2: PlaybackInstrument(index: 2, name: "Lead", samples: [firstSample, secondSample])
            ]
        )

        let document = tryUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 3)
        ))

        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 3))
        XCTAssertEqual(document.instrumentPalette[2]?.name, "Lead")
        XCTAssertEqual(document.instrumentPalette[2]?.sample(selectedSampleSlot: 3)?.name, "Lead C")
        XCTAssertEqual(document.controlPanelMetadata.selectedInstrumentDisplay, "I02 Lead")
        XCTAssertEqual(document.controlPanelMetadata.selectedInstrumentTooltip, "I02 Lead")
        XCTAssertEqual(document.controlPanelMetadata.selectedSampleDisplay, "S03 Lead C")
        XCTAssertEqual(document.controlPanelMetadata.selectedSampleTooltip, "S03 Lead C")
        XCTAssertEqual(document.metadata.instruments, 2)
        XCTAssertTrue(document.controlPanelMetadata.areInstrumentPlaceholdersEnabled)
    }

    func testLoadedModuleEditableCopyClampsSelectionToAvailablePalette() {
        let metadata = makeLoadedModuleMetadata(instruments: 4)
        let sample = makePlaybackSample(
            instrumentIndex: 4,
            sampleIndex: 1,
            pcm: [0.5],
            volume: 1,
            baseSampleRate: 8_363
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [4: PlaybackInstrument(index: 4, name: "Only", samples: [sample])]
        )

        let document = tryUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))

        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 4, selectedSample: 2))
    }

    func testLoadedModuleEditableCopyPreservesPublicFixtureSamplePayloadForAuditionAvailability() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/basic-instrument-sample.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)

        let document = try XCTUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))

        let sample = try XCTUnwrap(document.instrumentPalette[1]?.sample(selectedSampleSlot: 1))
        XCTAssertEqual(sample.name, "SINE64")
        XCTAssertEqual(sample.sampleLength, 64)
        XCTAssertEqual(sample.pcm.count, 64)
        XCTAssertFalse(sample.pcm.isEmpty)
        XCTAssertTrue(sample.isPlayable)
        guard case let .potentiallyAvailable(descriptor) = document.noteAuditionAvailability else {
            return XCTFail("copied public fixture palette should resolve note audition availability")
        }
        XCTAssertEqual(descriptor.instrumentIndex, 1)
        XCTAssertEqual(descriptor.sampleIndex, 0)
        XCTAssertEqual(descriptor.sampleFrameCount, 64)
        XCTAssertEqual(descriptor.previewPCM.count, 64)
        XCTAssertEqual(descriptor.sourceContext, .blankDocument)
    }

    func testLoadedModuleEditableCopyRemainsEditableForNoteEntry() {
        let metadata = makeLoadedModuleMetadata(channels: 1)
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        var document = tryUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: .default
        ))

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))

        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 01 .. ...")
    }

    func testLoadedModuleEditableCopyClearNoteClearsEnteredInstrument() {
        let metadata = makeLoadedModuleMetadata(channels: 1)
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        var document = tryUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: .default
        ))

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 01 .. ...")
        XCTAssertTrue(document.clearNote(row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0], .empty)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "... .. .. ...")
    }

    func testLoadedModuleEditableCopyTabNavigationMovesAcrossNoteFieldsAndWraps() {
        let metadata = makeLoadedModuleMetadata(channels: 3)
        let sample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: 64],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let document = tryUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: .default
        ))
        var cursor = PatternCursor(row: 5, channel: 0, field: .note)

        cursor.move(.nextChannelNote, rowCount: document.pattern.rowCount, channelCount: document.pattern.channels)
        XCTAssertEqual(cursor, PatternCursor(row: 5, channel: 1, field: .note))

        cursor.move(.nextChannelNote, rowCount: document.pattern.rowCount, channelCount: document.pattern.channels)
        XCTAssertEqual(cursor, PatternCursor(row: 5, channel: 2, field: .note))

        cursor.move(.nextChannelNote, rowCount: document.pattern.rowCount, channelCount: document.pattern.channels)
        XCTAssertEqual(cursor, PatternCursor(row: 5, channel: 0, field: .note))
        XCTAssertEqual(document.currentPosition, 0)
        XCTAssertEqual(document.currentPatternIndex, 0)
        XCTAssertEqual(document.orderTable, [0])
        XCTAssertEqual(document.pattern.channels, 3)
        XCTAssertEqual(document.pattern.rows[5], Array(repeating: XMPatternEventCell.empty, count: 3))
    }

    func testEditablePlaybackSongBuilderBuildsSnapshotWithPatternDataAndPalette() throws {
        let sample = makePlaybackSample(
            instrumentIndex: 2,
            sampleIndex: 0,
            name: "Lead Sample",
            pcm: [0.25, -0.25, 0.125],
            volume: 0.75,
            panning: 37,
            relativeNote: -1,
            finetune: 12,
            baseSampleRate: 8_363,
            loopStart: 1,
            loopLength: 2,
            loopType: 1
        )
        let instrument = PlaybackInstrument(
            index: 2,
            name: "Lead",
            samples: [sample],
            noteSampleMap: makeNoteSampleMap()
        )
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 2)
        pattern.rows[1][0] = XMPatternEventCell(
            note: 49,
            instrument: 2,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        )
        let document = makeBlankDocument(
            tempo: 140,
            speed: 3,
            selection: TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1),
            patterns: [pattern],
            instrumentPalette: [2: instrument]
        )

        let song = EditablePlaybackSongBuilder.build(from: document)

        XCTAssertEqual(song.title, BlankTrackerDocument.defaultTitle)
        XCTAssertEqual(song.initialTiming, PlaybackTiming(speed: 3, bpm: 140))
        XCTAssertEqual(song.orders, [PlaybackOrderEntry(orderIndex: 0, patternIndex: 0)])
        let playbackPattern = try XCTUnwrap(song.patternsByIndex[0])
        XCTAssertEqual(playbackPattern.rowCount, 4)
        XCTAssertEqual(playbackPattern.rows[1].cells.count, 2)
        XCTAssertEqual(playbackPattern.rows[1].cells[0], PlaybackCell(
            note: 49,
            instrument: 2,
            volumeColumn: 0x40,
            effectType: 0x0F,
            effectParam: 0x7D
        ))
        XCTAssertEqual(playbackPattern.rows[1].cells[1], PlaybackCell(
            note: 0,
            instrument: 0,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        ))
        XCTAssertEqual(song.instrumentsByIndex[2], instrument)
        XCTAssertEqual(song.instrumentsByIndex[2]?.sample(selectedSampleSlot: 1)?.pcm, sample.pcm)
        XCTAssertEqual(song.instrumentsByIndex[2]?.sample(selectedSampleSlot: 1)?.panning, 37)
        XCTAssertTrue(song.instrumentsByIndex[2]?.sample(selectedSampleSlot: 1)?.isPlayable == true)
        XCTAssertTrue(song.usesLinearFrequencyTable)
    }

    func testDerivedEditableCopyPlaybackSnapshotProducesAdapterPlanEventsAndPreservesSource() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/basic-instrument-sample.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let beforeMetadata = metadata
        let beforeLoadedSong = loadedSong
        var document = try XCTUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let editableSong = EditablePlaybackSongBuilder.build(from: document)
        let plan = RuntimeCMixerAdapterEventPlan.make(song: editableSong, sampleRate: 100)
        let noteTrigger = try XCTUnwrap(plan.events.first { event in
            if case .noteTrigger = event.action {
                return true
            }
            return false
        })

        XCTAssertEqual(metadata, beforeMetadata)
        XCTAssertEqual(loadedSong, beforeLoadedSong)
        XCTAssertTrue(plan.generated)
        XCTAssertEqual(plan.plannedEventCount, 1)
        XCTAssertEqual(noteTrigger.source, PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0))
        XCTAssertEqual(noteTrigger.channelIndex, 0)
        guard case let .noteTrigger(_, _, mapping) = noteTrigger.action else {
            return XCTFail("expected note trigger")
        }
        XCTAssertEqual(mapping.note, 49)
        XCTAssertEqual(mapping.instrumentIndex, 1)
        XCTAssertEqual(mapping.sampleIndex, 0)
        XCTAssertEqual(editableSong.instrumentsByIndex[1]?.firstPlayableSample?.pcm, loadedSong.instrumentsByIndex[1]?.firstPlayableSample?.pcm)
    }

    func testEditablePlaybackSnapshotBuildsCurrentPatternLoopRangeFromAdapterPlan() throws {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25, -0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            tempo: 25,
            speed: 1,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)],
            instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: 2, channel: 0))
        let song = EditablePlaybackSongBuilder.build(from: document)
        let playbackRange = try XCTUnwrap(song.patternLoopRange(containing: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0)))
        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let loopRange = try XCTUnwrap(plan.adapterEventLoopRange(for: playbackRange))

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(playbackRange.orderIndex, 0)
        XCTAssertEqual(playbackRange.patternIndex, 0)
        XCTAssertEqual(loopRange.playbackRange, playbackRange)
        XCTAssertEqual(loopRange.frameCount, 40)
        XCTAssertEqual(loopRange.events.map(\.source), [
            PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 2),
        ])
    }

    func testLoadedModuleDerivedEditableSnapshotBuildsCurrentPatternLoopRangeAndPreservesSource() throws {
        let loadedPattern = XMPatternData(
            index: 2,
            rowCount: 4,
            channels: 1,
            rows: [
                [XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)],
                [XMPatternEventCell.empty],
                [XMPatternEventCell.empty],
                [XMPatternEventCell.empty],
            ]
        )
        let metadata = makeLoadedModuleMetadata(
            defaultTempo: 1,
            defaultBPM: 25,
            orderTable: [2],
            patterns: [loadedPattern]
        )
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25, -0.25], volume: 1, baseSampleRate: 8_363)
        let loadedSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 4],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )
        let beforeMetadata = metadata
        let beforeLoadedSong = loadedSong
        var document = try XCTUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            sourcePatternIndex: 2
        ))

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: 2, channel: 0))
        let editableSong = EditablePlaybackSongBuilder.build(from: document)
        let playbackRange = try XCTUnwrap(editableSong.patternLoopRange(containing: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0)))
        let plan = RuntimeCMixerAdapterEventPlan.make(song: editableSong, sampleRate: 100)
        let loopRange = try XCTUnwrap(plan.adapterEventLoopRange(for: playbackRange))

        XCTAssertEqual(metadata, beforeMetadata)
        XCTAssertEqual(loadedSong, beforeLoadedSong)
        XCTAssertTrue(plan.generated)
        XCTAssertEqual(loopRange.playbackRange.orderIndex, 0)
        XCTAssertEqual(loopRange.playbackRange.patternIndex, 0)
        XCTAssertEqual(loopRange.events.map(\.source), [
            PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 2),
        ])
        XCTAssertEqual(editableSong.instrumentsByIndex[1]?.firstPlayableSample?.pcm, loadedSong.instrumentsByIndex[1]?.firstPlayableSample?.pcm)
    }

    @MainActor
    func testEmptyEditableDocumentPlaybackSnapshotIsSilentAndSafe() {
        let document = BlankTrackerDocument.makeDefault()
        let song = EditablePlaybackSongBuilder.build(from: document)
        let plan = RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: 100)
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )

        engine.load(song: song)
        engine.play(
            from: PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0),
            loopEnabled: true,
            timingSession: nil
        )

        XCTAssertTrue(plan.generated)
        XCTAssertEqual(plan.plannedEventCount, 0)
        XCTAssertEqual(song.instrumentsByIndex.keys.sorted(), [1])
        XCTAssertEqual(song.instrumentsByIndex[1]?.samples, [])
        XCTAssertEqual(engine.state.mode, .playing)
        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)
        XCTAssertEqual(audioOutput.consumedPatternLoopRanges.first??.orderIndex, 0)
        XCTAssertTrue(audioOutput.configuredPlans.contains { $0.generated && $0.plannedEventCount == 0 })
    }

    func testEditablePlaybackSongBuilderReflectsStoppedEditsInFreshSnapshot() throws {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)],
            instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let firstSnapshot = EditablePlaybackSongBuilder.build(from: document)
        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: 1, channel: 0))
        let secondSnapshot = EditablePlaybackSongBuilder.build(from: document)

        XCTAssertEqual(firstSnapshot.row(at: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0))?.cells[0].note, 49)
        XCTAssertEqual(firstSnapshot.row(at: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1))?.cells[0].note, 0)
        XCTAssertEqual(secondSnapshot.row(at: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0))?.cells[0].note, 49)
        XCTAssertEqual(secondSnapshot.row(at: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1))?.cells[0].note, 51)
    }

    @MainActor
    func testActiveEditableLoopEditRefreshUsesMutatedDocumentSnapshot() async throws {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            tempo: 25,
            speed: 1,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)],
            instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0)

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)

        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: 1, channel: 0))
        engine.requestEditablePatternLoopRefresh(song: EditablePlaybackSongBuilder.build(from: document))

        XCTAssertEqual(prewarmScheduler.requests.count, 2)
        XCTAssertEqual(
            prewarmScheduler.requests.last?.song.row(at: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1))?.cells[0].note,
            51
        )

        prewarmScheduler.complete(at: 1)
        await Task.yield()

        let pendingPlan = try XCTUnwrap(engine.pendingEditablePatternLoopRefreshPlanForTesting)
        XCTAssertEqual(noteTriggerSources(in: pendingPlan), [
            PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1),
        ])
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 1)
    }

    @MainActor
    func testActiveEditableLoopRepeatedNoteKeyDoesNotRequestSecondRefresh() {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            tempo: 25,
            speed: 1,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)],
            instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0)
        var cursor = PatternCursor(row: 0, channel: 0, field: .note)

        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        XCTAssertTrue(engine.isPatternLoopPlaybackActive)
        let requestCountBeforeMutation = prewarmScheduler.requests.count

        let first = applyPatternEditInput(.noteKey("z", isRepeat: false), to: &document, cursor: &cursor) { refreshedDocument in
            engine.requestEditablePatternLoopRefresh(song: EditablePlaybackSongBuilder.build(from: refreshedDocument))
        }
        let requestCountAfterFirstMutation = prewarmScheduler.requests.count
        let beforeRepeatDocument = document
        let beforeRepeatCursor = cursor
        let repeatInput = applyPatternEditInput(.noteKey("z", isRepeat: true), to: &document, cursor: &cursor) { refreshedDocument in
            engine.requestEditablePatternLoopRefresh(song: EditablePlaybackSongBuilder.build(from: refreshedDocument))
        }

        XCTAssertTrue(first.didMutate)
        XCTAssertEqual(requestCountAfterFirstMutation, requestCountBeforeMutation + 1)
        XCTAssertEqual(prewarmScheduler.requests.last?.song.row(at: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0))?.cells[0].note, 49)
        XCTAssertTrue(repeatInput.consumed)
        XCTAssertFalse(repeatInput.didMutate)
        XCTAssertTrue(repeatInput.route.shouldSuppressRepeatedMutation)
        XCTAssertEqual(prewarmScheduler.requests.count, requestCountAfterFirstMutation)
        XCTAssertEqual(document, beforeRepeatDocument)
        XCTAssertEqual(cursor, beforeRepeatCursor)
        XCTAssertEqual(document.pattern.rows[1][0], .empty)
    }

    @MainActor
    func testActiveEditableLoopTabNavigationChangesCursorOnlyWithoutRefresh() throws {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            tempo: 25,
            speed: 1,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 2)],
            instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0)

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let beforeNavigation = document
        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        XCTAssertTrue(engine.isPatternLoopPlaybackActive)
        let prewarmRequestCount = prewarmScheduler.requests.count
        let pendingRefreshBeforeNavigation = engine.hasPendingEditablePatternLoopRefreshForTesting
        let generatedPlanConfigureCount = audioOutput.generatedPlanConfigureCount
        var cursor = PatternCursor(row: 1, channel: 0, field: .effectParam)

        cursor.move(.nextChannelNote, rowCount: document.pattern.rowCount, channelCount: document.pattern.channels)

        XCTAssertEqual(cursor, PatternCursor(row: 1, channel: 1, field: .note))
        XCTAssertEqual(document, beforeNavigation)
        XCTAssertEqual(prewarmScheduler.requests.count, prewarmRequestCount)
        XCTAssertEqual(engine.hasPendingEditablePatternLoopRefreshForTesting, pendingRefreshBeforeNavigation)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, generatedPlanConfigureCount)
    }

    @MainActor
    func testActiveEditableLoopSelectionChangeDoesNotMutatePatternOrRefreshPlayback() {
        var document = makeTwoInstrumentLoadedModuleEditableDocument(channels: 2, rowCount: 4)
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0)

        let beforeSelection = document.selection
        let beforePattern = document.pattern
        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        let prewarmRequestCount = prewarmScheduler.requests.count
        let pendingRefreshBeforeSelection = engine.hasPendingEditablePatternLoopRefreshForTesting
        let generatedPlanConfigureCount = audioOutput.generatedPlanConfigureCount
        let selectedOctave = 6

        document.selectInstrument(2)
        document.selectSample(1)

        XCTAssertEqual(beforeSelection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1))
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 2, selectedSample: 1))
        XCTAssertEqual(selectedOctave, 6)
        XCTAssertEqual(document.pattern, beforePattern)
        XCTAssertTrue(engine.isPatternLoopPlaybackActive)
        XCTAssertEqual(prewarmScheduler.requests.count, prewarmRequestCount)
        XCTAssertEqual(engine.hasPendingEditablePatternLoopRefreshForTesting, pendingRefreshBeforeSelection)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, generatedPlanConfigureCount)
    }

    @MainActor
    func testActiveEditableLoopSampleChangeDoesNotMutatePatternOrRefreshPlaybackAndUpdatesAudition() {
        var document = makeTwoSampleLoadedModuleEditableDocument(rowCount: 4)
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0)

        let beforePattern = document.pattern
        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        let prewarmRequestCount = prewarmScheduler.requests.count
        let pendingRefreshBeforeSelection = engine.hasPendingEditablePatternLoopRefreshForTesting
        let generatedPlanConfigureCount = audioOutput.generatedPlanConfigureCount

        document.selectSample(2)

        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(document.pattern, beforePattern)
        XCTAssertTrue(engine.isPatternLoopPlaybackActive)
        XCTAssertEqual(prewarmScheduler.requests.count, prewarmRequestCount)
        XCTAssertEqual(engine.hasPendingEditablePatternLoopRefreshForTesting, pendingRefreshBeforeSelection)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, generatedPlanConfigureCount)

        guard case let .potentiallyAvailable(descriptor) = document.noteAuditionAvailability else {
            return XCTFail("expected second sample to be available for audition")
        }
        XCTAssertEqual(descriptor.instrumentIndex, 1)
        XCTAssertEqual(descriptor.sampleIndex, 1)
        XCTAssertEqual(descriptor.previewPCM, [0.75, -0.75, 0.75])
        XCTAssertEqual(descriptor.sourceContext, .blankDocument)
    }

    @MainActor
    func testActiveEditableLoopNoteEntryAfterInstrumentChangeRefreshesWithSelectedInstrument() async throws {
        var document = makeTwoInstrumentLoadedModuleEditableDocument(channels: 1, rowCount: 4)
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0)

        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        let prewarmRequestCount = prewarmScheduler.requests.count
        document.selectInstrument(2)
        XCTAssertEqual(prewarmScheduler.requests.count, prewarmRequestCount)

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 1, channel: 0))
        engine.requestEditablePatternLoopRefresh(song: EditablePlaybackSongBuilder.build(from: document))

        XCTAssertEqual(document.pattern.rows[1][0].note, 49)
        XCTAssertEqual(document.pattern.rows[1][0].instrument, 2)
        XCTAssertEqual(prewarmScheduler.requests.count, prewarmRequestCount + 1)
        XCTAssertEqual(
            prewarmScheduler.requests.last?.song.row(at: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1))?.cells[0],
            PlaybackCell(note: 49, instrument: 2, volumeColumn: 0, effectType: 0, effectParam: 0)
        )

        prewarmScheduler.complete(at: prewarmScheduler.requests.count - 1)
        await Task.yield()

        let pendingPlan = try XCTUnwrap(engine.pendingEditablePatternLoopRefreshPlanForTesting)
        XCTAssertEqual(noteTriggerSummaries(in: pendingPlan), [
            NoteTriggerSummary(
                source: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1),
                channelIndex: 0,
                note: 49,
                instrumentIndex: 2,
                sampleIndex: 0
            )
        ])
    }

    @MainActor
    func testActiveEditableLoopTabThenInstrumentChangeWritesNextChannelWithNewInstrument() async throws {
        var document = makeTwoInstrumentLoadedModuleEditableDocument(channels: 2, rowCount: 4)
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0)
        var cursor = PatternCursor(row: 0, channel: 0, field: .note)

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: cursor.row, channel: cursor.channel))
        cursor.row = TrackerEditStep.advancedRow(after: cursor.row, rowCount: document.pattern.rowCount)
        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        let prewarmRequestCount = prewarmScheduler.requests.count

        cursor.move(.nextChannelNote, rowCount: document.pattern.rowCount, channelCount: document.pattern.channels)
        document.selectInstrument(2)
        XCTAssertEqual(prewarmScheduler.requests.count, prewarmRequestCount)
        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: cursor.row, channel: cursor.channel))
        engine.requestEditablePatternLoopRefresh(song: EditablePlaybackSongBuilder.build(from: document))
        prewarmScheduler.complete(at: prewarmScheduler.requests.count - 1)
        await Task.yield()

        XCTAssertEqual(cursor, PatternCursor(row: 1, channel: 1, field: .note))
        XCTAssertEqual(document.pattern.rows[0][0].instrument, 1)
        XCTAssertEqual(document.pattern.rows[1][1].note, 51)
        XCTAssertEqual(document.pattern.rows[1][1].instrument, 2)

        let pendingPlan = try XCTUnwrap(engine.pendingEditablePatternLoopRefreshPlanForTesting)
        XCTAssertEqual(noteTriggerSummaries(in: pendingPlan), [
            NoteTriggerSummary(
                source: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0),
                channelIndex: 0,
                note: 49,
                instrumentIndex: 1,
                sampleIndex: 0
            ),
            NoteTriggerSummary(
                source: PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1),
                channelIndex: 1,
                note: 51,
                instrumentIndex: 2,
                sampleIndex: 0
            )
        ])
    }

    func testEditableAuditionAvailabilityUsesChangedSelectedInstrument() throws {
        var document = makeTwoInstrumentLoadedModuleEditableDocument(channels: 1, rowCount: 4)

        guard case let .potentiallyAvailable(firstDescriptor) = document.noteAuditionAvailability else {
            return XCTFail("expected first instrument to be available for audition")
        }

        document.selectInstrument(2)

        guard case let .potentiallyAvailable(secondDescriptor) = document.noteAuditionAvailability else {
            return XCTFail("expected second instrument to be available for audition")
        }

        XCTAssertEqual(firstDescriptor.instrumentIndex, 1)
        XCTAssertEqual(firstDescriptor.sampleIndex, 0)
        XCTAssertEqual(secondDescriptor.instrumentIndex, 2)
        XCTAssertEqual(secondDescriptor.sampleIndex, 0)
        XCTAssertEqual(secondDescriptor.previewPCM, [0.5, -0.5, 0.5])
        XCTAssertEqual(secondDescriptor.sourceContext, .blankDocument)
    }

    @MainActor
    func testActiveEditableLoopClearNoteRefreshUsesClearedSnapshot() async throws {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            tempo: 25,
            speed: 1,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)],
            instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0)

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)

        XCTAssertTrue(document.clearNote(row: 0, channel: 0))
        engine.requestEditablePatternLoopRefresh(song: EditablePlaybackSongBuilder.build(from: document))
        prewarmScheduler.complete(at: 1)
        await Task.yield()

        let pendingPlan = try XCTUnwrap(engine.pendingEditablePatternLoopRefreshPlanForTesting)
        XCTAssertEqual(document.pattern.rows[0][0], .empty)
        XCTAssertEqual(pendingPlan.plannedEventCount, 0)
        XCTAssertTrue(noteTriggerSources(in: pendingPlan).isEmpty)
    }

    @MainActor
    func testActiveEditableLoopRefreshWithoutPlayableSamplesIsSilentAndSafe() async throws {
        var document = makeBlankDocument(
            tempo: 25,
            speed: 1,
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)]
        )
        let prewarmScheduler = TestRuntimeAdapterPlanPrewarmScheduler()
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: prewarmScheduler
        )
        let initialSong = EditablePlaybackSongBuilder.build(from: document)

        engine.load(song: initialSong)
        engine.play(
            from: PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0),
            loopEnabled: true,
            timingSession: nil
        )

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 1, channel: 0))
        engine.requestEditablePatternLoopRefresh(song: EditablePlaybackSongBuilder.build(from: document))
        prewarmScheduler.complete(at: 1)
        await Task.yield()

        for _ in 0..<(4 * initialSong.initialTiming.ticksPerRow) {
            engine.advanceOneTick()
        }

        XCTAssertEqual(engine.state.mode, .playing)
        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)
        XCTAssertEqual(audioOutput.generatedPlanConfigureCount, 2)
        XCTAssertEqual(audioOutput.configuredPlans.last?.plannedEventCount, 0)
    }

    @MainActor
    func testEditableLoopStopThenEditThenPlayRebuildsSnapshotAndReappliesLoop() throws {
        let sample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, baseSampleRate: 8_363)
        var document = makeBlankDocument(
            tempo: 25,
            speed: 1,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)],
            instrumentPalette: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let audioOutput = TestRuntimeAdapterAudioOutput(audioBufferSampleRate: 100)
        let engine = PlaybackEngine(
            audioEngine: audioOutput,
            startsRealtimeTimer: false,
            runtimeAdapterPlanPrewarmScheduler: TestRuntimeAdapterPlanPrewarmScheduler()
        )
        let startContext = PlaybackStartContext(moduleTitle: document.title, songPosition: 0, patternIndex: 0, row: 0)

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        engine.load(song: EditablePlaybackSongBuilder.build(from: document))
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)
        engine.stop()

        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: 1, channel: 0))
        let secondSnapshot = EditablePlaybackSongBuilder.build(from: document)
        engine.load(song: secondSnapshot)
        engine.play(from: startContext, loopEnabled: true, timingSession: nil)

        let latestGeneratedPlan = try XCTUnwrap(audioOutput.configuredPlans.last { $0.generated })
        XCTAssertEqual(latestGeneratedPlan.plannedEventCount, 2)
        XCTAssertEqual(latestGeneratedPlan.events.map(\.source), [
            PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 1),
        ])
        XCTAssertEqual(audioOutput.consumedPatternLoopRanges.compactMap { $0?.orderIndex }, [0, 0])
    }

    func testBlankDocumentControlPanelMetadataIsSane() {
        let metadata = BlankTrackerDocument.makeDefault().controlPanelMetadata

        XCTAssertEqual(metadata.songTitle, "Untitled")
        XCTAssertEqual(metadata.songLength, "01")
        XCTAssertEqual(metadata.songPosition, "00")
        XCTAssertEqual(metadata.restartPosition, "00")
        XCTAssertEqual(metadata.patternRowCount, "64")
        XCTAssertEqual(metadata.channelCount, "8")
        XCTAssertEqual(metadata.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(metadata.selectedInstrumentTooltip, "I01")
        XCTAssertEqual(metadata.selectedSampleDisplay, "S01")
        XCTAssertEqual(metadata.selectedSampleTooltip, "S01")
        XCTAssertEqual(metadata.tempo, "125")
        XCTAssertEqual(metadata.speed, "06")
        XCTAssertEqual(metadata.songPositionValue, 0)
        XCTAssertEqual(metadata.maximumSongPosition, 0)
        XCTAssertFalse(metadata.isSongPositionEnabled)
        XCTAssertTrue(metadata.isPatternControlsEnabled)
        XCTAssertTrue(metadata.areInstrumentPlaceholdersEnabled)
    }

    func testBlankDocumentControlPanelDisplayStateUsesStartupDefaults() {
        let content = ControlPanelDisplayState.blankDocumentContent(
            for: BlankTrackerDocument.makeDefault(),
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false
        )

        XCTAssertEqual(content.songTitle, "Untitled")
        XCTAssertEqual(content.songTime, "--:--")
        XCTAssertEqual(content.songLength, "01")
        XCTAssertEqual(content.songPosition, "00")
        XCTAssertEqual(content.restartPosition, "00")
        XCTAssertEqual(content.patternRowCount, "64")
        XCTAssertEqual(content.channelCount, "8")
        XCTAssertEqual(content.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(content.selectedSampleDisplay, "S01")
        XCTAssertEqual(content.tempo, "125")
        XCTAssertEqual(content.speed, "06")
        XCTAssertEqual(content.selectedOctave, 4)
        XCTAssertEqual(content.songPositionValue, 0)
        XCTAssertEqual(content.maximumSongPosition, 0)
        XCTAssertFalse(content.isSongPositionEnabled)
        XCTAssertTrue(content.isPatternControlsEnabled)
        XCTAssertTrue(content.areInstrumentPlaceholdersEnabled)
    }

    func testBlankDocumentControlPanelDisplayStateKeepsPaletteControlsEnabledDuringPlayback() {
        let document = makeTwoInstrumentLoadedModuleEditableDocument(channels: 2, rowCount: 4)

        let content = ControlPanelDisplayState.blankDocumentContent(
            for: document,
            selectedOctave: 6,
            isLoopEnabled: true,
            isEditModeEnabled: true,
            isPlaybackActive: true
        )

        XCTAssertTrue(content.isPlaybackActive)
        XCTAssertTrue(content.isLoopEnabled)
        XCTAssertTrue(content.isEditModeEnabled)
        XCTAssertTrue(content.isPatternControlsEnabled)
        XCTAssertTrue(content.areInstrumentPlaceholdersEnabled)
        XCTAssertEqual(content.selectedInstrumentDisplay, "I01 Inst A")
        XCTAssertEqual(content.selectedSampleDisplay, "S01 Sample A")
        XCTAssertEqual(content.selectedOctave, 6)
    }

    func testFileNewEquivalentControlPanelDisplayStateReturnsToBlankDefaults() {
        var loadedLikeContent = ControlPanelContent()
        loadedLikeContent.songTitle = "Loaded Module"
        loadedLikeContent.songLength = "12"
        loadedLikeContent.songPosition = "05"
        loadedLikeContent.restartPosition = "02"
        loadedLikeContent.patternRowCount = "48"
        loadedLikeContent.channelCount = "16"
        loadedLikeContent.selectedInstrumentDisplay = "I07"
        loadedLikeContent.selectedSampleDisplay = "S03"
        loadedLikeContent.tempo = "180"
        loadedLikeContent.speed = "03"
        loadedLikeContent.selectedOctave = 7
        loadedLikeContent.isLoopEnabled = true
        loadedLikeContent.isEditModeEnabled = true

        let content = ControlPanelDisplayState.blankDocumentContent(
            for: BlankTrackerDocument.makeDefault(),
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false
        )

        XCTAssertNotEqual(content, loadedLikeContent)
        XCTAssertEqual(content.songTitle, "Untitled")
        XCTAssertEqual(content.songTime, "--:--")
        XCTAssertEqual(content.songLength, "01")
        XCTAssertEqual(content.songPosition, "00")
        XCTAssertEqual(content.restartPosition, "00")
        XCTAssertEqual(content.patternRowCount, "64")
        XCTAssertEqual(content.channelCount, "8")
        XCTAssertEqual(content.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(content.selectedSampleDisplay, "S01")
        XCTAssertEqual(content.tempo, "125")
        XCTAssertEqual(content.speed, "06")
        XCTAssertEqual(content.selectedOctave, 4)
        XCTAssertFalse(content.isLoopEnabled)
        XCTAssertFalse(content.isEditModeEnabled)
    }

    func testFileNewEquivalentResetsSelectedSampleToDefaultSlot() {
        let loadedLikeSelection = TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3)
        let reset = BlankTrackerDocument.makeDefault()

        XCTAssertEqual(loadedLikeSelection.sampleDisplayTitle, "S03")
        XCTAssertEqual(reset.selection.selectedSample, TrackerEditorSelection.defaultSample)
        XCTAssertEqual(reset.controlPanelMetadata.selectedSampleDisplay, "S01")
        XCTAssertEqual(reset.noteAuditionAvailability, .unavailable(.selectedSampleUnavailable))
    }

    func testLoadedModuleControlPanelDisplayStateUsesModuleMetadataAndEditorOctave() {
        let metadata = ParsedModuleMetadata(
            type: "XM",
            title: "Loaded Module",
            version: "1.04",
            channels: 6,
            patterns: 2,
            instruments: 3,
            xmFlags: 0x0001,
            defaultTempo: 3,
            defaultBPM: 180,
            songLength: 12,
            restartPosition: 2,
            orderTable: [1, 0],
            xmPatterns: [
                XMPatternData(index: 0, rowCount: 32, channels: 6, rows: []),
                XMPatternData(index: 1, rowCount: 48, channels: 6, rows: [])
            ]
        )

        let content = ControlPanelDisplayState.loadedModuleContent(
            metadata: metadata,
            selectedSongPositionIndex: 5,
            currentPatternIndex: 1,
            selectedOctave: 7,
            isLoopEnabled: true,
            isEditModeEnabled: true,
            isPlaybackActive: true
        )

        XCTAssertEqual(content.songTitle, "Loaded Module")
        XCTAssertEqual(content.songTime, "--:--")
        XCTAssertEqual(content.songLength, "12")
        XCTAssertEqual(content.songPosition, "05")
        XCTAssertEqual(content.restartPosition, "02")
        XCTAssertEqual(content.patternRowCount, "48")
        XCTAssertEqual(content.channelCount, "6")
        XCTAssertEqual(content.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(content.selectedSampleDisplay, "S01")
        XCTAssertEqual(content.tempo, "180")
        XCTAssertEqual(content.speed, "03")
        XCTAssertEqual(content.selectedOctave, 7)
        XCTAssertEqual(content.songPositionValue, 5)
        XCTAssertEqual(content.maximumSongPosition, 11)
        XCTAssertTrue(content.isLoopEnabled)
        XCTAssertTrue(content.isEditModeEnabled)
        XCTAssertTrue(content.isPlaybackActive)
        XCTAssertTrue(content.isSongPositionEnabled)
        XCTAssertTrue(content.isPatternControlsEnabled)
        XCTAssertTrue(content.areInstrumentPlaceholdersEnabled)
    }

    func testLoadedModuleControlPanelDisplayStateKeepsTimeUnavailableBeforeAdapterPlanReady() {
        let metadata = loadedModuleControlPanelMetadata(title: "Loaded Module")

        let content = ControlPanelDisplayState.loadedModuleContent(
            metadata: metadata,
            selectedSongPositionIndex: 0,
            currentPatternIndex: 0,
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false
        )

        XCTAssertEqual(content.songTitle, "Loaded Module")
        XCTAssertEqual(content.songTime, "--:--")
    }

    func testLoadedModuleControlPanelDisplayStateUsesAdapterPlanSongTime() {
        let metadata = loadedModuleControlPanelMetadata(title: "Loaded Module 03:25")

        let content = ControlPanelDisplayState.loadedModuleContent(
            metadata: metadata,
            selectedSongPositionIndex: 0,
            currentPatternIndex: 0,
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false,
            songTime: ControlPanelDisplayState.songTimeDisplay(durationSeconds: 185)
        )

        XCTAssertEqual(content.songTitle, "Loaded Module 03:25")
        XCTAssertEqual(content.songTime, "03:05")
    }

    func testControlPanelSongTimeDisplayFormatsMinutesAndSeconds() {
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: 0), "00:00")
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: 65), "01:05")
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: 185), "03:05")
    }

    func testControlPanelSongTimeDisplayReturnsUnavailableForInvalidDuration() {
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: nil), "--:--")
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: -Double.infinity), "--:--")
        XCTAssertEqual(ControlPanelDisplayState.songTimeDisplay(durationSeconds: -1), "--:--")
    }

    func testLoadedModuleControlPanelDisplayStateDoesNotInferDurationFromTitleText() {
        let metadata = ParsedModuleMetadata(
            type: "XM",
            title: "Loaded Module 03:25",
            version: "1.04",
            channels: 6,
            patterns: 1,
            instruments: 1,
            xmFlags: 0x0001,
            defaultTempo: 6,
            defaultBPM: 125,
            songLength: 1,
            restartPosition: 0,
            orderTable: [0],
            xmPatterns: [
                XMPatternData(index: 0, rowCount: 64, channels: 6, rows: [])
            ]
        )

        let content = ControlPanelDisplayState.loadedModuleContent(
            metadata: metadata,
            selectedSongPositionIndex: 0,
            currentPatternIndex: 0,
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false
        )

        XCTAssertEqual(content.songTitle, "Loaded Module 03:25")
        XCTAssertEqual(content.songTime, "--:--")
    }

    func testControlPanelPatternDisplayUsesZeroPaddedDecimal() {
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: 0), "000")
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: 12), "012")
        XCTAssertEqual(ControlPanelDisplayState.patternDisplayTitle(patternIndex: 111), "111")
    }

    func testLoadedModuleControlPanelDisplayStateUsesCurrentEditorInstrumentSelection() {
        let metadata = ParsedModuleMetadata(
            type: "XM",
            title: "Loaded Module",
            version: "1.04",
            channels: 4,
            patterns: 1,
            instruments: 8,
            xmFlags: 0x0001,
            defaultTempo: 6,
            defaultBPM: 125,
            songLength: 1,
            restartPosition: 0,
            orderTable: [0],
            xmPatterns: [
                XMPatternData(index: 0, rowCount: 64, channels: 4, rows: [])
            ]
        )

        let content = ControlPanelDisplayState.loadedModuleContent(
            metadata: metadata,
            selection: TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3),
            selectedSongPositionIndex: 0,
            currentPatternIndex: 0,
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: true,
            isPlaybackActive: false
        )

        XCTAssertEqual(content.selectedInstrumentDisplay, "I07")
        XCTAssertEqual(content.selectedSampleDisplay, "S03")
    }

    func testLoadedModuleControlPanelDisplayStateUsesSelectedInstrumentAndSampleNames() {
        let metadata = ParsedModuleMetadata(
            type: "XM",
            title: "Loaded Module",
            version: "1.04",
            channels: 4,
            patterns: 1,
            instruments: 8,
            xmFlags: 0x0001,
            defaultTempo: 6,
            defaultBPM: 125,
            songLength: 1,
            restartPosition: 0,
            orderTable: [0],
            xmPatterns: [
                XMPatternData(index: 0, rowCount: 64, channels: 4, rows: [])
            ]
        )

        let content = ControlPanelDisplayState.loadedModuleContent(
            metadata: metadata,
            selection: TrackerEditorSelection(selectedInstrument: 7, selectedSample: 3),
            selectedSongPositionIndex: 0,
            currentPatternIndex: 0,
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false,
            selectedInstrumentName: "Lead",
            selectedSampleName: "Kick"
        )

        XCTAssertEqual(content.selectedInstrumentDisplay, "I07 Lead")
        XCTAssertEqual(content.selectedInstrumentTooltip, "I07 Lead")
        XCTAssertEqual(content.selectedSampleDisplay, "S03 Kick")
        XCTAssertEqual(content.selectedSampleTooltip, "S03 Kick")
    }

    func testLoadedModuleControlPanelDisplayStateUsesInstrumentAndSampleNamesWhenProvided() {
        let metadata = ParsedModuleMetadata(
            type: "XM",
            title: "Loaded Module",
            version: "1.04",
            channels: 4,
            patterns: 1,
            instruments: 8,
            xmFlags: 0x0001,
            defaultTempo: 6,
            defaultBPM: 125,
            songLength: 1,
            restartPosition: 0,
            orderTable: [0],
            xmPatterns: [
                XMPatternData(index: 0, rowCount: 64, channels: 4, rows: [])
            ]
        )

        let content = ControlPanelDisplayState.loadedModuleContent(
            metadata: metadata,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            selectedSongPositionIndex: 0,
            currentPatternIndex: 0,
            selectedOctave: 4,
            isLoopEnabled: false,
            isEditModeEnabled: false,
            isPlaybackActive: false,
            selectedInstrumentName: "Very Long Instrument",
            selectedSampleName: "Kick"
        )

        XCTAssertEqual(content.selectedInstrumentDisplay, "I01 Very Long...")
        XCTAssertEqual(content.selectedInstrumentTooltip, "I01 Very Long Instrument")
        XCTAssertEqual(content.selectedSampleDisplay, "S01 Kick")
        XCTAssertEqual(content.selectedSampleTooltip, "S01 Kick")
    }

    func testFileNewEquivalentCreatesFreshBlankDocumentState() {
        let previous = BlankTrackerDocument.makeDefault()
        var previousPattern = previous.pattern
        previousPattern.rows[0][0] = XMPatternEventCell(
            note: 48,
            instrument: 1,
            volumeColumn: 0x40,
            effectType: 0,
            effectParam: 0
        )

        let reset = BlankTrackerDocument.makeDefault()

        XCTAssertEqual(reset.pattern.rows[0][0], .empty)
        XCTAssertEqual(reset.selection, .default)
        XCTAssertNotEqual(previousPattern.rows[0][0], reset.pattern.rows[0][0])
    }

    func testEnteringNaturalTrackerNoteMutatesSelectedBlankPatternCell() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0].note, 49)
        XCTAssertEqual(document.pattern.rows[0][1], .empty)
    }

    func testLowerRowNaturalAndSharpTrackerNotesUseSelectedOctave() {
        let expectedNotes: [(Character, UInt8, String)] = [
            ("z", 49, "C-4"),
            ("s", 50, "C#4"),
            ("x", 51, "D-4"),
            ("d", 52, "D#4"),
            ("c", 53, "E-4"),
            ("v", 54, "F-4"),
            ("g", 55, "F#4"),
            ("b", 56, "G-4"),
            ("h", 57, "G#4"),
            ("n", 58, "A-4"),
            ("j", 59, "A#4"),
            ("m", 60, "B-4")
        ]

        for (key, noteValue, noteText) in expectedNotes {
            var document = BlankTrackerDocument.makeDefault()

            XCTAssertTrue(document.enterNote(trackerKey: key, octave: 4, row: 0, channel: 0), String(key))
            XCTAssertEqual(document.pattern.rows[0][0].note, noteValue, String(key))
            XCTAssertEqual(ModuleMetadataLoader.formatXMNote(noteValue), noteText, String(key))
        }
    }

    func testUpperRowNaturalTrackerNotesUseSelectedOctavePlusOne() {
        let expectedNotes: [(Character, UInt8, String)] = [
            ("q", 61, "C-5"),
            ("w", 63, "D-5"),
            ("e", 65, "E-5"),
            ("r", 66, "F-5"),
            ("t", 68, "G-5"),
            ("y", 70, "A-5"),
            ("u", 72, "B-5")
        ]

        for (key, noteValue, noteText) in expectedNotes {
            var document = BlankTrackerDocument.makeDefault()

            XCTAssertTrue(document.enterNote(trackerKey: key, octave: 4, row: 0, channel: 0), String(key))
            XCTAssertEqual(document.pattern.rows[0][0].note, noteValue, String(key))
            XCTAssertEqual(ModuleMetadataLoader.formatXMNote(noteValue), noteText, String(key))
        }
    }

    func testUpperRowSharpTrackerNotesUseSelectedOctavePlusOne() {
        let expectedNotes: [(Character, UInt8, String)] = [
            ("2", 62, "C#5"),
            ("3", 64, "D#5"),
            ("5", 67, "F#5"),
            ("6", 69, "G#5"),
            ("7", 71, "A#5")
        ]

        for (key, noteValue, noteText) in expectedNotes {
            var document = BlankTrackerDocument.makeDefault()

            XCTAssertTrue(document.enterNote(trackerKey: key, octave: 4, row: 0, channel: 0), String(key))
            XCTAssertEqual(document.pattern.rows[0][0].note, noteValue, String(key))
            XCTAssertEqual(ModuleMetadataLoader.formatXMNote(noteValue), noteText, String(key))
        }
    }

    func testEditedBlankPatternCellFormatsExpectedNaturalNoteText() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))

        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 01 .. ...")
    }

    func testNoteEntryUsesSelectedOctave() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "m", octave: 7, row: 3, channel: 2))

        XCTAssertEqual(document.pattern.rows[3][2].note, 96)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[3][2].note), "B-7")
    }

    func testSelectedOctaveChangesAffectLowerAndUpperRows() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 3, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "q", octave: 3, row: 1, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 5, row: 2, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "q", octave: 5, row: 3, channel: 0))

        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "C-3")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[1][0].note), "C-4")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[2][0].note), "C-5")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[3][0].note), "C-6")
    }

    func testUpperRowClampsToSupportedNoteRangeNearTopOctave() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "q", octave: 7, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "u", octave: 7, row: 1, channel: 0))

        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "C-7")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[1][0].note), "B-7")
    }

    func testAccidentalNoteEntryUsesSelectedOctave() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "s", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.enterNote(trackerKey: "j", octave: 5, row: 1, channel: 1))

        XCTAssertEqual(document.pattern.rows[0][0].note, 50)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "C#4")
        XCTAssertEqual(document.pattern.rows[1][1].note, 71)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[1][1].note), "A#5")
    }

    func testKeyOffEntryUsesDistinctNoteOffValueAndFormatsAsEquals() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterKeyOff(row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0].note, TrackerNoteKeyMap.keyOffNoteValue)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "===")
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "=== .. .. ...")
        XCTAssertNotEqual(document.pattern.rows[0][0], .empty)
    }

    func testKeyOffDisplayIsDistinctFromEmptyCellDisplay() {
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(0), "...")
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(.empty), "... .. .. ...")
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(TrackerNoteKeyMap.keyOffNoteValue), "===")
        XCTAssertNotEqual(ModuleMetadataLoader.formatXMNote(0), ModuleMetadataLoader.formatXMNote(TrackerNoteKeyMap.keyOffNoteValue))
    }

    func testClearNoteReturnsSelectedNoteCellToEmptyDisplay() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterKeyOff(row: 0, channel: 0))
        XCTAssertTrue(document.clearNote(row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0], .empty)
        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[0][0].note), "...")
    }

    func testNoteKeyOffAndClearEntryUseOneRowEditStepAndClampAtFinalRow() {
        var row = 10
        row = TrackerEditStep.advancedRow(after: row, rowCount: BlankTrackerDocument.defaultRowCount)
        XCTAssertEqual(row, 11)

        row = TrackerEditStep.advancedRow(after: 63, rowCount: BlankTrackerDocument.defaultRowCount)
        XCTAssertEqual(row, 63)
    }

    func testFinalRowNoteEntryIsSafeAndClampsEditAdvance() {
        var document = BlankTrackerDocument.makeDefault()
        let selectedRow = 63
        let selectedChannel = 0

        XCTAssertTrue(document.enterNote(trackerKey: "x", octave: 4, row: selectedRow, channel: selectedChannel))
        let advancedRow = TrackerEditStep.advancedRow(after: selectedRow, rowCount: document.pattern.rowCount)

        XCTAssertEqual(document.pattern.rows[63][0].note, 51)
        XCTAssertEqual(advancedRow, 63)
        XCTAssertEqual(document.pattern.rows.count, BlankTrackerDocument.defaultRowCount)
    }

    func testFinalRowUpperNoteEntryUsesSameEditAdvanceClamp() {
        var document = BlankTrackerDocument.makeDefault()
        let selectedRow = 63

        XCTAssertTrue(document.enterNote(trackerKey: "q", octave: 4, row: selectedRow, channel: 0))
        let advancedRow = TrackerEditStep.advancedRow(after: selectedRow, rowCount: document.pattern.rowCount)

        XCTAssertEqual(ModuleMetadataLoader.formatXMNote(document.pattern.rows[63][0].note), "C-5")
        XCTAssertEqual(advancedRow, 63)
    }

    func testStoppedEditableNoteEntryUsesChangedSelectedInstrument() {
        var document = makeTwoInstrumentLoadedModuleEditableDocument(channels: 1, rowCount: 4)

        document.selectInstrument(2)
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))

        XCTAssertEqual(document.pattern.rows[0][0].note, 49)
        XCTAssertEqual(document.pattern.rows[0][0].instrument, 2)
    }

    func testBlankDocumentNoteEntryRejectsNonNoteKeysAndOutOfRangeCoordinates() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertFalse(document.enterNote(trackerKey: "i", octave: 4, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: ",", octave: 4, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: ".", octave: 4, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: "/", octave: 4, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: "z", octave: 8, row: 0, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: "z", octave: 4, row: 64, channel: 0))
        XCTAssertFalse(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 8))
        XCTAssertFalse(document.enterKeyOff(row: 64, channel: 0))
        XCTAssertFalse(document.clearNote(row: 0, channel: 8))
        XCTAssertEqual(document.pattern.rows[0][0], .empty)
    }

    func testBlankDocumentDoesNotRequirePlaybackOrAudioState() {
        let document = BlankTrackerDocument.makeDefault()

        XCTAssertEqual(document.metadata.instruments, 1)
        XCTAssertEqual(document.metadata.patterns, 1)
        XCTAssertEqual(document.metadata.defaultBPM, 125)
        XCTAssertEqual(document.metadata.defaultTempo, 6)
        XCTAssertEqual(document.metadata.restartPosition, 0)
        XCTAssertEqual(document.controlPanelMetadata.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(document.controlPanelMetadata.selectedSampleDisplay, "S01")
    }

    private func makeBlankDocument(
        currentPatternIndex: Int = BlankTrackerDocument.defaultPatternIndex,
        tempo: Int = BlankTrackerDocument.defaultTempo,
        speed: Int = BlankTrackerDocument.defaultSpeed,
        selection: TrackerEditorSelection = .default,
        orderTable: [Int] = [BlankTrackerDocument.defaultPatternIndex],
        patterns: [XMPatternData] = [BlankTrackerDocument.makeEmptyPattern(index: BlankTrackerDocument.defaultPatternIndex)],
        instrumentPalette: [Int: PlaybackInstrument] = [:]
    ) -> BlankTrackerDocument {
        BlankTrackerDocument(
            title: BlankTrackerDocument.defaultTitle,
            songLength: orderTable.count,
            currentPosition: min(max(0, currentPatternIndex), max(0, orderTable.count - 1)),
            restartPosition: BlankTrackerDocument.defaultRestartPosition,
            currentPatternIndex: currentPatternIndex,
            tempo: tempo,
            speed: speed,
            orderTable: orderTable,
            selection: selection,
            instrumentPalette: instrumentPalette,
            patterns: patterns
        )
    }

    private func makeTwoInstrumentLoadedModuleEditableDocument(channels: Int, rowCount: Int) -> BlankTrackerDocument {
        let metadata = makeLoadedModuleMetadata(
            channels: channels,
            instruments: 2,
            defaultTempo: 1,
            defaultBPM: 25,
            patterns: [
                BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: rowCount, channels: channels)
            ]
        )
        let firstSample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            name: "Sample A",
            pcm: [0.25, -0.25, 0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let secondSample = makePlaybackSample(
            instrumentIndex: 2,
            sampleIndex: 0,
            name: "Sample B",
            pcm: [0.5, -0.5, 0.5],
            volume: 1,
            baseSampleRate: 8_363
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: rowCount],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, name: "Inst A", samples: [firstSample]),
                2: PlaybackInstrument(index: 2, name: "Inst B", samples: [secondSample])
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )

        return tryUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))
    }

    private func makeTwoSampleLoadedModuleEditableDocument(rowCount: Int) -> BlankTrackerDocument {
        let metadata = makeLoadedModuleMetadata(
            channels: 1,
            instruments: 1,
            defaultTempo: 1,
            defaultBPM: 25,
            patterns: [
                BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: rowCount, channels: 1)
            ]
        )
        let firstSample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            name: "Sample A",
            pcm: [0.25, -0.25, 0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let secondSample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 1,
            name: "Sample B",
            pcm: [0.75, -0.75, 0.75],
            volume: 1,
            baseSampleRate: 8_363
        )
        let song = makePlaybackSong(
            orderPatternIndices: [0],
            patternRowCounts: [0: rowCount],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, name: "Inst A", samples: [firstSample, secondSample])
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 25)
        )

        return tryUnwrap(BlankTrackerDocument.makeEditableCopyClearingSongData(
            from: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        ))
    }

    private struct AppliedPatternEditInput: Equatable {
        let consumed: Bool
        let didMutate: Bool
        let route: EditorNoteAuditionInputRoute
    }

    private func applyPatternEditInput(
        _ input: PatternEditInput,
        to document: inout BlankTrackerDocument,
        cursor: inout PatternCursor,
        refresh: ((BlankTrackerDocument) -> Void)? = nil
    ) -> AppliedPatternEditInput {
        let route = EditorNoteAuditionInputPolicy.route(
            input: noteAuditionInputKind(for: input),
            editModeEnabled: true,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: cursor.field == .note
        )

        guard !route.shouldConsumeRepeatedNoteKey,
              !route.shouldSuppressRepeatedMutation else {
            return AppliedPatternEditInput(consumed: true, didMutate: false, route: route)
        }

        guard route.shouldMutatePattern else {
            return AppliedPatternEditInput(
                consumed: route.shouldConsumeNonMutatingInput(previewOutcome: .skipped(.missingRequest)),
                didMutate: false,
                route: route
            )
        }

        let didMutate: Bool
        switch input {
        case let .noteKey(character, _):
            didMutate = document.enterNote(
                trackerKey: character,
                octave: 4,
                row: cursor.row,
                channel: cursor.channel,
                patternIndex: document.currentPatternIndex
            )
        case .keyOff:
            didMutate = document.enterKeyOff(row: cursor.row, channel: cursor.channel, patternIndex: document.currentPatternIndex)
        case .clearField:
            didMutate = document.clearField(
                editablePatternCellField(for: cursor.field),
                row: cursor.row,
                channel: cursor.channel,
                patternIndex: document.currentPatternIndex
            )
        case .repeatedKeyOff, .repeatedClearField, .hexDigit:
            didMutate = false
        }

        guard didMutate else {
            return AppliedPatternEditInput(consumed: false, didMutate: false, route: route)
        }

        let editedPattern = document.pattern(for: document.currentPatternIndex) ?? document.pattern
        cursor.row = TrackerEditStep.advancedRow(after: cursor.row, rowCount: editedPattern.rowCount)
        refresh?(document)
        return AppliedPatternEditInput(consumed: true, didMutate: true, route: route)
    }

    private func noteAuditionInputKind(for input: PatternEditInput) -> EditorNoteAuditionInputKind {
        switch input {
        case let .noteKey(_, isRepeat):
            return .noteKey(isRepeat: isRepeat)
        case .keyOff:
            return .keyOff
        case .repeatedKeyOff:
            return .repeatedKeyOff
        case .clearField:
            return .clearField
        case .repeatedClearField:
            return .repeatedClearField
        case .hexDigit:
            return .other
        }
    }

    private func editablePatternCellField(for field: PatternCursorField) -> EditablePatternCellField {
        switch field {
        case .note:
            return .note
        case .instrument:
            return .instrument
        case .volume:
            return .volume
        case .effectType:
            return .effectType
        case .effectParam:
            return .effectParam
        }
    }

    private struct NoteTriggerSummary: Equatable {
        let source: PlaybackPosition
        let channelIndex: Int
        let note: UInt8
        let instrumentIndex: Int
        let sampleIndex: Int
    }

    private func noteTriggerSummaries(in plan: RuntimeCMixerAdapterEventPlan) -> [NoteTriggerSummary] {
        plan.events.compactMap { event in
            guard case let .noteTrigger(_, _, mapping) = event.action else {
                return nil
            }
            return NoteTriggerSummary(
                source: event.source,
                channelIndex: event.channelIndex,
                note: mapping.note,
                instrumentIndex: mapping.instrumentIndex,
                sampleIndex: mapping.sampleIndex
            )
        }
    }

    private func noteTriggerSources(in plan: RuntimeCMixerAdapterEventPlan) -> [PlaybackPosition] {
        plan.events.compactMap { event in
            guard case .noteTrigger = event.action else {
                return nil
            }
            return event.source
        }
    }

    private func makePreviewEvent(
        trackerKey: Character,
        selectedOctave: Int,
        sampleVolume: Float = 1,
        samplePanning: UInt8 = PlaybackSample.xmCenterPanning,
        baseSampleRate: Double,
        instrumentIndex: Int = 1,
        sampleIndex: Int = 0,
        previewPCM: [Float] = [0, 1, 0.5, -0.5, -1, -0.5, 0.5, 1],
        previewLoop: MixerSampleLoop = .none,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> EditorNoteAuditionPreviewEvent {
        let selection = TrackerEditorSelection(selectedInstrument: instrumentIndex, selectedSample: sampleIndex + 1)
        let request = try XCTUnwrap(
            EditorNoteAuditionRequest.noteOn(
                trackerKey: trackerKey,
                selectedOctave: selectedOctave,
                selection: selection,
                sourceContext: .loadedModule(patternIndex: 0),
                channelIndex: 0,
                rowIndex: 0
            ),
            file: file,
            line: line
        )
        guard case let .noteOn(noteValue, requestOctave) = request.kind else {
            throw XCTSkip("Expected note-on request")
        }
        let descriptor = EditorNoteAuditionSampleDescriptor(
            instrumentIndex: instrumentIndex,
            sampleIndex: sampleIndex,
            sampleFrameCount: previewPCM.count,
            hasSamplePayload: true,
            hasLoopMetadata: previewLoop.mode != .none,
            previewLoop: previewLoop,
            sourceContext: .loadedModule(patternIndex: 0),
            previewPCM: previewPCM,
            previewVolume: sampleVolume,
            previewPanning: samplePanning,
            previewBaseSampleRate: baseSampleRate
        )
        return EditorNoteAuditionPreviewEvent(
            request: request,
            sampleDescriptor: descriptor,
            noteValue: noteValue,
            selectedOctave: requestOctave
        )
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("tests/fixtures").appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return url
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

    private func loadedModuleControlPanelMetadata(title: String) -> ParsedModuleMetadata {
        makeLoadedModuleMetadata(title: title, channels: 6, instruments: 1)
    }

    private func makeLoadedModuleMetadata(
        type: String = "XM",
        title: String = "Loaded Module",
        channels: Int = 1,
        instruments: Int = 1,
        defaultTempo: Int = 6,
        defaultBPM: Int = 125,
        orderTable: [Int] = [0],
        patterns: [XMPatternData] = [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 64, channels: 1)]
    ) -> ParsedModuleMetadata {
        ParsedModuleMetadata(
            type: type,
            title: title,
            version: "1.04",
            channels: channels,
            patterns: patterns.count,
            instruments: instruments,
            xmFlags: 0x0001,
            defaultTempo: defaultTempo,
            defaultBPM: defaultBPM,
            songLength: orderTable.count,
            restartPosition: 0,
            orderTable: orderTable,
            xmPatterns: patterns
        )
    }

    private func tryUnwrap<T>(
        _ value: T?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> T {
        guard let value else {
            XCTFail("Expected non-nil value", file: file, line: line)
            fatalError("Expected non-nil value")
        }
        return value
    }

    private func pcmSHA256(_ sample: PlaybackSample) -> String {
        let data = Data(sample.pcm.flatMap { value -> [UInt8] in
            let quantized = UInt16(truncatingIfNeeded: max(-32_768, min(32_767, Int((value * 32_768).rounded()))))
            return [UInt8(quantized & 0x00FF), UInt8(quantized >> 8)]
        })
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private final class RecordingEditorNoteAuditionPreviewSink: EditorNoteAuditionPreviewSink {
    var isPreviewAvailable = true
    private(set) var events = [EditorNoteAuditionPreviewEvent]()
    private(set) var releasePreviewCount = 0
    private(set) var cancelPreviewCount = 0

    func preview(_ event: EditorNoteAuditionPreviewEvent) -> Bool {
        events.append(event)
        return true
    }

    func releasePreview() {
        releasePreviewCount += 1
    }

    func cancelPreview() {
        cancelPreviewCount += 1
    }
}
