import Foundation
import os
import Synchronization

@MainActor
protocol PlaybackTraceWriting: AnyObject {
    var isEnabled: Bool { get }

    func record(_ event: PlaybackTraceEvent)
    func flush()
}

@MainActor
final class NoopPlaybackTraceWriter: PlaybackTraceWriting {
    static let shared = NoopPlaybackTraceWriter()

    let isEnabled = false

    private init() {}

    func record(_ event: PlaybackTraceEvent) {}

    func flush() {}
}

enum PlaybackTraceJSONLFormatter {
    static func line(for event: PlaybackTraceEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(event)
        data.append(0x0A)
        return data
    }
}

@MainActor
final class PlaybackTraceJSONLWriter: PlaybackTraceWriting {
    let isEnabled = true

    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "PlaybackTrace")
    private let fileHandle: FileHandle

    init(url: URL) throws {
        let parentURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: url)
        try fileHandle.truncate(atOffset: 0)
    }

    deinit {
        try? fileHandle.close()
    }

    func record(_ event: PlaybackTraceEvent) {
        do {
            try fileHandle.write(contentsOf: PlaybackTraceJSONLFormatter.line(for: event))
        } catch {
            logger.error("Unable to write playback trace event: \(error.localizedDescription, privacy: .public)")
        }
    }

    func flush() {
        try? fileHandle.synchronize()
    }
}

@MainActor
protocol PlaybackTimingTraceSinking: AnyObject {
    func writePlaybackTimingTraceLine(_ line: String)
}

@MainActor
final class StandardErrorPlaybackTimingTraceSink: PlaybackTimingTraceSinking {
    static let shared = StandardErrorPlaybackTimingTraceSink()

    private init() {}

    func writePlaybackTimingTraceLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else {
            return
        }
        FileHandle.standardError.write(data)
    }
}

protocol PlaybackTimingTraceClock {
    func nowNanoseconds() -> UInt64
}

struct MonotonicPlaybackTimingTraceClock: PlaybackTimingTraceClock {
    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

struct PlaybackTimingTraceField: Equatable {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = Self.sanitizedKey(key)
        self.value = Self.sanitizedValue(value)
    }

    init(_ key: String, _ value: Int) {
        self.init(key, String(value))
    }

    init(_ key: String, _ value: UInt64) {
        self.init(key, String(value))
    }

    init(_ key: String, _ value: Bool) {
        self.init(key, value ? "true" : "false")
    }

    init(_ key: String, milliseconds value: Double) {
        self.init(key, PlaybackTimingTraceFormatter.format(milliseconds: value))
    }

    private static func sanitizedKey(_ key: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        let scalars = key.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        let result = scalars.joined()
        return result.isEmpty ? "field" : result
    }

    private static func sanitizedValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "empty"
        }
        let lowercased = trimmed.lowercased()
        if trimmed.contains("/") ||
            trimmed.contains("\\") ||
            lowercased.contains("desktop") ||
            lowercased.contains("gregory") {
            return "redacted"
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.,:+-=@")
        let scalars = trimmed.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        return scalars.joined()
    }
}

struct PlaybackTimingTraceRecord: Equatable {
    let lifecycle: String
    let phase: String
    let index: Int
    let elapsedMS: Double
    let fields: [PlaybackTimingTraceField]
}

enum PlaybackTimingTraceFormatter {
    static func line(for record: PlaybackTimingTraceRecord) -> String {
        var parts = [
            "vtx_playback_timing",
            "schema=1",
            "lifecycle=\(PlaybackTimingTraceField("lifecycle", record.lifecycle).value)",
            "phase=\(PlaybackTimingTraceField("phase", record.phase).value)",
            "index=\(record.index)",
            "elapsed_ms=\(format(milliseconds: record.elapsedMS))",
        ]
        parts.append(contentsOf: record.fields.map { "\($0.key)=\($0.value)" })
        return parts.joined(separator: " ")
    }

    static func format(milliseconds: Double) -> String {
        let safeMilliseconds = milliseconds.isFinite ? max(0, milliseconds) : 0
        return String(format: "%.3f", safeMilliseconds)
    }
}

