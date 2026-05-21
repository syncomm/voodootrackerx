import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

struct RuntimeCMixerAudioOutputDeviceDiagnostics: Equatable {
    let deviceID: AudioObjectID?
    let deviceUIDHash: String?
    let nominalSampleRate: Double?
    let ioBufferFrameSize: UInt32?
    let latencyFrames: UInt32?
    let safetyOffsetFrames: UInt32?
    let transportType: UInt32?
    let transportTypeName: String?

    var ioBufferDuration: Double? {
        guard let nominalSampleRate,
              nominalSampleRate > 0,
              let ioBufferFrameSize else {
            return nil
        }
        return Double(ioBufferFrameSize) / nominalSampleRate
    }

    var latencyDuration: Double? {
        duration(frames: latencyFrames)
    }

    var safetyOffsetDuration: Double? {
        duration(frames: safetyOffsetFrames)
    }

    static func currentDefaultOutputDevice() -> RuntimeCMixerAudioOutputDeviceDiagnostics {
        guard let deviceID = defaultOutputDeviceID() else {
            return RuntimeCMixerAudioOutputDeviceDiagnostics(
                deviceID: nil,
                deviceUIDHash: nil,
                nominalSampleRate: nil,
                ioBufferFrameSize: nil,
                latencyFrames: nil,
                safetyOffsetFrames: nil,
                transportType: nil,
                transportTypeName: nil
            )
        }
        let transportType = uint32Property(for: deviceID, selector: kAudioDevicePropertyTransportType)
        return RuntimeCMixerAudioOutputDeviceDiagnostics(
            deviceID: deviceID,
            deviceUIDHash: deviceUIDHash(for: deviceID),
            nominalSampleRate: nominalSampleRate(for: deviceID),
            ioBufferFrameSize: ioBufferFrameSize(for: deviceID),
            latencyFrames: uint32Property(for: deviceID, selector: kAudioDevicePropertyLatency),
            safetyOffsetFrames: uint32Property(for: deviceID, selector: kAudioDevicePropertySafetyOffset),
            transportType: transportType,
            transportTypeName: RuntimeCMixerDeviceIdentityRedactor.transportTypeName(for: transportType)
        )
    }

    private func duration(frames: UInt32?) -> Double? {
        guard let nominalSampleRate,
              nominalSampleRate > 0,
              let frames else {
            return nil
        }
        return Double(frames) / nominalSampleRate
    }

    private static func defaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr,
              deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }
        return deviceID
    }

    private static func nominalSampleRate(for deviceID: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        guard status == noErr,
              sampleRate.isFinite,
              sampleRate > 0 else {
            return nil
        }
        return Double(sampleRate)
    }

    private static func ioBufferFrameSize(for deviceID: AudioObjectID) -> UInt32? {
        uint32Property(for: deviceID, selector: kAudioDevicePropertyBufferFrameSize)
    }

    private static func uint32Property(for deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr,
              value > 0 else {
            return nil
        }
        return value
    }

    private static func deviceUIDHash(for deviceID: AudioObjectID) -> String? {
        RuntimeCMixerDeviceIdentityRedactor.hashedStableID(
            stringProperty(for: deviceID, selector: kAudioDevicePropertyDeviceUID)
        )
    }

    private static func stringProperty(for deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            return nil
        }
        guard let string = value?.takeUnretainedValue() as String?,
              !string.isEmpty else {
            return nil
        }
        return string
    }

}

