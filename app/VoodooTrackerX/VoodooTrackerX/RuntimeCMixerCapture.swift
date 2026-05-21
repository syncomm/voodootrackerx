import Foundation

struct RuntimeCMixerCaptureConfiguration: Equatable {
    static let pathEnvironmentKey = "VTX_C_MIXER_RUNTIME_CAPTURE_PATH"
    static let secondsEnvironmentKey = "VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS"
    static let defaultCaptureSeconds = 240.0
    static let maximumCaptureSeconds = 240.0

    let url: URL
    let pathName: String
    let seconds: Double
    let secondsPolicy: String
    let configurationWarning: String?

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RuntimeCMixerCaptureConfiguration? {
        guard !RuntimeCMixerDiagnosticEnvironment.flagEnabled(
            RuntimeCMixerDiagnosticEnvironment.disableCaptureEnvironmentKey,
            environment: environment
        ) else {
            return nil
        }
        guard let rawPath = trimmedEnvironmentValue(environment[pathEnvironmentKey]) else {
            return nil
        }
        let url = URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath)
        let pathName = url.lastPathComponent.isEmpty ? "runtime-c-mixer-capture.wav" : url.lastPathComponent
        let rawSeconds = trimmedEnvironmentValue(environment[secondsEnvironmentKey])
        let secondsResult = seconds(from: rawSeconds)
        return RuntimeCMixerCaptureConfiguration(
            url: url,
            pathName: pathName,
            seconds: secondsResult.seconds,
            secondsPolicy: secondsResult.policy,
            configurationWarning: secondsResult.warning
        )
    }

    func frameLimit(sampleRate: Double) -> Int {
        let safeSampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : MixerRenderConfig.defaultSampleRate
        let frames = (safeSampleRate * seconds).rounded(.up)
        guard frames.isFinite,
              frames > 0,
              frames <= Double(Int.max) else {
            return Int.max
        }
        return max(1, Int(frames))
    }

    private static func seconds(from rawValue: String?) -> (seconds: Double, policy: String, warning: String?) {
        guard let rawValue else {
            return (defaultCaptureSeconds, "default_runtime_capture_seconds", nil)
        }
        guard let parsed = Double(rawValue),
              parsed.isFinite,
              parsed > 0 else {
            return (defaultCaptureSeconds, "default_runtime_capture_seconds_fallback", "invalid_runtime_capture_seconds")
        }
        guard parsed <= maximumCaptureSeconds else {
            return (maximumCaptureSeconds, "max_runtime_capture_seconds_fallback", "runtime_capture_seconds_capped")
        }
        return (parsed, "env_runtime_capture_seconds", nil)
    }

    private static func trimmedEnvironmentValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct RuntimeCMixerCaptureSnapshot: Equatable {
    let enabled: Bool
    let pathName: String?
    let sampleRate: Double?
    let channelCount: Int?
    let seconds: Double?
    let frameLimit: Int?
    let capturedFrameCount: Int
    let truncated: Bool
    let outputPeak: Float
    let outputRMS: Float
    let overrangeSampleCount: UInt64
    let clippingSampleCount: UInt64
    let configurationWarning: String?

    var durationSeconds: Double? {
        guard let sampleRate,
              sampleRate > 0 else {
            return nil
        }
        return Double(capturedFrameCount) / sampleRate
    }

    static let disabled = RuntimeCMixerCaptureSnapshot(
        enabled: false,
        pathName: nil,
        sampleRate: nil,
        channelCount: nil,
        seconds: nil,
        frameLimit: nil,
        capturedFrameCount: 0,
        truncated: false,
        outputPeak: 0,
        outputRMS: 0,
        overrangeSampleCount: 0,
        clippingSampleCount: 0,
        configurationWarning: nil
    )
}

struct RuntimeCMixerCaptureBlockSnapshot: Equatable {
    let configuration: RuntimeCMixerCaptureConfiguration
    let snapshot: RuntimeCMixerCaptureSnapshot
    let block: MixerRenderBlock
}

final class RuntimeCMixerCaptureBuffer {
    let configuration: RuntimeCMixerCaptureConfiguration
    let config: MixerRenderConfig
    let frameLimit: Int

    private var interleavedPCM: [Float]
    private var capturedFrameCount = 0
    private var truncated = false
    private var outputPeak = Float(0)
    private var outputSquareSum = Double(0)
    private var capturedSampleCount: UInt64 = 0
    private var overrangeSampleCount: UInt64 = 0
    private var clippingSampleCount: UInt64 = 0

