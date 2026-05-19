import AVFoundation
import Foundation
import os

@MainActor
protocol PlaybackAudioOutput: AnyObject {
    var audioBufferSampleRate: Double { get }

    func trigger(_ request: AudioVoiceRequest)
    func update(channel: Int, controls: AudioChannelControls)
    func stop(channel: Int)
    func stopAll()
    func reset()
}

enum RuntimeAudioBackend: Equatable {
    case avAudio
    case cMixer

    var diagnosticName: String {
        switch self {
        case .avAudio:
            return "av_audio"
        case .cMixer:
            return "c_mixer"
        }
    }
}

struct RuntimeAudioBackendSelection: Equatable {
    static let environmentKey = "VTX_AUDIO_BACKEND"
    static let cMixerEnvironmentValue = "c_mixer"

    let backend: RuntimeAudioBackend
    let requestedValue: String?
    let fallbackReason: String?

    var experimentalCMixerEnabled: Bool {
        backend == .cMixer
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RuntimeAudioBackendSelection {
        let requestedValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestedValue,
              !requestedValue.isEmpty else {
            return RuntimeAudioBackendSelection(backend: .avAudio, requestedValue: nil, fallbackReason: nil)
        }
        guard requestedValue == cMixerEnvironmentValue else {
            return RuntimeAudioBackendSelection(
                backend: .avAudio,
                requestedValue: requestedValue,
                fallbackReason: "unknown_backend"
            )
        }
        return RuntimeAudioBackendSelection(backend: .cMixer, requestedValue: requestedValue, fallbackReason: nil)
    }
}

@MainActor
protocol PlaybackAudioBackendProviding: AnyObject {
    var runtimeAudioBackend: RuntimeAudioBackend { get }
}

struct RuntimeCMixerTraceEvent: Encodable, Equatable {
    let schemaVersion: Int
    let runtimeAction: String
    let runtimeAudioBackend: String
    let backendFlagValue: String?
    let fallbackReason: String?
    let experimentalCMixerEnabled: Bool
    let orderIndex: Int?
    let patternIndex: Int?
    let rowIndex: Int?
    let tickInRow: Int?
    let tickIndex: UInt64?
    let channelIndex: Int?
    let noteValue: UInt8?
    let instrumentIndex: Int?
    let effectType: String?
    let effectParam: String?
    let effect: String?
    let volumeColumn: String?
    let targetScope: String
    let targetedAllVoices: Bool
    let activeVoiceCount: Int?
    let loadedVoiceCount: Int?
    let activeVoiceCountBefore: Int?
    let activeVoiceCountAfter: Int?
    let loadedVoiceCountBefore: Int?
    let loadedVoiceCountAfter: Int?
    let stoppedVoiceCount: Int?
    let currentFrame: UInt64?
    let renderCallCount: UInt64?
    let renderedFrameCount: UInt64?
    let renderFrameCount: Int?
    let cMixerCallSucceeded: Bool?
    let reason: String?

    init(
        schemaVersion: Int = 1,
        runtimeAction: String,
        runtimeAudioBackend: String,
        backendFlagValue: String? = nil,
        fallbackReason: String? = nil,
        experimentalCMixerEnabled: Bool,
        context: AudioRuntimeTraceContext? = nil,
        targetScope: String = "none",
        targetedAllVoices: Bool = false,
        activeVoiceCount: Int? = nil,
        loadedVoiceCount: Int? = nil,
        activeVoiceCountBefore: Int? = nil,
        activeVoiceCountAfter: Int? = nil,
        loadedVoiceCountBefore: Int? = nil,
        loadedVoiceCountAfter: Int? = nil,
        stoppedVoiceCount: Int? = nil,
        currentFrame: UInt64? = nil,
        renderCallCount: UInt64? = nil,
        renderedFrameCount: UInt64? = nil,
        renderFrameCount: Int? = nil,
        cMixerCallSucceeded: Bool? = nil,
        reason: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runtimeAction = runtimeAction
        self.runtimeAudioBackend = runtimeAudioBackend
        self.backendFlagValue = backendFlagValue
        self.fallbackReason = fallbackReason
        self.experimentalCMixerEnabled = experimentalCMixerEnabled
        orderIndex = context?.orderIndex
        patternIndex = context?.patternIndex
        rowIndex = context?.rowIndex
        tickInRow = context?.tickInRow
        tickIndex = context?.tickIndex
        channelIndex = context?.channelIndex
        noteValue = context?.noteValue
        instrumentIndex = context?.instrumentIndex
        effectType = Self.hexByte(context?.effectType)
        effectParam = Self.hexByte(context?.effectParam)
        effect = Self.effectString(effectType: context?.effectType, effectParam: context?.effectParam)
        volumeColumn = Self.hexByte(context?.volumeColumn)
        self.targetScope = targetScope
        self.targetedAllVoices = targetedAllVoices
        self.activeVoiceCount = activeVoiceCount
        self.loadedVoiceCount = loadedVoiceCount
        self.activeVoiceCountBefore = activeVoiceCountBefore
        self.activeVoiceCountAfter = activeVoiceCountAfter
        self.loadedVoiceCountBefore = loadedVoiceCountBefore
        self.loadedVoiceCountAfter = loadedVoiceCountAfter
        self.stoppedVoiceCount = stoppedVoiceCount
        self.currentFrame = currentFrame
        self.renderCallCount = renderCallCount
        self.renderedFrameCount = renderedFrameCount
        self.renderFrameCount = renderFrameCount
        self.cMixerCallSucceeded = cMixerCallSucceeded
        self.reason = reason
    }

