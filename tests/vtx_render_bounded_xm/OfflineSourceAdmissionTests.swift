import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Compares Float32 storage exactly, including the sign of zero, without allocating PCM copies.
func assertSourcePCM(_ actual: [Float], _ expected: [Float], _ message: String = "",
                     file: StaticString = #filePath, line: UInt = #line) {
    let equal = actual.withUnsafeBytes { left in expected.withUnsafeBytes { right in left.elementsEqual(right) } }
    XCTAssertTrue(equal, "Float32 PCM bytes differ. \(message)", file: file, line: line)
}

/// Explicit public source/frame lists exercise delivery independently of EEx dispatch.
final class OfflineSourceAdmissionTests: XCTestCase {
    typealias R = PlaybackSongOfflineRenderer

    func testCheckpointPhysicalStopsAdmit256ButStillRefuse257AtTheExactFrame() throws {
        XCTAssertEqual(MemoryLayout<OfflineControlKey>.stride, 32)
        for rate in [44_100.0, 48_000] { for stop in [299, 300, 301] { for count in [256, 257] {
            // The first stop targets a generation not yet imported, ahead of all current-owner stops.
            let stops = [(300, 32)] + (0..<32).map { (stop, $0) }
            let input = SourceAdmissionInput.framed(rate: rate, starts: Array(repeating: 0, count: 32)
                + Array(repeating: 300, count: count), channels: (0..<(32 + count)).map { $0 % 32 }, stops: stops)
            let renderer = R(preparedPlan: input.plan), result = renderer.render(input.request)
            let fits = stop <= 300 && count == 256
            if fits {
                try result.controlAdmission.requireSuccess()
                let prefix = SourceAdmissionInput.framed(rate: rate, starts: Array(repeating: 0, count: 32),
                    channels: Array(0..<32), frames: stop)
                let suffix = SourceAdmissionInput.framed(rate: rate, starts: Array(repeating: 0, count: 256),
                    channels: (0..<256).map { $0 % 32 }, stops: [(0, 0)], frames: 212)
                let expected = rendererPCM(prefix) + Array(repeating: Float(0), count: (300 - stop) * 2) + rendererPCM(suffix)
                assertSourcePCM(result.block.interleavedPCM, expected)
                XCTAssertEqual(result.controlAdmission.sources?.imported, 288)
                XCTAssertEqual(result.controlAdmission.sources?.started, 288)
                XCTAssertEqual(result.controlAdmission.sources?.peakLoaded, 256)
                XCTAssertEqual(result.controlAdmission.sources?.rejected, 0)
                let session = renderer.prepare(input.request)
#if DEBUG
                session.configureAdmissionForTesting(forceSlow: true)
#endif
                for chunk in [17, 257] {
                    session.reset()
                    var pcm: [Float] = []
                    while pcm.count / 2 < 512 {
                        let block = session.render(frames: min(chunk, 512 - pcm.count / 2))
                        XCTAssertGreaterThan(block.frameCount, 0)
                        guard block.frameCount > 0 else { break }
                        pcm += block.interleavedPCM
                    }
                    assertSourcePCM(pcm, expected)
                    XCTAssertEqual(session.controlAdmission.accepted + session.controlAdmission.cancelled, session.controlAdmission.intended)
                    XCTAssertEqual(session.controlAdmission.pending, 0)
#if DEBUG
                    let ledger = session.controlLedgerForTesting
                    XCTAssertEqual(Set(ledger.map { $0.key.ordinal }).count, ledger.count)
                    XCTAssertEqual(ledger.filter { $0.key.family == 16 }.count, 33)
#endif
                }
                for mode in [PlaybackSongOfflineSamplePayloadStorageMode.sharedCPayload, .perVoicePreSanitizedCopy, .perVoiceDefensiveCopy] {
                    assertSourcePCM(renderer.renderWindowed(input.request, windowRows: 1, samplePayloadStorageMode: mode).block.interleavedPCM, expected)
                    var pcm: [Float] = []
                    let streamed = renderer.renderWindowedStreaming(input.request, windowRows: 1, samplePayloadStorageMode: mode) { _, _, _, block in pcm += block.interleavedPCM }
                    try streamed.controlAdmission.requireSuccess()
                    assertSourcePCM(pcm, expected)
                }
            } else {
                XCTAssertEqual(result.renderedFrameCount, 300)
                XCTAssertEqual(result.controlAdmission.failure?.reason, .sourceVoiceCapacity)
                XCTAssertEqual(result.controlAdmission.failure?.frameOrigin, 300)
                XCTAssertEqual(result.controlAdmission.sources?.imported, 32)
                XCTAssertEqual(result.controlAdmission.sources?.rejected, count)
                XCTAssertEqual(result.scheduledVoiceRejectionReasons.filter { $0 == .scheduledVoiceCapacity }.count, count)
                XCTAssertEqual(renderer.renderWindowed(input.request, windowRows: 1).renderedFrameCount, 300)
            }
        } } }
    }

