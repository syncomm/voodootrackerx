// Swift reference/spec mixer types. Audible runtime playback currently uses the
// CoreAudio-hosted C mixer path bridged through CSoftwareMixer.
import Foundation

enum MixerPanLaw: String, Equatable {
    case linear
    case ft2EqualPower = "ft2_equal_power"

    func leftGain(for pan: Float) -> Float {
        let sanitizedPan = Self.sanitizedPan(pan)
        switch self {
        case .linear:
            return sanitizedPan <= 0 ? 1 : 1 - sanitizedPan
        case .ft2EqualPower:
            if sanitizedPan <= -1 {
                return 1
            }
            if sanitizedPan >= 1 {
                return 0
            }
            let position = (Double(sanitizedPan) + 1.0) * 0.5
            return Float(cos(position * Double.pi / 2.0))
        }
    }

    func rightGain(for pan: Float) -> Float {
        let sanitizedPan = Self.sanitizedPan(pan)
        switch self {
        case .linear:
            return sanitizedPan >= 0 ? 1 : 1 + sanitizedPan
        case .ft2EqualPower:
            if sanitizedPan <= -1 {
                return 0
            }
            if sanitizedPan >= 1 {
                return 1
            }
            let position = (Double(sanitizedPan) + 1.0) * 0.5
            return Float(sin(position * Double.pi / 2.0))
        }
    }

    private static func sanitizedPan(_ pan: Float) -> Float {
        guard pan.isFinite else {
            return 0
        }
        return min(1, max(-1, pan))
    }
}

/// Explicit offline/reference mix policy applied inside the mixer before WAV export gain.
///
/// This intentionally separates reference-render panning/output scale from WAV export headroom and
/// runtime device safety gain.
enum MixerMixProfile: String, CaseIterable, Equatable {
    case vtx
    case ft2

    static let ft2ReferenceAmplification: Float = 10
    static let ft2ReferenceMasterVolume: Float = 256
    static let ft2ReferenceOutputDivisor: Float = 32 * 256
    static let ft2ReferenceOutputScale = (ft2ReferenceAmplification * ft2ReferenceMasterVolume) / ft2ReferenceOutputDivisor

    var panLaw: MixerPanLaw {
        switch self {
        case .vtx:
            return .linear
        case .ft2:
            return .ft2EqualPower
        }
    }

    var outputScale: Float {
        switch self {
        case .vtx:
            return 1
        case .ft2:
            return Self.ft2ReferenceOutputScale
        }
    }

    var outputScalePolicy: String {
        switch self {
        case .vtx:
            return "unity"
        case .ft2:
            return "ft2_clone_amplification_master_float_export"
        }
    }

    var outputScaleFormula: String {
        switch self {
        case .vtx:
            return "1.0"
        case .ft2:
            return "(amplification * master_volume) / (32 * 256)"
        }
    }

    var centerPanContribution: Float {
        panLaw.leftGain(for: 0)
    }

    var centeredOutputContribution: Float {
        centerPanContribution * outputScale
    }

    static func matching(panLaw: MixerPanLaw, outputScale: Float) -> MixerMixProfile? {
        allCases.first { profile in
            profile.panLaw == panLaw && abs(profile.outputScale - outputScale) <= 0.000_001
        }
    }
}

/// Deterministic software mixer configuration for offline rendering and a later runtime backend migration.
///
/// This offline path remains separate from the CoreAudio-hosted runtime C mixer.
struct MixerRenderConfig: Equatable {
    static let defaultSampleRate = 44_100.0
    static let defaultChannelCount = 2

    let sampleRate: Double
    let channelCount: Int
    let isInterleaved: Bool
    let mixProfile: MixerMixProfile

    var panLaw: MixerPanLaw {
        mixProfile.panLaw
    }

    var outputScale: Float {
        mixProfile.outputScale
    }

    /// Creates a safe render configuration, falling back to deterministic defaults for invalid values.
    init(
        sampleRate: Double = defaultSampleRate,
        channelCount: Int = defaultChannelCount,
        isInterleaved: Bool = true,
        mixProfile: MixerMixProfile = .vtx
    ) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : Self.defaultSampleRate
        self.channelCount = channelCount > 0 ? channelCount : Self.defaultChannelCount
        self.isInterleaved = isInterleaved
        self.mixProfile = mixProfile
    }
}

/// A single interleaved mixer output frame.
///
/// Future mixer PRs can use this as a typed boundary for inspecting per-frame channel samples without
/// depending on CoreAudio or AppKit types.
struct MixerFrame: Equatable {
    let samples: [Float]

    /// Creates one silent frame for the requested channel count.
    init(channelCount: Int) {
        samples = Array(repeating: 0, count: max(0, channelCount))
    }
}

/// Immutable mono Float32 PCM that preserves finite input and replaces non-finite values with zero.
struct MixerSampleBuffer: Equatable {
    let monoPCM: [Float]

    var frameCount: Int {
        monoPCM.count
    }

    init(monoPCM: [Float]) {
        self.monoPCM = monoPCM.map { $0.isFinite ? $0 : 0 }
    }
}

/// Synthetic sample loop modes owned by the deterministic offline mixer.
enum MixerSampleLoopMode: Equatable {
    case none
    case forward
    case pingPong
}

/// Synthetic sample loop metadata for `MixerVoice`.
///
/// `endFrame` is exclusive. For example, `startFrame: 1, endFrame: 4` loops source frames
/// 1, 2, and 3. Invalid loops are sanitized to `.none` so offline renders fall back to
/// one-shot playback instead of trapping or reading outside the synthetic sample buffer.
struct MixerSampleLoop: Equatable {
    static let none = MixerSampleLoop(mode: .none, startFrame: 0, endFrame: 0)

    let mode: MixerSampleLoopMode
    let startFrame: Int
    let endFrame: Int

    var lengthFrames: Int {
        max(0, endFrame - startFrame)
    }

    init(mode: MixerSampleLoopMode = .none, startFrame: Int = 0, endFrame: Int = 0) {
        self.mode = mode
        self.startFrame = startFrame
        self.endFrame = endFrame
    }

    func sanitized(sampleFrameCount: Int) -> MixerSampleLoop {
        guard mode != .none else {
            return .none
        }
        guard sampleFrameCount > 0,
              startFrame >= 0,
              endFrame <= sampleFrameCount,
              endFrame > startFrame else {
            return .none
        }
        if mode == .pingPong && lengthFrames < 2 {
            return .none
        }
        return self
    }
}

/// Explicit synthetic sample voice state for the deterministic mixer.
///
/// This path supports bounded synthetic mono samples only: no envelopes, pitch conversion,
/// pattern scheduling, or XM instrument ownership.
struct MixerVoice: Equatable {
    let channelIndex: Int
    let sample: MixerSampleBuffer
    let gain: Float
    let pan: Float
    let step: Double
    let loop: MixerSampleLoop
    var isActive: Bool
    private(set) var samplePosition: Double
    private(set) var pingPongDirection: Int

