import Foundation

/// Composed physical requests remain distinct from raw native semantic histories.
struct PlaybackSongInstrumentAutovibratoPublication {
    struct Request: Equatable {
        private let location: UInt64
        let scheduledFrame: Int, activeEventIndex: Int
        let playbackStep: Double
        var syntheticRow: Int { Int(location >> 32) }
        var channelIndex: Int { Int(location >> 16 & 0xffff) }
        var syntheticTick: Int { Int(location & 0xffff) }
        init(row: Int, tick: Int, channel: Int, frame: Int, generation: Int, step: Double) {
            // XM channels and initial speed are UInt16; traversal is bounded to
            // one million rows. This internal carrier narrows no persisted field.
            precondition(row >= 0 && row <= Int(UInt32.max) && tick >= 0 && tick <= Int(UInt16.max) && channel >= 0 && channel <= Int(UInt16.max))
            location = UInt64(row) << 32 | UInt64(channel) << 16 | UInt64(tick)
            scheduledFrame = frame; activeEventIndex = generation; playbackStep = step
        }
        /// Physical scan/history adapter only; zero placeholders carry no native authority.
        var stepUpdate: PlaybackSongSyntheticTonePortamentoStepUpdate {
            .init(syntheticTick: syntheticTick, scheduledFrame: scheduledFrame,
                linearPeriodBefore: 0, linearPeriodAfter: 0,
                playbackStepBefore: playbackStep, playbackStepAfter: playbackStep, reachedTarget: false)
        }
    }
    struct Builder {
        typealias K = PlaybackSongInstrumentAutovibratoComposition
        typealias Context = PlaybackSongSyntheticAdapter.AdapterRowContext
        typealias Step = PlaybackSongSyntheticTonePortamentoStepUpdate
        struct Source {
            var generation = -1, delta = 0
            var step = 0.0
            var native: Double?
            var affected = false
        }
        var enabled = false
        var requests = [Request]()
        // Newly composed holds append runtime identities after legacy events.
        // Ordinary zero births retain their established hold identity and order.
        var introducedHoldEventIndices = Set<Int>()
        var sources = [Source](), bounds = [Int: K.Bounds]()
        var generations = [Int](), deltas = [Int](), writers = [Int](), births = [Int]()
        var writerSteps = [Double](), writerNatives = [Double?](), activeAutomatic = [Bool](), staleBounds = [Int]()
        var speed = 0, channelCount = 0, rowStartFrame = 0
        var requestGrowthCount = 0, boundsGrowthCount = 0
        var rewrittenArrayCount = 0, rewrittenChildCapacityBytes = 0
        /// Capacity and changed-array proxies, not malloc counts or resident memory.
        var workspaceCapacityBytes: Int {
            sources.capacity * MemoryLayout<Source>.stride +
                (generations.capacity + deltas.capacity + writers.capacity + births.capacity + staleBounds.capacity) * MemoryLayout<Int>.stride +
                writerSteps.capacity * MemoryLayout<Double>.stride + writerNatives.capacity * MemoryLayout<Double?>.stride + activeAutomatic.capacity * MemoryLayout<Bool>.stride
        }

