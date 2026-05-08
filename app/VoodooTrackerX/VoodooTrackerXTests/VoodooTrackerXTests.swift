import AppKit
import XCTest

private enum TestPatternNavigationCommand {
    case up
    case down
    case pageUp
    case pageDown
    case home
    case end
    case left
    case right
}

private enum TestPatternCursorField: Int {
    case note
    case instrument
    case volume
    case effectType
    case effectParam
}

private struct TestPatternCursor: Equatable {
    var row: Int
    var channel: Int
    var field: TestPatternCursorField

    mutating func move(_ command: TestPatternNavigationCommand, rowCount: Int, channelCount: Int, pageStep: Int = 16) {
        row = min(max(0, row), max(0, rowCount - 1))
        channel = min(max(0, channel), max(0, channelCount - 1))

        switch command {
        case .up:
            row = rowCount > 0 ? (row == 0 ? rowCount - 1 : row - 1) : 0
        case .down:
            row = rowCount > 0 ? (row == rowCount - 1 ? 0 : row + 1) : 0
        case .pageUp:
            row = max(0, row - pageStep)
        case .pageDown:
            row = min(max(0, rowCount - 1), row + pageStep)
        case .home:
            row = 0
        case .end:
            row = max(0, rowCount - 1)
        case .left:
            if let previousField = TestPatternCursorField(rawValue: field.rawValue - 1) {
                field = previousField
            } else if channel > 0 {
                channel -= 1
                field = .effectParam
            }
        case .right:
            if let nextField = TestPatternCursorField(rawValue: field.rawValue + 1) {
                field = nextField
            } else if channel < channelCount - 1 {
                channel += 1
                field = .note
            }
        }
    }
}

private enum TestPatternEditInput {
    case clearField
    case hexDigit(UInt8)
}

private struct TestXMPatternEventCell: Equatable {
    let note: UInt8
    let instrument: UInt8
    let volumeColumn: UInt8
    let effectType: UInt8
    let effectParam: UInt8
}

private enum TestPatternEditEngine {
    static func hexNibble(from character: Character) -> UInt8? {
        guard let scalar = String(character).unicodeScalars.first else {
            return nil
        }
        switch scalar.value {
        case 48...57:
            return UInt8(scalar.value - 48)
        case 65...70:
            return UInt8(scalar.value - 55)
        case 97...102:
            return UInt8(scalar.value - 87)
        default:
            return nil
        }
    }

    static func apply(
        input: TestPatternEditInput,
        to cell: TestXMPatternEventCell,
        field: TestPatternCursorField,
        editModeEnabled: Bool
    ) -> TestXMPatternEventCell? {
        guard editModeEnabled else {
            return nil
        }
        switch input {
        case .clearField:
            switch field {
            case .note:
                return TestXMPatternEventCell(note: 0, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
            case .instrument:
                return TestXMPatternEventCell(note: cell.note, instrument: 0, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
            case .volume:
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: 0, effectType: cell.effectType, effectParam: cell.effectParam)
            case .effectType:
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: 0, effectParam: cell.effectParam)
            case .effectParam:
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: 0)
            }
        case let .hexDigit(nibble):
            guard nibble <= 0x0F else {
                return nil
            }
            switch field {
            case .note:
                return nil
            case .instrument:
                let value = ((cell.instrument & 0x0F) << 4) | nibble
                return TestXMPatternEventCell(note: cell.note, instrument: value, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
            case .volume:
                let value = ((cell.volumeColumn & 0x0F) << 4) | nibble
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: value, effectType: cell.effectType, effectParam: cell.effectParam)
            case .effectType:
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: nibble, effectParam: cell.effectParam)
            case .effectParam:
                let value = ((cell.effectParam & 0x0F) << 4) | nibble
                return TestXMPatternEventCell(note: cell.note, instrument: cell.instrument, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: value)
            }
        }
    }
}

private struct TestPatternSelectionEntry: Equatable {
    let patternIndex: Int
    let isUsed: Bool
    let rowCount: Int
}

