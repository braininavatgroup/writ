import Foundation
import MetricKit

enum ErrorReportKind: String, Codable {
    case crash
    case deviceSwitchFailed = "device-switch-failed"
}

struct ErrorReportPayload: Codable, Equatable {
    let kind: String
    let appVersion: String
    let osVersion: String
}

/// Opt-in reporting with a deliberately tiny boundary.
///
/// MetricKit tells us that a crash happened, but its diagnostic payload never
/// leaves the process. The request contains only the error kind, Writ version,
/// and macOS version promised in the privacy policy. Device names, identifiers,
/// settings, user content, and stack traces cannot enter this representation.
final class ErrorReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = ErrorReporter()

    static let enabledKey = "sendCrashReports"
    private static let lastAttemptPrefix = "errorReportLastAttempt."
    private static let throttleInterval: TimeInterval = 60 * 60

    private let defaults: UserDefaults
    private let endpoint: () -> URL?
    private let appVersion: () -> String
    private let osVersion: () -> String
    private let now: () -> Date
    private let send: (URLRequest) -> Void
    private let managesMetricKit: Bool
    private let lock = NSLock()
    private var started = false
    private var subscribed = false

    private override init() {
        defaults = .standard
        endpoint = {
            guard let value = Bundle.main.object(forInfoDictionaryKey: "WritErrorReportURL") as? String,
                  !value.isEmpty else { return nil }
            return URL(string: value)
        }
        appVersion = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        }
        osVersion = { Self.currentOSVersion }
        now = Date.init
        send = { request in URLSession.shared.dataTask(with: request).resume() }
        managesMetricKit = true
        super.init()
    }

    init(
        defaults: UserDefaults,
        endpoint: @escaping () -> URL?,
        appVersion: @escaping () -> String,
        osVersion: @escaping () -> String,
        now: @escaping () -> Date,
        send: @escaping (URLRequest) -> Void
    ) {
        self.defaults = defaults
        self.endpoint = endpoint
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.now = now
        self.send = send
        managesMetricKit = false
        super.init()
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var isConfigured: Bool { endpoint() != nil }

    func start() {
        lock.lock()
        started = true
        lock.unlock()
        updateSubscription()
    }

    func stop() {
        lock.lock()
        started = false
        lock.unlock()
        updateSubscription()
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        updateSubscription()
    }

    func report(_ kind: ErrorReportKind) {
        guard isEnabled, let endpoint = endpoint() else { return }

        // A failed CoreAudio switch can be retried on each device notification.
        // Record the attempt before starting the request so an offline Mac does
        // not turn that loop into an error-reporting loop of its own.
        let key = Self.lastAttemptPrefix + kind.rawValue
        lock.lock()
        guard started else {
            lock.unlock()
            return
        }
        let attemptedAt = defaults.double(forKey: key)
        let timestamp = now().timeIntervalSince1970
        guard attemptedAt == 0 || timestamp - attemptedAt >= Self.throttleInterval else {
            lock.unlock()
            return
        }
        defaults.set(timestamp, forKey: key)
        lock.unlock()

        guard let request = Self.request(
            kind: kind,
            endpoint: endpoint,
            appVersion: appVersion(),
            osVersion: osVersion()
        ) else { return }
        send(request)
    }

    static func request(
        kind: ErrorReportKind,
        endpoint: URL,
        appVersion: String,
        osVersion: String
    ) -> URLRequest? {
        let payload = ErrorReportPayload(
            kind: kind.rawValue,
            appVersion: appVersion,
            osVersion: osVersion
        )
        guard let body = try? JSONEncoder().encode(payload) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        return request
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let containsCrash = payloads.contains { !($0.crashDiagnostics?.isEmpty ?? true) }
        if containsCrash { report(.crash) }
    }

    private func updateSubscription() {
        guard managesMetricKit else { return }
        lock.lock()
        let isStarted = started
        lock.unlock()
        let shouldSubscribe = isStarted && isEnabled && isConfigured
        if shouldSubscribe && !subscribed {
            MXMetricManager.shared.add(self)
            subscribed = true
        } else if !shouldSubscribe && subscribed {
            MXMetricManager.shared.remove(self)
            subscribed = false
        }
    }

    private static var currentOSVersion: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
}
