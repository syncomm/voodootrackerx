import AudioToolbox
import Foundation

private let editorNoteAuditionAudioSinkRenderCallback: AURenderCallback = { userData, _, _, _, frameCount, ioData in
    guard let ioData else {
        return noErr
    }
    let host = Unmanaged<EditorNoteAuditionCoreAudioOutputHost>.fromOpaque(userData).takeUnretainedValue()
    return host.render(frameCount: frameCount, ioData: ioData)
}

/// Preview-only note-audition sink backed by its own CoreAudio DefaultOutput unit and C mixer instance.
///
/// This intentionally does not share `PlaybackEngine`, runtime transport state, runtime diagnostics,
/// offline render/export paths, or the runtime song playback mixer instance.
final class EditorNoteAuditionAudioSink: EditorNoteAuditionPreviewSink {
    static let defaultSampleRate = MixerRenderConfig.defaultSampleRate
    static let previewGain: Float = 0.25

    private let outputHost: EditorNoteAuditionCoreAudioOutputHost

    init(sampleRate: Double = EditorNoteAuditionAudioSink.defaultSampleRate) {
        outputHost = EditorNoteAuditionCoreAudioOutputHost(sampleRate: sampleRate)
    }

    func preview(_ event: EditorNoteAuditionPreviewEvent) {
        outputHost.preview(event)
    }

    func cancelPreview() {
        outputHost.cancelPreview()
    }

    static func renderPreviewBlock(
        for event: EditorNoteAuditionPreviewEvent,
        sampleRate: Double = defaultSampleRate,
        frames: Int
    ) -> MixerRenderBlock? {
        guard let plan = EditorNoteAuditionPreviewRenderPlan(event: event, sampleRate: sampleRate) else {
            return nil
        }
        let mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: sampleRate, channelCount: 2))
        mixer.addVoice(
            sample: plan.sample,
            gain: plan.gain,
            pan: 0,
            playbackStep: plan.playbackStep,
            loop: .none
        )
        return mixer.render(frames: frames)
    }
}

private struct EditorNoteAuditionPreviewRenderPlan {
    let sample: MixerSampleBuffer
    let gain: Float
    let playbackStep: Double

    init?(event: EditorNoteAuditionPreviewEvent, sampleRate: Double) {
        let descriptor = event.sampleDescriptor
        let frameCount = min(descriptor.sampleFrameCount, descriptor.previewPCM.count)
        guard frameCount > 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return nil
        }

        sample = MixerSampleBuffer(monoPCM: Array(descriptor.previewPCM.prefix(frameCount)))
        gain = descriptor.previewVolume * EditorNoteAuditionAudioSink.previewGain
        playbackStep = max(0.000_001, descriptor.previewBaseSampleRate / sampleRate)
    }
}

private final class EditorNoteAuditionCoreAudioOutputHost: @unchecked Sendable {
    private let sampleRate: Double
    private let channelCount = 2
    private let lock = NSLock()
    private let lifecycleQueue = DispatchQueue(label: "com.voodootrackerx.editor-note-audition-preview")
    private let mixer: CSoftwareMixer
    private var outputUnit: AudioUnit?
    private var isRunning = false
    private var previewGeneration: UInt64 = 0
    private var idleStopTimer: DispatchSourceTimer?
    private var scratch = [Float]()

