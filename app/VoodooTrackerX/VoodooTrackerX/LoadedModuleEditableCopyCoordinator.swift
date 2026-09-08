import Foundation

enum LoadedModuleEditableCopyDocumentKind: Equatable {
    case none
    case editable
    case loadedReadOnly
}

struct LoadedModuleEditableCopyContext: Equatable {
    let moduleIdentity: UUID?
    let kind: LoadedModuleEditableCopyDocumentKind
    let loadedMetadata: ParsedModuleMetadata?
    let loadedPlaybackSong: PlaybackSong?
    let selection: TrackerEditorSelection
    let currentPatternIndex: Int
    let isPlaybackActive: Bool

    static func loadedReadOnly(
        moduleIdentity: UUID? = UUID(),
        metadata: ParsedModuleMetadata?,
        playbackSong: PlaybackSong?,
        selection: TrackerEditorSelection,
        currentPatternIndex: Int,
        isPlaybackActive: Bool
    ) -> LoadedModuleEditableCopyContext {
        LoadedModuleEditableCopyContext(
            moduleIdentity: moduleIdentity,
            kind: .loadedReadOnly,
            loadedMetadata: metadata,
            loadedPlaybackSong: playbackSong,
            selection: selection,
            currentPatternIndex: currentPatternIndex,
            isPlaybackActive: isPlaybackActive
        )
    }

    static func editable(isPlaybackActive: Bool) -> LoadedModuleEditableCopyContext {
        LoadedModuleEditableCopyContext(
            moduleIdentity: nil,
            kind: .editable,
            loadedMetadata: nil,
            loadedPlaybackSong: nil,
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: isPlaybackActive
        )
    }

    static func none(isPlaybackActive: Bool) -> LoadedModuleEditableCopyContext {
        LoadedModuleEditableCopyContext(
            moduleIdentity: nil,
            kind: .none,
            loadedMetadata: nil,
            loadedPlaybackSong: nil,
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: isPlaybackActive
        )
    }
}

enum LoadedModuleEditableCopyResult: Equatable {
    case unavailable(LoadedModuleEditableCopyPlanUnavailableReason)
    case copied(BlankTrackerDocument)
    case normalized(BlankTrackerDocument, LoadedModuleEditableCopyNormalizationSummary)

    var userFacingTitle: String? {
        switch self {
        case .copied, .normalized:
            return "Editable Copy Created"
        case .unavailable(.noLoadedModule),
             .unavailable(.alreadyEditable),
             .unavailable(.playbackActive):
            return nil
        case .unavailable:
            return "Make Editable Copy Unavailable"
        }
    }

    var userFacingMessage: String? {
        switch self {
        case .copied:
            return "Created an untitled in-memory editable copy of the supported XM subset. The original module remains read-only and untouched."
        case .normalized:
            return "Created an untitled editable copy. VTX normalized empty sample-slot metadata that does not affect playback. The original XM remains unchanged. If you export this editable copy as XM, the file may differ structurally from the original."
        case .unavailable(.noLoadedModule),
             .unavailable(.alreadyEditable),
             .unavailable(.playbackActive):
            return nil
        case let .unavailable(reason):
            return reason.userFacingMessage
        }
    }

    var acknowledgementButtonTitle: String? {
        switch self {
        case .unavailable(.noLoadedModule),
             .unavailable(.alreadyEditable),
             .unavailable(.playbackActive),
             .copied,
             .normalized:
            return nil
        case .unavailable:
            return "OK"
        }
    }
}

struct LoadedModuleEditableCopyNormalizationSummary: Equatable {
    let requiredEmptySlotsCanonicalized: Int
    let trailingEmptySlotsDropped: Int
    let instrumentCountAffected: Int

    var isEmpty: Bool {
        requiredEmptySlotsCanonicalized == 0 && trailingEmptySlotsDropped == 0
    }
}

enum LoadedModuleEditableCopyPlanUnavailableReason: Error, Equatable {
    case noLoadedModule
    case alreadyEditable
    case playbackActive
    case missingPlaybackSong
    case nonLinearFrequencyTable
    case unsupportedSampleOrKeymapBoundary
    case representedLoopStateUnsupported
    case representedInstrumentStateUnstable
    case instrumentIdentityUnstable
    case writerUnsupported
    case unsupportedLoadedModule