@MainActor
final class PlaybackTimingTraceSession {
    private let lifecycle: String
    private let clock: PlaybackTimingTraceClock
    private let sink: PlaybackTimingTraceSinking
    private let startedAtNanoseconds: UInt64
    private var records = [PlaybackTimingTraceRecord]()
    private var isFinished = false

    init(
        lifecycle: String,
        clock: PlaybackTimingTraceClock,
        sink: PlaybackTimingTraceSinking
    ) {
        self.lifecycle = lifecycle
        self.clock = clock
        self.sink = sink
        startedAtNanoseconds = clock.nowNanoseconds()
    }

    func beginPhase() -> UInt64 {
        clock.nowNanoseconds()
    }

    /// Allows same-host input automation to correlate UI entry without including
    /// AX lookup or trace-reading overhead in the application's request duration.
    var startUptimeNanoseconds: UInt64 { startedAtNanoseconds }

    func recordPhase(
        _ phase: String,
        startedAt startNanoseconds: UInt64?,
        fields: [PlaybackTimingTraceField] = []
    ) {
        guard !isFinished else {
            return
        }
        let startedAt = startNanoseconds ?? clock.nowNanoseconds()
        records.append(PlaybackTimingTraceRecord(
            lifecycle: lifecycle,
            phase: phase,
            index: records.count + 1,
            elapsedMS: milliseconds(from: startedAt, to: clock.nowNanoseconds()),
            fields: fields
        ))
    }

    func recordMeasuredPhase(
        _ phase: String,
        elapsedMS: Double,
        fields: [PlaybackTimingTraceField] = []
    ) {
        guard !isFinished else {
            return
        }
        records.append(PlaybackTimingTraceRecord(
            lifecycle: lifecycle,
            phase: phase,
            index: records.count + 1,
            elapsedMS: elapsedMS,
            fields: fields
        ))
    }

    /// Records a monotonic observation relative to UI lifecycle entry. The host
    /// supplies its completed-render stamp; polling latency is not onset latency.
    func recordMilestone(_ phase: String, at uptimeNanoseconds: UInt64,
                         fields: [PlaybackTimingTraceField] = []) {
        recordMeasuredPhase(phase,
            elapsedMS: milliseconds(from: startedAtNanoseconds, to: uptimeNanoseconds), fields: fields)
    }

    func measure<T>(
        _ phase: String,
        fields: [PlaybackTimingTraceField] = [],
        _ body: () throws -> T
    ) rethrows -> T {
        let startedAt = beginPhase()
        defer {
            recordPhase(phase, startedAt: startedAt, fields: fields)
        }
        return try body()
    }

    func finish(fields: [PlaybackTimingTraceField] = []) {
        guard !isFinished else {
            return
        }
        records.append(PlaybackTimingTraceRecord(
            lifecycle: lifecycle,
            phase: "total",
            index: records.count + 1,
            elapsedMS: milliseconds(from: startedAtNanoseconds, to: clock.nowNanoseconds()),
            fields: fields
        ))
        isFinished = true
        for record in records {
            sink.writePlaybackTimingTraceLine(PlaybackTimingTraceFormatter.line(for: record))
        }
    }

    private func milliseconds(from startNanoseconds: UInt64, to endNanoseconds: UInt64) -> Double {
        guard endNanoseconds >= startNanoseconds else {
            return 0
        }
        return Double(endNanoseconds - startNanoseconds) / 1_000_000.0
    }
}

@MainActor
final class PlaybackTimingTraceRecorder {
    let isEnabled: Bool

    private let clock: PlaybackTimingTraceClock
    private let sink: PlaybackTimingTraceSinking

    init(
        isEnabled: Bool,
        clock: PlaybackTimingTraceClock = MonotonicPlaybackTimingTraceClock(),
        sink: PlaybackTimingTraceSinking = StandardErrorPlaybackTimingTraceSink.shared
    ) {
        self.isEnabled = isEnabled
        self.clock = clock
        self.sink = sink
    }

    func beginLifecycle(_ lifecycle: String) -> PlaybackTimingTraceSession? {
        guard isEnabled else {
            return nil
        }
        return PlaybackTimingTraceSession(lifecycle: lifecycle, clock: clock, sink: sink)
    }
}

enum PlaybackTimingTraceConfiguration {
    static let enabledEnvironmentKey = "VTX_PLAYBACK_TIMING_TRACE"

