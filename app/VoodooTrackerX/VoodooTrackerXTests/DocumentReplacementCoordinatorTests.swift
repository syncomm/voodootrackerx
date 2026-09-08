import AppKit
import XCTest

@MainActor
final class DocumentReplacementCoordinatorTests: XCTestCase {
    func testCanonicalFileNewDocumentHasNoDiscardableContent() {
        XCTAssertFalse(BlankTrackerDocument.makeDefault().hasDiscardableEditableContent)
    }

    func testNavigationOnlyDoesNotCreateDiscardableContent() {
        let document = copy(
            BlankTrackerDocument.makeDefault(),
            currentPosition: 4,
            currentPatternIndex: 7
        )

        XCTAssertFalse(document.hasDiscardableEditableContent)
    }

    func testInstrumentAndSampleSelectionOnlyDoNotCreateDiscardableContent() {
        let document = copy(
            BlankTrackerDocument.makeDefault(),
            selection: TrackerEditorSelection(selectedInstrument: 9, selectedSample: 12)
        )

        XCTAssertFalse(document.hasDiscardableEditableContent)
    }

    func testEnteredPatternNoteCreatesDiscardableContent() {
        var document = BlankTrackerDocument.makeDefault()

        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        XCTAssertTrue(document.hasDiscardableEditableContent)
    }

    func testAdditionalPatternAndOrderCreateDiscardableContent() {
        let base = BlankTrackerDocument.makeDefault()
        let additionalPattern = BlankTrackerDocument.makeEmptyPattern(index: 1)
        let document = copy(
            base,
            songLength: 2,
            orderTable: [0, 1],
            patterns: base.patterns + [additionalPattern]
        )

        XCTAssertTrue(document.hasDiscardableEditableContent)
    }

    func testGeneratedAndImportedSamplesCreateDiscardableContent() throws {
        var generated = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(generated.generateSineInSelectedEmptySample())

        var imported = BlankTrackerDocument.makeDefault()
        let candidate = try NormalizedSampleImport(
            decoded: DecodedSampleImport(
                sourceSampleRate: PlaybackSample.xmNeutralSampleRate,
                sourceChannelCount: 1,
                sourceBitDepthBits: 16,
                monoPCM: [-0.5, 0.5]
            ),
            sourceFilename: "public-test.wav"
        )
        let destination = try XCTUnwrap(imported.selectedSampleImportDestination)
        XCTAssertTrue(imported.importAudioSample(candidate, destination: destination))

        XCTAssertTrue(generated.hasDiscardableEditableContent)
        XCTAssertTrue(imported.hasDiscardableEditableContent)
    }

    func testInstrumentAndSampleMetadataCreateDiscardableContent() {
        var renamedInstrument = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(renamedInstrument.renameInstrument(at: 0, name: "Lead"))

        var editedSample = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(editedSample.generateSineInSelectedEmptySample())
        XCTAssertTrue(editedSample.setSampleVolume(instrumentAt: 0, sampleAt: 0, volume: 32))

        XCTAssertTrue(renamedInstrument.hasDiscardableEditableContent)
        XCTAssertTrue(editedSample.hasDiscardableEditableContent)
    }

    func testExplicitKeymapCreatesDiscardableContent() {
        let base = BlankTrackerDocument.makeDefault()
        let instrument = PlaybackInstrument(
            index: 1,
            samples: [],
            noteSampleMap: Array(repeating: 0, count: 96)
        )
        let document = copy(base, instrumentPalette: [1: instrument])

        XCTAssertTrue(document.hasDiscardableEditableContent)
    }

    func testTitleTimingAndChannelChangesCreateDiscardableContent() {
        let base = BlankTrackerDocument.makeDefault()
        let changedDocuments = [
            copy(base, title: "Authored Song"),
            copy(base, restartPosition: 1),
            copy(base, tempo: 140),
            copy(base, speed: 4),
            copy(base, patterns: [BlankTrackerDocument.makeEmptyPattern(index: 0, channels: 4)]),
        ]

        XCTAssertTrue(changedDocuments.allSatisfy(\.hasDiscardableEditableContent))
    }

