import XCTest

@MainActor
final class AudioExportPresentationGateTests: XCTestCase {
    private enum AudioFormat: CaseIterable {
        case wav
        case m4a
    }

    private enum TerminalResult: CaseIterable {
        case success
        case failure
        case cancellation
    }

    private final class ProgressSheetMarker {
        let format: AudioFormat

        init(format: AudioFormat) {
            self.format = format
        }
    }

    func testEligibleWAVAndM4ACommandsRemainAvailableWithoutInFlightExport() {
        let context = eligibleContext()

        XCTAssertTrue(commandIsAvailable(.wav, context: context, isExportInFlight: false))
        XCTAssertTrue(commandIsAvailable(.m4a, context: context, isExportInFlight: false))
    }

    func testEveryCrossFormatCommandIsRejectedWhileExportIsInFlight() {
        let context = eligibleContext()

        for activeFormat in AudioFormat.allCases {
            let activeSheet = ProgressSheetMarker(format: activeFormat)
            for requestedFormat in AudioFormat.allCases {
                var baseAvailabilityChecks = 0
                let isAvailable = AudioExportPresentationGate.isCommandAvailable(
                    isExportInFlight: activeSheet.format == activeFormat
                ) {
                    baseAvailabilityChecks += 1
                    return self.baseAvailability(for: requestedFormat, context: context)
                }

                XCTAssertFalse(
                    isAvailable,
                    "\(activeFormat) active must reject \(requestedFormat)"
                )
                XCTAssertEqual(baseAvailabilityChecks, 0)
            }
        }
    }

    func testStaleDirectActionWhileActiveDoesNotOpenDestinationPicker() {
        var destinationPickerStartCount = 0

        let didStart = AudioExportPresentationGate.performIfAvailable(isExportInFlight: true) {
            destinationPickerStartCount += 1
            return true
        } ?? false

        XCTAssertFalse(didStart)
        XCTAssertEqual(destinationPickerStartCount, 0)
    }

    func testDirectActionWithoutActiveExportStartsExactlyOnce() {
        var startCount = 0

        let result = AudioExportPresentationGate.performIfAvailable(isExportInFlight: false) {
            startCount += 1
            return "started"
        }

        XCTAssertEqual(result, "started")
        XCTAssertEqual(startCount, 1)
    }

    func testPresentationRevalidationCreatesNoTokenAndDoesNotReplaceActiveSheet() {
        let firstSheet = ProgressSheetMarker(format: .wav)
        let secondSheet = ProgressSheetMarker(format: .m4a)
        var activeSheet: ProgressSheetMarker? = firstSheet
        var tokenCreationCount = 0

        let didInstall = AudioExportPresentationGate.performIfAvailable(
            isExportInFlight: activeSheet != nil
        ) {
            tokenCreationCount += 1
            activeSheet = secondSheet
            return true
        } ?? false

        XCTAssertFalse(didInstall)
        XCTAssertEqual(tokenCreationCount, 0)
        XCTAssertTrue(activeSheet === firstSheet)
    }

    func testEveryTerminalResultRestoresNormalAvailabilityAfterSheetCleanup() {
        let context = eligibleContext()

        for activeFormat in AudioFormat.allCases {
            for terminalResult in TerminalResult.allCases {
                let originalSheet = ProgressSheetMarker(format: activeFormat)
                var activeSheet: ProgressSheetMarker? = originalSheet
                var closeCount = 0
                XCTAssertFalse(commandIsAvailable(.wav, context: context, isExportInFlight: activeSheet != nil))
                XCTAssertFalse(commandIsAvailable(.m4a, context: context, isExportInFlight: activeSheet != nil))

                activeSheet = AudioExportPresentationGate.endPresentation(activeSheet) { sheet in
                    XCTAssertTrue(sheet === originalSheet)
                    closeCount += 1
                }
                activeSheet = AudioExportPresentationGate.endPresentation(activeSheet) { _ in
                    closeCount += 1
                }

                XCTAssertNil(activeSheet)
                XCTAssertEqual(closeCount, 1, "Sheet should close once after \(terminalResult)")
                XCTAssertTrue(
                    commandIsAvailable(.wav, context: context, isExportInFlight: activeSheet != nil),
                    "WAV should be restored after \(terminalResult)"
                )
                XCTAssertTrue(
                    commandIsAvailable(.m4a, context: context, isExportInFlight: activeSheet != nil),
                    "M4A should be restored after \(terminalResult)"
                )
            }
        }
    }

    func testPlaybackActiveRejectionRemainsUnchanged() {
        let document = BlankTrackerDocument.makeDefault()
        let context = WAVExportDocumentContext.editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: true
        )

        XCTAssertFalse(commandIsAvailable(.wav, context: context, isExportInFlight: false))
        XCTAssertFalse(commandIsAvailable(.m4a, context: context, isExportInFlight: false))
    }

    func testUnavailableDocumentRejectionsRemainUnchanged() {
        let noDocument = WAVExportDocumentContext.none(isPlaybackActive: false)
        let missingSong = WAVExportDocumentContext.loadedReadOnly(
            playbackSong: nil,
            displayName: "Missing",
            isPlaybackActive: false
        )

        for format in AudioFormat.allCases {
            XCTAssertFalse(commandIsAvailable(format, context: noDocument, isExportInFlight: false))
            XCTAssertFalse(commandIsAvailable(format, context: missingSong, isExportInFlight: false))
        }
    }

    private func eligibleContext() -> WAVExportDocumentContext {
        let document = BlankTrackerDocument.makeDefault()
        return .editable(
            document: document,
            displayName: document.title,
            isPlaybackActive: false
        )
    }

    private func commandIsAvailable(
        _ format: AudioFormat,
        context: WAVExportDocumentContext,
        isExportInFlight: Bool
    ) -> Bool {
        AudioExportPresentationGate.isCommandAvailable(isExportInFlight: isExportInFlight) {
            self.baseAvailability(for: format, context: context)
        }
    }

    private func baseAvailability(
        for format: AudioFormat,
        context: WAVExportDocumentContext
    ) -> Bool {
        switch format {
        case .wav:
            WAVExportCoordinator.canExport(context: context)
        case .m4a:
            M4AExportCoordinator.canExport(context: context)
        }
    }
}
