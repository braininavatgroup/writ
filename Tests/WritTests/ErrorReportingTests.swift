import XCTest
@testable import Writ

final class ErrorReportingTests: XCTestCase {
    func testReportingIsOffByDefaultAndThrottlesEachKindWhenEnabled() {
        let defaults = makeTestDefaults()
        var requests: [URLRequest] = []
        var instant = Date(timeIntervalSince1970: 1_000_000)
        let reporter = ErrorReporter(
            defaults: defaults,
            endpoint: { URL(string: "https://errors.test/app/writ") },
            appVersion: { "1.1" },
            osVersion: { "15.7.1" },
            now: { instant },
            send: { requests.append($0) }
        )

        XCTAssertFalse(reporter.isEnabled)
        reporter.start()
        reporter.report(.crash)
        XCTAssertTrue(requests.isEmpty)

        reporter.setEnabled(true)
        reporter.report(.crash)
        reporter.report(.crash)
        reporter.report(.deviceSwitchFailed)
        XCTAssertEqual(requests.count, 2)

        instant.addTimeInterval(60 * 60)
        reporter.report(.crash)
        XCTAssertEqual(requests.count, 3)
    }

    func testEnabledReporterSendsOnlyWhileStarted() {
        let defaults = makeTestDefaults()
        defaults.set(true, forKey: ErrorReporter.enabledKey)
        var requests: [URLRequest] = []
        let reporter = ErrorReporter(
            defaults: defaults,
            endpoint: { URL(string: "https://errors.test/app/writ") },
            appVersion: { "1.1" },
            osVersion: { "15.7.1" },
            now: { Date(timeIntervalSince1970: 1_000_000) },
            send: { requests.append($0) }
        )

        reporter.report(.crash)
        XCTAssertTrue(requests.isEmpty, "preview and pre-launch reporters must stay dormant")
        reporter.start()
        reporter.report(.crash)
        XCTAssertEqual(requests.count, 1)
        reporter.stop()
        reporter.report(.deviceSwitchFailed)
        XCTAssertEqual(requests.count, 1, "a stopped reporter must not send another kind")
    }

    func testRequestContainsExactlyTheThreePromisedValues() throws {
        let endpoint = try XCTUnwrap(URL(string: "https://errors.test/app/writ"))
        let request = try XCTUnwrap(ErrorReporter.request(
            kind: .deviceSwitchFailed,
            endpoint: endpoint,
            appVersion: "1.1",
            osVersion: "15.7.1"
        ))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(Set(object.keys), ["kind", "appVersion", "osVersion"])
        XCTAssertEqual(object, [
            "kind": "device-switch-failed",
            "appVersion": "1.1",
            "osVersion": "15.7.1",
        ])
    }
}
