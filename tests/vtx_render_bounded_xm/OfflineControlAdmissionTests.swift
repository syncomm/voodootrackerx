import Darwin
import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Admission tests inspect real prepared sessions independently of audible PCM equality.
final class OfflineControlAdmissionTests: XCTestCase {
    private typealias R = PlaybackSongOfflineRenderer
    private let allReset = MixerPlaybackReset(volumeEnvelope: true, panEnvelope: true, keyOn: true, fadeout: true)

    func testCompactBoundaryAndNoTControlAdmitEveryScalarInBothModesAndRates() throws {
        XCTAssertEqual(CSoftwareMixer.maximumVoiceCount, 256)
        XCTAssertEqual(OfflineControlAdmission.queueLimit, 4096)
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for (rows, tremor, expected) in [(129, true, 4096), (130, true, 4128), (130, false, 0)] {
                let song = AdmissionInputs.compact(rows: rows, tremor: tremor, linear: linear)
                let plan = AdmissionInputs.plan(song, rate: rate)
                let frames = rows * 3 * Int(rate / 100)
                let session = R(preparedPlan: plan).prepare(AdmissionInputs.request(song, rate: rate, frames: frames))
                record(session)
                XCTAssertEqual(session.scheduledVoiceIndices.compactMap { $0 }.count, 32)
                XCTAssertTrue(session.scheduledVoiceRejectionReasons.allSatisfy { $0 == nil })
                XCTAssertEqual(session.render(frames: frames).frameCount, frames)
                try assertComplete(session.controlAdmission, expected: expected)
                XCTAssertEqual(session.controlAdmission.usedSlowPath, rows == 130 && tremor)
                if !session.controlAdmission.usedSlowPath {
                    XCTAssertEqual(session.controlAdmission.stagedKeyCount, 0)
                    XCTAssertEqual(session.controlAdmission.allocatedBytes, 0)
                }
                #if DEBUG
                XCTAssertEqual(session.controlLedgerForTesting.filter { $0.key.family == 3 && $0.accepted }.count, expected)
                #endif
                XCTAssertEqual(session.plan.pattern.events, plan.pattern.events)
            }
        } }
    }

    func testMixedResetGlobalAndGenerationControlAdmitsAllTwelveRetirements() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] { for tremor in [true, false] {
            let song = AdmissionInputs.mixed(tremor: tremor, linear: linear)
            let plan = AdmissionInputs.plan(song, rate: rate), frames = 520 * 6 * Int(rate / 100)
            let session = R(preparedPlan: plan).prepare(AdmissionInputs.request(song, rate: rate, frames: frames))
            record(session)
            XCTAssertEqual(session.scheduledVoiceIndices.compactMap { $0 }.count, 44)
            XCTAssertTrue(session.scheduledVoiceRejectionReasons.allSatisfy { $0 == nil })
            XCTAssertEqual(session.sameChannelVoiceLifetime.replacementEvents.count, 12)
            XCTAssertEqual(session.render(frames: frames).frameCount, frames)
            try assertComplete(session.controlAdmission, expected: tremor ? 4176 : 532)
            XCTAssertEqual(session.controlAdmission.usedSlowPath, tremor)
            #if DEBUG
            XCTAssertEqual(session.controlLedgerForTesting.filter { $0.key.family == 3 && $0.accepted }.count, tremor ? 4164 : 520)
            XCTAssertEqual(session.controlLedgerForTesting.filter { $0.key.family == 13 && $0.accepted }.count, 12)
            #endif
        } } }
    }

    func testSlowSessionBlocksZeroRenderAndRepeatedReplayRemainExact() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let song = AdmissionInputs.compact(rows: 260, linear: linear)
            let plan = AdmissionInputs.plan(song, rate: rate), frames = 260 * 3 * Int(rate / 100)
            let request = AdmissionInputs.request(song, rate: rate, frames: frames)
            let session = R(preparedPlan: plan).prepare(request)
            XCTAssertTrue(session.controlAdmission.usedSlowPath)
            let before = session.controlAdmission
            XCTAssertTrue(session.render(frames: 0).interleavedPCM.isEmpty)
            XCTAssertTrue(session.render(frames: -1).interleavedPCM.isEmpty)
            XCTAssertEqual(session.controlAdmission, before)
            session.reset()
            let expected = session.render(frames: frames).interleavedPCM
            try assertComplete(session.controlAdmission, expected: 8288)
            for size in [1, 17, 257, 4093] {
                session.reset()
                XCTAssertEqual(render(session, frames: frames, blocks: [size]), expected)
                try assertComplete(session.controlAdmission, expected: 8288)
            }
            session.reset()
            _ = session.render(frames: 129 * 3 * Int(rate / 100) + 1)
            session.reset()
            XCTAssertEqual(render(session, frames: frames, blocks: [71, 1, 997, 17, 4093, 257]), expected)
            try assertComplete(session.controlAdmission, expected: 8288)
        } }
    }

    func testPermanentStopCancelsOnlyPendingKeysAfterItsFrameExecutesAndResetRestoresThem() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let song = AdmissionInputs.compact(rows: 130, linear: linear)
            var plan = AdmissionInputs.plan(song, rate: rate)
            let refill = 129 * 3 * Int(rate / 100), stop = refill - 100, frames = 130 * 3 * Int(rate / 100)
            plan.xmEmptyRoutes.append(.init(source: .init(orderIndex: 1, patternIndex: 1, rowIndex: 1),
                channelIndex: 0, scheduledFrame: stop, instrumentIndex: 1, sampleIndex: 1, stoppedEventIndex: 0))
            let session = R(preparedPlan: plan).prepare(AdmissionInputs.request(song, rate: rate, frames: frames))
            XCTAssertTrue(session.controlAdmission.usedSlowPath)
            var expected = session.render(frames: stop).interleavedPCM
            XCTAssertEqual(session.controlAdmission.cancelled, 0)
            let atStop = session.controlAdmission
            XCTAssertTrue(session.render(frames: 0).interleavedPCM.isEmpty)
            XCTAssertEqual(session.controlAdmission, atStop)
            expected += session.render(frames: 1).interleavedPCM
            expected += session.render(frames: frames - stop - 1).interleavedPCM
            try session.controlAdmission.requireSuccess()
            XCTAssertEqual(session.controlAdmission.intended, 4128)
            XCTAssertEqual(session.controlAdmission.accepted, 4127)
            XCTAssertEqual(session.controlAdmission.cancelled, 1)
            XCTAssertEqual(session.controlAdmission.pending, 0)
            XCTAssertEqual(session.controlAdmission.rejected, 0)
            session.reset()
            XCTAssertEqual(render(session, frames: frames, blocks: [17, 257, 4093, 1]), expected)
            XCTAssertEqual(session.controlAdmission.cancelled, 1)
        } }
    }

    func testRealSameFrameResetBurstFits4096AndRefuses4097BeforePCMOrWAV() throws {
        for count in [4096, 4097] {
            let (song, plan) = resetPlan(count: count, frame: { _ in 1 })
            let request = AdmissionInputs.request(song, rate: 48_000, frames: 64)
            let renderer = R(preparedPlan: plan), session = renderer.prepare(request)
            if count == 4096 {
                XCTAssertEqual(session.render(frames: 64).frameCount, 64)
                try assertComplete(session.controlAdmission, expected: 4096)
            } else {
                XCTAssertEqual(session.controlAdmission.failure?.reason, .singleFrameCapacity)
                XCTAssertEqual(session.render(frames: 64).frameCount, 0)
                XCTAssertThrowsError(try session.controlAdmission.requireSuccess())
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vtx-control-refusal-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let url = directory.appendingPathComponent("must-not-exist.wav")
                XCTAssertThrowsError(try renderer.exportWAV(request, to: url))
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
                var progress = 0
                let streaming = renderer.renderStreaming(request, chunkFrameCount: 17) { _, _, _ in progress += 1 }
                XCTAssertEqual(progress, 0)
                XCTAssertEqual(streaming.renderedFrameCount, 0)
                XCTAssertEqual(streaming.controlAdmission.failure?.reason, .singleFrameCapacity)
                XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).controlAdmission.failure?.reason, .stateQueueCapacity)
                XCTAssertEqual(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).controlAdmission.failure?.reason, .stateQueueCapacity)
            }
        }
    }

    func testStagingBudgetAndCheckedArithmeticFailBeforeAllocatingOrRendering() throws {
        let byteLimit = OfflineControlAdmission.byteLimit
        XCTAssertEqual(byteLimit, 8 * 1024 * 1024)
        let keyStride = MemoryLayout<OfflineControlKey>.stride
        let limit = byteLimit / keyStride
        for count in [limit + 1, Int.max, -1] {
            let admission = OfflineControlAdmission(stagingCount: count)
            XCTAssertEqual(admission.snapshot.failure?.reason, .controlStagingBudgetExceeded)
            XCTAssertEqual(admission.snapshot.allocatedBytes, 0)
            XCTAssertThrowsError(try admission.snapshot.requireSuccess())
        }

        let positiveCount = limit / 2, positiveBytes = positiveCount * keyStride
        XCTAssertGreaterThan(positiveCount, 0)
        XCTAssertLessThanOrEqual(malloc_good_size(positiveBytes), byteLimit)
        let positive = OfflineControlAdmission(stagingCount: positiveCount)
        try positive.snapshot.requireSuccess()
        XCTAssertGreaterThan(positive.snapshot.allocatedBytes, 0)
        XCTAssertGreaterThanOrEqual(positive.snapshot.allocatedBytes, positiveBytes)
        XCTAssertLessThanOrEqual(positive.snapshot.allocatedBytes, byteLimit)

        let (requestedBytes, overflow) = limit.multipliedReportingOverflow(by: keyStride)
        XCTAssertFalse(overflow)
        XCTAssertLessThanOrEqual(requestedBytes, byteLimit)
        let goodSize = malloc_good_size(requestedBytes)
        let maximum = OfflineControlAdmission(stagingCount: limit)
        let boundary = maximum.snapshot
        XCTAssertTrue(boundary.usedSlowPath)
        XCTAssertEqual(boundary.stagedKeyCount, limit)
        XCTAssertEqual(boundary.accepted, 0)
        XCTAssertEqual(boundary.cancelled, 0)
        XCTAssertEqual(boundary.rejected, 0)
        XCTAssertEqual(boundary.sortScratchBytes, 0)
        // Exact-request admission can vary with allocator backing; the actual-byte ceiling cannot.
        if goodSize > byteLimit {
            XCTAssertEqual(boundary.failure?.reason, .controlStagingBudgetExceeded)
        }
        if let failure = boundary.failure {
            let expected = OfflineControlFailure(reason: .controlStagingBudgetExceeded, key: nil, voice: nil, frameOrigin: 0)
            XCTAssertEqual(failure, expected)
            XCTAssertEqual(boundary.allocatedBytes, 0)
            XCTAssertEqual(boundary.intended, limit)
            XCTAssertThrowsError(try boundary.requireSuccess()) { error in
                XCTAssertEqual(error as? OfflineControlFailure, expected)
            }
        } else {
            try boundary.requireSuccess()
            XCTAssertGreaterThanOrEqual(boundary.allocatedBytes, requestedBytes)
            XCTAssertLessThanOrEqual(boundary.allocatedBytes, byteLimit)
            XCTAssertEqual(boundary.intended, 0)
        }
        let (song, plan) = resetPlan(count: limit + 1, frame: { $0 / 100 + 1 })
        let request = AdmissionInputs.request(song, rate: 48_000, frames: (limit + 1) / 100 + 2)
        let session = R(preparedPlan: plan).prepare(request)
        XCTAssertEqual(session.controlAdmission.failure?.reason, .controlStagingBudgetExceeded)
        XCTAssertEqual(session.controlAdmission.allocatedBytes, 0)
        XCTAssertEqual(session.render(frames: request.boundedFrameCount).frameCount, 0)
    }

    func testWholeSplitStreamingAndExplicitWindowsMatchOnTheMixedLifetimeRange() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let song = AdmissionInputs.mixed(tremor: true, linear: linear, rows: 24), plan = AdmissionInputs.plan(song, rate: rate)
            let frames = 24 * 6 * Int(rate / 100), request = AdmissionInputs.request(song, rate: rate, frames: frames)
            let renderer = R(preparedPlan: plan), full = renderer.render(request)
            try full.controlAdmission.requireSuccess()
            let split = renderer.render(request, splitFrameCounts: [1, 17, 257, 4093, frames - 4368])
            XCTAssertEqual(split.block.interleavedPCM, full.block.interleavedPCM)
            var pcm = [Float]()
            let streaming = renderer.renderStreaming(request, chunkFrameCount: 257) { _, _, block in
                pcm.append(contentsOf: block.interleavedPCM)
            }
            try streaming.controlAdmission.requireSuccess()
            XCTAssertEqual(pcm, full.block.interleavedPCM)
            XCTAssertEqual(renderer.renderWindowed(request, windowRows: 1).block.interleavedPCM, full.block.interleavedPCM)
            XCTAssertEqual(renderer.renderWindowedUsingScanPerWindowSchedulingReference(request, windowRows: 1).block.interleavedPCM,
                full.block.interleavedPCM)
            enum Cancel: Error { case requested }
            var callbacks = 0
            XCTAssertThrowsError(try renderer.renderStreaming(request, chunkFrameCount: 257) { _, _, _ in
                callbacks += 1; throw Cancel.requested
            })
            XCTAssertEqual(callbacks, 1)
        } }
    }

    func testShortCaptureIsInvalidAndCannotSubmitItsPartialSchedule() {
        let admission = OfflineControlAdmission(stagingCount: 2), mixer = mixer(48_000)
        admission.submit(family: 0, parent: 0, source: 0, voice: 0, frame: 1, on: mixer, value: .step(1))
        admission.finishCapture()
        XCTAssertEqual(admission.snapshot.failure?.reason, .invalidControl)
        admission.refill(on: mixer, voices: [0: 0]) { _ in .step(1) }
        XCTAssertEqual(admission.snapshot.accepted, 0)
        XCTAssertThrowsError(try admission.snapshot.requireSuccess())
    }

    func testCLIExportBranchesRejectNativeAdmissionFailureWithoutChangingDestination() throws {
        let (song, plan) = resetPlan(count: 4097, frame: { _ in 1 })
        let request = AdmissionInputs.request(song, rate: 48_000, frames: 64)
        let renderer = R(preparedPlan: plan)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vtx-cli-control-refusal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let branches = [[], ["--progress"], ["--window-rows", "1", "--progress"]]
        for (index, flags) in branches.enumerated() { for existing in [false, true] {
            let output = directory.appendingPathComponent("branch-\(index)-\(existing).wav")
            let sentinel = Data("existing completed destination".utf8)
            if existing { try sentinel.write(to: output) }
            let before = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
            let arguments = try RenderToolArguments.parse(["--input", "unused-synthetic.xm", "--output", output.path,
                "--order", "0", "--rows", "1", "--sample-rate", "48000"] + flags)
            var messages = [String]()
            let tool = RenderTool(progressOutput: { messages.append($0) })
            XCTAssertThrowsError(try tool.renderAndExportWAV(request, to: output, renderer: renderer,
                arguments: arguments, startedAt: Date())) { error in
                XCTAssertEqual((error as? OfflineControlFailure)?.reason, index == 2 ? .stateQueueCapacity : .singleFrameCapacity)
            }
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), before)
            if existing { XCTAssertEqual(try Data(contentsOf: output), sentinel) }
            else { XCTAssertFalse(FileManager.default.fileExists(atPath: output.path)) }
            XCTAssertFalse(messages.contains { $0.contains("writing WAV") || $0.contains("export succeeded") || $0.contains("100%") })
        } }
    }

    func testInvalidControlDominatesCapacityAndFailedPreparedResetStaysFailed() {
        let admission = OfflineControlAdmission(), mixer = mixer(48_000)
        for ordinal in 0...4096 {
            admission.submit(family: 0, parent: ordinal, source: 0, voice: 0, frame: 1, on: mixer, value: .step(1))
        }
        XCTAssertEqual(admission.snapshot.failure?.reason, .stateQueueCapacity)
        admission.submit(family: 0, parent: 4097, source: 0, voice: 0, frame: 1, on: mixer, value: .step(.nan))
        XCTAssertEqual(admission.snapshot.failure?.reason, .invalidControl)
        XCTAssertTrue(admission.hadInvalidControl)
        XCTAssertEqual(admission.snapshot.rejected, 2)
        let (song, plan) = resetPlan(count: 4097, frame: { _ in 1 })
        let session = R(preparedPlan: plan).prepare(AdmissionInputs.request(song, rate: 48_000, frames: 64))
        let failed = session.controlAdmission
        session.reset()
        XCTAssertEqual(session.controlAdmission, failed)
        XCTAssertEqual(session.render(frames: 64).frameCount, 0)
        XCTAssertEqual(session.controlAdmission.failure?.reason, .singleFrameCapacity)
    }

    #if DEBUG
    func testSourceCheckpointsReuseAllFourteenProducerSelectionsWithoutNewTiming() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let song = AdmissionInputs.allFamilies(linear: linear), unit = Int(rate / 50)
            var plan = AdmissionInputs.plan(song, rate: rate)
            plan.xmEnvelopeTimeline = nil
            plan.initialHeldPitchEventIndices = [14]
            plan.playbackStateEvents += [
                .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 1, change: .reset(allReset)),
                .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 1, change: .keyOff(fadeoutDecrement: 0))]
            let request = AdmissionInputs.request(song, rate: rate, frames: 30 * unit)
            let eager = R(preparedPlan: plan).prepare(request), checkpoint = R(preparedPlan: plan).prepare(request)
            eager.configureAdmissionForTesting(forceSlow: false)
            checkpoint.configureSourceAdmissionForTesting(boundaries: [1, 2, unit, unit + 1, 6 * unit + 1, 12 * unit + 1])
            assertSourcePCM(checkpoint.render(frames: request.boundedFrameCount).interleavedPCM,
                eager.render(frames: request.boundedFrameCount).interleavedPCM)
            try checkpoint.controlAdmission.requireSuccess()
            let reference = Dictionary(uniqueKeysWithValues: eager.controlLedgerForTesting.map { ($0.key.ordinal, $0) })
            XCTAssertEqual(Set(reference.values.map { Int($0.key.family) }), Set(0...13))
            XCTAssertEqual(checkpoint.controlAdmission.intended, eager.controlAdmission.intended)
            XCTAssertEqual(checkpoint.controlAdmission.accepted + checkpoint.controlAdmission.cancelled, checkpoint.controlAdmission.intended)
            for entry in checkpoint.controlLedgerForTesting {
                let original = try XCTUnwrap(reference[entry.key.ordinal])
                // Physical slots change at checkpoints; the logical key and exact value do not.
                XCTAssertEqual(entry.key, original.key)
                XCTAssertEqual(entry.value, original.value)
                XCTAssertEqual(entry.accepted, original.accepted)
            }
        } }
    }

    func testForcedSlowLedgerPreservesAllFourteenRealProducerSelectionsAndPhysicalPlans() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            let song = AdmissionInputs.allFamilies(linear: linear)
            var plan = AdmissionInputs.plan(song, rate: rate)
            plan.xmEnvelopeTimeline = nil
            plan.initialHeldPitchEventIndices = [14]
            plan.playbackStateEvents += [
                .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 1, change: .reset(allReset)),
                .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: 1, change: .keyOff(fadeoutDecrement: 0))]
            let request = AdmissionInputs.request(song, rate: rate, frames: 5 * 6 * Int(rate / 100))
            let eager = R(preparedPlan: plan).prepare(request), staged = R(preparedPlan: plan).prepare(request)
            eager.configureAdmissionForTesting(forceSlow: false)
            staged.configureAdmissionForTesting(forceSlow: true)
            let expected = eager.render(frames: request.boundedFrameCount).interleavedPCM
            XCTAssertEqual(staged.render(frames: request.boundedFrameCount).interleavedPCM, expected)
            try eager.controlAdmission.requireSuccess(); try staged.controlAdmission.requireSuccess()
            let chronological = eager.controlLedgerForTesting.sorted {
                $0.key.frame == $1.key.frame ? $0.key.ordinal < $1.key.ordinal : $0.key.frame < $1.key.frame
            }
            XCTAssertEqual(staged.controlLedgerForTesting, chronological)
            XCTAssertEqual(Set(chronological.map { Int($0.key.family) }), Set(0...13))
            XCTAssertEqual(staged.plan, eager.plan)
            XCTAssertFalse(eager.controlAdmission.usedSlowPath)
            XCTAssertTrue(staged.controlAdmission.usedSlowPath)
        } }
    }

    func testAllNineNativeAPIsKeepTypedValuesAndEqualFrameCallOrderInSharedAdmission() throws {
        for rate in [44_100.0, 48_000] {
            let values: [(voice: Int, frame: Int, value: OfflineControlValue)] = [
                (0, 10, .state(.reset(allReset))), (0, 10, .state(.keyOff(fadeoutDecrement: 0.0001))),
                (0, 10, .gainPan(0.3, 0.4)), (0, 10, .step(0.5)), (0, 10, .position(7)),
                (0, 10, .combined(0.6, 0.7, 1.5)), (1, 10, .cut), (1, 10, .rampDown(4)),
                (2, 10, .retirement), (2, 11, .step(7))]
            let eagerMixer = mixer(rate), stagedMixer = mixer(rate)
            let eager = OfflineControlAdmission(), staged = OfflineControlAdmission(stagingCount: values.count)
            eager.ledger = []; staged.ledger = []
            for (ordinal, item) in values.enumerated() {
                for (admission, mixer) in [(eager, eagerMixer), (staged, stagedMixer)] {
                    admission.submit(family: ordinal, parent: ordinal, source: item.voice, voice: item.voice,
                        frame: item.frame, on: mixer, value: item.value)
                }
            }
            staged.finishCapture()
            staged.refill(on: stagedMixer, voices: [0: 0, 1: 1, 2: 2]) { values[Int($0.parent)].value }
            try assertComplete(eager.snapshot, expected: values.count)
            try assertComplete(staged.snapshot, expected: values.count)
            XCTAssertEqual(staged.ledger, eager.ledger)
            XCTAssertEqual(stagedMixer.render(frames: 400).interleavedPCM, eagerMixer.render(frames: 400).interleavedPCM)
            XCTAssertEqual(stagedMixer.voiceDiagnostic(forVoiceAt: 0)?.sampleStep, 1.5)
            XCTAssertEqual(stagedMixer.voiceDiagnostic(forVoiceAt: 2)?.sampleStep, 1)
            XCTAssertEqual(stagedMixer.voiceDiagnostic(forVoiceAt: 2)?.active, false)
        }
    }
    #endif

    private func assertComplete(_ status: OfflineControlAdmissionSnapshot, expected: Int,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        try status.requireSuccess()
        XCTAssertEqual(status.intended, expected, file: file, line: line)
        XCTAssertEqual(status.accepted, expected, file: file, line: line)
        XCTAssertEqual(status.cancelled, 0, file: file, line: line)
        XCTAssertEqual(status.rejected, 0, file: file, line: line)
        XCTAssertEqual(status.pending, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(status.peakQueuedCount, 4096, file: file, line: line)
        XCTAssertLessThanOrEqual(status.allocatedBytes, 8 * 1024 * 1024, file: file, line: line)
        XCTAssertEqual(status.sortScratchBytes, 0, file: file, line: line)
    }

    private func record(_ session: PlaybackSongOfflineRenderSession) {
        #if DEBUG
        session.configureAdmissionForTesting(forceSlow: false)
        #endif
    }

    private func render(_ session: PlaybackSongOfflineRenderSession, frames: Int, blocks: [Int]) -> [Float] {
        var pcm = [Float](), rendered = 0, index = 0
        while rendered < frames {
            let count = min(blocks[index % blocks.count], frames - rendered)
            let block = session.render(frames: count)
            XCTAssertEqual(block.frameCount, count)
            guard block.frameCount > 0 else { break }
            pcm.append(contentsOf: block.interleavedPCM)
            rendered += block.frameCount; index += 1
        }
        return pcm
    }

    private func resetPlan(count: Int, frame: (Int) -> Int) -> (PlaybackSong, PlaybackSongSyntheticPlan) {
        let song = AdmissionInputs.single()
        var plan = AdmissionInputs.plan(song, rate: 48_000)
        plan.xmEnvelopeTimeline = nil
        plan.playbackStateEvents = (0..<count).map {
            .init(activeEventIndex: 0, channelIndex: 0, scheduledFrame: frame($0), change: .reset(allReset))
        }
        return (song, plan)
    }

    private func mixer(_ rate: Double) -> CSoftwareMixer {
        let mixer = CSoftwareMixer(config: .init(sampleRate: rate, channelCount: 1))
        for _ in 0..<3 {
            _ = mixer.addVoice(sample: .init(monoPCM: (0..<64).map { Float($0 - 32) / 128 }),
                playbackStep: 1, loop: .init(mode: .forward, startFrame: 0, endFrame: 64))
        }
        return mixer
    }
}

