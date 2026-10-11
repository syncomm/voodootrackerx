import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

final class GlobalVolumeProjectionTests: XCTestCase {
    typealias Adapter = PlaybackSongSyntheticAdapter

    func testLateWriterCopiesFullControlsOnlyForPublishedTargets() throws {
        for count in [16, 32, 64] {
            for channels in [2, 4] {
                var rows = Array(repeating: Array(repeating: c(), count: channels), count: count)
                rows[0] = Array(repeating: c(note: 49, instrument: 1), count: channels)
                rows[count - 1][0] = c(17, 1)
                let sink = Sink()
                let profile = AdapterPlanProfileSession(lifecycle: "test", clock: MonotonicAdapterPlanProfileClock(), sink: sink)
                let plan = Adapter.adapt(song(rows), startOrderIndex: 0, orderCount: 2, sampleRate: 48_000, profileSession: profile)
                let fields = try XCTUnwrap(sink.fields)
                XCTAssertEqual(fields["projection_record_stride"], 16)
                XCTAssertEqual(fields["projection_record_count"], count * channels)
                XCTAssertEqual(fields["projection_logical_bytes"], count * channels * 16)
                XCTAssertEqual(fields["peak_projection_record_count"], channels)
                XCTAssertEqual(fields["channel_turn_count"], count * channels * 6)
                XCTAssertEqual(fields["full_controls_turn_copy_count"], 0)
                // Plain sources publish on the five nonzero H ticks, not tick zero or the tail.
                XCTAssertEqual(fields["target_state_materialization_count"], channels * 5)
                XCTAssertEqual(plan.diagnostics.voiceStateUpdates.filter {
                    if case .hxyChannelTarget = $0.command { return true }; return false
                }.count, channels * 5)
            }
        }
    }

    func testCanonicalTransitionsAndHeldTargetsStayDistinct() {
        let plan = Adapter.adapt(song([[c(16, 32, note: 49, instrument: 1), c(note: 49, instrument: 1), c(note: 49, instrument: 1)],
            [c(17, 1), c(), c(17, 0x10)], [c(), c(), c()]]), startOrderIndex: 0, orderCount: 2, sampleRate: 48_000)
        let targets = plan.diagnostics.voiceStateUpdates.filter { if case .hxyChannelTarget = $0.command { return true }; return false }
        XCTAssertEqual(targets.filter { $0.syntheticRow == 1 && $0.syntheticTick == 1 }.map(\.globalVolumeAfter), [31, 31, 32])
        XCTAssertEqual(plan.diagnostics.voiceStateUpdates.last { $0.effectType == 17 && $0.applied }?.globalVolumeAfter, 32)
        for channel in 0..<3 {
            XCTAssertEqual(targets.last { $0.channelIndex == channel }?.gainAfter, Float(channel == 2 ? 32 : 31) / 128)
        }
        XCTAssertTrue(targets.filter { $0.syntheticRow == 2 }.isEmpty)
    }

    #if DEBUG
    func testFrozenProjectionMatchesSyntheticWriterAndSourceLifecycles() throws {
        for rate in [44_100.0, 48_000] {
            for speed in [1, 3, 6] {
                for parameter: UInt8 in [1, 0x10, 0x12] {
                    for envelope in [false, true] {
                        for loop in [0, 1] {
                            let module = song(lifecycleRows(parameter, speed), speed: speed, loop: loop, envelope: envelope)
                            for start in [0, 1] {
                                try assertEquivalent(module, rate: rate, start: start, pcm: speed == 3 && parameter == 0x12)
                            }
                        }
                    }
                }
            }
        }
    }

