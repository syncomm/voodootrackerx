import Foundation

/// Partial producer observations: ordinary births (including folded births/E90), declared headers,
/// refusals, ordinary/delayed carried selection, and shared retained-note restart dispatches.
/// Pitch is the producer's canonical selection/base period, never a complete effect output.
/// Array order is capture order; coordinates describe actual occurrences, not a tick reducer.
struct PlaybackSongSelectionDispatchFacts: Equatable {
    enum Coverage { case notAdapterProduced, nativeSelectionProducersV1 }
    enum Domain { case linear, amigaVTX4x }
    enum Pitch: Equatable { case known(Domain, nativePeriod: Double), unavailable }
    enum Role { case trigger, emptySelection, refusedDispatch, carriedInstrument, retainedNoteRestart, coldDispatch, unavailableRoute }
    enum InputOrigin: Equatable {
        case absent, representedHeader, declaredEmptyHeader, finetuneCommand, refusedRoute, neutralDefault
        // References the actual earlier setter, independently for each conversion field.
        case selectionFact(Int)
    }
    struct TuningProducers: Equatable { var baseRate = -1, relativeNote = -1, finetune = -1 }
    struct Fact: Equatable {
        let source: PlaybackPosition
        let syntheticRow: Int, tick: Int, channel: Int, absoluteFrame: Int
        let role: Role
        // Dispatch provenance, independently of whether that dispatch resets clocks.
        let noteOnly: Bool
        let pitch: Pitch
        let semanticInstrument: Int?, semanticSample: Int?, carriedInstrument: Int?
        let carriedNote: UInt8
        let routedInstrument: Int?, mappedSample: Int?
        let selectionMethod: PlaybackSongSyntheticSampleSelectionMethod?
        let associatedGeneration: Int?
        let baseRate: Double?, relativeNote: Int?, finetune: Int?
        let baseRateOrigin: InputOrigin, relativeNoteOrigin: InputOrigin, finetuneOrigin: InputOrigin
        let cachedDefaultVolume: Int, cachedDefaultPan: UInt8
    }
    let coverage: Coverage
    let facts: [Fact]
    // Excludes seven-family outputs, tone targets, E9 clones, release/cut facts and final pitch.
    static let notAdapterProduced = Self(coverage: .notAdapterProduced, facts: [])
}

struct PlaybackSongSyntheticPlan: Equatable {
    let timingConfig: SyntheticTrackerTimingConfig
    let pattern: SyntheticPattern
    var diagnostics: PlaybackSongSyntheticDiagnostics {
        // Arbitrary diagnostic replacement must not leave producer references attached to new storage.
        didSet {
            instrumentAutovibratoClock = .notAdapterProduced
            semanticPitchProjection = .notAdapterProduced
            heldPitchProvenance = .notAdapterProduced
            nativePitchWriterSpans = .notAdapterProduced
            g23ChildlessPitchInvocations = .notAdapterProduced
            rowExitProvenance = .notAdapterProduced
            rowEntryTriggerResetFacts = .notAdapterProduced
            delayedInstrumentResetFacts = .notAdapterProduced
        }
    }
    let canonicalTickClock: PlaybackSongCanonicalTickClock
    let selectionDispatchFacts: PlaybackSongSelectionDispatchFacts
    var instrumentAutovibratoClock: PlaybackSongInstrumentAutovibratoClock = .notAdapterProduced
    // Causal physical step requests, separate from the seven ordinary diagnostic families.
    var instrumentAutovibratoRequests: [PlaybackSongInstrumentAutovibratoPublication.Request] = []
    // Added holds receive new IDs without displacing existing physical writers.
    var instrumentAutovibratoInitialHoldEventIndices: Set<Int> = []
    var semanticPitchProjection: PlaybackSongSemanticPitchProjection = .notAdapterProduced
    var heldPitchProvenance: PlaybackSongHeldPitchProvenance = .notAdapterProduced
    var nativePitchWriterSpans: PlaybackSongNativePitchWriterSpans = .notAdapterProduced
    var g23ChildlessPitchInvocations: PlaybackSongG23ChildlessPitchInvocations = .notAdapterProduced
    var rowExitProvenance: PlaybackSongRowExitProvenance = .notAdapterProduced
    var rowEntryTriggerResetFacts: PlaybackSongRowEntryTriggerResetFacts = .notAdapterProduced
    var delayedInstrumentResetFacts: PlaybackSongDelayedInstrumentResetFacts = .notAdapterProduced
    var noteOnlyEventIndices: Set<Int> = []
    var coldReleasedEventIndices: Set<Int> = []
    var playbackStateEvents: [PlaybackVoiceStateEvent] = [] {
        didSet {
            var timeline = xmEnvelopeTimeline
            timeline?.rebuild(plan: self)
            xmEnvelopeTimeline = timeline
        }
    }
    var xmEnvelopeTimeline: PlaybackXMEnvelopeTimeline? = nil {
        didSet { xmAudibleTimeline = xmEnvelopeTimeline == nil ? nil : PlaybackXMAudibleTimeline(plan: self) }
    }
    var xmAudibleTimeline: PlaybackXMAudibleTimeline? = nil
    var xmChannelRows: [PlaybackXMChannelRow] = []
    var xmEmptyRoutes: [PlaybackXMEmptyRoute] = []
    var xmInstrumentSelections: [PlaybackXMInstrumentSelection] = []
    // A cold effective-zero trigger starts PCM, then holds it before its first frame.
    var initialHeldPitchEventIndices: Set<Int> = []
}

/// Targets the existing trigger event identity, never a reusable mixer slot.
struct PlaybackVoiceStateEvent: Equatable {
    let activeEventIndex: Int
    let channelIndex: Int
    let scheduledFrame: Int
    let change: MixerPlaybackStateChange
}

enum PlaybackSongSyntheticAdapter {
    static let maxMixerEnvelopePointCount = 12
    static let xmLinearPeriodBase = 7_680.0
    static let xmLinearC4Period = 4_608.0
    static let xmLinearPeriodUnitsPerSemitone = 64.0
    static let xmLinearPeriodUnitsPerOctave = 768.0
    // FT2 regular/tone slides and E1x/E2x use param << 2; X1x/X2x use param.
    static let xmLinearPortamentoUnitsPerParam = 4.0
    static let xmLinearMaximumRealNoteIndex = 118
    static let xmLinearMaximumEffectiveNoteValue = xmLinearMaximumRealNoteIndex + 1
    static let xmLinearMinimumSafePeriod = xmLinearPeriodBase
        - (Double(xmLinearMaximumRealNoteIndex) * xmLinearPeriodUnitsPerSemitone)
        - (127.0 / 2.0)
    static let xmLinearMaximumSafePeriod = xmLinearPeriodBase + 64.0
    static let xmAmigaC4Period = 6_848.0
    // Amiga state and its frequency numerator are both 4x the FT2 table domain.
    static let xmAmigaPortamentoUnitsPerParam = 4.0 * xmAmigaPeriodLookupScale
    static let xmAmigaMinimumSafePeriod = 107.0
    static let xmAmigaMaximumSafePeriod = 438_272.0

    struct ChannelState: Equatable {
        // Existing tracker-volume writers change base and output together. There is no
        // row-boundary reset: a later transient effect may retain output independently.
        var baseChannelVolume = 64 {
            didSet { outputChannelVolume = baseChannelVolume }
        }
        var outputChannelVolume = 64
        // Carried instrument memory is independent of the sounding generation.
        // A declared empty header also refreshes defaults, without an audio source.
        var carriedInstrumentIndex: Int?
        var semanticInstrumentIndex: Int?
        var semanticSampleIndex: Int?
        var semanticVolumeEnvelopeEnabled = false
        // Last triggered XM note survives source completion and exact empty routing.
        // Keep this byte beside the flag, using existing alignment padding.
        var carriedNote: UInt8 = 0
        // Literal zero is semantic state; nonzero values also prove nonzero origin.
        // These bytes use padding and survive instrument/source/counter resets.
        var rRetriggerSpeedMemory: UInt8 = 0
        var rVolumeModeMemory: UInt8 = 0
        var rRetriggerCounter: UInt8 = 0
        // The channel-owned latch uses existing byte-alignment padding.
        var tonePortamentoDirection: PlaybackSongSyntheticTonePortamentoDirection = .none
        var panningSlideMemory: UInt8 = 0 // Own whole byte; admitted only by executed nonzero ticks.
        var triggeredSampleDefaultVolume = 0
        var triggeredSampleDefaultPan: UInt8 = 128
        var keyOffWithoutVoice = false
        var volumeValueZeroedByAxy = false
        var panningValue = 127.5
        var pan: Float = 0
        var activeEventIndex: Int?
        var activeEventMappingIndex: Int?
        var activeInstrumentIndex: Int?
        var activeSampleIndex: Int?
        // Represented header metadata/availability, never an additional song-gain factor.
        var activeSampleVolume: Float?
        // Period/envelope controls can belong to a silent channel. Only the event
        // association and represented sample availability authorize source-voice updates.
        var activePlaybackStep: Double?
        var activeLinearPeriod: Double?
        var activeAmigaPeriod: Double?
        var activeSampleBaseSampleRate: Double?
        var activeSampleRelativeNote: Int?
        var activeSampleFinetune: Int?
        var activeUsesLinearFrequencyTable: Bool?
        var activeVolumeEnvelopeStatus: PlaybackSongSyntheticEventMapping.VolumeEnvelopeStatus?
        var activeVolumeEnvelopeMaxFrame: Int?
        var activeVolumeEnvelopeSourcePointCount = 0
        var activeVolumeEnvelopeMappedPointCount = 0
        var tonePortamentoTargetNote: UInt8?
        var tonePortamentoTargetLinearPeriod: Double?
        var tonePortamentoTargetAmigaPeriod: Double?
        var tonePortamentoTargetPlaybackStep: Double?
        var tonePortamentoSpeed: Int?
        var sampleOffsetMemory: SampleOffsetMemory?
        var portamentoUpMemory: PortamentoSlideMemory?
        var portamentoDownMemory: PortamentoSlideMemory?
        var finePitchUpMemory: FinePitchMemory?
        var finePitchDownMemory: FinePitchMemory?
        var extraFinePitchUpMemory: FinePitchMemory?
        var extraFinePitchDownMemory: FinePitchMemory?
        var volumeSlideMemory: VolumeSlideMemory? // Shared Axy/5xy/6xy full parameter and origin.
        var fineVolumeUpMemory: FineVolumeSlideMemory?
        var fineVolumeDownMemory: FineVolumeSlideMemory?
        var globalVolumeSlideMemory: GlobalVolumeSlideMemory? // Hxy only; global volume itself is song-owned.
        var vibratoSpeed = 0
        var vibratoDepth = 0
        var vibratoSpeedMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var vibratoDepthMemorySource: PlaybackSongSyntheticEffectMemorySource?
        var vibratoControl: VibratoControlState?
        var vibratoPhase = 0
        var vibratoOutputLinearPeriod: Double?
        var vibratoOutputAmigaPeriod: Double?
        var tremolo = TremoloState()
        // FT2's ramp tremolo reads the sign of the vibrato phase. This observer
        // serves that quirk only; it does not change the existing pitch planner.
        var tremoloVibratoPhase = 0
        var tremoloVibratoSpeed = 0
        var tremoloVibratoControl = 0

        mutating func resolveRxyMemory(_ parameter: UInt8) {
            if parameter & 15 != 0 { rRetriggerSpeedMemory = parameter & 15 }
            if parameter >> 4 != 0 { rVolumeModeMemory = parameter >> 4 }
        }

        mutating func initializePanning(fromSampleHeader value: UInt8) {
            panningValue = Double(value)
            pan = PlaybackSamplePanningPolicy.plannedPan(value)
        }

        mutating func applyChannelPanningValue(_ value: Double) {
            panningValue = PlaybackSongSyntheticAdapter.clampedPanningValue(value)
            pan = PlaybackSongVolumeColumnDecoder.audioPan(forXMValue: panningValue)
        }
    }

