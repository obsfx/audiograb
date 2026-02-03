import CoreAudio
import Foundation

struct InputDeviceInfo {
    let deviceID: AudioObjectID
    let sampleRate: Double
    let channelCount: Int
}

func getDefaultInputDevice() throws -> InputDeviceInfo {
    // Get the default input device
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID: AudioObjectID = kAudioObjectUnknown
    var size = UInt32(MemoryLayout<AudioObjectID>.stride)

    var status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
    )
    guard status == noErr, deviceID != kAudioObjectUnknown else {
        throw AudioCaptureError.ioProcFailed(status)
    }

    // Get nominal sample rate
    var rateAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var sampleRate: Double = 0
    size = UInt32(MemoryLayout<Double>.stride)
    status = AudioObjectGetPropertyData(deviceID, &rateAddress, 0, nil, &size, &sampleRate)
    guard status == noErr else {
        throw AudioCaptureError.formatQueryFailed(status)
    }

    // Get input stream format for channel count
    var formatAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamFormat,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var format = AudioStreamBasicDescription()
    size = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
    status = AudioObjectGetPropertyData(deviceID, &formatAddress, 0, nil, &size, &format)
    guard status == noErr else {
        throw AudioCaptureError.formatQueryFailed(status)
    }

    return InputDeviceInfo(
        deviceID: deviceID,
        sampleRate: sampleRate,
        channelCount: Int(format.mChannelsPerFrame)
    )
}