private func buildPatternSelection(
    orderTable: [Int],
    patternCount: Int,
    rowCounts: [Int],
    showAllPatterns: Bool
) -> (entries: [TestPatternSelectionEntry], invalidReferencedPatterns: [Int]) {
    let safePatternCount = max(0, patternCount)
    var usedUnique = [Int]()
    var usedSeen = Set<Int>()
    var invalidReferenced = [Int]()

    for patternIndex in orderTable {
        if patternIndex >= 0 && patternIndex < safePatternCount {
            if !usedSeen.contains(patternIndex) {
                usedSeen.insert(patternIndex)
                usedUnique.append(patternIndex)
            }
        } else {
            invalidReferenced.append(patternIndex)
        }
    }

    var entries = [TestPatternSelectionEntry]()
    if showAllPatterns {
        for patternIndex in 0..<safePatternCount {
            let rowCount = patternIndex < rowCounts.count ? max(1, rowCounts[patternIndex]) : 64
            entries.append(
                TestPatternSelectionEntry(
                    patternIndex: patternIndex,
                    isUsed: usedSeen.contains(patternIndex),
                    rowCount: rowCount
                )
            )
        }
    } else {
        for patternIndex in usedUnique.sorted() {
            let rowCount = patternIndex < rowCounts.count ? max(1, rowCounts[patternIndex]) : 64
            entries.append(
                TestPatternSelectionEntry(
                    patternIndex: patternIndex,
                    isUsed: true,
                    rowCount: rowCount
                )
            )
        }
        if entries.isEmpty && safePatternCount > 0 {
            let rowCount = rowCounts.isEmpty ? 64 : max(1, rowCounts[0])
            entries.append(TestPatternSelectionEntry(patternIndex: 0, isUsed: false, rowCount: rowCount))
        }
    }
    return (entries, invalidReferenced)
}

private struct TestPatternViewportMetrics: Equatable {
    let rowHeight: CGFloat
    let viewportHeight: CGFloat

    var visibleRowCount: Int {
        guard rowHeight > 0 else { return 1 }
        let rows = max(1, Int(ceil(viewportHeight / rowHeight)) + 2)
        if rows % 2 == 0 {
            return rows + 1
        }
        return rows
    }

    var anchorRowIndex: Int {
        visibleRowCount / 2
    }

    func contentHeight(forRenderedRowCount renderedRowCount: Int, insetHeight: CGFloat) -> CGFloat {
        CGFloat(max(0, renderedRowCount)) * rowHeight + insetHeight * 2 + 2
    }
}

private struct TestPatternViewportState: Equatable {
    let currentRow: Int
    let anchorRowIndex: Int
    let visibleTopRow: Int
    let visibleBottomRow: Int
    let rowHeight: CGFloat
    let visibleRowCount: Int
    let rowCount: Int

    init(currentRow: Int, rowCount: Int, metrics: TestPatternViewportMetrics) {
        let safeRowCount = max(0, rowCount)
        let clampedRow = safeRowCount > 0 ? min(max(0, currentRow), safeRowCount - 1) : 0
        let visibleRowCount = max(1, metrics.visibleRowCount)
        let anchorRowIndex = min(metrics.anchorRowIndex, visibleRowCount - 1)
        let visibleTopRow = clampedRow - anchorRowIndex

        self.currentRow = clampedRow
        self.anchorRowIndex = anchorRowIndex
        self.visibleTopRow = visibleTopRow
        self.visibleBottomRow = visibleTopRow + visibleRowCount - 1
        self.rowHeight = metrics.rowHeight
        self.visibleRowCount = visibleRowCount
        self.rowCount = safeRowCount
    }

    func rowIndex(forSlot slotIndex: Int) -> Int? {
        guard (0..<visibleRowCount).contains(slotIndex) else { return nil }
        let rowIndex = visibleTopRow + slotIndex
        guard (0..<rowCount).contains(rowIndex) else { return nil }
        return rowIndex
    }

    var slotRows: [Int?] {
        (0..<visibleRowCount).map(rowIndex(forSlot:))
    }
}

private struct TestPatternViewportTextLayout: Equatable {
    static let rowNumberPrefixLength = 4
    static let leadingChannelPaddingLength = 0

    let slotRows: [Int?]
    let renderedLines: [String]

    init(state: TestPatternViewportState) {
        slotRows = state.slotRows
        renderedLines = state.slotRows.map { row in
            let rowPrefix = String(repeating: " ", count: Self.rowNumberPrefixLength)
            let leadingChannelPadding = String(repeating: " ", count: Self.leadingChannelPaddingLength)
            return rowPrefix + leadingChannelPadding + "CELL"
        }
    }
}

private enum TestTrackerChromeGeometry {
    static let dividerClearance: CGFloat = 4
    static let rowNumberPadding: CGFloat = 2

    static func pinnedGutterRowMinY(bodyMinY: CGFloat, insetHeight: CGFloat, slotIndex: Int, rowHeight: CGFloat) -> CGFloat {
        bodyMinY + insetHeight + CGFloat(slotIndex) * rowHeight
    }

    static func bodyRowMinY(bodyMinY: CGFloat, insetHeight: CGFloat, slotIndex: Int, rowHeight: CGFloat) -> CGFloat {
        bodyMinY + insetHeight + CGFloat(slotIndex) * rowHeight
    }

    static func visibleGutterWidth(for dividerX: CGFloat, rowNumberWidth: CGFloat) -> CGFloat {
        let maxWidthBeforeDivider = max(0, floor(dividerX - dividerClearance))
        let preferredWidth = ceil(rowNumberWidth) + rowNumberPadding
        return min(maxWidthBeforeDivider, preferredWidth)
    }

