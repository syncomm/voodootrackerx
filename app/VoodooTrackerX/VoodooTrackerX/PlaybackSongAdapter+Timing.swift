import Foundation

/// Plan-local coordinates only. Native semantic pitch/owner/reset capture is not implemented here.
final class PlaybackSongCanonicalTickClock: Equatable, Sendable {
    struct ClockRun: Equatable {
        let timingRowIndex: Int
        let firstCanonicalTickOrdinal: Int
    }

    struct Coordinate: Equatable {
        let syntheticRow: Int
        let tick: Int
        let channel: Int
        let absoluteFrame: Int
        let canonicalTickOrdinal: Int
        let localEffectPhase: Int
        let isFreshEntry: Bool
    }

    let runs: [ClockRun]
    let totalCanonicalTicks: Int
    let sampleRate: Double
    // These immutable Array values share the diagnostics' existing CoW storage.
    let rowTiming: [PlaybackSongSyntheticRowTimingDiagnostic]
    let rowDiagnostics: [PlaybackSongSyntheticRowDiagnostic]

    init(runs: [ClockRun], totalCanonicalTicks: Int, sampleRate: Double,
         rowTiming: [PlaybackSongSyntheticRowTimingDiagnostic], rowDiagnostics: [PlaybackSongSyntheticRowDiagnostic]) {
        self.runs = runs
        self.totalCanonicalTicks = totalCanonicalTicks
        self.sampleRate = sampleRate
        self.rowTiming = rowTiming
        self.rowDiagnostics = rowDiagnostics
    }

    /// Rejects noncanonical ticks (including row exits) and channels without a cell; never advances state.
    func coordinate(syntheticRow: Int, tick: Int, channel: Int) -> Coordinate? {
        guard runs.indices.contains(syntheticRow) else { return nil }
        let run = runs[syntheticRow]
        guard rowTiming.indices.contains(run.timingRowIndex), rowDiagnostics.indices.contains(syntheticRow) else { return nil }
        let timing = rowTiming[run.timingRowIndex]
        guard timing.syntheticRow == syntheticRow, rowDiagnostics[syntheticRow].syntheticRow == syntheticRow,
              tick >= 0, tick < timing.actualTickCount,
              channel >= 0, channel < rowDiagnostics[syntheticRow].cellCount else { return nil }
        let ordinal = run.firstCanonicalTickOrdinal.addingReportingOverflow(tick)
        guard !ordinal.overflow else { return nil }
        return Coordinate(syntheticRow: syntheticRow, tick: tick, channel: channel,
            absoluteFrame: PlaybackSongFxxRowTiming.frame(rowStartExactFrame: timing.rowStartExactFrame,
                tick: tick, bpm: timing.effectiveBPM, sampleRate: sampleRate), canonicalTickOrdinal: ordinal.partialValue,
            localEffectPhase: tick % timing.effectiveSpeed, isFreshEntry: tick == 0)
    }

    static func == (lhs: PlaybackSongCanonicalTickClock, rhs: PlaybackSongCanonicalTickClock) -> Bool {
        lhs === rhs || (lhs.runs == rhs.runs && lhs.totalCanonicalTicks == rhs.totalCanonicalTicks
            && lhs.sampleRate == rhs.sampleRate && lhs.rowTiming == rhs.rowTiming && lhs.rowDiagnostics == rhs.rowDiagnostics)
    }

    static let empty = PlaybackSongCanonicalTickClock(runs: [], totalCanonicalTicks: 0, sampleRate: 0,
        rowTiming: [], rowDiagnostics: [])
}

extension PlaybackSongSyntheticPlan {
    /// Manually authored synthetic mixer plans have no adapter traversal or canonical clock runs.
    init(timingConfig: SyntheticTrackerTimingConfig, pattern: SyntheticPattern, diagnostics: PlaybackSongSyntheticDiagnostics) {
        self.init(timingConfig: timingConfig, pattern: pattern, diagnostics: diagnostics,
            canonicalTickClock: .empty, selectionDispatchFacts: .notAdapterProduced)
    }
}

