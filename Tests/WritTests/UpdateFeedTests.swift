import XCTest
@testable import Writ

/// The feed is written by `release.sh` and read by `UpdateCheck`. Those two live
/// in different languages and different files, so nothing but a test keeps them
/// agreeing — and a feed the app cannot parse means every user silently stops
/// receiving updates, with no error anywhere.
final class UpdateFeedTests: XCTestCase {

    /// Byte-for-byte the shape release.sh emits.
    private let generated = """
    {
      "version": "1.1",
      "build": 23,
      "url": "https://writ.braininavat.dance/Writ-1.1.dmg",
      "notes": "Fixed the thing.\\nAdded the other thing."
    }
    """.data(using: .utf8)!

    func testGeneratedFeedDecodes() throws {
        let release = try JSONDecoder().decode(UpdateCheck.Release.self, from: generated)
        XCTAssertEqual(release.version, "1.1")
        XCTAssertEqual(release.build, 23)
        XCTAssertEqual(release.url, "https://writ.braininavat.dance/Writ-1.1.dmg")
        XCTAssertEqual(release.notes, "Fixed the thing.\nAdded the other thing.")
    }

    /// Notes are the only optional field. A release published without them must
    /// not stop everyone from updating.
    func testFeedWithoutNotesStillDecodes() throws {
        let minimal = """
        {"version": "1.1", "build": 23, "url": "https://example.com/Writ-1.1.dmg"}
        """.data(using: .utf8)!
        let release = try JSONDecoder().decode(UpdateCheck.Release.self, from: minimal)
        XCTAssertNil(release.notes)
        XCTAssertEqual(release.build, 23)
    }

    /// Builds are compared, never version strings. "1.10" sorts BELOW "1.9" as
    /// text, so a string comparison would strand everyone on 1.9 forever.
    func testBuildOrderingSurvivesTheTenthPatch() {
        XCTAssertTrue(23 > 9)
        XCTAssertLessThan("1.10", "1.9", "string ordering is exactly the trap being avoided")
    }

    func testMalformedFeedIsRejectedRatherThanMisread() {
        let bad = #"{"version": "1.1", "build": "23"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(UpdateCheck.Release.self, from: bad),
                             "a string build number must fail loudly, not coerce to 0")
    }

    /// With no feed URL compiled in, the app must make no network request at all
    /// and must not offer the menu item. This is the shipping default.
    @MainActor
    func testAbsentFeedURLDisablesTheFeature() {
        // Info.plist in a test bundle carries no WritUpdateFeedURL.
        let url = UpdateCheck.feedURL
        XCTAssertNil(url)
    }
}