    init(sampleRate: Double) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0
            ? sampleRate
            : EditorNoteAuditionAudioSink.defaultSampleRate
        mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: self.sampleRate, channelCount: channelCount))
        scratch = Array(repeating: 0, count: 4096 * channelCount)
    }

    deinit {
        lifecycleQueue.sync {
            idleStopTimer?.cancel()
            idleStopTimer = nil
            resetOutputUnit()
        }
    }

    func preview(_ event: EditorNoteAuditionPreviewEvent) {
        guard let plan = EditorNoteAuditionPreviewRenderPlan(event: event, sampleRate: sampleRate) else {
            return
        }

        let generation = nextPreviewGeneration()
        lock.lock()
        mixer.reset()
        mixer.addVoice(
            sample: plan.sample,
            gain: plan.gain,
            pan: 0,
            playbackStep: plan.playbackStep,
            loop: .none
        )
        lock.unlock()

        startAndScheduleIdleStop(for: generation)
    }

    func cancelPreview() {
        _ = nextPreviewGeneration()
        lock.lock()
        mixer.reset()
        lock.unlock()

        lifecycleQueue.async { [weak self] in
            guard let self else {
                return
            }
            idleStopTimer?.cancel()
            idleStopTimer = nil
            stopRunningOutputUnit()
        }
    }

    fileprivate func render(
        frameCount: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let frames = Int(frameCount)
        let sampleCount = max(0, frames * channelCount)
        guard sampleCount > 0 else {
            return noErr
        }
        let renderFrames = min(frames, scratch.count / channelCount)

        lock.lock()
        scratch.withUnsafeMutableBufferPointer { buffer in
            buffer.initialize(repeating: 0)
            _ = mixer.render(into: buffer, frames: renderFrames)
        }
        copyScratchToAudioBuffers(
            requestedFrameCount: frames,
            renderedFrameCount: renderFrames,
            ioData: ioData
        )
        lock.unlock()
        return noErr
    }

    private func nextPreviewGeneration() -> UInt64 {
        lifecycleQueue.sync {
            previewGeneration &+= 1
            return previewGeneration
        }
    }

    private func startAndScheduleIdleStop(for generation: UInt64) {
        lifecycleQueue.async { [weak self] in
            guard let self,
                  generation == previewGeneration else {
                return
            }
            _ = start()
            scheduleIdleStopTimer(for: generation)
        }
    }

    private func scheduleIdleStopTimer(for generation: UInt64) {
        idleStopTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: lifecycleQueue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.stopIfIdle(generation: generation)
        }
        idleStopTimer = timer
        timer.resume()
    }

    private func stopIfIdle(generation: UInt64) {
        guard generation == previewGeneration else {
            return
        }

        lock.lock()
        let isIdle = mixer.activeVoiceCount == 0
        lock.unlock()

        guard isIdle else {
            return
        }
        idleStopTimer?.cancel()
        idleStopTimer = nil
        stopRunningOutputUnit()
    }

    @discardableResult
    private func start() -> OSStatus {
        if isRunning {
            return noErr
        }
        let prepareStatus = prepare()
        guard prepareStatus == noErr,
              let outputUnit else {
            return prepareStatus
        }
        let startStatus = AudioOutputUnitStart(outputUnit)
        isRunning = startStatus == noErr
        return startStatus
    }

    @discardableResult
    private func prepare() -> OSStatus {
        if outputUnit != nil {
            return noErr
        }

        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_DefaultOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            return kAudio_ParamError
        }

        var unit: AudioUnit?
        let instanceStatus = AudioComponentInstanceNew(component, &unit)
        guard instanceStatus == noErr,
              let unit else {
            return instanceStatus
        }
        outputUnit = unit

        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size * channelCount),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size * channelCount),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )
        let streamStatus = withUnsafePointer(to: &streamDescription) { pointer in
            AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input,
                0,
                pointer,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            )
        }
        guard streamStatus == noErr else {
            resetOutputUnit()
            return streamStatus
        }

        var callback = AURenderCallbackStruct(
            inputProc: editorNoteAuditionAudioSinkRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let callbackStatus = withUnsafePointer(to: &callback) { pointer in
            AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_SetRenderCallback,
                kAudioUnitScope_Input,
                0,
                pointer,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            )
        }
        guard callbackStatus == noErr else {
            resetOutputUnit()
            return callbackStatus
        }

        let initializeStatus = AudioUnitInitialize(unit)
        guard initializeStatus == noErr else {
            resetOutputUnit()
            return initializeStatus
        }
        return noErr
    }

    private func stopRunningOutputUnit() {
        guard isRunning,
              let outputUnit else {
            return
        }
        AudioOutputUnitStop(outputUnit)
        isRunning = false
    }

    private func resetOutputUnit() {
        if let outputUnit {
            stopRunningOutputUnit()
            AudioUnitUninitialize(outputUnit)
            AudioComponentInstanceDispose(outputUnit)
        }
        outputUnit = nil
        isRunning = false
    }

    private func copyScratchToAudioBuffers(
        requestedFrameCount: Int,
        renderedFrameCount: Int,
        ioData: UnsafeMutablePointer<AudioBufferList>
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        for bufferIndex in buffers.indices {
            let channelCountInBuffer = max(1, Int(buffers[bufferIndex].mNumberChannels))
            let writableSampleCount = min(
                Int(buffers[bufferIndex].mDataByteSize) / MemoryLayout<Float>.size,
                requestedFrameCount * channelCountInBuffer
            )
            guard writableSampleCount > 0,
                  let data = buffers[bufferIndex].mData else {
                continue
            }
            let output = data.bindMemory(to: Float.self, capacity: writableSampleCount)
            output.initialize(repeating: 0, count: writableSampleCount)

            if channelCountInBuffer == channelCount {
                let copyCount = min(writableSampleCount, renderedFrameCount * channelCount)
                output.update(from: scratch, count: copyCount)
            } else {
                let sourceChannel = min(bufferIndex, channelCount - 1)
                for frame in 0..<renderedFrameCount where frame < writableSampleCount {
                    output[frame] = scratch[(frame * channelCount) + sourceChannel]
                }
            }
            buffers[bufferIndex].mDataByteSize = UInt32(writableSampleCount * MemoryLayout<Float>.size)
        }
    }
}