    private static func hexByte(_ value: UInt8?) -> String? {
        value.map { String(format: "%02X", $0) }
    }

    private static func effectString(effectType: UInt8?, effectParam: UInt8?) -> String? {
        guard let effectType,
              let effectParam else {
            return nil
        }
        return String(format: "%02X%02X", effectType, effectParam)
    }
}

@MainActor
protocol RuntimeCMixerTraceWriting: AnyObject {
    var isEnabled: Bool { get }

    func record(_ event: RuntimeCMixerTraceEvent)
    func flush()
}

@MainActor
final class NoopRuntimeCMixerTraceWriter: RuntimeCMixerTraceWriting {
    static let shared = NoopRuntimeCMixerTraceWriter()

    let isEnabled = false

    private init() {}

    func record(_ event: RuntimeCMixerTraceEvent) {}

    func flush() {}
}

enum RuntimeCMixerTraceJSONLFormatter {
    static func line(for event: RuntimeCMixerTraceEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(event)
        data.append(0x0A)
        return data
    }
}

@MainActor
final class RuntimeCMixerTraceJSONLWriter: RuntimeCMixerTraceWriting {
    let isEnabled = true

    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "RuntimeCMixerTrace")
    private let fileHandle: FileHandle

    init(url: URL) throws {
        let parentURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: url)
        try fileHandle.truncate(atOffset: 0)
    }

    deinit {
        try? fileHandle.close()
    }

    func record(_ event: RuntimeCMixerTraceEvent) {
        do {
            try fileHandle.write(contentsOf: RuntimeCMixerTraceJSONLFormatter.line(for: event))
        } catch {
            logger.error("Unable to write runtime C mixer trace event: \(error.localizedDescription, privacy: .public)")
        }
    }

    func flush() {
        try? fileHandle.synchronize()
    }
}

enum RuntimeCMixerTraceConfiguration {
    static let pathEnvironmentKey = "VTX_C_MIXER_RUNTIME_TRACE_PATH"

    static func traceURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let rawPath = environment[pathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath)
    }

    @MainActor
    static func makeWriter(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RuntimeCMixerTraceWriting {
        #if DEBUG
        guard let url = traceURL(environment: environment) else {
            return NoopRuntimeCMixerTraceWriter.shared
        }
        do {
            return try RuntimeCMixerTraceJSONLWriter(url: url)
        } catch {
            Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "RuntimeCMixerTrace")
                .error("Unable to open runtime C mixer trace at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return NoopRuntimeCMixerTraceWriter.shared
        }
        #else
        return NoopRuntimeCMixerTraceWriter.shared
        #endif
    }
}

