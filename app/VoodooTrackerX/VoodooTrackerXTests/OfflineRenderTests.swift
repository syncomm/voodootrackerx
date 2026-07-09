import AppKit
import AudioToolbox
import XCTest

final class OfflineRenderTests: XCTestCase {
    func testPlaybackSongOfflineRendererArpeggioWindowedRenderRemainsDeterministic() {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x00, effectParam: 0x37),
                makePlaybackRow(index: 2),
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [makeRampPlaybackSample(frameCount: 600, baseSampleRate: 100)])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 18
        )
        let renderer = PlaybackSongOfflineRenderer()

        let single = renderer.render(request)
        let firstWindowed = renderer.renderWindowed(request, windowRows: 1)
        let secondWindowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertFloatArrayEqual(firstWindowed.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertEqual(secondWindowed.block, firstWindowed.block)
        XCTAssertEqual(firstWindowed.diagnostics.arpeggioEffectCount, 1)
        XCTAssertEqual(firstWindowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 2)
    }

    func testPlaybackSongOfflineRendererReturnsSilenceAndDiagnosticsForEmptyAdaptedSegment() {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0)]]
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        )

        let result = PlaybackSongOfflineRenderer().render(request)

        XCTAssertEqual(result.block.interleavedPCM, [0, 0, 0, 0])
        XCTAssertEqual(result.diagnostics.syntheticRowCount, 1)
        XCTAssertEqual(result.diagnostics.emittedEventCount, 0)
        XCTAssertEqual(result.diagnostics.ignoredCellCount, 1)
        XCTAssertEqual(result.diagnostics.ignoredCells.map(\.reason), [.emptyNote])
    }

    func testPlaybackSongOfflineRendererRendersBasicTriggerAndSourceDiagnostics() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5], volume: 0.5, loopStart: 0, loopLength: 0, loopType: 0)
        let row = PlaybackRow(index: 3, cells: [
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        ])
        let song = makePlaybackSong(
            orderPatternIndices: [7],
            patternRowsByIndex: [7: [row]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        )

        let result = PlaybackSongOfflineRenderer().render(request)
        let event = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(result.block.interleavedPCM, [0.5, 0.25, 0])
        XCTAssertEqual(result.scheduledVoiceIndices, [0])
        XCTAssertEqual(result.diagnostics.adaptedOrders.map(\.requestedOrderIndex), [0])
        XCTAssertEqual(event.source.patternIndex, 7)
        XCTAssertEqual(event.source.rowIndex, 3)
        XCTAssertEqual(event.channelIndex, 0)
        XCTAssertEqual(event.syntheticRow, 0)
        XCTAssertEqual(event.syntheticTick, 0)
        XCTAssertEqual(event.instrumentIndex, 1)
        XCTAssertEqual(event.sampleIndex, 0)
        XCTAssertEqual(event.loopMode, .none)
        XCTAssertEqual(result.diagnostics.emittedRowCount, 1)
        XCTAssertEqual(result.diagnostics.emittedEventCount, 1)
    }

    func testPlaybackSongOfflineRendererBoundsExplicitFrameRequests() {
        let sample = makePlaybackSample(pcm: [1, 1, 1, 1])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let renderer = PlaybackSongOfflineRenderer(maximumFrameCount: 3)
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5,
            maximumFrameCount: 10
        )

        let result = renderer.render(request)

        XCTAssertEqual(result.requestedFrameCount, 5)
        XCTAssertEqual(result.renderedFrameCount, 3)
        XCTAssertEqual(result.maximumFrameCount, 3)
        XCTAssertTrue(result.wasFrameCountBounded)
        XCTAssertEqual(result.block.interleavedPCM, [1, 1, 1])
    }

    func testPlaybackSongOfflineRendererSchedulesDenseRenderAbovePreviousCapacity() throws {
        let sample = makePlaybackSample(pcm: [1])
        let row = PlaybackRow(index: 0, cells: (0..<33).map { _ in
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        })
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [row]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        ))

        XCTAssertEqual(result.diagnostics.eventCoverage.normalNoteCells, 33)
        XCTAssertEqual(result.diagnostics.eventCoverage.scheduledNoteEvents, 33)
        XCTAssertEqual(result.diagnostics.eventCoverage.cMixerVoiceCapacityLimitCount, 0)
        XCTAssertEqual(result.scheduledVoiceIndices.compactMap { $0 }.count, 33)
        XCTAssertEqual(result.scheduledVoiceIndices.filter { $0 == nil }.count, 0)
    }

    func testPlaybackSongOfflineRendererReportsCMixerVoiceCapacityRejections() throws {
        let sample = makePlaybackSample(pcm: [1])
        let attemptedVoiceCount = CSoftwareMixer.maximumScheduledVoiceCount + 1
        let row = PlaybackRow(index: 0, cells: (0..<attemptedVoiceCount).map { _ in
            PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
        })
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [row]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        ))

        XCTAssertEqual(result.diagnostics.eventCoverage.normalNoteCells, attemptedVoiceCount)
        XCTAssertEqual(result.diagnostics.eventCoverage.scheduledNoteEvents, attemptedVoiceCount)
        XCTAssertEqual(result.diagnostics.eventCoverage.cMixerVoiceCapacityLimitCount, 1)
        XCTAssertTrue(result.diagnostics.eventCoverage.skipReasonCounts.contains { item in
            item.reason == .cMixerVoiceCapacityLimit && item.count == 1
        })
        XCTAssertEqual(result.scheduledVoiceIndices.compactMap { $0 }.count, CSoftwareMixer.maximumScheduledVoiceCount)
        XCTAssertEqual(result.scheduledVoiceIndices.filter { $0 == nil }.count, 1)
        XCTAssertEqual(result.scheduledVoiceRejectionReasons.filter { $0 == .scheduledVoiceCapacity }.count, 1)
    }

    func testPlaybackSongOfflineRendererWindowedSingleWindowMatchesNonWindowedRender() {
        let sample = makePlaybackSample(pcm: [1, 0.5, -0.5], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0),
                    makePlaybackRow(index: 1, note: 49, instrument: 1),
                    makePlaybackRow(index: 2)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        )
        let renderer = PlaybackSongOfflineRenderer()

        let nonWindowed = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 64)

        XCTAssertEqual(windowed.block, nonWindowed.block)
        XCTAssertEqual(windowed.scheduledVoiceAttempts.map(\.eventIndex), [0])
        XCTAssertEqual(windowed.windowedRenderSummary?.windowRows, 64)
        XCTAssertEqual(windowed.windowedRenderSummary?.windowCount, 1)
        XCTAssertEqual(windowed.windowedRenderSummary?.totalScheduledCapacityRejects, 0)
    }

    func testPlaybackSongOfflineRendererWindowedMatchesConcatenatedStreamingBlocksAcrossMultipleWindows() {
        let sample = makePlaybackSample(
            pcm: [0.25, -0.5, 0.75, -1],
            baseSampleRate: 100,
            loopStart: 0,
            loopLength: 4,
            loopType: 1
        )
        let rows = (0..<130).map { rowIndex in
            makePlaybackRow(
                index: rowIndex,
                note: rowIndex == 0 || rowIndex == 70 ? 49 : 0,
                instrument: rowIndex == 0 || rowIndex == 70 ? 1 : 0
            )
        }
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 130
        )
        let renderer = PlaybackSongOfflineRenderer()
        let accumulated = renderer.renderWindowed(request, windowRows: 64)
        var streamedBlocks = [MixerRenderBlock]()

        let streaming = renderer.renderWindowedStreaming(request, windowRows: 64) { completedWindow, totalWindows, diagnostic, block in
            XCTAssertEqual(completedWindow, streamedBlocks.count + 1)
            XCTAssertEqual(totalWindows, 3)
            XCTAssertEqual(diagnostic.renderedFrames, block.frameCount)
            streamedBlocks.append(block)
        }
        let streamedPCM = streamedBlocks.flatMap(\.interleavedPCM)

        XCTAssertEqual(streamedBlocks.map(\.frameCount), [64, 64, 2])
        XCTAssertTrue(streamedBlocks.allSatisfy { $0.config == accumulated.block.config })
        XCTAssertEqual(streamedPCM, accumulated.block.interleavedPCM)
        XCTAssertTrue(streamedPCM.dropFirst(64).contains { $0 != 0 })
        XCTAssertGreaterThan(accumulated.windowedRenderSummary?.totalBoundaryContinuations ?? 0, 0)
        XCTAssertEqual(streaming.request, accumulated.request)
        XCTAssertEqual(streaming.plan, accumulated.plan)
        XCTAssertEqual(streaming.renderedFrameCount, accumulated.renderedFrameCount)
        XCTAssertEqual(streaming.scheduledVoiceIndices, accumulated.scheduledVoiceIndices)
        XCTAssertEqual(streaming.scheduledVoiceRejectionReasons, accumulated.scheduledVoiceRejectionReasons)
        XCTAssertEqual(streaming.windowedRenderSummary, accumulated.windowedRenderSummary)
        XCTAssertEqual(streaming.sameChannelVoiceLifetime, accumulated.sameChannelVoiceLifetime)
    }

    func testPlaybackSongOfflineRendererPerformanceInstrumentationDoesNotChangePCM() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5, -0.5, 0.25], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1),
                makePlaybackRow(index: 2),
                makePlaybackRow(index: 3)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        )
        let renderer = PlaybackSongOfflineRenderer()

        let baseline = renderer.renderWindowed(request, windowRows: 1)
        let instrumented = renderer.renderWindowed(
            request,
            windowRows: 1,
            collectPerformanceDiagnostics: true
        )

        XCTAssertEqual(instrumented.block, baseline.block)
        XCTAssertEqual(instrumented.scheduledVoiceIndices, baseline.scheduledVoiceIndices)
        XCTAssertNil(baseline.performanceDiagnostics)
        XCTAssertNotNil(instrumented.performanceDiagnostics)
    }

    func testPlaybackSongOfflineRendererPerformanceInstrumentationReportsSamplePayloadUploads() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5, -0.5], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(
            request,
            windowRows: 64,
            collectPerformanceDiagnostics: true
        )
        let performance = try XCTUnwrap(result.performanceDiagnostics)

        XCTAssertEqual(performance.samplePayloadUploadCount, 1)
        XCTAssertEqual(performance.approximateSamplePayloadBytesCopied, 3 * MemoryLayout<Float>.size)
        XCTAssertEqual(performance.windows.count, 1)
        XCTAssertEqual(performance.windows.first?.samplePayloadUploadCount, 1)
    }

    func testPlaybackSongOfflineRendererPerformanceInstrumentationHandlesSilentWindowedRender() throws {
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0)]],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(
            request,
            windowRows: 64,
            collectPerformanceDiagnostics: true
        )
        let performance = try XCTUnwrap(result.performanceDiagnostics)

        XCTAssertEqual(result.block.interleavedPCM, [0])
        XCTAssertEqual(performance.totalFramesPlanned, 1)
        XCTAssertEqual(performance.totalFramesRendered, 1)
        XCTAssertEqual(performance.renderWindowCount, 1)
        XCTAssertEqual(performance.totalScheduledEvents, 0)
        XCTAssertEqual(performance.samplePayloadUploadCount, 0)
        XCTAssertEqual(performance.approximateSamplePayloadBytesCopied, 0)
        XCTAssertTrue(performance.windows.allSatisfy { $0.schedulingDurationSeconds >= 0 })
        XCTAssertTrue(performance.windows.allSatisfy { $0.cMixerRenderDurationSeconds >= 0 })
    }

    func testPlaybackSongOfflineRendererWindowedRenderReusesScheduledCapacityAcrossRows() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let notesPerRow = 100
        let rows = (0..<3).map { rowIndex in
            PlaybackRow(index: rowIndex, cells: (0..<notesPerRow).map { _ in
                PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
            })
        }
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        )
        let renderer = PlaybackSongOfflineRenderer()

        let allAtOnce = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)
        let summary = try XCTUnwrap(windowed.windowedRenderSummary)

        XCTAssertEqual(allAtOnce.diagnostics.eventCoverage.normalNoteCells, notesPerRow * rows.count)
        XCTAssertEqual(allAtOnce.scheduledVoiceRejectionReasons.filter { $0 == .scheduledVoiceCapacity }.count, 44)
        XCTAssertEqual(windowed.scheduledVoiceRejectionReasons.filter { $0 == .scheduledVoiceCapacity }.count, 0)
        XCTAssertEqual(windowed.diagnostics.eventCoverage.cMixerVoiceCapacityLimitCount, 0)
        XCTAssertEqual(summary.windowCount, 3)
        XCTAssertEqual(summary.totalScheduledEvents, notesPerRow * rows.count)
        XCTAssertEqual(summary.totalAcceptedScheduledEvents, notesPerRow * rows.count)
        XCTAssertEqual(summary.totalScheduledCapacityRejects, 0)
        XCTAssertEqual(summary.windows.map(\.scheduledEventCount), [100, 100, 100])
        XCTAssertEqual(summary.windows.map(\.acceptedScheduledEventCount), [100, 100, 100])
        XCTAssertEqual(summary.windows.map(\.scheduledCapacityRejectedCount), [0, 0, 0])
        XCTAssertGreaterThan(windowed.block.interleavedPCM.reduce(0, +), allAtOnce.block.interleavedPCM.reduce(0, +))
    }

    func testPlaybackSongOfflineRendererWindowedDiagnosticsAggregatePerWindowRejects() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let attemptedVoiceCount = CSoftwareMixer.maximumScheduledVoiceCount + 1
        let rows = [
            PlaybackRow(index: 0, cells: (0..<attemptedVoiceCount).map { _ in
                PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
            }),
            PlaybackRow(index: 1, cells: [
                PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
            ])
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: 1)
        let summary = try XCTUnwrap(result.windowedRenderSummary)

        XCTAssertEqual(summary.totalScheduledEvents, attemptedVoiceCount + 1)
        XCTAssertEqual(summary.totalScheduledCapacityRejects, 1)
        XCTAssertEqual(summary.firstWindowsWithRejects.map(\.windowIndex), [0])
        XCTAssertEqual(summary.windows.map(\.scheduledEventCount), [attemptedVoiceCount, 1])
        XCTAssertEqual(summary.windows.map(\.scheduledCapacityRejectedCount), [1, 0])
        XCTAssertEqual(result.diagnostics.eventCoverage.cMixerVoiceCapacityLimitCount, 1)
        XCTAssertTrue(result.diagnostics.eventCoverage.skipReasonCounts.contains { item in
            item.reason == .cMixerVoiceCapacityLimit && item.count == 1
        })
    }

    func testPlaybackSongOfflineRendererWindowedMultipleRunsAreDeterministic() {
        let sample = makePlaybackSample(pcm: [1, 0.5, -0.5], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, note: 49, instrument: 1),
                    makePlaybackRow(index: 1, note: 49, instrument: 1),
                    makePlaybackRow(index: 2, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        )
        let renderer = PlaybackSongOfflineRenderer()

        let first = renderer.renderWindowed(request, windowRows: 1)
        let second = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.windowedRenderSummary?.windowCount, 3)
    }

    func testPlaybackSongOfflineRendererWindowedShortVoicesDoNotCreateCarryover() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let rows = (0..<3).map { makePlaybackRow(index: $0, note: 49, instrument: 1) }
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: 1)
        let summary = try XCTUnwrap(result.windowedRenderSummary)

        XCTAssertEqual(result.block.interleavedPCM, [1, 1, 1])
        XCTAssertEqual(summary.totalCarriedVoices, 0)
        XCTAssertEqual(summary.totalBoundaryContinuations, 0)
        XCTAssertEqual(summary.totalDroppedAtWindowBoundaries, 0)
        XCTAssertFalse(summary.mayContainBoundaryCuts)
    }

    func testPlaybackSongOfflineRendererWindowedCarriesSustainedOneShotSamplePosition() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5, -0.5, 0.25], baseSampleRate: 100)
        let rows = [
            makePlaybackRow(index: 0, note: 49, instrument: 1),
            makePlaybackRow(index: 1),
            makePlaybackRow(index: 2),
            makePlaybackRow(index: 3)
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        )
        let renderer = PlaybackSongOfflineRenderer()

        let nonWindowed = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)
        let summary = try XCTUnwrap(windowed.windowedRenderSummary)

        XCTAssertEqual(windowed.block, nonWindowed.block)
        XCTAssertEqual(windowed.block.interleavedPCM, [1, 0.5, -0.5, 0.25])
        XCTAssertEqual(summary.totalCarriedVoices, 3)
        XCTAssertEqual(summary.totalBoundaryContinuations, 3)
        XCTAssertEqual(summary.totalDroppedAtWindowBoundaries, 0)
    }

    func testPlaybackSongOfflineRendererWindowedCarriesForwardLoopState() {
        let sample = makePlaybackSample(pcm: [0, 1, 2], baseSampleRate: 100, loopStart: 1, loopLength: 2, loopType: 1)
        let rows = [
            makePlaybackRow(index: 0, note: 49, instrument: 1),
            makePlaybackRow(index: 1),
            makePlaybackRow(index: 2),
            makePlaybackRow(index: 3),
            makePlaybackRow(index: 4)
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: 1)

        XCTAssertEqual(result.block.interleavedPCM, [0, 1, 2, 1, 2])
        XCTAssertEqual(result.windowedRenderSummary?.totalCarriedVoices, 4)
    }

    func testPlaybackSongOfflineRendererWindowedCarriesPingPongLoopDirection() {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3], baseSampleRate: 100, loopStart: 1, loopLength: 3, loopType: 2)
        let rows = (0..<7).map { rowIndex in
            rowIndex == 0
                ? makePlaybackRow(index: rowIndex, note: 49, instrument: 1)
                : makePlaybackRow(index: rowIndex)
        }
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 7
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: 1)

        XCTAssertEqual(result.block.interleavedPCM, [0, 1, 2, 3, 2, 1, 2])
        XCTAssertEqual(result.windowedRenderSummary?.totalCarriedVoices, 6)
    }

    func testPlaybackSongOfflineRendererWindowedCarriesEnvelopePosition() {
        let sample = makePlaybackSample(pcm: [1, 1], baseSampleRate: 100, loopStart: 0, loopLength: 2, loopType: 1)
        let envelope = makePlaybackVolumeEnvelope(
            points: [
                PlaybackEnvelopePoint(tick: 0, value: 64),
                PlaybackEnvelopePoint(tick: 4, value: 0)
            ]
        )
        let rows = (0..<5).map { rowIndex in
            rowIndex == 0
                ? makePlaybackRow(index: rowIndex, note: 49, instrument: 1)
                : makePlaybackRow(index: rowIndex)
        }
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: 1)

        XCTAssertPCMEqual(result.block.interleavedPCM, [1, 0.75, 0.5, 0.25, 0])
        XCTAssertEqual(result.windowedRenderSummary?.totalCarriedVoices, 4)
    }

    func testPlaybackSongOfflineRendererWindowedCarriesKeyOffReleaseAndFadeout() throws {
        let sample = makePlaybackSample(pcm: [1, 1], baseSampleRate: 100, loopStart: 0, loopLength: 2, loopType: 1)
        let envelope = PlaybackVolumeEnvelope(
            enabled: false,
            points: [],
            sustainPointIndex: nil,
            loopStartPointIndex: nil,
            loopEndPointIndex: nil,
            typeFlags: 0,
            fadeout: 32_768
        )
        let rows = [
            makePlaybackRow(index: 0, note: 49, instrument: 1),
            makePlaybackRow(index: 1),
            makePlaybackRow(index: 2, note: 97),
            makePlaybackRow(index: 3),
            makePlaybackRow(index: 4)
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope)],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 5
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: 1)
        let summary = try XCTUnwrap(result.windowedRenderSummary)

        XCTAssertPCMEqual(result.block.interleavedPCM, [1, 1, 1, 0.75, 0.5])
        XCTAssertGreaterThan(summary.totalReleasedVoiceCarryovers, 0)
        XCTAssertEqual(summary.totalDroppedAtWindowBoundaries, 0)
    }

    func testPlaybackSongOfflineRendererWindowedUsesAdapterVolumePanAndFxxStateAcrossWindows() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let rows = [
            makePlaybackRow(index: 0, volumeColumn: 0x20),
            makePlaybackRow(index: 1, note: 49, instrument: 1, volumeColumn: 0xCF),
            makePlaybackRow(index: 2, effectType: 0x0F, effectParam: 0x03),
            makePlaybackRow(index: 3),
            makePlaybackRow(index: 4, note: 49, instrument: 1)
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 22
        )
        let renderer = PlaybackSongOfflineRenderer()

        let nonWindowed = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)
        let firstEvent = try XCTUnwrap(windowed.diagnostics.eventMappings.first)

        XCTAssertEqual(windowed.block, nonWindowed.block)
        XCTAssertEqual(windowed.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6, 12, 18, 21])
        XCTAssertEqual(firstEvent.effectiveVolumeValue, 16)
        XCTAssertEqual(firstEvent.effectivePan, 1)
    }

    func testPlaybackSongOfflineRendererWindowedCarriesReplacementRampAtBoundary() {
        let firstSample = makePlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: [1, 1], baseSampleRate: 100, loopStart: 0, loopLength: 2, loopType: 1)
        let replacementSample = makePlaybackSample(instrumentIndex: 2, sampleIndex: 0, pcm: [0.25, 0.25], baseSampleRate: 100, loopStart: 0, loopLength: 2, loopType: 1)
        let rows = [
            makePlaybackRow(index: 0, note: 49, instrument: 1),
            makePlaybackRow(index: 1, note: 49, instrument: 2),
            makePlaybackRow(index: 2)
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [
                1: PlaybackInstrument(index: 1, samples: [firstSample]),
                2: PlaybackInstrument(index: 2, samples: [replacementSample])
            ],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: 1)

        XCTAssertEqual(result.block.interleavedPCM, [1, 1.21875, 1.1875])
        XCTAssertEqual(result.windowedRenderSummary?.totalBoundaryContinuations, 3)
        XCTAssertEqual(result.sameChannelVoiceLifetime.replacementRampFrameCount, 32)
        XCTAssertEqual(result.sameChannelVoiceLifetime.sameChannelActiveVoiceCount, 2)
        XCTAssertEqual(result.sameChannelVoiceLifetime.sameChannelReplacementStartCount, 1)
        XCTAssertEqual(result.sameChannelVoiceLifetime.sameChannelReplacementCompletionCount, 0)
        XCTAssertEqual(result.sameChannelVoiceLifetime.sameChannelVoiceOverlapFrames, 2)
        XCTAssertEqual(result.sameChannelVoiceLifetime.windowBoundaryPruneCount, 0)
        XCTAssertEqual(result.sameChannelVoiceLifetime.oldVoiceKeptReasonCounts["replacement_ramp_overlap"], 1)
    }

    func testPlaybackSongOfflineRendererWindowedDiagnosticsReportBoundaryDrops() throws {
        let sample = makePlaybackSample(pcm: [1, 1], baseSampleRate: 100, loopStart: 0, loopLength: 2, loopType: 1)
        let attemptedVoiceCount = CSoftwareMixer.maximumScheduledVoiceCount + 1
        let rows = [
            PlaybackRow(index: 0, cells: (0..<attemptedVoiceCount).map { _ in
                PlaybackCell(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0)
            }),
            makePlaybackRow(index: 1)
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 2
        )

        let result = PlaybackSongOfflineRenderer().renderWindowed(request, windowRows: 1)
        let summary = try XCTUnwrap(result.windowedRenderSummary)
        let secondWindow = try XCTUnwrap(summary.windows.last)

        XCTAssertEqual(secondWindow.boundaryContinuationCount, attemptedVoiceCount)
        XCTAssertEqual(secondWindow.carriedVoiceCount, CSoftwareMixer.maximumScheduledVoiceCount)
        XCTAssertEqual(secondWindow.droppedAtWindowBoundaryCount, 1)
        XCTAssertTrue(summary.mayContainBoundaryCuts)
        XCTAssertEqual(summary.totalDroppedAtWindowBoundaries, 1)
    }

    func testPlaybackSongOfflineRendererCanRenderByRowCount() {
        let sample = makePlaybackSample(pcm: [1, 0.5, -0.5, 0.25])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            rows: 2
        )

        let result = PlaybackSongOfflineRenderer().render(request)

        XCTAssertEqual(result.requestedFrameCount, 4)
        XCTAssertEqual(result.block.interleavedPCM, [1, 0.5, -0.5, 0.25])
    }

    func testPlaybackSongOfflineRendererRowCountUsesVariableFxxTiming() {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                    makePlaybackRow(index: 1),
                    makePlaybackRow(index: 2, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            rows: 3
        )

        let result = PlaybackSongOfflineRenderer().render(request)

        XCTAssertEqual(result.requestedFrameCount, 12)
        XCTAssertEqual(result.diagnostics.rowTiming.map(\.rowStartFrame), [0, 6, 9])
        XCTAssertEqual(result.block.interleavedPCM, Array(repeating: Float(0), count: 9) + [1, 0, 0])
    }

    func testPlaybackSongOfflineRendererSplitRendersMatchOneLargerRender() {
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
        let renderer = PlaybackSongOfflineRenderer()
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        )

        let single = renderer.render(request)
        let split = renderer.render(request, splitFrameCounts: [1, 2, 3])

        XCTAssertEqual(single.block.interleavedPCM, [0, 0, 1, 0.5, -0.5, 0])
        XCTAssertEqual(split.block, single.block)
        XCTAssertEqual(split.diagnostics, single.diagnostics)
    }

    func testPlaybackSongOfflineRendererPreparedSessionResetIsDeterministic() {
        let sample = makePlaybackSample(pcm: [1, 0.5, -0.5])
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        )
        let session = PlaybackSongOfflineRenderer().prepare(request)

        let first = session.render(frames: 6)
        _ = session.render(frames: 2)
        session.reset()
        let reset = session.render(frames: 6)

        XCTAssertEqual(first, reset)
    }

    func testPlaybackSongOfflineRendererCarriesLoopMetadataToCMixer() throws {
        let forwardSample = makePlaybackSample(pcm: [0, 1, 2, 3], loopStart: 1, loopLength: 2, loopType: 1)
        let pingPongSample = makePlaybackSample(pcm: [0, 1, 2, 3], loopStart: 1, loopLength: 3, loopType: 2)
        let renderer = PlaybackSongOfflineRenderer()

        let forward = renderer.render(PlaybackSongOfflineRenderRequest(
            song: makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [forwardSample])]
            ),
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let pingPong = renderer.render(PlaybackSongOfflineRenderRequest(
            song: makePlaybackSong(
                orderPatternIndices: [2],
                patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
                instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [pingPongSample])]
            ),
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 7
        ))

        XCTAssertEqual(forward.block.interleavedPCM, [0, 1, 2, 1, 2, 1])
        XCTAssertEqual(try XCTUnwrap(forward.diagnostics.eventMappings.first).loopMode, .forward)
        XCTAssertEqual(pingPong.block.interleavedPCM, [0, 1, 2, 3, 2, 1, 2])
        XCTAssertEqual(try XCTUnwrap(pingPong.diagnostics.eventMappings.first).loopMode, .pingPong)
    }

    func testPlaybackSongOfflineRendererForwardLoopWorksWithNonNeutralPitchStep() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3, 4], baseSampleRate: 100, loopStart: 1, loopLength: 3, loopType: 1)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 61, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )

        let result = PlaybackSongOfflineRenderer().render(PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        ))
        let mapping = try XCTUnwrap(result.diagnostics.eventMappings.first)

        XCTAssertEqual(mapping.playbackStep, 2, accuracy: 0.000000001)
        XCTAssertEqual(mapping.loopMode, .forward)
        XCTAssertEqual(result.block.interleavedPCM, [0, 2, 1, 3, 2, 1])
    }

    func testPlaybackSongOfflineRendererShortForwardLoopAmiga3xxWindowedRenderPreservesPhase() throws {
        let sample = makePlaybackSample(
            pcm: (0..<188).map { Float($0) / 187.0 },
            finetune: -39,
            baseSampleRate: 8_363,
            loopStart: 0,
            loopLength: 188,
            loopType: 1
        )
        let rows = [
            makePlaybackRow(index: 0, note: 49, instrument: 1),
            makePlaybackRow(index: 1, note: 51, instrument: 1, effectType: 0x03, effectParam: 0x0A),
            makePlaybackRow(index: 2),
            makePlaybackRow(index: 3),
            makePlaybackRow(index: 4),
            makePlaybackRow(index: 5),
        ]
        let song = makePlaybackSong(
            orderPatternIndices: [32],
            patternRowsByIndex: [32: rows],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 125),
            usesLinearFrequencyTable: false
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 48_000, channelCount: 1),
            frames: 33_600
        )
        let renderer = PlaybackSongOfflineRenderer()

        let single = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)
        let mapping = try XCTUnwrap(single.diagnostics.eventMappings.first)
        let tonePortamento = try XCTUnwrap(single.diagnostics.tonePortamentoEffects.first)

        XCTAssertFloatArrayEqual(windowed.block.interleavedPCM, single.block.interleavedPCM)
        XCTAssertEqual(mapping.loopMode, .forward)
        XCTAssertEqual(mapping.selectedSampleLength, 188)
        XCTAssertEqual(try XCTUnwrap(mapping.amigaPeriod), 6_972, accuracy: 0.000000001)
        XCTAssertEqual(mapping.playbackStep, 0.17113042646777588, accuracy: 0.000000000001)
        XCTAssertTrue(tonePortamento.applied)
        XCTAssertEqual(tonePortamento.activeEventIndex, 0)
        XCTAssertTrue(tonePortamento.sameCellNote)
        XCTAssertFalse(tonePortamento.samplePositionReset)
        XCTAssertFalse(tonePortamento.cMixerReceivesNewVoice)
        XCTAssertTrue(tonePortamento.cMixerReceivesOnlyStateUpdates)
        XCTAssertEqual(try XCTUnwrap(tonePortamento.targetAmigaPeriod), 6_212, accuracy: 0.000000001)
        XCTAssertEqual(tonePortamento.stepUpdates.map(\.syntheticTick), [1, 2, 3, 4, 5])
        XCTAssertEqual(tonePortamento.stepUpdates.map(\.scheduledFrame), [6_720, 7_680, 8_640, 9_600, 10_560])
        XCTAssertEqual(tonePortamento.stepUpdates.map { $0.amigaPeriodAfter ?? 0 }, [6_812, 6_652, 6_492, 6_332, 6_212])
        XCTAssertEqual(windowed.windowedRenderSummary?.totalDroppedAtWindowBoundaries, 0)
        XCTAssertGreaterThan(windowed.windowedRenderSummary?.totalCarriedTonePortamentoVoices ?? 0, 0)
    }

    func testPlaybackSongOfflineRendererWindowedAppliesECxCutToCarriedVoice() throws {
        let sample = makePlaybackSample(pcm: [1, 1], baseSampleRate: 100, loopStart: 0, loopLength: 2, loopType: 1)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0xC0),
                makePlaybackRow(index: 2)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 1, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 3
        )
        let renderer = PlaybackSongOfflineRenderer()

        let normal = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertEqual(normal.block.interleavedPCM, [1, 0, 0])
        XCTAssertEqual(windowed.block, normal.block)
        XCTAssertEqual(windowed.diagnostics.noteCutEffects.first?.scheduledFrame, 1)
        XCTAssertEqual(windowed.windowedRenderSummary?.totalBoundaryContinuations, 1)
        XCTAssertEqual(windowed.windowedRenderSummary?.totalDroppedAtWindowBoundaries, 0)
    }

    func testPlaybackSongOfflineRendererWindowedAppliesEDxDelayWithinWindow() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1, effectType: 0x0E, effectParam: 0xD2),
                makePlaybackRow(index: 1)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 3, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        )
        let renderer = PlaybackSongOfflineRenderer()

        let normal = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertEqual(normal.block.interleavedPCM, [0, 0, 1, 0])
        XCTAssertEqual(windowed.block, normal.block)
        XCTAssertEqual(windowed.diagnostics.noteDelayEffects.first?.status, .applied)
        XCTAssertEqual(windowed.diagnostics.noteDelayEffects.first?.delayedFrame, 2)
        XCTAssertEqual(windowed.windowedRenderSummary?.windowCount, 2)
    }

    func testPlaybackSongOfflineRendererWindowedAppliesE9xRetriggerToCarriedVoice() throws {
        let sample = makePlaybackSample(pcm: [1, 0.5], baseSampleRate: 100, loopStart: 0, loopLength: 2, loopType: 1)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [
                makePlaybackRow(index: 0, note: 49, instrument: 1),
                makePlaybackRow(index: 1, effectType: 0x0E, effectParam: 0x91)
            ]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 2, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 4
        )
        let renderer = PlaybackSongOfflineRenderer()

        let normal = renderer.render(request)
        let windowed = renderer.renderWindowed(request, windowRows: 1)

        XCTAssertPCMEqual(normal.block.interleavedPCM, [1, 0.5, 1, 1])
        XCTAssertEqual(windowed.block, normal.block)
        XCTAssertEqual(windowed.diagnostics.retriggerEffects.first?.status, .applied)
        XCTAssertEqual(windowed.diagnostics.retriggerEffects.first?.retriggerFrames, [3])
        XCTAssertEqual(windowed.windowedRenderSummary?.totalBoundaryContinuations, 1)
    }

    func testMixerWAVExporterWritesValidPCM16HeaderFields() throws {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 8_000, channelCount: 2),
            frameCount: 3,
            interleavedPCM: [0, 0.25, -0.25, 0.5, -0.5, 1]
        )

        let data = try MixerWAVExporter.pcm16WAVData(from: block)
        let wav = try parsePCM16WAV(data)

        XCTAssertEqual(wav.riffSize, 48)
        XCTAssertEqual(wav.sampleRate, 8_000)
        XCTAssertEqual(wav.channelCount, 2)
        XCTAssertEqual(wav.bitsPerSample, 16)
        XCTAssertEqual(wav.byteRate, 32_000)
        XCTAssertEqual(wav.blockAlign, 4)
        XCTAssertEqual(wav.dataSize, 12)
        XCTAssertEqual(wav.samples.count, 6)
    }

    func testMixerWAVExporterClampsAndEncodesPCM16Deterministically() throws {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 8,
            interleavedPCM: [-2, -1, -0.5, 0, 0.5, 1, 2, .nan]
        )

        let wav = try parsePCM16WAV(try MixerWAVExporter.pcm16WAVData(from: block))

        XCTAssertEqual(wav.samples, [
            Int16.min,
            Int16.min,
            -16_384,
            0,
            16_384,
            Int16.max,
            Int16.max,
            0
        ])
    }

    func testMixerWAVExporterDefaultPolicyMatchesPreviousPCM16Output() throws {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 5,
            interleavedPCM: [-1, -0.25, 0, 0.25, 1]
        )

        let defaultData = try MixerWAVExporter.pcm16WAVData(from: block)
        let explicitUnityData = try MixerWAVExporter.pcm16WAVData(from: block, exportPolicy: .unity)

        XCTAssertEqual(defaultData, explicitUnityData)
    }

    func testMixerWAVExporterAppliesGainBeforePCM16Conversion() throws {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 3,
            interleavedPCM: [1, -1, 0.5]
        )

        let wav = try parsePCM16WAV(try MixerWAVExporter.pcm16WAVData(
            from: block,
            exportPolicy: MixerWAVExportPolicy(gain: 0.5)
        ))

        XCTAssertEqual(wav.samples, [16_384, -16_384, 8_192])
    }

    func testMixerWAVExporterReportsHeadroomAndClippingDiagnostics() throws {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2),
            frameCount: 2,
            interleavedPCM: [1.5, -0.25, 0.5, -2]
        )

        let unity = MixerWAVExporter.diagnostics(for: block)
        let headroom = MixerWAVExporter.diagnostics(
            for: block,
            exportPolicy: MixerWAVExportPolicy(headroomDB: -6)
        )

        XCTAssertEqual(unity.policy.gain, 1)
        XCTAssertEqual(unity.preExportPeak, 2)
        XCTAssertEqual(unity.preExportPerChannelPeak, [1.5, 2])
        XCTAssertEqual(unity.preExportOverrangeSampleCount, 2)
        XCTAssertEqual(unity.pcm16ClippingSampleCount, 2)
        XCTAssertTrue(unity.clippingDetected)
        XCTAssertNotNil(unity.recommendation)
        XCTAssertEqual(headroom.policy.headroomDB, -6)
        XCTAssertEqual(headroom.policy.gain, Float(pow(10.0, -6.0 / 20.0)), accuracy: 0.000_001)
        XCTAssertEqual(headroom.postGainPeak, 2 * headroom.policy.gain, accuracy: 0.000_001)
        XCTAssertEqual(headroom.pcm16ClippingSampleCount, 1)
    }

    func testMixerWAVExporterGainCanEliminatePCM16ClippingForHotRenderBlock() {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 1),
            frameCount: 2,
            interleavedPCM: [1.5, -1.5]
        )

        let unity = MixerWAVExporter.diagnostics(for: block)
        let reduced = MixerWAVExporter.diagnostics(
            for: block,
            exportPolicy: MixerWAVExportPolicy(gain: 0.5)
        )

        XCTAssertEqual(unity.pcm16ClippingSampleCount, 2)
        XCTAssertEqual(reduced.pcm16ClippingSampleCount, 0)
        XCTAssertFalse(reduced.clippingDetected)
        XCTAssertTrue(reduced.preExportOverrangeDetected)
        XCTAssertEqual(reduced.postGainPeak, 0.75)
    }

    func testMixerWAVExporterHandlesEmptyRenderBlockSafely() throws {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 22_050, channelCount: 2),
            frameCount: 0,
            interleavedPCM: []
        )

        let data = try MixerWAVExporter.pcm16WAVData(from: block)
        let wav = try parsePCM16WAV(data)

        XCTAssertEqual(data.count, 44)
        XCTAssertEqual(wav.riffSize, 36)
        XCTAssertEqual(wav.sampleRate, 22_050)
        XCTAssertEqual(wav.channelCount, 2)
        XCTAssertEqual(wav.dataSize, 0)
        XCTAssertEqual(wav.samples, [])
    }

    func testMixerWAVExporterRejectsInvalidPCMShape() {
        let block = MixerRenderBlock(
            config: MixerRenderConfig(sampleRate: 44_100, channelCount: 2),
            frameCount: 2,
            interleavedPCM: [0, 0, 0]
        )

        XCTAssertThrowsError(try MixerWAVExporter.pcm16WAVData(from: block)) { error in
            XCTAssertEqual(error as? MixerWAVExportError, .invalidPCMShape(expectedSampleCount: 4, actualSampleCount: 3))
        }
    }

    func testPlaybackSongOfflineRendererExportsBoundedAdaptedRenderToWAV() throws {
        let sample = makePlaybackSample(pcm: [0, 0.5, -0.5, 1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [
                2: [
                    makePlaybackRow(index: 0, effectType: 0x0F, effectParam: 0x03),
                    makePlaybackRow(index: 1, note: 49, instrument: 1)
                ]
            ],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])],
            initialTiming: PlaybackTiming(speed: 6, bpm: 250)
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 2),
            frames: 9
        )

        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let outputURL = tempDirectory.appendingPathComponent("vtx-candidate.wav")
        let result = try PlaybackSongOfflineRenderer().exportWAV(request, to: outputURL)
        let wav = try parsePCM16WAV(Data(contentsOf: outputURL))

        XCTAssertEqual(result.renderedFrameCount, 9)
        XCTAssertEqual(result.diagnostics.emittedEventCount, 1)
        XCTAssertEqual(result.plan.pattern.events.first?.scheduledStartFrame, 6)
        XCTAssertEqual(wav.sampleRate, 100)
        XCTAssertEqual(wav.channelCount, 2)
        XCTAssertEqual(wav.bitsPerSample, 16)
        XCTAssertEqual(wav.dataSize, 36)
        XCTAssertEqual(
            Array(wav.samples.prefix(18)),
            Array(repeating: Int16(0), count: 14) + [16_384, 16_384, -16_384, -16_384]
        )
    }

    func testPlaybackSongOfflineRendererExportWAVAppliesGainPolicy() throws {
        let sample = makePlaybackSample(pcm: [1], baseSampleRate: 100)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 1
        )
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let outputURL = tempDirectory.appendingPathComponent("gained-candidate.wav")

        let result = try PlaybackSongOfflineRenderer().exportWAV(
            request,
            to: outputURL,
            exportPolicy: MixerWAVExportPolicy(gain: 0.5)
        )
        let wav = try parsePCM16WAV(Data(contentsOf: outputURL))

        XCTAssertEqual(wav.samples, [16_384])
        XCTAssertEqual(result.exportDiagnostics?.policy.gain, 0.5)
        XCTAssertEqual(result.exportDiagnostics?.postGainPeak, 0.5)
    }

    func testPlaybackSongWAVExportIsDeterministicAndPreservesSplitRenderDeterminism() throws {
        let sample = makePlaybackSample(pcm: [0, 1, 2, 3, 4], baseSampleRate: 100, loopStart: 1, loopLength: 3, loopType: 1)
        let song = makePlaybackSong(
            orderPatternIndices: [2],
            patternRowsByIndex: [2: [makePlaybackRow(index: 0, note: 49, instrument: 1)]],
            instrumentsByIndex: [1: PlaybackInstrument(index: 1, samples: [sample])]
        )
        let request = PlaybackSongOfflineRenderRequest(
            song: song,
            orderIndex: 0,
            config: MixerRenderConfig(sampleRate: 100, channelCount: 1),
            frames: 6
        )
        let renderer = PlaybackSongOfflineRenderer()
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let firstURL = tempDirectory.appendingPathComponent("first-candidate.wav")
        let secondURL = tempDirectory.appendingPathComponent("second-candidate.wav")

        try renderer.exportWAV(request, to: firstURL)
        try renderer.exportWAV(request, to: secondURL)
        let singleRender = renderer.render(request)
        let splitRender = renderer.render(request, splitFrameCounts: [1, 2, 3])

        XCTAssertEqual(try Data(contentsOf: firstURL), try Data(contentsOf: secondURL))
        XCTAssertEqual(singleRender.block.interleavedPCM, splitRender.block.interleavedPCM)
    }
}
