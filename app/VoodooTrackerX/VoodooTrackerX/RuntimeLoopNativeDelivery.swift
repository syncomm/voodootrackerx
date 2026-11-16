import Synchronization

/// Precomputed follow geometry; reading it performs no musical interpretation.
struct RuntimeLoopNativeFollowRow {
    let source: PlaybackPosition
    let syntheticRow: Int
    let rowStartExactFrame: Double
    let rowStartFrame: Int
    let rowEndFrame: Int
    let effectiveSpeed: Int
    let effectiveBPM: Int
    let actualTickCount: Int
}

struct RuntimeLoopNativeFollowSnapshot: Equatable {
    var nativeFrame: UInt64
    let source: PlaybackPosition
    let syntheticRow: Int
    let tickInRow: Int
    let rowStartFrame: Int
    let rowEndFrame: Int
    let effectiveSpeed: Int
    let effectiveBPM: Int
    let actualTickCount: Int
    var isTerminal = false
}

/// Fixed POD publication, single callback writer and off-audio readers. Every
/// field is atomic; the sequence rejects mixed snapshots without taking the render lock.
final class RuntimeLoopNativeFollowPublication {
    private let sequence = Atomic<UInt64>(0)
    private let valid = Atomic(false)
    private let frame = Atomic<UInt64>(0)
    private let order = Atomic<Int>(0), pattern = Atomic<Int>(0), row = Atomic<Int>(0)
    private let synthetic = Atomic<Int>(0), tick = Atomic<Int>(0)
    private let start = Atomic<Int>(0), end = Atomic<Int>(0)
    private let speed = Atomic<Int>(0), bpm = Atomic<Int>(0), ticks = Atomic<Int>(0)
    private let terminal = Atomic(false)

    func publish(_ value: RuntimeLoopNativeFollowSnapshot) {
        // Sequential consistency keeps both sequence edges around every scalar access.
        // Readers make one bounded attempt; a concurrent publication leaves UI follow unchanged.
        _ = sequence.wrappingAdd(1, ordering: .sequentiallyConsistent)
        frame.store(value.nativeFrame, ordering: .sequentiallyConsistent)
        order.store(value.source.orderIndex, ordering: .sequentiallyConsistent)
        pattern.store(value.source.patternIndex, ordering: .sequentiallyConsistent)
        row.store(value.source.rowIndex, ordering: .sequentiallyConsistent)
        synthetic.store(value.syntheticRow, ordering: .sequentiallyConsistent)
        tick.store(value.tickInRow, ordering: .sequentiallyConsistent)
        start.store(value.rowStartFrame, ordering: .sequentiallyConsistent)
        end.store(value.rowEndFrame, ordering: .sequentiallyConsistent)
        speed.store(value.effectiveSpeed, ordering: .sequentiallyConsistent)
        bpm.store(value.effectiveBPM, ordering: .sequentiallyConsistent)
        ticks.store(value.actualTickCount, ordering: .sequentiallyConsistent)
        terminal.store(value.isTerminal, ordering: .sequentiallyConsistent)
        valid.store(true, ordering: .sequentiallyConsistent)
        _ = sequence.wrappingAdd(1, ordering: .sequentiallyConsistent)
    }

    func read() -> RuntimeLoopNativeFollowSnapshot? {
        let before = sequence.load(ordering: .sequentiallyConsistent)
        guard before & 1 == 0, valid.load(ordering: .sequentiallyConsistent) else { return nil }
        let result = RuntimeLoopNativeFollowSnapshot(nativeFrame: frame.load(ordering: .sequentiallyConsistent),
            source: .init(orderIndex: order.load(ordering: .sequentiallyConsistent),
                patternIndex: pattern.load(ordering: .sequentiallyConsistent), rowIndex: row.load(ordering: .sequentiallyConsistent)),
            syntheticRow: synthetic.load(ordering: .sequentiallyConsistent), tickInRow: tick.load(ordering: .sequentiallyConsistent),
            rowStartFrame: start.load(ordering: .sequentiallyConsistent), rowEndFrame: end.load(ordering: .sequentiallyConsistent),
            effectiveSpeed: speed.load(ordering: .sequentiallyConsistent), effectiveBPM: bpm.load(ordering: .sequentiallyConsistent),
            actualTickCount: ticks.load(ordering: .sequentiallyConsistent),
            isTerminal: terminal.load(ordering: .sequentiallyConsistent))
        return sequence.load(ordering: .sequentiallyConsistent) == before ? result : nil
    }
}