    init(
        channelIndex: Int,
        sample: MixerSampleBuffer = MixerSampleBuffer(monoPCM: []),
        gain: Float = 1,
        pan: Float = 0,
        step: Double = 1,
        loop: MixerSampleLoop = .none,
        isActive: Bool? = nil
    ) {
        self.channelIndex = max(0, channelIndex)
        self.sample = sample
        self.gain = gain.isFinite ? gain : 0
        self.pan = min(1, max(-1, pan.isFinite ? pan : 0))
        self.step = step.isFinite && step > 0 ? step : 1
        self.loop = loop.sanitized(sampleFrameCount: sample.frameCount)
        samplePosition = 0
        pingPongDirection = 1
        self.isActive = isActive ?? !sample.monoPCM.isEmpty
    }

    var leftPanGain: Float {
        MixerPanLaw.linear.leftGain(for: pan)
    }

    var rightPanGain: Float {
        MixerPanLaw.linear.rightGain(for: pan)
    }

    mutating func reset() {
        samplePosition = 0
        pingPongDirection = 1
        isActive = !sample.monoPCM.isEmpty
    }

    mutating func nextMonoSample() -> Float? {
        guard isActive else {
            return nil
        }
        let sourceIndex = Int(samplePosition)
        guard sample.monoPCM.indices.contains(sourceIndex) else {
            isActive = false
            return nil
        }

        let value = sample.monoPCM[sourceIndex] * gain
        advanceSamplePosition()
        return value
    }

    private mutating func advanceSamplePosition() {
        switch loop.mode {
        case .none:
            advanceOneShotPosition()
        case .forward:
            advanceForwardLoopPosition()
        case .pingPong:
            advancePingPongLoopPosition()
        }
    }

    private mutating func advanceOneShotPosition() {
        samplePosition += step
        if samplePosition >= Double(sample.frameCount) {
            isActive = false
        }
    }

    private mutating func advanceForwardLoopPosition() {
        samplePosition += step
        guard samplePosition >= Double(loop.endFrame) else {
            return
        }

        let loopLength = Double(loop.lengthFrames)
        guard loopLength > 0 else {
            isActive = false
            return
        }
        let overflow = samplePosition - Double(loop.endFrame)
        samplePosition = Double(loop.startFrame) + overflow.truncatingRemainder(dividingBy: loopLength)
    }

    private mutating func advancePingPongLoopPosition() {
        samplePosition += step * Double(pingPongDirection)

        let firstLoopFrame = Double(loop.startFrame)
        let lastLoopFrame = Double(loop.endFrame - 1)
        let span = lastLoopFrame - firstLoopFrame
        guard span > 0 else {
            samplePosition = firstLoopFrame
            pingPongDirection = 1
            return
        }

        let period = span * 2
        if pingPongDirection > 0 && samplePosition > lastLoopFrame {
            let overshoot = (samplePosition - lastLoopFrame).truncatingRemainder(dividingBy: period)
            samplePosition = lastLoopFrame + overshoot
        } else if pingPongDirection < 0 && samplePosition < firstLoopFrame {
            let overshoot = (firstLoopFrame - samplePosition).truncatingRemainder(dividingBy: period)
            samplePosition = firstLoopFrame - overshoot
        }

        if pingPongDirection > 0 && samplePosition > lastLoopFrame {
            let overshoot = samplePosition - lastLoopFrame
            samplePosition = lastLoopFrame - overshoot
            pingPongDirection = -1
        } else if pingPongDirection < 0 && samplePosition < firstLoopFrame {
            let overshoot = firstLoopFrame - samplePosition
            samplePosition = firstLoopFrame + overshoot
            pingPongDirection = 1
        }
    }
}

/// A deterministic Float32 PCM render block produced by `SoftwareMixer`.
///
/// Samples are interleaved according to `config.channelCount`.
struct MixerRenderBlock: Equatable {
    let config: MixerRenderConfig
    let frameCount: Int
    let interleavedPCM: [Float]

    var sampleCount: Int {
        interleavedPCM.count
    }
}

enum MixerWAVExportError: LocalizedError, Equatable {
    case invalidChannelCount(Int)
    case invalidSampleRate(Double)
    case invalidPCMShape(expectedSampleCount: Int, actualSampleCount: Int)
    case invalidWAVFile(String)
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case let .invalidChannelCount(channelCount):
            return "Cannot export WAV with invalid channel count: \(channelCount)."
        case let .invalidSampleRate(sampleRate):
            return "Cannot export WAV with invalid sample rate: \(sampleRate)."
        case let .invalidPCMShape(expectedSampleCount, actualSampleCount):
            return "Cannot export WAV with \(actualSampleCount) samples; expected \(expectedSampleCount)."
        case let .invalidWAVFile(message):
            return "Cannot process Float32 WAV file. \(message)"
        case .fileTooLarge:
            return "Cannot export WAV because the render block exceeds RIFF/WAVE size limits."
        }
    }
}

enum MixerWAVFormat: String, CaseIterable, Equatable {
    case pcm16
    case float32

    var wavFormatCode: UInt16 {
        switch self {
        case .pcm16:
            return 1
        case .float32:
            return 3
        }
    }

    var bitsPerSample: Int {
        switch self {
        case .pcm16:
            return 16
        case .float32:
            return 32
        }
    }

    var bytesPerSample: Int {
        bitsPerSample / 8
    }
}

/// Render scope represented by a shared audio-export profile.
enum AudioExportRenderScope: Equatable {
    case untilSongEnd
}

/// Shared safety limits for app and developer-tool offline audio exports.
enum AudioExportRenderLimits {
    static let maximumFrameCount = 100_000_000
}

/// App-product render values that can also be expanded by developer export tools.
///
/// This contains export policy only. It does not select an AppKit destination, alter the mixer,
/// or replace the render tool's separate diagnostic defaults.
struct AudioExportRenderProfile: Equatable {
    static let productWAVExport = AudioExportRenderProfile(
        scope: .untilSongEnd,
        sampleRate: 48_000,
        channelCount: MixerRenderConfig.defaultChannelCount,
        wavFormat: .float32,
        mixProfile: .vtx,
        tailSeconds: 3,
        windowRows: 64,
        autoHeadroomEnabled: true,
        allowLongRender: true,
        maximumFrameCount: AudioExportRenderLimits.maximumFrameCount
    )

    let scope: AudioExportRenderScope
    let sampleRate: Double
    let channelCount: Int
    let wavFormat: MixerWAVFormat
    let mixProfile: MixerMixProfile
    let tailSeconds: Double
    let windowRows: Int
    let autoHeadroomEnabled: Bool
    let allowLongRender: Bool
    let maximumFrameCount: Int
}

/// Converts export-side durations to frame counts with explicit rounding semantics.
enum AudioExportFrameCount {
    static let productExportRoundingRule = FloatingPointRoundingRule.toNearestOrAwayFromZero