    func testExportDoesNotMakeAuthoredContentPristine() throws {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        let before = document

        _ = try EditableXMWriter().data(from: document)

        XCTAssertEqual(document, before)
        XCTAssertTrue(document.hasDiscardableEditableContent)
    }

    func testNonPristineEditableNewRequiresConfirmationWithoutReplacement() throws {
        let harness = makeEditedHarness()

        let request = try confirmationRequest(
            from: harness.coordinator.begin(.newDocument),
            expectedAction: .newDocument
        )

        XCTAssertTrue(harness.coordinator.isConfirmationActive)
        XCTAssertEqual(request.action, .newDocument)
        XCTAssertTrue(harness.performedActions.isEmpty)
    }

    func testCancelNewPreservesExactDocumentIdentityRevisionAndUndo() throws {
        let harness = makeEditedHarness()
        let before = harness.snapshot
        let request = try confirmationRequest(from: harness.coordinator.begin(.newDocument))

        XCTAssertTrue(harness.coordinator.cancel(operationToken: request.operationToken))

        XCTAssertEqual(harness.snapshot, before)
        XCTAssertTrue(harness.performedActions.isEmpty)
        XCTAssertFalse(harness.coordinator.isConfirmationActive)
    }

    func testConfirmNewCreatesCanonicalDocumentExactlyOnce() throws {
        let harness = makeEditedHarness()
        let oldIdentity = harness.documentIdentity
        let request = try confirmationRequest(from: harness.coordinator.begin(.newDocument))

        XCTAssertTrue(harness.coordinator.confirm(operationToken: request.operationToken))

        XCTAssertEqual(harness.editableDocument, .makeDefault())
        XCTAssertNotEqual(harness.documentIdentity, oldIdentity)
        XCTAssertEqual(harness.undoEntries, [])
        XCTAssertEqual(harness.performedActions, [.newDocument])
        XCTAssertFalse(harness.coordinator.confirm(operationToken: request.operationToken))
        XCTAssertEqual(harness.performedActions, [.newDocument])
    }

    func testPristineEditableNewProceedsWithoutConfirmation() {
        let harness = ReplacementHarness(editableDocument: .makeDefault())

        XCTAssertEqual(harness.coordinator.begin(.newDocument), .performedWithoutConfirmation)
        XCTAssertFalse(harness.coordinator.isConfirmationActive)
        XCTAssertEqual(harness.performedActions, [.newDocument])
    }

    func testLoadedReadOnlyNewProceedsWithoutDiscardConfirmation() {
        let harness = ReplacementHarness(loadedReadOnly: true)

        XCTAssertEqual(harness.coordinator.begin(.newDocument), .performedWithoutConfirmation)
        XCTAssertEqual(harness.editableDocument, .makeDefault())
        XCTAssertEqual(harness.performedActions, [.newDocument])
    }

    func testNonPristineEditableOpenRequiresConfirmationBeforePicker() throws {
        let harness = makeEditedHarness()

        _ = try confirmationRequest(
            from: harness.coordinator.begin(.openModule),
            expectedAction: .openModule
        )

        XCTAssertEqual(harness.pickerPresentationCount, 0)
        XCTAssertTrue(harness.performedActions.isEmpty)
    }

    func testCancelOpenConfirmationNeverPresentsPickerOrReplacesDocument() throws {
        let harness = makeEditedHarness()
        let before = harness.snapshot
        let request = try confirmationRequest(from: harness.coordinator.begin(.openModule))

        XCTAssertTrue(harness.coordinator.cancel(operationToken: request.operationToken))

        XCTAssertEqual(harness.pickerPresentationCount, 0)
        XCTAssertEqual(harness.snapshot, before)
        XCTAssertTrue(harness.performedActions.isEmpty)
    }

    func testConfirmOpenThenPickerCancelPreservesExactEditableState() throws {
        let harness = makeEditedHarness(openOutcome: .pickerCancelled)
        let before = harness.snapshot
        let request = try confirmationRequest(from: harness.coordinator.begin(.openModule))

        XCTAssertTrue(harness.coordinator.confirm(operationToken: request.operationToken))

        XCTAssertEqual(harness.pickerPresentationCount, 1)
        XCTAssertEqual(harness.loadAttemptCount, 0)
        XCTAssertEqual(harness.snapshot, before)
    }

