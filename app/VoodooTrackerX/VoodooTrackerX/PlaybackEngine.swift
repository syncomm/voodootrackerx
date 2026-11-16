import Foundation
import os

/// Bounded request meaning only: never owns source, checkpoint, event or PCM payloads.
/// B2 supplies this meaning through the engine-local production source broker.
struct PlaybackPreparationKey: Equatable, Sendable {
    enum FrequencyMode: Equatable, Sendable { case linear, amiga }
    struct Bounds: Equatable, Sendable { let lowerOrder: Int; let upperOrder: Int }
    enum Origin: Equatable, Sendable { case cold(order: Int, row: Int), warm(frontier: UInt64) }
    enum Purpose: Equatable, Sendable { case normalPlay, resetSeek, loopRefresh, editRefresh, userLoop }
    struct LoopScope: Equatable, Sendable { let order: Int; let pattern: Int }

    let instanceEpoch: UUID
    let transportEpoch: UInt64
    let documentID: UUID
    let revision: UInt64
    let sourceGeneration: UInt64
    let sampleRateBits: UInt64
    let frequencyMode: FrequencyMode
    let traversalBounds: Bounds
    let origin: Origin
    let purpose: Purpose
    let loopScope: LoopScope?
    let backendVersion: UInt64
    let plannerVersion: UInt64
    let renderProfile: UInt64

    init?(
        instanceEpoch: UUID, transportEpoch: UInt64 = 0, documentID: UUID,
        revision: UInt64 = 0, sourceGeneration: UInt64 = 0, sampleRate: Double,
        frequencyMode: FrequencyMode = .linear,
        traversalBounds: Bounds = .init(lowerOrder: 0, upperOrder: 1),
        origin: Origin = .cold(order: 0, row: 0), purpose: Purpose = .normalPlay,
        loopScope: LoopScope? = nil, backendVersion: UInt64 = 1,
        plannerVersion: UInt64 = 1, renderProfile: UInt64 = 0
    ) {
        guard sampleRate.isFinite, sampleRate > 0,
              traversalBounds.lowerOrder >= 0,
              traversalBounds.upperOrder > traversalBounds.lowerOrder else { return nil }
        if case let .cold(order, row) = origin {
            guard (traversalBounds.lowerOrder..<traversalBounds.upperOrder).contains(order), row >= 0 else { return nil }
        }
        if let loopScope {
            guard (traversalBounds.lowerOrder..<traversalBounds.upperOrder).contains(loopScope.order),
                  loopScope.pattern >= 0 else { return nil }
        }
        self.instanceEpoch = instanceEpoch
        self.transportEpoch = transportEpoch
        self.documentID = documentID
        self.revision = revision
        self.sourceGeneration = sourceGeneration
        self.sampleRateBits = sampleRate.bitPattern
        self.frequencyMode = frequencyMode
        self.traversalBounds = traversalBounds
        self.origin = origin
        self.purpose = purpose
        self.loopScope = loopScope
        self.backendVersion = backendVersion
        self.plannerVersion = plannerVersion
        self.renderProfile = renderProfile
    }
}

/// Minted by one owner; equal content keys never authenticate another attempt.
struct PlaybackPreparationAttempt: Equatable, Sendable {
    fileprivate let ownerID: UUID
    let epoch: UUID
    let serial: UInt64
}

/// A producer checks this token within construction on its off-RT worker.
final class PlaybackPreparationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Cancels an off-Main preparation or timing-only metadata traversal.
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Notifications contain scalar identity/status only and may be delayed or discarded.
struct PlaybackPreparationNotification: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case ready, retired, claimed }
    let attempt: PlaybackPreparationAttempt
    let kind: Kind
}

/// Off-RT ownership proof, independent of planning horizon, event identity and native audio.
/// A separate core lets facade deinit revoke a paused producer without retaining the facade.
final class PlaybackPreparationOwner<Product: Sendable>: Sendable {
    typealias Attempt = PlaybackPreparationAttempt
    typealias Notification = PlaybackPreparationNotification
    enum Phase: Equatable, Sendable { case idle, constructing, draining, ready }
    enum WaitStatus: Equatable, Sendable { case ready, retired, timedOut, invalid }
    struct Snapshot: Sendable {
        let activeAttempt: PlaybackPreparationAttempt?
        let pendingAttempt: PlaybackPreparationAttempt?
        let phase: Phase
        let retiredCount: UInt64
        let lastRetiredAttempt: PlaybackPreparationAttempt?
        let isShutdown: Bool
        let hasReadyProduct: Bool
        var activeCount: Int { activeAttempt == nil ? 0 : 1 }
        var pendingCount: Int { pendingAttempt == nil ? 0 : 1 }
    }

    private struct Request: Sendable {
        let key: PlaybackPreparationKey
        let attempt: PlaybackPreparationAttempt
    }

    /// All mutable state is protected by condition; neither producer nor observer runs under it.
    private final class Core: @unchecked Sendable {
        let condition = NSCondition()
        let ownerID = UUID()
        let queue: DispatchQueue
        let producer: @Sendable (PlaybackPreparationKey, PlaybackPreparationAttempt, PlaybackPreparationCancellation) -> Product?
        let notify: @Sendable (PlaybackPreparationNotification) -> Void
        var epoch = UUID()
        var serial: UInt64
        var active: Request?
        var pending: Request?
        var token: PlaybackPreparationCancellation?
        var product: Product?
        var phase: Phase = .idle
        var workerScheduled = false
        var closed = false
        var retiredCount: UInt64 = 0
        var lastRetiredAttempt: PlaybackPreparationAttempt?

        init(
            target: DispatchQueue?, initialSerial: UInt64,
            producer: @escaping @Sendable (PlaybackPreparationKey, PlaybackPreparationAttempt, PlaybackPreparationCancellation) -> Product?,
            notify: @escaping @Sendable (PlaybackPreparationNotification) -> Void
        ) {
            // Always serial, including when a caller supplies a concurrent target for testing.
            queue = DispatchQueue(label: "com.syncomm.VoodooTrackerX.preparation-owner", qos: .utility, target: target)
            serial = initialSerial
            self.producer = producer
            self.notify = notify
        }

        func offer(_ key: PlaybackPreparationKey) -> PlaybackPreparationAttempt? {
            condition.lock()
            defer { condition.unlock() }
            guard !closed else { return nil }
            let next = serial.addingReportingOverflow(1)
            if next.overflow {
                epoch = UUID()
                serial = 0
            } else {
                serial = next.partialValue
            }
            let attempt = PlaybackPreparationAttempt(ownerID: ownerID, epoch: epoch, serial: serial)
            pending = Request(key: key, attempt: attempt)
            revokeActiveLocked()
            scheduleLocked()
            condition.broadcast()
            return attempt
        }

        func revokeActiveLocked() {
            if active != nil {
                token?.cancel()
                phase = .draining
            }
        }

        func scheduleLocked() {
            guard !workerScheduled else { return }
            workerScheduled = true
            // One drain job, not one source-bearing closure per offered intent.
            queue.async { [self] in drain() }
        }

        func stop(shutdown: Bool) {
            condition.lock()
            if shutdown { closed = true }
            pending = nil
            revokeActiveLocked()
            if active != nil { scheduleLocked() }
            condition.broadcast()
            condition.unlock()
        }

        func observe(_ attempt: PlaybackPreparationAttempt, key: PlaybackPreparationKey) -> PlaybackPreparationAttempt? {
            condition.lock()
            defer { condition.unlock() }
            guard !closed else { return nil }
            if let active, active.attempt == attempt, active.key == key, phase != .draining { return attempt }
            if let pending, pending.attempt == attempt, pending.key == key { return attempt }
            return nil
        }

        func claim(_ attempt: PlaybackPreparationAttempt, key: PlaybackPreparationKey) -> Product? {
            condition.lock()
            guard !closed, phase == .ready,
                  let active, active.attempt == attempt, active.key == key else {
                condition.unlock()
                return nil
            }
            // The local value pins the payload through unlocking and transfer to its new owner.
            let claimed = product
            product = nil
            self.active = nil
            token = nil
            phase = .idle
            condition.broadcast()
            condition.unlock()
            notify(.init(attempt: attempt, kind: .claimed))
            return claimed
        }

        func wait(for attempt: PlaybackPreparationAttempt, timeout: TimeInterval) -> WaitStatus {
            guard timeout.isFinite, timeout >= 0 else { return .timedOut }
            let deadline = Date(timeIntervalSinceNow: timeout)
            condition.lock()
            defer { condition.unlock() }
            guard attempt.ownerID == ownerID else { return .invalid }
            while active?.attempt == attempt || pending?.attempt == attempt {
                if active?.attempt == attempt, phase == .ready { return .ready }
                guard condition.wait(until: deadline) else {
                    if active?.attempt == attempt, phase == .ready { return .ready }
                    if active?.attempt != attempt, pending?.attempt != attempt { return .retired }
                    return .timedOut
                }
            }
            // No speculative roots remain; a claimed product has transferred, not been destroyed.
            return .retired
        }

        var snapshot: Snapshot {
            condition.lock()
            defer { condition.unlock() }
            return Snapshot(activeAttempt: active?.attempt, pendingAttempt: pending?.attempt,
                phase: phase, retiredCount: retiredCount, lastRetiredAttempt: lastRetiredAttempt,
                isShutdown: closed, hasReadyProduct: product != nil)
        }

        func drain() {
            while true {
                condition.lock()
                if let active {
                    if phase == .ready {
                        workerScheduled = false
                        condition.unlock()
                        return
                    }
                    // Construction is synchronous on this same serial worker; only ready
                    // invalidation can leave an active request for the next drain iteration.
                    precondition(phase == .draining)
                    condition.unlock()
                    autoreleasepool { discardReadyProduct() }
                    retire(active.attempt)
                    continue
                }
                guard let request = pending, !closed else {
                    workerScheduled = false
                    condition.broadcast()
                    condition.unlock()
                    return
                }
                pending = nil
                active = request
                let cancellation = PlaybackPreparationCancellation()
                token = cancellation
                phase = .constructing
                condition.broadcast()
                condition.unlock()

                // No Product escapes this lexical/pool boundary except the sole ready slot.
                // Thus rejected locals and their source children are gone before retirement.
                let staged = autoreleasepool { buildAndStage(request, cancellation: cancellation) }
                if staged {
                    notify(.init(attempt: request.attempt, kind: .ready))
                } else {
                    retire(request.attempt)
                }
            }
        }

        @inline(never)
        func buildAndStage(_ request: Request, cancellation: PlaybackPreparationCancellation) -> Bool {
            let result = producer(request.key, request.attempt, cancellation)
            condition.lock()
            guard !closed, phase == .constructing, active?.attempt == request.attempt,
                  result != nil else {
                condition.unlock()
                withExtendedLifetime(result) {}
                return false
            }
            product = result
            phase = .ready
            condition.broadcast()
            condition.unlock()
            withExtendedLifetime(result) {}
            return true
        }

        @inline(never)
        func discardReadyProduct() {
            condition.lock()
            var discarded = product
            product = nil
            condition.unlock()
            // Never perform a last release under the owner gate or on its caller's executor.
            withExtendedLifetime(discarded) {}
            discarded = nil
        }

        func retire(_ attempt: PlaybackPreparationAttempt) {
            condition.lock()
            precondition(active?.attempt == attempt && product == nil)
            active = nil
            token = nil
            phase = .idle
            let nextCount = retiredCount.addingReportingOverflow(1)
            retiredCount = nextCount.overflow ? .max : nextCount.partialValue
            lastRetiredAttempt = attempt
            condition.broadcast()
            condition.unlock()
            notify(.init(attempt: attempt, kind: .retired))
        }
    }

    private let core: Core

    /// `workerQueue` is a target only; the owner always creates its own serial worker.
    /// `initialSerial` permits a bounded overflow test without issuing billions of intents.
    /// Notifications run synchronously outside the gate (ready/retired on the worker,
    /// claimed on its caller). Delayed delivery must enqueue only this scalar value;
    /// observers must not block the worker awaiting its own retirement.
    init(
        workerQueue: DispatchQueue? = nil, initialSerial: UInt64 = 0,
        producer: @escaping @Sendable (PlaybackPreparationKey, PlaybackPreparationAttempt, PlaybackPreparationCancellation) -> Product?,
        notify: @escaping @Sendable (PlaybackPreparationNotification) -> Void = { _ in }
    ) {
        core = Core(target: workerQueue, initialSerial: initialSerial, producer: producer, notify: notify)
    }

    deinit { core.stop(shutdown: true) }

    /// A genuinely new intent, including an equal-key restart, always revokes the old attempt.
    func offer(_ key: PlaybackPreparationKey) -> PlaybackPreparationAttempt? { core.offer(key) }

    /// Duplicate observation requires the exact ongoing attempt as well as its complete key.
    func observe(_ attempt: PlaybackPreparationAttempt, key: PlaybackPreparationKey) -> PlaybackPreparationAttempt? {
        core.observe(attempt, key: key)
    }

    /// One-shot ownership transfer; cancellation and claim linearize under the same gate.
    func claim(_ attempt: PlaybackPreparationAttempt, key: PlaybackPreparationKey) -> Product? {
        core.claim(attempt, key: key)
    }

    /// Revokes speculative interest; independently admitted products remain caller-owned.
    func stop() { core.stop(shutdown: false) }

    /// Permanently rejects offers and arranges worker-side disposal without blocking deinit.
    func shutdown() { core.stop(shutdown: true) }

    /// Waits on worker-owned condition state, never a MainActor notification. Not render-safe.
    /// Retired means no speculative ownership, including a successful transfer after claim;
    /// only a retired notification identifies worker-side rejection/disposal specifically.
    func wait(for attempt: PlaybackPreparationAttempt, timeout: TimeInterval = 5) -> WaitStatus {
        core.wait(for: attempt, timeout: timeout)
    }

    var snapshot: Snapshot { core.snapshot }

    /// Explicit Loop uses this same serial lane after revoking normal preparation.
    /// It must never perform work from a render callback or wait on its own queue.
    var productionQueue: DispatchQueue { core.queue }
}

/// A synchronous control-side source supply; queued requests retain only `key` and attempt.
struct RuntimeAdapterPlanPrewarmRequest: @unchecked Sendable {
    let generation: UInt64
    let song: PlaybackSong
    let sampleRate: Double
    let adapterPlanProfileRecorder: AdapterPlanProfileRecorder?
    let key: PlaybackPreparationKey
}

/// One observable result root; rejected plan/source aliases are cleared before retirement.
final class RuntimeAdapterPlanPrewarmResult: @unchecked Sendable {
    let generation: UInt64
    private(set) var plan: RuntimeCMixerAdapterEventPlan?
    let makeMS: Double?
    let completedAfterCancellation: Bool
    let adapterPlanProfileSession: AdapterPlanProfileSession?
    private(set) var sourceSong: PlaybackSong?
    private let receipt: (@Sendable (RuntimeAdapterPlanPreparationReceipt) -> Void)?
    private let key: PlaybackPreparationKey?
    private let attempt: PlaybackPreparationAttempt?
    private let eventStorageID: UInt?

    init(generation: UInt64, plan: RuntimeCMixerAdapterEventPlan?, makeMS: Double?,
         completedAfterCancellation: Bool, adapterPlanProfileSession: AdapterPlanProfileSession?,
         sourceSong: PlaybackSong? = nil, key: PlaybackPreparationKey? = nil,
         attempt: PlaybackPreparationAttempt? = nil,
         receipt: (@Sendable (RuntimeAdapterPlanPreparationReceipt) -> Void)? = nil) {
        self.generation = generation
        self.plan = plan
        self.makeMS = makeMS
        self.completedAfterCancellation = completedAfterCancellation
        self.adapterPlanProfileSession = adapterPlanProfileSession
        self.sourceSong = sourceSong
        self.key = key
        self.attempt = attempt
        self.receipt = receipt
        eventStorageID = plan.flatMap { $0.events.withUnsafeBufferPointer { $0.baseAddress.map { UInt(bitPattern: $0) } } }
        receipt?(.init(kind: .resultCreated, key: key, attempt: attempt, isMainThread: Thread.isMainThread, eventStorageID: eventStorageID))
    }

    deinit {
        // Admitted backend/cache aliases remain their consumers' responsibility. For a
        // rejected result, this clears its owned graph/source before B1 acknowledges it.
        plan = nil
        sourceSong = nil
        receipt?(.init(kind: .resultReleased, key: key, attempt: attempt, isMainThread: Thread.isMainThread, eventStorageID: eventStorageID))
    }
}

protocol RuntimeAdapterPlanPrewarmJob: AnyObject, Sendable {
    var generation: UInt64 { get }
    var key: PlaybackPreparationKey { get }
    var attempt: PlaybackPreparationAttempt { get }

    /// Cancellation is control-side; it never destroys a worker-owned result on its caller.
    func cancel()
    /// Joins the worker condition without requiring actor notification progress.
    func waitUntilReady() -> Bool
    /// Transfers the ready result once; nil means this attempt was revoked or already claimed.
    func waitForResult() -> RuntimeAdapterPlanPrewarmResult?
}

@MainActor
protocol RuntimeAdapterPlanPrewarmScheduling: AnyObject {
    func schedule(
        request: RuntimeAdapterPlanPrewarmRequest,
        completion: @escaping @Sendable (PlaybackPreparationNotification) -> Void
    ) -> RuntimeAdapterPlanPrewarmJob
}

/// Optional scalar probes and worker barriers exercise the actual production arbitration.
/// Construction uses full traversal bounds with a cold origin supplied by the request.
struct RuntimeAdapterPlanPreparationHooks: Sendable {
    var beforeSourceResolution: @Sendable (PlaybackPreparationKey, PlaybackPreparationAttempt) -> Void = { _, _ in }
    var beforeMake: @Sendable (PlaybackPreparationKey, PlaybackPreparationAttempt) -> Void = { _, _ in }
    var afterMake: @Sendable (PlaybackPreparationKey, PlaybackPreparationAttempt) -> Void = { _, _ in }
    var receipt: @Sendable (RuntimeAdapterPlanPreparationReceipt) -> Void = { _ in }
    var makePlan: @Sendable (PlaybackSong, Double, AdapterPlanProfileSession?, PlaybackPreparationKey, PlaybackPreparationCancellation) -> RuntimeCMixerAdapterEventPlan? = { song, rate, profile, key, cancellation in
        guard case let .cold(order, row) = key.origin,
              let origin = song.position(orderIndex: order, rowIndex: row),
              origin.orderIndex == order, origin.rowIndex == row else { return nil }
        return RuntimeCMixerAdapterEventPlan.make(song: song, sampleRate: rate, profileSession: profile,
            rowCaptureRetention: .runtimeFinalized, initialPosition: origin,
            isCancelled: { cancellation.isCancelled })
    }
}

struct RuntimeAdapterPlanPreparationReceipt: Sendable {
    enum Kind: Sendable { case sourceSupplied, sourceAcquired, sourceReleased, resultCreated, resultReleased,
                               constructorStarted, constructorFinished, ready, retired, claimed, waitStarted }
    let kind: Kind
    let key: PlaybackPreparationKey?
    let attempt: PlaybackPreparationAttempt?
    let isMainThread: Bool
    let eventStorageID: UInt?