/// Preordered descriptor; event/source numeric fields are copied, never rewritten.
struct RuntimeLoopNativeCommandDescriptor: @unchecked Sendable {
    let eventID: Int
    let eventOrdinal: Int
    let localSourceIndex: Int // -1 only for an honestly source-free command.
    let channel: Int
    let localFrame: Int
    let targetBindingOrdinal: Int // -1 for no source target.
    let opcode: UInt32
    let payload: UnsafeRawPointer? // Immutable, native-ready operation-specific POD.
}

/// Reuses the existing POD RuntimeCMixerAdapterVoiceState as State in integration.
/// Allocate once off audio; access only from the serialized render owner thereafter.
final class RuntimeLoopNativeVoiceTable<State>: @unchecked Sendable {
    private struct Entry {
        var birth: RuntimeLoopNativeSourceIdentity?
        var incarnation: UInt64 = 0
        var channel = -1
        var state: State?
    }
    private let capacity: Int
    private let channelCount: Int
    private let entries: UnsafeMutablePointer<Entry>
    private let current: UnsafeMutablePointer<Int>

    init(nativeVoiceCapacity: Int, channelCount: Int) {
        precondition(nativeVoiceCapacity > 0 && channelCount > 0)
        capacity = nativeVoiceCapacity
        self.channelCount = channelCount
        entries = .allocate(capacity: nativeVoiceCapacity)
        entries.initialize(repeating: Entry(), count: nativeVoiceCapacity)
        current = .allocate(capacity: channelCount)
        current.initialize(repeating: -1, count: channelCount)
    }

    deinit { // Caller must retain through callback quiescence; State must be POD.
        entries.deinitialize(count: capacity)
        entries.deallocate()
        current.deinitialize(count: channelCount)
        current.deallocate()
    }

    /// Publish only after native birth succeeds and returns its actual voice slot.
    /// The C pool chooses a free native slot; no speculative voice index is assumed.
    func bindBirth(_ birth: RuntimeLoopNativeSourceIdentity, channel: Int,
                   nativeVoice: Int, state: State) -> UInt64? {
        guard (0..<capacity).contains(nativeVoice), (0..<channelCount).contains(channel),
              entries[nativeVoice].incarnation < .max else { return nil }
        let oldChannel = entries[nativeVoice].channel
        if (0..<channelCount).contains(oldChannel), current[oldChannel] == nativeVoice {
            current[oldChannel] = -1
        }
        let incarnation = entries[nativeVoice].incarnation + 1
        entries[nativeVoice] = Entry(birth: birth, incarnation: incarnation,
                                     channel: channel, state: state)
        current[channel] = nativeVoice
        return incarnation
    }

    /// Resolve a full birth key, never a channel-only or raw-index fallback.
    /// Incarnation 0 means a producer cannot yet know the native slot: full-key scan.
    func resolve(_ binding: RuntimeLoopNativeSourceBinding, channel: Int,
                 requiresCurrent: Bool = true) -> Int? {
        guard (0..<channelCount).contains(channel) else { return nil }
        var index = binding.nativeSlot
        if !(0..<capacity).contains(index) || entries[index].birth != binding.birth {
            index = -1
            for candidate in 0..<capacity where entries[candidate].birth == binding.birth {
                index = candidate
                break
            }
        }
        guard index >= 0, entries[index].channel == channel,
              binding.nativeIncarnation == 0 || entries[index].incarnation == binding.nativeIncarnation,
              !requiresCurrent || current[channel] == index else { return nil }
        return index
    }

    func state(at nativeVoice: Int) -> State? {
        guard (0..<capacity).contains(nativeVoice) else { return nil }
        return entries[nativeVoice].state
    }

    /// Caller first resolved full identity and checked actual C active/tag/retiring state.
    func storeState(_ state: State, at nativeVoice: Int) {
        precondition((0..<capacity).contains(nativeVoice))
        entries[nativeVoice].state = state
    }

    func source(on channel: Int) -> RuntimeLoopNativeSourceIdentity? {
        guard (0..<channelCount).contains(channel), current[channel] >= 0 else { return nil }
        return entries[current[channel]].birth
    }

