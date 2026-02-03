import AudioToolbox
import CoreAudio
import Foundation

enum AudioCaptureError: Error, CustomStringConvertible {
    case permissionDenied
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case tapAssignmentFailed(OSStatus)
    case formatQueryFailed(OSStatus)
    case ioProcFailed(OSStatus)

    var description: String {
        switch self {
        case .permissionDenied:
            return "System audio recording permission denied"
        case .tapCreationFailed(let status):
            return "Failed to create audio tap (OSStatus: \(status))"
        case .aggregateDeviceCreationFailed(let status):
            return "Failed to create aggregate device (OSStatus: \(status))"
        case .tapAssignmentFailed(let status):
            return "Failed to assign tap to aggregate device (OSStatus: \(status))"
        case .formatQueryFailed(let status):
            return "Failed to query tap format (OSStatus: \(status))"
        case .ioProcFailed(let status):
            return "Failed to create/start IOProc (OSStatus: \(status))"
        }
    }
}

class AudioTapManager {
    private var tapID: AudioObjectID?
    private(set) var aggregateDeviceID: AudioObjectID?
    private(set) var tapFormat: AudioStreamBasicDescription?

    func setup(mute: Bool) throws {
        Logger.debug("Setting up audio tap")

        let tap = try createTap(mute: mute)
        tapID = tap

        tapFormat = try queryTapFormat(tapID: tap)
        Logger.debug("Tap format: \(tapFormat!.mSampleRate) Hz, \(tapFormat!.mChannelsPerFrame) ch")

        // Get tap UID for aggregate device
        let tapUID = try getTapUID(tapID: tap)

        // Create aggregate device with tap included in dictionary
        let device = try createAggregateDevice(tapUID: tapUID)
        aggregateDeviceID = device

        Logger.info("Audio tap ready")
    }

    func teardown() {
        Logger.debug("Tearing down audio tap")

        if let deviceID = aggregateDeviceID {
            AudioHardwareDestroyAggregateDevice(deviceID)
            aggregateDeviceID = nil
        }

        if let tapID = tapID {
            AudioHardwareDestroyProcessTap(tapID)
            self.tapID = nil
        }
    }

    deinit {
        teardown()
    }

    // MARK: - Private

    private func createTap(mute: Bool) throws -> AudioObjectID {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "audiograb-tap"
        description.uuid = UUID()
        description.isPrivate = true
        description.isMixdown = true

        if mute {
            description.muteBehavior = .mutedWhenTapped
        } else {
            description.muteBehavior = .unmuted
        }

        var tapObjectID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapObjectID)

        if status == kAudioHardwareBadObjectError || status == OSStatus(kAudioHardwareNotRunningError) {
            throw AudioCaptureError.permissionDenied
        }

        guard status == kAudioHardwareNoError else {
            throw AudioCaptureError.tapCreationFailed(status)
        }

        Logger.debug("Tap created: \(tapObjectID)")
        return tapObjectID
    }

    private func queryTapFormat(tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        var format = AudioStreamBasicDescription()

        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr else {
            throw AudioCaptureError.formatQueryFailed(status)
        }
        return format
    }

    private func getTapUID(tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.stride)
        var tapUID: CFString = "" as CFString

        let status = withUnsafeMutablePointer(to: &tapUID) { ptr in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else {
            throw AudioCaptureError.tapAssignmentFailed(status)
        }

        return tapUID as String
    }

    private func createAggregateDevice(tapUID: String) throws -> AudioObjectID {
        let uid = UUID().uuidString

        // Include tap in the aggregate device dictionary at creation time
        let tapEntry: [String: Any] = [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: false,
        ]

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "audiograb-device",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [tapEntry],
            kAudioAggregateDeviceTapAutoStartKey: false,
        ]

        var deviceID: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)

        guard status == kAudioHardwareNoError else {
            throw AudioCaptureError.aggregateDeviceCreationFailed(status)
        }

        Logger.debug("Aggregate device created: \(deviceID)")
        return deviceID
    }
}
