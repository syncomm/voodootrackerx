import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

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
    static let previewSafetyGainCap: Float = 0.5
    static let previewOutputHeadroomGain = RuntimeCMixerOutputPolicy.defaultPolicy.outputGain

    private let outputHost: EditorNoteAuditionCoreAudioOutputHost

    init(sampleRate: Double = EditorNoteAuditionAudioSink.defaultSampleRate) {
        outputHost = EditorNoteAuditionCoreAudioOutputHost(sampleRate: sampleRate)
    }

    var isPreviewAvailable: Bool { outputHost.isAvailable }

    func preview(_ event: EditorNoteAuditionPreviewEvent) -> Bool {
        outputHost.isAvailable && outputHost.preview(event)
    }

    func releasePreview() {
        outputHost.releasePreview()
    }

    func cancelPreview() {
        outputHost.cancelPreview()
    }

    func setPreviewInvalidationHandler(_ handler: @escaping @Sendable () -> Void) {
        outputHost.setPreviewInvalidationHandler(handler)
    }

    static func renderPreviewBlock(
        for event: EditorNoteAuditionPreviewEvent,
        sampleRate: Double = defaultSampleRate,
        frames: Int
    ) -> MixerRenderBlock? {
        let previewMixer = EditorNoteAuditionPreviewMixer(sampleRate: sampleRate)
        guard previewMixer.replacePreview(with: event) else {
            return nil
        }
        return previewMixer.render(frames: frames)
    }

    static func previewRenderParameters(
        for event: EditorNoteAuditionPreviewEvent,
        sampleRate: Double = defaultSampleRate
    ) -> EditorNoteAuditionPreviewRenderParameters? {
        EditorNoteAuditionPreviewRenderPlan(event: event, sampleRate: sampleRate).map {
            EditorNoteAuditionPreviewRenderParameters(
                gain: $0.gain,
                pan: $0.pan,
                playbackStep: $0.playbackStep,
                loop: $0.loop,
                instrumentIndex: $0.instrumentIndex,
                sampleIndex: $0.sampleIndex
            )
        }
    }
}

struct EditorNoteAuditionPreviewRenderParameters: Equatable {
    let gain: Float
    let pan: Float
    let playbackStep: Double
    let loop: MixerSampleLoop
    let instrumentIndex: Int
    let sampleIndex: Int
}

private struct EditorNoteAuditionPreviewRenderPlan {
    let sample: MixerSampleBuffer
    let gain: Float
    let pan: Float
    let playbackStep: Double
    let loop: MixerSampleLoop
    let instrumentIndex: Int
    let sampleIndex: Int

    init?(event: EditorNoteAuditionPreviewEvent, sampleRate: Double) {
        let descriptor = event.sampleDescriptor
        let frameCount = min(descriptor.sampleFrameCount, descriptor.previewPCM.count)
        guard frameCount > 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return nil
        }

        sample = MixerSampleBuffer(monoPCM: Array(descriptor.previewPCM.prefix(frameCount)))
        gain = EditorNoteAuditionPreviewGainPolicy.gain(sampleVolume: descriptor.previewVolume)
        pan = PlaybackSamplePanningPolicy.plannedPan(descriptor.previewPanning)
        loop = descriptor.previewLoop.sanitized(sampleFrameCount: frameCount)
        instrumentIndex = descriptor.instrumentIndex
        sampleIndex = descriptor.sampleIndex
        playbackStep = EditorNoteAuditionPreviewPitchPolicy.playbackStep(
            noteValue: event.noteValue,
            descriptor: descriptor,
            outputSampleRate: sampleRate
        ) ?? max(0.000_001, descriptor.previewBaseSampleRate / sampleRate)
    }
}

final class EditorNoteAuditionPreviewMixer {
    private let sampleRate: Double
    private let mixer: CSoftwareMixer
    private(set) var lastRenderParameters: EditorNoteAuditionPreviewRenderParameters?

