import AppKit
import SwiftUI

/// Shortcut editing lives in an ordinary window, not in the menu bar panel.
///
/// The panel is `.nonactivatingPanel` on purpose — it must never take key focus,
/// or it swallows ⌘V in whatever app you were typing in. But recording a
/// shortcut means receiving key events, which requires exactly the key focus the
/// panel refuses to take. Rather than fight that, this is a real window.
@MainActor
final class ShortcutWindowController {
    static let shared = ShortcutWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NSHostingController(rootView: ShortcutSettingsView())
        let window = NSWindow(contentViewController: controller)
        window.title = "Keyboard Shortcuts"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        // A menu bar app is an accessory and cannot ordinarily take focus, so
        // it has to become a regular app for as long as this window is open —
        // otherwise the window opens behind everything and never accepts a key.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in NSApp.setActivationPolicy(.accessory) }
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject private var manager = HotkeyManager.shared
    @State private var recording: HotkeyAction?
    @State private var conflict: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 15, weight: .semibold))
                Text("These work from any app. Writ registers only the combinations "
                     + "listed here — it never reads your keyboard.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            VStack(spacing: 0) {
                ForEach(HotkeyAction.allCases) { action in
                    ShortcutRow(action: action,
                                manager: manager,
                                recording: $recording,
                                conflict: $conflict)
                    if action != HotkeyAction.allCases.last { Divider().padding(.leading, 18) }
                }
            }

            Divider()

            HStack {
                if let conflict {
                    Label(conflict, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                } else {
                    Text("Click a shortcut to change it. Press ⎋ to cancel, ⌫ to clear.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Restore Defaults") {
                    manager.resetToDefaults()
                    recording = nil
                    conflict = nil
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 460)
    }
}

private struct ShortcutRow: View {
    let action: HotkeyAction
    @ObservedObject var manager: HotkeyManager
    @Binding var recording: HotkeyAction?
    @Binding var conflict: String?

    private var isRecording: Bool { recording == action }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).font(.system(size: 12))
                Text(action.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)

            if isRecording {
                KeyRecorder { event in complete(with: event) }
                    .frame(width: 108, height: 22)
            } else {
                Button {
                    conflict = nil
                    recording = action
                } label: {
                    Text(manager.shortcut(for: action)?.display ?? "Not set")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(manager.shortcut(for: action) == nil
                                         ? Color.secondary : Color.primary)
                        .frame(width: 108, height: 22)
                        .background(Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Click to record a new shortcut")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(isRecording ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private func complete(with event: NSEvent?) {
        defer { recording = nil }

        guard let event else { return }                          // ⎋ — cancelled
        if event.keyCode == 51 {                                 // ⌫ — clear it
            manager.setShortcut(nil, for: action)
            conflict = nil
            return
        }
        guard let shortcut = Shortcut(event: event) else {
            conflict = "Add ⌘, ⌥ or ⌃ — a shortcut without one would swallow ordinary typing."
            return
        }
        if let owner = manager.conflict(shortcut, excluding: action) {
            conflict = "\(shortcut.display) is already used by “\(owner.title)”."
            return
        }
        conflict = nil
        manager.setShortcut(shortcut, for: action)
    }
}

/// Captures one key combination. A local monitor is enough here because this
/// window IS key while recording — no Accessibility permission involved.
private struct KeyRecorder: NSViewRepresentable {
    let onComplete: (NSEvent?) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onComplete = onComplete
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onComplete = onComplete
    }

    final class RecorderView: NSView {
        var onComplete: ((NSEvent?) -> Void)?
        private var monitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { teardown(); return }
            window?.makeFirstResponder(self)

            // Swallow the event: without returning nil the combination is also
            // delivered to the app underneath, so recording ⌘W closes a window
            // while you are still assigning it.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self else { return event }
                self.teardown()
                self.onComplete?(event.keyCode == 53 ? nil : event)   // ⎋ cancels
                return nil
            }
        }

        private func teardown() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1
            path.stroke()

            let text = "Press keys…" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.controlAccentColor,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                  y: bounds.midY - size.height / 2),
                      withAttributes: attributes)
        }
    }
}
