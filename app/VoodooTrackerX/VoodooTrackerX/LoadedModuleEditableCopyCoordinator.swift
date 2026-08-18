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

struct LoadedModuleEditableCopyCoordinator {
    static func canMakeEditableCopy(context: LoadedModuleEditableCopyContext) -> Bool {
        unavailableReason(for: context) == nil
    }

    static func unavailableReason(
        for context: LoadedModuleEditableCopyContext
    ) -> LoadedModuleEditableCopyUnavailableReason? {
        switch context.kind {
        case .none:
            return .noLoadedModule
        case .editable:
            return .alreadyEditable
        case .loadedReadOnly:
            break
        }

        guard !context.isPlaybackActive else {
            return .playbackActive
        }
        guard let metadata = context.loadedMetadata else {
            return .noLoadedModule
        }
        guard context.loadedPlaybackSong != nil else {
            return .missingPlaybackSong
        }
        guard metadata.type == "XM",
              metadata.usesLinearFrequencyTable,
              !metadata.xmPatterns.isEmpty else {
            return .unsupportedLoadedModule
        }
        guard makeSupportedEditableCopy(context: context) != nil else {
            return .unsupportedLoadedModule
        }
        return nil
    }

    func makeEditableCopy(context: LoadedModuleEditableCopyContext) -> LoadedModuleEditableCopyResult {
        if let reason = Self.unavailableReason(for: context) {
            return .unavailable(reason)
        }
        guard let document = Self.makeSupportedEditableCopy(context: context) else {
            return .unavailable(.unsupportedLoadedModule)
        }
        return .copied(document)
    }

    private static func makeSupportedEditableCopy(context: LoadedModuleEditableCopyContext) -> BlankTrackerDocument? {
        guard let metadata = context.loadedMetadata,
              let playbackSong = context.loadedPlaybackSong,
              matchesLoadedSampleCopyBoundary(playbackSong),
              let document = BlankTrackerDocument.makeEditableCopy(
                  from: metadata,
                  playbackSong: playbackSong,
                  selection: context.selection,
                  sourcePatternIndex: context.currentPatternIndex
              ) else {
            return nil
        }
        do {
            _ = try EditableXMWriter().data(from: document)
            return document
        } catch {
            return nil
        }
    }

    /// Missing identities are copy-safe only when the normal loader saw the complete source span and
    /// classified every corresponding zero-length header as VTX's exact 40-byte all-zero placeholder.
    private static func matchesLoadedSampleCopyBoundary(_ playbackSong: PlaybackSong) -> Bool {
        playbackSong.instrumentsByIndex.values.allSatisfy { instrument in
            let representedIndices = instrument.samples.map(\.sampleIndex).sorted()
            guard Set(representedIndices).count == representedIndices.count,
                  representedIndices.allSatisfy({
                      (0..<BlankTrackerDocument.maximumSampleCountPerInstrument).contains($0)
                  }) else {
                return false
            }

            let mappedIndices: [Int]
            if let noteSampleMap = instrument.noteSampleMap {
                guard noteSampleMap.count == 96,
                      noteSampleMap.allSatisfy({
                          (0..<BlankTrackerDocument.maximumSampleCountPerInstrument).contains($0)
                      }) else {
                    return false
                }
                mappedIndices = noteSampleMap
            } else {
                mappedIndices = []
            }

            let highestRequiredIndex = [representedIndices.max(), mappedIndices.max()]
                .compactMap { $0 }
                .max()
            let requiredSpanCount = highestRequiredIndex.map { $0 + 1 } ?? 0
            let representedSet = Set(representedIndices)
            let missingIndices = (0..<requiredSpanCount).filter { !representedSet.contains($0) }

            guard let provenance = playbackSong.xmSampleSlotProvenanceByInstrument[instrument.index] else {
                return missingIndices.isEmpty
            }
            guard provenance.count == requiredSpanCount,
                  provenance.map(\.sampleIndex) == Array(0..<requiredSpanCount) else { return false }
            let provenanceByIndex = Dictionary(uniqueKeysWithValues: provenance.map { ($0.sampleIndex, $0) })
            return missingIndices.allSatisfy { sampleIndex in
                guard let sourceSlot = provenanceByIndex[sampleIndex] else { return false }
                return sourceSlot.decodedPayloadLength == 0 && sourceSlot.isCanonicalEmptySlotHeader
            }
        }
    }
}