    fileprivate var userFacingMessage: String {
        let explanation: String
        switch self {
        case .nonLinearFrequencyTable:
            explanation = "This XM uses Amiga frequency mode. VTX can play it, but current editable documents use Linear frequency mode. Creating an editable copy would change pitch and frequency semantics, so conversion is not available yet."
        case .unsupportedSampleOrKeymapBoundary:
            explanation = "This XM contains sample-slot or note-mapping state that the current editable document model cannot preserve safely. VTX will not silently repair or change it."
        case .representedLoopStateUnsupported:
            explanation = "This XM contains represented sample loop state that VTX cannot currently preserve safely in an editable copy and later export."
        case .representedInstrumentStateUnstable:
            explanation = "This XM contains represented instrument envelope or state that would change if VTX wrote and reopened an editable copy."
        case .instrumentIdentityUnstable:
            explanation = "VTX cannot currently preserve this XM's represented instrument identity and palette exactly enough for a safe editable copy."
        case .writerUnsupported:
            explanation = "VTX can play this XM, but the current XM writer cannot safely represent some loaded state in an editable copy."
        case .missingPlaybackSong:
            explanation = "VTX loaded this XM, but the playback state needed to create an editable copy is not currently available."
        case .unsupportedLoadedModule, .noLoadedModule, .alreadyEditable, .playbackActive:
            explanation = "VTX can play this XM, but some loaded module state cannot currently be preserved safely in an editable copy."
        }
        return "\(explanation) The loaded XM remains unchanged."
    }
}

enum LoadedModuleEditableCopyPlan: Equatable {
    case exact(BlankTrackerDocument)
    case normalized(BlankTrackerDocument, LoadedModuleEditableCopyNormalizationSummary)
    case unavailable(LoadedModuleEditableCopyPlanUnavailableReason)
}

/// Authoritative pure/structural admission path for loaded-XM editable-copy planning.
/// It never writes a temporary file and never mutates the loaded source values.
enum LoadedModuleEditableCopyPlanner {
    private enum BoundaryValidation {
        case accepted(LoadedModuleEditableCopyNormalizationSummary)
        case unavailable(LoadedModuleEditableCopyPlanUnavailableReason)
    }

    static func plan(context: LoadedModuleEditableCopyContext) -> LoadedModuleEditableCopyPlan {
        switch context.kind {
        case .none:
            return .unavailable(.noLoadedModule)
        case .editable:
            return .unavailable(.alreadyEditable)
        case .loadedReadOnly:
            break
        }

        guard !context.isPlaybackActive else {
            return .unavailable(.playbackActive)
        }
        guard let metadata = context.loadedMetadata else {
            return .unavailable(.noLoadedModule)
        }
        guard let playbackSong = context.loadedPlaybackSong else {
            return .unavailable(.missingPlaybackSong)
        }
        guard metadata.type == "XM", !metadata.xmPatterns.isEmpty else {
            return .unavailable(.unsupportedLoadedModule)
        }
        guard metadata.usesLinearFrequencyTable, playbackSong.usesLinearFrequencyTable else {
            return .unavailable(.nonLinearFrequencyTable)
        }
        guard hasStableInstrumentIdentities(metadata: metadata, playbackSong: playbackSong) else {
            return .unavailable(.instrumentIdentityUnstable)
        }

        let normalizationSummary: LoadedModuleEditableCopyNormalizationSummary
        switch validateSampleAndKeymapBoundary(playbackSong) {
        case let .accepted(summary):
            normalizationSummary = summary
        case let .unavailable(reason):
            return .unavailable(reason)
        }

        guard playbackSong.instrumentsByIndex.values.allSatisfy({
            EditableXMWriterEnvelopeCanonicalization.reopensStably($0.volumeEnvelope) &&
                EditableXMWriterEnvelopeCanonicalization.reopensStably($0.panningEnvelope)
        }) else {
            return .unavailable(.representedInstrumentStateUnstable)
        }
        guard let document = BlankTrackerDocument.makeEditableCopy(
            from: metadata,
            playbackSong: playbackSong,
            selection: context.selection,
            sourcePatternIndex: context.currentPatternIndex
        ), preservesSupportedSongSemantics(metadata: metadata, source: playbackSong, document: document) else {
            return .unavailable(.unsupportedLoadedModule)
        }

        do {
            _ = try EditableXMWriter().data(from: document)
        } catch let error as EditableXMWriterError {
            if isRepresentedLoopFailure(error) {
                return .unavailable(.representedLoopStateUnsupported)
            }
            return .unavailable(.writerUnsupported)
        } catch {
            return .unavailable(.writerUnsupported)
        }

        return normalizationSummary.isEmpty
            ? .exact(document)
            : .normalized(document, normalizationSummary)
    }

    private static func hasStableInstrumentIdentities(
        metadata: ParsedModuleMetadata,
        playbackSong: PlaybackSong
    ) -> Bool {
        guard (0...BlankTrackerDocument.maximumInstrumentCount).contains(metadata.instruments) else {
            return false
        }
        let expectedIndices = Set(metadata.instruments > 0 ? Array(1...metadata.instruments) : [])
        guard Set(playbackSong.instrumentsByIndex.keys) == expectedIndices,
              playbackSong.instrumentsByIndex.allSatisfy({ $0.key == $0.value.index }) else {
            return false
        }
        let highestPatternInstrument = metadata.xmPatterns
            .flatMap(\.rows)
            .flatMap { $0 }
            .map { Int($0.instrument) }
            .max() ?? 0
        return highestPatternInstrument <= metadata.instruments
    }

