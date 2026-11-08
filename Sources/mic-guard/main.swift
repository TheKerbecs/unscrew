// mic-guard: when the default input is a Bluetooth headset, switch it to the built-in mic.
// Using a headset's mic drops it to the low quality hands-free profile.
import Foundation
import CoreAudio

// Imported as Int32, unlike the other object IDs.
let systemObject = AudioObjectID(kAudioObjectSystemObject)

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

// Reads a fixed size property.
func value<T>(of object: AudioObjectID, _ prop: AudioObjectPropertyAddress, as: T.Type) -> T? {
    var a = prop
    let size = MemoryLayout<T>.size
    let out = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T>.alignment)
    defer { out.deallocate() }
    out.initializeMemory(as: UInt8.self, repeating: 0, count: size)
    var length = UInt32(size)
    guard AudioObjectGetPropertyData(object, &a, 0, nil, &length, out) == noErr else { return nil }
    return out.load(as: T.self)
}

func devices() -> [AudioDeviceID] {
    var a = address(kAudioHardwarePropertyDevices)
    var length = UInt32(0)
    guard AudioObjectGetPropertyDataSize(systemObject, &a, 0, nil, &length) == noErr, length > 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(length) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(systemObject, &a, 0, nil, &length, &ids) == noErr else { return [] }
    return Array(ids.prefix(Int(length) / MemoryLayout<AudioDeviceID>.size))
}

func transport(of device: AudioDeviceID) -> UInt32? {
    value(of: device, address(kAudioDevicePropertyTransportType), as: UInt32.self)
}

func isBluetooth(_ device: AudioDeviceID) -> Bool {
    let t = transport(of: device)
    return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
}

func hasInputs(_ device: AudioDeviceID) -> Bool {
    var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
    var length = UInt32(0)
    return AudioObjectGetPropertyDataSize(device, &a, 0, nil, &length) == noErr && length > 0
}

func name(of device: AudioDeviceID) -> String {
    var a = address(kAudioObjectPropertyName)
    var ref: Unmanaged<CFString>?
    var length = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &a, 0, nil, &length, &ref) == noErr,
          let cf = ref?.takeRetainedValue() else { return "device \(device)" }
    return cf as String
}

func check() {
    guard let input = value(of: systemObject,
                             address(kAudioHardwarePropertyDefaultInputDevice), as: AudioDeviceID.self),
          input != kAudioDeviceUnknown, isBluetooth(input) else { return }

    guard let mic = devices().first(where: { transport(of: $0) == kAudioDeviceTransportTypeBuiltIn && hasInputs($0) }) else {
        print("mic-guard: the default input is a Bluetooth device, but there is no built-in input to take over")
        fflush(stdout)
        return
    }

    var a = address(kAudioHardwarePropertyDefaultInputDevice)
    var id = mic
    let status = AudioObjectSetPropertyData(systemObject, &a, 0, nil,
                                           UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    if status != noErr {
        print("mic-guard: cannot set the default input (OSStatus \(status))")
    } else {
        print("input -> \(name(of: mic))")
    }
    fflush(stdout)
}

check()

// Re-check when the default input or the device list changes.
for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
    var a = address(selector)
    AudioObjectAddPropertyListenerBlock(systemObject, &a, DispatchQueue.main) { _, _ in check() }
}
RunLoop.main.run()