    func testFrozenProjectionMatchesPublicFixturesWindowsAndIndependentRebuilds() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated")
        for name in ["global-volume-publication", "global-volume-slide-timing", "global-volume-slide-memory",
                     "cold-a00-output-restoration", "cold-500-local-publication", "cold-600-local-publication",
                     "fine-volume-directional-memory", "fine-pitch-directional-memory", "extra-fine-pitch-directional-memory"] {
            let path = directory.appendingPathComponent(name + ".xm").path
            let module = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: path), modulePath: path)
            for rate in [44_100.0, 48_000] {
                try assertEquivalent(module, rate: rate, start: 0, pcm: name.hasPrefix("global"))
            }
        }
    }

    private func assertEquivalent(_ module: PlaybackSong, rate: Double, start: Int, pcm: Bool) throws {
        let count = module.orders.count - start
        let actual = Adapter.adapt(module, startOrderIndex: start, orderCount: count, sampleRate: rate)
        let expected = Adapter.adaptUsingGlobalVolumeProjection(module, startOrderIndex: start, orderCount: count,
            sampleRate: rate, oracle: Adapter.legacyGlobalVolumeChannelTargets)
        XCTAssertEqual(actual, expected) // Includes every diagnostic field, source generation and held gain.
        let a = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate, preparedPlan: actual)
        let b = RuntimeCMixerAdapterEventPlan.make(song: module, sampleRate: rate, preparedPlan: expected)
        XCTAssertEqual(a.events, b.events)
        XCTAssertEqual(a.categories, b.categories)
        let range = try XCTUnwrap(module.patternLoopRange(containing: .init(orderIndex: start, patternIndex: start, rowIndex: 0)))
        XCTAssertEqual(a.events(in: range), b.events(in: range))
        guard pcm else { return }
        let request = PlaybackSongOfflineRenderRequest(song: module, startOrderIndex: start, orderCount: count,
            config: .init(sampleRate: rate), frames: try XCTUnwrap(a.plannedSongEndFrame))
        let ar = PlaybackSongOfflineRenderer(preparedPlan: actual), br = PlaybackSongOfflineRenderer(preparedPlan: expected)
        let whole = ar.render(request).block
        XCTAssertEqual(whole, br.render(request).block)
        for window in [1, 5] {
            let split = ar.renderWindowed(request, windowRows: window).block
            XCTAssertEqual(split, br.renderWindowed(request, windowRows: window).block)
            XCTAssertEqual(split.frameCount, whole.frameCount)
            XCTAssertLessThanOrEqual(zip(split.interleavedPCM, whole.interleavedPCM).map { abs($0 - $1) }.max() ?? 0, 1e-7)
        }
    }
    #endif

    private final class Sink: AdapterPlanProfileSinking {
        var fields: [String: Int]?
        func writeAdapterPlanProfileLine(_ line: String) {
            guard line.contains("phase=global_volume_channel_projection ") else { return }
            fields = line.split(separator: " ").reduce(into: [:]) { result, item in
                let pair = item.split(separator: "=", maxSplits: 1)
                if pair.count == 2, let value = Int(pair[1]) { result[String(pair[0])] = value }
            }
        }
    }

    private func lifecycleRows(_ h: UInt8, _ speed: Int) -> [[PlaybackCell]] {
        [[c(16, 32, note: 49, instrument: 1), c(note: 49, instrument: 1), c(note: 49, instrument: 1), c(17)],
         [c(note: 49), c(16, 16), c(note: 49), c()],
         [c(17, h), c(10), c(17, 0x10), c(15, UInt8(speed))],
         [c(17), c(12, 64), c(17), c(17)], [c(14, 0xA0), c(14, 0xB0), c(5), c(6)],
         [c(instrument: 1), c(note: 97), c(20, 0), c(7, 0x48)],
         [c(14, 0x10), c(33, 0x20), c(10), c(volume: 0x71)],
         [c(note: 50), c(14, 0xC1), c(14, 0xD2, note: 49, instrument: 1), c()],
         [c(note: 49), c(note: 49), c(14, 0x93), c(16, 16)],
         [c(17), c(17, 1), c(), c()], [c(), c(), c(), c()]]
    }

    private func c(_ effect: UInt8 = 0, _ parameter: UInt8 = 0, note: UInt8 = 0, instrument: UInt8 = 0, volume: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: volume, effectType: effect, effectParam: parameter)
    }

    private func song(_ rows: [[PlaybackCell]], speed: Int = 6, loop: Int = 1, envelope: Bool = false) -> PlaybackSong {
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: Float(1) / 32, count: 64),
            volume: 0.5, relativeNote: 0, finetune: 0, baseSampleRate: 8363, loopStart: 0, loopLength: loop == 0 ? 0 : 64, loopType: loop)
        let empty = PlaybackSample(instrumentIndex: 1, sampleIndex: 1, pcm: [], volume: 0, relativeNote: 0, finetune: 0, baseSampleRate: 8363)
        var map = Array(repeating: 0, count: 96); map[49] = 1
        let env = PlaybackVolumeEnvelope(enabled: envelope, points: envelope ? [.init(tick: 0, value: 48), .init(tick: 8, value: 32)] : [],
            sustainPointIndex: nil, loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: envelope ? 1 : 0, fadeout: envelope ? 4096 : 0)
        let channels = rows.map(\.count).max() ?? 1, split = max(1, rows.count / 2)
        let patterns = [Array(rows[..<split]), Array(rows[split...])].enumerated().map { index, chunk in
            PlaybackPattern(index: index, rows: chunk.enumerated().map {
                .init(index: $0.offset, cells: $0.element + Array(repeating: c(), count: channels - $0.element.count))
            })
        }
        return .init(title: "Public global projection equivalence", orders: patterns.map { .init(orderIndex: $0.index, patternIndex: $0.index) },
            patternsByIndex: Dictionary(uniqueKeysWithValues: patterns.map { ($0.index, $0) }),
            instrumentsByIndex: [1: .init(index: 1, samples: [sample, empty], volumeEnvelope: env, noteSampleMap: map)],
            restartOrderIndex: 0, endBehavior: .stopAtEnd, initialTiming: .init(speed: speed, bpm: 125), usesLinearFrequencyTable: true,
            xmSampleSlotProvenanceByInstrument: [1: [.init(sampleIndex: 1, decodedPayloadLength: 0, isCanonicalEmptySlotHeader: true,
                volume: 0, panning: 0, finetune: 0, relativeNote: 0)]])
    }
}

