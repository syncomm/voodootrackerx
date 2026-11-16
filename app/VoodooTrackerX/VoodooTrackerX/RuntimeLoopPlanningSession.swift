import Dispatch
import Foundation
import Synchronization

/// Serial off-audio owner of one native transport generation. The caller
/// supplies the existing playback-preparation queue and pins this owner in Core
/// until host quiescence and native C reset precede cancelAndWait().
final class RuntimeLoopPlanningSession: @unchecked Sendable {
    enum RefreshRefusal: String, Error, Sendable {
        case stoppedReloadRequired, incompatibleScope, incompatiblePatternShape, reusedSourceGeneration
    }
    enum RefreshStatus: Sendable {
        case pending(serial: UInt64)
        case preparing(serial: UInt64, boundaryFrame: UInt64)
        case published(serial: UInt64, boundaryFrame: UInt64)
        case admitted(serial: UInt64, scope: RuntimeLoopNativeScope, boundaryFrame: UInt64)
        case refused(serial: UInt64, reason: RefreshRefusal)
    }
    struct RefreshReceipt: @unchecked Sendable {
        let serial: UInt64
        let scope: RuntimeLoopNativeScope
        let boundaryFrame: UInt64
        let song: PlaybackSong
    }
    private struct RefreshRequest {
        let serial: UInt64
        let song: PlaybackSong
        let scope: RuntimeLoopNativeScope
    }
    // No native pointer owner or old plan is stored here. Two records follow the
    // channel's active/ready slots; both checkpoints are bounded value state.
    private final class BatchStart {
        let scope: RuntimeLoopNativeScope
        let song: PlaybackSong
        let sequence: UInt64
        let startFrame: UInt64
        let endFrame: UInt64
        let start: PlaybackSongUserLoopProducer.ResumeState
        let terminal: PlaybackSongUserLoopProducer.ResumeState
        let boundaries: [PlaybackSongUserLoopProducer.NaturalBoundary]
        let refreshSerial: UInt64?

        // Immutable flat checkpoints share one record instead of widening every
        // worker call frame with copies of both start and terminal values.
        init(scope: RuntimeLoopNativeScope, song: PlaybackSong, sequence: UInt64,
             startFrame: UInt64, endFrame: UInt64, start: PlaybackSongUserLoopProducer.ResumeState,
             terminal: PlaybackSongUserLoopProducer.ResumeState,
             boundaries: [PlaybackSongUserLoopProducer.NaturalBoundary], refreshSerial: UInt64?) {
            self.scope = scope; self.song = song; self.sequence = sequence
            self.startFrame = startFrame; self.endFrame = endFrame
            self.start = start; self.terminal = terminal; self.boundaries = boundaries
            self.refreshSerial = refreshSerial
        }
    }
    private let refreshRequestSerial = Atomic<UInt64>(0)
    // Protected by condition; each replacement coalesces one revocable source value.
    private var refreshRequest: RefreshRequest?
    private var refreshStatus: RefreshStatus?
    private var admittedRefresh: RefreshReceipt?
    private struct PublishedRefresh { let receipt: RefreshReceipt; let sequence: UInt64 }
    private var publishedRefresh: PublishedRefresh? // Condition-protected, installed before native publication.
    private var latestRequestedSourceGeneration: UInt64 = 0
    // Worker only. These are bounded start/terminal values, never an old plan ledger.
    private var batchStarts = [BatchStart]()
    private var productionScope: RuntimeLoopNativeScope?
    private var maximumObservedPipelineNanos: UInt64 = 0
    private var maximumObservedReplayNanos: UInt64 = 0
    private var lastOrdinaryPipelineNanos: UInt64 = 0, lastOrdinaryRowCount = 1
    private var readinessSerial: UInt64 = 0, readinessNanos: UInt64 = 0, readinessFrameAdvance: UInt64 = 0
    private var attemptedRefresh: (serial: UInt64, activeSequence: UInt64, boundaryFrame: UInt64)?
    private var pendingCutover: (serial: UInt64, sequence: UInt64, frame: UInt64)?
    private struct PrevalidatedRefresh {
        let serial: UInt64
        let sourceGeneration: UInt64
        let proof: PlaybackSongUserLoopProducer.RefreshCatalogProof
    }
    private var prevalidatedRefresh: PrevalidatedRefresh? // Worker-only, latest request/source only.

    enum Stage: String, Sendable { case validation, producer, nativePreparation, publication, initialAdmission }
    struct Failure: Error, Sendable {
        let stage: Stage
        let message: String
    }
    struct Preparation: @unchecked Sendable {
        let channel: RuntimeLoopNativeTwoSlotChannel
        let scope: RuntimeLoopNativeScope
        let trackerChannelCount: Int
        let firstBatchEndFrame: UInt64
        let preparedThroughFrame: UInt64
    }
    enum PreparationResult: @unchecked Sendable {
        case pending, ready(Preparation), failed(Failure), cancelled
    }
    struct ProductionMeasurement: Sendable {
        let sequence: UInt64
        let warmup: Bool
        let rowCount: Int
        let commandCount: Int
        let preparedBirthCount: Int
        let ownedPODBytes: Int
        let milliseconds: Double
        let remainingHorizonBeforeFrames: Int64?
        let remainingHorizonAfterFrames: Int64?
    }
    struct RefreshMeasurement: Sendable {
        enum Outcome: String, Sendable { case published, admitted, superseded, deadlineAborted, refused, failed }
        let requestSerial: UInt64
        let activeSequence: UInt64
        let boundaryFrame: UInt64
        let outcome: Outcome
        let milliseconds: Double
        let remainingMandatoryHorizonFrames: Int64?
        var startedAtNativeFrame: UInt64? = nil
        var readyAtNativeFrame: UInt64? = nil
        var publishedAtNativeFrame: UInt64? = nil
        var firstReadyVisibleBoundaryFrame: UInt64? = nil
        var admittedBoundaryFrame: UInt64? = nil
    }
    struct CatalogValidationMeasurement: Sendable {
        enum Outcome: String, Sendable { case accepted, superseded, refused }
        let requestSerial: UInt64
        let activeSequence: UInt64
        let milliseconds: Double
        let outcome: Outcome
        let remainingHorizonBeforeFrames: Int64?
        let remainingHorizonAfterFrames: Int64?
    }
    enum Diagnostic: Sendable {
        case refreshCatalogValidated(CatalogValidationMeasurement)
        case produced(ProductionMeasurement)
        case refreshPrepared(RefreshMeasurement)
        case failed(Failure, afterStart: Bool)
    }
    typealias Diagnostics = @Sendable (Diagnostic) -> Void
    typealias NativeFrame = @Sendable () -> UInt64?
    typealias NativeQuantum = @Sendable () -> Int?