    init(sampleRate: Double = EditorNoteAuditionAudioSink.defaultSampleRate) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0
            ? sampleRate
            : EditorNoteAuditionAudioSink.defaultSampleRate
        mixer = CSoftwareMixer(config: MixerRenderConfig(sampleRate: self.sampleRate, channelCount: 2))
    }

    var activeVoiceCount: Int {
        mixer.activeVoiceCount
    }

    var loadedVoiceCount: Int {
        mixer.loadedVoiceCount
    }

    var rampingOutVoiceCount: Int {
        mixer.rampingOutVoiceCount
    }

    @discardableResult
    func replacePreview(with event: EditorNoteAuditionPreviewEvent) -> Bool {
        guard let plan = EditorNoteAuditionPreviewRenderPlan(event: event, sampleRate: sampleRate) else {
            return false
        }
        mixer.clearVoices()
        mixer.addVoice(
            sample: plan.sample,
            gain: plan.gain,
            pan: plan.pan,
            playbackStep: plan.playbackStep,
            loop: plan.loop
        )
        lastRenderParameters = EditorNoteAuditionPreviewRenderParameters(
            gain: plan.gain,
            pan: plan.pan,
            playbackStep: plan.playbackStep,
            loop: plan.loop,
            instrumentIndex: plan.instrumentIndex,
            sampleIndex: plan.sampleIndex
        )
        return true
    }

    func cancelPreview() {
        mixer.clearVoices()
        lastRenderParameters = nil
    }

    func render(frames: Int) -> MixerRenderBlock {
        mixer.render(frames: frames)
    }

    @discardableResult
    func render(into interleavedPCM: UnsafeMutableBufferPointer<Float>, frames: Int) -> Int {
        mixer.render(into: interleavedPCM, frames: frames)
    }
}

enum EditorNoteAuditionPreviewGainPolicy {
    static let maximumGain = EditorNoteAuditionAudioSink.previewSafetyGainCap
    static let runtimeOutputHeadroomGain = EditorNoteAuditionAudioSink.previewOutputHeadroomGain

    static func gain(sampleVolume: Float) -> Float {
        let runtimeVoiceGain = PlaybackSongSyntheticAdapter.adaptedGain(
            sampleVolume: sampleVolume,
            channelVolume: 64,
            globalVolume: PlaybackSongSyntheticAdapter.GlobalVolumeState.defaultValue
        )
        let normalized = runtimeVoiceGain * runtimeOutputHeadroomGain
        guard normalized.isFinite else {
            return 0
        }
        return min(maximumGain, max(0, normalized))
    }
}

enum EditorNoteAuditionPreviewPitchPolicy {
    static func playbackStep(
        noteValue: UInt8,
        descriptor: EditorNoteAuditionSampleDescriptor,
        outputSampleRate: Double
    ) -> Double? {
        guard (1...TrackerNoteKeyMap.maximumNoteValue).contains(Int(noteValue)),
              outputSampleRate.isFinite,
              outputSampleRate > 0 else {
            return nil
        }
        let sample = PlaybackSample(
            instrumentIndex: descriptor.instrumentIndex,
            sampleIndex: descriptor.sampleIndex,
            pcm: descriptor.previewPCM.isEmpty ? [0] : descriptor.previewPCM,
            volume: descriptor.previewVolume,
            relativeNote: descriptor.previewRelativeNote,
            finetune: descriptor.previewFinetune,
            baseSampleRate: descriptor.previewBaseSampleRate,
            sampleLength: max(1, descriptor.sampleFrameCount)
        )
        let calculation = PlaybackPitchCalculator.calculation(
            note: noteValue,
            sample: sample,
            pitchOffsetSemitones: 0,
            outputSampleRate: outputSampleRate
        )
        return calculation.playbackRate.isFinite && calculation.playbackRate > 0
            ? calculation.playbackRate
            : nil
    }
}

