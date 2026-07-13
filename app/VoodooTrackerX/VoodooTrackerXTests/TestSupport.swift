import AppKit
import AudioToolbox
import XCTest

enum TestPatternNavigationCommand {
    case up
    case down
    case pageUp
    case pageDown
    case home
    case end
    case left
    case right
}

enum TestPatternCursorField: Int {
    case note
    case instrument
    case volume
    case effectType
    case effectParam
}

struct TestPatternCursor: Equatable {
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

enum TestPatternEditInput {
    case clearField
    case hexDigit(UInt8)
    case keyOff
}

struct TestXMPatternEventCell: Equatable {
    let note: UInt8
    let instrument: UInt8
    let volumeColumn: UInt8
    let effectType: UInt8
    let effectParam: UInt8
}

enum TestPatternEditEngine {
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
                return TestXMPatternEventCell(note: 0, instrument: 0, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
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
        case .keyOff:
            guard field == .note else {
                return nil
            }
            return TestXMPatternEventCell(note: TrackerNoteKeyMap.keyOffNoteValue, instrument: 0, volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
        }
    }
}

struct TestPatternSelectionEntry: Equatable {
    let patternIndex: Int
    let isUsed: Bool
    let rowCount: Int
}

func buildPatternSelection(
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

struct TestPatternViewportMetrics: Equatable {
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

struct TestPatternViewportState: Equatable {
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

struct TestPatternViewportTextLayout: Equatable {
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

enum TestTrackerChromeGeometry {
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

enum TestTrackerViewportScrollGeometry {
    static func clampedHorizontalOrigin(preferredOriginX: CGFloat, contentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        let maxOriginX = max(0, contentWidth - viewportWidth)
        return min(max(0, preferredOriginX), maxOriginX)
    }
}

enum TestTrackerViewportResizeBehavior {
    static func shouldCaptureStableHorizontalOrigin(isLiveResize: Bool) -> Bool {
        !isLiveResize
    }

    static func shouldRevealCursorHorizontally(isViewportResizeRerender: Bool) -> Bool {
        !isViewportResizeRerender
    }
}

enum TestPatternCursorOutlineGeometry {
    static func strokeRect(for fieldRect: CGRect) -> CGRect {
        fieldRect.insetBy(dx: -2, dy: -2)
    }

    static func minimumVisibleBounds(for bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: 2, dy: 2)
    }
}

func displayedPatternIndex(orderTable: [Int], songLength: Int, songPosition: Int) -> Int? {
    let safeSongLength = min(songLength, orderTable.count)
    guard safeSongLength > 0 else {
        return nil
    }
    let clampedPosition = min(max(0, songPosition), safeSongLength - 1)
    return orderTable[clampedPosition]
}

func formattedPatternSelectorTitle(patternIndex: Int, rowCount: Int) -> String {
    String(format: "P%02X", patternIndex)
}

func makePlaybackSong(
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

func makePlaybackSong(
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

func makePlaybackRow(
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

struct TestPlaybackPatternLoopRange: Equatable {
    let orderEntry: PlaybackOrderEntry
    let firstPosition: PlaybackPosition
    let lastPosition: PlaybackPosition
    let rowCount: Int

    var orderIndex: Int {
        orderEntry.orderIndex
    }

    var patternIndex: Int {
        orderEntry.patternIndex
    }

    func contains(_ position: PlaybackPosition) -> Bool {
        position.orderIndex == orderIndex &&
            position.patternIndex == patternIndex &&
            position.rowIndex >= firstPosition.rowIndex &&
            position.rowIndex <= lastPosition.rowIndex
    }
}

struct TestPlaybackPatternLoopTransportBoundary: Equatable {
    enum AdapterPlanStrategy: Equatable {
        case existingPlanRange
    }

    let range: TestPlaybackPatternLoopRange
    let adapterPlanStrategy: AdapterPlanStrategy
    let requiresRuntimeAdapterPlan: Bool
    let usesTimerDrivenTriggers: Bool
    let clearsActiveVoicesAtBoundary: Bool
}

enum TestPlaybackPatternLoopTransportBoundaryResolver {
    static func boundary(
        containing position: PlaybackPosition,
        in song: PlaybackSong
    ) -> TestPlaybackPatternLoopTransportBoundary? {
        guard let range = range(containing: position, in: song) else {
            return nil
        }
        return TestPlaybackPatternLoopTransportBoundary(
            range: range,
            adapterPlanStrategy: .existingPlanRange,
            requiresRuntimeAdapterPlan: true,
            usesTimerDrivenTriggers: false,
            clearsActiveVoicesAtBoundary: false
        )
    }

    private static func range(
        containing position: PlaybackPosition,
        in song: PlaybackSong
    ) -> TestPlaybackPatternLoopRange? {
        guard song.orders.indices.contains(position.orderIndex) else {
            return nil
        }
        let orderEntry = song.orders[position.orderIndex]
        guard orderEntry.patternIndex == position.patternIndex,
              let pattern = song.patternsByIndex[position.patternIndex],
              !pattern.rows.isEmpty,
              pattern.rows.indices.contains(position.rowIndex) else {
            return nil
        }
        return TestPlaybackPatternLoopRange(
            orderEntry: orderEntry,
            firstPosition: PlaybackPosition(
                orderIndex: orderEntry.orderIndex,
                patternIndex: orderEntry.patternIndex,
                rowIndex: 0
            ),
            lastPosition: PlaybackPosition(
                orderIndex: orderEntry.orderIndex,
                patternIndex: orderEntry.patternIndex,
                rowIndex: pattern.rows.count - 1
            ),
            rowCount: pattern.rows.count
        )
    }
}

extension RuntimeCMixerAdapterEventPlan {
    func testEvents(in range: TestPlaybackPatternLoopRange) -> [RuntimeCMixerAdapterEvent] {
        events.filter { range.contains($0.source) }
    }
}

func makePlaybackSample(
    instrumentIndex: Int = 1,
    sampleIndex: Int = 0,
    name: String = "",
    pcm: [Float] = [1, 0.5, -0.5],
    volume: Float = 1,
    panning: UInt8 = 128,
    relativeNote: Int = 0,
    finetune: Int = 0,
    baseSampleRate: Double = 100,
    loopStart: Int = 0,
    loopLength: Int = 0,
    loopType: Int = 0
) -> PlaybackSample {
    PlaybackSample(
        instrumentIndex: instrumentIndex,
        sampleIndex: sampleIndex,
        name: name,
        pcm: pcm,
        volume: volume,
        panning: panning,
        relativeNote: relativeNote,
        finetune: finetune,
        baseSampleRate: baseSampleRate,
        sampleLength: pcm.count,
        loopStart: loopStart,
        loopLength: loopLength,
        loopType: loopType
    )
}

func makeRampPlaybackSample(
    frameCount: Int = 600,
    instrumentIndex: Int = 1,
    sampleIndex: Int = 0,
    volume: Float = 1,
    relativeNote: Int = 0,
    finetune: Int = 0,
    baseSampleRate: Double = 100,
    loopStart: Int = 0,
    loopLength: Int = 0,
    loopType: Int = 0
) -> PlaybackSample {
    makePlaybackSample(
        instrumentIndex: instrumentIndex,
        sampleIndex: sampleIndex,
        pcm: (0..<max(0, frameCount)).map { Float($0) / 1_000.0 },
        volume: volume,
        relativeNote: relativeNote,
        finetune: finetune,
        baseSampleRate: baseSampleRate,
        loopStart: loopStart,
        loopLength: loopLength,
        loopType: loopType
    )
}

func XCTAssertFloatArrayEqual(
    _ actual: [Float],
    _ expected: [Float],
    accuracy: Float = 0.000_001,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for index in 0..<min(actual.count, expected.count) {
        XCTAssertEqual(actual[index], expected[index], accuracy: accuracy, "index \(index)", file: file, line: line)
    }
}

func makePlaybackVolumeEnvelope(
    enabled: Bool = true,
    points: [PlaybackEnvelopePoint],
    sustainPointIndex: Int? = nil,
    loopStartPointIndex: Int? = nil,
    loopEndPointIndex: Int? = nil,
    typeFlags: UInt8 = 0x01,
    fadeout: Int = 0
) -> PlaybackVolumeEnvelope {
    PlaybackVolumeEnvelope(
        enabled: enabled,
        points: points,
        sustainPointIndex: sustainPointIndex,
        loopStartPointIndex: loopStartPointIndex,
        loopEndPointIndex: loopEndPointIndex,
        typeFlags: typeFlags,
        fadeout: fadeout
    )
}

func makeNoteSampleMap(defaultSampleIndex: Int = 0, overrides: [UInt8: Int] = [:]) -> [Int] {
    var map = Array(repeating: defaultSampleIndex, count: 96)
    for (note, sampleIndex) in overrides where (1...96).contains(note) {
        map[Int(note) - 1] = sampleIndex
    }
    return map
}

enum TestPlaybackMode: Equatable {
    case stopped
    case playing
    case paused
}

struct TestPlaybackStartContext: Equatable {
    let moduleTitle: String?
    let songPosition: Int
    let patternIndex: Int
    let row: Int
}

struct TestPlaybackState: Equatable {
    var mode: TestPlaybackMode
    var context: TestPlaybackStartContext?

    static let stopped = TestPlaybackState(mode: .stopped, context: nil)
}

final class TestPlaybackEngine {
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
final class TestPlaybackAudioOutput: PlaybackAudioOutput {
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
final class TestRuntimeAdapterAudioOutput: PlaybackAudioOutput, PlaybackAudioBackendProviding, RuntimeCMixerAdapterEventConsuming {
    let audioBufferSampleRate: Double
    let runtimeAudioBackend: RuntimeAudioBackend = .cMixer
    private(set) var triggeredRequests = [AudioVoiceRequest]()
    private(set) var updatedControls = [(channel: Int, controls: AudioChannelControls)]()
    private(set) var stoppedChannels = [Int]()
    private(set) var stopAllCount = 0
    private(set) var resetCount = 0
    private(set) var configuredPlans = [RuntimeCMixerAdapterEventPlan]()
    private(set) var generationMSValues = [Double?]()
    private(set) var resetConsumptionCount = 0
    private(set) var consumedContexts = [AudioRuntimeTraceContext?]()
    private(set) var consumedPatternLoopRanges = [PlaybackPatternLoopRange?]()
    private var adapterEventPlan: RuntimeCMixerAdapterEventPlan

    init(audioBufferSampleRate: Double = 100.0) {
        self.audioBufferSampleRate = audioBufferSampleRate
        adapterEventPlan = .unavailable(sampleRate: audioBufferSampleRate)
    }

    var hasRuntimeAdapterEventPlan: Bool {
        adapterEventPlan.generated
    }

    var generatedPlanConfigureCount: Int {
        configuredPlans.filter { $0.generated }.count
    }

    var unavailablePlanConfigureCount: Int {
        configuredPlans.filter { !$0.generated }.count
    }

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
        resetRuntimeAdapterEventConsumption()
    }

    func reset() {
        resetCount += 1
        stopAll()
    }

    func configureRuntimeAdapterEventPlan(_ plan: RuntimeCMixerAdapterEventPlan, generationMS: Double?, timingSession _: PlaybackTimingTraceSession?) {
        adapterEventPlan = plan
        configuredPlans.append(plan)
        generationMSValues.append(generationMS)
        resetRuntimeAdapterEventConsumption()
    }

    func resetRuntimeAdapterEventConsumption() {
        resetConsumptionCount += 1
    }

    func consumeRuntimeAdapterEvents(
        context: AudioRuntimeTraceContext?,
        patternLoopRange: PlaybackPatternLoopRange?,
        timingSession _: PlaybackTimingTraceSession?
    ) {
        consumedContexts.append(context)
        consumedPatternLoopRanges.append(patternLoopRange)
    }
}

final class TestRuntimeAdapterPlanPrewarmJob: RuntimeAdapterPlanPrewarmJob, @unchecked Sendable {
    let generation: UInt64
    var cancelCount = 0
    var waitCount = 0
    var waitResult: RuntimeAdapterPlanPrewarmResult?

    init(generation: UInt64) {
        self.generation = generation
    }

    func cancel() {
        cancelCount += 1
    }

    func waitForResult() -> RuntimeAdapterPlanPrewarmResult? {
        waitCount += 1
        return waitResult
    }
}

@MainActor
final class TestRuntimeAdapterPlanPrewarmScheduler: RuntimeAdapterPlanPrewarmScheduling {
    private(set) var requests = [RuntimeAdapterPlanPrewarmRequest]()
    private(set) var jobs = [TestRuntimeAdapterPlanPrewarmJob]()
    private var completions = [(@Sendable (RuntimeAdapterPlanPrewarmResult) -> Void)]()
    private var defaultResults = [RuntimeAdapterPlanPrewarmResult]()
    var makeMS: Double = 2.0

    func schedule(
        request: RuntimeAdapterPlanPrewarmRequest,
        completion: @escaping @Sendable (RuntimeAdapterPlanPrewarmResult) -> Void
    ) -> RuntimeAdapterPlanPrewarmJob {
        let job = TestRuntimeAdapterPlanPrewarmJob(generation: request.generation)
        let profileSession = request.adapterPlanProfileRecorder?.beginLifecycle("prewarm")
        let plan = RuntimeCMixerAdapterEventPlan.make(
            song: request.song,
            sampleRate: request.sampleRate,
            profileSession: profileSession
        )
        let result = RuntimeAdapterPlanPrewarmResult(
            generation: request.generation,
            plan: plan,
            makeMS: makeMS,
            completedAfterCancellation: false,
            adapterPlanProfileSession: profileSession
        )
        requests.append(request)
        jobs.append(job)
        completions.append(completion)
        defaultResults.append(result)
        return job
    }

    func defaultResult(at index: Int = 0) -> RuntimeAdapterPlanPrewarmResult {
        defaultResults[index]
    }

    func complete(at index: Int = 0, result: RuntimeAdapterPlanPrewarmResult? = nil) {
        completions[index](result ?? defaultResults[index])
    }
}

@MainActor
final class TestRuntimeFollowAudioOutput: PlaybackAudioOutput, PlaybackAudioBackendProviding, PlaybackFollowPositionProviding, RuntimeAudioDiagnosticOutput {
    let audioBufferSampleRate = 100.0
    let runtimeAudioBackend: RuntimeAudioBackend = .cMixer
    var followPositions = [PlaybackFollowPosition?]()
    private(set) var recordedFollowEvents = [(position: PlaybackFollowPosition, resolverFailureReason: String?)]()

    func trigger(_ request: AudioVoiceRequest) {}
    func update(channel: Int, controls: AudioChannelControls) {}
    func stop(channel: Int) {}
    func stopAll() {}
    func reset() {}

    func playbackFollowPosition(timerPosition: PlaybackPosition, timerTickInRow: Int) -> PlaybackFollowPosition? {
        guard !followPositions.isEmpty else {
            return nil
        }
        return followPositions.removeFirst()
    }

    func trigger(_ request: AudioVoiceRequest, context: AudioRuntimeTraceContext?) {}
    func update(channel: Int, controls: AudioChannelControls, context: AudioRuntimeTraceContext?) {}
    func stop(channel: Int, context: AudioRuntimeTraceContext?) {}
    func stopAll(context: AudioRuntimeTraceContext?, reason: String) {}
    func recordTransition(previousContext: AudioRuntimeTraceContext?, context: AudioRuntimeTraceContext?, phase: String, reason: String) {}

    func recordPublishedPlaybackFollowPosition(
        timerContext: AudioRuntimeTraceContext?,
        publishedPosition: PlaybackFollowPosition,
        publicationDisabled: Bool,
        consumedByUI: Bool,
        duplicateSuppressed: Bool,
        resolverFailureReason: String?
    ) {
        recordedFollowEvents.append((publishedPosition, resolverFailureReason))
    }
}

@MainActor
final class TestPlaybackTraceWriter: PlaybackTraceWriting {
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

@MainActor
final class TestRuntimeCMixerTraceWriter: RuntimeCMixerTraceWriting {
    private(set) var events = [RuntimeCMixerTraceEvent]()
    private(set) var flushCount = 0

    let isEnabled = true

    func record(_ event: RuntimeCMixerTraceEvent) {
        events.append(event)
    }

    func flush() {
        flushCount += 1
    }
}

@MainActor
final class TestRuntimeMixerMetricsTraceWriter: RuntimeMixerMetricsTraceWriting {
    private(set) var records = [RuntimeMixerMetricsTraceRecord]()
    private(set) var flushCount = 0

    let isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func record(_ record: RuntimeMixerMetricsTraceRecord) {
        records.append(record)
    }

    func flush() {
        flushCount += 1
    }

    var lines: [String] {
        records.map { RuntimeMixerMetricsTraceFormatter.line(for: $0) }
    }
}

func stereoPCM(from monoPCM: [Float]) -> [Float] {
    monoPCM.flatMap { [$0, $0] }
}

func XCTAssertPCMEqual(
    _ actual: [Float],
    _ expected: [Float],
    accuracy: Float = 0.000001,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (index, pair) in zip(actual, expected).enumerated() {
        XCTAssertEqual(pair.0, pair.1, accuracy: accuracy, "PCM mismatch at sample \(index)", file: file, line: line)
    }
}

func renderRuntimePCM(_ core: RuntimeCMixerRenderCore, frames: Int) -> [Float] {
    var output = Array(repeating: Float(0), count: frames * core.config.channelCount)
    output.withUnsafeMutableBufferPointer { buffer in
        XCTAssertTrue(core.render(into: buffer, frameCount: frames))
    }
    return output
}

func renderCoreAudioRuntimePCM(
    _ core: RuntimeCMixerRenderCore,
    frames: Int,
    initialValue: Float = 0
) -> [Float] {
    var output = Array(repeating: initialValue, count: frames * core.config.channelCount)
    output.withUnsafeMutableBufferPointer { outputBuffer in
        let audioBuffer = AudioBuffer(
            mNumberChannels: UInt32(core.config.channelCount),
            mDataByteSize: UInt32(outputBuffer.count * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(outputBuffer.baseAddress)
        )
        var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
        let status = withUnsafeMutablePointer(to: &audioBufferList) { listPointer in
            core.render(frameCount: UInt32(max(0, frames)), ioData: listPointer)
        }
        XCTAssertEqual(status, noErr)
    }
    return output
}

func defaultRuntimePan(forChannel channel: Int) -> Float {
    PlaybackEffectHandler.audioPanning(forXMValue: PlaybackChannelState.defaultPanning(forChannel: channel))
}

func pitchOffsetSemitones(forPlaybackStep playbackStep: Double) -> Double {
    12 * log2(playbackStep)
}

func makeSyntheticEventMapping(
    source: PlaybackPosition = PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 0),
    channelIndex: Int = 0,
    note: UInt8 = 49,
    instrumentIndex: Int = 1,
    sampleIndex: Int = 0,
    selectedSampleLength: Int = 64,
    syntheticTick: Int = 0,
    eventIndex: Int = 0,
    effectType: UInt8 = 0,
    effectParam: UInt8 = 0,
    effectivePan: Float = 0,
    playbackStep: Double = 1
) -> PlaybackSongSyntheticEventMapping {
    let sampleOffset = PlaybackSongSyntheticSampleOffsetDiagnostic(
        source: source,
        channelIndex: channelIndex,
        syntheticRow: source.rowIndex,
        syntheticTick: syntheticTick,
        effectType: effectType,
        effectParam: effectParam,
        status: .notPresent,
        detected: false,
        applied: false,
        deferred: false,
        ignoredAsNoOp: false,
        skipped: false,
        outOfRange: false,
        computedOffsetFrames: 0,
        appliedOffsetFrames: nil,
        selectedSampleLength: selectedSampleLength,
        effectMemoryReused: false,
        effectMemoryMissing: false,
        effectMemoryDeferred: false,
        memorySource: nil,
        memoryUnavailableReason: nil
    )
    let envelopeSemantics = PlaybackSongSyntheticEnvelopeSemanticsDiagnostic(
        envelopeEnabled: false,
        sourcePointCount: 0,
        mappedPointCount: 0,
        sustainEnabled: false,
        sustainApplied: false,
        sustainDeferred: false,
        sustainPointIndex: nil,
        sustainTick: nil,
        sustainFrame: nil,
        loopEnabled: false,
        loopApplied: false,
        loopDeferred: false,
        loopStartPointIndex: nil,
        loopEndPointIndex: nil,
        loopStartTick: nil,
        loopEndTick: nil,
        loopStartFrame: nil,
        loopEndFrame: nil,
        keyOffEncountered: false,
        keyOffApplied: false,
        keyOffDeferred: false,
        keyOffSource: nil,
        keyOffChannelIndex: nil,
        keyOffSyntheticRow: nil,
        keyOffSyntheticTick: nil,
        releaseFrame: nil,
        fadeoutValue: 0,
        fadeoutApplied: false,
        fadeoutDeferred: false,
        limitations: []
    )
    return PlaybackSongSyntheticEventMapping(
        source: source,
        channelIndex: channelIndex,
        note: note,
        instrumentIndex: instrumentIndex,
        sampleIndex: sampleIndex,
        sampleVolume: 1,
        sampleVolumeRawEstimate: 64,
        selectedSampleLength: selectedSampleLength,
        sampleMapKeymapPresent: false,
        mappedSampleIndex: nil,
        mappedSampleValid: false,
        sampleSelectionMethod: .firstPlayableFallback,
        sampleSelectionStrategy: PlaybackSongSyntheticSampleSelectionMethod.firstPlayableFallback.rawValue,
        firstPlayableSampleFallbackUsed: false,
        sampleMapKeymapBehaviorDeferred: false,
        sampleMapKeymapMissingOrDeferred: false,
        effectType: effectType,
        effectParam: effectParam,
        syntheticRow: source.rowIndex,
        syntheticTick: syntheticTick,
        eventIndex: eventIndex,
        loopMode: .none,
        volumeColumn: PlaybackSongVolumeColumnDecoder.decode(0),
        sampleOffset: sampleOffset,
        hasIgnoredVolumeColumn: false,
        hasIgnoredEffect: false,
        effectiveVolumeValue: 64,
        effectiveGlobalVolumeValue: 64,
        effectiveGlobalVolumeMultiplier: 1,
        effectivePan: effectivePan,
        volumeEnvelopeStatus: .absent,
        sourceVolumeEnvelopePointCount: 0,
        mappedVolumeEnvelopePointCount: 0,
        hasDeferredVolumeEnvelopeSustain: false,
        hasDeferredVolumeEnvelopeLoop: false,
        hasDeferredVolumeEnvelopeFadeout: false,
        volumeEnvelopeSemantics: envelopeSemantics,
        sampleBaseSampleRate: 44_100,
        sampleRelativeNote: 0,
        sampleFinetune: 0,
        outputSampleRate: 44_100,
        effectiveNoteValue: Int(note),
        effectiveNoteIndex: Int(note) - 1,
        effectiveFinetune: 0,
        linearPeriod: nil,
        linearFrequency: nil,
        amigaPeriod: nil,
        amigaFrequency: nil,
        finetuneStatus: .applied,
        usesLinearFrequencyTable: true,
        frequencyTableStatus: .linearApplied,
        linearFrequencyApplied: true,
        amigaFrequencyApplied: false,
        amigaFrequencyDeferred: false,
        playbackStep: playbackStep,
        pitchMappingApplied: true,
        pitchMappingUsedNeutralStep: playbackStep == 1
    )
}

func swiftOneShotBlock(
    sample: MixerSampleBuffer,
    frames: Int,
    config: MixerRenderConfig = MixerRenderConfig(sampleRate: 1_000, channelCount: 2),
    gain: Float = 1,
    pan: Float = 0,
    loop: MixerSampleLoop = .none
) -> MixerRenderBlock {
    let mixer = SoftwareMixer(config: config)
    mixer.addVoice(sample: sample, gain: gain, pan: pan, loop: loop)
    return mixer.render(frames: frames)
}

func cOneShotBlock(
    sample: MixerSampleBuffer,
    frames: Int,
    config: MixerRenderConfig = MixerRenderConfig(sampleRate: 1_000, channelCount: 2),
    gain: Float = 1,
    pan: Float = 0,
    playbackStep: Double = 1,
    loop: MixerSampleLoop = .none,
    initialSourceFrame: Int = 0,
    volumeEnvelope: MixerEnvelope? = nil,
    panEnvelope: MixerEnvelope? = nil,
    keyOffFrame: Int? = nil,
    fadeoutFrameDecrement: Float = 0
) -> MixerRenderBlock {
    let mixer = CSoftwareMixer(config: config)
    mixer.addVoice(
        sample: sample,
        gain: gain,
        pan: pan,
        playbackStep: playbackStep,
        loop: loop,
        initialSourceFrame: initialSourceFrame,
        volumeEnvelope: volumeEnvelope,
        panEnvelope: panEnvelope,
        keyOffFrame: keyOffFrame,
        fadeoutFrameDecrement: fadeoutFrameDecrement
    )
    return mixer.render(frames: frames)
}

func cScheduledBlock(
    sample: MixerSampleBuffer,
    scheduledStartFrame: Int,
    frames: Int,
    config: MixerRenderConfig = MixerRenderConfig(sampleRate: 1_000, channelCount: 2),
    gain: Float = 1,
    pan: Float = 0,
    playbackStep: Double = 1,
    loop: MixerSampleLoop = .none,
    initialSourceFrame: Int = 0,
    volumeEnvelope: MixerEnvelope? = nil,
    panEnvelope: MixerEnvelope? = nil,
    keyOffFrame: Int? = nil,
    fadeoutFrameDecrement: Float = 0
) -> MixerRenderBlock {
    let mixer = CSoftwareMixer(config: config)
    _ = mixer.addScheduledVoice(
        sample: sample,
        scheduledStartFrame: scheduledStartFrame,
        gain: gain,
        pan: pan,
        playbackStep: playbackStep,
        loop: loop,
        initialSourceFrame: initialSourceFrame,
        volumeEnvelope: volumeEnvelope,
        panEnvelope: panEnvelope,
        keyOffFrame: keyOffFrame,
        fadeoutFrameDecrement: fadeoutFrameDecrement
    )
    return mixer.render(frames: frames)
}

func cSyntheticTrackerBlock(
    events: [SyntheticTrackerEvent],
    frames: Int,
    timingConfig: SyntheticTrackerTimingConfig = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100),
    channelCount: Int = 1
) -> MixerRenderBlock {
    let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: timingConfig.sampleRate, channelCount: channelCount))
    let scheduler = SyntheticTrackerScheduler(config: timingConfig)
    _ = scheduler.schedule(events, on: mixer)
    return mixer.render(frames: frames)
}

func cSyntheticPatternBlock(
    pattern: SyntheticPattern,
    frames: Int,
    timingConfig: SyntheticTrackerTimingConfig = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100),
    channelCount: Int = 1
) -> MixerRenderBlock {
    let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: timingConfig.sampleRate, channelCount: channelCount))
    let scheduler = SyntheticPatternScheduler(config: timingConfig)
    _ = scheduler.schedule(pattern, on: mixer)
    return mixer.render(frames: frames)
}

struct TestPCM16WAV: Equatable {
    let riffSize: UInt32
    let sampleRate: UInt32
    let channelCount: UInt16
    let byteRate: UInt32
    let blockAlign: UInt16
    let bitsPerSample: UInt16
    let dataSize: UInt32
    let samples: [Int16]
}

enum TestWAVParseError: Error {
    case invalidData
}

func parsePCM16WAV(_ data: Data) throws -> TestPCM16WAV {
    guard data.count >= 44,
          Array(data[0..<4]) == Array("RIFF".utf8),
          Array(data[8..<12]) == Array("WAVE".utf8),
          Array(data[12..<16]) == Array("fmt ".utf8),
          readLE32(data, offset: 16) == 16,
          readLE16(data, offset: 20) == 1,
          Array(data[36..<40]) == Array("data".utf8) else {
        throw TestWAVParseError.invalidData
    }

    let dataSize = readLE32(data, offset: 40)
    guard data.count == 44 + Int(dataSize),
          dataSize % 2 == 0 else {
        throw TestWAVParseError.invalidData
    }

    var samples = [Int16]()
    samples.reserveCapacity(Int(dataSize) / 2)
    for offset in stride(from: 44, to: data.count, by: 2) {
        samples.append(readLEInt16(data, offset: offset))
    }

    return TestPCM16WAV(
        riffSize: readLE32(data, offset: 4),
        sampleRate: readLE32(data, offset: 24),
        channelCount: readLE16(data, offset: 22),
        byteRate: readLE32(data, offset: 28),
        blockAlign: readLE16(data, offset: 32),
        bitsPerSample: readLE16(data, offset: 34),
        dataSize: dataSize,
        samples: samples
    )
}

func readLE16(_ data: Data, offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

func readLE32(_ data: Data, offset: Int) -> UInt32 {
    UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
}

func readLEInt16(_ data: Data, offset: Int) -> Int16 {
    Int16(bitPattern: readLE16(data, offset: offset))
}