    static func frameCount(
        seconds: Double,
        sampleRate: Double,
        roundingRule: FloatingPointRoundingRule = productExportRoundingRule
    ) -> Int {
        guard seconds.isFinite,
              seconds > 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return 0
        }
        let frames = (seconds * sampleRate).rounded(roundingRule)
        guard frames > 0 else {
            return 0
        }
        guard frames < Double(Int.max) else {
            return Int.max
        }
        return Int(frames)
    }
}

/// Output policy for local/offline WAV export.
///
/// The gain is applied only at the WAV export boundary, after offline Float32 rendering and before
/// WAV encoding. It does not change mixer state, C mixer DSP, or runtime playback.
struct MixerWAVExportPolicy: Equatable {
    static let unity = MixerWAVExportPolicy(gain: 1)
    static let autoHeadroomSafetyDB = -1.0

    let gain: Float
    let headroomDB: Double?
    let autoHeadroomEnabled: Bool
    let autoHeadroomSafetyDB: Double?
    let computedHeadroomDB: Double

    init(
        gain: Float = 1,
        headroomDB: Double? = nil,
        autoHeadroomEnabled: Bool = false,
        autoHeadroomSafetyDB: Double? = nil,
        computedHeadroomDB: Double? = nil
    ) {
        let safeGain = gain.isFinite && gain > 0 ? gain : 1
        self.gain = safeGain
        self.headroomDB = headroomDB
        self.autoHeadroomEnabled = autoHeadroomEnabled
        self.autoHeadroomSafetyDB = autoHeadroomSafetyDB
        self.computedHeadroomDB = computedHeadroomDB ?? (20.0 * log10(Double(safeGain)))
    }

    init(headroomDB: Double) {
        self.init(
            gain: Float(pow(10.0, headroomDB / 20.0)),
            headroomDB: headroomDB
        )
    }

    static func autoHeadroom(for block: MixerRenderBlock) -> MixerWAVExportPolicy {
        let preExportPeak = MixerWAVExporter.diagnostics(for: block).preExportPeak
        return autoHeadroom(preExportPeak: preExportPeak)
    }

    static func autoHeadroom(preExportPeak: Float) -> MixerWAVExportPolicy {
        let gain: Float
        if preExportPeak > 1 {
            let safetyMargin = pow(10.0, autoHeadroomSafetyDB / 20.0)
            gain = Float((1.0 / Double(preExportPeak)) * safetyMargin)
        } else {
            gain = 1
        }
        return MixerWAVExportPolicy(
            gain: gain,
            autoHeadroomEnabled: true,
            autoHeadroomSafetyDB: autoHeadroomSafetyDB
        )
    }
}

/// Incremental export-time level statistics for streamed WAV writing and auto-headroom preflight.
struct MixerWAVExportDiagnosticsAccumulator {
    let channelCount: Int
    let exportPolicy: MixerWAVExportPolicy
    let wavFormat: MixerWAVFormat

    private var prePerChannelPeak: [Float]
    private var postPerChannelPeak: [Float]
    private var preSquareSum = Double(0)
    private var postSquareSum = Double(0)
    private var prePeak = Float(0)
    private var postPeak = Float(0)
    private var preOverrange = 0
    private var postOverrange = 0
    private var pcm16Clipping = 0
    private var sampleCount = 0

    init(
        channelCount: Int,
        exportPolicy: MixerWAVExportPolicy = .unity,
        wavFormat: MixerWAVFormat = .float32
    ) {
        self.channelCount = max(1, channelCount)
        self.exportPolicy = exportPolicy
        self.wavFormat = wavFormat
        prePerChannelPeak = Array(repeating: Float(0), count: self.channelCount)
        postPerChannelPeak = Array(repeating: Float(0), count: self.channelCount)
    }

    @discardableResult
    mutating func append(samples: [Float]) -> Bool {
        var allSamplesFinite = true
        var channel = sampleCount % channelCount
        for sample in samples {
            allSamplesFinite = allSamplesFinite && sample.isFinite
            append(sample: sample, channel: channel)
            channel += 1
            if channel == channelCount {
                channel = 0
            }
        }
        sampleCount += samples.count
        return allSamplesFinite
    }

    mutating func append(sample: Float) {
        append(sample: sample, channel: sampleCount % channelCount)
        sampleCount += 1
    }

    mutating func append(block: MixerRenderBlock) throws {
        _ = try MixerWAVExporter.validatePCMShape(block)
        append(samples: block.interleavedPCM)
    }

    func diagnostics() -> MixerWAVExportDiagnostics {
        let safeSampleCount = max(1, sampleCount)
        return MixerWAVExportDiagnostics(
            wavFormat: wavFormat,
            policy: exportPolicy,
            preExportPeak: prePeak,
            preExportPerChannelPeak: prePerChannelPeak,
            preExportOverrangeSampleCount: preOverrange,
            preExportRMS: Float(sqrt(preSquareSum / Double(safeSampleCount))),
            postGainPeak: postPeak,
            postGainPerChannelPeak: postPerChannelPeak,
            postGainOverrangeSampleCount: postOverrange,
            postGainRMS: Float(sqrt(postSquareSum / Double(safeSampleCount))),
            pcm16ClippingSampleCount: pcm16Clipping
        )
    }

    private mutating func append(sample: Float, channel: Int) {
        let finiteSample = sample.isFinite ? sample : 0
        let preAbs = abs(finiteSample)
        let postSample = MixerWAVExporter.scaledSample(finiteSample, gain: exportPolicy.gain)
        let postAbs = abs(postSample)

        prePeak = max(prePeak, preAbs)
        postPeak = max(postPeak, postAbs)
        prePerChannelPeak[channel] = max(prePerChannelPeak[channel], preAbs)
        postPerChannelPeak[channel] = max(postPerChannelPeak[channel], postAbs)
        preSquareSum += Double(finiteSample) * Double(finiteSample)
        postSquareSum += Double(postSample) * Double(postSample)
        if preAbs > 1 {
            preOverrange += 1
        }
        if postAbs > 1 {
            postOverrange += 1
        }
        if wavFormat == .pcm16 && abs(Double(finiteSample) * Double(exportPolicy.gain)) >= 1 {
            pcm16Clipping += 1
        }
    }
}

/// Export-time level statistics for local WAV diagnostics.
struct MixerWAVExportDiagnostics: Equatable {
    let wavFormat: MixerWAVFormat
    let policy: MixerWAVExportPolicy
    let preExportPeak: Float
    let preExportPerChannelPeak: [Float]
    let preExportOverrangeSampleCount: Int
    let preExportRMS: Float
    let postGainPeak: Float
    let postGainPerChannelPeak: [Float]
    let postGainOverrangeSampleCount: Int
    let postGainRMS: Float
    let pcm16ClippingSampleCount: Int

    var autoHeadroomEnabled: Bool {
        policy.autoHeadroomEnabled
    }

    var autoHeadroomSafetyDB: Double? {
        policy.autoHeadroomSafetyDB
    }

    var computedExportGain: Float {
        policy.gain
    }