    static func targetOriginXForCursorVisibility(
        visibleMinX: CGFloat,
        visibleMaxX: CGFloat,
        leftObstructionWidth: CGFloat,
        targetMinX: CGFloat,
        targetMaxX: CGFloat,
        maxOriginX: CGFloat
    ) -> CGFloat {
        let effectiveVisibleMinX = visibleMinX + leftObstructionWidth
        if targetMinX < effectiveVisibleMinX {
            return max(0, targetMinX - leftObstructionWidth)
        }
        if targetMaxX > visibleMaxX {
            return min(maxOriginX, targetMaxX - (visibleMaxX - visibleMinX))
        }
        return visibleMinX
    }
}

private enum TestTrackerViewportScrollGeometry {
    static func clampedHorizontalOrigin(preferredOriginX: CGFloat, contentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        let maxOriginX = max(0, contentWidth - viewportWidth)
        return min(max(0, preferredOriginX), maxOriginX)
    }
}

private enum TestTrackerViewportResizeBehavior {
    static func shouldCaptureStableHorizontalOrigin(isLiveResize: Bool) -> Bool {
        !isLiveResize
    }

    static func shouldRevealCursorHorizontally(isViewportResizeRerender: Bool) -> Bool {
        !isViewportResizeRerender
    }
}

private enum TestPatternCursorOutlineGeometry {
    static func strokeRect(for fieldRect: CGRect) -> CGRect {
        fieldRect.insetBy(dx: -2, dy: -2)
    }

    static func minimumVisibleBounds(for bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: 2, dy: 2)
    }
}

private func displayedPatternIndex(orderTable: [Int], songLength: Int, songPosition: Int) -> Int? {
    let safeSongLength = min(songLength, orderTable.count)
    guard safeSongLength > 0 else {
        return nil
    }
    let clampedPosition = min(max(0, songPosition), safeSongLength - 1)
    return orderTable[clampedPosition]
}

private func formattedPatternSelectorTitle(patternIndex: Int, rowCount: Int) -> String {
    String(format: "P%02X", patternIndex)
}

private func makePlaybackSong(
    orderPatternIndices: [Int],
    patternRowCounts: [Int: Int],
    instrumentsByIndex: [Int: PlaybackInstrument] = [:],
    note: UInt8 = 0,
    instrument: UInt8 = 0,
    effectType: UInt8 = 0,
    effectParam: UInt8 = 0,
    endBehavior: PlaybackEndBehavior = .stopAtEnd
) -> PlaybackSong {
    let patterns = patternRowCounts.reduce(into: [Int: PlaybackPattern]()) { partialResult, entry in
        let rows = (0..<entry.value).map { rowIndex in
            PlaybackRow(
                index: rowIndex,
                cells: [PlaybackCell(note: note, instrument: instrument, volumeColumn: 0, effectType: effectType, effectParam: effectParam)]
            )
        }
        partialResult[entry.key] = PlaybackPattern(index: entry.key, rows: rows)
    }
    return PlaybackSong(
        title: "test",
        orders: orderPatternIndices.enumerated().map { PlaybackOrderEntry(orderIndex: $0.offset, patternIndex: $0.element) },
        patternsByIndex: patterns,
        instrumentsByIndex: instrumentsByIndex,
        restartOrderIndex: 0,
        endBehavior: endBehavior
    )
}

private func makePlaybackSong(
    orderPatternIndices: [Int],
    patternRowsByIndex: [Int: [PlaybackRow]],
    instrumentsByIndex: [Int: PlaybackInstrument] = [:],
    endBehavior: PlaybackEndBehavior = .stopAtEnd
) -> PlaybackSong {
    let patterns = patternRowsByIndex.reduce(into: [Int: PlaybackPattern]()) { partialResult, entry in
        partialResult[entry.key] = PlaybackPattern(index: entry.key, rows: entry.value)
    }
    return PlaybackSong(
        title: "test",
        orders: orderPatternIndices.enumerated().map { PlaybackOrderEntry(orderIndex: $0.offset, patternIndex: $0.element) },
        patternsByIndex: patterns,
        instrumentsByIndex: instrumentsByIndex,
        restartOrderIndex: 0,
        endBehavior: endBehavior
    )
}

private func makePlaybackRow(
    index: Int,
    note: UInt8 = 0,
    instrument: UInt8 = 0,
    effectType: UInt8 = 0,
    effectParam: UInt8 = 0
) -> PlaybackRow {
    PlaybackRow(
        index: index,
        cells: [PlaybackCell(note: note, instrument: instrument, volumeColumn: 0, effectType: effectType, effectParam: effectParam)]
    )
}

private enum TestPlaybackMode: Equatable {
    case stopped
    case playing
    case paused
}

private struct TestPlaybackStartContext: Equatable {
    let moduleTitle: String?
    let songPosition: Int
    let patternIndex: Int
    let row: Int
}

private struct TestPlaybackState: Equatable {
    var mode: TestPlaybackMode
    var context: TestPlaybackStartContext?