    func testCheckpointPhysicalStopDoesNotShortenAnotherSourcesRetirementTail() throws {
        for rate in [44_100.0, 48_000] {
            let deadline = 100 + Int(rate * 0.005)
            for birth in [deadline - 1, deadline] {
                let input = SourceAdmissionInput.framed(rate: rate, starts: [0, 100] + Array(repeating: birth, count: 256),
                    channels: [0, 0] + (0..<256).map { $0 % 32 }, stops: [(birth, 1)])
                let result = R(preparedPlan: input.plan).render(input.request)
                if birth < deadline {
                    XCTAssertEqual(result.controlAdmission.failure?.reason, .sourceVoiceCapacity)
                    XCTAssertEqual(result.controlAdmission.failure?.frameOrigin, birth)
                    XCTAssertEqual(result.controlAdmission.sources?.rejected, 256)
                    XCTAssertEqual(result.renderedFrameCount, birth)
                } else {
                    try result.controlAdmission.requireSuccess()
                    let prefix = SourceAdmissionInput.framed(rate: rate, starts: [0, 100], channels: [0, 0], frames: birth)
                    let suffix = SourceAdmissionInput.framed(rate: rate, starts: Array(repeating: 0, count: 256),
                        channels: (0..<256).map { $0 % 32 }, frames: 512 - birth)
                    assertSourcePCM(result.block.interleavedPCM, rendererPCM(prefix) + rendererPCM(suffix))
                    XCTAssertEqual(result.controlAdmission.sources?.peakLoaded, 256)
                }
            }
        }
    }