    /// Resolve the existing opt-in flag off audio; callbacks never inspect environment.
    static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        flagEnabled(enabledEnvironmentKey, environment: environment)
    }

    @MainActor
    static func makeRecorder(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        clock: PlaybackTimingTraceClock = MonotonicPlaybackTimingTraceClock(),
        sink: PlaybackTimingTraceSinking = StandardErrorPlaybackTimingTraceSink.shared
    ) -> PlaybackTimingTraceRecorder {
        PlaybackTimingTraceRecorder(
            isEnabled: isEnabled(environment: environment),
            clock: clock,
            sink: sink
        )
    }

    private static func flagEnabled(_ key: String, environment: [String: String]) -> Bool {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawValue.isEmpty else {
            return false
        }
        return rawValue == "1" || rawValue == "true" || rawValue == "yes" || rawValue == "on"
    }
}

/// Completed probes measure Main dispatch delay; an outstanding probe contributes
/// its age at finish as a lower bound, so a blocked handler cannot hide its wait.
struct PlaybackMainThreadHeartbeatMeasurement {
    let enqueuedProbeCount: UInt64
    let completedProbeCount: UInt64
    let maximumDispatchDelayNanoseconds: UInt64
    let outstandingWaitNanoseconds: UInt64

    var maximumDispatchDelayMS: Double { Double(maximumDispatchDelayNanoseconds) / 1_000_000 }
    var fields: [PlaybackTimingTraceField] {
        [.init("main_probe_enqueued_count", enqueuedProbeCount),
         .init("main_probe_completed_count", completedProbeCount),
         .init("main_dispatch_max_delay_ms", milliseconds: maximumDispatchDelayMS),
         .init("main_outstanding_probe_wait_ms", milliseconds: Double(outstandingWaitNanoseconds) / 1_000_000)]
    }
}

/// Opt-in off-Main timer with at most one outstanding Main-queue probe. No audio
/// callback, file output, or musical transport service participates in measurement.
final class PlaybackMainThreadHeartbeatProbe: @unchecked Sendable {
    private let active = Atomic(true)
    private let pendingSince = Atomic(UInt64(0))
    private let enqueued = Atomic(UInt64(0)), completed = Atomic(UInt64(0))
    private let maximumDelay = Atomic(UInt64(0)), finalOutstandingWait = Atomic(UInt64(0))
    private let timer: DispatchSourceTimer

    private init() {
        let queue = DispatchQueue(label: "com.syncomm.VoodooTrackerX.playback-timing-heartbeat", qos: .userInitiated)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.enqueueProbe() }
        timer.resume()
    }

    deinit { active.store(false, ordering: .releasing); timer.cancel() }

    /// Begin at UI Play entry, before snapshot work. Production uses the existing flag.
    @MainActor
    static func begin(isEnabled: Bool = PlaybackTimingTraceConfiguration.isEnabled()) -> PlaybackMainThreadHeartbeatProbe? {
        isEnabled ? PlaybackMainThreadHeartbeatProbe() : nil
    }

    /// Stop at request completion on Main; repeated finish preserves the same result.
    @MainActor
    func finish() -> PlaybackMainThreadHeartbeatMeasurement {
        if active.exchange(false, ordering: .acquiringAndReleasing) {
            timer.cancel()
            let pending = pendingSince.exchange(0, ordering: .acquiringAndReleasing)
            if pending > 0 {
                let now = DispatchTime.now().uptimeNanoseconds
                let wait = now >= pending ? now - pending : 0
                finalOutstandingWait.store(wait, ordering: .relaxed)
                recordMaximum(wait)
            }
        }
        return .init(enqueuedProbeCount: enqueued.load(ordering: .acquiring),
            completedProbeCount: completed.load(ordering: .acquiring),
            maximumDispatchDelayNanoseconds: maximumDelay.load(ordering: .acquiring),
            outstandingWaitNanoseconds: finalOutstandingWait.load(ordering: .acquiring))
    }

    private func enqueueProbe() {
        guard active.load(ordering: .acquiring) else { return }
        let started = DispatchTime.now().uptimeNanoseconds
        guard pendingSince.compareExchange(expected: 0, desired: started,
            ordering: .acquiringAndReleasing).exchanged else { return }
        guard active.load(ordering: .acquiring) else {
            _ = pendingSince.compareExchange(expected: started, desired: 0, ordering: .acquiringAndReleasing)
            return
        }
        enqueued.wrappingAdd(1, ordering: .releasing)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active.load(ordering: .acquiring) else { return }
            let pending = self.pendingSince.load(ordering: .acquiring)
            guard pending > 0 else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            self.recordMaximum(now >= pending ? now - pending : 0)
            self.completed.wrappingAdd(1, ordering: .releasing)
            _ = self.pendingSince.compareExchange(expected: pending, desired: 0, ordering: .acquiringAndReleasing)
        }
    }

    private func recordMaximum(_ delay: UInt64) {
        var previous = maximumDelay.load(ordering: .acquiring)
        while delay > previous {
            let updated = maximumDelay.compareExchange(expected: previous, desired: delay, ordering: .acquiringAndReleasing)
            if updated.exchanged { return }
            previous = updated.original
        }
    }