@MainActor
enum PlaybackAudioOutputFactory {
    private static let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "AudioBackend")

    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runtimeCMixerTraceWriter: RuntimeCMixerTraceWriting = RuntimeCMixerTraceConfiguration.makeWriter()
    ) -> PlaybackAudioOutput {
        let selection = RuntimeAudioBackendSelection.resolve(environment: environment)
        if let requestedValue = selection.requestedValue,
           let fallbackReason = selection.fallbackReason {
            logger.warning(
                "Unknown VTX_AUDIO_BACKEND value '\(requestedValue, privacy: .public)'; falling back to av_audio reason=\(fallbackReason, privacy: .public)"
            )
        }
        logger.info(
            "Selected audio backend=\(selection.backend.diagnosticName, privacy: .public) experimental_c_mixer_enabled=\(selection.experimentalCMixerEnabled, privacy: .public) sample_rate=\(MixerRenderConfig.defaultSampleRate, privacy: .public) channel_count=\(MixerRenderConfig.defaultChannelCount, privacy: .public)"
        )
        if runtimeCMixerTraceWriter.isEnabled {
            runtimeCMixerTraceWriter.record(RuntimeCMixerTraceEvent(
                runtimeAction: "backend_selected",
                runtimeAudioBackend: selection.backend.diagnosticName,
                backendFlagValue: selection.requestedValue,
                fallbackReason: selection.fallbackReason,
                experimentalCMixerEnabled: selection.experimentalCMixerEnabled,
                targetScope: "none",
                targetedAllVoices: false,
                cMixerCallSucceeded: nil,
                reason: selection.fallbackReason
            ))
        }
        switch selection.backend {
        case .avAudio:
            return PlaybackAudioEngine()
        case .cMixer:
            return RuntimeCMixerAudioEngine(traceWriter: runtimeCMixerTraceWriter)
        }
    }
}

struct RuntimeCMixerRenderSnapshot: Equatable {
    let activeVoiceCount: Int
    let loadedVoiceCount: Int
    let renderCallCount: UInt64
    let renderedFrameCount: UInt64
    let currentFrame: UInt64
}

struct RuntimeCMixerTriggerResult: Equatable {
    let succeeded: Bool
    let reason: String?
    let snapshotBefore: RuntimeCMixerRenderSnapshot
    let snapshotAfter: RuntimeCMixerRenderSnapshot
    let channelStopBeforeAdd: RuntimeCMixerChannelStopResult?
}

struct RuntimeCMixerChannelStopResult: Equatable {
    let channel: Int
    let stoppedVoiceCount: Int
    let snapshotBefore: RuntimeCMixerRenderSnapshot
    let snapshotAfter: RuntimeCMixerRenderSnapshot
    let reason: String
}

struct RuntimeCMixerStopResult: Equatable {
    let snapshotBefore: RuntimeCMixerRenderSnapshot
    let snapshotAfter: RuntimeCMixerRenderSnapshot
    let targetedAllVoices: Bool
    let stoppedVoiceCount: Int
    let reason: String
}

final class RuntimeCMixerRenderCore: @unchecked Sendable {
    private let lock = NSLock()
    private let mixer: CSoftwareMixer
    private let maximumRenderFrames: Int
    private var scratchInterleavedPCM: [Float]
    private var renderCallCount: UInt64 = 0
    private var renderedFrameCount: UInt64 = 0

    let config: MixerRenderConfig

    init(config: MixerRenderConfig = MixerRenderConfig(), maximumRenderFrames: Int = 16_384) {
        self.config = config
        self.maximumRenderFrames = max(1, maximumRenderFrames)
        mixer = CSoftwareMixer(config: config)
        scratchInterleavedPCM = Array(repeating: 0, count: self.maximumRenderFrames * mixer.config.channelCount)
    }

    @discardableResult
    func trigger(_ request: AudioVoiceRequest) -> Bool {
        triggerWithDiagnostics(request).succeeded
    }