    var computedHeadroomDB: Double {
        policy.computedHeadroomDB
    }

    var preExportOverrangeDetected: Bool {
        preExportOverrangeSampleCount > 0
    }

    var clippingDetected: Bool {
        wavFormat == .pcm16 && pcm16ClippingSampleCount > 0
    }

    var recommendation: String? {
        guard wavFormat == .pcm16, clippingDetected else {
            return nil
        }
        return "PCM16 clipping/clamping detected after export gain; rerender with --headroom-db <negative dB> or --gain <linear gain>."
    }

    func replacingPolicy(withEquivalentGain policy: MixerWAVExportPolicy) -> MixerWAVExportDiagnostics {
        // Numeric fields are reusable only when the replacement policy applies the exact same gain.
        precondition(policy.gain == self.policy.gain)
        return MixerWAVExportDiagnostics(
            wavFormat: wavFormat,
            policy: policy,
            preExportPeak: preExportPeak,
            preExportPerChannelPeak: preExportPerChannelPeak,
            preExportOverrangeSampleCount: preExportOverrangeSampleCount,
            preExportRMS: preExportRMS,
            postGainPeak: postGainPeak,
            postGainPerChannelPeak: postGainPerChannelPeak,
            postGainOverrangeSampleCount: postGainOverrangeSampleCount,
            postGainRMS: postGainRMS,
            pcm16ClippingSampleCount: pcm16ClippingSampleCount
        )
    }
}

struct MixerWAVExportResult: Equatable {
    let data: Data
    let diagnostics: MixerWAVExportDiagnostics
}

struct MixerWAVLayout: Equatable {
    let sampleRate: UInt32
    let channelCount: UInt16
    let blockAlign: UInt16
    let byteRate: UInt32
    let dataByteCount: UInt32
    let riffChunkSize: UInt32
    let expectedSampleCount: Int
}

/// Deterministic RIFF/WAVE writer for offline mixer render blocks.
///
/// This helper is local/offline infrastructure only. It does not add a runtime playback backend,
/// change mixer DSP behavior, parse modules, or compare candidate audio against references.
enum MixerWAVExporter {
    static let bitsPerSample = MixerWAVFormat.pcm16.bitsPerSample
    private static let canonicalWAVHeaderByteCount = 44

    static func layout(
        config: MixerRenderConfig,
        frameCount: Int,
        format: MixerWAVFormat
    ) throws -> MixerWAVLayout {
        let channelCount = config.channelCount
        guard channelCount > 0, channelCount <= Int(UInt16.max) else {
            throw MixerWAVExportError.invalidChannelCount(channelCount)
        }

        let roundedSampleRate = config.sampleRate.rounded(.toNearestOrAwayFromZero)
        guard config.sampleRate.isFinite,
              roundedSampleRate > 0,
              roundedSampleRate <= Double(UInt32.max) else {
            throw MixerWAVExportError.invalidSampleRate(config.sampleRate)
        }

        let safeFrameCount = max(0, frameCount)
        let (expectedSampleCount, sampleCountOverflow) = safeFrameCount.multipliedReportingOverflow(by: channelCount)
        guard !sampleCountOverflow else {
            throw MixerWAVExportError.fileTooLarge
        }

        let (dataByteCount, dataByteCountOverflow) = expectedSampleCount.multipliedReportingOverflow(by: format.bytesPerSample)
        let (riffChunkSize, riffChunkSizeOverflow) = dataByteCount.addingReportingOverflow(36)
        guard !dataByteCountOverflow,
              !riffChunkSizeOverflow,
              dataByteCount <= Int(UInt32.max),
              riffChunkSize <= Int(UInt32.max) else {
            throw MixerWAVExportError.fileTooLarge
        }

        let sampleRate = UInt32(roundedSampleRate)
        let blockAlign = channelCount * format.bytesPerSample
        let byteRate = UInt64(sampleRate) * UInt64(blockAlign)
        guard blockAlign <= Int(UInt16.max),
              byteRate <= UInt64(UInt32.max) else {
            throw MixerWAVExportError.fileTooLarge
        }

        return MixerWAVLayout(
            sampleRate: sampleRate,
            channelCount: UInt16(channelCount),
            blockAlign: UInt16(blockAlign),
            byteRate: UInt32(byteRate),
            dataByteCount: UInt32(dataByteCount),
            riffChunkSize: UInt32(riffChunkSize),
            expectedSampleCount: expectedSampleCount
        )
    }