/// Original model inputs isolate real controls without external modules or fixture files.
private enum AdmissionInputs {
    static func compact(rows: Int, tremor: Bool = true, linear: Bool = true) -> PlaybackSong {
        let cells = (0..<rows).map { row in
            (0..<32).map { _ in cell(tremor ? 29 : 0, note: row == 0 ? 49 : 0, instrument: 1) }
        }
        return song(cells, linear: linear, speed: 3)
    }

    static func mixed(tremor: Bool, linear: Bool, rows: Int = 520) -> PlaybackSong {
        let cells = (0..<rows).map { row in
            (0..<32).map { channel -> PlaybackCell in
                if row == 0 { return cell(tremor ? 29 : 0, tremor ? 0x11 : 0, note: 49, instrument: 1) }
                if row == 4 && channel < 8 { return cell(tremor ? 29 : 0, note: 53) }
                if row == 8 && channel < 4 { return cell(tremor ? 29 : 0, note: 97) }
                if row == 12 && channel < 4 { return cell(tremor ? 29 : 0, note: 49, instrument: 1) }
                if row % 64 == 16 && channel == 31 { return cell(16, 32) }
                if row % 64 == 20 && channel == 31 { return cell(16, 64) }
                return row % 4 == 3 ? cell(instrument: 1) :
                    cell(tremor ? 29 : 0, tremor && row % 4 == 0 ? 0x11 : 0)
            }
        }
        return song(cells, linear: linear, speed: 6)
    }