    func testRetriggerTailsCountAs256LiveSourcesAndRefuseThe257thWithoutTruncation() throws {
        for rate in [44_100.0, 48_000] { for extra in [false, true] {
            let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.5, count: 256),
                volume: 1 / 64, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: 256, loopType: 1)
            // Compress time synthetically so 224 nonzero old tails coexist with 32 current sources.
            let rows = (0..<(extra ? 9 : 8)).map { row in PlaybackRow(index: row, cells: (0..<32).map { channel in
                PlaybackCell(note: row == 0 ? 49 : 0, instrument: row == 0 ? 1 : 0, volumeColumn: 0,
                    effectType: row > 0 && (row < 8 || channel == 0) ? 27 : 0, effectParam: 0)
            }) }
            let song = PlaybackSong(title: "Original bounded live retrigger tails", orders: [.init(orderIndex: 0, patternIndex: 0)],
                patternsByIndex: [0: .init(index: 0, rows: rows)], instrumentsByIndex: [1: .init(index: 1,
                    samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))], restartOrderIndex: 0,
                endBehavior: .stopAtEnd, initialTiming: .init(speed: 1, bpm: 4000), usesLinearFrequencyTable: true)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
            XCTAssertEqual(plan.pattern.events.count, extra ? 257 : 256)
            let boundary = PlaybackSongFxxRowTiming.frame(rowStartExactFrame: 0, tick: extra ? 8 : 7, bpm: 4000, sampleRate: rate)
            let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), frames: boundary + 1)
            let renderer = R(preparedPlan: plan), result = renderer.render(request)
            if extra {
                XCTAssertEqual(result.controlAdmission.failure?.reason, .sourceVoiceCapacity)
                XCTAssertEqual(result.controlAdmission.failure?.frameOrigin, boundary)
                XCTAssertEqual(result.controlAdmission.sources?.rejected, 1)
            } else {
                try result.controlAdmission.requireSuccess()
                XCTAssertEqual(result.scheduledVoiceIndices.compactMap { $0 }.count, 256)
                XCTAssertEqual(result.sameChannelVoiceLifetime.maxVoicesPerSourceChannel[0], 8)
                #if DEBUG
                let session = renderer.prepare(request)
                _ = session.render(frames: boundary + 1)
                let voices = (0..<256).compactMap { session.sourceVoiceForTesting($0) }
                XCTAssertEqual(voices.filter(\.active).count, 256)
                XCTAssertEqual(voices.filter { $0.active && $0.gainRamp?.songRetirement == true }.count, 224)
                #endif
                assertSourcePCM(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, result.block.interleavedPCM)
            }
        } }
    }

    private func rendererPCM(_ input: SourceAdmissionInput.Input) -> [Float] {
        R(preparedPlan: input.plan).render(input.request).block.interleavedPCM
    }

    func testEE0SourceControlsKeepTheOriginalUnstagedFastPath() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for retrigger in [false, true] {
            let input = SourceAdmissionInput.make(rate: rate, linear: linear, retrigger: retrigger, ticks: 31)
            let renderer = R(preparedPlan: input.plan), result = renderer.render(input.request)
            try result.controlAdmission.requireSuccess()
            XCTAssertNil(result.controlAdmission.sources)
            XCTAssertFalse(result.controlAdmission.usedSlowPath)
            XCTAssertEqual(result.controlAdmission.allocatedBytes, 0)
            XCTAssertEqual(result.scheduledVoiceIndices.compactMap { $0 }.count, retrigger ? 49 : 32)
            XCTAssertTrue(result.scheduledVoiceRejectionReasons.allSatisfy { $0 == nil })
            let window = renderer.renderWindowed(input.request, windowRows: 1)
            XCTAssertNil(window.controlAdmission.sources)
            assertSourcePCM(window.block.interleavedPCM, result.block.interleavedPCM)
        } } }
    }

    func testPressureBirthsUseBoundedPhysicalImportsAtBothRatesAndModes() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for retrigger in [false, true] {
            let input = SourceAdmissionInput.make(rate: rate, linear: linear, retrigger: retrigger)
            let session = R(preparedPlan: input.plan).prepare(input.request)
            let initial = try XCTUnwrap(session.controlAdmission.sources)
            XCTAssertGreaterThan(initial.deferred, 0)
            let block = session.render(frames: input.frames)
            try session.controlAdmission.requireSuccess()
            let result = try XCTUnwrap(session.controlAdmission.sources)
            XCTAssertEqual(block.frameCount, input.frames)
            XCTAssertEqual(result.intended, retrigger ? 745 : 497)
            XCTAssertEqual(result.imported, result.intended)
            XCTAssertEqual(result.started, result.intended)
            XCTAssertEqual(result.deferred, 0)
            XCTAssertEqual(result.cancelled, 0)
            XCTAssertEqual(result.rejected, 0)
            XCTAssertLessThanOrEqual(result.peakLoaded, 256)
            XCTAssertTrue(session.scheduledVoiceRejectionReasons.allSatisfy { $0 == nil })
            XCTAssertEqual(session.scheduledVoiceIndices.compactMap { $0 }.count, result.intended)
            XCTAssertEqual(input.plan.pattern.rowCount, 1)
            XCTAssertEqual(input.plan.diagnostics.rowMappings.count, 1)
            let unit = Int(rate / 50)
            XCTAssertEqual(result.windows.map { $0.startFrame / unit } + [input.frames / unit],
                retrigger ? [0, 148, 294, 440, 496] : [0, 217, 403, 496])
            XCTAssertEqual(result.windows.map(\.births), retrigger ? [223, 219, 219, 84] : [218, 186, 93])
            XCTAssertEqual(result.windows.map(\.continuations), retrigger ? [0, 4, 4, 4] : [0, 32, 32])
            XCTAssertEqual(session.controlAdmission.pending, 0)
            XCTAssertEqual(session.controlAdmission.rejected, 0)
            XCTAssertLessThanOrEqual(session.controlAdmission.peakQueuedCount, 4096)
            XCTAssertLessThanOrEqual(session.controlAdmission.allocatedBytes, 8 * 1024 * 1024)
        } } }
    }

    func testWholeSplitResetAndStressCutsPreserveExactPCMAndNativeAllocation() throws {
        for retrigger in [false, true] {
            let input = SourceAdmissionInput.make(rate: 48_000, linear: true, retrigger: retrigger)
            let renderer = R(preparedPlan: input.plan), session = renderer.prepare(input.request)
#if DEBUG
            let identity = session.sourceMixerIdentityForTesting
#endif
            let expected = session.render(frames: input.frames).interleavedPCM
            for size in [17, 257] {
                session.reset()
                XCTAssertEqual(session.scheduledVoiceIndices.compactMap { $0 }.count, session.controlAdmission.sources?.imported)
                XCTAssertGreaterThan(session.controlAdmission.sources?.deferred ?? 0, 0)
                var pcm: [Float] = []
                while pcm.count / 2 < input.frames {
                    let block = session.render(frames: min(size, input.frames - pcm.count / 2))
                    XCTAssertGreaterThan(block.frameCount, 0)
                    guard block.frameCount > 0 else { break }
                    pcm += block.interleavedPCM
                }
                assertSourcePCM(pcm, expected)
#if DEBUG
                XCTAssertEqual(session.sourceMixerIdentityForTesting, identity)
#endif
                XCTAssertEqual(session.controlAdmission.sources?.started, input.plan.pattern.events.count)
            }
#if DEBUG
            let stress = renderer.prepare(input.request), n = 240, unit = 960
            var cuts: [Int] = []
            for f in stride(from: 31 * unit, to: input.frames, by: 31 * unit) {
                cuts += [f - 1, f, f + 1, f + n / 2, f + n, f + n + 1]
            }
            stress.configureSourceAdmissionForTesting(boundaries: cuts)
            assertSourcePCM(stress.render(frames: input.frames).interleavedPCM, expected)
            try stress.controlAdmission.requireSuccess()
            XCTAssertEqual(stress.sourceBirthsForTesting.count, input.plan.pattern.events.count)
            XCTAssertTrue(stress.sourceBirthsForTesting.allSatisfy { $0.cursor == 0 })
            XCTAssertEqual(stress.sourceBirthsForTesting.map(\.frame), input.starts)
#endif
        }
    }

    func testAllPublicOutputPathsAndPayloadModesUseTheSameDeliveryAuthority() throws {
        for retrigger in [false, true] { for rate in [44_100.0, 48_000] { for linear in [true, false] {
            let input = SourceAdmissionInput.make(rate: rate, linear: linear, retrigger: retrigger)
            let renderer = R(preparedPlan: input.plan)
            let full = renderer.render(input.request)
            try full.controlAdmission.requireSuccess()
            let split = renderer.render(input.request, splitFrameCounts: [17, 257, input.frames - 274])
            assertSourcePCM(split.block.interleavedPCM, full.block.interleavedPCM)
            var stream: [Float] = []
            let streaming = renderer.renderStreaming(input.request, chunkFrameCount: 257) { _, _, block in stream += block.interleavedPCM }
            try streaming.controlAdmission.requireSuccess()
            assertSourcePCM(stream, full.block.interleavedPCM)
            for mode in [PlaybackSongOfflineSamplePayloadStorageMode.sharedCPayload, .perVoicePreSanitizedCopy, .perVoiceDefensiveCopy] {
                let window = renderer.renderWindowed(input.request, windowRows: 1, samplePayloadStorageMode: mode, collectPerformanceDiagnostics: true)
                try window.controlAdmission.requireSuccess()
                assertSourcePCM(window.block.interleavedPCM, full.block.interleavedPCM)
                XCTAssertEqual(window.windowedRenderSummary?.totalAcceptedScheduledEvents, input.plan.pattern.events.count)
                XCTAssertEqual(window.controlAdmission.sources?.imported, input.plan.pattern.events.count)
                XCTAssertEqual(window.windowedRenderSummary?.totalScheduledCapacityRejects, 0)
                XCTAssertEqual(window.performanceDiagnostics?.cMixerVoiceAddCount,
                    input.plan.pattern.events.count + (window.controlAdmission.sources?.continuationImports ?? 0))
                var pcm: [Float] = []
                let result = renderer.renderWindowedStreaming(input.request, windowRows: 1, samplePayloadStorageMode: mode) { _, _, _, block in pcm += block.interleavedPCM }
                try result.controlAdmission.requireSuccess()
                assertSourcePCM(pcm, full.block.interleavedPCM)
            }
            let scan = renderer.renderWindowedUsingScanPerWindowSchedulingReference(input.request, windowRows: 1)
            try scan.controlAdmission.requireSuccess()
            assertSourcePCM(scan.block.interleavedPCM, full.block.interleavedPCM)
        } } }
    }

    func testSoftTargetAdmits256AndAReallyOverfullAtomicFrameFailsAtItsOwnFrame() throws {
        let input = SourceAdmissionInput.make(rate: 48_000, linear: true, retrigger: false)
        let template = input.plan.pattern.events[0]
        func event(_ frame: Int) -> SyntheticTrackerEvent {
            .init(row: 0, scheduledStartFrame: frame, sample: template.sample, gain: template.gain,
                pan: template.pan, playbackStep: template.playbackStep, loop: template.loop)
        }
        let within = SourceAdmissionInput.replacing(input,
            events: Array(repeating: event(0), count: 256) + [event(241)], frames: 512)
        let accepted = R(preparedPlan: within.plan).render(within.request)
        try accepted.controlAdmission.requireSuccess()
        XCTAssertEqual(accepted.controlAdmission.sources?.imported, 257)
        XCTAssertEqual(accepted.controlAdmission.sources?.peakLoaded, 256)
        XCTAssertEqual(accepted.controlAdmission.sources?.rejected, 0)
        let over = SourceAdmissionInput.replacing(input,
            events: [event(0)] + Array(repeating: event(300), count: 257), frames: 512)
        let refused = R(preparedPlan: over.plan).render(over.request)
        XCTAssertEqual(refused.block.frameCount, 300)
        XCTAssertEqual(refused.controlAdmission.failure?.reason, .sourceVoiceCapacity)
        XCTAssertEqual(refused.controlAdmission.failure?.frameOrigin, 300)
        XCTAssertEqual(refused.controlAdmission.sources?.imported, 1)
        XCTAssertEqual(refused.controlAdmission.sources?.started, 1)
        XCTAssertEqual(refused.controlAdmission.sources?.rejected, 257)
        XCTAssertEqual(refused.scheduledVoiceRejectionReasons.filter { $0 == .scheduledVoiceCapacity }.count, 257)
        XCTAssertThrowsError(try refused.controlAdmission.requireSuccess())
        let renderer = R(preparedPlan: over.plan)
        XCTAssertEqual(renderer.render(over.request, splitFrameCounts: [17, 257, 238]).block.frameCount, 300)
        XCTAssertEqual(renderer.renderWindowed(over.request, windowRows: 1).block.frameCount, 300)
        var delivered = 0
        let stream = renderer.renderStreaming(over.request, chunkFrameCount: 257) { frame, _, _ in delivered = frame }
        XCTAssertEqual(stream.renderedFrameCount, 300)
        XCTAssertEqual(delivered, 300)
        XCTAssertEqual(stream.controlAdmission.failure?.frameOrigin, 300)
    }

    func testIsolationDoesNotRetainExcludedSilentGenerationsAcrossCheckpoints() throws {
        for rate in [44_100.0, 48_000] { for channel in [0, 1] {
            let input = SourceAdmissionInput.make(rate: rate, linear: true, retrigger: false)
            let mappings = Dictionary(uniqueKeysWithValues: input.plan.diagnostics.eventMappings.map { ($0.eventIndex, $0.channelIndex) })
            let selected = input.plan.pattern.events.enumerated().filter { mappings[$0.offset] == channel }.map(\.element)
            let reference = SourceAdmissionInput.replacing(input, events: selected, frames: input.frames)
            let expected = R(preparedPlan: reference.plan).render(reference.request).block.interleavedPCM
            let request = PlaybackSongOfflineRenderRequest(song: input.request.song, config: input.request.config,
                frames: input.frames, isolationFilter: .init(soloChannelIndex: channel))
            let renderer = R(preparedPlan: input.plan), whole = renderer.render(request)
            try whole.controlAdmission.requireSuccess()
            assertSourcePCM(whole.block.interleavedPCM, expected)
            XCTAssertEqual(whole.controlAdmission.sources?.imported, 497)
            XCTAssertEqual(whole.controlAdmission.sources?.rejected, 0)
            XCTAssertLessThanOrEqual(whole.controlAdmission.sources?.peakLoaded ?? 0, 256)
            let window = renderer.renderWindowed(request, windowRows: 1)
            try window.controlAdmission.requireSuccess()
            assertSourcePCM(window.block.interleavedPCM, expected)
        } }
    }

    func testSourceCaptureHonorsTheExistingStagingBudgetBeforeAnyNativeImport() throws {
        let input = SourceAdmissionInput.make(rate: 48_000, linear: true, retrigger: false)
        var plan = input.plan
        let count = OfflineControlAdmission.byteLimit / MemoryLayout<OfflineControlKey>.stride + 1
        plan.instrumentAutovibratoRequests = (0..<count).map { index in
            .init(row: 0, tick: 0, channel: 0, frame: index + 1, generation: 0, step: 0.25)
        }
        let session = R(preparedPlan: plan).prepare(input.request)
        XCTAssertEqual(session.controlAdmission.failure?.reason, .controlStagingBudgetExceeded)
        XCTAssertEqual(session.controlAdmission.allocatedBytes, 0)
        XCTAssertEqual(session.controlAdmission.sources?.imported, 0)
        XCTAssertEqual(session.controlAdmission.sources?.peakLoaded, 0)
        XCTAssertEqual(session.controlAdmission.sources?.deferred, 497)
        XCTAssertEqual(session.render(frames: input.frames).frameCount, 0)
        XCTAssertThrowsError(try session.controlAdmission.requireSuccess())
    }