struct RuntimeCMixerAudioGraphDiagnostics: Equatable {
    let routeLabel: String?
    let cMixerRenderSampleRate: Double
    let cMixerRenderChannelCount: Int
    let sourceNodeRenderSampleRate: Double
    let sourceNodeChannelCount: Int
    let mainMixerOutputSampleRate: Double
    let mainMixerOutputChannelCount: Int
    let mainMixerInputSampleRate: Double
    let mainMixerInputChannelCount: Int
    let mainMixerLatency: Double
    let mainMixerOutputPresentationLatency: Double
    let outputNodeSampleRate: Double
    let outputNodeChannelCount: Int
    let outputNodeLatency: Double
    let outputNodeOutputPresentationLatency: Double
    let outputDeviceID: AudioObjectID?
    let outputDeviceUIDHash: String?
    let hardwareNominalSampleRate: Double?
    let hardwareIOBufferFrameSize: UInt32?
    let hardwareIOBufferDuration: Double?
    let hardwareLatencyFrames: UInt32?
    let hardwareLatencyDuration: Double?
    let hardwareSafetyOffsetFrames: UInt32?
    let hardwareSafetyOffsetDuration: Double?
    let hardwareTransportType: UInt32?
    let hardwareTransportTypeName: String?
    let engineRunning: Bool
    let sourceNodeAttached: Bool
    let sourceNodeConnected: Bool
    let mainMixerConnectedToOutput: Bool
    let formatConversionLikely: Bool
    let captureMatchesSourceNodeFormat: Bool?
    let captureMatchesEngineOutputFormat: Bool?
    let captureMatchesHardwareSampleRate: Bool?

    init(
        snapshot: RuntimeCMixerRenderSnapshot,
        routeLabel: String?,
        sourceFormat: AVAudioFormat,
        mainMixerInputFormat: AVAudioFormat,
        mainMixerOutputFormat: AVAudioFormat,
        outputNodeFormat: AVAudioFormat,
        outputDevice: RuntimeCMixerAudioOutputDeviceDiagnostics,
        engineRunning: Bool,
        sourceNodeAttached: Bool,
        sourceNodeConnected: Bool,
        mainMixerConnectedToOutput: Bool,
        mainMixerLatency: Double,
        mainMixerOutputPresentationLatency: Double,
        outputNodeLatency: Double,
        outputNodeOutputPresentationLatency: Double,
        engineRunningOverride: Bool? = nil,
        sourceNodeAttachedOverride: Bool? = nil,
        sourceNodeConnectedOverride: Bool? = nil,
        mainMixerConnectedToOutputOverride: Bool? = nil,
        formatConversionLikelyOverride: Bool? = nil
    ) {
        self.routeLabel = routeLabel
        cMixerRenderSampleRate = snapshot.sampleRate
        cMixerRenderChannelCount = snapshot.channelCount
        sourceNodeRenderSampleRate = sourceFormat.sampleRate
        sourceNodeChannelCount = Int(sourceFormat.channelCount)
        mainMixerOutputSampleRate = mainMixerOutputFormat.sampleRate
        mainMixerOutputChannelCount = Int(mainMixerOutputFormat.channelCount)
        mainMixerInputSampleRate = mainMixerInputFormat.sampleRate
        mainMixerInputChannelCount = Int(mainMixerInputFormat.channelCount)
        self.mainMixerLatency = mainMixerLatency
        self.mainMixerOutputPresentationLatency = mainMixerOutputPresentationLatency
        outputNodeSampleRate = outputNodeFormat.sampleRate
        outputNodeChannelCount = Int(outputNodeFormat.channelCount)
        self.outputNodeLatency = outputNodeLatency
        self.outputNodeOutputPresentationLatency = outputNodeOutputPresentationLatency
        outputDeviceID = outputDevice.deviceID
        outputDeviceUIDHash = outputDevice.deviceUIDHash
        hardwareNominalSampleRate = outputDevice.nominalSampleRate
        hardwareIOBufferFrameSize = outputDevice.ioBufferFrameSize
        hardwareIOBufferDuration = outputDevice.ioBufferDuration
        hardwareLatencyFrames = outputDevice.latencyFrames
        hardwareLatencyDuration = outputDevice.latencyDuration
        hardwareSafetyOffsetFrames = outputDevice.safetyOffsetFrames
        hardwareSafetyOffsetDuration = outputDevice.safetyOffsetDuration
        hardwareTransportType = outputDevice.transportType
        hardwareTransportTypeName = outputDevice.transportTypeName
        self.engineRunning = engineRunningOverride ?? engineRunning
        self.sourceNodeAttached = sourceNodeAttachedOverride ?? sourceNodeAttached
        self.sourceNodeConnected = sourceNodeConnectedOverride ?? sourceNodeConnected
        self.mainMixerConnectedToOutput = mainMixerConnectedToOutputOverride ?? mainMixerConnectedToOutput
        formatConversionLikely = formatConversionLikelyOverride ?? RuntimeCMixerFormatDiagnostics.formatConversionLikely(
            sourceSampleRate: sourceNodeRenderSampleRate,
            sourceChannelCount: sourceNodeChannelCount,
            mainMixerSampleRate: mainMixerOutputSampleRate,
            mainMixerChannelCount: mainMixerOutputChannelCount,
            outputSampleRate: outputNodeSampleRate,
            outputChannelCount: outputNodeChannelCount,
            hardwareSampleRate: hardwareNominalSampleRate
        )
        captureMatchesSourceNodeFormat = Self.captureMatches(
            capture: snapshot.capture,
            sampleRate: sourceNodeRenderSampleRate,
            channelCount: sourceNodeChannelCount
        )
        captureMatchesEngineOutputFormat = Self.captureMatches(
            capture: snapshot.capture,
            sampleRate: outputNodeSampleRate,
            channelCount: outputNodeChannelCount
        )
        captureMatchesHardwareSampleRate = RuntimeCMixerFormatDiagnostics.sampleRatesMatch(
            snapshot.capture.sampleRate,
            hardwareNominalSampleRate
        )
    }