#if DEBUG
// Frozen pre-compaction projection from dcfa7b2; intentionally retains the full-state replay.
extension PlaybackSongSyntheticAdapter {
    /// Projects Gxx/Hxy canonical transitions into existing immutable gain publications.
    /// Held values are output targets by trigger identity, never channel-local global-volume state.
    static func legacyGlobalVolumeChannelTargets(timingPlan: PlaybackSongFxxTimingPlan, context: inout AdapterRowContext) {
        let original = context.voiceStateUpdates
        guard let firstRow = original.first(where: { $0.effectType == 0x10 || ($0.effectType == 0x11 && $0.syntheticTick > 0) })?.syntheticRow else { return }
        let updatesByRow = Dictionary(grouping: original.indices, by: { original[$0].syntheticRow })
        let controlsByRow = Dictionary(grouping: context.xmChannelRows, by: \.syntheticRow)
        struct Route { let frame: Int; let channel: Int; let event: Int? }
        var routes = context.eventMappings.map { mapping in
            let event = context.events[mapping.eventIndex]
            return Route(frame: event.scheduledStartFrame ?? timingPlan.frameFor(row: event.row, tick: event.tick),
                  channel: mapping.channelIndex, event: mapping.eventIndex)
        }
        routes += context.xmEmptyRoutes.map { Route(frame: $0.scheduledFrame, channel: $0.channelIndex, event: nil) }
        routes.sort { $0.frame == $1.frame ? $0.channel < $1.channel : $0.frame < $1.frame }
        let sampleVolumes = Dictionary(uniqueKeysWithValues: context.eventMappings.map { ($0.eventIndex, $0.sampleVolume) })
        let resets = Dictionary(grouping: context.playbackStateEvents, by: \.scheduledFrame)
        let releases = Dictionary(grouping: context.keyOffEvents.filter(\.applied), by: { $0.scheduledFrame ?? -1 })
        let cuts = Dictionary(grouping: context.noteCutEffects.filter(\.applied), by: { $0.scheduledFrame ?? -1 })
        var active = [Int: Int](), heldGains = [Int: Float](), affected = Set<Int>(), released = Set<Int>()
        var gxxAffected = Set<Int>()
        var routeCursor = 0
        // This is a read-only projection of canonical mutations, not a second arithmetic authority.
        var visibleGlobal = GlobalVolumeState.defaultValue
        var result = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        result.reserveCapacity(original.count)
        var lastControls = [Int: ChannelState]()
        for timing in timingPlan.rowTimings {
            let row = timing.syntheticRow
            let rowControls = (controlsByRow[row] ?? []).sorted { $0.channelIndex < $1.channelIndex }
            let byTick = Dictionary(grouping: updatesByRow[row] ?? [], by: { original[$0].syntheticTick })
            let rowHasH = (updatesByRow[row] ?? []).contains { original[$0].effectType == 0x11 && original[$0].syntheticTick > 0 }
            var controls = Dictionary(uniqueKeysWithValues: rowControls.map { ($0.channelIndex, $0.controls) })
            if row < firstRow { result.append(contentsOf: (updatesByRow[row] ?? []).map { original[$0] }) }
            for tick in 0..<timing.effectiveSpeed {
                let frame = timingPlan.frameFor(row: row, tick: tick)
                while routeCursor < routes.count && routes[routeCursor].frame <= frame {
                    let route = routes[routeCursor]
                    active[route.channel] = route.event
                    if let event = route.event { heldGains[event] = context.events[event].gain }
                    routeCursor += 1
                }
                for reset in resets[frame] ?? [] {
                    if case let .reset(dimensions) = reset.change, dimensions.keyOn { released.remove(reset.activeEventIndex) }
                    if case .keyOff = reset.change { released.insert(reset.activeEventIndex) }
                }
                for release in releases[frame] ?? [] {
                    if let event = release.activeEventIndex { released.insert(event) }
                }
                for cut in cuts[frame] ?? [] {
                    if active[cut.channelIndex] == cut.activeEventIndex { active[cut.channelIndex] = nil }
                }
                let indices = byTick[tick] ?? []
                let turns = Dictionary(grouping: indices, by: { original[$0].channelIndex })
                let hasH = indices.contains { if case .hxyGlobalVolumeSlide = original[$0].command { return original[$0].applied }; return false }
                let hasG = indices.contains { if case .gxxSetGlobalVolume = original[$0].command { return original[$0].applied }; return false }
                // Keep G12/H00 target ownership, extending the same held-state
                // contract to G-only generations without creating another global.
                if hasH || (tick == 0 && rowHasH) { affected.formUnion(active.values) }
                if hasG { gxxAffected.formUnion(active.values) }
                for rowControl in rowControls {
                    let channel = rowControl.channelIndex
                    var state = controls[channel] ?? rowControl.controls
                    var localVolumePublication = false
                    for ordinal in turns[channel] ?? [] {
                        let update = original[ordinal]
                        switch update.command {
                        case .gxxSetGlobalVolume, .hxyGlobalVolumeSlide:
                            if update.applied, let value = update.globalVolumeAfter { visibleGlobal = value }
                        default:
                            if update.applied, legacyIsVolumePublicationWriter(update.command) {
                                if let output = update.effectiveVolumeAfter { state.outputChannelVolume = output }
                                localVolumePublication = true
                            }
                        }
                        var retained = update
                        if let event = update.activeEventIndex {
                            if affected.contains(event) || gxxAffected.contains(event) {
                                // Keep typed writer/quick-volume intent and pan metadata, but let
                                // the channel-turn snapshot own this frame's scalar gain once.
                                retained.gainBefore = nil; retained.gainAfter = nil
                            } else if let after = update.gainAfter, update.gainBefore != after {
                                heldGains[event] = after
                            }
                        }
                        if row >= firstRow { result.append(retained) }
                    }
                    controls[channel] = state
                    guard let event = active[channel], affected.contains(event) || gxxAffected.contains(event),
                          hasH || hasG || localVolumePublication || context.events[event].volumeEnvelope != nil || released.contains(event) else { continue }
                    state.activeEventIndex = event
                    state.activeSampleVolume = sampleVolumes[event]
                    var target = legacyGlobalVolumeChannelTarget(source: timing.source, channel: channel, row: row, tick: tick,
                        frame: frame, state: state, globalVolume: visibleGlobal,
                        gxxReason: affected.contains(event) ? nil : hasG ? "global_volume_set" :
                            localVolumePublication ? "local_volume_writer" : "envelope_or_release_tick")
                    target.gainBefore = heldGains[event] ?? context.events[event].gain
                    heldGains[event] = target.gainAfter
                    result.append(target)
                }
            }
            lastControls = controls
        }
        // A forced envelope/release publication at the first tail tick observes the final
        // canonical state. Plain voices retain their held target until another writer.
        if let last = timingPlan.rowTimings.last {
            let row = last.syntheticRow + 1
            for channel in active.keys.sorted() {
                guard let event = active[channel], affected.contains(event) || gxxAffected.contains(event),
                      context.events[event].volumeEnvelope != nil || released.contains(event),
                      var state = lastControls[channel] else { continue }
                state.activeEventIndex = event; state.activeSampleVolume = sampleVolumes[event]
                var target = legacyGlobalVolumeChannelTarget(source: last.source, channel: channel, row: row, tick: 0,
                    frame: timingPlan.frameFor(row: row), state: state, globalVolume: visibleGlobal,
                    gxxReason: affected.contains(event) ? nil : "envelope_or_release_tick")
                target.gainBefore = heldGains[event] ?? context.events[event].gain
                result.append(target)
            }
        }
        context.voiceStateUpdates = result
    }

