import XCTest

/// Protect the non-obvious AppKit construction invariant behind Writ's panel
/// without creating or showing a window on the user's active desktop.
final class PanelConstructionTests: XCTestCase {

    func testNonactivatingStyleIsEstablishedAtInitialization() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Writ/StatusItemController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("styleMask: panelStyle"))
        XCTAssertFalse(
            source.contains("panel.styleMask ="),
            "a non-activating panel must receive its style when it is created"
        )
    }
}
