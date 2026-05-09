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

struct PlaybackSampleLoopRegion: Equatable {
    let isEnabled: Bool
    let startFrame: Int
    let endFrame: Int
    let lengthFrames: Int
    let loopType: Int
    let loopTypeName: String

    static func clamped(sampleFrameCount: Int, loopStart: Int, loopLength: Int, loopType: Int) -> PlaybackSampleLoopRegion {
        let frameCount = max(0, sampleFrameCount)
        let startFrame = min(max(0, loopStart), frameCount)
        let requestedLength = max(0, loopLength)
        let remainingFrames = max(0, frameCount - startFrame)
        let endFrame = startFrame + min(requestedLength, remainingFrames)
        let lengthFrames = max(0, endFrame - startFrame)
        let loopTypeName: String
        switch loopType {
        case 1:
            loopTypeName = "forward"
        case 2:
            loopTypeName = "ping_pong_deferred"
        default:
            loopTypeName = "none"
        }
        return PlaybackSampleLoopRegion(
            isEnabled: loopType == 1 && lengthFrames > 0,
            startFrame: startFrame,
            endFrame: endFrame,
            lengthFrames: lengthFrames,
            loopType: loopType,
            loopTypeName: loopTypeName
        )
    }
}

struct AudioSamplePlaybackPlan: Equatable {
    let introRange: Range<Int>?
    let loopRange: Range<Int>?

    var isLooped: Bool {
        loopRange != nil
    }
}

enum AudioSamplePlaybackPlanner {
    static func plan(for sample: PlaybackSample, sampleStartOffset: Int) -> AudioSamplePlaybackPlan? {
        let frameCount = sample.pcm.count
        let startOffset = min(max(0, sampleStartOffset), frameCount)
        guard sample.isPlayable,
              startOffset < frameCount else {
            return nil
        }

        let loop = sample.loopRegion
        guard loop.isEnabled else {
            return AudioSamplePlaybackPlan(introRange: startOffset..<frameCount, loopRange: nil)
        }

        guard startOffset < loop.endFrame else {
            return AudioSamplePlaybackPlan(introRange: startOffset..<frameCount, loopRange: nil)
        }

        return AudioSamplePlaybackPlan(
            introRange: startOffset..<loop.endFrame,
            loopRange: loop.startFrame..<loop.endFrame
        )
    }
}

struct PlaybackPitchCalculation: Equatable {
    let noteValue: UInt8
    let relativeNote: Int
    let finetune: Int
    let sourceSampleRate: Double
    let audioBufferSampleRate: Double
    let targetFrequency: Double
    let frequency: Double
    let playbackRate: Double
    let varispeedRate: Double
    let rateBasis: String
}

enum PlaybackPitchCalculator {
    static let c4NoteValue = 49
    static let defaultAudioBufferSampleRate = 44_100.0
    static let audioBufferSampleRateBasis = "targetFrequency/audioBufferSampleRate"

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
        let audioBufferSampleRate = max(1, outputSampleRate)
        return PlaybackPitchCalculation(
            noteValue: note,
            relativeNote: sample.relativeNote,
            finetune: sample.finetune,
            sourceSampleRate: sample.baseSampleRate,
            audioBufferSampleRate: audioBufferSampleRate,
            targetFrequency: frequency,
            frequency: frequency,
            playbackRate: max(0.001, frequency / audioBufferSampleRate),
            varispeedRate: varispeedRate,
            rateBasis: audioBufferSampleRateBasis
        )
    }
}