    @discardableResult
    func triggerWithDiagnostics(_ request: AudioVoiceRequest) -> RuntimeCMixerTriggerResult {
        let invalidReason: String?
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96,
              request.channel >= 0,
              request.channel <= Int(UInt32.max),
              request.sampleStartOffset < request.sample.pcm.count else {
            if !request.sample.isPlayable {
                invalidReason = "sample_not_playable"
            } else if request.note == 0 || request.note > 96 {
                invalidReason = "invalid_note"
            } else if request.channel < 0 || request.channel > Int(UInt32.max) {
                invalidReason = "invalid_channel"
            } else {
                invalidReason = "sample_start_offset_out_of_range"
            }
            let snapshot = snapshot()
            return RuntimeCMixerTriggerResult(
                succeeded: false,
                reason: invalidReason,
                snapshotBefore: snapshot,
                snapshotAfter: snapshot,
                channelStopBeforeAdd: nil
            )
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        let snapshotBefore = snapshotLocked()
        let channelStopBeforeAdd = stopChannelLocked(
            request.channel,
            reason: "note_replacement_stop_channel"
        )

        let voiceIndex = mixer.addVoice(
            sample: MixerSampleBuffer(monoPCM: request.sample.pcm),
            gain: PlaybackVolumeCalculator.clamped(request.sample.volume * request.volumeScale),
            pan: request.panning,
            playbackStep: PlaybackPitchCalculator.calculation(
                note: request.note,
                sample: request.sample,
                pitchOffsetSemitones: request.pitchOffsetSemitones,
                outputSampleRate: mixer.config.sampleRate
            ).playbackRate,
            loop: mixerLoop(for: request.sample),
            initialSourceFrame: request.sampleStartOffset
        )
        mixer.setChannelTag(request.channel, forVoiceAt: voiceIndex)
        return RuntimeCMixerTriggerResult(
            succeeded: true,
            reason: nil,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            channelStopBeforeAdd: channelStopBeforeAdd.stoppedVoiceCount > 0 ? channelStopBeforeAdd : nil
        )
    }

    func update(channel _: Int, controls _: AudioChannelControls) {
        // The first runtime C mixer smoke path applies controls at note trigger time.
        // Continuous tick-level gain/pan/pitch automation needs a frame-position bridge and is intentionally
        // deferred so this backend remains an opt-in skeleton.
    }

    func stop(channel: Int) {
        _ = stopChannelWithDiagnostics(channel, reason: "channel_stop")
    }

    func stopAll() {
        _ = stopAllWithDiagnostics(reason: "transport_stop_all")
    }

    @discardableResult
    func stopChannelWithDiagnostics(_ channel: Int, reason: String) -> RuntimeCMixerChannelStopResult {
        lock.lock()
        defer {
            lock.unlock()
        }
        return stopChannelLocked(channel, reason: reason)
    }

    @discardableResult
    func stopAllWithDiagnostics(reason: String) -> RuntimeCMixerStopResult {
        lock.lock()
        defer {
            lock.unlock()
        }
        let snapshotBefore = snapshotLocked()
        resetLocked()
        return RuntimeCMixerStopResult(
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            targetedAllVoices: true,
            stoppedVoiceCount: snapshotBefore.loadedVoiceCount,
            reason: reason
        )
    }

    @discardableResult
    func render(into outputInterleavedPCM: UnsafeMutableBufferPointer<Float>, frameCount: Int) -> Bool {
        let safeFrameCount = max(0, frameCount)
        guard safeFrameCount > 0 else {
            return true
        }
        guard safeFrameCount <= maximumRenderFrames,
              outputInterleavedPCM.count >= safeFrameCount * mixer.config.channelCount else {
            clear(outputInterleavedPCM)
            return false
        }
        guard lock.try() else {
            clear(outputInterleavedPCM)
            return false
        }
        defer {
            lock.unlock()
        }
        _ = mixer.render(into: outputInterleavedPCM, frames: safeFrameCount)
        renderCallCount &+= 1
        renderedFrameCount &+= UInt64(safeFrameCount)
        return true
    }

    func render(frameCount: AVAudioFrameCount, ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let safeFrameCount = Int(frameCount)

        // Audio callback safety rules: no AppKit, no parsing, no file I/O, no diagnostics logging, and no
        // allocation-heavy work. Voice/sample preparation happens on the main side before this callback; this
        // callback only renders the preloaded C mixer into preallocated scratch storage and copies it out.
        clear(ioData: ioData, frameCount: safeFrameCount)
        guard safeFrameCount > 0,
              safeFrameCount <= maximumRenderFrames else {
            return noErr
        }

        let sampleCount = safeFrameCount * mixer.config.channelCount
        let rendered = scratchInterleavedPCM.withUnsafeMutableBufferPointer { scratch in
            render(
                into: UnsafeMutableBufferPointer(start: scratch.baseAddress, count: sampleCount),
                frameCount: safeFrameCount
            )
        }
        if rendered {
            copyScratchToAudioBuffers(ioData: ioData, frameCount: safeFrameCount)
        }
        return noErr
    }

    private func resetLocked() {
        mixer.clearVoices()
        mixer.reset()
    }

    private func stopChannelLocked(_ channel: Int, reason: String) -> RuntimeCMixerChannelStopResult {
        let snapshotBefore = snapshotLocked()
        let stoppedVoiceCount: Int
        if channel >= 0 && channel <= Int(UInt32.max) {
            stoppedVoiceCount = mixer.stopVoices(channel: channel)
        } else {
            stoppedVoiceCount = 0
        }
        return RuntimeCMixerChannelStopResult(
            channel: channel,
            stoppedVoiceCount: stoppedVoiceCount,
            snapshotBefore: snapshotBefore,
            snapshotAfter: snapshotLocked(),
            reason: reason
        )
    }

    func snapshot() -> RuntimeCMixerRenderSnapshot {
        lock.lock()
        defer {
            lock.unlock()
        }
        return snapshotLocked()
    }

    private func snapshotLocked() -> RuntimeCMixerRenderSnapshot {
        RuntimeCMixerRenderSnapshot(
            activeVoiceCount: mixer.activeVoiceCount,
            loadedVoiceCount: mixer.loadedVoiceCount,
            renderCallCount: renderCallCount,
            renderedFrameCount: renderedFrameCount,
            currentFrame: mixer.currentFrame
        )
    }

    private func mixerLoop(for sample: PlaybackSample) -> MixerSampleLoop {
        let loop = sample.loopRegion
        guard loop.isEnabled else {
            return .none
        }
        return MixerSampleLoop(
            mode: loop.isPingPongLoop ? .pingPong : .forward,
            startFrame: loop.startFrame,
            endFrame: loop.endFrame
        )
    }

    private func clear(_ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>) {
        for index in outputInterleavedPCM.indices {
            outputInterleavedPCM[index] = 0
        }
    }

    private func clear(ioData: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        for buffer in buffers {
            guard let data = buffer.mData else {
                continue
            }
            let availableSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let requestedSampleCount = max(0, frameCount) * max(1, Int(buffer.mNumberChannels))
            let sampleCount = min(availableSampleCount, requestedSampleCount)
            let output = data.assumingMemoryBound(to: Float.self)
            for sampleIndex in 0..<sampleCount {
                output[sampleIndex] = 0
            }
        }
    }

    private func copyScratchToAudioBuffers(ioData: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        let channelCount = mixer.config.channelCount
        if buffers.count == 1,
           let data = buffers[0].mData,
           Int(buffers[0].mNumberChannels) == channelCount {
            let sampleCount = min(
                Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size,
                frameCount * channelCount
            )
            let output = data.assumingMemoryBound(to: Float.self)
            for sampleIndex in 0..<sampleCount {
                output[sampleIndex] = scratchInterleavedPCM[sampleIndex]
            }
            return
        }

        for (bufferIndex, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else {
                continue
            }
            let bufferChannelCount = max(1, Int(buffer.mNumberChannels))
            let availableSampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let output = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                for bufferChannel in 0..<bufferChannelCount {
                    let outputIndex = frame * bufferChannelCount + bufferChannel
                    guard outputIndex < availableSampleCount else {
                        return
                    }
                    let sourceChannel = buffers.count == channelCount ? bufferIndex : bufferChannel
                    output[outputIndex] = sourceChannel < channelCount
                        ? scratchInterleavedPCM[(frame * channelCount) + sourceChannel]
                        : 0
                }
            }
        }
    }
}

