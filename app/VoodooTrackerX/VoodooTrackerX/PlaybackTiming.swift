import Foundation

struct PlaybackTiming: Equatable {
    var speed: Int
    var bpm: Int

    static let xmDefault = PlaybackTiming(speed: 6, bpm: 125)

    var tickDuration: TimeInterval {
        2.5 / Double(max(1, bpm))
    }

    var rowDuration: TimeInterval {
        tickDuration * Double(ticksPerRow)
    }

    var ticksPerRow: Int {
        max(1, speed)
    }
}

struct PlaybackTickState: Equatable {
    var tickInRow: Int = 0

    mutating func advance(timing: PlaybackTiming) -> Bool {
        tickInRow += 1
        guard tickInRow >= timing.ticksPerRow else {
            return false
        }
        tickInRow = 0
        return true
    }

    mutating func reset() {
        tickInRow = 0
    }

    mutating func setTickInRow(_ tickInRow: Int, timing: PlaybackTiming) {
        self.tickInRow = min(max(0, tickInRow), max(0, timing.ticksPerRow - 1))
    }
}

/// Synthetic tracker-style timing configuration for offline C-backed mixer scheduling.
///
/// This is an orchestration helper only: it does not parse XM pattern/order data, implement effects,
/// change tempo during a render, or replace runtime CoreAudio C mixer playback.
struct SyntheticTrackerTimingConfig: Equatable {
    let speed: Int
    let bpm: Int
    let sampleRate: Double

    /// Creates a deterministic timing configuration from simple tracker-style values.
    ///
    /// Invalid speed and BPM values are clamped to 1, matching `PlaybackTiming`'s safe timing behavior.
    /// Invalid sample rates use the mixer default sample rate.
    init(
        speed: Int = PlaybackTiming.xmDefault.speed,
        bpm: Int = PlaybackTiming.xmDefault.bpm,
        sampleRate: Double = MixerRenderConfig.defaultSampleRate
    ) {
        self.speed = max(1, speed)
        self.bpm = max(1, bpm)
        self.sampleRate = sampleRate.isFinite && sampleRate > 0
            ? sampleRate
            : MixerRenderConfig.defaultSampleRate
    }

    var playbackTiming: PlaybackTiming {
        PlaybackTiming(speed: speed, bpm: bpm)
    }
}

/// Deterministic row/tick-to-frame conversion for synthetic offline mixer events.
struct SyntheticTrackerTiming: Equatable {
    let config: SyntheticTrackerTimingConfig

    /// Exact frames per tick from the existing XM-style `PlaybackTiming` formula: `sampleRate * 2.5 / BPM`.
    var framesPerTick: Double {
        config.sampleRate * config.playbackTiming.tickDuration
    }

    /// Exact frames per row for the configured constant speed.
    var framesPerRow: Double {
        framesPerTick * Double(config.speed)
    }

    /// Converts a zero-based row index to an absolute output frame using deterministic floor rounding.
    func frameFor(row: Int) -> Int {
        frameFor(row: row, tick: 0)
    }

    /// Converts a zero-based row/tick coordinate to an absolute output frame.
    ///
    /// Negative rows and ticks clamp to 0. Ticks beyond the configured speed clamp to the last tick in
    /// the row because this synthetic helper represents tracker-style in-row tick coordinates.
    func frameFor(row: Int, tick: Int) -> Int {
        let safeRow = max(0, row)
        let safeTick = min(max(0, tick), config.speed - 1)
        let absoluteTick = Double(safeRow) * Double(config.speed) + Double(safeTick)
        return Self.floorFrame(absoluteTick * framesPerTick)
    }

    private static func floorFrame(_ exactFrame: Double) -> Int {
        guard exactFrame.isFinite,
              exactFrame > 0 else {
            return 0
        }
        guard exactFrame < Double(Int.max) else {
            return Int.max
        }
        return Int(exactFrame.rounded(.down))
    }
}

