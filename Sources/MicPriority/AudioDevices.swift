import CoreAudio
import Foundation

enum Direction: String, Codable, CaseIterable, Identifiable {
    case input, output
    var id: String { rawValue }

    var scope: AudioObjectPropertyScope {
        self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    }
    var defaultSelector: AudioObjectPropertySelector {
        self == .input ? kAudioHardwarePropertyDefaultInputDevice
                       : kAudioHardwarePropertyDefaultOutputDevice
    }
    var label: String { self == .input ? "Microphone" : "Output" }
}

enum DeviceKind {
    case usb, bluetooth, airplay, builtIn, display, other

    /// Matches the device iconography Apple uses in the Control Center Sound
    /// menu, so the list reads the same way theirs does.
    func symbolName(_ direction: Direction) -> String {
        switch self {
        case .display:   return "display"
        case .bluetooth: return "headphones"
        case .airplay:   return "airplayaudio"
        case .builtIn:   return "laptopcomputer"
        case .usb:       return direction == .input ? "mic" : "hifispeaker"
        case .other:     return direction == .input ? "mic" : "speaker.wave.2"
        }
    }

    /// Lower sorts higher. New devices are seeded at the rank their CLASS
    /// deserves rather than in CoreAudio's arbitrary enumeration order —
    /// otherwise a device discovered later lands last regardless of what it is,
    /// which is how AirPods ended up outranking a dedicated USB mic.
    func rank(_ direction: Direction) -> Int {
        switch direction {
        case .input:
            // A dedicated mic always beats a headset; Bluetooth last.
            switch self {
            case .usb: return 0
            case .other: return 1
            case .builtIn: return 2
            case .bluetooth: return 3
            case .airplay: return 4
            case .display: return 5
            }
        case .output:
            // Headphones you deliberately put on should win; monitors never.
            switch self {
            case .bluetooth: return 0
            case .airplay: return 1
            case .builtIn: return 2
            case .usb: return 3
            case .other: return 4
            case .display: return 5
            }
        }
    }
}

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let kind: DeviceKind

    /// Monitor/TV audio over DisplayPort or HDMI — the class of device that
    /// hijacks output the moment a display connects.
    var isDisplayAudio: Bool { kind == .display }
}

enum Audio {

    /// macOS spawns a private "CADefaultDeviceAggregate-<pid>-<n>" device
    /// whenever an app taps the default input — including our own level meter.
    /// It is plumbing, never something you can choose, and it must be rejected
    /// both when enumerating AND when loading remembered devices, or old ones
    /// linger in the saved list forever.
    static func isSystemArtifact(uid: String, name: String) -> Bool {
        if uid.hasPrefix("CADefaultDeviceAggregate") || name.hasPrefix("CADefaultDeviceAggregate") {
            return true
        }
        return false
    }

    /// macOS names every AirPlay target the bare string "AirPlay" and drops the
    /// device object when the session ends. Such an entry is only meaningful
    /// while it is actually playing — that is when you can tell which speaker it
    /// is — so it is shown live and discarded afterwards unless you've labelled
    /// it, at which point it becomes yours and is kept.
    static func isAnonymousAirPlay(name: String) -> Bool {
        name == "AirPlay"
    }

    /// AirPlay UIDs look like
    ///   cb56dc98-8819-425c-a21d-6b9ca8bb805a-2926033793250-Audio
    /// where the leading UUID identifies the speaker and the trailing digits are
    /// per-session. Keying on the whole string meant a reconnected HomePod read
    /// as a brand-new device, so your label — and its rank — were lost every
    /// time, and the enforcer bounced you back to the laptop speakers.
    static func stableUID(_ uid: String, name: String) -> String {
        guard isAnonymousAirPlay(name: name) else { return uid }
        let parts = uid.split(separator: "-")
        guard parts.count >= 5 else { return uid }
        let candidate = parts.prefix(5).joined(separator: "-")
        return UUID(uuidString: candidate) != nil ? candidate : uid
    }

    // MARK: - Reading

    static func devices(_ direction: Direction) -> [AudioDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasChannels(id, direction.scope) else { return nil }
            guard let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            guard !isSystemArtifact(uid: uid, name: name), !isHidden(id) else { return nil }
            return AudioDevice(id: id, uid: stableUID(uid, name: name), name: name, kind: kind(id))
        }
    }

    static func current(_ direction: Direction) -> AudioDevice? {
        var addr = AudioObjectPropertyAddress(
            mSelector: direction.defaultSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        return devices(direction).first { $0.id == id }
    }

    // MARK: - Writing

    @discardableResult
    static func setCurrent(_ device: AudioDevice, _ direction: Direction) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: direction.defaultSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = device.id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &id) == noErr
    }

    // MARK: - Volume

    /// Master scalar volume, falling back to the average of the first two
    /// channels for devices that expose no master element (most USB gear).
    static func volume(_ device: AudioDevice, _ direction: Direction) -> Float? {
        if let v = volume(device.id, direction.scope, element: kAudioObjectPropertyElementMain) { return v }
        let l = volume(device.id, direction.scope, element: 1)
        let r = volume(device.id, direction.scope, element: 2)
        guard let l else { return nil }
        return r.map { (l + $0) / 2 } ?? l
    }

    @discardableResult
    static func setVolume(_ value: Float, _ device: AudioDevice, _ direction: Direction) -> Bool {
        var ok = setVolume(value, device.id, direction.scope, element: kAudioObjectPropertyElementMain)
        if !ok {
            let l = setVolume(value, device.id, direction.scope, element: 1)
            let r = setVolume(value, device.id, direction.scope, element: 2)
            ok = l || r
        }
        return ok
    }

    private static func volume(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope,
                               element: AudioObjectPropertyElement) -> Float? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func setVolume(_ value: Float, _ id: AudioDeviceID, _ scope: AudioObjectPropertyScope,
                                  element: AudioObjectPropertyElement) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { return false }
        var v = Float32(max(0, min(1, value)))
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    // MARK: - Mute

    static func isMuted(_ device: AudioDevice, _ direction: Direction) -> Bool? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute, mScope: direction.scope,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device.id, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device.id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool, _ device: AudioDevice, _ direction: Direction) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute, mScope: direction.scope,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device.id, &addr) else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device.id, &addr, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    // MARK: - Change notification

    static func addChangeListener(_ handler: @escaping () -> Void) {
        for selector in [kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultInputDevice,
                         kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { _, _ in
                    handler()
                }
        }
    }

    // MARK: - Helpers

    private static func isHidden(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIsHidden,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private static func kind(_ id: AudioDeviceID) -> DeviceKind {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport) == noErr else { return .other }

        switch transport {
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return .display
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        // AirPlay targets only become CoreAudio devices once macOS has actually
        // connected to one; before that they exist only to the system's own
        // Sound UI. Nothing here can conjure them early.
        case kAudioDeviceTransportTypeAirPlay: return .airplay
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        default: return .other
        }
    }

    private static func hasChannels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }

        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return false }

        let list = buf.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).contains { $0.mNumberChannels > 0 }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // CoreAudio hands back a +1 CFStringRef, so take it unmanaged rather
        // than pointing raw memory at a Swift CFString variable.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