#if DEBUG
    func testIndexedFrameBucketsRetainEarlierBirthsWhenOneRowHasSeveralWindows() throws {
        for rate in [44_100.0, 48_000] {
            let input = SourceAdmissionInput.make(rate: rate, linear: true, retrigger: false, ticks: 217)
            let unit = Int(rate / 50), renderer = R(preparedPlan: input.plan)
            let cuts = [1, 31 * unit - 1, 31 * unit, 31 * unit + 1, 62 * unit, 93 * unit, 216 * unit]
            let full = renderer.render(input.request)
            let indexed = renderer.renderWindowedAtFrameBoundariesForTesting(input.request, boundaries: cuts, usePreindexedScheduling: true)
            let scan = renderer.renderWindowedAtFrameBoundariesForTesting(input.request, boundaries: cuts)
            assertSourcePCM(indexed.block.interleavedPCM, full.block.interleavedPCM)
            assertSourcePCM(scan.block.interleavedPCM, full.block.interleavedPCM)
            XCTAssertEqual(Set(indexed.scheduledVoiceAttempts.map(\.eventIndex)).count, input.plan.pattern.events.count)
            let dense = SourceAdmissionInput.make(rate: rate, linear: true, retrigger: false)
            let bounded = R(preparedPlan: dense.plan)
            let expected = bounded.render(dense.request)
            let result = bounded.renderWindowedAtFrameBoundariesForTesting(dense.request, boundaries: cuts, usePreindexedScheduling: true)
            assertSourcePCM(result.block.interleavedPCM, expected.block.interleavedPCM)
            XCTAssertEqual(result.controlAdmission.sources?.started, 497)
        }
    }

    func testRetiredLogicalControlsCannotReachReusedSlotsAndFutureOwnersRemainDeferred() throws {
        let input = SourceAdmissionInput.make(rate: 48_000, linear: true, retrigger: false)
        var plan = input.plan
        let boundary = 217 * 960
        plan.xmEmptyRoutes = [.init(source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0),
            channelIndex: 0, scheduledFrame: 100, instrumentIndex: 1, sampleIndex: 0, stoppedEventIndex: 0)]
        plan.instrumentAutovibratoRequests = [
            .init(row: 0, tick: 217, channel: 0, frame: boundary + 5, generation: 0, step: 9),
            .init(row: 0, tick: 217, channel: 1, frame: boundary + 5, generation: 218, step: 0.25),
            .init(row: 0, tick: 497, channel: 0, frame: input.frames + 1, generation: 0, step: 7)]
        let session = R(preparedPlan: plan).prepare(input.request)
        let initial = session.controlAdmission
        XCTAssertNil(session.sourceSlotForTesting(218))
        XCTAssertEqual(session.sourceSlotForTesting(0), 0)
        XCTAssertGreaterThan(initial.pending, 0)
        XCTAssertGreaterThan(initial.sources?.deferred ?? 0, 0)
        XCTAssertEqual(session.render(frames: boundary + 6).frameCount, boundary + 6)
        XCTAssertNil(session.sourceVoiceForTesting(0))
        XCTAssertEqual(session.sourceSlotForTesting(187), 0)
        XCTAssertEqual(session.sourceVoiceForTesting(187)?.sampleStep, plan.pattern.events[187].playbackStep)
        XCTAssertEqual(session.sourceVoiceForTesting(218)?.sampleStep, 0.25)
        XCTAssertEqual(session.controlAdmission.cancelled, 1)
        try session.controlAdmission.requireSuccess()
        _ = session.render(frames: input.frames)
        XCTAssertEqual(session.controlAdmission.pending, 1)
        let before = session.controlAdmission
        XCTAssertEqual(session.render(frames: 0).frameCount, 0)
        XCTAssertEqual(session.controlAdmission, before)
        session.reset()
        XCTAssertEqual(session.sourceSlotForTesting(0), 0)
        XCTAssertNil(session.sourceSlotForTesting(218))
        XCTAssertEqual(session.controlAdmission.cancelled, 0)
    }

    func testSilentECxOwnerRecoversItsProgressedCursorAfterCheckpoints() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let seed = SourceAdmissionInput.make(rate: rate, linear: linear, retrigger: false).request.song
            let cells: [PlaybackCell] = [
                .init(note: 49, instrument: 1, volumeColumn: 0, effectType: 0, effectParam: 0),
                .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 14, effectParam: 0xC0),
                .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
                .init(note: 0, instrument: 0, volumeColumn: 0, effectType: 12, effectParam: 64)]
            let song = PlaybackSong(title: "Original silent owner control", orders: seed.orders,
                patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
                instrumentsByIndex: seed.instrumentsByIndex, restartOrderIndex: 0, endBehavior: .stopAtEnd,
                initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: linear)
            let unit = Int(rate / 50), n = Int(rate * 0.005), frames = 24 * unit
            let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), frames: frames)
            let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
            let renderer = R(preparedPlan: plan), session = renderer.prepare(request)
            session.configureSourceAdmissionForTesting(boundaries: [1, 6 * unit, 6 * unit + n / 2, 6 * unit + n, 12 * unit, 18 * unit, 18 * unit + n])
            var pcm = session.render(frames: 12 * unit + 1).interleavedPCM
            XCTAssertTrue(try XCTUnwrap(session.sourceVoiceForTesting(0)).active)
            XCTAssertEqual(session.sourceVoiceForTesting(0)?.audibleOutputState?.current, [0, 0, 0])
            pcm += session.render(frames: frames).interleavedPCM
            assertSourcePCM(pcm, renderer.render(request).block.interleavedPCM)
            XCTAssertTrue(pcm[((18 * unit + n) * 2)...].contains { $0 != 0 })
            XCTAssertEqual(session.controlAdmission.sources?.started, 1)
        } }
    }

    func testNativeSnapshotsCarryFutureReleaseFadeoutPingPongAndZeroStepExactly() throws {
        for rate in [44_100.0, 48_000] {
            let input = SourceAdmissionInput.make(rate: rate, linear: true, retrigger: false)
            let unit = Int(rate / 50), n = Int(rate * 0.005), frames = unit * 6
            let sample = input.plan.pattern.events[0].sample
            let event = SyntheticTrackerEvent(row: 0, scheduledStartFrame: 0, sample: sample,
                gain: 0.4, pan: -0.6, playbackStep: 0.125,
                loop: .init(mode: .pingPong, startFrame: 0, endFrame: sample.frameCount),
                volumeEnvelope: .init(points: [.init(positionFrame: 0, value: 1), .init(positionFrame: unit, value: 0.5)], sustainFrame: unit),
                panEnvelope: .init(points: [.init(positionFrame: 0, value: -0.25), .init(positionFrame: unit, value: 0.25)], loopStartFrame: 0, loopEndFrame: unit),
                keyOffFrame: unit * 3 + 31, fadeoutFrameDecrement: 0.00002)
            let base = SourceAdmissionInput.replacing(input, events: [event], frames: frames)
            var plan = base.plan
            plan.initialHeldPitchEventIndices = [0]
            plan.playbackStateEvents = [
                .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: unit + 17, change: .keyOff(fadeoutDecrement: 0.00001)),
                .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 2 * unit + 13,
                    change: .reset(.init(volumeEnvelope: true, panEnvelope: true, keyOn: true, fadeout: true)))]
            plan.instrumentAutovibratoRequests = [
                .init(row: 0, tick: 1, channel: 0, frame: unit + 7, generation: 0, step: 0.375),
                .init(row: 0, tick: 1, channel: 0, frame: unit + 80, generation: 0, step: 0),
                .init(row: 0, tick: 2, channel: 0, frame: 2 * unit + 3, generation: 0, step: 0.625),
                .init(row: 0, tick: 7, channel: 0, frame: frames + 10, generation: 0, step: 0.5)]
            let renderer = R(preparedPlan: plan), eager = renderer.prepare(base.request), restored = renderer.prepare(base.request)
            let boundaries = [1, n / 2, n - 1, n, n + 1, unit - 1, unit + 7, unit + 18,
                unit + 80, unit + 81, 2 * unit + 3, 2 * unit + 14, 3 * unit + 31, 3 * unit + 32, 4 * unit + 1]
            restored.configureSourceAdmissionForTesting(boundaries: boundaries)
            var frame = 0, originalPCM: [Float] = [], restoredPCM: [Float] = []
            for boundary in boundaries {
                originalPCM += eager.render(frames: boundary - frame).interleavedPCM
                restoredPCM += restored.render(frames: boundary - frame).interleavedPCM
                restored.advanceSourceWindowForTesting()
                XCTAssertEqual(restored.sourceVoiceForTesting(0), eager.sourceVoiceForTesting(0), "state at \(boundary)")
                frame = boundary
            }
            originalPCM += eager.render(frames: frames - frame).interleavedPCM
            restoredPCM += restored.render(frames: frames - frame).interleavedPCM
            assertSourcePCM(restoredPCM, originalPCM)
            try restored.controlAdmission.requireSuccess()
            XCTAssertEqual(restored.controlAdmission.pending, 1)
            XCTAssertEqual(restored.controlAdmission.sources?.started, 1)
            restored.reset()
            assertSourcePCM(restored.render(frames: frames).interleavedPCM, originalPCM)
        }
    }

    func testManagedEnvelopeOutputAndECxOwnersSurviveArbitraryCheckpoints() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for name in ["envelope-release-fadeout-timing", "amiga-vibrato", "instrument-autovibrato-composition-linear", "instrument-autovibrato-composition-amiga"] {
            for rate in [44_100.0, 48_000] {
                let path = root.appendingPathComponent("reference-xm/generated/\(name).xm").path
                let song = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: path), modulePath: path)
                let plan = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
                let frames = 24 * Int(rate / 50), n = Int(rate * 0.005)
                let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), frames: frames)
                let renderer = R(preparedPlan: plan), session = renderer.prepare(request)
                var cuts: [Int] = []
                for f in stride(from: 0, to: frames, by: 6 * Int(rate / 50)) {
                    cuts += [f + 1, f + n / 2, f + n - 1, f + n, f + n + 1]
                }
                session.configureSourceAdmissionForTesting(boundaries: cuts)
                assertSourcePCM(session.render(frames: frames).interleavedPCM, renderer.render(request).block.interleavedPCM, name)
                try session.controlAdmission.requireSuccess()
            }
        }
    }

    func testNonchronologicalSourcesMergeContinuationsAndFutureBirthsInOriginalOrder() throws {
        for rate in [44_100.0, 48_000] {
            let prefix = SourceAdmissionInput.make(rate: rate, linear: true, retrigger: false, ticks: 217, nonchronological: true)
            let eager = R(preparedPlan: prefix.plan).prepare(prefix.request)
            let expected = eager.render(frames: prefix.frames).interleavedPCM
            let checkpoint = R(preparedPlan: prefix.plan).prepare(prefix.request)
            checkpoint.configureSourceAdmissionForTesting(boundaries: [1, 62 * Int(rate / 50), 62 * Int(rate / 50) + 1])
            assertSourcePCM(checkpoint.render(frames: prefix.frames).interleavedPCM, expected)
            XCTAssertTrue(checkpoint.sourceBirthsForTesting.allSatisfy { $0.cursor == 0 && $0.frame == prefix.starts[$0.source] })
            XCTAssertEqual(checkpoint.sourceBirthsForTesting.count, prefix.plan.pattern.events.count)
            let full = SourceAdmissionInput.make(rate: rate, linear: true, retrigger: false, nonchronological: true)
            let renderer = R(preparedPlan: full.plan), reference = renderer.render(full.request)
            assertSourcePCM(renderer.renderWindowed(full.request, windowRows: 1).block.interleavedPCM, reference.block.interleavedPCM)
            let stress = renderer.prepare(full.request)
            stress.configureSourceAdmissionForTesting(boundaries: [1, 31 * Int(rate / 50) + 1, 217 * Int(rate / 50) + 1])
            assertSourcePCM(stress.render(frames: full.frames).interleavedPCM, reference.block.interleavedPCM)
        }
    }