    func testConfirmOpenThenFailedLoadPreservesExactEditableState() throws {
        let harness = makeEditedHarness(openOutcome: .loadFailed)
        let before = harness.snapshot
        let request = try confirmationRequest(from: harness.coordinator.begin(.openModule))

        XCTAssertTrue(harness.coordinator.confirm(operationToken: request.operationToken))

        XCTAssertEqual(harness.pickerPresentationCount, 1)
        XCTAssertEqual(harness.loadAttemptCount, 1)
        XCTAssertEqual(harness.snapshot, before)
    }

    func testConfirmOpenThenSuccessfulPublicFixtureLoadTransitionsReadOnly() throws {
        let harness = makeEditedHarness(openOutcome: .loadSucceeded)
        let request = try confirmationRequest(from: harness.coordinator.begin(.openModule))
        let fixtureURL = try publicXMFixtureURL("generated/basic-instrument-sample.xm")
        harness.openSuccessValidator = {
            try? ModuleMetadataLoader().load(fromPath: fixtureURL.path)
        }

        XCTAssertTrue(harness.coordinator.confirm(operationToken: request.operationToken))

        XCTAssertEqual(harness.pickerPresentationCount, 1)
        XCTAssertEqual(harness.loadAttemptCount, 1)
        XCTAssertNil(harness.editableDocument)
        XCTAssertNil(harness.documentIdentity)
        XCTAssertTrue(harness.isLoadedReadOnly)
        XCTAssertEqual(harness.loadedMetadata?.type, "XM")
        XCTAssertEqual(harness.undoEntries, [])
    }

    func testPristineEditableOpenProceedsWithoutConfirmation() {
        let harness = ReplacementHarness(
            editableDocument: .makeDefault(),
            openOutcome: .pickerCancelled
        )

        XCTAssertEqual(harness.coordinator.begin(.openModule), .performedWithoutConfirmation)
        XCTAssertEqual(harness.pickerPresentationCount, 1)
        XCTAssertFalse(harness.coordinator.isConfirmationActive)
    }

    func testLoadedReadOnlyOpenProceedsWithoutDiscardConfirmation() {
        let harness = ReplacementHarness(loadedReadOnly: true, openOutcome: .pickerCancelled)

        XCTAssertEqual(harness.coordinator.begin(.openModule), .performedWithoutConfirmation)
        XCTAssertEqual(harness.pickerPresentationCount, 1)
        XCTAssertFalse(harness.coordinator.isConfirmationActive)
    }

    func testRevisionOrSnapshotChangeBeforeConfirmationRejectsReplacement() throws {
        for mutate in [
            { (harness: ReplacementHarness) in harness.documentRevision &+= 1 },
            { (harness: ReplacementHarness) in
                var document = harness.editableDocument!
                _ = document.enterNote(trackerKey: "x", octave: 4, row: 1, channel: 0)
                harness.editableDocument = document
            },
        ] {
            let harness = makeEditedHarness()
            let request = try confirmationRequest(from: harness.coordinator.begin(.newDocument))
            mutate(harness)

            XCTAssertFalse(harness.coordinator.confirm(operationToken: request.operationToken))
            XCTAssertTrue(harness.performedActions.isEmpty)
        }
    }

    func testIdentityModeEligibilityOrPresentationChangeRejectsReplacement() throws {
        for mutate in [
            { (harness: ReplacementHarness) in harness.documentIdentity = UUID() },
            { (harness: ReplacementHarness) in
                harness.editableDocument = nil
                harness.isLoadedReadOnly = true
            },
            { (harness: ReplacementHarness) in harness.editableDocument = .makeDefault() },
            { (harness: ReplacementHarness) in harness.hasPresentationConflict = true },
        ] {
            let harness = makeEditedHarness()
            let request = try confirmationRequest(from: harness.coordinator.begin(.openModule))
            mutate(harness)

            XCTAssertFalse(harness.coordinator.confirm(operationToken: request.operationToken))
            XCTAssertEqual(harness.pickerPresentationCount, 0)
            XCTAssertTrue(harness.performedActions.isEmpty)
        }
    }

