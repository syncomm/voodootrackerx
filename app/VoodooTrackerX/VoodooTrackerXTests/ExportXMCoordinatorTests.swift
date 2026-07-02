import Foundation
import XCTest

@MainActor
final class ExportXMCoordinatorTests: XCTestCase {
    func testEditableStoppedDocumentRequestsDestinationAndReturnsPendingNotImplementedWithoutWritingFile() throws {
        let document = BlankTrackerDocument.makeDefault()
        let originalDocument = document
        let destination = try temporaryDestination(filename: "song.xm")
        let provider = FakeExportXMDestinationProvider(destination: destination)
        let coordinator = ExportXMCoordinator(destinationProvider: provider)
        let context = ExportXMDocumentContext.editable(
            displayName: document.title,
            isPlaybackActive: false
        )

        XCTAssertTrue(ExportXMCoordinator.canExport(context: context))
        let result = coordinator.beginExport(context: context)

        XCTAssertEqual(provider.requests, [
            ExportXMDestinationRequest(suggestedFilename: "Untitled.xm")
        ])
        XCTAssertEqual(result, .pendingNotImplemented(destination: destination))
        XCTAssertEqual(result.userFacingMessage, ExportXMCoordinator.notImplementedMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(document, originalDocument)
    }

    func testCancelingDestinationSelectionWritesNothingAndLeavesDocumentUnchanged() throws {
        let document = BlankTrackerDocument.makeDefault()
        let originalDocument = document
        let destination = try temporaryDestination(filename: "cancelled.xm")
        let provider = FakeExportXMDestinationProvider(destination: nil)
        let coordinator = ExportXMCoordinator(destinationProvider: provider)

        let result = coordinator.beginExport(context: .editable(
            displayName: document.title,
            isPlaybackActive: false
        ))

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(provider.requests, [
            ExportXMDestinationRequest(suggestedFilename: "Untitled.xm")
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(document, originalDocument)
    }

    func testLoadedReadOnlyModuleIsDisabledAndDoesNotRequestDestination() {
        let provider = FakeExportXMDestinationProvider(destination: URL(fileURLWithPath: "/tmp/should-not-be-requested.xm"))
        let coordinator = ExportXMCoordinator(destinationProvider: provider)
        let context = ExportXMDocumentContext.loadedReadOnly(isPlaybackActive: false)

        XCTAssertFalse(ExportXMCoordinator.canExport(context: context))
        XCTAssertEqual(coordinator.beginExport(context: context), .unavailable(.loadedModuleReadOnly))
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testActivePlaybackIsDisabledAndDoesNotRequestDestination() {
        let document = BlankTrackerDocument.makeDefault()
        let provider = FakeExportXMDestinationProvider(destination: URL(fileURLWithPath: "/tmp/should-not-be-requested.xm"))
        let coordinator = ExportXMCoordinator(destinationProvider: provider)
        let context = ExportXMDocumentContext.editable(
            displayName: document.title,
            isPlaybackActive: true
        )

        XCTAssertFalse(ExportXMCoordinator.canExport(context: context))
        XCTAssertEqual(coordinator.beginExport(context: context), .unavailable(.playbackActive))
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testNoDocumentAndInvalidEditableStateAreDisabledWithoutDestinationRequest() {
        let provider = FakeExportXMDestinationProvider(destination: URL(fileURLWithPath: "/tmp/should-not-be-requested.xm"))
        let coordinator = ExportXMCoordinator(destinationProvider: provider)
        let missingDocument = ExportXMDocumentContext.none(isPlaybackActive: false)
        let invalidEditable = ExportXMDocumentContext.editable(
            displayName: "Untitled",
            isPlaybackActive: false,
            hasValidEditableState: false
        )

        XCTAssertFalse(ExportXMCoordinator.canExport(context: missingDocument))
        XCTAssertEqual(coordinator.beginExport(context: missingDocument), .unavailable(.noDocument))
        XCTAssertFalse(ExportXMCoordinator.canExport(context: invalidEditable))
        XCTAssertEqual(coordinator.beginExport(context: invalidEditable), .unavailable(.invalidEditableDocumentState))
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testDefaultFilenameUsesXMExtensionAndSanitizesDocumentDisplayName() {
        XCTAssertEqual(ExportXMCoordinator.defaultFilename(displayName: nil), "Untitled.xm")
        XCTAssertEqual(ExportXMCoordinator.defaultFilename(displayName: "  Demo Song  "), "Demo Song.xm")
        XCTAssertEqual(ExportXMCoordinator.defaultFilename(displayName: "already.xm"), "already.xm")
        XCTAssertEqual(ExportXMCoordinator.defaultFilename(displayName: "bad/name:demo"), "bad-name-demo.xm")
    }

    private func temporaryDestination(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent(filename)
    }
}

@MainActor
private final class FakeExportXMDestinationProvider: ExportXMDestinationProviding {
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
