import AppKit
import Carbon.HIToolbox

/// Global keyboard shortcuts.
///
/// Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor. A
/// monitor sees every keystroke you type anywhere on the machine and needs
/// Accessibility permission to do it; a registered hot key asks the system to
/// deliver one specific combination and nothing else. For an app that also
/// listens to your microphone, being unable to read your keyboard is worth more
/// than the convenience of the modern API.
struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }

        // At least one non-shift modifier. A bare key — or Shift plus a key —
        // would swallow ordinary typing system-wide.
        guard carbon != 0, carbon != UInt32(shiftKey) else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = carbon
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    /// Names for the keys that carry no printable character, then the layout's
    /// own character for everything else — so a Dvorak or AZERTY user sees the
    /// key they actually pressed rather than the QWERTY letter in that position.
    static func keyName(_ code: UInt32) -> String {
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = named[Int(code)] { return name }
        return currentLayoutCharacter(code) ?? "Key \(code)"
    }

    private static func currentLayoutCharacter(_ code: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data

        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?
                .assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}

/// What a shortcut can do. Raw values are persisted, so they must not change.
enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
    case toggleMute
    case togglePanel
    case toggleEnforcing
    case restoreOrder
    case cycleInput
    case cycleOutput

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleMute:      return "Mute or unmute the microphone"
        case .togglePanel:     return "Show or hide Writ"
        case .toggleEnforcing: return "Pause or resume enforcing"
        case .restoreOrder:    return "Restore priority order"
        case .cycleInput:      return "Switch to the next input"
        case .cycleOutput:     return "Switch to the next output"
        }
    }

    var detail: String {
        switch self {
        case .toggleMute:      return "Works from any app, including while you're in a call"
        case .togglePanel:     return "Useful when a menu bar manager has hidden the icon"
        case .toggleEnforcing: return "Stops Writ changing devices until you resume"
        case .restoreOrder:    return "Undoes a device you picked by hand"
        case .cycleInput:      return "Steps through connected, eligible inputs"
        case .cycleOutput:     return "Steps through connected, eligible outputs"
        }
    }

    /// Defaults are deliberately sparse. Every registered shortcut is taken away
    /// from every other app on the machine, so only the two that earn it are
    /// bound out of the box; the rest are there to be assigned.
    var defaultShortcut: Shortcut? {
        switch self {
        case .toggleMute:
            return Shortcut(keyCode: UInt32(kVK_ANSI_M),
                            modifiers: UInt32(cmdKey | optionKey | controlKey))
        case .togglePanel:
            return Shortcut(keyCode: UInt32(kVK_ANSI_A),
                            modifiers: UInt32(cmdKey | optionKey | controlKey))
        default:
            return nil
        }
    }
}

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    /// nil means "assigned nothing"; absent means "never touched, use default".
    @Published private(set) var shortcuts: [HotkeyAction: Shortcut] = [:]

    private var registered: [UInt32: (action: HotkeyAction, ref: EventHotKeyRef)] = [:]
    private var handler: EventHandlerRef?
    private let defaultsKey = "hotkeys"
    private static let signature: OSType = 0x57726974   // 'Writ'

    private init() {
        load()
        installHandler()
        registerAll()
    }

    func shortcut(for action: HotkeyAction) -> Shortcut? { shortcuts[action] }

    /// Which other action already owns this combination, if any. The system
    /// silently refuses a duplicate registration, so catching it here is the
    /// difference between "that shortcut is taken" and a key that does nothing.
    func conflict(_ shortcut: Shortcut, excluding action: HotkeyAction) -> HotkeyAction? {
        shortcuts.first { $0.key != action && $0.value == shortcut }?.key
    }

    func setShortcut(_ shortcut: Shortcut?, for action: HotkeyAction) {
        if let shortcut { shortcuts[action] = shortcut } else { shortcuts.removeValue(forKey: action) }
        save()
        registerAll()
    }

    func resetToDefaults() {
        shortcuts = Dictionary(uniqueKeysWithValues:
            HotkeyAction.allCases.compactMap { action in
                action.defaultShortcut.map { (action, $0) }
            })
        save()
        registerAll()
    }

    // MARK: - Registration

    private func registerAll() {
        for (_, entry) in registered { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()

        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let shortcut = shortcuts[action] else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode, shortcut.modifiers,
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(), 0, &ref)

            // A combination already owned by macOS or another app fails here.
            // Say so in the log rather than leaving a dead key in the UI.
            guard status == noErr, let ref else {
                NSLog("Writ: could not register %@ for %@ (status %d) — probably already taken",
                      shortcut.display, action.rawValue, status)
                continue
            }
            registered[id] = (action, ref)
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            // The Carbon callback is a bare C function and cannot capture self,
            // so it hops back to the main actor and looks the action up there.
            Task { @MainActor in HotkeyManager.shared.perform(id: id.id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func perform(id: UInt32) {
        guard let action = registered[id]?.action else { return }
        let model = PriorityModel.shared

        switch action {
        case .toggleMute:      model.toggleMute(.input)
        case .togglePanel:     NotificationCenter.default.post(name: .writTogglePanel, object: nil)
        case .toggleEnforcing: model.enforcing.toggle()
        case .restoreOrder:    model.refreshDevices(); model.enforceAll(reason: "hotkey")
        case .cycleInput:      model.cycleDevice(.input)
        case .cycleOutput:     model.cycleDevice(.output)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) else {
            // First run only. After that an empty map means "the user cleared
            // them", and must not be quietly refilled with defaults.
            resetToDefaults()
            return
        }
        shortcuts = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            HotkeyAction(rawValue: key).map { ($0, value) }
        })
    }

    private func save() {
        let plain = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(plain) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

extension Notification.Name {
    /// Posted by the "Show or hide Writ" hot key. The status item controller
    /// owns the panel, so it does the work.
    static let writTogglePanel = Notification.Name("WritTogglePanel")
}
