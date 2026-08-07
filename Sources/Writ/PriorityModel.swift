import Combine
import Foundation
import ServiceManagement
import SwiftUI   // for move(fromOffsets:toOffset:)

/// One remembered device, in priority order. Devices are remembered by UID even
/// while disconnected, so unplugging something doesn't lose its rank.
struct PriorityEntry: Codable, Identifiable, Hashable {
    var uid: String
    var name: String
    /// Skip while the lid is shut. Set on the built-in mic, which is
    /// hardware-disconnected in clamshell and would capture silence.
    var requiresLidOpen: Bool = false
    /// Never auto-select this device.
    var ignored: Bool = false
    /// Class rank at the time this device was first seen. Kept so a device that
    /// is currently disconnected (and therefore exposes no transport type) can
    /// still be compared when placing a newly-discovered device.
    var seedRank: Int = 1
    /// Icon captured when first seen, so disconnected devices still show the
    /// right glyph. Optional so lists saved by earlier builds still decode.
    var symbolName: String?
    /// Your glyph choice, which always wins over the class default.
    var customSymbol: String?
    /// Your label — the only way to tell two "AirPlay" devices apart.
    var customName: String?
    /// True for devices macOS exposes anonymously and transiently (AirPlay).
    var ephemeral: Bool?

    var id: String { uid }

    var displayName: String { customName ?? name }
    /// An unlabelled ephemeral device is disposable; a labelled one is yours.
    var isDisposable: Bool { (ephemeral ?? false) && customName == nil && customSymbol == nil }
}

/// Mutable per-direction state. Kept inside the single ObservableObject rather
/// than as nested observables, because nested ObservableObjects don't propagate
/// change notifications to SwiftUI on their own.
private struct DirectionState {
    var entries: [PriorityEntry] = []
    var connected: [AudioDevice] = []
    var currentName: String = "—"
    var currentUID: String = ""
    var lastSignature = ""
    var lastAction = ""
}

@MainActor
final class PriorityModel: ObservableObject {

    static let shared = PriorityModel()

    @Published private(set) var lidClosed: Bool = false
    @Published var enforcing: Bool = true { didSet { saveSettings(); enforceAll(reason: "toggled") } }
    @Published var showing: Direction = .input

    @Published private var state: [Direction: DirectionState] = [
        .input: DirectionState(), .output: DirectionState()
    ]

    private let entriesKey = "priorityEntries"     // + "." + direction
    private let enforcingKey = "enforcing"
    private var lidTimer: Timer?

