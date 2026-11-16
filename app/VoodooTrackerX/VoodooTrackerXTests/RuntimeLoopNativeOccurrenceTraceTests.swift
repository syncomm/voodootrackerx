import Foundation
import XCTest

final class RuntimeLoopNativeOccurrenceTraceTests: XCTestCase {
    func testNormalTraceNilAdditionsPreserveExactJSON() throws {
        let event = RuntimeCMixerTraceEvent(runtimeAction: "control", runtimeAudioBackend: "c_mixer")
        let data = try RuntimeCMixerTraceJSONLFormatter.line(for: event)
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
            "{\"runtimeAction\":\"control\",\"runtimeAudioBackend\":\"c_mixer\",\"schemaVersion\":1,\"targetScope\":\"none\",\"targetedAllVoices\":false}\n")
    }

    func testOccurrenceKeepsOriginalNumbersAndDistinguishesImportedBirthScope() throws {
        let scope = RuntimeLoopNativeScope(documentHigh: 1, documentLow: 2, sourceGeneration: 4,
            transportEpoch: 9, sampleRateBits: 48_000.0.bitPattern, semanticVersion: 1,
            linearFrequencyMode: true, order: 0, pattern: 0, firstRow: 0, lastRow: 3)
        let birth = RuntimeLoopNativeSourceIdentity(sourceGeneration: 3, transportEpoch: 9,
            birthSequence: 1, birthEventIndex: 17)
        let occurrence = RuntimeLoopNativeOccurrence(scope: scope, sequence: 2, eventID: 7,
            eventOrdinal: 8, localSourceIndex: 0,
            source: .init(orderIndex: 0, patternIndex: 0, rowIndex: 2), tick: 1, channel: 0,
            opcode: 2, plannedFrame: 512, appliedFrame: 512, targetBirth: birth,
            sourceBefore: birth, sourceAfter: birth, nativeVoiceIndex: 5, disposition: 0)
        let event = RuntimeCMixerTraceEvent(runtimeAction: "user_loop_native_occurrence",
            runtimeAudioBackend: "c_mixer", plannedEventID: 7, loopOccurrence: .init(occurrence),
            adapterActiveEventIndex: 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: RuntimeCMixerTraceJSONLFormatter.line(for: event)) as? [String: Any])
        XCTAssertEqual(object["plannedEventID"] as? Int, 7)
        XCTAssertEqual(object["adapterActiveEventIndex"] as? Int, 0)
        let capsule = try XCTUnwrap(object["loopOccurrence"] as? [String: Any])
        XCTAssertEqual(capsule["eventID"] as? Int, 7)
        XCTAssertEqual(capsule["eventOrdinal"] as? Int, 8)
        XCTAssertEqual(capsule["localSourceIndex"] as? Int, 0)
        let target = try XCTUnwrap(capsule["targetBirth"] as? [String: Any])
        XCTAssertEqual(target["sourceGeneration"] as? Int, 3)
        XCTAssertEqual(target["birthSequence"] as? Int, 1)
        XCTAssertEqual(target["birthEventIndex"] as? Int, 17)
        let current = try XCTUnwrap(capsule["scope"] as? [String: Any])
        XCTAssertEqual(current["sourceGeneration"] as? Int, 4)
        XCTAssertEqual(capsule["plannedRuntimeFrame"] as? Int, 512)
        XCTAssertEqual(capsule["appliedRuntimeFrame"] as? Int, 512)
    }

    @MainActor
    func testStoppedBackendDrainsNativeOccurrencesBeforeCoreResetAndOnlyOnce() throws {
        let recorder = NativeOccurrenceTraceRecorder()
        let output = RuntimeCMixerAudioEngine(sampleRate: 48_000, channelCount: 1,
            startsOutputHostOnDemand: false, traceWriter: recorder)
        let sample = makePlaybackSample(pcm: [0.25, -0.25, 0.125, -0.125], baseSampleRate: 8363,
            loopStart: 0, loopLength: 4, loopType: 1)
        let song = makePlaybackSong(orderPatternIndices: [0], patternRowsByIndex: [0: [
            makePlaybackRow(index: 0, note: 49, instrument: 1), makePlaybackRow(index: 1)]],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample], noteSampleMap: Array(repeating: 0, count: 96))],
            initialTiming: .init(speed: 3, bpm: 125))
        let scope = RuntimeLoopNativeScope(documentHigh: 1, documentLow: 2, sourceGeneration: 3,
            transportEpoch: 9, sampleRateBits: 48_000.0.bitPattern, semanticVersion: 1,
            linearFrequencyMode: song.usesLinearFrequencyTable, order: 0, pattern: 0, firstRow: 0, lastRow: 1)
        let session = RuntimeLoopPlanningSession(song: song,
            origin: .init(orderIndex: 0, patternIndex: 0, rowIndex: 0), scope: scope,
            workerQueue: .init(label: "public.loop.trace.stop"), horizonFrames: 512, maximumRows: 8)
        defer { output.stopAll(); session.cancelAndWait() }
        guard case let .ready(prepared) = session.waitForPreparation(timeout: 5) else {
            return XCTFail("Expected public Loop preparation")
        }
        XCTAssertTrue(output.configureRuntimeUserLoop(session, preparation: prepared))
        _ = output.renderForTesting(frameCount: 128)
        XCTAssertFalse(recorder.events.contains { $0.loopOccurrence != nil })
        output.stopAll(context: nil, reason: "public_trace_stop")
        XCTAssertEqual(output.snapshotForTesting().currentFrame, 0)
        let occurrences = recorder.events.compactMap(\.loopOccurrence)
        XCTAssertFalse(occurrences.isEmpty)
        XCTAssertTrue(occurrences.allSatisfy { $0.scope == scope && $0.plannedRuntimeFrame == $0.appliedRuntimeFrame })
        let summaries = recorder.events.compactMap(\.loopOccurrenceSummary)
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summary.recordedOccurrences, occurrences.count)
        XCTAssertEqual(summary.attemptedOccurrences, summary.appliedOccurrences + summary.suppressedOccurrences + summary.failedOccurrences)
        XCTAssertEqual(summary.droppedOccurrences, 0)
        let count = occurrences.count
        output.stopAll()
        XCTAssertEqual(recorder.events.compactMap(\.loopOccurrence).count, count)
        XCTAssertEqual(recorder.events.compactMap(\.loopOccurrenceSummary).count, 1)
    }
}

@MainActor
private final class NativeOccurrenceTraceRecorder: RuntimeCMixerTraceWriting {
    let isEnabled = true
    var events = [RuntimeCMixerTraceEvent]()
    func record(_ event: RuntimeCMixerTraceEvent) { events.append(event) }
    func flush() {}
}