    var formatSignature: [String] {
        [
            "\(cMixerRenderSampleRate)",
            "\(cMixerRenderChannelCount)",
            "\(sourceNodeRenderSampleRate)",
            "\(sourceNodeChannelCount)",
            "\(mainMixerInputSampleRate)",
            "\(mainMixerInputChannelCount)",
            "\(mainMixerOutputSampleRate)",
            "\(mainMixerOutputChannelCount)",
            "\(outputNodeSampleRate)",
            "\(outputNodeChannelCount)",
            "\(hardwareNominalSampleRate ?? -1)"
        ]
    }

    var routeSignature: [String] {
        [
            routeLabel ?? "unlabeled",
            outputDeviceUIDHash ?? "unknown",
            "\(outputDeviceID ?? 0)",
            "\(hardwareNominalSampleRate ?? -1)",
            "\(hardwareIOBufferFrameSize ?? 0)",
            "\(hardwareLatencyFrames ?? 0)",
            "\(hardwareSafetyOffsetFrames ?? 0)",
            "\(hardwareTransportType ?? 0)"
        ]
    }

    var outputDeviceIdentitySignature: [String] {
        [
            outputDeviceUIDHash ?? "unknown",
            "\(outputDeviceID ?? 0)",
            "\(hardwareTransportType ?? 0)"
        ]
    }

    var outputNodeFormatSignature: [String] {
        [
            "\(outputNodeSampleRate)",
            "\(outputNodeChannelCount)"
        ]
    }

    private static func captureMatches(
        capture: RuntimeCMixerCaptureSnapshot,
        sampleRate: Double,
        channelCount: Int
    ) -> Bool? {
        guard capture.enabled,
              let captureSampleRate = capture.sampleRate,
              let captureChannelCount = capture.channelCount else {
            return nil
        }
        return RuntimeCMixerFormatDiagnostics.sampleRatesMatch(captureSampleRate, sampleRate) &&
            captureChannelCount == channelCount
    }
}

struct RuntimeCMixerAudioGraphChanges: Equatable {
    let formatChanged: Bool
    let routeChanged: Bool
    let outputDeviceChanged: Bool
    let outputSampleRateChanged: Bool
    let outputChannelCountChanged: Bool
    let hardwareIOBufferDurationChanged: Bool
    let outputNodeFormatChanged: Bool

    static let none = RuntimeCMixerAudioGraphChanges(
        formatChanged: false,
        routeChanged: false,
        outputDeviceChanged: false,
        outputSampleRateChanged: false,
        outputChannelCountChanged: false,
        hardwareIOBufferDurationChanged: false,
        outputNodeFormatChanged: false
    )
}
