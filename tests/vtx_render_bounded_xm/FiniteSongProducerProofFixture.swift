import Foundation
@testable import VoodooTrackerXPlaybackSupport

/// Public, in-memory cold-entry song with an E60 seam, E61 repeat, B/D order
/// transition, carried pitch/global memory, Fxx timing, and three real births.
enum FiniteSongProducerProofFixture {
    static let origin = PlaybackPosition(orderIndex: 0, patternIndex: 0, rowIndex: 2)

    static func make(linear: Bool) -> PlaybackSong {
        func cell(_ effect: UInt8 = 0, _ param: UInt8 = 0,
                  note: UInt8 = 0, instrument: UInt8 = 0) -> PlaybackCell {
            .init(note: note, instrument: instrument, volumeColumn: 0,
                effectType: effect, effectParam: param)
        }
        let first = PlaybackPattern(index: 0, rows: [
            .init(index: 0, cells: [cell(), cell(14, 0x60), cell()]),
            .init(index: 1, cells: [cell(1, 1), cell(), cell()]),
            .init(index: 2, cells: [cell(note: 49, instrument: 1), cell(14, 0x61), cell(17, 1)]),
            .init(index: 3, cells: [cell(11, 1), cell(13, 1), cell()]),
        ])
        let second = PlaybackPattern(index: 1, rows: [
            .init(index: 0, cells: [cell(), cell(), cell()]),
            .init(index: 1, cells: [cell(1, 0), cell(15, 3), cell(17, 0)]),
            .init(index: 2, cells: [cell(note: 53, instrument: 1), cell(), cell()]),
            .init(index: 3, cells: [cell(), cell(), cell(17, 0)]),
        ])
        let sample = PlaybackSample(instrumentIndex: 1, sampleIndex: 0,
            pcm: [0.25, -0.25, 0.125, -0.125], volume: 1, relativeNote: 0, finetune: 0,
            baseSampleRate: 8363, loopStart: 0, loopLength: 4, loopType: 1)
        let envelope = PlaybackVolumeEnvelope(enabled: true,
            points: [.init(tick: 0, value: 64)], sustainPointIndex: nil,
            loopStartPointIndex: nil, loopEndPointIndex: nil, typeFlags: 1, fadeout: 0)
        let instrument = PlaybackInstrument(index: 1, samples: [sample], volumeEnvelope: envelope,
            noteSampleMap: Array(repeating: 0, count: 96))
        return .init(title: "Public finite cold continuation proof", orders: [
            .init(orderIndex: 0, patternIndex: 0), .init(orderIndex: 1, patternIndex: 1),
        ], patternsByIndex: [0: first, 1: second], instrumentsByIndex: [1: instrument],
        restartOrderIndex: 0, endBehavior: .stopAtEnd,
        initialTiming: .init(speed: 3, bpm: 125), usesLinearFrequencyTable: linear)
    }
}
