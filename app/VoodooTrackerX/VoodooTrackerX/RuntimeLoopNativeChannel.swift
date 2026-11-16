import Synchronization

/// Equality is exact and independent of callback/UI notification timing.
struct RuntimeLoopNativeScope: Equatable, Sendable, Encodable {
    enum TransportKind: String, Sendable {
        case explicitLoop = "explicit_loop"
        case finiteSong = "finite_song"
    }

    let documentHigh: UInt64
    let documentLow: UInt64
    let sourceGeneration: UInt64
    let transportEpoch: UInt64
    let sampleRateBits: UInt64
    let semanticVersion: UInt32
    let linearFrequencyMode: Bool
    let order: Int
    let pattern: Int
    let firstRow: Int
    let lastRow: Int
    var transportKind: TransportKind = .explicitLoop

    private enum CodingKeys: String, CodingKey {
        case documentHigh, documentLow, sourceGeneration, transportEpoch, sampleRateBits
        case semanticVersion, linearFrequencyMode, order, pattern, firstRow, lastRow, transportKind
    }

    /// Preserve the existing explicit-Loop v1 scope bytes; finite mode is explicit.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(documentHigh, forKey: .documentHigh)
        try container.encode(documentLow, forKey: .documentLow)
        try container.encode(sourceGeneration, forKey: .sourceGeneration)
        try container.encode(transportEpoch, forKey: .transportEpoch)
        try container.encode(sampleRateBits, forKey: .sampleRateBits)
        try container.encode(semanticVersion, forKey: .semanticVersion)
        try container.encode(linearFrequencyMode, forKey: .linearFrequencyMode)
        try container.encode(order, forKey: .order)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(firstRow, forKey: .firstRow)
        try container.encode(lastRow, forKey: .lastRow)
        if transportKind != .explicitLoop {
            try container.encode(transportKind.rawValue, forKey: .transportKind)
        }
    }
}

/// Original source numbers stay local to their immutable birth plan.
struct RuntimeLoopNativeSourceIdentity: Equatable, Hashable, Sendable, Encodable {
    let sourceGeneration: UInt64
    let transportEpoch: UInt64
    let birthSequence: UInt64
    let birthEventIndex: Int
}

/// A lookup import is a binding, never a note-trigger command.
struct RuntimeLoopNativeSourceBinding: Equatable, Sendable {
    let localLookupIndex: Int
    let birth: RuntimeLoopNativeSourceIdentity
    let nativeSlot: Int
    let nativeIncarnation: UInt64
}

/// Explicit traversal iteration transition; row zero alone is not a boundary.
struct RuntimeLoopNativeIterationBoundary: Sendable {
    let localFrame: Int
    let iteration: UInt64
    let stateToken: UInt64
}

/// Prepared authorization to supersede only a verified executed active prefix.
struct RuntimeLoopNativeEarlyCutover: Sendable {
    let previousScope: RuntimeLoopNativeScope
    let predecessorSequence: UInt64
    let boundaryFrame: UInt64
    let boundaryStateToken: UInt64
    let requestSerial: UInt64
}

/// The frame/token distinguish an early executed prefix from an unplayed discarded tail.
struct RuntimeLoopNativeExecutionFrontier: Equatable, Sendable {
    let sourceGeneration: UInt64
    let sequence: UInt64
    let frame: UInt64
    let stateToken: UInt64
    let wholeBatch: Bool
    let admittedSourceGeneration: UInt64 // Zero means no successor was admitted.
    let admittedSequence: UInt64
    var firstNaturalBoundaryAfterReady: UInt64 = 0
}