    func testConflictingPresentationAndActiveRequestBlockAnotherReplacement() throws {
        let conflicted = makeEditedHarness()
        conflicted.hasPresentationConflict = true
        XCTAssertEqual(conflicted.coordinator.begin(.newDocument), .rejected)

        let active = makeEditedHarness()
        _ = try confirmationRequest(from: active.coordinator.begin(.newDocument))
        XCTAssertEqual(active.coordinator.begin(.openModule), .rejected)
        XCTAssertEqual(active.pickerPresentationCount, 0)
    }

    func testNewAndOpenAlertsUseExactWarningCopyAndSafeButtons() {
        let newAlert = DocumentReplacementAlert.make(request: DocumentReplacementRequest(
            operationToken: UUID(), action: .newDocument
        ))
        XCTAssertEqual(newAlert.alertStyle, .warning)
        XCTAssertEqual(newAlert.messageText, "Start a New Song?")
        XCTAssertEqual(newAlert.buttons.map(\.title), ["New Song", "Cancel"])
        XCTAssertTrue(newAlert.informativeText.contains("patterns, instruments, samples, and undo history"))
        XCTAssertTrue(newAlert.informativeText.contains("Export XM first"))

        let openAlert = DocumentReplacementAlert.make(request: DocumentReplacementRequest(
            operationToken: UUID(), action: .openModule
        ))
        XCTAssertEqual(openAlert.alertStyle, .warning)
        XCTAssertEqual(openAlert.messageText, "Open Another Module?")
        XCTAssertEqual(openAlert.buttons.map(\.title), ["Open…", "Cancel"])
        XCTAssertEqual(newAlert.buttons[1].keyEquivalent, "\u{1b}")
        XCTAssertEqual(openAlert.buttons[1].keyEquivalent, "\u{1b}")
        XCTAssertTrue(DocumentReplacementAlert.isConfirmed(.alertFirstButtonReturn))
        XCTAssertFalse(DocumentReplacementAlert.isConfirmed(.alertSecondButtonReturn))
    }

    func testCmdNAndCmdOUseTheSameGuardedMenuActions() throws {
        let mainMenu = ApplicationMenuBuilder.build(target: NSObject()).mainMenu
        let fileMenu = try XCTUnwrap(mainMenu.items.first { $0.title == "File" }?.submenu)
        let newItem = try XCTUnwrap(fileMenu.item(withTitle: "New"))
        let openItem = try XCTUnwrap(fileMenu.item(withTitle: "Open..."))

        XCTAssertEqual(newItem.action, ApplicationMenuBuilder.Actions.newTrackerDocument)
        XCTAssertEqual(newItem.keyEquivalent, "n")
        XCTAssertEqual(newItem.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(openItem.action, ApplicationMenuBuilder.Actions.openModuleFile)
        XCTAssertEqual(openItem.keyEquivalent, "o")
        XCTAssertEqual(openItem.keyEquivalentModifierMask, [.command])
    }

    private func makeEditedHarness(
        openOutcome: ReplacementHarness.OpenOutcome = .pickerCancelled
    ) -> ReplacementHarness {
        var document = BlankTrackerDocument.makeDefault()
        XCTAssertTrue(document.enterNote(trackerKey: "z", octave: 4, row: 0, channel: 0))
        return ReplacementHarness(editableDocument: document, openOutcome: openOutcome)
    }

    private func confirmationRequest(
        from result: DocumentReplacementBeginResult,
        expectedAction: DocumentReplacementAction? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> DocumentReplacementRequest {
        guard case let .confirmationRequired(request) = result else {
            XCTFail("Expected discard confirmation, got \(result)", file: file, line: line)
            throw ConfirmationTestError.missingRequest
        }
        if let expectedAction {
            XCTAssertEqual(request.action, expectedAction, file: file, line: line)
        }
        return request
    }

    private func copy(
        _ document: BlankTrackerDocument,
        title: String? = nil,
        songLength: Int? = nil,
        currentPosition: Int? = nil,
        restartPosition: Int? = nil,
        currentPatternIndex: Int? = nil,
        tempo: Int? = nil,
        speed: Int? = nil,
        orderTable: [Int]? = nil,
        selection: TrackerEditorSelection? = nil,
        instrumentPalette: [Int: PlaybackInstrument]? = nil,
        patterns: [XMPatternData]? = nil
    ) -> BlankTrackerDocument {
        BlankTrackerDocument(
            title: title ?? document.title,
            songLength: songLength ?? document.songLength,
            currentPosition: currentPosition ?? document.currentPosition,
            restartPosition: restartPosition ?? document.restartPosition,
            currentPatternIndex: currentPatternIndex ?? document.currentPatternIndex,
            tempo: tempo ?? document.tempo,
            speed: speed ?? document.speed,
            orderTable: orderTable ?? document.orderTable,
            selection: selection ?? document.selection,
            instrumentPalette: instrumentPalette ?? document.instrumentPalette,
            patterns: patterns ?? document.patterns
        )
    }

    private func publicXMFixtureURL(_ relativePath: String) throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("tests/reference-xm").appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing public XM fixture \(relativePath)")
        }
        return url
    }
}

