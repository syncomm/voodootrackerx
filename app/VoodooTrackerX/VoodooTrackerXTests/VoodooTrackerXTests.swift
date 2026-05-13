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

private func makePlaybackSample(
    instrumentIndex: Int = 1,
    sampleIndex: Int = 0,
    pcm: [Float] = [1, 0.5, -0.5],
    volume: Float = 1,
    loopStart: Int = 0,
    loopLength: Int = 0,
    loopType: Int = 0
) -> PlaybackSample {
    PlaybackSample(
        instrumentIndex: instrumentIndex,
        sampleIndex: sampleIndex,
        pcm: pcm,
        volume: volume,
        relativeNote: 0,
        finetune: 0,
        baseSampleRate: 8_363,
        sampleLength: pcm.count,
        loopStart: loopStart,
        loopLength: loopLength,
        loopType: loopType
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

private func stereoPCM(from monoPCM: [Float]) -> [Float] {
    monoPCM.flatMap { [$0, $0] }
}

private func swiftOneShotBlock(
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

private func cOneShotBlock(
    sample: MixerSampleBuffer,
    frames: Int,
    config: MixerRenderConfig = MixerRenderConfig(sampleRate: 1_000, channelCount: 2),
    gain: Float = 1,
    pan: Float = 0,
    loop: MixerSampleLoop = .none,
    volumeEnvelope: MixerEnvelope? = nil,
    panEnvelope: MixerEnvelope? = nil
) -> MixerRenderBlock {
    let mixer = CSoftwareMixer(config: config)
    mixer.addVoice(
        sample: sample,
        gain: gain,
        pan: pan,
        loop: loop,
        volumeEnvelope: volumeEnvelope,
        panEnvelope: panEnvelope
    )
    return mixer.render(frames: frames)
}

private func cScheduledBlock(
    sample: MixerSampleBuffer,
    scheduledStartFrame: Int,
    frames: Int,
    config: MixerRenderConfig = MixerRenderConfig(sampleRate: 1_000, channelCount: 2),
    gain: Float = 1,
    pan: Float = 0,
    loop: MixerSampleLoop = .none,
    volumeEnvelope: MixerEnvelope? = nil,
    panEnvelope: MixerEnvelope? = nil
) -> MixerRenderBlock {
    let mixer = CSoftwareMixer(config: config)
    _ = mixer.addScheduledVoice(
        sample: sample,
        scheduledStartFrame: scheduledStartFrame,
        gain: gain,
        pan: pan,
        loop: loop,
        volumeEnvelope: volumeEnvelope,
        panEnvelope: panEnvelope
    )
    return mixer.render(frames: frames)
}

private func cSyntheticTrackerBlock(
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

private func cSyntheticPatternBlock(
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

final class VoodooTrackerXTests: XCTestCase {
    func testCMixerCoreReturnsPredictableInvalidArgumentStatus() {
        let config = vtx_c_mixer_default_config()
        var state = VTXCMixerState()
        XCTAssertEqual(vtx_c_mixer_init(&state, config), VTX_C_MIXER_STATUS_OK)

        XCTAssertEqual(vtx_c_mixer_init(nil, config), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_reset(nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_configure(nil, config), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_clear_voices(nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_one_shot_sample(nil, nil, 0, 1, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_one_shot_sample(&state, nil, 1, 1, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_sample_voice(nil, nil, 0, 1, 0, VTX_C_MIXER_LOOP_FORWARD, 0, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_sample_voice(&state, nil, 1, 1, 0, VTX_C_MIXER_LOOP_FORWARD, 0, 1, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_scheduled_sample_voice(nil, nil, 0, 1, 0, VTX_C_MIXER_LOOP_NONE, 0, 0, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_add_scheduled_sample_voice(&state, nil, 1, 1, 0, VTX_C_MIXER_LOOP_NONE, 0, 0, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_volume_envelope(nil, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_volume_envelope(&state, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_pan_envelope(nil, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_set_voice_pan_envelope(&state, 0, nil), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_render(nil, nil, 0), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_render(&state, nil, 1), VTX_C_MIXER_STATUS_INVALID_ARGUMENT)
        XCTAssertEqual(vtx_c_mixer_render(&state, nil, 0), VTX_C_MIXER_STATUS_OK)

        var scheduledState = VTXCMixerState()
        XCTAssertEqual(vtx_c_mixer_init(&scheduledState, config), VTX_C_MIXER_STATUS_OK)
        var output = Array(repeating: Float(0), count: 4)
        XCTAssertEqual(
            output.withUnsafeMutableBufferPointer { buffer in
                vtx_c_mixer_render(&scheduledState, buffer.baseAddress, 2)
            },
            VTX_C_MIXER_STATUS_OK
        )
        let sample: [Float] = [1]
        XCTAssertEqual(
            sample.withUnsafeBufferPointer { buffer in
                vtx_c_mixer_add_scheduled_sample_voice(
                    &scheduledState,
                    buffer.baseAddress,
                    1,
                    1,
                    0,
                    VTX_C_MIXER_LOOP_NONE,
                    0,
                    0,
                    1,
                    nil
                )
            },
            VTX_C_MIXER_STATUS_INVALID_ARGUMENT
        )
    }

    func testCSoftwareMixerInitializesWithDefaultRenderConfiguration() {
        let mixer = CSoftwareMixer()

        XCTAssertEqual(mixer.config, MixerRenderConfig())
        XCTAssertEqual(mixer.config.sampleRate, 44_100)
        XCTAssertEqual(mixer.config.channelCount, 2)
        XCTAssertTrue(mixer.config.isInterleaved)
    }

    func testCSoftwareMixerCanConfigureSampleRateAndChannelCount() {
        let mixer = CSoftwareMixer()

        mixer.configure(sampleRate: 48_000, channelCount: 1)

        XCTAssertEqual(mixer.config.sampleRate, 48_000)
        XCTAssertEqual(mixer.config.channelCount, 1)
    }

    func testCSoftwareMixerZeroFrameRenderReturnsEmptyBlock() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2))

        let block = mixer.render(frames: 0)

        XCTAssertEqual(block, MixerRenderBlock(config: mixer.config, frameCount: 0, interleavedPCM: []))
    }

    func testCSoftwareMixerPositiveRenderReturnsRequestedFramesAndSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2))

        let block = mixer.render(frames: 8)

        XCTAssertEqual(block.frameCount, 8)
        XCTAssertEqual(block.sampleCount, 16)
        XCTAssertEqual(block.sampleCount, block.frameCount * mixer.config.channelCount)
        XCTAssertEqual(block.interleavedPCM, Array(repeating: Float(0), count: 16))
    }

    func testCSoftwareMixerResetIsDeterministic() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 22_050, channelCount: 2))

        let first = mixer.render(frames: 6)
        mixer.reset()
        let second = mixer.render(frames: 6)

        XCTAssertEqual(first, second)
    }

    func testCSoftwareMixerRepeatedRendersAfterResetMatch() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))

        let first = mixer.render(frames: 4)
        _ = mixer.render(frames: 4)
        mixer.reset()
        let reset = mixer.render(frames: 4)

        XCTAssertEqual(first, reset)
        XCTAssertEqual(reset.interleavedPCM, Array(repeating: Float(0), count: 4))
    }

    func testCSoftwareMixerInvalidConfigurationFallsBackToDeterministicDefaults() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: -1, channelCount: 0))

        XCTAssertEqual(mixer.config, MixerRenderConfig())

        mixer.configure(sampleRate: .nan, channelCount: -4)
        let block = mixer.render(frames: 2)

        XCTAssertEqual(mixer.config, MixerRenderConfig())
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0])
    }

    func testCSoftwareMixerOneSampleBufferMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1])

        let cBlock = cOneShotBlock(sample: sample, frames: 3)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 3)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [1, 1, 0, 0, 0, 0])
    }

    func testCSoftwareMixerMultiSampleBufferMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5, -1])

        let cBlock = cOneShotBlock(sample: sample, frames: 4)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 4)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [1, 1, 0.5, 0.5, -0.5, -0.5, -1, -1])
    }

    func testCSoftwareMixerMonoOutputMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let config = MixerRenderConfig(sampleRate: 1_000, channelCount: 1)

        let cBlock = cOneShotBlock(sample: sample, frames: 4, config: config)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 4, config: config)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [1, 0.5, -0.5, 0])
    }

    func testCSoftwareMixerRendersSilenceAfterSampleEndsLikeSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0.25, 0.5, 0.25])

        let cBlock = cOneShotBlock(sample: sample, frames: 5)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [0.25, 0.25, 0.5, 0.5, 0.25, 0.25, 0, 0, 0, 0])
    }

    func testCSoftwareMixerRepeatedRenderAfterResetRewindsVoicesDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [0.25, 0.5, 0.25])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample)

        let first = mixer.render(frames: 4)
        mixer.reset()
        let second = mixer.render(frames: 4)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, swiftOneShotBlock(sample: sample, frames: 4))
    }

    func testCSoftwareMixerClearVoicesReturnsToSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5]))

        mixer.clearVoices()
        let block = mixer.render(frames: 2)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0])
    }

    func testCSoftwareMixerGainMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, -1])

        let cBlock = cOneShotBlock(sample: sample, frames: 2, gain: 0.5)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 2, gain: 0.5)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [0.5, 0.5, -0.5, -0.5])
    }

    func testCSoftwareMixerCenterMonoToStereoMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0.25])

        let cBlock = cOneShotBlock(sample: sample, frames: 1, pan: 0)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 1, pan: 0)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [0.25, 0.25])
    }

    func testCSoftwareMixerPanBehaviorMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1])
        let cMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        cMixer.addVoice(sample: sample, gain: 0.25, pan: -1)
        cMixer.addVoice(sample: sample, gain: 0.5, pan: 1)

        let swiftMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        swiftMixer.addVoice(sample: sample, gain: 0.25, pan: -1)
        swiftMixer.addVoice(sample: sample, gain: 0.5, pan: 1)

        let cBlock = cMixer.render(frames: 1)
        let swiftBlock = swiftMixer.render(frames: 1)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [0.25, 0.5])
    }

    func testCSoftwareMixerMultipleSmallRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        singleRenderMixer.addVoice(sample: sample)
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        splitRenderMixer.addVoice(sample: sample)

        let singleRender = singleRenderMixer.render(frames: 5)
        let splitRender = splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        XCTAssertEqual(singleRender, swiftOneShotBlock(sample: sample, frames: 5))
    }

    func testCSoftwareMixerEmptySampleBufferRendersSilenceSafely() {
        let sample = MixerSampleBuffer(monoPCM: [])

        let cBlock = cOneShotBlock(sample: sample, frames: 3)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 3)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testCSoftwareMixerInvalidGainAndPanMatchSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1])

        let invalidGainCBlock = cOneShotBlock(sample: sample, frames: 1, gain: .nan, pan: 0)
        let invalidGainSwiftBlock = swiftOneShotBlock(sample: sample, frames: 1, gain: .nan, pan: 0)
        XCTAssertEqual(invalidGainCBlock, invalidGainSwiftBlock)
        XCTAssertEqual(invalidGainCBlock.interleavedPCM, [0, 0])

        let invalidPanCBlock = cOneShotBlock(sample: sample, frames: 1, gain: 1, pan: .infinity)
        let invalidPanSwiftBlock = swiftOneShotBlock(sample: sample, frames: 1, gain: 1, pan: .infinity)
        XCTAssertEqual(invalidPanCBlock, invalidPanSwiftBlock)
        XCTAssertEqual(invalidPanCBlock.interleavedPCM, [1, 1])
    }

    func testCSoftwareMixerNoLoopModeStillMatchesOneShotBehavior() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let loop = MixerSampleLoop(mode: .none, startFrame: 1, endFrame: 3)

        let cBlock = cOneShotBlock(sample: sample, frames: 5, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [1, 0.5, -0.5, 0, 0]))
    }

    func testCSoftwareMixerForwardLoopRepeatsExclusiveLoopRegionAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)

        let cBlock = cOneShotBlock(sample: sample, frames: 9, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 9, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2, 3, 1, 2]))
    }

    func testCSoftwareMixerForwardLoopCrossesBoundaryInFirstRenderAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)

        let cBlock = cOneShotBlock(sample: sample, frames: 5, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1]))
    }

    func testCSoftwareMixerForwardLoopWorksAcrossSmallRenderCalls() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, loop: loop)

        let splitPCM = mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM +
            mixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2, 3, 1, 2]))
    }

    func testCSoftwareMixerPingPongLoopReversesDirectionAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)

        let cBlock = cOneShotBlock(sample: sample, frames: 9, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 9, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1, 2, 3, 2]))
    }

    func testCSoftwareMixerPingPongLoopCrossesBoundaryInFirstRenderAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)

        let cBlock = cOneShotBlock(sample: sample, frames: 5, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2]))
    }

    func testCSoftwareMixerPingPongLoopWorksAcrossSmallRenderCalls() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, loop: loop)

        let splitPCM = mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM +
            mixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1, 2, 3, 2]))
    }

    func testCSoftwareMixerLoopSplitRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loops = [
            MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4),
            MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        ]

        for loop in loops {
            let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            singleRenderMixer.addVoice(sample: sample, loop: loop)
            let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            splitRenderMixer.addVoice(sample: sample, loop: loop)

            let singleRender = singleRenderMixer.render(frames: 11)
            let splitRender = splitRenderMixer.render(frames: 4).interleavedPCM +
                splitRenderMixer.render(frames: 1).interleavedPCM +
                splitRenderMixer.render(frames: 6).interleavedPCM

            XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        }
    }

    func testCSoftwareMixerResetRestoresForwardLoopOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, loop: loop)

        let first = mixer.render(frames: 9)
        mixer.reset()
        let second = mixer.render(frames: 9)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, swiftOneShotBlock(sample: sample, frames: 9, loop: loop))
    }

    func testCSoftwareMixerResetRestoresPingPongLoopOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, loop: loop)

        let first = mixer.render(frames: 9)
        mixer.reset()
        let second = mixer.render(frames: 9)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, swiftOneShotBlock(sample: sample, frames: 9, loop: loop))
    }

    func testCSoftwareMixerClearVoicesReturnsLoopedMixerToSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )

        _ = mixer.render(frames: 4)
        mixer.clearVoices()
        let block = mixer.render(frames: 3)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testCSoftwareMixerGainAppliesToLoopedOutputAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, 2, 3])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)

        let cBlock = cOneShotBlock(sample: sample, frames: 5, gain: 0.5, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, gain: 0.5, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0.5, 1, 1.5, 1, 1.5]))
    }

    func testCSoftwareMixerPanAppliesToLoopedOutputAndMatchesSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, 0.25])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)

        let cBlock = cOneShotBlock(sample: sample, frames: 4, pan: -1, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 4, pan: -1, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, [1, 0, 0.5, 0, 0.25, 0, 0.5, 0])
    }

    func testCSoftwareMixerInvalidLoopDefinitionsFallBackToOneShotPlaybackLikeSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2])
        let invalidLoops = [
            MixerSampleLoop(mode: .forward, startFrame: -1, endFrame: 2),
            MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4),
            MixerSampleLoop(mode: .forward, startFrame: 2, endFrame: 2),
            MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 2)
        ]

        for loop in invalidLoops {
            let cBlock = cOneShotBlock(sample: sample, frames: 5, loop: loop)
            let swiftBlock = swiftOneShotBlock(sample: sample, frames: 5, loop: loop)

            XCTAssertEqual(cBlock, swiftBlock)
            XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 1, 2, 0, 0]))
        }
    }

    func testCSoftwareMixerLoopedEmptySampleRendersSilenceSafelyLikeSwiftReference() {
        let sample = MixerSampleBuffer(monoPCM: [])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 0, endFrame: 1)

        let cBlock = cOneShotBlock(sample: sample, frames: 3, loop: loop)
        let swiftBlock = swiftOneShotBlock(sample: sample, frames: 3, loop: loop)

        XCTAssertEqual(cBlock, swiftBlock)
        XCTAssertEqual(cBlock.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testCSoftwareMixerConstantVolumeEnvelopeProducesDeterministicOutput() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0.5)
        ])

        let block = cOneShotBlock(sample: sample, frames: 4, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0.5, 0.5, 0.5, 0.5]))
    }

    func testCSoftwareMixerDescendingVolumeEnvelopeReducesOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 1),
            MixerEnvelopePoint(positionFrame: 2, value: 0)
        ])

        let block = cOneShotBlock(sample: sample, frames: 3, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [1, 0.5, 0]))
    }

    func testCSoftwareMixerAscendingVolumeEnvelopeIncreasesOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 2, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 3, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0.5, 1]))
    }

    func testCSoftwareMixerVolumeEnvelopeInterpolatesAndClampsOutsidePoints() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1, 1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 2, value: 0),
            MixerEnvelopePoint(positionFrame: 4, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 6, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0, 0.5, 1, 1]))
    }

    func testCSoftwareMixerVolumeEnvelopeWorksAcrossPointBoundariesAndSplitRenders() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 1, value: 1),
            MixerEnvelopePoint(positionFrame: 3, value: 0)
        ])
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        singleRenderMixer.addVoice(sample: sample, volumeEnvelope: envelope)
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        splitRenderMixer.addVoice(sample: sample, volumeEnvelope: envelope)

        let singleRender = singleRenderMixer.render(frames: 4)
        let splitRender = splitRenderMixer.render(frames: 1).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 1).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        XCTAssertEqual(singleRender.interleavedPCM, stereoPCM(from: [0, 1, 0.5, 0]))
    }

    func testCSoftwareMixerResetRestoresVolumeEnvelopeOutputDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 3, value: 1)
        ])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: sample, volumeEnvelope: envelope)

        let first = mixer.render(frames: 4)
        _ = mixer.render(frames: 2)
        mixer.reset()
        let reset = mixer.render(frames: 4)

        XCTAssertEqual(first, reset)
    }

    func testCSoftwareMixerClearVoicesReturnsEnvelopeEnabledMixerToSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 1, 1]),
            volumeEnvelope: MixerEnvelope(points: [
                MixerEnvelopePoint(positionFrame: 0, value: 1),
                MixerEnvelopePoint(positionFrame: 2, value: 0)
            ])
        )

        _ = mixer.render(frames: 2)
        mixer.clearVoices()
        let block = mixer.render(frames: 3)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testCSoftwareMixerInvalidVolumeEnvelopeFallsBackToConstantGainSafely() {
        let sample = MixerSampleBuffer(monoPCM: [0.25, 0.5])
        let invalidEnvelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 0, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 2, volumeEnvelope: invalidEnvelope)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0.25, 0.5]))
    }

    func testCSoftwareMixerGainCombinesWithVolumeEnvelopeDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0.5)
        ])

        let block = cOneShotBlock(sample: sample, frames: 1, gain: 0.5, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.25])
    }

    func testCSoftwareMixerExistingPanStillAppliesWithEnvelopeEnabledVoice() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 2, pan: -1, volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 1, 0])
    }

    func testCSoftwareMixerPanningEnvelopeIsDeterministic() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1])
        let panEnvelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: -1),
            MixerEnvelopePoint(positionFrame: 2, value: 1)
        ])

        let block = cOneShotBlock(sample: sample, frames: 3, panEnvelope: panEnvelope)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 1, 1, 0, 1])
    }

    func testCSoftwareMixerScheduledRenderWithoutVoicesProducesSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0, 0]))
    }

    func testCSoftwareMixerScheduledFrameZeroMatchesImmediateOneShotRendering() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])

        let scheduled = cScheduledBlock(sample: sample, scheduledStartFrame: 0, frames: 5)
        let immediate = cOneShotBlock(sample: sample, frames: 5)

        XCTAssertEqual(scheduled, immediate)
        XCTAssertEqual(scheduled.interleavedPCM, stereoPCM(from: [1, 0.5, -0.5, 0, 0]))
    }

    func testCSoftwareMixerScheduledVoiceRendersSilenceBeforeStartAndBeginsExactlyOnFrame() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1])

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 3, frames: 6, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 1, 1, 0])
    }

    func testCSoftwareMixerScheduledVoiceContinuesAcrossSplitRenderCalls() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, 0.25])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: sample, scheduledStartFrame: 2))

        let splitPCM = mixer.render(frames: 1).interleavedPCM +
            mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitPCM, [0, 0, 1, 0.5, 0.25, 0])
    }

    func testCSoftwareMixerScheduledSplitRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        XCTAssertNotNil(singleRenderMixer.addScheduledVoice(sample: sample, scheduledStartFrame: 4))
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        XCTAssertNotNil(splitRenderMixer.addScheduledVoice(sample: sample, scheduledStartFrame: 4))

        let singleRender = singleRenderMixer.render(frames: 8)
        let splitRender = splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        XCTAssertEqual(singleRender.interleavedPCM, stereoPCM(from: [0, 0, 0, 0, 1, 0.5, -0.5, 0]))
    }

    func testCSoftwareMixerScheduledResetRestoresPlaybackDeterministically() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5])
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: sample, scheduledStartFrame: 2))

        let first = mixer.render(frames: 5)
        _ = mixer.render(frames: 3)
        mixer.reset()
        let reset = mixer.render(frames: 5)

        XCTAssertEqual(first, reset)
        XCTAssertEqual(reset.interleavedPCM, stereoPCM(from: [0, 0, 1, 0.5, 0]))
    }

    func testCSoftwareMixerClearScheduledVoicesReturnsToSilence() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5]), scheduledStartFrame: 1))

        mixer.clearScheduledVoices()
        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0, 0]))
    }

    func testCSoftwareMixerMultipleScheduledVoicesRenderAtNonOverlappingPositions() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1, 1]), scheduledStartFrame: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]), scheduledStartFrame: 4))

        let block = mixer.render(frames: 7)

        XCTAssertEqual(block.interleavedPCM, [0, 1, 1, 0, 0.5, 0.25, 0])
    }

    func testCSoftwareMixerOverlappingScheduledVoicesMixDeterministically() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1, 1, 1]), scheduledStartFrame: 1))
        XCTAssertNotNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]), scheduledStartFrame: 2))

        let block = mixer.render(frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 1, 1.5, 1.25, 0, 0])
    }

    func testCSoftwareMixerGainAppliesToScheduledVoice() {
        let sample = MixerSampleBuffer(monoPCM: [1, -1])

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 1, frames: 4, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1), gain: 0.5)

        XCTAssertEqual(block.interleavedPCM, [0, 0.5, -0.5, 0])
    }

    func testCSoftwareMixerPanAppliesToScheduledVoice() {
        let sample = MixerSampleBuffer(monoPCM: [1])

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 1, frames: 3, pan: -1)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 1, 0, 0, 0])
    }

    func testCSoftwareMixerVolumeEnvelopeAppliesFromScheduledVoiceStart() {
        let sample = MixerSampleBuffer(monoPCM: [1, 1, 1])
        let envelope = MixerEnvelope(points: [
            MixerEnvelopePoint(positionFrame: 0, value: 0),
            MixerEnvelopePoint(positionFrame: 2, value: 1)
        ])

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 2, frames: 6, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1), volumeEnvelope: envelope)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0.5, 1, 0])
    }

    func testCSoftwareMixerForwardLoopVoiceCanBeScheduled() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3])
        let loop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 2, frames: 8, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1), loop: loop)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 1, 2, 1, 2, 1])
    }

    func testCSoftwareMixerPingPongLoopVoiceCanBeScheduled() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3])
        let loop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 3)

        let block = cScheduledBlock(sample: sample, scheduledStartFrame: 2, frames: 8, config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1), loop: loop)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 1, 2, 1, 2, 1])
    }

    func testCSoftwareMixerInvalidScheduledStartIsRejectedSafely() {
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))

        XCTAssertNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1]), scheduledStartFrame: -1))
        _ = mixer.render(frames: 2)
        XCTAssertNil(mixer.addScheduledVoice(sample: MixerSampleBuffer(monoPCM: [1]), scheduledStartFrame: 1))
        XCTAssertEqual(mixer.render(frames: 3).interleavedPCM, [0, 0, 0])
    }

    func testSyntheticTrackerTimingFramesPerTickUsesPlaybackTimingFormula() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 183, sampleRate: 44_100)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(timing.framesPerTick, 44_100 * (2.5 / 183.0), accuracy: 0.000001)
    }

    func testSyntheticTrackerTimingFramesPerRowUsesConfiguredSpeed() {
        let config = SyntheticTrackerTimingConfig(speed: 3, bpm: 250, sampleRate: 100)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(timing.framesPerTick, 1)
        XCTAssertEqual(timing.framesPerRow, 3)
    }

    func testSyntheticTrackerTimingMapsRowsAndTicksToAbsoluteFrames() {
        let timing = SyntheticTrackerTiming(config: SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100))

        XCTAssertEqual(timing.frameFor(row: 0, tick: 0), 0)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 0), 2)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 1), 3)
    }

    func testSyntheticTrackerTimingUsesDeterministicFloorRoundingForFractionalFrames() {
        let timing = SyntheticTrackerTiming(config: SyntheticTrackerTimingConfig(speed: 2, bpm: 183, sampleRate: 44_100))

        XCTAssertEqual(timing.frameFor(row: 1, tick: 0), 1_204)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 1), 1_807)
    }

    func testSyntheticTrackerTimingInvalidBPMClampsSafely() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 0, sampleRate: 100)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(config.bpm, 1)
        XCTAssertEqual(timing.framesPerTick, 250)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 0), 500)
    }

    func testSyntheticTrackerTimingInvalidSpeedClampsSafely() {
        let config = SyntheticTrackerTimingConfig(speed: 0, bpm: 250, sampleRate: 100)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(config.speed, 1)
        XCTAssertEqual(timing.framesPerRow, 1)
        XCTAssertEqual(timing.frameFor(row: 1, tick: 1), 1)
    }

    func testSyntheticTrackerTimingInvalidSampleRateFallsBackSafely() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 125, sampleRate: .nan)
        let timing = SyntheticTrackerTiming(config: config)

        XCTAssertEqual(config.sampleRate, MixerRenderConfig.defaultSampleRate)
        XCTAssertEqual(timing.framesPerTick, 882)
    }

    func testSyntheticTrackerSchedulerFrameZeroRendersLikeImmediatePlayback() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5])
        let event = SyntheticTrackerEvent(row: 0, tick: 0, sample: sample)

        let scheduled = cSyntheticTrackerBlock(events: [event], frames: 4, timingConfig: config)
        let immediate = cOneShotBlock(
            sample: sample,
            frames: 4,
            config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1)
        )

        XCTAssertEqual(scheduled, immediate)
        XCTAssertEqual(scheduled.interleavedPCM, [1, 0.5, 0, 0])
    }

    func testSyntheticTrackerSchedulerLaterRowRendersSilenceBeforeEvent() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5])
        let event = SyntheticTrackerEvent(row: 2, tick: 0, sample: sample)

        let block = cSyntheticTrackerBlock(events: [event], frames: 7)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0, 1, 0.5, 0])
    }

    func testSyntheticTrackerSchedulerRowTickEventStartsAtComputedFrame() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticTrackerScheduler(config: config)
        let event = SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.75]))

        let block = cSyntheticTrackerBlock(events: [event], frames: 5, timingConfig: config)

        XCTAssertEqual(scheduler.frame(for: event), 3)
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0.75, 0])
    }

    func testSyntheticTrackerSchedulerMultipleEventsRenderAtDeterministicPositions() {
        let events = [
            SyntheticTrackerEvent(row: 0, tick: 0, sample: MixerSampleBuffer(monoPCM: [1])),
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.5])),
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.25]))
        ]

        let block = cSyntheticTrackerBlock(events: events, frames: 5)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 0.5, 0.25, 0])
    }

    func testSyntheticTrackerSchedulerOverlappingEventsMixDeterministically() {
        let events = [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 1, 1])),
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]))
        ]

        let block = cSyntheticTrackerBlock(events: events, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 1, 1.5, 1.25, 0])
    }

    func testSyntheticTrackerSchedulerSplitRendersMatchOneLargerRender() {
        let events = [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])),
            SyntheticTrackerEvent(row: 2, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.25]))
        ]
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticTrackerScheduler(config: config)
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        _ = scheduler.schedule(events, on: singleRenderMixer)
        _ = scheduler.schedule(events, on: splitRenderMixer)

        let singleRender = singleRenderMixer.render(frames: 6)
        let splitRender = splitRenderMixer.render(frames: 1).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
    }

    func testSyntheticTrackerSchedulerResetRestoresPlaybackDeterministically() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticTrackerScheduler(config: config)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        _ = scheduler.schedule(
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [1, 0.5])),
            on: mixer
        )

        let first = mixer.render(frames: 6)
        _ = mixer.render(frames: 3)
        mixer.reset()
        let reset = mixer.render(frames: 6)

        XCTAssertEqual(first, reset)
        XCTAssertEqual(reset.interleavedPCM, [0, 0, 0, 1, 0.5, 0])
    }

    func testSyntheticPatternEmptyPatternRendersSilence() {
        let pattern = SyntheticPattern(rowCount: 4)

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0, 0, 0])
    }

    func testSyntheticPatternFrameZeroEventMatchesImmediateScheduledPlayback() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let pattern = SyntheticPattern(rowCount: 1, events: [
            SyntheticTrackerEvent(row: 0, tick: 0, sample: sample)
        ])

        let patternBlock = cSyntheticPatternBlock(pattern: pattern, frames: 5)
        let immediateBlock = cScheduledBlock(
            sample: sample,
            scheduledStartFrame: 0,
            frames: 5,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1)
        )

        XCTAssertEqual(patternBlock, immediateBlock)
        XCTAssertEqual(patternBlock.interleavedPCM, [1, 0.5, -0.5, 0, 0])
    }

    func testSyntheticPatternLaterRowRendersSilenceBeforeEvent() {
        let pattern = SyntheticPattern(rowCount: 3, events: [
            SyntheticTrackerEvent(row: 2, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 0.5]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 7)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0, 1, 0.5, 0])
    }

    func testSyntheticPatternEventStartsAtSyntheticTimingFrame() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let timing = SyntheticTrackerTiming(config: config)
        let scheduler = SyntheticPatternScheduler(config: config)
        let event = SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.75]))
        let pattern = SyntheticPattern(rowCount: 2, events: [event])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 5, timingConfig: config)

        XCTAssertEqual(timing.frameFor(row: 1, tick: 1), 3)
        XCTAssertEqual(scheduler.frame(for: event), 3)
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0.75, 0])
    }

    func testSyntheticPatternMultipleRowsRenderDeterministically() {
        let pattern = SyntheticPattern(rowCount: 3, events: [
            SyntheticTrackerEvent(row: 0, tick: 0, sample: MixerSampleBuffer(monoPCM: [1])),
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.5])),
            SyntheticTrackerEvent(row: 2, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.25]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 0.5, 0, 0.25, 0])
    }

    func testSyntheticPatternMultipleEventsOnSameRowMixDeterministically() {
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 1])),
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 5)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 1.5, 1.25, 0])
    }

    func testSyntheticPatternDifferentTicksInSameRowRenderDeterministically() {
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 1, 1])),
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [0.5, 0.25]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 1, 1.5, 1.25, 0])
    }

    func testSyntheticPatternLoopedEventUsesCForwardLoopBehavior() {
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(
                row: 1,
                tick: 0,
                sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3]),
                loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
            )
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 8)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 1, 2, 1, 2, 1])
    }

    func testSyntheticPatternEnvelopeEventUsesCEnvelopeBehavior() {
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(
                row: 1,
                tick: 0,
                sample: MixerSampleBuffer(monoPCM: [1, 1, 1]),
                volumeEnvelope: MixerEnvelope(points: [
                    MixerEnvelopePoint(positionFrame: 0, value: 0),
                    MixerEnvelopePoint(positionFrame: 2, value: 1)
                ])
            )
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 6)

        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0.5, 1, 0])
    }

    func testSyntheticPatternSplitRendersMatchOneLargerRender() {
        let pattern = SyntheticPattern(rowCount: 3, events: [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])),
            SyntheticTrackerEvent(row: 2, tick: 0, sample: MixerSampleBuffer(monoPCM: [0.25]))
        ])
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticPatternScheduler(config: config)
        let singleRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        let splitRenderMixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        _ = scheduler.schedule(pattern, on: singleRenderMixer)
        _ = scheduler.schedule(pattern, on: splitRenderMixer)

        let singleRender = singleRenderMixer.render(frames: 6)
        let splitRender = splitRenderMixer.render(frames: 1).interleavedPCM +
            splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
    }

    func testSyntheticPatternResetRestoresPlaybackDeterministically() {
        let config = SyntheticTrackerTimingConfig(speed: 2, bpm: 250, sampleRate: 100)
        let scheduler = SyntheticPatternScheduler(config: config)
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: config.sampleRate, channelCount: 1))
        let pattern = SyntheticPattern(rowCount: 2, events: [
            SyntheticTrackerEvent(row: 1, tick: 1, sample: MixerSampleBuffer(monoPCM: [1, 0.5]))
        ])
        _ = scheduler.schedule(pattern, on: mixer)

        let first = mixer.render(frames: 6)
        _ = mixer.render(frames: 3)
        mixer.reset()
        let reset = mixer.render(frames: 6)

        XCTAssertEqual(first, reset)
        XCTAssertEqual(reset.interleavedPCM, [0, 0, 0, 1, 0.5, 0])
    }

    func testSyntheticPatternEmptyRowsAreSafeAndDeterministic() {
        let pattern = SyntheticPattern(rowCount: 4, events: [
            SyntheticTrackerEvent(row: 3, tick: 0, sample: MixerSampleBuffer(monoPCM: [1]))
        ])

        let first = cSyntheticPatternBlock(pattern: pattern, frames: 8)
        let second = cSyntheticPatternBlock(pattern: pattern, frames: 8)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.interleavedPCM, [0, 0, 0, 0, 0, 0, 1, 0])
    }

    func testSyntheticPatternInvalidRowCountClampsToEmptyPattern() {
        let pattern = SyntheticPattern(rowCount: -4, events: [
            SyntheticTrackerEvent(row: 0, tick: 0, sample: MixerSampleBuffer(monoPCM: [1]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 3)

        XCTAssertEqual(pattern.rowCount, 0)
        XCTAssertEqual(pattern.scheduledEvents, [])
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0])
    }

    func testSyntheticPatternEventsBeyondPatternRowCountAreIgnored() {
        let pattern = SyntheticPattern(rowCount: 1, events: [
            SyntheticTrackerEvent(row: 1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 4)

        XCTAssertEqual(pattern.scheduledEvents, [])
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0])
    }

    func testSyntheticPatternInvalidNegativeRowEventsAreIgnored() {
        let pattern = SyntheticPattern(rowCount: 1, events: [
            SyntheticTrackerEvent(row: -1, tick: 0, sample: MixerSampleBuffer(monoPCM: [1]))
        ])

        let block = cSyntheticPatternBlock(pattern: pattern, frames: 3)

        XCTAssertEqual(pattern.scheduledEvents, [])
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0])
    }

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
        let sample = makePlaybackSample(pcm: samplePCM, volume: 0.625, loopStart: 1, loopLength: 2, loopType: 1)
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
        XCTAssertEqual(event.loop, MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3))
        XCTAssertEqual(plan.diagnostics.emittedRowCount, 2)
        XCTAssertEqual(plan.diagnostics.emittedEventCount, 1)
        XCTAssertEqual(plan.diagnostics.rowMappings.map(\.syntheticRow), [0, 1])
        XCTAssertEqual(plan.diagnostics.eventMappings, [
            PlaybackSongSyntheticEventMapping(
                source: PlaybackPosition(orderIndex: 0, patternIndex: 2, rowIndex: 1),
                channelIndex: 0,
                note: 49,
                instrumentIndex: 1,
                sampleIndex: 0,
                syntheticRow: 1,
                eventIndex: 0
            )
        ])
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
        XCTAssertEqual(plan.diagnostics.ignoredCells.map(\.reason), [
            .emptyNote,
            .keyOff,
            .invalidNote,
            .missingInstrument,
            .noPlayableSample,
            .noPlayableSample
        ])
        XCTAssertEqual(plan.diagnostics.ignoredCells.map(\.channelIndex), [0, 1, 2, 3, 4, 5])
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

    func testPlaybackSongSyntheticAdapterIgnoresEffectsAndVolumeColumns() {
        let sample = makePlaybackSample(pcm: [1], volume: 0.5)
        let plainSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 125)
        )
        let decoratedSong = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1, volumeColumn: 0x20, effectType: 0x0F, effectParam: 0x03)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 125)
        )

        let plain = PlaybackSongSyntheticAdapter.adapt(plainSong, orderIndex: 0, sampleRate: 100)
        let decorated = PlaybackSongSyntheticAdapter.adapt(decoratedSong, orderIndex: 0, sampleRate: 100)

        XCTAssertEqual(decorated.timingConfig, SyntheticTrackerTimingConfig(speed: 4, bpm: 125, sampleRate: 100))
        XCTAssertEqual(decorated.pattern.events, plain.pattern.events)
        XCTAssertEqual(decorated.diagnostics.eventMappings, plain.diagnostics.eventMappings)
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

    func testSoftwareMixerInitializesWithDefaultRenderConfiguration() {
        let mixer = SoftwareMixer()

        XCTAssertEqual(mixer.config, MixerRenderConfig())
        XCTAssertEqual(mixer.config.sampleRate, 44_100)
        XCTAssertEqual(mixer.config.channelCount, 2)
        XCTAssertTrue(mixer.config.isInterleaved)
    }

    func testSoftwareMixerRenderReturnsRequestedFrameCount() {
        let mixer = SoftwareMixer()

        let block = mixer.render(frames: 16)

        XCTAssertEqual(block.frameCount, 16)
        XCTAssertEqual(block.sampleCount, 32)
        XCTAssertEqual(block.interleavedPCM.count, 16 * mixer.config.channelCount)
    }

    func testSoftwareMixerSilenceRenderingIsDeterministicAfterReset() {
        let mixer = SoftwareMixer()

        let first = mixer.render(frames: 8)
        mixer.reset()
        let second = mixer.render(frames: 8)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.interleavedPCM, Array(repeating: Float(0), count: 16))
    }

    func testSoftwareMixerOneSampleBufferRendersOneFrameThenSilence() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1]))

        let block = mixer.render(frames: 3)

        XCTAssertEqual(block.interleavedPCM, [1, 1, 0, 0, 0, 0])
        XCTAssertEqual(mixer.voices.first?.isActive, false)
    }

    func testSoftwareMixerMultiSampleBufferRendersSamplesInOrder() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5, -1]))

        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, [1, 1, 0.5, 0.5, -0.5, -0.5, -1, -1])
    }

    func testSoftwareMixerMonoOutputUsesMonoSampleValues() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 1))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]))

        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, [1, 0.5, -0.5, 0])
    }

    func testSoftwareMixerRendersSilenceAfterSampleEnds() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [0.25, 0.5, 0.25]))

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.25, 0.5, 0.5, 0.25, 0.25, 0, 0, 0, 0])
    }

    func testSoftwareMixerRepeatedRenderAfterResetRewindsVoicesDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [0.25, 0.5, 0.25]))

        let first = mixer.render(frames: 4)
        mixer.reset()
        let second = mixer.render(frames: 4)

        XCTAssertEqual(first, second)
    }

    func testSoftwareMixerClearVoicesReturnsToSilence() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5]))

        mixer.clearVoices()
        let block = mixer.render(frames: 2)

        XCTAssertTrue(mixer.voices.isEmpty)
        XCTAssertEqual(block.interleavedPCM, [0, 0, 0, 0])
    }

    func testSoftwareMixerGainIsAppliedDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, -1]), gain: 0.5)

        let block = mixer.render(frames: 2)

        XCTAssertEqual(block.interleavedPCM, [0.5, 0.5, -0.5, -0.5])
    }

    func testSoftwareMixerCenterMonoToStereoOutputIsDeterministic() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [0.25]), pan: 0)

        let block = mixer.render(frames: 1)

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.25])
    }

    func testSoftwareMixerPanBehaviorIsDeterministic() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1]), gain: 0.25, pan: -1)
        mixer.addVoice(sample: MixerSampleBuffer(monoPCM: [1]), gain: 0.5, pan: 1)

        let block = mixer.render(frames: 1)

        XCTAssertEqual(block.interleavedPCM, [0.25, 0.5])
    }

    func testSoftwareMixerMultipleSmallRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [1, 0.5, -0.5])
        let singleRenderMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        singleRenderMixer.addVoice(sample: sample)
        let splitRenderMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        splitRenderMixer.addVoice(sample: sample)

        let singleRender = singleRenderMixer.render(frames: 5)
        let splitRender = splitRenderMixer.render(frames: 2).interleavedPCM +
            splitRenderMixer.render(frames: 3).interleavedPCM

        XCTAssertEqual(splitRender, singleRender.interleavedPCM)
    }

    func testSoftwareMixerResetReturnsToInitialDeterministicState() {
        let mixer = SoftwareMixer()
        mixer.configure(sampleRate: 48_000, channelCount: 2)
        let configuredBlock = mixer.render(frames: 4)

        mixer.reset()
        let resetBlock = mixer.render(frames: 4)

        XCTAssertEqual(configuredBlock, resetBlock)
        XCTAssertTrue(mixer.voices.isEmpty)
    }

    func testSoftwareMixerHandlesZeroAndInvalidFrameRequestsSafely() {
        let mixer = SoftwareMixer()

        XCTAssertEqual(mixer.render(frames: 0), MixerRenderBlock(config: mixer.config, frameCount: 0, interleavedPCM: []))
        XCTAssertEqual(mixer.render(frames: -12), MixerRenderBlock(config: mixer.config, frameCount: 0, interleavedPCM: []))

        mixer.configure(sampleRate: -1, channelCount: 0)
        XCTAssertEqual(mixer.config, MixerRenderConfig())
        XCTAssertEqual(mixer.render(frames: 0).sampleCount, 0)
    }

    func testSoftwareMixerOfflineRendererInitializesWithExistingMixer() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 8_000, channelCount: 1))
        let renderer = SoftwareMixerOfflineRenderer(mixer: mixer, maximumFrameCount: 128)

        XCTAssertEqual(renderer.config.sampleRate, 8_000)
        XCTAssertEqual(renderer.config.channelCount, 1)
        XCTAssertEqual(renderer.maximumFrameCount, 128)
    }

    func testSoftwareMixerOfflineRendererCreatesMixerFromRenderConfiguration() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 48_000, channelCount: 2))

        XCTAssertEqual(renderer.config.sampleRate, 48_000)
        XCTAssertEqual(renderer.config.channelCount, 2)
        XCTAssertEqual(renderer.maximumFrameCount, OfflineRenderRequest.defaultMaximumFrameCount)
    }

    func testSoftwareMixerOfflineRendererRendersExplicitFrameCount() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let result = renderer.render(frames: 16)

        XCTAssertEqual(result.requestedFrameCount, 16)
        XCTAssertEqual(result.renderedFrameCount, 16)
        XCTAssertEqual(result.block.sampleCount, 32)
        XCTAssertFalse(result.wasFrameCountBounded)
    }

    func testSoftwareMixerOfflineRendererConvertsDurationToFramesDeterministically() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let result = renderer.render(durationSeconds: 0.125)

        XCTAssertEqual(result.requestedFrameCount, 125)
        XCTAssertEqual(result.renderedFrameCount, 125)
        XCTAssertEqual(result.block.sampleCount, 250)
    }

    func testSoftwareMixerOfflineRendererReturnsEmptyBlocksForZeroRequests() {
        let renderer = SoftwareMixerOfflineRenderer()

        XCTAssertEqual(renderer.render(frames: 0).block, MixerRenderBlock(config: renderer.config, frameCount: 0, interleavedPCM: []))
        XCTAssertEqual(renderer.render(durationSeconds: 0).block, MixerRenderBlock(config: renderer.config, frameCount: 0, interleavedPCM: []))
    }

    func testSoftwareMixerOfflineRendererHandlesInvalidRequestsSafely() {
        let renderer = SoftwareMixerOfflineRenderer()

        XCTAssertEqual(renderer.render(frames: -64).renderedFrameCount, 0)
        XCTAssertEqual(renderer.render(durationSeconds: -0.5).renderedFrameCount, 0)
        XCTAssertEqual(renderer.render(durationSeconds: .nan).renderedFrameCount, 0)
    }

    func testSoftwareMixerOfflineRendererBoundsOversizedRequests() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2), maximumFrameCount: 10)

        let result = renderer.render(frames: 12)

        XCTAssertEqual(result.requestedFrameCount, 12)
        XCTAssertEqual(result.renderedFrameCount, 10)
        XCTAssertEqual(result.maximumFrameCount, 10)
        XCTAssertTrue(result.wasFrameCountBounded)
        XCTAssertEqual(result.block.sampleCount, 20)
    }

    func testSoftwareMixerOfflineRendererAppliesRequestConfigurationWithinRendererLimit() {
        let renderer = SoftwareMixerOfflineRenderer(maximumFrameCount: 10)
        let request = OfflineRenderRequest(
            config: MixerRenderConfig(sampleRate: 2_000, channelCount: 1),
            frames: 12,
            maximumFrameCount: 20
        )

        let result = renderer.render(request)

        XCTAssertEqual(renderer.config.sampleRate, 2_000)
        XCTAssertEqual(renderer.config.channelCount, 1)
        XCTAssertEqual(result.renderedFrameCount, 10)
        XCTAssertEqual(result.maximumFrameCount, 10)
        XCTAssertTrue(result.wasFrameCountBounded)
    }

    func testSoftwareMixerOfflineRendererRepeatedRenderAfterResetIsDeterministic() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let first = renderer.render(frames: 8)
        renderer.reset()
        let second = renderer.render(frames: 8)

        XCTAssertEqual(first, second)
    }

    func testSoftwareMixerOfflineRendererRendersSilenceWhenNoVoicesAreLoaded() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))

        let result = renderer.render(frames: 4)

        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 8))
    }

    func testSoftwareMixerOfflineRendererRendersSyntheticOneShotVoice() {
        let renderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        renderer.addVoice(sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]), gain: 0.5)

        let result = renderer.render(frames: 5)

        XCTAssertEqual(result.renderedFrameCount, 5)
        XCTAssertEqual(result.block.interleavedPCM, [0.5, 0.5, 0.25, 0.25, -0.25, -0.25, 0, 0, 0, 0])
    }

    func testSoftwareMixerNoLoopModeStillMatchesOneShotBehavior() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]),
            loop: MixerSampleLoop(mode: .none, startFrame: 1, endFrame: 3)
        )

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [1, 0.5, -0.5, 0, 0]))
    }

    func testSoftwareMixerForwardLoopRepeatsExclusiveLoopRegion() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        let block = mixer.render(frames: 9)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2, 3, 1, 2]))
    }

    func testSoftwareMixerForwardLoopCrossesBoundaryInFirstRender() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1]))
    }

    func testSoftwareMixerForwardLoopWorksAcrossSmallRenderCalls() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        let splitPCM = mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM +
            mixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2, 3, 1, 2]))
    }

    func testSoftwareMixerPingPongLoopReversesDirectionDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let block = mixer.render(frames: 9)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1, 2, 3, 2]))
    }

    func testSoftwareMixerPingPongLoopCrossesBoundaryInFirstRender() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2]))
    }

    func testSoftwareMixerPingPongLoopWorksAcrossSmallRenderCalls() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let splitPCM = mixer.render(frames: 2).interleavedPCM +
            mixer.render(frames: 3).interleavedPCM +
            mixer.render(frames: 4).interleavedPCM

        XCTAssertEqual(splitPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1, 2, 3, 2]))
    }

    func testSoftwareMixerLoopSplitRendersMatchOneLargerRender() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4])
        let forwardLoop = MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        let pingPongLoop = MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)

        for loop in [forwardLoop, pingPongLoop] {
            let singleRenderMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            singleRenderMixer.addVoice(sample: sample, loop: loop)
            let splitRenderMixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            splitRenderMixer.addVoice(sample: sample, loop: loop)

            let singleRender = singleRenderMixer.render(frames: 11)
            let splitRender = splitRenderMixer.render(frames: 4).interleavedPCM +
                splitRenderMixer.render(frames: 1).interleavedPCM +
                splitRenderMixer.render(frames: 6).interleavedPCM

            XCTAssertEqual(splitRender, singleRender.interleavedPCM)
        }
    }

    func testSoftwareMixerResetRestoresForwardLoopOutputDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )

        let first = mixer.render(frames: 9)
        mixer.reset()
        let second = mixer.render(frames: 9)

        XCTAssertEqual(first, second)
    }

    func testSoftwareMixerResetRestoresPingPongLoopOutputDeterministically() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let first = mixer.render(frames: 9)
        mixer.reset()
        let second = mixer.render(frames: 9)

        XCTAssertEqual(first, second)
    }

    func testSoftwareMixerClearVoicesReturnsLoopedMixerToSilence() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 0.5, -0.5]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )

        _ = mixer.render(frames: 4)
        mixer.clearVoices()
        let block = mixer.render(frames: 3)

        XCTAssertTrue(mixer.voices.isEmpty)
        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testSoftwareMixerGainAppliesToLoopedOutput() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 2, 3]),
            gain: 0.5,
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )

        let block = mixer.render(frames: 5)

        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0.5, 1, 1.5, 1, 1.5]))
    }

    func testSoftwareMixerPanAppliesToLoopedOutput() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [1, 0.5, 0.25]),
            pan: -1,
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 3)
        )

        let block = mixer.render(frames: 4)

        XCTAssertEqual(block.interleavedPCM, [1, 0, 0.5, 0, 0.25, 0, 0.5, 0])
    }

    func testSoftwareMixerInvalidLoopDefinitionsFallBackToOneShotPlayback() {
        let sample = MixerSampleBuffer(monoPCM: [0, 1, 2])
        let invalidLoops = [
            MixerSampleLoop(mode: .forward, startFrame: -1, endFrame: 2),
            MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4),
            MixerSampleLoop(mode: .forward, startFrame: 2, endFrame: 2),
            MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 2)
        ]

        for loop in invalidLoops {
            let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
            mixer.addVoice(sample: sample, loop: loop)

            let block = mixer.render(frames: 5)

            XCTAssertEqual(mixer.voices.first?.loop, MixerSampleLoop.none)
            XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 1, 2, 0, 0]))
        }
    }

    func testSoftwareMixerLoopedEmptySampleRendersSilenceSafely() {
        let mixer = SoftwareMixer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: []),
            loop: MixerSampleLoop(mode: .forward, startFrame: 0, endFrame: 1)
        )

        let block = mixer.render(frames: 3)

        XCTAssertEqual(mixer.voices.first?.loop, MixerSampleLoop.none)
        XCTAssertEqual(block.interleavedPCM, stereoPCM(from: [0, 0, 0]))
    }

    func testSoftwareMixerOfflineRendererRendersSyntheticLoopedVoices() {
        let forwardRenderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        forwardRenderer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .forward, startFrame: 1, endFrame: 4)
        )
        let pingPongRenderer = SoftwareMixerOfflineRenderer(config: MixerRenderConfig(sampleRate: 1_000, channelCount: 2))
        pingPongRenderer.addVoice(
            sample: MixerSampleBuffer(monoPCM: [0, 1, 2, 3, 4]),
            loop: MixerSampleLoop(mode: .pingPong, startFrame: 1, endFrame: 4)
        )

        let forward = forwardRenderer.render(frames: 6)
        let pingPong = pingPongRenderer.render(frames: 6)

        XCTAssertEqual(forward.block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 1, 2]))
        XCTAssertEqual(pingPong.block.interleavedPCM, stereoPCM(from: [0, 1, 2, 3, 2, 1]))
    }

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
            pingPongLoopApplied: false,
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
        XCTAssertEqual(object["startedFromDebugSeek"] as? Bool, false)
        XCTAssertTrue(object["requestedStartOrder"] is NSNull)
        XCTAssertTrue(object["actualStartOrder"] is NSNull)
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
        XCTAssertEqual(object["pingPongLoopApplied"] as? Bool, false)
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

    func testPlaybackDebugLaunchConfigurationParsesEnvironment() {
        let configuration = PlaybackDebugLaunchConfiguration.parse(environment: [
            PlaybackDebugLaunchConfiguration.startOrderEnvironmentKey: "30",
            PlaybackDebugLaunchConfiguration.startRowEnvironmentKey: "4",
            PlaybackDebugLaunchConfiguration.startTickEnvironmentKey: "2",
            PlaybackDebugLaunchConfiguration.autoplayEnvironmentKey: "1",
            PlaybackDebugLaunchConfiguration.stopAfterSecondsEnvironmentKey: "10.5"
        ])

        XCTAssertEqual(configuration.startRequest?.requestedOrderIndex, 30)
        XCTAssertEqual(configuration.startRequest?.requestedRowIndex, 4)
        XCTAssertEqual(configuration.startRequest?.requestedTickInRow, 2)
        XCTAssertTrue(configuration.autoplay)
        XCTAssertEqual(configuration.stopAfterSeconds, 10.5)
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
        XCTAssertEqual(event?.startedFromDebugSeek, false)
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
    func testPlaybackEngineStartsFromDebugOrderRowAndAnnotatesTrace() {
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput(), traceWriter: traceWriter)
        engine.load(song: makePlaybackSong(orderPatternIndices: [2, 5], patternRowCounts: [2: 2, 5: 8]))

        engine.play(
            from: nil,
            debugStart: PlaybackDebugStartRequest(orderIndex: 1, rowIndex: 3)
        )

        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 3))
        let timingEvent = traceWriter.events.first { $0.decision == .observed && $0.decisionReason == "row_timing_before_effects" }
        XCTAssertEqual(timingEvent?.startedFromDebugSeek, true)
        XCTAssertEqual(timingEvent?.requestedStartOrder, 1)
        XCTAssertNil(timingEvent?.requestedStartPattern)
        XCTAssertEqual(timingEvent?.requestedStartRow, 3)
        XCTAssertNil(timingEvent?.requestedStartTick)
        XCTAssertEqual(timingEvent?.actualStartOrder, 1)
        XCTAssertEqual(timingEvent?.actualStartPattern, 5)
        XCTAssertEqual(timingEvent?.actualStartRow, 3)
        XCTAssertEqual(timingEvent?.actualStartTick, 0)
    }

    @MainActor
    func testPlaybackEngineDebugSeekCanResolvePatternIndexWithoutAutoplay() {
        let engine = PlaybackEngine(audioEngine: TestPlaybackAudioOutput())
        engine.load(song: makePlaybackSong(orderPatternIndices: [2, 5, 2], patternRowCounts: [2: 4, 5: 8]))
        var positions = [PlaybackPosition]()
        engine.positionDidChange = { positions.append($0) }

        let position = engine.seek(
            to: PlaybackDebugStartRequest(patternIndex: 5, rowIndex: 6),
            autoplay: false
        )

        XCTAssertEqual(position, PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 6))
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 6))
        XCTAssertEqual(engine.state.mode, .stopped)
        XCTAssertEqual(positions, [PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 6)])
    }

    @MainActor
    func testPlaybackEngineDebugSeekWhilePlayingResetsStateAndCanStartAtTick() {
        let audioOutput = TestPlaybackAudioOutput()
        let traceWriter = TestPlaybackTraceWriter()
        let engine = PlaybackEngine(audioEngine: audioOutput, traceWriter: traceWriter)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [0.25], volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 8_363)
        engine.load(song: makePlaybackSong(
            orderPatternIndices: [2, 5],
            patternRowsByIndex: [
                2: [makePlaybackRow(index: 0, note: 49, instrument: 1)],
                5: [makePlaybackRow(index: 0, note: 53, instrument: 1, effectType: 0x0E, effectParam: 0xC2)]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 4, bpm: 125)
        ))

        engine.play(from: nil)
        _ = engine.seek(
            to: PlaybackDebugStartRequest(orderIndex: 1, rowIndex: 0, tickInRow: 2),
            autoplay: true
        )

        XCTAssertEqual(audioOutput.stopAllCount, 1)
        XCTAssertEqual(engine.currentPosition, PlaybackPosition(orderIndex: 1, patternIndex: 5, rowIndex: 0))
        XCTAssertTrue(audioOutput.stoppedChannels.contains(0))
        let debugTickEvent = traceWriter.events.last { $0.startedFromDebugSeek && $0.tickInRow == 2 }
        XCTAssertEqual(debugTickEvent?.requestedStartOrder, 1)
        XCTAssertEqual(debugTickEvent?.requestedStartRow, 0)
        XCTAssertEqual(debugTickEvent?.requestedStartTick, 2)
        XCTAssertEqual(debugTickEvent?.actualStartOrder, 1)
        XCTAssertEqual(debugTickEvent?.actualStartPattern, 5)
        XCTAssertEqual(debugTickEvent?.actualStartRow, 0)
        XCTAssertEqual(debugTickEvent?.actualStartTick, 2)
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

    func testPlaybackSampleLoopRegionEnablesPingPongLoops() {
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

        XCTAssertEqual(sample.loopRegion, PlaybackSampleLoopRegion(isEnabled: true, startFrame: 100, endFrame: 400, lengthFrames: 300, loopType: 2, loopTypeName: "ping_pong"))
        XCTAssertTrue(sample.loopRegion.pingPongLoopApplied)
    }

    func testPingPongLoopFrameConstructionBuildsForwardThenReverseInterior() {
        let frameIndices = AudioSampleLoopFrameBuilder.pingPongFrameIndices(for: 2..<6, sampleFrameCount: 8)

        XCTAssertEqual(frameIndices, [2, 3, 4, 5, 4, 3])
    }

    func testPingPongLoopFrameConstructionRejectsInvalidBounds() {
        XCTAssertEqual(AudioSampleLoopFrameBuilder.pingPongFrameIndices(for: 6..<6, sampleFrameCount: 8), [])
        XCTAssertEqual(AudioSampleLoopFrameBuilder.pingPongFrameIndices(for: 6..<9, sampleFrameCount: 8), [])
        XCTAssertEqual(AudioSampleLoopFrameBuilder.pingPongFrameIndices(for: -1..<3, sampleFrameCount: 8), [])
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
        XCTAssertEqual(plan.loopMode, .forward)
        XCTAssertTrue(plan.isLooped)
        XCTAssertFalse(plan.usesPingPongLoop)
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
        XCTAssertEqual(plan.loopMode, .forward)
        XCTAssertTrue(plan.isLooped)
    }

    func testAudioSamplePlaybackPlannerSchedulesPingPongLoopAfterIntro() throws {
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
            loopType: 2
        )

        let plan = try XCTUnwrap(AudioSamplePlaybackPlanner.plan(for: sample, sampleStartOffset: 64))

        XCTAssertEqual(plan.introRange, 64..<200)
        XCTAssertEqual(plan.loopRange, 200..<500)
        XCTAssertEqual(plan.loopMode, .pingPong)
        XCTAssertTrue(plan.isLooped)
        XCTAssertTrue(plan.usesPingPongLoop)
    }

    func testAudioSamplePlaybackPlannerClampsInvalidPingPongBoundsSafely() throws {
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
            loopLength: 300,
            loopType: 2
        )

        let plan = try XCTUnwrap(AudioSamplePlaybackPlanner.plan(for: sample, sampleStartOffset: 64))

        XCTAssertEqual(sample.loopRegion, PlaybackSampleLoopRegion(isEnabled: false, startFrame: 1_000, endFrame: 1_000, lengthFrames: 0, loopType: 2, loopTypeName: "ping_pong"))
        XCTAssertEqual(plan.introRange, 64..<1_000)
        XCTAssertNil(plan.loopRange)
        XCTAssertNil(plan.loopMode)
        XCTAssertFalse(plan.isLooped)
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