private final class RuntimeLoopNativeFrontierPublication {
    private let stamp = Atomic<UInt64>(0)
    private let valid = Atomic(false)
    private let generation = Atomic<UInt64>(0), sequence = Atomic<UInt64>(0)
    private let frame = Atomic<UInt64>(0), token = Atomic<UInt64>(0)
    private let whole = Atomic(false)
    private let firstReadyBoundary = Atomic<UInt64>(0)
    private let admittedGeneration = Atomic<UInt64>(0), admittedSequence = Atomic<UInt64>(0)
    func publish(_ value: RuntimeLoopNativeExecutionFrontier) {
        _ = stamp.wrappingAdd(1, ordering: .sequentiallyConsistent)
        generation.store(value.sourceGeneration, ordering: .sequentiallyConsistent)
        sequence.store(value.sequence, ordering: .sequentiallyConsistent)
        frame.store(value.frame, ordering: .sequentiallyConsistent)
        token.store(value.stateToken, ordering: .sequentiallyConsistent)
        whole.store(value.wholeBatch, ordering: .sequentiallyConsistent)
        firstReadyBoundary.store(value.firstNaturalBoundaryAfterReady, ordering: .sequentiallyConsistent)
        admittedGeneration.store(value.admittedSourceGeneration, ordering: .sequentiallyConsistent)
        admittedSequence.store(value.admittedSequence, ordering: .sequentiallyConsistent)
        valid.store(true, ordering: .sequentiallyConsistent)
        _ = stamp.wrappingAdd(1, ordering: .sequentiallyConsistent)
    }
    func read() -> RuntimeLoopNativeExecutionFrontier? {
        let first = stamp.load(ordering: .sequentiallyConsistent)
        guard first & 1 == 0, valid.load(ordering: .sequentiallyConsistent) else { return nil }
        let result = RuntimeLoopNativeExecutionFrontier(sourceGeneration: generation.load(ordering: .sequentiallyConsistent),
            sequence: sequence.load(ordering: .sequentiallyConsistent), frame: frame.load(ordering: .sequentiallyConsistent),
            stateToken: token.load(ordering: .sequentiallyConsistent), wholeBatch: whole.load(ordering: .sequentiallyConsistent),
            admittedSourceGeneration: admittedGeneration.load(ordering: .sequentiallyConsistent),
            admittedSequence: admittedSequence.load(ordering: .sequentiallyConsistent),
            firstNaturalBoundaryAfterReady: firstReadyBoundary.load(ordering: .sequentiallyConsistent))
        return stamp.load(ordering: .sequentiallyConsistent) == first ? result : nil
    }
}

/// POD view into immutable native-ready memory retained by an off-audio owner.
/// Neither pointer may refer to temporary Swift Array buffer-borrow storage.
struct RuntimeLoopNativeBatchHeader: @unchecked Sendable {
    let scope: RuntimeLoopNativeScope
    let sequence: UInt64 // One-based, never reused within this scope/epoch.
    let predecessorSequence: UInt64
    let predecessorStateToken: UInt64
    let terminalStateToken: UInt64
    let firstIteration: UInt64
    let runtimeStartFrame: UInt64
    let runtimeEndFrame: UInt64 // Exclusive for audio; zero-tail finite end writers may run here before acknowledgement.
    let localStartFrame: Int
    let commands: UnsafeRawPointer?
    let commandCount: Int
    let commandStride: Int
    let bindings: UnsafePointer<RuntimeLoopNativeSourceBinding>?
    let bindingCount: Int
    var followRows: UnsafePointer<RuntimeLoopNativeFollowRow>? = nil
    var followRowCount: Int = 0
    // Callback is sole writer; producer reads only after retirement acquire/quiescence.
    var executedRawIDWords: UnsafeMutablePointer<UInt64>? = nil
    var executedRawIDWordCount: Int = 0
    var naturalBoundaries: UnsafePointer<RuntimeLoopNativeIterationBoundary>? = nil
    var naturalBoundaryCount: Int = 0
    var earlyCutover: RuntimeLoopNativeEarlyCutover? = nil
    // A finite terminal owns its musical boundary and the tail through runtimeEndFrame.
    var finiteSongEndFrame: UInt64? = nil

    var hasValidShape: Bool {
        sequence > 0 && terminalStateToken > 0 && runtimeEndFrame > runtimeStartFrame &&
            localStartFrame >= 0 && commandCount >= 0 && bindingCount >= 0 &&
            (commandCount == 0 || (commands != nil && commandStride > 0)) &&
            (bindingCount == 0 || bindings != nil) && followRowCount >= 0 &&
            (followRowCount == 0 || followRows != nil) && executedRawIDWordCount >= 0 &&
            (executedRawIDWordCount == 0 || executedRawIDWords != nil) && naturalBoundaryCount >= 0 &&
            (naturalBoundaryCount == 0 || naturalBoundaries != nil) &&
            (finiteSongEndFrame.map { scope.transportKind == .finiteSong &&
                $0 >= runtimeStartFrame && $0 <= runtimeEndFrame && earlyCutover == nil } ?? true)
    }
}