        mutating func prepare(context: borrowing Context, channelCount: Int, speed: Int, rowStartFrame: Int) {
            self.speed = speed; self.channelCount = channelCount; self.rowStartFrame = rowStartFrame
            while sources.count < context.channelStates.count { sources.append(.init()) }
            let count = channelCount * speed
            generations.removeAll(keepingCapacity: true); generations.append(contentsOf: repeatElement(-1, count: count))
            deltas.removeAll(keepingCapacity: true); deltas.append(contentsOf: repeatElement(0, count: count))
            writers.removeAll(keepingCapacity: true); writers.append(contentsOf: repeatElement(-1, count: count))
            births.removeAll(keepingCapacity: true); births.append(contentsOf: repeatElement(-1, count: count))
            writerSteps.removeAll(keepingCapacity: true); writerSteps.append(contentsOf: repeatElement(0, count: count))
            writerNatives.removeAll(keepingCapacity: true); writerNatives.append(contentsOf: repeatElement(nil, count: count))
            activeAutomatic.removeAll(keepingCapacity: true); activeAutomatic.append(contentsOf: repeatElement(false, count: count))
            let semantic = context.semanticPitchBuilder, first = semantic.firstOrdinal
            for channel in 0..<channelCount {
                let records = semantic.channels[channel], runs = semantic.automatic.channels[channel]
                var record = upperBound(records, first, \.ordinal) - 1
                var run = upperBound(runs, first, \.ordinal) - 1
                for tick in 0..<speed {
                    let ordinal = first + tick, slot = channel * speed + tick
                    while record + 1 < records.count && records[record + 1].ordinal <= ordinal { record += 1 }
                    while run + 1 < runs.count && runs[run + 1].ordinal <= ordinal { run += 1 }
                    generations[slot] = record >= 0 ? records[record].generation : -1
                    let clock = (run >= 0 ? runs[run] : .init()).result(at: ordinal, interpreted: true)
                    deltas[slot] = K.delta(clock: clock)
                    activeAutomatic[slot] = clock.raw.map { $0.depth > 0 && $0.rate > 0 } ?? false
                }
            }
        }

        private func upperBound<T>(_ values: borrowing [T], _ ordinal: Int, _ key: KeyPath<T, Int>) -> Int {
            var low = 0, high = values.count
            while low < high {
                let middle = low + (high - low) / 2
                if values[middle][keyPath: key] <= ordinal { low = middle + 1 } else { high = middle }
            }
            return low
        }

        func rowIndices<T>(_ values: borrowing [T], row: Int, _ key: KeyPath<T, Int>) -> Range<Int> {
            upperBound(values, row - 2, key)..<values.count
        }

        mutating func sourceBounds(_ generation: Int, context: borrowing Context) -> K.Bounds? {
            if let cached = bounds[generation] { return cached }
            // Adapter births and mappings share exact append identities, including E9/Rxy.
            guard context.eventMappings.indices.contains(generation) else { return nil }
            let mapping = context.eventMappings[generation]
            precondition(mapping.eventIndex == generation)
            let value = K.Bounds(linear: mapping.usesLinearFrequencyTable,
                baseSampleRate: mapping.sampleBaseSampleRate, outputSampleRate: mapping.outputSampleRate)
            let capacity = bounds.capacity
            bounds[generation] = value
            if bounds.capacity != capacity { boundsGrowthCount += 1 }
            return value
        }

        mutating func rewrite(_ input: [Step], commandRow: Int, channel: Int, generation: Int?,
            row: Int, rowSpeed: Int, context: borrowing Context, terminal: Bool = false) -> [Step] {
            guard let generation, let conversion = sourceBounds(generation, context: context) else { return input }
            var result = input, changed = false
            for index in input.indices {
                let child = input[index]
                let tick: Int
                if terminal { guard child.syntheticTick == context.semanticPitchBuilder.speed else { continue }; tick = -1 }
                else if commandRow == row, child.syntheticTick < speed { tick = child.syntheticTick }
                else if commandRow == row - 1, child.scheduledFrame == rowStartFrame { tick = 0 }
                else { continue }
                let slot = channel * speed + tick
                let current = tick >= 0 && channel < channelCount && slot >= 0 && slot < deltas.count
                let delta = current ? deltas[slot] : (sources.indices.contains(channel) ? sources[channel].delta : 0)
                let period = child.audibleNativePeriod(linear: conversion.linear)
                guard let period, let step = conversion.step(period: period, delta: delta) else { continue }
                if step != child.playbackStepAfter {
                    changed = true
                    result[index] = .init(syntheticTick: child.syntheticTick, scheduledFrame: child.scheduledFrame,
                        linearPeriodBefore: child.linearPeriodBefore, linearPeriodAfter: child.linearPeriodAfter,
                        amigaPeriodBefore: child.amigaPeriodBefore, amigaPeriodAfter: child.amigaPeriodAfter,
                        playbackStepBefore: child.playbackStepBefore, playbackStepAfter: step,
                        reachedTarget: child.reachedTarget, clamped: child.clamped,
                        glissandoFinetune: child.glissandoFinetune, vibrato: child.vibrato)
                }
                if current && generations[slot] == generation {
                    writers[slot] = generation; writerSteps[slot] = step; writerNatives[slot] = period
                } else if !current && !terminal && commandRow == row - 1,
                          sources.indices.contains(channel), sources[channel].generation == generation {
                    // A sparse row can omit this canonical channel while a genuine
                    // prior-row restoration still updates its ordinary physical intent.
                    // Retain the frozen delta; no oscillator tick or request is created.
                    sources[channel].native = period; sources[channel].step = step
                    sources[channel].affected = sources[channel].affected || delta != 0
                }
            }
            if changed {
                rewrittenArrayCount += 1
                rewrittenChildCapacityBytes += result.capacity * MemoryLayout<Step>.stride
            }
            return result
        }

