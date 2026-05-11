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
    volumeColumn: UInt8 = 0,
    effectType: UInt8 = 0,
    effectParam: UInt8 = 0,
    endBehavior: PlaybackEndBehavior = .stopAtEnd,
    initialTiming: PlaybackTiming = .xmDefault,
    usesLinearFrequencyTable: Bool = true
) -> PlaybackSong {
    let patterns = patternRowCounts.reduce(into: [Int: PlaybackPattern]()) { partialResult, entry in
        let rows = (0..<entry.value).map { rowIndex in
            PlaybackRow(
                index: rowIndex,
                cells: [PlaybackCell(note: note, instrument: instrument, volumeColumn: volumeColumn, effectType: effectType, effectParam: effectParam)]
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
        endBehavior: endBehavior,
        initialTiming: initialTiming,
        usesLinearFrequencyTable: usesLinearFrequencyTable
    )
}

private func makePlaybackSong(
    orderPatternIndices: [Int],
    patternRowsByIndex: [Int: [PlaybackRow]],
    instrumentsByIndex: [Int: PlaybackInstrument] = [:],
    endBehavior: PlaybackEndBehavior = .stopAtEnd,
    initialTiming: PlaybackTiming = .xmDefault,
    usesLinearFrequencyTable: Bool = true
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
        endBehavior: endBehavior,
        initialTiming: initialTiming,
        usesLinearFrequencyTable: usesLinearFrequencyTable
    )
}

private func makePlaybackRow(
    index: Int,
    note: UInt8 = 0,
    instrument: UInt8 = 0,
    volumeColumn: UInt8 = 0,
    effectType: UInt8 = 0,
    effectParam: UInt8 = 0
) -> PlaybackRow {
    PlaybackRow(
        index: index,
        cells: [PlaybackCell(note: note, instrument: instrument, volumeColumn: volumeColumn, effectType: effectType, effectParam: effectParam)]
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
    let audioBufferSampleRate = 44_100.0
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

@MainActor
private final class TestPlaybackTraceWriter: PlaybackTraceWriting {
    private(set) var events = [PlaybackTraceEvent]()
    private(set) var flushCount = 0

    let isEnabled = true

    func record(_ event: PlaybackTraceEvent) {
        events.append(event)
    }

    func flush() {
        flushCount += 1
    }
}

final class VoodooTrackerXTests: XCTestCase {
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
        XCTAssertEqual(object["usesLinearFrequencyTable"] as? Bool, true)
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

    @MainActor
    func testPlaybackEngineRecordsTraceForTriggeredNote() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(
            instrumentIndex: 1,
            sampleIndex: 0,
            pcm: Array(repeating: 0.25, count: 1024),
            volume: 1,
            relativeNote: 0,
            finetune: 0,
            baseSampleRate: 8_363
        )
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x09, effectParam: 0x02)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        let timingEvent = traceWriter.events.first { $0.decision == .observed && $0.decisionReason == "row_timing_before_effects" }
        XCTAssertEqual(timingEvent?.speed, 6)
        XCTAssertEqual(timingEvent?.bpm, 125)
        XCTAssertEqual(timingEvent?.tickDuration ?? 0, 0.02, accuracy: 0.0001)
        XCTAssertEqual(timingEvent?.rowDuration ?? 0, 0.12, accuracy: 0.0001)

        let event = traceWriter.events.first { $0.decision == .triggered }
        XCTAssertEqual(event?.tickIndex, 0)
        XCTAssertEqual(event?.orderIndex, 0)
        XCTAssertEqual(event?.patternIndex, 2)
        XCTAssertEqual(event?.rowIndex, 0)
        XCTAssertEqual(event?.tickInRow, 0)
        XCTAssertEqual(event?.channelIndex, 0)
        XCTAssertEqual(event?.noteValue, 49)
        XCTAssertEqual(event?.instrumentIndex, 1)
        XCTAssertEqual(event?.sampleIndex, 0)
        XCTAssertEqual(event?.effectCommand, "09")
        XCTAssertEqual(event?.effectParameter, "02")
        XCTAssertEqual(event?.computedVolume, 1)
        XCTAssertEqual(event?.computedPanning ?? 0, PlaybackEffectHandler.audioPanning(forXMValue: 64), accuracy: 0.0001)
        XCTAssertEqual(event?.computedPitchSemitones, 0)
        XCTAssertEqual(event?.sourceSampleRate, 8_363)
        XCTAssertEqual(event?.audioBufferSampleRate, 44_100)
        XCTAssertEqual(event?.targetFrequency ?? 0, 8_363, accuracy: 0.0001)
        XCTAssertEqual(event?.computedRate ?? 0, 8_363.0 / 44_100.0, accuracy: 0.000001)
        XCTAssertEqual(event?.rateBasis, PlaybackPitchCalculator.audioBufferSampleRateBasis)
        XCTAssertEqual(event?.loopEnabled, false)
        XCTAssertEqual(event?.sampleOffset, 512)
        XCTAssertEqual(event?.envelopeEnabled, false)
        XCTAssertEqual(event?.envelopeTick, 0)
        XCTAssertEqual(event?.envelopeValue, 1)
        XCTAssertEqual(event?.fadeoutValue, 1)
        XCTAssertEqual(event?.finalAppliedVolume, 1)
        XCTAssertEqual(event?.decisionReason, "row_note")
        XCTAssertEqual(audioOutput.triggeredRequests.count, 1)
        XCTAssertEqual(audioOutput.triggeredRequests.first?.panning ?? 0, PlaybackEffectHandler.audioPanning(forXMValue: 64), accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackEngineRecordsTraceForDelayCutAndRetriggerDecisions() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD2),
                    makePlaybackRow(index: 1, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xC1),
                    makePlaybackRow(index: 2, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0x92)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))
        engine.configureTiming(PlaybackTiming(speed: 3, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(traceWriter.events.contains { $0.decision == .delayed && $0.decisionReason == "note_delay" })
        XCTAssertTrue(traceWriter.events.contains { $0.decision == .cut && $0.decisionReason == "note_cut" })
        XCTAssertTrue(traceWriter.events.contains { $0.decision == .retriggered && $0.decisionReason == "retrigger_interval" })
    }

    @MainActor
    func testPlaybackEngineAppliesVolumeColumnSetVolume() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x3D)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.volumeScale ?? 0, Float(45) / 64.0, accuracy: 0.0001)
        let event = traceWriter.events.first { $0.decision == .triggered }
        XCTAssertEqual(event?.rawVolumeColumn, "3D")
        XCTAssertEqual(event?.decodedVolumeColumnCommand, "setVolume")
        XCTAssertEqual(event?.volumeColumnApplied, true)
        XCTAssertEqual(event?.volumeColumnVolume, 45)
        XCTAssertEqual(event?.computedVolume ?? 0, Float(45) / 64.0, accuracy: 0.0001)
        XCTAssertEqual(event?.finalAppliedVolume ?? 0, Float(45) / 64.0, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackEngineMapsVolumeColumnPanning() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0xCC)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.panning ?? 0, PlaybackEffectHandler.audioPanning(forXMValue: 204), accuracy: 0.0001)
        let event = traceWriter.events.first { $0.decision == .triggered }
        XCTAssertEqual(event?.rawVolumeColumn, "CC")
        XCTAssertEqual(event?.decodedVolumeColumnCommand, "setPanning")
        XCTAssertEqual(event?.volumeColumnApplied, true)
        XCTAssertEqual(event?.volumeColumnPanning, 204)
        XCTAssertEqual(event?.computedPanning ?? 0, PlaybackEffectHandler.audioPanning(forXMValue: 204), accuracy: 0.0001)
    }

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
    func testPlaybackEngineUsesSongInitialTimingFromXMHeader() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        let song = makePlaybackSong(orderPatternIndices: [2], patternRowCounts: [2: 2], initialTiming: PlaybackTiming(speed: 2, bpm: 183))

        engine.load(song: song)

        XCTAssertEqual(engine.timing, PlaybackTiming(speed: 2, bpm: 183))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(engine.timing, PlaybackTiming(speed: 2, bpm: 183))
    }

    @MainActor
    func testPlaybackEngineDistinguishesFxxSpeedAndBPM() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                    makePlaybackRow(index: 1, effectType: 0x0F, effectParam: 0x7D),
                    makePlaybackRow(index: 2)
                ]
            ],
            initialTiming: PlaybackTiming(speed: 6, bpm: 183)
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        XCTAssertEqual(engine.timing, PlaybackTiming(speed: 3, bpm: 183))

        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
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
    func testPlaybackEngineApplies8xxPanningToTriggeredVoiceAndTrace() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x08, effectParam: 0xFF)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(audioOutput.triggeredRequests.first?.panning ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(traceWriter.events.first { $0.decision == .triggered }?.computedPanning ?? 0, 1.0, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackEngineUsesConservativeDefaultChannelPanning() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    PlaybackRow(
                        index: 0,
                        cells: [
                            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
                        ]
                    )
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        ))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))

        XCTAssertEqual(
            audioOutput.triggeredRequests.map(\.panning),
            [
                PlaybackEffectHandler.audioPanning(forXMValue: 64),
                PlaybackEffectHandler.audioPanning(forXMValue: 191),
                PlaybackEffectHandler.audioPanning(forXMValue: 191),
                PlaybackEffectHandler.audioPanning(forXMValue: 64)
            ]
        )
    }

    @MainActor
    func testPlaybackEngineAppliesGxxGlobalVolumeToTriggeredVoice() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x10, effectParam: 0x20)]
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
    func testPlaybackEngineAppliesPxyPanningSlideAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x08, effectParam: 0x80),
                    makePlaybackRow(index: 1, effectType: 0x19, effectParam: 0x20),
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

        XCTAssertTrue(audioOutput.updatedControls.contains {
            $0.channel == 0 && abs($0.controls.panning - PlaybackEffectHandler.audioPanning(forXMValue: 130)) < 0.0001
        })
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
    func testPlaybackEngineAppliesTremoloAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0C, effectParam: 0x20),
                    makePlaybackRow(index: 1, effectType: 0x07, effectParam: 0x48),
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

        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && $0.controls.volumeScale > 0.5 && $0.controls.volumeScale < 1.0 })
    }

    @MainActor
    func testPlaybackEngineAppliesHxyGlobalVolumeSlideAcrossTicks() {
        let audioOutput = TestPlaybackAudioOutput()
        let engine = PlaybackEngine(audioEngine: audioOutput)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x10, effectParam: 0x20),
                    makePlaybackRow(index: 1, effectType: 0x11, effectParam: 0x10),
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

        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.volumeScale - 0.515625) < 0.0001 })
    }

    @MainActor
    func testPlaybackEngineAppliesVolumeEnvelopeToActiveVoice() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let envelope = PlaybackVolumeEnvelope(
            enabled: true,
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 1, value: 32)
            ],
            sustainPointIndex: nil,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0x01,
            fadeout: 0
        )
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 0.5, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)]
        ))
        engine.configureTiming(PlaybackTiming(speed: 3, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()

        XCTAssertEqual(audioOutput.triggeredRequests.first?.volumeScale ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.volumeScale - 0.5) < 0.0001 })
        let updatedEvent = traceWriter.events.first { $0.decision == .updated && $0.envelopeTick == 1 }
        XCTAssertEqual(updatedEvent?.envelopeEnabled, true)
        XCTAssertEqual(updatedEvent?.envelopeValue ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(updatedEvent?.finalAppliedVolume ?? 0, 0.25, accuracy: 0.0001)
    }

    @MainActor
    func testPlaybackEngineAppliesFadeoutAfterKeyOff() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let envelope = PlaybackVolumeEnvelope(
            enabled: false,
            points: [],
            sustainPointIndex: nil,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0,
            fadeout: 32_768
        )
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 97),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        engine.advanceOneTick()
        engine.advanceOneTick()
        engine.advanceOneTick()

        XCTAssertTrue(traceWriter.events.contains { $0.decisionReason == "key_off" && $0.noteValue == 97 })
        XCTAssertTrue(audioOutput.updatedControls.contains { $0.channel == 0 && abs($0.controls.volumeScale - 0.5) < 0.0001 })
        XCTAssertTrue(traceWriter.events.contains { $0.fadeoutValue.map { abs($0 - 0.5) < 0.0001 } ?? false })
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

    @MainActor
    func testPlaybackEngineAppliesPatternDelayBeforeAdvancingRows() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0E, effectParam: 0xE2),
                    makePlaybackRow(index: 1)
                ]
            ]
        ))
        engine.configureTiming(PlaybackTiming(speed: 2, bpm: 125))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        engine.play(from: PlaybackStartContext(moduleTitle: "example", songPosition: 0, patternIndex: 2, row: 0))
        for _ in 0..<5 {
            engine.advanceOneTick()
        }
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0))

        engine.advanceOneTick()

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1))
        XCTAssertEqual(positions, [
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 0),
            PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1)
        ])
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

    func testPlaybackSampleLoopRegionDefersPingPongLoops() {
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

        XCTAssertEqual(sample.loopRegion, PlaybackSampleLoopRegion(isEnabled: false, startFrame: 100, endFrame: 400, lengthFrames: 300, loopType: 2, loopTypeName: "ping_pong_deferred"))
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
        XCTAssertTrue(plan.isLooped)
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
        XCTAssertTrue(plan.isLooped)
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