private func makeRuntimeCMixerSourceNode(
    format: AVAudioFormat,
    renderCore: RuntimeCMixerRenderCore
) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) { _, _, frameCount, ioData in
        renderCore.render(frameCount: frameCount, ioData: ioData)
    }
}

@MainActor
protocol RuntimeAudioDiagnosticOutput: AnyObject {
    func trigger(_ request: AudioVoiceRequest, context: AudioRuntimeTraceContext?)
    func update(channel: Int, controls: AudioChannelControls, context: AudioRuntimeTraceContext?)
    func stop(channel: Int, context: AudioRuntimeTraceContext?)
    func stopAll(context: AudioRuntimeTraceContext?, reason: String)
}

@MainActor
final class RuntimeCMixerAudioEngine: PlaybackAudioOutput, PlaybackAudioBackendProviding, RuntimeAudioDiagnosticOutput {
    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Audio")
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sourceNode: AVAudioSourceNode
    private let renderCore: RuntimeCMixerRenderCore
    private let fallbackAudioEngine = PlaybackAudioEngine()
    private let traceWriter: RuntimeCMixerTraceWriting
    private var isPrepared = false
    private var isFallbackActive = false

    init(
        sampleRate: Double = MixerRenderConfig.defaultSampleRate,
        channelCount: Int = MixerRenderConfig.defaultChannelCount,
        traceWriter: RuntimeCMixerTraceWriting = NoopRuntimeCMixerTraceWriter.shared
    ) {
        let config = MixerRenderConfig(sampleRate: sampleRate, channelCount: channelCount)
        renderCore = RuntimeCMixerRenderCore(config: config)
        self.traceWriter = traceWriter
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: renderCore.config.sampleRate,
            channels: AVAudioChannelCount(renderCore.config.channelCount),
            interleaved: false
        )!
        sourceNode = makeRuntimeCMixerSourceNode(format: format, renderCore: renderCore)
        logger.info(
            "Initialized experimental C mixer runtime backend sample_rate=\(self.renderCore.config.sampleRate, privacy: .public) channel_count=\(self.renderCore.config.channelCount, privacy: .public)"
        )
    }

    var runtimeAudioBackend: RuntimeAudioBackend {
        .cMixer
    }

    var audioBufferSampleRate: Double {
        format.sampleRate
    }

    func trigger(_ request: AudioVoiceRequest) {
        trigger(request, context: nil)
    }

    func trigger(_ request: AudioVoiceRequest, context: AudioRuntimeTraceContext?) {
        if isFallbackActive {
            recordRuntimeEvent(
                action: "unsupported_runtime_action",
                context: context,
                targetScope: "channel",
                snapshot: renderCore.snapshot(),
                succeeded: nil,
                reason: "runtime_c_mixer_fallback_av_audio_active"
            )
            fallbackAudioEngine.trigger(request)
            return
        }
        prepareIfNeeded()
        let result = renderCore.triggerWithDiagnostics(request)
        if let channelStop = result.channelStopBeforeAdd {
            recordRuntimeEvent(
                action: "c_mixer_stop_channel",
                context: contextWithFallbackChannel(context, channel: channelStop.channel),
                targetScope: "channel",
                snapshotBefore: channelStop.snapshotBefore,
                snapshot: channelStop.snapshotAfter,
                succeeded: true,
                stoppedVoiceCount: channelStop.stoppedVoiceCount,
                reason: channelStop.reason
            )
        }
        recordRuntimeEvent(
            action: "c_mixer_add_voice",
            context: context,
            targetScope: "channel",
            snapshotBefore: result.snapshotBefore,
            snapshot: result.snapshotAfter,
            succeeded: result.succeeded,
            reason: result.reason
        )
        guard result.succeeded else {
            logger.debug("Experimental C mixer runtime ignored an unplayable trigger")
            return
        }
        if !startEngineIfNeeded() {
            isFallbackActive = true
            fallbackAudioEngine.trigger(request)
        }
    }

    func update(channel: Int, controls: AudioChannelControls) {
        update(channel: channel, controls: controls, context: nil)
    }

    func update(channel: Int, controls: AudioChannelControls, context: AudioRuntimeTraceContext?) {
        if isFallbackActive {
            fallbackAudioEngine.update(channel: channel, controls: controls)
        } else {
            renderCore.update(channel: channel, controls: controls)
            recordRuntimeEvent(
                action: "unsupported_runtime_action",
                context: context,
                targetScope: "channel",
                snapshot: renderCore.snapshot(),
                succeeded: nil,
                reason: "runtime_c_mixer_update_gain_pan_and_step_deferred"
            )
        }
    }

    func stop(channel: Int) {
        stop(channel: channel, context: nil)
    }

    func stop(channel: Int, context: AudioRuntimeTraceContext?) {
        let result = renderCore.stopChannelWithDiagnostics(channel, reason: "channel_stop")
        recordRuntimeEvent(
            action: "c_mixer_stop_channel",
            context: contextWithFallbackChannel(context, channel: channel),
            targetScope: "channel",
            snapshotBefore: result.snapshotBefore,
            snapshot: result.snapshotAfter,
            succeeded: true,
            stoppedVoiceCount: result.stoppedVoiceCount,
            reason: result.reason
        )
        if isFallbackActive {
            fallbackAudioEngine.stop(channel: channel)
        }
    }

    func stopAll() {
        stopAll(context: nil, reason: "transport_stop_all")
    }

    func stopAll(context: AudioRuntimeTraceContext?, reason: String) {
        let result = renderCore.stopAllWithDiagnostics(reason: reason)
        recordRuntimeEvent(
            action: "c_mixer_clear_all",
            context: context,
            targetScope: "all_channels",
            targetedAllVoices: result.targetedAllVoices,
            snapshotBefore: result.snapshotBefore,
            snapshot: result.snapshotAfter,
            succeeded: true,
            stoppedVoiceCount: result.stoppedVoiceCount,
            reason: result.reason
        )
        engine.pause()
        if isFallbackActive {
            fallbackAudioEngine.stopAll()
        }
    }

    func reset() {
        stopAll()
        engine.stop()
        fallbackAudioEngine.reset()
        isFallbackActive = false
        if isPrepared {
            engine.detach(sourceNode)
        }
        engine.reset()
        isPrepared = false
    }

    private func prepareIfNeeded() {
        guard !isPrepared else {
            return
        }
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        isPrepared = true
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else {
            return true
        }
        do {
            try engine.start()
            logger.info(
                "Experimental C mixer runtime start succeeded=true sample_rate=\(self.format.sampleRate, privacy: .public) channel_count=\(self.format.channelCount, privacy: .public)"
            )
            return true
        } catch {
            logger.error(
                "Experimental C mixer runtime start succeeded=false falling_back=true error=\(error.localizedDescription, privacy: .public)"
            )
            renderCore.stopAll()
            return false
        }
    }

    private func recordRuntimeEvent(
        action: String,
        context: AudioRuntimeTraceContext?,
        targetScope: String,
        targetedAllVoices: Bool = false,
        snapshotBefore: RuntimeCMixerRenderSnapshot? = nil,
        snapshot: RuntimeCMixerRenderSnapshot,
        succeeded: Bool?,
        stoppedVoiceCount: Int? = nil,
        reason: String?
    ) {
        guard traceWriter.isEnabled else {
            return
        }
        traceWriter.record(RuntimeCMixerTraceEvent(
            runtimeAction: action,
            runtimeAudioBackend: runtimeAudioBackend.diagnosticName,
            experimentalCMixerEnabled: true,
            context: context,
            targetScope: targetScope,
            targetedAllVoices: targetedAllVoices,
            activeVoiceCount: snapshot.activeVoiceCount,
            loadedVoiceCount: snapshot.loadedVoiceCount,
            activeVoiceCountBefore: snapshotBefore?.activeVoiceCount,
            activeVoiceCountAfter: snapshot.activeVoiceCount,
            loadedVoiceCountBefore: snapshotBefore?.loadedVoiceCount,
            loadedVoiceCountAfter: snapshot.loadedVoiceCount,
            stoppedVoiceCount: stoppedVoiceCount,
            currentFrame: snapshot.currentFrame,
            renderCallCount: snapshot.renderCallCount,
            renderedFrameCount: snapshot.renderedFrameCount,
            cMixerCallSucceeded: succeeded,
            reason: reason
        ))
    }

    private func contextWithFallbackChannel(
        _ context: AudioRuntimeTraceContext?,
        channel: Int
    ) -> AudioRuntimeTraceContext? {
        guard context?.channelIndex == nil else {
            return context
        }
        return AudioRuntimeTraceContext(channelIndex: channel)
    }
}