    let channel: RuntimeLoopNativeTwoSlotChannel
    let scope: RuntimeLoopNativeScope
    private var song: PlaybackSong // Worker only after initialization; changes on prepared refresh.
    private let origin: PlaybackPosition
    private let workerQueue: DispatchQueue
    private let workerKey = DispatchSpecificKey<UInt8>()
    private let horizonFrames: Int
    private let maximumRows: Int
    private let refreshPublicationGuardFrames: Int
    private let finiteSongTailFrames: Int
    private let diagnostics: Diagnostics?
    private let onInitialPreparation: (@Sendable (PreparationResult) -> Void)?
    private let cancellation = Atomic(false)
    private let shutdownComplete = Atomic(false)
    private let acknowledgedRawUniqueIDCount = Atomic(UInt64(0))
    private let condition = NSCondition()
    // These two snapshots contain no mutable musical scratch or native pointer owner.
    private var preparationResult = PreparationResult.pending
    private var failureSnapshot: Failure?

    // Access only on workerQueue. Native pointer ownership stays in the two slots;
    // no Batch/semantic-plan ledger or third pending native owner is retained here.
    private var producer: PlaybackSongUserLoopProducer?
    private var cache: CSoftwareMixerSharedSamplePayloadCache?
    private var timer: DispatchSourceTimer?
    private var nativeFrame: NativeFrame?
    private var nativeQuantum: NativeQuantum?
    private var trackerChannelCount = 0
    private var latestPublishedEndFrame: UInt64 = 0
    private var productionStarted = false
    private var productionFailed = false
    private var shutdown = false
    private var consumedRawEventIDs = Set<Int>() // Worker only; bounded by the batch-local ID domain.

    /// Starts asynchronous warmup on the supplied serial playback-preparation queue.
    /// horizonFrames is an explicit caller policy; maximumRows remains bounded to 512.
    /// The optional initial result fires once after unlocking. Its caller must
    /// weakly capture its owner and revalidate transport intent before admission.
    init(song: PlaybackSong, origin: PlaybackPosition, scope: RuntimeLoopNativeScope,
         workerQueue: DispatchQueue, horizonFrames: Int, maximumRows: Int = 128,
         refreshPublicationGuardFrames: Int = 0, finiteSongTailFrames: Int = 0,
         diagnostics: Diagnostics? = nil,
         onInitialPreparation: (@Sendable (PreparationResult) -> Void)? = nil) {
        self.song = song; self.origin = origin; self.scope = scope
        self.workerQueue = workerQueue; self.horizonFrames = horizonFrames
        self.maximumRows = maximumRows; self.diagnostics = diagnostics
        self.refreshPublicationGuardFrames = refreshPublicationGuardFrames
        self.finiteSongTailFrames = finiteSongTailFrames
        self.onInitialPreparation = onInitialPreparation
        channel = RuntimeLoopNativeTwoSlotChannel(scope: scope)
        workerQueue.setSpecific(key: workerKey, value: 1)
        workerQueue.async { [self] in warmupOnWorker() }
    }

    var isCancelled: Bool { cancellation.load(ordering: .acquiring) }

    /// Coalesces one source snapshot without queueing closures that retain older songs.
    /// Incompatible live edits return a typed Stop/retry result for Engine service.
    @discardableResult
    func requestEditableRefresh(song: PlaybackSong, scope proposed: RuntimeLoopNativeScope) -> UInt64? {
        guard !isCancelled else { return nil }
        var previous = refreshRequestSerial.load(ordering: .acquiring)
        while true {
            guard previous < .max else { return nil }
            let claim = refreshRequestSerial.compareExchange(expected: previous, desired: previous + 1,
                ordering: .acquiringAndReleasing)
            if claim.exchanged { break }
            previous = claim.original
        }
        let serial = previous + 1
        // Callback rejects an obsolete candidate immediately, even if worker/UI is delayed.
        channel.authorizeRefreshRequest(serial)
        condition.lock()
        if proposed.documentHigh != scope.documentHigh || proposed.documentLow != scope.documentLow ||
            proposed.transportEpoch != scope.transportEpoch || proposed.sampleRateBits != scope.sampleRateBits ||
            proposed.semanticVersion != scope.semanticVersion || proposed.linearFrequencyMode != scope.linearFrequencyMode ||
            proposed.transportKind != scope.transportKind ||
            proposed.order != scope.order || proposed.pattern != scope.pattern ||
            proposed.firstRow != scope.firstRow || proposed.lastRow != scope.lastRow {
            refreshRequest = nil
            refreshStatus = .refused(serial: serial, reason: .incompatibleScope)
        } else if scope.transportKind == .finiteSong {
            refreshRequest = nil
            refreshStatus = .refused(serial: serial, reason: .stoppedReloadRequired)
        } else if proposed.sourceGeneration <= max(scope.sourceGeneration, latestRequestedSourceGeneration) {
            refreshRequest = nil
            refreshStatus = .refused(serial: serial, reason: .reusedSourceGeneration)
        } else {
            latestRequestedSourceGeneration = proposed.sourceGeneration
            refreshRequest = .init(serial: serial, song: song, scope: proposed)
            refreshStatus = .pending(serial: serial)
        }
        condition.unlock()
        workerQueue.async { [weak self] in self?.serviceProductionOnWorker() }
        return serial
    }