    static let stopped = TestPlaybackState(mode: .stopped, context: nil)
}

private final class TestPlaybackEngine {
    private(set) var state: TestPlaybackState = .stopped

    func play(from context: TestPlaybackStartContext?) {
        state = TestPlaybackState(mode: .playing, context: context)
    }

    func stop() {
        state = .stopped
    }

    func pause() {
        guard state.mode == .playing else {
            return
        }
        state = TestPlaybackState(mode: .paused, context: state.context)
    }
}

@MainActor
private final class TestPlaybackAudioOutput: PlaybackAudioOutput {
    private(set) var triggeredRequests = [AudioVoiceRequest]()
    private(set) var updatedControls = [(channel: Int, controls: AudioChannelControls)]()
    private(set) var stoppedChannels = [Int]()
    private(set) var stopAllCount = 0
    private(set) var resetCount = 0

    func trigger(_ request: AudioVoiceRequest) {
        triggeredRequests.append(request)
    }

    func update(channel: Int, controls: AudioChannelControls) {
        updatedControls.append((channel: channel, controls: controls))
    }

    func stop(channel: Int) {
        stoppedChannels.append(channel)
    }

    func stopAll() {
        stopAllCount += 1
    }

    func reset() {
        resetCount += 1
    }
}

final class VoodooTrackerXTests: XCTestCase {
    func testPlaybackEngineStartsPlayingFromContext() {
        let engine = TestPlaybackEngine()
        let context = TestPlaybackStartContext(moduleTitle: "example", songPosition: 3, patternIndex: 2, row: 16)

        engine.play(from: context)

        XCTAssertEqual(engine.state, TestPlaybackState(mode: .playing, context: context))
    }

    func testPlaybackEngineStopsAndClearsContext() {
        let engine = TestPlaybackEngine()
        engine.play(from: TestPlaybackStartContext(moduleTitle: "example", songPosition: 3, patternIndex: 2, row: 16))

        engine.stop()

        XCTAssertEqual(engine.state, .stopped)
    }

    func testPlaybackEnginePausePreservesContext() {
        let engine = TestPlaybackEngine()
        let context = TestPlaybackStartContext(moduleTitle: "example", songPosition: 3, patternIndex: 2, row: 16)
        engine.play(from: context)

        engine.pause()

        XCTAssertEqual(engine.state, TestPlaybackState(mode: .paused, context: context))
    }

