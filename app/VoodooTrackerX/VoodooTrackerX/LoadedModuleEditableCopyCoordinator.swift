import Foundation

enum LoadedModuleEditableCopyDocumentKind: Equatable {
    case none
    case editable
    case loadedReadOnly
}

struct LoadedModuleEditableCopyContext: Equatable {
    let kind: LoadedModuleEditableCopyDocumentKind
    let loadedMetadata: ParsedModuleMetadata?
    let loadedPlaybackSong: PlaybackSong?
    let selection: TrackerEditorSelection
    let currentPatternIndex: Int
    let isPlaybackActive: Bool

    static func loadedReadOnly(
        metadata: ParsedModuleMetadata?,
        playbackSong: PlaybackSong?,
        selection: TrackerEditorSelection,
        currentPatternIndex: Int,
        isPlaybackActive: Bool
    ) -> LoadedModuleEditableCopyContext {
        LoadedModuleEditableCopyContext(
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
            kind: .none,
            loadedMetadata: nil,
            loadedPlaybackSong: nil,
            selection: .default,
            currentPatternIndex: 0,
            isPlaybackActive: isPlaybackActive
        )
    }
}

enum LoadedModuleEditableCopyUnavailableReason: Equatable {
    case noLoadedModule
    case alreadyEditable
    case playbackActive
    case missingPlaybackSong
    case unsupportedLoadedModule
}

enum LoadedModuleEditableCopyResult: Equatable {
    case unavailable(LoadedModuleEditableCopyUnavailableReason)
    case copied(BlankTrackerDocument)

    var userFacingTitle: String? {
        switch self {
        case .copied:
            return "Editable Copy Created"
        case .unavailable(.unsupportedLoadedModule):
            return "Make Editable Copy Unavailable"
        case .unavailable:
            return nil
        }
    }

    var userFacingMessage: String? {
        switch self {
        case .copied:
            return "Created an untitled in-memory editable copy of the supported XM subset. The original module remains read-only and untouched."
        case .unavailable(.unsupportedLoadedModule):
            return "This module cannot be converted into the current supported editable subset."
        case .unavailable:
            return nil
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
    /// PR 1 compatibility bridge: only exact plans remain visible to the existing action.
    static func canMakeEditableCopy(context: LoadedModuleEditableCopyContext) -> Bool {
        guard case .exact = LoadedModuleEditableCopyPlanner.plan(context: context) else {
            return false
        }
        return true
    }

    static func unavailableReason(
        for context: LoadedModuleEditableCopyContext
    ) -> LoadedModuleEditableCopyUnavailableReason? {
        switch LoadedModuleEditableCopyPlanner.plan(context: context) {
        case .exact:
            return nil
        case .normalized:
            return .unsupportedLoadedModule
        case let .unavailable(reason):
            return compatibilityUnavailableReason(reason)
        }
    }

    func makeEditableCopy(context: LoadedModuleEditableCopyContext) -> LoadedModuleEditableCopyResult {
        switch LoadedModuleEditableCopyPlanner.plan(context: context) {
        case let .exact(document):
            return .copied(document)
        case .normalized:
            return .unavailable(.unsupportedLoadedModule)
        case let .unavailable(reason):
            return .unavailable(Self.compatibilityUnavailableReason(reason))
        }
    }

    private static func compatibilityUnavailableReason(
        _ reason: LoadedModuleEditableCopyPlanUnavailableReason
    ) -> LoadedModuleEditableCopyUnavailableReason {
        switch reason {
        case .noLoadedModule:
            return .noLoadedModule
        case .alreadyEditable:
            return .alreadyEditable
        case .playbackActive:
            return .playbackActive
        case .missingPlaybackSong:
            return .missingPlaybackSong
        case .nonLinearFrequencyTable,
             .unsupportedSampleOrKeymapBoundary,
             .representedLoopStateUnsupported,
             .representedInstrumentStateUnstable,
             .instrumentIdentityUnstable,
             .writerUnsupported,
             .unsupportedLoadedModule:
            return .unsupportedLoadedModule
        }
    }
}