/// A non-owning view, valid only until callback retirement or host quiescence.
struct RuntimeLoopNativeBatchLease: @unchecked Sendable {
    let slot: Int
    let header: RuntimeLoopNativeBatchHeader
}

enum RuntimeLoopNativeAdmission {
    case admitted(RuntimeLoopNativeBatchLease)
    case completed(RuntimeLoopNativeSongCompletion)
    case missingSuccessor
    case revoked
    case invalidBoundary
    case invalidSuccessor
}

/// Successful finite delivery, published only after its exact C tail-stop boundary.
struct RuntimeLoopNativeSongCompletion: Equatable, Sendable {
    let scope: RuntimeLoopNativeScope
    let musicalEndFrame: UInt64
    let runtimeEndFrame: UInt64
}

/// Single serial producer + one serialized render consumer; revoke may run elsewhere.
/// This object and its two slots must outlive every callback that can borrow a lease.
final class RuntimeLoopNativeTwoSlotChannel: @unchecked Sendable {
    struct Reservation: Sendable {
        fileprivate let slot: Int
        fileprivate let serial: UInt64
    }

    private enum State {
        static let free: UInt8 = 0, preparing: UInt8 = 1, ready: UInt8 = 2
        static let active: UInt8 = 3, retired: UInt8 = 4
    }
    private final class Slot {
        let state = Atomic<UInt8>(State.free)
        // Producer writes before release publication; callback reads after acquire claim.
        // Once published, neither field changes before retirement/quiescence.
        var header: RuntimeLoopNativeBatchHeader?
        var owner: AnyObject? // Accessed/released only by the serial off-audio producer.
        var reservationSerial: UInt64 = 0 // Producer-only ABA protection.
        let firstBoundaryToken = Atomic<UInt64>(0), firstBoundaryFrame = Atomic<UInt64>(0)
        let optionalCutoverFrame = Atomic<UInt64>(.max) // Safe scalar peek; header requires mailbox ownership.
    }

    private static let observationBusy: UInt64 = 1 << 63, observationReady: UInt64 = 1 << 62
    private static let closed: UInt64 = .max
    private static let claiming: UInt64 = .max - 1 // Callback owns the publication while checking its immutable header.
    private let scope: RuntimeLoopNativeScope
    private let slots = [Slot(), Slot()] // Allocate once, outside rendering.
    private let revoked = Atomic(false)
    private let terminalPublished = Atomic(false)
    private let mailbox = Atomic<UInt64>(0) // 0 none, 1/2 published slot, max closed.
    private let executedSequence = Atomic<UInt64>(0)
    private let executionFrontier = RuntimeLoopNativeFrontierPublication()
    private let authorizedRefreshSerial = Atomic<UInt64>(0)
    private let admittedScopeGeneration = Atomic<UInt64>(0)
    private let rejectedRefreshSerial = Atomic<UInt64>(0)
    private var publicationSerial: UInt64 = 0 // Producer-only; encoded in every mailbox token.
    private var activeSlot = -1 // Callback-only until explicit host quiescence.

    init(scope: RuntimeLoopNativeScope) {
        self.scope = scope
        admittedScopeGeneration.store(scope.sourceGeneration, ordering: .relaxed)
    }

    /// Reserve BEFORE construction; active+ready leaves no third construction slot.
    /// Call only on the one serial off-audio producer.
    func reserve() -> Reservation? {
        let word = mailbox.load(ordering: .acquiring)
        guard !revoked.load(ordering: .acquiring), !terminalPublished.load(ordering: .acquiring),
              word != Self.closed, word != Self.claiming else { return nil }
        for index in 0..<2 {
            let slot = slots[index]
            guard slot.state.compareExchange(expected: State.free, desired: State.preparing,
                ordering: .acquiringAndReleasing).exchanged else { continue }
            precondition(slot.reservationSerial < .max, "Loop reservation serial exhausted")
            slot.reservationSerial += 1
            return Reservation(slot: index, serial: slot.reservationSerial)
        }
        return nil
    }

