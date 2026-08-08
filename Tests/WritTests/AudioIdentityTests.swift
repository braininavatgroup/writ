import XCTest
@testable import Writ

/// These cover the two identity rules that produced the worst bugs in this
/// project. Both were pure functions the whole time, and both would have been
/// caught here in seconds rather than in live use.
final class AudioIdentityTests: XCTestCase {

    // MARK: - stableUID

    /// The HomePod bug: a reconnected AirPlay speaker read as a brand-new
    /// device, so its label and rank were lost and the enforcer bounced output
    /// back to the laptop speakers a second after connecting.
    func testAirPlayUIDIsStableAcrossSessions() {
        let uuid = "cb56dc98-8819-425c-a21d-6b9ca8bb805a"
        let first  = Audio.stableUID("\(uuid)-2926033793250-Audio", name: "AirPlay")
        let second = Audio.stableUID("\(uuid)-9184773310021-Audio", name: "AirPlay")

        XCTAssertEqual(first, second, "same speaker across two sessions must key the same")
        XCTAssertEqual(first, uuid)
    }

    /// Two different speakers must not collapse into one entry.
    func testDifferentAirPlaySpeakersStayDistinct() {
        let a = Audio.stableUID("cb56dc98-8819-425c-a21d-6b9ca8bb805a-111-Audio", name: "AirPlay")
        let b = Audio.stableUID("ffffffff-8819-425c-a21d-6b9ca8bb805a-111-Audio", name: "AirPlay")
        XCTAssertNotEqual(a, b)
    }

    /// Non-AirPlay UIDs are already stable and must pass through untouched —
    /// truncating a USB device's UID would silently merge unrelated devices.
    func testNonAirPlayUIDIsUnchanged() {
        let uid = "AppleUSBAudioEngine:MOVO:GM-7:14200000:1"
        XCTAssertEqual(Audio.stableUID(uid, name: "MOVO GM-7"), uid)
    }

    /// A named speaker is no longer anonymous, so its UID must be left alone
    /// even though it came from AirPlay.
    func testNamedDeviceWithUUIDShapedUIDIsUnchanged() {
        let uid = "cb56dc98-8819-425c-a21d-6b9ca8bb805a-2926033793250-Audio"
        XCTAssertEqual(Audio.stableUID(uid, name: "Living Room"), uid)
    }

    /// Malformed input must degrade to the original string, never to a partial
    /// key that could collide with another device.
    func testShortOrMalformedAirPlayUIDFallsBack() {
        XCTAssertEqual(Audio.stableUID("short-uid", name: "AirPlay"), "short-uid")
        XCTAssertEqual(Audio.stableUID("", name: "AirPlay"), "")
        XCTAssertEqual(Audio.stableUID("not-a-uuid-at-all-here-x", name: "AirPlay"),
                       "not-a-uuid-at-all-here-x",
                       "five dash-separated parts that are not a UUID must not be treated as a key")
    }

    // MARK: - isSystemArtifact

    /// The meter feedback loop: tapping the default input makes macOS spawn a
    /// phantom aggregate device. It must be rejected on enumeration AND on load,
    /// or saved state accumulates entries that can never be selected.
    func testPhantomAggregateIsRejected() {
        XCTAssertTrue(Audio.isSystemArtifact(uid: "CADefaultDeviceAggregate-1234-5",
                                             name: "Writ"))
        XCTAssertTrue(Audio.isSystemArtifact(uid: "whatever",
                                             name: "CADefaultDeviceAggregate-1234-5"))
    }

    func testRealDevicesAreNotArtifacts() {
        XCTAssertFalse(Audio.isSystemArtifact(uid: "BuiltInSpeakerDevice",
                                              name: "MacBook Air Speakers"))
        XCTAssertFalse(Audio.isSystemArtifact(uid: "AppleUSBAudioEngine:MOVO:GM-7:1",
                                              name: "MOVO GM-7"))
    }

    // MARK: - isAnonymousAirPlay

    func testAnonymousAirPlayIsExactMatchOnly() {
        XCTAssertTrue(Audio.isAnonymousAirPlay(name: "AirPlay"))
        // A user-named speaker must not be swept up by a prefix match.
        XCTAssertFalse(Audio.isAnonymousAirPlay(name: "AirPlay Speaker"))
        XCTAssertFalse(Audio.isAnonymousAirPlay(name: "Living Room"))
    }
}

/// The ranking table is the product decision this whole app exists to express.
/// It is easy to reorder by accident and impossible to notice until the wrong
/// device is live in a call.
final class DeviceRankingTests: XCTestCase {

    func testDedicatedMicOutranksBluetoothOnInput() {
        // The original complaint: putting on AirPods stole the mic from the USB
        // microphone.
        XCTAssertLessThan(DeviceKind.usb.rank(.input), DeviceKind.bluetooth.rank(.input))
        XCTAssertLessThan(DeviceKind.usb.rank(.input), DeviceKind.builtIn.rank(.input))
    }

    func testHeadphonesOutrankSpeakersOnOutput() {
        XCTAssertLessThan(DeviceKind.bluetooth.rank(.output), DeviceKind.builtIn.rank(.output))
    }

    /// Display audio must be last in BOTH directions — a monitor hijacking
    /// output the moment it connects is the single most common complaint about
    /// macOS audio, and it must never win by default.
    func testDisplayAudioIsAlwaysLast() {
        for direction in Direction.allCases {
            let display = DeviceKind.display.rank(direction)
            for kind in [DeviceKind.usb, .bluetooth, .airplay, .builtIn, .other] {
                XCTAssertLessThan(kind.rank(direction), display,
                                  "\(kind) must outrank display audio on \(direction)")
            }
        }
    }

    /// Ranks must be a total order with no ties, or seeding order becomes
    /// dependent on CoreAudio's arbitrary enumeration order — the bug the
    /// seeding was introduced to fix.
    func testRanksAreUniqueWithinEachDirection() {
        let all: [DeviceKind] = [.usb, .bluetooth, .airplay, .builtIn, .display, .other]
        for direction in Direction.allCases {
            let ranks = all.map { $0.rank(direction) }
            XCTAssertEqual(Set(ranks).count, all.count, "duplicate rank on \(direction)")
        }
    }

    func testEveryKindHasASymbolForBothDirections() {
        let all: [DeviceKind] = [.usb, .bluetooth, .airplay, .builtIn, .display, .other]
        for direction in Direction.allCases {
            for kind in all {
                XCTAssertFalse(kind.symbolName(direction).isEmpty)
            }
        }
    }
}