struct PlaybackSongFxxRowTiming: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
    let rowStartExactFrame: Double
    let rowEndExactFrame: Double
    let effectiveSpeed: Int
    let effectiveBPM: Int
    var patternDelayCycles: Int = 0
    var actualTickCount: Int { effectiveSpeed * (patternDelayCycles + 1) }

    var rowStartFrame: Int {
        Self.floorFrame(rowStartExactFrame)
    }

    var rowEndFrame: Int {
        Self.floorFrame(rowEndExactFrame)
    }

    var rowDurationFrames: Int {
        max(0, rowEndFrame - rowStartFrame)
    }

    var diagnostic: PlaybackSongSyntheticRowTimingDiagnostic {
        PlaybackSongSyntheticRowTimingDiagnostic(
            source: source,
            syntheticRow: syntheticRow,
            rowStartExactFrame: rowStartExactFrame,
            rowEndExactFrame: rowEndExactFrame,
            rowStartFrame: rowStartFrame,
            rowDurationFrames: rowDurationFrames,
            effectiveSpeed: effectiveSpeed,
            effectiveBPM: effectiveBPM,
            patternDelayCycles: patternDelayCycles
        )
    }

    /// Shared Fxx arithmetic: preserve the multiplication, addition and floor order exactly.
    static func frame(rowStartExactFrame: Double, tick: Int, bpm: Int, sampleRate: Double) -> Int {
        floorFrame(rowStartExactFrame + (Double(tick) * (sampleRate * 2.5 / Double(max(1, bpm)))))
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

struct PlaybackSongFxxTimingPlan: Equatable {
    let sampleRate: Double
    let initialSpeed: Int
    let initialBPM: Int
    let rowTimings: [PlaybackSongFxxRowTiming]
    let timingChanges: [PlaybackSongSyntheticTimingChangeDiagnostic]
    let finalSpeed: Int
    let finalBPM: Int
    let endExactFrame: Double

    var rowTimingDiagnostics: [PlaybackSongSyntheticRowTimingDiagnostic] {
        rowTimings.map(\.diagnostic)
    }

    func timingConfig(forSyntheticRow syntheticRow: Int) -> SyntheticTrackerTimingConfig {
        let timing = timingFor(syntheticRow: syntheticRow)
        return SyntheticTrackerTimingConfig(
            speed: timing.speed,
            bpm: timing.bpm,
            sampleRate: sampleRate,
            patternDelayCycles: timing.delay
        )
    }

    func actualTickCount(for row: Int) -> Int { timingFor(syntheticRow: row).ticks }

    func localEffectPhase(row: Int, elapsedTick: Int) -> Int {
        elapsedTick % timingFor(syntheticRow: row).speed
    }

    func frameFor(row: Int, tick: Int = 0) -> Int {
        let safeRow = max(0, row)
        let timing = timingFor(syntheticRow: safeRow)
        let safeTick = min(max(0, tick), timing.ticks - 1)
        return PlaybackSongFxxRowTiming.frame(rowStartExactFrame: timing.rowStartExactFrame,
            tick: safeTick, bpm: timing.bpm, sampleRate: sampleRate)
    }

    private func timingFor(syntheticRow: Int) -> (rowStartExactFrame: Double, speed: Int, bpm: Int, delay: Int, ticks: Int) {
        if rowTimings.indices.contains(syntheticRow),
           rowTimings[syntheticRow].syntheticRow == syntheticRow {
            let rowTiming = rowTimings[syntheticRow]
            return (
                rowStartExactFrame: rowTiming.rowStartExactFrame,
                speed: rowTiming.effectiveSpeed,
                bpm: rowTiming.effectiveBPM,
                delay: rowTiming.patternDelayCycles, ticks: rowTiming.actualTickCount
            )
        }

        let extraRows = max(0, syntheticRow - rowTimings.count)
        let rowStart = endExactFrame + (Double(extraRows) * rowDuration(speed: finalSpeed, bpm: finalBPM))
        return (rowStartExactFrame: rowStart, speed: finalSpeed, bpm: finalBPM, delay: 0, ticks: finalSpeed)
    }

    private func framesPerTick(bpm: Int) -> Double {
        sampleRate * 2.5 / Double(max(1, bpm))
    }

    private func rowDuration(speed: Int, bpm: Int) -> Double {
        framesPerTick(bpm: bpm) * Double(max(1, speed))
    }

}

enum PlaybackSongFxxTimingPlanner {
    static func plan(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        sampleRate: Double
    ) -> PlaybackSongFxxTimingPlan {
        let traversalPlan = PlaybackSongTraversalPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount
        )
        return plan(song, traversalPlan: traversalPlan, sampleRate: sampleRate)
    }

    static func plan(
        _ song: PlaybackSong,
        traversalPlan: PlaybackSongTraversalPlan,
        sampleRate: Double
    ) -> PlaybackSongFxxTimingPlan {
        let initialConfig = SyntheticTrackerTimingConfig(
            speed: song.initialTiming.speed,
            bpm: song.initialTiming.bpm,
            sampleRate: sampleRate
        )
        var currentSpeed = initialConfig.speed
        var currentBPM = initialConfig.bpm
        var currentExactFrame = 0.0
        var rowTimings = [PlaybackSongFxxRowTiming]()
        var timingChanges = [PlaybackSongSyntheticTimingChangeDiagnostic]()

        for traversalRow in traversalPlan.rows {
            let row = traversalRow.row
            let syntheticRow = traversalRow.syntheticRow
            let source = traversalRow.source
            let rowStartExactFrame = currentExactFrame
            let rowStartFrame = rowTimings.last?.rowEndFrame ?? 0

            // FT2 processes channels at tick 0 before timing that tick. The last
            // speed and BPM commands each win, and both govern this entire row.
            var nextSpeed = currentSpeed
            var nextBPM = currentBPM
            for (channelIndex, cell) in row.cells.enumerated() where isFxxTimingEffect(cell) {
                let speedBefore = nextSpeed
                let bpmBefore = nextBPM
                let kind: PlaybackSongSyntheticTimingChangeDiagnostic.Kind
                let applied: Bool
                switch cell.effectParam {
                case 0:
                    kind = .ignoredF00
                    applied = false
                case 0x01...0x1F:
                    kind = .speed
                    applied = true
                    nextSpeed = Int(cell.effectParam)
                default:
                    kind = .bpm
                    applied = true
                    nextBPM = Int(cell.effectParam)
                }
                timingChanges.append(PlaybackSongSyntheticTimingChangeDiagnostic(
                    source: source,
                    channelIndex: channelIndex,
                    effectType: cell.effectType,
                    effectParam: cell.effectParam,
                    rowStartFrame: rowStartFrame,
                    appliesToSyntheticRowAfter: syntheticRow,
                    kind: kind,
                    applied: applied,
                    speedBefore: speedBefore,
                    bpmBefore: bpmBefore,
                    speedAfter: nextSpeed,
                    bpmAfter: nextBPM
                ))
            }

            currentSpeed = nextSpeed
            currentBPM = nextBPM
            let delay = row.cells.last(where: { $0.effectType == 0x0E && $0.effectParam >> 4 == 0x0E })
                .map { Int($0.effectParam & 15) } ?? 0
            currentExactFrame += rowDuration(
                speed: currentSpeed,
                bpm: currentBPM,
                sampleRate: initialConfig.sampleRate
            ) * Double(delay + 1)
            rowTimings.append(PlaybackSongFxxRowTiming(
                source: source,
                syntheticRow: syntheticRow,
                rowStartExactFrame: rowStartExactFrame,
                rowEndExactFrame: currentExactFrame,
                effectiveSpeed: currentSpeed,
                effectiveBPM: currentBPM,
                patternDelayCycles: delay
            ))
        }

        return PlaybackSongFxxTimingPlan(
            sampleRate: initialConfig.sampleRate,
            initialSpeed: initialConfig.speed,
            initialBPM: initialConfig.bpm,
            rowTimings: rowTimings,
            timingChanges: timingChanges,
            finalSpeed: currentSpeed,
            finalBPM: currentBPM,
            endExactFrame: currentExactFrame
        )
    }

    static func isFxxTimingEffect(_ cell: PlaybackCell) -> Bool {
        cell.effectType == 0x0F
    }

    private static func rowDuration(speed: Int, bpm: Int, sampleRate: Double) -> Double {
        sampleRate * 2.5 / Double(max(1, bpm)) * Double(max(1, speed))
    }
}
