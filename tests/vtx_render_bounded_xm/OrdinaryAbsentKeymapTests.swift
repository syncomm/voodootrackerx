import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class OrdinaryAbsentKeymapTests: XCTestCase {
    private typealias A = PlaybackSongSyntheticAdapter
    private typealias R = PlaybackSongOfflineRenderer

    func testNilPCMAndNeutralRoutesDoNotStartOrCutAtImmediateED0OrED3Dispatch() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for neutral in [false, true] { for cold in [false, true] { for delay in [-1, 0, 3] {
                let prefix = cold ? c() : c(49, 1)
                let dispatch = c(61, 2, effect: delay < 0 ? 0 : 14, param: delay < 0 ? 0 : UInt8(0xD0 + delay))
                let input = song([prefix, dispatch, c()], linear: linear, neutral: neutral)
                let result = R().render(.init(song: input, config: .init(sampleRate: rate), rows: 3))
                let plan = result.plan
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), cold ? [] : [1])
                XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
                XCTAssertTrue(plan.xmEmptyRoutes.isEmpty, "Absent routing must not acquire mapped-empty cuts")
                XCTAssertEqual(plan.xmChannelRows.last?.controls.activeEventIndex, cold ? nil : 0)
                let ignored = try XCTUnwrap(plan.diagnostics.ignoredCells.first { $0.source.rowIndex == 1 })
                XCTAssertFalse(ignored.sampleMapKeymapPresent)
                XCTAssertNil(ignored.mappedSampleIndex)
                XCTAssertEqual(ignored.sampleSelectionMethod, .skippedNoValidSample)
                XCTAssertFalse(ignored.firstPlayableSampleFallbackUsed)
                let control = song([prefix, c(), c()], linear: linear, neutral: neutral)
                XCTAssertEqual(result.block.interleavedPCM,
                    R().render(.init(song: control, config: .init(sampleRate: rate), rows: 3)).block.interleavedPCM)
                let boundary = (6 + max(0, delay)) * Int(rate / 50)
                if cold { XCTAssertTrue(result.block.interleavedPCM.allSatisfy { $0 == 0 }) }
                else {
                    XCTAssertTrue(R.hasActiveSource(eventIndex: 0, at: boundary + 1, plan: plan))
                    XCTAssertGreaterThan(result.block.interleavedPCM[boundary * 2 + 2], 0)
                }
                let windowed = R().renderWindowed(.init(song: input, config: .init(sampleRate: rate), rows: 3), windowRows: 1)
                assertPCM(result.block.interleavedPCM, windowed.block.interleavedPCM)
                XCTAssertEqual(RuntimeCMixerAdapterEventPlan.make(song: input, sampleRate: rate).plan, plan)
                XCTAssertNil(input.instrumentsByIndex[2]?.noteSampleMap)
            } } }
        } }
    }

    func testNilToneTargetsPreserveSourceAndExistingSlideWithoutSelectingPCM() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for neutral in [false, true] { for cold in [false, true] {
                for (fx, byte, volume): (UInt8, UInt8, UInt8) in [(3, 4, 0), (5, 0, 0), (0, 0, 0xF1)] {
                    let prefix = cold ? [c(), c()] : [c(49, 1), c(53, 1, effect: 3, param: 4)]
                    let target = c(61, 2, volume: volume, effect: fx, param: byte)
                    let input = song(prefix + [target, c(effect: 3)], linear: linear, neutral: neutral)
                    let request = PlaybackSongOfflineRenderRequest(song: input, config: .init(sampleRate: rate), rows: 4)
                    let result = R().render(request), plan = result.plan
                    XCTAssertEqual(plan.diagnostics.eventMappings.map(\.instrumentIndex), cold ? [] : [1])
                    XCTAssertTrue(plan.xmEmptyRoutes.isEmpty)
                    XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
                    let after = try XCTUnwrap(plan.xmChannelRows.last).controls
                    XCTAssertEqual(after.activeEventIndex, cold ? nil : 0)
                    if !cold {
                        XCTAssertEqual(after.tonePortamentoTargetNote, 53)
                        let control = song(prefix + [c(volume: volume, effect: fx, param: byte), c(effect: 3)], linear: linear)
                        assertPCM(result.block.interleavedPCM,
                            R().render(.init(song: control, config: .init(sampleRate: rate), rows: 4)).block.interleavedPCM)
                    } else { XCTAssertTrue(result.block.interleavedPCM.allSatisfy { $0 == 0 }) }
                    assertPCM(result.block.interleavedPCM, R().renderWindowed(request, windowRows: 1).block.interleavedPCM)
                }
            } }
        } }
    }

    func testExactMapSelectsDistinguishableSparsePCMAndMissingRouteRetainsIdentity() throws {
        for linear in [true, false] { for rate in [44_100.0, 48_000] {
            for slot in [3, 7] {
                let input = song([c(49, 1), c(61, 2), c()], linear: linear, destination: slot)
                let result = R().render(.init(song: input, config: .init(sampleRate: rate), rows: 3))
                let plan = result.plan, frame = 6 * Int(rate / 50) + Int(rate / 100)
                XCTAssertEqual(plan.diagnostics.eventMappings.map(\.sampleIndex), slot == 3 ? [0, 3] : [0])
                if slot == 3 {
                    let mapping = try XCTUnwrap(plan.diagnostics.eventMappings.last)
                    XCTAssertEqual(mapping.sampleSelectionMethod, .sampleMap)
                    XCTAssertEqual(mapping.mappedSampleIndex, 3)
                    XCTAssertEqual(plan.pattern.events[1].sample.monoPCM, Array(repeating: -0.25, count: 256))
                    XCTAssertLessThan(result.block.interleavedPCM[frame * 2], 0)
                } else {
                    let ignored = try XCTUnwrap(plan.diagnostics.ignoredCells.first { $0.source.rowIndex == 1 })
                    XCTAssertTrue(ignored.sampleMapKeymapPresent)
                    XCTAssertEqual(ignored.mappedSampleIndex, 7)
                    XCTAssertEqual(ignored.sampleSelectionMethod, .skippedNoValidSample)
                    XCTAssertGreaterThan(result.block.interleavedPCM[frame * 2], 0)
                }
                XCTAssertTrue(plan.diagnostics.eventMappings.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
            }
        } }
    }

    func testLoadedShortAndPartialSampledHeadersRemainUnchangedAndCannotFallback() throws {
        // Independently authored bytes: both a short header and a partial 95-note
        // LUT reach the existing read-only loader with PCM and honest nil routing.
        for size in [33, 128] {
            let directory = URL(fileURLWithPath: "/private/tmp/vtx-policy-b-loaded-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("synthetic-short-header.xm")
            let bytes = loadedFixture(headerSize: size)
            try bytes.write(to: url)
            let loaded = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
            let instrument = try XCTUnwrap(loaded.instrumentsByIndex[1])
            XCTAssertNil(instrument.noteSampleMap)
            XCTAssertEqual(instrument.samples.map(\.sampleIndex), [0, 1])
            XCTAssertNotEqual(instrument.samples[0].pcm, instrument.samples[1].pcm)
            for rate in [44_100.0, 48_000] {
                let result = R().render(.init(song: loaded, config: .init(sampleRate: rate), rows: 4))
                XCTAssertTrue(result.plan.pattern.events.isEmpty)
                XCTAssertTrue(result.plan.xmEmptyRoutes.isEmpty)
                XCTAssertTrue(result.block.interleavedPCM.allSatisfy { $0 == 0 })
                XCTAssertTrue(result.plan.diagnostics.ignoredCells.allSatisfy { !$0.firstPlayableSampleFallbackUsed })
            }
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertEqual(loaded.instrumentsByIndex[1], instrument)
        }
    }

    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, volume: UInt8 = 0,
                   effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: param)
    }

    private func song(_ cells: [PlaybackCell], linear: Bool, neutral: Bool = false, destination: Int? = nil) -> PlaybackSong {
        func sample(_ instrument: Int, _ slot: Int, _ value: Float) -> PlaybackSample {
            .init(instrumentIndex: instrument, sampleIndex: slot, pcm: Array(repeating: value, count: 256),
                volume: 0.5, panning: 128, relativeNote: 0, finetune: 0, baseSampleRate: 8363,
                loopStart: 0, loopLength: 256, loopType: 1)
        }
        return .init(title: "Policy B synthetic routing", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: cells.enumerated().map { .init(index: $0.offset, cells: [$0.element]) })],
            instrumentsByIndex: [1: .init(index: 1, samples: [sample(1, 0, 0.25)], noteSampleMap: Array(repeating: 0, count: 96)),
                2: .init(index: 2, samples: neutral ? [] : [sample(2, 0, 0.125), sample(2, 3, -0.25)],
                    noteSampleMap: destination.map { Array(repeating: $0, count: 96) })],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .xmDefault, usesLinearFrequencyTable: linear)
    }

    private func loadedFixture(headerSize: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: 336)
        func put(_ n: Int, at offset: Int, count: Int) {
            for i in 0..<count { bytes[offset + i] = UInt8(truncatingIfNeeded: n >> (8 * i)) }
        }
        bytes.replaceSubrange(0..<17, with: Array("Extended Module: ".utf8))
        bytes[37] = 0x1A; put(0x0104, at: 58, count: 2); put(276, at: 60, count: 4)
        for (offset, n) in [(64, 1), (68, 1), (70, 1), (72, 1), (74, 1), (76, 6), (78, 125)] { put(n, at: offset, count: 2) }
        let cells = [c(49, 1), c(61, 1, effect: 3, param: 4), c(49, 1, effect: 14, param: 0xD0), c(49, 1, effect: 14, param: 0xD3)]
        bytes += [9, 0, 0, 0, 0, 4, 0, 20, 0]
        for cell in cells { bytes += [cell.note, cell.instrument, cell.volumeColumn, cell.effectType, cell.effectParam] }
        let start = bytes.count
        bytes += Array(repeating: 0, count: headerSize)
        put(headerSize, at: start, count: 4); put(2, at: start + 27, count: 2); put(40, at: start + 29, count: 4)
        for _ in 0..<2 {
            let header = bytes.count
            bytes += Array(repeating: 0, count: 40)
            put(256, at: header, count: 4); put(256, at: header + 8, count: 4)
            bytes[header + 12] = 32; bytes[header + 14] = 1; bytes[header + 15] = 128
        }
        for value: UInt8 in [16, 224] { bytes += [value] + Array(repeating: 0, count: 255) }
        return Data(bytes)
    }

    private func assertPCM(_ lhs: [Float], _ rhs: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        XCTAssertLessThanOrEqual(zip(lhs, rhs).map { abs($0 - $1) }.max() ?? 0, 1e-7, file: file, line: line)
    }
}