    static func allFamilies(linear: Bool) -> PlaybackSong {
        var cells = Array(repeating: Array(repeating: cell(), count: 15), count: 5)
        cells[0] = Array(repeating: cell(note: 49, instrument: 1), count: 15)
        cells[1][1] = cell(21, 2)
        cells[1][2] = cell(12, 24)
        cells[1][3] = cell(3, 4, note: 53)
        cells[1][4] = cell(1, 2)
        cells[1][5] = cell(14, 0x11)
        cells[1][6] = cell(14, 0x22)
        cells[1][7] = cell(33, 0x11)
        cells[1][8] = cell(0, 0x37)
        cells[1][9] = cell(4, 0x48)
        cells[1][11] = cell(14, 0x92)
        cells[3][12] = cell(note: 53)
        return song(cells, linear: linear, speed: 6, envelope: true, automatic: true)
    }

    static func single(linear: Bool = true) -> PlaybackSong {
        song([[cell(note: 49, instrument: 1)], [cell()]], linear: linear, speed: 3)
    }

    static func request(_ song: PlaybackSong, rate: Double, frames: Int) -> PlaybackSongOfflineRenderRequest {
        .init(song: song, orderCount: song.orders.count, config: .init(sampleRate: rate), frames: frames)
    }

    static func plan(_ song: PlaybackSong, rate: Double) -> PlaybackSongSyntheticPlan {
        PlaybackSongSyntheticAdapter.adapt(song, startOrderIndex: 0, orderCount: song.orders.count, sampleRate: rate)
    }

