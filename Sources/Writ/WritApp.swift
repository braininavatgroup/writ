import SwiftUI
import UniformTypeIdentifiers

/// `--preview` renders the same view in an ordinary window. The menu bar
/// popover can be parked off-screen by menu bar managers, which makes the real
/// UI impossible to inspect; this is how the design gets reviewed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var statusItem = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--preview") {
            // Design review only: a normal window, and deliberately NO menu bar
            // item, so a preview instance can never add a second icon.
            let window = NSWindow(
                contentRect: NSRect(x: 240, y: 240, width: 340, height: 620),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Writ — preview"
            window.contentView = NSHostingView(rootView: MenuView(model: PriorityModel.shared))
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        statusItem.install()
    }
}

@main
struct WritApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar item and its panel are built in AppKit (see
    // StatusItemController) because MenuBarExtra's window takes key focus.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - Root

struct MenuView: View {
    @ObservedObject var model: PriorityModel
    @StateObject private var meter = LevelMonitor()
    @State private var draggingUID: String?

    private var d: Direction { model.showing }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                DirectionPicker(selection: $model.showing)

                nowPlaying
                priorityList
            }
            .padding(14)
            .opacity(model.enforcing ? 1 : 0.5)
            .allowsHitTesting(true)

            Divider()
            footer
        }
        .frame(width: 328)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "headset")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text("Audio Priority")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.enforcing ? "Enforcing your order" : "Paused")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VividSwitch(isOn: $model.enforcing)
                .help(model.enforcing
                      ? "Pause — stop changing devices automatically"
                      : "Resume enforcing your priority order")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Current device

    private var nowPlaying: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: d == .input ? "mic.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.currentName(d))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                if model.canMute(d) {
                    Button {
                        model.toggleMute(d)
                    } label: {
                        Image(systemName: model.isMuted(d)
                              ? (d == .input ? "mic.slash.fill" : "speaker.slash.fill")
                              : (d == .input ? "mic.fill" : "speaker.wave.2.fill"))
                            .font(.system(size: 11))
                            .foregroundStyle(model.isMuted(d) ? Color.red : Color.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(model.isMuted(d) ? "Unmute" : "Mute")
                }
            }

            if d == .input { InputMeter(meter: meter) }
            volumeSlider
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { if d == .input { meter.start() } }
        .onDisappear { meter.stop() }
        .onChange(of: model.showing) { new in
            new == .input ? meter.start() : meter.stop()
        }
        // Keyed on the device UID, not the display name: a name can blip to "—"
        // for an instant while CoreAudio reshuffles, and restarting on that blip
        // is what produced the runaway meter restart loop.
        .onChange(of: model.currentUID(.input)) { _ in meter.restartIfDeviceChanged() }
    }

    /// The subtitle describes THIS device, not some other one. It previously
    /// said "built-in mic unavailable" underneath whichever device was in use,
    /// which read as though that device were the unavailable one.
    private var subtitle: String {
        if !model.enforcing { return "Automatic switching paused" }
        // AirPlay is left alone deliberately; say so rather than looking broken.
        if model.currentIsAnonymousAirPlay(d) { return "AirPlay · not managed until you name it" }
        return d == .input ? "Currently receiving audio" : "Currently playing audio"
    }

    @ViewBuilder
    private var volumeSlider: some View {
        if let level = model.volume(d) {
            HStack(spacing: 6) {
                Image(systemName: d == .input ? "mic" : "speaker.fill")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
                    .frame(width: 10)
                Slider(value: Binding(get: { Double(level) },
                                      set: { model.setVolume(Float($0), d) }), in: 0...1)
                    .controlSize(.mini)
                Text("\(Int(level * 100))")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)
            }
            .help(d == .input ? "Input gain" : "Output volume")
        }
    }

    // MARK: List

    private var priorityList: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Apple's Sound menu uses a plain sentence-case section label, not
            // tracked-out caps.
            HStack(alignment: .firstTextBaseline) {
                Text("Priority")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Click to use · drag to reorder")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if model.entries(d).isEmpty {
                Text("No devices found yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.entries(d)) { entry in
                        DeviceRow(entry: entry, direction: d, model: model)
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: model.entries(d))
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Menu {
                Toggle("Open at Login", isOn: Binding(get: { model.launchesAtLogin },
                                                     set: { model.setLaunchAtLogin($0) }))
                Divider()
                // Renamed from "Re-apply", which said nothing about what it does.
                // It re-asserts your ranking after you've clicked a device by
                // hand — the undo for a manual pick.
                Button("Restore Priority Order") {
                    model.refreshDevices(); model.enforceAll(reason: "manual")
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            // A menu bar app has no app menu and no Dock icon, so this is the
            // only way to quit it. It stays.
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Row

struct DeviceRow: View {
    static let height: CGFloat = 38

    let entry: PriorityEntry
    let direction: Direction
    @ObservedObject var model: PriorityModel

    @State private var hovering = false
    @State private var dragging = false
    @State private var showingPicker = false

    private var selectable: Bool { connected && !blocked && !isCurrent }
    private var isCurrent: Bool { model.isCurrent(entry, direction) }
    private var connected: Bool { model.isConnected(entry, direction) }
    private var lidBlocked: Bool { entry.requiresLidOpen && model.lidClosed }
    private var blocked: Bool { entry.ignored || lidBlocked }

    var body: some View {
        HStack(spacing: 8) {
            // The grip is the ONLY drag target. Previously the whole row was
            // draggable, which meant the drag gesture ate every click.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(dragging ? Color.accentColor
                                 : (hovering ? Color.secondary : Color.secondary.opacity(0.35)))
                .frame(width: 14, height: Self.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if !dragging { dragging = true; model.beginDrag(entry, direction) }
                            model.updateDrag(translation: value.translation.height,
                                             rowHeight: Self.height, direction)
                        }
                        .onEnded { _ in
                            dragging = false
                            model.endDrag(direction)
                        }
                )
                .help("Drag to reorder")

            // Click-to-use lives on a real Button, not a tap gesture competing
            // with a drag.
            Button {
                model.selectNow(entry, direction)
            } label: {
                HStack(spacing: 9) {
                    deviceBadge

                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.displayName)
                            .font(.system(size: 13))
                            .foregroundStyle(rowColor)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let note = noteText {
                            Text(note)
                                .font(.system(size: 10))
                                .foregroundStyle(noteColor)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!selectable)

            // Exactly one chip, and it always states the CURRENT truth. The old
            // "Lid open" badge described the rule but read as a status claim,
            // so it appeared to assert the lid was open while it was shut.
            if entry.ignored {
                Chip(icon: "nosign", text: "Never", color: .red)
            } else if entry.requiresLidOpen {
                if lidBlocked {
                    Chip(icon: "laptopcomputer.slash", text: "Lid closed", color: .orange)
                } else {
                    Chip(icon: "laptopcomputer", text: "Only when open", color: .secondary)
                }
            }

            Menu {
                Button(entry.ignored ? "Allow This Device" : "Never Use This Device") {
                    model.toggleIgnored(entry, direction)
                }
                Button(entry.requiresLidOpen ? "Use Regardless of Lid" : "Only Use When Lid Is Open") {
                    model.toggleLidRule(entry, direction)
                }
                Divider()
                Button("Icon & Label…") { showingPicker = true }
                Button("Move to Top") { model.moveToTop(entry, direction) }
                if !connected {
                    Button("Forget Device") { model.forget(entry, direction) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0.25)
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)   // fixed height makes the drag maths exact
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        }
        .overlay {
            if dragging {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
        .onHover { hovering = $0 }
        .help(helpText)
        .popover(isPresented: $showingPicker, arrowEdge: .trailing) {
            GlyphPicker(entry: entry, direction: direction, model: model)
        }
        .contextMenu {
            Button("Icon & Label…") { showingPicker = true }
            Button(entry.ignored ? "Allow This Device" : "Never Use This Device") {
                model.toggleIgnored(entry, direction)
            }
            Button(entry.requiresLidOpen ? "Use Regardless of Lid" : "Only Use When Lid Is Open") {
                model.toggleLidRule(entry, direction)
            }
        }
    }

    /// Apple's Sound menu identifies the active device by FILLING its circular
    /// badge rather than tinting the whole row, so this matches that.
    private var deviceBadge: some View {
        DeviceBadge(symbol: model.symbol(entry, direction),
                    filled: isCurrent,
                    dimmed: !connected)
            .opacity(blocked ? 0.45 : 1)
    }

    private var rowColor: Color {
        if blocked { return .secondary }
        return connected ? .primary : .secondary
    }

    /// The chip owns everything about rules and blocking, so the note only ever
    /// reports connection state. No row states the same fact twice.
    private var noteText: String? {
        if isCurrent {
            // Nudge, because an unlabelled AirPlay row is indistinguishable from
            // any other and this is the one moment you know which speaker it is.
            return model.isAnonymousAirPlay(entry) && entry.customName == nil
                ? "In use · name it from the ••• menu"
                : "In use"
        }
        if !connected { return "Not connected" }
        return nil
    }

    private var noteColor: Color { isCurrent ? .green : .secondary }

    private var helpText: String {
        let name = entry.displayName
        if entry.ignored { return "\(name) — set to never be used" }
        if lidBlocked { return "\(name) — unavailable while the lid is closed" }
        if !connected { return "\(name) — not connected" }
        if isCurrent { return "\(name) — currently in use" }
        return "Use \(name) now"
    }
}

// MARK: - Bits

/// Segmented level meter with peak hold — so you can see you're being heard
/// before you start talking, which is the whole point on a machine where the
/// built-in mic goes silent in clamshell.
struct InputMeter: View {
    @ObservedObject var meter: LevelMonitor

    @ViewBuilder
    private func readout(_ label: String, _ db: Float, highlight: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text(db <= -119 ? "--" : "\(Int(db))")
                .font(.system(size: 9, weight: highlight ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(highlight ? Color.primary : Color.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Continuous gradient bar with a peak-hold tick and a −12 dB
            // headroom marker, rather than a row of dots you have to count.
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))

                    Capsule()
                        .fill(LinearGradient(
                            stops: [.init(color: .green, location: 0),
                                    .init(color: .green, location: 0.72),
                                    .init(color: .yellow, location: 0.86),
                                    .init(color: .red, location: 1)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(1, CGFloat(meter.level))) * w)
                        .animation(.linear(duration: 0.05), value: meter.level)

                    // Headroom marker: aim to peak just below this.
                    Rectangle()
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 1, height: 10)
                        .offset(x: w * 0.8)

                    if meter.peak > 0.01 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.8))
                            .frame(width: 2, height: 10)
                            .offset(x: max(0, min(1, CGFloat(meter.peak)) * w - 1))
                            .animation(.linear(duration: 0.08), value: meter.peak)
                    }
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                if meter.denied {
                    Label("Microphone access denied — enable in Privacy & Security",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                } else if !meter.running {
                    Text("Starting meter…").font(.system(size: 9)).foregroundStyle(.tertiary)
                } else if meter.clipping {
                    Label("Clipping — lower the gain", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                } else if meter.level < 0.02 && meter.averageDB <= -119 {
                    Text("Silent").font(.system(size: 9)).foregroundStyle(.orange)
                } else {
                    // Peak / average / floor together are what make an A/B
                    // comparison readable — a bouncing bar alone isn't.
                    HStack(spacing: 6) {
                        readout("pk", meter.peakDB)
                        readout("avg", meter.averageDB)
                        readout("floor", meter.noiseFloorDB, highlight: true)
                    }
                }
                Spacer()
                if meter.running && !meter.denied {
                    Button("Reset") { meter.resetPeak() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .help("Reset the peak-hold marker")
                }
            }

            if meter.running && !meter.denied {
                Divider().padding(.vertical, 1)
                HStack(spacing: 5) {
                    // Same panel, no menu switching: the picker opens in front
                    // and the meter keeps running behind it.
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(meter.microphoneMode)
                        .font(.system(size: 10, weight: .medium))
                    if meter.microphoneModeDiffersFromPreferred {
                        Text("(device can't do your preferred mode)")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Change…") {
                        // Apple's picker opens in Control Center, and our panel
                        // sits at .statusBar level — so it must step aside or it
                        // covers the very thing it just opened.
                        NotificationCenter.default.post(name: .writYieldPanel, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            meter.showModePicker()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentColor)
                    .help("Opens Apple's microphone mode picker — macOS provides no way to set this from an app")
                }
            }
        }
    }
}

/// The panel is deliberately non-key (so it never steals keyboard focus), and
/// AppKit renders standard controls in their disabled grey state in non-key
/// windows. These draw their own colours so the UI reads as live.
struct VividSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.4))
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                    .padding(2)
            }
            .frame(width: 34, height: 20)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

struct DirectionPicker: View {
    @Binding var selection: Direction

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Direction.allCases) { direction in
                Button { selection = direction } label: {
                    Text(direction == .input ? "Input" : "Output")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selection == direction ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(selection == direction ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// One definition of the device badge, used by both the list and the icon
/// picker so what you pick is exactly what you get.
///
/// Sizing matters here: an 11pt glyph inside a 24pt circle left detailed
/// symbols (airplayaudio, homepodmini) rendering as mush. A larger glyph at
/// medium weight, scaled to fit rather than fixed, keeps them legible.
struct DeviceBadge: View {
    let symbol: String
    var filled: Bool = false
    var dimmed: Bool = false
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(filled ? Color.accentColor : Color.primary.opacity(0.10))
            Image(systemName: symbol)
                .font(.system(size: size * 0.52, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .imageScale(.medium)
                .scaledToFit()
                .frame(width: size * 0.62, height: size * 0.62)
                .foregroundStyle(filled ? Color.white
                                 : (dimmed ? Color.secondary.opacity(0.55)
                                           : Color.primary.opacity(0.8)))
        }
        .frame(width: size, height: size)
    }
}

struct Chip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .semibold))
            Text(text).font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
        .fixedSize()
    }
}