    init(kind: Kind, key: PlaybackPreparationKey?, attempt: PlaybackPreparationAttempt?,
         isMainThread: Bool, eventStorageID: UInt? = nil) {
        self.kind = kind
        self.key = key
        self.attempt = attempt
        self.isMainThread = isMainThread
        self.eventStorageID = eventStorageID
    }
}

private enum RuntimeAdapterPlanCacheSource: String {
    case none
    case prewarm
    case syncFallback = "sync_fallback"
}

private enum RuntimeAdapterPlanPlayMode: String {
    case prewarmed
    case waited
    case syncFallback = "sync_fallback"
    case cachedReuse = "cached_reuse"
    case unavailable
}

private struct PendingEditablePatternLoopRefresh {
    let generation: UInt64
    let attempt: PlaybackPreparationAttempt
}

private struct IsolatedPatternLoopPlaybackContext {
    let patternIndex: Int
    let anchorOrderIndex: Int
}

private struct IsolatedPatternLoopPlaybackRestoreState {
    var sourceSong: PlaybackSong
    var runtimeAdapterEventPlan: RuntimeCMixerAdapterEventPlan
    var runtimeAdapterPlanCacheSource: RuntimeAdapterPlanCacheSource
    var runtimeAdapterPlanUseCount: Int
    var key: PlaybackPreparationKey?
}

/// One immutable revision lease. The broker and currently executing producer may alias it;
/// it is never captured by a pending request or a MainActor notification.
private final class RuntimeAdapterPlanPreparationSource: @unchecked Sendable {
    let generation: UInt64
    let key: PlaybackPreparationKey
    let sampleRate: Double
    let recorder: AdapterPlanProfileRecorder?
    private(set) var song: PlaybackSong?
    private let receipt: @Sendable (RuntimeAdapterPlanPreparationReceipt) -> Void

    init(_ request: RuntimeAdapterPlanPrewarmRequest, hooks: RuntimeAdapterPlanPreparationHooks) {
        generation = request.generation
        key = request.key
        sampleRate = request.sampleRate
        recorder = request.adapterPlanProfileRecorder
        song = request.song
        receipt = hooks.receipt
        receipt(.init(kind: .sourceSupplied, key: key, attempt: nil, isMainThread: Thread.isMainThread))
    }

    deinit {
        // Release this source alias before recording its disappearance; other actual
        // consumers (document, admitted graph or worker) keep their independent aliases.
        song = nil
        receipt(.init(kind: .sourceReleased, key: key, attempt: nil, isMainThread: Thread.isMainThread))
    }
}

/// A single authoritative supplied snapshot, separate from the owner's scalar mailbox.
private final class RuntimeAdapterPlanPreparationBroker: @unchecked Sendable {
    private let lock = NSLock()
    private var source: RuntimeAdapterPlanPreparationSource?
    private var completion: (@Sendable (PlaybackPreparationNotification) -> Void)?

    func supply(_ request: RuntimeAdapterPlanPrewarmRequest, hooks: RuntimeAdapterPlanPreparationHooks,
                completion: @escaping @Sendable (PlaybackPreparationNotification) -> Void) {
        lock.lock()
        var oldSource = source
        source = nil
        self.completion = completion
        lock.unlock()
        // End obsolete broker ownership before allocating the new wrapper. A producer
        // already using that snapshot has its own lease; a not-yet-started obsolete
        // attempt may now resolve nil and retire, independently of MainActor progress.
        withExtendedLifetime(oldSource) {}
        oldSource = nil
        let newSource = RuntimeAdapterPlanPreparationSource(request, hooks: hooks)
        lock.lock()
        source = newSource
        lock.unlock()
    }

    func resolve(_ key: PlaybackPreparationKey) -> RuntimeAdapterPlanPreparationSource? {
        lock.lock()
        defer { lock.unlock() }
        guard source?.key == key else { return nil }
        return source
    }

    func clear(matching key: PlaybackPreparationKey? = nil) {
        lock.lock()
        guard key == nil || source?.key == key else { lock.unlock(); return }
        let oldSource = source
        source = nil
        if key == nil { completion = nil }
        lock.unlock()
        withExtendedLifetime(oldSource) {}
    }

    func notify(_ notification: PlaybackPreparationNotification) {
        lock.lock()
        let callback = completion
        lock.unlock()
        // Production callback only enqueues the scalar; it must never await MainActor.
        callback?(notification)
    }
}

private final class DispatchQueueRuntimeAdapterPlanPrewarmJob: RuntimeAdapterPlanPrewarmJob, @unchecked Sendable {
    let generation: UInt64
    let key: PlaybackPreparationKey
    let attempt: PlaybackPreparationAttempt
    private let owner: PlaybackPreparationOwner<RuntimeAdapterPlanPrewarmResult>
    private let broker: RuntimeAdapterPlanPreparationBroker
    private let receipt: @Sendable (RuntimeAdapterPlanPreparationReceipt) -> Void

    init(generation: UInt64, key: PlaybackPreparationKey, attempt: PlaybackPreparationAttempt,
         owner: PlaybackPreparationOwner<RuntimeAdapterPlanPrewarmResult>,
         broker: RuntimeAdapterPlanPreparationBroker, hooks: RuntimeAdapterPlanPreparationHooks) {
        self.generation = generation
        self.key = key
        self.attempt = attempt
        self.owner = owner
        self.broker = broker
        receipt = hooks.receipt
    }

    func cancel() {
        // Offers and cancellation are serialized by the engine's MainActor control side.
        // An old job must not revoke a successor that has already become authoritative.
        if owner.observe(attempt, key: key) != nil {
            owner.stop()
            broker.clear(matching: key)
        }
    }

    func waitUntilReady() -> Bool {
        receipt(.init(kind: .waitStarted, key: key, attempt: attempt, isMainThread: Thread.isMainThread))
        while true {
            switch owner.wait(for: attempt) {
            case .ready: return true
            case .timedOut: continue
            case .retired, .invalid: return false
            }
        }
    }

    func waitForResult() -> RuntimeAdapterPlanPrewarmResult? {
        let result = owner.claim(attempt, key: key)
        if result != nil { broker.clear(matching: key) }
        return result
    }
}

/// The single production constructor for prewarm, compatible waits, fallback and refresh.
/// The fixed producer closes over the broker only, never the engine or an initial song.
@MainActor
protocol RuntimeUserLoopWorkerProviding: AnyObject {
    var userLoopWorkerQueue: DispatchQueue { get }
}

final class DispatchQueueRuntimeAdapterPlanPrewarmScheduler: RuntimeAdapterPlanPrewarmScheduling, RuntimeUserLoopWorkerProviding {
    private let broker: RuntimeAdapterPlanPreparationBroker
    private let owner: PlaybackPreparationOwner<RuntimeAdapterPlanPrewarmResult>
    private let hooks: RuntimeAdapterPlanPreparationHooks

    init(workerQueue: DispatchQueue? = nil, hooks: RuntimeAdapterPlanPreparationHooks = .init()) {
        let broker = RuntimeAdapterPlanPreparationBroker()
        self.broker = broker
        self.hooks = hooks
        owner = PlaybackPreparationOwner(workerQueue: workerQueue, producer: { key, attempt, cancellation in
            hooks.beforeSourceResolution(key, attempt)
            guard !cancellation.isCancelled, let source = broker.resolve(key), let song = source.song else { return nil }
            hooks.receipt(.init(kind: .sourceAcquired, key: key, attempt: attempt, isMainThread: Thread.isMainThread))
            let isRefresh = key.purpose == .editRefresh || key.purpose == .loopRefresh
            if isRefresh {
                // A generated refresh may transfer only after proving its immutable source
                // has the exact boundary scope. Pattern loop ranges always begin at row 0;
                // source and key cannot change after this worker-side admission check.
                guard let scope = key.loopScope,
                      let anchor = song.position(orderIndex: scope.order, rowIndex: 0),
                      anchor.patternIndex == scope.pattern,
                      let range = song.patternLoopRange(containing: anchor),
                      range.orderIndex == scope.order, range.patternIndex == scope.pattern else {
                    broker.clear(matching: key)
                    return nil
                }
            }
            hooks.beforeMake(key, attempt)
            guard !cancellation.isCancelled else { return nil }
            let profileSession = source.recorder?.beginLifecycle("prewarm")
            hooks.receipt(.init(kind: .constructorStarted, key: key, attempt: attempt, isMainThread: Thread.isMainThread))
            let start = DispatchTime.now().uptimeNanoseconds
            let plan = hooks.makePlan(song, source.sampleRate, profileSession, key, cancellation)
            let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            hooks.receipt(.init(kind: .constructorFinished, key: key, attempt: attempt, isMainThread: Thread.isMainThread))
            hooks.afterMake(key, attempt)
            if isRefresh, plan?.generated != true {
                // An unavailable refresh has no boundary consumer. Reject it here so its
                // plan/source aliases leave this worker scope before B1 acknowledges exit.
                broker.clear(matching: key)
                return nil
            }
            return RuntimeAdapterPlanPrewarmResult(
                generation: source.generation, plan: plan, makeMS: elapsedMS,
                completedAfterCancellation: cancellation.isCancelled,
                adapterPlanProfileSession: profileSession,
                sourceSong: isRefresh ? song : nil,
                key: key, attempt: attempt, receipt: hooks.receipt
            )
        }, notify: { notification in
            let kind: RuntimeAdapterPlanPreparationReceipt.Kind
            switch notification.kind {
            case .ready: kind = .ready
            case .retired: kind = .retired
            case .claimed: kind = .claimed
            }
            hooks.receipt(.init(kind: kind, key: nil, attempt: notification.attempt, isMainThread: Thread.isMainThread))
            broker.notify(notification)
        })
    }

    deinit {
        owner.shutdown()
        broker.clear()
    }

    var snapshot: PlaybackPreparationOwner<RuntimeAdapterPlanPrewarmResult>.Snapshot { owner.snapshot }
    var userLoopWorkerQueue: DispatchQueue { owner.productionQueue }

    func schedule(
        request: RuntimeAdapterPlanPrewarmRequest,
        completion: @escaping @Sendable (PlaybackPreparationNotification) -> Void
    ) -> RuntimeAdapterPlanPrewarmJob {
        broker.supply(request, hooks: hooks, completion: completion)
        guard let attempt = owner.offer(request.key) else { preconditionFailure("A live scheduler cannot be shut down") }
        return DispatchQueueRuntimeAdapterPlanPrewarmJob(
            generation: request.generation, key: request.key, attempt: attempt,
            owner: owner, broker: broker, hooks: hooks
        )
    }
}

@MainActor
final class PlaybackEngine: PlaybackTransport {
    private static let runtimeCMixerSongEndTransportStopGraceSeconds: TimeInterval = 0.5

    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Playback")
    private let audioEngine: PlaybackAudioOutput

    /// Diagnostic polling is scoped to the admitted transport, never a later Play.
    var timingTransportEpoch: UInt64 { preparationTransportEpoch }

    func firstHostOutputObservation() -> RuntimeCMixerFirstHostOutputObservation? {
        (audioEngine as? RuntimeCMixerAudioEngine)?.firstHostOutputObservation()
    }
    private let traceWriter: PlaybackTraceWriting
    private let runtimeCMixerTraceWriter: RuntimeCMixerTraceWriting
    private let playbackTimingRecorder: PlaybackTimingTraceRecorder?
    private let adapterPlanProfileRecorder: AdapterPlanProfileRecorder?
    private let runtimeAdapterPlanPrewarmScheduler: RuntimeAdapterPlanPrewarmScheduling
    private let runtimeCMixerFollowPublicationDisabled: Bool
    private let runtimeCMixerSongEndTailPolicy: RuntimeCMixerSongEndTailPolicy
    private let debugStopAfterSeconds: TimeInterval?
    private let startsRealtimeTimer: Bool

    private(set) var state: PlaybackState = .stopped
    private(set) var song: PlaybackSong?
    private(set) var currentPosition: PlaybackPosition?
    private(set) var currentPublishedFollowPosition: PlaybackFollowPosition?
    private(set) var timing = PlaybackTiming.xmDefault
    private var tickState = PlaybackTickState()
    private var timer: Timer?
    private var runtimeCMixerSongEndStopTimer: Timer?
    private var runtimeCMixerFollowTimer: Timer?
    private var runtimeCMixerSongEndStopPending = false
    private var pendingPositionCommand: PlaybackPositionCommand?
    private var runtimeAdapterEventPlan = RuntimeCMixerAdapterEventPlan.unavailable()
    private var runtimeAdapterPlanGeneration: UInt64 = 0
    private let preparationInstanceID = UUID()
    private var preparationDocumentID = UUID()
    private var preparationTransportEpoch: UInt64 = 0
    private var preparationControlIntent: UInt64 = 0
    private var preparationSourceSerial: UInt64 = 0
    private var currentSourceGeneration: UInt64 = 0
    private var runtimeAdapterPlanKey: PlaybackPreparationKey?
    private var userLoopPreparationSession: RuntimeLoopPlanningSession?
    private var userLoopPreparationKey: PlaybackPreparationKey?
    private var intendsExecutedUserLoop = false
    private var lastAdmittedUserLoopRefresh: UInt64 = 0
    private var desiredUserLoopRefresh: (serial: UInt64, song: PlaybackSong, generation: UInt64)?
    private var runtimeAdapterPlanPrewarmJob: RuntimeAdapterPlanPrewarmJob?
    private var runtimeAdapterPlanPrewarmTimingSession: PlaybackTimingTraceSession?
    private var runtimeAdapterPlanCacheSource = RuntimeAdapterPlanCacheSource.none
    private var runtimeAdapterPlanUseCount = 0
    private var editablePatternLoopRefreshGeneration: UInt64 = 0
    private var editablePatternLoopRefreshJob: RuntimeAdapterPlanPrewarmJob?
    private var pendingEditablePatternLoopRefresh: PendingEditablePatternLoopRefresh?
    private var isolatedPatternLoopPlaybackContext: IsolatedPatternLoopPlaybackContext?
    private var isolatedPatternLoopPlaybackRestoreState: IsolatedPatternLoopPlaybackRestoreState?
    private var channelStates = [Int: PlaybackChannelState]()
    private var globalState = PlaybackGlobalState()
    private var rowDelayDurationsRemaining = 0
    private var lastVoiceRequests = [Int: AudioVoiceRequest]()
    private var delayedVoiceRequests = [Int: AudioVoiceRequest]()
    private var traceTickIndex: UInt64 = 0
    private var runtimeNoteTriggerEventCount: UInt64 = 0
    private var activeDebugStartTraceContext: PlaybackDebugStartTraceContext?
    private var activePatternLoopRange: PlaybackPatternLoopRange?
    private struct PendingPlay {
        let id: UUID
        let completion: @MainActor (Bool) -> Void
    }
    private var pendingPlay: PendingPlay?
    var isPreparingPlayback: Bool { pendingPlay != nil }

    var positionDidChange: ((PlaybackPosition) -> Void)?
    var playbackDidStop: (() -> Void)?
    var playbackDidFail: ((RuntimeCMixerAdmissionFault) -> Void)?
    var userLoopPlaybackDidFail: ((RuntimeUserLoopPlaybackFailure) -> Void)?
    var runtimeAdapterPlanDidUpdate: (() -> Void)?
    var playbackPreparationDidChange: (() -> Void)?

    var runtimeAdapterPlanDurationSeconds: TimeInterval? {
        runtimeAdapterEventPlan.plannedSongEndSeconds
    }

    var isPatternLoopPlaybackActive: Bool {
        state.isPlaying && activePatternLoopRange != nil
    }

#if DEBUG
    var isRuntimeCMixerSongEndStopPendingForTesting: Bool {
        runtimeCMixerSongEndStopPending
    }

    var hasPendingEditablePatternLoopRefreshForTesting: Bool {
        editablePatternLoopRefreshJob != nil || pendingEditablePatternLoopRefresh != nil
    }

    var runtimePreparationJobForTesting: RuntimeAdapterPlanPrewarmJob? { runtimeAdapterPlanPrewarmJob }

    var hasReadyEditablePatternLoopRefreshForTesting: Bool { pendingEditablePatternLoopRefresh != nil }

    var preparationWillAdmitForTesting: ((PlaybackPreparationAttempt) -> Void)?

    func deliverPreparationNotificationForTesting(_ notification: PlaybackPreparationNotification) {
        completeRuntimeAdapterPlanPrewarm(notification)
        completeEditablePatternLoopRefresh(notification)
    }
#endif

