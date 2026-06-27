import XCTest

final class BlankTrackerDocumentTests: XCTestCase {
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
            sourceContext: .loadedModule(patternIndex: 0)
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
        XCTAssertEqual(document.noteAuditionAvailability, .unavailable(.blankDocumentMissingInstrumentSamplePayload))
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

        XCTAssertEqual(outcome, .skipped(.unavailable(.blankDocumentMissingInstrumentSamplePayload)))
        XCTAssertTrue(sink.events.isEmpty)
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
        XCTAssertEqual(sink.cancelPreviewCount, 1)
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
        XCTAssertEqual(sink.cancelPreviewCount, 1)
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
        XCTAssertEqual(sink.cancelPreviewCount, 0)
        XCTAssertTrue(previewer.stopPreview(for: secondIdentity))
        XCTAssertNil(previewer.activePreviewToken)
        XCTAssertEqual(sink.cancelPreviewCount, 1)
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
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 .. .. ...")
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
        XCTAssertEqual(outcome, .skipped(.unavailable(.blankDocumentMissingInstrumentSamplePayload)))
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
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 .. .. ...")
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
            XCTAssertEqual(sink.cancelPreviewCount, 1)
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
            XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 .. .. ...")
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
        XCTAssertTrue(editBlankRoute.shouldMutatePattern)
        XCTAssertTrue(document.enterKeyOff(row: 0, channel: 0))
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "=== .. .. ...")
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
        let editBlankRoute = EditorNoteAuditionInputPolicy.route(
            input: .clearField,
            editModeEnabled: true,
            sourceContext: document.noteAuditionSourceContext,
            isNoteField: true
        )

        XCTAssertFalse(nonEditBlankRoute.shouldMutatePattern)
        XCTAssertFalse(editLoadedRoute.shouldMutatePattern)
        XCTAssertEqual(document, beforeNonEditClear)
        XCTAssertTrue(editBlankRoute.shouldMutatePattern)
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

    func testClearSongDataOnAlreadyEmptyBlankDocumentIsSafe() {
        var document = BlankTrackerDocument.makeDefault()
        let before = document

        document.clearSongData()

        XCTAssertEqual(document, before)
        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "... .. .. ...")
    }

    func testLoadedModuleClearSongDataIsUnavailableAndDoesNotMutateMetadata() {
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

    func testBlankDocumentControlPanelMetadataIsSane() {
        let metadata = BlankTrackerDocument.makeDefault().controlPanelMetadata

        XCTAssertEqual(metadata.songTitle, "Untitled")
        XCTAssertEqual(metadata.songLength, "01")
        XCTAssertEqual(metadata.songPosition, "00")
        XCTAssertEqual(metadata.restartPosition, "00")
        XCTAssertEqual(metadata.patternRowCount, "64")
        XCTAssertEqual(metadata.channelCount, "8")
        XCTAssertEqual(metadata.selectedInstrumentDisplay, "I01")
        XCTAssertEqual(metadata.selectedSampleDisplay, "S01")
        XCTAssertEqual(metadata.tempo, "125")
        XCTAssertEqual(metadata.speed, "06")
        XCTAssertEqual(metadata.songPositionValue, 0)
        XCTAssertEqual(metadata.maximumSongPosition, 0)
        XCTAssertFalse(metadata.isSongPositionEnabled)
        XCTAssertTrue(metadata.isPatternControlsEnabled)
        XCTAssertFalse(metadata.areInstrumentPlaceholdersEnabled)
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
        XCTAssertFalse(content.areInstrumentPlaceholdersEnabled)
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
        XCTAssertEqual(reset.noteAuditionAvailability, .unavailable(.blankDocumentMissingInstrumentSamplePayload))
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

        XCTAssertEqual(ModuleMetadataLoader.formatXMCell(document.pattern.rows[0][0]), "C-4 .. .. ...")
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

        XCTAssertEqual(document.metadata.instruments, 0)
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
        patterns: [XMPatternData] = [BlankTrackerDocument.makeEmptyPattern(index: BlankTrackerDocument.defaultPatternIndex)]
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
            patterns: patterns
        )
    }

    private func makePreviewEvent(
        trackerKey: Character,
        selectedOctave: Int,
        sampleVolume: Float = 1,
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
        ParsedModuleMetadata(
            type: "XM",
            title: title,
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
    }
}

private final class RecordingEditorNoteAuditionPreviewSink: EditorNoteAuditionPreviewSink {
    private(set) var events = [EditorNoteAuditionPreviewEvent]()
    private(set) var cancelPreviewCount = 0

    func preview(_ event: EditorNoteAuditionPreviewEvent) {
        events.append(event)
    }

    func cancelPreview() {
        cancelPreviewCount += 1
    }
}