    init(configuration: RuntimeCMixerCaptureConfiguration, config: MixerRenderConfig) {
        self.configuration = configuration
        self.config = config
        frameLimit = configuration.frameLimit(sampleRate: config.sampleRate)
        let channelCount = max(1, config.channelCount)
        let sampleCount = frameLimit.multipliedReportingOverflow(by: channelCount)
        interleavedPCM = Array(repeating: 0, count: sampleCount.overflow ? 0 : max(0, sampleCount.partialValue))
    }

    var snapshot: RuntimeCMixerCaptureSnapshot {
        let rms = capturedSampleCount > 0
            ? Float(sqrt(outputSquareSum / Double(capturedSampleCount)))
            : 0
        return RuntimeCMixerCaptureSnapshot(
            enabled: true,
            pathName: configuration.pathName,
            sampleRate: config.sampleRate,
            channelCount: config.channelCount,
            seconds: configuration.seconds,
            frameLimit: frameLimit,
            capturedFrameCount: capturedFrameCount,
            truncated: truncated,
            outputPeak: outputPeak,
            outputRMS: rms,
            overrangeSampleCount: overrangeSampleCount,
            clippingSampleCount: clippingSampleCount,
            configurationWarning: configuration.configurationWarning
        )
    }

    @discardableResult
    func capture(
        _ outputInterleavedPCM: UnsafeMutableBufferPointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) -> RuntimeCMixerSampleSummary? {
        let safeChannelCount = max(1, channelCount)
        let availableFrames = outputInterleavedPCM.count / safeChannelCount
        let requestedFrames = min(max(0, frameCount), availableFrames)
        guard requestedFrames > 0 else {
            return nil
        }
        guard !truncated,
              capturedFrameCount < frameLimit,
              !interleavedPCM.isEmpty else {
            truncated = true
            return nil
        }

        let remainingFrames = max(0, frameLimit - capturedFrameCount)
        let framesToCopy = min(requestedFrames, remainingFrames)
        let samplesToCopy = framesToCopy * safeChannelCount
        let destinationStart = capturedFrameCount * safeChannelCount
        guard samplesToCopy > 0,
              destinationStart >= 0,
              destinationStart + samplesToCopy <= interleavedPCM.count else {
            truncated = true
            return nil
        }

        var checksum = RuntimeCMixerSampleSummary.empty.checksum
        var segmentPeak = Float(0)
        var segmentSquareSum = Double(0)
        for sampleIndex in 0..<samplesToCopy {
            let sample = outputInterleavedPCM[sampleIndex].isFinite ? outputInterleavedPCM[sampleIndex] : 0
            interleavedPCM[destinationStart + sampleIndex] = sample
            checksum = RuntimeCMixerSampleSummary.hash(checksum, sample: sample)
            let absolute = abs(sample)
            segmentPeak = max(segmentPeak, absolute)
            segmentSquareSum += Double(sample) * Double(sample)
            outputPeak = max(outputPeak, absolute)
            outputSquareSum += Double(sample) * Double(sample)
            capturedSampleCount &+= 1
            if absolute > 1 {
                overrangeSampleCount &+= 1
            }
            if absolute >= 1 {
                clippingSampleCount &+= 1
            }
        }

        capturedFrameCount += framesToCopy
        if framesToCopy < requestedFrames || capturedFrameCount >= frameLimit {
            truncated = true
        }
        let rms = samplesToCopy > 0
            ? Float(sqrt(segmentSquareSum / Double(samplesToCopy)))
            : 0
        return RuntimeCMixerSampleSummary(
            frameCount: framesToCopy,
            channelCount: safeChannelCount,
            sampleCount: samplesToCopy,
            finiteSampleCount: samplesToCopy,
            checksum: checksum,
            peak: segmentPeak,
            rms: rms
        )
    }

    func blockSnapshot() -> RuntimeCMixerCaptureBlockSnapshot? {
        let sampleCount = capturedFrameCount * max(1, config.channelCount)
        guard sampleCount <= interleavedPCM.count else {
            return nil
        }
        return RuntimeCMixerCaptureBlockSnapshot(
            configuration: configuration,
            snapshot: snapshot,
            block: MixerRenderBlock(
                config: config,
                frameCount: capturedFrameCount,
                interleavedPCM: Array(interleavedPCM.prefix(sampleCount))
            )
        )
    }

    func reset() {
        capturedFrameCount = 0
        truncated = false
        outputPeak = 0
        outputSquareSum = 0
        capturedSampleCount = 0
        overrangeSampleCount = 0
        clippingSampleCount = 0
    }
}

enum RuntimeCMixerCaptureWAVWriter {
    @discardableResult
    static func write(_ capture: RuntimeCMixerCaptureBlockSnapshot) throws -> MixerWAVExportDiagnostics {
        try FileManager.default.createDirectory(
            at: capture.configuration.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try MixerWAVExporter.writePCM16WAV(from: capture.block, to: capture.configuration.url)
    }
}
