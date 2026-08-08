import AppKit

/// Shown once, the first time Writ launches.
///
/// A `LSUIElement` app has no Dock icon and no window. Someone who has just
/// double-clicked it gets no feedback whatsoever that anything happened, and the
/// menu bar icon they are meant to notice may not even be visible — Bartender
/// and similar managers park unrecognised status items off-screen, which cost
/// real time to diagnose during development and would otherwise arrive as
/// "I installed it and nothing happened".
///
/// So this checks where the icon actually ended up and says the true thing about
/// it, rather than confidently pointing at a menu bar it is not in.
@MainActor
enum FirstRun {
    private static let key = "hasSeenWelcome"

    /// Call after the status item is installed. `delay` gives the status item
    /// window time to acquire a real frame — see `isOffscreen`.
    static func presentIfNeeded(statusButton: NSStatusBarButton?,
                                delay: TimeInterval = 1.5,
                                onShowPanel: @escaping () -> Void) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            present(statusButton: statusButton, onShowPanel: onShowPanel)
        }
    }

    private static func present(statusButton: NSStatusBarButton?, onShowPanel: () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Writ is running in your menu bar"

        if isOffscreen(statusButton) {
            // Do not tell someone to look at an icon that is provably not there.
            alert.informativeText = """
                Its icon has been hidden by a menu bar manager such as Bartender \
                or Ice — it is currently parked off-screen.

                Show Writ in that app's settings, or use the button below to open \
                the panel now.
                """
        } else {
            alert.informativeText = """
                Look for the headset icon in the menu bar. Click it to set the \
                order your input and output devices should be used in.

                Writ has no Dock icon and no window — the menu bar is where it \
                lives.
                """
        }

        alert.addButton(withTitle: "Open Writ")
        alert.addButton(withTitle: "Done")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { onShowPanel() }
    }

    /// A hidden status item is not removed — it is moved far off the left edge
    /// of the screen (observed at x ≈ −8500). Anything outside the union of the
    /// real screens is not somewhere a person can click.
    ///
    /// An EMPTY frame is not evidence of hiding, it is evidence of not having
    /// been laid out yet, and treating the two the same told a user with a
    /// perfectly visible icon to go hunting in Bartender's settings. When the
    /// frame says nothing, say the ordinary thing.
    private static func isOffscreen(_ button: NSStatusBarButton?) -> Bool {
        guard let frame = button?.window?.frame, !frame.isEmpty else { return false }
        let visible = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        return !visible.intersects(frame)
    }
}
