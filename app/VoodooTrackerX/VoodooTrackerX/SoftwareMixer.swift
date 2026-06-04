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

/// A mono Float32 PCM source owned by the deterministic software mixer.
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
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case let .invalidChannelCount(channelCount):
            return "Cannot export WAV with invalid channel count: \(channelCount)."
        case let .invalidSampleRate(sampleRate):
            return "Cannot export WAV with invalid sample rate: \(sampleRate)."
        case let .invalidPCMShape(expectedSampleCount, actualSampleCount):
            return "Cannot export WAV with \(actualSampleCount) samples; expected \(expectedSampleCount)."
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
}

struct MixerWAVExportResult: Equatable {
    let data: Data
    let diagnostics: MixerWAVExportDiagnostics
}

/// Deterministic RIFF/WAVE writer for offline mixer render blocks.
///
/// This helper is local/offline infrastructure only. It does not add a runtime playback backend,
/// change mixer DSP behavior, parse modules, or compare candidate audio against references.
enum MixerWAVExporter {
    static let bitsPerSample = MixerWAVFormat.pcm16.bitsPerSample

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
        let channelCount = block.config.channelCount
        guard channelCount > 0, channelCount <= Int(UInt16.max) else {
            throw MixerWAVExportError.invalidChannelCount(channelCount)
        }

        let roundedSampleRate = block.config.sampleRate.rounded(.toNearestOrAwayFromZero)
        guard block.config.sampleRate.isFinite,
              roundedSampleRate > 0,
              roundedSampleRate <= Double(UInt32.max) else {
            throw MixerWAVExportError.invalidSampleRate(block.config.sampleRate)
        }

        let (expectedSampleCount, sampleCountOverflow) = block.frameCount.multipliedReportingOverflow(by: channelCount)
        guard !sampleCountOverflow,
              expectedSampleCount == block.interleavedPCM.count else {
            throw MixerWAVExportError.invalidPCMShape(
                expectedSampleCount: sampleCountOverflow ? Int.max : expectedSampleCount,
                actualSampleCount: block.interleavedPCM.count
            )
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

        var data = Data()
        data.reserveCapacity(44 + dataByteCount)
        appendASCII("RIFF", to: &data)
        appendLE32(UInt32(riffChunkSize), to: &data)
        appendASCII("WAVE", to: &data)
        appendASCII("fmt ", to: &data)
        appendLE32(16, to: &data)
        appendLE16(format.wavFormatCode, to: &data)
        appendLE16(UInt16(channelCount), to: &data)
        appendLE32(sampleRate, to: &data)
        appendLE32(UInt32(byteRate), to: &data)
        appendLE16(UInt16(blockAlign), to: &data)
        appendLE16(UInt16(format.bitsPerSample), to: &data)
        appendASCII("data", to: &data)
        appendLE32(UInt32(dataByteCount), to: &data)

        for sample in block.interleavedPCM {
            let scaledSample = scaledSample(sample, gain: exportPolicy.gain)
            switch format {
            case .pcm16:
                appendLEInt16(pcm16Sample(from: scaledSample), to: &data)
            case .float32:
                appendLEFloat32(scaledSample, to: &data)
            }
        }
        return MixerWAVExportResult(
            data: data,
            diagnostics: diagnostics(for: block, exportPolicy: exportPolicy, wavFormat: format)
        )
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
        let channelCount = max(1, block.config.channelCount)
        var prePerChannelPeak = Array(repeating: Float(0), count: channelCount)
        var postPerChannelPeak = Array(repeating: Float(0), count: channelCount)
        var preSquareSum = Double(0)
        var postSquareSum = Double(0)
        var prePeak = Float(0)
        var postPeak = Float(0)
        var preOverrange = 0
        var postOverrange = 0
        var pcm16Clipping = 0

        for (sampleIndex, sample) in block.interleavedPCM.enumerated() {
            let channel = sampleIndex % channelCount
            let finiteSample = sample.isFinite ? sample : 0
            let preAbs = abs(finiteSample)
            let postSample = scaledSample(finiteSample, gain: exportPolicy.gain)
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

        let sampleCount = max(1, block.interleavedPCM.count)
        return MixerWAVExportDiagnostics(
            wavFormat: wavFormat,
            policy: exportPolicy,
            preExportPeak: prePeak,
            preExportPerChannelPeak: prePerChannelPeak,
            preExportOverrangeSampleCount: preOverrange,
            preExportRMS: Float(sqrt(preSquareSum / Double(sampleCount))),
            postGainPeak: postPeak,
            postGainPerChannelPeak: postPerChannelPeak,
            postGainOverrangeSampleCount: postOverrange,
            postGainRMS: Float(sqrt(postSquareSum / Double(sampleCount))),
            pcm16ClippingSampleCount: pcm16Clipping
        )
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

    private static func scaledSample(_ sample: Float, gain: Float) -> Float {
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

    private static func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private static func appendLE16(_ value: UInt16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
    }

    private static func appendLE32(_ value: UInt32, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
    }

    private static func appendLEInt16(_ value: Int16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
    }

    private static func appendLEFloat32(_ value: Float, to data: inout Data) {
        var littleEndianValue = value.bitPattern.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
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
