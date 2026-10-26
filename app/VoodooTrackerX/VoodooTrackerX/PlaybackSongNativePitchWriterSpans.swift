import Foundation

/// Partial observations of existing numeric pitch children, excluding synthetic row exits.
/// Producer append order is distinct from scheduled-time order and physical/C admission.
struct PlaybackSongNativePitchWriterSpans: Equatable {
    enum Coverage { case notAdapterProduced, partialChildBearingProducersV1 }
    enum Family: UInt8, CaseIterable {
        case tonePortamento, portamentoSlide, finePortamentoUp, finePortamentoDown
        case extraFinePortamento, arpeggio, vibrato
    }
    struct Span: Equatable {
        let diagnosticIndex: Int
        let capturedChildCount: Int
        // Original COW backing, retained for stable raw ordinals and memory accounting.
        // Only the bounded prefix is observed; a retained trailing row exit is excluded.
        let originalChildren: [PlaybackSongSyntheticTonePortamentoStepUpdate]
        let family: Family

        func child(at index: Int) -> PlaybackSongSyntheticTonePortamentoStepUpdate? {
            guard index >= 0, index < capturedChildCount else { return nil }
            return originalChildren[index]
        }
    }
    enum Delivery: Equatable {
        case unknownDelivery, retainedDiagnosticChild, suppressedNoActiveSource, supersededDelayedBirth
    }
    /// A calculated native value. No delivery case asserts mixer acceptance or winning output.
    struct Observation: Equatable {
        let family: Family
        let diagnosticIndex: Int
        let childIndex: Int
        let producerAppendOrdinal: Int
        let source: PlaybackPosition
        let syntheticRow: Int
        let channelIndex: Int
        let syntheticTick: Int
        let scheduledFrame: Int
        let domain: PlaybackSongSelectionDispatchFacts.Domain
        let nativePeriodBefore: Double
        let nativePeriodAfter: Double
        let associatedGeneration: Int?
        let delivery: Delivery
    }
    let coverage: Coverage
    let domain: PlaybackSongSelectionDispatchFacts.Domain?
    let spans: [Span]
    let storageGrowthCount: Int
    static let notAdapterProduced = Self(coverage: .notAdapterProduced, domain: nil, spans: [], storageGrowthCount: 0)

    /// Planning-only capture at existing diagnostic construction sites; no song/tick reduction.
    struct Observer {
        var spans = [Span]()
        var storageGrowthCount = 0
        var capturedChildCount = 0
        var referencedChildCount = 0
        var referencedChildCapacity = 0

        @discardableResult
        mutating func record(family: Family, diagnosticIndex: Int, rowSpeed: Int,
            children: [PlaybackSongSyntheticTonePortamentoStepUpdate]) -> Int? {
            let count = children.count - (children.last?.syntheticTick == rowSpeed ? 1 : 0)
            guard count > 0 else { return nil }
            let capacity = spans.capacity
            spans.append(.init(diagnosticIndex: diagnosticIndex, capturedChildCount: count,
                originalChildren: children, family: family))
            if spans.capacity != capacity { storageGrowthCount += 1 }
            capturedChildCount += count
            referencedChildCount += children.count
            referencedChildCapacity += children.capacity
            return spans.count - 1
        }

        func evidence(domain: PlaybackSongSelectionDispatchFacts.Domain) -> PlaybackSongNativePitchWriterSpans {
            .init(coverage: .partialChildBearingProducersV1, domain: domain, spans: spans,
                storageGrowthCount: storageGrowthCount)
        }
    }
}