    /// Stop targeting this birth; its native retirement tail remains owned/rendered in C.
    func clearCurrent(_ binding: RuntimeLoopNativeSourceBinding, channel: Int) {
        guard let index = resolve(binding, channel: channel) else { return }
        current[channel] = -1
        // Keep birth/incarnation while C may still own a live/tail source at that slot.
        _ = index
    }
}

enum RuntimeLoopNativeDeliveryFailure: UInt8, Sendable {
    case missingSuccessor, invalidBoundary, invalidSuccessor, invalidCommand, nativeRenderFailure, nativeCommandFailure
}

/// Fixed scalar record; publish only once retirement is actually complete.
struct RuntimeLoopNativeDeliveryFault: Sendable {
    let scope: RuntimeLoopNativeScope
    let sequence: UInt64
    let boundaryFrame: UInt64
    let retirementEndFrame: UInt64
    let reason: RuntimeLoopNativeDeliveryFailure
}

/// RenderCore implements these hooks using existing C operations and fixed diagnostics.
/// Calls occur under its existing render lock. No hook may build/release graph storage.
protocol RuntimeLoopNativeDeliverySink: AnyObject {
    var nativeLoopCurrentFrame: UInt64 { get }
    func renderNativeLoopFrames(outputOffset: Int, frameCount: Int)
    func silenceNativeLoopFrames(outputOffset: Int, frameCount: Int)
    func applyPreparedNativeLoopCommand(_ command: RuntimeLoopNativeCommandDescriptor,
        header: RuntimeLoopNativeBatchHeader, target: RuntimeLoopNativeSourceBinding?) -> Bool
    func beginNativeLoopRetirement()
    func didAdmitNativeLoopScope(_ scope: RuntimeLoopNativeScope)
    func reachNativeSongEnd(atRuntimeFrame frame: UInt64)
    func finishNativeSong(atRuntimeFrame frame: UInt64)
}

extension RuntimeLoopNativeDeliverySink {
    func didAdmitNativeLoopScope(_ scope: RuntimeLoopNativeScope) {}
    func reachNativeSongEnd(atRuntimeFrame frame: UInt64) {}
    func finishNativeSong(atRuntimeFrame frame: UInt64) {}
}

/// One callback-owned cursor over two producer-owned batches. No payload owner is copied.
final class RuntimeLoopNativeDeliveryCursor: @unchecked Sendable {
    private let channel: RuntimeLoopNativeTwoSlotChannel
    private var scope: RuntimeLoopNativeScope
    private let retirementFrames: UInt64
    private var lease: RuntimeLoopNativeBatchLease?
    private var nextCommand = 0
    private var nextNaturalBoundary = 0
    private var revoked = false
    private var fault: RuntimeLoopNativeDeliveryFault?
    private var terminalFollow: RuntimeLoopNativeFollowSnapshot?
    private var lastFollow: RuntimeLoopNativeFollowSnapshot?
    private let completed = Atomic(false)
    private let consumed = Atomic(false)
    private var songCompletion: RuntimeLoopNativeSongCompletion?
    private let songCompleted = Atomic(false), songCompletionConsumed = Atomic(false)
    private var reachedSongEnd = false

    init(channel: RuntimeLoopNativeTwoSlotChannel, scope: RuntimeLoopNativeScope,
         retirementFrames: Int) {
        precondition(retirementFrames > 0)
        self.channel = channel
        self.scope = scope
        self.retirementFrames = UInt64(retirementFrames)
    }