private enum ConfirmationTestError: Error {
    case missingRequest
}

@MainActor
private final class ReplacementHarness {
    enum OpenOutcome {
        case pickerCancelled
        case loadFailed
        case loadSucceeded
    }

    struct Snapshot: Equatable {
        let editableDocument: BlankTrackerDocument?
        let documentIdentity: UUID?
        let documentRevision: UInt64
        let isLoadedReadOnly: Bool
        let undoEntries: [String]
    }

    var editableDocument: BlankTrackerDocument?
    var documentIdentity: UUID?
    var documentRevision: UInt64 = 8
    var isLoadedReadOnly: Bool
    var hasPresentationConflict = false
    var undoEntries = ["Enter Note"]
    var openOutcome: OpenOutcome
    var openSuccessValidator: (() -> ParsedModuleMetadata?)?
    private(set) var loadedMetadata: ParsedModuleMetadata?
    private(set) var performedActions = [DocumentReplacementAction]()
    private(set) var pickerPresentationCount = 0
    private(set) var loadAttemptCount = 0
    private let replacementIdentity = UUID()

    lazy var coordinator = DocumentReplacementCoordinator(
        contextProvider: { [unowned self] in
            DocumentReplacementContext(
                source: source,
                hasConflictingDocumentPresentation: hasPresentationConflict
            )
        },
        replacementHandler: { [unowned self] action in perform(action) }
    )

    init(
        editableDocument: BlankTrackerDocument? = nil,
        loadedReadOnly: Bool = false,
        openOutcome: OpenOutcome = .pickerCancelled
    ) {
        self.editableDocument = editableDocument
        documentIdentity = editableDocument == nil ? nil : UUID()
        isLoadedReadOnly = loadedReadOnly
        self.openOutcome = openOutcome
    }

    var snapshot: Snapshot {
        Snapshot(
            editableDocument: editableDocument,
            documentIdentity: documentIdentity,
            documentRevision: documentRevision,
            isLoadedReadOnly: isLoadedReadOnly,
            undoEntries: undoEntries
        )
    }

    private var source: DocumentReplacementSource {
        if let editableDocument {
            return .editable(
                documentIdentity: documentIdentity,
                documentRevision: documentRevision,
                document: editableDocument
            )
        }
        return isLoadedReadOnly ? .loadedReadOnly : .none
    }

    private func perform(_ action: DocumentReplacementAction) {
        performedActions.append(action)
        switch action {
        case .newDocument:
            editableDocument = .makeDefault()
            documentIdentity = replacementIdentity
            documentRevision &+= 1
            isLoadedReadOnly = false
            loadedMetadata = nil
            undoEntries = []
        case .openModule:
            pickerPresentationCount += 1
            guard openOutcome != .pickerCancelled else { return }
            loadAttemptCount += 1
            guard openOutcome == .loadSucceeded,
                  let metadata = openSuccessValidator?() else { return }
            editableDocument = nil
            documentIdentity = nil
            documentRevision &+= 1
            isLoadedReadOnly = true
            loadedMetadata = metadata
            undoEntries = []
        }
    }
}