        mutating func captureScalarIntents(context: borrowing Context) {
            for operation in context.semanticPitchBuilder.operations {
                guard case let .writer(ref, _, _, native) = operation.action, let native else { continue }
                let generation: Int?
                switch ref.kind {
                case .fineUp: generation = context.finePortamentoUpEffects[ref.index].activeEventIndex
                case .fineDown: generation = context.finePortamentoDownEffects[ref.index].activeEventIndex
                case .extraFine: generation = context.extraFinePortamentoEffects[ref.index].activeEventIndex
                case .toneHold: generation = context.tonePortamentoEffects[ref.index].activeEventIndex
                default: continue
                }
                let slot = operation.channel * speed + operation.tick
                guard operation.channel < channelCount, generations.indices.contains(slot),
                      let generation, generations[slot] == generation, writers[slot] != generation else { continue }
                writerNatives[slot] = native
            }
        }

        mutating func foldBirths(row: Int, context: inout Context) {
            for generation in context.events.indices.reversed() {
                let event = context.events[generation]
                if event.row < row { break }
                let mapping = context.eventMappings[generation], channel = mapping.channelIndex, tick = mapping.syntheticTick
                guard channel < channelCount, tick < speed else { continue }
                let slot = channel * speed + tick
                if !activeAutomatic[slot] {
                    // Preserve the ordinary trigger/hold protocol for an inactive
                    // owner, including legacy E9 zero placeholders. A positive raw
                    // mapping also removes any automatic step inherited from a parent.
                    let ordinary = mapping.playbackStep > 0 ? mapping.playbackStep : event.playbackStep
                    if ordinary != event.playbackStep { context.events[generation] = event.withPlaybackStep(ordinary) }
                    if generations[slot] == generation { births[slot] = generation }
                    continue
                }
                guard let conversion = sourceBounds(generation, context: context) else { continue }
                let native = conversion.linear ? mapping.linearPeriod : mapping.amigaPeriod
                guard let native, let step = conversion.step(period: native, delta: deltas[slot]) else { continue }
                // The ordinary birth mapping already owns same-cell fine folds.
                // E9 clones carry that initial native input, independently of the
                // semantic effect latch or a parent's composed physical step.
                context.events[generation] = event.withPlaybackStep(step > 0 ? step : event.playbackStep)
                if step == 0 {
                    if context.initialHeldPitchEventIndices.insert(generation).inserted {
                        introducedHoldEventIndices.insert(generation)
                    }
                } else {
                    context.initialHeldPitchEventIndices.remove(generation)
                    introducedHoldEventIndices.remove(generation)
                }
                if generations[slot] == generation { births[slot] = generation }
            }
        }