@MainActor
final class PlaybackAudioEngine: PlaybackAudioOutput, PlaybackAudioBackendProviding {
    private final class ChannelVoice {
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
    }

    private let logger = Logger(subsystem: "com.syncomm.VoodooTrackerX", category: "Audio")
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var voicesByChannel = [Int: ChannelVoice]()
    private var isPrepared = false

    init(sampleRate: Double = 44_100) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    var audioBufferSampleRate: Double {
        format.sampleRate
    }

    var runtimeAudioBackend: RuntimeAudioBackend {
        .avAudio
    }

    func trigger(_ request: AudioVoiceRequest) {
        guard let plan = AudioSamplePlaybackPlanner.plan(for: request.sample, sampleStartOffset: request.sampleStartOffset) else {
            return
        }
        let introBuffer = plan.introRange.flatMap { makeBuffer(for: request, sampleRange: $0) }
        let loopBuffer = plan.loopRange.flatMap { loopRange in
            plan.usesPingPongLoop
                ? makePingPongLoopBuffer(for: request, sampleRange: loopRange)
                : makeBuffer(for: request, sampleRange: loopRange)
        }
        guard introBuffer != nil || loopBuffer != nil else {
            return
        }
        let voice = voice(forChannel: request.channel)
        prepareIfNeeded()
        guard startEngineIfNeeded() else {
            return
        }

        apply(
            AudioChannelControls(
                volumeScale: request.volumeScale,
                pitchOffsetSemitones: request.pitchOffsetSemitones,
                panning: request.panning
            ),
            to: voice
        )
        voice.player.stop()
        if let introBuffer {
            voice.player.scheduleBuffer(introBuffer, at: nil, options: [], completionHandler: nil)
        }
        if let loopBuffer {
            voice.player.scheduleBuffer(loopBuffer, at: nil, options: .loops, completionHandler: nil)
        }
        voice.player.play()
    }