    init() {
        load()
        refreshDevices()

        Audio.addChangeListener { [weak self] in
            Task { @MainActor in self?.somethingChanged() }
        }

        // The lid emits no CoreAudio event, so poll it. Cheap: one IORegistry read.
        lidTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.somethingChanged() }
        }

        enforceAll(reason: "launch")
    }

    // MARK: - Accessors

    func entries(_ d: Direction) -> [PriorityEntry] { state[d]?.entries ?? [] }
    /// Prefers your label over the system name, so a renamed AirPlay speaker
    /// reads as "Kitchen HomePod" rather than the generic "AirPlay".
    func currentName(_ d: Direction) -> String {
        guard let s = state[d] else { return "—" }
        if let entry = s.entries.first(where: { $0.uid == s.currentUID }) {
            return entry.displayName
        }
        return s.currentName
    }

    func currentUID(_ d: Direction) -> String { state[d]?.currentUID ?? "" }

    func currentIsAnonymousAirPlay(_ d: Direction) -> Bool {
        guard let s = state[d] else { return false }
        guard let entry = s.entries.first(where: { $0.uid == s.currentUID }) else {
            return Audio.isAnonymousAirPlay(name: s.currentName)
        }
        return Audio.isAnonymousAirPlay(name: entry.name) && entry.customName == nil
    }
    func lastAction(_ d: Direction) -> String { state[d]?.lastAction ?? "" }
    func isConnected(_ entry: PriorityEntry, _ d: Direction) -> Bool {
        state[d]?.connected.contains { $0.uid == entry.uid } ?? false
    }

    /// The device actually in use — matched by UID, not by name, so a renamed
    /// device still resolves. Distinct from `winner`, which is only what the
    /// ranking WOULD choose; the two legitimately differ whenever something is
    /// left alone (AirPlay) or you've picked a device by hand.
    func isCurrent(_ entry: PriorityEntry, _ d: Direction) -> Bool {
        guard let s = state[d], !s.currentUID.isEmpty else { return false }
        return s.currentUID == entry.uid
    }

    func isAnonymousAirPlay(_ entry: PriorityEntry) -> Bool {
        Audio.isAnonymousAirPlay(name: entry.name)
    }

    /// Prefer the live device's class, fall back to what we stored when the
    /// device was last seen, then to a generic glyph.
    func symbol(_ entry: PriorityEntry, _ d: Direction) -> String {
        if let custom = entry.customSymbol { return custom }   // your choice wins
        if let device = state[d]?.connected.first(where: { $0.uid == entry.uid }) {
            return device.kind.symbolName(d)
        }
        return entry.symbolName ?? (d == .input ? "mic" : "speaker.wave.2")
    }

    func setCustomSymbol(_ symbol: String?, for entry: PriorityEntry, _ d: Direction) {
        guard var s = state[d], let i = s.entries.firstIndex(of: entry) else { return }
        s.entries[i].customSymbol = symbol
        state[d] = s
        saveEntries()
    }

    func setCustomName(_ name: String?, for entry: PriorityEntry, _ d: Direction) {
        guard var s = state[d], let i = s.entries.firstIndex(of: entry) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        s.entries[i].customName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        state[d] = s
        saveEntries()
    }

    func winner(_ d: Direction) -> AudioDevice? {
        guard let s = state[d] else { return nil }
        for entry in s.entries {
            if entry.ignored { continue }
            if entry.requiresLidOpen && lidClosed { continue }
            if let device = s.connected.first(where: { $0.uid == entry.uid }) { return device }
        }
        return nil
    }

    // MARK: - Device tracking

    func refreshDevices() {
        lidClosed = LidState.isClosed
        for d in Direction.allCases {
            var s = state[d] ?? DirectionState()
            s.connected = Audio.devices(d)
            if let current = Audio.current(d) {
                s.currentName = current.name
                s.currentUID = current.uid
            } else if s.connected.contains(where: { $0.uid == s.currentUID }) {
                // The default slot is momentarily held by something we filter
                // (a metering aggregate). Keep the last real device rather than
                // reporting "—", which the enforcer would read as "device gone"
                // and act on.
            } else {
                s.currentName = "—"
                s.currentUID = ""
            }

            // Remember any device we've never seen. Insert it by CLASS rank
            // rather than appending: appending meant a device discovered later
            // ranked last no matter what it was, which is how AirPods came to
            // outrank a dedicated USB mic.
            for device in s.connected where !s.entries.contains(where: { $0.uid == device.uid }) {
                let rank = device.kind.rank(d)
                var entry = PriorityEntry(uid: device.uid, name: device.name)
                entry.seedRank = rank
                entry.symbolName = device.kind.symbolName(d)
                entry.ephemeral = Audio.isAnonymousAirPlay(name: device.name)
                // Sensible defaults, both matching how these devices fail: the
                // built-in mic is hardware-dead in clamshell, and monitor
                // speakers hijack output the moment a display connects.
                if device.uid == "BuiltInMicrophoneDevice" { entry.requiresLidOpen = true }
                if device.isDisplayAudio { entry.ignored = true }

                // Slot in ahead of the first worse-ranked device, so any manual
                // ordering you've already made is preserved.
                let index = s.entries.firstIndex { $0.seedRank > rank } ?? s.entries.count
                s.entries.insert(entry, at: index)
            }
            state[d] = s
        }
        saveEntries()
    }

    /// Only act when the device set or lid state actually changes, so a manual
    /// override in System Settings survives until you plug or unplug something.
    private func somethingChanged() {
        // A drag is mid-flight and holds indices into `entries`. Reordering or
        // purging underneath it invalidates those indices.
        guard dragUID == nil else { return }
        refreshDevices()
        sweepDisposables()
        for d in Direction.allCases {
            guard var s = state[d] else { continue }
            let signature = s.connected.map(\.uid).sorted().joined(separator: "|") + "|lid=\(lidClosed)"
            let setChanged = signature != s.lastSignature

            // A device you marked "never use" — or one skipped because the lid
            // is shut — is a hard block, not a preference. macOS parks you on
            // the monitor on display wake or reconnect without any device set
            // change, so correct that immediately rather than treating it as a
            // manual override to be respected.
            let entry = s.entries.first { $0.uid == s.currentUID }
            let currentIneligible = (entry?.ignored ?? false)
                || ((entry?.requiresLidOpen ?? false) && lidClosed)

            guard setChanged || currentIneligible else { continue }
            s.lastSignature = signature
            state[d] = s
            enforce(d, reason: currentIneligible ? "blocked device was selected" : "devices changed")
        }
    }

    // MARK: - Enforcement

    func enforceAll(reason: String) {
        for d in Direction.allCases { enforce(d, reason: reason) }
    }

    func enforce(_ d: Direction, reason: String) {
        guard enforcing else { return }
        guard var s = state[d] else { return }

        // Nothing connects to an AirPlay speaker by accident — it is always a
        // deliberate choice made in Control Center. Bluetooth auto-connects and
        // needs overriding; AirPlay never does. Stealing audio back from a
        // HomePod the moment you sent it there is exactly wrong.
        //
        // Detected by NAME as well as transport type: relying on the transport
        // alone was fragile, and a single miss yanks you off the speaker.
        if let current = Audio.current(d),
           current.kind == .airplay || Audio.isAnonymousAirPlay(name: current.name) {
            s.lastAction = "AirPlay in use — left alone"
            state[d] = s
            return
        }
        guard let winner = winner(d) else {
            s.lastAction = "no eligible device — left \(s.currentName) alone"
            state[d] = s
            return
        }
        guard winner.name != s.currentName else { return }
        let from = s.currentName
        if Audio.setCurrent(winner, d) {
            s.currentName = winner.name
            s.lastAction = "\(from) → \(winner.name) (\(reason))"
        } else {
            s.lastAction = "failed to select \(winner.name)"
        }
        state[d] = s
    }

    // MARK: - Editing

    func moveUp(_ entry: PriorityEntry, _ d: Direction) {
        guard var s = state[d], let i = s.entries.firstIndex(of: entry), i > 0 else { return }
        s.entries.swapAt(i, i - 1); state[d] = s
        saveEntries(); enforce(d, reason: "reordered")
    }

    func moveDown(_ entry: PriorityEntry, _ d: Direction) {
        guard var s = state[d], let i = s.entries.firstIndex(of: entry),
              i < s.entries.count - 1 else { return }
        s.entries.swapAt(i, i + 1); state[d] = s
        saveEntries(); enforce(d, reason: "reordered")
    }

    func move(from source: IndexSet, to destination: Int, _ d: Direction) {
        guard var s = state[d] else { return }
        s.entries.move(fromOffsets: source, toOffset: destination); state[d] = s
        saveEntries(); enforce(d, reason: "reordered")
    }

    // MARK: - Reordering
    //
    // Plain gesture maths rather than NSItemProvider drag-and-drop. The
    // system drag session did not deliver inside the menu bar panel, and it
    // also swallowed taps, which is why neither dragging nor clicking worked.

    private var dragUID: String?
    private var dragOriginIndex: Int?

    func beginDrag(_ entry: PriorityEntry, _ d: Direction) {
        dragUID = entry.uid
        dragOriginIndex = state[d]?.entries.firstIndex(of: entry)
    }

    /// Live reorder while dragging. Deliberately does NOT enforce — switching
    /// the audio device on every row crossed would thrash. The release commits.
    func updateDrag(translation: CGFloat, rowHeight: CGFloat, _ d: Direction) {
        guard rowHeight > 0 else { return }
        guard var s = state[d], !s.entries.isEmpty,
              let uid = dragUID, let origin = dragOriginIndex,
              let current = s.entries.firstIndex(where: { $0.uid == uid }) else { return }
        // Re-clamp the origin too: the list can legitimately shrink between the
        // drag starting and this update (a device disconnecting), which would
        // otherwise leave a stale index behind.
        let safeOrigin = min(origin, s.entries.count - 1)
        let steps = Int((translation / rowHeight).rounded())
        let target = max(0, min(s.entries.count - 1, safeOrigin + steps))
        guard target != current, s.entries.indices.contains(current) else { return }
        let moved = s.entries.remove(at: current)
        s.entries.insert(moved, at: target)
        state[d] = s
    }

    func endDrag(_ d: Direction) {
        guard dragUID != nil else { return }
        dragUID = nil
        dragOriginIndex = nil
        saveEntries()
        enforce(d, reason: "reordered")
    }

    var isDragging: Bool { dragUID != nil }
    func isDragging(_ entry: PriorityEntry) -> Bool { dragUID == entry.uid }

    /// Click a device to use it right now. Blocked devices refuse rather than
    /// being silently reverted a moment later by the enforcer.
    func selectNow(_ entry: PriorityEntry, _ d: Direction) {
        guard let s = state[d],
              let device = s.connected.first(where: { $0.uid == entry.uid }) else { return }
        if entry.ignored || (entry.requiresLidOpen && lidClosed) { return }
        Audio.setCurrent(device, d)
        refreshDevices()
    }

    var canSelect: (PriorityEntry, Direction) -> Bool {
        { [weak self] entry, d in
            guard let self, let s = self.state[d] else { return false }
            guard s.connected.contains(where: { $0.uid == entry.uid }) else { return false }
            return !entry.ignored && !(entry.requiresLidOpen && self.lidClosed)
        }
    }

    // MARK: - Volume

    func volume(_ d: Direction) -> Float? {
        guard let s = state[d],
              let device = s.connected.first(where: { $0.uid == s.currentUID }) else { return nil }
        return Audio.volume(device, d)
    }

    func canMute(_ d: Direction) -> Bool {
        guard let s = state[d],
              let device = s.connected.first(where: { $0.uid == s.currentUID }) else { return false }
        return Audio.isMuted(device, d) != nil
    }

    func isMuted(_ d: Direction) -> Bool {
        guard let s = state[d],
              let device = s.connected.first(where: { $0.uid == s.currentUID }) else { return false }
        return Audio.isMuted(device, d) ?? false
    }

    func toggleMute(_ d: Direction) {
        guard let s = state[d],
              let device = s.connected.first(where: { $0.uid == s.currentUID }) else { return }
        Audio.setMuted(!(Audio.isMuted(device, d) ?? false), device, d)
        objectWillChange.send()
    }

    func setVolume(_ value: Float, _ d: Direction) {
        guard let s = state[d],
              let device = s.connected.first(where: { $0.uid == s.currentUID }) else { return }
        Audio.setVolume(value, device, d)
        objectWillChange.send()
    }

    func moveToTop(_ entry: PriorityEntry, _ d: Direction) {
        guard var s = state[d], let i = s.entries.firstIndex(of: entry), i > 0 else { return }
        let moved = s.entries.remove(at: i)
        s.entries.insert(moved, at: 0)
        state[d] = s
        saveEntries(); enforce(d, reason: "moved to top")
    }

    func forget(_ entry: PriorityEntry, _ d: Direction) {
        guard var s = state[d] else { return }
        s.entries.removeAll { $0.uid == entry.uid }
        state[d] = s
        saveEntries()
    }

    func toggleLidRule(_ entry: PriorityEntry, _ d: Direction) {
        guard var s = state[d], let i = s.entries.firstIndex(of: entry) else { return }
        s.entries[i].requiresLidOpen.toggle(); state[d] = s
        saveEntries(); enforce(d, reason: "lid rule changed")
    }

    func toggleIgnored(_ entry: PriorityEntry, _ d: Direction) {
        guard var s = state[d], let i = s.entries.firstIndex(of: entry) else { return }
        s.entries[i].ignored.toggle(); state[d] = s
        saveEntries(); enforce(d, reason: "ignore changed")
    }

    // MARK: - Persistence

    private func load() {
        let defaults = UserDefaults.standard
        defer { purgeArtifacts() }
        migrateFromPreviousBundleID()
        // Entries FIRST: assigning `enforcing` fires its didSet → save, which
        // would otherwise persist empty lists over the stored priorities.
        for d in Direction.allCases {
            guard let data = defaults.data(forKey: entriesKey + "." + d.rawValue),
                  let decoded = try? JSONDecoder().decode([PriorityEntry].self, from: data) else { continue }
            var s = state[d] ?? DirectionState()
            s.entries = decoded
            state[d] = s
        }
        enforcing = defaults.object(forKey: enforcingKey) as? Bool ?? true
        migrateAirPlayKeys()
    }

    /// Renaming the app changes its bundle identifier, which means a brand new
    /// UserDefaults domain — every ranking, label and glyph would silently
    /// reset. Copy them across once, then leave the old domain alone.
    private func migrateFromPreviousBundleID() {
        let defaults = UserDefaults.standard
        let migratedKey = "migratedFrom.micpriority"
        guard !defaults.bool(forKey: migratedKey) else { return }
        guard let old = UserDefaults(suiteName: "dance.braininavat.micpriority") else { return }

        var carried = false
        for d in Direction.allCases {
            let key = entriesKey + "." + d.rawValue
            guard defaults.data(forKey: key) == nil,
                  let data = old.data(forKey: key) else { continue }
            defaults.set(data, forKey: key)
            if let decoded = try? JSONDecoder().decode([PriorityEntry].self, from: data) {
                var s = state[d] ?? DirectionState()
                s.entries = decoded
                state[d] = s
            }
            carried = true
        }
        if defaults.object(forKey: enforcingKey) == nil,
           let value = old.object(forKey: enforcingKey) as? Bool {
            defaults.set(value, forKey: enforcingKey)
        }
        defaults.set(true, forKey: migratedKey)
        if carried { NSLog("Writ: migrated settings from the previous bundle identifier") }
    }

    /// Rewrite AirPlay entries saved under a per-session UID onto the stable
    /// speaker UUID, and drop duplicates that accumulated under the old scheme.
    private func migrateAirPlayKeys() {
        var changed = false
        for d in Direction.allCases {
            guard var s = state[d] else { continue }
            var seen = Set<String>()
            var migrated: [PriorityEntry] = []
            for var entry in s.entries {
                let stable = Audio.stableUID(entry.uid, name: entry.name)
                if stable != entry.uid { entry.uid = stable; changed = true }
                // Keep the first (highest ranked) of any duplicates, preferring
                // one that carries your label.
                if seen.contains(entry.uid) {
                    if let i = migrated.firstIndex(where: { $0.uid == entry.uid }),
                       migrated[i].customName == nil, entry.customName != nil {
                        migrated[i] = entry
                    }
                    changed = true
                    continue
                }
                seen.insert(entry.uid)
                migrated.append(entry)
            }
            if changed { s.entries = migrated; state[d] = s }
        }
        if changed { saveEntries() }
    }

    /// Drop system plumbing that earlier builds wrote into the saved list.
    /// Device memory is deliberately permanent, so a bad entry never ages out
    /// on its own — it has to be removed explicitly.
    private func purgeArtifacts() {
        var removed = false
        for d in Direction.allCases {
            guard var s = state[d] else { continue }
            let before = s.entries.count
            let connectedUIDs = Set(s.connected.map(\.uid))
            s.entries.removeAll { entry in
                if Audio.isSystemArtifact(uid: entry.uid, name: entry.name) { return true }
                // Anonymous AirPlay devices you never labelled are disposable
                // once they stop playing — that is what stopped three identical
                // dead "AirPlay" rows piling up. Label one and it stays.
                if entry.isDisposable && !connectedUIDs.contains(entry.uid) { return true }
                // Legacy rows saved before ephemeral tracking existed.
                if entry.name == "AirPlay" && entry.customName == nil
                    && entry.customSymbol == nil && !connectedUIDs.contains(entry.uid) { return true }
                return false
            }
            if s.entries.count != before { state[d] = s; removed = true }
        }
        if removed { saveEntries() }
    }

    /// Called whenever devices change, so stale AirPlay rows disappear as soon
    /// as they stop playing rather than lingering until the next launch.
    private func sweepDisposables() { purgeArtifacts() }

    private func saveEntries() {
        let defaults = UserDefaults.standard
        for d in Direction.allCases {
            guard let entries = state[d]?.entries,
                  let data = try? JSONEncoder().encode(entries) else { continue }
            defaults.set(data, forKey: entriesKey + "." + d.rawValue)
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(enforcing, forKey: enforcingKey)
    }

    // MARK: - Login item

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
        } catch {
            var s = state[showing] ?? DirectionState()
            s.lastAction = "login item failed: \(error.localizedDescription)"
            state[showing] = s
        }
    }
}