#if DEBUG
    var hasOutstandingProbeForTesting: Bool { pendingSince.load(ordering: .acquiring) > 0 }
#endif
}

enum PlaybackTimingTraceFields {
    static func moduleMetadata(_ metadata: ParsedModuleMetadata) -> [PlaybackTimingTraceField] {
        [
            PlaybackTimingTraceField("module_type", metadata.type),
            PlaybackTimingTraceField("channel_count", metadata.channels),
            PlaybackTimingTraceField("order_count", metadata.orderTable.count),
            PlaybackTimingTraceField("song_length", metadata.songLength),
            PlaybackTimingTraceField("pattern_count", metadata.patterns),
            PlaybackTimingTraceField("decoded_pattern_count", metadata.xmPatterns.count),
            PlaybackTimingTraceField("instrument_count", metadata.instruments),
        ]
    }

    static func playbackSong(_ song: PlaybackSong?, buildSucceeded: Bool? = nil) -> [PlaybackTimingTraceField] {
        var fields = [PlaybackTimingTraceField]()
        if let buildSucceeded {
            fields.append(PlaybackTimingTraceField("build_succeeded", buildSucceeded))
        }
        guard let song else {
            fields.append(PlaybackTimingTraceField("has_song", false))
            return fields
        }
        fields.append(contentsOf: [
            PlaybackTimingTraceField("has_song", true),
            PlaybackTimingTraceField("order_count", song.orders.count),
            PlaybackTimingTraceField("pattern_count", song.patternsByIndex.count),
            PlaybackTimingTraceField("instrument_count", song.instrumentsByIndex.count),
            PlaybackTimingTraceField("sample_count", sampleCount(in: song)),
        ])
        return fields
    }

    static func adapterPlan(_ plan: RuntimeCMixerAdapterEventPlan) -> [PlaybackTimingTraceField] {
        [
            PlaybackTimingTraceField("plan_generated", plan.generated),
            PlaybackTimingTraceField("planned_event_count", plan.plannedEventCount),
            PlaybackTimingTraceField("category_count", plan.categories.count),
            PlaybackTimingTraceField("planned_song_end_frame", plan.plannedSongEndFrame ?? -1),
        ]
    }

    static func playbackPosition(_ position: PlaybackPosition?) -> [PlaybackTimingTraceField] {
        guard let position else {
            return [PlaybackTimingTraceField("has_position", false)]
        }
        return [
            PlaybackTimingTraceField("has_position", true),
            PlaybackTimingTraceField("order_index", position.orderIndex),
            PlaybackTimingTraceField("pattern_index", position.patternIndex),
            PlaybackTimingTraceField("row_index", position.rowIndex),
        ]
    }

    static func playbackStartContext(_ context: PlaybackStartContext?) -> [PlaybackTimingTraceField] {
        guard let context else {
            return [PlaybackTimingTraceField("has_context", false)]
        }
        return [
            PlaybackTimingTraceField("has_context", true),
            PlaybackTimingTraceField("song_position", context.songPosition),
            PlaybackTimingTraceField("pattern_index", context.patternIndex),
            PlaybackTimingTraceField("row_index", context.row),
        ]
    }

    private static func sampleCount(in song: PlaybackSong) -> Int {
        song.instrumentsByIndex.values.reduce(0) { partialResult, instrument in
            partialResult + instrument.samples.count
        }
    }
}