    static func cell(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0,
                     instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private static func song(_ cells: [[PlaybackCell]], linear: Bool, speed: Int,
                             envelope: Bool = false, automatic: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: (0..<256).map { Float($0 - 128) / 512 }, volume: 0.75, panning: 128,
            relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: 256, loopType: 1)
        let volumeEnvelope = envelope ? PlaybackVolumeEnvelope(enabled: true,
            points: [.init(tick: 0, value: 64), .init(tick: 5, value: 48), .init(tick: 20, value: 32)],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 0) : .disabled
        let count = (cells.count + 127) / 128
        let patterns = Dictionary(uniqueKeysWithValues: (0..<count).map { index in
            let start = index * 128, end = min(cells.count, start + 128)
            return (index, PlaybackPattern(index: index, rows: (start..<end).map {
                .init(index: $0 - start, cells: cells[$0])
            }))
        })
        return PlaybackSong(title: "Original offline control admission",
            orders: (0..<count).map { .init(orderIndex: $0, patternIndex: $0) }, patternsByIndex: patterns,
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: volumeEnvelope,
                autoVibrato: automatic ? .init(depth: 4, rate: 5) : .disabled,
                noteSampleMap: Array(repeating: 0, count: 96))],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 250),
            usesLinearFrequencyTable: linear)
    }
}