    /// RenderCore passes callback's buffer through the sink without allocating a closure.
    func render<S: RuntimeLoopNativeDeliverySink>(frameCount: Int, sink: borrowing S) {
        guard frameCount > 0 else { return }
        var offset = 0
        while offset < frameCount {
            if revoked {
                sink.silenceNativeLoopFrames(outputOffset: offset, frameCount: frameCount - offset)
                return
            }
            if songCompletion != nil {
                // The exact stop hook already cleared C voices. Keep normal-song
                // silent sample-clock advancement after its deadline.
                sink.renderNativeLoopFrames(outputOffset: offset, frameCount: frameCount - offset)
                return
            }
            if let failure = fault {
                let frame = sink.nativeLoopCurrentFrame
                if frame >= failure.retirementEndFrame {
                    completed.store(true, ordering: .releasing)
                    sink.silenceNativeLoopFrames(outputOffset: offset, frameCount: frameCount - offset)
                    return
                }
                let count = Int(min(UInt64(frameCount - offset), failure.retirementEndFrame - frame))
                sink.renderNativeLoopFrames(outputOffset: offset, frameCount: count)
                guard sink.nativeLoopCurrentFrame == frame + UInt64(count) else {
                    sink.silenceNativeLoopFrames(outputOffset: offset, frameCount: frameCount - offset)
                    return // Existing native render-fault service remains authoritative.
                }
                offset += count
                if sink.nativeLoopCurrentFrame == failure.retirementEndFrame {
                    completed.store(true, ordering: .releasing)
                }
                continue
            }
            if lease == nil {
                let admission: RuntimeLoopNativeAdmission
                if let active = channel.currentLease() { admission = .admitted(active) }
                else { admission = channel.begin(at: sink.nativeLoopCurrentFrame) }
                accept(admission, at: sink.nativeLoopCurrentFrame, sink: sink)
                continue
            }
            let active = lease!
            let header = active.header
            let frame = sink.nativeLoopCurrentFrame
            guard frame >= header.runtimeStartFrame, frame <= header.runtimeEndFrame,
                  header.commandStride == MemoryLayout<RuntimeLoopNativeCommandDescriptor>.stride else {
                fail(.invalidBoundary, at: frame, sequence: header.sequence, sink: sink)
                continue
            }
            if settleBoundary(at: frame, sink: sink) { continue }
            var nextFrame = header.runtimeEndFrame
            if let musicalEnd = header.finiteSongEndFrame, !reachedSongEnd, musicalEnd > frame {
                nextFrame = min(nextFrame, musicalEnd)
            }
            if nextNaturalBoundary < header.naturalBoundaryCount {
                guard let boundaries = header.naturalBoundaries,
                      let boundary = runtimeFrame(boundaries[nextNaturalBoundary].localFrame, in: header),
                      boundary > frame, boundary <= header.runtimeEndFrame,
                      boundaries[nextNaturalBoundary].stateToken > 0 else {
                    fail(.invalidBoundary, at: frame, sequence: header.sequence, sink: sink); continue
                }
                nextFrame = min(nextFrame, boundary)
            }
            if nextCommand < header.commandCount {
                guard let commands = header.commands?.assumingMemoryBound(to: RuntimeLoopNativeCommandDescriptor.self),
                      let target = runtimeFrame(commands[nextCommand].localFrame, in: header),
                      target >= frame,
                      target < header.runtimeEndFrame ||
                          (header.finiteSongEndFrame == header.runtimeEndFrame && target == header.runtimeEndFrame) else {
                    fail(.invalidCommand, at: frame, sequence: header.sequence, sink: sink)
                    continue
                }
                nextFrame = min(nextFrame, target)
            }
            if nextFrame > frame {
                let count = Int(min(UInt64(frameCount - offset), nextFrame - frame))
                sink.renderNativeLoopFrames(outputOffset: offset, frameCount: count)
                guard sink.nativeLoopCurrentFrame == frame + UInt64(count) else {
                    fail(.nativeRenderFailure, at: frame, sequence: header.sequence, sink: sink)
                    sink.silenceNativeLoopFrames(outputOffset: offset, frameCount: frameCount - offset)
                    return
                }
                offset += count
                // A callback-edge B is acknowledged now, not one callback or UI turn later.
                _ = settleBoundary(at: sink.nativeLoopCurrentFrame, sink: sink)
                continue
            }
            let command = header.commands!.assumingMemoryBound(to: RuntimeLoopNativeCommandDescriptor.self)[nextCommand]
            let target: RuntimeLoopNativeSourceBinding?
            if command.targetBindingOrdinal >= 0 {
                guard command.targetBindingOrdinal < header.bindingCount, let bindings = header.bindings else {
                    fail(.invalidCommand, at: frame, sequence: header.sequence, sink: sink)
                    continue
                }
                target = bindings[command.targetBindingOrdinal]
            } else { target = nil }
            let executedWord: UnsafeMutablePointer<UInt64>?
            let executedBit: UInt64
            if header.executedRawIDWordCount > 0 {
                guard command.eventID >= 0, let words = header.executedRawIDWords,
                      command.eventID / 64 < header.executedRawIDWordCount else {
                    fail(.invalidCommand, at: frame, sequence: header.sequence, sink: sink)
                    continue
                }
                executedWord = words.advanced(by: command.eventID / 64)
                executedBit = UInt64(1) << (command.eventID % 64)
            } else { executedWord = nil; executedBit = 0 }
            guard sink.applyPreparedNativeLoopCommand(command, header: header, target: target) else {
                fail(.nativeCommandFailure, at: frame, sequence: header.sequence, sink: sink)
                continue
            }
            // Raw unique-ID meaning is unchanged; repeated occurrences set the same bit.
            // Retirement/quiescence publishes these non-atomic callback-only writes to producer.
            if let executedWord { executedWord.pointee |= executedBit }
            nextCommand += 1 // Preordered equal-frame commands retain their exact order/IDs.
        }
    }