    @MainActor
    func testPlaybackEngineIgnoresPlayWhileAlreadyPlaying() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 4],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            note: 49,
            instrument: 1
        ))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        let firstContext = PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0)
        let secondContext = PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 2)
        engine.play(from: firstContext)
        engine.play(from: secondContext)

        XCTAssertEqual(engine.state, PlaybackState(mode: .playing, context: firstContext))
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(positions, [PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0)])
        XCTAssertEqual(audioOutput.triggeredRequests.count, 1)
    }

    @MainActor
    func testPlaybackEngineStopIsIdempotentAfterPlayback() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        engine.load(song: makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 4]))
        var stopNotificationCount = 0
        engine.playbackDidStop = { stopNotificationCount += 1 }

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.stop()
        engine.stop()

        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))
        XCTAssertEqual(stopNotificationCount, 1)
        XCTAssertEqual(audioOutput.stopAllCount, 1)
    }

    @MainActor
    func testPlaybackEngineLoadWhilePlayingStopsAndReplacesSong() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let firstSong = makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 4])
        let secondSong = makePlaybackSong(orderPatternIndices: [7], patternRowCounts: [7: 8])
        var stopNotificationCount = 0
        engine.playbackDidStop = { stopNotificationCount += 1 }

        engine.load(song: firstSong)
        engine.play(from: PlaybackStartContext(moduleTitle: "first", songPosition: 0, patternIndex: 2, row: 0))
        engine.load(song: secondSong)

        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 7, rowIndex: 0))
        XCTAssertEqual(stopNotificationCount, 0)
        XCTAssertEqual(audioOutput.resetCount, 2)
    }

    @MainActor
    func testPlaybackEngineToggleStartsThroughPlaybackPath() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        engine.load(song: makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 4]))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.togglePlayPause(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 1))

        XCTAssertEqual(engine.state, PlaybackState(mode: .playing, context: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 1)))
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(positions, [PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)])
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
        XCTAssertNil(PlaybackEffectHandler.extendedTimingEffect(effectParam: 0xA1))
    }

    func testPlaybackChannelStateTreatsZeroedSupportedEffectsWithoutMemoryAsNoOps() {
        var state = PlaybackChannelState()

        XCTAssertTrue(state.apply(effectType: 0x03, effectParam: 0x00))
        XCTAssertTrue(state.apply(effectType: 0x04, effectParam: 0x00))
        XCTAssertTrue(state.apply(effectType: 0x05, effectParam: 0x00))
        XCTAssertTrue(state.apply(effectType: 0x06, effectParam: 0x00))
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

    @MainActor
    func testPlaybackEngineAppliesFxxTimingOnRowEntry() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowCounts: [2: 2],
            effectType: 0x0F,
            effectParam: 0x03
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(engine.timing, PlaybackTiming(speed: 3, bpm: 125))
    }

    @MainActor
    func testPlaybackEngineAppliesBxxPositionJumpOnNextRowAdvance() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 3, 4],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0B, effectParam: 0x02)],
                3: [makePlaybackRow(index: 0)],
                4: [makePlaybackRow(index: 0)]
            ]
        ))
        engine.configureTiming(PlaybackTiming(speed: 1, bpm: 125))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 2, patternIndex: 4, rowIndex: 0))
        XCTAssertEqual(positions, [
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0),
            PlaybackPosition(orderIndex: 2, patternIndex: 4, rowIndex: 0)
        ])
    }

    @MainActor
    func testPlaybackEngineIgnoresOutOfBoundsBxxPositionJump() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0B, effectParam: 0x7F)],
                3: [makePlaybackRow(index: 0)]
            ]
        ))
        engine.configureTiming(PlaybackTiming(speed: 1, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 0))
    }

    @MainActor
    func testPlaybackEngineAppliesDxxPatternBreakOnNextRowAdvance() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 3],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, effectType: 0x0D, effectParam: 0x02)],
                3: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1),
                    makePlaybackRow(index: 2),
                    makePlaybackRow(index: 3)
                ]
            ]
        ))
        engine.configureTiming(PlaybackTiming(speed: 1, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 3, rowIndex: 2))
    }

    @MainActor
    func testPlaybackEngineAppliesCxxVolumeToTriggeredVoice() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0C, effectParam: 0x20)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.volumeScale, 0.5)
    }

    @MainActor
    func testPlaybackEngineAppliesArpeggioAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x00, effectParam: 0x37),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 4, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.updatedControls.suffix(3).map { $0.controls.pitchOffsetSemitones }, [3, 7, 0])
    }

    @MainActor
    func testPlaybackEngineAppliesVolumeAndPitchSlidesAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0C, effectParam: 0x20),
                    makePlaybackRow(index: 1, effectType: 0x0A, effectParam: 0x20),
                    makePlaybackRow(index: 2, effectType: 0x01, effectParam: 0x08),
                    makePlaybackRow(index: 3)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.volumeScale - 0.53125) < 0.0001 })
        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.pitchOffsetSemitones - 0.125) < 0.0001 })
    }

    @MainActor
    func testPlaybackEngineAppliesTonePortamentoWithoutRetriggeringSample() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 53, instrument: 1, effectType: 0x03, effectParam: 0x10),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.triggeredRequests.count, 1)
        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.pitchOffsetSemitones - 0.25) < 0.0001 })
    }

    @MainActor
    func testPlaybackEngineAppliesVibratoAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x04, effectParam: 0x48),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 3, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()

        let vibratoOffsets = audioOutput.updatedControls.map { $0.controls.pitchOffsetSemitones }.filter { abs($0) > 0.0001 }
        XCTAssertFalse(vibratoOffsets.isEmpty)
    }

    @MainActor
    func testPlaybackEngineAppliesSampleOffsetToTriggeredVoice() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.25, count: 1024), volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x02)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.sampleStartOffset, 512)
    }

    @MainActor
    func testPlaybackEngineRetriggersCurrentVoiceOnConfiguredTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x92),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 4, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.triggeredRequests.map(\.note), [49, 49])
    }

    @MainActor
    func testPlaybackEngineCutsNoteOnConfiguredTick() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC2),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 4, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.triggeredRequests.count, 1)
        XCTAssertEqual(audioOutput.stoppedChannels, [0])
    }

    @MainActor
    func testPlaybackEngineDelaysNoteUntilConfiguredTick() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD2),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 4, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)

        engine.advanceOneTick()
        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)

        engine.advanceOneTick()
        XCTAssertEqual(audioOutput.triggeredRequests.map(\.note), [49])
    }

    @MainActor
    func testPlaybackEngineSkipsNoteDelayBeyondCurrentRowSpeed() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD3),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(audioOutput.triggeredRequests.isEmpty)
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

    func testPlaybackTickStateAdvancesRowsAfterConfiguredSpeed() {
        let timing = PlaybackTiming(speed: 3, bpm: 125)
        var tickState = PlaybackTickState()

        XCTAssertFalse(tickState.advance(timing: timing))
        XCTAssertFalse(tickState.advance(timing: timing))
        XCTAssertTrue(tickState.advance(timing: timing))
        XCTAssertEqual(tickState, PlaybackTickState(tickInRow: 0))
    }

    func testUsedPatternsSelectionDeduplicatesByOrderAndTracksInvalidReferences() {
        let result = buildPatternSelection(
            orderTable: [0, 2, 2, 5, 1, 0],
            patternCount: 4,
            rowCounts: [64, 32, 48, 16],
            showAllPatterns: false
        )

        XCTAssertEqual(result.entries.map(\.patternIndex), [0, 1, 2])
        XCTAssertEqual(result.entries.map(\.isUsed), [true, true, true])
        XCTAssertEqual(result.invalidReferencedPatterns, [5])
    }

    func testShowAllPatternsIncludesUnusedPatterns() {
        let result = buildPatternSelection(
            orderTable: [2, 2, 0],
            patternCount: 4,
            rowCounts: [64, 32, 48, 16],
            showAllPatterns: true
        )

        XCTAssertEqual(result.entries.map(\.patternIndex), [0, 1, 2, 3])
        XCTAssertEqual(result.entries.map(\.isUsed), [true, false, true, false])
    }

    func testCursorVerticalNavigationWrapsAtPatternBounds() {
        var cursor = TestPatternCursor(row: 0, channel: 1, field: .note)
        cursor.move(.up, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor.row, 63)

        cursor.move(.down, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor.row, 0)
    }

    func testCursorHorizontalFieldWrappingAcrossChannelsAndBounds() {
        var cursor = TestPatternCursor(row: 10, channel: 0, field: .note)
        cursor.move(.left, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 0, field: .note))

        cursor = TestPatternCursor(row: 10, channel: 0, field: .effectParam)
        cursor.move(.right, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 1, field: .note))

        cursor = TestPatternCursor(row: 10, channel: 3, field: .note)
        cursor.move(.left, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 2, field: .effectParam))

        cursor = TestPatternCursor(row: 10, channel: 3, field: .effectParam)
        cursor.move(.right, rowCount: 64, channelCount: 4)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 3, field: .effectParam))
    }

    func testViewportDefinesStaticAnchorRowNearViewportMiddle() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 0, rowCount: 64, metrics: metrics)

        XCTAssertEqual(metrics.visibleRowCount, 19)
        XCTAssertEqual(state.anchorRowIndex, 9)
        XCTAssertEqual(state.slotRows[state.anchorRowIndex], 0)
    }

    func testViewportUsesOneSharedSlotListForGutterAndPatternBody() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 12, rowCount: 64, metrics: metrics)
        let layout = TestPatternViewportTextLayout(state: state)

        XCTAssertEqual(layout.slotRows, state.slotRows)
        XCTAssertEqual(layout.slotRows[state.anchorRowIndex], 12)
    }

    func testViewportLeavesBlankSlotsAboveRowZeroOnInitialLoad() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 0, rowCount: 64, metrics: metrics)

        XCTAssertEqual(Array(state.slotRows.prefix(state.anchorRowIndex)), Array(repeating: nil, count: state.anchorRowIndex))
        XCTAssertEqual(state.slotRows[state.anchorRowIndex], 0)
    }

    func testViewportContentHeightUsesVisibleSlotCount() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 0, rowCount: 64, metrics: metrics)

        XCTAssertEqual(state.visibleRowCount, 19)
        XCTAssertEqual(metrics.contentHeight(forRenderedRowCount: state.visibleRowCount, insetHeight: 2), 329)
    }

    func testDownFromLastRowWrapsRowZeroIntoAnchorSlot() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        var cursor = TestPatternCursor(row: 63, channel: 0, field: .note)

        cursor.move(.down, rowCount: 64, channelCount: 4)
        let state = TestPatternViewportState(currentRow: cursor.row, rowCount: 64, metrics: metrics)

        XCTAssertEqual(cursor.row, 0)
        XCTAssertEqual(state.slotRows[state.anchorRowIndex], 0)
        XCTAssertEqual(Array(state.slotRows.prefix(state.anchorRowIndex)), Array(repeating: nil, count: state.anchorRowIndex))
    }

    func testUpFromRowZeroWrapsLastRowIntoAnchorSlot() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        var cursor = TestPatternCursor(row: 0, channel: 0, field: .note)

        cursor.move(.up, rowCount: 64, channelCount: 4)
        let state = TestPatternViewportState(currentRow: cursor.row, rowCount: 64, metrics: metrics)

        XCTAssertEqual(cursor.row, 63)
        XCTAssertEqual(state.slotRows[state.anchorRowIndex], 63)
        XCTAssertEqual(Array(state.slotRows.suffix(state.visibleRowCount - state.anchorRowIndex - 1)), Array(repeating: nil, count: state.visibleRowCount - state.anchorRowIndex - 1))
    }

    func testBlankSlotsRemainBlankInBothGutterAndBodyAtPatternBottom() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 63, rowCount: 64, metrics: metrics)
        let layout = TestPatternViewportTextLayout(state: state)

        let blankTailCount = state.visibleRowCount - state.anchorRowIndex - 1
        XCTAssertEqual(Array(layout.slotRows.suffix(blankTailCount)), Array(repeating: nil, count: blankTailCount))
    }

    func testRenderedTextReservesBlankRowPrefixForPinnedGutter() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 0, rowCount: 64, metrics: metrics)
        let layout = TestPatternViewportTextLayout(state: state)

        XCTAssertEqual(layout.renderedLines[state.anchorRowIndex], "    CELL")
        XCTAssertEqual(layout.renderedLines[state.anchorRowIndex - 1], "    CELL")
    }

    func testPinnedGutterUsesSameSlotYAsBodyRows() {
        let metrics = TestPatternViewportMetrics(rowHeight: 17, viewportHeight: 280)
        let state = TestPatternViewportState(currentRow: 12, rowCount: 64, metrics: metrics)
        let anchorSlot = state.anchorRowIndex

        let gutterY = TestTrackerChromeGeometry.pinnedGutterRowMinY(bodyMinY: 0, insetHeight: 2, slotIndex: anchorSlot, rowHeight: state.rowHeight)
        let bodyY = TestTrackerChromeGeometry.bodyRowMinY(bodyMinY: 0, insetHeight: 2, slotIndex: anchorSlot, rowHeight: state.rowHeight)

        XCTAssertEqual(state.slotRows[anchorSlot], 12)
        XCTAssertEqual(gutterY, bodyY)
    }

    func testPinnedGutterLeavesClearanceBeforeGridBoundary() {
        XCTAssertEqual(TestTrackerChromeGeometry.visibleGutterWidth(for: 36, rowNumberWidth: 16), 18)
        XCTAssertEqual(TestTrackerChromeGeometry.visibleGutterWidth(for: 4, rowNumberWidth: 16), 0)
    }

    func testPinnedGutterPrefersTwoDigitColumnWidthOverHiddenRowPrefixWidth() {
        XCTAssertEqual(TestTrackerChromeGeometry.visibleGutterWidth(for: 80, rowNumberWidth: 16), 18)
        XCTAssertEqual(TestTrackerChromeGeometry.visibleGutterWidth(for: 12, rowNumberWidth: 16), 8)
    }

    func testHorizontalCursorVisibilityAccountsForPinnedGutterObstruction() {
        let targetOriginX = TestTrackerChromeGeometry.targetOriginXForCursorVisibility(
            visibleMinX: 40,
            visibleMaxX: 240,
            leftObstructionWidth: 18,
            targetMinX: 50,
            targetMaxX: 70,
            maxOriginX: 400
        )

        XCTAssertEqual(targetOriginX, 32)
    }

    func testResizeKeepsLastStableHorizontalViewportOriginWhenPossible() {
        let originX = TestTrackerViewportScrollGeometry.clampedHorizontalOrigin(
            preferredOriginX: 120,
            contentWidth: 480,
            viewportWidth: 240
        )

        XCTAssertEqual(originX, 120)
    }

    func testResizeClampsLastStableHorizontalViewportOriginWhenViewportWidens() {
        let originX = TestTrackerViewportScrollGeometry.clampedHorizontalOrigin(
            preferredOriginX: 300,
            contentWidth: 480,
            viewportWidth: 320
        )

        XCTAssertEqual(originX, 160)
    }

    func testResizeDoesNotReplaceStableHorizontalOriginDuringLiveResize() {
        XCTAssertFalse(TestTrackerViewportResizeBehavior.shouldCaptureStableHorizontalOrigin(isLiveResize: true))
        XCTAssertTrue(TestTrackerViewportResizeBehavior.shouldCaptureStableHorizontalOrigin(isLiveResize: false))
    }

    func testResizeRerenderDoesNotRevealCursorHorizontally() {
        XCTAssertFalse(TestTrackerViewportResizeBehavior.shouldRevealCursorHorizontally(isViewportResizeRerender: true))
        XCTAssertTrue(TestTrackerViewportResizeBehavior.shouldRevealCursorHorizontally(isViewportResizeRerender: false))
    }

    func testFieldCursorSurvivesRowNavigation() {
        var cursor = TestPatternCursor(row: 10, channel: 2, field: .effectParam)

        cursor.move(.down, rowCount: 64, channelCount: 8)
        XCTAssertEqual(cursor, TestPatternCursor(row: 11, channel: 2, field: .effectParam))

        cursor.move(.up, rowCount: 64, channelCount: 8)
        XCTAssertEqual(cursor, TestPatternCursor(row: 10, channel: 2, field: .effectParam))
    }

    func testCursorOutlineGeometryExpandsFieldRectAndReservesVisibleBounds() {
        let fieldRect = CGRect(x: 100, y: 8, width: 18, height: 15)
        let strokeRect = TestPatternCursorOutlineGeometry.strokeRect(for: fieldRect)
        let clipRect = TestPatternCursorOutlineGeometry.minimumVisibleBounds(for: CGRect(x: 0, y: 0, width: 320, height: 200))

        XCTAssertEqual(strokeRect, CGRect(x: 98, y: 6, width: 22, height: 19))
        XCTAssertEqual(clipRect, CGRect(x: 2, y: 2, width: 316, height: 196))
        XCTAssertTrue(clipRect.contains(CGPoint(x: strokeRect.minX, y: strokeRect.minY)))
    }

    func testEditEngineClearFieldByCursorField() {
        let source = TestXMPatternEventCell(note: 24, instrument: 0x2A, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)

        XCTAssertEqual(
            TestPatternEditEngine.apply(input: .clearField, to: source, field: .note, editModeEnabled: true),
            TestXMPatternEventCell(note: 0, instrument: 0x2A, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)
        )
        XCTAssertEqual(
            TestPatternEditEngine.apply(input: .clearField, to: source, field: .instrument, editModeEnabled: true),
            TestXMPatternEventCell(note: 24, instrument: 0x00, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x9C)
        )
        XCTAssertEqual(
            TestPatternEditEngine.apply(input: .clearField, to: source, field: .effectParam, editModeEnabled: true),
            TestXMPatternEventCell(note: 24, instrument: 0x2A, volumeColumn: 0x40, effectType: 0x0E, effectParam: 0x00)
        )
    }

    func testEditEngineHexEntryRulesAndBounds() {
        var cell = TestXMPatternEventCell(note: 0, instrument: 0x00, volumeColumn: 0x00, effectType: 0x00, effectParam: 0x00)
        cell = TestPatternEditEngine.apply(input: .hexDigit(0x0A), to: cell, field: .instrument, editModeEnabled: true) ?? cell
        XCTAssertEqual(cell.instrument, 0x0A)
        cell = TestPatternEditEngine.apply(input: .hexDigit(0x0B), to: cell, field: .instrument, editModeEnabled: true) ?? cell
        XCTAssertEqual(cell.instrument, 0xAB)

        cell = TestPatternEditEngine.apply(input: .hexDigit(0x05), to: cell, field: .effectType, editModeEnabled: true) ?? cell
        XCTAssertEqual(cell.effectType, 0x05)

        cell = TestPatternEditEngine.apply(input: .hexDigit(0x0C), to: cell, field: .effectParam, editModeEnabled: true) ?? cell
        cell = TestPatternEditEngine.apply(input: .hexDigit(0x0D), to: cell, field: .effectParam, editModeEnabled: true) ?? cell
        XCTAssertEqual(cell.effectParam, 0xCD)

        XCTAssertNil(TestPatternEditEngine.apply(input: .hexDigit(0x0A), to: cell, field: .note, editModeEnabled: true))
        XCTAssertNil(TestPatternEditEngine.apply(input: .hexDigit(0x1F), to: cell, field: .effectParam, editModeEnabled: true))
        XCTAssertEqual(TestPatternEditEngine.hexNibble(from: "A"), 0x0A)
        XCTAssertEqual(TestPatternEditEngine.hexNibble(from: "f"), 0x0F)
        XCTAssertNil(TestPatternEditEngine.hexNibble(from: "G"))
    }

    func testEditEngineRespectsEditModeGating() {
        let source = TestXMPatternEventCell(note: 10, instrument: 0x12, volumeColumn: 0x34, effectType: 0x05, effectParam: 0x67)
        XCTAssertNil(TestPatternEditEngine.apply(input: .clearField, to: source, field: .instrument, editModeEnabled: false))
        XCTAssertNil(TestPatternEditEngine.apply(input: .hexDigit(0x0A), to: source, field: .effectParam, editModeEnabled: false))
    }

    func testSongPositionDrivesDisplayedPatternSelection() {
        XCTAssertEqual(displayedPatternIndex(orderTable: [3, 7, 3, 9], songLength: 4, songPosition: 0), 3)
        XCTAssertEqual(displayedPatternIndex(orderTable: [3, 7, 3, 9], songLength: 4, songPosition: 1), 7)
        XCTAssertEqual(displayedPatternIndex(orderTable: [3, 7, 3, 9], songLength: 4, songPosition: 3), 9)
    }

    func testSongPositionClampsToSongLengthBounds() {
        XCTAssertEqual(displayedPatternIndex(orderTable: [1, 4, 6], songLength: 3, songPosition: -1), 1)
        XCTAssertEqual(displayedPatternIndex(orderTable: [1, 4, 6], songLength: 3, songPosition: 99), 6)
    }

    func testPatternSelectorUsesHexPatternLabels() {
        XCTAssertEqual(formattedPatternSelectorTitle(patternIndex: 0x00, rowCount: 64), "P00")
        XCTAssertEqual(formattedPatternSelectorTitle(patternIndex: 0x0A, rowCount: 32), "P0A")
        XCTAssertEqual(formattedPatternSelectorTitle(patternIndex: 0x1F, rowCount: 16), "P1F")
    }
}