    func update(channel: Int, controls: AudioChannelControls) {
        guard let voice = voicesByChannel[channel] else {
            return
        }
        apply(controls, to: voice)
    }

    func stop(channel: Int) {
        voicesByChannel[channel]?.player.stop()
    }

    func stopAll() {
        for voice in voicesByChannel.values {
            voice.player.stop()
        }
        engine.pause()
    }

    func reset() {
        stopAll()
        for voice in voicesByChannel.values {
            engine.detach(voice.player)
            engine.detach(voice.varispeed)
        }
        voicesByChannel.removeAll()
        engine.reset()
        isPrepared = false
    }

    private func prepareIfNeeded() {
        guard !isPrepared else {
            return
        }
        engine.prepare()
        isPrepared = true
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else {
            return true
        }
        do {
            try engine.start()
            return true
        } catch {
            logger.error("Unable to start audio engine: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func voice(forChannel channel: Int) -> ChannelVoice {
        if let voice = voicesByChannel[channel] {
            return voice
        }
        let voice = ChannelVoice()
        engine.attach(voice.player)
        engine.attach(voice.varispeed)
        engine.connect(voice.player, to: voice.varispeed, format: format)
        engine.connect(voice.varispeed, to: engine.mainMixerNode, format: format)
        voicesByChannel[channel] = voice
        return voice
    }

    private func apply(_ controls: AudioChannelControls, to voice: ChannelVoice) {
        voice.player.volume = min(1, max(0, controls.volumeScale))
        voice.player.pan = min(1, max(-1, controls.panning))
        let rate = Float(pow(2.0, controls.pitchOffsetSemitones / 12.0))
        voice.varispeed.rate = min(4, max(0.25, rate))
    }

    private func makeBuffer(for request: AudioVoiceRequest, sampleRange: Range<Int>) -> AVAudioPCMBuffer? {
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96,
              sampleRange.lowerBound >= 0,
              sampleRange.upperBound <= request.sample.pcm.count,
              !sampleRange.isEmpty else {
            return nil
        }
        return makeBuffer(for: request, sourceFrameCount: sampleRange.count) { sourceFrame in
            let sampleIndex = min(sampleRange.upperBound - 1, sampleRange.lowerBound + sourceFrame)
            return request.sample.pcm[sampleIndex]
        }
    }

    private func makePingPongLoopBuffer(for request: AudioVoiceRequest, sampleRange: Range<Int>) -> AVAudioPCMBuffer? {
        let frameIndices = AudioSampleLoopFrameBuilder.pingPongFrameIndices(
            for: sampleRange,
            sampleFrameCount: request.sample.pcm.count
        )
        guard !frameIndices.isEmpty else {
            return nil
        }
        return makeBuffer(for: request, sourceFrameCount: frameIndices.count) { sourceFrame in
            request.sample.pcm[frameIndices[sourceFrame]]
        }
    }

    private func makeBuffer(
        for request: AudioVoiceRequest,
        sourceFrameCount: Int,
        sampleAt: (Int) -> Float
    ) -> AVAudioPCMBuffer? {
        guard request.sample.isPlayable,
              request.note > 0,
              request.note <= 96,
              sourceFrameCount > 0 else {
            return nil
        }
        let pitchRatio = PlaybackPitchCalculator.notePitchRatio(note: request.note, sample: request.sample)
        let increment = max(0.001, (request.sample.baseSampleRate / format.sampleRate) * pitchRatio)
        let frameCount = max(1, Int(Double(sourceFrameCount) / increment))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let output = buffer.floatChannelData?[0] else {
            return nil
        }

        var samplePosition = 0.0
        let gain = min(0.8, max(0, request.sample.volume))
        for frame in 0..<frameCount {
            let sourceFrame = min(sourceFrameCount - 1, Int(samplePosition))
            output[frame] = sampleAt(sourceFrame) * gain
            samplePosition += increment
        }
        return buffer
    }
}
