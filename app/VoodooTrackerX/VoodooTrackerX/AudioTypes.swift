import Foundation

struct AudioChannelControls: Equatable {
    var volumeScale: Float = 1
    var pitchOffsetSemitones: Double = 0
    var panning: Float = 0
}

struct AudioVoiceRequest: Equatable {
    let sample: PlaybackSample
    let note: UInt8
    let channel: Int
    var volumeScale: Float = 1
    var pitchOffsetSemitones: Double = 0
    var panning: Float = 0
    var sampleStartOffset: Int = 0
}

struct PlaybackPitchCalculation: Equatable {
    let noteValue: UInt8
    let relativeNote: Int
    let finetune: Int
    let sourceSampleRate: Double
    let frequency: Double
    let playbackRate: Double
    let varispeedRate: Double
}

enum PlaybackPitchCalculator {
    static let c4NoteValue = 49

    static func notePitchRatio(note: UInt8, sample: PlaybackSample) -> Double {
        let semitoneOffset = Double(Int(note) + sample.relativeNote - c4NoteValue)
        let finetuneSemitones = Double(sample.finetune) / 128.0
        return pow(2.0, (semitoneOffset + finetuneSemitones) / 12.0)
    }

    static func varispeedRate(for pitchOffsetSemitones: Double) -> Double {
        pow(2.0, pitchOffsetSemitones / 12.0)
    }

    static func calculation(
        note: UInt8,
        sample: PlaybackSample,
        pitchOffsetSemitones: Double,
        outputSampleRate: Double
    ) -> PlaybackPitchCalculation {
        let varispeedRate = varispeedRate(for: pitchOffsetSemitones)
        let frequency = sample.baseSampleRate * notePitchRatio(note: note, sample: sample) * varispeedRate
        return PlaybackPitchCalculation(
            noteValue: note,
            relativeNote: sample.relativeNote,
            finetune: sample.finetune,
            sourceSampleRate: sample.baseSampleRate,
            frequency: frequency,
            playbackRate: max(0.001, frequency / max(1, outputSampleRate)),
            varispeedRate: varispeedRate
        )
    }
}