    /// Fixed status only; MainActor updates document ownership after native admission,
    /// or performs the explicit stopped reload/retry required by a typed refusal.
    func latestEditableRefreshStatus() -> RefreshStatus? {
        condition.lock(); defer { condition.unlock() }
        return refreshStatus
    }

    /// Latest actual native admission, even if another desired revision superseded it.
    /// One COW source value is retained; no receipt/history chain is accumulated.
    func latestAdmittedEditableRefresh() -> RefreshReceipt? {
        condition.lock(); defer { condition.unlock() }
        return acknowledgedPublishedRefreshLocked() ?? admittedRefresh
    }

    /// Called under condition. Native receipt, never worker/UI timing, authorizes the source.
    private func acknowledgedPublishedRefreshLocked() -> RefreshReceipt? {
        guard let published = publishedRefresh, let frontier = channel.latestExecutionFrontier else { return nil }
        let value = published.receipt
        let justAdmitted = frontier.admittedSourceGeneration == value.scope.sourceGeneration &&
            frontier.admittedSequence == published.sequence && frontier.frame == value.boundaryFrame
        let alreadyExecuted = frontier.sourceGeneration == value.scope.sourceGeneration &&
            frontier.sequence >= published.sequence && frontier.frame >= value.boundaryFrame
        return justAdmitted || alreadyExecuted ? value : nil
    }

    private func latestRefreshOnWorker() -> RefreshRequest? {
        condition.lock(); defer { condition.unlock() }
        return refreshRequest
    }

    private func setRefreshStatusOnWorker(_ status: RefreshStatus, serial: UInt64) {
        condition.lock(); defer { condition.unlock() }
        guard refreshRequestSerial.load(ordering: .acquiring) == serial else { return }
        refreshStatus = status
    }

    private func refuseRefreshOnWorker(_ request: RefreshRequest, reason: RefreshRefusal) {
        prevalidatedRefresh = nil
        condition.lock(); defer { condition.unlock() }
        guard refreshRequest?.serial == request.serial else { return }
        refreshRequest = nil
        refreshStatus = .refused(serial: request.serial, reason: reason)
        // Keep normal delivery safe until Engine observes the typed refusal and Stops.
        // Refusal is never reported as a planning underrun or a successful stale refresh.
    }

    /// Live publication includes retired batches only; final Stop also merges active partial bits.
    var acknowledgedRawUniqueEventCount: UInt64 { acknowledgedRawUniqueIDCount.load(ordering: .acquiring) }

    /// Copies the final legacy raw-ID union after producer join, never while callback writes.
    func consumedRawEventIDsAfterShutdown() -> Set<Int> {
        precondition(shutdownComplete.load(ordering: .acquiring))
        return consumedRawEventIDs
    }