/// Tiny synthetic tracker event used only to schedule C-backed offline mixer voices.
struct SyntheticTrackerEvent: Equatable {
    let row: Int
    let tick: Int
    let scheduledStartFrame: Int?
    let sample: MixerSampleBuffer
    let gain: Float
    let pan: Float
    let playbackStep: Double
    let loop: MixerSampleLoop
    let initialSourceFrame: Int
    let volumeEnvelope: MixerEnvelope?
    let panEnvelope: MixerEnvelope?
    let keyOffFrame: Int?
    let fadeoutFrameDecrement: Float

    init(
        row: Int,
        tick: Int = 0,
        scheduledStartFrame: Int? = nil,
        sample: MixerSampleBuffer,
        gain: Float = 1,
        pan: Float = 0,
        playbackStep: Double = 1,
        loop: MixerSampleLoop = .none,
        initialSourceFrame: Int = 0,
        volumeEnvelope: MixerEnvelope? = nil,
        panEnvelope: MixerEnvelope? = nil,
        keyOffFrame: Int? = nil,
        fadeoutFrameDecrement: Float = 0
    ) {
        self.row = row
        self.tick = tick
        self.scheduledStartFrame = scheduledStartFrame.map { max(0, $0) }
        self.sample = sample
        self.gain = gain
        self.pan = pan
        self.playbackStep = playbackStep.isFinite && playbackStep > 0 ? playbackStep : 1
        self.loop = loop
        self.initialSourceFrame = max(0, initialSourceFrame)
        self.volumeEnvelope = volumeEnvelope
        self.panEnvelope = panEnvelope
        self.keyOffFrame = keyOffFrame.map { max(0, $0) }
        self.fadeoutFrameDecrement = fadeoutFrameDecrement.isFinite && fadeoutFrameDecrement > 0 ? fadeoutFrameDecrement : 0
    }

    func withKeyOffFrame(_ frame: Int, fadeoutFrameDecrement: Float) -> SyntheticTrackerEvent {
        SyntheticTrackerEvent(
            row: row,
            tick: tick,
            scheduledStartFrame: scheduledStartFrame,
            sample: sample,
            gain: gain,
            pan: pan,
            playbackStep: playbackStep,
            loop: loop,
            initialSourceFrame: initialSourceFrame,
            volumeEnvelope: volumeEnvelope,
            panEnvelope: panEnvelope,
            keyOffFrame: frame,
            fadeoutFrameDecrement: fadeoutFrameDecrement
        )
    }

    func withGainPan(gain: Float? = nil, pan: Float? = nil) -> SyntheticTrackerEvent {
        SyntheticTrackerEvent(
            row: row,
            tick: tick,
            scheduledStartFrame: scheduledStartFrame,
            sample: sample,
            gain: gain ?? self.gain,
            pan: pan ?? self.pan,
            playbackStep: playbackStep,
            loop: loop,
            initialSourceFrame: initialSourceFrame,
            volumeEnvelope: volumeEnvelope,
            panEnvelope: panEnvelope,
            keyOffFrame: keyOffFrame,
            fadeoutFrameDecrement: fadeoutFrameDecrement
        )
    }

    func withPlaybackStep(_ playbackStep: Double) -> SyntheticTrackerEvent {
        SyntheticTrackerEvent(
            row: row,
            tick: tick,
            scheduledStartFrame: scheduledStartFrame,
            sample: sample,
            gain: gain,
            pan: pan,
            playbackStep: playbackStep,
            loop: loop,
            initialSourceFrame: initialSourceFrame,
            volumeEnvelope: volumeEnvelope,
            panEnvelope: panEnvelope,
            keyOffFrame: keyOffFrame,
            fadeoutFrameDecrement: fadeoutFrameDecrement
        )
    }
}

/// Schedules synthetic tracker row/tick events as absolute-frame C-backed mixer voices.
///
/// The scheduler is intentionally stateless. Determinism across split renders and resets remains owned by
/// `CSoftwareMixer`, which receives only absolute frame positions.
struct SyntheticTrackerScheduler: Equatable {
    let timing: SyntheticTrackerTiming