    init(
        audioEngine: PlaybackAudioOutput? = nil,
        traceWriter: PlaybackTraceWriting = PlaybackTraceConfiguration.makeWriter(),
        runtimeCMixerTraceWriter: RuntimeCMixerTraceWriting = RuntimeCMixerTraceConfiguration.makeWriter(),
        startsRealtimeTimer: Bool = true,
        playbackTimingRecorder: PlaybackTimingTraceRecorder? = nil,
        adapterPlanProfileRecorder: AdapterPlanProfileRecorder? = nil,
        runtimeAdapterPlanPrewarmScheduler: RuntimeAdapterPlanPrewarmScheduling = DispatchQueueRuntimeAdapterPlanPrewarmScheduler(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.runtimeCMixerTraceWriter = runtimeCMixerTraceWriter
        self.startsRealtimeTimer = startsRealtimeTimer
        self.playbackTimingRecorder = playbackTimingRecorder
        self.adapterPlanProfileRecorder = adapterPlanProfileRecorder
        self.runtimeAdapterPlanPrewarmScheduler = runtimeAdapterPlanPrewarmScheduler
        debugStopAfterSeconds = PlaybackDebugLaunchConfiguration.parse(environment: environment).stopAfterSeconds
        let resolvedAudioEngine = audioEngine ?? PlaybackAudioOutputFactory.make(
            environment: environment,
            runtimeCMixerTraceWriter: runtimeCMixerTraceWriter
        )
        self.audioEngine = resolvedAudioEngine
        self.traceWriter = traceWriter
        runtimeCMixerFollowPublicationDisabled =
            ((resolvedAudioEngine as? PlaybackAudioBackendProviding)?.runtimeAudioBackend.usesRuntimeCMixer ?? false) &&
            RuntimeCMixerDiagnosticEnvironment.flagEnabled(
                RuntimeCMixerDiagnosticEnvironment.disableFollowPublicationEnvironmentKey,
                environment: environment
            )
        runtimeCMixerSongEndTailPolicy =
            ((resolvedAudioEngine as? PlaybackAudioBackendProviding)?.runtimeAudioBackend.usesRuntimeCMixer ?? false)
                ? RuntimeCMixerSongEndTailPolicy.resolve(environment: environment)
                : .defaultPolicy
    }

    deinit {
        runtimeAdapterPlanPrewarmJob?.cancel()
        editablePatternLoopRefreshJob?.cancel()
    }

    private var preparedEditableSourceIdentity: UUID?
    private var intendedColdPosition: PlaybackPosition?

    /// Resolves a known launch origin before speculative construction begins.
    func startContext(for request: PlaybackDebugStartRequest?, in song: PlaybackSong?) -> PlaybackStartContext? {
        guard let request, let song, let resolved = resolveDebugStart(request, in: song) else { return nil }
        return .init(moduleTitle: song.title, songPosition: resolved.position.orderIndex,
            patternIndex: resolved.position.patternIndex, row: resolved.position.rowIndex)
    }

    /// Reuses an unchanged editable audio value after focus/navigation-only revisions.
    /// A different document identity always creates a fresh source generation.
    func loadEditableSnapshot(song: PlaybackSong, identity: UUID?, startContext: PlaybackStartContext?,
                              loopEnabled: Bool, timingSession: PlaybackTimingTraceSession?) {
        if let identity, preparedEditableSourceIdentity == identity, self.song == song {
            prepare(from: startContext, loopEnabled: loopEnabled)
            return
        }
        load(song: song, startContext: startContext, loopEnabled: loopEnabled, timingSession: timingSession)
        preparedEditableSourceIdentity = identity
    }

    func load(song: PlaybackSong?, startContext: PlaybackStartContext? = nil, loopEnabled: Bool = false, timingSession: PlaybackTimingTraceSession? = nil) {
        preparedEditableSourceIdentity = nil
        runtimeAdapterPlanGeneration &+= 1
        cancelRuntimeAdapterPlanPrewarm(reason: "load_invalidation")
        cancelEditablePatternLoopRefresh(reason: "load_invalidation")
        let wasPlaying = state.isPlaying
        let stopStart = timingSession?.beginPhase()
        stop(notify: false, resetAudio: true)
        timingSession?.recordPhase(
            "playback_engine_stop_for_load",
            startedAt: stopStart,
            fields: [PlaybackTimingTraceField("was_playing_before_load", wasPlaying)]
        )
        let stateResetStart = timingSession?.beginPhase()
        self.song = song
        preparationDocumentID = UUID()
        currentSourceGeneration = mintSourceGeneration()
        timing = song?.initialTiming ?? .xmDefault
        currentPosition = startContext == nil ? song?.startPosition : song.flatMap { playbackStartPosition(from: startContext, in: $0) ?? $0.startPosition }
        intendedColdPosition = currentPosition
        intendsExecutedUserLoop = loopEnabled && supportsExecutedUserLoop
        if loopEnabled && !intendsExecutedUserLoop { intendedColdPosition = song?.startPosition }
        currentPublishedFollowPosition = currentPosition.map { PlaybackFollowPosition.timer(position: $0, tickInRow: 0) }
        pendingPositionCommand = nil
        channelStates.removeAll()
        globalState = PlaybackGlobalState()
        rowDelayDurationsRemaining = 0
        lastVoiceRequests.removeAll()
        delayedVoiceRequests.removeAll()
        traceTickIndex = 0
        runtimeNoteTriggerEventCount = 0
        activeDebugStartTraceContext = nil
        timingSession?.recordPhase(
            "playback_engine_load_state_reset",
            startedAt: stateResetStart,
            fields: PlaybackTimingTraceFields.playbackSong(song)
        )
        invalidateRuntimeAdapterEventPlan(timingSession: timingSession)
        if intendsExecutedUserLoop, let song, let position = currentPosition {
            _ = scheduleUserLoopPreparation(song: song, position: position)
        } else { scheduleRuntimeAdapterPlanPrewarmIfNeeded(for: song, timingSession: timingSession) }
        cancelRuntimeCMixerSongEndStop()
        logger.debug("Playback song loaded. hadActivePlayback=\(wasPlaying, privacy: .public) hasSong=\((song != nil), privacy: .public)")
    }

    func configureTiming(_ timing: PlaybackTiming) {
        self.timing = timing
        if state.isPlaying {
            restartTimer()
        }
    }

    func requestEditablePatternLoopRefresh(song refreshedSong: PlaybackSong) {
        guard state.isPlaying,
              activePatternLoopRange != nil,
              audioEngine as? RuntimeCMixerAdapterEventConsuming != nil else {
            return
        }
        let playbackRefreshSong: PlaybackSong
        if let isolatedPatternLoopPlaybackContext {
            guard let isolatedSong = refreshedSong.isolatedPatternLoopSong(
                patternIndex: isolatedPatternLoopPlaybackContext.patternIndex,
                anchorOrderIndex: isolatedPatternLoopPlaybackContext.anchorOrderIndex
            ) else {
                return
            }
            playbackRefreshSong = isolatedSong
            isolatedPatternLoopPlaybackRestoreState?.sourceSong = refreshedSong
            isolatedPatternLoopPlaybackRestoreState?.runtimeAdapterEventPlan = .unavailable(sampleRate: audioEngine.audioBufferSampleRate)
            isolatedPatternLoopPlaybackRestoreState?.runtimeAdapterPlanCacheSource = .none
            isolatedPatternLoopPlaybackRestoreState?.runtimeAdapterPlanUseCount = 0
            isolatedPatternLoopPlaybackRestoreState?.key = nil
        } else {
            playbackRefreshSong = refreshedSong
        }
        if let native = audioEngine as? RuntimeCMixerUserLoopConsuming, native.hasRuntimeUserLoop,
           let session = userLoopPreparationSession {
            let original = session.scope
            let generation = mintSourceGeneration()
            let scope = RuntimeLoopNativeScope(documentHigh: original.documentHigh, documentLow: original.documentLow,
                sourceGeneration: generation, transportEpoch: original.transportEpoch,
                sampleRateBits: audioEngine.audioBufferSampleRate.bitPattern, semanticVersion: original.semanticVersion,
                linearFrequencyMode: playbackRefreshSong.usesLinearFrequencyTable,
                order: original.order, pattern: original.pattern, firstRow: original.firstRow, lastRow: original.lastRow)
            if let serial = session.requestEditableRefresh(song: playbackRefreshSong, scope: scope) {
                desiredUserLoopRefresh = (serial, playbackRefreshSong, generation)
            }
            return
        }
        cancelRuntimeAdapterPlanPrewarm(reason: "edit_refresh")
        cancelEditablePatternLoopRefresh(reason: "superseded_refresh")
        let generation = editablePatternLoopRefreshGeneration
        guard let key = preparationKey(for: playbackRefreshSong, sourceGeneration: mintSourceGeneration(), purpose: .editRefresh) else { return }
        let request = RuntimeAdapterPlanPrewarmRequest(
            generation: generation, song: playbackRefreshSong,
            sampleRate: audioEngine.audioBufferSampleRate,
            adapterPlanProfileRecorder: nil, key: key
        )
        editablePatternLoopRefreshJob = runtimeAdapterPlanPrewarmScheduler.schedule(request: request) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.completeEditablePatternLoopRefresh(notification)
            }
        }
    }

    func play(from context: PlaybackStartContext?) {
        let timingSession = playbackTimingRecorder?.beginLifecycle("play")
        play(from: context, debugStart: nil, loopEnabled: false, action: .play, timingSession: timingSession)
        finishOwnedPlayTimingSession(timingSession, context: context)
    }

    func play(from context: PlaybackStartContext?, timingSession: PlaybackTimingTraceSession?) {
        play(from: context, debugStart: nil, loopEnabled: false, action: .play, timingSession: timingSession)
    }

    func play(from context: PlaybackStartContext?, loopEnabled: Bool, timingSession: PlaybackTimingTraceSession?) {
        play(from: context, debugStart: nil, loopEnabled: loopEnabled, action: .play, timingSession: timingSession)
    }

    /// Product Play prepares a fresh normal origin without joining a constructor
    /// on Main. A compatible admitted full plan and explicit Loop keep their paths.
    func requestPlay(from context: PlaybackStartContext?, loopEnabled: Bool,
                     timingSession: PlaybackTimingTraceSession?,
                     admissionIsCurrent: @escaping @MainActor () -> Bool = { true },
                     completion: @escaping @MainActor (Bool) -> Void) {
        guard !state.isPlaying else { completion(false); return }
        if let previous = pendingPlay {
            preparationControlIntent += 1
            let cancellationIntent = preparationControlIntent
            cancelUserLoopPreparation()
            finishPendingPlay(previous.id, started: false)
            guard preparationControlIntent == cancellationIntent, !state.isPlaying else {
                completion(false); return
            }
        }
        if (audioEngine as? RuntimeCMixerUserLoopConsuming)?.hasRuntimeUserLoop == true {
            // A position observer can replace Play after the old native graph is
            // installed but before its transport state becomes playing.
            let replacementIntent = preparationControlIntent + 1
            stop(notify: false, resetAudio: false, reason: "loop_start_superseded")
            guard preparationControlIntent == replacementIntent, !state.isPlaying,
                  (audioEngine as? RuntimeCMixerUserLoopConsuming)?.hasRuntimeUserLoop != true else {
                completion(false); return
            }
        }
        let admissionIntent = preparationControlIntent
        let admissionEpoch = preparationTransportEpoch
        let admissionGeneration = currentSourceGeneration
        guard let song, let position = playbackStartPosition(from: context, in: song) ?? song.startPosition,
              admissionIsCurrent(), preparationControlIntent == admissionIntent,
              preparationTransportEpoch == admissionEpoch,
              currentSourceGeneration == admissionGeneration,
              pendingPlay == nil, !state.isPlaying else { completion(false); return }
        let compatibleFullPlan = runtimeAdapterEventPlan.generated &&
            !runtimeAdapterEventPlan.requiresAuthoredCycleContinuation &&
            runtimeAdapterPlanKey?.sourceGeneration == currentSourceGeneration &&
            runtimeAdapterPlanKey?.origin == .cold(order: position.orderIndex, row: position.rowIndex) &&
            runtimeAdapterPlanKey?.sampleRateBits == audioEngine.audioBufferSampleRate.bitPattern &&
            runtimeAdapterPlanKey?.frequencyMode == (song.usesLinearFrequencyTable ? .linear : .amiga)
        if loopEnabled || !supportsExecutedUserLoop || compatibleFullPlan {
            play(from: context, loopEnabled: loopEnabled, timingSession: timingSession)
            completion(state.isPlaying)
            return
        }
        intendsExecutedUserLoop = false
        updatePreparationOrigin(position, timingSession: timingSession)
        preparationControlIntent += 1
        let intent = preparationControlIntent, epoch = preparationTransportEpoch
        let generation = currentSourceGeneration, requestID = UUID()
        pendingPlay = PendingPlay(id: requestID, completion: completion)
        let waitStart = timingSession?.beginPhase()
        let session = scheduleUserLoopPreparation(song: song, position: position, transportKind: .finiteSong,
            onInitialPreparation: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.pendingPlay?.id == requestID else { return }
                    guard self.preparationControlIntent == intent, self.preparationTransportEpoch == epoch,
                          self.currentSourceGeneration == generation, !self.state.isPlaying,
                          case let .ready(preparation) = result,
                          let session = self.userLoopPreparationSession,
                          session.scope == preparation.scope, session.channel === preparation.channel,
                          !session.isCancelled else {
                        self.finishPendingPlay(requestID, started: false)
                        return
                    }
                    guard admissionIsCurrent(), self.pendingPlay?.id == requestID,
                          self.preparationControlIntent == intent, self.preparationTransportEpoch == epoch,
                          self.currentSourceGeneration == generation, !self.state.isPlaying,
                          self.userLoopPreparationSession === session, !session.isCancelled else {
                        self.finishPendingPlay(requestID, started: false)
                        return
                    }
                    timingSession?.recordPhase("normal_continuation_preparation", startedAt: waitStart)
                    self.play(from: context, debugStart: nil, loopEnabled: false, action: .play,
                        timingSession: timingSession, preparedContinuation: (session, preparation))
                    let started = self.state.isPlaying && self.preparationTransportEpoch == epoch &&
                        self.currentSourceGeneration == generation && self.userLoopPreparationSession === session
                    self.finishPendingPlay(requestID, started: started)
                }
            })
        guard session != nil else { finishPendingPlay(requestID, started: false); return }
        playbackPreparationDidChange?()
    }

    private func finishPendingPlay(_ id: UUID, started: Bool) {
        guard let pendingPlay, pendingPlay.id == id else { return }
        self.pendingPlay = nil
        if !started, userLoopPreparationSession?.scope.transportKind == .finiteSong {
            cancelUserLoopPreparation()
        }
        playbackPreparationDidChange?()
        pendingPlay.completion(started)
    }

    func playCurrentPatternLoop(from context: PlaybackStartContext?, timingSession: PlaybackTimingTraceSession?) {
        guard !state.isPlaying else {
            timingSession?.recordPhase(
                "playback_engine_play_current_pattern_ignored_already_playing",
                startedAt: nil,
                fields: [PlaybackTimingTraceField("is_playing_before", true)]
            )
            logger.debug("Ignoring Play Current Pattern request because playback is already active")
            return
        }
        guard audioEngine as? RuntimeCMixerAdapterEventConsuming != nil else {
            timingSession?.recordPhase(
                "playback_engine_play_current_pattern_unavailable",
                startedAt: nil,
                fields: [PlaybackTimingTraceField("requires_runtime_adapter_event_plan", true)]
            )
            logger.error("Unable to start Play Current Pattern without runtime adapter event consumption")
            return
        }
        guard let sourceSong = song,
              let context,
              let isolatedSong = sourceSong.isolatedPatternLoopSong(
                  patternIndex: context.patternIndex,
                  anchorOrderIndex: context.songPosition
              ) else {
            timingSession?.recordPhase(
                "playback_engine_play_current_pattern_no_pattern",
                startedAt: nil,
                fields: [
                    PlaybackTimingTraceField("has_song", song != nil),
                    PlaybackTimingTraceField("pattern_index", context?.patternIndex ?? -1),
                ]
            )
            return
        }
        let loopContext = PlaybackStartContext(
            moduleTitle: context.moduleTitle,
            songPosition: context.songPosition,
            patternIndex: context.patternIndex,
            row: 0
        )

        isolatedPatternLoopPlaybackRestoreState = IsolatedPatternLoopPlaybackRestoreState(
            sourceSong: sourceSong,
            runtimeAdapterEventPlan: .unavailable(sampleRate: audioEngine.audioBufferSampleRate),
            runtimeAdapterPlanCacheSource: .none,
            runtimeAdapterPlanUseCount: 0,
            key: runtimeAdapterPlanKey
        )
        isolatedPatternLoopPlaybackContext = IsolatedPatternLoopPlaybackContext(
            patternIndex: loopContext.patternIndex,
            anchorOrderIndex: loopContext.songPosition
        )
        cancelRuntimeAdapterPlanPrewarm(reason: "play_current_pattern_loop")
        song = isolatedSong
        currentSourceGeneration = mintSourceGeneration()
        invalidateRuntimeAdapterEventPlan(timingSession: timingSession)
        play(from: loopContext, debugStart: nil, loopEnabled: true, action: .playCurrentPattern, timingSession: timingSession)
        if !state.isPlaying {
            restoreIsolatedPatternLoopSourceIfNeeded(configureAudioPlan: true)
        }
    }

    func play(from context: PlaybackStartContext?, debugStart: PlaybackDebugStartRequest?) {
        let timingSession = playbackTimingRecorder?.beginLifecycle("play")
        play(from: context, debugStart: debugStart, loopEnabled: false, action: .play, timingSession: timingSession)
        finishOwnedPlayTimingSession(timingSession, context: context)
    }

    func play(
        from context: PlaybackStartContext?,
        debugStart: PlaybackDebugStartRequest?,
        timingSession: PlaybackTimingTraceSession?
    ) {
        play(from: context, debugStart: debugStart, loopEnabled: false, action: .play, timingSession: timingSession)
    }

    private func play(
        from context: PlaybackStartContext?,
        debugStart: PlaybackDebugStartRequest?,
        loopEnabled: Bool,
        action: PlaybackTransportAction,
        timingSession: PlaybackTimingTraceSession?,
        preparedContinuation: (RuntimeLoopPlanningSession, RuntimeLoopPlanningSession.Preparation)? = nil
    ) {
        guard !state.isPlaying else {
            timingSession?.recordPhase(
                "playback_engine_play_ignored_already_playing",
                startedAt: nil,
                fields: [PlaybackTimingTraceField("is_playing_before", true)]
            )
            logger.debug("Ignoring play request because playback is already active")
            return
        }
        if (audioEngine as? RuntimeCMixerUserLoopConsuming)?.hasRuntimeUserLoop == true {
            // A synchronous observer may replace a start before transport publishes
            // playing. Quiesce that installed generation before creating the new one.
            let replacementIntent = preparationControlIntent + 1
            stop(notify: false, resetAudio: false, reason: "loop_start_superseded")
            guard preparationControlIntent == replacementIntent, !state.isPlaying else { return }
        }
        guard let song else {
            let stopStart = timingSession?.beginPhase()
            stop()
            timingSession?.recordPhase(
                "playback_engine_play_no_song_stop",
                startedAt: stopStart,
                fields: [PlaybackTimingTraceField("has_song", false)]
            )
            return
        }
        let resolvedDebugStart = debugStart.flatMap { resolveDebugStart($0, in: song) }
        let selectedPosition = resolvedDebugStart?.position ?? playbackStartPosition(from: context, in: song) ?? song.startPosition
        let executedLoop = loopEnabled && supportsExecutedUserLoop
        intendsExecutedUserLoop = executedLoop
        updatePreparationOrigin(executedLoop ? selectedPosition : loopEnabled ? song.startPosition : selectedPosition,
            timingSession: timingSession)
        preparationControlIntent += 1
        let playAdmissionIntent = preparationControlIntent
        let playAdmissionEpoch = preparationTransportEpoch
        let preparedLoop: (RuntimeLoopPlanningSession, RuntimeLoopPlanningSession.Preparation)?
        if let preparedContinuation {
            guard preparedContinuation.0 === userLoopPreparationSession,
                  preparedContinuation.1.scope.transportKind == .finiteSong,
                  !preparedContinuation.0.isCancelled else { return }
            preparedLoop = preparedContinuation
        } else if executedLoop {
            guard let selectedPosition,
                  let session = scheduleUserLoopPreparation(song: song, position: selectedPosition),
                  let preparation = awaitUserLoopPreparation(session, epoch: playAdmissionEpoch, intent: playAdmissionIntent),
                  preparationTransportEpoch == playAdmissionEpoch, preparationControlIntent == playAdmissionIntent else { return }
            preparedLoop = (session, preparation)
        } else {
            cancelUserLoopPreparation()
            guard prepareRuntimeAdapterEventPlanIfNeeded(for: song, timingSession: timingSession),
                  preparationTransportEpoch == playAdmissionEpoch,
                  preparationControlIntent == playAdmissionIntent else {
                logger.error("Unable to prepare runtime adapter event plan; playback start aborted")
                return
            }
            if runtimeAdapterEventPlan.requiresAuthoredCycleContinuation, supportsExecutedUserLoop {
                guard let selectedPosition,
                      let session = scheduleUserLoopPreparation(song: song, position: selectedPosition, transportKind: .finiteSong),
                      let preparation = awaitUserLoopPreparation(session, epoch: playAdmissionEpoch, intent: playAdmissionIntent),
                      preparationTransportEpoch == playAdmissionEpoch, preparationControlIntent == playAdmissionIntent else { return }
                preparedLoop = (session, preparation)
            } else { preparedLoop = nil }
        }
        let startPositionStart = timingSession?.beginPhase()
        let positionBeforePlay = currentPosition
        currentPosition = selectedPosition
        timingSession?.recordPhase(
            "playback_engine_start_position_resolution",
            startedAt: startPositionStart,
            fields: PlaybackTimingTraceFields.playbackPosition(currentPosition)
        )

        let resetStart = timingSession?.beginPhase()
        let resetsColdTiming = resolvedDebugStart != nil || audioEngine is RuntimeCMixerAdapterEventConsuming
        resetRuntimeState(resetTiming: resetsColdTiming)
        activePatternLoopRange = loopEnabled
            ? currentPosition.flatMap { song.patternLoopRange(containing: $0) }
            : nil
        if let (session, preparation) = preparedLoop {
            guard (audioEngine as? RuntimeCMixerUserLoopConsuming)?.configureRuntimeUserLoop(session, preparation: preparation) == true,
                  preparationTransportEpoch == playAdmissionEpoch, preparationControlIntent == playAdmissionIntent else { return }
        }
        timingSession?.recordPhase(
            "playback_engine_transient_runtime_state_reset",
            startedAt: resetStart,
            fields: [
                PlaybackTimingTraceField("reset_timing", resetsColdTiming),
                PlaybackTimingTraceField("pattern_loop_enabled_for_play", activePatternLoopRange != nil),
                PlaybackTimingTraceField("pattern_loop_order", activePatternLoopRange?.orderIndex ?? -1),
                PlaybackTimingTraceField("pattern_loop_pattern", activePatternLoopRange?.patternIndex ?? -1),
            ]
        )

        activeDebugStartTraceContext = resolvedDebugStart.map {
            PlaybackDebugStartTraceContext(request: $0.request, position: $0.position, actualTickInRow: $0.actualTickInRow)
        }
        if let currentPosition {
            let enterStart = timingSession?.beginPhase()
            recordRuntimeTransportAction(
                action,
                positionBefore: positionBeforePlay,
                positionAfter: currentPosition,
                tickInRowBefore: 0,
                reason: "transport_play"
            )
            enter(position: currentPosition, previousPosition: nil, timingSession: timingSession)
            guard preparationTransportEpoch == playAdmissionEpoch,
                  preparationControlIntent == playAdmissionIntent else { return }
            applyDebugStartTickIfNeeded(resolvedDebugStart?.actualTickInRow, at: currentPosition)
            timingSession?.recordPhase(
                "playback_engine_enter_selected_playback_position",
                startedAt: enterStart,
                fields: PlaybackTimingTraceFields.playbackPosition(currentPosition)
            )
        }
        let restartTimerStart = timingSession?.beginPhase()
        restartTimer()
        timingSession?.recordPhase(
            "playback_engine_restart_timer",
            startedAt: restartTimerStart,
            fields: [PlaybackTimingTraceField("starts_realtime_timer", startsRealtimeTimer)]
        )

        let transportStateStart = timingSession?.beginPhase()
        apply(action: action, nextState: PlaybackState(mode: .playing, context: context))
        timingSession?.recordPhase("playback_engine_apply_transport_state", startedAt: transportStateStart)

        guard !serviceRuntimeCMixerAdmissionFailure() else { return }

        let songEndStopStart = timingSession?.beginPhase()
        scheduleRuntimeCMixerSongEndStopIfNeeded()
        timingSession?.recordPhase("playback_engine_schedule_runtime_song_end_stop", startedAt: songEndStopStart)
    }

    @discardableResult
    func seek(
        to request: PlaybackDebugStartRequest,
        autoplay: Bool? = nil,
        timingSession: PlaybackTimingTraceSession? = nil
    ) -> PlaybackPosition? {
        adoptUserLoopRefresh(from: userLoopPreparationSession)
        guard var song = self.song,
              var resolvedStart = resolveDebugStart(request, in: song) else {
            return nil
        }
        let retiringUserLoopSession = userLoopPreparationSession
        let shouldPlay = autoplay ?? state.isPlaying
        let executedLoop = intendsExecutedUserLoop && supportsExecutedUserLoop
        if executedLoop {
            preparationTransportEpoch += 1
            cancelUserLoopPreparation()
        }
        timer?.invalidate()
        timer = nil
        cancelRuntimeCMixerFollowTimer()
        cancelRuntimeCMixerSongEndStop()
        let quiescenceIntent = preparationControlIntent
        stopAllAudio(context: runtimeTraceContext(at: currentPosition, tickInRow: tickState.tickInRow, channelIndex: nil), reason: "debug_seek")
        guard preparationControlIntent == quiescenceIntent else { return currentPosition }
        adoptUserLoopRefresh(from: retiringUserLoopSession)
        if let admitted = self.song, let selected = resolveDebugStart(request, in: admitted) {
            song = admitted; resolvedStart = selected
        }
        currentPosition = resolvedStart.position
        resetRuntimeState(resetTiming: true)
        activeDebugStartTraceContext = shouldPlay
            ? PlaybackDebugStartTraceContext(
                request: resolvedStart.request,
                position: resolvedStart.position,
                actualTickInRow: resolvedStart.actualTickInRow
            )
            : nil

        updatePreparationOrigin(resolvedStart.position, timingSession: timingSession)
        preparationControlIntent += 1
        let seekAdmissionIntent = preparationControlIntent
        if shouldPlay {
            let admissionEpoch = preparationTransportEpoch
            let prepared: Bool
            if executedLoop {
                if let session = scheduleUserLoopPreparation(song: song, position: resolvedStart.position),
                   let preparation = awaitUserLoopPreparation(session, epoch: admissionEpoch, intent: seekAdmissionIntent) {
                    prepared = (audioEngine as? RuntimeCMixerUserLoopConsuming)?
                        .configureRuntimeUserLoop(session, preparation: preparation) == true
                    activePatternLoopRange = song.patternLoopRange(containing: resolvedStart.position)
                } else { prepared = false }
            } else {
                let fullReady = prepareRuntimeAdapterEventPlanIfNeeded(for: song, timingSession: timingSession)
                if fullReady, runtimeAdapterEventPlan.requiresAuthoredCycleContinuation, supportsExecutedUserLoop {
                    if let session = scheduleUserLoopPreparation(song: song, position: resolvedStart.position, transportKind: .finiteSong),
                       let preparation = awaitUserLoopPreparation(session, epoch: admissionEpoch, intent: seekAdmissionIntent) {
                        prepared = (audioEngine as? RuntimeCMixerUserLoopConsuming)?
                            .configureRuntimeUserLoop(session, preparation: preparation) == true
                    } else { prepared = false }
                } else { prepared = fullReady }
            }
            guard preparationTransportEpoch == admissionEpoch,
                  preparationControlIntent == seekAdmissionIntent else { return resolvedStart.position }
            guard prepared else {
                activeDebugStartTraceContext = nil
                apply(action: .stop, nextState: .stopped)
                logger.error("Unable to prepare runtime adapter event plan for debug seek; playback start aborted")
                return resolvedStart.position
            }
            let enterStart = timingSession?.beginPhase()
            enter(position: resolvedStart.position, previousPosition: nil, timingSession: timingSession)
            guard preparationTransportEpoch == admissionEpoch,
                  preparationControlIntent == seekAdmissionIntent else { return resolvedStart.position }
            applyDebugStartTickIfNeeded(resolvedStart.actualTickInRow, at: resolvedStart.position)
            timingSession?.recordPhase(
                "playback_engine_enter_selected_playback_position",
                startedAt: enterStart,
                fields: PlaybackTimingTraceFields.playbackPosition(resolvedStart.position)
            )
            let restartTimerStart = timingSession?.beginPhase()
            restartTimer()
            timingSession?.recordPhase(
                "playback_engine_restart_timer",
                startedAt: restartTimerStart,
                fields: [PlaybackTimingTraceField("starts_realtime_timer", startsRealtimeTimer)]
            )
            apply(action: .play, nextState: PlaybackState(mode: .playing, context: state.context))
            guard !serviceRuntimeCMixerAdmissionFailure() else { return resolvedStart.position }
            scheduleRuntimeCMixerSongEndStopIfNeeded()
        } else {
            publishPlaybackFollowPosition(timerPosition: resolvedStart.position, tickInRow: 0, allowBackendOverride: false)
            guard preparationControlIntent == seekAdmissionIntent else { return resolvedStart.position }
            apply(action: .stop, nextState: .stopped)
        }
        return resolvedStart.position
    }

    func stop() {
        stop(action: .stop)
    }

    func stopFromDebugTimer() {
        stop(action: .stop, reason: "debug_stop_after_seconds")
    }

    private func stop(action: PlaybackTransportAction) {
        stop(action: action, reason: "transport_stop_preserve_position")
    }

    private func stop(action: PlaybackTransportAction, reason: String) {
        stop(notify: true, resetAudio: false, action: action, reason: reason)
    }

    private func stop(notify: Bool, resetAudio: Bool, action: PlaybackTransportAction = .stop, reason: String = "transport_stop_preserve_position") {
        // Stop revokes speculative work even before first Play; admitted cache stays reusable.
        preparationTransportEpoch += 1
        preparationControlIntent += 1
        let stopAdmissionIntent = preparationControlIntent
        cancelRuntimeAdapterPlanPrewarm(reason: "transport_stop")
        cancelEditablePatternLoopRefresh(reason: "transport_stop")
        let retiringUserLoopSession = userLoopPreparationSession
        cancelUserLoopPreparation()
        if let pendingPlay { finishPendingPlay(pendingPlay.id, started: false) }
        guard preparationControlIntent == stopAdmissionIntent else { return }
        let wasActive = state.mode != .stopped || timer != nil ||
            (audioEngine as? RuntimeCMixerUserLoopConsuming)?.hasRuntimeUserLoop == true
        guard wasActive || resetAudio else {
            logger.debug("Ignoring stop request because playback is already stopped")
            return
        }
        let positionBeforeStop = currentPosition
        let tickInRowBeforeStop = tickState.tickInRow
        timer?.invalidate()
        timer = nil
        cancelRuntimeCMixerFollowTimer()
        cancelRuntimeCMixerSongEndStop()
        cancelEditablePatternLoopRefresh(reason: "transport_stop")
        // Capture after host quiescence, while the retiring schedule still owns
        // its geometry. A delayed UI timer is never a stopped-position authority.
        let capturedHead = resetAudio ? nil : captureRuntimePlaybackHeadForTransport()
        let unavailableFollow = currentPublishedFollowPosition.flatMap {
            !resetAudio && $0.sampleTimeStatus == "capture_unavailable" ? $0 : nil
        }
        let preservedPosition = resetAudio ? song?.startPosition :
            capturedHead?.follow.position ?? currentPublishedFollowPosition?.position ?? currentPosition ?? song?.startPosition
        let automaticStop = reason == "planned_song_end" || reason == "runtime_song_end_tail" || reason == "debug_stop_after_seconds"
        // A callback can fail after the service poll; quiesce before consuming and resetting.
        let finalAdmissionFault = !resetAudio && automaticStop
            ? (audioEngine as? RuntimeCMixerAdmissionFailureConsuming)?.quiesceOutputAndConsumeAdmissionFailure()
            : nil
        if resetAudio {
            audioEngine.reset()
        } else {
            let audioStopReason = automaticStop || reason == "runtime_mixer_admission_failure" || reason.hasPrefix("loop_")
                ? reason : "transport_stop"
            stopAllAudio(
                context: runtimeTraceContext(at: capturedHead?.follow.position ?? positionBeforeStop,
                    tickInRow: capturedHead?.follow.tickInRow ?? tickInRowBeforeStop, channelIndex: nil,
                    timingOverride: capturedHead?.timing),
                reason: audioStopReason
            )
        }
        guard preparationControlIntent == stopAdmissionIntent else { return }
        adoptUserLoopRefresh(from: retiringUserLoopSession)
        tickState.reset()
        currentPosition = preservedPosition
        currentPublishedFollowPosition = capturedHead?.follow ?? unavailableFollow ??
            preservedPosition.map { PlaybackFollowPosition.timer(position: $0, tickInRow: 0) }
        if let capturedHead { timing = capturedHead.timing }
        pendingPositionCommand = nil
        channelStates.removeAll()
        globalState = PlaybackGlobalState()
        rowDelayDurationsRemaining = 0
        lastVoiceRequests.removeAll()
        delayedVoiceRequests.removeAll()
        runtimeCMixerSongEndStopPending = false
        activePatternLoopRange = nil
        if resetAudio {
            timing = song?.initialTiming ?? .xmDefault
        }
        activeDebugStartTraceContext = nil
        if notify {
            recordRuntimeTransportAction(
                action,
                positionBefore: positionBeforeStop,
                positionAfter: currentPosition,
                tickInRowBefore: tickInRowBeforeStop,
                reason: reason
            )
        }
        guard preparationControlIntent == stopAdmissionIntent else { return }
        traceWriter.flush()
        runtimeCMixerTraceWriter.flush()
        guard preparationControlIntent == stopAdmissionIntent else { return }
        restoreIsolatedPatternLoopSourceIfNeeded(configureAudioPlan: true)
        guard preparationControlIntent == stopAdmissionIntent else { return }
        apply(action: action, nextState: .stopped)
        if notify, wasActive {
            playbackDidStop?()
        }
        if let finalAdmissionFault { playbackDidFail?(finalAdmissionFault) }
    }

    func pause() {
        guard state.mode == .playing else {
            return
        }
        if (audioEngine as? RuntimeCMixerUserLoopConsuming)?.hasRuntimeUserLoop == true {
            preparationTransportEpoch += 1 // A fresh Loop session must never reuse actual birth keys.
        }
        preparationControlIntent += 1
        let retiringUserLoopSession = userLoopPreparationSession
        let pauseIntent = preparationControlIntent
        cancelUserLoopPreparation()
        timer?.invalidate()
        timer = nil
        cancelRuntimeCMixerSongEndStop()
        let capturedHead = captureRuntimePlaybackHeadForTransport()
        stopAllAudio(context: runtimeTraceContext(at: capturedHead?.follow.position ?? currentPosition,
            tickInRow: capturedHead?.follow.tickInRow ?? tickState.tickInRow, channelIndex: nil,
            timingOverride: capturedHead?.timing), reason: "transport_pause")
        guard preparationControlIntent == pauseIntent else { return }
        adoptUserLoopRefresh(from: retiringUserLoopSession)
        var context = state.context
        if let capturedHead { adoptRuntimePlaybackHead(capturedHead) }
        // A failed capture keeps its explicitly tagged last-known resume row;
        // retaining the original Play context would silently rewind that row.
        let resumePosition = capturedHead?.follow.position ?? currentPublishedFollowPosition.flatMap {
            $0.sampleTimeStatus == "capture_unavailable" ? $0.position : nil
        }
        if let resumePosition {
            context = .init(moduleTitle: context?.moduleTitle,
                songPosition: resumePosition.orderIndex,
                patternIndex: resumePosition.patternIndex, row: resumePosition.rowIndex)
        }
        apply(action: .pause, nextState: PlaybackState(mode: .paused, context: context))
        if let capturedHead {
            publishPlaybackFollowPosition(capturedHead.follow, timerPosition: capturedHead.follow.position,
                timerTickInRow: capturedHead.follow.tickInRow, notifyDuplicatePositions: false)
        }
    }

    func togglePlayPause(from context: PlaybackStartContext?) {
        switch state.mode {
        case .playing:
            pause()
        case .paused, .stopped:
            play(from: context ?? state.context)
        }
    }

    func togglePlayStop(from context: PlaybackStartContext?) {
        togglePlayStop(from: context, timingSession: nil)
    }

    func togglePlayStop(from context: PlaybackStartContext?, timingSession: PlaybackTimingTraceSession?) {
        if state.isPlaying {
            stop(action: .spacebarStop)
        } else {
            play(from: context ?? state.context, debugStart: nil, loopEnabled: false, action: .spacebarPlay, timingSession: timingSession)
        }
    }

    func togglePlayStop(from context: PlaybackStartContext?, loopEnabled: Bool, timingSession: PlaybackTimingTraceSession?) {
        if state.isPlaying {
            stop(action: .spacebarStop)
        } else {
            play(from: context ?? state.context, debugStart: nil, loopEnabled: loopEnabled, action: .spacebarPlay, timingSession: timingSession)
        }
    }

    private func finishOwnedPlayTimingSession(_ timingSession: PlaybackTimingTraceSession?, context: PlaybackStartContext?) {
        guard let timingSession else {
            return
        }
        var fields = PlaybackTimingTraceFields.playbackStartContext(context)
        fields.append(contentsOf: PlaybackTimingTraceFields.playbackSong(song))
        fields.append(PlaybackTimingTraceField("is_playing_after", state.isPlaying))
        timingSession.finish(fields: fields)
    }

    private func apply(action: PlaybackTransportAction, nextState: PlaybackState) {
        state = nextState
        logger.debug("Playback transport action: \(String(describing: action), privacy: .public)")
    }

    private func restoreIsolatedPatternLoopSourceIfNeeded(configureAudioPlan: Bool) {
        guard let restoreState = isolatedPatternLoopPlaybackRestoreState else {
            return
        }
        song = restoreState.sourceSong
        runtimeAdapterEventPlan = restoreState.runtimeAdapterEventPlan
        runtimeAdapterPlanCacheSource = restoreState.runtimeAdapterPlanCacheSource
        runtimeAdapterPlanUseCount = restoreState.runtimeAdapterPlanUseCount
        runtimeAdapterPlanKey = restoreState.key
        if case let .cold(order, row) = restoreState.key?.origin {
            intendedColdPosition = song?.position(orderIndex: order, rowIndex: row) ?? song?.startPosition
        } else { intendedColdPosition = song?.startPosition }
        currentSourceGeneration = restoreState.key?.sourceGeneration ?? mintSourceGeneration()
        isolatedPatternLoopPlaybackRestoreState = nil
        isolatedPatternLoopPlaybackContext = nil
        if configureAudioPlan,
           let adapterConsumer = audioEngine as? RuntimeCMixerAdapterEventConsuming {
            adapterConsumer.configureRuntimeAdapterEventPlan(runtimeAdapterEventPlan, generationMS: nil, timingSession: nil)
        }
        runtimeAdapterPlanDidUpdate?()
    }

    private func resetRuntimeState(resetTiming: Bool) {
        tickState.reset()
        pendingPositionCommand = nil
        channelStates.removeAll()
        globalState = PlaybackGlobalState()
        rowDelayDurationsRemaining = 0
        lastVoiceRequests.removeAll()
        delayedVoiceRequests.removeAll()
        traceTickIndex = 0
        runtimeNoteTriggerEventCount = 0
        if resetTiming {
            timing = song?.initialTiming ?? .xmDefault
        }
        activeDebugStartTraceContext = nil
        activePatternLoopRange = nil
        (audioEngine as? RuntimeCMixerAdapterEventConsuming)?.resetRuntimeAdapterEventConsumption()
        runtimeCMixerSongEndStopPending = false
        cancelEditablePatternLoopRefresh(reason: "runtime_state_reset")
    }

    private var usesRuntimeAdapterEventPlan: Bool {
        (audioEngine as? RuntimeCMixerAdapterEventConsuming)?.hasRuntimeAdapterEventPlan == true
    }

    private func invalidateRuntimeAdapterEventPlan(timingSession: PlaybackTimingTraceSession?) {
        let unavailablePlan = RuntimeCMixerAdapterEventPlan.unavailable(sampleRate: audioEngine.audioBufferSampleRate)
        runtimeAdapterEventPlan = unavailablePlan
        runtimeAdapterPlanKey = nil
        runtimeAdapterPlanCacheSource = .none
        runtimeAdapterPlanUseCount = 0
        if let adapterConsumer = audioEngine as? RuntimeCMixerAdapterEventConsuming {
            adapterConsumer.configureRuntimeAdapterEventPlan(unavailablePlan, generationMS: nil, timingSession: timingSession)
        }
        timingSession?.recordPhase(
            "runtime_adapter_event_plan_invalidated",
            startedAt: nil,
            fields: PlaybackTimingTraceFields.adapterPlan(unavailablePlan)
        )
    }

    /// Updates speculative work when stopped navigation changes the next cold start.
    func prepare(from context: PlaybackStartContext?, loopEnabled: Bool = false) {
        guard !state.isPlaying, let song else { return }
        let executedLoop = loopEnabled && supportsExecutedUserLoop
        if intendsExecutedUserLoop != executedLoop {
            preparationControlIntent += 1
            cancelUserLoopPreparation()
            cancelRuntimeAdapterPlanPrewarm(reason: "playback_mode_changed")
            invalidateRuntimeAdapterEventPlan(timingSession: nil)
        }
        intendsExecutedUserLoop = executedLoop
        if executedLoop {
            let position = playbackStartPosition(from: context, in: song) ?? song.startPosition
            updatePreparationOrigin(position, timingSession: nil)
            if let position { _ = scheduleUserLoopPreparation(song: song, position: position) }
            return
        }
        let position = loopEnabled ? song.startPosition : playbackStartPosition(from: context, in: song) ?? song.startPosition
        updatePreparationOrigin(position, timingSession: nil)
        if !runtimeAdapterEventPlan.generated && runtimeAdapterPlanPrewarmJob == nil {
            scheduleRuntimeAdapterPlanPrewarmIfNeeded(for: song, timingSession: nil)
        }
    }

    #if DEBUG
    /// Immutable worker status for focused transport races; never takes the render lock.
    var userLoopRefreshStatusForTesting: RuntimeLoopPlanningSession.RefreshStatus? {
        userLoopPreparationSession?.latestEditableRefreshStatus()
    }
    #endif

    private var supportsExecutedUserLoop: Bool {
        audioEngine is RuntimeCMixerUserLoopConsuming && runtimeAdapterPlanPrewarmScheduler is RuntimeUserLoopWorkerProviding
    }

    private func cancelUserLoopPreparation() {
        let session = userLoopPreparationSession
        adoptUserLoopRefresh(from: session)
        userLoopPreparationSession = nil; userLoopPreparationKey = nil
        lastAdmittedUserLoopRefresh = 0; desiredUserLoopRefresh = nil
        guard let session else { return }
        session.cancel()
        // An installed generation is joined by Backend only after host quiescence
        // and C reset. A purely speculative session has no native voice references.
        if (audioEngine as? RuntimeCMixerUserLoopConsuming)?.hasRuntimeUserLoop != true,
           let worker = runtimeAdapterPlanPrewarmScheduler as? RuntimeUserLoopWorkerProviding {
            worker.userLoopWorkerQueue.async { session.cancelAndWait() }
        }
    }

    @discardableResult
    private func scheduleUserLoopPreparation(song: PlaybackSong, position: PlaybackPosition,
        transportKind: RuntimeLoopNativeScope.TransportKind = .explicitLoop,
        onInitialPreparation: (@Sendable (RuntimeLoopPlanningSession.PreparationResult) -> Void)? = nil
    ) -> RuntimeLoopPlanningSession? {
        guard let worker = runtimeAdapterPlanPrewarmScheduler as? RuntimeUserLoopWorkerProviding,
              audioEngine is RuntimeCMixerUserLoopConsuming,
              let pattern = song.pattern(for: position.orderIndex), pattern.index == position.patternIndex,
              let first = pattern.rows.first, let last = pattern.rows.last,
              let key = PlaybackPreparationKey(instanceEpoch: preparationInstanceID, transportEpoch: preparationTransportEpoch,
                documentID: preparationDocumentID, revision: currentSourceGeneration, sourceGeneration: currentSourceGeneration,
                sampleRate: audioEngine.audioBufferSampleRate,
                frequencyMode: song.usesLinearFrequencyTable ? .linear : .amiga,
                traversalBounds: .init(lowerOrder: 0, upperOrder: max(1, song.orders.count)),
                origin: .cold(order: position.orderIndex, row: position.rowIndex),
                purpose: transportKind == .explicitLoop ? .userLoop : .normalPlay,
                loopScope: transportKind == .explicitLoop ? .init(order: position.orderIndex, pattern: position.patternIndex) : nil,
                plannerVersion: transportKind == .explicitLoop ? 2 : 3)
            else { return nil }
        if onInitialPreparation == nil, userLoopPreparationKey == key,
           let session = userLoopPreparationSession, !session.isCancelled {
            switch session.waitForPreparation() {
            case .pending, .ready: return session
            case .failed, .cancelled: break
            }
        }
        cancelUserLoopPreparation()
        cancelRuntimeAdapterPlanPrewarm(reason: transportKind == .explicitLoop ? "executed_user_loop" : "normal_continuation")
        let schedulingEpoch = preparationTransportEpoch, schedulingIntent = preparationControlIntent
        invalidateRuntimeAdapterEventPlan(timingSession: nil)
        guard preparationTransportEpoch == schedulingEpoch, preparationControlIntent == schedulingIntent else { return nil }
        var uuid = preparationDocumentID.uuid
        let halves = withUnsafeBytes(of: &uuid) { bytes in
            ((0..<8).reduce(UInt64(0)) { ($0 << 8) | UInt64(bytes[$1]) },
             (8..<16).reduce(UInt64(0)) { ($0 << 8) | UInt64(bytes[$1]) })
        }
        let scope = RuntimeLoopNativeScope(documentHigh: halves.0, documentLow: halves.1,
            sourceGeneration: currentSourceGeneration, transportEpoch: preparationTransportEpoch,
            sampleRateBits: key.sampleRateBits, semanticVersion: 1, linearFrequencyMode: song.usesLinearFrequencyTable,
            order: position.orderIndex, pattern: position.patternIndex, firstRow: first.index, lastRow: last.index,
            transportKind: transportKind)
        let profile = adapterPlanProfileRecorder?.beginLifecycle(transportKind == .explicitLoop ? "user_loop" : "normal_continuation")
        let diagnostics: RuntimeLoopPlanningSession.Diagnostics?
        if let profile {
            diagnostics = { value in
                switch value {
                case .produced(let measurement):
                    profile.recordMeasuredPhase("user_loop_batch_production", elapsedMS: measurement.milliseconds,
                        fields: [.init("batch_sequence", measurement.sequence), .init("warmup", measurement.warmup),
                            .init("row_count", measurement.rowCount), .init("command_count", measurement.commandCount),
                            .init("prepared_birth_count", measurement.preparedBirthCount), .init("native_pod_bytes", measurement.ownedPODBytes),
                            .init("remaining_before_frames", measurement.remainingHorizonBeforeFrames.map(String.init) ?? "unavailable"),
                            .init("remaining_after_frames", measurement.remainingHorizonAfterFrames.map(String.init) ?? "unavailable")])
                case .refreshCatalogValidated(let measurement):
                    profile.recordMeasuredPhase("user_loop_edit_catalog_validation", elapsedMS: measurement.milliseconds,
                        fields: [.init("request_serial", measurement.requestSerial), .init("active_sequence", measurement.activeSequence),
                            .init("outcome", measurement.outcome.rawValue),
                            .init("remaining_before_frames", measurement.remainingHorizonBeforeFrames.map(String.init) ?? "unavailable"),
                            .init("remaining_after_frames", measurement.remainingHorizonAfterFrames.map(String.init) ?? "unavailable")])
                case .failed(let failure, let afterStart):
                    profile.recordPhase("user_loop_production_failed", startedAt: nil,
                        fields: [.init("stage", failure.stage.rawValue), .init("after_start", afterStart)])
                case .refreshPrepared(let measurement):
                    profile.recordMeasuredPhase("user_loop_edit_preparation", elapsedMS: measurement.milliseconds,
                        fields: [.init("request_serial", measurement.requestSerial), .init("active_sequence", measurement.activeSequence),
                            .init("boundary_frame", measurement.boundaryFrame), .init("outcome", measurement.outcome.rawValue),
                            .init("remaining_mandatory_frames", measurement.remainingMandatoryHorizonFrames.map(String.init) ?? "unavailable"),
                            .init("ready_at_frame", measurement.readyAtNativeFrame.map(String.init) ?? "unavailable"),
                            .init("published_at_frame", measurement.publishedAtNativeFrame.map(String.init) ?? "unavailable"),
                            .init("first_ready_boundary", measurement.firstReadyVisibleBoundaryFrame.map(String.init) ?? "unavailable"),
                            .init("admitted_boundary", measurement.admittedBoundaryFrame.map(String.init) ?? "unavailable")])
                }
            }
        } else { diagnostics = nil }
        let rate = audioEngine.audioBufferSampleRate
        guard let callbackCapacity = (audioEngine as? RuntimeCMixerUserLoopConsuming)?
            .prepareRuntimeUserLoopCallbackCapacity() else {
            userLoopPlaybackDidFail?(.host(.init(scope: scope, lastPublishedNativeFrame: 0)))
            return nil
        }
        let session = RuntimeLoopPlanningSession(song: song, origin: position, scope: scope,
            workerQueue: worker.userLoopWorkerQueue, horizonFrames: max(1, Int(rate * 0.5)),
            maximumRows: 128, refreshPublicationGuardFrames: callbackCapacity,
            finiteSongTailFrames: runtimeCMixerSongEndTailPolicy.tailFrames(sampleRate: rate),
            diagnostics: diagnostics, onInitialPreparation: onInitialPreparation)
        userLoopPreparationSession = session; userLoopPreparationKey = key
        return session
    }

    private func awaitUserLoopPreparation(_ session: RuntimeLoopPlanningSession,
        epoch: UInt64, intent: UInt64) -> RuntimeLoopPlanningSession.Preparation? {
        while preparationTransportEpoch == epoch, preparationControlIntent == intent, !session.isCancelled {
            switch session.waitForPreparation(timeout: 0.002) {
            case .ready(let preparation): return preparation
            case .failed(let failure):
                logger.error("User Loop preparation failed at \(failure.stage.rawValue, privacy: .public)")
                return nil
            case .cancelled: return nil
            case .pending:
                // Keep newer Stop/load/navigation intents observable during a cold wait.
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002))
            }
        }
        return nil
    }

    private func updatePreparationOrigin(_ position: PlaybackPosition?, timingSession: PlaybackTimingTraceSession?) {
        guard intendedColdPosition != position else { return }
        intendedColdPosition = position
        preparationControlIntent += 1
        cancelUserLoopPreparation()
        cancelRuntimeAdapterPlanPrewarm(reason: "cold_origin_changed")
        // Drop the obsolete admitted graph before allocating its replacement.
        invalidateRuntimeAdapterEventPlan(timingSession: timingSession)
    }

    private func scheduleRuntimeAdapterPlanPrewarmIfNeeded(for song: PlaybackSong?, timingSession: PlaybackTimingTraceSession?) {
        guard !intendsExecutedUserLoop, let song,
              audioEngine as? RuntimeCMixerAdapterEventConsuming != nil else {
            return
        }
        let generation = runtimeAdapterPlanGeneration
        guard let key = preparationKey(for: song, sourceGeneration: currentSourceGeneration, purpose: .normalPlay) else { return }
        let request = RuntimeAdapterPlanPrewarmRequest(
            generation: generation,
            song: song,
            sampleRate: audioEngine.audioBufferSampleRate,
            adapterPlanProfileRecorder: adapterPlanProfileRecorder, key: key
        )
        let fields = runtimeAdapterPlanGenerationFields(generation) +
            PlaybackTimingTraceFields.playbackSong(song) +
            [PlaybackTimingTraceField("sample_rate", Int(audioEngine.audioBufferSampleRate.rounded()))]
        timingSession?.recordPhase(
            "runtime_adapter_event_plan_prewarm_scheduled",
            startedAt: nil,
            fields: fields
        )
        let prewarmTimingSession = playbackTimingRecorder?.beginLifecycle("prewarm")
        prewarmTimingSession?.recordPhase(
            "runtime_adapter_event_plan_prewarm_scheduled",
            startedAt: nil,
            fields: fields
        )
        runtimeAdapterPlanPrewarmTimingSession = prewarmTimingSession
        runtimeAdapterPlanPrewarmJob = runtimeAdapterPlanPrewarmScheduler.schedule(request: request) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.completeRuntimeAdapterPlanPrewarm(notification)
            }
        }
    }

    private func completeRuntimeAdapterPlanPrewarm(_ notification: PlaybackPreparationNotification) {
        guard notification.kind == .ready,
              let job = runtimeAdapterPlanPrewarmJob, job.attempt == notification.attempt else { return }
#if DEBUG
        preparationWillAdmitForTesting?(job.attempt)
#endif
        guard isCurrentPrewarm(job), let result = job.waitForResult() else { return }
        // MainActor claim, cache publication and backend configuration form one synchronous,
        // non-reentrant transaction. Observers run only after backend admission.
        let installed = admitPreparation(result, job: job, mode: nil, timingSession: runtimeAdapterPlanPrewarmTimingSession)
        runtimeAdapterPlanPrewarmJob = nil
        recordRuntimeAdapterPlanPrewarmMake(result)
        finishRuntimeAdapterPlanPrewarm(result: result, outcome: installed ? "installed" : "unavailable")
        if installed { runtimeAdapterPlanDidUpdate?() }
    }

    private func mintSourceGeneration() -> UInt64 {
        precondition(preparationSourceSerial < .max, "Preparation generation exhausted")
        preparationSourceSerial += 1
        return preparationSourceSerial
    }

    private func preparationKey(for song: PlaybackSong, sourceGeneration: UInt64,
                                purpose: PlaybackPreparationKey.Purpose) -> PlaybackPreparationKey? {
        PlaybackPreparationKey(instanceEpoch: preparationInstanceID,
            transportEpoch: preparationTransportEpoch, documentID: preparationDocumentID,
            revision: sourceGeneration, sourceGeneration: sourceGeneration,
            sampleRate: audioEngine.audioBufferSampleRate,
            frequencyMode: song.usesLinearFrequencyTable ? .linear : .amiga,
            traversalBounds: .init(lowerOrder: 0, upperOrder: max(1, song.orders.count)),
            origin: .cold(order: purpose == .editRefresh ? 0 : intendedColdPosition?.orderIndex ?? 0,
                          row: purpose == .editRefresh ? 0 : intendedColdPosition?.rowIndex ?? 0), purpose: purpose,
            loopScope: purpose == .editRefresh ? activePatternLoopRange.map {
                .init(order: $0.orderIndex, pattern: $0.patternIndex)
            } : nil)
    }

    private func isCurrentPrewarm(_ job: RuntimeAdapterPlanPrewarmJob) -> Bool {
        guard let song else { return false }
        return runtimeAdapterPlanPrewarmJob?.attempt == job.attempt &&
            job.generation == runtimeAdapterPlanGeneration &&
            job.key == preparationKey(for: song, sourceGeneration: currentSourceGeneration, purpose: .normalPlay)
    }

    /// Called only within the synchronous MainActor claim/admission transaction.
    private func admitPreparation(_ result: RuntimeAdapterPlanPrewarmResult,
                                  job: RuntimeAdapterPlanPrewarmJob, mode: RuntimeAdapterPlanPlayMode?,
                                  timingSession: PlaybackTimingTraceSession?) -> Bool {
        guard isCurrentPrewarm(job), !result.completedAfterCancellation,
              let plan = result.plan, plan.generated,
              let consumer = audioEngine as? RuntimeCMixerAdapterEventConsuming else { return false }
        runtimeAdapterEventPlan = plan
        runtimeAdapterPlanKey = job.key
        runtimeAdapterPlanCacheSource = mode == .syncFallback ? .syncFallback : .prewarm
        runtimeAdapterPlanUseCount = 0
        consumer.configureRuntimeAdapterEventPlan(plan, generationMS: result.makeMS, timingSession: timingSession)
        // Profiling/tracing and arbitrary observer hooks follow the publication winner.
        recordAdapterPlanProfileBackendConfiguration(plan: plan, generation: result.generation,
            mode: mode, startedAt: nil, profileSession: result.adapterPlanProfileSession)
        runtimeAdapterPlanPrewarmTimingSession?.recordPhase("runtime_adapter_event_plan_prewarm_configure",
            startedAt: nil, fields: PlaybackTimingTraceFields.adapterPlan(plan) + runtimeAdapterPlanGenerationFields(result.generation))
        return true
    }

    private func cancelRuntimeAdapterPlanPrewarm(reason: String) {
        guard let job = runtimeAdapterPlanPrewarmJob else {
            runtimeAdapterPlanPrewarmTimingSession?.finish(fields: [
                PlaybackTimingTraceField("prewarm_outcome", "cancelled"),
                PlaybackTimingTraceField("prewarm_cancel_reason", reason),
            ])
            runtimeAdapterPlanPrewarmTimingSession = nil
            return
        }
        job.cancel()
        runtimeAdapterPlanPrewarmJob = nil
        runtimeAdapterPlanPrewarmTimingSession?.finish(fields: [
            PlaybackTimingTraceField("prewarm_outcome", "cancelled"),
            PlaybackTimingTraceField("prewarm_cancel_reason", reason),
            PlaybackTimingTraceField("song_generation", job.generation),
        ])
        runtimeAdapterPlanPrewarmTimingSession = nil
    }

    private func completeEditablePatternLoopRefresh(_ notification: PlaybackPreparationNotification) {
        guard let job = editablePatternLoopRefreshJob,
              job.attempt == notification.attempt,
              job.generation == editablePatternLoopRefreshGeneration else { return }
        if notification.kind == .retired {
            // Unavailable/invalid refresh source and result aliases have already left
            // the worker. This acknowledgment carries no graph to the control executor.
            editablePatternLoopRefreshJob = nil
            pendingEditablePatternLoopRefresh = nil
            return
        }
        guard notification.kind == .ready, state.isPlaying, activePatternLoopRange != nil else { return }
        // The sole owner retains the result until the established boundary, not this task.
        pendingEditablePatternLoopRefresh = .init(generation: job.generation, attempt: job.attempt)
    }

    private func cancelEditablePatternLoopRefresh(reason _: String) {
        editablePatternLoopRefreshGeneration &+= 1
        editablePatternLoopRefreshJob?.cancel()
        editablePatternLoopRefreshJob = nil
        pendingEditablePatternLoopRefresh = nil
    }

    private func finishRuntimeAdapterPlanPrewarm(result: RuntimeAdapterPlanPrewarmResult, outcome: String) {
        guard let timingSession = runtimeAdapterPlanPrewarmTimingSession else {
            return
        }
        timingSession.finish(fields: [
            PlaybackTimingTraceField("prewarm_outcome", outcome),
            PlaybackTimingTraceField("prewarm_cancelled_before_completion", result.completedAfterCancellation),
            PlaybackTimingTraceField("song_generation", result.generation),
        ])
        runtimeAdapterPlanPrewarmTimingSession = nil
    }

    private func recordRuntimeAdapterPlanPrewarmMake(_ result: RuntimeAdapterPlanPrewarmResult) {
        guard let makeMS = result.makeMS,
              let plan = result.plan else {
            return
        }
        runtimeAdapterPlanPrewarmTimingSession?.recordMeasuredPhase(
            "runtime_adapter_event_plan_prewarm_make",
            elapsedMS: makeMS,
            fields: PlaybackTimingTraceFields.adapterPlan(plan) +
                runtimeAdapterPlanGenerationFields(result.generation)
        )
    }

    private func recordAdapterPlanProfileBackendConfiguration(
        plan: RuntimeCMixerAdapterEventPlan,
        generation: UInt64,
        mode: RuntimeAdapterPlanPlayMode?,
        startedAt startNanoseconds: UInt64?,
        profileSession: AdapterPlanProfileSession?
    ) {
        var fields = AdapterPlanProfileFields.adapterPlan(plan) + AdapterPlanProfileFields.generation(generation)
        if let mode {
            fields.append(AdapterPlanProfileField("play_adapter_plan_mode", mode.rawValue))
        }
        profileSession?.recordPhase(
            "backend_plan_configuration",
            startedAt: startNanoseconds,
            fields: fields
        )
    }

    private func prepareRuntimeAdapterEventPlanIfNeeded(for song: PlaybackSong, timingSession: PlaybackTimingTraceSession?) -> Bool {
        guard let adapterConsumer = audioEngine as? RuntimeCMixerAdapterEventConsuming else {
            runtimeAdapterEventPlan = .unavailable(sampleRate: audioEngine.audioBufferSampleRate)
            runtimeAdapterPlanCacheSource = .none
            runtimeAdapterPlanUseCount = 0
            return true
        }
        // Cache compatibility is content meaning, independently of a revoked request attempt.
        if runtimeAdapterEventPlan.generated,
           let key = runtimeAdapterPlanKey,
           key.sourceGeneration == currentSourceGeneration,
           key.origin == preparationKey(for: song, sourceGeneration: currentSourceGeneration, purpose: .normalPlay)?.origin,
           key.sampleRateBits == audioEngine.audioBufferSampleRate.bitPattern,
           key.frequencyMode == (song.usesLinearFrequencyTable ? .linear : .amiga) {
            if !adapterConsumer.hasRuntimeAdapterEventPlan {
                adapterConsumer.configureRuntimeAdapterEventPlan(runtimeAdapterEventPlan, generationMS: nil, timingSession: timingSession)
            }
            let mode: RuntimeAdapterPlanPlayMode = runtimeAdapterPlanUseCount == 0 && runtimeAdapterPlanCacheSource == .prewarm ? .prewarmed : .cachedReuse
            recordRuntimeAdapterPlanReadyForPlay(mode: mode, timingSession: timingSession)
            runtimeAdapterPlanUseCount += 1
            return true
        }
        if let job = runtimeAdapterPlanPrewarmJob, !isCurrentPrewarm(job) {
            cancelRuntimeAdapterPlanPrewarm(reason: "incompatible_request")
        }
        if runtimeAdapterPlanPrewarmJob == nil {
            scheduleRuntimeAdapterPlanPrewarmIfNeeded(for: song, timingSession: timingSession)
        }
        // An unavailable prewarm permits one compatibility retry through the SAME owner.
        // A revoked wait never means unavailable and never starts an inline constructor.
        for retry in 0...1 {
            guard let job = runtimeAdapterPlanPrewarmJob else { return false }
            let waitStart = timingSession?.beginPhase()
            let ready = job.waitUntilReady()
#if DEBUG
            preparationWillAdmitForTesting?(job.attempt)
#endif
            guard ready, isCurrentPrewarm(job), let result = job.waitForResult() else { return false }
            if result.plan?.generated == true {
                let mode: RuntimeAdapterPlanPlayMode = retry == 0 ? .waited : .syncFallback
                guard admitPreparation(result, job: job, mode: mode, timingSession: timingSession) else { return false }
                runtimeAdapterPlanPrewarmJob = nil
                timingSession?.recordPhase("runtime_adapter_event_plan_configure", startedAt: nil,
                    fields: PlaybackTimingTraceFields.adapterPlan(runtimeAdapterEventPlan) +
                        runtimeAdapterPlanGenerationFields(job.generation) + runtimeAdapterPlanPlayFields(mode: mode))
                timingSession?.recordPhase("runtime_adapter_event_plan_prewarm_wait", startedAt: waitStart,
                    fields: runtimeAdapterPlanGenerationFields(job.generation) +
                        [PlaybackTimingTraceField("prewarm_result_available", result.plan != nil)])
                if retry == 1, let makeMS = result.makeMS {
                    timingSession?.recordMeasuredPhase("runtime_adapter_event_plan_make", elapsedMS: makeMS,
                        fields: PlaybackTimingTraceFields.adapterPlan(runtimeAdapterEventPlan) + runtimeAdapterPlanPlayFields(mode: .syncFallback))
                }
                recordRuntimeAdapterPlanPrewarmMake(result)
                finishRuntimeAdapterPlanPrewarm(result: result, outcome: "waited_by_play")
                recordRuntimeAdapterPlanReadyForPlay(mode: mode, timingSession: timingSession)
                runtimeAdapterPlanUseCount += 1
                runtimeAdapterPlanDidUpdate?()
                return true
            }
            runtimeAdapterPlanPrewarmJob = nil
            finishRuntimeAdapterPlanPrewarm(result: result, outcome: "unavailable")
            guard retry == 0 else {
                recordRuntimeAdapterPlanReadyForPlay(mode: .unavailable, timingSession: timingSession)
                return false
            }
            scheduleRuntimeAdapterPlanPrewarmIfNeeded(for: song, timingSession: timingSession)
        }
        return false
    }

    private func recordRuntimeAdapterPlanReadyForPlay(
        mode: RuntimeAdapterPlanPlayMode,
        timingSession: PlaybackTimingTraceSession?
    ) {
        timingSession?.recordPhase(
            "runtime_adapter_event_plan_ready_for_play",
            startedAt: nil,
            fields: PlaybackTimingTraceFields.adapterPlan(runtimeAdapterEventPlan) +
                runtimeAdapterPlanGenerationFields(runtimeAdapterPlanGeneration) +
                runtimeAdapterPlanPlayFields(mode: mode)
        )
    }

    private func runtimeAdapterPlanGenerationFields(_ generation: UInt64) -> [PlaybackTimingTraceField] {
        [PlaybackTimingTraceField("song_generation", generation)]
    }

    private func runtimeAdapterPlanPlayFields(mode: RuntimeAdapterPlanPlayMode) -> [PlaybackTimingTraceField] {
        [
            PlaybackTimingTraceField("play_adapter_plan_mode", mode.rawValue),
            PlaybackTimingTraceField("plan_cache_source", runtimeAdapterPlanCacheSource.rawValue),
            PlaybackTimingTraceField("plan_use_count_before", runtimeAdapterPlanUseCount),
        ]
    }

    private func consumeRuntimeAdapterEvents(at position: PlaybackPosition, tickInRow: Int, timingSession: PlaybackTimingTraceSession? = nil) {
        guard let adapterConsumer = audioEngine as? RuntimeCMixerAdapterEventConsuming else {
            return
        }
        adapterConsumer.consumeRuntimeAdapterEvents(
            context: runtimeTraceContext(
                at: position,
                tickInRow: tickInRow,
                channelIndex: nil
            ),
            patternLoopRange: activePatternLoopRange,
            timingSession: timingSession
        )
    }

    private func restartTimer() {
        timer?.invalidate()
        cancelRuntimeCMixerFollowTimer()
        guard startsRealtimeTimer else {
            timer = nil
            return
        }
        let timer = Timer(timeInterval: timing.tickDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceOneTick()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func advanceOneTick() {
        guard !serviceRuntimeCMixerAdmissionFailure() else { return }
        if let provider = audioEngine as? RuntimeCMixerPlaybackHeadProviding, provider.hasRuntimePlaybackHead {
            guard state.isPlaying, let head = provider.runtimePlaybackHead() else { return }
            adoptRuntimePlaybackHead(head)
            publishPlaybackFollowPosition(head.follow, timerPosition: head.follow.position,
                timerTickInRow: head.follow.tickInRow, notifyDuplicatePositions: false)
            return
        }
        guard state.isPlaying,
              let song,
              let position = currentPosition else {
            return
        }
        traceTickIndex += 1
        guard tickState.advance(timing: timing) else {
            applyTickEffects(tickInRow: tickState.tickInRow, position: position)
            return
        }
        guard rowDelayDurationsRemaining <= 0 else {
            rowDelayDurationsRemaining -= 1
            return
        }
        let admissionEpoch = preparationTransportEpoch
        let admissionIntent = preparationControlIntent
        let step = nextStep(after: position, in: song)
        guard preparationTransportEpoch == admissionEpoch,
              preparationControlIntent == admissionIntent else { return }
        switch step {
        case let .advanced(nextPosition):
            currentPosition = nextPosition
            enter(position: nextPosition, previousPosition: position)
        case let .ended(restartPosition):
            if let restartPosition {
                currentPosition = restartPosition
                publishPlaybackFollowPosition(timerPosition: restartPosition, tickInRow: 0, allowBackendOverride: false)
            }
            guard !holdTransportForRuntimeCMixerSongEndTailIfNeeded() else {
                return
            }
            logger.debug("Playback reached end of song; stopping cleanly")
            stop(action: .stop, reason: "planned_song_end")
        }
    }

    private func scheduleRuntimeCMixerSongEndStopIfNeeded() {
        cancelRuntimeCMixerSongEndStop()
        guard activePatternLoopRange == nil,
              runtimeUsesCMixer,
              runtimeAdapterEventPlan.generated,
              let plannedSongEndFrame = runtimeAdapterEventPlan.plannedSongEndFrame,
              let currentPosition,
              audioEngine.audioBufferSampleRate.isFinite,
              audioEngine.audioBufferSampleRate > 0 else {
            return
        }
        let context = runtimeTraceContext(
            at: currentPosition,
            tickInRow: tickState.tickInRow,
            channelIndex: nil
        )
        guard let plannedStartFrame = runtimeAdapterEventPlan.plannedFrame(matching: context) ??
            runtimeAdapterEventPlan.plannedRowStartFrame(matching: context) else {
            return
        }
        let tailFrames = runtimeCMixerSongEndTailPolicy.tailFrames(sampleRate: audioEngine.audioBufferSampleRate)
        let framesUntilSongEnd = max(0, plannedSongEndFrame - plannedStartFrame)
        let stopFrames = framesUntilSongEnd.addingReportingOverflow(tailFrames)
        guard !stopFrames.overflow else {
            return
        }
        let stopSeconds = Double(max(0, stopFrames.partialValue)) / audioEngine.audioBufferSampleRate +
            Self.runtimeCMixerSongEndTransportStopGraceSeconds
        runtimeCMixerSongEndStopPending = true
        guard stopSeconds > 0 else {
            finishRuntimeCMixerSongEndTail()
            return
        }
        runtimeCMixerSongEndStopTimer = Timer.scheduledTimer(withTimeInterval: stopSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finishRuntimeCMixerSongEndTail()
            }
        }
    }

    private func finishRuntimeCMixerSongEndTail() {
        guard !serviceRuntimeCMixerAdmissionFailure() else { return }
        guard runtimeCMixerSongEndStopPending, state.isPlaying else { return }
        runtimeCMixerSongEndStopTimer = nil
        if let provider = audioEngine as? RuntimeCMixerPlaybackHeadProviding, provider.hasRuntimePlaybackHead {
            // Wall time only wakes us. The existing native song/tail deadline
            // must actually be rendered, including a nonzero selected origin.
            let head = provider.runtimePlaybackHead()
            let tail = runtimeCMixerSongEndTailPolicy.tailFrames(sampleRate: audioEngine.audioBufferSampleRate)
            let deadline = runtimeAdapterEventPlan.plannedSongEndFrame?.addingReportingOverflow(tail)
            guard let head, let frame = head.follow.sampleTimeFrame,
                  let deadline, !deadline.overflow, frame >= deadline.partialValue else {
                runtimeCMixerSongEndStopTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.finishRuntimeCMixerSongEndTail() }
                }
                return
            }
        }
        runtimeCMixerSongEndStopPending = false
        stop(action: .stop, reason: "runtime_song_end_tail")
    }

    private func adoptRuntimePlaybackHead(_ head: RuntimeCMixerPlaybackHead) {
        currentPosition = head.follow.position
        timing = head.timing
        tickState.setTickInRow(head.follow.tickInRow % max(1, head.timing.speed), timing: head.timing)
    }

    private func captureRuntimePlaybackHeadForTransport() -> RuntimeCMixerPlaybackHead? {
        guard let provider = audioEngine as? RuntimeCMixerPlaybackHeadProviding,
              provider.hasRuntimePlaybackHead else { return nil }
        switch provider.quiesceAndCaptureRuntimePlaybackHead() {
        case .captured(let head): return head
        case .notRendered: return nil // Preserve the explicit cold selection.
        case .unavailable(let reason):
            // Keep the last known coordinate, honestly tagged; never claim that a
            // failed host stop supplied an exact new audio head.
            logger.error("Unable to capture stopped mixer position: \(reason, privacy: .public)")
            if let previous = currentPublishedFollowPosition {
                currentPublishedFollowPosition = .init(position: previous.position, tickInRow: previous.tickInRow,
                    source: previous.source, sampleTimeFrame: previous.sampleTimeFrame,
                    sampleTimeStatus: "capture_unavailable", syntheticRow: previous.syntheticRow)
            }
            return nil
        }
    }

    private func adoptUserLoopRefresh(from session: RuntimeLoopPlanningSession?) {
        guard let receipt = session?.latestAdmittedEditableRefresh(), receipt.serial > lastAdmittedUserLoopRefresh else { return }
        lastAdmittedUserLoopRefresh = receipt.serial
        song = receipt.song
        currentSourceGeneration = receipt.scope.sourceGeneration
        userLoopPreparationKey = nil
    }

    /// Transfers ownership only after delivery acknowledges the revision's exact boundary.
    private func serviceUserLoopRefresh() -> Bool {
        guard let session = userLoopPreparationSession,
              (audioEngine as? RuntimeCMixerUserLoopConsuming)?.hasRuntimeUserLoop == true else { return false }
        adoptUserLoopRefresh(from: session)
        if case let .refused(serial, reason) = session.latestEditableRefreshStatus(),
           let desired = desiredUserLoopRefresh, desired.serial == serial {
            let scope = session.scope
            let wasIsolated = isolatedPatternLoopPlaybackContext != nil
            let stopIntent = preparationControlIntent + 1
            let stopEpoch = preparationTransportEpoch + 1
            stop(action: .stop, reason: "loop_refresh_requires_restart")
            // Teardown and the Stop observer may synchronously load or Play a
            // newer source. Only this refusal's own completed Stop may recover it.
            guard preparationControlIntent == stopIntent,
                  preparationTransportEpoch == stopEpoch else { return true }
            // The refused value remains available for the next cold Play. The loaded
            // source/editor ownership is unchanged; no rejected commands were executed.
            if !wasIsolated {
                song = desired.song
                currentSourceGeneration = desired.generation
            }
            userLoopPlaybackDidFail?(.refresh(scope, reason))
            return true
        }
        return false
    }

    /// Services faults on the existing main cadence, independently of tracing and follow publication.
    private func serviceRuntimeCMixerAdmissionFailure() -> Bool {
        guard !serviceUserLoopRefresh() else { return true }
        if let native = audioEngine as? RuntimeCMixerUserLoopConsuming, native.hasRuntimeUserLoop,
           let fault = native.consumeRuntimeUserLoopFailure() {
            guard fault.scope.transportEpoch == preparationTransportEpoch else { return false }
            stop(action: .stop, reason: fault.stopReason)
            userLoopPlaybackDidFail?(fault)
            return true
        }
        if let native = audioEngine as? RuntimeCMixerUserLoopConsuming,
           let completed = native.consumeRuntimeSongContinuationCompletion(),
           completed.scope.transportEpoch == preparationTransportEpoch,
           completed.scope.sourceGeneration == currentSourceGeneration, state.isPlaying {
            stop(action: .stop, reason: "runtime_song_end_tail")
            return true
        }
        guard let consumer = audioEngine as? RuntimeCMixerAdmissionFailureConsuming,
              let fault = consumer.consumeRuntimeAdmissionFailure() else { return false }
        // Stop the host and retire the failed generation before any alert can enter a modal run loop.
        stop(action: .stop, reason: "runtime_mixer_admission_failure")
        playbackDidFail?(fault)
        return true
    }

    private func holdTransportForRuntimeCMixerSongEndTailIfNeeded() -> Bool {
        guard runtimeCMixerSongEndStopPending else {
            return false
        }
        timer?.invalidate()
        timer = nil
        startRuntimeCMixerFollowTimerIfNeeded()
        return true
    }

    private func cancelRuntimeCMixerSongEndStop() {
        runtimeCMixerSongEndStopTimer?.invalidate()
        runtimeCMixerSongEndStopTimer = nil
        runtimeCMixerSongEndStopPending = false
        cancelRuntimeCMixerFollowTimer()
    }

    private func startRuntimeCMixerFollowTimerIfNeeded() {
        guard runtimeUsesCMixer,
              startsRealtimeTimer,
              runtimeCMixerFollowTimer == nil,
              audioEngine as? PlaybackFollowPositionProviding != nil else {
            return
        }
        let interval = min(0.05, max(1.0 / 60.0, timing.tickDuration))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.publishRuntimeCMixerHeldFollowPosition()
            }
        }
        runtimeCMixerFollowTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelRuntimeCMixerFollowTimer() {
        runtimeCMixerFollowTimer?.invalidate()
        runtimeCMixerFollowTimer = nil
    }

    private func publishRuntimeCMixerHeldFollowPosition() {
        guard !serviceRuntimeCMixerAdmissionFailure() else { return }
        if let provider = audioEngine as? RuntimeCMixerPlaybackHeadProviding, provider.hasRuntimePlaybackHead {
            guard runtimeCMixerSongEndStopPending, state.isPlaying,
                  let head = provider.runtimePlaybackHead() else { return }
            adoptRuntimePlaybackHead(head)
            publishPlaybackFollowPosition(head.follow, timerPosition: head.follow.position,
                timerTickInRow: head.follow.tickInRow, notifyDuplicatePositions: false)
            return
        }
        guard runtimeCMixerSongEndStopPending,
              state.isPlaying,
              let position = currentPosition ?? currentPublishedFollowPosition?.position else {
            return
        }
        publishPlaybackFollowPosition(
            timerPosition: position,
            tickInRow: tickState.tickInRow,
            allowBackendOverride: true,
            notifyDuplicatePositions: false
        )
    }