    private static func validateSampleAndKeymapBoundary(_ playbackSong: PlaybackSong) -> BoundaryValidation {
        let validSampleIndices = 0..<BlankTrackerDocument.maximumSampleCountPerInstrument
        var requiredEmptySlotsCanonicalized = 0
        var trailingEmptySlotsDropped = 0
        var affectedInstruments = 0

        for instrument in playbackSong.instrumentsByIndex.values {
            let representedIndices = instrument.samples.map(\.sampleIndex).sorted()
            guard Set(representedIndices).count == representedIndices.count,
                  representedIndices.allSatisfy(validSampleIndices.contains),
                  instrument.samples.allSatisfy({ sample in
                      sample.instrumentIndex == instrument.index &&
                          sample.sampleLength > 0 &&
                          sample.sampleLength == sample.pcm.count &&
                          !sample.pcm.isEmpty &&
                          sample.pcm.allSatisfy { $0.isFinite && (-1...1).contains($0) } &&
                          sample.volume.isFinite && (0...1).contains(sample.volume) &&
                          sample.baseSampleRate.isFinite && sample.baseSampleRate > 0 &&
                          PlaybackSample.xmRelativeNoteRange.contains(sample.relativeNote) &&
                          PlaybackSample.xmFinetuneRange.contains(sample.finetune)
                  }) else {
                return .unavailable(.unsupportedSampleOrKeymapBoundary)
            }

            for sample in instrument.samples {
                guard sample.loopType == 0 || sample.loopType == 1 || sample.loopType == 2,
                      sample.loopStart >= 0,
                      sample.loopLength >= 0 else {
                    return .unavailable(.representedLoopStateUnsupported)
                }
                if sample.loopType != 0, !sample.loopRegion.isEnabled {
                    return .unavailable(.representedLoopStateUnsupported)
                }
            }

            let mappedIndices: [Int]
            if let noteSampleMap = instrument.noteSampleMap {
                guard noteSampleMap.count == 96,
                      noteSampleMap.allSatisfy(validSampleIndices.contains) else {
                    return .unavailable(.unsupportedSampleOrKeymapBoundary)
                }
                mappedIndices = noteSampleMap
            } else {
                guard instrument.samples.isEmpty else {
                    return .unavailable(.unsupportedSampleOrKeymapBoundary)
                }
                mappedIndices = []
            }

            let highestRequiredIndex = [representedIndices.max(), mappedIndices.max()]
                .compactMap { $0 }
                .max()
            let requiredSpanCount = highestRequiredIndex.map { $0 + 1 } ?? 0
            let representedSet = Set(representedIndices)
            let missingRequiredIndices = (0..<requiredSpanCount).filter { !representedSet.contains($0) }

            guard let provenance = playbackSong.xmSampleSlotProvenanceByInstrument[instrument.index] else {
                guard missingRequiredIndices.isEmpty else {
                    return .unavailable(.unsupportedSampleOrKeymapBoundary)
                }
                continue
            }
            guard (provenance.isEmpty || instrument.noteSampleMap != nil),
                  provenance.count <= BlankTrackerDocument.maximumSampleCountPerInstrument,
                  provenance.map(\.sampleIndex) == Array(0..<provenance.count),
                  representedIndices.allSatisfy({ sampleIndex in
                      provenance.indices.contains(sampleIndex) &&
                          provenance[sampleIndex].declaredPayloadLength > 0 &&
                          provenance[sampleIndex].decodedPayloadLength > 0
                  }),
                  missingRequiredIndices.allSatisfy(provenance.indices.contains) else {
                return .unavailable(.unsupportedSampleOrKeymapBoundary)
            }

            var instrumentRequiredCount = 0
            var instrumentTrailingCount = 0
            for sourceSlot in provenance where !representedSet.contains(sourceSlot.sampleIndex) {
                guard sourceSlot.declaredPayloadLength == 0,
                      sourceSlot.decodedPayloadLength == 0,
                      sourceSlot.isProfileV1NormalizableEmptySlotHeader else {
                    return .unavailable(.unsupportedSampleOrKeymapBoundary)
                }
                let isRequired = sourceSlot.sampleIndex < requiredSpanCount
                if sourceSlot.isCanonicalEmptySlotHeader {
                    if !isRequired {
                        instrumentTrailingCount += 1
                    }
                } else {
                    if isRequired {
                        instrumentRequiredCount += 1
                    } else {
                        instrumentTrailingCount += 1
                    }
                }
            }
            if instrumentRequiredCount > 0 || instrumentTrailingCount > 0 {
                affectedInstruments += 1
                requiredEmptySlotsCanonicalized += instrumentRequiredCount
                trailingEmptySlotsDropped += instrumentTrailingCount
            }
        }

        return .accepted(LoadedModuleEditableCopyNormalizationSummary(
            requiredEmptySlotsCanonicalized: requiredEmptySlotsCanonicalized,
            trailingEmptySlotsDropped: trailingEmptySlotsDropped,
            instrumentCountAffected: affectedInstruments
        ))
    }