    static func pcm16WAVData(
        from block: MixerRenderBlock,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> Data {
        try wavExport(from: block, format: .pcm16, exportPolicy: exportPolicy).data
    }

    static func pcm16WAVExport(
        from block: MixerRenderBlock,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> MixerWAVExportResult {
        try wavExport(from: block, format: .pcm16, exportPolicy: exportPolicy)
    }

    static func float32WAVData(
        from block: MixerRenderBlock,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> Data {
        try wavExport(from: block, format: .float32, exportPolicy: exportPolicy).data
    }

    static func float32WAVExport(
        from block: MixerRenderBlock,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> MixerWAVExportResult {
        try wavExport(from: block, format: .float32, exportPolicy: exportPolicy)
    }

    static func wavData(
        from block: MixerRenderBlock,
        format: MixerWAVFormat = .pcm16,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> Data {
        try wavExport(from: block, format: format, exportPolicy: exportPolicy).data
    }

    static func wavExport(
        from block: MixerRenderBlock,
        format: MixerWAVFormat = .pcm16,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> MixerWAVExportResult {
        let layout = try layout(config: block.config, frameCount: block.frameCount, format: format)
        guard layout.expectedSampleCount == block.interleavedPCM.count else {
            let (expectedSampleCount, sampleCountOverflow) = block.frameCount.multipliedReportingOverflow(by: block.config.channelCount)
            throw MixerWAVExportError.invalidPCMShape(
                expectedSampleCount: sampleCountOverflow ? Int.max : expectedSampleCount,
                actualSampleCount: block.interleavedPCM.count
            )
        }

        var data = Data()
        data.reserveCapacity(44 + Int(layout.dataByteCount))
        appendHeader(layout: layout, format: format, to: &data)

        var diagnosticsAccumulator = MixerWAVExportDiagnosticsAccumulator(
            channelCount: block.config.channelCount,
            exportPolicy: exportPolicy,
            wavFormat: format
        )
        let allSamplesFinite = diagnosticsAccumulator.append(samples: block.interleavedPCM)
        switch format {
        case .pcm16:
            for sample in block.interleavedPCM {
                let scaledSample = scaledSample(sample, gain: exportPolicy.gain)
                appendLEInt16(pcm16Sample(from: scaledSample), to: &data)
            }
        case .float32:
            appendFloat32Samples(
                block.interleavedPCM,
                exportPolicy: exportPolicy,
                allSamplesFinite: allSamplesFinite,
                to: &data
            )
        }
        return MixerWAVExportResult(
            data: data,
            diagnostics: diagnosticsAccumulator.diagnostics()
        )
    }

    @discardableResult
    static func writeStreamingFloat32WAV(
        config: MixerRenderConfig,
        frameCount: Int,
        to url: URL,
        exportPolicy: MixerWAVExportPolicy = .unity,
        writeBlocks: (_ writer: MixerFloat32WAVStreamWriter) throws -> Void
    ) throws -> MixerWAVExportDiagnostics {
        let writer = try MixerFloat32WAVStreamWriter(
            config: config,
            expectedFrameCount: frameCount,
            url: url,
            exportPolicy: exportPolicy
        )
        do {
            try writeBlocks(writer)
            return try writer.finish()
        } catch {
            writer.close()
            throw error
        }
    }

    @discardableResult
    static func writeFloat32WAVApplyingGain(
        from sourceURL: URL,
        to destinationURL: URL,
        exportPolicy: MixerWAVExportPolicy,
        chunkSampleCount: Int = 262_144,
        progress: ((Int, Int) throws -> Void)? = nil
    ) throws -> MixerWAVExportDiagnostics {
        let layout = try readCanonicalFloat32WAVLayout(from: sourceURL)
        let inputHandle = try FileHandle(forReadingFrom: sourceURL)
        defer {
            try? inputHandle.close()
        }
        guard let header = try inputHandle.read(upToCount: canonicalWAVHeaderByteCount),
              header.count == canonicalWAVHeaderByteCount else {
            throw MixerWAVExportError.invalidWAVFile("Missing canonical WAV header.")
        }

        try? FileManager.default.removeItem(at: destinationURL)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: destinationURL)
        var outputClosed = false
        func closeOutput() {
            guard !outputClosed else {
                return
            }
            try? outputHandle.close()
            outputClosed = true
        }
        defer {
            closeOutput()
        }

        do {
            try outputHandle.write(contentsOf: header)
            var diagnosticsAccumulator = MixerWAVExportDiagnosticsAccumulator(
                channelCount: Int(layout.channelCount),
                exportPolicy: exportPolicy,
                wavFormat: .float32
            )
            let safeChunkSampleCount = max(1, chunkSampleCount)
            let chunkByteCount = safeChunkSampleCount * MixerWAVFormat.float32.bytesPerSample
            let totalDataBytes = Int(layout.dataByteCount)
            var processedDataBytes = 0
            var pendingBytes = Data()
            pendingBytes.reserveCapacity(MixerWAVFormat.float32.bytesPerSample)
            var outputData = Data()
            outputData.reserveCapacity(chunkByteCount + MixerWAVFormat.float32.bytesPerSample)

            while processedDataBytes < totalDataBytes {
                let requestedByteCount = min(chunkByteCount, totalDataBytes - processedDataBytes)
                guard let inputData = try inputHandle.read(upToCount: requestedByteCount),
                      !inputData.isEmpty else {
                    throw MixerWAVExportError.invalidWAVFile("Unexpected end of Float32 sample data.")
                }
                processedDataBytes += inputData.count
                outputData.removeAll(keepingCapacity: true)
                try inputData.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) in
                    // FileHandle may legally return a short read; retain only its final 0...3 bytes.
                    var inputOffset = 0
                    if !pendingBytes.isEmpty {
                        let copiedByteCount = min(
                            MixerWAVFormat.float32.bytesPerSample - pendingBytes.count,
                            inputBytes.count
                        )
                        for byteOffset in 0..<copiedByteCount {
                            pendingBytes.append(inputBytes[byteOffset])
                        }
                        inputOffset += copiedByteCount
                        if pendingBytes.count == MixerWAVFormat.float32.bytesPerSample {
                            try pendingBytes.withUnsafeBytes { (pendingInputBytes: UnsafeRawBufferPointer) in
                                try appendScaledFloat32Samples(
                                    from: pendingInputBytes,
                                    to: &outputData,
                                    exportPolicy: exportPolicy,
                                    diagnosticsAccumulator: &diagnosticsAccumulator
                                )
                            }
                            pendingBytes.removeAll(keepingCapacity: true)
                        }
                    }

                    let remainingByteCount = inputBytes.count - inputOffset
                    let processableByteCount = remainingByteCount
                        - (remainingByteCount % MixerWAVFormat.float32.bytesPerSample)
                    if processableByteCount > 0 {
                        let processableBytes = UnsafeRawBufferPointer(rebasing: inputBytes[
                            inputOffset..<(inputOffset + processableByteCount)
                        ])
                        try appendScaledFloat32Samples(
                            from: processableBytes,
                            to: &outputData,
                            exportPolicy: exportPolicy,
                            diagnosticsAccumulator: &diagnosticsAccumulator
                        )
                        inputOffset += processableByteCount
                    }

                    while inputOffset < inputBytes.count {
                        pendingBytes.append(inputBytes[inputOffset])
                        inputOffset += 1
                    }
                }
                if !outputData.isEmpty {
                    try outputHandle.write(contentsOf: outputData)
                }
                try progress?(processedDataBytes, totalDataBytes)
            }

            guard pendingBytes.isEmpty else {
                throw MixerWAVExportError.invalidWAVFile("Float32 sample data is not four-byte aligned.")
            }
            closeOutput()
            return diagnosticsAccumulator.diagnostics()
        } catch {
            closeOutput()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    @discardableResult
    static func validatePCMShape(_ block: MixerRenderBlock) throws -> Int {
        let (expectedSampleCount, sampleCountOverflow) = block.frameCount.multipliedReportingOverflow(by: block.config.channelCount)
        guard !sampleCountOverflow,
              expectedSampleCount == block.interleavedPCM.count else {
            throw MixerWAVExportError.invalidPCMShape(
                expectedSampleCount: sampleCountOverflow ? Int.max : expectedSampleCount,
                actualSampleCount: block.interleavedPCM.count
            )
        }
        return expectedSampleCount
    }

    fileprivate static func appendHeader(layout: MixerWAVLayout, format: MixerWAVFormat, to data: inout Data) {
        appendASCII("RIFF", to: &data)
        appendLE32(layout.riffChunkSize, to: &data)
        appendASCII("WAVE", to: &data)
        appendASCII("fmt ", to: &data)
        appendLE32(16, to: &data)
        appendLE16(format.wavFormatCode, to: &data)
        appendLE16(layout.channelCount, to: &data)
        appendLE32(layout.sampleRate, to: &data)
        appendLE32(layout.byteRate, to: &data)
        appendLE16(layout.blockAlign, to: &data)
        appendLE16(UInt16(format.bitsPerSample), to: &data)
        appendASCII("data", to: &data)
        appendLE32(layout.dataByteCount, to: &data)
    }

    private static func readCanonicalFloat32WAVLayout(from url: URL) throws -> MixerWAVLayout {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw MixerWAVExportError.invalidWAVFile("Could not determine file size.")
        }
        let inputHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? inputHandle.close()
        }
        guard let header = try inputHandle.read(upToCount: canonicalWAVHeaderByteCount),
              header.count == canonicalWAVHeaderByteCount,
              Array(header[0..<4]) == Array("RIFF".utf8),
              Array(header[8..<12]) == Array("WAVE".utf8),
              Array(header[12..<16]) == Array("fmt ".utf8),
              Array(header[36..<40]) == Array("data".utf8) else {
            throw MixerWAVExportError.invalidWAVFile("Expected a canonical 44-byte RIFF/WAVE header.")
        }

        let formatCode = readLE16(header, offset: 20)
        let channelCount = readLE16(header, offset: 22)
        let sampleRate = readLE32(header, offset: 24)
        let byteRate = readLE32(header, offset: 28)
        let blockAlign = readLE16(header, offset: 32)
        let bitsPerSample = readLE16(header, offset: 34)
        let dataByteCount = readLE32(header, offset: 40)
        let riffChunkSize = readLE32(header, offset: 4)
        let expectedFileSize = UInt64(canonicalWAVHeaderByteCount) + UInt64(dataByteCount)
        let expectedByteRate = UInt64(sampleRate) * UInt64(blockAlign)
        let expectedRiffChunkSize = UInt64(dataByteCount) + 36

        guard readLE32(header, offset: 16) == 16,
              formatCode == MixerWAVFormat.float32.wavFormatCode,
              bitsPerSample == UInt16(MixerWAVFormat.float32.bitsPerSample),
              channelCount > 0,
              blockAlign == channelCount * UInt16(MixerWAVFormat.float32.bytesPerSample),
              UInt64(byteRate) == expectedByteRate,
              dataByteCount % UInt32(blockAlign) == 0,
              UInt64(riffChunkSize) == expectedRiffChunkSize,
              UInt64(fileSize.uint64Value) == expectedFileSize else {
            throw MixerWAVExportError.invalidWAVFile("Header fields do not describe a supported Float32 WAV file.")
        }

        let expectedSampleCount = Int(dataByteCount) / MixerWAVFormat.float32.bytesPerSample
        return MixerWAVLayout(
            sampleRate: sampleRate,
            channelCount: channelCount,
            blockAlign: blockAlign,
            byteRate: byteRate,
            dataByteCount: dataByteCount,
            riffChunkSize: riffChunkSize,
            expectedSampleCount: expectedSampleCount
        )
    }

    private static func appendScaledFloat32Samples(
        from inputBytes: UnsafeRawBufferPointer,
        to outputData: inout Data,
        exportPolicy: MixerWAVExportPolicy,
        diagnosticsAccumulator: inout MixerWAVExportDiagnosticsAccumulator
    ) throws {
        guard inputBytes.count % MixerWAVFormat.float32.bytesPerSample == 0 else {
            throw MixerWAVExportError.invalidWAVFile("Float32 sample data is not four-byte aligned.")
        }
        guard !inputBytes.isEmpty else {
            return
        }

        let outputStartOffset = outputData.count
        outputData.count += inputBytes.count
        outputData.withUnsafeMutableBytes { (outputBytes: UnsafeMutableRawBufferPointer) in
            var inputOffset = 0
            var outputOffset = outputStartOffset
            while inputOffset < inputBytes.count {
                let bitPattern = UInt32(inputBytes[inputOffset])
                    | (UInt32(inputBytes[inputOffset + 1]) << 8)
                    | (UInt32(inputBytes[inputOffset + 2]) << 16)
                    | (UInt32(inputBytes[inputOffset + 3]) << 24)
                let sample = Float(bitPattern: bitPattern)
                diagnosticsAccumulator.append(sample: sample)
                writeLittleEndianFloat32(
                    scaledSample(sample, gain: exportPolicy.gain),
                    to: outputBytes,
                    at: outputOffset
                )
                inputOffset += MixerWAVFormat.float32.bytesPerSample
                outputOffset += MixerWAVFormat.float32.bytesPerSample
            }
        }
    }

    fileprivate static func appendFloat32Samples(
        _ samples: [Float],
        exportPolicy: MixerWAVExportPolicy,
        allSamplesFinite: Bool,
        to data: inout Data
    ) {
        guard !samples.isEmpty else {
            return
        }
        let outputByteCount = samples.count * MixerWAVFormat.float32.bytesPerSample
#if _endian(little)
        // Finite unity-gain samples are already in canonical Float32 little-endian form.
        if exportPolicy.gain == 1, allSamplesFinite {
            samples.withUnsafeBufferPointer { sampleBuffer in
                data.append(contentsOf: UnsafeRawBufferPointer(sampleBuffer))
            }
            return
        }
#endif
        let outputStartOffset = data.count
        data.count += outputByteCount
        data.withUnsafeMutableBytes { (outputBytes: UnsafeMutableRawBufferPointer) in
            let destinationBytes = UnsafeMutableRawBufferPointer(rebasing: outputBytes[
                outputStartOffset..<(outputStartOffset + outputByteCount)
            ])
            samples.withUnsafeBufferPointer { sampleBuffer in
                for sampleOffset in sampleBuffer.indices {
                    writeLittleEndianFloat32(
                        scaledSample(sampleBuffer[sampleOffset], gain: exportPolicy.gain),
                        to: destinationBytes,
                        at: sampleOffset * MixerWAVFormat.float32.bytesPerSample
                    )
                }
            }
        }
    }

    private static func writeLittleEndianFloat32(
        _ value: Float,
        to bytes: UnsafeMutableRawBufferPointer,
        at offset: Int
    ) {
        let bitPattern = value.bitPattern
        bytes[offset] = UInt8(truncatingIfNeeded: bitPattern)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: bitPattern >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: bitPattern >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: bitPattern >> 24)
    }

    private static func readLE16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset])
            | (UInt16(data[offset + 1]) << 8)
    }

    private static func readLE32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    @discardableResult
    static func writePCM16WAV(
        from block: MixerRenderBlock,
        to url: URL,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> MixerWAVExportDiagnostics {
        let result = try wavExport(from: block, format: .pcm16, exportPolicy: exportPolicy)
        try result.data.write(to: url, options: [])
        return result.diagnostics
    }

    @discardableResult
    static func writeFloat32WAV(
        from block: MixerRenderBlock,
        to url: URL,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> MixerWAVExportDiagnostics {
        let result = try wavExport(from: block, format: .float32, exportPolicy: exportPolicy)
        try result.data.write(to: url, options: [])
        return result.diagnostics
    }

    @discardableResult
    static func writeWAV(
        from block: MixerRenderBlock,
        to url: URL,
        format: MixerWAVFormat = .pcm16,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws -> MixerWAVExportDiagnostics {
        let result = try wavExport(from: block, format: format, exportPolicy: exportPolicy)
        try result.data.write(to: url, options: [])
        return result.diagnostics
    }

    static func diagnostics(
        for block: MixerRenderBlock,
        exportPolicy: MixerWAVExportPolicy = .unity,
        wavFormat: MixerWAVFormat = .pcm16
    ) -> MixerWAVExportDiagnostics {
        var accumulator = MixerWAVExportDiagnosticsAccumulator(
            channelCount: block.config.channelCount,
            exportPolicy: exportPolicy,
            wavFormat: wavFormat
        )
        try? accumulator.append(block: block)
        return accumulator.diagnostics()
    }

    static func pcm16Sample(from sample: Float) -> Int16 {
        let finiteSample = sample.isFinite ? sample : 0
        let clamped = min(Float(1), max(Float(-1), finiteSample))
        if clamped <= -1 {
            return Int16.min
        }
        if clamped >= 1 {
            return Int16.max
        }
        return Int16((Double(clamped) * Double(Int16.max)).rounded(.toNearestOrAwayFromZero))
    }

    fileprivate static func scaledSample(_ sample: Float, gain: Float) -> Float {
        let finiteSample = sample.isFinite ? Double(sample) : 0
        let finiteGain = gain.isFinite && gain > 0 ? Double(gain) : 1
        let scaled = finiteSample * finiteGain
        guard scaled.isFinite else {
            return 0
        }
        if scaled > Double(Float.greatestFiniteMagnitude) {
            return Float.greatestFiniteMagnitude
        }
        if scaled < -Double(Float.greatestFiniteMagnitude) {
            return -Float.greatestFiniteMagnitude
        }
        return Float(scaled)
    }

    fileprivate static func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    fileprivate static func appendLE16(_ value: UInt16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
    }

    fileprivate static func appendLE32(_ value: UInt32, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
    }

    fileprivate static func appendLEInt16(_ value: Int16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
    }

}

final class MixerFloat32WAVStreamWriter {
    private let layout: MixerWAVLayout
    private let exportPolicy: MixerWAVExportPolicy
    private let fileHandle: FileHandle
    private let channelCount: Int
    private var isClosed = false
    private var writtenFrames = 0
    private var writtenSamples = 0
    private var encodedData = Data()
    private var diagnosticsAccumulator: MixerWAVExportDiagnosticsAccumulator

    init(
        config: MixerRenderConfig,
        expectedFrameCount: Int,
        url: URL,
        exportPolicy: MixerWAVExportPolicy = .unity
    ) throws {
        layout = try MixerWAVExporter.layout(
            config: config,
            frameCount: expectedFrameCount,
            format: .float32
        )
        self.exportPolicy = exportPolicy
        channelCount = Int(layout.channelCount)
        diagnosticsAccumulator = MixerWAVExportDiagnosticsAccumulator(
            channelCount: channelCount,
            exportPolicy: exportPolicy,
            wavFormat: .float32
        )

        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: url)
        var header = Data()
        header.reserveCapacity(44)
        MixerWAVExporter.appendHeader(layout: layout, format: .float32, to: &header)
        try fileHandle.write(contentsOf: header)
    }

    func write(block: MixerRenderBlock) throws {
        guard !isClosed else {
            throw MixerWAVExportError.invalidPCMShape(
                expectedSampleCount: layout.expectedSampleCount,
                actualSampleCount: writtenSamples
            )
        }
        _ = try MixerWAVExporter.validatePCMShape(block)
        let blockLayout = try MixerWAVExporter.layout(
            config: block.config,
            frameCount: block.frameCount,
            format: .float32
        )
        guard blockLayout.channelCount == layout.channelCount,
              blockLayout.sampleRate == layout.sampleRate,
              blockLayout.blockAlign == layout.blockAlign else {
            throw MixerWAVExportError.invalidPCMShape(
                expectedSampleCount: layout.expectedSampleCount,
                actualSampleCount: writtenSamples + block.interleavedPCM.count
            )
        }
        guard writtenFrames <= Int.max - block.frameCount,
              writtenFrames + block.frameCount <= layout.expectedSampleCount / channelCount else {
            throw MixerWAVExportError.fileTooLarge
        }

        let allSamplesFinite = diagnosticsAccumulator.append(samples: block.interleavedPCM)
        encodedData.removeAll(keepingCapacity: true)
        MixerWAVExporter.appendFloat32Samples(
            block.interleavedPCM,
            exportPolicy: exportPolicy,
            allSamplesFinite: allSamplesFinite,
            to: &encodedData
        )

        try fileHandle.write(contentsOf: encodedData)
        writtenFrames += block.frameCount
        writtenSamples += block.interleavedPCM.count
    }

    func finish() throws -> MixerWAVExportDiagnostics {
        defer {
            close()
        }
        guard writtenSamples == layout.expectedSampleCount else {
            throw MixerWAVExportError.invalidPCMShape(
                expectedSampleCount: layout.expectedSampleCount,
                actualSampleCount: writtenSamples
            )
        }
        return diagnosticsAccumulator.diagnostics()
    }

    func close() {
        guard !isClosed else {
            return
        }
        try? fileHandle.close()
        isClosed = true
    }
}

/// Bounded offline render request for deterministic software mixer validation.
///
/// Frame counts are sanitized to zero for invalid input and clamped to `maximumFrameCount` before
/// rendering. The default maximum is 60 seconds at 44.1 kHz so local comparison tooling cannot
/// accidentally request unbounded PCM.
struct OfflineRenderRequest: Equatable {
    static let defaultMaximumFrameCount = Int(MixerRenderConfig.defaultSampleRate) * 60

    let config: MixerRenderConfig
    let requestedFrameCount: Int
    let maximumFrameCount: Int

    var boundedFrameCount: Int {
        min(requestedFrameCount, maximumFrameCount)
    }

    var wasFrameCountBounded: Bool {
        requestedFrameCount > maximumFrameCount
    }

    init(
        config: MixerRenderConfig = MixerRenderConfig(),
        frames: Int,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.config = config
        requestedFrameCount = max(0, frames)
        self.maximumFrameCount = max(0, maximumFrameCount)
    }

    init(
        config: MixerRenderConfig = MixerRenderConfig(),
        durationSeconds: Double,
        maximumFrameCount: Int = Self.defaultMaximumFrameCount
    ) {
        self.init(
            config: config,
            frames: Self.frameCount(durationSeconds: durationSeconds, sampleRate: config.sampleRate),
            maximumFrameCount: maximumFrameCount
        )
    }

    private static func frameCount(durationSeconds: Double, sampleRate: Double) -> Int {
        guard durationSeconds.isFinite,
              durationSeconds > 0,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return 0
        }
        let frameCount = (durationSeconds * sampleRate).rounded(.down)
        guard frameCount.isFinite,
              frameCount > 0 else {
            return 0
        }
        guard frameCount < Double(Int.max) else {
            return Int.max
        }
        return Int(frameCount)
    }
}