#if DEBUG
    func publishRuntimeCMixerHeldFollowPositionForTesting() {
        publishRuntimeCMixerHeldFollowPosition()
    }

    func finishRuntimeCMixerSongEndTailForTesting() {
        finishRuntimeCMixerSongEndTail()
    }
#endif

    private var runtimeUsesCMixer: Bool {
        (audioEngine as? PlaybackAudioBackendProviding)?.runtimeAudioBackend.usesRuntimeCMixer == true
    }

    private func enter(position: PlaybackPosition, previousPosition: PlaybackPosition?, timingSession: PlaybackTimingTraceSession? = nil) {
        let admissionEpoch = preparationTransportEpoch
        let admissionIntent = preparationControlIntent
        publishPlaybackFollowPosition(timerPosition: position, tickInRow: tickState.tickInRow, allowBackendOverride: true)
        guard preparationTransportEpoch == admissionEpoch,
              preparationControlIntent == admissionIntent else { return }
        traceRowTiming(at: position, reason: "row_timing_before_effects")
        recordRuntimeRowTransition(from: previousPosition, to: position, phase: "before_events")
        guard preparationTransportEpoch == admissionEpoch,
              preparationControlIntent == admissionIntent else { return }
        let usesAdapterPlan = usesRuntimeAdapterEventPlan
        prepareRowPlaybackState(at: position, emitRuntimeControlUpdates: !usesAdapterPlan)
        // Follow/diagnostic observers can synchronously Stop or load. Their newer intent
        // wins before this row can admit a native event schedule.
        guard preparationTransportEpoch == admissionEpoch,
              preparationControlIntent == admissionIntent else { return }
        if usesAdapterPlan {
            consumeRuntimeAdapterEvents(at: position, tickInRow: 0, timingSession: timingSession)
        } else {
            triggerAudio(at: position)
            applyImmediateTimingEffects()
        }
        recordRuntimeRowTransition(from: previousPosition, to: position, phase: "after_events")
    }

    private func applyDebugStartTickIfNeeded(_ requestedTickInRow: Int?, at position: PlaybackPosition) {
        guard let requestedTickInRow,
              requestedTickInRow > 0 else {
            return
        }
        let actualTickInRow = min(requestedTickInRow, max(0, timing.ticksPerRow - 1))
        guard actualTickInRow > 0 else {
            return
        }
        for tick in 1...actualTickInRow {
            traceTickIndex += 1
            applyTickEffects(tickInRow: tick, position: position)
        }
        tickState.setTickInRow(actualTickInRow, timing: timing)
    }

    private func nextStep(after position: PlaybackPosition, in song: PlaybackSong) -> PlaybackStepResult {
        if let activePatternLoopRange,
           activePatternLoopRange.contains(position) {
            pendingPositionCommand = nil
            let nextRowIndex = position.rowIndex + 1
            if nextRowIndex <= activePatternLoopRange.lastPosition.rowIndex,
               let nextPosition = song.position(orderIndex: activePatternLoopRange.orderIndex, rowIndex: nextRowIndex) {
                return .advanced(nextPosition)
            }
            return .advanced(applyPendingEditablePatternLoopRefreshAtBoundary(fallbackPosition: activePatternLoopRange.firstPosition))
        }
        guard let pendingPositionCommand else {
            return song.position(after: position)
        }
        self.pendingPositionCommand = nil
        switch pendingPositionCommand {
        case let .positionJump(orderIndex):
            guard song.orders.indices.contains(orderIndex) else {
                logger.debug("Ignoring out-of-bounds position jump: \(orderIndex, privacy: .public)")
                return song.position(after: position)
            }
            return song.position(orderIndex: orderIndex, rowIndex: 0).map(PlaybackStepResult.advanced) ?? .ended(restartPosition: nil)
        case let .patternBreak(rowIndex):
            let nextOrderIndex = position.orderIndex + 1
            guard song.orders.indices.contains(nextOrderIndex) else {
                return .ended(restartPosition: nil)
            }
            return song.position(orderIndex: nextOrderIndex, rowIndex: rowIndex).map(PlaybackStepResult.advanced) ?? .ended(restartPosition: nil)
        }
    }

    private func applyPendingEditablePatternLoopRefreshAtBoundary(fallbackPosition: PlaybackPosition) -> PlaybackPosition {
        guard let pending = pendingEditablePatternLoopRefresh,
              pending.generation == editablePatternLoopRefreshGeneration,
              let job = editablePatternLoopRefreshJob, pending.attempt == job.attempt,
              state.isPlaying, let activePatternLoopRange,
              let adapterConsumer = audioEngine as? RuntimeCMixerAdapterEventConsuming else { return fallbackPosition }
#if DEBUG
        preparationWillAdmitForTesting?(job.attempt)
#endif
        guard editablePatternLoopRefreshJob?.attempt == job.attempt, state.isPlaying,
              job.key.purpose == .editRefresh,
              job.key.loopScope == .init(order: activePatternLoopRange.orderIndex, pattern: activePatternLoopRange.patternIndex),
              job.key.transportEpoch == preparationTransportEpoch,
              job.key.documentID == preparationDocumentID,
              job.key.sampleRateBits == audioEngine.audioBufferSampleRate.bitPattern,
              let result = job.waitForResult(), !result.completedAfterCancellation,
              let plan = result.plan, plan.generated, let refreshedSong = result.sourceSong,
              job.key == preparationKey(for: refreshedSong, sourceGeneration: job.key.sourceGeneration, purpose: .editRefresh),
              let refreshedAnchor = refreshedSong.position(orderIndex: activePatternLoopRange.orderIndex,
                  rowIndex: activePatternLoopRange.firstPosition.rowIndex),
              refreshedAnchor.patternIndex == activePatternLoopRange.patternIndex,
              let refreshedRange = refreshedSong.patternLoopRange(containing: refreshedAnchor),
              refreshedRange.orderIndex == activePatternLoopRange.orderIndex,
              refreshedRange.patternIndex == activePatternLoopRange.patternIndex else {
            cancelEditablePatternLoopRefresh(reason: "unavailable_boundary")
            return fallbackPosition
        }
        // No actor suspension or user callback between claim and actual configuration.
        song = refreshedSong
        currentSourceGeneration = job.key.sourceGeneration
        self.activePatternLoopRange = refreshedRange
        runtimeAdapterEventPlan = plan
        runtimeAdapterPlanKey = job.key
        runtimeAdapterPlanCacheSource = .prewarm
        runtimeAdapterPlanUseCount = 0
        adapterConsumer.configureRuntimeAdapterEventPlan(plan, generationMS: result.makeMS, timingSession: nil)
        editablePatternLoopRefreshJob = nil
        pendingEditablePatternLoopRefresh = nil
        runtimeAdapterPlanDidUpdate?()
        return refreshedRange.firstPosition
    }

    private func prepareRowPlaybackState(at position: PlaybackPosition, emitRuntimeControlUpdates: Bool = true) {
        guard let song,
              let row = song.row(at: position) else {
            return
        }
        globalState.beginRow()
        rowDelayDurationsRemaining = 0
        for (channelIndex, cell) in row.cells.enumerated() {
            var channelState = state(forChannel: channelIndex)
            let volumeColumnCommand = PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn)
            channelState.beginRow()
            if cell.note == 97 {
                channelState.noteOff()
            } else if PlaybackEffectHandler.isTonePortamentoEffect(cell.effectType) || isVolumeColumnTonePortamento(volumeColumnCommand) {
                channelState.setTonePortamentoTarget(note: cell.note)
            } else {
                let volumeEnvelope = song.instrument(forInstrument: Int(cell.instrument))?.volumeEnvelope ?? .disabled
                channelState.start(note: cell.note, volumeEnvelope: volumeEnvelope)
            }

            _ = channelState.apply(volumeColumnCommand: volumeColumnCommand)

            if let command = PlaybackEffectHandler.command(effectType: cell.effectType, effectParam: cell.effectParam) {
                apply(command, channelIndex: channelIndex, channelState: &channelState)
            } else if cell.effectType == 0x11 {
                if !globalState.applyVolumeSlide(effectParam: cell.effectParam) {
                    logUnsupportedEffectIfNeeded(cell)
                }
            } else if !channelState.apply(effectType: cell.effectType, effectParam: cell.effectParam) {
                logUnsupportedEffectIfNeeded(cell)
            }

            channelStates[channelIndex] = channelState
        }
        if emitRuntimeControlUpdates {
            updateActiveChannelControls()
        }
    }

    private func isVolumeColumnTonePortamento(_ command: PlaybackVolumeColumnCommand) -> Bool {
        if case .tonePortamento = command {
            return true
        }
        return false
    }

    private func apply(_ command: PlaybackEffectCommand, channelIndex: Int, channelState: inout PlaybackChannelState) {
        switch command {
        case let .setSpeed(speed):
            configureTiming(PlaybackTiming(speed: speed, bpm: timing.bpm))
        case let .setBPM(bpm):
            configureTiming(PlaybackTiming(speed: timing.speed, bpm: bpm))
        case let .positionJump(orderIndex):
            pendingPositionCommand = .positionJump(orderIndex: orderIndex)
        case let .patternBreak(rowIndex):
            pendingPositionCommand = .patternBreak(rowIndex: rowIndex)
        case let .setVolume(volume):
            channelState.volume = volume
        case let .setPanning(panning):
            channelState.panning = PlaybackEffectHandler.clampedPanning(panning)
        case let .setGlobalVolume(volume):
            globalState.setVolume(volume)
        case let .patternDelay(rowDurations):
            rowDelayDurationsRemaining = max(0, rowDurations)
        }
    }

    private func applyTickEffects(tickInRow: Int, position: PlaybackPosition) {
        if usesRuntimeAdapterEventPlan {
            consumeRuntimeAdapterEvents(at: position, tickInRow: tickInRow)
            return
        }
        let oldGlobalVolume = globalState.volume
        globalState.advanceContinuousEffects()
        for channelIndex in channelStates.keys.sorted() {
            guard var channelState = channelStates[channelIndex] else {
                continue
            }
            if channelState.activeEffect != nil {
                channelState.advanceContinuousEffect(tickInRow: tickInRow)
            }
            channelState.advanceEnvelopeTick()
            channelStates[channelIndex] = channelState
            updateAudioChannel(
                channelIndex,
                controls: effectiveControls(for: channelState),
                context: runtimeTraceContext(at: position, tickInRow: tickInRow, channelIndex: channelIndex, channelState: channelState)
            )
            traceChannelEvent(
                at: position,
                tickInRow: tickInRow,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .updated,
                reason: "tick_controls_updated"
            )
            if channelState.volumeEnvelopeState.isFullyFadedOut {
                stopAudioChannel(
                    channelIndex,
                    context: runtimeTraceContext(at: position, tickInRow: tickInRow, channelIndex: channelIndex, channelState: channelState),
                    reason: "envelope_fadeout_completed"
                )
                channelStates.removeValue(forKey: channelIndex)
                continue
            }
            applyTimingEffects(channelIndex: channelIndex, channelState: channelState, tickInRow: tickInRow, position: position)
        }
        if oldGlobalVolume != globalState.volume, channelStates.isEmpty {
            logger.debug("Applied global volume slide without active channels")
        }
    }

    private func applyImmediateTimingEffects() {
        for channelIndex in channelStates.keys.sorted() {
            guard let channelState = channelStates[channelIndex],
                  channelState.noteCutTick == 0 else {
                continue
            }
            stopAudioChannel(
                channelIndex,
                context: runtimeTraceContext(at: currentPosition, tickInRow: 0, channelIndex: channelIndex, channelState: channelState),
                reason: "note_cut_tick_0"
            )
            traceChannelEvent(
                at: currentPosition,
                tickInRow: 0,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .cut,
                reason: "note_cut_tick_0"
            )
        }
    }

    private func applyTimingEffects(channelIndex: Int, channelState: PlaybackChannelState, tickInRow: Int, position: PlaybackPosition) {
        if channelState.noteCutTick == tickInRow {
            stopAudioChannel(
                channelIndex,
                context: runtimeTraceContext(at: position, tickInRow: tickInRow, channelIndex: channelIndex, channelState: channelState),
                reason: "note_cut"
            )
            traceChannelEvent(
                at: position,
                tickInRow: tickInRow,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .cut,
                reason: "note_cut"
            )
        }
        if let delayedRequest = delayedVoiceRequests[channelIndex],
           channelState.noteDelayTick == tickInRow {
            traceRequest(
                delayedRequest,
                at: position,
                tickInRow: tickInRow,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .triggered,
                reason: "delayed_note_triggered"
            )
            trigger(
                delayedRequest,
                channelIndex: channelIndex,
                context: runtimeTraceContext(
                    at: position,
                    tickInRow: tickInRow,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    request: delayedRequest
                )
            )
            delayedVoiceRequests[channelIndex] = nil
        }
        if let interval = channelState.retriggerInterval,
           interval > 0,
           tickInRow.isMultiple(of: interval),
           let request = lastVoiceRequests[channelIndex] {
            traceRequest(
                request,
                at: position,
                tickInRow: tickInRow,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .retriggered,
                reason: "retrigger_interval"
            )
            trigger(
                request,
                channelIndex: channelIndex,
                context: runtimeTraceContext(
                    at: position,
                    tickInRow: tickInRow,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    request: request
                )
            )
        }
    }

    private func logUnsupportedEffectIfNeeded(_ cell: PlaybackCell) {
        guard cell.effectType != 0 || cell.effectParam != 0 else {
            return
        }
        logger.debug("Deferred XM effect \(cell.effectType, privacy: .public) param \(cell.effectParam, privacy: .public)")
    }

    private func triggerAudio(at position: PlaybackPosition) {
        guard let song,
              let row = song.row(at: position) else {
            return
        }
        for (channelIndex, cell) in row.cells.enumerated() {
            let channelState = state(forChannel: channelIndex)
            guard cell.note > 0 else {
                traceChannelEvent(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .ignored,
                    reason: "no_note"
                )
                continue
            }
            guard cell.note != 97 else {
                traceChannelEvent(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .updated,
                    reason: "key_off"
                )
                recordRuntimeEngineAction(
                    action: "key_off",
                    context: runtimeTraceContext(at: position, tickInRow: 0, channelIndex: channelIndex, channelState: channelState),
                    targetScope: "channel",
                    targetedAllVoices: false,
                    reason: "key_off"
                )
                continue
            }
            guard cell.note <= 96 else {
                traceChannelEvent(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .ignored,
                    reason: "invalid_note"
                )
                continue
            }
            guard let sample = song.resolveSample(
                instrumentIndex: Int(cell.instrument),
                note: cell.note,
                missingKeymapPolicy: .firstPlayableSample
            )?.sample else {
                traceChannelEvent(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .ignored,
                    reason: "missing_sample"
                )
                continue
            }
            let controls = effectiveControls(for: channelState)
            let request = AudioVoiceRequest(
                sample: sample,
                note: cell.note,
                channel: channelIndex,
                volumeScale: controls.volumeScale,
                pitchOffsetSemitones: controls.pitchOffsetSemitones,
                panning: controls.panning,
                sampleStartOffset: channelState.sampleStartOffset
            )
            if let delayTick = channelState.noteDelayTick,
               delayTick > 0 {
                if delayTick < timing.ticksPerRow {
                    delayedVoiceRequests[channelIndex] = request
                    traceRequest(
                        request,
                        at: position,
                        tickInRow: 0,
                        channelIndex: channelIndex,
                        channelState: channelState,
                        decision: .delayed,
                        reason: "note_delay"
                    )
                } else {
                    traceRequest(
                        request,
                        at: position,
                        tickInRow: 0,
                        channelIndex: channelIndex,
                        channelState: channelState,
                        decision: .ignored,
                        reason: "note_delay_exceeds_row_speed"
                    )
                }
                continue
            }
            guard channelState.suppressesNoteTrigger != true else {
                traceRequest(
                    request,
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    decision: .ignored,
                    reason: "note_trigger_suppressed"
                )
                continue
            }
            traceRequest(
                request,
                at: position,
                tickInRow: 0,
                channelIndex: channelIndex,
                channelState: channelState,
                decision: .triggered,
                reason: "row_note"
            )
            trigger(
                request,
                channelIndex: channelIndex,
                context: runtimeTraceContext(
                    at: position,
                    tickInRow: 0,
                    channelIndex: channelIndex,
                    channelState: channelState,
                    request: request
                )
            )
        }
    }

    private func trigger(_ request: AudioVoiceRequest, channelIndex: Int, context: AudioRuntimeTraceContext?) {
        recordRuntimeEngineAction(
            action: "note_trigger",
            context: context,
            targetScope: "channel",
            targetedAllVoices: false,
            reason: "playback_engine_note_trigger"
        )
        if let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput {
            diagnosticOutput.trigger(request, context: context)
        } else {
            audioEngine.trigger(request)
        }
        lastVoiceRequests[channelIndex] = request
    }

    private func updateActiveChannelControls() {
        for channelIndex in channelStates.keys.sorted() {
            guard let channelState = channelStates[channelIndex] else {
                continue
            }
            updateAudioChannel(
                channelIndex,
                controls: effectiveControls(for: channelState),
                context: runtimeTraceContext(at: currentPosition, tickInRow: tickState.tickInRow, channelIndex: channelIndex, channelState: channelState)
            )
        }
    }

    private func updateAudioChannel(_ channelIndex: Int, controls: AudioChannelControls, context: AudioRuntimeTraceContext?) {
        if let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput {
            diagnosticOutput.update(channel: channelIndex, controls: controls, context: context)
        } else {
            audioEngine.update(channel: channelIndex, controls: controls)
        }
    }

    private func stopAudioChannel(_ channelIndex: Int, context: AudioRuntimeTraceContext?, reason: String) {
        recordRuntimeEngineAction(
            action: "channel_stop",
            context: context,
            targetScope: "channel",
            targetedAllVoices: false,
            reason: reason
        )
        if let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput {
            diagnosticOutput.stop(channel: channelIndex, context: context)
        } else {
            audioEngine.stop(channel: channelIndex)
        }
    }

    private func stopAllAudio(context: AudioRuntimeTraceContext?, reason: String) {
        if let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput {
            diagnosticOutput.stopAll(context: context, reason: reason)
        } else {
            audioEngine.stopAll()
        }
    }

    private func recordRuntimeEngineAction(
        action: String,
        context: AudioRuntimeTraceContext?,
        targetScope: String,
        targetedAllVoices: Bool,
        reason: String
    ) {
        guard runtimeCMixerTraceWriter.isEnabled else {
            return
        }
        let noteTriggerEventCount: UInt64?
        if action == "note_trigger" {
            runtimeNoteTriggerEventCount &+= 1
            noteTriggerEventCount = runtimeNoteTriggerEventCount
        } else {
            noteTriggerEventCount = nil
        }
        let backend = (audioEngine as? PlaybackAudioBackendProviding)?.runtimeAudioBackend ?? .cMixer
        runtimeCMixerTraceWriter.record(RuntimeCMixerTraceEvent(
            runtimeAction: action,
            runtimeAudioBackend: backend.diagnosticName,
            runtimeOutputHostType: backend.runtimeOutputHostType,
            debugStopAfterSeconds: debugStopAfterSeconds,
            sampleRate: audioEngine.audioBufferSampleRate,
            context: context,
            targetScope: targetScope,
            targetedAllVoices: targetedAllVoices,
            noteTriggerEventCount: noteTriggerEventCount,
            cMixerCallSucceeded: nil,
            reason: reason
        ))
    }

    private func recordRuntimeTransportAction(
        _ action: PlaybackTransportAction,
        positionBefore: PlaybackPosition?,
        positionAfter: PlaybackPosition?,
        tickInRowBefore: Int,
        reason: String
    ) {
        guard runtimeCMixerTraceWriter.isEnabled else {
            return
        }
        let backend = (audioEngine as? PlaybackAudioBackendProviding)?.runtimeAudioBackend ?? .cMixer
        runtimeCMixerTraceWriter.record(RuntimeCMixerTraceEvent(
            runtimeAction: action.traceName,
            runtimeAudioBackend: backend.diagnosticName,
            runtimeOutputHostType: backend.runtimeOutputHostType,
            debugStopAfterSeconds: debugStopAfterSeconds,
            sampleRate: audioEngine.audioBufferSampleRate,
            context: runtimeTraceContext(at: positionAfter ?? positionBefore, tickInRow: positionAfter == nil ? tickInRowBefore : 0, channelIndex: nil),
            targetScope: "transport",
            targetedAllVoices: true,
            previousOrderIndex: positionBefore?.orderIndex,
            previousPatternIndex: positionBefore?.patternIndex,
            previousRowIndex: positionBefore?.rowIndex,
            nextOrderIndex: positionAfter?.orderIndex,
            nextPatternIndex: positionAfter?.patternIndex,
            nextRowIndex: positionAfter?.rowIndex,
            cMixerCallSucceeded: nil,
            reason: reason
        ))
    }

    private func recordRuntimeRowTransition(from previousPosition: PlaybackPosition?, to position: PlaybackPosition, phase: String) {
        guard let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput else {
            return
        }
        diagnosticOutput.recordTransition(
            previousContext: runtimeTraceContext(
                at: previousPosition,
                tickInRow: tickState.tickInRow,
                channelIndex: nil
            ),
            context: runtimeTraceContext(
                at: position,
                tickInRow: tickState.tickInRow,
                channelIndex: nil
            ),
            phase: phase,
            reason: phase == "after_events" ? "playback_engine_row_enter_after_events" : "playback_engine_row_enter"
        )
    }

    private func publishPlaybackFollowPosition(
        timerPosition: PlaybackPosition,
        tickInRow: Int,
        allowBackendOverride: Bool,
        notifyDuplicatePositions: Bool = true
    ) {
        let provider = audioEngine as? PlaybackFollowPositionProviding
        let published = allowBackendOverride
            ? provider?.playbackFollowPosition(
                timerPosition: timerPosition,
                timerTickInRow: tickInRow
            )
            : nil
        let resolverFailureReason = allowBackendOverride && provider != nil && published == nil
            ? "resolver_unresolved"
            : nil
        let followPosition = published ?? PlaybackFollowPosition.timer(position: timerPosition, tickInRow: tickInRow)
        publishPlaybackFollowPosition(followPosition, timerPosition: timerPosition, timerTickInRow: tickInRow,
            notifyDuplicatePositions: notifyDuplicatePositions, resolverFailureReason: resolverFailureReason)
    }

    /// Publishes the same immutable value used to update transport state; no second native read.
    private func publishPlaybackFollowPosition(_ followPosition: PlaybackFollowPosition,
        timerPosition: PlaybackPosition, timerTickInRow: Int, notifyDuplicatePositions: Bool,
        resolverFailureReason: String? = nil) {
        let publicationIntent = preparationControlIntent
        // The UI observer consumes row coordinates. Exact tick/frame state and
        // diagnostics still update below for every coherent native observation.
        let duplicateSuppressed = !notifyDuplicatePositions &&
            currentPublishedFollowPosition?.position == followPosition.position
        let consumedByUI = !runtimeCMixerFollowPublicationDisabled &&
            !duplicateSuppressed &&
            positionDidChange != nil
        currentPublishedFollowPosition = followPosition
        if let diagnosticOutput = audioEngine as? RuntimeAudioDiagnosticOutput {
            diagnosticOutput.recordPublishedPlaybackFollowPosition(
                timerContext: runtimeTraceContext(at: timerPosition, tickInRow: timerTickInRow, channelIndex: nil),
                publishedPosition: followPosition,
                publicationDisabled: runtimeCMixerFollowPublicationDisabled,
                consumedByUI: consumedByUI,
                duplicateSuppressed: duplicateSuppressed,
                resolverFailureReason: resolverFailureReason
            )
        }
        guard preparationControlIntent == publicationIntent else { return }
        if !runtimeCMixerFollowPublicationDisabled, !duplicateSuppressed {
            positionDidChange?(followPosition.position)
        }
    }

    private func effectiveControls(for channelState: PlaybackChannelState) -> AudioChannelControls {
        var controls = channelState.audioControls
        controls.volumeScale = PlaybackVolumeCalculator.clamped(controls.volumeScale * globalState.volume)
        return controls
    }

    private func runtimeTraceContext(
        at position: PlaybackPosition?,
        tickInRow: Int,
        channelIndex: Int?,
        channelState: PlaybackChannelState? = nil,
        request: AudioVoiceRequest? = nil,
        timingOverride: PlaybackTiming? = nil
    ) -> AudioRuntimeTraceContext? {
        guard let position else {
            return nil
        }
        let traceCell: PlaybackCell?
        if let channelIndex {
            traceCell = cell(at: position, channelIndex: channelIndex)
        } else {
            traceCell = nil
        }
        let noteValue: UInt8?
        if let note = traceCell?.note, note > 0 {
            noteValue = note
        } else if let request {
            noteValue = request.note
        } else {
            noteValue = channelState?.baseNote
        }
        let instrumentIndex: Int?
        if let instrument = traceCell?.instrument, instrument > 0 {
            instrumentIndex = Int(instrument)
        } else {
            instrumentIndex = request?.sample.instrumentIndex
        }
        return AudioRuntimeTraceContext(
            orderIndex: position.orderIndex,
            patternIndex: position.patternIndex,
            rowIndex: position.rowIndex,
            tickInRow: tickInRow,
            channelIndex: channelIndex,
            noteValue: noteValue,
            instrumentIndex: instrumentIndex,
            effectType: traceCell?.effectType,
            effectParam: traceCell?.effectParam,
            volumeColumn: traceCell?.volumeColumn,
            speed: (timingOverride ?? timing).speed,
            bpm: (timingOverride ?? timing).bpm,
            tickIndex: traceTickIndex
        )
    }

    private func state(forChannel channelIndex: Int) -> PlaybackChannelState {
        channelStates[channelIndex] ?? PlaybackChannelState.defaultState(forChannel: channelIndex)
    }

    private func playbackStartPosition(from context: PlaybackStartContext?, in song: PlaybackSong) -> PlaybackPosition? {
        guard let context else {
            return currentPosition ?? song.startPosition
        }
        if let contextPosition = song.position(orderIndex: context.songPosition, rowIndex: context.row),
           contextPosition.patternIndex == context.patternIndex {
            return contextPosition
        }
        for order in song.orders where order.patternIndex == context.patternIndex {
            return song.position(orderIndex: order.orderIndex, rowIndex: context.row)
        }
        return song.startPosition
    }

    private func resolveDebugStart(_ request: PlaybackDebugStartRequest, in song: PlaybackSong) -> PlaybackResolvedDebugStart? {
        let position: PlaybackPosition?
        if let orderIndex = request.requestedOrderIndex {
            position = song.position(orderIndex: orderIndex, rowIndex: request.requestedRowIndex)
        } else if let patternIndex = request.requestedPatternIndex {
            position = song.position(patternIndex: patternIndex, rowIndex: request.requestedRowIndex)
        } else {
            position = song.position(orderIndex: 0, rowIndex: request.requestedRowIndex)
        }
        guard let position else {
            logger.debug("Ignoring debug seek because no matching playback position was found")
            return nil
        }
        let actualTickInRow = request.requestedTickInRow.map { min($0, max(0, song.initialTiming.ticksPerRow - 1)) }
        return PlaybackResolvedDebugStart(request: request, position: position, actualTickInRow: actualTickInRow)
    }

    private func traceChannelEvent(
        at position: PlaybackPosition?,
        tickInRow: Int,
        channelIndex: Int,
        channelState: PlaybackChannelState,
        decision: PlaybackTraceDecision,
        reason: String
    ) {
        guard traceWriter.isEnabled,
              let position else {
            return
        }
        let cell = cell(at: position, channelIndex: channelIndex)
        let request = lastVoiceRequests[channelIndex] ?? delayedVoiceRequests[channelIndex]
        let controls = effectiveControls(for: channelState)
        let noteValue = traceNoteValue(cell: cell, channelState: channelState, request: request)
        traceWriter.record(makeTraceEvent(
            position: position,
            tickInRow: tickInRow,
            channelIndex: channelIndex,
            cell: cell,
            noteValue: noteValue,
            instrumentIndex: traceInstrumentIndex(cell: cell, request: request),
            sampleIndex: request?.sample.sampleIndex,
            controls: controls,
            sample: request?.sample,
            sampleOffset: channelState.sampleStartOffset,
            channelState: channelState,
            decision: decision,
            reason: reason
        ))
    }

    private func traceRequest(
        _ request: AudioVoiceRequest,
        at position: PlaybackPosition,
        tickInRow: Int,
        channelIndex: Int,
        channelState: PlaybackChannelState,
        decision: PlaybackTraceDecision,
        reason: String
    ) {
        guard traceWriter.isEnabled else {
            return
        }
        let cell = cell(at: position, channelIndex: channelIndex)
        traceWriter.record(makeTraceEvent(
            position: position,
            tickInRow: tickInRow,
            channelIndex: channelIndex,
            cell: cell,
            noteValue: request.note,
            instrumentIndex: request.sample.instrumentIndex,
            sampleIndex: request.sample.sampleIndex,
            controls: AudioChannelControls(
                volumeScale: request.volumeScale,
                pitchOffsetSemitones: request.pitchOffsetSemitones,
                panning: request.panning
            ),
            sample: request.sample,
            sampleOffset: request.sampleStartOffset,
            channelState: channelState,
            decision: decision,
            reason: reason
        ))
    }

    private func traceRowTiming(at position: PlaybackPosition, reason: String) {
        guard traceWriter.isEnabled else {
            return
        }
        traceWriter.record(makeTraceEvent(
            position: position,
            tickInRow: tickState.tickInRow,
            channelIndex: -1,
            cell: nil,
            noteValue: nil,
            instrumentIndex: nil,
            sampleIndex: nil,
            controls: AudioChannelControls(),
            sample: nil,
            sampleOffset: nil,
            channelState: nil,
            decision: .observed,
            reason: reason
        ))
    }

    private func makeTraceEvent(
        position: PlaybackPosition,
        tickInRow: Int,
        channelIndex: Int,
        cell: PlaybackCell?,
        noteValue: UInt8?,
        instrumentIndex: Int?,
        sampleIndex: Int?,
        controls: AudioChannelControls,
        sample: PlaybackSample?,
        sampleOffset: Int?,
        channelState: PlaybackChannelState?,
        decision: PlaybackTraceDecision,
        reason: String
    ) -> PlaybackTraceEvent {
        let computedRate = rateApproximation(
            note: noteValue,
            sample: sample,
            pitchOffsetSemitones: controls.pitchOffsetSemitones
        )
        let pitchCalculation = pitchCalculation(
            note: noteValue,
            sample: sample,
            pitchOffsetSemitones: controls.pitchOffsetSemitones
        )
        let loopRegion = sample?.loopRegion
        let debugTrace = activeDebugStartTraceContext
        return PlaybackTraceEvent(
            tickIndex: traceTickIndex,
            orderIndex: position.orderIndex,
            patternIndex: position.patternIndex,
            rowIndex: position.rowIndex,
            tickInRow: tickInRow,
            channelIndex: channelIndex,
            speed: timing.speed,
            bpm: timing.bpm,
            tickDuration: timing.tickDuration,
            rowDuration: timing.rowDuration,
            runtimeAudioBackend: (audioEngine as? PlaybackAudioBackendProviding)?.runtimeAudioBackend.diagnosticName,
            usesLinearFrequencyTable: song?.usesLinearFrequencyTable,
            startedFromDebugSeek: debugTrace != nil,
            requestedStartOrder: debugTrace?.requestedStartOrder,
            requestedStartPattern: debugTrace?.requestedStartPattern,
            requestedStartRow: debugTrace?.requestedStartRow,
            requestedStartTick: debugTrace?.requestedStartTick,
            actualStartOrder: debugTrace?.actualStartOrder,
            actualStartPattern: debugTrace?.actualStartPattern,
            actualStartRow: debugTrace?.actualStartRow,
            actualStartTick: debugTrace?.actualStartTick,
            noteValue: noteValue,
            instrumentIndex: instrumentIndex,
            sampleIndex: sampleIndex,
            relativeNote: sample?.relativeNote,
            finetune: sample?.finetune,
            sourceSampleRate: sample?.baseSampleRate,
            audioBufferSampleRate: pitchCalculation?.audioBufferSampleRate,
            rawVolumeColumn: rawVolumeColumnString(for: cell),
            decodedVolumeColumnCommand: decodedVolumeColumnCommandString(for: cell),
            volumeColumnApplied: volumeColumnApplied(for: cell),
            volumeColumnVolume: volumeColumnVolume(for: cell),
            volumeColumnPanning: volumeColumnPanning(for: cell),
            effectCommand: effectCommandString(for: cell),
            effectParameter: effectParameterString(for: cell),
            effect: effectString(for: cell),
            computedVolume: controls.volumeScale,
            computedPanning: controls.panning,
            computedPitchSemitones: controls.pitchOffsetSemitones,
            targetFrequency: pitchCalculation?.targetFrequency,
            computedRate: computedRate,
            rateBasis: pitchCalculation?.rateBasis,
            computedFrequency: pitchCalculation?.frequency,
            computedVarispeedRate: pitchCalculation?.varispeedRate,
            computedPeriodApproximation: computedRate.map { 1.0 / max(0.000001, $0) },
            sampleOffset: sampleOffset,
            sampleLength: sample?.sampleLength,
            loopStart: sample?.loopStart,
            loopLength: sample?.loopLength,
            loopType: sample?.loopType,
            loopTypeName: loopRegion?.loopTypeName,
            loopEnabled: loopRegion?.isEnabled,
            loopStartFrame: loopRegion?.startFrame,
            loopEndFrame: loopRegion?.endFrame,
            loopLengthFrames: loopRegion?.lengthFrames,
            pingPongLoopApplied: loopRegion?.pingPongLoopApplied,
            envelopeEnabled: channelState?.volumeEnvelopeState.envelopeEnabled,
            envelopeTick: channelState?.volumeEnvelopeState.tick,
            envelopeValue: channelState?.volumeEnvelopeState.envelopeValue,
            envelopeSustainActive: channelState?.volumeEnvelopeState.sustainActive,
            envelopeLoopActive: channelState?.volumeEnvelopeState.loopActive,
            fadeoutValue: channelState?.volumeEnvelopeState.fadeoutValue,
            finalAppliedVolume: sample.map {
                PlaybackVolumeCalculator.finalAppliedVolume(sampleVolume: $0.volume, nodeVolumeScale: controls.volumeScale)
            },
            decision: decision,
            decisionReason: reason
        )
    }

    private func cell(at position: PlaybackPosition, channelIndex: Int) -> PlaybackCell? {
        guard let row = song?.row(at: position),
              row.cells.indices.contains(channelIndex) else {
            return nil
        }
        return row.cells[channelIndex]
    }

    private func traceNoteValue(cell: PlaybackCell?, channelState: PlaybackChannelState, request: AudioVoiceRequest?) -> UInt8? {
        if let note = cell?.note, note > 0 {
            return note
        }
        if let note = request?.note {
            return note
        }
        return channelState.baseNote
    }

    private func traceInstrumentIndex(cell: PlaybackCell?, request: AudioVoiceRequest?) -> Int? {
        if let instrument = cell?.instrument, instrument > 0 {
            return Int(instrument)
        }
        return request?.sample.instrumentIndex
    }

    private func rateApproximation(note: UInt8?, sample: PlaybackSample?, pitchOffsetSemitones: Double) -> Double? {
        let controlRate = pow(2.0, pitchOffsetSemitones / 12.0)
        guard let note,
              let sample else {
            return controlRate
        }
        return PlaybackPitchCalculator.calculation(
            note: note,
            sample: sample,
            pitchOffsetSemitones: pitchOffsetSemitones,
            outputSampleRate: audioEngine.audioBufferSampleRate
        ).playbackRate
    }

    private func pitchCalculation(note: UInt8?, sample: PlaybackSample?, pitchOffsetSemitones: Double) -> PlaybackPitchCalculation? {
        guard let note,
              let sample else {
            return nil
        }
        return PlaybackPitchCalculator.calculation(
            note: note,
            sample: sample,
            pitchOffsetSemitones: pitchOffsetSemitones,
            outputSampleRate: audioEngine.audioBufferSampleRate
        )
    }

    private func effectCommandString(for cell: PlaybackCell?) -> String {
        guard let cell else {
            return "00"
        }
        return String(format: "%02X", cell.effectType)
    }

    private func effectParameterString(for cell: PlaybackCell?) -> String {
        guard let cell else {
            return "00"
        }
        return String(format: "%02X", cell.effectParam)
    }

    private func effectString(for cell: PlaybackCell?) -> String {
        "\(effectCommandString(for: cell))\(effectParameterString(for: cell))"
    }

    private func rawVolumeColumnString(for cell: PlaybackCell?) -> String? {
        guard let cell else {
            return nil
        }
        return String(format: "%02X", cell.volumeColumn)
    }

    private func decodedVolumeColumnCommandString(for cell: PlaybackCell?) -> String? {
        guard let cell else {
            return nil
        }
        return PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn).traceName
    }

    private func volumeColumnApplied(for cell: PlaybackCell?) -> Bool? {
        guard let cell else {
            return nil
        }
        switch PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn) {
        case .none, .setVibratoSpeed, .vibrato:
            return false
        case let .volumeSlideDown(amount),
             let .volumeSlideUp(amount),
             let .fineVolumeSlideDown(amount),
             let .fineVolumeSlideUp(amount),
             let .panningSlideLeft(amount),
             let .panningSlideRight(amount),
             let .tonePortamento(amount):
            return amount > 0
        case .setVolume, .setPanning:
            return true
        }
    }

    private func volumeColumnVolume(for cell: PlaybackCell?) -> Int? {
        guard let cell else {
            return nil
        }
        return PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn).volumeValue
    }

    private func volumeColumnPanning(for cell: PlaybackCell?) -> Int? {
        guard let cell else {
            return nil
        }
        return PlaybackEffectHandler.volumeColumnCommand(cell.volumeColumn).panningValue
    }
}

private struct PlaybackResolvedDebugStart: Equatable {
    let request: PlaybackDebugStartRequest
    let position: PlaybackPosition
    let actualTickInRow: Int?
}

private struct PlaybackDebugStartTraceContext: Equatable {
    let requestedStartOrder: Int?
    let requestedStartPattern: Int?
    let requestedStartRow: Int
    let requestedStartTick: Int?
    let actualStartOrder: Int
    let actualStartPattern: Int
    let actualStartRow: Int
    let actualStartTick: Int?

    init(request: PlaybackDebugStartRequest, position: PlaybackPosition, actualTickInRow: Int?) {
        requestedStartOrder = request.requestedOrderIndex
        requestedStartPattern = request.requestedPatternIndex
        requestedStartRow = request.requestedRowIndex
        requestedStartTick = request.requestedTickInRow
        actualStartOrder = position.orderIndex
        actualStartPattern = position.patternIndex
        actualStartRow = position.rowIndex
        actualStartTick = actualTickInRow ?? 0
    }
}

private enum PlaybackPositionCommand: Equatable {
    case positionJump(orderIndex: Int)
    case patternBreak(rowIndex: Int)
}
