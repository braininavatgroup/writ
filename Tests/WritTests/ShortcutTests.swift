import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Writ

final class ShortcutTests: XCTestCase {

    private func keyEvent(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "",
                         isARepeat: false, keyCode: keyCode)!
    }

    /// A global hot key is taken away from every other app on the machine. One
    /// without a real modifier would swallow ordinary typing everywhere.
    func testBareKeyIsRejected() {
        XCTAssertNil(Shortcut(event: keyEvent(UInt16(kVK_ANSI_M), [])))
    }

    /// Shift alone is not enough either — ⇧M is just a capital M.
    func testShiftAloneIsRejected() {
        XCTAssertNil(Shortcut(event: keyEvent(UInt16(kVK_ANSI_M), [.shift])))
    }

    func testCommandOptionControlAreEachSufficient() {
        for flag in [NSEvent.ModifierFlags.command, .option, .control] {
            XCTAssertNotNil(Shortcut(event: keyEvent(UInt16(kVK_ANSI_M), flag)),
                            "\(flag) should be accepted as a modifier")
        }
    }

    func testCarbonModifierMaskIsBuiltCorrectly() {
        let shortcut = Shortcut(event: keyEvent(UInt16(kVK_ANSI_M),
                                                [.command, .option, .control]))
        XCTAssertEqual(shortcut?.modifiers,
                       UInt32(cmdKey | optionKey | controlKey))
        XCTAssertEqual(shortcut?.keyCode, UInt32(kVK_ANSI_M))
    }

    /// Apple's order is ⌃⌥⇧⌘. Getting it wrong makes every shortcut in the UI
    /// look subtly foreign.
    func testDisplayUsesAppleModifierOrder() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_A),
                                modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
        XCTAssertTrue(shortcut.display.hasPrefix("⌃⌥⇧⌘"),
                      "got \(shortcut.display)")
    }

    func testNamedKeysAreSpelledOut() {
        XCTAssertEqual(Shortcut.keyName(UInt32(kVK_Space)), "Space")
        XCTAssertEqual(Shortcut.keyName(UInt32(kVK_Escape)), "⎋")
        XCTAssertEqual(Shortcut.keyName(UInt32(kVK_LeftArrow)), "←")
        XCTAssertEqual(Shortcut.keyName(UInt32(kVK_F5)), "F5")
    }

    func testShortcutRoundTripsThroughJSON() throws {
        let original = Shortcut(keyCode: UInt32(kVK_ANSI_M),
                                modifiers: UInt32(cmdKey | optionKey))
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), original)
    }

    // MARK: - Defaults

    /// Every registered shortcut is taken from every other app, so the defaults
    /// are deliberately sparse. If this count grows, it should be a decision.
    func testOnlyTwoActionsAreBoundByDefault() {
        let bound = HotkeyAction.allCases.filter { $0.defaultShortcut != nil }
        XCTAssertEqual(Set(bound), [.toggleMute, .togglePanel])
    }

    func testDefaultShortcutsDoNotCollide() {
        let defaults = HotkeyAction.allCases.compactMap(\.defaultShortcut)
        XCTAssertEqual(Set(defaults).count, defaults.count)
    }

    /// ⌃⌥⌘ together is chosen precisely because almost nothing else uses it.
    /// A default that lands on a common combination silently fails to register.
    func testDefaultsUseThreeModifiers() {
        for action in HotkeyAction.allCases {
            guard let shortcut = action.defaultShortcut else { continue }
            XCTAssertEqual(shortcut.modifiers,
                           UInt32(cmdKey | optionKey | controlKey),
                           "\(action.rawValue) should use ⌃⌥⌘")
        }
    }

    /// Raw values are the persistence keys — changing one silently discards
    /// whatever the user had assigned to it.
    func testActionRawValuesAreStable() {
        XCTAssertEqual(Set(HotkeyAction.allCases.map(\.rawValue)),
                       ["toggleMute", "togglePanel", "toggleEnforcing",
                        "restoreOrder", "cycleInput", "cycleOutput"])
    }

    func testEveryActionHasTitleAndDetail() {
        for action in HotkeyAction.allCases {
            XCTAssertFalse(action.title.isEmpty)
            XCTAssertFalse(action.detail.isEmpty)
        }
    }
}