        mutating func emit(row: Int, timingPlan: PlaybackSongFxxTimingPlan, context: borrowing Context) {
            var changedSource = false
            for channel in 0..<channelCount { for tick in 0..<speed {
                let slot = channel * speed + tick, generation = generations[slot]
                guard generation >= 0, context.events.indices.contains(generation) else { continue }
                if sources[channel].generation != generation {
                    sources[channel] = .init(generation: generation, delta: 0,
                        step: context.initialHeldPitchEventIndices.contains(generation) ? 0 : context.events[generation].playbackStep,
                        native: context.eventMappings[generation].usesLinearFrequencyTable
                            ? context.eventMappings[generation].linearPeriod : context.eventMappings[generation].amigaPeriod,
                        affected: false)
                    changedSource = true
                }
                sources[channel].delta = deltas[slot]
                if births[slot] == generation {
                    sources[channel].step = context.initialHeldPitchEventIndices.contains(generation) ? 0 : context.events[generation].playbackStep
                    sources[channel].affected = deltas[slot] != 0
                    continue
                }
                if writers[slot] == generation {
                    sources[channel].step = writerSteps[slot]
                    sources[channel].native = writerNatives[slot]
                    sources[channel].affected = sources[channel].affected || deltas[slot] != 0
                    continue
                }
                // Only an actual current scalar invocation may replace the
                // ordinary intent basis when no physical writer exists at this tick.
                if let scalar = writerNatives[slot] { sources[channel].native = scalar }
                guard activeAutomatic[slot] || sources[channel].affected,
                      let native = sources[channel].native,
                      let conversion = sourceBounds(generation, context: context),
                      let step = conversion.step(period: native, delta: deltas[slot]) else { continue }
                sources[channel].affected = sources[channel].affected || deltas[slot] != 0
                if step != sources[channel].step {
                    let capacity = requests.capacity
                    requests.append(.init(row: row, tick: tick, channel: channel,
                        frame: timingPlan.frameFor(row: row, tick: tick), generation: generation, step: step))
                    if requests.capacity != capacity { requestGrowthCount += 1 }
                    sources[channel].step = step
                }
            } }
            if changedSource {
                staleBounds.removeAll(keepingCapacity: true)
                for generation in bounds.keys where !sources.contains(where: { $0.generation == generation }) { staleBounds.append(generation) }
                for generation in staleBounds { bounds.removeValue(forKey: generation) }
            }
        }
    }
}