/// Result metadata for a bounded offline software mixer render.
struct OfflineRenderResult: Equatable {
    let request: OfflineRenderRequest
    let block: MixerRenderBlock

    var requestedFrameCount: Int {
        request.requestedFrameCount
    }

    var renderedFrameCount: Int {
        block.frameCount
    }

    var maximumFrameCount: Int {
        request.maximumFrameCount
    }

    var wasFrameCountBounded: Bool {
        request.wasFrameCountBounded
    }
}

/// Pull-based software mixer behind the playback/audio boundary.
///
/// This type is independent of AppKit, `AVAudioPlayerNode`, and CoreAudio render-thread assumptions. It
/// currently renders deterministic interleaved Float32 PCM for explicitly supplied synthetic sample voices;
/// live playback now uses the CoreAudio-hosted C mixer path.
final class SoftwareMixer {
    private(set) var config: MixerRenderConfig
    private(set) var voices: [MixerVoice]

    init(config: MixerRenderConfig = MixerRenderConfig()) {
        self.config = config
        voices = []
    }

    /// Applies a complete render configuration and resets transient mixer state.
    func configure(_ config: MixerRenderConfig) {
        self.config = config
        reset()
    }

    /// Applies a new render configuration using safe deterministic defaults for invalid values.
    func configure(sampleRate: Double, channelCount: Int) {
        configure(MixerRenderConfig(sampleRate: sampleRate, channelCount: channelCount))
    }