struct EditorNoteAuditionPersistentOutputLifecycle {
    enum Command: Equatable { case none, start, stopReconfigureAndStart, stopAndDispose }
    private var isRunning = false
    private var isDisposed = false
    mutating func activate() -> Command {
        guard !isDisposed, !isRunning else { return .none }
        isRunning = true
        return .start
    }
    mutating func routeOrFormatChanged() -> Command {
        guard !isDisposed else { return .none }
        defer { isRunning = true }
        return isRunning ? .stopReconfigureAndStart : .start
    }
    mutating func startFailed() { isRunning = false }
    mutating func teardown() -> Command {
        guard !isDisposed else { return .none }
        let command: Command = isRunning ? .stopAndDispose : .none
        isDisposed = true
        return command
    }
}

/// One off-thread-built mixer voice. Its configuration is immutable after publication;
/// only the render consumer advances its private mixer cursor.
private final class EditorNoteAuditionPreparedVoiceSlot: @unchecked Sendable {
    let mixer: EditorNoteAuditionPreviewMixer
    init?(event: EditorNoteAuditionPreviewEvent, sampleRate: Double) {
        mixer = EditorNoteAuditionPreviewMixer(sampleRate: sampleRate)
        guard mixer.replacePreview(with: event) else { return nil }
    }
}

private struct EditorNoteAuditionRawCommand {
    static let empty = EditorNoteAuditionRawCommand(kind: 0, generation: 0, voiceAddress: 0)
    static let noteOnKind: UInt64 = 1, releaseKind: UInt64 = 2
    let kind: UInt64, generation: UInt64
    let voiceAddress: UInt
}

enum EditorNoteAuditionReleaseDelivery: Equatable { case queued, atomicFallback }

/// Fixed-capacity SPSC storage. Payload publication uses release/acquire ordering;
/// the audio callback only reads preallocated trivial values.
private final class EditorNoteAuditionCommandQueue: @unchecked Sendable {
    let capacity: Int
    private let storage: UnsafeMutablePointer<EditorNoteAuditionRawCommand>
    private let producerIndex = Atomic(UInt64(0))
    private let consumerIndex = Atomic(UInt64(0))

    init(capacity: Int) {
        self.capacity = max(2, capacity)
        storage = .allocate(capacity: self.capacity)
        storage.initialize(repeating: .empty, count: self.capacity)
    }
    deinit { storage.deinitialize(count: capacity); storage.deallocate() }
    func enqueue(_ command: EditorNoteAuditionRawCommand) -> Bool {
        let write = producerIndex.load(ordering: .relaxed)
        let read = consumerIndex.load(ordering: .acquiring)
        guard write &- read < UInt64(capacity) else { return false }
        storage[Int(write % UInt64(capacity))] = command
        producerIndex.store(write &+ 1, ordering: .releasing)
        return true
    }
    func peek() -> EditorNoteAuditionRawCommand? {
        let read = consumerIndex.load(ordering: .relaxed)
        guard read != producerIndex.load(ordering: .acquiring) else { return nil }
        return storage[Int(read % UInt64(capacity))]
    }
    @discardableResult
    func removeFirst() -> EditorNoteAuditionRawCommand? {
        guard let command = peek() else { return nil }
        let read = consumerIndex.load(ordering: .relaxed)
        consumerIndex.store(read &+ 1, ordering: .releasing)
        return command
    }
}

/// Publishes fully prepared voices off the audio thread and consumes ordered commands in the callback.
/// Fixed permits make retirement infallibly bounded; the callback never allocates, locks, waits, logs,
/// or reclaims objects. One serialized control producer owns command publication and reclamation.
final class EditorNoteAuditionPreviewCommandHandoff: @unchecked Sendable {
    private let sampleRate: Double
    private let commands: EditorNoteAuditionCommandQueue
    private let retiredVoices: EditorNoteAuditionCommandQueue
    private let voicePermitCapacity: UInt64
    private let latestPublishedGeneration = Atomic(UInt64(0))
    private let cancelledThroughGeneration = Atomic(UInt64(0))
    private let releasedThroughGeneration = Atomic(UInt64(0))
    private let rejectedNoteOnCountValue = Atomic(UInt64(0))
    private let lastRenderedGenerationValue = Atomic(UInt64(0))
    private let outstandingVoiceCountValue = Atomic(UInt64(0))
    private var producerGeneration: UInt64 = 0, renderVoiceAddress: UInt = 0, renderGeneration: UInt64 = 0
    private var producerActiveGeneration: UInt64?
    private var renderHasProducedOnset = false, releaseAfterRender = false

