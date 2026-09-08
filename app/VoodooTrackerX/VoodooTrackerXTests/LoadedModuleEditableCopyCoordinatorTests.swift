import CryptoKit
import XCTest

final class LoadedModuleEditableCopyCoordinatorTests: XCTestCase {
    func testCommandEligibilityDependsOnLoadedStoppedPresentationNotPlannerOutcome() throws {
        let exactContext = identified(supportedLoadedContext(isPlaybackActive: false))
        let normalizedContext = identified(profileV1NormalizedContext())
        let unavailableContext = identified(nonLinearFrequencyTableContext())

        guard case .exact = LoadedModuleEditableCopyPlanner.plan(context: exactContext) else {
            return XCTFail("expected exact plan fixture")
        }
        guard case .normalized = LoadedModuleEditableCopyPlanner.plan(context: normalizedContext) else {
            return XCTFail("expected normalized plan fixture")
        }
        XCTAssertEqual(
            LoadedModuleEditableCopyPlanner.plan(context: unavailableContext),
            .unavailable(.nonLinearFrequencyTable)
        )

        for context in [exactContext, normalizedContext, unavailableContext] {
            XCTAssertTrue(LoadedModuleEditableCopyCoordinator.canInvoke(
                context: context,
                hasConflictingPresentation: false
            ))
        }
    }

    func testCommandEligibilityRejectsPlayingEditableMissingNonXMAndConflictingPresentation() throws {
        let stoppedLoadedXM = identified(supportedLoadedContext(isPlaybackActive: false))
        let xmMetadata = try XCTUnwrap(stoppedLoadedXM.loadedMetadata)
        let loadedMOD = LoadedModuleEditableCopyContext.loadedReadOnly(
            moduleIdentity: stoppedLoadedXM.moduleIdentity,
            metadata: makeLoadedModuleMetadata(
                type: "MOD",
                title: "Loaded MOD",
                channels: xmMetadata.channels,
                instruments: xmMetadata.instruments,
                orderTable: xmMetadata.orderTable,
                patterns: xmMetadata.xmPatterns
            ),
            playbackSong: stoppedLoadedXM.loadedPlaybackSong,
            selection: stoppedLoadedXM.selection,
            currentPatternIndex: stoppedLoadedXM.currentPatternIndex,
            isPlaybackActive: false
        )

        XCTAssertFalse(LoadedModuleEditableCopyCoordinator.canInvoke(
            context: identified(supportedLoadedContext(isPlaybackActive: true)),
            hasConflictingPresentation: false
        ))
        XCTAssertFalse(LoadedModuleEditableCopyCoordinator.canInvoke(
            context: .editable(isPlaybackActive: false),
            hasConflictingPresentation: false
        ))
        XCTAssertFalse(LoadedModuleEditableCopyCoordinator.canInvoke(
            context: .none(isPlaybackActive: false),
            hasConflictingPresentation: false
        ))
        XCTAssertFalse(LoadedModuleEditableCopyCoordinator.canInvoke(
            context: stoppedLoadedXM,
            hasConflictingPresentation: true
        ))
        XCTAssertFalse(LoadedModuleEditableCopyCoordinator.canInvoke(
            context: loadedMOD,
            hasConflictingPresentation: false
        ))
    }

    func testExactActionImmediatelyDispatchesPlannerDocumentWithoutChangingSource() {
        let context = identified(supportedLoadedContext(isPlaybackActive: false))
        let originalMetadata = context.loadedMetadata
        let originalSong = context.loadedPlaybackSong
        guard case let .exact(expectedDocument) = LoadedModuleEditableCopyPlanner.plan(context: context) else {
            return XCTFail("expected exact plan")
        }
        var returnedFromPerform = false
        var receivedResult: LoadedModuleEditableCopyResult?

        let didPerform = LoadedModuleEditableCopyCoordinator().perform(
            contextProvider: { context },
            presentationConflictProvider: { false }
        ) { result in
            XCTAssertFalse(returnedFromPerform, "the stopped exact action should dispatch synchronously")
            receivedResult = result
        }
        returnedFromPerform = true

        XCTAssertTrue(didPerform)
        XCTAssertEqual(receivedResult, .copied(expectedDocument))
        XCTAssertEqual(context.loadedMetadata, originalMetadata)
        XCTAssertEqual(context.loadedPlaybackSong, originalSong)
    }