    /// Adds one synthetic sample voice for offline rendering and returns its voice array index.
    @discardableResult
    func addVoice(
        sample: MixerSampleBuffer,
        gain: Float = 1,
        pan: Float = 0,
        step: Double = 1,
        loop: MixerSampleLoop = .none,
        channelIndex: Int = 0
    ) -> Int {
        voices.append(MixerVoice(
            channelIndex: channelIndex,
            sample: sample,
            gain: gain,
            pan: pan,
            step: step,
            loop: loop
        ))
        return voices.count - 1
    }

    /// Removes all loaded voices so subsequent renders produce silence.
    func clearVoices() {
        voices.removeAll()
    }

    /// Returns an interleaved Float32 PCM block containing exactly `frames` frames for positive requests.
    ///
    /// Non-positive frame requests are handled predictably by returning an empty block. This keeps callers
    /// safe while the mixer is still used for bounded offline experiments rather than runtime audio.
    func render(frames: Int) -> MixerRenderBlock {
        let frameCount = max(0, frames)
        let sampleCount = frameCount * config.channelCount
        var interleavedPCM = Array(repeating: Float(0), count: sampleCount)
        guard frameCount > 0,
              config.channelCount > 0,
              !voices.isEmpty else {
            return MixerRenderBlock(
                config: config,
                frameCount: frameCount,
                interleavedPCM: interleavedPCM
            )
        }

        for frameIndex in 0..<frameCount {
            let frameOffset = frameIndex * config.channelCount
            for voiceIndex in voices.indices {
                guard let monoSample = voices[voiceIndex].nextMonoSample() else {
                    continue
                }
                mix(monoSample, from: voices[voiceIndex], into: &interleavedPCM, at: frameOffset)
            }
            applyOutputScale(to: &interleavedPCM, at: frameOffset)
        }

        return MixerRenderBlock(
            config: config,
            frameCount: frameCount,
            interleavedPCM: interleavedPCM
        )
    }