    var lastRenderedGeneration: UInt64? {
        let value = lastRenderedGenerationValue.load(ordering: .acquiring)
        return value == 0 ? nil : value
    }
    var rejectedNoteOnCount: UInt64 { rejectedNoteOnCountValue.load(ordering: .acquiring) }
    var outstandingVoiceCount: UInt64 { outstandingVoiceCountValue.load(ordering: .acquiring) }

    init(sampleRate: Double, queueCapacity: Int = 256) {
        self.sampleRate = sampleRate
        commands = EditorNoteAuditionCommandQueue(capacity: queueCapacity)
        retiredVoices = EditorNoteAuditionCommandQueue(capacity: queueCapacity + 1)
        voicePermitCapacity = UInt64(retiredVoices.capacity)
    }
    deinit { shutdownAfterOutputStopped() }

    @discardableResult
    func publish(_ event: EditorNoteAuditionPreviewEvent) -> UInt64? {
        reclaimRetiredVoices()
        guard reserveVoicePermit() else {
            rejectedNoteOnCountValue.wrappingAdd(1, ordering: .releasing)
            return nil
        }
        guard let voice = EditorNoteAuditionPreparedVoiceSlot(event: event, sampleRate: sampleRate) else {
            releaseVoicePermit()
            return nil
        }
        producerGeneration &+= 1
        let generation = producerGeneration
        latestPublishedGeneration.store(generation, ordering: .releasing)
        let address = UInt(bitPattern: Unmanaged.passRetained(voice).toOpaque())
        let command = EditorNoteAuditionRawCommand(
            kind: EditorNoteAuditionRawCommand.noteOnKind,
            generation: generation,
            voiceAddress: address
        )
        guard commands.enqueue(command) else {
            releaseRetainedVoice(address)
            releaseVoicePermit()
            rejectedNoteOnCountValue.wrappingAdd(1, ordering: .releasing)
            return nil
        }
        producerActiveGeneration = generation
        return generation
    }

    @discardableResult
    func release(generation: UInt64) -> EditorNoteAuditionReleaseDelivery {
        reclaimRetiredVoices()
        let command = EditorNoteAuditionRawCommand(
            kind: EditorNoteAuditionRawCommand.releaseKind,
            generation: generation,
            voiceAddress: 0
        )
        if commands.enqueue(command) { return .queued }
        publishRelease(through: generation)
        return .atomicFallback
    }

    func releaseActivePreview() {
        guard let generation = producerActiveGeneration else { return }
        _ = release(generation: generation)
        producerActiveGeneration = nil
    }

    func cancel() { reclaimRetiredVoices(); producerActiveGeneration = nil; cancelAllPublishedPreviews() }
    func cancelAllPublishedPreviews() {
        publishCancellation(through: latestPublishedGeneration.load(ordering: .acquiring))
    }