    func testNormalizedActionImmediatelyDispatchesPlannerDocumentAndSummaryWithoutConfirmation() throws {
        let context = identified(profileV1NormalizedContext())
        let originalMetadata = context.loadedMetadata
        let originalSong = context.loadedPlaybackSong
        guard case let .normalized(expectedDocument, expectedSummary) =
            LoadedModuleEditableCopyPlanner.plan(context: context) else {
            return XCTFail("expected Profile-v1 normalized plan")
        }
        var results = [LoadedModuleEditableCopyResult]()

        let didPerform = LoadedModuleEditableCopyCoordinator().perform(
            contextProvider: { context },
            presentationConflictProvider: { false },
            resultHandler: { results.append($0) }
        )

        XCTAssertTrue(didPerform)
        XCTAssertEqual(results, [.normalized(expectedDocument, expectedSummary)])
        XCTAssertEqual(context.loadedMetadata, originalMetadata)
        XCTAssertEqual(context.loadedPlaybackSong, originalSong)
        XCTAssertEqual(expectedSummary.requiredEmptySlotsCanonicalized, 1)
        XCTAssertEqual(expectedDocument.instrumentPalette[1]?.noteSampleMap?[48], 1)
        XCTAssertNil(expectedDocument.instrumentPalette[1]?.sample(mappedSampleIndex: 1))
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1,
            note: 49,
            instrumentsByIndex: expectedDocument.instrumentPalette
        ))
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.userFacingTitle, "Editable Copy Created")
        let message = try XCTUnwrap(result.userFacingMessage)
        for expectedText in [
            "Created an untitled editable copy",
            "empty sample-slot metadata",
            "does not affect playback",
            "original XM remains unchanged",
            "export this editable copy as XM",
            "may differ structurally",
        ] {
            XCTAssertTrue(message.contains(expectedText), "missing: \(expectedText)")
        }
        XCTAssertFalse(message.contains("in-memory"))
        XCTAssertFalse(message.contains("canonical VTX structure"))
    }

    func testUnavailableActionDispatchesTypedExplanationWithoutTransitionOrMutation() {
        let context = identified(nonLinearFrequencyTableContext())
        let originalContext = context
        var transitionCount = 0
        var unavailableReasons = [LoadedModuleEditableCopyPlanUnavailableReason]()

        let didPerform = LoadedModuleEditableCopyCoordinator().perform(
            contextProvider: { context },
            presentationConflictProvider: { false }
        ) { result in
            switch result {
            case let .unavailable(reason):
                unavailableReasons.append(reason)
            case .copied, .normalized:
                transitionCount += 1
            }
        }

        XCTAssertTrue(didPerform)
        XCTAssertEqual(unavailableReasons, [.nonLinearFrequencyTable])
        XCTAssertEqual(transitionCount, 0)
        XCTAssertEqual(context, originalContext)
    }

    func testTypedUnavailableReasonsUseActionablePrivateSafeMessages() throws {
        let context = identified(supportedLoadedContext(isPlaybackActive: false))
        let cases: [(LoadedModuleEditableCopyPlanUnavailableReason, [String])] = [
            (.nonLinearFrequencyTable, ["Amiga frequency mode", "Linear frequency mode", "pitch"]),
            (.unsupportedSampleOrKeymapBoundary, ["sample-slot", "note-mapping", "preserve"]),
            (.representedLoopStateUnsupported, ["sample loop state", "preserve"]),
            (.representedInstrumentStateUnstable, ["instrument envelope", "wrote and reopened"]),
            (.instrumentIdentityUnstable, ["instrument identity", "palette"]),
            (.writerUnsupported, ["XM writer", "safely represent"]),
            (.unsupportedLoadedModule, ["some loaded module state", "preserved safely"]),
        ]

        for (reason, expectedFragments) in cases {
            var presentedResult: LoadedModuleEditableCopyResult?
            XCTAssertTrue(LoadedModuleEditableCopyCoordinator(planner: { _ in
                .unavailable(reason)
            }).perform(
                contextProvider: { context },
                presentationConflictProvider: { false },
                resultHandler: { presentedResult = $0 }
            ))
            let result = try XCTUnwrap(presentedResult)
            XCTAssertEqual(result, .unavailable(reason))
            XCTAssertEqual(result.userFacingTitle, "Make Editable Copy Unavailable")
            let message = try XCTUnwrap(result.userFacingMessage)
            for fragment in expectedFragments {
                XCTAssertTrue(message.contains(fragment), "\(reason): missing \(fragment)")
            }
            XCTAssertTrue(message.contains("loaded XM remains unchanged"), "\(reason)")
            XCTAssertFalse(message.contains(String(describing: reason)), "\(reason)")
            let macOSHomePathPrefix = ["", "Users", ""].joined(separator: "/")
            XCTAssertFalse(message.contains(macOSHomePathPrefix), "\(reason)")
            XCTAssertEqual(result.acknowledgementButtonTitle, "OK")
        }
    }

    func testExactActionRejectsChangedSourceIdentityBeforeTransition() {
        let first = identified(supportedLoadedContext(isPlaybackActive: false), identity: UUID())
        let replacement = identified(first, identity: UUID())
        var contextReads = 0
        var receivedResult: LoadedModuleEditableCopyResult?

        let didPerform = LoadedModuleEditableCopyCoordinator().perform(
            contextProvider: {
                defer { contextReads += 1 }
                return contextReads == 0 ? first : replacement
            },
            presentationConflictProvider: { false },
            resultHandler: { receivedResult = $0 }
        )

        XCTAssertFalse(didPerform)
        XCTAssertNil(receivedResult)
    }

    func testNormalizedActionRejectsChangedSourceBeforeTransition() {
        let first = identified(profileV1NormalizedContext(), identity: UUID())
        var replacement = first
        replacement = .loadedReadOnly(
            moduleIdentity: first.moduleIdentity,
            metadata: first.loadedMetadata,
            playbackSong: first.loadedPlaybackSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2),
            currentPatternIndex: first.currentPatternIndex,
            isPlaybackActive: false
        )
        var contextReads = 0
        var receivedResult: LoadedModuleEditableCopyResult?

        let didPerform = LoadedModuleEditableCopyCoordinator().perform(
            contextProvider: {
                defer { contextReads += 1 }
                return contextReads == 0 ? first : replacement
            },
            presentationConflictProvider: { false },
            resultHandler: { receivedResult = $0 }
        )

        XCTAssertFalse(didPerform)
        XCTAssertNil(receivedResult)
    }

    func testActionRejectsPlaybackThatStartsBeforeTransition() {
        let stopped = identified(supportedLoadedContext(isPlaybackActive: false))
        let playing = LoadedModuleEditableCopyContext.loadedReadOnly(
            moduleIdentity: stopped.moduleIdentity,
            metadata: stopped.loadedMetadata,
            playbackSong: stopped.loadedPlaybackSong,
            selection: stopped.selection,
            currentPatternIndex: stopped.currentPatternIndex,
            isPlaybackActive: true
        )
        var contextReads = 0
        var receivedResult: LoadedModuleEditableCopyResult?

        let didPerform = LoadedModuleEditableCopyCoordinator().perform(
            contextProvider: {
                defer { contextReads += 1 }
                return contextReads == 0 ? stopped : playing
            },
            presentationConflictProvider: { false },
            resultHandler: { receivedResult = $0 }
        )

        XCTAssertFalse(didPerform)
        XCTAssertNil(receivedResult)
    }

    func testActionRejectsChangedPlannerResultBeforeTransition() {
        let context = identified(supportedLoadedContext(isPlaybackActive: false))
        let document = BlankTrackerDocument.makeDefault()
        var plannerCalls = 0
        let coordinator = LoadedModuleEditableCopyCoordinator { _ in
            defer { plannerCalls += 1 }
            return plannerCalls == 0
                ? .exact(document)
                : .unavailable(.writerUnsupported)
        }
        var receivedResult: LoadedModuleEditableCopyResult?

        let didPerform = coordinator.perform(
            contextProvider: { context },
            presentationConflictProvider: { false },
            resultHandler: { receivedResult = $0 }
        )

        XCTAssertFalse(didPerform)
        XCTAssertEqual(plannerCalls, 2)
        XCTAssertNil(receivedResult)
    }

    func testDirectActionDuringConflictingPresentationIsInert() {
        let context = identified(supportedLoadedContext(isPlaybackActive: false))
        var plannerCalls = 0
        let coordinator = LoadedModuleEditableCopyCoordinator { context in
            plannerCalls += 1
            return LoadedModuleEditableCopyPlanner.plan(context: context)
        }
        var receivedResult: LoadedModuleEditableCopyResult?

        let didPerform = coordinator.perform(
            contextProvider: { context },
            presentationConflictProvider: { true },
            resultHandler: { receivedResult = $0 }
        )

        XCTAssertFalse(didPerform)
        XCTAssertEqual(plannerCalls, 0)
        XCTAssertNil(receivedResult)
    }

    func testActionRejectsPresentationConflictThatAppearsBeforeTransition() {
        let context = identified(supportedLoadedContext(isPlaybackActive: false))
        var presentationChecks = 0
        var receivedResult: LoadedModuleEditableCopyResult?

        let didPerform = LoadedModuleEditableCopyCoordinator().perform(
            contextProvider: { context },
            presentationConflictProvider: {
                defer { presentationChecks += 1 }
                return presentationChecks > 0
            },
            resultHandler: { receivedResult = $0 }
        )

        XCTAssertFalse(didPerform)
        XCTAssertEqual(presentationChecks, 2)
        XCTAssertNil(receivedResult)
    }

    func testLoadedReadOnlyStoppedXMModuleCanMakeEditableCopyWhenSupported() {
        let context = supportedLoadedContext(isPlaybackActive: false)

        XCTAssertTrue(LoadedModuleEditableCopyCoordinator.canMakeEditableCopy(context: context))
        XCTAssertNil(LoadedModuleEditableCopyCoordinator.unavailableReason(for: context))
    }

    func testAlreadyEditableNoDocumentPlaybackAndUnsupportedStatesAreUnavailable() {
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: .editable(isPlaybackActive: false)),
            .alreadyEditable
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: .none(isPlaybackActive: false)),
            .noLoadedModule
        )

        var activePlaybackContext = supportedLoadedContext(isPlaybackActive: true)
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: activePlaybackContext),
            .playbackActive
        )

        activePlaybackContext = .loadedReadOnly(
            metadata: activePlaybackContext.loadedMetadata,
            playbackSong: nil,
            selection: activePlaybackContext.selection,
            currentPatternIndex: activePlaybackContext.currentPatternIndex,
            isPlaybackActive: false
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: activePlaybackContext),
            .missingPlaybackSong
        )

        let unsupportedMetadata = makeLoadedModuleMetadata(type: "MOD", patterns: [])
        let unsupportedContext = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: unsupportedMetadata,
            playbackSong: makePlaybackSong(orderPatternIndices: [0], patternRowCounts: [0: 64]),
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: unsupportedContext),
            .unavailable(.unsupportedLoadedModule)
        )

        let unsupportedSample = makePlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: [0.25, -0.25],
            volume: 1,
            baseSampleRate: 8_363
        )
        let unsupportedSampleContext = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: supportedLoadedContext(isPlaybackActive: false).loadedMetadata,
            playbackSong: makePlaybackSong(
                orderPatternIndices: [0],
                patternRowCounts: [0: 4],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [unsupportedSample])]
            ),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: unsupportedSampleContext),
            .unavailable(.unsupportedSampleOrKeymapBoundary)
        )
    }

    func testAmigaFrequencyTableModuleIsRejectedInsteadOfSilentlyConvertedToLinear() {
        var context = supportedLoadedContext(isPlaybackActive: false)
        context = .loadedReadOnly(
            metadata: context.loadedMetadata.map { metadata in
                makeLoadedModuleMetadata(
                    channels: metadata.channels,
                    instruments: 1,
                    xmFlags: 0,
                    orderTable: metadata.orderTable,
                    patterns: metadata.xmPatterns
                )
            },
            playbackSong: context.loadedPlaybackSong,
            selection: context.selection,
            currentPatternIndex: context.currentPatternIndex,
            isPlaybackActive: false
        )

        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator.unavailableReason(for: context),
            .nonLinearFrequencyTable
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context),
            .unavailable(.nonLinearFrequencyTable)
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyPlanner.plan(context: context),
            .unavailable(.nonLinearFrequencyTable)
        )
    }

    func testPlannerClassifiesDenseCanonicalLoadedXMAsExact() throws {
        let instrument = PlaybackInstrument(
            index: 1,
            name: "Dense Exact",
            samples: [persistableSample(sampleIndex: 0, name: "S01", pcm: [-0.5, 0.5])],
            noteSampleMap: Array(repeating: 0, count: 96)
        )
        let context = try loadedContext(
            from: EditableXMWriter().data(from: sparseSourceDocument(instrument: instrument)),
            filename: "planner-dense-exact.xm"
        )

        guard case let .exact(document) = LoadedModuleEditableCopyPlanner.plan(context: context) else {
            return XCTFail("expected dense canonical state to plan an exact copy")
        }
        try assertSupportedSemanticsPreserved(context: context, document: document)
    }

    func testPlannerClassifiesSparseCanonicalInteriorEmptyAsExact() throws {
        var map = Array(repeating: 0, count: 96)
        map[48] = 1
        map[49] = 2
        let instrument = PlaybackInstrument(
            index: 1,
            name: "Sparse Exact",
            samples: [
                persistableSample(sampleIndex: 0, name: "S01", pcm: [-0.5, 0.5]),
                persistableSample(sampleIndex: 2, name: "S03", pcm: [-0.75, 0.75]),
            ],
            noteSampleMap: map
        )
        let source = sparseSourceDocument(instrument: instrument)
        let context = try loadedContext(from: EditableXMWriter().data(from: source), filename: "planner-sparse-exact.xm")

        guard case let .exact(document) = LoadedModuleEditableCopyPlanner.plan(context: context) else {
            return XCTFail("expected canonical interior empty state to plan an exact copy")
        }
        try assertSupportedSemanticsPreserved(context: context, document: document)
        XCTAssertNil(document.instrumentPalette[1]?.sample(mappedSampleIndex: 1))
    }

    func testPlannerClassifiesCurrentVTXAuthoredExportReopenAsExact() throws {
        let source = BlankTrackerDocument.makeDefault()
        let context = try loadedContext(
            from: EditableXMWriter().data(from: source),
            filename: "planner-vtx-authored-exact.xm"
        )

        guard case let .exact(document) = LoadedModuleEditableCopyPlanner.plan(context: context) else {
            return XCTFail("expected current VTX-authored export/reopen to plan an exact copy")
        }
        try assertSupportedSemanticsPreserved(context: context, document: document)
    }

    @MainActor
    func testCopyIsEditableUntitledInMemoryAndDoesNotMutateLoadedSourceState() throws {
        let context = supportedLoadedContext(isPlaybackActive: false)
        let originalMetadata = context.loadedMetadata
        let originalSong = context.loadedPlaybackSong

        let result = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context)

        guard case let .copied(document) = result else {
            return XCTFail("expected editable copy")
        }
        XCTAssertEqual(document.title, BlankTrackerDocument.defaultTitle)
        XCTAssertEqual(document.noteAuditionSourceContext, .blankDocument)
        XCTAssertTrue(EditorPatternMutationPolicy.canMutatePattern(sourceContext: document.noteAuditionSourceContext))
        XCTAssertEqual(context.loadedMetadata, originalMetadata)
        XCTAssertEqual(context.loadedPlaybackSong, originalSong)

        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
        XCTAssertTrue(ExportXMCoordinator.canExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        )))
        XCTAssertFalse(ExportXMCoordinator.canExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: true
        )))

        let mainMenu = ApplicationMenuBuilder.build(target: nil).mainMenu
        let fileMenu = try XCTUnwrap(mainMenu.item(withTitle: "File")?.submenu)
        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(fileMenu.item(withTitle: "Save As...")).isEnabled)
    }

    func testCopyPreservesOrderPatternNotesAndPalettePayload() throws {
        let firstPattern = pattern(
            index: 0,
            rowCount: 4,
            channels: 2,
            cells: [
                (1, 0, XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0x40, effectType: 0x0F, effectParam: 0x06))
            ]
        )
        let secondPattern = pattern(
            index: 1,
            rowCount: 6,
            channels: 2,
            cells: [
                (5, 1, XMPatternEventCell(note: XMPatternEventCell.keyOffNoteValue, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0))
            ]
        )
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            name: "Tiny",
            pcm: [0, 0.5, -0.5, 0.25],
            volume: 0.5,
            panning: 37,
            relativeNote: -1,
            finetune: 2,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let metadata = makeLoadedModuleMetadata(
            title: "Loaded Source",
            channels: 2,
            instruments: 1,
            defaultTempo: 3,
            defaultBPM: 140,
            songLength: 2,
            restartPosition: 1,
            orderTable: [0, 1],
            patterns: [firstPattern, secondPattern]
        )
        let song = playbackSongMatchingMetadata(
            metadata,
            instrumentsByIndex: [1: PlaybackInstrument(
                index: 1,
                name: "Tiny Inst",
                samples: [sample],
                noteSampleMap: Array(repeating: 0, count: 96)
            )]
        )
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 1,
            isPlaybackActive: false
        )

        let result = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context)

        guard case let .copied(document) = result else {
            return XCTFail("expected editable copy")
        }
        XCTAssertEqual(document.title, "Untitled")
        XCTAssertEqual(document.songLength, 2)
        XCTAssertEqual(document.currentPosition, 1)
        XCTAssertEqual(document.currentPatternIndex, 1)
        XCTAssertEqual(document.restartPosition, 1)
        XCTAssertEqual(document.tempo, 140)
        XCTAssertEqual(document.speed, 3)
        XCTAssertEqual(document.orderTable, [0, 1])
        XCTAssertEqual(document.patterns, [firstPattern, secondPattern])
        XCTAssertEqual(document.pattern(for: 0)?.rows[1][0].note, 49)
        XCTAssertEqual(document.pattern(for: 1)?.rows[5][1].note, XMPatternEventCell.keyOffNoteValue)
        let copiedSample = try XCTUnwrap(document.instrumentPalette[1]?.sample(selectedSampleSlot: 1))
        XCTAssertEqual(copiedSample.name, "Tiny")
        XCTAssertEqual(copiedSample.pcm, [0, 0.5, -0.5, 0.25])
        XCTAssertEqual(copiedSample.volume, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(copiedSample.panning, 37)
        XCTAssertEqual(copiedSample.relativeNote, -1)
        XCTAssertEqual(copiedSample.finetune, 2)
        XCTAssertEqual(document.instrumentPalette[1]?.noteSampleMap, Array(repeating: 0, count: 96))
    }

    func testPublicXMEditableCopiesWithRepresentedSamplesAlwaysHaveExactBoundedKeymaps() throws {
        let fixtures = [
            "generated/basic-instrument-sample.xm",
            "generated/multi-pattern-loop-boundary.xm",
            "generated/instrument-sustained-defaults.xm",
            "generated/instrument-metadata-matrix.xm",
            "generated/instrument-envelopes-keymap.xm",
        ]

        for fixture in fixtures {
            let sourceURL = try referenceXMFixtureURL(fixture)
            let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
            let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
            let context = LoadedModuleEditableCopyContext.loadedReadOnly(
                metadata: metadata,
                playbackSong: song,
                selection: .default,
                currentPatternIndex: 0,
                isPlaybackActive: false
            )
            guard case let .copied(document) = LoadedModuleEditableCopyCoordinator()
                .makeEditableCopy(context: context) else {
                return XCTFail("expected public fixture to become editable: \(fixture)")
            }
            let representedInstruments = document.instrumentPalette.values.filter { !$0.samples.isEmpty }
            XCTAssertFalse(representedInstruments.isEmpty, fixture)
            for instrument in representedInstruments {
                let map = try XCTUnwrap(instrument.noteSampleMap, fixture)
                XCTAssertEqual(map.count, 96, fixture)
                XCTAssertTrue(map.allSatisfy { (0..<16).contains($0) }, fixture)
            }
        }
    }

    @MainActor
    func testExportSmokeAfterEditableCopyReopensAsLoadedReadOnly() throws {
        let fixtureURL = try referenceXMFixtureURL("generated/basic-instrument-sample.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: fixtureURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected public fixture to become an editable copy")
        }
        let destination = try temporaryDestination(filename: "editable-copy-smoke.xm")
        let provider = FakeEditableCopyExportXMDestinationProvider(destination: destination)

        let exportResult = ExportXMCoordinator(destinationProvider: provider).beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))

        XCTAssertEqual(exportResult, .exported(destination: destination))
        let reloaded = try ModuleMetadataLoader().load(fromPath: destination.path)
        XCTAssertEqual(reloaded.type, "XM")
        XCTAssertEqual(reloaded.title, "Untitled")
        XCTAssertEqual(reloaded.orderTable, metadata.orderTable)
        XCTAssertEqual(reloaded.channels, metadata.channels)
        XCTAssertEqual(reloaded.patterns, metadata.patterns)
        XCTAssertEqual(reloaded.instruments, 1)
        XCTAssertEqual(reloaded.xmPatterns[0].rows[0][0].note, 49)
        XCTAssertEqual(reloaded.xmPatterns[0].rows[0][0].instrument, 1)

        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
    }

    func testClearedInteriorSampleReopensCopiesAndReexportsByteIdenticallyWithExactIdentityAndMap() throws {
        let first = makePlaybackSample(
            sampleIndex: 0,
            name: "Distinct S01",
            pcm: [-0.25, 0.25],
            volume: 0.5,
            panning: 37,
            relativeNote: -2,
            finetune: 7,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let second = makePlaybackSample(
            sampleIndex: 1,
            name: "Cleared S02",
            pcm: [-0.5, 0, 0.5],
            volume: 0.25,
            panning: 111,
            relativeNote: 1,
            finetune: 2,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let third = makePlaybackSample(
            sampleIndex: 2,
            name: "Distinct S03",
            pcm: [-0.75, 0.75],
            volume: 0.75,
            panning: 201,
            relativeNote: 3,
            finetune: -8,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[48] = 1
        noteSampleMap[49] = 2
        let sourceInstrument = PlaybackInstrument(
            index: 1,
            name: "Sparse Instrument",
            samples: [first, second, third],
            autoVibrato: .init(waveformType: 2, sweep: 3, depth: 4, rate: 5),
            noteSampleMap: noteSampleMap
        )
        var sourceDocument = sparseSourceDocument(
            instrument: sourceInstrument,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2)
        )
        XCTAssertTrue(sourceDocument.clearSample(instrumentAt: 0, sampleAt: 1))
        let clearedInstrument = try XCTUnwrap(sourceDocument.instrumentPalette[1])
        XCTAssertEqual(clearedInstrument.samples, [first, third])
        XCTAssertEqual(clearedInstrument.samples.map(\.sampleIndex), [0, 2])
        XCTAssertEqual(clearedInstrument.noteSampleMap, noteSampleMap)
        XCTAssertEqual(sourceDocument.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertEqual(
            sourceDocument.sampleSlotPresentationRows(forInstrument: 1).map(\.isEmptyDestination),
            [false, true, false]
        )

        let sourceData = try EditableXMWriter().data(from: sourceDocument)
        let sourceURL = try temporaryDestination(filename: "sparse-source.xm")
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let loadedInstrument = try XCTUnwrap(song.instrumentsByIndex[1])
        XCTAssertEqual(loadedInstrument, clearedInstrument)
        XCTAssertEqual(loadedInstrument.samples.map(\.sampleIndex), [0, 2])
        XCTAssertEqual(loadedInstrument.noteSampleMap, noteSampleMap)
        XCTAssertEqual(song.xmSampleSlotProvenanceByInstrument[1], [
            .init(sampleIndex: 0, decodedPayloadLength: 2, isCanonicalEmptySlotHeader: false),
            .init(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true),
            .init(sampleIndex: 2, decodedPayloadLength: 2, isCanonicalEmptySlotHeader: false),
        ])
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        XCTAssertTrue(LoadedModuleEditableCopyCoordinator.canMakeEditableCopy(context: context))
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected canonical sparse source to become editable")
        }
        let copiedInstrument = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(copiedInstrument, loadedInstrument)
        XCTAssertEqual(copiedInstrument.samples.map(\.sampleIndex), [0, 2])
        XCTAssertNil(copiedInstrument.sample(mappedSampleIndex: 1))
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrument: copiedInstrument
        ))
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 50, instrument: copiedInstrument
        )?.sampleIndex, 2)

        let reexportedData = try EditableXMWriter().data(from: document)
        XCTAssertEqual(reexportedData, sourceData)
        let reexportedURL = try temporaryDestination(filename: "sparse-reexported.xm")
        try reexportedData.write(to: reexportedURL, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: reexportedURL.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: reexportedURL.path)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1], loadedInstrument)
        XCTAssertEqual(reopenedMetadata.xmPatterns, metadata.xmPatterns)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    func testClearPopulateInteriorReopensAndCopiesExactIdentityMapAndSampleState() throws {
        let first = makePlaybackSample(
            sampleIndex: 0, name: "Distinct S01", pcm: [-0.25, 0.25], panning: 37,
            baseSampleRate: 8_363, sourceBitDepthBits: 16,
            sourceIsSignedPCM: true, sourceIsDeltaEncoded: true
        )
        let second = makePlaybackSample(
            sampleIndex: 1, name: "Old S02", pcm: [-0.5, 0, 0.5], panning: 111,
            baseSampleRate: 8_363, sourceBitDepthBits: 16,
            sourceIsSignedPCM: true, sourceIsDeltaEncoded: true
        )
        let third = makePlaybackSample(
            sampleIndex: 2, name: "Distinct S03", pcm: [-0.75, 0.75], panning: 201,
            baseSampleRate: 8_363, sourceBitDepthBits: 16,
            sourceIsSignedPCM: true, sourceIsDeltaEncoded: true
        )
        var map = Array(repeating: 0, count: TrackerNoteKeyMap.maximumNoteValue)
        map[48] = 1
        map[49] = 2
        var document = sparseSourceDocument(
            instrument: PlaybackInstrument(
                index: 1, name: "Recovered Instrument", samples: [first, second, third],
                noteSampleMap: map
            ),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2)
        )

        XCTAssertTrue(document.clearSample(instrumentAt: 0, sampleAt: 1))
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrumentsByIndex: document.instrumentPalette
        ))
        XCTAssertTrue(document.importAudioSample(
            try normalizedImportCandidate(name: "Recovered.wav", pcm: [-0.625, 0, 0.625]),
            destination: try XCTUnwrap(document.selectedSampleImportDestination)
        ))
        let populatedInstrument = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(populatedInstrument.samples.map(\.sampleIndex), [0, 1, 2])
        XCTAssertEqual(populatedInstrument.noteSampleMap, map)
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrumentsByIndex: document.instrumentPalette
        )?.sampleIndex, 1)

        let data = try EditableXMWriter().data(from: document)
        let url = try temporaryDestination(filename: "clear-populate-interior.xm")
        try data.write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        XCTAssertEqual(song.instrumentsByIndex[1], populatedInstrument)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: document.selection,
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(copy) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected populated dense source to become editable")
        }
        XCTAssertEqual(copy.instrumentPalette[1], populatedInstrument)
        XCTAssertEqual(copy.selection, document.selection)
        XCTAssertEqual(try EditableXMWriter().data(from: copy), data)
    }

    func testDenseDuplicateExportsReopensCopiesAndReexportsDeterministically() throws {
        let first = persistableSample(sampleIndex: 0, name: "Exact Dense Source", pcm: [-0.5, 0, 0.5])
        let second = persistableSample(sampleIndex: 1, name: "Distinct Dense S02", pcm: [-0.75, 0.75])
        var map = Array(repeating: 0, count: TrackerNoteKeyMap.maximumNoteValue)
        map[48] = 1
        var document = sparseSourceDocument(
            instrument: PlaybackInstrument(
                index: 1, name: "Dense Duplicate", samples: [first, second], noteSampleMap: map
            )
        )

        XCTAssertEqual(document.duplicateSample(instrumentAt: 0, sampleAt: 0), 2)
        let duplicatedInstrument = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(duplicatedInstrument.samples.map(\.sampleIndex), [0, 1, 2])
        XCTAssertEqual(duplicatedInstrument.sample(mappedSampleIndex: 2)?.reidentified(sampleIndex: 0), first)
        XCTAssertEqual(duplicatedInstrument.noteSampleMap, map)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 3))
        _ = try assertDuplicatePersistence(
            document, instrument: duplicatedInstrument, filename: "dense-duplicate-source.xm"
        )
    }

    func testSparseDuplicatePreservesInteriorGapThroughExportReopenCopyAndDeterministicReexport() throws {
        let first = persistableSample(sampleIndex: 0, name: "Exact Sparse Source", pcm: [-0.5, 0, 0.5])
        let third = persistableSample(sampleIndex: 2, name: "Stable Sparse S03", pcm: [-0.75, 0.75])
        var map = Array(repeating: 0, count: TrackerNoteKeyMap.maximumNoteValue)
        map[48] = 1
        map[49] = 2
        var document = sparseSourceDocument(
            instrument: PlaybackInstrument(
                index: 1, name: "Sparse Duplicate", samples: [first, third], noteSampleMap: map
            )
        )

        XCTAssertEqual(document.duplicateSample(instrumentAt: 0, sampleAt: 0), 3)
        let duplicatedInstrument = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(duplicatedInstrument.samples.map(\.sampleIndex), [0, 2, 3])
        XCTAssertNil(duplicatedInstrument.sample(mappedSampleIndex: 1))
        XCTAssertEqual(duplicatedInstrument.sample(mappedSampleIndex: 2), third)
        XCTAssertEqual(duplicatedInstrument.sample(mappedSampleIndex: 3)?.name, first.name)
        XCTAssertEqual(duplicatedInstrument.noteSampleMap, map)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 4))

        let song = try assertDuplicatePersistence(
            document, instrument: duplicatedInstrument, filename: "sparse-duplicate-source.xm"
        )
        XCTAssertEqual(song.xmSampleSlotProvenanceByInstrument[1]?.map(\.sampleIndex), [0, 1, 2, 3])
        XCTAssertTrue(song.xmSampleSlotProvenanceByInstrument[1]?[1].isCanonicalEmptySlotHeader == true)
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrumentsByIndex: song.instrumentsByIndex
        ))
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 50, instrumentsByIndex: song.instrumentsByIndex
        )?.sampleIndex, 2)
    }

    func testDenseMoveAndRepresentedSwapResultsSurviveExportReopenAndEditableCopy() throws {
        let source = PlaybackInstrument(
            index: 1,
            name: "Dense Permutation",
            samples: [
                persistableSample(sampleIndex: 0, name: "Content A", pcm: [-0.25, 0.25]),
                persistableSample(sampleIndex: 1, name: "Content B", pcm: [-0.5, 0.5]),
                persistableSample(sampleIndex: 2, name: "Content C", pcm: [-0.75, 0.75]),
            ],
            noteSampleMap: (0..<96).map { $0 % 3 }
        )
        let scenarios: [(name: String, permutation: SampleSlotPermutation, expectedNames: [String])] = [
            ("move", try .move(from: 2, to: 0), ["Content C", "Content A", "Content B"]),
            ("swap", try .swap(2, 0), ["Content C", "Content B", "Content A"]),
        ]

        for scenario in scenarios {
            var document = sparseSourceDocument(
                instrument: source,
                selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 3)
            )
            XCTAssertTrue(document.applySampleSlotPermutation(scenario.permutation, instrumentAt: 0), scenario.name)
            let transformed = try XCTUnwrap(document.instrumentPalette[1], scenario.name)

            XCTAssertEqual(transformed.samples.map(\.name), scenario.expectedNames, scenario.name)
            XCTAssertEqual(transformed.samples.map(\.sampleIndex), [0, 1, 2], scenario.name)
            _ = try assertPermutationPersistence(
                document,
                instrument: transformed,
                filename: "dense-\(scenario.name)-permutation.xm"
            )
        }
    }

    func testSparseMoveTransactionIncludingEmptyIdentitiesSurvivesExportReopenAndEditableCopy() throws {
        let source = PlaybackInstrument(
            index: 1,
            name: "Sparse Permutation",
            samples: [
                persistableSample(sampleIndex: 0, name: "Content A", pcm: [-0.25, 0.25]),
                persistableSample(sampleIndex: 2, name: "Content B", pcm: [-0.5, 0.5]),
                persistableSample(sampleIndex: 4, name: "Content C", pcm: [-0.75, 0.75]),
            ],
            noteSampleMap: (0..<96).map { $0 % 5 }
        )
        let permutation = try SampleSlotPermutation.move(from: 4, to: 1)
        var document = sparseSourceDocument(
            instrument: source,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2)
        )
        XCTAssertTrue(document.applySampleSlotPermutation(permutation, instrumentAt: 0))
        let transformed = try XCTUnwrap(document.instrumentPalette[1])
        let selectedEmptyIndex = document.selection.selectedSample - 1

        XCTAssertEqual(transformed.samples.map(\.name), ["Content A", "Content C", "Content B"])
        XCTAssertEqual(transformed.samples.map(\.sampleIndex), [0, 1, 3])
        XCTAssertNil(transformed.sample(mappedSampleIndex: selectedEmptyIndex))
        let song = try assertPermutationPersistence(
            document, instrument: transformed, filename: "sparse-permutation.xm"
        )
        XCTAssertEqual(
            song.xmSampleSlotProvenanceByInstrument[1]?.filter(\.isCanonicalEmptySlotHeader).map(\.sampleIndex),
            [2, 4]
        )
    }

    func testRepresentedEmptySwapSurvivesExportReopenAndEditableCopy() throws {
        let source = PlaybackInstrument(
            index: 1,
            name: "Sparse Swap",
            samples: [
                persistableSample(sampleIndex: 0, name: "Content A", pcm: [-0.25, 0.25]),
                persistableSample(sampleIndex: 2, name: "Content B", pcm: [-0.5, 0.5]),
            ],
            noteSampleMap: (0..<96).map { $0 % 3 }
        )
        let permutation = try SampleSlotPermutation.swap(0, 1)
        var document = sparseSourceDocument(
            instrument: source,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1)
        )
        XCTAssertTrue(document.applySampleSlotPermutation(permutation, instrumentAt: 0))
        let transformed = try XCTUnwrap(document.instrumentPalette[1])

        XCTAssertEqual(transformed.samples.map(\.name), ["Content A", "Content B"])
        XCTAssertEqual(transformed.samples.map(\.sampleIndex), [1, 2])
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        let song = try assertPermutationPersistence(
            document, instrument: transformed, filename: "sparse-swap.xm"
        )
        XCTAssertEqual(
            song.xmSampleSlotProvenanceByInstrument[1]?.filter(\.isCanonicalEmptySlotHeader).map(\.sampleIndex),
            [0]
        )
    }

    func testClearingOnlyMappedSamplePreservesInstrumentMetadataAndMapThroughReopenAndCopy() throws {
        let onlySample = makePlaybackSample(
            name: "Only S01",
            pcm: [-0.5, 0.5],
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let noteSampleMap = Array(repeating: 0, count: 96)
        let sourceInstrument = PlaybackInstrument(
            index: 1,
            name: "Only Mapped Sample",
            samples: [onlySample],
            volumeEnvelope: .init(
                enabled: true,
                points: [.init(tick: 0, value: 64), .init(tick: 8, value: 32)],
                sustainPointIndex: 1,
                loopStartPointIndex: 0,
                loopEndPointIndex: 1,
                typeFlags: 0x07,
                fadeout: 2_048
            ),
            panningEnvelope: .init(
                enabled: true,
                points: [.init(tick: 0, value: 32), .init(tick: 8, value: 48)],
                sustainPointIndex: 0,
                loopStartPointIndex: 0,
                loopEndPointIndex: 1,
                typeFlags: 0x05
            ),
            autoVibrato: .init(waveformType: 2, sweep: 8, depth: 6, rate: 24),
            noteSampleMap: noteSampleMap
        )
        var document = sparseSourceDocument(instrument: sourceInstrument)

        XCTAssertTrue(document.clearSample(instrumentAt: 0, sampleAt: 0))
        let clearedInstrument = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(clearedInstrument.samples, [])
        XCTAssertEqual(clearedInstrument.noteSampleMap, noteSampleMap)
        XCTAssertEqual(clearedInstrument.name, sourceInstrument.name)
        XCTAssertEqual(clearedInstrument.volumeEnvelope, sourceInstrument.volumeEnvelope)
        XCTAssertEqual(clearedInstrument.panningEnvelope, sourceInstrument.panningEnvelope)
        XCTAssertEqual(clearedInstrument.autoVibrato, sourceInstrument.autoVibrato)
        XCTAssertEqual(document.selection, .default)
        XCTAssertEqual(document.sampleSlotPresentationRows(forInstrument: 1).map(\.isEmptyDestination), [true])

        let sourceData = try EditableXMWriter().data(from: document)
        let sourceURL = try temporaryDestination(filename: "cleared-only-mapped-source.xm")
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let reopenedInstrument = try XCTUnwrap(song.instrumentsByIndex[1])
        XCTAssertEqual(reopenedInstrument, clearedInstrument)
        XCTAssertEqual(song.xmSampleSlotProvenanceByInstrument[1], [
            .init(sampleIndex: 0, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true),
        ])
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrument: reopenedInstrument
        ))

        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(copiedDocument) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected cleared mapped-only source to become editable")
        }
        XCTAssertEqual(copiedDocument.instrumentPalette[1], clearedInstrument)
        XCTAssertEqual(copiedDocument.selection, .default)
        XCTAssertEqual(try EditableXMWriter().data(from: copiedDocument), sourceData)
    }

    func testClearingHighestUnreferencedSelectedSampleKeepsSessionDestinationButDoesNotExtendSerializedSpan() throws {
        let first = makePlaybackSample(
            name: "Mapped S01",
            pcm: [-0.5, 0.5],
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let second = makePlaybackSample(
            sampleIndex: 1,
            name: "Unreferenced S02",
            pcm: [-0.75, 0, 0.75],
            panning: 201,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let noteSampleMap = Array(repeating: 0, count: 96)
        var document = sparseSourceDocument(
            instrument: PlaybackInstrument(
                index: 1,
                name: "Trailing Session Dest",
                samples: [first, second],
                noteSampleMap: noteSampleMap
            ),
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2)
        )

        XCTAssertTrue(document.clearSample(instrumentAt: 0, sampleAt: 1))
        let clearedInstrument = try XCTUnwrap(document.instrumentPalette[1])
        XCTAssertEqual(clearedInstrument.samples, [first])
        XCTAssertEqual(clearedInstrument.noteSampleMap, noteSampleMap)
        XCTAssertEqual(document.selection, TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2))
        let sessionRows = document.sampleSlotPresentationRows(forInstrument: 1)
        XCTAssertEqual(sessionRows.map(\.sampleSlot), [1, 2])
        XCTAssertEqual(sessionRows.map(\.isEmptyDestination), [false, true])

        let sourceData = try EditableXMWriter().data(from: document)
        let instrumentOffset = firstInstrumentOffset(in: sourceData)
        XCTAssertEqual(readLE16(sourceData, offset: instrumentOffset + 27), 1)
        let sourceURL = try temporaryDestination(filename: "cleared-unreferenced-trailing-source.xm")
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let reopenedInstrument = try XCTUnwrap(song.instrumentsByIndex[1])
        XCTAssertEqual(reopenedInstrument, clearedInstrument)
        XCTAssertEqual(reopenedInstrument.samples.map(\.sampleIndex), [0])
        XCTAssertEqual(song.xmSampleSlotProvenanceByInstrument[1], [
            .init(sampleIndex: 0, decodedPayloadLength: 2, isCanonicalEmptySlotHeader: false),
        ])

    }

    func testTrailingReferencedEmptyCanonicalSlotStillRecoversAsEditableCopy() throws {
        let first = makePlaybackSample(
            name: "Only S01",
            pcm: [-0.5, 0.5],
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[48] = 1
        let sourceInstrument = PlaybackInstrument(
            index: 1,
            name: "Trailing Empty",
            samples: [first],
            noteSampleMap: noteSampleMap
        )
        let sourceData = try EditableXMWriter().data(from: sparseSourceDocument(instrument: sourceInstrument))
        let sourceURL = try temporaryDestination(filename: "trailing-empty-source.xm")
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        XCTAssertEqual(song.xmSampleSlotProvenanceByInstrument[1], [
            .init(sampleIndex: 0, decodedPayloadLength: 2, isCanonicalEmptySlotHeader: false),
            .init(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true),
        ])
        let selectedEmptyS02 = TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: selectedEmptyS02,
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected canonical trailing empty source to become editable")
        }
        XCTAssertEqual(document.instrumentPalette[1], sourceInstrument)
        XCTAssertEqual(document.selection, selectedEmptyS02)
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1, note: 49, instrument: sourceInstrument
        ))
        XCTAssertEqual(try EditableXMWriter().data(from: document), sourceData)
    }

    func testProfileV1InertRequiredEmptyHeadersPlanNormalizedAndReachCurrentAction() throws {
        let first = makePlaybackSample(
            name: "Only S01",
            pcm: [-0.5, 0.5],
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[48] = 1
        let canonicalData = try EditableXMWriter().data(from: sparseSourceDocument(
            instrument: PlaybackInstrument(index: 1, samples: [first], noteSampleMap: noteSampleMap)
        ))
        let emptyHeaderOffset = firstInstrumentSampleHeaderOffset(in: canonicalData, sampleIndex: 1)
        let mutations: [(String, Int, UInt8)] = [
            ("name", 18, 0x4E),
            ("name-padding", 19, 0x20),
            ("volume", 12, 1),
            ("finetune", 13, 0x80),
            ("panning", 15, 128),
            ("relative-note", 16, 0x80),
            ("reserved", 17, 1),
        ]

        for (name, fieldOffset, value) in mutations {
            var sourceData = canonicalData
            sourceData[emptyHeaderOffset + fieldOffset] = value
            let sourceURL = try temporaryDestination(filename: "noncanonical-empty-\(name).xm")
            try sourceData.write(to: sourceURL, options: .atomic)
            let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
            let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
            let provenance = try XCTUnwrap(song.xmSampleSlotProvenanceByInstrument[1])
            XCTAssertEqual(provenance[1].decodedPayloadLength, 0, name)
            XCTAssertFalse(provenance[1].isCanonicalEmptySlotHeader, name)
            let context = LoadedModuleEditableCopyContext.loadedReadOnly(
                metadata: metadata,
                playbackSong: song,
                selection: .default,
                currentPatternIndex: 0,
                isPlaybackActive: false
            )

            guard case let .normalized(document, summary) = LoadedModuleEditableCopyPlanner.plan(context: context) else {
                return XCTFail("expected Profile-v1 normalized plan for \(name)")
            }
            XCTAssertEqual(summary.requiredEmptySlotsCanonicalized, 1, name)
            XCTAssertEqual(summary.trailingEmptySlotsDropped, 0, name)
            XCTAssertEqual(summary.instrumentCountAffected, 1, name)
            XCTAssertEqual(document.instrumentPalette[1]?.noteSampleMap, noteSampleMap, name)
            XCTAssertNil(document.instrumentPalette[1]?.sample(mappedSampleIndex: 1), name)
            XCTAssertEqual(document.instrumentPalette[1]?.samples.first, first, name)
            XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
                instrumentIndex: 1,
                note: 49,
                instrumentsByIndex: document.instrumentPalette
            ), name)
            try assertSupportedSemanticsPreserved(context: context, document: document, message: name)
            XCTAssertTrue(LoadedModuleEditableCopyCoordinator.canMakeEditableCopy(context: context), name)
            XCTAssertEqual(
                LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context),
                .normalized(document, summary),
                name
            )
            XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData, name)
        }
    }

    func testProfileV1TrailingEmptyHeadersPlanNormalizedAndAreDroppedFromSemanticSpan() throws {
        let first = persistableSample(sampleIndex: 0, name: "Only S01", pcm: [-0.5, 0.5])
        var sourceMap = Array(repeating: 0, count: 96)
        sourceMap[48] = 2
        let source = sparseSourceDocument(instrument: PlaybackInstrument(
            index: 1,
            samples: [first],
            noteSampleMap: sourceMap
        ))
        var data = try EditableXMWriter().data(from: source)
        let instrumentOffset = firstInstrumentOffset(in: data)
        data.replaceSubrange(instrumentOffset + 33..<instrumentOffset + 129, with: repeatElement(0, count: 96))
        data[firstInstrumentSampleHeaderOffset(in: data, sampleIndex: 2) + 12] = 32
        let context = try loadedContext(from: data, filename: "planner-trailing-normalized.xm")

        guard case let .normalized(document, summary) = LoadedModuleEditableCopyPlanner.plan(context: context) else {
            return XCTFail("expected trailing empty slots to plan a normalized copy")
        }
        XCTAssertEqual(summary.requiredEmptySlotsCanonicalized, 0)
        XCTAssertEqual(summary.trailingEmptySlotsDropped, 2)
        XCTAssertEqual(summary.instrumentCountAffected, 1)
        XCTAssertEqual(document.instrumentPalette[1]?.samples, [first])
        XCTAssertEqual(document.instrumentPalette[1]?.noteSampleMap, Array(repeating: 0, count: 96))
        try assertSupportedSemanticsPreserved(context: context, document: document)
        XCTAssertTrue(LoadedModuleEditableCopyCoordinator.canMakeEditableCopy(context: context))
    }

    func testProfileV1CombinedRequiredAndTrailingNormalizationCountsAndRouting() throws {
        let first = persistableSample(sampleIndex: 0, name: "Only S01", pcm: [-0.5, 0.5])
        var sourceMap = Array(repeating: 0, count: 96)
        sourceMap[48] = 2
        let source = sparseSourceDocument(instrument: PlaybackInstrument(
            index: 1,
            samples: [first],
            noteSampleMap: sourceMap
        ))
        var data = try EditableXMWriter().data(from: source)
        let instrumentOffset = firstInstrumentOffset(in: data)
        data.replaceSubrange(instrumentOffset + 33..<instrumentOffset + 129, with: repeatElement(0, count: 96))
        data[instrumentOffset + 33 + 48] = 1
        data[firstInstrumentSampleHeaderOffset(in: data, sampleIndex: 1) + 15] = 64
        data[firstInstrumentSampleHeaderOffset(in: data, sampleIndex: 2) + 18] = 0x42
        let context = try loadedContext(from: data, filename: "planner-combined-normalized.xm")

        guard case let .normalized(document, summary) = LoadedModuleEditableCopyPlanner.plan(context: context) else {
            return XCTFail("expected combined Profile-v1 normalized plan")
        }
        XCTAssertEqual(summary.requiredEmptySlotsCanonicalized, 1)
        XCTAssertEqual(summary.trailingEmptySlotsDropped, 1)
        XCTAssertEqual(summary.instrumentCountAffected, 1)
        XCTAssertEqual(document.instrumentPalette[1]?.noteSampleMap?[48], 1)
        XCTAssertNil(document.instrumentPalette[1]?.sample(mappedSampleIndex: 1))
        XCTAssertNil(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1,
            note: 49,
            instrumentsByIndex: document.instrumentPalette
        ))
        XCTAssertEqual(PlaybackInstrumentSampleResolver.resolveSample(
            instrumentIndex: 1,
            note: 1,
            instrumentsByIndex: document.instrumentPalette
        )?.sampleIndex, 0)
        try assertSupportedSemanticsPreserved(context: context, document: document)
    }

    func testPlannerRejectsSampleAndKeymapBoundaryAmbiguity() {
        let first = persistableSample(sampleIndex: 0, name: "S01", pcm: [-0.5, 0.5])
        var missingMap = Array(repeating: 0, count: 96)
        missingMap[48] = 1
        let sourceSlots: [(String, XMSourceSampleSlotProvenance)] = [
            ("declared-payload", profileEmptyProvenance(sampleIndex: 1, declaredPayloadLength: 1)),
            ("decoded-payload", profileEmptyProvenance(sampleIndex: 1, decodedPayloadLength: 1)),
            ("extended-header", profileEmptyProvenance(sampleIndex: 1, sampleHeaderSize: 41)),
            ("loop-start", profileEmptyProvenance(sampleIndex: 1, loopStart: 1)),
            ("loop-length", profileEmptyProvenance(sampleIndex: 1, loopLength: 1)),
            ("active-loop", profileEmptyProvenance(sampleIndex: 1, typeFlags: 0x01)),
            ("sixteen-bit", profileEmptyProvenance(sampleIndex: 1, typeFlags: 0x10)),
        ]
        for (name, missingSlot) in sourceSlots {
            let instrument = PlaybackInstrument(index: 1, samples: [first], noteSampleMap: missingMap)
            let context = planningContext(
                instrumentsByIndex: [1: instrument],
                provenance: [1: [
                    .init(sampleIndex: 0, decodedPayloadLength: first.pcm.count, isCanonicalEmptySlotHeader: false),
                    missingSlot,
                ]]
            )
            XCTAssertEqual(
                LoadedModuleEditableCopyPlanner.plan(context: context),
                .unavailable(.unsupportedSampleOrKeymapBoundary),
                name
            )
        }

        let invalidIdentities = PlaybackInstrument(
            index: 1,
            samples: [persistableSample(sampleIndex: 16, name: "S17", pcm: [-0.5, 0.5])],
            noteSampleMap: Array(repeating: 16, count: 96)
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyPlanner.plan(context: planningContext(instrumentsByIndex: [1: invalidIdentities])),
            .unavailable(.unsupportedSampleOrKeymapBoundary)
        )

        let invalidMap = PlaybackInstrument(
            index: 1,
            samples: [first],
            noteSampleMap: Array(repeating: 16, count: 96)
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyPlanner.plan(context: planningContext(instrumentsByIndex: [1: invalidMap])),
            .unavailable(.unsupportedSampleOrKeymapBoundary)
        )
    }

    func testPlannerRejectsRepresentedSamplesWithoutCanonicalKeymap() {
        let sample = persistableSample(sampleIndex: 0, name: "S01", pcm: [-0.5, 0.5])
        for map in [nil, Array(repeating: 0, count: 95)] as [[Int]?] {
            let instrument = PlaybackInstrument(index: 1, samples: [sample], noteSampleMap: map)
            XCTAssertEqual(
                LoadedModuleEditableCopyPlanner.plan(context: planningContext(instrumentsByIndex: [1: instrument])),
                .unavailable(.unsupportedSampleOrKeymapBoundary)
            )
        }

        let emptyWithoutSourceMap = PlaybackInstrument(index: 1, samples: [], noteSampleMap: nil)
        XCTAssertEqual(
            LoadedModuleEditableCopyPlanner.plan(context: planningContext(
                instrumentsByIndex: [1: emptyWithoutSourceMap],
                patternInstrument: 0,
                provenance: [1: [profileEmptyProvenance(sampleIndex: 0)]]
            )),
            .unavailable(.unsupportedSampleOrKeymapBoundary)
        )
    }

    func testPlannerRejectsWriterUnstableEnvelopeState() {
        let sample = persistableSample(sampleIndex: 0, name: "S01", pcm: [-0.5, 0.5])
        let points = [PlaybackEnvelopePoint(tick: 0, value: 64), .init(tick: 8, value: 32)]
        let unstableInstruments = [
            PlaybackInstrument(
                index: 1,
                samples: [sample],
                volumeEnvelope: PlaybackVolumeEnvelope(
                    enabled: true,
                    points: points,
                    sustainPointIndex: nil,
                    loopStartPointIndex: 0,
                    loopEndPointIndex: 1,
                    typeFlags: 0x03,
                    fadeout: 1_024
                ),
                noteSampleMap: Array(repeating: 0, count: 96)
            ),
            PlaybackInstrument(
                index: 1,
                samples: [sample],
                panningEnvelope: PlaybackPanningEnvelope(
                    enabled: true,
                    points: points,
                    sustainPointIndex: 0,
                    loopStartPointIndex: 0,
                    loopEndPointIndex: 1,
                    typeFlags: 0x0F
                ),
                noteSampleMap: Array(repeating: 0, count: 96)
            ),
        ]

        for instrument in unstableInstruments {
            XCTAssertEqual(
                LoadedModuleEditableCopyPlanner.plan(context: planningContext(instrumentsByIndex: [1: instrument])),
                .unavailable(.representedInstrumentStateUnstable)
            )
        }
    }

    func testPlannerRejectsInstrumentIdentityInstabilityAndIncompletePalette() {
        let instrument = PlaybackInstrument(
            index: 1,
            samples: [persistableSample(sampleIndex: 0, name: "S01", pcm: [-0.5, 0.5])],
            noteSampleMap: Array(repeating: 0, count: 96)
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyPlanner.plan(context: planningContext(
                instrumentsByIndex: [1: instrument],
                metadataInstrumentCount: 2
            )),
            .unavailable(.instrumentIdentityUnstable)
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyPlanner.plan(context: planningContext(
                instrumentsByIndex: [1: instrument],
                metadataInstrumentCount: 1,
                patternInstrument: 2
            )),
            .unavailable(.instrumentIdentityUnstable)
        )
    }

    func testPlannerRejectsInvalidRepresentedLoopStateAndOtherWriterFailures() {
        let looped = makePlaybackSample(
            name: "Invalid Loop",
            pcm: [-0.5, 0.5],
            baseSampleRate: PlaybackSample.xmNeutralSampleRate,
            loopStart: 1,
            loopLength: 0,
            loopType: 1,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let loopInstrument = PlaybackInstrument(
            index: 1,
            samples: [looped],
            noteSampleMap: Array(repeating: 0, count: 96)
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyPlanner.plan(context: planningContext(instrumentsByIndex: [1: loopInstrument])),
            .unavailable(.representedLoopStateUnsupported)
        )

        let unsupportedPCM = makePlaybackSample(
            name: "Unsupported Depth",
            pcm: [-0.5, 0.5],
            baseSampleRate: 8_363,
            sourceBitDepthBits: 24,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        let unsupportedInstrument = PlaybackInstrument(
            index: 1,
            samples: [unsupportedPCM],
            noteSampleMap: Array(repeating: 0, count: 96)
        )
        XCTAssertEqual(
            LoadedModuleEditableCopyPlanner.plan(context: planningContext(instrumentsByIndex: [1: unsupportedInstrument])),
            .unavailable(.writerUnsupported)
        )
    }

    @MainActor
    func testNonCenterSamplePanningSurvivesLoadedCopyExportAndReopenRoundTrip() throws {
        let sourceURL = try temporaryDestination(filename: "sample-panning-source.xm")
        let sourceData = try EditableXMWriter().data(from: samplePanningSourceDocument(panning: 37))
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        XCTAssertEqual(context.kind, .loadedReadOnly)
        XCTAssertEqual(loadedSong.instrumentsByIndex[1]?.samples.first?.panning, 37)
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected generated public-safe XM to become an editable copy")
        }
        XCTAssertEqual(document.instrumentPalette[1]?.samples.first?.panning, 37)

        var editedDocument = document
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: editedDocument, isPlaybackActive: false) },
            documentApplyHandler: { editedDocument = $0 }
        )
        XCTAssertTrue(coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 201))
        XCTAssertEqual(editedDocument.selection, document.selection)
        let sourceSample = try XCTUnwrap(loadedSong.instrumentsByIndex[1]?.samples.first)
        let editedSample = try XCTUnwrap(editedDocument.instrumentPalette[1]?.samples.first)
        XCTAssertEqual(editedSample.panning, 201)
        XCTAssertEqual(editedSample.withPanning(37), sourceSample)

        let destination = try temporaryDestination(filename: "sample-panning-export.xm")
        let result = ExportXMCoordinator(
            destinationProvider: FakeEditableCopyExportXMDestinationProvider(destination: destination)
        ).beginExport(context: .editable(
            document: editedDocument,
            displayName: editedDocument.title,
            isPlaybackActive: false
        ))
        XCTAssertEqual(result, .exported(destination: destination))

        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        let reopenedSample = try XCTUnwrap(reopenedSong.instrumentsByIndex[1]?.samples.first)
        XCTAssertEqual(reopenedSample.panning, 201)
        XCTAssertEqual(reopenedSample.withPanning(37), sourceSample)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
    }

    @MainActor
    func testEditedSampleVolumeSurvivesLoadedCopyExportAndReopenRoundTrip() throws {
        let sourceURL = try temporaryDestination(filename: "sample-volume-source.xm")
        let sourceData = try EditableXMWriter().data(from: samplePanningSourceDocument(panning: 37, volume: 48))
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected generated public-safe XM to become an editable copy")
        }
        let sourceSample = try XCTUnwrap(loadedSong.instrumentsByIndex[1]?.samples.first)
        XCTAssertEqual(sourceSample.xmVolume, 48)
        XCTAssertEqual(document.instrumentPalette[1]?.samples.first?.xmVolume, 48)

        var editedDocument = document
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: editedDocument, isPlaybackActive: false) },
            documentApplyHandler: { editedDocument = $0 }
        )
        XCTAssertTrue(coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 17))
        let editedSample = try XCTUnwrap(editedDocument.instrumentPalette[1]?.samples.first)
        XCTAssertEqual(editedSample.xmVolume, 17)
        XCTAssertEqual(editedSample.withVolume(48), sourceSample)
        XCTAssertEqual(editedDocument.selection, document.selection)

        let destination = try temporaryDestination(filename: "sample-volume-export.xm")
        let result = ExportXMCoordinator(
            destinationProvider: FakeEditableCopyExportXMDestinationProvider(destination: destination)
        ).beginExport(context: .editable(
            document: editedDocument,
            displayName: editedDocument.title,
            isPlaybackActive: false
        ))
        XCTAssertEqual(result, .exported(destination: destination))

        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        let reopenedSample = try XCTUnwrap(reopenedSong.instrumentsByIndex[1]?.samples.first)
        XCTAssertEqual(reopenedSample.xmVolume, 17)
        XCTAssertEqual(reopenedSample.withVolume(48), sourceSample)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    @MainActor
    func testInstrumentPanningEnvelopeAndAutoVibratoSurviveLoadedCopyExportAndReopenRoundTrip() throws {
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
        let sourceURL = try temporaryDestination(filename: "instrument-autovibrato-source.xm")
        let sourceData = try EditableXMWriter().data(from: samplePanningSourceDocument(
            panning: 37,
            panningEnvelope: panningEnvelope,
            autoVibrato: autoVibrato
        ))
        try sourceData.write(to: sourceURL, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )

        XCTAssertEqual(loadedSong.instrumentsByIndex[1]?.panningEnvelope, panningEnvelope)
        XCTAssertEqual(loadedSong.instrumentsByIndex[1]?.autoVibrato, autoVibrato)
        XCTAssertEqual(loadedSong.instrumentsByIndex[1]?.samples.first?.panning, 37)
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected generated public-safe XM to become an editable copy")
        }
        XCTAssertEqual(document.instrumentPalette[1]?.panningEnvelope, panningEnvelope)
        XCTAssertEqual(document.instrumentPalette[1]?.autoVibrato, autoVibrato)
        XCTAssertEqual(document.instrumentPalette[1]?.samples.first?.panning, 37)

        let destination = try temporaryDestination(filename: "instrument-autovibrato-export.xm")
        let result = ExportXMCoordinator(
            destinationProvider: FakeEditableCopyExportXMDestinationProvider(destination: destination)
        ).beginExport(context: .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        ))
        XCTAssertEqual(result, .exported(destination: destination))

        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1]?.panningEnvelope, panningEnvelope)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1]?.autoVibrato, autoVibrato)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1]?.samples.first?.panning, 37)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
    }

    @MainActor
    func testSustainedFixtureLoadsCopiesAndNoEditRoundTripsExactSemantics() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-sustained-defaults.xm")
        let sourceData = try Data(contentsOf: sourceURL)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let instrument = try XCTUnwrap(loadedSong.instrumentsByIndex[1])
        let sample = try XCTUnwrap(instrument.samples.first)

        XCTAssertEqual(metadata.title, "VTX SUSTAINED")
        XCTAssertEqual(metadata.instruments, 1)
        XCTAssertEqual(metadata.xmPatterns.map(\.rowCount), [64])
        XCTAssertEqual(instrument.name, "SUSTAINED DEFAULTS")
        XCTAssertEqual(sample.name, "SINE SUSTAIN 16")
        XCTAssertEqual(sample.sampleLength, 16_384)
        XCTAssertEqual(sample.sourceBitDepthBits, 16)
        XCTAssertEqual(sample.xmVolume, 64)
        XCTAssertEqual(sample.panning, 128)
        XCTAssertEqual(sample.finetune, 0)
        XCTAssertEqual(sample.relativeNote, 0)
        XCTAssertEqual(sample.loopType, 1)
        XCTAssertEqual(sample.loopStart, 4_096)
        XCTAssertEqual(sample.loopLength, 8_192)
        XCTAssertEqual(pcmSHA256(sample), "46c42a0de8820c8b24419c1676b183398d1e7ced677860df1fe0ea45a48779b0")
        XCTAssertEqual(instrument.volumeEnvelope.points, [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 24, value: 56),
            PlaybackEnvelopePoint(tick: 48, value: 64),
        ])

        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        XCTAssertFalse(ExportXMCoordinator.canExport(context: .loadedReadOnly(isPlaybackActive: false)))
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected sustained fixture to become an editable copy")
        }
        guard case .potentiallyAvailable = document.noteAuditionAvailability else {
            return XCTFail("expected sustained fixture note preview to be available")
        }
        XCTAssertEqual(document.instrumentPalette, loadedSong.instrumentsByIndex)

        let destination = try temporaryDestination(filename: "round-trip-sustained.xm")
        try EditableXMWriter().data(from: document).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedMetadata.orderTable, metadata.orderTable)
        XCTAssertEqual(reopenedMetadata.xmPatterns, metadata.xmPatterns)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, loadedSong.instrumentsByIndex)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    @MainActor
    func testSustainedFixtureSupportsFocusedEditsUndoRedoAndExportReopen() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-sustained-defaults.xm")
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(sourceDocument) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected sustained fixture to become editable")
        }
        let sourceInstrument = try XCTUnwrap(sourceDocument.instrumentPalette[1])
        let sourceSample = try XCTUnwrap(sourceInstrument.samples.first)
        let sourcePlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: sourceDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        var editedDocument = sourceDocument
        var playbackActive = false
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: editedDocument, isPlaybackActive: playbackActive) },
            documentApplyHandler: { editedDocument = $0 }
        )

        XCTAssertTrue(coordinator.renameInstrument(at: 0, name: "Edited Sustained"))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.name, sourceInstrument.name)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 201))
        let panningPlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: editedDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        XCTAssertEqual(panningPlan.pattern.events.map(\.pan), Array(
            repeating: PlaybackSamplePanningPolicy.plannedPan(201),
            count: sourcePlan.pattern.events.count
        ))
        XCTAssertEqual(panningPlan.pattern.events.map(\.row), sourcePlan.pattern.events.map(\.row))
        XCTAssertEqual(panningPlan.pattern.events.map(\.tick), sourcePlan.pattern.events.map(\.tick))
        XCTAssertEqual(panningPlan.pattern.events.map(\.gain), sourcePlan.pattern.events.map(\.gain))
        XCTAssertEqual(panningPlan.pattern.events.map(\.playbackStep), sourcePlan.pattern.events.map(\.playbackStep))
        XCTAssertEqual(panningPlan.pattern.events.map(\.sample), sourcePlan.pattern.events.map(\.sample))
        XCTAssertEqual(panningPlan.pattern.events.map(\.loop), sourcePlan.pattern.events.map(\.loop))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.samples.first?.panning, 128)
        XCTAssertTrue(coordinator.redo())

        XCTAssertTrue(coordinator.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 17))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.samples.first?.xmVolume, 64)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleFinetune(instrumentAt: 0, sampleAt: 0, finetune: 64))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.samples.first?.finetune, 0)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleRelativeNote(instrumentAt: 0, sampleAt: 0, relativeNote: -12))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[1]?.samples.first?.relativeNote, 0)
        XCTAssertTrue(coordinator.redo())

        playbackActive = true
        let previewAvailability = editedDocument.noteAuditionAvailability
        XCTAssertFalse(coordinator.setSamplePanning(instrumentAt: 0, sampleAt: 0, panning: 17))
        XCTAssertEqual(editedDocument.noteAuditionAvailability, previewAvailability)
        playbackActive = false

        let editedInstrument = try XCTUnwrap(editedDocument.instrumentPalette[1])
        let editedSample = try XCTUnwrap(editedInstrument.samples.first)
        XCTAssertEqual(editedInstrument.name, "Edited Sustained")
        XCTAssertEqual(editedSample.panning, 201)
        XCTAssertEqual(editedSample.xmVolume, 17)
        XCTAssertEqual(editedSample.finetune, 64)
        XCTAssertEqual(editedSample.relativeNote, -12)
        XCTAssertEqual(editedSample.pcm, sourceSample.pcm)
        XCTAssertEqual(editedSample.loopRegion, sourceSample.loopRegion)
        XCTAssertEqual(editedInstrument.volumeEnvelope, sourceInstrument.volumeEnvelope)
        let editedPlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: editedDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        let sourceEvent = try XCTUnwrap(sourcePlan.pattern.events.first)
        let editedEvent = try XCTUnwrap(editedPlan.pattern.events.first)
        XCTAssertEqual(editedEvent.gain, 17.0 / 64.0, accuracy: 0.000_001)
        XCTAssertEqual(
            editedEvent.playbackStep,
            sourceEvent.playbackStep * pow(2.0, -11.5 / 12.0),
            accuracy: 0.000_001
        )

        let destination = try temporaryDestination(filename: "edited-sustained.xm")
        try EditableXMWriter().data(from: editedDocument).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedSong.instrumentsByIndex[1], editedInstrument)
    }

    @MainActor
    func testMetadataMatrixFixtureLoadsCopiesAndNoEditRoundTripsExactSemantics() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-metadata-matrix.xm")
        let sourceData = try Data(contentsOf: sourceURL)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let samples = try (1...5).map { try XCTUnwrap(loadedSong.instrumentsByIndex[$0]?.samples.first) }

        XCTAssertEqual(metadata.title, "VTX META MATRIX")
        XCTAssertEqual(metadata.instruments, 5)
        XCTAssertEqual(metadata.xmPatterns.map(\.rowCount), [48])
        XCTAssertEqual(samples.map(\.xmVolume), [0, 16, 32, 48, 64])
        XCTAssertEqual(samples.map(\.panning), [0, 64, 128, 192, 255])
        XCTAssertEqual(samples.map(\.finetune), [-96, -32, 0, 48, 96])
        XCTAssertEqual(samples.map(\.relativeNote), [-12, 5, -5, 12, 0])
        XCTAssertEqual(samples.map(\.sourceBitDepthBits), [8, 16, 8, 16, 8])
        XCTAssertEqual(samples.map(\.loopType), [0, 1, 2, 0, 1])
        XCTAssertEqual(samples.map(pcmSHA256), [
            "47a72c66257b66e4f88bb5e0debaf033873db681b1355945de9370f4bac43984",
            "f333231435f182b19ad8e75a6687fa3ee79d963a36ba6a7599e5f9612e49d838",
            "fad28cc0b65e3ca34d80665310de002cce1ea02327185abae6eb2676945891dc",
            "1bab28408c4d7ac5b9ed7d8d87595ec051ce5f744077487865dbde189b63ab33",
            "151d0d127539d5eb8c8a7dbcfb3d1b01434ed30c6f63325d770b05b080e5b147",
        ])

        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 3, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected metadata matrix to become editable")
        }
        XCTAssertEqual(document.instrumentPalette, loadedSong.instrumentsByIndex)

        let destination = try temporaryDestination(filename: "round-trip-metadata-matrix.xm")
        try EditableXMWriter().data(from: document).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedMetadata.xmPatterns, metadata.xmPatterns)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, loadedSong.instrumentsByIndex)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    @MainActor
    func testMetadataMatrixFocusedMutationPreservesNeighborsAndPanningAffectsNextPlan() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-metadata-matrix.xm")
        let sourceData = try Data(contentsOf: sourceURL)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(selectedInstrument: 3, selectedSample: 1),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(sourceDocument) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected metadata matrix to become editable")
        }
        let sourceInstrument = try XCTUnwrap(sourceDocument.instrumentPalette[3])
        let sourceSample = try XCTUnwrap(sourceInstrument.samples.first)
        let sourcePlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: sourceDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        var editedDocument = sourceDocument
        let coordinator = EditableDocumentEditCoordinator(
            contextProvider: { .editable(document: editedDocument, isPlaybackActive: false) },
            documentApplyHandler: { editedDocument = $0 }
        )

        XCTAssertTrue(coordinator.setSamplePanning(instrumentAt: 2, sampleAt: 0, panning: 37))
        let editedPanningPlan = PlaybackSongSyntheticAdapter.adapt(
            EditablePlaybackSongBuilder.build(from: editedDocument),
            orderIndex: 0,
            sampleRate: 100
        )
        let sourceMapping = try XCTUnwrap(sourcePlan.diagnostics.eventMappings.first { $0.instrumentIndex == 3 })
        let editedMapping = try XCTUnwrap(editedPanningPlan.diagnostics.eventMappings.first { $0.instrumentIndex == 3 })
        let sourceEvent = sourcePlan.pattern.events[sourceMapping.eventIndex]
        let editedEvent = editedPanningPlan.pattern.events[editedMapping.eventIndex]
        XCTAssertEqual(sourceEvent.pan, 0)
        XCTAssertEqual(editedEvent.pan, PlaybackSamplePanningPolicy.plannedPan(37), accuracy: 0.000_001)
        XCTAssertEqual(sourceEvent.row, editedEvent.row)
        XCTAssertEqual(sourceEvent.tick, editedEvent.tick)
        XCTAssertEqual(sourceEvent.gain, editedEvent.gain)
        XCTAssertEqual(sourceEvent.playbackStep, editedEvent.playbackStep)
        XCTAssertEqual(sourcePlan.pattern.events.count, editedPanningPlan.pattern.events.count)
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[3]?.samples.first?.panning, 128)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleVolume(instrumentAt: 2, sampleAt: 0, volume: 47))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[3]?.samples.first?.xmVolume, 32)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleFinetune(instrumentAt: 2, sampleAt: 0, finetune: -17))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[3]?.samples.first?.finetune, 0)
        XCTAssertTrue(coordinator.redo())
        XCTAssertTrue(coordinator.setSampleRelativeNote(instrumentAt: 2, sampleAt: 0, relativeNote: 7))
        XCTAssertTrue(coordinator.undo())
        XCTAssertEqual(editedDocument.instrumentPalette[3]?.samples.first?.relativeNote, -5)
        XCTAssertTrue(coordinator.redo())

        let editedInstrument = try XCTUnwrap(editedDocument.instrumentPalette[3])
        let editedSample = try XCTUnwrap(editedInstrument.samples.first)
        XCTAssertEqual(editedSample.panning, 37)
        XCTAssertEqual(editedSample.xmVolume, 47)
        XCTAssertEqual(editedSample.finetune, -17)
        XCTAssertEqual(editedSample.relativeNote, 7)
        XCTAssertEqual(editedSample.pcm, sourceSample.pcm)
        XCTAssertEqual(editedSample.loopRegion, sourceSample.loopRegion)
        XCTAssertEqual(editedSample.name, sourceSample.name)
        for instrumentIndex in [1, 2, 4, 5] {
            XCTAssertEqual(editedDocument.instrumentPalette[instrumentIndex], sourceDocument.instrumentPalette[instrumentIndex])
        }

        let destination = try temporaryDestination(filename: "edited-metadata-matrix.xm")
        try EditableXMWriter().data(from: editedDocument).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, editedDocument.instrumentPalette)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    @MainActor
    func testEnvelopesKeymapFixtureLoadsCopiesAndRoundTripsExactSemantics() throws {
        let sourceURL = try referenceXMFixtureURL("generated/instrument-envelopes-keymap.xm")
        let sourceData = try Data(contentsOf: sourceURL)
        let metadata = try ModuleMetadataLoader().load(fromPath: sourceURL.path)
        let loadedSong = try PlaybackSongBuilder.build(from: metadata, modulePath: sourceURL.path)
        let instrument = try XCTUnwrap(loadedSong.instrumentsByIndex[1])

        XCTAssertEqual(metadata.title, "VTX ENV KEYMAP")
        XCTAssertEqual(metadata.xmPatterns.map(\.rowCount), [32])
        XCTAssertEqual(instrument.name, "SPLIT ENV KEYMAP")
        XCTAssertEqual(instrument.samples.map(\.name), ["LOW PULSE 8", "HIGH TRIANGLE 16"])
        XCTAssertEqual(instrument.samples.map(\.sourceBitDepthBits), [8, 16])
        XCTAssertEqual(instrument.samples.map(\.loopType), [1, 1])
        XCTAssertEqual(instrument.samples.map(\.loopStart), [256, 256])
        XCTAssertEqual(instrument.samples.map(\.loopLength), [1_536, 1_536])
        XCTAssertEqual(instrument.samples.map(pcmSHA256), [
            "405470958403dee4c1dbd41c888b2f8f6cb7c8eb5d950dcf1f4fcf09e447fc33",
            "24d3e9d895e34280cf17e78111b7c5d14c035996c8c88d8bd3a0d78c5077b46b",
        ])
        let noteSampleMap = try XCTUnwrap(instrument.noteSampleMap)
        XCTAssertEqual(Array(noteSampleMap.prefix(48)), Array(repeating: 0, count: 48))
        XCTAssertEqual(Array(noteSampleMap.suffix(48)), Array(repeating: 1, count: 48))
        XCTAssertEqual(instrument.mappedSampleIndex(forNote: 48), 0)
        XCTAssertEqual(instrument.mappedSampleIndex(forNote: 49), 1)
        XCTAssertEqual(instrument.volumeEnvelope.points, [
            PlaybackEnvelopePoint(tick: 0, value: 64),
            PlaybackEnvelopePoint(tick: 8, value: 48),
            PlaybackEnvelopePoint(tick: 16, value: 32),
            PlaybackEnvelopePoint(tick: 24, value: 64),
        ])
        XCTAssertEqual(instrument.volumeEnvelope.sustainPointIndex, 1)
        XCTAssertEqual(instrument.volumeEnvelope.loopStartPointIndex, 1)
        XCTAssertEqual(instrument.volumeEnvelope.loopEndPointIndex, 3)
        XCTAssertEqual(instrument.volumeEnvelope.typeFlags, 7)
        XCTAssertEqual(instrument.volumeEnvelope.fadeout, 2_048)
        XCTAssertEqual(instrument.panningEnvelope.points, [
            PlaybackEnvelopePoint(tick: 0, value: 32),
            PlaybackEnvelopePoint(tick: 8, value: 48),
            PlaybackEnvelopePoint(tick: 16, value: 16),
            PlaybackEnvelopePoint(tick: 24, value: 32),
        ])
        XCTAssertEqual(instrument.panningEnvelope.sustainPointIndex, 2)
        XCTAssertEqual(instrument.panningEnvelope.loopStartPointIndex, 0)
        XCTAssertEqual(instrument.panningEnvelope.loopEndPointIndex, 3)
        XCTAssertEqual(instrument.panningEnvelope.typeFlags, 7)
        XCTAssertEqual(instrument.autoVibrato, PlaybackInstrumentAutoVibrato(
            waveformType: 2,
            sweep: 8,
            depth: 6,
            rate: 24
        ))

        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata,
            playbackSong: loadedSong,
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 2),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
        guard case let .copied(document) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            return XCTFail("expected envelopes/keymap fixture to become editable")
        }
        XCTAssertEqual(document.instrumentPalette, loadedSong.instrumentsByIndex)

        let destination = try temporaryDestination(filename: "round-trip-envelopes-keymap.xm")
        try EditableXMWriter().data(from: document).write(to: destination, options: .atomic)
        let reopenedMetadata = try ModuleMetadataLoader().load(fromPath: destination.path)
        let reopenedSong = try PlaybackSongBuilder.build(from: reopenedMetadata, modulePath: destination.path)
        XCTAssertEqual(reopenedMetadata.xmPatterns, metadata.xmPatterns)
        XCTAssertEqual(reopenedSong.instrumentsByIndex, loadedSong.instrumentsByIndex)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    }

    private func supportedLoadedContext(isPlaybackActive: Bool) -> LoadedModuleEditableCopyContext {
        let pattern = pattern(
            index: 0,
            rowCount: 4,
            channels: 1,
            cells: [
                (0, 0, XMPatternEventCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0))
            ]
        )
        let metadata = makeLoadedModuleMetadata(
            channels: 1,
            instruments: 1,
            orderTable: [0],
            patterns: [pattern]
        )
        let sample = persistableSample(sampleIndex: 0, name: "Supported S01", pcm: [-0.5, 0.5])
        let instrument = PlaybackInstrument(
            index: 1,
            samples: [sample],
            noteSampleMap: Array(repeating: 0, count: 96)
        )
        let song = playbackSongMatchingMetadata(metadata, instrumentsByIndex: [1: instrument])
        return .loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: isPlaybackActive
        )
    }

    private func profileV1NormalizedContext() -> LoadedModuleEditableCopyContext {
        let first = persistableSample(sampleIndex: 0, name: "S01", pcm: [-0.5, 0.5])
        var noteSampleMap = Array(repeating: 0, count: 96)
        noteSampleMap[48] = 1
        return planningContext(
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [first], noteSampleMap: noteSampleMap),
            ],
            provenance: [
                1: [
                    .init(
                        sampleIndex: 0,
                        decodedPayloadLength: first.pcm.count,
                        isCanonicalEmptySlotHeader: false
                    ),
                    profileEmptyProvenance(sampleIndex: 1),
                ],
            ]
        )
    }

    private func nonLinearFrequencyTableContext() -> LoadedModuleEditableCopyContext {
        let context = supportedLoadedContext(isPlaybackActive: false)
        return .loadedReadOnly(
            moduleIdentity: context.moduleIdentity,
            metadata: context.loadedMetadata.map { metadata in
                makeLoadedModuleMetadata(
                    channels: metadata.channels,
                    instruments: metadata.instruments,
                    xmFlags: 0,
                    orderTable: metadata.orderTable,
                    patterns: metadata.xmPatterns
                )
            },
            playbackSong: context.loadedPlaybackSong,
            selection: context.selection,
            currentPatternIndex: context.currentPatternIndex,
            isPlaybackActive: false
        )
    }

    private func identified(
        _ context: LoadedModuleEditableCopyContext,
        identity: UUID = UUID()
    ) -> LoadedModuleEditableCopyContext {
        .loadedReadOnly(
            moduleIdentity: identity,
            metadata: context.loadedMetadata,
            playbackSong: context.loadedPlaybackSong,
            selection: context.selection,
            currentPatternIndex: context.currentPatternIndex,
            isPlaybackActive: context.isPlaybackActive
        )
    }

    private func planningContext(
        instrumentsByIndex: [Int: PlaybackInstrument],
        metadataInstrumentCount: Int? = nil,
        patternInstrument: UInt8 = 1,
        provenance: [Int: [XMSourceSampleSlotProvenance]] = [:]
    ) -> LoadedModuleEditableCopyContext {
        let sourcePattern = pattern(index: 0, rowCount: 4, channels: 1, cells: [
            (0, 0, XMPatternEventCell(
                note: 49, instrument: patternInstrument, volumeColumn: 0, effectType: 0, effectParam: 0
            )),
        ])
        let metadata = makeLoadedModuleMetadata(
            channels: 1,
            instruments: metadataInstrumentCount ?? instrumentsByIndex.count,
            orderTable: [0],
            patterns: [sourcePattern]
        )
        let song = playbackSongMatchingMetadata(
            metadata,
            instrumentsByIndex: instrumentsByIndex,
            provenance: provenance
        )
        return .loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: TrackerEditorSelection(
                selectedInstrument: instrumentsByIndex.keys.sorted().first ?? 1,
                selectedSample: 1
            ),
            currentPatternIndex: 0,
            isPlaybackActive: false
        )
    }

    private func loadedContext(from data: Data, filename: String) throws -> LoadedModuleEditableCopyContext {
        let url = try temporaryDestination(filename: filename)
        try data.write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        return .loadedReadOnly(
            metadata: metadata,
            playbackSong: song,
            selection: .default,
            currentPatternIndex: metadata.orderTable.first ?? 0,
            isPlaybackActive: false
        )
    }

    private func playbackSongMatchingMetadata(
        _ metadata: ParsedModuleMetadata,
        instrumentsByIndex: [Int: PlaybackInstrument],
        provenance: [Int: [XMSourceSampleSlotProvenance]] = [:]
    ) -> PlaybackSong {
        let base = try! PlaybackSongBuilder.build(from: metadata)
        return PlaybackSong(
            title: base.title,
            orders: base.orders,
            patternsByIndex: base.patternsByIndex,
            instrumentsByIndex: instrumentsByIndex,
            restartOrderIndex: base.restartOrderIndex,
            endBehavior: base.endBehavior,
            initialTiming: base.initialTiming,
            usesLinearFrequencyTable: base.usesLinearFrequencyTable,
            xmSampleSlotProvenanceByInstrument: provenance
        )
    }

    private func profileEmptyProvenance(
        sampleIndex: Int,
        declaredPayloadLength: Int = 0,
        decodedPayloadLength: Int = 0,
        sampleHeaderSize: Int = 40,
        loopStart: Int = 0,
        loopLength: Int = 0,
        typeFlags: UInt8 = 0
    ) -> XMSourceSampleSlotProvenance {
        XMSourceSampleSlotProvenance(
            sampleIndex: sampleIndex,
            decodedPayloadLength: decodedPayloadLength,
            isCanonicalEmptySlotHeader: false,
            declaredPayloadLength: declaredPayloadLength,
            sampleHeaderSize: sampleHeaderSize,
            loopStart: loopStart,
            loopLength: loopLength,
            typeFlags: typeFlags
        )
    }

    private func assertSupportedSemanticsPreserved(
        context: LoadedModuleEditableCopyContext,
        document: BlankTrackerDocument,
        message: String = ""
    ) throws {
        let source = try XCTUnwrap(context.loadedPlaybackSong, message)
        let candidate = EditablePlaybackSongBuilder.build(from: document)
        XCTAssertEqual(candidate.orders, source.orders, message)
        XCTAssertEqual(candidate.patternsByIndex, source.patternsByIndex, message)
        XCTAssertEqual(candidate.initialTiming, source.initialTiming, message)
        XCTAssertEqual(candidate.usesLinearFrequencyTable, source.usesLinearFrequencyTable, message)
        XCTAssertEqual(candidate.instrumentsByIndex, source.instrumentsByIndex, message)
        XCTAssertEqual(document.instrumentPalette, source.instrumentsByIndex, message)

        for instrumentIndex in Set(source.instrumentsByIndex.keys).union(candidate.instrumentsByIndex.keys) {
            for note in UInt8(1)...UInt8(96) {
                let sourceResolution = source.resolveSample(instrumentIndex: instrumentIndex, note: note)
                let candidateResolution = candidate.resolveSample(instrumentIndex: instrumentIndex, note: note)
                XCTAssertEqual(sourceResolution, candidateResolution, "\(message) I\(instrumentIndex) note \(note)")
            }
        }
        XCTAssertNoThrow(try EditableXMWriter().data(from: document), message)
    }

    private func sparseSourceDocument(
        instrument: PlaybackInstrument,
        selection: TrackerEditorSelection = .default
    ) -> BlankTrackerDocument {
        BlankTrackerDocument(
            title: BlankTrackerDocument.defaultTitle,
            songLength: 1,
            currentPosition: 0,
            restartPosition: 0,
            currentPatternIndex: 0,
            tempo: 125,
            speed: 6,
            orderTable: [0],
            selection: selection,
            instrumentPalette: [instrument.index: instrument],
            patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)]
        )
    }

    private func persistableSample(sampleIndex: Int, name: String, pcm: [Float]) -> PlaybackSample {
        makePlaybackSample(
            sampleIndex: sampleIndex, name: name, pcm: pcm, baseSampleRate: 8_363,
            sourceBitDepthBits: 8, sourceIsSignedPCM: true, sourceIsDeltaEncoded: true
        )
    }

    private func assertDuplicatePersistence(
        _ document: BlankTrackerDocument,
        instrument: PlaybackInstrument,
        filename: String
    ) throws -> PlaybackSong {
        let data = try EditableXMWriter().data(from: document)
        let url = try temporaryDestination(filename: filename)
        try data.write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        XCTAssertEqual(song.instrumentsByIndex[1], instrument)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata, playbackSong: song, selection: document.selection,
            currentPatternIndex: 0, isPlaybackActive: false
        )
        guard case let .copied(copy) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            XCTFail("duplicate export was unexpectedly unavailable for editable copy")
            return song
        }
        XCTAssertEqual(copy.instrumentPalette[1], instrument)
        XCTAssertEqual(copy.selection, document.selection)
        XCTAssertEqual(try EditableXMWriter().data(from: copy), data)
        return song
    }

    private func assertPermutationPersistence(
        _ document: BlankTrackerDocument,
        instrument: PlaybackInstrument,
        filename: String
    ) throws -> PlaybackSong {
        let data = try EditableXMWriter().data(from: document)
        let url = try temporaryDestination(filename: filename)
        try data.write(to: url, options: .atomic)
        let metadata = try ModuleMetadataLoader().load(fromPath: url.path)
        let song = try PlaybackSongBuilder.build(from: metadata, modulePath: url.path)
        XCTAssertEqual(song.instrumentsByIndex[1], instrument)
        let context = LoadedModuleEditableCopyContext.loadedReadOnly(
            metadata: metadata, playbackSong: song, selection: document.selection,
            currentPatternIndex: 0, isPlaybackActive: false
        )
        guard case let .copied(copy) = LoadedModuleEditableCopyCoordinator().makeEditableCopy(context: context) else {
            XCTFail("permuted export was unexpectedly unavailable for editable copy")
            return song
        }
        XCTAssertEqual(copy.instrumentPalette[1], instrument)
        XCTAssertEqual(copy.selection, document.selection)
        XCTAssertEqual(try EditableXMWriter().data(from: copy), data)
        return song
    }

    private func firstInstrumentSampleHeaderOffset(in data: Data, sampleIndex: Int) -> Int {
        let offset = firstInstrumentOffset(in: data)
        let instrumentHeaderSize = Int(readLE32(data, offset: offset))
        let sampleHeaderSize = Int(readLE32(data, offset: offset + 29))
        return offset + instrumentHeaderSize + (sampleIndex * sampleHeaderSize)
    }

    private func firstInstrumentOffset(in data: Data) -> Int {
        var offset = 60 + Int(readLE32(data, offset: 60))
        for _ in 0..<Int(readLE16(data, offset: 70)) {
            offset += Int(readLE32(data, offset: offset)) + Int(readLE16(data, offset: offset + 7))
        }
        return offset
    }

    private func readLE16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readLE32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private func samplePanningSourceDocument(
        panning: UInt8,
        volume: UInt8 = 64,
        panningEnvelope: PlaybackPanningEnvelope = .disabled,
        autoVibrato: PlaybackInstrumentAutoVibrato = .disabled
    ) -> BlankTrackerDocument {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: 0, rowCount: 4, channels: 1)
        pattern.rows[0][0] = XMPatternEventCell(
            note: 49,
            instrument: 1,
            volumeColumn: 0,
            effectType: 0,
            effectParam: 0
        )
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            name: "Panning Sample",
            pcm: [0, 0.5, -0.5, 0.25],
            volume: Float(volume) / 64.0,
            panning: panning,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363,
            sourceBitDepthBits: 8,
            sourceIsSignedPCM: true,
            sourceIsDeltaEncoded: true
        )
        return BlankTrackerDocument(
            title: "Panning Source",
            songLength: 1,
            currentPosition: 0,
            restartPosition: 0,
            currentPatternIndex: 0,
            tempo: 125,
            speed: 6,
            orderTable: [0],
            selection: TrackerEditorSelection(selectedInstrument: 1, selectedSample: 1),
            instrumentPalette: [
                1: PlaybackInstrument(
                    index: 1,
                    name: "Panning Instrument",
                    samples: [sample],
                    panningEnvelope: panningEnvelope,
                    autoVibrato: autoVibrato
                )
            ],
            patterns: [pattern]
        )
    }

    private func makeLoadedModuleMetadata(
        type: String = "XM",
        title: String = "Loaded Module",
        channels: Int = 1,
        instruments: Int = 0,
        xmFlags: Int = 0x0001,
        defaultTempo: Int = 6,
        defaultBPM: Int = 125,
        songLength: Int? = nil,
        restartPosition: Int = 0,
        orderTable: [Int] = [0],
        patterns: [XMPatternData]
    ) -> ParsedModuleMetadata {
        ParsedModuleMetadata(
            type: type,
            title: title,
            version: type == "XM" ? "1.4" : nil,
            channels: channels,
            patterns: patterns.count,
            instruments: instruments,
            xmFlags: xmFlags,
            defaultTempo: defaultTempo,
            defaultBPM: defaultBPM,
            songLength: songLength ?? orderTable.count,
            restartPosition: restartPosition,
            orderTable: orderTable,
            xmPatterns: patterns
        )
    }

    private func referenceXMFixtureURL(_ relativePath: String) throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("tests/reference-xm")
            .appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing reference XM fixture \(relativePath)")
        }
        return url
    }

    private func pcmSHA256(_ sample: PlaybackSample) -> String {
        var data = Data()
        if sample.sourceBitDepthBits == 16 {
            for value in sample.pcm {
                let quantized = UInt16(truncatingIfNeeded: max(-32_768, min(32_767, Int((value * 32_768).rounded()))))
                data.append(UInt8(quantized & 0x00FF))
                data.append(UInt8((quantized >> 8) & 0x00FF))
            }
        } else {
            for value in sample.pcm {
                data.append(UInt8(truncatingIfNeeded: max(-128, min(127, Int((value * 128).rounded())))))
            }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func temporaryDestination(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtx-editable-copy-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent(filename)
    }

    private func pattern(
        index: Int,
        rowCount: Int,
        channels: Int,
        cells: [(row: Int, channel: Int, cell: XMPatternEventCell)]
    ) -> XMPatternData {
        var pattern = BlankTrackerDocument.makeEmptyPattern(index: index, rowCount: rowCount, channels: channels)
        for cell in cells where pattern.rows.indices.contains(cell.row) && pattern.rows[cell.row].indices.contains(cell.channel) {
            pattern.rows[cell.row][cell.channel] = cell.cell
        }
        return pattern
    }
}

@MainActor
private final class FakeEditableCopyExportXMDestinationProvider: ExportXMDestinationProviding {
    private let destination: URL?
    private(set) var requests = [ExportXMDestinationRequest]()

    init(destination: URL?) {
        self.destination = destination
    }

    func chooseExportXMDestination(request: ExportXMDestinationRequest) -> URL? {
        requests.append(request)
        return destination
    }
}
