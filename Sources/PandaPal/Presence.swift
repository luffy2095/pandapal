import CoreAudio
import CoreMediaIO
import IOKit.pwr_mgt

/// What macOS reports about calls and videos. Each answer is only on or off: no permission, and nothing about
/// who you talk to or what you watch.
enum Presence {
    /// Some app is recording from a microphone or using a camera: you are probably on a call.
    static func inCall() -> Bool { recordingAudio() || cameraOn() }

    /// Some app keeps the display awake, as video players and presentations do.
    static func displayKeptAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let levels = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (levels["PreventUserIdleDisplaySleep"] ?? 0) > 0           // kIOPMAssertPreventUserIdleDisplaySleep
    }

    /// Cheap first: a running microphone-only device means someone records. Only when a headset (microphone and
    /// speaker in one) is running, for music or a call, ask each process, which costs more (1.4 ms, measured).
    private static func recordingAudio() -> Bool {
        var headsetBusy = false
        for device in audioObjects(kAudioHardwarePropertyDevices) where streams(device, kAudioObjectPropertyScopeInput) {
            guard flag(device, kAudioDevicePropertyDeviceIsRunningSomewhere) else { continue }
            if !streams(device, kAudioObjectPropertyScopeOutput) { return true }
            headsetBusy = true
        }
        return headsetBusy && audioObjects(kAudioHardwarePropertyProcessObjectList).contains { flag($0, kAudioProcessPropertyIsRunningInput) }
    }

    private static func audioObjects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        return AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr ? ids : []
    }

    private static func streams(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func cameraOn() -> Bool {
        var list = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &list, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &list, 0, nil, size, &used, &devices) == 0 else { return false }
        var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        return devices.contains { device in
            var on: UInt32 = 0
            var got: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &on) == 0 && on != 0
        }
    }
}