    private static func preservesSupportedSongSemantics(
        metadata: ParsedModuleMetadata,
        source: PlaybackSong,
        document: BlankTrackerDocument
    ) -> Bool {
        let candidate = EditablePlaybackSongBuilder.build(from: document)
        let expectedRestartPosition = document.songLength > 0
            ? min(max(0, metadata.restartPosition), document.songLength - 1)
            : 0
        return candidate.orders == source.orders &&
            candidate.patternsByIndex == source.patternsByIndex &&
            candidate.instrumentsByIndex == source.instrumentsByIndex &&
            candidate.initialTiming == source.initialTiming &&
            candidate.usesLinearFrequencyTable == source.usesLinearFrequencyTable &&
            document.songLength == source.orders.count &&
            document.restartPosition == expectedRestartPosition &&
            document.orderTable == source.orders.map(\.patternIndex)
    }

    private static func isRepresentedLoopFailure(_ error: EditableXMWriterError) -> Bool {
        switch error {
        case .unsupportedSampleLoopType, .unsupportedSampleLoopRegion:
            return true
        default:
            return false
        }
    }
}

struct LoadedModuleEditableCopyCoordinator {
    typealias Planner = (LoadedModuleEditableCopyContext) -> LoadedModuleEditableCopyPlan

    private let planner: Planner

    init(planner: @escaping Planner = LoadedModuleEditableCopyPlanner.plan) {
        self.planner = planner
    }

    /// Answers whether the command may be invoked from the current presentation state.
    /// Compatibility remains exclusively owned by `LoadedModuleEditableCopyPlanner`.
    static func canInvoke(
        context: LoadedModuleEditableCopyContext,
        hasConflictingPresentation: Bool
    ) -> Bool {
        context.kind == .loadedReadOnly &&
            context.moduleIdentity != nil &&
            context.loadedMetadata?.type == "XM" &&
            !context.isPlaybackActive &&
            !hasConflictingPresentation
    }

    static func canMakeEditableCopy(context: LoadedModuleEditableCopyContext) -> Bool {
        switch LoadedModuleEditableCopyPlanner.plan(context: context) {
        case .exact, .normalized:
            return true
        case .unavailable:
            return false
        }
    }

    static func unavailableReason(
        for context: LoadedModuleEditableCopyContext
    ) -> LoadedModuleEditableCopyPlanUnavailableReason? {
        switch LoadedModuleEditableCopyPlanner.plan(context: context) {
        case .exact, .normalized:
            return nil
        case let .unavailable(reason):
            return reason
        }
    }

    func makeEditableCopy(context: LoadedModuleEditableCopyContext) -> LoadedModuleEditableCopyResult {
        result(for: planner(context))
    }

    /// Captures, plans, and revalidates one command invocation before dispatch.
    /// Returning `false` guarantees the result handler was not called.
    @discardableResult
    func perform(
        contextProvider: () -> LoadedModuleEditableCopyContext,
        presentationConflictProvider: () -> Bool,
        resultHandler: (LoadedModuleEditableCopyResult) -> Void
    ) -> Bool {
        let capturedContext = contextProvider()
        guard Self.canInvoke(
            context: capturedContext,
            hasConflictingPresentation: presentationConflictProvider()
        ) else {
            return false
        }
        let capturedPlan = planner(capturedContext)

        // Re-run the authoritative planner at the transition/presentation edge.
        // Full value and UUID equality prevents an identical-looking replacement
        // module, changed selection, or changed transport state from being used.
        let currentContext = contextProvider()
        guard currentContext == capturedContext,
              Self.canInvoke(
                  context: currentContext,
                  hasConflictingPresentation: presentationConflictProvider()
              ),
              planner(currentContext) == capturedPlan else {
            return false
        }

        resultHandler(result(for: capturedPlan))
        return true
    }

    private func result(for plan: LoadedModuleEditableCopyPlan) -> LoadedModuleEditableCopyResult {
        switch plan {
        case let .exact(document):
            return .copied(document)
        case let .normalized(document, summary):
            return .normalized(document, summary)
        case let .unavailable(reason):
            return .unavailable(reason)
        }
    }
}