    struct SampleOffsetMemory: Equatable {
        let offsetFrames: Int
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    struct PortamentoSlideMemory: Equatable {
        let amount: Int
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    struct VolumeSlideMemory: Equatable {
        let parameter: UInt8
        let source: PlaybackSongSyntheticEffectMemorySource

        var slide: VolumeSlideAmounts {
            PlaybackSongSyntheticAdapter.axyVolumeSlideAmounts(effectParam: parameter)
        }
    }

    struct FinePitchMemory: Equatable {
        let amount: Int
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    struct GlobalVolumeSlideMemory: Equatable {
        let parameter: UInt8
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    struct FineVolumeSlideMemory: Equatable {
        let amount: Int
        let source: PlaybackSongSyntheticEffectMemorySource
    }

    struct VibratoControlState: Equatable {
        let controlValue: Int
        let waveform: VibratoWaveform
        let retriggerSuppressed: Bool
        let source: PlaybackSongSyntheticEffectMemorySource?
    }

    enum VibratoWaveform: Int, Equatable {
        case sine = 0
        case rampDown = 1
        case square = 2

        var name: String {
            switch self {
            case .sine:
                return "sine"
            case .rampDown:
                return "ramp_down"
            case .square:
                return "square"
            }
        }
    }

    struct GlobalVolumeState: Equatable {
        static let defaultValue = 64

        var volumeValue = defaultValue

        var multiplier: Float {
            globalVolumeMultiplier(for: volumeValue)
        }
    }

    struct GlobalVolumeSlidePlan: Equatable {
        let up: Int
        let down: Int
        let direction: PlaybackSongSyntheticGlobalVolumeSlideDirection
        let amount: Int
        let bothNibblesNonzero: Bool
        let policy: String?
    }

    struct VolumeSlideAmounts: Equatable {
        let up: Int
        let down: Int
        let direction: String
        let amount: Int
        let rawUpNibble: Int
        let rawDownNibble: Int
        let bothNibblesNonzero: Bool
        let policy: String
    }

    struct SampleSelection: Equatable {
        let sample: PlaybackSample?
        let diagnosticSample: PlaybackSample?
        let skippedReason: PlaybackSongSyntheticIgnoredCell.Reason?
        let sampleMapKeymapPresent: Bool
        let mappedSampleIndex: Int?
        let mappedSampleValid: Bool
        let method: PlaybackSongSyntheticSampleSelectionMethod
        let firstPlayableSampleFallbackUsed: Bool
        let sampleMapKeymapBehaviorDeferred: Bool
        let sampleMapKeymapMissingOrDeferred: Bool
    }

    struct MixerSampleBufferCacheKey: Hashable {
        let storageAddress: UInt
        let frameCount: Int
    }

    static func clearActiveVoiceState(_ state: inout ChannelState) {
        state.activeEventIndex = nil
        state.activeEventMappingIndex = nil
        state.activeInstrumentIndex = nil
        state.activeSampleIndex = nil
        state.activeSampleVolume = nil
        state.activePlaybackStep = nil
        state.activeLinearPeriod = nil
        state.vibratoOutputLinearPeriod = nil
        state.vibratoOutputAmigaPeriod = nil
        state.activeAmigaPeriod = nil
        state.activeSampleBaseSampleRate = nil
        state.activeSampleRelativeNote = nil
        state.activeSampleFinetune = nil
        state.activeUsesLinearFrequencyTable = nil
        state.activeVolumeEnvelopeStatus = nil
        state.activeVolumeEnvelopeMaxFrame = nil
        state.activeVolumeEnvelopeSourcePointCount = 0
        state.activeVolumeEnvelopeMappedPointCount = 0
        state.tonePortamentoTargetNote = nil
        state.tonePortamentoTargetLinearPeriod = nil
        state.tonePortamentoTargetAmigaPeriod = nil
        state.tonePortamentoTargetPlaybackStep = nil
        state.tonePortamentoDirection = .none
    }

    static func effectMemorySource(
        source: PlaybackPosition,
        channelIndex: Int,
        cell: PlaybackCell
    ) -> PlaybackSongSyntheticEffectMemorySource {
        PlaybackSongSyntheticEffectMemorySource(
            source: source,
            channelIndex: channelIndex,
            effectType: cell.effectType,
            effectParam: cell.effectParam
        )
    }

    static func memoryUnavailableReason(from reasons: [String]) -> String? {
        let uniqueReasons = Set(reasons)
        if uniqueReasons.contains("missing_vibrato_speed_memory"),
           uniqueReasons.contains("missing_vibrato_depth_memory") {
            return "missing_vibrato_speed_depth_memory"
        }
        return reasons.first
    }

    struct EventCoverageBuilder: Equatable {
        var totalCellsVisited = 0
        var emptyCells = 0
        var normalNoteCells = 0
        var noteOffCells = 0
        var invalidNoteCells = 0
        var instrumentOnlyCells = 0
        var noteWithInstrumentCells = 0
        var noteWithMissingOrZeroInstrumentCells = 0
        var scheduledNoteEvents = 0
        var skippedNoteEvents = 0
        var skippedNoteOffEventsNoActiveVoice = 0
        var ignoredOrDeferredCells = 0
        var sampleMapSelectionEvents = 0
        var firstPlayableSampleFallbackEvents = 0
        var fallbackAfterInvalidSampleMapEvents = 0
        var skippedNoValidSampleEvents = 0
        var sampleMapKeymapDeferredEvents = 0
        var eventOutsideBoundedRowRangeCount = 0
        var eventCapacityLimitCount = 0
        var cMixerVoiceCapacityLimitCount = 0
        var skipReasonCounts = [PlaybackSongSyntheticSkipReason: Int]()

        /// Records coverage and returns the existing classification of completely empty cells.
        mutating func visit(_ cell: PlaybackCell) -> Bool {
            totalCellsVisited += 1
            if isCompletelyEmpty(cell) {
                emptyCells += 1
                return true
            }
            if (1...96).contains(cell.note) {
                normalNoteCells += 1
                if cell.instrument > 0 {
                    noteWithInstrumentCells += 1
                } else {
                    noteWithMissingOrZeroInstrumentCells += 1
                }
            } else if cell.note == 97 {
                noteOffCells += 1
            } else if cell.note > 97 {
                invalidNoteCells += 1
            } else if cell.note == 0, cell.instrument > 0, cell.volumeColumn == 0, cell.effectType == 0, cell.effectParam == 0 {
                instrumentOnlyCells += 1
            }
            return false
        }

        mutating func recordScheduledNote(
            method: PlaybackSongSyntheticSampleSelectionMethod,
            firstPlayableSampleFallbackUsed: Bool,
            sampleMapKeymapBehaviorDeferred: Bool
        ) {
            scheduledNoteEvents += 1
            if method == .sampleMap {
                sampleMapSelectionEvents += 1
            }
            if firstPlayableSampleFallbackUsed {
                firstPlayableSampleFallbackEvents += 1
            }
            if method == .fallbackAfterInvalidMap {
                fallbackAfterInvalidSampleMapEvents += 1
            }
            if sampleMapKeymapBehaviorDeferred {
                sampleMapKeymapDeferredEvents += 1
            }
        }

        mutating func recordSkippedSampleSelection(
            method: PlaybackSongSyntheticSampleSelectionMethod,
            sampleMapKeymapBehaviorDeferred: Bool
        ) {
            if method == .skippedNoValidSample {
                skippedNoValidSampleEvents += 1
            }
            if sampleMapKeymapBehaviorDeferred {
                sampleMapKeymapDeferredEvents += 1
            }
        }

        mutating func recordIgnoredCell(
            reason: PlaybackSongSyntheticSkipReason,
            isNormalNote: Bool,
            isNoteOffWithoutActiveVoice: Bool = false
        ) {
            ignoredOrDeferredCells += 1
            skipReasonCounts[reason, default: 0] += 1
            if isNormalNote {
                skippedNoteEvents += 1
            }
            if isNoteOffWithoutActiveVoice {
                skippedNoteOffEventsNoActiveVoice += 1
            }
        }

        mutating func recordDeferredCellWithoutSkip() {
            ignoredOrDeferredCells += 1
            skipReasonCounts[.unsupportedDeferredEffectInteraction, default: 0] += 1
        }

        var summary: PlaybackSongSyntheticEventCoverageSummary {
            PlaybackSongSyntheticEventCoverageSummary(
                totalCellsVisited: totalCellsVisited,
                emptyCells: emptyCells,
                normalNoteCells: normalNoteCells,
                noteOffCells: noteOffCells,
                invalidNoteCells: invalidNoteCells,
                instrumentOnlyCells: instrumentOnlyCells,
                noteWithInstrumentCells: noteWithInstrumentCells,
                noteWithMissingOrZeroInstrumentCells: noteWithMissingOrZeroInstrumentCells,
                scheduledNoteEvents: scheduledNoteEvents,
                skippedNoteEvents: skippedNoteEvents,
                skippedNoteOffEventsNoActiveVoice: skippedNoteOffEventsNoActiveVoice,
                ignoredOrDeferredCells: ignoredOrDeferredCells,
                sampleMapSelectionEvents: sampleMapSelectionEvents,
                firstPlayableSampleFallbackEvents: firstPlayableSampleFallbackEvents,
                fallbackAfterInvalidSampleMapEvents: fallbackAfterInvalidSampleMapEvents,
                skippedNoValidSampleEvents: skippedNoValidSampleEvents,
                sampleMapKeymapDeferredEvents: sampleMapKeymapDeferredEvents,
                eventOutsideBoundedRowRangeCount: eventOutsideBoundedRowRangeCount,
                eventCapacityLimitCount: eventCapacityLimitCount,
                cMixerVoiceCapacityLimitCount: cMixerVoiceCapacityLimitCount,
                skipReasonCounts: skipReasonCounts
                    .map { PlaybackSongSyntheticSkipReasonCount(reason: $0.key, count: $0.value) }
                    .sorted { lhs, rhs in
                        if lhs.count != rhs.count {
                            return lhs.count > rhs.count
                        }
                        return lhs.reason.rawValue < rhs.reason.rawValue
                    }
            )
        }

        private func isCompletelyEmpty(_ cell: PlaybackCell) -> Bool {
            cell.note == 0 &&
                cell.instrument == 0 &&
                cell.volumeColumn == 0 &&
                cell.effectType == 0 &&
                cell.effectParam == 0
        }
    }

    struct TraversalEffectKey: Hashable {
        let orderIndex: Int
        let patternIndex: Int
        let rowIndex: Int
        let channelIndex: Int
        let syntheticRow: Int
        let effectType: UInt8
        let effectParam: UInt8
    }

    struct AdapterRowContext {
        var semanticPitchBuilder = PlaybackSongSemanticPitchProjection.Builder()
        var heldPitchObserver = PlaybackSongHeldPitchProvenance.Observer()
        var nativePitchWriterObserver = PlaybackSongNativePitchWriterSpans.Observer()
        var rowExitObserver = PlaybackSongRowExitProvenance.Observer()
        var rowEntryTriggerResetObserver = PlaybackSongRowEntryTriggerResetFacts.Observer()
        var delayedInstrumentResetObserver = PlaybackSongDelayedInstrumentResetFacts.Observer()
        var g23ChildlessPitchInvocationObserver = PlaybackSongG23ChildlessPitchInvocations.Observer()
        var selectionFacts = [PlaybackSongSelectionDispatchFacts.Fact]()
        var selectionTuningProducers = [PlaybackSongSelectionDispatchFacts.TuningProducers]()
        var selectionFactStorageGrowthCount = 0
        let emptyVolumeColumn = PlaybackSongVolumeColumnDecoder.decode(0)
        var emptyCellFastPathCount = 0
        var fullCellDispatchCount = 0
        var rowDiagnostics = [PlaybackSongSyntheticRowDiagnostic]()
        var volumeColumnMappings = [PlaybackSongSyntheticVolumeColumnMapping]()
        var voiceStateUpdates = [PlaybackSongSyntheticVoiceStateUpdateDiagnostic]()
        var playbackStateEvents = [PlaybackVoiceStateEvent]()
        var noteOnlyEventIndices = Set<Int>()
        var coldReleasedEventIndices = Set<Int>()
        var xmChannelRows = [PlaybackXMChannelRow]()
        var xmEmptyRoutes = [PlaybackXMEmptyRoute]()
        var xmInstrumentSelections = [PlaybackXMInstrumentSelection]()
        var initialHeldPitchEventIndices = Set<Int>()
        var sampleOffsetEffects = [PlaybackSongSyntheticSampleOffsetDiagnostic]()
        var setFinetuneEffects = [PlaybackSongSyntheticSetFinetuneDiagnostic]()
        var envelopePositionEffects = [PlaybackSongSyntheticEnvelopePositionDiagnostic]()
        var noteCutEffects = [PlaybackSongSyntheticNoteCutDiagnostic]()
        var noteDelayEffects = [PlaybackSongSyntheticNoteDelayDiagnostic]()
        var retriggerEffects = [PlaybackSongSyntheticRetriggerDiagnostic]()
        var tonePortamentoEffects = [PlaybackSongSyntheticTonePortamentoDiagnostic]()
        var portamentoSlideEffects = [PlaybackSongSyntheticPortamentoSlideDiagnostic]()
        var finePortamentoUpEffects = [PlaybackSongSyntheticFinePortamentoUpDiagnostic]()
        var finePortamentoDownEffects = [PlaybackSongSyntheticFinePortamentoDownDiagnostic]()
        var extraFinePortamentoEffects = [PlaybackSongSyntheticExtraFinePortamentoDiagnostic]()
        var arpeggioEffects = [PlaybackSongSyntheticArpeggioDiagnostic]()
        var vibratoControlEffects = [PlaybackSongSyntheticVibratoControlDiagnostic]()
        var vibratoEffects = [PlaybackSongSyntheticVibratoDiagnostic]()
        var ordinaryDelayedVibratoIndices = [Int]()
        var keyOffEvents = [PlaybackSongSyntheticKeyOffDiagnostic]()
        var effectCommandDiagnostics = [PlaybackSongSyntheticEffectCommandDiagnostic]()
        var eventMappings = [PlaybackSongSyntheticEventMapping]()
        var ignoredCells = [PlaybackSongSyntheticIgnoredCell]()
        var deferredCellFields = [PlaybackSongSyntheticDeferredCellField]()
        var eventCoverage = EventCoverageBuilder()
        var events = [SyntheticTrackerEvent]()
        var channelStates = [ChannelState]()
        var mixerSampleBuffers = [MixerSampleBufferCacheKey: MixerSampleBuffer]()
        var globalVolumeState = GlobalVolumeState()
        var traversalEffectStatuses = [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status]()
    }

    /// Observes existing producer scalars. Provenance cursors never participate in musical decisions.
    static func captureSelection(source: PlaybackPosition, row: Int, tick: Int, channel: Int, frame: Int,
        role: PlaybackSongSelectionDispatchFacts.Role, linear: Bool, noteOnly: Bool = false,
        tuning: PlaybackSongSelectionDispatchFacts.InputOrigin? = nil, finetuneCommand: Bool = false,
        defaultedBaseRate: Bool = false, defaultedFinetune: Bool = false,
        routedInstrument: Int? = nil, selection: SampleSelection? = nil,
        state: borrowing ChannelState, context: inout AdapterRowContext) {
        typealias Origin = PlaybackSongSelectionDispatchFacts.InputOrigin
        let index = context.selectionFacts.count
        var producers = context.selectionTuningProducers[channel]
        func origin(_ valuePresent: Bool, _ producer: inout Int, update: Origin?) -> Origin {
            guard valuePresent else { producer = -1; return .absent }
            if let update { producer = index; return update }
            precondition(producer >= 0, "Selection input has no captured producer")
            return .selectionFact(producer)
        }
        let base = origin(state.activeSampleBaseSampleRate != nil, &producers.baseRate,
            update: defaultedBaseRate || tuning == .declaredEmptyHeader ? .neutralDefault : tuning == .refusedRoute ? nil : tuning)
        let relative = origin(state.activeSampleRelativeNote != nil, &producers.relativeNote, update: tuning)
        let fine = origin(state.activeSampleFinetune != nil, &producers.finetune,
            update: defaultedFinetune ? .neutralDefault : tuning == .refusedRoute ? nil : finetuneCommand ? .finetuneCommand : tuning)
        let period = linear ? state.activeLinearPeriod : state.activeAmigaPeriod
        let selectedInstrument = tuning == nil ? nil : state.semanticInstrumentIndex
        let selectedSample = tuning == nil ? nil : state.semanticSampleIndex
        let capacity = context.selectionFacts.capacity
        context.selectionFacts.append(.init(source: source, syntheticRow: row, tick: tick, channel: channel,
            absoluteFrame: frame, role: role, noteOnly: noteOnly,
            pitch: period.map { .known(linear ? .linear : .amigaVTX4x, nativePeriod: $0) } ?? .unavailable,
            semanticInstrument: state.semanticInstrumentIndex, semanticSample: state.semanticSampleIndex,
            carriedInstrument: state.carriedInstrumentIndex, carriedNote: state.carriedNote,
            routedInstrument: routedInstrument ?? selectedInstrument, mappedSample: selection?.mappedSampleIndex ?? selectedSample,
            selectionMethod: selection?.method, associatedGeneration: state.activeEventIndex,
            baseRate: state.activeSampleBaseSampleRate, relativeNote: state.activeSampleRelativeNote, finetune: state.activeSampleFinetune,
            baseRateOrigin: base, relativeNoteOrigin: relative, finetuneOrigin: fine,
            cachedDefaultVolume: state.triggeredSampleDefaultVolume, cachedDefaultPan: state.triggeredSampleDefaultPan))
        if context.selectionFacts.capacity != capacity { context.selectionFactStorageGrowthCount += 1 }
        context.selectionTuningProducers[channel] = producers
        context.semanticPitchBuilder.add(tick: tick, channel: channel, action: .selection(index))
    }

    static func adapt(
        _ song: PlaybackSong,
        orderIndex: Int,
        sampleRate: Double,
        profileSession: AdapterPlanProfileSession? = nil
    ) -> PlaybackSongSyntheticPlan {
        adapt(song, startOrderIndex: orderIndex, orderCount: 1, sampleRate: sampleRate, profileSession: profileSession)
    }

    static func adapt(
        _ song: PlaybackSong,
        orderRange: Range<Int>,
        sampleRate: Double,
        profileSession: AdapterPlanProfileSession? = nil
    ) -> PlaybackSongSyntheticPlan {
        adapt(
            song,
            startOrderIndex: orderRange.lowerBound,
            orderCount: max(0, orderRange.count),
            sampleRate: sampleRate,
            profileSession: profileSession
        )
    }

    static func adapt(
        _ song: PlaybackSong,
        startOrderIndex: Int,
        orderCount: Int,
        sampleRate: Double,
        profileSession: AdapterPlanProfileSession? = nil
    ) -> PlaybackSongSyntheticPlan {
        adapt(song, startOrderIndex: startOrderIndex, orderCount: orderCount, sampleRate: sampleRate,
              profileSession: profileSession, eligibilityOracle: nil)
    }

    #if DEBUG
    /// Equivalence oracle only: production uses the indexed projection of this same predicate.
    static func adaptUsingScanEligibility(_ song: PlaybackSong, startOrderIndex: Int = 0,
                                          orderCount: Int, sampleRate: Double) -> PlaybackSongSyntheticPlan {
        adapt(song, startOrderIndex: startOrderIndex, orderCount: orderCount, sampleRate: sampleRate,
              profileSession: nil, eligibilityOracle: { event, frame, plan in
                  PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: event, at: frame, plan: plan)
              })
    }

    /// Test-only injection of the frozen pre-compaction projection into a complete adapter plan.
    static func adaptUsingGlobalVolumeProjection(_ song: PlaybackSong, startOrderIndex: Int = 0,
        orderCount: Int, sampleRate: Double,
        oracle: @escaping (PlaybackSongFxxTimingPlan, inout AdapterRowContext) -> Void) -> PlaybackSongSyntheticPlan {
        adapt(song, startOrderIndex: startOrderIndex, orderCount: orderCount, sampleRate: sampleRate,
              profileSession: nil, eligibilityOracle: nil, globalVolumeProjectionOracle: oracle)
    }
    #endif

    private static func adapt(
        _ song: PlaybackSong, startOrderIndex: Int, orderCount: Int, sampleRate: Double,
        profileSession: AdapterPlanProfileSession?,
        eligibilityOracle: ((Int, Int, PlaybackSongSyntheticPlan) -> Bool)?,
        globalVolumeProjectionOracle: ((PlaybackSongFxxTimingPlan, inout AdapterRowContext) -> Void)? = nil
    ) -> PlaybackSongSyntheticPlan {
        let totalStart = profileSession?.beginPhase()
        let traversalStart = profileSession?.beginPhase()
        let traversalPlan = PlaybackSongTraversalPlanner.plan(
            song,
            startOrderIndex: startOrderIndex,
            orderCount: orderCount
        )
        profileSession?.recordPhase(
            "order_traversal",
            startedAt: traversalStart,
            fields: AdapterPlanProfileFields.playbackSong(song) + [
                AdapterPlanProfileField("requested_start_order_index", startOrderIndex),
                AdapterPlanProfileField("requested_order_count", max(0, orderCount)),
                AdapterPlanProfileField("row_count", traversalPlan.pathLength),
                AdapterPlanProfileField("adapted_order_count", traversalPlan.adaptedOrders.count),
                AdapterPlanProfileField("traversal_diagnostic_count", traversalPlan.traversalDiagnostics.count),
                AdapterPlanProfileField("traversal_guard_hit", traversalPlan.guardHit),
                AdapterPlanProfileField("traversal_stop_reason", traversalPlan.stopReason.rawValue),
            ]
        )
        let timingStart = profileSession?.beginPhase()
        let timingPlan = PlaybackSongFxxTimingPlanner.plan(
            song,
            traversalPlan: traversalPlan,
            sampleRate: sampleRate
        )
        profileSession?.recordPhase(
            "timing_frame_calculation",
            startedAt: timingStart,
            fields: [
                AdapterPlanProfileField("row_count", timingPlan.rowTimings.count),
                AdapterPlanProfileField("timing_change_count", timingPlan.timingChanges.count),
                AdapterPlanProfileField("initial_speed", timingPlan.initialSpeed),
                AdapterPlanProfileField("initial_bpm", timingPlan.initialBPM),
                AdapterPlanProfileField("final_speed", timingPlan.finalSpeed),
                AdapterPlanProfileField("final_bpm", timingPlan.finalBPM),
            ]
        )
        let timingConfig = SyntheticTrackerTimingConfig(
            speed: timingPlan.initialSpeed,
            bpm: timingPlan.initialBPM,
            sampleRate: timingPlan.sampleRate
        )
        let safeOrderCount = max(0, orderCount)
        var rowMappings = [PlaybackSongSyntheticRowMapping]()
        var context = AdapterRowContext()
        // Keep the optional composition workspace out of every ordinary row helper.
        var automaticPitchBuilder = PlaybackSongInstrumentAutovibratoPublication.Builder()
        let automaticEnabled = song.instrumentsByIndex.values.contains { $0.autoVibrato.depth > 0 && $0.autoVibrato.rate > 0 }
        automaticPitchBuilder.enabled = automaticEnabled
        let estimatedRows = timingPlan.rowTimings.count
        var clockRuns = [PlaybackSongCanonicalTickClock.ClockRun]()
        clockRuns.reserveCapacity(estimatedRows)
        var canonicalTickCount = 0

        rowMappings.reserveCapacity(estimatedRows)
        context.rowDiagnostics.reserveCapacity(estimatedRows)
        context.events.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.eventMappings.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.ignoredCells.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.deferredCellFields.reserveCapacity(min(estimatedRows * 4, 65_536))
        context.effectCommandDiagnostics.reserveCapacity(min(estimatedRows, 65_536))
        context.volumeColumnMappings.reserveCapacity(min(estimatedRows, 65_536))
        context.voiceStateUpdates.reserveCapacity(min(estimatedRows * 2, 65_536))
        context.channelStates.reserveCapacity(traversalPlan.rows.reduce(0) { max($0, $1.row.cells.count) })
        context.mixerSampleBuffers.reserveCapacity(song.instrumentsByIndex.values.reduce(0) { $0 + $1.samples.count })
        let traversalStatusStart = profileSession?.beginPhase()
        context.traversalEffectStatuses = traversalEffectStatuses(from: traversalPlan.traversalDiagnostics)
        profileSession?.recordPhase(
            "traversal_effect_status_indexing",
            startedAt: traversalStatusStart,
            fields: [
                AdapterPlanProfileField("traversal_diagnostic_count", traversalPlan.traversalDiagnostics.count),
                AdapterPlanProfileField("traversal_effect_status_count", context.traversalEffectStatuses.count),
            ]
        )

        let rowIterationStart = profileSession?.beginPhase()
        var eventGenerationNanoseconds: UInt64 = 0
        var semanticPublicationNanoseconds: UInt64 = 0
        for (rowIndex, traversalRow) in traversalPlan.rows.enumerated() {
            rowMappings.append(PlaybackSongSyntheticRowMapping(
                source: traversalRow.source,
                syntheticRow: traversalRow.syntheticRow
            ))
            let rowTiming = timingPlan.rowTimings.indices.contains(traversalRow.syntheticRow)
                ? timingPlan.rowTimings[traversalRow.syntheticRow]
                : nil
            let rowTimingConfig = rowTiming.map { timing in
                SyntheticTrackerTimingConfig(
                    speed: timing.effectiveSpeed,
                    bpm: timing.effectiveBPM,
                    sampleRate: timingPlan.sampleRate
                )
            } ?? timingPlan.timingConfig(forSyntheticRow: traversalRow.syntheticRow)
            let nextOrdinal = canonicalTickCount.addingReportingOverflow(rowTimingConfig.speed)
            precondition(!nextOrdinal.overflow, "Canonical tick ordinal overflow")
            clockRuns.append(.init(timingRowIndex: traversalRow.syntheticRow, firstCanonicalTickOrdinal: canonicalTickCount))
            canonicalTickCount = nextOrdinal.partialValue
            let eventGenerationStart = profileSession == nil ? nil : DispatchTime.now().uptimeNanoseconds
            context.semanticPitchBuilder.begin(states: context.channelStates, count: traversalRow.row.cells.count,
                firstOrdinal: canonicalTickCount - rowTimingConfig.speed, speed: rowTimingConfig.speed, linear: song.usesLinearFrequencyTable,
                retriggers: context.retriggerEffects.count, rowResets: context.rowEntryTriggerResetObserver.facts.count,
                delayedResets: context.delayedInstrumentResetObserver.facts.count, exits: context.rowExitObserver.references.count, rows: context.xmChannelRows.count)
            context.semanticPitchBuilder.firstRelease = context.keyOffEvents.count
            let rowDiagnostic = appendEvents(
                from: traversalRow.row,
                source: traversalRow.source,
                syntheticRow: traversalRow.syntheticRow,
                song: song,
                timingConfig: rowTimingConfig,
                timingPlan: timingPlan,
                scheduledStartFrame: rowTiming?.rowStartFrame ?? timingPlan.frameFor(row: traversalRow.syntheticRow, tick: 0),
                nextRow: traversalPlan.rows.indices.contains(rowIndex + 1) ? traversalPlan.rows[rowIndex + 1].row : nil,
                context: &context
            )
            if let eventGenerationStart {
                let eventGenerationEnd = DispatchTime.now().uptimeNanoseconds
                if eventGenerationEnd >= eventGenerationStart {
                    eventGenerationNanoseconds += eventGenerationEnd - eventGenerationStart
                }
            }
            let publicationStart = profileSession == nil ? nil : DispatchTime.now().uptimeNanoseconds
            finishSemanticPitchRow(context: &context, song: song)
            if automaticEnabled {
                materializeInstrumentAutovibratoRow(context: &context, builder: &automaticPitchBuilder, source: traversalRow.source,
                    row: traversalRow.syntheticRow, channelCount: traversalRow.row.cells.count,
                    timingConfig: rowTimingConfig, timingPlan: timingPlan)
            }
            if let publicationStart { semanticPublicationNanoseconds += DispatchTime.now().uptimeNanoseconds - publicationStart }
            context.rowDiagnostics.append(rowDiagnostic)
        }
        if automaticEnabled { finishInstrumentAutovibratoTail(context: &context, builder: &automaticPitchBuilder) }
        profileSession?.recordMeasuredPhase("semantic_pitch_publication", elapsedMS: Double(semanticPublicationNanoseconds) / 1_000_000.0,
            fields: [AdapterPlanProfileField("semantic_pitch_capture_failures", context.semanticPitchBuilder.failures)])
        profileSession?.recordMeasuredPhase(
            "event_generation",
            elapsedMS: Double(eventGenerationNanoseconds) / 1_000_000.0,
            fields: [
                AdapterPlanProfileField("row_count", traversalPlan.pathLength),
                AdapterPlanProfileField("synthetic_event_count", context.events.count),
                AdapterPlanProfileField("event_mapping_count", context.eventMappings.count),
                AdapterPlanProfileField("ignored_cell_count", context.ignoredCells.count),
                AdapterPlanProfileField("voice_state_update_count", context.voiceStateUpdates.count),
                AdapterPlanProfileField("empty_cell_bypass_count", context.emptyCellFastPathCount),
                AdapterPlanProfileField("full_cell_dispatch_count", context.fullCellDispatchCount),
                AdapterPlanProfileField("selection_fact_count", context.selectionFacts.count),
                AdapterPlanProfileField("selection_fact_stride", MemoryLayout<PlaybackSongSelectionDispatchFacts.Fact>.stride),
                AdapterPlanProfileField("selection_fact_capacity", context.selectionFacts.capacity),
                AdapterPlanProfileField("selection_fact_storage_growth_count", context.selectionFactStorageGrowthCount),
                AdapterPlanProfileField("semantic_pitch_record_count", context.semanticPitchBuilder.evidence.recordCount),
                AdapterPlanProfileField("semantic_pitch_record_capacity", context.semanticPitchBuilder.evidence.recordCapacity),
                AdapterPlanProfileField("semantic_pitch_record_stride", MemoryLayout<PlaybackSongSemanticPitchProjection.Record>.stride),
                AdapterPlanProfileField("semantic_pitch_reset_run_count", context.semanticPitchBuilder.evidence.resetRunCount),
                AdapterPlanProfileField("semantic_pitch_reset_run_capacity", context.semanticPitchBuilder.evidence.resetRunCapacity),
                AdapterPlanProfileField("semantic_pitch_reset_run_stride", MemoryLayout<PlaybackSongSemanticPitchProjection.ResetRun>.stride),
                AdapterPlanProfileField("semantic_pitch_reset_run_growths", context.semanticPitchBuilder.resetGrowths),
                AdapterPlanProfileField("semantic_pitch_workspace_capacity", context.semanticPitchBuilder.workspaceHighWater),
                AdapterPlanProfileField("semantic_pitch_storage_growths", context.semanticPitchBuilder.growths),
                AdapterPlanProfileField("semantic_pitch_capture_failures", context.semanticPitchBuilder.failures),
                AdapterPlanProfileField("automatic_clock_run_count", context.semanticPitchBuilder.automatic.evidence.runCount),
                AdapterPlanProfileField("automatic_clock_run_capacity", context.semanticPitchBuilder.automatic.evidence.runCapacity),
                AdapterPlanProfileField("automatic_clock_run_stride", MemoryLayout<PlaybackSongInstrumentAutovibratoClock.Run>.stride),
                AdapterPlanProfileField("automatic_clock_growths", context.semanticPitchBuilder.automatic.growths),
                AdapterPlanProfileField("automatic_clock_workspace_capacity", context.semanticPitchBuilder.automatic.evidence.workspaceCapacity),
                AdapterPlanProfileField("instrument_auto_request_count", automaticPitchBuilder.requests.count),
                AdapterPlanProfileField("instrument_auto_introduced_hold_count", automaticPitchBuilder.introducedHoldEventIndices.count),
                AdapterPlanProfileField("instrument_auto_request_capacity", automaticPitchBuilder.requests.capacity),
                AdapterPlanProfileField("instrument_auto_request_stride", MemoryLayout<PlaybackSongInstrumentAutovibratoPublication.Request>.stride),
                AdapterPlanProfileField("instrument_auto_request_growths", automaticPitchBuilder.requestGrowthCount),
                AdapterPlanProfileField("instrument_auto_bounds_capacity", automaticPitchBuilder.bounds.capacity),
                AdapterPlanProfileField("instrument_auto_bounds_growths", automaticPitchBuilder.boundsGrowthCount),
                AdapterPlanProfileField("instrument_auto_workspace_capacity_bytes", automaticPitchBuilder.workspaceCapacityBytes),
                AdapterPlanProfileField("instrument_auto_rewritten_array_count", automaticPitchBuilder.rewrittenArrayCount),
                AdapterPlanProfileField("instrument_auto_rewritten_child_capacity_bytes", automaticPitchBuilder.rewrittenChildCapacityBytes),
                AdapterPlanProfileField("semantic_pitch_seed_count", context.semanticPitchBuilder.seeds.count),
                AdapterPlanProfileField("semantic_pitch_seed_capacity", context.semanticPitchBuilder.seeds.capacity),
                AdapterPlanProfileField("semantic_pitch_channel_capacity", context.semanticPitchBuilder.states.capacity),
                AdapterPlanProfileField("semantic_pitch_operation_capacity", context.semanticPitchBuilder.operationCapacityHighWater),
                AdapterPlanProfileField("semantic_pitch_operation_stride", MemoryLayout<PlaybackSongSemanticPitchProjection.Builder.Operation>.stride),
                AdapterPlanProfileField("semantic_pitch_boundary_capacity", context.semanticPitchBuilder.boundaryCapacityHighWater),
                AdapterPlanProfileField("semantic_pitch_boundary_stride", MemoryLayout<PlaybackSongSemanticPitchProjection.Builder.Boundary>.stride),
                AdapterPlanProfileField("native_writer_span_count", context.nativePitchWriterObserver.spans.count),
                AdapterPlanProfileField("native_writer_span_stride", MemoryLayout<PlaybackSongNativePitchWriterSpans.Span>.stride),
                AdapterPlanProfileField("native_writer_span_capacity", context.nativePitchWriterObserver.spans.capacity),
                AdapterPlanProfileField("native_writer_span_growth_count", context.nativePitchWriterObserver.storageGrowthCount),
                AdapterPlanProfileField("native_writer_child_count", context.nativePitchWriterObserver.capturedChildCount),
                AdapterPlanProfileField("native_writer_referenced_child_count", context.nativePitchWriterObserver.referencedChildCount),
                AdapterPlanProfileField("native_writer_referenced_child_capacity", context.nativePitchWriterObserver.referencedChildCapacity),
                AdapterPlanProfileField("native_writer_observer_stride", MemoryLayout<PlaybackSongNativePitchWriterSpans.Observer>.stride),
                AdapterPlanProfileField("g23_childless_run_count", context.g23ChildlessPitchInvocationObserver.runs.count),
                AdapterPlanProfileField("g23_childless_run_stride", MemoryLayout<PlaybackSongG23ChildlessPitchInvocations.Run>.stride),
                AdapterPlanProfileField("g23_childless_run_capacity", context.g23ChildlessPitchInvocationObserver.runs.capacity),
                AdapterPlanProfileField("g23_childless_run_growth_count", context.g23ChildlessPitchInvocationObserver.storageGrowthCount),
                AdapterPlanProfileField("synthetic_plan_stride", MemoryLayout<PlaybackSongSyntheticPlan>.stride),
                AdapterPlanProfileField("held_pitch_row_hold_count", context.heldPitchObserver.rowHolds.count),
                AdapterPlanProfileField("held_pitch_row_hold_stride", MemoryLayout<PlaybackSongHeldPitchProvenance.RowHold>.stride),
                AdapterPlanProfileField("held_pitch_row_hold_capacity", context.heldPitchObserver.rowHolds.capacity),
                AdapterPlanProfileField("held_pitch_storage_growth_count", context.heldPitchObserver.storageGrowthCount),
                AdapterPlanProfileField("held_pitch_channel_capacity", context.heldPitchObserver.channels.capacity),
                AdapterPlanProfileField("held_pitch_channel_stride", MemoryLayout<PlaybackSongHeldPitchProvenance.Held>.stride),
                AdapterPlanProfileField("held_pitch_channel_growth_count", context.heldPitchObserver.channelStorageGrowthCount),
                AdapterPlanProfileField("selection_provenance_count", context.selectionTuningProducers.count),
                AdapterPlanProfileField("selection_provenance_stride", MemoryLayout<PlaybackSongSelectionDispatchFacts.TuningProducers>.stride),
            ]
        )
        profileSession?.recordPhase(
            "pattern_row_iteration",
            startedAt: rowIterationStart,
            fields: [
                AdapterPlanProfileField("row_count", traversalPlan.pathLength),
                AdapterPlanProfileField("row_diagnostic_count", context.rowDiagnostics.count),
                AdapterPlanProfileField("synthetic_event_count", context.events.count),
            ]
        )

        if let globalVolumeProjectionOracle {
            globalVolumeProjectionOracle(timingPlan, &context)
        } else {
            planGlobalVolumeChannelTargets(timingPlan: timingPlan, context: &context, profileSession: profileSession)
        }
        let rowTimingDiagnostics = timingPlan.rowTimingDiagnostics
        let canonicalTickClock = PlaybackSongCanonicalTickClock(runs: clockRuns, totalCanonicalTicks: canonicalTickCount,
            sampleRate: timingConfig.sampleRate, rowTiming: rowTimingDiagnostics, rowDiagnostics: context.rowDiagnostics)
        var plan = PlaybackSongSyntheticPlan(
            timingConfig: timingConfig,
            pattern: SyntheticPattern(rowCount: traversalPlan.pathLength, events: context.events),
            diagnostics: PlaybackSongSyntheticDiagnostics(
                requestedStartOrderIndex: startOrderIndex,
                requestedOrderCount: safeOrderCount,
                sampleRate: timingConfig.sampleRate,
                initialSpeed: timingConfig.speed,
                initialBPM: timingConfig.bpm,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                syntheticRowCount: traversalPlan.pathLength,
                adaptedOrders: traversalPlan.adaptedOrders,
                rowMappings: rowMappings,
                rowTiming: rowTimingDiagnostics,
                timingChanges: timingPlan.timingChanges,
                traversalDiagnostics: traversalPlan.traversalDiagnostics,
                traversalPathLength: traversalPlan.pathLength,
                traversalStopReason: traversalPlan.stopReason,
                traversalGuardHit: traversalPlan.guardHit,
                effectCommandDiagnostics: context.effectCommandDiagnostics,
                rowDiagnostics: context.rowDiagnostics,
                volumeColumnMappings: context.volumeColumnMappings,
                voiceStateUpdates: context.voiceStateUpdates,
                sampleOffsetEffects: context.sampleOffsetEffects,
                setFinetuneEffects: context.setFinetuneEffects,
                envelopePositionEffects: context.envelopePositionEffects,
                noteCutEffects: context.noteCutEffects,
                noteDelayEffects: context.noteDelayEffects,
                retriggerEffects: context.retriggerEffects,
                tonePortamentoEffects: context.tonePortamentoEffects,
                portamentoSlideEffects: context.portamentoSlideEffects,
                finePortamentoUpEffects: context.finePortamentoUpEffects,
                finePortamentoDownEffects: context.finePortamentoDownEffects,
                extraFinePortamentoEffects: context.extraFinePortamentoEffects,
                arpeggioEffects: context.arpeggioEffects,
                vibratoControlEffects: context.vibratoControlEffects,
                vibratoEffects: context.vibratoEffects,
                keyOffEvents: context.keyOffEvents,
                eventMappings: context.eventMappings,
                ignoredCells: context.ignoredCells,
                deferredCellFields: context.deferredCellFields,
                eventCoverage: context.eventCoverage.summary
            ),
            canonicalTickClock: canonicalTickClock,
            selectionDispatchFacts: .init(coverage: .nativeSelectionProducersV1, facts: context.selectionFacts)
        )
        plan.noteOnlyEventIndices = context.noteOnlyEventIndices
        plan.coldReleasedEventIndices = context.coldReleasedEventIndices
        plan.playbackStateEvents = context.playbackStateEvents
        plan.xmChannelRows = context.xmChannelRows
        plan.xmEmptyRoutes = context.xmEmptyRoutes
        plan.xmInstrumentSelections = context.xmInstrumentSelections
        plan.initialHeldPitchEventIndices = context.initialHeldPitchEventIndices
        plan.instrumentAutovibratoRequests = automaticPitchBuilder.requests
        plan.instrumentAutovibratoInitialHoldEventIndices = automaticPitchBuilder.introducedHoldEventIndices
        plan.xmEnvelopeTimeline = PlaybackXMEnvelopeTimeline(song: song, timing: timingPlan, plan: plan)
        admitFinePitchPublications(in: &plan, ordinaryDelayedVibratoIndices: context.ordinaryDelayedVibratoIndices,
            profileSession: profileSession, oracle: eligibilityOracle)
        // Eligibility must see managed envelope/release lifetime. Only completed
        // cold-500 sources require rebuilding targets after gain admission changes.
        if excludeCompletedCold500Publications(from: &plan) {
            plan.xmAudibleTimeline = PlaybackXMAudibleTimeline(plan: plan)
        }
        // Install only after existing diagnostic/admission mutations have completed.
        plan.semanticPitchProjection = context.semanticPitchBuilder.evidence
        plan.instrumentAutovibratoClock = context.semanticPitchBuilder.automatic.evidence
        plan.heldPitchProvenance = context.heldPitchObserver.evidence
        plan.nativePitchWriterSpans = context.nativePitchWriterObserver.evidence(
            domain: song.usesLinearFrequencyTable ? .linear : .amigaVTX4x)
        plan.g23ChildlessPitchInvocations = context.g23ChildlessPitchInvocationObserver.evidence
        plan.rowExitProvenance = context.rowExitObserver.evidence
        plan.rowEntryTriggerResetFacts = context.rowEntryTriggerResetObserver.evidence
        plan.delayedInstrumentResetFacts = context.delayedInstrumentResetObserver.evidence
        profileSession?.recordPhase(
            "playback_song_synthetic_adapter_adapt_total",
            startedAt: totalStart,
            fields: AdapterPlanProfileFields.playbackSong(song) + AdapterPlanProfileFields.syntheticPlan(plan)
        )
        return plan
    }

    /// Admits fine/extra-fine and ordinary delayed Bx writes against the existing source lifetime.
    private static func admitFinePitchPublications(in plan: inout PlaybackSongSyntheticPlan,
        ordinaryDelayedVibratoIndices: [Int],
        profileSession: AdapterPlanProfileSession?, oracle: ((Int, Int, PlaybackSongSyntheticPlan) -> Bool)?) {
        let start = profileSession?.beginPhase(), buildStart = profileSession?.beginPhase()
        let hasQueries = plan.diagnostics.finePortamentoUpEffects.contains { $0.applied && !$0.appliedToInitialPlaybackStep && $0.activeEventIndex != nil } ||
            plan.diagnostics.finePortamentoDownEffects.contains { $0.applied && !$0.appliedToInitialPlaybackStep && $0.activeEventIndex != nil } ||
            plan.diagnostics.extraFinePortamentoEffects.contains { $0.applied && !$0.appliedToInitialPlaybackStep && $0.activeEventIndex != nil } ||
            ordinaryDelayedVibratoIndices.contains { !plan.diagnostics.vibratoEffects[$0].stepUpdates.isEmpty } ||
            !plan.instrumentAutovibratoRequests.isEmpty
        let work = profileSession == nil ? nil : PlaybackSongOfflineRenderer.PitchSourceHistory.Work()
        // Admission only removes writes to an already dead source. Its earlier, eligible
        // positive-step prefix is unchanged, so this immutable projection stays valid.
        let history = hasQueries && oracle == nil ? PlaybackSongOfflineRenderer.PitchSourceHistory(plan: plan, work: work) : nil
        let fields: [AdapterPlanProfileField] = [
            .init("index_build_count", history == nil ? 0 : 1), .init("source_count", history?.sourceCount ?? 0),
            .init("pitch_diagnostics_visited", history?.diagnosticsVisited ?? 0),
            .init("history_record_count", history?.recordCount ?? 0), .init("source_stride", history?.sourceStride ?? 0),
            .init("history_record_stride", history?.recordStride ?? 0), .init("index_logical_bytes", history?.logicalBytes ?? 0)
        ]
        if history != nil { profileSession?.recordPhase("fine_pitch_source_history_build", startedAt: buildStart, fields: fields) }
        var queryCount = 0
        let eligibleSource: (Int, Int, PlaybackSongSyntheticPlan) -> Bool = { event, frame, plan in
            queryCount += 1
            return oracle?(event, frame, plan) ?? PlaybackSongOfflineRenderer.hasActiveSource(
                eventIndex: event, at: frame, plan: plan, pitchHistory: history)
        }
        for index in plan.diagnostics.finePortamentoUpEffects.indices {
            let command = plan.diagnostics.finePortamentoUpEffects[index]
            guard command.applied, !command.appliedToInitialPlaybackStep else { continue }
            let eligible = command.activeEventIndex.map {
                eligibleSource($0, command.scheduledFrame ?? 0, plan)
            } ?? false
            plan.diagnostics.finePortamentoUpEffects[index].execution.sourceEligible = eligible
            if !eligible {
                plan.diagnostics.finePortamentoUpEffects[index].stepUpdates = []
                plan.diagnostics.finePortamentoUpEffects[index].execution.publicationSuppressionReason = "no_active_source"
            }
        }
        for index in plan.diagnostics.finePortamentoDownEffects.indices {
            let command = plan.diagnostics.finePortamentoDownEffects[index]
            guard command.applied, !command.appliedToInitialPlaybackStep else { continue }
            let eligible = command.activeEventIndex.map {
                eligibleSource($0, command.scheduledFrame ?? 0, plan)
            } ?? false
            plan.diagnostics.finePortamentoDownEffects[index].execution.sourceEligible = eligible
            if !eligible {
                plan.diagnostics.finePortamentoDownEffects[index].stepUpdates = []
                plan.diagnostics.finePortamentoDownEffects[index].execution.publicationSuppressionReason = "no_active_source"
            }
        }
        for index in plan.diagnostics.extraFinePortamentoEffects.indices {
            let command = plan.diagnostics.extraFinePortamentoEffects[index]
            guard command.applied, !command.appliedToInitialPlaybackStep else { continue }
            let eligible = command.activeEventIndex.map {
                eligibleSource($0, command.scheduledFrame ?? 0, plan)
            } ?? false
            plan.diagnostics.extraFinePortamentoEffects[index].execution.sourceEligible = eligible
            if !eligible {
                plan.diagnostics.extraFinePortamentoEffects[index].stepUpdates = []
                plan.diagnostics.extraFinePortamentoEffects[index].execution.publicationSuppressionReason = "no_active_source"
            }
        }
        for index in ordinaryDelayedVibratoIndices {
            let command = plan.diagnostics.vibratoEffects[index]
            guard let event = command.activeEventIndex else { continue }
            for update in command.stepUpdates where !eligibleSource(event, update.scheduledFrame, plan) {
                plan.diagnostics.vibratoEffects[index].inactiveSourceStepUpdates.append(update)
            }
            if !plan.diagnostics.vibratoEffects[index].inactiveSourceStepUpdates.isEmpty {
                let inactive = Set(plan.diagnostics.vibratoEffects[index].inactiveSourceStepUpdates.map(\.scheduledFrame))
                plan.diagnostics.vibratoEffects[index].stepUpdates.removeAll { inactive.contains($0.scheduledFrame) }
            }
        }
        // Compact in place; future requests cannot revive an already completed generation.
        var retained = 0
        for index in plan.instrumentAutovibratoRequests.indices {
            let request = plan.instrumentAutovibratoRequests[index]
            if eligibleSource(request.activeEventIndex, request.scheduledFrame, plan) {
                if retained != index { plan.instrumentAutovibratoRequests[retained] = request }
                retained += 1
            }
        }
        plan.instrumentAutovibratoRequests.removeLast(plan.instrumentAutovibratoRequests.count - retained)
        profileSession?.recordPhase("fine_pitch_source_eligibility", startedAt: start, fields: fields + [
            .init("eligibility_query_count", queryCount), .init("position_lookup_count", work?.lookupCount ?? 0),
            .init("position_entries_visited", work?.entriesVisited ?? 0)
        ])
    }

    /// Keeps cold-500 semantic execution while excluding completed sources from C gain scheduling.
    private static func excludeCompletedCold500Publications(from plan: inout PlaybackSongSyntheticPlan) -> Bool {
        var completedChannelsByFrame = [Int: Set<Int>]()
        for update in plan.diagnostics.voiceStateUpdates {
            guard case .effect5xyVolumeSlide = update.command,
                  update.applied, update.effectParam == 0,
                  !update.effectMemoryReused, update.activeVoiceUpdated,
                  let eventIndex = update.activeEventIndex,
                  !PlaybackSongOfflineRenderer.hasActiveSource(eventIndex: eventIndex, at: update.scheduledFrame, plan: plan) else { continue }
            completedChannelsByFrame[update.scheduledFrame, default: []].insert(update.channelIndex)
        }
        guard !completedChannelsByFrame.isEmpty else { return false }
        for index in plan.diagnostics.voiceStateUpdates.indices {
            let update = plan.diagnostics.voiceStateUpdates[index]
            guard completedChannelsByFrame[update.scheduledFrame]?.contains(update.channelIndex) == true else { continue }
            switch update.command {
            case .effect5xyVolumeSlide, .gxxChannelTarget(_, reason: "local_volume_writer"):
                plan.diagnostics.voiceStateUpdates[index].activeVoiceUpdated = false
            default: break
            }
        }
        return true
    }

    static func traversalEffectStatuses(
        from diagnostics: [PlaybackSongSyntheticTraversalDiagnostic]
    ) -> [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status] {
        diagnostics.reduce(into: [TraversalEffectKey: PlaybackSongSyntheticEffectCommandDiagnostic.Status]()) { result, diagnostic in
            let key = TraversalEffectKey(
                orderIndex: diagnostic.source.orderIndex,
                patternIndex: diagnostic.source.patternIndex,
                rowIndex: diagnostic.source.rowIndex,
                channelIndex: diagnostic.channelIndex,
                syntheticRow: diagnostic.syntheticRow,
                effectType: diagnostic.effectType,
                effectParam: diagnostic.effectParam
            )
            result[key] = effectCommandStatus(for: diagnostic.status)
        }
    }

    static func effectCommandStatus(
        for traversalStatus: PlaybackSongSyntheticTraversalDiagnostic.Status
    ) -> PlaybackSongSyntheticEffectCommandDiagnostic.Status {
        switch traversalStatus {
        case .applied, .loopStartMarked, .loopTaken:
            return .applied
        case .deferred:
            return .deferredUnsupported
        case .invalidTarget:
            return .invalidTarget
        case .outOfRange:
            return .outOfRange
        case .missingLoopStart:
            return .missingLoopStart
        case .loopLimitHit:
            return .loopLimitHit
        }
    }

    static func appendEvents(
        from row: PlaybackRow,
        source: PlaybackPosition,
        syntheticRow: Int,
        song: PlaybackSong,
        timingConfig: SyntheticTrackerTimingConfig,
        timingPlan: PlaybackSongFxxTimingPlan,
        scheduledStartFrame: Int,
        nextRow: PlaybackRow? = nil,
        context: inout AdapterRowContext
    ) -> PlaybackSongSyntheticRowDiagnostic {
        context.rowExitObserver.beginRow(syntheticRow, firstVibratoDiagnosticIndex: context.vibratoEffects.count,
            domain: song.usesLinearFrequencyTable ? .linear : .amigaVTX4x)
        let eventStartCount = context.events.count
        let ignoredStartCount = context.ignoredCells.count
        if context.channelStates.count < row.cells.count {
            context.channelStates.append(contentsOf: repeatElement(
                ChannelState(),
                count: row.cells.count - context.channelStates.count
            ))
        }
        if context.selectionTuningProducers.count < row.cells.count {
            context.selectionTuningProducers.append(contentsOf: repeatElement(.init(),
                count: row.cells.count - context.selectionTuningProducers.count))
        }
        context.heldPitchObserver.ensureChannels(row.cells.count)
        for channelIndex in row.cells.indices {
            var cell = row.cells[channelIndex]
            let heldPitchRow = context.heldPitchObserver.begin(cell, channel: channelIndex,
                firstFact: context.selectionFacts.count, vibratoCount: context.vibratoEffects.count,
                slideCount: context.portamentoSlideEffects.count, toneCount: context.tonePortamentoEffects.count)
            defer { captureHeldPitchRow(heldPitchRow, channel: channelIndex, context: &context) }
            if context.eventCoverage.visit(cell) {
                // Empty cells have no row writers. Capture the unchanged controls once,
                // retaining every occurrence and diagnostic without copying a working
                // channel state or dispatching no-op decoding/effect helpers. The later
                // nonzero-tick pass stays in its established row-wide order below.
                context.emptyCellFastPathCount += 1
                context.xmChannelRows.append(.init(source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame,
                    controls: context.channelStates[channelIndex], instrumentOnlyReset: nil))
                context.ignoredCells.append(ignoredCell(
                    source: source, channelIndex: channelIndex, cell: cell, reason: .emptyNote,
                    volumeColumn: context.emptyVolumeColumn, hasIgnoredVolumeColumn: false, hasIgnoredEffect: false
                ))
                context.eventCoverage.recordIgnoredCell(reason: .emptyCell, isNormalNote: false)
                continue
            }
            context.fullCellDispatchCount += 1
            let nextCell = nextRow.flatMap { $0.cells.indices.contains(channelIndex) ? $0.cells[channelIndex] : nil }
            let restoreVibratoAtRowEnd = nextCell.map { $0.effectType != 4 && $0.effectType != 6 } ?? false
            var channelState = context.channelStates[channelIndex]
            // Memory resolves even if source routing or the current scheduler cannot run.
            if isRxyMultiRetriggerEffect(cell) { channelState.resolveRxyMemory(cell.effectParam) }
            if let effectCommandDiagnostic = effectCommandDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                traversalEffectStatuses: context.traversalEffectStatuses,
                timingConfig: timingConfig,
                channelState: channelState
            ) {
                context.effectCommandDiagnostics.append(effectCommandDiagnostic)
            }
            let isE90 = cell.effectType == 0x0E && cell.effectParam == 0x90
            let e90PreviousEvent = isE90 ? channelState.activeEventIndex : nil
            let e90PreviousMapping = isE90 ? channelState.activeEventMappingIndex : nil
            let firstRowEvent = context.events.count
            if isE90, cell.note == 0 {
                cell = PlaybackCell(note: channelState.carriedNote, instrument: cell.instrument,
                    volumeColumn: cell.volumeColumn, effectType: cell.effectType, effectParam: cell.effectParam)
            }
            // A row establishes H memory only when its nonzero-tick handler runs.
            // Planning knows the effective speed, so F01 neither seeds nor replaces it.
            if cell.effectType == 0x11, cell.effectParam != 0, timingConfig.speed > 1 {
                channelState.globalVolumeSlideMemory = .init(parameter: cell.effectParam,
                    source: effectMemorySource(source: source, channelIndex: channelIndex, cell: cell))
            }
            let isNoteOnly = cell.instrument == 0
            let routedInstrumentIndex = isNoteOnly ? channelState.carriedInstrumentIndex ?? 0 : Int(cell.instrument)
            let refusedSelection = refusedOrdinarySelection(cell: cell, instrumentIndex: routedInstrumentIndex, song: song)
            let retainsDelayedTrigger = isNonzeroOrdinaryDelay(cell) && refusedOrdinarySelection(cell: cell,
                instrumentIndex: routedInstrumentIndex, song: song, admission: .retained) != nil
            let ordinaryEmptyHeader = ordinaryDelayedEmptyHeader(cell: cell, song: song)
            let delaysOrdinaryEmpty = isNonzeroOrdinaryDelay(cell) && ordinaryEmptyHeader != nil
            let defersOrdinaryTriggerState = retainsDelayedTrigger || delaysOrdinaryEmpty
            let delaysRefusedTrigger = refusedSelection != nil && isNonzeroOrdinaryDelay(cell)
            let ordinaryDelayedBx = isNonzeroOrdinaryDelay(cell) && cell.volumeColumn >> 4 == 0xB && !delaysRefusedTrigger
            if isDelayedInstrumentOnly(cell) || delaysRefusedTrigger {
                // ED1...EDF selects the carried owner now; source/default/reset work
                // waits for the nonzero-tick pass after all row-entry writers.
                if song.instrumentsByIndex[Int(cell.instrument)] != nil {
                    channelState.carriedInstrumentIndex = Int(cell.instrument)
                    captureSelection(source: source, row: syntheticRow, tick: 0, channel: channelIndex,
                        frame: scheduledStartFrame, role: .carriedInstrument, linear: song.usesLinearFrequencyTable,
                        state: channelState, context: &context)
                }
                context.xmChannelRows.append(.init(source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame,
                    controls: channelState, instrumentOnlyReset: nil))
                context.channelStates[channelIndex] = channelState
                continue
            }
            var instrumentOnlyReset: MixerPlaybackStateChange?
            var delayedRetainedRowEntry: ChannelState? = defersOrdinaryTriggerState || ordinaryDelayedBx ? channelState : nil
            var ordinaryBxDiagnosticIndex: Int?
            if cell.instrument > 0, song.instrumentsByIndex[Int(cell.instrument)] != nil {
                delayedRetainedRowEntry?.carriedInstrumentIndex = Int(cell.instrument)
            }
            defer {
                if ordinaryDelayedBx, extendedEffectTick(cell) + 1 < timingConfig.speed {
                    appendOrdinaryDelayedVibrato(cell: cell, source: source, channelIndex: channelIndex,
                        syntheticRow: syntheticRow, ticks: (extendedEffectTick(cell) + 1)..<timingConfig.speed,
                        timingConfig: timingConfig, timingPlan: timingPlan, state: &channelState, context: &context)
                }
                if isRxyMultiRetriggerEffect(cell) {
                    handleRxyTick(cell: cell, source: source, channelIndex: channelIndex,
                        syntheticRow: syntheticRow, tick: 0, song: song, timingConfig: timingConfig,
                        timingPlan: timingPlan, state: &channelState, context: &context)
                }
                if isE90 {
                    context.retriggerEffects.append(e90Diagnostic(cell: cell, source: source,
                        channelIndex: channelIndex, syntheticRow: syntheticRow, timingConfig: timingConfig,
                        previousEventIndex: e90PreviousEvent, firstRowEvent: firstRowEvent, context: context))
                }
                if isNoteCutEffect(cell), extendedEffectTick(cell) == 0 {
                    applyNoteCutVolume(cell: cell, source: source, channelIndex: channelIndex,
                        syntheticRow: syntheticRow, tick: 0, timingPlan: timingPlan,
                        globalVolume: context.globalVolumeState.volumeValue,
                        state: &channelState, updates: &context.voiceStateUpdates)
                }
                context.xmChannelRows.append(.init(source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame, controls: delayedRetainedRowEntry ?? channelState,
                    instrumentOnlyReset: instrumentOnlyReset))
                let axyUpdates = isOrdinaryVolumeColumnSlide(cell.volumeColumn) ? [] : applyEffectColumnVolumeSlide(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    globalVolumeValue: context.globalVolumeState.volumeValue
                )
                if !axyUpdates.isEmpty {
                    context.voiceStateUpdates.append(contentsOf: axyUpdates)
                }
                context.channelStates[channelIndex] = channelState
            }
            let extendedSubcommand = cell.effectType == 0x0E ? ((cell.effectParam >> 4) & 0x0F) : nil
            let hasNoteCutEffect = extendedSubcommand == 0x0C
            let hasNoteDelayEffect = extendedSubcommand == 0x0D && refusedSelection == nil
            if extendedSubcommand == 0x0D, refusedSelection != nil {
                context.noteDelayEffects.append(.init(source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, syntheticTick: 0, effectType: cell.effectType,
                    effectParam: cell.effectParam, status: .sourceRefused, detected: true,
                    applied: true, deferred: false, ignoredAsNoOp: false, outOfRow: false,
                    requestedTick: 0, rowSpeed: timingConfig.speed, rowBPM: timingConfig.bpm,
                    originalFrame: scheduledStartFrame, delayedFrame: scheduledStartFrame, eventIndex: nil))
            }
            let hasRetriggerEffect = isE9xRetriggerEffect(cell) && !isE90
            let hasSetFinetuneEffect = extendedSubcommand == 0x05
            let hasFinePortamentoUpEffect = extendedSubcommand == 0x01
            let hasFinePortamentoDownEffect = extendedSubcommand == 0x02
            let hasXxyExtraFinePortamentoEffect = isXxyExtraFinePortamentoEffect(cell)
            let hasVibratoControlEffect = extendedSubcommand == 0x04
            let hasArpeggio = isArpeggioEffect(cell)
            let hasPortamentoSlide = isPortamentoSlideEffect(cell)
            let hasTonePortamento = isTonePortamentoEffect(cell)
            let hasVibrato = isVibratoEffect(cell) || ((0xB0...0xBF).contains(cell.volumeColumn) && !isRxyMultiRetriggerEffect(cell))
            let hasVibratoVolumeSlide = isVibratoVolumeSlideEffect(cell)
            let hasKxxKeyOff = isKxxKeyOffEffect(cell)
            let hasLxxSetEnvelopePosition = isLxxSetEnvelopePositionEffect(cell)
            var volumeColumn = PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn)
            let hasVolumeColumnTonePortamento = isTonePortamentoVolumeColumn(volumeColumn)
            let handlesTonePortamento = !isE90 && (hasTonePortamento || hasVolumeColumnTonePortamento)
            if let refusedSelection {
                applyRefusedOrdinarySelection(refusedSelection, cell: cell, source: source,
                    channelIndex: channelIndex, syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame,
                    timingConfig: timingConfig, song: song, state: &channelState, context: &context)
                // Continue through the existing writers/effect dispatch on the retained
                // source. Refusal suppresses only the ordinary source/pitch trigger.
                cell = .init(note: 0, instrument: 0, volumeColumn: cell.volumeColumn,
                    effectType: cell.effectType, effectParam: cell.effectParam)
            }
            if (1...96).contains(cell.note), !handlesTonePortamento,
               !(hasKxxKeyOff && cell.effectParam == 0),
               !hasNoteDelayEffect || Int(cell.effectParam & 15) < timingConfig.speed {
                channelState.carriedNote = cell.note
            }
            let hasValidImmediateNoteInstrument = (1...96).contains(cell.note) &&
                cell.instrument > 0 &&
                (!hasNoteDelayEffect || (cell.effectParam == 0xD0 && ordinaryEmptyHeader != nil))
            // Target routing and retained sounding-header defaults are independent.
            // Both modes reuse the owned-header or cold instrument reset below.
            let toneTargetSelection: SampleSelection? = hasValidImmediateNoteInstrument && handlesTonePortamento
                ? song.instrumentsByIndex[Int(cell.instrument)].map {
                    selectSample(forNote: cell.note, from: $0)
                } : nil
            var tonePortamentoInstrumentStateBefore: ChannelState?
            var tonePortamentoInstrumentStateAfter: ChannelState?
            var tonePortamentoInstrumentDefaultVolumeApplied = false
            // Resolve once through the existing keymap authority. Ordinary triggers
            // load the new sample's default before same-cell volume writers; delayed,
            // retrigger, key-off, and portamento paths retain their own contracts.
            let explicitTriggerSelection: SampleSelection?
            if hasValidImmediateNoteInstrument, !handlesTonePortamento, !hasRetriggerEffect,
               !(hasKxxKeyOff && cell.effectParam == 0),
               let instrument = song.instrumentsByIndex[Int(cell.instrument)] {
                explicitTriggerSelection = selectSample(forNote: cell.note, from: instrument,
                    missingKeymapPolicy: isE90 ? .fail : .firstPlayableSample)
            } else {
                explicitTriggerSelection = nil
            }
            var selectedEmptyPitch: PlaybackStepMapping?
            if let selection = explicitTriggerSelection, selection.sample == nil,
               let slot = selection.mappedSampleIndex,
               let header = song.xmSampleSlotProvenanceByInstrument[Int(cell.instrument)]?.first(where: {
                   $0.sampleIndex == slot && $0.declaredPayloadLength == 0 && $0.decodedPayloadLength == 0
               }) {
                selectedEmptyPitch = dispatchOrdinaryEmptyHeader(header, cell: cell, source: source,
                    syntheticRow: syntheticRow, channelIndex: channelIndex, frame: scheduledStartFrame, selection: selection, song: song,
                    timingConfig: timingConfig, state: &channelState, context: &context)
            }
            if isE90, let selection = explicitTriggerSelection, selection.sample == nil,
               selectedEmptyPitch == nil {
                let slot = selection.mappedSampleIndex
                context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
                    scheduledFrame: scheduledStartFrame, instrumentIndex: routedInstrumentIndex, sampleIndex: slot,
                    stoppedEventIndex: channelState.activeEventIndex))
                clearSourceAssociation(&channelState)
                channelState.semanticInstrumentIndex = routedInstrumentIndex
                channelState.semanticSampleIndex = slot
                channelState.semanticVolumeEnvelopeEnabled = song.instrumentsByIndex[routedInstrumentIndex]?.volumeEnvelope.enabled == true
            }
            // Note-only selects a source/header but does not reload tracker volume/pan
            // or restart instrument clocks. Resolve before the same-cell writers.
            if isNoteOnly, (1...96).contains(cell.note), !handlesTonePortamento,
               !(hasKxxKeyOff && cell.effectParam == 0),
               !hasNoteDelayEffect || cell.effectParam == 0xD0,
               let instrument = song.instrumentsByIndex[routedInstrumentIndex] {
                let selection = selectSample(forNote: cell.note, from: instrument, missingKeymapPolicy: .fail)
                if selection.sample == nil, selection.mappedSampleIndex != nil || isE90 {
                    let slot = selection.mappedSampleIndex
                    context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
                        scheduledFrame: scheduledStartFrame, instrumentIndex: routedInstrumentIndex, sampleIndex: slot,
                        stoppedEventIndex: channelState.activeEventIndex, preservesChannelState: true))
                    if let header = song.xmSampleSlotProvenanceByInstrument[routedInstrumentIndex]?.first(where: {
                        $0.sampleIndex == slot && $0.declaredPayloadLength == 0 && $0.decodedPayloadLength == 0
                    }) {
                        selectedEmptyPitch = selectEmptyHeader(header, cell: cell, instrumentIndex: routedInstrumentIndex,
                            initializesDefaults: false, song: song, timingConfig: timingConfig, state: &channelState)
                        captureSelection(source: source, row: syntheticRow, tick: 0, channel: channelIndex,
                            frame: scheduledStartFrame, role: .emptySelection, linear: song.usesLinearFrequencyTable,
                            noteOnly: true, tuning: .declaredEmptyHeader, finetuneCommand: hasSetFinetuneEffect,
                            routedInstrument: routedInstrumentIndex, selection: selection, state: channelState, context: &context)
                    } else {
                        // An undeclared slot has no header defaults to invent.
                        clearSourceAssociation(&channelState)
                        channelState.semanticInstrumentIndex = routedInstrumentIndex
                        channelState.semanticSampleIndex = slot
                        channelState.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
                        applyActiveVolumeEnvelopeMapping(mixerVolumeEnvelope(from: instrument.volumeEnvelope,
                            timingConfig: timingConfig), to: &channelState)
                    }
                }
            }
            if cell.instrument > 0, song.instrumentsByIndex[Int(cell.instrument)] != nil {
                channelState.carriedInstrumentIndex = Int(cell.instrument)
                if cell.note == 0 || isNonzeroOrdinaryDelay(cell) || selectedEmptyPitch != nil {
                    captureSelection(source: source, row: syntheticRow, tick: 0, channel: channelIndex,
                        frame: scheduledStartFrame, role: .carriedInstrument, linear: song.usesLinearFrequencyTable,
                        state: channelState, context: &context)
                }
            }
            let rawK00 = hasKxxKeyOff && cell.effectParam == 0 && !hasVolumeColumnTonePortamento
            let restoresInstrumentOnlyDefaults = (cell.note == 0 || cell.note == 97 || rawK00) && cell.instrument > 0 &&
                song.instrumentsByIndex[Int(cell.instrument)] != nil &&
                !(hasNoteDelayEffect && cell.effectParam & 15 != 0)
            // Release before cached defaults and writers; raw K00 owns a simultaneous note97.
            if cell.note == 97 || rawK00 {
                handleKeyOff(source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                    syntheticTick: 0, scheduledFrame: scheduledStartFrame, rowSpeed: timingConfig.speed,
                    rowBPM: timingConfig.bpm, volumeColumn: volumeColumn, cell: cell, channelState: &channelState,
                    events: &context.events, keyOffEvents: &context.keyOffEvents,
                    voiceStateUpdates: &context.voiceStateUpdates, globalVolume: context.globalVolumeState.volumeValue,
                    eventMappings: &context.eventMappings, ignoredCells: &context.ignoredCells,
                    deferredCellFields: &context.deferredCellFields, eventCoverage: &context.eventCoverage,
                    effectType: rawK00 ? cell.effectType : nil, effectParam: rawK00 ? cell.effectParam : nil,
                    instrumentOnlyVolumeRestored: restoresInstrumentOnlyDefaults)
            }
            if restoresInstrumentOnlyDefaults {
                if channelState.activeEventIndex == nil {
                    channelState.keyOffWithoutVoice = cell.note == 97 || rawK00
                }
                instrumentOnlyReset = restoreInstrumentOnlyDefaults(cell: cell, source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame,
                    globalVolume: context.globalVolumeState.volumeValue, channelState: &channelState,
                    updates: &context.voiceStateUpdates, resets: &context.playbackStateEvents)
            }
            if channelState.activeEventIndex == nil && !handlesTonePortamento &&
                (cell.note == 97 || (hasKxxKeyOff && cell.effectParam == 0)) {
                channelState.keyOffWithoutVoice = true
            }
            prepareTremoloRow(
                cell: cell, song: song, source: source, channelIndex: channelIndex,
                syntheticRow: syntheticRow, scheduledFrame: scheduledStartFrame,
                globalVolume: context.globalVolumeState.volumeValue,
                initializesInstrumentVolume: refusedSelection != nil || explicitTriggerSelection?.sample != nil || selectedEmptyPitch != nil || restoresInstrumentOnlyDefaults ||
                    (toneTargetSelection?.sample != nil && channelState.activeEventIndex != nil) ||
                    (toneTargetSelection != nil && channelState.activeEventIndex == nil && channelState.semanticInstrumentIndex == nil),
                channelState: &channelState, updates: &context.voiceStateUpdates,
                observer: &context.rowEntryTriggerResetObserver
            )
            if let sample = explicitTriggerSelection?.sample {
                channelState.baseChannelVolume = sampleVolumeRawEstimate(for: sample.volume)
                channelState.volumeValueZeroedByAxy = false
            }
            var toneInstrumentResetApplied = false
            if toneTargetSelection?.sample != nil ||
                (toneTargetSelection != nil && channelState.activeEventIndex == nil && channelState.semanticInstrumentIndex == nil) {
                let before = channelState
                toneInstrumentResetApplied = applySameCellTonePortamentoInstrumentReset(
                    cell: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                    scheduledFrame: scheduledStartFrame, globalVolume: context.globalVolumeState.volumeValue,
                    song: song, state: &channelState, context: &context, silentReset: &instrumentOnlyReset)
                if toneInstrumentResetApplied {
                    tonePortamentoInstrumentStateBefore = before
                    tonePortamentoInstrumentDefaultVolumeApplied = before.baseChannelVolume != channelState.baseChannelVolume
                }
            }
            let delaysInstrumentVolumeState = hasValidImmediateNoteInstrument && handlesTonePortamento && !toneInstrumentResetApplied
            let channelStateBeforeVolumeColumn = channelState
            if !delaysInstrumentVolumeState && !defersOrdinaryTriggerState {
                volumeColumn = applyVolumeColumn(volumeColumn, to: &channelState,
                    memorySource: effectMemorySource(source: source, channelIndex: channelIndex, cell: cell))
            }
            let hasDeferredEffectCell = hasDeferredEffect(cell, channelState: channelState)
            if !delaysInstrumentVolumeState && !defersOrdinaryTriggerState, let update = voiceStateUpdate(
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledStartFrame,
                cell: cell,
                volumeColumn: volumeColumn,
                channelStateBefore: channelStateBeforeVolumeColumn,
                channelStateAfter: channelState,
                globalVolumeValue: context.globalVolumeState.volumeValue
            ) {
                context.voiceStateUpdates.append(update)
            }
            if let update = applyEffectColumnState(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                scheduledFrame: scheduledStartFrame,
                rowSpeed: timingConfig.speed,
                channelState: &channelState,
                globalVolumeValue: context.globalVolumeState.volumeValue
            ) {
                context.voiceStateUpdates.append(update)
            }
            if hasVibratoControlEffect {
                let diagnostic = handleVibratoControl(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    channelState: &channelState
                )
                context.vibratoControlEffects.append(diagnostic)
            }
            context.channelStates[channelIndex] = channelState
            if cell.effectType == 0x10 {
                context.voiceStateUpdates.append(contentsOf: applyGlobalVolumeSet(
                    from: cell,
                    source: source,
                    sourceChannelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledStartFrame,
                    channelStates: context.channelStates,
                    globalVolumeState: &context.globalVolumeState
                ))
            }
            if cell.effectType == 0x11 && cell.effectParam == 0 && channelState.globalVolumeSlideMemory == nil {
                context.voiceStateUpdates.append(contentsOf: applyGlobalVolumeSlide(
                    from: cell,
                    source: source,
                    sourceChannelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledStartFrame,
                    channelStates: context.channelStates,
                    globalVolumeState: &context.globalVolumeState
                ))
            }
            if !delaysInstrumentVolumeState && !defersOrdinaryTriggerState, cell.volumeColumn != 0 {
                context.volumeColumnMappings.append(PlaybackSongSyntheticVolumeColumnMapping(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    syntheticTick: 0,
                    volumeColumn: volumeColumn
                ))
            }
            if !delaysInstrumentVolumeState {
                appendDeferredFields(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    volumeColumn: volumeColumn,
                    includeKeyOff: false,
                    hasDeferredEffectOverride: hasDeferredEffectCell,
                    deferredCellFields: &context.deferredCellFields
                )
            }
            let noteDelay = hasNoteDelayEffect
                ? noteDelayDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    originalFrame: scheduledStartFrame,
                    eventIndex: nil,
                    instrumentOnlyImmediate: restoresInstrumentOnlyDefaults
                )
                : nil
            if hasArpeggio, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handleArpeggio(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                appendArpeggio(diagnostic, to: &context)
                context.channelStates[channelIndex] = channelState
            }
            if hasPortamentoSlide, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handlePortamentoSlide(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState
                )
                appendPitchWriter(diagnostic, to: &context)
                context.channelStates[channelIndex] = channelState
            }
            if hasFinePortamentoUpEffect, !(1...96).contains(cell.note) {
                let diagnostic = handleFinePortamentoUp(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                appendFinePitch(diagnostic, to: &context)
                context.channelStates[channelIndex] = channelState
            }
            if hasFinePortamentoDownEffect, !(1...96).contains(cell.note) {
                let diagnostic = handleFinePortamentoDown(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                appendFinePitch(diagnostic, to: &context)
                context.channelStates[channelIndex] = channelState
            }
            if hasXxyExtraFinePortamentoEffect, !(1...96).contains(cell.note) {
                let diagnostic = handleExtraFinePortamento(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    timingPlan: timingPlan,
                    channelState: &channelState
                )
                appendFinePitch(diagnostic, to: &context)
                context.channelStates[channelIndex] = channelState
            }
            if hasVibrato || hasVibratoVolumeSlide, !(1...96).contains(cell.note), cell.note != 97 {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    restoreAtRowEnd: restoreVibratoAtRowEnd,
                    channelState: &channelState
                )
                appendPitchWriter(diagnostic, to: &context)
                context.channelStates[channelIndex] = channelState
            }
            if handlesTonePortamento, cell.note != 97, !delaysInstrumentVolumeState {
                if toneInstrumentResetApplied { tonePortamentoInstrumentStateAfter = channelState }
                let diagnostic = handleTonePortamento(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState,
                    instrumentStateBefore: tonePortamentoInstrumentStateBefore,
                    instrumentStateAfter: tonePortamentoInstrumentStateAfter,
                    instrumentDefaultVolumeApplied: tonePortamentoInstrumentDefaultVolumeApplied,
                    sampleSelectedBefore: tonePortamentoInstrumentStateBefore?.activeSampleIndex,
                    sampleSelectedAfter: tonePortamentoInstrumentStateAfter?.activeSampleIndex,
                    targetPitchSample: toneInstrumentResetApplied && channelState.activeEventIndex != nil ? toneTargetSelection?.sample : nil,
                    volumeColumn: hasVolumeColumnTonePortamento ? volumeColumn : nil,
                    executionTicks: isRxyMultiRetriggerEffect(cell) ? 1..<1 : nil
                )
                appendPitchWriter(diagnostic, to: &context, invocationTick: isRxyMultiRetriggerEffect(cell) ? nil : 1)
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                context.channelStates[channelIndex] = channelState
                continue
            }
            if cell.note == 97 || (hasKxxKeyOff && cell.effectParam == 0 && !hasVolumeColumnTonePortamento) {
                if hasRetriggerEffect {
                    _ = handleRetrigger(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        volumeColumn: volumeColumn,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        globalVolumeState: context.globalVolumeState,
                        channelState: &channelState,
                        events: &context.events,
                        eventMappings: &context.eventMappings,
                        retriggerEffects: &context.retriggerEffects,
                        eventCoverage: &context.eventCoverage
                    )
                }
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect && refusedSelection == nil {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: song.usesLinearFrequencyTable ? .noNoteDeferred : .noNoteInert,
                        activeVoiceFound: channelState.activeEventIndex != nil,
                        activeEventIndex: channelState.activeEventIndex,
                        activeEventMappingIndex: channelState.activeEventMappingIndex
                    ))
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                }
                context.channelStates[channelIndex] = channelState
                continue
            }
            guard (1...96).contains(cell.note) else {
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                let retrigger = hasRetriggerEffect
                    ? handleRetrigger(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        volumeColumn: volumeColumn,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        globalVolumeState: context.globalVolumeState,
                        channelState: &channelState,
                        events: &context.events,
                        eventMappings: &context.eventMappings,
                        retriggerEffects: &context.retriggerEffects,
                        eventCoverage: &context.eventCoverage
                    )
                    : nil
                if retrigger?.applied == true {
                    context.channelStates[channelIndex] = channelState
                    continue
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: song.usesLinearFrequencyTable ? .noNoteDeferred : .noNoteInert,
                        activeVoiceFound: channelState.activeEventIndex != nil,
                        activeEventIndex: channelState.activeEventIndex,
                        activeEventMappingIndex: channelState.activeEventMappingIndex
                    ))
                }
                if hasKxxKeyOff {
                    context.channelStates[channelIndex] = channelState
                    continue
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                    context.channelStates[channelIndex] = channelState
                    continue
                }
                if refusedSelection != nil { continue }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: noteDelay?.status == .noNoteDeferred
                        ? .noteDelayWithoutNote
                        : ignoredNoteReason(cell, volumeColumn: volumeColumn),
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: noteDelay != nil || hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: false)
                context.channelStates[channelIndex] = channelState
                continue
            }
            if ordinaryDelayedBx {
                // Bx belongs to the incoming source through the ED dispatch tick.
                // Only an admitted trigger below can supersede that tick's write.
                ordinaryBxDiagnosticIndex = context.vibratoEffects.count
                appendOrdinaryDelayedVibrato(cell: cell, source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, ticks: 1..<min(extendedEffectTick(cell) + 1, timingConfig.speed),
                    timingConfig: timingConfig, timingPlan: timingPlan, state: &channelState, context: &context)
            }
            if let noteDelay, noteDelay.outOfRow {
                context.noteDelayEffects.append(noteDelay)
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .noteDelayOutOfRow,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: true
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }

            let instrumentIndex = routedInstrumentIndex
            guard instrumentIndex > 0 else {
                if (hasVibrato || hasVibratoVolumeSlide) && !ordinaryDelayedBx {
                    // No owning instrument means no sample trigger or fallback.
                    appendPitchWriter(handleVibrato(
                        from: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                        timingConfig: timingConfig, timingPlan: timingPlan,
                        restoreAtRowEnd: restoreVibratoAtRowEnd, channelState: &channelState
                    ), to: &context)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noActiveVoice,
                        activeVoiceFound: false,
                        activeEventIndex: nil,
                        activeEventMappingIndex: nil
                    ))
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasXxyExtraFinePortamentoEffect {
                    let diagnostic = handleExtraFinePortamento(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .missingInstrument,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }
            guard let instrument = song.instrument(forInstrument: instrumentIndex) else {
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: .noActiveVoice,
                        activeVoiceFound: false,
                        activeEventIndex: nil,
                        activeEventMappingIndex: nil
                    ))
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasXxyExtraFinePortamentoEffect {
                    let diagnostic = handleExtraFinePortamento(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .unknownInstrument,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }
            let sampleSelection = explicitTriggerSelection ?? toneTargetSelection ?? selectSample(forNote: cell.note, from: instrument,
                missingKeymapPolicy: isNoteOnly || isE90 ? .fail : .firstPlayableSample)
            guard let sample = sampleSelection.sample else {
                if selectedEmptyPitch == nil && ordinaryEmptyHeader == nil && !(hasNoteDelayEffect && extendedEffectTick(cell) > 0) {
                    captureSelection(source: source, row: syntheticRow, tick: 0, channel: channelIndex,
                        frame: scheduledStartFrame, role: .unavailableRoute, linear: song.usesLinearFrequencyTable,
                        noteOnly: isNoteOnly, routedInstrument: instrumentIndex, selection: sampleSelection, state: channelState, context: &context)
                }
                if (hasVibrato || hasVibratoVolumeSlide) && !ordinaryDelayedBx {
                    // Empty routing retires the source, not channel-local effect execution.
                    // The existing instrument gate has already applied the prior E4 reset policy.
                    appendPitchWriter(handleVibrato(
                        from: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                        timingConfig: timingConfig, timingPlan: timingPlan,
                        restoreAtRowEnd: restoreVibratoAtRowEnd, channelState: &channelState
                    ), to: &context)
                }
                if let header = ordinaryEmptyHeader, var delay = noteDelay {
                    if delay.requestedTick > 0 {
                        supersedeDelayedVibratoBirth(ordinaryBxDiagnosticIndex, tick: delay.requestedTick, context: &context)
                        if isOrdinaryVolumeColumnSlide(cell.volumeColumn) {
                            for tick in 1...delay.requestedTick {
                                context.voiceStateUpdates.append(contentsOf: applyVolumeColumnSlideTick(volumeColumn,
                                    cell: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                                    tick: tick, rowSpeed: timingConfig.speed, timingPlan: timingPlan,
                                    state: &channelState, globalVolume: context.globalVolumeState.volumeValue))
                            }
                        }
                        selectedEmptyPitch = dispatchOrdinaryEmptyHeader(header, cell: cell, source: source,
                            syntheticRow: syntheticRow, channelIndex: channelIndex, frame: delay.delayedFrame!, tick: delay.requestedTick, selection: sampleSelection,
                            song: song, timingConfig: timingConfig, state: &channelState, context: &context)
                        resetDelayedInstrument(cell: cell, state: &channelState)
                        context.semanticPitchBuilder.add(tick: delay.requestedTick, channel: channelIndex, action: .automaticReset(.delayedNote))
                    }
                    delay.cachedDefaultVolume = channelState.triggeredSampleDefaultVolume
                    delay.cachedDefaultPan = channelState.triggeredSampleDefaultPan
                    delay.delayedPanningValue = channelState.panningValue
                    context.noteDelayEffects.append(delay)
                }
                if isNoteOnly, let slot = sampleSelection.mappedSampleIndex {
                    if let delay = noteDelay, delay.applied, delay.requestedTick > 0 {
                        supersedeDelayedVibratoBirth(ordinaryBxDiagnosticIndex, tick: delay.requestedTick, context: &context)
                        context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
                            scheduledFrame: delay.delayedFrame ?? scheduledStartFrame, instrumentIndex: instrumentIndex,
                            sampleIndex: slot, stoppedEventIndex: channelState.activeEventIndex, tick: delay.requestedTick))
                        if let header = song.xmSampleSlotProvenanceByInstrument[instrumentIndex]?.first(where: {
                            $0.sampleIndex == slot && $0.declaredPayloadLength == 0 && $0.decodedPayloadLength == 0
                        }) {
                            selectedEmptyPitch = selectEmptyHeader(header, cell: cell, instrumentIndex: instrumentIndex,
                                initializesDefaults: false, song: song, timingConfig: timingConfig, state: &channelState)
                            captureSelection(source: source, row: syntheticRow, tick: delay.requestedTick, channel: channelIndex,
                                frame: delay.delayedFrame!, role: .emptySelection, linear: song.usesLinearFrequencyTable,
                                noteOnly: true, tuning: .declaredEmptyHeader, routedInstrument: instrumentIndex,
                                selection: sampleSelection, state: channelState, context: &context)
                        } else {
                            clearSourceAssociation(&channelState)
                            channelState.semanticInstrumentIndex = instrumentIndex
                            channelState.semanticSampleIndex = slot
                            channelState.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
                            applyActiveVolumeEnvelopeMapping(mixerVolumeEnvelope(from: instrument.volumeEnvelope,
                                timingConfig: timingConfig), to: &channelState)
                            context.semanticPitchBuilder.add(tick: delay.requestedTick, channel: channelIndex,
                                action: .emptyRoute(context.xmEmptyRoutes.count - 1))
                        }
                        resetTremoloTriggerPhases(state: &channelState)
                        context.semanticPitchBuilder.add(tick: delay.requestedTick, channel: channelIndex, action: .automaticReset(.delayedNote))
                    }
                    // E9x repeats the selected empty route at the existing tick cadence.
                    // Its instrument reset belongs to the channel, with no source event.
                    let repeatInterval = retriggerIntervalNibble(from: cell)
                    if extendedSubcommand == 9, repeatInterval > 0, repeatInterval < timingConfig.speed {
                        resetTremoloTriggerPhases(state: &channelState)
                        for tick in stride(from: repeatInterval, to: timingConfig.speed, by: repeatInterval) {
                            context.semanticPitchBuilder.add(tick: tick, channel: channelIndex, action: .automaticReset(.retrigger))
                            context.xmEmptyRoutes.append(.init(source: source, channelIndex: channelIndex,
                                scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                                instrumentIndex: instrumentIndex, sampleIndex: slot, stoppedEventIndex: nil, tick: tick))
                        }
                    }
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasSetFinetuneEffect {
                    context.setFinetuneEffects.append(setFinetuneDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        status: selectedEmptyPitch.map { setFinetuneStatus(for: $0) } ?? .noActiveVoice,
                        activeVoiceFound: false,
                        activeEventIndex: nil,
                        activeEventMappingIndex: nil,
                        sampleFinetune: sampleSelection.diagnosticSample?.finetune,
                        pitchMapping: selectedEmptyPitch
                    ))
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasXxyExtraFinePortamentoEffect {
                    let diagnostic = handleExtraFinePortamento(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasLxxSetEnvelopePosition {
                    context.envelopePositionEffects.append(envelopePositionDiagnostic(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        timingConfig: timingConfig,
                        channelState: channelState
                    ))
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: sampleSelection.skippedReason ?? .unknown,
                    diagnosticSample: sampleSelection.diagnosticSample,
                    sampleMapKeymapPresent: sampleSelection.sampleMapKeymapPresent,
                    mappedSampleIndex: sampleSelection.mappedSampleIndex,
                    mappedSampleValid: sampleSelection.mappedSampleValid,
                    sampleSelectionMethod: sampleSelection.method,
                    firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred,
                    sampleMapKeymapMissingOrDeferred: sampleSelection.sampleMapKeymapMissingOrDeferred,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.eventCoverage.recordSkippedSampleSelection(
                    method: sampleSelection.method,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred
                )
                context.channelStates[channelIndex] = channelState
                continue
            }

            let sampleLength = selectedSampleLength(sample)
            if delaysInstrumentVolumeState {
                let instrumentStateBefore = channelState
                tonePortamentoInstrumentStateBefore = instrumentStateBefore
                tonePortamentoInstrumentStateAfter = channelState
                let instrumentGainBefore = instrumentStateBefore.activeSampleVolume.map { _ in
                    songGain(outputChannelVolume: instrumentStateBefore.outputChannelVolume)
                }
                let instrumentGainAfter = channelState.activeSampleVolume.map { _ in
                    songGain(outputChannelVolume: channelState.outputChannelVolume)
                }
                tonePortamentoInstrumentDefaultVolumeApplied = instrumentStateBefore.baseChannelVolume != channelState.baseChannelVolume ||
                    instrumentStateBefore.activeSampleVolume != channelState.activeSampleVolume
                if handlesTonePortamento {
                    context.voiceStateUpdates.append(voiceStateUpdateDiagnostic(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        scheduledFrame: scheduledStartFrame,
                        cell: cell,
                        commandSource: .instrumentState,
                        command: .instrumentDefaultVolume(value: channelState.baseChannelVolume),
                        rawVolumeColumn: nil,
                        effectType: cell.effectType,
                        effectParam: cell.effectParam,
                        status: .applied,
                        behavior: nil,
                        channelStateBefore: instrumentStateBefore,
                        channelStateAfter: channelState,
                        globalVolumeBefore: context.globalVolumeState.volumeValue,
                        globalVolumeAfter: context.globalVolumeState.volumeValue,
                        activeVoiceUpdatedOverride: instrumentStateBefore.activeEventIndex != nil &&
                            instrumentStateBefore.activeSampleVolume != nil &&
                            instrumentGainBefore != instrumentGainAfter
                    ))
                }
                let beforeVolumeColumn = channelState
                volumeColumn = applyVolumeColumn(volumeColumn, to: &channelState,
                    memorySource: effectMemorySource(source: source, channelIndex: channelIndex, cell: cell))
                if handlesTonePortamento {
                    tonePortamentoInstrumentStateAfter = channelState
                }
                if let update = voiceStateUpdate(
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledStartFrame,
                    cell: cell,
                    volumeColumn: volumeColumn,
                    channelStateBefore: beforeVolumeColumn,
                    channelStateAfter: channelState,
                    globalVolumeValue: context.globalVolumeState.volumeValue
                ) {
                    context.voiceStateUpdates.append(update)
                }
                if cell.volumeColumn != 0 {
                    context.volumeColumnMappings.append(PlaybackSongSyntheticVolumeColumnMapping(
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        syntheticTick: 0,
                        volumeColumn: volumeColumn
                    ))
                }
                appendDeferredFields(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    volumeColumn: volumeColumn,
                    includeKeyOff: false,
                    hasDeferredEffectOverride: hasDeferredEffectCell,
                    deferredCellFields: &context.deferredCellFields
                )
            }
            let sampleOffset = sampleOffsetDiagnostic(
                from: cell,
                source: source,
                channelIndex: channelIndex,
                syntheticRow: syntheticRow,
                selectedSampleLength: sampleLength,
                channelState: &channelState
            )
            if sampleOffset.detected {
                context.sampleOffsetEffects.append(sampleOffset)
            }
            if sampleOffset.skipped {
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                if hasFinePortamentoUpEffect {
                    let diagnostic = handleFinePortamentoUp(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasFinePortamentoDownEffect {
                    let diagnostic = handleFinePortamentoDown(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                if hasXxyExtraFinePortamentoEffect {
                    let diagnostic = handleExtraFinePortamento(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        timingPlan: timingPlan,
                        channelState: &channelState
                    )
                    appendFinePitch(diagnostic, to: &context)
                }
                let ignored = ignoredCell(
                    source: source,
                    channelIndex: channelIndex,
                    cell: cell,
                    reason: .sampleOffsetOutOfRange,
                    diagnosticSample: sample,
                    sampleOffsetFrames: sampleOffset.computedOffsetFrames,
                    sampleMapKeymapPresent: sampleSelection.sampleMapKeymapPresent,
                    mappedSampleIndex: sampleSelection.mappedSampleIndex,
                    mappedSampleValid: sampleSelection.mappedSampleValid,
                    sampleSelectionMethod: sampleSelection.method,
                    firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                    sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred,
                    sampleMapKeymapMissingOrDeferred: sampleSelection.sampleMapKeymapMissingOrDeferred,
                    volumeColumn: volumeColumn,
                    hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                    hasIgnoredEffect: hasDeferredEffectCell
                )
                context.ignoredCells.append(ignored)
                context.eventCoverage.recordIgnoredCell(reason: ignored.skipReason, isNormalNote: true)
                context.channelStates[channelIndex] = channelState
                continue
            }

            if !handlesTonePortamento && !isNoteOnly && !retainsDelayedTrigger {
                volumeColumn = applyTriggeredSamplePanning(
                    sample.panning,
                    volumeColumn: volumeColumn,
                    cell: cell,
                    to: &channelState
                )
            }

            if handlesTonePortamento {
                let diagnostic = handleTonePortamento(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState,
                    instrumentStateBefore: tonePortamentoInstrumentStateBefore,
                    instrumentStateAfter: tonePortamentoInstrumentStateAfter,
                    instrumentDefaultVolumeApplied: tonePortamentoInstrumentDefaultVolumeApplied,
                    sampleSelectedBefore: tonePortamentoInstrumentStateBefore?.activeSampleIndex,
                    sampleSelectedAfter: sample.sampleIndex,
                    volumeColumn: hasVolumeColumnTonePortamento ? volumeColumn : nil,
                    executionTicks: isRxyMultiRetriggerEffect(cell) ? 1..<1 : nil
                )
                appendPitchWriter(diagnostic, to: &context, invocationTick: isRxyMultiRetriggerEffect(cell) ? nil : 1)
                if let noteDelay {
                    context.noteDelayEffects.append(noteDelay)
                }
                if hasNoteCutEffect {
                    handleNoteCut(
                        from: cell,
                        source: source,
                        channelIndex: channelIndex,
                        syntheticRow: syntheticRow,
                        timingConfig: timingConfig,
                        timingPlan: timingPlan,
                        channelState: &channelState,
                        noteCutEffects: &context.noteCutEffects
                    )
                }
                context.channelStates[channelIndex] = channelState
                continue
            }

            let eventIndex = context.events.count
            let loop = mixerLoop(from: sample)
            let envelopeMapping = mixerVolumeEnvelope(
                from: instrument.volumeEnvelope,
                timingConfig: timingConfig
            )
            var envelopeSemantics = volumeEnvelopeSemantics(
                from: instrument.volumeEnvelope,
                mapping: envelopeMapping
            )
            if isE90, isNoteOnly, let parent = e90PreviousMapping,
               context.eventMappings[parent].volumeEnvelopeSemantics.keyOffEncountered {
                // Inherit the finalized causal annotation; the channel timeline owns
                // carried release/fadeout clocks. This source is not released again.
                envelopeSemantics = context.eventMappings[parent].volumeEnvelopeSemantics
            }
            let scheduledNoteFrame = noteDelay?.delayedFrame ?? scheduledStartFrame
            let scheduledNoteTick = noteDelay?.applied == true ? noteDelay?.requestedTick ?? 0 : 0
            if scheduledNoteTick > 0 {
                supersedeDelayedVibratoBirth(ordinaryBxDiagnosticIndex, tick: scheduledNoteTick, context: &context)
                // Column writes precede the existing delayed trigger/reset on its tick.
                if isOrdinaryVolumeColumnSlide(cell.volumeColumn) {
                    for tick in 1...scheduledNoteTick {
                        context.voiceStateUpdates.append(contentsOf: applyVolumeColumnSlideTick(volumeColumn, cell: cell, source: source,
                            channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick, rowSpeed: timingConfig.speed,
                            timingPlan: timingPlan, state: &channelState, globalVolume: context.globalVolumeState.volumeValue))
                    }
                }
                if retainsDelayedTrigger {
                    if cell.instrument > 0 {
                        channelState.triggeredSampleDefaultVolume = sampleVolumeRawEstimate(for: sample.volume)
                        channelState.triggeredSampleDefaultPan = sample.panning
                        restoreCachedInstrumentDefaults(state: &channelState)
                    }
                    switch volumeColumn.command {
                    case .setVolume, .setPanning: _ = applyVolumeColumn(volumeColumn, to: &channelState)
                    default: break
                    }
                }
                // The established EDx path has resolved a real delayed trigger.
                // Reset at that trigger, rather than on an out-of-row delay.
                resetTremoloTriggerPhases(state: &channelState)
                context.semanticPitchBuilder.add(tick: scheduledNoteTick, channel: channelIndex, action: .automaticReset(.delayedNote))
                if channelState.tremolo.activated, cell.instrument > 0, !retainsDelayedTrigger {
                    channelState.baseChannelVolume = 64
                    // FT2's delayed trigger replays an explicit volume value,
                    // not slide commands already handled by the column path.
                    if case .setVolume = volumeColumn.command {
                        _ = applyVolumeColumn(volumeColumn, to: &channelState)
                    }
                }
            }
            let setFinetuneOverride = hasSetFinetuneEffect
                ? setFinetuneValue(from: cell)
                : nil
            var pitchMapping = playbackStepMapping(
                note: cell.note,
                sample: sample,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                timingConfig: timingConfig,
                finetuneOverride: setFinetuneOverride
            )
            if ordinaryPitchAdmission(note: cell.note, relativeNote: sample.relativeNote) == .retained {
                pitchMapping = retainedPitchMapping(sample: sample, state: channelState,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable, timingConfig: timingConfig,
                    finetune: setFinetuneOverride ?? sample.finetune)
            }
            if hasSetFinetuneEffect {
                context.setFinetuneEffects.append(setFinetuneDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    status: setFinetuneStatus(for: pitchMapping),
                    activeVoiceFound: true,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    sampleFinetune: sample.finetune,
                    pitchMapping: pitchMapping
                ))
            }
            if hasFinePortamentoUpEffect {
                let result = finePortamentoUpAdjustedPitchMapping(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState,
                    basePitchMapping: pitchMapping,
                    baseSampleRate: sample.baseSampleRate,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    scheduledFrame: scheduledNoteFrame
                )
                pitchMapping = result.pitchMapping
                appendFinePitch(result.diagnostic, to: &context)
            }
            if hasFinePortamentoDownEffect {
                let result = finePortamentoDownAdjustedPitchMapping(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState,
                    basePitchMapping: pitchMapping,
                    baseSampleRate: sample.baseSampleRate,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    scheduledFrame: scheduledNoteFrame
                )
                pitchMapping = result.pitchMapping
                appendFinePitch(result.diagnostic, to: &context)
            }
            if hasXxyExtraFinePortamentoEffect {
                let result = extraFinePortamentoAdjustedPitchMapping(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState,
                    basePitchMapping: pitchMapping,
                    baseSampleRate: sample.baseSampleRate,
                    activeEventIndex: eventIndex,
                    activeEventMappingIndex: context.eventMappings.count,
                    scheduledFrame: scheduledNoteFrame
                )
                pitchMapping = result.pitchMapping
                appendFinePitch(result.diagnostic, to: &context)
            }
            let gain = songGain(
                outputChannelVolume: channelState.outputChannelVolume,
                globalVolume: context.globalVolumeState.volumeValue
            )
            let pan = channelState.pan
            if pitchMapping.playbackStep == 0 {
                context.initialHeldPitchEventIndices.insert(eventIndex)
            }
            if isNoteOnly && scheduledNoteTick == 0 {
                context.noteOnlyEventIndices.insert(eventIndex)
                if channelState.activeEventIndex == nil && channelState.keyOffWithoutVoice {
                    context.coldReleasedEventIndices.insert(eventIndex)
                }
            }
            context.events.append(SyntheticTrackerEvent(
                row: syntheticRow,
                tick: scheduledNoteTick,
                scheduledStartFrame: scheduledNoteFrame,
                sample: mixerSampleBuffer(for: sample, cache: &context.mixerSampleBuffers),
                gain: gain,
                pan: pan,
                playbackStep: pitchMapping.playbackStep,
                loop: loop,
                initialSourceFrame: sampleOffset.appliedOffsetFrames ?? 0,
                volumeEnvelope: envelopeMapping.envelope,
                panEnvelope: inertPanningEnvelopeClock(from: instrument.panningEnvelope, timingConfig: timingConfig)
            ))
            context.eventCoverage.recordScheduledNote(
                method: sampleSelection.method,
                firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred
            )
            if hasDeferredEffectCell || volumeColumn.deferred {
                context.eventCoverage.recordDeferredCellWithoutSkip()
            }
            channelState.activeEventIndex = eventIndex
            channelState.carriedNote = cell.note
            channelState.activeEventMappingIndex = context.eventMappings.count
            channelState.activeInstrumentIndex = instrumentIndex
            channelState.activeSampleIndex = sample.sampleIndex
            channelState.semanticInstrumentIndex = instrumentIndex
            channelState.semanticSampleIndex = sample.sampleIndex
            channelState.semanticVolumeEnvelopeEnabled = instrument.volumeEnvelope.enabled
            channelState.activeSampleVolume = sample.volume
            channelState.triggeredSampleDefaultVolume = sampleVolumeRawEstimate(for: sample.volume)
            channelState.triggeredSampleDefaultPan = sample.panning
            channelState.activePlaybackStep = pitchMapping.playbackStep
            channelState.activeLinearPeriod = pitchMapping.linearPeriod
            channelState.vibratoOutputLinearPeriod = nil
            channelState.vibratoOutputAmigaPeriod = nil
            channelState.activeAmigaPeriod = pitchMapping.amigaPeriod
            channelState.activeSampleBaseSampleRate = sample.baseSampleRate
            channelState.activeSampleRelativeNote = sample.relativeNote
            channelState.activeSampleFinetune = pitchMapping.effectiveFinetune ?? sample.finetune
            channelState.activeUsesLinearFrequencyTable = song.usesLinearFrequencyTable
            applyActiveVolumeEnvelopeMapping(envelopeMapping, to: &channelState)
            captureSelection(source: source, row: syntheticRow, tick: scheduledNoteTick, channel: channelIndex,
                frame: scheduledNoteFrame, role: .trigger, linear: song.usesLinearFrequencyTable,
                noteOnly: isNoteOnly, tuning: .representedHeader, finetuneCommand: hasSetFinetuneEffect,
                routedInstrument: instrumentIndex, selection: sampleSelection, state: channelState, context: &context)
            // The latent tone target belongs to the channel, independently of this
            // new source. Only target-setting commands replace it; 300 can reuse it.
            channelState.volumeValueZeroedByAxy = false
            context.channelStates[channelIndex] = channelState
            context.eventMappings.append(PlaybackSongSyntheticEventMapping(
                source: source,
                channelIndex: channelIndex,
                note: cell.note,
                instrumentIndex: instrumentIndex,
                sampleIndex: sample.sampleIndex,
                sampleVolume: sample.volume,
                sampleVolumeRawEstimate: sampleVolumeRawEstimate(for: sample.volume),
                selectedSampleLength: sampleLength,
                sampleMapKeymapPresent: sampleSelection.sampleMapKeymapPresent,
                mappedSampleIndex: sampleSelection.mappedSampleIndex,
                mappedSampleValid: sampleSelection.mappedSampleValid,
                sampleSelectionMethod: sampleSelection.method,
                sampleSelectionStrategy: sampleSelection.method.rawValue,
                firstPlayableSampleFallbackUsed: sampleSelection.firstPlayableSampleFallbackUsed,
                sampleMapKeymapBehaviorDeferred: sampleSelection.sampleMapKeymapBehaviorDeferred,
                sampleMapKeymapMissingOrDeferred: sampleSelection.sampleMapKeymapMissingOrDeferred,
                effectType: cell.effectType,
                effectParam: cell.effectParam,
                syntheticRow: syntheticRow,
                syntheticTick: scheduledNoteTick,
                eventIndex: eventIndex,
                loopMode: loop.mode,
                volumeColumn: volumeColumn,
                sampleOffset: sampleOffset,
                hasIgnoredVolumeColumn: cell.volumeColumn != 0 && !volumeColumn.applied,
                hasIgnoredEffect: hasDeferredEffectCell,
                effectiveVolumeValue: channelState.outputChannelVolume,
                effectiveGlobalVolumeValue: context.globalVolumeState.volumeValue,
                effectiveGlobalVolumeMultiplier: context.globalVolumeState.multiplier,
                effectivePan: pan,
                volumeEnvelopeStatus: envelopeMapping.status,
                sourceVolumeEnvelopePointCount: envelopeMapping.sourcePointCount,
                mappedVolumeEnvelopePointCount: envelopeMapping.mappedPointCount,
                hasDeferredVolumeEnvelopeSustain: envelopeSemantics.sustainDeferred,
                hasDeferredVolumeEnvelopeLoop: envelopeSemantics.loopDeferred,
                hasDeferredVolumeEnvelopeFadeout: envelopeSemantics.fadeoutDeferred,
                volumeEnvelopeSemantics: envelopeSemantics,
                sampleBaseSampleRate: sample.baseSampleRate,
                sampleRelativeNote: sample.relativeNote,
                sampleFinetune: sample.finetune,
                outputSampleRate: pitchMapping.outputSampleRate,
                effectiveNoteValue: pitchMapping.effectiveNoteValue,
                effectiveNoteIndex: pitchMapping.effectiveNoteIndex,
                effectiveFinetune: pitchMapping.effectiveFinetune,
                linearPeriod: pitchMapping.linearPeriod,
                linearFrequency: pitchMapping.linearFrequency,
                amigaPeriod: pitchMapping.amigaPeriod,
                amigaFrequency: pitchMapping.amigaFrequency,
                finetuneStatus: pitchMapping.finetuneStatus,
                usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                frequencyTableStatus: pitchMapping.frequencyTableStatus,
                linearFrequencyApplied: pitchMapping.linearFrequencyApplied,
                amigaFrequencyApplied: pitchMapping.amigaFrequencyApplied,
                amigaFrequencyDeferred: pitchMapping.amigaFrequencyDeferred,
                playbackStep: pitchMapping.playbackStep,
                pitchMappingApplied: pitchMapping.applied,
                pitchMappingUsedNeutralStep: pitchMapping.usedNeutralStep
            ))
            if hasLxxSetEnvelopePosition {
                context.envelopePositionEffects.append(envelopePositionDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    scheduledFrame: scheduledNoteFrame,
                    timingConfig: timingConfig,
                    channelState: channelState
                ))
            }
            if hasArpeggio {
                let diagnostic = handleArpeggio(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    includeTickZeroUpdate: false
                )
                appendArpeggio(diagnostic, to: &context)
                context.channelStates[channelIndex] = channelState
            }
            if hasPortamentoSlide {
                let diagnostic = handlePortamentoSlide(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                    channelState: &channelState
                )
                appendPitchWriter(diagnostic, to: &context)
                context.channelStates[channelIndex] = channelState
            }
            if (hasVibrato || hasVibratoVolumeSlide) && !ordinaryDelayedBx {
                let diagnostic = handleVibrato(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    restoreAtRowEnd: restoreVibratoAtRowEnd,
                    channelState: &channelState
                )
                appendPitchWriter(diagnostic, to: &context)
                context.channelStates[channelIndex] = channelState
            }
            if let noteDelay, noteDelay.applied {
                var appliedDelay = noteDelayDiagnostic(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    originalFrame: scheduledStartFrame,
                    eventIndex: eventIndex
                ) ?? noteDelay
                if retainsDelayedTrigger {
                    appliedDelay.cachedDefaultVolume = channelState.triggeredSampleDefaultVolume
                    appliedDelay.cachedDefaultPan = channelState.triggeredSampleDefaultPan
                    appliedDelay.delayedPanningValue = channelState.panningValue
                }
                context.noteDelayEffects.append(appliedDelay)
            }
            if hasRetriggerEffect {
                _ = handleRetrigger(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    volumeColumn: volumeColumn,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    globalVolumeState: context.globalVolumeState,
                    channelState: &channelState,
                    events: &context.events,
                    eventMappings: &context.eventMappings,
                    retriggerEffects: &context.retriggerEffects,
                    eventCoverage: &context.eventCoverage
                )
            }
            if hasNoteCutEffect {
                handleNoteCut(
                    from: cell,
                    source: source,
                    channelIndex: channelIndex,
                    syntheticRow: syntheticRow,
                    timingConfig: timingConfig,
                    timingPlan: timingPlan,
                    channelState: &channelState,
                    noteCutEffects: &context.noteCutEffects
                )
            }
            context.channelStates[channelIndex] = channelState
        }
        // Plan ordinary column slides and 6xy/tremolo after all tick-zero writers.
        // A later channel's Gxx must not see a future slide or tremolo value.
        for channelIndex in row.cells.indices {
            let cell = row.cells[channelIndex]
            if isDelayedInstrumentOnly(cell) {
                handleDelayedInstrumentOnly(cell: cell, source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, song: song, timingConfig: timingConfig,
                    timingPlan: timingPlan, context: &context)
                continue
            }
            if isNonzeroOrdinaryDelay(cell), let selection = refusedOrdinarySelection(cell: cell,
                instrumentIndex: cell.instrument == 0 ? context.channelStates[channelIndex].carriedInstrumentIndex ?? 0 : Int(cell.instrument), song: song) {
                handleDelayedRefusedOrdinary(selection, cell: cell, source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, song: song, timingConfig: timingConfig,
                    timingPlan: timingPlan, context: &context)
                continue
            }
            let columnSlide = isOrdinaryVolumeColumnSlide(cell.volumeColumn)
                ? PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn) : nil
            if isNoteCutEffect(cell), extendedEffectTick(cell) > 0 {
                // Column slides precede ECx on each actual tick. Do not expose a future
                // zero to tick-zero snapshots or to another channel's row-entry writers.
                for tick in 1..<max(1, timingConfig.speed) {
                    context.voiceStateUpdates.append(contentsOf: applyVolumeColumnSlideTick(columnSlide, cell: cell,
                        source: source, channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick,
                        rowSpeed: timingConfig.speed, timingPlan: timingPlan,
                        state: &context.channelStates[channelIndex], globalVolume: context.globalVolumeState.volumeValue))
                    if tick == extendedEffectTick(cell) {
                        applyNoteCutVolume(cell: cell, source: source, channelIndex: channelIndex,
                            syntheticRow: syntheticRow, tick: tick, timingPlan: timingPlan,
                            globalVolume: context.globalVolumeState.volumeValue,
                            state: &context.channelStates[channelIndex], updates: &context.voiceStateUpdates)
                    }
                }
                continue
            }
            if isKxxKeyOffEffect(cell) {
                var state = context.channelStates[channelIndex]
                let releaseTick = Int(cell.effectParam & 31)
                if cell.effectParam != 0 && (releaseTick == 0 || releaseTick >= timingConfig.speed) {
                    handleKxxKeyOff(from: cell, source: source, channelIndex: channelIndex,
                        syntheticRow: syntheticRow, timingConfig: timingConfig, timingPlan: timingPlan,
                        volumeColumn: PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn),
                        channelState: &state, context: &context)
                }
                for tick in 1..<max(1, timingConfig.speed) {
                    context.voiceStateUpdates.append(contentsOf: applyVolumeColumnSlideTick(columnSlide, cell: cell,
                        source: source, channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick,
                        rowSpeed: timingConfig.speed, timingPlan: timingPlan, state: &state,
                        globalVolume: context.globalVolumeState.volumeValue))
                    // Release consumes this tick's column write, not a future row mutation.
                    if cell.effectParam != 0 && tick == releaseTick {
                        handleKxxKeyOff(from: cell, source: source, channelIndex: channelIndex,
                            syntheticRow: syntheticRow, timingConfig: timingConfig, timingPlan: timingPlan,
                            volumeColumn: PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn),
                            channelState: &state, context: &context)
                    }
                }
                context.channelStates[channelIndex] = state
                continue
            }
            if isRxyMultiRetriggerEffect(cell) {
                // Only this R row needs interleaved column/retrigger invocations.
                // Tick zero already ran on the channel's ordinary row-entry path.
                let index = context.retriggerEffects.lastIndex {
                    $0.syntheticRow == syntheticRow && $0.channelIndex == channelIndex
                }!
                var state = context.channelStates[channelIndex]
                for tick in 1..<max(1, timingConfig.speed) {
                    context.voiceStateUpdates.append(contentsOf: applyVolumeColumnSlideTick(columnSlide, cell: cell,
                        source: source, channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick,
                        rowSpeed: timingConfig.speed, timingPlan: timingPlan, state: &state,
                        globalVolume: context.globalVolumeState.volumeValue))
                    if (0xB0...0xBF).contains(cell.volumeColumn) {
                        appendPitchWriter(handleVibrato(from: cell, source: source, channelIndex: channelIndex,
                            syntheticRow: syntheticRow, timingConfig: timingConfig, timingPlan: timingPlan,
                            channelState: &state, executionTicks: tick..<(tick + 1)), to: &context)
                    }
                    if cell.volumeColumn >> 4 == 0x0F {
                        let continuation = PlaybackCell(note: 0, instrument: 0, volumeColumn: cell.volumeColumn,
                            effectType: cell.effectType, effectParam: cell.effectParam)
                        appendPitchWriter(handleTonePortamento(from: continuation, source: source,
                            channelIndex: channelIndex, syntheticRow: syntheticRow, timingConfig: timingConfig,
                            timingPlan: timingPlan, usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                            channelState: &state, volumeColumn: PlaybackSongVolumeColumnDecoder.decode(cell.volumeColumn),
                            executionTicks: tick..<(tick + 1)), to: &context, invocationTick: tick)
                    }
                    handleRxyTick(cell: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                        tick: tick, song: song, timingConfig: timingConfig, timingPlan: timingPlan,
                        state: &state, context: &context, diagnosticIndex: index)
                }
                context.channelStates[channelIndex] = state
                continue
            }
            if cell.effectType == 0x19 {
                context.voiceStateUpdates.append(contentsOf: applyPxyPanningSlide(
                    cell: cell, columnSlide: columnSlide, source: source, channelIndex: channelIndex,
                    syntheticRow: syntheticRow, rowSpeed: timingConfig.speed, timingPlan: timingPlan,
                    state: &context.channelStates[channelIndex], globalVolume: context.globalVolumeState.volumeValue))
            } else if columnSlide != nil {
                if cell.effectType == 0x0A || cell.effectType == 0x05 {
                    context.voiceStateUpdates.append(contentsOf: applyEffectColumnVolumeSlide(
                        from: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                        timingConfig: timingConfig, timingPlan: timingPlan,
                        channelState: &context.channelStates[channelIndex], usesLinearFrequencyTable: song.usesLinearFrequencyTable,
                        globalVolumeValue: context.globalVolumeState.volumeValue,
                        volumeColumnSlide: columnSlide))
                } else if cell.effectType != 0x06 && cell.effectType != 0x07 && timingConfig.speed > 1 {
                    var firstTick = 1
                    if cell.effectType == 0x0E && cell.effectParam >> 4 == 0x0D,
                       let eventIndex = context.channelStates[channelIndex].activeEventIndex,
                       context.events[eventIndex].row == syntheticRow {
                        firstTick = max(1, context.events[eventIndex].tick + 1)
                    }
                    if ordinaryDelayedEmptyHeader(cell: cell, song: song) != nil,
                       isNonzeroOrdinaryDelay(cell), extendedEffectTick(cell) < timingConfig.speed {
                        firstTick = extendedEffectTick(cell) + 1
                    }
                    for tick in firstTick..<timingConfig.speed {
                        context.voiceStateUpdates.append(contentsOf: applyVolumeColumnSlideTick(columnSlide, cell: cell, source: source,
                            channelIndex: channelIndex, syntheticRow: syntheticRow, tick: tick, rowSpeed: timingConfig.speed,
                            timingPlan: timingPlan, state: &context.channelStates[channelIndex],
                            globalVolume: context.globalVolumeState.volumeValue))
                    }
                }
            }
            context.voiceStateUpdates.append(contentsOf: apply6xyVolumeSlide(
                from: cell, source: source, channelIndex: channelIndex, syntheticRow: syntheticRow,
                timingConfig: timingConfig, timingPlan: timingPlan,
                channelState: &context.channelStates[channelIndex], globalVolumeValue: context.globalVolumeState.volumeValue,
                volumeColumnSlide: columnSlide
            ))
            advanceTremoloVibratoObserver(cell: cell, rowSpeed: timingConfig.speed,
                                         state: &context.channelStates[channelIndex])
            context.voiceStateUpdates.append(contentsOf: applyTremolo(
                cell: cell, source: source, channelIndex: channelIndex,
                syntheticRow: syntheticRow, timingConfig: timingConfig,
                timingPlan: timingPlan, globalVolume: context.globalVolumeState.volumeValue,
                state: &context.channelStates[channelIndex], volumeColumnSlide: columnSlide
            ))
        }
        if timingConfig.speed > 1 {
            for tick in 1..<timingConfig.speed {
                for channelIndex in row.cells.indices where row.cells[channelIndex].effectType == 0x11 {
                    // Cold H00 has no publication. Seeded replay enters G12 unchanged.
                    guard row.cells[channelIndex].effectParam != 0 || context.channelStates[channelIndex].globalVolumeSlideMemory != nil else { continue }
                    context.voiceStateUpdates.append(contentsOf: applyGlobalVolumeSlide(
                        from: row.cells[channelIndex], source: source, sourceChannelIndex: channelIndex,
                        syntheticRow: syntheticRow, syntheticTick: tick,
                        scheduledFrame: timingPlan.frameFor(row: syntheticRow, tick: tick),
                        channelStates: context.channelStates, globalVolumeState: &context.globalVolumeState))
                }
            }
        }
        return PlaybackSongSyntheticRowDiagnostic(
            source: source,
            syntheticRow: syntheticRow,
            cellCount: row.cells.count,
            emittedEventCount: context.events.count - eventStartCount,
            ignoredCellCount: context.ignoredCells.count - ignoredStartCount
        )
    }

}
