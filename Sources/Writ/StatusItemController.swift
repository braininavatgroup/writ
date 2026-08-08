import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item and its panel.
///
/// This replaces SwiftUI's `MenuBarExtra`, which opens a window that takes key
/// focus — that is why the panel being open swallowed ⌘V and broke pasting into
/// other apps. An `NSPanel` with `.nonactivatingPanel`, shown via
/// `orderFrontRegardless()`, never activates this app or steals the responder
/// chain, so the app you were typing in stays focused.
extension Notification.Name {
    /// Posted when a system UI is about to open that would otherwise appear
    /// BEHIND our panel. We drop the window level rather than hiding, so the
    /// panel — and the level meter — stay visible alongside it.
    static let writYieldPanel = Notification.Name("WritYieldPanel")

    /// Posted when the panel is ordered out or back in.
    ///
    /// SwiftUI's onAppear/onDisappear do NOT fire for a hosted view when its
    /// window is merely ordered out — the view hierarchy never changes. Relying
    /// on them left the microphone tap running after the panel closed, with the
    /// orange recording indicator lit, for as long as the app was running.
    /// Measured, not assumed: `kAudioDevicePropertyDeviceIsRunningSomewhere`
    /// stayed true indefinitely after closing the panel.
    static let writPanelDidHide = Notification.Name("WritPanelDidHide")
    static let writPanelDidShow = Notification.Name("WritPanelDidShow")
}

@MainActor
final class StatusItemController: NSObject {

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var outsideMonitor: Any?
    private var yieldRestoreTimer: Timer?
    private var isYielding = false
    private var cancellables = Set<AnyCancellable>()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateGlyph()

        PriorityModel.shared.$enforcing
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateGlyph() }
            .store(in: &cancellables)

        PriorityModel.shared.$inputMuted
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateGlyph() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .writYieldPanel)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.yieldToSystemUI() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .writTogglePanel)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.togglePanel() }
            .store(in: &cancellables)

        _ = HotkeyManager.shared   // register global shortcuts

        // Deferred one turn of the run loop: the status item's window has no
        // real frame until it has been laid out, and FirstRun reads that frame
        // to decide whether the icon is actually reachable.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            FirstRun.presentIfNeeded(statusButton: item.button) { self.show() }
        }
    }

    /// Drop below Control Center so its picker draws on top, WITHOUT closing —
    /// so you can flip microphone modes and watch the meter react at the same
    /// time. The level restores as soon as you come back to the panel.
    private func yieldToSystemUI() {
        guard let panel else { return }
        // Clicking Control Center is a click "outside" us, which would otherwise
        // dismiss the panel — the exact thing we're trying to avoid.
        isYielding = true
        panel.level = .normal
        yieldRestoreTimer?.invalidate()
        yieldRestoreTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.restoreLevel() }
        }
    }

    private func restoreLevel() {
        yieldRestoreTimer?.invalidate()
        yieldRestoreTimer = nil
        isYielding = false
        panel?.level = .statusBar
    }

    // MARK: - Glyph

    /// Two genuinely distinct glyphs. `headset.slash` does not exist in SF
    /// Symbols (verified), so the disabled state is drawn by striking the
    /// headset through — which reads at a glance far better than dimming it.
    private func updateGlyph() {
        guard let button = statusItem?.button else { return }
        let enforcing = PriorityModel.shared.enforcing
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)

        // Muted outranks everything else the icon could say. A shortcut that
        // mutes your microphone from any app, with no visible state, is how you
        // end up talking to a muted mic — so this takes over the icon entirely
        // and is the one case where colour is warranted.
        if PriorityModel.shared.inputMuted {
            let muted = NSImage(systemSymbolName: "mic.slash.fill",
                                accessibilityDescription: "Writ — microphone muted")?
                .withSymbolConfiguration(config)
            muted?.isTemplate = true
            button.image = muted
            button.contentTintColor = .systemRed
            button.toolTip = "Writ — microphone is MUTED"
            return
        }
        button.contentTintColor = nil

        guard let base = NSImage(systemSymbolName: "headset",
                                 accessibilityDescription: "Writ")?
            .withSymbolConfiguration(config) else { return }

        if enforcing {
            base.isTemplate = true
            button.image = base
            button.toolTip = "Writ — holding input and output to your order"
        } else {
            let size = base.size
            let struck = NSImage(size: size, flipped: false) { rect in
                base.draw(in: rect)
                let path = NSBezierPath()
                path.move(to: NSPoint(x: rect.minX + 1.5, y: rect.minY + 1.5))
                path.line(to: NSPoint(x: rect.maxX - 1.5, y: rect.maxY - 1.5))
                path.lineWidth = 1.6
                NSColor.black.setStroke()
                path.stroke()
                return true
            }
            struck.isTemplate = true
            button.image = struck
            button.toolTip = "Writ — paused, devices can change freely"
        }
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if let panel, panel.isVisible { hide() } else { show() }
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        restoreLevel()
        // orderFrontRegardless shows the panel WITHOUT activating this app.
        panel.orderFrontRegardless()
        installOutsideMonitor()
        NotificationCenter.default.post(name: .writPanelDidShow, object: nil)
        anchorToStatusItem()
    }

    /// Put the panel under the menu bar item, at whatever size its content
    /// currently wants.
    ///
    /// Called again whenever the content resizes, which it genuinely does while
    /// open: the meter appears a moment after the panel does, and devices
    /// connect and disconnect underneath you. Measuring once at open meant the
    /// panel kept the size the content happened to have at that instant — and
    /// once closing the panel started stopping the meter, that instant was the
    /// collapsed one, so it opened too short to be usable.
    private func anchorToStatusItem() {
        guard let panel,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        let size = panel.frame.size
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(x: buttonRect.midX - size.width / 2,
                             y: buttonRect.minY - size.height - 6)

        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
            if origin.y < visible.minY + 8 { origin.y = visible.minY + 8 }
        }
        panel.setFrameOrigin(origin)
    }

    private func hide() {
        panel?.orderOut(nil)
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        // Explicit, because ordering the window out does not tell SwiftUI
        // anything — and a microphone that keeps running after you close the
        // panel is the one bug this app cannot afford to have.
        NotificationCenter.default.post(name: .writPanelDidHide, object: nil)
    }

    private func makePanel() -> NSPanel {
        // NSHostingController, not NSHostingView: the controller propagates the
        // SwiftUI content's preferred size to its window, so the panel tracks
        // its content automatically instead of being measured once by hand.
        let controller = NSHostingController(rootView: PanelRoot(model: PriorityModel.shared))

        let panel = NSPanel(
            contentViewController: controller)
        panel.styleMask = [.nonactivatingPanel, .fullSizeContentView, .borderless]
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true   // only when a control truly needs it
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // A window resizes from its bottom-left corner, so content growing
        // downward would walk the panel away from the menu bar item it belongs
        // to. Re-anchor on every resize instead.
        NotificationCenter.default
            .publisher(for: NSWindow.didResizeNotification, object: panel)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.anchorToStatusItem() }
            .store(in: &cancellables)

        return panel
    }

    /// Click anywhere outside to dismiss, the way a menu bar popover should.
    private func installOutsideMonitor() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isYielding else { return }
                    self.hide()
                }
        }
    }
}

/// Rounded, material-backed container so a borderless panel still looks native.
struct PanelRoot: View {
    @ObservedObject var model: PriorityModel

    var body: some View {
        MenuView(model: model)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .padding(6)   // room for the panel shadow
    }
}