extension PlaybackSongSyntheticPlan {
    /// Looks up one captured original child; nil means unobserved, never native period zero.
    func nativePitchWriter(span spanIndex: Int, child childIndex: Int) -> PlaybackSongNativePitchWriterSpans.Observation? {
        let evidence = nativePitchWriterSpans
        guard evidence.coverage == .partialChildBearingProducersV1, let domain = evidence.domain,
              evidence.spans.indices.contains(spanIndex) else { return nil }
        let span = evidence.spans[spanIndex]
        guard let child = span.child(at: childIndex) else { return nil }
        let before = domain == .linear ? child.linearPeriodBefore : child.amigaPeriodBefore
        let after = domain == .linear ? child.linearPeriodAfter : child.amigaPeriodAfter
        guard let before, let after else { return nil }
        typealias Delivery = PlaybackSongNativePitchWriterSpans.Delivery
        var source: PlaybackPosition
        var row: Int, channel: Int
        var generation: Int?
        var currentChildren: [PlaybackSongSyntheticTonePortamentoStepUpdate]
        var delivery = Delivery.unknownDelivery
        let index = span.diagnosticIndex
        switch span.family {
        case .tonePortamento:
            guard diagnostics.tonePortamentoEffects.indices.contains(index) else { return nil }
            let command = diagnostics.tonePortamentoEffects[index]
            source = command.source; row = command.syntheticRow; channel = command.channelIndex
            generation = command.activeEventIndex; currentChildren = command.stepUpdates
        case .portamentoSlide:
            guard diagnostics.portamentoSlideEffects.indices.contains(index) else { return nil }
            let command = diagnostics.portamentoSlideEffects[index]
            source = command.source; row = command.syntheticRow; channel = command.channelIndex
            generation = command.activeEventIndex; currentChildren = command.stepUpdates
        case .finePortamentoUp:
            guard diagnostics.finePortamentoUpEffects.indices.contains(index) else { return nil }
            let command = diagnostics.finePortamentoUpEffects[index]
            source = command.source; row = command.syntheticRow; channel = command.channelIndex
            generation = command.activeEventIndex; currentChildren = command.stepUpdates
            if command.execution.publicationSuppressionReason == "no_active_source" { delivery = .suppressedNoActiveSource }
        case .finePortamentoDown:
            guard diagnostics.finePortamentoDownEffects.indices.contains(index) else { return nil }
            let command = diagnostics.finePortamentoDownEffects[index]
            source = command.source; row = command.syntheticRow; channel = command.channelIndex
            generation = command.activeEventIndex; currentChildren = command.stepUpdates
            if command.execution.publicationSuppressionReason == "no_active_source" { delivery = .suppressedNoActiveSource }
        case .extraFinePortamento:
            guard diagnostics.extraFinePortamentoEffects.indices.contains(index) else { return nil }
            let command = diagnostics.extraFinePortamentoEffects[index]
            source = command.source; row = command.syntheticRow; channel = command.channelIndex
            generation = command.activeEventIndex; currentChildren = command.stepUpdates
            if command.execution.publicationSuppressionReason == "no_active_source" { delivery = .suppressedNoActiveSource }
        case .arpeggio:
            guard diagnostics.arpeggioEffects.indices.contains(index) else { return nil }
            let command = diagnostics.arpeggioEffects[index]
            source = command.source; row = command.syntheticRow; channel = command.channelIndex
            generation = command.activeEventIndex; currentChildren = command.stepUpdates
        case .vibrato:
            guard diagnostics.vibratoEffects.indices.contains(index) else { return nil }
            let command = diagnostics.vibratoEffects[index]
            source = command.source; row = command.syntheticRow; channel = command.channelIndex
            generation = command.activeEventIndex; currentChildren = command.stepUpdates
            if command.inactiveSourceStepUpdates.contains(child) { delivery = .suppressedNoActiveSource }
            if childIndex == span.capturedChildCount - 1, command.supersededDelayedBirth == child {
                delivery = .supersededDelayedBirth
            }
        }
        // Matching the same immutable ordinal proves diagnostic retention only. After
        // interior filtering, uncertain ordinal association remains unknown delivery.
        if delivery == .unknownDelivery, currentChildren.indices.contains(childIndex) {
            let current = currentChildren[childIndex]
            // Composition changes physical step payloads, never this captured native identity.
            if current.syntheticTick == child.syntheticTick && current.scheduledFrame == child.scheduledFrame &&
                current.linearPeriodBefore == child.linearPeriodBefore && current.linearPeriodAfter == child.linearPeriodAfter &&
                current.amigaPeriodBefore == child.amigaPeriodBefore && current.amigaPeriodAfter == child.amigaPeriodAfter &&
                current.reachedTarget == child.reachedTarget && current.clamped == child.clamped && current.vibrato == child.vibrato {
                delivery = .retainedDiagnosticChild
            }
        }
        return .init(family: span.family, diagnosticIndex: index, childIndex: childIndex,
            producerAppendOrdinal: spanIndex, source: source, syntheticRow: row, channelIndex: channel,
            syntheticTick: child.syntheticTick, scheduledFrame: child.scheduledFrame, domain: domain,
            nativePeriodBefore: before, nativePeriodAfter: after, associatedGeneration: generation,
            delivery: delivery)
    }
}
