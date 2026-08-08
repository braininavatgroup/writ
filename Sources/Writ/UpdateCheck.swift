import AppKit
import Combine
import Foundation

/// Update checking against a small JSON feed.
///
/// Deliberately dormant: the feed URL is read from the `WritUpdateFeedURL` key
/// in Info.plist, and if that key is absent the whole feature — including the
/// menu item — does not exist. A build with no feed makes no network requests
/// at all, so this can ship before the download site does.
///
/// Checks daily and can be switched off. The request carries no identifier for
/// the user or the machine, and a check nobody asked for stays silent unless it
/// actually finds something — an app that watches your microphone has to be
/// obviously well-behaved about what it sends anywhere.
@MainActor
final class UpdateCheck: ObservableObject {
    static let shared = UpdateCheck()

    struct Release: Decodable {
        let version: String          // marketing version, e.g. "1.1"
        let build: Int               // monotonic CFBundleVersion
        let url: String              // download page or direct .dmg
        let notes: String?
    }

    /// `nil` when no feed is configured — the caller uses this to decide
    /// whether to offer the menu item at all.
    static var feedURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "WritUpdateFeedURL") as? String,
              !s.isEmpty, let u = URL(string: s) else { return nil }
        return u
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
    }

    @Published private(set) var checking = false
    let installer = Installer()

    private var timer: Timer?
    private static let automaticKey = "automaticUpdateChecks"
    private static let lastCheckKey = "lastUpdateCheck"

    /// On by default, and switchable in the gear menu. An app people install to
    /// stop babysitting their audio should not need babysitting to stay current.
    var automaticChecks: Bool {
        get { UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.automaticKey)
            objectWillChange.send()
            scheduleAutomaticChecks()
        }
    }

    /// Daily, and never at launch.
    ///
    /// Checking on launch would put a network request in the seconds when
    /// someone is starting a call — the exact moment this app is most needed and
    /// least allowed to be busy. The first check happens well after startup, and
    /// only if a day has actually passed.
    func scheduleAutomaticChecks() {
        timer?.invalidate()
        timer = nil
        guard automaticChecks, Self.feedURL != nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        // Deliberately late: launch is the worst moment to make a request.
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard automaticChecks else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let now = Date().timeIntervalSince1970
        guard last == 0 || now - last > 24 * 3600 else { return }
        UserDefaults.standard.set(now, forKey: Self.lastCheckKey)
        check(silent: true)
    }

    /// `silent` suppresses "you're up to date" and error alerts — nobody wants a
    /// dialog from a check they did not ask for. A found update still speaks up.
    func check(silent: Bool = false) {
        guard !checking, let feed = Self.feedURL else { return }
        checking = true

        var request = URLRequest(url: feed)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self else { return }
                self.checking = false

                guard let data,
                      let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    if !silent {
                        self.report(title: "Couldn’t check for updates",
                                    body: error?.localizedDescription
                                          ?? "The update feed could not be read.")
                    }
                    return
                }

                // Compare builds, not version strings: "1.10" sorts before
                // "1.9" as text and there is no reason to reinvent that.
                guard release.build > Self.currentBuild else {
                    if !silent {
                        self.report(title: "Writ is up to date",
                                    body: "You’re on \(Self.currentVersion).")
                    }
                    return
                }
                self.offer(release)
            }
        }.resume()
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        // Two releases can share a marketing version and differ only by build —
        // a rebuild, or a fix that did not earn a version bump. Announcing
        // "Writ 1.0 is available" to somebody already running 1.0 reads as a
        // bug in the updater.
        let newVersion = release.version != Self.currentVersion
        alert.messageText = newVersion
            ? "Writ \(release.version) is available"
            : "A newer build of Writ \(release.version) is available"
        alert.informativeText = (release.notes ?? "")
            + (newVersion ? "\n\nYou’re on \(Self.currentVersion)."
                          : "\n\nYou’re on build \(Self.currentBuild); this is build \(release.build).")
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        installer.install(from: release.url)
        watchInstall(release)
    }

    /// The installer replaces the running app and relaunches, so success is not
    /// something this process reports — it simply stops existing. Only failure
    /// needs to be surfaced, and it must be, or a silently failed update looks
    /// exactly like a successful one.
    private func watchInstall(_ release: Release) {
        var cancellable: AnyCancellable?
        cancellable = installer.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard case .failed(let message) = phase else { return }
                cancellable?.cancel()
                self?.report(title: "Couldn’t install Writ \(release.version)", body: message
                    + "\n\nYour current version is untouched. You can download the "
                    + "update by hand instead.")
            }
        cancellable?.store(in: &installWatch)
    }

    private var installWatch = Set<AnyCancellable>()

    private func report(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// Opens a pre-addressed mail draft with the facts every support thread ends up
/// asking for anyway. The user sees and can edit the whole body before sending;
/// nothing leaves the machine on its own.
@MainActor
enum Support {
    static var email: String? {
        let s = Bundle.main.object(forInfoDictionaryKey: "WritSupportEmail") as? String
        return (s?.isEmpty == false) ? s : nil
    }

    static func compose(to address: String) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let body = """


        ——— please leave this below the line ———
        Writ \(UpdateCheck.currentVersion) (\(UpdateCheck.currentBuild))
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        Hardware: \(hardwareModel())
        Inputs: \(deviceSummary(.input))
        Outputs: \(deviceSummary(.output))
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Writ \(UpdateCheck.currentVersion)"),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private static func deviceSummary(_ direction: Direction) -> String {
        let names = Audio.devices(direction).map(\.name)
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