    /// Reads or briefly waits for an immutable preparation result. This function
    /// never builds work, invokes callbacks, pumps a run loop, or acquires a render lock.
    func waitForPreparation(timeout: TimeInterval = 0) -> PreparationResult {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: max(0, timeout))
        while case .pending = preparationResult, !isCancelled, timeout > 0 {
            if !condition.wait(until: deadline) { break }
        }
        return isCancelled ? .cancelled : preparationResult
    }

    /// Service may inspect this diagnostic while the native cursor owns the actual
    /// missing-boundary retirement. A production failure does not grant early Stop.
    func latestProductionFailure() -> Failure? {
        condition.lock(); defer { condition.unlock() }
        return failureSnapshot
    }

    /// Starts the 5ms refill cadence on the same serial worker. The optional frame
    /// reader must read a published atomic scalar, such as a weak Core's native frame.
    func startProduction(nativeFrame: NativeFrame? = nil, nativeQuantum: NativeQuantum? = nil) {
        workerQueue.async { [weak self] in
            guard let self, !self.isCancelled, !self.shutdown, !self.productionStarted,
                  !self.productionFailed, self.isPreparedOnWorker() else { return }
            self.nativeFrame = nativeFrame
            self.nativeQuantum = nativeQuantum
            self.productionStarted = true
            let timer = DispatchSource.makeTimerSource(queue: self.workerQueue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.serviceProductionOnWorker() }
            self.timer = timer
            timer.resume()
        }
    }

    /// Revokes future construction immediately. Native cancellation/quiescence is
    /// owned by Backend; this atomic flag never releases callback-borrowed storage.
    func cancel() {
        cancellation.store(true, ordering: .releasing)
        channel.revoke() // Atomic publication revocation; borrowed owners remain pinned.
        condition.lock()
        let wasPending: Bool
        if case .pending = preparationResult { wasPending = true } else { wasPending = false }
        preparationResult = .cancelled
        condition.broadcast()
        condition.unlock()
        if wasPending { onInitialPreparation?(.cancelled) }
    }

    /// Call after the host is quiescent and Core has reset C voices. Joining the
    /// serial worker precedes channel retirement and generation PCM-cache release.
    func cancelAndWait() {
        cancel()
        guard !shutdownComplete.load(ordering: .acquiring) else { return }
        if DispatchQueue.getSpecific(key: workerKey) != nil { shutdownOnWorker() }
        else { workerQueue.sync { [self] in shutdownOnWorker() } }
    }

    private func isPreparedOnWorker() -> Bool {
        condition.lock(); defer { condition.unlock() }
        if case .ready = preparationResult { return true }
        return false
    }

    private func warmupOnWorker() {
        guard !isCancelled, !shutdown else { return }
        do {
            let rate = Double(bitPattern: scope.sampleRateBits)
            guard horizonFrames > 0, (1...512).contains(maximumRows), refreshPublicationGuardFrames >= 0,
                  finiteSongTailFrames >= 0,
                  rate.isFinite, rate > 0, scope.sourceGeneration > 0, scope.transportEpoch > 0,
                  scope.firstRow >= 0, scope.lastRow >= scope.firstRow,
                  origin.orderIndex == scope.order, origin.patternIndex == scope.pattern,
                  song.usesLinearFrequencyTable == scope.linearFrequencyMode,
                  let pattern = song.pattern(for: scope.order), pattern.index == scope.pattern,
                  pattern.rows.indices.contains(origin.rowIndex),
                  !pattern.rows.isEmpty,
                  pattern.rows.allSatisfy({ (scope.firstRow...scope.lastRow).contains($0.index) }) else {
                throw Failure(stage: .validation, message: "Invalid native preparation scope")
            }
            trackerChannelCount = scope.transportKind == .finiteSong
                ? song.patternsByIndex.values.reduce(0) { count, pattern in
                    max(count, pattern.rows.reduce(0) { max($0, $1.cells.count) })
                }
                : pattern.rows.reduce(0) { max($0, $1.cells.count) }
            guard trackerChannelCount > 0 else {
                throw Failure(stage: .validation, message: "Selected pattern has no tracker channels")
            }
            productionScope = scope
            cache = CSoftwareMixerSharedSamplePayloadCache()
            do {
                producer = try PlaybackSongUserLoopProducer(song: song, initialPosition: origin,
                    sampleRate: rate, sourceGeneration: scope.sourceGeneration, transportEpoch: scope.transportEpoch,
                    mode: scope.transportKind == .finiteSong ? .finiteSong : .explicitLoop,
                    terminalTailFrames: scope.transportKind == .finiteSong ? finiteSongTailFrames : 0)
            } catch {
                throw Failure(stage: .producer, message: String(describing: error))
            }
            guard let firstReservation = channel.reserve() else {
                throw Failure(stage: .publication, message: "First Loop slot unavailable")
            }
            let firstEnd = try produceAndPublishOnWorker(firstReservation, warmup: true)
            guard !isCancelled else { return }
            // No host callback can run before Backend receives ready. Admit first
            // now so the second reserved slot is the sole prepared successor.
            guard case .admitted = channel.begin(at: 0) else {
                throw Failure(stage: .initialAdmission, message: "Initial Loop batch was not admitted at frame zero")
            }
            var preparedThrough = firstEnd
            if producer?.exportResumeState().terminalStopReason == nil {
                guard let secondReservation = channel.reserve() else {
                    throw Failure(stage: .publication, message: "Successor Loop slot unavailable")
                }
                preparedThrough = try produceAndPublishOnWorker(secondReservation, warmup: true)
            }
            guard !isCancelled else { return }
            let ready = Preparation(channel: channel, scope: scope,
                trackerChannelCount: trackerChannelCount, firstBatchEndFrame: firstEnd,
                preparedThroughFrame: preparedThrough)
            condition.lock()
            let publish = !isCancelled
            if publish { preparationResult = .ready(ready) }
            condition.broadcast()
            condition.unlock()
            if publish { onInitialPreparation?(.ready(ready)) }
        } catch {
            if !isCancelled { failOnWorker(error, afterStart: false) }
        }
    }

    private func serviceProductionOnWorker() {
        guard !isCancelled, !shutdown, !productionFailed else { return }
        // Exact native acknowledgement makes retired owners releasable here.
        // A reservation must exist before any traversal/semantic/native work starts.
        reconcileExecutionOnWorker()
        channel.reclaimRetired(beforeRelease: { [self] in collectRetiredBatchOnWorker($0) })
        reconcileExecutionOnWorker()
        do {
            switch try serviceEditableRefreshOnWorker() {
            case .ordinary: break
            case .handled: return
            case let .restore(active, reservation, completion):
                defer { completion?() }
                try restoreOrdinarySuccessorOnWorker(active: active, reservation: reservation)
                return
            }
            if producer?.exportResumeState().terminalStopReason != nil { return }
            guard let reservation = channel.reserve() else { return }
            if let active = activeStartOnWorker(), let producer {
                let state = producer.exportResumeState()
                if state.sequence != active.sequence || state.sourceGeneration != active.scope.sourceGeneration {
                    try restoreOrdinarySuccessorOnWorker(active: active, reservation: reservation)
                    return
                }
            }
            _ = try produceAndPublishOnWorker(reservation, warmup: false)
        }
        catch {
            if !isCancelled { failOnWorker(error, afterStart: true) }
        }
    }

    private func remainingHorizonOnWorker() -> Int64? {
        guard let frame = nativeFrame?() else { return nil }
        if latestPublishedEndFrame >= frame {
            return Int64(clamping: latestPublishedEndFrame - frame)
        }
        let delta = frame - latestPublishedEndFrame
        return delta > UInt64(Int64.max) ? Int64.min : -Int64(delta)
    }

    /// The reservation is owned on entry and is discarded on every unpublished path.
    @inline(never)
    private func produceAndPublishOnWorker(_ reservation: RuntimeLoopNativeTwoSlotChannel.Reservation,
                                           warmup: Bool) throws -> UInt64 {
        var published = false
        defer { if !published { channel.discard(reservation) } }
        guard !isCancelled, let producer, let cache else {
            throw Failure(stage: .producer, message: "Loop construction cancelled or unavailable")
        }
        let started = DispatchTime.now().uptimeNanoseconds
        let remainingBefore = remainingHorizonOnWorker()
        let scope = productionScope ?? self.scope
        let start = producer.exportResumeState()
        let batch: PlaybackSongUserLoopProducer.Batch
        do {
            batch = try producer.next(minimumHorizonFrames: horizonFrames, maximumRows: maximumRows,
                minimumNaturalBoundaryTailFrames: Int(clamping: fallbackReserveFrames(rate: Double(bitPattern: scope.sampleRateBits))),
                isCancelled: { [weak self] in self?.isCancelled ?? true })
        } catch { throw Failure(stage: .producer, message: String(describing: error)) }
        guard !isCancelled else { throw Failure(stage: .producer, message: "Loop construction cancelled") }
        let storage: RuntimeLoopNativeBatchStorage
        do {
            storage = try .init(batch: batch, scope: scope, trackerChannelCount: trackerChannelCount,
                cache: cache, recordsCategories: diagnostics != nil,
                sourceSong: scope.transportKind == .finiteSong ? song : nil)
        } catch { throw Failure(stage: .nativePreparation, message: String(describing: error)) }
        guard !isCancelled else { throw Failure(stage: .nativePreparation, message: "Loop construction cancelled") }
        guard channel.publish(reservation, header: storage.header, retaining: storage) else {
            throw Failure(stage: .publication, message: "Loop publication rejected")
        }
        published = true
        batchStarts.append(makeBatchStartOnWorker(batch: batch, storage: storage, song: song,
            scope: scope, start: start, terminal: producer.exportResumeState()))
        lastOrdinaryPipelineNanos = DispatchTime.now().uptimeNanoseconds - started
        lastOrdinaryRowCount = max(1, storage.rowTimings.count)
        maximumObservedPipelineNanos = max(maximumObservedPipelineNanos, lastOrdinaryPipelineNanos)
        latestPublishedEndFrame = storage.header.runtimeEndFrame
        diagnostics?(.produced(.init(sequence: batch.sequence, warmup: warmup,
            rowCount: storage.rowTimings.count, commandCount: storage.header.commandCount,
            preparedBirthCount: storage.preparedBirthCount, ownedPODBytes: storage.ownedPODBytes,
            milliseconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000,
            remainingHorizonBeforeFrames: remainingBefore,
            remainingHorizonAfterFrames: remainingHorizonOnWorker())))
        return storage.header.runtimeEndFrame
    }

    private enum RefreshAborted: Error { case supersededOrDeadline }

    /// Reconciles only native-owned acknowledgements. No UI timer or speculative
    /// producer terminal checkpoint advances the active state used for an edit.
    private func reconcileExecutionOnWorker() {
        condition.lock()
        if let actual = acknowledgedPublishedRefreshLocked() { admittedRefresh = actual }
        condition.unlock()
        guard let frontier = channel.latestExecutionFrontier else { return }
        if let pending = pendingCutover,
           frontier.admittedSequence == pending.sequence,
           let admitted = batchStarts.first(where: { $0.sequence == pending.sequence &&
               $0.scope.sourceGeneration == frontier.admittedSourceGeneration }),
           admitted.refreshSerial == pending.serial {
            condition.lock()
            admittedRefresh = .init(serial: pending.serial, scope: admitted.scope,
                boundaryFrame: frontier.frame, song: admitted.song)
            if refreshRequest?.serial == pending.serial { refreshRequest = nil }
            if refreshRequestSerial.load(ordering: .acquiring) == pending.serial {
                refreshStatus = .admitted(serial: pending.serial, scope: admitted.scope,
                    boundaryFrame: frontier.frame)
            }
            condition.unlock()
            diagnostics?(.refreshPrepared(.init(requestSerial: pending.serial,
                activeSequence: frontier.sequence, boundaryFrame: frontier.frame, outcome: .admitted,
                milliseconds: 0, remainingMandatoryHorizonFrames: nil,
                firstReadyVisibleBoundaryFrame: frontier.firstNaturalBoundaryAfterReady == 0 ? nil : frontier.firstNaturalBoundaryAfterReady,
                admittedBoundaryFrame: frontier.frame)))
            pendingCutover = nil
            attemptedRefresh = nil
            prevalidatedRefresh = nil
        }
        // A prefix acknowledgement retires this record too; the frontier's actual
        // frame/token, not its old terminal checkpoint, authenticated the next start.
    }

    private func activeStartOnWorker() -> BatchStart? {
        if let frontier = channel.latestExecutionFrontier {
            guard frontier.admittedSequence > 0 else { return nil }
            return batchStarts.first { $0.sequence == frontier.admittedSequence &&
                $0.scope.sourceGeneration == frontier.admittedSourceGeneration }
        }
        return batchStarts.first { $0.sequence == 1 }
    }

    private func framesForObservedNanos(_ nanos: UInt64, rate: Double) -> UInt64 {
        let frames = (Double(nanos) * rate / 1_000_000_000).rounded(.up)
        return frames.isFinite && frames < Double(UInt64.max) ? UInt64(max(0, frames)) : .max
    }

    /// Conservatively protects the mandatory fallback deadline, never chooses an edit B.
    private func fallbackReserveFrames(rate: Double) -> UInt64 {
        let work = framesForObservedNanos(maximumObservedPipelineNanos, rate: rate)
        let quantum = UInt64(max(refreshPublicationGuardFrames, max(0, nativeQuantum?() ?? 0)))
        let cadence = UInt64((rate * 0.005).rounded(.up))
        let a = work.addingReportingOverflow(quantum), b = a.partialValue.addingReportingOverflow(cadence)
        return a.overflow || b.overflow ? .max : b.partialValue
    }

    /// A request learns actual work/clock advance when an early attempt misses. Cold
    /// PCM upload outliers protect fallback but do not delay every later warm edit.
    private func readinessEstimateFrames(rows: Int, rate: Double) -> UInt64 {
        let steady = lastOrdinaryPipelineNanos > 0 ? lastOrdinaryPipelineNanos : maximumObservedPipelineNanos
        let perRow = steady / UInt64(max(1, lastOrdinaryRowCount))
        let replay = perRow.multipliedReportingOverflow(by: UInt64(max(1, rows)))
        let estimate = steady.addingReportingOverflow(replay.partialValue)
        guard !replay.overflow, !estimate.overflow else { return .max }
        return max(framesForObservedNanos(max(estimate.partialValue, readinessNanos), rate: rate), readinessFrameAdvance)
    }

    private func refreshIsCurrent(_ serial: UInt64) -> Bool {
        !isCancelled && refreshRequestSerial.load(ordering: .acquiring) == serial
    }

    private func validateRefreshShape(_ request: RefreshRequest, active: BatchStart) -> RefreshRefusal? {
        // Initial-tempo replacement uses the existing stopped reload path. Live Fxx
        // cell edits remain ordinary pattern changes and retain executed warm timing.
        guard request.song.initialTiming == active.song.initialTiming else { return .stoppedReloadRequired }
        guard request.scope.sourceGeneration > active.scope.sourceGeneration,
              request.scope.documentHigh == active.scope.documentHigh,
              request.scope.documentLow == active.scope.documentLow,
              request.scope.transportEpoch == active.scope.transportEpoch,
              request.scope.sampleRateBits == active.scope.sampleRateBits,
              request.scope.semanticVersion == active.scope.semanticVersion,
              request.scope.transportKind == active.scope.transportKind,
              request.scope.linearFrequencyMode == active.scope.linearFrequencyMode,
              request.scope.order == active.scope.order, request.scope.pattern == active.scope.pattern,
              request.song.usesLinearFrequencyTable == active.song.usesLinearFrequencyTable else {
            return .incompatibleScope
        }
        guard let old = active.song.pattern(for: active.scope.order),
              let new = request.song.pattern(for: request.scope.order), new.index == old.index,
              new.rows.count == old.rows.count,
              zip(new.rows, old.rows).allSatisfy({ pair in
                  pair.0.index == pair.1.index && pair.0.cells.count == pair.1.cells.count
              }) else {
            return .incompatiblePatternShape
        }
        return nil // Deep instrument/sample/keymap equality is checked once by Producer init.
    }

    private enum RefreshServiceResult {
        case ordinary, handled
        case restore(BatchStart, RuntimeLoopNativeTwoSlotChannel.Reservation, (() -> Void)?)
    }

    /// Return reserved recovery work so this frame retires before interpreting rows.
    /// Keeping both frames live exhausts a normal worker stack under ASan.
    private func serviceEditableRefreshOnWorker() throws -> RefreshServiceResult {
        guard let active = activeStartOnWorker(),
              let frame = nativeFrame?(), frame >= active.startFrame, frame < active.endFrame,
              let cache else { return .ordinary }
        if let validated = prevalidatedRefresh,
           validated.serial != refreshRequestSerial.load(ordering: .acquiring) ||
            validated.sourceGeneration != active.scope.sourceGeneration {
            prevalidatedRefresh = nil
        }
        if let pending = pendingCutover, !refreshIsCurrent(pending.serial) {
            // A typed refusal also supersedes an older candidate; keep the old Loop
            // safe while MainActor receives its explicit Stop/retry reason.
            guard let reservation = channel.reserve() ?? channel.retractReady() else { return .handled }
            pendingCutover = nil
            batchStarts.removeAll { $0.sequence > active.sequence }
            latestPublishedEndFrame = active.endFrame
            return .restore(active, reservation, nil)
        }
        guard let request = latestRefreshOnWorker() else {
            prevalidatedRefresh = nil
            return .ordinary
        }
        if let refusal = validateRefreshShape(request, active: active) {
            refuseRefreshOnWorker(request, reason: refusal)
            return .ordinary
        }
        if let pending = pendingCutover {
            if !batchStarts.contains(where: { $0.sequence == pending.sequence }) {
                // A rejected obsolete candidate may already have retired off audio.
                pendingCutover = nil
                if let reservation = channel.reserve() {
                    return .restore(active, reservation, nil)
                }
                return .ordinary
            }
            if pending.serial == request.serial && frame < pending.frame { return .handled }
            // A new request or a missed optional B can retract only an unclaimed publication.
            guard let reservation = channel.reserve() ?? channel.retractReady() else { return .handled }
            pendingCutover = nil
            batchStarts.removeAll { $0.sequence > active.sequence }
            latestPublishedEndFrame = active.endFrame
            return .restore(active, reservation, nil)
        }
        if prevalidatedRefresh == nil {
            // Keep the ordinary ready owner published for all potentially PCM-wide
            // equality work. No reservation/retraction or musical replay has begun.
            let started = DispatchTime.now().uptimeNanoseconds
            let remainingBefore = remainingHorizonOnWorker()
            var outcome = CatalogValidationMeasurement.Outcome.refused
            defer {
                diagnostics?(.refreshCatalogValidated(.init(requestSerial: request.serial,
                    activeSequence: active.sequence,
                    milliseconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000,
                    outcome: outcome, remainingHorizonBeforeFrames: remainingBefore,
                    remainingHorizonAfterFrames: remainingHorizonOnWorker())))
            }
            do {
                let proof = try PlaybackSongUserLoopProducer.prevalidateRefresh(song: request.song,
                    resuming: active.start, sourceGeneration: request.scope.sourceGeneration)
                guard refreshIsCurrent(request.serial) else { outcome = .superseded; return .handled }
                prevalidatedRefresh = .init(serial: request.serial,
                    sourceGeneration: active.scope.sourceGeneration, proof: proof)
                outcome = .accepted
            } catch {
                if refreshIsCurrent(request.serial) {
                    refuseRefreshOnWorker(request, reason: .stoppedReloadRequired)
                } else { outcome = .superseded }
                return .handled
            }
            // Validation may outlast an old active interval. Re-read actual admission,
            // current frame and observed quantum in a fresh service pass before retracting.
            workerQueue.async { [weak self] in self?.serviceProductionOnWorker() }
            return .handled
        }
        let rate = Double(bitPattern: active.scope.sampleRateBits)
        if readinessSerial != request.serial {
            readinessSerial = request.serial; readinessNanos = 0; readinessFrameAdvance = 0
        }
        let fallbackReserve = fallbackReserveFrames(rate: rate)
        guard active.endFrame > frame, fallbackReserve < active.endFrame - frame,
              let boundary = active.boundaries.first(where: { candidate in
                  guard candidate.frame >= 0 else { return false }
                  let absolute = UInt64(candidate.frame)
                  let retryFloor = attemptedRefresh.flatMap { previous -> UInt64? in
                      previous.serial == request.serial && previous.activeSequence == active.sequence ? previous.boundaryFrame : nil
                  } ?? 0
                  let work = readinessEstimateFrames(rows: candidate.rowCount, rate: rate)
                  return absolute > max(frame, retryFloor) && absolute - frame > work &&
                      absolute < active.endFrame && active.endFrame - absolute > fallbackReserve
              }) else { return .ordinary }
        // Retraction first wins ownership of the exact ready publication. It never
        // releases a slot claimed by the callback, even during the claim/header gap.
        guard let reservation = channel.reserve() ?? channel.retractReady() else { return .ordinary }
        attemptedRefresh = (request.serial, active.sequence, UInt64(boundary.frame))
        batchStarts.removeAll { $0.sequence > active.sequence }
        latestPublishedEndFrame = active.endFrame
        let boundaryFrame = UInt64(boundary.frame)
        setRefreshStatusOnWorker(.preparing(serial: request.serial, boundaryFrame: boundaryFrame), serial: request.serial)
        var published = false
        defer { if !published { channel.discard(reservation) } }
        let started = DispatchTime.now().uptimeNanoseconds
        var outcome = RefreshMeasurement.Outcome.failed
        var readyFrame: UInt64?, publicationFrame: UInt64?
        let finishAttempt = { [self, requestSerial = request.serial,
            activeSequence = active.sequence, activeEndFrame = active.endFrame] in
            let elapsed = DispatchTime.now().uptimeNanoseconds - started
            if readinessSerial == requestSerial {
                readinessNanos = max(readinessNanos, elapsed)
                if let now = nativeFrame?(), now >= frame { readinessFrameAdvance = max(readinessFrameAdvance, now - frame) }
            }
            let mandatoryRemaining: Int64?
            if let now = nativeFrame?() {
                mandatoryRemaining = activeEndFrame >= now ? Int64(clamping: activeEndFrame - now) :
                    -Int64(clamping: now - activeEndFrame)
            } else { mandatoryRemaining = nil }
            diagnostics?(.refreshPrepared(.init(requestSerial: requestSerial,
                activeSequence: activeSequence, boundaryFrame: boundaryFrame, outcome: outcome,
                milliseconds: Double(elapsed) / 1_000_000,
                remainingMandatoryHorizonFrames: mandatoryRemaining, startedAtNativeFrame: frame,
                readyAtNativeFrame: readyFrame, publishedAtNativeFrame: publicationFrame)))
        }
        var completesAfterRecovery = false
        defer { if !completesAfterRecovery { finishAttempt() } }
        let fallbackDeadline = active.endFrame - fallbackReserve
        let abort = { [weak self] in
            guard let self, self.refreshIsCurrent(request.serial) else { return true }
            guard let now = self.nativeFrame?() else { return true }
            return now >= min(boundaryFrame, fallbackDeadline)
        }
        do {
            guard !abort(), let newPattern = request.song.pattern(for: request.scope.order),
                  let nextRow = newPattern.rows.first else { throw RefreshAborted.supersededOrDeadline }
            // Function scope ends the old prefix graph before new semantic/native construction.
            let resume = try replayEditedPrefixOnWorker(active: active, until: boundaryFrame,
                nextRow: nextRow, isCancelled: abort)
            guard !abort() else { throw RefreshAborted.supersededOrDeadline }
            let nativePreparationStarted = DispatchTime.now().uptimeNanoseconds
            guard let validated = prevalidatedRefresh, validated.serial == request.serial,
                  validated.sourceGeneration == active.scope.sourceGeneration else {
                throw RefreshAborted.supersededOrDeadline
            }
            let edited = try PlaybackSongUserLoopProducer(resuming: resume, validatedRefresh: validated.proof)
            let start = edited.exportResumeState()
            let batch = try edited.next(minimumHorizonFrames: horizonFrames, maximumRows: maximumRows,
                minimumNaturalBoundaryTailFrames: Int(clamping: fallbackReserve), isCancelled: abort)
            guard batch.sequence == active.sequence + 1, batch.startFrame == Int(boundaryFrame),
                  !abort() else { throw RefreshAborted.supersededOrDeadline }
            let cutover = RuntimeLoopNativeEarlyCutover(previousScope: active.scope,
                predecessorSequence: active.sequence, boundaryFrame: boundaryFrame,
                boundaryStateToken: boundary.stateToken, requestSerial: request.serial)
            let storage = try RuntimeLoopNativeBatchStorage(batch: batch, scope: request.scope,
                trackerChannelCount: trackerChannelCount, cache: cache,
                recordsCategories: diagnostics != nil, earlyCutover: cutover)
            readyFrame = nativeFrame?()
            publicationFrame = readyFrame
            guard refreshIsCurrent(request.serial), (nativeFrame?() ?? .max) < boundaryFrame else {
                throw RefreshAborted.supersededOrDeadline
            }
            // Freeze the exact source before callback may win admission. Main/lifecycle
            // readers can authenticate this one candidate directly against native frontier.
            condition.lock()
            publishedRefresh = .init(receipt: .init(serial: request.serial, scope: request.scope,
                boundaryFrame: boundaryFrame, song: request.song), sequence: batch.sequence)
            condition.unlock()
            guard channel.publish(reservation, header: storage.header, retaining: storage) else {
                throw RefreshAborted.supersededOrDeadline
            }
            published = true
            outcome = .published
            maximumObservedPipelineNanos = max(maximumObservedPipelineNanos,
                DispatchTime.now().uptimeNanoseconds - nativePreparationStarted)
            batchStarts.append(makeBatchStartOnWorker(batch: batch, storage: storage, song: request.song,
                scope: request.scope, start: start, terminal: edited.exportResumeState(), refreshSerial: request.serial))
            producer = edited; song = request.song; productionScope = request.scope
            latestPublishedEndFrame = storage.header.runtimeEndFrame
            pendingCutover = (request.serial, batch.sequence, boundaryFrame)
            setRefreshStatusOnWorker(.published(serial: request.serial, boundaryFrame: boundaryFrame), serial: request.serial)
            diagnostics?(.produced(.init(sequence: batch.sequence, warmup: false,
                rowCount: storage.rowTimings.count, commandCount: storage.header.commandCount,
                preparedBirthCount: storage.preparedBirthCount, ownedPODBytes: storage.ownedPODBytes,
                milliseconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000,
                remainingHorizonBeforeFrames: Int64(clamping: active.endFrame - frame),
                remainingHorizonAfterFrames: remainingHorizonOnWorker())))
            return .handled
        } catch {
            if let failure = error as? PlaybackSongUserLoopProducer.Failure,
               case .incompatibleRefresh = failure {
                outcome = .refused
                refuseRefreshOnWorker(request, reason: .stoppedReloadRequired)
            } else if let failure = error as? PlaybackSongUserLoopProducer.Failure,
                      case .cancelled = failure {
                outcome = refreshIsCurrent(request.serial) ? .deadlineAborted : .superseded
            } else if !(error is RefreshAborted) && refreshIsCurrent(request.serial) {
                throw error
            }
            if error is RefreshAborted {
                outcome = refreshIsCurrent(request.serial) ? .deadlineAborted : .superseded
            }
            if outcome == .deadlineAborted {
                setRefreshStatusOnWorker(.pending(serial: request.serial), serial: request.serial)
            }
            // Rejected optional work is not a musical stop. Reconstruct the ordinary
            // successor from its exact old terminal checkpoint before the mandatory E.
            channel.discard(reservation)
            if let fallback = channel.reserve() {
                completesAfterRecovery = true
                return .restore(active, fallback, finishAttempt)
            }
            return .handled
        }
    }

    @inline(never)
    private func replayEditedPrefixOnWorker(active: BatchStart, until frame: UInt64,
        nextRow: PlaybackRow, isCancelled: @escaping () -> Bool) throws -> PlaybackSongUserLoopProducer.ResumeState {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            maximumObservedReplayNanos = max(maximumObservedReplayNanos,
                DispatchTime.now().uptimeNanoseconds - started)
        }
        guard frame <= UInt64(Int.max) else { throw RefreshAborted.supersededOrDeadline }
        let replay = try PlaybackSongUserLoopProducer(song: active.song, resuming: active.start,
            sourceGeneration: active.scope.sourceGeneration)
        let prefix = try replay.next(minimumHorizonFrames: Int.max, maximumRows: maximumRows,
            untilFrame: Int(frame), nextRowOverride: nextRow, isCancelled: isCancelled)
        guard prefix.sequence == active.sequence, prefix.endFrame == Int(frame) else {
            throw RefreshAborted.supersededOrDeadline
        }
        return replay.exportResumeState() // No prefix plan/rows escape this call.
    }

    private func restoreOrdinarySuccessorOnWorker(active: BatchStart,
        reservation: RuntimeLoopNativeTwoSlotChannel.Reservation) throws {
        producer = try PlaybackSongUserLoopProducer(song: active.song, resuming: active.terminal,
            sourceGeneration: active.scope.sourceGeneration)
        song = active.song; productionScope = active.scope
        _ = try produceAndPublishOnWorker(reservation, warmup: false)
    }

    private func makeBatchStartOnWorker(batch: PlaybackSongUserLoopProducer.Batch,
        storage: RuntimeLoopNativeBatchStorage, song: PlaybackSong, scope: RuntimeLoopNativeScope,
        start: PlaybackSongUserLoopProducer.ResumeState, terminal: PlaybackSongUserLoopProducer.ResumeState,
        refreshSerial: UInt64? = nil) -> BatchStart {
        let boundaries = storage.naturalBoundaries
        return .init(scope: scope, song: song, sequence: batch.sequence,
            startFrame: storage.header.runtimeStartFrame, endFrame: storage.header.runtimeEndFrame,
            start: start, terminal: terminal, boundaries: boundaries, refreshSerial: refreshSerial)
    }

    private func failOnWorker(_ error: Error, afterStart: Bool) {
        productionFailed = true
        stopTimerOnWorker()
        let failure = error as? Failure ?? Failure(stage: .producer, message: String(describing: error))
        condition.lock()
        failureSnapshot = failure
        let publish: Bool
        if !afterStart, case .pending = preparationResult {
            preparationResult = .failed(failure)
            publish = true
        } else { publish = false }
        condition.broadcast()
        condition.unlock()
        if publish { onInitialPreparation?(.failed(failure)) }
        // Preserve the active/ready owners. The actual native boundary determines
        // missing-successor failure and completes the established C retirement.
        diagnostics?(.failed(failure, afterStart: afterStart))
    }

    private func stopTimerOnWorker() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func collectExecutedRawIDsOnWorker(_ owner: AnyObject) {
        guard let storage = owner as? RuntimeLoopNativeBatchStorage else { return }
        storage.mergeExecutedRawEventIDs(into: &consumedRawEventIDs)
        acknowledgedRawUniqueIDCount.store(UInt64(consumedRawEventIDs.count), ordering: .releasing)
    }

    private func collectRetiredBatchOnWorker(_ owner: AnyObject) {
        collectExecutedRawIDsOnWorker(owner)
        guard let storage = owner as? RuntimeLoopNativeBatchStorage else { return }
        batchStarts.removeAll { $0.sequence == storage.header.sequence &&
            $0.scope.sourceGeneration == storage.header.scope.sourceGeneration }
    }

    private func shutdownOnWorker() {
        guard !shutdown else { return }
        shutdown = true
        stopTimerOnWorker()
        nativeFrame = nil
        nativeQuantum = nil
        reconcileExecutionOnWorker() // Host is quiescent; includes a last CAS won just before cancel.
        channel.shutdownAfterCallbackQuiescence(beforeRelease: { [self] in collectRetiredBatchOnWorker($0) })
        producer = nil
        batchStarts.removeAll()
        pendingCutover = nil
        prevalidatedRefresh = nil
        condition.lock()
        refreshRequest = nil
        publishedRefresh = nil // Preserve only the final actual receipt until Session deinit.
        condition.unlock()
        cache = nil
        workerQueue.setSpecific(key: workerKey, value: nil)
        shutdownComplete.store(true, ordering: .releasing)
    }
}