    private static func legacyIsVolumePublicationWriter(_ command: PlaybackSongSyntheticVoiceStateUpdateCommand) -> Bool {
        switch command {
        case .instrumentDefaultVolume, .cxxSetVolume, .keyOffWithoutEnvelope, .axyVolumeSlide,
             .eaxFineVolumeSlideUp, .ebxFineVolumeSlideDown, .effect5xyVolumeSlide, .effect6xyVolumeSlide, .tremolo:
            return true
        case let .volumeColumn(column):
            switch column {
            case .setVolume, .volumeSlideDown, .volumeSlideUp, .fineVolumeSlideDown, .fineVolumeSlideUp: return true
            default: return false
            }
        default: return false
        }
    }

    private static func legacyGlobalVolumeChannelTarget(source: PlaybackPosition, channel: Int, row: Int, tick: Int,
        frame: Int, state: ChannelState, globalVolume: Int, gxxReason: String? = nil) -> PlaybackSongSyntheticVoiceStateUpdateDiagnostic {
        voiceStateUpdateDiagnostic(source: source, channelIndex: channel, syntheticRow: row, syntheticTick: tick,
            scheduledFrame: frame, cell: PlaybackCell(note: 0, instrument: 0, volumeColumn: 0, effectType: 0, effectParam: 0),
            commandSource: .effectColumn, command: gxxReason.map { .gxxChannelTarget(globalVolume: globalVolume, reason: $0) } ?? .hxyChannelTarget(globalVolume: globalVolume),
            // Snapshots also refresh at tick zero; their explicit frame owns timing.
            rawVolumeColumn: nil, effectType: nil, effectParam: nil, status: .applied, behavior: nil,
            channelStateBefore: state, channelStateAfter: state, globalVolumeBefore: globalVolume,
            globalVolumeAfter: globalVolume, includeGlobalVolumeFields: true, targetChannelIndex: channel,
            activeVoiceUpdatedOverride: true)
    }

}
#endif
