import Foundation
@testable import VoodooTrackerXPlaybackSupport
import XCTest

/// Split the same already-interpreted facts; never reproduce effect arithmetic here.
final class XMContinuingFoldTests: XCTestCase {
    typealias Envelope = PlaybackXMEnvelopeTimeline
    typealias Audible = PlaybackXMAudibleTimeline

    func testDefaultNilCheckpointArgumentsKeepTheColdFoldExact() throws {
        let input = song(managed: true)
        let full = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: 48_000)
        let existing = try XCTUnwrap(full.xmEnvelopeTimeline)
        let rebuilt = Envelope(song: input, timing: existing.timing, plan: full)
        XCTAssertEqual(rebuilt, existing)
        let installed = PlaybackSongSyntheticPlan(continuing: full, envelope: rebuilt)
        XCTAssertEqual(installed, full)
    }

    func testEveryRowSplitKeepsSegmentReleaseResetAndAudibleTargetsExact() throws {
        for rate in [44_100.0, 48_000] {
            var plan = PlaybackSongSyntheticAdapter.adapt(song(managed: true), orderIndex: 0, sampleRate: rate)
            let timing = try XCTUnwrap(plan.xmEnvelopeTimeline).timing
            // Include a real off-tick reset, rather than manufacturing another clock tick.
            plan.playbackStateEvents.append(.init(activeEventIndex: 0, channelIndex: 0,
                scheduledFrame: timing.frameFor(row: 7) + 1,
                change: .reset(.init(volumeEnvelope: true, fadeout: true))))
            try assertSplit(song(managed: true), plan: plan, strictEnvelopePublications: true)
        }
    }

    func testPlainReleaseContinuesThroughBlankRowsWithoutNewGlobalOrReleaseWriter() throws {
        for rate in [44_100.0, 48_000] {
            let input = song(managed: false)
            var plan = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
            let timing = try XCTUnwrap(plan.xmEnvelopeTimeline).timing
            plan.playbackStateEvents.append(.init(activeEventIndex: 0, channelIndex: 0,
                scheduledFrame: timing.frameFor(row: 5), change: .keyOff(fadeoutDecrement: 0)))
            try assertSplit(input, plan: plan, strictEnvelopePublications: false)
            XCTAssertFalse(plan.diagnostics.voiceStateUpdates.contains { $0.effectType == 0x10 || $0.effectType == 0x11 })
            XCTAssertTrue(try XCTUnwrap(plan.xmAudibleTimeline).updates.contains { $0.source.rowIndex == 6 })
        }
    }

    func testSourceFreeReleaseSilentResetAndLaterSourceKeepExactTickState() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("reference-xm/generated/empty-slot-playback-state.xm")
        let input = try PlaybackSongBuilder.build(from: ModuleMetadataLoader().load(fromPath: url.path), modulePath: url.path)
        for rate in [44_100.0, 48_000] {
            let plan = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: rate)
            // This fixture also has a plain one-shot whose later reset admits earlier
            // neutral full-plan histories; tick state and actual audible targets remain exact.
            try assertSplit(input, plan: plan, strictEnvelopePublications: false)
            XCTAssertTrue(try XCTUnwrap(plan.xmEnvelopeTimeline).channelUpdates.contains { $0.sourceEventIndex == nil })
        }
    }

    func testCheckpointsDoNotRetainThePreviousBatchRowCaptures() throws {
        let input = song(managed: true)
        let full = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: 48_000)
        let timing = try XCTUnwrap(full.xmEnvelopeTimeline).timing
        var channels = [Int: Envelope.ChannelCheckpoint](), sources = [Int: Audible.SourceCheckpoint]()
        weak var retiredRow: PlaybackXMChannelRow?
        do {
            let first = batch(full, timing: timing, row: 0)
            retiredRow = try XCTUnwrap(first.xmChannelRows.first)
            let envelope = Envelope(song: input, timing: oneRow(timing, 0), plan: first,
                terminalCheckpoint: { channels = $0 })
            _ = PlaybackSongSyntheticPlan(continuing: first, envelope: envelope,
                terminalAudibleCheckpoint: { sources = $0 })
        }
        XCTAssertFalse(channels.isEmpty)
        XCTAssertFalse(sources.isEmpty)
        XCTAssertNil(retiredRow)
    }

    func testRetainedSourceRemapsToCompactScratchIndexWithoutBirthOrOldRows() throws {
        let input = song(managed: true, channels: 2)
        let full = PlaybackSongSyntheticAdapter.adapt(input, orderIndex: 0, sampleRate: 48_000)
        let timing = try XCTUnwrap(full.xmEnvelopeTimeline).timing
        var channels = [Int: Envelope.ChannelCheckpoint]()
        let first = batch(full, timing: timing, row: 0)
        let envelope = Envelope(song: input, timing: oneRow(timing, 0), plan: first,
            terminalCheckpoint: { channels = $0 })
        var sources = [Int: Audible.SourceCheckpoint]()
        _ = PlaybackSongSyntheticPlan(continuing: first, envelope: envelope,
            terminalAudibleCheckpoint: { sources = $0 })
        XCTAssertEqual(Set(sources.keys), [0, 1])
        // Retire channel 0, and import original source 1 as this batch's scratch source 0.
        var kept = try XCTUnwrap(channels[1])
        XCTAssertEqual(kept.route?.sourceEventIndex, 1)
        kept.route?.sourceEventIndex = 0
        let old = batch(full, timing: timing, row: 1)
        var compact = PlaybackSongSyntheticPlan(timingConfig: old.timingConfig,
            pattern: .init(rowCount: 1, events: [full.pattern.events[1]]),
            diagnostics: diagnostics(full, timing: oneRow(timing, 1), row: 1,
                mappings: [mapping(full.diagnostics.eventMappings[1], eventIndex: 0)]))
        compact.xmChannelRows = old.xmChannelRows.filter { $0.channelIndex == 1 }.map {
            var controls = $0.controls
            controls.activeEventIndex = 0; controls.activeEventMappingIndex = 0
            return .init(source: $0.source, channelIndex: 1, syntheticRow: 0,
                scheduledFrame: $0.scheduledFrame, controls: controls, instrumentOnlyReset: $0.instrumentOnlyReset)
        }
        let start = timing.frameFor(row: 1), end = timing.frameFor(row: 2)
        var terminalChannels = [Int: Envelope.ChannelCheckpoint]()
        let resumed = Envelope(song: input, timing: oneRow(timing, 1), plan: compact,
            continuationSeed: [1: kept], importedEventIndices: [0], batchStartFrame: start,
            terminalCheckpoint: { terminalChannels = $0 })
        var terminalSources = [Int: Audible.SourceCheckpoint]()
        let folded = PlaybackSongSyntheticPlan(continuing: compact, envelope: resumed,
            audibleSeed: [0: try XCTUnwrap(sources[1])], importedEventIndices: [0], batchStartFrame: start,
            terminalAudibleCheckpoint: { terminalSources = $0 })
        assertSameElements(resumed.updates, try XCTUnwrap(full.xmEnvelopeTimeline).updates.filter {
            $0.eventIndex == 1 && (start..<end).contains($0.scheduledFrame)
        }.map { envelopeUpdate($0, eventIndex: 0) }, label: "compact envelope")
        assertSameElements(try XCTUnwrap(folded.xmAudibleTimeline).updates,
            try XCTUnwrap(full.xmAudibleTimeline).updates.filter {
                $0.eventIndex == 1 && (start..<end).contains($0.scheduledFrame)
            }.map { audibleUpdate($0, eventIndex: 0) }, label: "compact audible")
        XCTAssertEqual(Set(terminalChannels.keys), [1])
        XCTAssertEqual(Set(terminalSources.keys), [0])
        XCTAssertEqual(compact.pattern.events.count, 1)
        XCTAssertEqual(compact.xmChannelRows.count, 1)
        XCTAssertTrue(try XCTUnwrap(folded.xmAudibleTimeline).updates.allSatisfy { $0.intent != "initial" })
    }

    private func assertSplit(_ input: PlaybackSong, plan: PlaybackSongSyntheticPlan,
                             strictEnvelopePublications: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let timing = try XCTUnwrap(plan.xmEnvelopeTimeline, file: file, line: line).timing
        var expectedChannels = [Int: Envelope.ChannelCheckpoint]()
        // Request inspection state even for plain sources; this does not admit neutral voice publications.
        let whole = Envelope(song: input, timing: timing, plan: plan,
            terminalCheckpoint: { expectedChannels = $0 })
        assertSameElements(whole.updates, try XCTUnwrap(plan.xmEnvelopeTimeline, file: file, line: line).updates,
            label: "cold envelope", file: file, line: line)
        var channels = [Int: Envelope.ChannelCheckpoint](), sources = [Int: Audible.SourceCheckpoint]()
        var channelUpdates = [PlaybackXMChannelUpdate](), updates = [PlaybackXMEnvelopeUpdate]()
        var audible = [PlaybackXMAudibleUpdate]()
        for row in timing.rowTimings.indices {
            let local = oneRow(timing, row), start = local.frameFor(row: 0)
            let base = batch(plan, timing: timing, row: row)
            let scheduler = SyntheticTrackerScheduler(config: base.timingConfig)
            let imported = Set(base.pattern.events.indices.filter { scheduler.frame(for: base.pattern.events[$0]) < start })
            let envelope = Envelope(song: input, timing: local, plan: base, continuationSeed: channels,
                importedEventIndices: imported, batchStartFrame: start, terminalCheckpoint: { channels = $0 })
            let folded = PlaybackSongSyntheticPlan(continuing: base, envelope: envelope,
                audibleSeed: sources, importedEventIndices: imported, batchStartFrame: start,
                terminalAudibleCheckpoint: { sources = $0 })
            // The next seed owns only active semantic source bindings, never historical generations.
            let retained = Set(channels.values.compactMap { $0.route?.sourceEventIndex })
            sources = sources.filter { retained.contains($0.key) }
            XCTAssertLessThanOrEqual(channels.count, input.patternsByIndex.values.flatMap(\.rows).map { $0.cells.count }.max() ?? 0,
                file: file, line: line)
            XCTAssertLessThanOrEqual(sources.count, channels.count, file: file, line: line)
            XCTAssertEqual(base.xmChannelRows.count, plan.xmChannelRows.filter { $0.syntheticRow == row }.count,
                file: file, line: line)
            channelUpdates += envelope.channelUpdates; updates += envelope.updates
            let current = try XCTUnwrap(folded.xmAudibleTimeline, file: file, line: line).updates
            if row > 0 {
                XCTAssertFalse(current.contains { imported.contains($0.eventIndex) && $0.intent == "initial" }, file: file, line: line)
            }
            audible += current
        }
        assertSameElements(channelUpdates, whole.channelUpdates, label: "channel tick state", file: file, line: line)
        if strictEnvelopePublications {
            assertSameElements(updates, whole.updates, label: "envelope publications", file: file, line: line)
        }
        assertSameElements(audible, try XCTUnwrap(plan.xmAudibleTimeline, file: file, line: line).updates,
            label: "audible publications", file: file, line: line)
        XCTAssertEqual(channels, expectedChannels, file: file, line: line)
    }

    private func assertSameElements<Value: Equatable>(_ actual: [Value], _ expected: [Value],
        label: String, file: StaticString = #filePath, line: UInt = #line) {
        for index in 0..<min(actual.count, expected.count) where actual[index] != expected[index] {
            XCTFail("\(label): first difference at \(index), counts \(actual.count)/\(expected.count)\nactual: \(actual[index])\nexpected: \(expected[index])",
                file: file, line: line)
            return
        }
        if actual.count != expected.count {
            XCTFail("\(label): matching prefix, counts \(actual.count)/\(expected.count)", file: file, line: line)
        }
    }

    private func oneRow(_ full: PlaybackSongFxxTimingPlan, _ index: Int) -> PlaybackSongFxxTimingPlan {
        let old = full.rowTimings[index]
        let row = PlaybackSongFxxRowTiming(source: old.source, syntheticRow: 0,
            rowStartExactFrame: old.rowStartExactFrame, rowEndExactFrame: old.rowEndExactFrame,
            effectiveSpeed: old.effectiveSpeed, effectiveBPM: old.effectiveBPM, patternDelayCycles: old.patternDelayCycles)
        return .init(sampleRate: full.sampleRate, initialSpeed: row.effectiveSpeed, initialBPM: row.effectiveBPM,
            rowTimings: [row], timingChanges: [], finalSpeed: row.effectiveSpeed,
            finalBPM: row.effectiveBPM, endExactFrame: row.rowEndExactFrame)
    }

    private func batch(_ full: PlaybackSongSyntheticPlan, timing: PlaybackSongFxxTimingPlan, row: Int) -> PlaybackSongSyntheticPlan {
        let local = oneRow(timing, row), start = local.frameFor(row: 0), end = local.frameFor(row: 1)
        let scheduler = SyntheticTrackerScheduler(config: full.timingConfig)
        let events = Array(full.pattern.events.prefix { scheduler.frame(for: $0) < end })
        var result = PlaybackSongSyntheticPlan(timingConfig: local.timingConfig(forSyntheticRow: 0),
            pattern: .init(rowCount: 1, events: events),
            diagnostics: diagnostics(full, timing: local, row: row,
                mappings: full.diagnostics.eventMappings.filter { events.indices.contains($0.eventIndex) }))
        result.noteOnlyEventIndices = full.noteOnlyEventIndices.intersection(events.indices)
        result.coldReleasedEventIndices = full.coldReleasedEventIndices.intersection(events.indices)
        result.playbackStateEvents = full.playbackStateEvents.filter { (start..<end).contains($0.scheduledFrame) }
        result.xmChannelRows = full.xmChannelRows.filter { $0.syntheticRow == row }.map {
            .init(source: $0.source, channelIndex: $0.channelIndex, syntheticRow: 0,
                scheduledFrame: $0.scheduledFrame, controls: $0.controls, instrumentOnlyReset: $0.instrumentOnlyReset)
        }
        result.xmEmptyRoutes = full.xmEmptyRoutes.filter { (start..<end).contains($0.scheduledFrame) }
        result.xmInstrumentSelections = full.xmInstrumentSelections.filter { (start..<end).contains($0.scheduledFrame) }
        return result
    }

    private func diagnostics(_ full: PlaybackSongSyntheticPlan, timing: PlaybackSongFxxTimingPlan, row: Int,
                             mappings: [PlaybackSongSyntheticEventMapping]) -> PlaybackSongSyntheticDiagnostics {
        let d = full.diagnostics
        return .init(
            requestedStartOrderIndex: d.requestedStartOrderIndex,
            requestedOrderCount: d.requestedOrderCount,
            sampleRate: d.sampleRate,
            initialSpeed: d.initialSpeed,
            initialBPM: d.initialBPM,
            usesLinearFrequencyTable: d.usesLinearFrequencyTable,
            syntheticRowCount: 1,
            adaptedOrders: [],
            rowMappings: [],
            rowTiming: timing.rowTimingDiagnostics,
            timingChanges: [],
            traversalDiagnostics: [],
            traversalPathLength: 1,
            traversalStopReason: d.traversalStopReason,
            traversalGuardHit: false,
            effectCommandDiagnostics: [],
            rowDiagnostics: [],
            volumeColumnMappings: [],
            voiceStateUpdates: d.voiceStateUpdates.filter { $0.syntheticRow == row },
            sampleOffsetEffects: [],
            setFinetuneEffects: [],
            envelopePositionEffects: d.envelopePositionEffects.filter { $0.syntheticRow == row },
            noteCutEffects: d.noteCutEffects.filter { $0.syntheticRow == row },
            noteDelayEffects: d.noteDelayEffects.filter { $0.syntheticRow == row },
            retriggerEffects: [],
            tonePortamentoEffects: [],
            portamentoSlideEffects: [],
            finePortamentoUpEffects: [],
            finePortamentoDownEffects: [],
            extraFinePortamentoEffects: [],
            arpeggioEffects: [],
            vibratoControlEffects: [],
            vibratoEffects: [],
            keyOffEvents: d.keyOffEvents.filter { $0.syntheticRow == row },
            eventMappings: mappings,
            ignoredCells: [],
            deferredCellFields: [],
            eventCoverage: d.eventCoverage
        )
    }

    private func mapping(_ old: PlaybackSongSyntheticEventMapping, eventIndex: Int) -> PlaybackSongSyntheticEventMapping {
        .init(
            source: old.source,
            channelIndex: old.channelIndex,
            note: old.note,
            instrumentIndex: old.instrumentIndex,
            sampleIndex: old.sampleIndex,
            sampleVolume: old.sampleVolume,
            sampleVolumeRawEstimate: old.sampleVolumeRawEstimate,
            selectedSampleLength: old.selectedSampleLength,
            sampleMapKeymapPresent: old.sampleMapKeymapPresent,
            mappedSampleIndex: old.mappedSampleIndex,
            mappedSampleValid: old.mappedSampleValid,
            sampleSelectionMethod: old.sampleSelectionMethod,
            sampleSelectionStrategy: old.sampleSelectionStrategy,
            firstPlayableSampleFallbackUsed: old.firstPlayableSampleFallbackUsed,
            sampleMapKeymapBehaviorDeferred: old.sampleMapKeymapBehaviorDeferred,
            sampleMapKeymapMissingOrDeferred: old.sampleMapKeymapMissingOrDeferred,
            effectType: old.effectType,
            effectParam: old.effectParam,
            syntheticRow: old.syntheticRow,
            syntheticTick: old.syntheticTick,
            eventIndex: eventIndex,
            loopMode: old.loopMode,
            volumeColumn: old.volumeColumn,
            sampleOffset: old.sampleOffset,
            hasIgnoredVolumeColumn: old.hasIgnoredVolumeColumn,
            hasIgnoredEffect: old.hasIgnoredEffect,
            effectiveVolumeValue: old.effectiveVolumeValue,
            effectiveGlobalVolumeValue: old.effectiveGlobalVolumeValue,
            effectiveGlobalVolumeMultiplier: old.effectiveGlobalVolumeMultiplier,
            effectivePan: old.effectivePan,
            volumeEnvelopeStatus: old.volumeEnvelopeStatus,
            sourceVolumeEnvelopePointCount: old.sourceVolumeEnvelopePointCount,
            mappedVolumeEnvelopePointCount: old.mappedVolumeEnvelopePointCount,
            hasDeferredVolumeEnvelopeSustain: old.hasDeferredVolumeEnvelopeSustain,
            hasDeferredVolumeEnvelopeLoop: old.hasDeferredVolumeEnvelopeLoop,
            hasDeferredVolumeEnvelopeFadeout: old.hasDeferredVolumeEnvelopeFadeout,
            volumeEnvelopeSemantics: old.volumeEnvelopeSemantics,
            sampleBaseSampleRate: old.sampleBaseSampleRate,
            sampleRelativeNote: old.sampleRelativeNote,
            sampleFinetune: old.sampleFinetune,
            outputSampleRate: old.outputSampleRate,
            effectiveNoteValue: old.effectiveNoteValue,
            effectiveNoteIndex: old.effectiveNoteIndex,
            effectiveFinetune: old.effectiveFinetune,
            linearPeriod: old.linearPeriod,
            linearFrequency: old.linearFrequency,
            amigaPeriod: old.amigaPeriod,
            amigaFrequency: old.amigaFrequency,
            finetuneStatus: old.finetuneStatus,
            usesLinearFrequencyTable: old.usesLinearFrequencyTable,
            frequencyTableStatus: old.frequencyTableStatus,
            linearFrequencyApplied: old.linearFrequencyApplied,
            amigaFrequencyApplied: old.amigaFrequencyApplied,
            amigaFrequencyDeferred: old.amigaFrequencyDeferred,
            playbackStep: old.playbackStep,
            pitchMappingApplied: old.pitchMappingApplied,
            pitchMappingUsedNeutralStep: old.pitchMappingUsedNeutralStep
        )
    }

    private func envelopeUpdate(_ u: PlaybackXMEnvelopeUpdate, eventIndex: Int) -> PlaybackXMEnvelopeUpdate {
        .init(eventIndex: eventIndex, channelIndex: u.channelIndex, source: u.source, tick: u.tick,
            scheduledFrame: u.scheduledFrame, bpm: u.bpm, speed: u.speed, state: u.state,
            channelPanningValue: u.channelPanningValue)
    }

    private func audibleUpdate(_ u: PlaybackXMAudibleUpdate, eventIndex: Int) -> PlaybackXMAudibleUpdate {
        .init(eventIndex: eventIndex, channelIndex: u.channelIndex, source: u.source, tick: u.tick,
            scheduledFrame: u.scheduledFrame, bpm: u.bpm, speed: u.speed, amplitude: u.amplitude,
            pan: u.pan, durationFrames: u.durationFrames, intent: u.intent, activation: u.activation,
            rebaseFromCurrent: u.rebaseFromCurrent)
    }

    private func c(_ note: UInt8 = 0, _ instrument: UInt8 = 0, effect: UInt8 = 0, param: UInt8 = 0) -> PlaybackCell {
        .init(note: note, instrument: instrument, volumeColumn: 0, effectType: effect, effectParam: param)
    }

    private func song(managed: Bool, channels: Int = 1) -> PlaybackSong {
        let volume = PlaybackVolumeEnvelope(enabled: managed,
            points: managed ? [.init(tick: 0, value: 16), .init(tick: 2, value: 32), .init(tick: 6, value: 64), .init(tick: 12, value: 16)] : [],
            sustainPointIndex: managed ? 2 : nil, loopStartPointIndex: managed ? 1 : nil,
            loopEndPointIndex: managed ? 2 : nil, typeFlags: managed ? 7 : 0, fadeout: 1234)
        let pan = PlaybackPanningEnvelope(enabled: managed,
            points: managed ? [.init(tick: 0, value: 0), .init(tick: 4, value: 64)] : [],
            sustainPointIndex: nil, loopStartPointIndex: managed ? 0 : nil,
            loopEndPointIndex: managed ? 1 : nil, typeFlags: managed ? 5 : 0)
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0, pcm: Array(repeating: 0.5, count: 256),
            volume: 1, relativeNote: 0, finetune: 0, baseSampleRate: 100, loopStart: 0, loopLength: 256, loopType: 1)
        let commands: [Int: PlaybackCell] = [0: c(49, 1), 2: c(effect: 15, param: 250),
            3: c(effect: 0x15, param: 8), 4: c(effect: 8, param: 224), 5: managed ? c(97) : c(),
            7: c(0, 1), 9: c(effect: 15, param: 3), 11: c(52), 13: c(effect: 12, param: 32), 14: c(effect: 14, param: 0xC2)]
        return .init(title: "Continuing fold", orders: [.init(orderIndex: 0, patternIndex: 0)],
            patternsByIndex: [0: .init(index: 0, rows: (0..<16).map { index in
                .init(index: index, cells: Array(repeating: commands[index] ?? c(), count: channels))
            })], instrumentsByIndex: [1: .init(index: 1, samples: [sample], volumeEnvelope: volume,
                panningEnvelope: pan, noteSampleMap: Array(repeating: 0, count: 96))], restartOrderIndex: 0,
            endBehavior: .stopAtEnd, initialTiming: .init(speed: 6, bpm: 125), usesLinearFrequencyTable: true)
    }
}
