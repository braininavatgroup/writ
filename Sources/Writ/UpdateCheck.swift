import AppKit
import Foundation

/// Manual update check against a small JSON feed.
///
/// Deliberately dormant: the feed URL is read from the `WritUpdateFeedURL` key
/// in Info.plist, and if that key is absent the whole feature — including the
/// menu item — does not exist. A build with no feed makes no network requests
/// at all, so this can ship before the download site does.
///
/// Manual, not background. An app that watches your microphone has to be
/// obviously well-behaved about what it sends anywhere, and a menu item you
/// press is the version of that which needs no explaining.
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

    func check() {
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
                    self.report(title: "Couldn’t check for updates",
                                body: error?.localizedDescription
                                      ?? "The update feed could not be read.")
                    return
                }

                // Compare builds, not version strings: "1.10" sorts before
                // "1.9" as text and there is no reason to reinvent that.
                guard release.build > Self.currentBuild else {
                    self.report(title: "Writ is up to date",
                                body: "You’re on \(Self.currentVersion).")
                    return
                }
                self.offer(release)
            }
        }.resume()
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Writ \(release.version) is available"
        alert.informativeText = release.notes ?? "You’re on \(Self.currentVersion)."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: release.url) {
            NSWorkspace.shared.open(url)
        }
    }

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