#endif
}

/// The verified witnesses have ED starts every31 ticks and R starts every2 ticks.
/// These are authored source lists, not an effect handler or an increased logical row speed.
enum SourceAdmissionInput {
    struct Input {
        let plan: PlaybackSongSyntheticPlan
        let request: PlaybackSongOfflineRenderRequest
        let starts: [Int]
        var frames: Int { request.boundedFrameCount }
    }
    static func framed(rate: Double, starts: [Int], channels: [Int], stops: [(Int, Int)] = [], frames: Int = 512) -> Input {
        let seed = make(rate: rate, linear: true, retrigger: false, ticks: 31)
        let template = seed.plan.pattern.events[0]
        let events = starts.map { SyntheticTrackerEvent(row: 0, scheduledStartFrame: $0, sample: template.sample,
            gain: template.gain, pan: template.pan, playbackStep: template.playbackStep, loop: template.loop) }
        let mappings = events.indices.map { CarriedStateEligibilityReference.mapping(seed.plan.diagnostics.eventMappings[0], eventIndex: $0, channelIndex: channels[$0]) }
        var plan = PlaybackSongSyntheticPlan(timingConfig: seed.plan.timingConfig, pattern: .init(rowCount: 1, events: events),
            diagnostics: CarriedStateEligibilityReference.diagnostics(seed.plan.diagnostics, mappings: mappings, retriggers: []),
            canonicalTickClock: seed.plan.canonicalTickClock, selectionDispatchFacts: .notAdapterProduced)
        plan.xmEmptyRoutes = stops.map { frame, source in
            .init(source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), channelIndex: channels[source],
                scheduledFrame: frame, instrumentIndex: 1, sampleIndex: 0, stoppedEventIndex: source)
        }
        return .init(plan: plan, request: seed.request.replacingFrameCount(frames), starts: starts)
    }
    static func replacing(_ input: Input, events: [SyntheticTrackerEvent], frames: Int) -> Input {
        let seed = input.plan
        let mappings = events.indices.map { CarriedStateEligibilityReference.mapping(seed.diagnostics.eventMappings[0], eventIndex: $0, channelIndex: 0) }
        let diagnostics = CarriedStateEligibilityReference.diagnostics(seed.diagnostics, mappings: mappings, retriggers: [])
        let plan = PlaybackSongSyntheticPlan(timingConfig: seed.timingConfig, pattern: .init(rowCount: 1, events: events),
            diagnostics: diagnostics, canonicalTickClock: seed.canonicalTickClock, selectionDispatchFacts: .notAdapterProduced)
        return .init(plan: plan, request: input.request.replacingFrameCount(frames), starts: events.map { $0.scheduledStartFrame! })
    }
    static func make(rate: Double, linear: Bool, retrigger: Bool, ticks: Int = 496, nonchronological: Bool = false) -> Input {
        let channels = retrigger ? 4 : 32
        let cells = (0..<channels).map { channel in
            PlaybackCell(note: 49, instrument: 1, volumeColumn: retrigger && channel > 0 ? 0x20 : 0,
                effectType: retrigger && channel > 0 ? 27 : 0, effectParam: retrigger && channel > 0 ? 2 : 0)
        }
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: (0..<256).map { Float(($0 * 79) % 251 - 125) / 2048 }, volume: 0.5, panning: 128,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363,
            loopStart: 0, loopLength: 256, loopType: 1)
        let song = PlaybackSong(title: "Original bounded source list",
            orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: [.init(index: 0, cells: cells)])],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: 31, bpm: 125), usesLinearFrequencyTable: linear)
        let seed = PlaybackSongSyntheticAdapter.adapt(song, orderIndex: 0, sampleRate: rate)
        let template = seed.pattern.events[0], unit = Int(rate / 50)
        let births = [(tick: 0, channel: 0)] + stride(from: 0, to: ticks, by: retrigger ? 2 : 31).flatMap { tick in
            (1..<channels).map { (tick: tick, channel: $0) }
        }
        let ordered = births.sorted {
            if nonchronological { return $0.channel == $1.channel ? $0.tick > $1.tick : $0.channel > $1.channel }
            return $0.tick == $1.tick ? $0.channel < $1.channel : $0.tick < $1.tick
        }
        let starts = ordered.map { $0.tick * unit }
        let events = starts.map { frame in
            SyntheticTrackerEvent(row: 0, scheduledStartFrame: frame, sample: template.sample,
                gain: template.gain, pan: template.pan, playbackStep: template.playbackStep, loop: template.loop)
        }
        let mappings = ordered.enumerated().map { i, birth in
            CarriedStateEligibilityReference.mapping(seed.diagnostics.eventMappings[0], eventIndex: i, channelIndex: birth.channel)
        }
        let retriggers: [PlaybackSongSyntheticRetriggerDiagnostic] = retrigger ? (1..<channels).map { channel in
            var diagnostic = seed.diagnostics.retriggerEffects.first { $0.channelIndex == channel }!
            let indices = ordered.indices.filter { ordered[$0].channel == channel }.sorted { ordered[$0].tick < ordered[$1].tick }
            diagnostic.retriggerTicks = indices.dropFirst().map { ordered[$0].tick }
            diagnostic.retriggerFrames = indices.dropFirst().map { starts[$0] }
            diagnostic.retriggerEventIndices = Array(indices.dropFirst())
            diagnostic.replacedEventIndices = Array(indices.dropLast())
            diagnostic.replacementFrames = diagnostic.retriggerFrames
            return diagnostic
        } : []
        let diagnostics = CarriedStateEligibilityReference.diagnostics(seed.diagnostics, mappings: mappings, retriggers: retriggers)
        let plan = PlaybackSongSyntheticPlan(timingConfig: seed.timingConfig, pattern: .init(rowCount: 1, events: events),
            diagnostics: diagnostics, canonicalTickClock: seed.canonicalTickClock, selectionDispatchFacts: .notAdapterProduced)
        let request = PlaybackSongOfflineRenderRequest(song: song, config: .init(sampleRate: rate), frames: ticks * unit)
        return .init(plan: plan, request: request, starts: starts)
    }
}