    /// Publish immutable buffers; this never waits on the callback's render lock.
    /// The retaining owner must own every pointer target, including native PCM leases.
    /// A successful publication may subsequently be revoked; its roots then stay pinned.
    @discardableResult
    func publish(_ reservation: Reservation, header: RuntimeLoopNativeBatchHeader,
                 retaining owner: AnyObject) -> Bool {
        guard validReservation(reservation) else { return false }
        guard !revoked.load(ordering: .acquiring), !terminalPublished.load(ordering: .acquiring)
            else { discard(reservation); return false }
        let slot = slots[reservation.slot]
        guard compatibleTransport(header.scope), header.hasValidShape, publishableScope(header) else {
            discard(reservation)
            return false
        }
        guard publicationSerial < (UInt64.max >> 4) else { discard(reservation); return false }
        publicationSerial += 1
        let word = (publicationSerial << 2) | UInt64(reservation.slot + 1)
        slot.header = header
        slot.owner = owner
        slot.optionalCutoverFrame.store(header.earlyCutover?.boundaryFrame ?? .max, ordering: .relaxed)
        slot.firstBoundaryFrame.store(0, ordering: .relaxed)
        slot.firstBoundaryToken.store(word, ordering: .relaxed)
        slot.state.store(State.ready, ordering: .relaxed)
        if mailbox.compareExchange(expected: 0, desired: word,
            ordering: .releasing).exchanged {
            if header.finiteSongEndFrame != nil { terminalPublished.store(true, ordering: .releasing) }
            return true
        }
        // Failed CAS means this slot was never published or visible to the callback.
        slot.owner = nil
        slot.header = nil
        slot.state.store(State.free, ordering: .releasing)
        return false
    }

    /// Abandon only an unpublished reservation, on the serial off-audio producer.
    func discard(_ reservation: Reservation) {
        guard validReservation(reservation) else { return }
        slots[reservation.slot].state.store(State.free, ordering: .releasing)
    }

    /// Coalescing callers authorize the newest request immediately, before queued construction.
    func authorizeRefreshRequest(_ serial: UInt64) {
        precondition(serial > 0)
        var current = authorizedRefreshSerial.load(ordering: .acquiring)
        while serial > current { // Off-audio request publication, never a callback loop.
            let result = authorizedRefreshSerial.compareExchange(expected: current, desired: serial,
                ordering: .acquiringAndReleasing)
            if result.exchanged { return }
            current = result.original
        }
    }

    /// Serial producer only. A callback that won mailbox ownership may still show ready
    /// briefly; losing this CAS therefore grants no permission to touch its slot/header.
    func retractReady() -> Reservation? {
        guard scope.transportKind == .explicitLoop, !revoked.load(ordering: .acquiring) else { return nil }
        let word = mailbox.load(ordering: .acquiring)
        guard let index = slotIndex(for: word),
              mailbox.compareExchange(expected: word, desired: 0, ordering: .acquiringAndReleasing).exchanged else { return nil }
        let slot = slots[index]
        precondition(slot.state.load(ordering: .acquiring) == State.ready)
        slot.owner = nil; slot.header = nil // Off-audio release; this batch was never claimed.
        guard !revoked.load(ordering: .acquiring), mailbox.load(ordering: .acquiring) != Self.closed else {
            slot.state.store(State.free, ordering: .releasing); return nil
        }
        precondition(slot.reservationSerial < .max)
        slot.reservationSerial += 1
        slot.state.store(State.preparing, ordering: .releasing)
        return .init(slot: index, serial: slot.reservationSerial)
    }