    @discardableResult
    func render(into output: UnsafeMutableBufferPointer<Float>, frames: Int) -> Int {
        let frameCount = min(max(0, frames), output.count / 2)
        for index in 0..<(frameCount * 2) { output[index] = 0 }
        guard frameCount > 0 else { return 0 }

        var processedCommandCount = 0
        while processedCommandCount <= commands.capacity {
            if releaseAfterRender && renderHasProducedOnset,
               !retireCurrentVoice() { return 0 }
            if renderVoiceAddress == 0 {
                guard let command = commands.removeFirst() else { break }
                processedCommandCount += 1
                guard command.kind == EditorNoteAuditionRawCommand.noteOnKind else { continue }
                renderVoiceAddress = command.voiceAddress
                renderGeneration = command.generation
                renderHasProducedOnset = false
                releaseAfterRender = false
            }

            if renderGeneration <= cancelledThroughGeneration.load(ordering: .acquiring) {
                guard retireCurrentVoice() else { return 0 }
                continue
            }
            if renderGeneration <= releasedThroughGeneration.load(ordering: .acquiring) {
                if renderHasProducedOnset {
                    guard retireCurrentVoice() else { return 0 }
                    continue
                }
                releaseAfterRender = true
                break
            }
            guard let next = commands.peek() else { break }
            if next.kind == EditorNoteAuditionRawCommand.noteOnKind {
                if renderHasProducedOnset {
                    guard retireCurrentVoice() else { return 0 }
                    continue
                }
                break
            }

            _ = commands.removeFirst()
            processedCommandCount += 1
            guard next.generation == renderGeneration else { continue }
            if renderHasProducedOnset {
                releaseAfterRender = true
                guard retireCurrentVoice() else { return 0 }
                continue
            }
            releaseAfterRender = true
            break
        }

        guard let pointer = UnsafeRawPointer(bitPattern: renderVoiceAddress) else { return 0 }
        let voice = Unmanaged<EditorNoteAuditionPreparedVoiceSlot>.fromOpaque(pointer).takeUnretainedValue()
        _ = voice.mixer.render(into: output, frames: frameCount)
        renderHasProducedOnset = true
        lastRenderedGenerationValue.store(renderGeneration, ordering: .releasing)
        if releaseAfterRender { _ = retireCurrentVoice() }
        return frameCount
    }

    func renderForTesting(frames: Int) -> [Float] {
        var output = Array(repeating: Float(0), count: max(0, frames) * 2)
        output.withUnsafeMutableBufferPointer { _ = render(into: $0, frames: frames) }
        return output
    }

    func reclaimRetiredVoices() {
        while let command = retiredVoices.removeFirst() {
            releaseRetainedVoice(command.voiceAddress)
            releaseVoicePermit()
        }
    }

    func discardCurrentVoiceAfterOutputStopped() {
        guard renderVoiceAddress != 0 else { return }
        releaseRetainedVoice(renderVoiceAddress)
        releaseVoicePermit()
        clearCurrentVoice()
    }

    /// The owning render adapter must stop its callback and detach its producer before shutdown.
    func shutdownAfterOutputStopped() {
        cancelAllPublishedPreviews()
        discardCurrentVoiceAfterOutputStopped()
        while let command = commands.removeFirst() {
            if command.kind == EditorNoteAuditionRawCommand.noteOnKind {
                releaseRetainedVoice(command.voiceAddress)
                releaseVoicePermit()
            }
        }
        reclaimRetiredVoices()
        lastRenderedGenerationValue.store(0, ordering: .releasing)
    }

    private func publishCancellation(through generation: UInt64) {
        var current = cancelledThroughGeneration.load(ordering: .acquiring)
        while generation > current {
            let result = cancelledThroughGeneration.compareExchange(
                expected: current, desired: generation, ordering: .acquiringAndReleasing
            )
            if result.exchanged { return }
            current = result.original
        }
    }

    private func publishRelease(through generation: UInt64) {
        var current = releasedThroughGeneration.load(ordering: .acquiring)
        while generation > current {
            let result = releasedThroughGeneration.compareExchange(
                expected: current, desired: generation, ordering: .acquiringAndReleasing
            )
            if result.exchanged { return }
            current = result.original
        }
    }

    private func reserveVoicePermit() -> Bool {
        var count = outstandingVoiceCountValue.load(ordering: .acquiring)
        while count < voicePermitCapacity {
            let result = outstandingVoiceCountValue.compareExchange(
                expected: count, desired: count + 1, ordering: .acquiringAndReleasing
            )
            if result.exchanged { return true }
            count = result.original
        }
        return false
    }