    init(config: SyntheticTrackerTimingConfig) {
        timing = SyntheticTrackerTiming(config: config)
    }

    func frame(for event: SyntheticTrackerEvent) -> Int {
        if let scheduledStartFrame = event.scheduledStartFrame {
            return scheduledStartFrame
        }
        return timing.frameFor(row: event.row, tick: event.tick)
    }

    @discardableResult
    func schedule(_ event: SyntheticTrackerEvent, on mixer: CSoftwareMixer) -> Int? {
        scheduleWithResult(event, on: mixer).voiceIndex
    }

    @discardableResult
    func scheduleWithResult(_ event: SyntheticTrackerEvent, on mixer: CSoftwareMixer) -> CSoftwareMixerScheduledVoiceResult {
        mixer.addScheduledVoiceWithResult(
            sample: event.sample,
            scheduledStartFrame: frame(for: event),
            gain: event.gain,
            pan: event.pan,
            playbackStep: event.playbackStep,
            loop: event.loop,
            initialSourceFrame: event.initialSourceFrame,
            volumeEnvelope: event.volumeEnvelope,
            panEnvelope: event.panEnvelope,
            keyOffFrame: event.keyOffFrame,
            fadeoutFrameDecrement: event.fadeoutFrameDecrement
        )
    }

    @discardableResult
    func schedule(_ events: [SyntheticTrackerEvent], on mixer: CSoftwareMixer) -> [Int?] {
        events.map { schedule($0, on: mixer) }
    }

    @discardableResult
    func scheduleWithResults(_ events: [SyntheticTrackerEvent], on mixer: CSoftwareMixer) -> [CSoftwareMixerScheduledVoiceResult] {
        events.map { scheduleWithResult($0, on: mixer) }
    }
}

/// Tiny synthetic pattern container for offline C-backed mixer scheduling.
///
/// This is intentionally not an XM pattern model: it stores only a safe row count and flat synthetic
/// row/tick events that can already be scheduled by `SyntheticTrackerScheduler`.
struct SyntheticPattern: Equatable {
    let rowCount: Int
    let events: [SyntheticTrackerEvent]

    init(rowCount: Int, events: [SyntheticTrackerEvent] = []) {
        self.rowCount = max(0, rowCount)
        self.events = events
    }

    var scheduledEvents: [SyntheticTrackerEvent] {
        events.filter { event in
            contains(row: event.row)
        }
    }

    func contains(row: Int) -> Bool {
        row >= 0 && row < rowCount
    }
}

/// Schedules tiny synthetic patterns through the existing tracker row/tick timing adapter.
///
/// Pattern orchestration stays in Swift. The C mixer still receives only absolute-frame synthetic voices,
/// and this type does not parse XM orders, rows, instruments, effects, or tempo changes.
struct SyntheticPatternScheduler: Equatable {
    let trackerScheduler: SyntheticTrackerScheduler

    init(config: SyntheticTrackerTimingConfig) {
        trackerScheduler = SyntheticTrackerScheduler(config: config)
    }

    func frame(for event: SyntheticTrackerEvent) -> Int {
        trackerScheduler.frame(for: event)
    }

    @discardableResult
    func schedule(_ pattern: SyntheticPattern, on mixer: CSoftwareMixer) -> [Int?] {
        trackerScheduler.schedule(pattern.scheduledEvents, on: mixer)
    }

    @discardableResult
    func scheduleWithResults(_ pattern: SyntheticPattern, on mixer: CSoftwareMixer) -> [CSoftwareMixerScheduledVoiceResult] {
        trackerScheduler.scheduleWithResults(pattern.scheduledEvents, on: mixer)
    }
}

protocol AdapterPlanProfileSinking: AnyObject {
    func writeAdapterPlanProfileLine(_ line: String)
}

final class StandardErrorAdapterPlanProfileSink: AdapterPlanProfileSinking, @unchecked Sendable {
    static let shared = StandardErrorAdapterPlanProfileSink()