    /// Optional natural boundary. No candidate or a retraction race continues old active
    /// playback. Only a successfully claimed immutable header can authorize a scope change.
    func tryAdmitEarlyCutover(at frame: UInt64, stateToken: UInt64) -> RuntimeLoopNativeBatchLease? {
        guard scope.transportKind == .explicitLoop, !revoked.load(ordering: .acquiring), activeSlot >= 0,
              let old = slots[activeSlot].header,
              matchesNaturalBoundary(old, frame: frame, token: stateToken) else { return nil }
        let word = mailbox.load(ordering: .acquiring)
        guard let index = slotIndex(for: word) else { return nil }
        let candidate = slots[index]
        let targetFrame = candidate.optionalCutoverFrame.load(ordering: .acquiring)
        if targetFrame != .max,
           candidate.firstBoundaryToken.compareExchange(expected: word, desired: word | Self.observationBusy,
                ordering: .acquiringAndReleasing).exchanged {
            candidate.firstBoundaryFrame.store(frame, ordering: .relaxed)
            _ = candidate.firstBoundaryToken.compareExchange(expected: word | Self.observationBusy,
                desired: word | Self.observationReady, ordering: .releasing)
        }
        guard targetFrame <= frame,
              mailbox.compareExchange(expected: word, desired: Self.claiming, ordering: .acquiringAndReleasing).exchanged else { return nil }
        guard candidate.state.load(ordering: .acquiring) == State.ready,
              let header = candidate.header else {
            candidate.state.store(State.retired, ordering: .releasing)
            _ = mailbox.compareExchange(expected: Self.claiming, desired: 0, ordering: .acquiringAndReleasing)
            return nil
        }
        let next = old.sequence.addingReportingOverflow(1)
        guard let cutover = header.earlyCutover, !next.overflow, header.hasValidShape,
              compatibleTransport(header.scope), cutover.previousScope == old.scope,
              header.scope.sourceGeneration > old.scope.sourceGeneration,
              cutover.requestSerial == authorizedRefreshSerial.load(ordering: .acquiring),
              cutover.requestSerial > 0, cutover.predecessorSequence == old.sequence,
              cutover.boundaryFrame == frame, cutover.boundaryStateToken == stateToken,
              header.runtimeStartFrame == frame, header.sequence == next.partialValue,
              header.predecessorSequence == old.sequence, header.predecessorStateToken == stateToken,
              frame > old.runtimeStartFrame, frame <= old.runtimeEndFrame,
              !revoked.load(ordering: .acquiring), mailbox.load(ordering: .acquiring) != Self.closed else {
            rejectedRefreshSerial.store(header.earlyCutover?.requestSerial ?? 0, ordering: .releasing)
            candidate.state.store(State.retired, ordering: .releasing)
            _ = mailbox.compareExchange(expected: Self.claiming, desired: 0, ordering: .acquiringAndReleasing)
            return nil
        }
        guard mailbox.compareExchange(expected: Self.claiming, desired: 0,
            ordering: .acquiringAndReleasing).exchanged else {
            candidate.state.store(State.retired, ordering: .releasing); return nil
        }
        let oldSlot = activeSlot
        activeSlot = index
        candidate.state.store(State.active, ordering: .releasing)
        admittedScopeGeneration.store(header.scope.sourceGeneration, ordering: .releasing)
        publishRetirement(old, frame: frame, token: stateToken, whole: frame == old.runtimeEndFrame,
            admitted: header, firstReadyBoundary: candidate.firstBoundaryToken.load(ordering: .acquiring) == word | Self.observationReady
                ? candidate.firstBoundaryFrame.load(ordering: .relaxed) : 0)
        // Old commands/pointers must not be read after this release publication.
        slots[oldSlot].state.store(State.retired, ordering: .releasing)
        return .init(slot: index, header: header)
    }

    /// Claim first batch at the actual start frame, before interpreting any commands.
    /// Call only from the serialized callback/render owner.
    func begin(at runtimeFrame: UInt64) -> RuntimeLoopNativeAdmission {
        guard activeSlot == -1 else { return seal(.invalidBoundary) }
        return claimReady(sequence: 1, predecessor: 0, stateToken: 0, frame: runtimeFrame, expectedScope: scope)
    }