    private func releaseVoicePermit() { outstandingVoiceCountValue.wrappingSubtract(1, ordering: .releasing) }

    private func retireCurrentVoice() -> Bool {
        guard renderVoiceAddress != 0 else { return true }
        guard retireVoice(renderVoiceAddress) else { return false }
        clearCurrentVoice()
        return true
    }

    private func clearCurrentVoice() {
        renderVoiceAddress = 0
        renderGeneration = 0
        renderHasProducedOnset = false
        releaseAfterRender = false
    }

    private func retireVoice(_ address: UInt) -> Bool {
        guard address != 0 else { return true }
        return retiredVoices.enqueue(EditorNoteAuditionRawCommand(kind: 0, generation: 0, voiceAddress: address))
    }

    private func releaseRetainedVoice(_ address: UInt) {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<EditorNoteAuditionPreparedVoiceSlot>.fromOpaque(pointer).release()
    }
}

private final class EditorNoteAuditionCoreAudioOutputHost: @unchecked Sendable {
    private let sampleRate: Double
    private let channelCount = 2
    private let lifecycleQueue = DispatchQueue(label: "com.voodootrackerx.editor-note-audition-preview")
    private let lifecycleQueueKey = DispatchSpecificKey<UInt8>()
    private let handoff: EditorNoteAuditionPreviewCommandHandoff
    private var outputLifecycle = EditorNoteAuditionPersistentOutputLifecycle()
    private var outputUnit: AudioUnit?
    private var isRunning = false
    private var defaultOutputDeviceID: AudioObjectID?
    private var defaultOutputSampleRate: Double?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var outputFormatListener: AudioObjectPropertyListenerBlock?
    private var previewInvalidationHandler: (@Sendable () -> Void)?
    private let scratch: UnsafeMutablePointer<Float>

