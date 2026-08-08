import XCTest
@testable import Writ

/// The rule that decides whether a device may be selected at all. It used to be
/// written out four separate times, in `winner`, `somethingChanged`,
/// `selectNow` and `canSelect`, which is four chances for them to disagree.
final class EligibilityTests: XCTestCase {

    private func entry(ignored: Bool = false, requiresLidOpen: Bool = false) -> PriorityEntry {
        var e = PriorityEntry(uid: "uid", name: "Device")
        e.ignored = ignored
        e.requiresLidOpen = requiresLidOpen
        return e
    }

    func testOrdinaryDeviceIsAlwaysEligible() {
        XCTAssertTrue(entry().isEligible(lidClosed: false))
        XCTAssertTrue(entry().isEligible(lidClosed: true))
    }

    /// "Never use" is a hard block, not a preference — the lid has no bearing
    /// on it in either direction.
    func testIgnoredIsBlockedRegardlessOfLid() {
        XCTAssertFalse(entry(ignored: true).isEligible(lidClosed: false))
        XCTAssertFalse(entry(ignored: true).isEligible(lidClosed: true))
    }

    /// The built-in mic is hardware-disconnected in clamshell, so selecting it
    /// with the lid shut picks a device that captures silence.
    func testLidRuleBlocksOnlyWhileClosed() {
        XCTAssertTrue(entry(requiresLidOpen: true).isEligible(lidClosed: false))
        XCTAssertFalse(entry(requiresLidOpen: true).isEligible(lidClosed: true))
    }

    func testBothRulesTogetherStillBlock() {
        let e = entry(ignored: true, requiresLidOpen: true)
        XCTAssertFalse(e.isEligible(lidClosed: false))
        XCTAssertFalse(e.isEligible(lidClosed: true))
    }
}

/// Device memory rules. An entry that is disposable gets swept when it stops
/// playing; one that is yours is kept forever.
final class DisposabilityTests: XCTestCase {

    private func airPlay(customName: String? = nil, customSymbol: String? = nil) -> PriorityEntry {
        var e = PriorityEntry(uid: "uid", name: "AirPlay")
        e.ephemeral = true
        e.customName = customName
        e.customSymbol = customSymbol
        return e
    }

    /// Unlabelled AirPlay rows are indistinguishable from each other, which is
    /// how three identical dead "AirPlay" entries piled up in the list.
    func testUnlabelledEphemeralIsDisposable() {
        XCTAssertTrue(airPlay().isDisposable)
    }

    /// Naming a speaker is the act that makes it yours — after that it must
    /// survive disconnection, or the label is lost every session.
    func testLabelledEphemeralIsKept() {
        XCTAssertFalse(airPlay(customName: "Kitchen HomePod").isDisposable)
    }

    /// Choosing a glyph is just as much a claim on the device as naming it.
    func testCustomGlyphAloneIsEnoughToKeep() {
        XCTAssertFalse(airPlay(customSymbol: "homepodmini").isDisposable)
    }

    /// A normal device is never disposable, however it is labelled.
    func testNonEphemeralIsNeverDisposable() {
        var e = PriorityEntry(uid: "uid", name: "MOVO GM-7")
        XCTAssertFalse(e.isDisposable)
        e.ephemeral = false
        XCTAssertFalse(e.isDisposable)
    }

    /// Lists written by builds that predate ephemeral tracking decode with a nil
    /// flag, and must not be treated as disposable.
    func testMissingEphemeralFlagDefaultsToKeeping() {
        let e = PriorityEntry(uid: "uid", name: "AirPlay")
        XCTAssertNil(e.ephemeral)
        XCTAssertFalse(e.isDisposable)
    }
}

/// Saved lists must survive a round trip. Device memory is permanent by design,
/// so a decode failure silently resets everything a user has arranged.
final class PersistenceTests: XCTestCase {

    func testEntryRoundTripsThroughJSON() throws {
        var original = PriorityEntry(uid: "uid-1", name: "MOVO GM-7")
        original.requiresLidOpen = true
        original.ignored = false
        original.seedRank = 3
        original.symbolName = "mic"
        original.customSymbol = "music.mic"
        original.customName = "Podcast mic"
        original.ephemeral = false

        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([PriorityEntry].self, from: data)

        XCTAssertEqual(decoded, [original])
    }

    /// Every field added since 1.0 is optional precisely so that older saved
    /// lists still decode. If this breaks, an update wipes people's settings.
    func testListFromAnEarlierBuildStillDecodes() throws {
        let legacy = """
        [{"uid":"uid-1","name":"MOVO GM-7","requiresLidOpen":false,"ignored":false,"seedRank":0}]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([PriorityEntry].self, from: legacy)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].displayName, "MOVO GM-7")
        XCTAssertNil(decoded[0].customName)
        XCTAssertNil(decoded[0].ephemeral)
        XCTAssertFalse(decoded[0].isDisposable)
    }

    func testCustomNameWinsOverSystemName() {
        var e = PriorityEntry(uid: "uid", name: "AirPlay")
        XCTAssertEqual(e.displayName, "AirPlay")
        e.customName = "Kitchen HomePod"
        XCTAssertEqual(e.displayName, "Kitchen HomePod")
    }
}
