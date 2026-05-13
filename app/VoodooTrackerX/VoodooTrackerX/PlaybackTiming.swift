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
/// change tempo during a render, or replace runtime `AVAudioPlayerNode` playback.
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
    let sample: MixerSampleBuffer
    let gain: Float
    let pan: Float
    let loop: MixerSampleLoop
    let volumeEnvelope: MixerEnvelope?
    let panEnvelope: MixerEnvelope?

    init(
        row: Int,
        tick: Int = 0,
        sample: MixerSampleBuffer,
        gain: Float = 1,
        pan: Float = 0,
        loop: MixerSampleLoop = .none,
        volumeEnvelope: MixerEnvelope? = nil,
        panEnvelope: MixerEnvelope? = nil
    ) {
        self.row = row
        self.tick = tick
        self.sample = sample
        self.gain = gain
        self.pan = pan
        self.loop = loop
        self.volumeEnvelope = volumeEnvelope
        self.panEnvelope = panEnvelope
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
        timing.frameFor(row: event.row, tick: event.tick)
    }

    @discardableResult
    func schedule(_ event: SyntheticTrackerEvent, on mixer: CSoftwareMixer) -> Int? {
        mixer.addScheduledVoice(
            sample: event.sample,
            scheduledStartFrame: frame(for: event),
            gain: event.gain,
            pan: event.pan,
            loop: event.loop,
            volumeEnvelope: event.volumeEnvelope,
            panEnvelope: event.panEnvelope
        )
    }

    @discardableResult
    func schedule(_ events: [SyntheticTrackerEvent], on mixer: CSoftwareMixer) -> [Int?] {
        events.map { schedule($0, on: mixer) }
    }
}