    /// Render the complete active interval first, including silent/held frames.
    /// At its exclusive end acknowledge execution and claim the exact successor,
    /// or complete a finite terminal whose C voices the cursor already cleared.
    func finishBoundary(at runtimeFrame: UInt64) -> RuntimeLoopNativeAdmission {
        guard activeSlot >= 0, let old = slots[activeSlot].header,
              runtimeFrame == old.runtimeEndFrame else { return seal(.invalidBoundary) }
        let oldSlot = activeSlot
        activeSlot = -1
        let next = old.sequence.addingReportingOverflow(1)
        let result: RuntimeLoopNativeAdmission
        if let musicalEnd = old.finiteSongEndFrame {
            // The cursor clears C voices before calling this method. Closing and
            // releasing the old owner must never precede that last PCM borrow.
            let word = mailbox.exchange(Self.closed, ordering: .acquiringAndReleasing)
            if revoked.load(ordering: .acquiring) { result = .revoked }
            else if word == 0 {
                result = .completed(.init(scope: old.scope, musicalEndFrame: musicalEnd,
                                          runtimeEndFrame: runtimeFrame))
            } else {
                if let index = slotIndex(for: word) { slots[index].state.store(State.retired, ordering: .releasing) }
                result = seal(.invalidSuccessor)
            }
        } else if next.overflow { result = seal(.invalidSuccessor) }
        else { result = claimReady(sequence: next.partialValue, predecessor: old.sequence,
            stateToken: old.terminalStateToken, frame: runtimeFrame, expectedScope: old.scope) }
        let admitted: RuntimeLoopNativeBatchHeader?
        if case let .admitted(value) = result { admitted = value.header } else { admitted = nil }
        publishRetirement(old, frame: runtimeFrame, token: old.terminalStateToken, whole: true, admitted: admitted)
        // No callback access to old slot/payload follows this release store.
        slots[oldSlot].state.store(State.retired, ordering: .releasing)
        return result
    }

    /// Callback-only borrowed access; no retain/release of a payload owner occurs here.
    func currentLease() -> RuntimeLoopNativeBatchLease? {
        guard activeSlot >= 0, let header = slots[activeSlot].header else { return nil }
        return .init(slot: activeSlot, header: header)
    }

    /// A scalar delivered frontier; never advance this from speculative preparation.
    var acknowledgedSequence: UInt64 { executedSequence.load(ordering: .acquiring) }
    var latestExecutionFrontier: RuntimeLoopNativeExecutionFrontier? { executionFrontier.read() }
    var rejectedRefreshRequestSerial: UInt64 { rejectedRefreshSerial.load(ordering: .acquiring) }

    /// Sticky revocation. Published roots remain held until retirement or quiescence.
    func revoke() {
        revoked.store(true, ordering: .releasing)
        _ = mailbox.exchange(Self.closed, ordering: .acquiringAndReleasing)
    }

    /// Release acknowledged/rejected payloads on the serial off-audio producer only.
    /// Retired slots do not alone imply execution; use acknowledgedSequence for that.
    @discardableResult
    func reclaimRetired(beforeRelease: ((AnyObject) -> Void)? = nil) -> Int {
        var reclaimed = 0
        for index in 0..<2 {
            let slot = slots[index]
            guard slot.state.load(ordering: .acquiring) == State.retired else { continue }
            if let owner = slot.owner { beforeRelease?(owner) }
            slot.owner = nil
            slot.header = nil
            slot.state.store(State.free, ordering: .releasing)
            reclaimed += 1
        }
        return reclaimed
    }

    /// Call off audio only AFTER producer cancellation/join AND host callback quiescence.
    /// An atomic revoke alone is not proof that a callback stopped borrowing its lease.
    func shutdownAfterCallbackQuiescence(beforeRelease: ((AnyObject) -> Void)? = nil) {
        revoke()
        activeSlot = -1
        for index in 0..<2 {
            if let owner = slots[index].owner { beforeRelease?(owner) }
            slots[index].owner = nil
            slots[index].header = nil
            slots[index].state.store(State.free, ordering: .releasing)
        }
    }

    private func compatibleTransport(_ value: RuntimeLoopNativeScope) -> Bool {
        value.documentHigh == scope.documentHigh && value.documentLow == scope.documentLow &&
            value.transportKind == scope.transportKind &&
            value.transportEpoch == scope.transportEpoch && value.sampleRateBits == scope.sampleRateBits &&
            value.semanticVersion == scope.semanticVersion && value.linearFrequencyMode == scope.linearFrequencyMode &&
            value.order == scope.order && value.pattern == scope.pattern &&
            value.firstRow == scope.firstRow && value.lastRow == scope.lastRow
    }