    /// Rewinds loaded voices so repeated renders from the same inputs are deterministic.
    func reset() {
        for voiceIndex in voices.indices {
            voices[voiceIndex].reset()
        }
    }

    private func mix(_ monoSample: Float, from voice: MixerVoice, into interleavedPCM: inout [Float], at frameOffset: Int) {
        guard config.channelCount > 0 else {
            return
        }
        if config.channelCount == 1 {
            interleavedPCM[frameOffset] += monoSample
            return
        }

        interleavedPCM[frameOffset] += monoSample * config.panLaw.leftGain(for: voice.pan)
        interleavedPCM[frameOffset + 1] += monoSample * config.panLaw.rightGain(for: voice.pan)
    }

    private func applyOutputScale(to interleavedPCM: inout [Float], at frameOffset: Int) {
        let scale = config.outputScale
        guard scale != 1 else {
            return
        }
        for channelIndex in 0..<config.channelCount {
            interleavedPCM[frameOffset + channelIndex] *= scale
        }
    }
}

/// Offline harness for bounded deterministic renders from `SoftwareMixer`.
///
/// This renderer is independent of AppKit, `AVAudioPlayerNode`, and live playback. It exists for tests and
/// future CLI/export tooling; runtime playback stays separate from this bounded offline harness.
final class SoftwareMixerOfflineRenderer {
    private let mixer: SoftwareMixer
    let maximumFrameCount: Int

    var config: MixerRenderConfig {
        mixer.config
    }

    init(
        mixer: SoftwareMixer,
        maximumFrameCount: Int = OfflineRenderRequest.defaultMaximumFrameCount
    ) {
        self.mixer = mixer
        self.maximumFrameCount = max(0, maximumFrameCount)
    }

    convenience init(
        config: MixerRenderConfig = MixerRenderConfig(),
        maximumFrameCount: Int = OfflineRenderRequest.defaultMaximumFrameCount
    ) {
        self.init(
            mixer: SoftwareMixer(config: config),
            maximumFrameCount: maximumFrameCount
        )
    }

    /// Renders a bounded frame count using the renderer's current mixer configuration.
    func render(frames: Int) -> OfflineRenderResult {
        render(OfflineRenderRequest(
            config: mixer.config,
            frames: frames,
            maximumFrameCount: maximumFrameCount
        ))
    }

    /// Converts duration to frames with deterministic floor rounding, then renders a bounded block.
    func render(durationSeconds: Double) -> OfflineRenderResult {
        render(OfflineRenderRequest(
            config: mixer.config,
            durationSeconds: durationSeconds,
            maximumFrameCount: maximumFrameCount
        ))
    }

    /// Adds one synthetic sample voice to the underlying offline mixer.
    @discardableResult
    func addVoice(
        sample: MixerSampleBuffer,
        gain: Float = 1,
        pan: Float = 0,
        step: Double = 1,
        loop: MixerSampleLoop = .none,
        channelIndex: Int = 0
    ) -> Int {
        mixer.addVoice(
            sample: sample,
            gain: gain,
            pan: pan,
            step: step,
            loop: loop,
            channelIndex: channelIndex
        )
    }

    /// Removes all voices from the underlying offline mixer.
    func clearVoices() {
        mixer.clearVoices()
    }

    /// Renders a request after applying its configuration, clamping oversized requests to the configured maximum.
    func render(_ request: OfflineRenderRequest) -> OfflineRenderResult {
        let effectiveRequest = OfflineRenderRequest(
            config: request.config,
            frames: request.requestedFrameCount,
            maximumFrameCount: min(request.maximumFrameCount, maximumFrameCount)
        )
        if mixer.config != request.config {
            mixer.configure(request.config)
        }
        return OfflineRenderResult(
            request: effectiveRequest,
            block: mixer.render(frames: effectiveRequest.boundedFrameCount)
        )
    }

    /// Rewinds mixer state so the same request can be rendered deterministically again.
    func reset() {
        mixer.reset()
    }
}