    private let lock = NSLock()

    private init() {}

    func writeAdapterPlanProfileLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else {
            return
        }
        lock.lock()
        FileHandle.standardError.write(data)
        lock.unlock()
    }
}

struct AdapterPlanProfileField: Equatable {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = Self.sanitizedKey(key)
        self.value = Self.sanitizedValue(value, key: key)
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
        self.init(key, AdapterPlanProfileFormatter.format(milliseconds: value))
    }

    private static func sanitizedKey(_ key: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        let scalars = key.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        let result = scalars.joined()
        return result.isEmpty ? "field" : result
    }

    private static func sanitizedValue(_ value: String, key: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "empty"
        }
        let lowercasedKey = key.lowercased()
        let lowercasedValue = trimmed.lowercased()
        if lowercasedKey.contains("path") ||
            lowercasedKey.contains("title") ||
            lowercasedKey.contains("filename") ||
            lowercasedKey.contains("basename") ||
            trimmed.contains("/") ||
            trimmed.contains("\\") ||
            lowercasedValue.contains("desktop") ||
            lowercasedValue.contains("gregory") {
            return "redacted"
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.,:+-=@")
        let scalars = trimmed.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        return scalars.joined()
    }
}

struct AdapterPlanProfileRecord: Equatable {
    let lifecycle: String
    let phase: String
    let index: Int
    let elapsedMS: Double
    let fields: [AdapterPlanProfileField]
}