    private func matchesNaturalBoundary(_ header: RuntimeLoopNativeBatchHeader, frame: UInt64, token: UInt64) -> Bool {
        guard frame >= header.runtimeStartFrame, let entries = header.naturalBoundaries else { return false }
        let offset = frame - header.runtimeStartFrame
        guard offset <= UInt64(Int.max), header.localStartFrame <= Int.max - Int(offset) else { return false }
        let local = header.localStartFrame + Int(offset)
        for index in 0..<header.naturalBoundaryCount where entries[index].localFrame == local && entries[index].stateToken == token {
            return true
        }
        return false
    }

    private func publishableScope(_ header: RuntimeLoopNativeBatchHeader) -> Bool {
        let admitted = admittedScopeGeneration.load(ordering: .acquiring)
        guard let edit = header.earlyCutover else { return header.scope.sourceGeneration == admitted }
        return scope.transportKind == .explicitLoop && compatibleTransport(edit.previousScope) && edit.previousScope.sourceGeneration == admitted &&
            header.scope.sourceGeneration > admitted && edit.requestSerial > 0 &&
            edit.requestSerial == authorizedRefreshSerial.load(ordering: .acquiring)
    }

    private func slotIndex(for word: UInt64) -> Int? {
        guard word != Self.closed, word != Self.claiming, word >> 2 > 0 else { return nil }
        let tag = word & 3
        return tag == 1 || tag == 2 ? Int(tag) - 1 : nil
    }

    private func publishRetirement(_ old: RuntimeLoopNativeBatchHeader, frame: UInt64, token: UInt64, whole: Bool,
                                   admitted: RuntimeLoopNativeBatchHeader?, firstReadyBoundary: UInt64 = 0) {
        executionFrontier.publish(.init(sourceGeneration: old.scope.sourceGeneration, sequence: old.sequence,
            frame: frame, stateToken: token, wholeBatch: whole,
            admittedSourceGeneration: admitted?.scope.sourceGeneration ?? 0, admittedSequence: admitted?.sequence ?? 0,
            firstNaturalBoundaryAfterReady: firstReadyBoundary))
        executedSequence.store(old.sequence, ordering: .releasing)
    }

    private func validReservation(_ value: Reservation) -> Bool {
        (0..<2).contains(value.slot) && slots[value.slot].reservationSerial == value.serial &&
            slots[value.slot].state.load(ordering: .acquiring) == State.preparing
    }

    private func seal(_ result: RuntimeLoopNativeAdmission) -> RuntimeLoopNativeAdmission {
        revoke()
        return result
    }

    private func claimReady(sequence: UInt64, predecessor: UInt64, stateToken: UInt64,
                            frame: UInt64, expectedScope: RuntimeLoopNativeScope) -> RuntimeLoopNativeAdmission {
        // This exchange is the exact mandatory-deadline linearization point. It claims
        // any ready serial token without a retry loop and prevents retraction/header reuse.
        guard !revoked.load(ordering: .acquiring) else { return .revoked }
        let word = mailbox.exchange(Self.claiming, ordering: .acquiringAndReleasing)
        if word == Self.closed {
            mailbox.store(Self.closed, ordering: .releasing)
            return .revoked
        }
        if word == 0 {
            mailbox.store(Self.closed, ordering: .releasing)
            return .missingSuccessor
        }
        guard let index = slotIndex(for: word) else { return seal(.invalidSuccessor) }
        let slot = slots[index]
        guard slot.state.load(ordering: .acquiring) == State.ready,
              let header = slot.header else { return seal(.invalidSuccessor) }
        guard header.scope == expectedScope, header.earlyCutover == nil, header.hasValidShape, header.sequence == sequence,
              header.predecessorSequence == predecessor, header.predecessorStateToken == stateToken,
              header.runtimeStartFrame == frame else {
            // Reclamation is off audio; this rejected batch never advances executedSequence.
            slot.state.store(State.retired, ordering: .releasing)
            return seal(.invalidSuccessor)
        }
        guard mailbox.compareExchange(expected: Self.claiming, desired: 0,
            ordering: .acquiringAndReleasing).exchanged else {
            slot.state.store(State.retired, ordering: .releasing)
            return .revoked
        }
        activeSlot = index
        slot.state.store(State.active, ordering: .releasing)
        return .admitted(.init(slot: index, header: header))
    }
}
