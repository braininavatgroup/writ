import XCTest
@testable import Writ

/// Push-to-talk is the one action that behaves differently on key release, and
/// getting the held/press distinction wrong leaves a microphone open.
final class HeldActionTests: XCTestCase {

    func testOnlyPushToTalkIsHeld() {
        let held = HotkeyAction.allCases.filter(\.isHeld)
        XCTAssertEqual(held, [.pushToTalk])
    }

    /// A held action must never be bound by default. Shipping one would mean a
    /// key that mutes the microphone on release, which is a startling thing to
    /// discover by accident.
    func testHeldActionIsNotBoundByDefault() {
        XCTAssertNil(HotkeyAction.pushToTalk.defaultShortcut)
    }

    func testPushToTalkHasItsOwnStableRawValue() {
        XCTAssertEqual(HotkeyAction.pushToTalk.rawValue, "pushToTalk")
        XCTAssertEqual(HotkeyAction(rawValue: "pushToTalk"), .pushToTalk)
    }

    /// Adding an action means deciding whether it is held. This fails loudly if
    /// a new case is added without that decision being made deliberately.
    func testEveryActionDeclaresItsKind() {
        XCTAssertEqual(HotkeyAction.allCases.count, 7)
        for action in HotkeyAction.allCases where action != .pushToTalk {
            XCTAssertFalse(action.isHeld, "\(action.rawValue) should act on press")
        }
    }
}