enum AdapterPlanProfileFormatter {
    static func line(for record: AdapterPlanProfileRecord) -> String {
        var parts = [
            "vtx_adapter_plan_profile",
            "schema=1",
            "lifecycle=\(AdapterPlanProfileField("lifecycle", record.lifecycle).value)",
            "phase=\(AdapterPlanProfileField("phase", record.phase).value)",
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

protocol AdapterPlanProfileClock {
    func nowNanoseconds() -> UInt64
}

struct MonotonicAdapterPlanProfileClock: AdapterPlanProfileClock {
    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

final class AdapterPlanProfileSession: @unchecked Sendable {
    private let lifecycle: String
    private let clock: AdapterPlanProfileClock
    private let sink: AdapterPlanProfileSinking
    private let lock = NSLock()
    private var recordCount = 0

    init(
        lifecycle: String,
        clock: AdapterPlanProfileClock,
        sink: AdapterPlanProfileSinking
    ) {
        self.lifecycle = lifecycle
        self.clock = clock
        self.sink = sink
    }

    func beginPhase() -> UInt64 {
        clock.nowNanoseconds()
    }

    func recordPhase(
        _ phase: String,
        startedAt startNanoseconds: UInt64?,
        fields: [AdapterPlanProfileField] = []
    ) {
        let startedAt = startNanoseconds ?? clock.nowNanoseconds()
        recordMeasuredPhase(
            phase,
            elapsedMS: milliseconds(from: startedAt, to: clock.nowNanoseconds()),
            fields: fields
        )
    }

    func recordMeasuredPhase(
        _ phase: String,
        elapsedMS: Double,
        fields: [AdapterPlanProfileField] = []
    ) {
        lock.lock()
        recordCount += 1
        let record = AdapterPlanProfileRecord(
            lifecycle: lifecycle,
            phase: phase,
            index: recordCount,
            elapsedMS: elapsedMS,
            fields: fields
        )
        lock.unlock()
        sink.writeAdapterPlanProfileLine(AdapterPlanProfileFormatter.line(for: record))
    }

    private func milliseconds(from startNanoseconds: UInt64, to endNanoseconds: UInt64) -> Double {
        guard endNanoseconds >= startNanoseconds else {
            return 0
        }
        return Double(endNanoseconds - startNanoseconds) / 1_000_000.0
    }
}

final class AdapterPlanProfileRecorder: @unchecked Sendable {
    let isEnabled: Bool

    private let clock: AdapterPlanProfileClock
    private let sink: AdapterPlanProfileSinking

    init(
        isEnabled: Bool,
        clock: AdapterPlanProfileClock = MonotonicAdapterPlanProfileClock(),
        sink: AdapterPlanProfileSinking = StandardErrorAdapterPlanProfileSink.shared
    ) {
        self.isEnabled = isEnabled
        self.clock = clock
        self.sink = sink
    }

    func beginLifecycle(_ lifecycle: String) -> AdapterPlanProfileSession? {
        guard isEnabled else {
            return nil
        }
        return AdapterPlanProfileSession(lifecycle: lifecycle, clock: clock, sink: sink)
    }
}

enum AdapterPlanProfileConfiguration {
    static let enabledEnvironmentKey = "VTX_ADAPTER_PLAN_PROFILE"

    static func makeRecorder(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        clock: AdapterPlanProfileClock = MonotonicAdapterPlanProfileClock(),
        sink: AdapterPlanProfileSinking = StandardErrorAdapterPlanProfileSink.shared
    ) -> AdapterPlanProfileRecorder? {
        guard flagEnabled(enabledEnvironmentKey, environment: environment) else {
            return nil
        }
        return AdapterPlanProfileRecorder(isEnabled: true, clock: clock, sink: sink)
    }

    private static func flagEnabled(_ key: String, environment: [String: String]) -> Bool {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawValue.isEmpty else {
            return false
        }
        return rawValue == "1" || rawValue == "true" || rawValue == "yes" || rawValue == "on"
    }
}

enum AdapterPlanProfileFields {
    static func playbackSong(_ song: PlaybackSong) -> [AdapterPlanProfileField] {
        [
            AdapterPlanProfileField("order_count", song.orders.count),
            AdapterPlanProfileField("pattern_count", song.patternsByIndex.count),
            AdapterPlanProfileField("source_row_count", sourceRowCount(in: song)),
            AdapterPlanProfileField("instrument_count", song.instrumentsByIndex.count),
            AdapterPlanProfileField("sample_count", sampleCount(in: song)),
        ]
    }

    static func syntheticPlan(_ plan: PlaybackSongSyntheticPlan) -> [AdapterPlanProfileField] {
        [
            AdapterPlanProfileField("row_count", plan.diagnostics.rowTiming.count),
            AdapterPlanProfileField("synthetic_row_count", plan.diagnostics.syntheticRowCount),
            AdapterPlanProfileField("synthetic_event_count", plan.pattern.events.count),
            AdapterPlanProfileField("event_mapping_count", plan.diagnostics.eventMappings.count),
            AdapterPlanProfileField("timing_change_count", plan.diagnostics.timingChanges.count),
            AdapterPlanProfileField("traversal_diagnostic_count", plan.diagnostics.traversalDiagnostics.count),
            AdapterPlanProfileField("traversal_guard_hit", plan.diagnostics.traversalGuardHit),
            AdapterPlanProfileField("traversal_stop_reason", plan.diagnostics.traversalStopReason.rawValue),
        ]
    }

    static func adapterPlan(_ plan: RuntimeCMixerAdapterEventPlan) -> [AdapterPlanProfileField] {
        [
            AdapterPlanProfileField("plan_generated", plan.generated),
            AdapterPlanProfileField("planned_event_count", plan.plannedEventCount),
            AdapterPlanProfileField("category_count", plan.categories.count),
            AdapterPlanProfileField("planned_song_end_frame", plan.plannedSongEndFrame ?? -1),
        ]
    }

    static func generation(_ generation: UInt64) -> [AdapterPlanProfileField] {
        [AdapterPlanProfileField("song_generation", generation)]
    }

    private static func sourceRowCount(in song: PlaybackSong) -> Int {
        song.patternsByIndex.values.reduce(0) { partialResult, pattern in
            partialResult + pattern.rows.count
        }
    }

    private static func sampleCount(in song: PlaybackSong) -> Int {
        song.instrumentsByIndex.values.reduce(0) { partialResult, instrument in
            partialResult + instrument.samples.count
        }
    }
}
