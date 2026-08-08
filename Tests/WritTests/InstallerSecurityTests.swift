import XCTest
@testable import Writ

/// The signature check is the only thing standing between "we download an
/// executable over the network" and "anyone who can answer for the update host
/// runs code as the user". It is tested against real bundles on disk rather
/// than mocked, because a mocked security boundary proves nothing.
final class InstallerSecurityTests: XCTestCase {

    /// An ad-hoc signed copy of whatever was last built — the closest available
    /// stand-in for an attacker's build: a structurally valid, correctly signed
    /// app bundle whose signature is simply not ours.
    ///
    /// Built here rather than pointed at `dist/Writ.app`, because what is in
    /// dist depends on which script ran last. That made this test pass or fail
    /// on build order rather than on behaviour — it failed the first time
    /// release.sh signed dist with the real Developer ID, which was the check
    /// working correctly and the test being wrong.
    private func makeAdHocCopy() throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("dist/Writ.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("run ./build.sh first")
        }

        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdHocWrit-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: source, to: copy)

        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--deep", "-s", "-", copy.path]
        sign.standardError = Pipe()
        try sign.run()
        sign.waitUntilExit()
        guard sign.terminationStatus == 0 else {
            throw XCTSkip("could not produce an ad-hoc fixture")
        }
        return copy
    }

    /// Whatever is installed. On a development machine this may be either a
    /// Developer ID build or an ad-hoc one, so the test adapts — what matters is
    /// that the verdict agrees with the system's own view.
    private let installed = URL(fileURLWithPath: "/Applications/Writ.app")

    func testAdHocSignedBundleIsRejected() throws {
        let bundle = try makeAdHocCopy()
        defer { try? FileManager.default.removeItem(at: bundle) }
        XCTAssertFalse(Installer.verifySignature(at: bundle),
                       "an ad-hoc signature must never satisfy the Developer ID requirement")
    }

    /// The positive half. A check that rejects everything would pass every test
    /// above while making updates impossible, so the real signed article has to
    /// be accepted too.
    func testDeveloperIDSignedBundleIsAccepted() throws {
        let installed = URL(fileURLWithPath: "/Applications/Writ.app")
        guard FileManager.default.fileExists(atPath: installed.path) else {
            throw XCTSkip("Writ is not installed")
        }
        let spctl = Process()
        spctl.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        spctl.arguments = ["-a", "-t", "exec", installed.path]
        spctl.standardError = Pipe()
        try spctl.run()
        spctl.waitUntilExit()
        guard spctl.terminationStatus == 0 else {
            throw XCTSkip("the installed build is not a notarised Developer ID build")
        }
        XCTAssertTrue(Installer.verifySignature(at: installed))
    }

    func testMissingBundleIsRejected() {
        let nowhere = URL(fileURLWithPath: "/Applications/DefinitelyNotWrit.app")
        XCTAssertFalse(Installer.verifySignature(at: nowhere))
    }

    /// An unsigned directory that merely looks like an app must not pass.
    func testUnsignedDirectoryIsRejected() throws {
        let fake = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeWrit-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(
            at: fake.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try "not a binary".write(to: fake.appendingPathComponent("Contents/MacOS/Writ"),
                                 atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fake) }

        XCTAssertFalse(Installer.verifySignature(at: fake))
    }

    /// The verdict must match `spctl`, the system's own authority. If these ever
    /// disagree, one of them is wrong about what is safe to run.
    func testVerdictAgreesWithTheSystem() throws {
        guard FileManager.default.fileExists(atPath: installed.path) else {
            throw XCTSkip("Writ is not installed")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["-a", "-t", "exec", installed.path]
        process.standardError = Pipe()
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        let systemAcceptsIt = process.terminationStatus == 0
        XCTAssertEqual(Installer.verifySignature(at: installed), systemAcceptsIt,
                       "our check and spctl must agree about the installed app")
    }
}
