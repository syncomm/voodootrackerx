import Foundation

struct PlaybackSongFxxRowTiming: Equatable {
    let source: PlaybackPosition
    let syntheticRow: Int
    let rowStartExactFrame: Double
    let rowEndExactFrame: Double
    let effectiveSpeed: Int
    let effectiveBPM: Int

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
            effectiveBPM: effectiveBPM
        )
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
            sampleRate: sampleRate
        )
    }

    func frameFor(row: Int, tick: Int = 0) -> Int {
        let safeRow = max(0, row)
        let timing = timingFor(syntheticRow: safeRow)
        let safeTick = min(max(0, tick), timing.speed - 1)
        let exactFrame = timing.rowStartExactFrame + (Double(safeTick) * framesPerTick(bpm: timing.bpm))
        return floorFrame(exactFrame)
    }

    private func timingFor(syntheticRow: Int) -> (rowStartExactFrame: Double, speed: Int, bpm: Int) {
        if rowTimings.indices.contains(syntheticRow),
           rowTimings[syntheticRow].syntheticRow == syntheticRow {
            let rowTiming = rowTimings[syntheticRow]
            return (
                rowStartExactFrame: rowTiming.rowStartExactFrame,
                speed: rowTiming.effectiveSpeed,
                bpm: rowTiming.effectiveBPM
            )
        }

        let extraRows = max(0, syntheticRow - rowTimings.count)
        let rowStart = endExactFrame + (Double(extraRows) * rowDuration(speed: finalSpeed, bpm: finalBPM))
        return (rowStartExactFrame: rowStart, speed: finalSpeed, bpm: finalBPM)
    }

    private func framesPerTick(bpm: Int) -> Double {
        sampleRate * 2.5 / Double(max(1, bpm))
    }

    private func rowDuration(speed: Int, bpm: Int) -> Double {
        framesPerTick(bpm: bpm) * Double(max(1, speed))
    }

    private func floorFrame(_ exactFrame: Double) -> Int {
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
            let rowEndExactFrame = currentExactFrame + rowDuration(
                speed: currentSpeed,
                bpm: currentBPM,
                sampleRate: initialConfig.sampleRate
            )
            let rowTiming = PlaybackSongFxxRowTiming(
                source: source,
                syntheticRow: syntheticRow,
                rowStartExactFrame: rowStartExactFrame,
                rowEndExactFrame: rowEndExactFrame,
                effectiveSpeed: currentSpeed,
                effectiveBPM: currentBPM
            )
            rowTimings.append(rowTiming)

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
                    rowStartFrame: rowTiming.rowStartFrame,
                    appliesToSyntheticRowAfter: syntheticRow + 1,
                    kind: kind,
                    applied: applied,
                    speedBefore: speedBefore,
                    bpmBefore: bpmBefore,
                    speedAfter: nextSpeed,
                    bpmAfter: nextBPM
                ))
            }

            currentExactFrame = rowEndExactFrame
            currentSpeed = nextSpeed
            currentBPM = nextBPM
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