    /// Safe on the service cadence only after completed acquire publication; immutable thereafter.
    func takeCompletedFault() -> RuntimeLoopNativeDeliveryFault? {
        guard completed.load(ordering: .acquiring),
              !consumed.exchange(true, ordering: .acquiringAndReleasing) else { return nil }
        return fault
    }

    /// One successful finite Stop receipt, independent of the fault consumer.
    func takeCompletedSong() -> RuntimeLoopNativeSongCompletion? {
        guard songCompleted.load(ordering: .acquiring),
              !songCompletionConsumed.exchange(true, ordering: .acquiringAndReleasing) else { return nil }
        return songCompletion
    }

    /// Serialized render-owner query, also permitted after host quiescence. A
    /// terminal interval holds its last musical coordinate as raw silence advances.
    func follow(at runtimeFrame: UInt64, sampleRate: Double) -> RuntimeLoopNativeFollowSnapshot? {
        if var terminal = terminalFollow {
            terminal.nativeFrame = runtimeFrame
            return terminal
        }
        guard let header = lease?.header, let rows = header.followRows, header.followRowCount > 0,
              runtimeFrame >= header.runtimeStartFrame else { return nil }
        let offset = runtimeFrame - header.runtimeStartFrame
        guard offset <= UInt64(Int.max), header.localStartFrame <= Int.max - Int(offset) else { return nil }
        let local = header.localStartFrame + Int(offset)
        var lower = 0, upper = header.followRowCount
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if rows[middle].rowStartFrame <= local { lower = middle + 1 } else { upper = middle }
        }
        let row = rows[max(0, lower - 1)]
        guard row.actualTickCount > 0, row.effectiveSpeed > 0, row.effectiveBPM > 0 else { return nil }
        lower = 0; upper = row.actualTickCount
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let frame = PlaybackSongFxxRowTiming.frame(rowStartExactFrame: row.rowStartExactFrame,
                tick: middle, bpm: row.effectiveBPM, sampleRate: sampleRate)
            if frame <= local { lower = middle + 1 } else { upper = middle }
        }
        let result = RuntimeLoopNativeFollowSnapshot(nativeFrame: runtimeFrame, source: row.source, syntheticRow: row.syntheticRow,
            tickInRow: max(0, lower - 1), rowStartFrame: row.rowStartFrame, rowEndFrame: row.rowEndFrame,
            effectiveSpeed: row.effectiveSpeed, effectiveBPM: row.effectiveBPM, actualTickCount: row.actualTickCount)
        lastFollow = result
        return result
    }

    private func runtimeFrame(_ localFrame: Int, in header: RuntimeLoopNativeBatchHeader) -> UInt64? {
        guard localFrame >= header.localStartFrame else { return nil }
        let result = header.runtimeStartFrame.addingReportingOverflow(UInt64(localFrame - header.localStartFrame))
        return result.overflow ? nil : result.partialValue
    }

    /// Called even at callback edges. A ready edit wins before any old right-boundary writer.
    private func settleBoundary<S: RuntimeLoopNativeDeliverySink>(at frame: UInt64, sink: borrowing S) -> Bool {
        guard let active = lease else { return false }
        let header = active.header
        if let musicalEnd = header.finiteSongEndFrame, !reachedSongEnd, frame >= musicalEnd {
            guard frame == musicalEnd else {
                fail(.invalidBoundary, at: frame, sequence: header.sequence, sink: sink); return true
            }
            captureTerminalFollow(at: frame)
            sink.reachNativeSongEnd(atRuntimeFrame: frame)
            reachedSongEnd = true
        }
        while nextNaturalBoundary < header.naturalBoundaryCount {
            guard let boundaries = header.naturalBoundaries,
                  let boundaryFrame = runtimeFrame(boundaries[nextNaturalBoundary].localFrame, in: header),
                  boundaryFrame > header.runtimeStartFrame, boundaryFrame <= header.runtimeEndFrame,
                  boundaries[nextNaturalBoundary].stateToken > 0 else {
                fail(.invalidBoundary, at: frame, sequence: header.sequence, sink: sink); return true
            }
            guard boundaryFrame <= frame else { break }
            guard boundaryFrame == frame else {
                fail(.invalidBoundary, at: frame, sequence: header.sequence, sink: sink); return true
            }
            if let next = channel.tryAdmitEarlyCutover(at: frame, stateToken: boundaries[nextNaturalBoundary].stateToken) {
                lease = nil // Old POD pointers cease before producer can reclaim the retired slot.
                accept(.admitted(next), at: frame, sink: sink)
                return true
            }
            nextNaturalBoundary += 1
        }
        if frame == header.runtimeEndFrame {
            let hasZeroTailEndWriter: Bool
            if header.finiteSongEndFrame == frame, nextCommand < header.commandCount,
               let commands = header.commands?.assumingMemoryBound(to: RuntimeLoopNativeCommandDescriptor.self) {
                hasZeroTailEndWriter = runtimeFrame(commands[nextCommand].localFrame, in: header) == frame
            } else { hasZeroTailEndWriter = false }
            if !hasZeroTailEndWriter { finish(at: frame, sink: sink); return true }
        }
        return false
    }

    private func finish<S: RuntimeLoopNativeDeliverySink>(at frame: UInt64, sink: borrowing S) {
        captureTerminalFollow(at: frame)
        if lease?.header.finiteSongEndFrame != nil {
            // C may still borrow generation PCM. Clear it before channel retirement
            // lets the serial producer release the final batch/cache owner.
            sink.finishNativeSong(atRuntimeFrame: frame)
        }
        lease = nil // POD only. Do not access old pointers after channel retirement publishes.
        nextCommand = 0
        accept(channel.finishBoundary(at: frame), at: frame, sink: sink)
    }

    private func accept<S: RuntimeLoopNativeDeliverySink>(_ result: RuntimeLoopNativeAdmission,
                                                        at frame: UInt64, sink: borrowing S) {
        switch result {
        case let .admitted(next):
            terminalFollow = nil
            lease = next; nextCommand = 0; nextNaturalBoundary = 0; scope = next.header.scope
            reachedSongEnd = false
            sink.didAdmitNativeLoopScope(next.header.scope)
        case let .completed(value):
            lease = nil
            songCompletion = value
            songCompleted.store(true, ordering: .releasing)
        case .missingSuccessor: fail(.missingSuccessor, at: frame, sequence: channel.acknowledgedSequence, sink: sink)
        case .invalidBoundary: fail(.invalidBoundary, at: frame, sequence: channel.acknowledgedSequence, sink: sink)
        case .invalidSuccessor: fail(.invalidSuccessor, at: frame, sequence: channel.acknowledgedSequence, sink: sink)
        case .revoked: revoked = true; lease = nil // Explicit Stop/edit, not a planning-underrun alert.
        }
    }

    private func fail<S: RuntimeLoopNativeDeliverySink>(_ reason: RuntimeLoopNativeDeliveryFailure,
        at frame: UInt64, sequence: UInt64, sink: borrowing S) {
        guard fault == nil else { return }
        captureTerminalFollow(at: frame)
        channel.revoke()
        lease = nil
        let end = frame.addingReportingOverflow(retirementFrames)
        fault = .init(scope: scope, sequence: sequence, boundaryFrame: frame,
                      retirementEndFrame: end.overflow ? UInt64.max : end.partialValue, reason: reason)
        sink.beginNativeLoopRetirement() // Existing C policy only, once; never clear at B.
    }

    private func captureTerminalFollow(at frame: UInt64) {
        guard terminalFollow == nil,
              var value = follow(at: frame, sampleRate: Double(bitPattern: scope.sampleRateBits)) ?? lastFollow else { return }
        value.nativeFrame = frame
        value.isTerminal = true
        terminalFollow = value // Scalars only; no borrowed row pointer survives retirement.
    }
}