extension PlaybackSongSyntheticAdapter {
    /// Materializes one completed canonical row without extending its oscillator clock.
    static func materializeInstrumentAutovibratoRow(context: inout AdapterRowContext,
        builder: inout PlaybackSongInstrumentAutovibratoPublication.Builder, source: PlaybackPosition, row: Int, channelCount: Int,
        timingConfig: SyntheticTrackerTimingConfig, timingPlan: PlaybackSongFxxTimingPlan) {
        guard builder.enabled else { return }
        // A capture gap cannot authorize a new automatic phase or native value.
        // Keep the already proven physical prefix; ordinary intents retain authority.
        guard context.semanticPitchBuilder.automatic.valid else { return }
        builder.prepare(context: context, channelCount: channelCount, speed: timingConfig.actualTickCount,
            rowStartFrame: timingPlan.frameFor(row: row, tick: 0))
        // Existing family order is physical authority. Each native intermediate
        // receives the same tick delta; the final semantic value never replaces it.
        for index in builder.rowIndices(context.tonePortamentoEffects, row: row, \.syntheticRow) {
            let command = context.tonePortamentoEffects[index]
            guard command.applied else { continue }
            let children = builder.rewrite(command.stepUpdates, commandRow: command.syntheticRow,
                channel: command.channelIndex, generation: command.activeEventIndex, row: row,
                rowSpeed: command.rowSpeed, context: context)
            context.tonePortamentoEffects[index].stepUpdates = children
        }
        for index in builder.rowIndices(context.portamentoSlideEffects, row: row, \.syntheticRow) {
            let command = context.portamentoSlideEffects[index]
            guard command.applied else { continue }
            let children = builder.rewrite(command.stepUpdates, commandRow: command.syntheticRow,
                channel: command.channelIndex, generation: command.activeEventIndex, row: row,
                rowSpeed: command.rowSpeed, context: context)
            context.portamentoSlideEffects[index].stepUpdates = children
        }
        for index in builder.rowIndices(context.finePortamentoUpEffects, row: row, \.syntheticRow) {
            let command = context.finePortamentoUpEffects[index]
            guard command.applied else { continue }
            let children = builder.rewrite(command.stepUpdates, commandRow: command.syntheticRow,
                channel: command.channelIndex, generation: command.activeEventIndex, row: row,
                rowSpeed: command.rowSpeed, context: context)
            context.finePortamentoUpEffects[index].stepUpdates = children
        }
        for index in builder.rowIndices(context.finePortamentoDownEffects, row: row, \.syntheticRow) {
            let command = context.finePortamentoDownEffects[index]
            guard command.applied else { continue }
            let children = builder.rewrite(command.stepUpdates, commandRow: command.syntheticRow,
                channel: command.channelIndex, generation: command.activeEventIndex, row: row,
                rowSpeed: command.rowSpeed, context: context)
            context.finePortamentoDownEffects[index].stepUpdates = children
        }
        for index in builder.rowIndices(context.extraFinePortamentoEffects, row: row, \.syntheticRow) {
            let command = context.extraFinePortamentoEffects[index]
            guard command.applied else { continue }
            let children = builder.rewrite(command.stepUpdates, commandRow: command.syntheticRow,
                channel: command.channelIndex, generation: command.activeEventIndex, row: row,
                rowSpeed: command.rowSpeed, context: context)
            context.extraFinePortamentoEffects[index].stepUpdates = children
        }
        for index in builder.rowIndices(context.arpeggioEffects, row: row, \.syntheticRow) {
            let command = context.arpeggioEffects[index]
            guard command.applied else { continue }
            let children = builder.rewrite(command.stepUpdates, commandRow: command.syntheticRow,
                channel: command.channelIndex, generation: command.activeEventIndex, row: row,
                rowSpeed: command.rowSpeed, context: context)
            context.arpeggioEffects[index].stepUpdates = children
        }
        for index in builder.rowIndices(context.vibratoEffects, row: row, \.syntheticRow) {
            let command = context.vibratoEffects[index]
            guard command.applied else { continue }
            let children = builder.rewrite(command.stepUpdates, commandRow: command.syntheticRow,
                channel: command.channelIndex, generation: command.activeEventIndex, row: row,
                rowSpeed: command.rowSpeed, context: context)
            context.vibratoEffects[index].stepUpdates = children
        }
        builder.captureScalarIntents(context: context)
        builder.foldBirths(row: row, context: &context)
        builder.emit(row: row, timingPlan: timingPlan, context: context)
    }

    /// Preserves the final automatic value on existing terminal restoration intents.
    static func finishInstrumentAutovibratoTail(context: inout AdapterRowContext,
        builder: inout PlaybackSongInstrumentAutovibratoPublication.Builder) {
        guard builder.enabled else { return }
        guard context.semanticPitchBuilder.automatic.valid else { return }
        for index in context.arpeggioEffects.indices.reversed() {
            let command = context.arpeggioEffects[index]
            if command.syntheticRow < context.rowDiagnostics.count - 1 { break }
            let children = builder.rewrite(command.stepUpdates, commandRow: command.syntheticRow,
                channel: command.channelIndex, generation: command.activeEventIndex, row: command.syntheticRow,
                rowSpeed: command.rowSpeed, context: context, terminal: true)
            context.arpeggioEffects[index].stepUpdates = children
        }
        for index in context.vibratoEffects.indices.reversed() {
            let command = context.vibratoEffects[index]
            if command.syntheticRow < context.rowDiagnostics.count - 1 { break }
            let children = builder.rewrite(command.stepUpdates, commandRow: command.syntheticRow,
                channel: command.channelIndex, generation: command.activeEventIndex, row: command.syntheticRow,
                rowSpeed: command.rowSpeed, context: context, terminal: true)
            context.vibratoEffects[index].stepUpdates = children
        }
    }
}
