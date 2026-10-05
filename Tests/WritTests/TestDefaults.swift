import XCTest

extension XCTestCase {
    /// A fresh UserDefaults suite stored in a temporary directory and removed
    /// when the test ends. A suite named by a bare name is a plist in
    /// ~/Library/Preferences, and cfprefsd rewrites it there even after
    /// removePersistentDomain, so every run left files behind. A suite named
    /// by an absolute path keeps its plist at that path instead.
    func makeTestDefaults() -> UserDefaults {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("writ-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return UserDefaults(suiteName: dir.appendingPathComponent("defaults").path)!
    }
}

/// Holds every test to makeTestDefaults(), so no test can leak a suite plist.
final class TestDefaultsTests: XCTestCase {
    private static let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    func testOnlyTheHelperCreatesASuite() throws {
        let files = FileManager.default.enumerator(atPath: Self.testDir.path)?
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") } ?? []
        XCTAssertFalse(files.isEmpty, "no tests found at \(Self.testDir.path)")
        for path in files where path != "TestDefaults.swift" {
            let text = try String(contentsOf: Self.testDir.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(
                text.contains("UserDefaults(suiteName"),
                "\(path) creates a UserDefaults suite directly: use makeTestDefaults(), which keeps it out of ~/Library/Preferences and removes it after the test"
            )
        }
    }
}