    init(sampleRate: Double) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0
            ? sampleRate
            : EditorNoteAuditionAudioSink.defaultSampleRate
        handoff = EditorNoteAuditionPreviewCommandHandoff(sampleRate: self.sampleRate)
        scratch = .allocate(capacity: 4096 * channelCount)
        scratch.initialize(repeating: 0, count: 4096 * channelCount)
        lifecycleQueue.setSpecific(key: lifecycleQueueKey, value: 1)
        lifecycleQueue.sync {
            activateOutput()
            installDefaultOutputListener()
        }
    }

    deinit {
        performOnLifecycleQueue {
            removeOutputFormatListener()
            removeDefaultOutputListener()
            handoff.cancelAllPublishedPreviews()
            if outputLifecycle.teardown() == .stopAndDispose { resetOutputUnit() }
            handoff.shutdownAfterOutputStopped()
        }
        scratch.deinitialize(count: 4096 * channelCount)
        scratch.deallocate()
    }

    private func performOnLifecycleQueue(_ operation: () -> Void) {
        if DispatchQueue.getSpecific(key: lifecycleQueueKey) != nil { operation() }
        else { lifecycleQueue.sync(execute: operation) }
    }

    var isAvailable: Bool {
        var available = false
        performOnLifecycleQueue { available = isRunning }
        return available
    }

    func setPreviewInvalidationHandler(_ handler: @escaping @Sendable () -> Void) {
        performOnLifecycleQueue { previewInvalidationHandler = handler }
    }

    func preview(_ event: EditorNoteAuditionPreviewEvent) -> Bool { handoff.publish(event) != nil }
    func releasePreview() { handoff.releaseActivePreview() }
    func cancelPreview() { handoff.cancel() }

    fileprivate func render(
        frameCount: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let frames = Int(frameCount)
        guard frames > 0 else { return noErr }
        let renderFrames = min(frames, 4096)
        let scratchBuffer = UnsafeMutableBufferPointer(start: scratch, count: renderFrames * channelCount)
        _ = handoff.render(into: scratchBuffer, frames: renderFrames)
        copyScratchToAudioBuffers(
            requestedFrameCount: frames,
            renderedFrameCount: renderFrames,
            ioData: ioData
        )
        return noErr
    }

    private func activateOutput() {
        guard outputLifecycle.activate() == .start else { return }
        if start() != noErr {
            resetOutputUnit()
            outputLifecycle.startFailed()
        }
    }

    private func defaultOutputDidChange() {
        let output = RuntimeCMixerAudioOutputDeviceDiagnostics.currentDefaultOutputDevice()
        guard output.deviceID != defaultOutputDeviceID else { return }
        removeOutputFormatListener()
        defaultOutputDeviceID = output.deviceID
        defaultOutputSampleRate = output.nominalSampleRate
        installOutputFormatListener()
        reconfigureOutputForRouteOrFormatChange()
    }

    private func outputFormatDidChange() {
        let output = RuntimeCMixerAudioOutputDeviceDiagnostics.currentDefaultOutputDevice()
        guard output.deviceID == defaultOutputDeviceID,
              output.nominalSampleRate != defaultOutputSampleRate else { return }
        defaultOutputSampleRate = output.nominalSampleRate
        reconfigureOutputForRouteOrFormatChange()
    }

    private func reconfigureOutputForRouteOrFormatChange() {
        handoff.cancelAllPublishedPreviews()
        switch outputLifecycle.routeOrFormatChanged() {
        case .stopReconfigureAndStart:
            resetOutputUnit()
            handoff.discardCurrentVoiceAfterOutputStopped()
        case .start: break
        case .none, .stopAndDispose: return
        }
        if start() != noErr {
            resetOutputUnit()
            outputLifecycle.startFailed()
        }
        previewInvalidationHandler?()
    }

    private func installDefaultOutputListener() {
        let output = RuntimeCMixerAudioOutputDeviceDiagnostics.currentDefaultOutputDevice()
        defaultOutputDeviceID = output.deviceID
        defaultOutputSampleRate = output.nominalSampleRate
        var address = Self.defaultOutputPropertyAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.defaultOutputDidChange() }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, lifecycleQueue, listener
        ) == noErr else { return }
        defaultOutputListener = listener
        installOutputFormatListener()
    }

    private func removeDefaultOutputListener() {
        guard let defaultOutputListener else { return }
        var address = Self.defaultOutputPropertyAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, lifecycleQueue, defaultOutputListener
        )
        self.defaultOutputListener = nil
    }

    private func installOutputFormatListener() {
        guard let defaultOutputDeviceID else { return }
        var address = Self.outputFormatPropertyAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.outputFormatDidChange() }
        guard AudioObjectAddPropertyListenerBlock(
            defaultOutputDeviceID, &address, lifecycleQueue, listener
        ) == noErr else { return }
        outputFormatListener = listener
    }

    private func removeOutputFormatListener() {
        guard let defaultOutputDeviceID, let outputFormatListener else { return }
        var address = Self.outputFormatPropertyAddress
        AudioObjectRemovePropertyListenerBlock(
            defaultOutputDeviceID, &address, lifecycleQueue, outputFormatListener
        )
        self.outputFormatListener = nil
    }

    private static let defaultOutputPropertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static let outputFormatPropertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    @discardableResult
    private func start() -> OSStatus {
        if isRunning { return noErr }
        let prepareStatus = prepare()
        guard prepareStatus == noErr, let outputUnit else { return prepareStatus }
        let startStatus = AudioOutputUnitStart(outputUnit)
        isRunning = startStatus == noErr
        return startStatus
    }

    @discardableResult
    private func prepare() -> OSStatus {
        if outputUnit != nil { return noErr }

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
        guard instanceStatus == noErr, let unit else { return instanceStatus }
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
        guard isRunning, let outputUnit else { return }
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
